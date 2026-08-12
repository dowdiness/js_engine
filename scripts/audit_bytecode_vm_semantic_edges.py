#!/usr/bin/env python3
"""Fail closed when the bytecode activation's resolved call graph changes.

The graph is rooted at the activation's start, step, completion-delivery, and
direct-run boundaries. MoonBit's IDE resolves each candidate reference; this
script never treats receiver spelling as symbol identity. Consequently receiver
aliases, compiler wrappers, and expressions inside interpolated strings are
ordinary semantic edges, while comments and raw/literal string text are not.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Any


ROOT_SYMBOLS = (
    "BytecodeExecutorCode::start",
    "BytecodeFrame::step",
    "BytecodeFrame::deliver_activation_completion",
    "run_bytecode_function",
)
COMPILER_PACKAGE = "dowdiness/js_engine/compiler"
RUNTIME_PREFIXES = (
    "@runtime.",
    "@dowdiness/js_engine/interpreter/runtime.",
)
BASELINE = Path("scripts/bytecode_vm_semantic_edges.json")

ORDINARY_FIXTURE = r'''///|
using @runtime { make_array }

///|
#warnings("-unused_value")
fn semantic_edge_audit_ordinary_fixture(interp : Interpreter) -> String raise Error {
  let factory = make_array
  ignore(factory([]))
  let ordinary = "ordinary \{interp.observe_execution_step()} \{@runtime.make_array([])}"
  let escaped = "escaped \\{interp.get_console_member(\"ignored\")}"
  let raw = #|raw \{@runtime.make_array([])}
  ordinary + escaped + raw
}
'''

COMBINED_FIXTURE = r'''///|
#warnings("-unused_value")
fn semantic_edge_audit_fixture_root(interp : Interpreter) -> String raise Error {
  let executor = interp
  executor.observe_execution_step()
  let wrapper = semantic_edge_audit_cross_file_wrapper
  wrapper(interp)
  let ordinary = "ordinary \{interp.observe_execution_step()} \{@runtime.make_array([])}"
  let dollar =
    $|dollar \{interp.observe_execution_step()} \{@runtime.make_array([])}
  let escaped = "escaped \\{interp.get_console_member(\"ignored\")} \\{@runtime.make_array([])}"
  let raw =
    #|raw \{interp.get_console_member("ignored")} \{@runtime.make_array([])}
  ordinary + dollar + escaped + raw
}

///|
#warnings("-unused_value")
fn semantic_edge_audit_startup_fixture_root(interp : Interpreter) -> Unit raise Error {
  semantic_edge_audit_cross_file_wrapper(interp)
}

///|
#warnings("-unused_value")
fn semantic_edge_audit_completion_fixture_root() -> Unit {
  let complete = @runtime.make_array
  ignore(complete([]))
}
'''

WRAPPER_FIXTURE = r'''///|
#warnings("-unused_value")
fn semantic_edge_audit_cross_file_wrapper(
  interp : Interpreter,
) -> Unit raise Error {
  ignore(interp.get_console_member("log"))
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


def ensure_semantic_index(root: Path) -> None:
    checked = run(root, "moon", "check", "--deny-warn", check=False)
    if checked.returncode != 0:
        raise RuntimeError(
            "cannot build the semantic edge index:\n"
            + checked.stdout
            + checked.stderr
        )


@contextmanager
def semantic_fixture_sources(root: Path):
    fixtures = {
        root / "compiler/semantic_edge_audit_ordinary_fixture_tmp.mbt": ORDINARY_FIXTURE,
        root / "compiler/semantic_edge_audit_fixture_tmp.mbt": COMBINED_FIXTURE,
        root / "compiler/semantic_edge_audit_wrapper_tmp.mbt": WRAPPER_FIXTURE,
    }
    preexisting = [path for path in fixtures if path.exists()]
    if preexisting:
        raise RuntimeError(f"semantic audit fixture path already exists: {preexisting}")
    try:
        for path, source in fixtures.items():
            path.write_text(source)
        ensure_semantic_index(root)
        yield
    finally:
        for path in fixtures:
            path.unlink(missing_ok=True)
        cleanup = run(root, "moon", "check", "--deny-warn", check=False)
        if cleanup.returncode != 0 and sys.exc_info()[0] is None:
            raise RuntimeError(
                "semantic audit fixture cleanup failed:\n"
                + cleanup.stdout
                + cleanup.stderr
            )


def symbol_identity(entry: dict[str, Any]) -> str | None:
    kind = entry.get("kind", [])
    if len(kind) == 2 and kind[0] == "Sym":
        return kind[1]
    if len(kind) == 3 and kind[0] == "SymChild":
        return f"{kind[1]}::{kind[2]}"
    if len(kind) == 4 and kind[0] == "TraitImpl":
        return f"{kind[3]}::{kind[2]}"
    return None


def load_symbols(
    root: Path,
) -> tuple[dict[str, dict[str, Any]], dict[str, list[tuple[str, dict[str, Any]]]]]:
    symbols_path = root / "symbols.jsonl"
    try:
        run(root, "moon", "ide", "gen-symbols", "--no-check")
        compiler_symbols: dict[str, dict[str, Any]] = {}
        by_simple_name: dict[str, list[tuple[str, dict[str, Any]]]] = {}
        for line in symbols_path.read_text().splitlines():
            entry = json.loads(line)
            identity = symbol_identity(entry)
            if identity is None:
                continue
            package = entry.get("pkg")
            if package == COMPILER_PACKAGE:
                query = identity
                compiler_symbols[identity] = entry
            elif package == "dowdiness/js_engine/interpreter/runtime":
                if "::" in identity:
                    query = f"@runtime.{identity}"
                else:
                    query = f"@runtime.{identity}"
            else:
                continue
            simple_name = identity.split("::")[-1]
            by_simple_name.setdefault(simple_name, []).append((query, entry))
        return compiler_symbols, by_simple_name
    finally:
        symbols_path.unlink(missing_ok=True)


QUALIFIED_OR_MEMBER = re.compile(
    r"(?:@[A-Za-z0-9_./-]+\.)?[A-Za-z_][A-Za-z0-9_]*(?=\s*\()"
    r"|(?<=\.)[A-Za-z_][A-Za-z0-9_]*"
)


def candidate_locations(
    root: Path,
    entry: dict[str, Any],
    compiler_names: set[str],
) -> list[tuple[int, int]]:
    path = root / entry["path"]
    lines = path.read_text().splitlines()
    start_line, start_col, end_line, end_col = entry["range"]
    name_line, name_start, _, name_end = entry["name_range"]
    exclude_declaration_name = entry.get("kind", [None])[0] == "TraitImpl"
    locations: set[tuple[int, int]] = set()
    bare_names = {name.split("::")[-1] for name in compiler_names}
    bare_pattern = re.compile(
        r"\b(?:" + "|".join(re.escape(name) for name in sorted(bare_names)) + r")\b"
    )
    # Current `moon ide gen-symbols` reports logical source lines for `$|`
    # interpolation, which can extend past the physical line count. Hover still
    # uses physical source coordinates, so clamp the enclosing range here.
    physical_end_line = min(end_line, len(lines))
    for line_no in range(start_line, physical_end_line + 1):
        line = lines[line_no - 1]
        lo = start_col - 1 if line_no == start_line else 0
        hi = end_col - 1 if line_no == end_line else len(line)
        fragment = line[lo:hi]
        for pattern in (QUALIFIED_OR_MEMBER, bare_pattern):
            for match in pattern.finditer(fragment):
                token = match.group(0)
                token_start = match.start()
                if token.startswith("@"):
                    token_start += token.rfind(".") + 1
                column = lo + token_start + 1
                if (
                    exclude_declaration_name
                    and line_no == name_line
                    and name_start <= column <= name_end
                ):
                    continue
                locations.add((line_no, column))
    return sorted(locations)


def candidate_names(
    root: Path,
    entry: dict[str, Any],
    known_names: set[str],
) -> set[str]:
    path = root / entry["path"]
    lines = path.read_text().splitlines()
    start_line, start_col, end_line, end_col = entry["range"]
    physical_end_line = min(end_line, len(lines))
    names: set[str] = set()
    pattern = re.compile(
        r"\b(?:" + "|".join(re.escape(name) for name in sorted(known_names)) + r")\b"
    )
    for line_no in range(start_line, physical_end_line + 1):
        line = lines[line_no - 1]
        lo = start_col - 1 if line_no == start_line else 0
        hi = end_col - 1 if line_no == end_line else len(line)
        names.update(match.group(0) for match in pattern.finditer(line[lo:hi]))
    return names


def contains_dollar_multiline(root: Path, entry: dict[str, Any]) -> bool:
    lines = (root / entry["path"]).read_text().splitlines()
    start_line, _, end_line, _ = entry["range"]
    physical_end_line = min(end_line, len(lines))
    return any(
        lines[line_no - 1].lstrip().startswith("$|")
        for line_no in range(start_line, physical_end_line + 1)
    )


FN_IDENTITY = re.compile(
    r"```moonbit\s+(?:(?:pub(?:\([^)]*\))?|priv)\s+)?fn\s+([^\s(]+)",
)


def resolve_hover(root: Path, path: str, line: int, col: int) -> str | None:
    result = run(
        root,
        "moon",
        "ide",
        "hover",
        "--loc",
        f"{path}:{line}:{col}",
        "--output-json",
        "--no-check",
        check=False,
    )
    if result.returncode != 0:
        return None
    try:
        contents = "\n".join(json.loads(result.stdout)["contents"])
    except (KeyError, TypeError, json.JSONDecodeError):
        return None
    match = FN_IDENTITY.search(contents)
    return match.group(1) if match else None


def local_target(identity: str, symbols: dict[str, dict[str, Any]]) -> str | None:
    if identity in symbols:
        return identity
    unqualified = identity.rsplit(".", 1)[-1]
    if unqualified in symbols:
        return unqualified
    matches = [name for name in symbols if name.endswith(f"::{unqualified}")]
    return matches[0] if len(matches) == 1 else None


REFERENCE_LOCATION = re.compile(r"^(.+\.mbt):(\d+):(\d+)-", re.MULTILINE)


def semantic_references(
    root: Path,
    query: str,
    cache: dict[str, list[tuple[str, int, int]]],
) -> list[tuple[str, int, int]]:
    if query in cache:
        return cache[query]
    result = run(
        root,
        "moon",
        "ide",
        "find-references",
        query,
        "--no-check",
        check=False,
    )
    references: list[tuple[str, int, int]] = []
    if result.returncode == 0:
        for match in REFERENCE_LOCATION.finditer(result.stdout):
            path = os.path.relpath(match.group(1), root)
            references.append((path, int(match.group(2)), int(match.group(3))))
    cache[query] = references
    return references


def semantic_edges_from_roots(
    root: Path,
    root_symbols: tuple[str, ...],
) -> list[dict[str, Any]]:
    symbols, symbols_by_name = load_symbols(root)
    missing_roots = [symbol for symbol in root_symbols if symbol not in symbols]
    if missing_roots:
        raise RuntimeError(f"semantic audit roots not found: {missing_roots}")
    pending = list(root_symbols)
    visited: set[str] = set()
    reference_cache: dict[str, list[tuple[str, int, int]]] = {}
    edges: set[tuple[str, str, int, int, str, str]] = set()
    while pending:
        enclosing = pending.pop()
        if enclosing in visited:
            continue
        visited.add(enclosing)
        entry = symbols[enclosing]
        path = entry["path"]
        has_dollar_multiline = contains_dollar_multiline(root, entry)
        hover_locations = (
            []
            if has_dollar_multiline
            else candidate_locations(root, entry, set(symbols_by_name))
        )
        for line, col in hover_locations:
            target = resolve_hover(root, path, line, col)
            if target is None:
                continue
            if target.startswith(RUNTIME_PREFIXES):
                edges.add((enclosing, path, line, col, "runtime", target))
                continue
            compiler_target = local_target(target, symbols)
            if compiler_target is not None:
                if compiler_target != enclosing:
                    edges.add((enclosing, path, line, col, "compiler", compiler_target))
                    if compiler_target not in visited:
                        pending.append(compiler_target)
                continue
        # `moon ide hover` currently uses physical source positions while its
        # symbol/reference index uses logical positions for `$|` strings. Use
        # semantic find-references as the fallback authority for every known
        # symbol name present in the enclosing source. This also catches
        # first-class aliases without guessing their receiver spelling.
        start_line, _, end_line, _ = entry["range"]
        fallback_names = (
            candidate_names(root, entry, set(symbols_by_name))
            if has_dollar_multiline
            else set()
        )
        for name in fallback_names:
            for query, target_entry in symbols_by_name[name]:
                target_identity = symbol_identity(target_entry)
                if target_identity is None:
                    continue
                target_package = target_entry["pkg"]
                if target_package == COMPILER_PACKAGE:
                    recorded_target = target_identity
                    kind = "compiler"
                else:
                    recorded_target = (
                        query
                        if "::" in target_identity
                        else "@dowdiness/js_engine/interpreter/runtime."
                        + target_identity
                    )
                    kind = "runtime"
                for ref_path, ref_line, ref_col in semantic_references(
                    root, query, reference_cache,
                ):
                    if ref_path != path or not start_line <= ref_line <= end_line:
                        continue
                    name_line, name_start, _, name_end = target_entry["name_range"]
                    if (
                        ref_path == target_entry["path"]
                        and ref_line == name_line
                        and name_start <= ref_col <= name_end
                    ):
                        continue
                    edges.add(
                        (enclosing, path, ref_line, ref_col, kind, recorded_target),
                    )
                    if kind == "compiler" and recorded_target not in visited:
                        pending.append(recorded_target)
    return [
        {
            "enclosing": enclosing,
            "path": path,
            "line": line,
            "column": col,
            "kind": kind,
            "target": target,
        }
        for enclosing, path, line, col, kind, target in sorted(edges)
    ]


def semantic_edges(root: Path, root_symbol: str) -> list[dict[str, Any]]:
    return semantic_edges_from_roots(root, (root_symbol,))


def render_payload(payload: dict[str, Any]) -> str:
    edge_lines = [
        "    " + json.dumps(edge, sort_keys=True, separators=(",", ":"))
        for edge in payload["edges"]
    ]
    rendered_edges = ",\n".join(edge_lines)
    return (
        "{\n"
        f"  \"version\": {payload['version']},\n"
        f"  \"roots\": {json.dumps(payload['roots'])},\n"
        "  \"edges\": [\n"
        f"{rendered_edges}\n"
        "  ]\n"
        "}\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--update", action="store_true")
    parser.add_argument(
        "--root-symbol",
        action="append",
        dest="root_symbols",
        help="override an activation root; repeat to supply a root set",
    )
    parser.add_argument("--print", action="store_true", dest="print_edges")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    # CI restores `_build` from another commit. Never let `--no-check` IDE
    # queries consume that stale source-position/type index.
    ensure_semantic_index(root)
    root_symbols = tuple(args.root_symbols) if args.root_symbols else ROOT_SYMBOLS
    edges = semantic_edges_from_roots(root, root_symbols)
    if args.self_test:
        with semantic_fixture_sources(root):
            ordinary_edges = semantic_edges(
                root, "semantic_edge_audit_ordinary_fixture",
            )
            ordinary_observed = [
                (edge["kind"], edge["target"]) for edge in ordinary_edges
            ]
            ordinary_runtime = [
                edge for edge in ordinary_observed if edge[0] == "runtime"
            ]
            expected_ordinary = sorted(
                [
                    ("runtime", "@runtime.Interpreter::observe_execution_step"),
                    (
                        "runtime",
                        "@dowdiness/js_engine/interpreter/runtime.make_array",
                    ),
                    (
                        "runtime",
                        "@dowdiness/js_engine/interpreter/runtime.make_array",
                    ),
                ],
            )
            if sorted(ordinary_runtime) != expected_ordinary:
                print(
                    "ordinary interpolation semantic self-test failed: "
                    f"observed={sorted(ordinary_observed)}",
                    file=sys.stderr,
                )
                return 1
            fixture_edges = semantic_edges_from_roots(
                root,
                (
                    "semantic_edge_audit_fixture_root",
                    "semantic_edge_audit_startup_fixture_root",
                    "semantic_edge_audit_completion_fixture_root",
                ),
            )
        observed = [
            (edge["enclosing"], edge["kind"], edge["target"])
            for edge in fixture_edges
        ]
        required = {
            (
                "semantic_edge_audit_fixture_root",
                "compiler",
                "semantic_edge_audit_cross_file_wrapper",
            ),
            (
                "semantic_edge_audit_cross_file_wrapper",
                "runtime",
                "@runtime.Interpreter::get_console_member",
            ),
            (
                "semantic_edge_audit_startup_fixture_root",
                "compiler",
                "semantic_edge_audit_cross_file_wrapper",
            ),
            (
                "semantic_edge_audit_completion_fixture_root",
                "runtime",
                "@dowdiness/js_engine/interpreter/runtime.make_array",
            ),
        }
        missing = sorted(required - set(observed))
        root_observe = sum(
            enclosing == "semantic_edge_audit_fixture_root"
            and kind == "runtime"
            and target == "@runtime.Interpreter::observe_execution_step"
            for enclosing, kind, target in observed
        )
        root_arrays = sum(
            enclosing == "semantic_edge_audit_fixture_root"
            and kind == "runtime"
            and target
            == "@dowdiness/js_engine/interpreter/runtime.make_array"
            for enclosing, kind, target in observed
        )
        forbidden_literal_edges = [
            item
            for item in observed
            if item[0] == "semantic_edge_audit_fixture_root"
            and item[2] == "@runtime.Interpreter::get_console_member"
        ]
        if missing or root_observe != 3 or root_arrays != 2 or forbidden_literal_edges:
            print(
                "semantic edge self-test failed: "
                f"missing={missing}, observe={root_observe}, arrays={root_arrays}, "
                f"literal_edges={forbidden_literal_edges}",
                file=sys.stderr,
            )
            return 1
        print("ok: semantic resolver covers aliases, wrappers, and interpolation")
    payload = {"version": 2, "roots": list(root_symbols), "edges": edges}
    baseline = root / BASELINE
    rendered = render_payload(payload)
    if args.print_edges:
        sys.stdout.write(rendered)
    if args.update:
        baseline.write_text(rendered)
        print(f"updated {BASELINE} ({len(edges)} resolved edges)")
        return 0
    if not baseline.exists():
        print(f"semantic edge baseline missing: {BASELINE}", file=sys.stderr)
        return 1
    expected = json.loads(baseline.read_text())
    if expected != payload:
        expected_edges = {json.dumps(edge, sort_keys=True) for edge in expected.get("edges", [])}
        actual_edges = {json.dumps(edge, sort_keys=True) for edge in edges}
        print("bytecode VM semantic edge audit failed:", file=sys.stderr)
        for edge in sorted(actual_edges - expected_edges):
            print(f"+ {edge}", file=sys.stderr)
        for edge in sorted(expected_edges - actual_edges):
            print(f"- {edge}", file=sys.stderr)
        print("review the resolved call graph; use --update only for an intentional boundary change", file=sys.stderr)
        return 1
    runtime_count = sum(edge["kind"] == "runtime" for edge in edges)
    print(
        f"ok: bytecode VM semantic call graph matches inventory "
        f"({len(edges)} edges, {runtime_count} runtime boundaries)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
