#!/usr/bin/env python3
"""Deterministic tests for the bytecode semantic-edge resolver boundary."""

from __future__ import annotations

import json
import sys
from tempfile import TemporaryDirectory
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_ROOT))
import audit_bytecode_vm_semantic_edges as audit_script  # noqa: E402

from audit_bytecode_vm_semantic_edges import (  # noqa: E402
    AmbiguousCandidate,
    Candidate,
    IntentionallyIgnored,
    ResolvedCompiler,
    ResolvedOutOfScope,
    ResolvedRuntime,
    UnresolvedCandidate,
    classify_hover_identity,
    classify_hover_result,
    render_resolution_diagnostics,
    update_root_override_error,
)


def candidate(spelling: str = "shared") -> Candidate:
    return Candidate(
        path="compiler/fixture.mbt",
        line=12,
        column=9,
        enclosing="fixture_root",
        spelling=spelling,
        resolver_phase="hover",
    )


def compiler_entry(identity: str) -> dict[str, object]:
    return {
        "kind": ["Sym", identity],
        "pkg": "dowdiness/js_engine/compiler",
        "path": "compiler/fixture.mbt",
        "range": [1, 1, 2, 2],
        "name_range": [1, 4, 1, 10],
    }


def runtime_entry(identity: str) -> dict[str, object]:
    return {
        "kind": ["Sym", identity],
        "pkg": "dowdiness/js_engine/interpreter/runtime",
        "path": "interpreter/runtime/fixture.mbt",
        "range": [1, 1, 2, 2],
        "name_range": [1, 4, 1, 10],
    }


class ResolverOutcomeTests(unittest.TestCase):
    def test_unqualified_compiler_target_is_explicitly_ambiguous(self) -> None:
        symbols = {
            "Alpha::shared": compiler_entry("Alpha::shared"),
            "Beta::shared": compiler_entry("Beta::shared"),
        }
        by_name = {
            "shared": [
                ("Alpha::shared", symbols["Alpha::shared"]),
                ("Beta::shared", symbols["Beta::shared"]),
            ]
        }

        outcome = classify_hover_identity(
            candidate(),
            "shared",
            symbols,
            by_name,
        )

        self.assertIsInstance(outcome, AmbiguousCandidate)
        self.assertEqual(outcome.candidates, ("Alpha::shared", "Beta::shared"))

    def test_unqualified_runtime_and_compiler_target_is_ambiguous(self) -> None:
        symbols = {"Compiler::shared": compiler_entry("Compiler::shared")}
        by_name = {
            "shared": [
                ("Compiler::shared", symbols["Compiler::shared"]),
                (
                    "@runtime.shared",
                    runtime_entry("shared"),
                ),
            ]
        }

        outcome = classify_hover_identity(
            candidate(),
            "shared",
            symbols,
            by_name,
        )

        self.assertIsInstance(outcome, AmbiguousCandidate)
        self.assertEqual(
            outcome.candidates,
            ("@runtime.shared", "Compiler::shared"),
        )

    def test_resolved_runtime_and_external_targets_remain_distinct(self) -> None:
        symbols = {"Compiler::known": compiler_entry("Compiler::known")}
        by_name = {
            "known": [("Compiler::known", symbols["Compiler::known"])],
            "runtime_call": [
                (
                    "@runtime.runtime_call",
                    runtime_entry("runtime_call"),
                )
            ],
        }

        runtime = classify_hover_identity(
            candidate("runtime_call"),
            "@runtime.runtime_call",
            symbols,
            by_name,
        )
        external = classify_hover_identity(
            candidate("external"),
            "@moonbitlang/core.external",
            symbols,
            by_name,
        )

        self.assertIsInstance(runtime, ResolvedRuntime)
        self.assertIsInstance(external, ResolvedOutOfScope)

    def test_hover_failures_keep_the_failure_phase_and_detail(self) -> None:
        command = ("moon", "ide", "hover", "--output-json")
        cases = [
            ("moon_ide_nonzero", 1, "", "index unavailable"),
            ("invalid_json", 0, "{", ""),
            ("missing_json_field", 0, json.dumps({"range": "1:1-1:2"}), ""),
            (
                "no_callable_identity",
                0,
                json.dumps({"contents": ["```moonbit\nstruct Value {}\n```"]}),
                "",
            ),
        ]
        for reason, returncode, stdout, stderr in cases:
            with self.subTest(reason=reason):
                outcome = classify_hover_result(
                    candidate(),
                    returncode=returncode,
                    stdout=stdout,
                    stderr=stderr,
                    command=command,
                    symbols={},
                    symbols_by_name={},
                )
                self.assertIsInstance(outcome, UnresolvedCandidate)
                self.assertEqual(outcome.diagnostic.reason, reason)
                self.assertEqual(outcome.diagnostic.command, command)

    def test_diagnostics_are_sorted_and_counted(self) -> None:
        symbols = {
            "Alpha::shared": compiler_entry("Alpha::shared"),
            "Beta::shared": compiler_entry("Beta::shared"),
        }
        by_name = {
            "shared": [
                ("Beta::shared", symbols["Beta::shared"]),
                ("Alpha::shared", symbols["Alpha::shared"]),
            ]
        }
        ambiguous = classify_hover_identity(candidate(), "shared", symbols, by_name)
        unresolved = classify_hover_result(
            Candidate(
                path="compiler/a.mbt",
                line=3,
                column=2,
                enclosing="a",
                spelling="lost",
                resolver_phase="hover",
            ),
            returncode=1,
            stdout="",
            stderr="failed",
            command=("moon", "ide", "hover"),
            symbols={},
            symbols_by_name={},
        )

        rendered = render_resolution_diagnostics([ambiguous, unresolved])

        self.assertIn("unresolved=1 ambiguous=1", rendered)
        self.assertLess(rendered.index("compiler/a.mbt:3:2"), rendered.index("compiler/fixture.mbt:12:9"))

    def test_dollar_fallback_without_symbol_match_is_unresolved(self) -> None:
        entry = {
            "kind": ["Sym", "fixture_root"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "compiler/fixture.mbt",
            "range": [1, 1, 1, 30],
            "name_range": [1, 4, 1, 16],
        }
        fallback = Candidate(
            path="compiler/fixture.mbt",
            line=1,
            column=25,
            enclosing="fixture_root",
            spelling="missing_call",
            resolver_phase="hover",
            executable_hint=True,
        )
        with patch.object(
            audit_script,
            "load_symbols",
            return_value=({"fixture_root": entry}, {}),
        ), patch.object(
            audit_script,
            "candidate_locations",
            return_value=[fallback],
        ), patch.object(
            audit_script,
            "contains_dollar_multiline",
            return_value=True,
        ), patch.object(
            audit_script,
            "_dollar_source_lines",
            return_value={1},
        ), patch.object(
            audit_script,
            "semantic_references",
            side_effect=AssertionError("zero matches must fail before find-references"),
        ):
            _, outcomes = audit_script.collect_semantic_edges(
                Path("."),
                ("fixture_root",),
            )

        self.assertEqual(len(outcomes), 1)
        self.assertIsInstance(outcomes[0], UnresolvedCandidate)
        diagnostic = outcomes[0].diagnostic
        self.assertEqual(diagnostic.reason, "find_references_no_symbol_match")
        self.assertEqual(diagnostic.detail, "no compiler/runtime symbol-table identity matched executable fallback candidate")
        self.assertEqual(diagnostic.candidate.path, "compiler/fixture.mbt")
        self.assertEqual(diagnostic.candidate.line, 1)
        self.assertEqual(diagnostic.candidate.column, 25)
        self.assertEqual(diagnostic.candidate.enclosing, "fixture_root")
        self.assertEqual(diagnostic.candidate.spelling, "missing_call")
        self.assertEqual(diagnostic.candidate.resolver_phase, "find-references")

    def test_normal_line_in_dollar_function_uses_hover_without_shadowing_propagation(self) -> None:
        entry = {
            "kind": ["Sym", "fixture_root"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "fixture.mbt",
            "range": [1, 1, 2, 30],
            "name_range": [1, 1, 1, 12],
        }
        normal = Candidate(
            path="fixture.mbt",
            line=1,
            column=1,
            enclosing="fixture_root",
            spelling="shadowed",
            resolver_phase="hover",
            executable_hint=True,
        )
        dollar = Candidate(
            path="fixture.mbt",
            line=2,
            column=12,
            enclosing="fixture_root",
            spelling="shadowed",
            resolver_phase="hover",
            executable_hint=True,
        )
        hovered: list[Candidate] = []

        def fake_hover(
            _root: Path,
            candidate: Candidate,
            _symbols: dict[str, dict[str, object]],
            _symbols_by_name: dict[str, list[tuple[str, dict[str, object]]]],
        ) -> ResolvedRuntime:
            hovered.append(candidate)
            return ResolvedRuntime(candidate, "@runtime.shadowed")

        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.mbt").write_text("shadowed()\n$|shadowed()\n")
            with patch.object(
                audit_script,
                "load_symbols",
                return_value=({"fixture_root": entry}, {}),
            ), patch.object(
                audit_script,
                "candidate_locations",
                return_value=[normal, dollar],
            ), patch.object(
                audit_script,
                "contains_dollar_multiline",
                return_value=True,
            ), patch.object(
                audit_script,
                "resolve_hover",
                side_effect=fake_hover,
            ), patch.object(
                audit_script,
                "semantic_references",
                side_effect=AssertionError("zero-match fallback must not call find-references"),
            ):
                _, outcomes = audit_script.collect_semantic_edges(
                    root,
                    ("fixture_root",),
                )

        self.assertEqual(hovered, [normal])
        self.assertIsInstance(outcomes[0], ResolvedRuntime)
        self.assertIsInstance(outcomes[1], UnresolvedCandidate)
        self.assertEqual(
            outcomes[1].diagnostic.candidate.resolver_phase,
            "find-references",
        )

    def test_non_executable_normal_candidate_does_not_call_hover(self) -> None:
        entry = {
            "kind": ["Sym", "fixture_root"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "compiler/fixture.mbt",
            "range": [1, 1, 1, 30],
            "name_range": [1, 1, 1, 12],
        }
        non_executable = Candidate(
            path="compiler/fixture.mbt",
            line=1,
            column=20,
            enclosing="fixture_root",
            spelling="Return",
            resolver_phase="hover",
            executable_hint=False,
        )
        with patch.object(
            audit_script,
            "load_symbols",
            return_value=({"fixture_root": entry}, {}),
        ), patch.object(
            audit_script,
            "candidate_locations",
            return_value=[non_executable],
        ), patch.object(
            audit_script,
            "contains_dollar_multiline",
            return_value=False,
        ), patch.object(
            audit_script,
            "resolve_hover",
            side_effect=AssertionError("non-executable candidates must not call hover"),
        ):
            _, outcomes = audit_script.collect_semantic_edges(
                Path("."),
                ("fixture_root",),
            )

        self.assertEqual(
            outcomes,
            [IntentionallyIgnored(non_executable, "non_callable_reference")],
        )

    def test_update_with_root_override_rejects_before_index_and_preserves_baseline(self) -> None:
        baseline = Path("scripts/bytecode_vm_semantic_edges.json")
        before = baseline.read_bytes()
        self.assertEqual(
            update_root_override_error(True, ("custom_root",)),
            "--update cannot be combined with --root-symbol; use canonical roots",
        )
        with patch.object(
            audit_script,
            "ensure_semantic_index",
            side_effect=AssertionError("guard must run before semantic indexing"),
        ), patch.object(
            sys,
            "argv",
            ["audit_bytecode_vm_semantic_edges.py", "--update", "--root-symbol", "custom_root"],
        ):
            self.assertEqual(audit_script.main(), 2)
        self.assertEqual(baseline.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
