#!/usr/bin/env python3
"""Fail closed when compiler code reaches runtime-owned representation fields."""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import subprocess
import sys
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator


CONFIG = "scripts/architecture_representation_access.json"
MEMBER = re.compile(r"\.\s*(?P<field>[A-Za-z_][A-Za-z0-9_]*)\b")
STRUCT_DEFINITION = re.compile(r"\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\b")
DEFINITION_PATH = re.compile(r"^Definition found at file (.+)$", re.MULTILINE)


@dataclass(frozen=True)
class Rule:
    id: str
    receiver_type: str
    fields: frozenset[str]
    kind: str
    reason: str
    areas: frozenset[str]


@dataclass(frozen=True)
class Access:
    path: str
    line: int
    rule: Rule
    field: str
    signature: str


def run(root: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=root,
        text=True,
        capture_output=True,
        check=check,
    )


def load_config(root: Path) -> tuple[dict[str, Any], list[Rule]]:
    try:
        data = json.loads((root / CONFIG).read_text())
    except json.JSONDecodeError as error:
        raise RuntimeError(f"invalid JSON in {CONFIG}: {error}") from error
    patterns = {item["id"]: item for item in data["representation_patterns"]}
    rules: list[Rule] = []
    for item in data.get("semantic_member_rules", []):
        rule_id = item["id"]
        pattern = patterns.get(rule_id)
        if pattern is None:
            raise RuntimeError(
                f"semantic member rule {rule_id!r} has no representation pattern"
            )
        rules.append(
            Rule(
                id=rule_id,
                receiver_type=item["receiver_type"],
                fields=frozenset(
                    token[1:] if token.startswith(".") else token
                    for token in pattern["pattern"].split("|")
                ),
                kind=pattern["kind"],
                reason=pattern["reason"],
                areas=frozenset(item.get("areas", [])),
            )
        )
    if not rules:
        raise RuntimeError("semantic_member_rules must list at least one rule")
    return data, rules


def ignored(path: str, globs: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in globs)


def compiler_sources(root: Path, data: dict[str, Any]) -> Iterator[Path]:
    globs = data.get("ignore_globs", [])
    for scan_root in data.get("scan_roots", []):
        if scan_root != "compiler":
            continue
        for path in sorted((root / scan_root).rglob("*.mbt")):
            rel = path.relative_to(root).as_posix()
            if not ignored(rel, globs):
                yield path


def member_owner(root: Path, rel: str, line: int, column: int, field: str) -> str | None:
    result = run(
        root,
        "moon",
        "ide",
        "peek-def",
        field,
        "--loc",
        f"{rel}:{line}:{column}",
        "--no-check",
        check=False,
    )
    if result.returncode != 0:
        diagnostic = (result.stderr or result.stdout).strip()
        raise RuntimeError(
            f"Moon IDE could not resolve {rel}:{line}:{column} .{field}: {diagnostic}"
        )
    if "Definition found at file " not in result.stdout:
        raise RuntimeError(
            f"Moon IDE returned no definition for {rel}:{line}:{column} .{field}"
        )
    path_match = DEFINITION_PATH.search(result.stdout)
    struct_match = STRUCT_DEFINITION.search(result.stdout)
    if path_match is None or struct_match is None:
        return None
    definition_path = Path(path_match.group(1)).resolve()
    runtime_root = (root / "interpreter/runtime").resolve()
    if not definition_path.is_relative_to(runtime_root):
        return None
    return f"@runtime.{struct_match.group(1)}"


def normalize_line(line: str) -> str:
    return " ".join(line.strip().split())


def scan_file(root: Path, path: Path, rules: list[Rule]) -> list[Access]:
    rel = path.relative_to(root).as_posix()
    by_field: dict[str, list[Rule]] = {}
    for rule in rules:
        if not rule.areas or "compiler" in rule.areas:
            for field in rule.fields:
                by_field.setdefault(field, []).append(rule)
    accesses: list[Access] = []
    for line_no, line in enumerate(path.read_text().splitlines(), 1):
        for match in MEMBER.finditer(line):
            field = match.group("field")
            candidates = by_field.get(field, [])
            if not candidates:
                continue
            receiver_type = member_owner(
                root, rel, line_no, match.start("field") + 1, field
            )
            for rule in candidates:
                if receiver_type == rule.receiver_type:
                    accesses.append(
                        Access(
                            path=rel,
                            line=line_no,
                            rule=rule,
                            field=field,
                            signature=f".{field}:{normalize_line(line)}",
                        )
                    )
    return accesses


def hash_part(text: str, initial: int, multiplier: int, modulo: int) -> int:
    value = initial
    for char in text:
        value = (value * multiplier + ord(char)) % modulo
    return value


def fingerprint(signatures: list[str]) -> str:
    h1 = sum(hash_part(item, 17, 31, 1_000_003) for item in signatures) % 1_000_003
    h2 = sum(hash_part(item, 29, 37, 1_000_033) for item in signatures) % 1_000_033
    return f"{len(signatures)}:{sum(map(len, signatures))}:{h1}:{h2}"


def audit(root: Path, paths: list[Path] | None = None) -> tuple[list[str], int]:
    data, rules = load_config(root)
    selected = paths if paths is not None else list(compiler_sources(root, data))
    accesses = [access for path in selected for access in scan_file(root, path, rules)]
    debts = {
        (item["path"], item["pattern_id"]): item
        for item in data.get("semantic_allowlisted_access", [])
        if any(rule.id == item["pattern_id"] for rule in rules)
    }
    grouped: dict[tuple[str, str], list[Access]] = {}
    for access in accesses:
        grouped.setdefault((access.path, access.rule.id), []).append(access)
    failures: list[str] = []
    for key, items in grouped.items():
        debt = debts.get(key)
        actual = fingerprint([item.signature for item in items])
        if debt is None:
            failures.extend(
                f"{item.path}:{item.line} {item.rule.id}: .{item.field}"
                for item in items
            )
        elif debt["allowed_count"] != len(items) or debt["fingerprint"] != actual:
            failures.append(
                f"{key[0]} {key[1]} debt changed: "
                f"expected {debt['allowed_count']} / {debt['fingerprint']}, "
                f"found {len(items)} / {actual}"
            )
    for key in debts:
        if key not in grouped:
            failures.append(f"stale semantic representation debt: {key[0]} {key[1]}")
    return failures, len(accesses)


FIXTURE = """///|
pub fn runtime_representation_audit_fixture_tmp(
  env : @runtime.Environment,
  envs : Array[@runtime.Environment],
) -> Unit {
  let environment = runtime_representation_audit_wrapper_tmp(env)
  let cell = environment.bindings.get("x").unwrap()
  if cell.initialized {
    cell.value = cell.value
    ignore(cell.kind)
  }
  ignore(runtime_representation_audit_wrapper_tmp(env).bindings)
  ignore(envs[0].bindings)
}
"""
WRAPPER_FIXTURE = """///|
pub fn runtime_representation_audit_wrapper_tmp(
  env : @runtime.Environment,
) -> @runtime.Environment {
  env
}
"""


@contextmanager
def fixture(root: Path) -> Iterator[Path]:
    path = root / "compiler/runtime_representation_audit_fixture_tmp.mbt"
    wrapper = root / "compiler/runtime_representation_audit_wrapper_tmp.mbt"
    path.unlink(missing_ok=True)
    wrapper.unlink(missing_ok=True)
    try:
        path.write_text(FIXTURE)
        wrapper.write_text(WRAPPER_FIXTURE)
        check = run(root, "moon", "check", "--deny-warn", check=False)
        if check.returncode != 0:
            raise RuntimeError(check.stdout + check.stderr)
        yield path
    finally:
        path.unlink(missing_ok=True)
        wrapper.unlink(missing_ok=True)
        run(root, "moon", "check", "--deny-warn", check=False)


def self_test(root: Path) -> None:
    with fixture(root) as path:
        _, rules = load_config(root)
        accesses = scan_file(root, path, rules)
        found: dict[tuple[str, str], int] = {}
        for item in accesses:
            key = (item.rule.id, item.field)
            found[key] = found.get(key, 0) + 1
        expected = {
            ("runtime-environment-bindings-field", "bindings"): 3,
            ("runtime-binding-fields", "initialized"): 1,
            ("runtime-binding-fields", "value"): 2,
            ("runtime-binding-fields", "kind"): 1,
        }
        if found != expected:
            raise RuntimeError(f"semantic fixture mismatch: {sorted(found.items())}")
    resolution_failed_closed = False
    try:
        member_owner(root, "compiler/bytecode_vm.mbt", 1, 1, "bindings")
    except RuntimeError:
        resolution_failed_closed = True
    if not resolution_failed_closed:
        raise RuntimeError("unresolved executable member did not fail closed")
    print("ok: semantic representation audit rejects aliased and expression receivers")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    try:
        if sys.version_info < (3, 9):
            raise RuntimeError("Python 3.9 or newer is required")
        if args.self_test:
            self_test(root)
        ensure = run(root, "moon", "check", "--deny-warn", check=False)
        if ensure.returncode != 0:
            raise RuntimeError(ensure.stdout + ensure.stderr)
        failures, count = audit(root)
        if failures:
            print("runtime representation access audit failed:", file=sys.stderr)
            for failure in failures:
                print(f"- {failure}", file=sys.stderr)
            return 1
        print(f"ok: semantic runtime representation access matches inventory ({count} accesses)")
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"runtime representation access audit failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
