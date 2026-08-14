#!/usr/bin/env python3
"""Deterministic tests for the semantic resolver and lifecycle multigraph."""

from __future__ import annotations

from contextlib import nullcontext, redirect_stderr
import io
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


def candidate(
    spelling: str = "shared",
    *,
    call_syntax: bool = True,
) -> Candidate:
    return Candidate(
        path="compiler/fixture.mbt",
        line=12,
        column=9,
        enclosing="fixture_root",
        spelling=spelling,
        resolver_phase="hover",
        call_syntax=call_syntax,
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
            candidate("BytecodeFrameSuspended", call_syntax=False),
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

    def test_first_class_local_value_hover_is_intentionally_ignored(self) -> None:
        outcome = classify_hover_result(
            candidate("name", call_syntax=False),
            returncode=0,
            stdout=json.dumps({"contents": ["```moonbit\nString\n```"]}),
            stderr="",
            command=("moon", "ide", "hover"),
            symbols={},
            symbols_by_name={},
        )

        self.assertEqual(
            outcome,
            IntentionallyIgnored(outcome.candidate, "non_callable_reference"),
        )

    def test_optional_local_value_hover_is_intentionally_ignored(self) -> None:
        outcome = classify_hover_result(
            candidate("name", call_syntax=False),
            returncode=0,
            stdout=json.dumps({"contents": ["```moonbit\nString?\n```"]}),
            stderr="",
            command=("moon", "ide", "hover"),
            symbols={},
            symbols_by_name={},
        )

        self.assertEqual(
            outcome,
            IntentionallyIgnored(outcome.candidate, "non_callable_reference"),
        )

    def test_annotated_type_hover_is_intentionally_ignored(self) -> None:
        outcome = classify_hover_result(
            candidate("BytecodeFunction", call_syntax=False),
            returncode=0,
            stdout=json.dumps(
                {
                    "contents": [
                        '```moonbit\n#warnings("-unused_field")\n'
                        "struct BytecodeFunction {\n  name : String?\n}\n```"
                    ]
                }
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

    def test_arrow_callback_keeps_wrapper_and_downstream_runtime_edges(self) -> None:
        root_entry = {
            "kind": ["Sym", "root"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "root.mbt",
            "range": [1, 1, 1, 31],
            "name_range": [1, 4, 1, 8],
        }
        wrapper_entry = {
            "kind": ["Sym", "wrapper"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "wrapper.mbt",
            "range": [1, 1, 1, 100],
            "name_range": [1, 4, 1, 11],
        }
        symbols = {"root": root_entry, "wrapper": wrapper_entry}
        symbols_by_name = {
            "helper": [("wrapper", wrapper_entry)],
            "observe_execution_step": [
                ("@runtime.Interpreter::observe_execution_step", runtime_entry("observe_execution_step"))
            ],
        }
        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "root.mbt").write_text("fn root() { helper(x => x) }\n")
            (root / "wrapper.mbt").write_text(
                "fn wrapper(interp : Interpreter) { interp.observe_execution_step() }\n"
            )

            def fake_hover(
                _root: Path,
                candidate: Candidate,
                _symbols: dict[str, dict[str, object]],
                _symbols_by_name: dict[str, list[tuple[str, dict[str, object]]]],
            ) -> audit_script.ResolutionOutcome:
                if candidate.spelling == "helper":
                    return ResolvedCompiler(candidate, "wrapper")
                if candidate.spelling == "observe_execution_step":
                    return ResolvedRuntime(
                        candidate,
                        "@runtime.Interpreter::observe_execution_step",
                    )
                return IntentionallyIgnored(candidate, "test_non_callable")

            with patch.object(audit_script, "load_symbols", return_value=(symbols, symbols_by_name)), patch.object(
                audit_script, "resolve_hover", side_effect=fake_hover
            ):
                edges = audit_script.semantic_edges_from_roots(root, ("root",))

        observed = {
            (edge["enclosing"], edge["kind"], edge["target"])
            for edge in edges
        }
        self.assertIn(("root", "compiler", "wrapper"), observed)
        self.assertIn(
            ("wrapper", "runtime", "@runtime.Interpreter::observe_execution_step"),
            observed,
        )

    def test_forward_pipeline_candidates_reach_semantic_resolution(self) -> None:
        source = (
            "fn root() { interp |> helper; [] |> make_array; "
            "[] |> @runtime.make_array; value |> Type::method; "
            "value |> @runtime.SomeType::method; value |> Trait::method; "
            "let callback = Type::method; "
            "let callback2 = @runtime.SomeType::method; consume(Type::method); "
            "let pair = (Trait::method, value); return Type::method }\n"
        )
        root_entry = {
            "kind": ["Sym", "root"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "root.mbt",
            "range": [1, 1, 1, len(source)],
            "name_range": [1, 4, 1, 8],
        }
        wrapper_entry = {
            "kind": ["Sym", "wrapper"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "wrapper.mbt",
            "range": [1, 1, 1, 26],
            "name_range": [1, 4, 1, 11],
        }
        symbols = {"root": root_entry, "wrapper": wrapper_entry}
        symbols_by_name = {
            "helper": [("wrapper", wrapper_entry)],
            "make_array": [
                ("@runtime.make_array", runtime_entry("make_array"))
            ],
            "method": [("@runtime.Type::method", runtime_entry("method"))],
        }
        resolved_spellings: list[str] = []
        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "root.mbt").write_text(source)
            (root / "wrapper.mbt").write_text("fn wrapper() { () }\n")

            def fake_hover(
                _root: Path,
                candidate: Candidate,
                _symbols: dict[str, dict[str, object]],
                _symbols_by_name: dict[str, list[tuple[str, dict[str, object]]]],
            ) -> audit_script.ResolutionOutcome:
                spelling = candidate.spelling or ""
                resolved_spellings.append(spelling)
                if spelling == "helper":
                    return ResolvedCompiler(candidate, "wrapper")
                if spelling.endswith("make_array"):
                    return ResolvedRuntime(candidate, "@runtime.make_array")
                if spelling == "method":
                    return ResolvedRuntime(candidate, "@runtime.Type::method")
                return IntentionallyIgnored(candidate, "test_non_callable")

            with patch.object(
                audit_script,
                "load_symbols",
                return_value=(symbols, symbols_by_name),
            ), patch.object(audit_script, "resolve_hover", side_effect=fake_hover):
                edges = audit_script.semantic_edges_from_roots(root, ("root",))

        self.assertIn("helper", resolved_spellings)
        self.assertEqual(
            sum(spelling.endswith("make_array") for spelling in resolved_spellings),
            2,
        )
        self.assertEqual(resolved_spellings.count("method"), 8)
        self.assertIn(
            ("root", "compiler", "wrapper"),
            {
                (edge["enclosing"], edge["kind"], edge["target"])
                for edge in edges
            },
        )

    def test_implicit_result_callables_reach_semantic_resolution(self) -> None:
        sources = {
            "root_method": "fn root_method() {\n  Type::method\n}\n",
            "root_package_method": (
                "fn root_package_method() {\n  @runtime.SomeType::method\n}\n"
            ),
            "root_wrapper": (
                "fn root_wrapper() {\n  semantic_edge_audit_cross_file_wrapper\n}\n"
            ),
            "wrapper": "fn wrapper() { () }\n",
        }
        symbols = {
            name: {
                "kind": ["Sym", name],
                "pkg": "dowdiness/js_engine/compiler",
                "path": f"{name}.mbt",
                "range": [
                    1,
                    1,
                    len(source.splitlines()),
                    len(source.splitlines()[-1]) + 1,
                ],
                "name_range": [1, 4, 1, 4 + len(name)],
            }
            for name, source in sources.items()
        }
        symbols_by_name = {
            "method": [("@runtime.Type::method", runtime_entry("method"))],
            "semantic_edge_audit_cross_file_wrapper": [
                ("wrapper", symbols["wrapper"])
            ],
        }
        with TemporaryDirectory() as directory:
            root = Path(directory)
            for name, source in sources.items():
                (root / f"{name}.mbt").write_text(source)

            def fake_hover(
                _root: Path,
                candidate: Candidate,
                _symbols: dict[str, dict[str, object]],
                _symbols_by_name: dict[str, list[tuple[str, dict[str, object]]]],
            ) -> audit_script.ResolutionOutcome:
                if candidate.spelling == "method":
                    return ResolvedRuntime(candidate, "@runtime.Type::method")
                if candidate.spelling == "semantic_edge_audit_cross_file_wrapper":
                    return ResolvedCompiler(candidate, "wrapper")
                return IntentionallyIgnored(candidate, "test_non_callable")

            with patch.object(
                audit_script,
                "load_symbols",
                return_value=(symbols, symbols_by_name),
            ), patch.object(audit_script, "resolve_hover", side_effect=fake_hover):
                edges = audit_script.semantic_edges_from_roots(
                    root,
                    ("root_method", "root_package_method", "root_wrapper"),
                )

        observed = {
            (edge["enclosing"], edge["kind"], edge["target"])
            for edge in edges
        }
        self.assertIn(
            ("root_method", "runtime", "@runtime.Type::method"),
            observed,
        )
        self.assertIn(
            ("root_package_method", "runtime", "@runtime.Type::method"),
            observed,
        )
        self.assertIn(("root_wrapper", "compiler", "wrapper"), observed)


class CandidateScannerTests(unittest.TestCase):
    def test_moon_ide_callable_tags_exclude_type_field_and_variant_tags(self) -> None:
        for tag in ("0x1000", "0x1001", "0x4000", "0x4001"):
            with self.subTest(tag=tag):
                self.assertTrue(audit_script._symbol_entry_is_callable({"tag": tag}))
        for tag in ("0x10", "0x53", "0xd3", "0xd8"):
            with self.subTest(tag=tag):
                self.assertFalse(audit_script._symbol_entry_is_callable({"tag": tag}))

    def candidates_for(
        self,
        source: str,
        known_names: set[str],
    ) -> list[Candidate | IntentionallyIgnored]:
        with TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "fixture.mbt"
            path.write_text(source)
            lines = source.splitlines()
            entry = {
                "kind": ["Sym", "root"],
                "pkg": "dowdiness/js_engine/compiler",
                "path": "fixture.mbt",
                "range": [1, 1, len(lines), len(lines[-1]) + 1],
                "name_range": [1, 4, 1, 8],
            }
            return audit_script.candidate_locations(root, entry, known_names)

    def executable_spellings(
        self,
        source: str,
        known_names: set[str],
    ) -> list[str]:
        return [
            outcome.spelling or ""
            for outcome in self.candidates_for(source, known_names)
            if isinstance(outcome, Candidate) and outcome.executable_hint
        ]

    def test_same_line_calls_after_quoted_interpolation_remain_executable(self) -> None:
        source = (
            'fn root() { let pair = ("first \\{interp.observe_execution_step()} '
            '\\{interp.observe_execution_step()}", @runtime.make_array([])); '
            "semantic_edge_audit_cross_file_wrapper(interp) }\n"
        )

        spellings = self.executable_spellings(
            source,
            {
                "observe_execution_step",
                "make_array",
                "semantic_edge_audit_cross_file_wrapper",
            },
        )

        self.assertIn("@runtime.make_array", spellings)
        self.assertIn("semantic_edge_audit_cross_file_wrapper", spellings)

    def test_escaped_interpolation_and_raw_text_remain_ignored(self) -> None:
        escaped = self.executable_spellings(
            'fn root() { let text = "escaped \\\\{@runtime.make_array([])}" }\n',
            {"make_array"},
        )
        raw = self.executable_spellings(
            'fn root() { let text = #|raw \\{@runtime.make_array([])}\n }\n',
            {"make_array"},
        )

        self.assertEqual(escaped, [])
        self.assertEqual(raw, [])

    def test_first_class_references_before_arrow_expression_remain_executable(self) -> None:
        source = (
            "fn root() { let pair = (@runtime.make_array, "
            "semantic_edge_audit_cross_file_wrapper, (x : Int) => x) }\n"
        )

        spellings = self.executable_spellings(
            source,
            {"make_array", "semantic_edge_audit_cross_file_wrapper"},
        )

        self.assertIn("make_array", spellings)
        self.assertIn("semantic_edge_audit_cross_file_wrapper", spellings)

    def test_reverse_pipeline_references_remain_executable(self) -> None:
        source = (
            "fn root() { semantic_edge_audit_cross_file_wrapper <| interp; "
            "make_array <| [] }\n"
        )

        spellings = self.executable_spellings(
            source,
            {"semantic_edge_audit_cross_file_wrapper", "make_array"},
        )

        self.assertIn("semantic_edge_audit_cross_file_wrapper", spellings)
        self.assertIn("make_array", spellings)

    def test_forward_pipeline_references_remain_executable_calls(self) -> None:
        source = (
            "fn root() { interp |> semantic_edge_audit_cross_file_wrapper; "
            "[] |> make_array; [] |> @runtime.make_array }\n"
        )

        candidates = [
            outcome
            for outcome in self.candidates_for(
                source,
                {"semantic_edge_audit_cross_file_wrapper", "make_array"},
            )
            if isinstance(outcome, Candidate)
            and outcome.spelling
            in {"semantic_edge_audit_cross_file_wrapper", "make_array"}
        ]

        self.assertEqual(len(candidates), 3)
        self.assertTrue(all(candidate.executable_hint for candidate in candidates))
        self.assertTrue(all(candidate.call_syntax for candidate in candidates))

    def test_method_qualified_pipeline_references_remain_executable_calls(self) -> None:
        source = (
            "fn root() { value |> Type::method; "
            "value |> @runtime.SomeType::method; value |> Trait::method; "
            "Type::method(extra_arg); Type::method <| value }\n"
        )

        candidates = [
            outcome
            for outcome in self.candidates_for(source, {"method"})
            if isinstance(outcome, Candidate) and outcome.spelling == "method"
        ]

        self.assertEqual(len(candidates), 5)
        self.assertTrue(all(candidate.executable_hint for candidate in candidates))
        self.assertTrue(all(candidate.call_syntax for candidate in candidates))

    def test_method_qualified_first_class_references_remain_executable(self) -> None:
        source = (
            "fn root() { let callback = Type::method; "
            "let callback2 = @runtime.SomeType::method; consume(Type::method); "
            "let pair = (Trait::method, value); return Type::method }\n"
        )

        candidates = [
            outcome
            for outcome in self.candidates_for(source, {"method"})
            if isinstance(outcome, Candidate) and outcome.spelling == "method"
        ]

        self.assertEqual(len(candidates), 5)
        self.assertTrue(all(candidate.executable_hint for candidate in candidates))
        self.assertTrue(all(not candidate.call_syntax for candidate in candidates))

    def test_implicit_result_callable_references_remain_executable(self) -> None:
        sources = (
            "fn root() {\n  Type::method\n}\n",
            "fn root() {\n  @runtime.SomeType::method\n}\n",
            "fn root() {\n  semantic_edge_audit_cross_file_wrapper\n}\n",
        )

        candidates = [
            outcome
            for source in sources
            for outcome in self.candidates_for(
                source,
                {"method", "semantic_edge_audit_cross_file_wrapper"},
            )
            if isinstance(outcome, Candidate)
            and outcome.spelling
            in {"method", "semantic_edge_audit_cross_file_wrapper"}
        ]

        self.assertEqual(len(candidates), 3)
        self.assertTrue(all(candidate.executable_hint for candidate in candidates))
        self.assertTrue(all(not candidate.call_syntax for candidate in candidates))

    def test_known_callable_match_result_reaches_resolution(self) -> None:
        source = "fn root(value) { match value { _ => Type::method } }\n"

        candidates = [
            outcome
            for outcome in self.candidates_for(source, {"method"})
            if isinstance(outcome, Candidate) and outcome.spelling == "method"
        ]

        self.assertEqual(len(candidates), 1)
        self.assertTrue(candidates[0].executable_hint)
        self.assertFalse(candidates[0].call_syntax)

    def test_method_declaration_name_range_remains_excluded(self) -> None:
        source = "fn Type::method() { return Type::method }\n"
        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.mbt").write_text(source)
            entry = {
                "kind": ["Sym", "Type::method"],
                "pkg": "dowdiness/js_engine/compiler",
                "path": "fixture.mbt",
                "range": [1, 1, 1, len(source)],
                "name_range": [1, 10, 1, 16],
            }

            outcomes = audit_script.candidate_locations(root, entry, {"method"})

        methods = [
            outcome
            for outcome in outcomes
            if isinstance(outcome, Candidate) and outcome.spelling == "method"
        ]
        self.assertEqual(len(methods), 1)
        self.assertTrue(methods[0].executable_hint)

    def test_known_named_argument_values_reach_resolution(self) -> None:
        source = (
            "fn root() { consume(source_text=func_def.source_text, "
            "rest_param=func_def.rest_param) }\n"
        )

        candidates = [
            outcome
            for outcome in self.candidates_for(
                source,
                {"source_text", "rest_param"},
            )
            if isinstance(outcome, Candidate)
            and outcome.spelling in {"source_text", "rest_param"}
        ]

        self.assertEqual(len(candidates), 4)
        self.assertTrue(all(candidate.executable_hint for candidate in candidates))

    def test_token_local_binders_remain_non_executable(self) -> None:
        source = (
            "fn root() { let semantic_edge_audit_cross_file_wrapper = "
            "(make_array : Int) => make_array }\n"
        )

        outcomes = self.candidates_for(
            source,
            {"semantic_edge_audit_cross_file_wrapper", "make_array"},
        )
        candidates = [
            outcome for outcome in outcomes if isinstance(outcome, Candidate)
        ]

        self.assertFalse(candidates[0].executable_hint)
        self.assertFalse(candidates[1].executable_hint)


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
        baseline = SCRIPT_ROOT / "bytecode_vm_semantic_edges.json"
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

    def test_self_test_resolution_failure_uses_deterministic_diagnostic(self) -> None:
        error = audit_script.SemanticResolutionError(
            [
                audit_script.ResolutionDiagnostic(
                    candidate("lost"),
                    "moon_ide_nonzero",
                    detail="fixture index unavailable",
                )
            ]
        )
        stderr = io.StringIO()
        with patch.object(audit_script, "ensure_semantic_index"), patch.object(
            audit_script, "semantic_edges_from_roots", return_value=[]
        ), patch.object(
            audit_script, "semantic_fixture_sources", return_value=nullcontext()
        ), patch.object(
            audit_script, "semantic_edges", side_effect=error
        ), patch.object(
            sys,
            "argv",
            ["audit_bytecode_vm_semantic_edges.py", "--self-test"],
        ), redirect_stderr(stderr):
            self.assertEqual(audit_script.main(), 1)

        rendered = stderr.getvalue()
        self.assertIn("unresolved=1 ambiguous=0", rendered)
        self.assertNotIn("Traceback", rendered)

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
