#!/usr/bin/env python3
"""Deterministic tests for the bytecode semantic-edge resolver boundary."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


SCRIPT_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_ROOT))

from audit_bytecode_vm_semantic_edges import (  # noqa: E402
    AmbiguousCandidate,
    Candidate,
    ResolvedCompiler,
    ResolvedOutOfScope,
    ResolvedRuntime,
    UnresolvedCandidate,
    classify_hover_identity,
    classify_hover_result,
    render_resolution_diagnostics,
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
            ("nonzero", 1, "", "index unavailable"),
            ("invalid_json", 0, "{", ""),
            ("missing_field", 0, json.dumps({"range": "1:1-1:2"}), ""),
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


if __name__ == "__main__":
    unittest.main()
