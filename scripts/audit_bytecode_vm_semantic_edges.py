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
from dataclasses import dataclass
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


@dataclass(frozen=True)
class Candidate:
    path: str
    line: int
    column: int
    enclosing: str
    spelling: str | None
    resolver_phase: str
    executable_hint: bool = True


@dataclass(frozen=True)
class ResolutionDiagnostic:
    candidate: Candidate
    reason: str
    detail: str = ""
    command: tuple[str, ...] = ()
    json_detail: str | None = None
    identity: str | None = None
    candidates: tuple[str, ...] = ()


@dataclass(frozen=True)
class ResolvedCompiler:
    candidate: Candidate
    target: str


@dataclass(frozen=True)
class ResolvedRuntime:
    candidate: Candidate
    target: str


@dataclass(frozen=True)
class ResolvedOutOfScope:
    candidate: Candidate
    identity: str


@dataclass(frozen=True)
class IntentionallyIgnored:
    candidate: Candidate | None
    reason: str


@dataclass(frozen=True)
class UnresolvedCandidate:
    diagnostic: ResolutionDiagnostic


@dataclass(frozen=True)
class AmbiguousCandidate:
    diagnostic: ResolutionDiagnostic

    @property
    def candidates(self) -> tuple[str, ...]:
        return self.diagnostic.candidates


ResolutionOutcome = (
    ResolvedCompiler
    | ResolvedRuntime
    | ResolvedOutOfScope
    | IntentionallyIgnored
    | UnresolvedCandidate
    | AmbiguousCandidate
)


class SemanticResolutionError(RuntimeError):
    def __init__(self, diagnostics: list[ResolutionDiagnostic]):
        self.diagnostics = tuple(sorted(diagnostics, key=diagnostic_sort_key))
        super().__init__(render_resolution_diagnostics(self.diagnostics))

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


def diagnostic_sort_key(diagnostic: ResolutionDiagnostic) -> tuple[object, ...]:
    candidate = diagnostic.candidate
    return (
        candidate.path,
        candidate.line,
        candidate.column,
        candidate.enclosing,
        candidate.spelling or "",
        candidate.resolver_phase,
        diagnostic.reason,
        diagnostic.identity or "",
        diagnostic.candidates,
        diagnostic.detail,
    )


def _diagnostic(
    candidate: Candidate,
    reason: str,
    *,
    detail: str = "",
    command: tuple[str, ...] = (),
    json_detail: str | None = None,
    identity: str | None = None,
    candidates: tuple[str, ...] = (),
) -> ResolutionDiagnostic:
    return ResolutionDiagnostic(
        candidate=candidate,
        reason=reason,
        detail=detail,
        command=command,
        json_detail=json_detail,
        identity=identity,
        candidates=tuple(sorted(set(candidates))),
    )


def _outcome_diagnostic(outcome: ResolutionOutcome) -> ResolutionDiagnostic | None:
    if isinstance(outcome, (UnresolvedCandidate, AmbiguousCandidate)):
        return outcome.diagnostic
    return None


def render_resolution_diagnostics(
    outcomes: list[ResolutionOutcome] | tuple[ResolutionOutcome, ...] | list[ResolutionDiagnostic] | tuple[ResolutionDiagnostic, ...],
) -> str:
    diagnostics: list[ResolutionDiagnostic] = []
    for outcome in outcomes:
        if isinstance(outcome, ResolutionDiagnostic):
            diagnostics.append(outcome)
        else:
            diagnostic = _outcome_diagnostic(outcome)
            if diagnostic is not None:
                diagnostics.append(diagnostic)
    diagnostics.sort(key=diagnostic_sort_key)
    unresolved = sum(d.reason != "ambiguous_mapping" for d in diagnostics)
    ambiguous = sum(d.reason == "ambiguous_mapping" for d in diagnostics)
    lines = [
        "bytecode VM semantic edge resolution failed: "
        f"unresolved={unresolved} ambiguous={ambiguous}"
    ]
    for diagnostic in diagnostics:
        candidate = diagnostic.candidate
        payload = {
            "path": candidate.path,
            "line": candidate.line,
            "column": candidate.column,
            "enclosing": candidate.enclosing,
            "spelling": candidate.spelling,
            "resolver_phase": candidate.resolver_phase,
            "reason": diagnostic.reason,
            "command": list(diagnostic.command),
            "json": diagnostic.json_detail,
            "identity": diagnostic.identity,
            "candidates": list(diagnostic.candidates),
            "detail": diagnostic.detail,
        }
        location = f"{candidate.path}:{candidate.line}:{candidate.column}"
        lines.append(
            "  "
            + location
            + " "
            + json.dumps(payload, sort_keys=True, separators=(",", ":"))
        )
    return "\n".join(lines)


def _runtime_target(query: str, identity: str, entry: dict[str, Any]) -> str:
    if identity.startswith(RUNTIME_PREFIXES):
        return identity
    if "::" in identity:
        return query
    return "@dowdiness/js_engine/interpreter/runtime." + identity


def _entry_package(entry: dict[str, Any]) -> str | None:
    package = entry.get("pkg")
    return package if isinstance(package, str) else None


RUNTIME_PACKAGE = "dowdiness/js_engine/interpreter/runtime"


def _is_runtime_query(query: str, entry: dict[str, Any]) -> bool:
    """Recognize runtime identities, including imported `using` aliases."""
    return query.startswith(RUNTIME_PREFIXES) or _entry_package(entry) == RUNTIME_PACKAGE


def classify_hover_identity(
    candidate: Candidate,
    identity: str | None,
    compiler_symbols: dict[str, dict[str, Any]],
    symbols_by_name: dict[str, list[tuple[str, dict[str, Any]]]],
    *,
    command: tuple[str, ...] = (),
    detail: str = "",
) -> ResolutionOutcome:
    if identity is None:
        if not candidate.executable_hint:
            return IntentionallyIgnored(candidate, "non_callable_reference")
        return UnresolvedCandidate(
            _diagnostic(
                candidate,
                "no_callable_identity",
                detail=detail,
                command=command,
            )
        )

    runtime_entries: dict[str, tuple[str, dict[str, Any]]] = {}
    for entries in symbols_by_name.values():
        for query, entry in entries:
            if not _is_runtime_query(query, entry):
                continue
            target_identity = symbol_identity(entry)
            if target_identity is None:
                continue
            target = _runtime_target(query, target_identity, entry)
            aliases = {
                query,
                target,
                "@runtime." + target_identity,
                "@dowdiness/js_engine/interpreter/runtime." + target_identity,
            }
            for alias in aliases:
                runtime_entries[alias] = (target, entry)
    if identity in runtime_entries:
        target, _ = runtime_entries[identity]
        return ResolvedRuntime(candidate, target)

    simple_name = identity.rsplit(".", 1)[-1]
    matches = sorted(
        {
            query
            for query, entry in symbols_by_name.get(simple_name, [])
            if _entry_package(entry) == COMPILER_PACKAGE or _is_runtime_query(query, entry)
        }
    )
    if len(matches) > 1:
        return AmbiguousCandidate(
            _diagnostic(
                candidate,
                "ambiguous_mapping",
                detail=detail,
                command=command,
                identity=identity,
                candidates=tuple(matches),
            )
        )
    if len(matches) == 1:
        query = matches[0]
        entry = next(
            entry for candidate_query, entry in symbols_by_name[simple_name]
            if candidate_query == query
        )
        if _entry_package(entry) == COMPILER_PACKAGE and not _is_runtime_query(query, entry):
            target = query
            return ResolvedCompiler(candidate, target)
        return ResolvedRuntime(candidate, _runtime_target(query, identity, entry))

    if identity in compiler_symbols:
        return ResolvedCompiler(candidate, identity)

    if identity.startswith(RUNTIME_PREFIXES):
        return UnresolvedCandidate(
            _diagnostic(
                candidate,
                "unresolved_mapping",
                detail=detail,
                command=command,
                identity=identity,
            )
        )
    if "::" in identity:
        return ResolvedOutOfScope(candidate, identity)
    if identity.startswith("@"):
        return ResolvedOutOfScope(candidate, identity)
    return ResolvedOutOfScope(candidate, identity)


def _callable_identity(contents: list[str]) -> str | None:
    match = FN_IDENTITY.search("\n".join(contents))
    return match.group(1) if match else None


def _hover_is_value_type(contents: list[str]) -> bool:
    first = contents[0].strip() if contents else ""
    if first.startswith("```moonbit"):
        first = first[len("```moonbit") :].lstrip("\n ")
        first = first.splitlines()[0] if first else ""
    return bool(
        re.match(r"^(?:\([^\n]*\)|[A-Za-z_@][^\n]*)\s*->", first)
    )


def classify_hover_result(
    candidate: Candidate,
    *,
    returncode: int,
    stdout: str,
    stderr: str,
    command: tuple[str, ...],
    compiler_symbols: dict[str, dict[str, Any]] | None = None,
    symbols: dict[str, dict[str, Any]] | None = None,
    symbols_by_name: dict[str, list[tuple[str, dict[str, Any]]]] | None = None,
) -> ResolutionOutcome:
    # `symbols` is accepted as a compatibility spelling for the compiler map
    # used by the deterministic tests and older callers.
    if compiler_symbols is None:
        compiler_symbols = symbols or {}
    if symbols_by_name is None:
        symbols_by_name = {}
    if returncode != 0:
        return UnresolvedCandidate(
            _diagnostic(
                candidate,
                "moon_ide_nonzero",
                detail=stderr.strip(),
                command=command,
            )
        )
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError as error:
        return UnresolvedCandidate(
            _diagnostic(
                candidate,
                "invalid_json",
                detail=str(error),
                command=command,
                json_detail=stdout,
            )
        )
    if not isinstance(payload, dict) or "contents" not in payload:
        return UnresolvedCandidate(
            _diagnostic(
                candidate,
                "missing_json_field",
                detail="required hover field `contents` is missing",
                command=command,
                json_detail=stdout,
            )
        )
    contents = payload["contents"]
    if not isinstance(contents, list) or not all(
        isinstance(content, str) for content in contents
    ):
        return UnresolvedCandidate(
            _diagnostic(
                candidate,
                "missing_json_field",
                detail="hover field `contents` must be an array of strings",
                command=command,
                json_detail=stdout,
            )
        )
    identity = _callable_identity(contents)
    if identity is None:
        if not candidate.executable_hint or _hover_is_value_type(contents):
            return IntentionallyIgnored(candidate, "non_callable_reference")
        return UnresolvedCandidate(
            _diagnostic(
                candidate,
                "no_callable_identity",
                detail="hover contents contain no callable identity",
                command=command,
                json_detail=stdout,
            )
        )
    return classify_hover_identity(
        candidate,
        identity,
        compiler_symbols,
        symbols_by_name,
        command=command,
        detail="\n".join(contents),
    )


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
            imported_runtime_alias = _imported_runtime_alias(root, entry, identity)
            if imported_runtime_alias is not None:
                simple_name = identity.split("::")[-1]
                by_simple_name.setdefault(simple_name, []).append(
                    (imported_runtime_alias, entry)
                )
                continue
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


def _imported_runtime_alias(
    root: Path,
    entry: dict[str, Any],
    identity: str,
) -> str | None:
    """Map a compiler-package `using @runtime` alias to its runtime target."""
    path = root / entry.get("path", "")
    if not path.is_file():
        return None
    name_range = entry.get("name_range")
    if not isinstance(name_range, list) or not name_range:
        return None
    line_number = name_range[0]
    if not isinstance(line_number, int):
        return None
    lines = path.read_text().splitlines()
    if line_number < 1 or line_number > len(lines):
        return None
    line = lines[line_number - 1]
    if "using @runtime" not in line:
        return None
    if not re.search(r"\b" + re.escape(identity.rsplit("::", 1)[-1]) + r"\b", line):
        return None
    return "@runtime." + identity


QUALIFIED_OR_MEMBER = re.compile(
    r"(?:@[A-Za-z0-9_./-]+\.)?[A-Za-z_][A-Za-z0-9_]*(?=\s*\()"
    r"|(?<=\.)[A-Za-z_][A-Za-z0-9_]*"
)

NON_CALLABLE_WORDS = {
    "break",
    "catch",
    "continue",
    "else",
    "for",
    "guard",
    "if",
    "let",
    "match",
    "raise",
    "return",
    "try",
    "while",
}


def _mark_interpolation(
    mask: list[bool],
    line: str,
    start: int,
) -> int:
    r"""Mark one basic `\{...}` expression and return its closing offset."""
    if start + 1 >= len(line) or line[start] != "\\" or line[start + 1] != "{":
        return start
    slash_count = 1
    before = start - 1
    while before >= 0 and line[before] == "\\":
        slash_count += 1
        before -= 1
    if slash_count % 2 == 0:
        return start + 1
    depth = 1
    cursor = start + 2
    while cursor < len(line):
        if line[cursor] == "{":
            depth += 1
        elif line[cursor] == "}":
            depth -= 1
            if depth == 0:
                for position in range(start + 2, cursor):
                    mask[position] = True
                return cursor
        cursor += 1
    for position in range(start + 2, len(line)):
        mask[position] = True
    return len(line) - 1


def _executable_mask(line: str) -> list[bool]:
    """Return source positions that can contain executable expressions.

    This is deliberately a lexical boundary only. Moon IDE remains the source
    of callable identity; the mask prevents comments and literal/raw text from
    becoming candidates while retaining ordinary and `$|` interpolation.
    """
    mask = [False] * len(line)
    if line.lstrip().startswith("#") and not line.lstrip().startswith("#|"):
        return mask
    cursor = 0
    while cursor < len(line):
        if line.startswith("//", cursor):
            break
        if line.startswith("#|", cursor):
            break
        if line.startswith("$|", cursor):
            cursor += 2
            while cursor < len(line):
                if line[cursor] == "\\" and cursor + 1 < len(line) and line[cursor + 1] == "{":
                    cursor = _mark_interpolation(mask, line, cursor)
                cursor += 1
            break
        if line[cursor] == '"':
            cursor += 1
            while cursor < len(line):
                if line[cursor] == "\\":
                    if cursor + 1 < len(line) and line[cursor + 1] == "{":
                        cursor = _mark_interpolation(mask, line, cursor)
                    cursor += 2
                    continue
                if line[cursor] == '"':
                    cursor += 1
                    break
                cursor += 1
            continue
        if line.startswith("/*", cursor):
            end = line.find("*/", cursor + 2)
            cursor = len(line) if end < 0 else end + 2
            continue
        if line.startswith("#|", cursor):
            break
        if line.startswith("$|", cursor):
            break
        mask[cursor] = True
        cursor += 1
    return mask


def _candidate_executable_hint(
    line: str,
    start: int,
    end: int,
    token: str,
) -> bool:
    suffix = line[end:]
    prefix = line[:start].rstrip()
    if prefix.startswith(("let ", "guard ")) or "=>" in suffix:
        return False
    if re.match(r"\s*\(", suffix):
        return True
    if re.search(r"(?<![=!<>])=(?![=])", prefix) and re.search(
        r"@[A-Za-z0-9_./-]+\.$", prefix
    ):
        return True
    if re.search(r"(?<![=!<>])=(?![=])\s*$", prefix):
        return True
    if token.startswith("@"):
        return True
    return False


def candidate_locations(
    root: Path,
    entry: dict[str, Any],
    known_names: set[str],
) -> list[Candidate | IntentionallyIgnored]:
    path = root / entry["path"]
    lines = path.read_text().splitlines()
    start_line, start_col, end_line, end_col = entry["range"]
    name_line, name_start, _, name_end = entry["name_range"]
    exclude_declaration_name = True
    locations: dict[tuple[int, int], Candidate | IntentionallyIgnored] = {}
    bare_names = {name.split("::")[-1] for name in known_names}
    bare_pattern = (
        re.compile(
            r"\b(?:" + "|".join(re.escape(name) for name in sorted(bare_names)) + r")\b"
        )
        if bare_names
        else None
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
        executable_mask = _executable_mask(line)
        patterns = [QUALIFIED_OR_MEMBER]
        if bare_pattern is not None:
            patterns.append(bare_pattern)
        for pattern in patterns:
            for match in pattern.finditer(fragment):
                token = match.group(0)
                if token in NON_CALLABLE_WORDS:
                    continue
                if pattern is bare_pattern:
                    after_match = fragment[match.end() :]
                    if after_match.startswith((".", "::")):
                        continue
                token_start = match.start()
                if token.startswith("@"):
                    token_start += token.rfind(".") + 1
                absolute_start = lo + token_start
                column = absolute_start + 1
                if (
                    exclude_declaration_name
                    and line_no == name_line
                    and name_start <= column <= name_end
                ):
                    continue
                executable = (
                    absolute_start < len(executable_mask)
                    and executable_mask[absolute_start]
                )
                candidate = Candidate(
                    path=entry["path"],
                    line=line_no,
                    column=column,
                    enclosing=symbol_identity(entry) or "<unknown>",
                    spelling=token,
                    resolver_phase="hover",
                    executable_hint=executable
                    and _candidate_executable_hint(
                        line,
                        absolute_start,
                        absolute_start + len(token.rsplit(".", 1)[-1]),
                        token,
                    ),
                )
                outcome: Candidate | IntentionallyIgnored = (
                    candidate
                    if executable
                    else IntentionallyIgnored(candidate, "literal_or_comment")
                )
                key = (line_no, column)
                previous = locations.get(key)
                if previous is None or (
                    isinstance(previous, IntentionallyIgnored)
                    and isinstance(outcome, Candidate)
                ):
                    locations[key] = outcome
    return [locations[key] for key in sorted(locations)]


def candidate_names(
    root: Path,
    entry: dict[str, Any],
    known_names: set[str],
) -> set[str]:
    return {
        outcome.spelling.rsplit(".", 1)[-1]
        for outcome in candidate_locations(root, entry, known_names)
        if isinstance(outcome, Candidate) and outcome.spelling is not None
    }


def _dollar_source_lines(root: Path, entry: dict[str, Any]) -> set[int]:
    lines = (root / entry["path"]).read_text().splitlines()
    start_line, _, end_line, _ = entry["range"]
    physical_end_line = min(end_line, len(lines))
    return {
        line_no
        for line_no in range(start_line, physical_end_line + 1)
        if lines[line_no - 1].lstrip().startswith("$|")
    }


def contains_dollar_multiline(root: Path, entry: dict[str, Any]) -> bool:
    return bool(_dollar_source_lines(root, entry))


FN_IDENTITY = re.compile(
    r"```moonbit\s*\n\s*(?:(?:pub(?:\([^)]*\))?|priv)\s+)?"
    r"fn(?:\[[^\]]+\])?\s+([^\s(]+)",
)


def resolve_hover(
    root: Path,
    candidate: Candidate,
    compiler_symbols: dict[str, dict[str, Any]],
    symbols_by_name: dict[str, list[tuple[str, dict[str, Any]]]],
) -> ResolutionOutcome:
    path = candidate.path
    line = candidate.line
    col = candidate.column
    command = (
        "moon",
        "ide",
        "hover",
        "--loc",
        f"{path}:{line}:{col}",
        "--output-json",
        "--no-check",
    )
    result = run(
        root,
        *command,
        check=False,
    )
    return classify_hover_result(
        candidate,
        returncode=result.returncode,
        stdout=result.stdout,
        stderr=result.stderr,
        command=command,
        compiler_symbols=compiler_symbols,
        symbols_by_name=symbols_by_name,
    )


def local_target(identity: str, symbols: dict[str, dict[str, Any]]) -> str | None:
    if identity in symbols:
        return identity
    unqualified = identity.rsplit(".", 1)[-1]
    if unqualified in symbols:
        return unqualified
    matches = [name for name in symbols if name.endswith(f"::{unqualified}")]
    return matches[0] if len(matches) == 1 else None


REFERENCE_LOCATION = re.compile(r"^(.+\.mbt):(\d+):(\d+)-", re.MULTILINE)


@dataclass(frozen=True)
class ReferenceLookup:
    references: tuple[tuple[str, int, int], ...]
    returncode: int
    command: tuple[str, ...]
    stdout: str
    stderr: str


def semantic_references(
    root: Path,
    query: str,
    cache: dict[str, ReferenceLookup],
) -> ReferenceLookup:
    if query in cache:
        return cache[query]
    command = ("moon", "ide", "find-references", query, "--no-check")
    result = run(
        root,
        *command,
        check=False,
    )
    references: list[tuple[str, int, int]] = []
    if result.returncode == 0:
        for match in REFERENCE_LOCATION.finditer(result.stdout):
            path = os.path.relpath(match.group(1), root)
            references.append((path, int(match.group(2)), int(match.group(3))))
    lookup = ReferenceLookup(
        references=tuple(sorted(set(references))),
        returncode=result.returncode,
        command=command,
        stdout=result.stdout,
        stderr=result.stderr,
    )
    cache[query] = lookup
    return lookup


def _reference_candidate(
    path: str,
    line: int,
    column: int,
    enclosing: str,
    spelling: str | None,
) -> Candidate:
    return Candidate(
        path=path,
        line=line,
        column=column,
        enclosing=enclosing,
        spelling=spelling,
        resolver_phase="find-references",
    )


def _recorded_target(
    query: str,
    target_entry: dict[str, Any],
) -> tuple[str, str] | None:
    target_identity = symbol_identity(target_entry)
    target_package = _entry_package(target_entry)
    if target_identity is None:
        return None
    if target_package == COMPILER_PACKAGE:
        return "compiler", target_identity
    if _is_runtime_query(query, target_entry):
        return "runtime", _runtime_target(query, target_identity, target_entry)
    return None


def _add_resolved_edge(
    edges: set[tuple[str, str, int, int, str, str]],
    pending: list[str],
    visited: set[str],
    enclosing: str,
    outcome: ResolutionOutcome,
) -> None:
    if isinstance(outcome, ResolvedRuntime):
        candidate = outcome.candidate
        edges.add(
            (
                enclosing,
                candidate.path,
                candidate.line,
                candidate.column,
                "runtime",
                outcome.target,
            )
        )
    elif isinstance(outcome, ResolvedCompiler):
        candidate = outcome.candidate
        if outcome.target != enclosing:
            edges.add(
                (
                    enclosing,
                    candidate.path,
                    candidate.line,
                    candidate.column,
                    "compiler",
                    outcome.target,
                )
            )
            if outcome.target not in visited:
                pending.append(outcome.target)


def collect_semantic_edges(
    root: Path,
    root_symbols: tuple[str, ...],
) -> tuple[list[dict[str, Any]], list[ResolutionOutcome]]:
    symbols, symbols_by_name = load_symbols(root)
    missing_roots = [symbol for symbol in root_symbols if symbol not in symbols]
    if missing_roots:
        raise RuntimeError(f"semantic audit roots not found: {missing_roots}")
    pending = list(root_symbols)
    visited: set[str] = set()
    reference_cache: dict[str, ReferenceLookup] = {}
    edges: set[tuple[str, str, int, int, str, str]] = set()
    outcomes: list[ResolutionOutcome] = []
    while pending:
        enclosing = pending.pop()
        if enclosing in visited:
            continue
        visited.add(enclosing)
        entry = symbols[enclosing]
        path = entry["path"]
        has_dollar_multiline = contains_dollar_multiline(root, entry)
        dollar_lines = _dollar_source_lines(root, entry) if has_dollar_multiline else set()
        candidate_outcomes = candidate_locations(root, entry, set(symbols_by_name))
        for candidate_outcome in candidate_outcomes:
            if isinstance(candidate_outcome, IntentionallyIgnored):
                outcomes.append(candidate_outcome)
                continue
            if not candidate_outcome.executable_hint:
                outcomes.append(
                    IntentionallyIgnored(candidate_outcome, "non_callable_reference")
                )
                continue
            if candidate_outcome.line in dollar_lines:
                continue
            outcome = resolve_hover(
                root,
                candidate_outcome,
                symbols,
                symbols_by_name,
            )
            outcomes.append(outcome)
            _add_resolved_edge(
                edges,
                pending,
                visited,
                enclosing,
                outcome,
            )
        # `moon ide hover` currently uses physical source positions while its
        # symbol/reference index uses logical positions for `$|` strings. Use
        # semantic find-references as the fallback authority for every
        # executable known symbol in an enclosing source containing `$|`. This
        # also catches first-class aliases without guessing receiver spelling.
        start_line, _, end_line, _ = entry["range"]
        fallback_candidates = (
            [
                candidate_outcome
                for candidate_outcome in candidate_outcomes
                if isinstance(candidate_outcome, Candidate)
                and candidate_outcome.executable_hint
                and candidate_outcome.line in dollar_lines
            ]
            if dollar_lines
            else []
        )
        for candidate in fallback_candidates:
            spelling = candidate.spelling or ""
            name = spelling.rsplit(".", 1)[-1]
            matches = symbols_by_name.get(name, [])
            exact_matches = [
                (query, target_entry)
                for query, target_entry in matches
                if query == spelling
                or (
                    (recorded := _recorded_target(query, target_entry)) is not None
                    and recorded[1] == spelling
                )
            ]
            if exact_matches:
                matches = exact_matches
            unique_matches = {
                query: target_entry for query, target_entry in matches
            }
            if len(unique_matches) > 1:
                queries = tuple(sorted(unique_matches))
                outcomes.append(
                    AmbiguousCandidate(
                        _diagnostic(
                            Candidate(
                                path=candidate.path,
                                line=candidate.line,
                                column=candidate.column,
                                enclosing=candidate.enclosing,
                                spelling=candidate.spelling,
                                resolver_phase="find-references",
                            ),
                            "ambiguous_mapping",
                            detail="simple-name fallback has multiple local identities",
                            identity=spelling,
                            candidates=queries,
                        )
                    )
                )
                continue
            if not unique_matches:
                outcomes.append(
                    UnresolvedCandidate(
                        _diagnostic(
                            Candidate(
                                path=candidate.path,
                                line=candidate.line,
                                column=candidate.column,
                                enclosing=candidate.enclosing,
                                spelling=candidate.spelling,
                                resolver_phase="find-references",
                            ),
                            "find_references_no_symbol_match",
                            detail=(
                                "no compiler/runtime symbol-table identity matched "
                                "executable fallback candidate"
                            ),
                            identity=spelling,
                        )
                    )
                )
                continue
            if len(unique_matches) != 1:
                continue
            query, target_entry = next(iter(unique_matches.items()))
            recorded = _recorded_target(query, target_entry)
            if recorded is None:
                outcomes.append(
                    IntentionallyIgnored(candidate, "out_of_scope_reference")
                )
                continue
            lookup = semantic_references(root, query, reference_cache)
            if lookup.returncode != 0:
                outcomes.append(
                    UnresolvedCandidate(
                        _diagnostic(
                            Candidate(
                                path=candidate.path,
                                line=candidate.line,
                                column=candidate.column,
                                enclosing=candidate.enclosing,
                                spelling=candidate.spelling,
                                resolver_phase="find-references",
                            ),
                            "find_references_nonzero",
                            detail=lookup.stderr.strip(),
                            command=lookup.command,
                        )
                    )
                )
                continue
            kind, target = recorded
            matching_references: list[tuple[str, int, int]] = []
            for ref_path, ref_line, ref_col in lookup.references:
                if ref_path != path or not start_line <= ref_line <= end_line:
                    continue
                name_line, name_start, _, name_end = target_entry["name_range"]
                if (
                    ref_path == target_entry["path"]
                    and ref_line == name_line
                    and name_start <= ref_col <= name_end
                ):
                    continue
                matching_references.append((ref_path, ref_line, ref_col))
            if not matching_references:
                outcomes.append(
                    UnresolvedCandidate(
                        _diagnostic(
                            Candidate(
                                path=candidate.path,
                                line=candidate.line,
                                column=candidate.column,
                                enclosing=candidate.enclosing,
                                spelling=candidate.spelling,
                                resolver_phase="find-references",
                            ),
                            "find_references_no_reference",
                            detail="no reference location matched the enclosing source range",
                            command=lookup.command,
                            identity=target,
                        )
                    )
                )
                continue
            for ref_path, ref_line, ref_col in matching_references:
                ref_candidate = _reference_candidate(
                    ref_path,
                    ref_line,
                    ref_col,
                    enclosing,
                    candidate.spelling,
                )
                outcome = (
                    ResolvedCompiler(ref_candidate, target)
                    if kind == "compiler"
                    else ResolvedRuntime(ref_candidate, target)
                )
                outcomes.append(outcome)
                _add_resolved_edge(edges, pending, visited, enclosing, outcome)
    rendered_edges = [
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
    return rendered_edges, outcomes


def semantic_edges_from_roots(
    root: Path,
    root_symbols: tuple[str, ...],
) -> list[dict[str, Any]]:
    edges, outcomes = collect_semantic_edges(root, root_symbols)
    diagnostics = [
        diagnostic
        for outcome in outcomes
        if (diagnostic := _outcome_diagnostic(outcome)) is not None
    ]
    if diagnostics:
        raise SemanticResolutionError(diagnostics)
    return edges


def semantic_edges(root: Path, root_symbol: str) -> list[dict[str, Any]]:
    return semantic_edges_from_roots(root, (root_symbol,))


def update_root_override_error(
    update: bool,
    root_symbols: list[str] | tuple[str, ...] | None,
) -> str | None:
    if update and root_symbols:
        return "--update cannot be combined with --root-symbol; use canonical roots"
    return None


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
    if (error := update_root_override_error(args.update, args.root_symbols)) is not None:
        print(f"error: {error}", file=sys.stderr)
        return 2
    root = args.root.resolve()
    # CI restores `_build` from another commit. Never let `--no-check` IDE
    # queries consume that stale source-position/type index.
    ensure_semantic_index(root)
    root_symbols = tuple(args.root_symbols) if args.root_symbols else ROOT_SYMBOLS
    try:
        edges = semantic_edges_from_roots(root, root_symbols)
    except SemanticResolutionError as error:
        print(str(error), file=sys.stderr)
        return 1
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
