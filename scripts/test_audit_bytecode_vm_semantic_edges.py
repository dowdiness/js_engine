#!/usr/bin/env python3
"""Deterministic tests for the semantic resolver and lifecycle multigraph."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch


SCRIPT_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_ROOT))
import audit_bytecode_vm_semantic_edges as audit_script  # noqa: E402

from audit_bytecode_vm_semantic_edges import (  # noqa: E402
    AmbiguousCandidate,
    Candidate,
    IntentionallyIgnored,
    MigrationError,
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


def raw_edge(
    enclosing: str = "Root",
    path: str = "compiler/a.mbt",
    line: int = 10,
    column: int = 3,
    kind: str = "compiler",
    target: str = "Helper",
    reachable_from: list[str] | None = None,
) -> dict[str, object]:
    edge: dict[str, object] = {
        "enclosing": enclosing,
        "path": path,
        "line": line,
        "column": column,
        "kind": kind,
        "target": target,
    }
    if reachable_from is not None:
        edge["reachable_from"] = reachable_from
    return edge


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

        outcome = classify_hover_identity(candidate(), "shared", symbols, by_name)

        self.assertIsInstance(outcome, AmbiguousCandidate)
        self.assertEqual(outcome.candidates, ("Alpha::shared", "Beta::shared"))

    def test_unqualified_runtime_and_compiler_target_is_ambiguous(self) -> None:
        symbols = {"Compiler::shared": compiler_entry("Compiler::shared")}
        by_name = {
            "shared": [
                ("Compiler::shared", symbols["Compiler::shared"]),
                ("@runtime.shared", runtime_entry("shared")),
            ]
        }

        outcome = classify_hover_identity(candidate(), "shared", symbols, by_name)

        self.assertIsInstance(outcome, AmbiguousCandidate)
        self.assertEqual(
            outcome.candidates,
            ("@runtime.shared", "Compiler::shared"),
        )

    def test_resolved_runtime_and_external_targets_remain_distinct(self) -> None:
        symbols = {"Compiler::known": compiler_entry("Compiler::known")}
        by_name = {
            "known": [("Compiler::known", symbols["Compiler::known"])],
            "runtime_call": [("@runtime.runtime_call", runtime_entry("runtime_call"))],
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

    def test_hover_failures_keep_phase_and_detail(self) -> None:
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

    def test_value_hover_is_intentionally_ignored(self) -> None:
        outcome = classify_hover_result(
            candidate("BytecodeFrameSuspended"),
            returncode=0,
            stdout=json.dumps(
                {"contents": ["```moonbit\n(@runtime.Step) -> BytecodeFrameStep\n```"]}
            ),
            stderr="",
            command=("moon", "ide", "hover"),
            symbols={},
            symbols_by_name={},
        )

        self.assertEqual(
            outcome,
            IntentionallyIgnored(outcome.candidate, "non_callable_reference"),
        )

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
        self.assertLess(
            rendered.index("compiler/a.mbt:3:2"),
            rendered.index("compiler/fixture.mbt:12:9"),
        )

    def test_comments_raw_and_escaped_text_are_not_executable_candidates(self) -> None:
        with TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "fixture.mbt"
            path.write_text(
                "fn fixture_root() {\n"
                "  // target()\n"
                "  let escaped = \"escaped \\\\{target()}\"\n"
                "  let raw = #|raw \\{target()}\n"
                "  let ordinary = \"ordinary \\{target()}\"\n"
                "}\n"
            )
            entry = {
                "kind": ["Sym", "fixture_root"],
                "pkg": "dowdiness/js_engine/compiler",
                "path": "fixture.mbt",
                "range": [1, 1, 6, 2],
                "name_range": [1, 4, 1, 16],
            }

            candidates = audit_script.candidate_locations(root, entry, {"target"})

        executable = [
            item
            for item in candidates
            if isinstance(item, Candidate) and item.spelling == "target"
        ]
        ignored = [
            item
            for item in candidates
            if isinstance(item, IntentionallyIgnored)
            and item.candidate is not None
            and item.candidate.spelling == "target"
        ]
        self.assertEqual(len(executable), 1)
        self.assertEqual(executable[0].line, 5)
        self.assertGreaterEqual(len(ignored), 2)

    def test_dollar_fallback_without_symbol_match_is_unresolved(self) -> None:
        entry = {
            "kind": ["Sym", "fixture_root"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "fixture.mbt",
            "range": [1, 1, 1, 30],
            "name_range": [1, 4, 1, 16],
        }
        fallback = Candidate(
            path="fixture.mbt",
            line=1,
            column=25,
            enclosing="fixture_root",
            spelling="missing_call",
            resolver_phase="hover",
            executable_hint=True,
        )
        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.mbt").write_text("$|missing_call()\n")
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
                "_dollar_source_lines",
                return_value={1},
            ), patch.object(
                audit_script,
                "semantic_references",
                side_effect=AssertionError("zero matches must fail before find-references"),
            ):
                _, outcomes = audit_script.collect_semantic_edges(
                    root,
                    ("fixture_root",),
                )

        self.assertEqual(len(outcomes), 1)
        self.assertIsInstance(outcomes[0], UnresolvedCandidate)
        self.assertEqual(
            outcomes[0].diagnostic.reason,
            "find_references_no_symbol_match",
        )


class MultigraphTests(unittest.TestCase):
    roots = ("Root", "OtherRoot")

    def test_coordinate_comment_and_same_symbol_file_movement_are_stable(self) -> None:
        before = [raw_edge(reachable_from=["Root"])]
        after = [
            raw_edge(
                path="compiler/moved_same_symbol.mbt",
                line=99,
                column=41,
                reachable_from=["Root"],
            )
        ]

        self.assertEqual(
            audit_script.semantic_multigraph(before, ("Root",)),
            audit_script.semantic_multigraph(after, ("Root",)),
        )

    def test_edge_addition_and_removal_change_the_graph(self) -> None:
        one = [raw_edge()]
        two = one + [raw_edge(line=11, target="Another")]

        self.assertNotEqual(
            audit_script.semantic_multigraph(one, ("Root",)),
            audit_script.semantic_multigraph(two, ("Root",)),
        )

    def test_caller_kind_count_and_reachability_changes_change_graph(self) -> None:
        base = audit_script.semantic_multigraph(
            [raw_edge(reachable_from=["Root"])], self.roots
        )
        caller = audit_script.semantic_multigraph(
            [raw_edge(enclosing="Changed", reachable_from=["Root"])], self.roots
        )
        kind = audit_script.semantic_multigraph(
            [raw_edge(kind="runtime", reachable_from=["Root"])], self.roots
        )
        count = audit_script.semantic_multigraph(
            [
                raw_edge(line=10, reachable_from=["Root"]),
                raw_edge(line=11, reachable_from=["Root"]),
            ],
            self.roots,
        )
        roots = audit_script.semantic_multigraph(
            [raw_edge(reachable_from=["OtherRoot"])], self.roots
        )

        self.assertNotEqual(base, caller)
        self.assertNotEqual(base, kind)
        self.assertNotEqual(base, count)
        self.assertNotEqual(base, roots)

    def test_reachable_roots_are_sorted_and_union_across_callsite_sites(self) -> None:
        graph = audit_script.semantic_multigraph(
            [
                raw_edge(line=10, reachable_from=["OtherRoot"]),
                raw_edge(line=11, reachable_from=["Root"]),
            ],
            self.roots,
        )

        self.assertEqual(graph[0]["count"], 2)
        self.assertEqual(graph[0]["reachable_from"], ["OtherRoot", "Root"])

    def test_duplicate_live_callsite_is_counted_once(self) -> None:
        site = raw_edge(reachable_from=["Root"])
        duplicate = dict(site)
        duplicate["reachable_from"] = ["OtherRoot"]

        graph = audit_script.semantic_multigraph([site, duplicate], self.roots)

        self.assertEqual(graph[0]["count"], 1)
        self.assertEqual(graph[0]["reachable_from"], ["OtherRoot", "Root"])


class MigrationTests(unittest.TestCase):
    def test_v2_callsite_aggregation_is_complete_and_conserves_multiplicity(self) -> None:
        v2 = [
            raw_edge(line=10, reachable_from=["Root"]),
            raw_edge(line=11, reachable_from=["Root"]),
            raw_edge(
                line=12,
                kind="runtime",
                target="@runtime.call",
                reachable_from=["OtherRoot"],
            ),
        ]
        current = v2 + [
            raw_edge(
                line=13,
                kind="runtime",
                target="@runtime.new_call",
                reachable_from=["Root"],
            )
        ]

        roots = ("Root", "OtherRoot")
        graph, evidence = audit_script.migrate_v2_to_v3(v2, current, roots)

        self.assertEqual(evidence["v2_callsite_coverage"], 3)
        self.assertEqual(evidence["v2_aggregated_callsite_count"], 3)
        self.assertTrue(evidence["v2_multiplicity_conserved"])
        self.assertEqual(evidence["v3_callsite_count"], 4)
        self.assertEqual(evidence["v3_runtime_boundary_count"], 2)
        self.assertEqual(sum(edge["count"] for edge in graph), 4)

    def test_v2_callsite_missing_from_current_graph_fails_closed(self) -> None:
        with self.assertRaises(MigrationError):
            audit_script.migrate_v2_to_v3(
                [raw_edge()],
                [],
                ("Root",),
            )


class UpdateGuardTests(unittest.TestCase):
    def test_update_with_root_override_rejects_before_index_and_preserves_baseline(self) -> None:
        baseline = Path("scripts/bytecode_vm_semantic_edges.json")
        before = baseline.read_bytes()
        with patch.object(
            audit_script,
            "ensure_semantic_index",
            side_effect=AssertionError("guard must run before semantic indexing"),
        ), patch.object(
            sys,
            "argv",
            [
                "audit_bytecode_vm_semantic_edges.py",
                "--update",
                "--root-symbol",
                "custom_root",
            ],
        ):
            self.assertEqual(audit_script.main(), 2)
        self.assertEqual(baseline.read_bytes(), before)

    def test_rendered_v3_payload_is_deterministic(self) -> None:
        edges = [raw_edge(reachable_from=["Root"])]
        payload = {
            "version": 3,
            "roots": ["Root"],
            "edges": audit_script.semantic_multigraph(edges, ("Root",)),
        }

        self.assertEqual(
            audit_script.render_payload(payload), audit_script.render_payload(payload)
        )


if __name__ == "__main__":
    unittest.main()
