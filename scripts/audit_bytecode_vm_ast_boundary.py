#!/usr/bin/env python3
"""Guard the bytecode VM's executable AST boundary with typed hovers.

The source scanner below only supplies candidate coordinates. MoonBit's IDE
resolves every executable identifier at those coordinates, so inferred local
binders and expression results are checked without relying on receiver names.
An unresolved executable candidate is a failure, not an ignored edge. No
finalized bytecode carrier or VM entry may contain executable
``@ast.Stmt``/``@ast.Expr``/``@ast.Pattern`` values. Source text and typed
preparation are permitted; source-body/source-statement AST aliases must fail.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import json
from pathlib import Path
import re
import subprocess
import sys


VM_PATHS = (
    Path("compiler/bytecode_ir.mbt"),
    Path("compiler/bytecode_frame_transition.mbt"),
    Path("compiler/bytecode_vm.mbt"),
)
FORBIDDEN_MARKERS = ("@ast.Stmt", "@ast.Pattern", "@ast.Expr")
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
FIXTURE_PREFIX = "compiler/bytecode_vm_ast_boundary_fixture_"
FIXTURE_BASENAME_PREFIX = Path(FIXTURE_PREFIX).name

# These are syntax words, not executable identifiers. Every other identifier
# is sent to typed hover resolution; this list deliberately does not contain
# names such as `pattern`, `stmt`, `alias`, or `item`.
MOONBIT_KEYWORDS = frozenset(
    {
        "as",
        "async",
        "break",
        "catch",
        "const",
        "continue",
        "derive",
        "else",
        "enum",
        "extern",
        "false",
        "fn",
        "for",
        "guard",
        "if",
        "impl",
        "import",
        "in",
        "is",
        "let",
        "match",
        "mut",
        "newtype",
        "None",
        "priv",
        "pub",
        "raise",
        "return",
        "struct",
        "suberror",
        "test",
        "trait",
        "true",
        "type",
        "using",
        "while",
        "with",
    },
)

NEGATIVE_FIXTURE_SOURCES = {
    "helper_return": r'''///|
#warnings("-unused_value")
fn bytecode_vm_ast_boundary_fixture_helper() -> @ast.Stmt {
  abort("")
}

///|
pub fn bytecode_vm_ast_boundary_fixture_helper_return() -> Unit {
  let inferred = bytecode_vm_ast_boundary_fixture_helper()
  ignore(inferred)
}
''',
    "direct_match": r'''///|
#warnings("-unused_value")
fn bytecode_vm_ast_boundary_fixture_direct_match(stmt : @ast.Stmt) -> Unit {
  let renamed = stmt
  match renamed {
    _ => ()
  }
}
''',
    "loop": r'''///|
#warnings("-unused_value")
fn bytecode_vm_ast_boundary_fixture_loop(stmts : Array[@ast.Stmt]) -> Unit {
  for item in stmts {
    ignore(item)
  }
}
''',
    "source_body_alias": r'''///|
#warnings("-unused_value")
fn bytecode_vm_ast_boundary_fixture_source_body_alias(
  stmts : Array[@ast.Stmt],
) -> Unit {
  let retained = stmts
  for candidate in retained {
    ignore(candidate)
  }
}

///|
pub fn bytecode_vm_ast_boundary_fixture_source_body_alias_entry() -> Unit {
  ignore(bytecode_vm_ast_boundary_fixture_source_body_alias)
}
''',
    "direct_pattern": r'''///|
#warnings("-unused_value")
fn bytecode_vm_ast_boundary_fixture_direct_pattern(
  pattern : @ast.Pattern,
) -> Unit {
  match pattern {
    _ => ()
  }
}
''',
    "direct_expr": r'''///|
#warnings("-unused_value")
fn bytecode_vm_ast_boundary_fixture_direct_expr(
  expr : @ast.Expr,
) -> Unit {
  match expr {
    _ => ()
  }
}
''',
}

POSITIVE_FIXTURE_SOURCE = r'''///|
#warnings("-unused_value")
fn bytecode_vm_ast_boundary_fixture_destructure_plan(
  instruction : BytecodeInstr,
) -> Unit {
  match instruction {
    AssignDestructure(plan) => ignore(plan)
    _ => ()
  }
}
'''


def run(root: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=root,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def hover(root: Path, path: Path, line: int, column: int) -> str | None:
    result = run(
        root,
        "moon",
        "ide",
        "hover",
        "--loc",
        f"{path}:{line}:{column}",
        "--output-json",
        "--no-check",
        check=False,
    )
    if result.returncode != 0:
        return None
    try:
        contents = json.loads(result.stdout)["contents"]
    except (KeyError, TypeError, json.JSONDecodeError):
        return None
    return "\n".join(contents)


def executable_lines(lines: list[str]) -> list[str]:
    """Mask comments and literals while preserving source coordinates.

    This is coordinate discovery only; the compiler-backed hover below is the
    authority for whether a remaining identifier is executable and what type it
    has. The VM source currently has no multiline raw literals, but block
    comments are handled to keep unresolved-comment text from becoming a
    false architecture failure. MoonBit ``\\{...}`` interpolation bodies stay
    visible so their inferred executable values are audited too.
    """

    masked: list[str] = []
    in_block_comment = False
    for source in lines:
        chars = list(source)
        index = 0
        while index < len(chars):
            if in_block_comment:
                end = source.find("*/", index)
                if end < 0:
                    for position in range(index, len(chars)):
                        chars[position] = " "
                    index = len(chars)
                else:
                    for position in range(index, end + 2):
                        chars[position] = " "
                    index = end + 2
                    in_block_comment = False
                continue
            if source.startswith("//", index):
                for position in range(index, len(chars)):
                    chars[position] = " "
                break
            if source.startswith("/*", index):
                chars[index] = " "
                if index + 1 < len(chars):
                    chars[index + 1] = " "
                in_block_comment = True
                index += 2
                continue
            if chars[index] in ('"', "'"):
                quote = chars[index]
                chars[index] = " "
                index += 1
                while index < len(chars):
                    escaped = source[index] == "\\" and index + 1 < len(chars)
                    if escaped and source[index + 1] == "{":
                        chars[index] = " "
                        chars[index + 1] = " "
                        index += 2
                        interpolation_depth = 1
                        while index < len(chars) and interpolation_depth > 0:
                            if source[index] == "{":
                                interpolation_depth += 1
                            elif source[index] == "}":
                                interpolation_depth -= 1
                            index += 1
                        continue
                    chars[index] = " "
                    if escaped:
                        chars[index + 1] = " "
                        index += 2
                    else:
                        closed = source[index] == quote
                        index += 1
                        if closed:
                            break
                continue
            index += 1
        masked.append("".join(chars))
    return masked


def candidate_locations(root: Path, path: Path) -> list[tuple[int, int, str]]:
    lines = (root / path).read_text().splitlines()
    locations: list[tuple[int, int, str]] = []
    for line_number, line in enumerate(executable_lines(lines), start=1):
        for match in IDENTIFIER.finditer(line):
            token = match.group(0)
            if token not in MOONBIT_KEYWORDS:
                previous = line[: match.start()].rstrip()[-1:]
                if previous in ("@", "#"):
                    continue
                locations.append((line_number, match.start() + 1, token))
    return locations


def semantic_ast_accesses(
    root: Path,
    paths: tuple[Path, ...],
) -> list[dict[str, object]]:
    requests: list[tuple[Path, int, int, str, set[tuple[int, int]]]] = []
    for path in paths:
        for line, column, token in candidate_locations(root, path):
            requests.append((path, line, column, token, set()))

    def inspect(
        request : tuple[Path, int, int, str, set[tuple[int, int]]],
    ) -> dict[str, object] | None:
        path, line, column, token, allowances = request
        contents = hover(root, path, line, column)
        base = {"path": str(path), "line": line, "column": column, "token": token}
        if contents is None:
            return {**base, "type": "unresolved-executable-candidate"}
        if token == "BytecodeFunction" and "struct BytecodeFunction" in contents:
            # The frame carries the function metadata as a whole. A struct
            # hover enumerates its retained source metadata, but this token is
            # not a field read; direct AST-valued candidates remain checked.
            return None
        if token == "BytecodeInstr" and "enum BytecodeInstr" in contents:
            # A type reference is not an executable AST traversal.
            return None
        marker = next(
            (candidate for candidate in FORBIDDEN_MARKERS if candidate in contents),
            None,
        )
        if marker is None or (line, column) in allowances:
            return None
        return {**base, "type": marker}

    with ThreadPoolExecutor(max_workers=8) as executor:
        inspected = list(executor.map(inspect, requests))
    # `moon ide hover` shares compiler state within the workspace. Concurrent
    # requests can transiently return no JSON, so retry only those transport
    # failures serially. A candidate that remains unresolved still fails closed.
    violations = []
    for request, item in zip(requests, inspected):
        if item is not None and item["type"] == "unresolved-executable-candidate":
            item = inspect(request)
        if item is not None:
            violations.append(item)
    return sorted(
        violations,
        key=lambda item: (str(item["path"]), int(item["line"]), int(item["column"])),
    )


@contextmanager
def fixture_sources(root: Path, sources: dict[str, str]):
    paths = {
        root / f"{FIXTURE_PREFIX}{name}_tmp.mbt": source
        for name, source in sources.items()
    }
    preexisting = [path for path in paths if path.exists()]
    if preexisting:
        raise RuntimeError(f"AST boundary fixture paths already exist: {preexisting}")
    try:
        for path, source in paths.items():
            path.write_text(source)
        checked = run(root, "moon", "check", "--deny-warn", check=False)
        if checked.returncode != 0:
            raise RuntimeError(
                "AST boundary fixture did not type-check:\n"
                + checked.stdout
                + checked.stderr
            )
        yield tuple(paths)
    finally:
        for path in paths:
            path.unlink(missing_ok=True)
        cleaned = run(root, "moon", "check", "--deny-warn", check=False)
        if cleaned.returncode != 0 and sys.exc_info()[0] is None:
            raise RuntimeError(
                "AST boundary fixture cleanup check failed:\n"
                + cleaned.stdout
                + cleaned.stderr
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    checked = run(root, "moon", "check", "--deny-warn", check=False)
    if checked.returncode != 0:
        print(checked.stdout + checked.stderr, file=sys.stderr)
        return checked.returncode
    violations = semantic_ast_accesses(root, VM_PATHS)
    if violations:
        print("bytecode VM executable AST boundary failed:", file=sys.stderr)
        for violation in violations:
            print(json.dumps(violation, sort_keys=True), file=sys.stderr)
        return 1
    if args.self_test:
        expected_tokens = {
            "helper_return": "inferred",
            "direct_match": "renamed",
            "loop": "item",
            "source_body_alias": "retained",
            "direct_pattern": "pattern",
            "direct_expr": "expr",
        }
        with fixture_sources(root, NEGATIVE_FIXTURE_SOURCES) as paths:
            negative = {
                path.stem.removeprefix(FIXTURE_BASENAME_PREFIX).removesuffix("_tmp"):
                    semantic_ast_accesses(root, (path,))
                for path in paths
            }
        missing = {
            name: token
            for name, token in expected_tokens.items()
            if not any(item["token"] == token for item in negative[name])
        }
        if missing:
            print(
                "AST boundary inferred-value fixtures did not fail closed: "
                + json.dumps(missing, sort_keys=True),
                file=sys.stderr,
            )
            return 1
        with fixture_sources(root, {"assign_pattern": POSITIVE_FIXTURE_SOURCE}) as paths:
            positive = semantic_ast_accesses(root, paths)
        if positive:
            print(
                "AST boundary destructuring plan dispatch was rejected: "
                + json.dumps(positive, sort_keys=True),
                file=sys.stderr,
            )
            return 1
        print(
            "ok: typed bytecode VM AST boundary rejects all inferred AST values "
            "and permits only AST-free destructuring plan dispatch",
        )
    else:
        print("ok: typed bytecode VM AST boundary is clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
