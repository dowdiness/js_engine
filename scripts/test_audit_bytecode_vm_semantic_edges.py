#!/usr/bin/env python3
"""Deterministic tests for the semantic resolver and lifecycle multigraph."""

from __future__ import annotations

from contextlib import nullcontext, redirect_stderr
import io
import json
import sys
from types import SimpleNamespace
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch


SCRIPT_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_ROOT))
import audit_bytecode_vm_semantic_edges as audit_script  # noqa: E402

from audit_bytecode_vm_semantic_edges import (  # noqa: E402
    AmbiguousCandidate,
    CallableValue,
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


EMPTY_VALUE_DEFINITIONS = audit_script.ValueDefinitions(frozenset(), ())


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


def semantic_fixture(
    source: str,
    entries: list[dict[str, object]],
    *,
    function_type_locations: set[str] = set(),
    hover_identities: dict[str, str] | None = None,
    peek_payload: list[dict[str, str]] | None = None,
) -> tuple[list[dict[str, object]], list[object]]:
    hover_identities = hover_identities or {}
    if peek_payload is None:
        peek_payload = [{"path": "fixture.mbt", "range": "2:3-2:4"}]
    with TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "fixture.mbt").write_text(source)
        symbol_jsonl = "\n".join(json.dumps(entry) for entry in entries) + "\n"

        def fake_run(
            _root: Path,
            *args: str,
            check: bool = True,
        ) -> object:
            del check
            command = args[2]
            if command == "gen-symbols":
                (root / "symbols.jsonl").write_text(symbol_jsonl)
                return SimpleNamespace(returncode=0, stdout="", stderr="")
            location = args[args.index("--loc") + 1]
            if command == "hover":
                identity = hover_identities.get(location)
                if identity is not None:
                    contents = [f"```moonbit\nfn {identity}\n```"]
                elif location in function_type_locations:
                    contents = ["```moonbit\n() -> Value\n```"]
                else:
                    contents = ["```moonbit\nValue\n```"]
                return SimpleNamespace(
                    returncode=0,
                    stdout=json.dumps({"contents": contents}),
                    stderr="",
                )
            if command == "peek-def":
                return SimpleNamespace(
                    returncode=0,
                    stdout=json.dumps(peek_payload),
                    stderr="",
                )
            raise AssertionError(f"unexpected IDE command: {args}")

        with patch.object(audit_script, "run", side_effect=fake_run):
            return audit_script.collect_semantic_edges(root, ("root",))


class ResolverOutcomeTests(unittest.TestCase):
    def test_immutable_callable_alias_resolves_at_its_callsite(self) -> None:
        sources = (
            (
                "fn root() {\n"
                "  let complete = @runtime.make_array\n"
                "  complete([])\n"
                "}\n"
            ),
            (
                "fn root() {\n"
                "  let complete = @runtime.make_array // trailing note\n"
                "  complete([])\n"
                "}\n"
            ),
            (
                "fn root() {\n"
                "  let complete = // line note\n"
                "    @runtime.make_array\n"
                "  complete([])\n"
                "}\n"
            ),
        )
        root_entry = {
            "kind": ["Sym", "root"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "fixture.mbt",
            "range": [1, 1, 4, 2],
            "name_range": [1, 4, 1, 8],
        }
        runtime_make_array = runtime_entry("make_array")
        runtime_complete = runtime_entry("RuntimeThing::complete")

        for source in sources:
            root_entry["range"] = [1, 1, len(source.splitlines()), 2]
            call_line = source.count("\n", 0, source.index("complete([])")) + 1
            rhs_line = source.count("\n", 0, source.index("@runtime.make_array")) + 1
            for collision in (False, True):
                with self.subTest(source=source, collision=collision), TemporaryDirectory() as directory:
                    root = Path(directory)
                    (root / "fixture.mbt").write_text(source)
                    symbols_by_name = {
                        "make_array": [
                            ("@runtime.make_array", runtime_make_array),
                        ],
                    }
                    if collision:
                        symbols_by_name["complete"] = [
                            ("@runtime.RuntimeThing::complete", runtime_complete),
                        ]

                    def fake_run(
                        _root: Path,
                        *args: str,
                        check: bool = True,
                    ) -> object:
                        del check
                        command = args[2]
                        location = args[args.index("--loc") + 1]
                        if command == "hover":
                            line = int(location.rsplit(":", 1)[0].rsplit(":", 1)[1])
                            contents = (
                                ["```moonbit\nfn @runtime.make_array\n```"]
                                if line == rhs_line
                                else [
                                    "```moonbit\n"
                                    "(Array[@runtime.Value]) -> @runtime.Value\n"
                                    "```"
                                ]
                            )
                            return SimpleNamespace(
                                returncode=0,
                                stdout=json.dumps({"contents": contents}),
                                stderr="",
                            )
                        if command == "peek-def":
                            return SimpleNamespace(
                                returncode=0,
                                stdout=json.dumps(
                                    [
                                        {
                                            "path": str(root / "fixture.mbt"),
                                            "range": "2:7-2:15",
                                        }
                                    ]
                                ),
                                stderr="",
                            )
                        raise AssertionError(f"unexpected IDE command: {args}")

                    with patch.object(
                        audit_script,
                        "load_symbols",
                        return_value=(
                            {"root": root_entry},
                            symbols_by_name,
                            EMPTY_VALUE_DEFINITIONS,
                        ),
                    ), patch.object(audit_script, "run", side_effect=fake_run):
                        edges = audit_script.semantic_edges_from_roots(root, ("root",))

                    self.assertIn(
                        (
                            "root",
                            "runtime",
                            "@dowdiness/js_engine/interpreter/runtime.make_array",
                        ),
                        {
                            (edge["enclosing"], edge["kind"], edge["target"])
                            for edge in edges
                            if edge["line"] == call_line and edge["column"] == 3
                        },
                    )

    def test_alias_chain_preserves_the_original_callsite(self) -> None:
        source = (
            "fn root() {\n"
            "  let first = @runtime.make_array\n"
            "  let second = first\n"
            "  second([])\n"
            "}\n"
        )
        root_entry = {
            "kind": ["Sym", "root"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "fixture.mbt",
            "range": [1, 1, 5, 2],
            "name_range": [1, 4, 1, 8],
        }
        by_name = {"make_array": [("@runtime.make_array", runtime_entry("make_array"))]}

        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.mbt").write_text(source)

            def fake_run(_root: Path, *args: str, check: bool = True) -> object:
                del check
                command = args[2]
                location = args[args.index("--loc") + 1]
                line = int(location.rsplit(":", 1)[0].rsplit(":", 1)[1])
                if command == "hover":
                    if line == 2:
                        contents = ["```moonbit\nfn @runtime.make_array\n```"]
                    elif line in (3, 4):
                        contents = ["```moonbit\n(Array) -> Value\n```"]
                    else:
                        raise AssertionError(f"unexpected hover line: {line}")
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps({"contents": contents}),
                        stderr="",
                    )
                if command == "peek-def":
                    definition = {
                        4: "3:7-3:13",
                        3: "2:7-2:12",
                    }[line]
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps(
                            [{"path": str(root / "fixture.mbt"), "range": definition}]
                        ),
                        stderr="",
                    )
                raise AssertionError(args)

            with patch.object(
                audit_script,
                "load_symbols",
                return_value=(
                    {"root": root_entry},
                    by_name,
                    EMPTY_VALUE_DEFINITIONS,
                ),
            ), patch.object(audit_script, "run", side_effect=fake_run):
                edges = audit_script.semantic_edges_from_roots(root, ("root",))

        self.assertIn(
            (
                "root",
                "runtime",
                "@dowdiness/js_engine/interpreter/runtime.make_array",
            ),
            {
                (edge["enclosing"], edge["kind"], edge["target"])
                for edge in edges
                if edge["line"] == 4 and edge["column"] == 3
            },
        )

    def test_alias_to_compiler_wrapper_keeps_downstream_runtime_edge(self) -> None:
        source = (
            "fn root() {\n"
            "  let wrapper = helper\n"
            "  wrapper([])\n"
            "}\n"
            "fn helper() {\n"
            "  @runtime.make_array([])\n"
            "}\n"
        )
        root_entry = {
            "kind": ["Sym", "root"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "fixture.mbt",
            "range": [1, 1, 4, 2],
            "name_range": [1, 4, 1, 8],
        }
        helper_entry = {
            "kind": ["Sym", "helper"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "fixture.mbt",
            "range": [5, 1, 7, 2],
            "name_range": [5, 4, 5, 10],
        }
        by_name = {
            "helper": [("helper", helper_entry)],
            "make_array": [("@runtime.make_array", runtime_entry("make_array"))],
        }

        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.mbt").write_text(source)

            def fake_run(_root: Path, *args: str, check: bool = True) -> object:
                del check
                command = args[2]
                location = args[args.index("--loc") + 1]
                line = int(location.rsplit(":", 1)[0].rsplit(":", 1)[1])
                if command == "hover":
                    if line == 2:
                        contents = ["```moonbit\nfn helper\n```"]
                    elif line == 3:
                        contents = ["```moonbit\n(Array) -> Value\n```"]
                    elif line == 6:
                        contents = ["```moonbit\nfn @runtime.make_array\n```"]
                    else:
                        raise AssertionError(f"unexpected hover line: {line}")
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps({"contents": contents}),
                        stderr="",
                    )
                if command == "peek-def":
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps(
                            [{"path": str(root / "fixture.mbt"), "range": "2:7-2:14"}]
                        ),
                        stderr="",
                    )
                raise AssertionError(args)

            with patch.object(
                audit_script,
                "load_symbols",
                return_value=(
                    {"root": root_entry, "helper": helper_entry},
                    by_name,
                    EMPTY_VALUE_DEFINITIONS,
                ),
            ), patch.object(audit_script, "run", side_effect=fake_run):
                edges = audit_script.semantic_edges_from_roots(root, ("root",))

        observed = {
            (edge["enclosing"], edge["kind"], edge["target"])
            for edge in edges
        }
        self.assertIn(("root", "compiler", "helper"), observed)
        self.assertIn(
            ("helper", "runtime", "@dowdiness/js_engine/interpreter/runtime.make_array"),
            observed,
        )

    def test_lexical_shadowing_uses_the_definition_coordinate(self) -> None:
        source = (
            "fn root() {\n"
            "  let complete = @runtime.make_array\n"
            "  {\n"
            "    let complete = complete\n"
            "    complete([])\n"
            "  }\n"
            "}\n"
        )
        root_entry = {
            "kind": ["Sym", "root"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "fixture.mbt",
            "range": [1, 1, 7, 2],
            "name_range": [1, 4, 1, 8],
        }
        by_name = {
            "make_array": [("@runtime.make_array", runtime_entry("make_array"))],
        }

        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.mbt").write_text(source)
            peek_locations: list[str] = []

            def fake_run(_root: Path, *args: str, check: bool = True) -> object:
                del check
                command = args[2]
                location = args[args.index("--loc") + 1]
                line = int(location.rsplit(":", 1)[0].rsplit(":", 1)[1])
                if command == "hover":
                    if line == 2:
                        identity = "@runtime.make_array"
                        contents = [f"```moonbit\nfn {identity}\n```"]
                    elif line in (4, 5):
                        contents = ["```moonbit\n(Array) -> Value\n```"]
                    else:
                        raise AssertionError(f"unexpected hover line: {line}")
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps({"contents": contents}),
                        stderr="",
                    )
                if command == "peek-def":
                    location = args[args.index("--loc") + 1]
                    peek_locations.append(location)
                    definitions = {
                        "fixture.mbt:5:5": "4:9-4:17",
                        "fixture.mbt:4:20": "2:7-2:15",
                    }
                    if location not in definitions:
                        raise AssertionError(f"unexpected peek location: {location}")
                    definition = definitions[location]
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps(
                            [{"path": str(root / "fixture.mbt"), "range": definition}]
                        ),
                        stderr="",
                    )
                raise AssertionError(args)

            with patch.object(
                audit_script,
                "load_symbols",
                return_value=(
                    {"root": root_entry},
                    by_name,
                    EMPTY_VALUE_DEFINITIONS,
                ),
            ), patch.object(audit_script, "run", side_effect=fake_run):
                edges = audit_script.semantic_edges_from_roots(root, ("root",))

        self.assertEqual(
            peek_locations,
            ["fixture.mbt:5:5", "fixture.mbt:4:20"],
        )
        self.assertIn(
            (
                "root",
                "runtime",
                "@dowdiness/js_engine/interpreter/runtime.make_array",
            ),
            {
                (edge["enclosing"], edge["kind"], edge["target"])
                for edge in edges
                if edge["line"] == 5 and edge["column"] == 5
            },
        )

    def test_dynamic_mutable_callable_is_ignored_after_binding_confirmation(self) -> None:
        source = (
            "fn root() {\n"
            "  let mut callback = @runtime.make_array\n"
            "  callback([])\n"
            "}\n"
        )
        root_entry = {
            "kind": ["Sym", "root"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "fixture.mbt",
            "range": [1, 1, 4, 2],
            "name_range": [1, 4, 1, 8],
        }
        by_name = {"make_array": [("@runtime.make_array", runtime_entry("make_array"))]}

        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.mbt").write_text(source)

            def fake_run(_root: Path, *args: str, check: bool = True) -> object:
                del check
                command = args[2]
                location = args[args.index("--loc") + 1]
                line = int(location.rsplit(":", 1)[0].rsplit(":", 1)[1])
                if command == "hover":
                    contents = (
                        ["```moonbit\nfn @runtime.make_array\n```"]
                        if line == 2
                        else ["```moonbit\n(Array) -> Value\n```"]
                    )
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps({"contents": contents}),
                        stderr="",
                    )
                if command == "peek-def":
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps(
                            [{"path": str(root / "fixture.mbt"), "range": "2:11-2:19"}]
                        ),
                        stderr="",
                    )
                raise AssertionError(args)

            with patch.object(
                audit_script,
                "load_symbols",
                return_value=(
                    {"root": root_entry},
                    by_name,
                    EMPTY_VALUE_DEFINITIONS,
                ),
            ), patch.object(audit_script, "run", side_effect=fake_run):
                edges, outcomes = audit_script.collect_semantic_edges(root, ("root",))

        self.assertFalse(
            [edge for edge in edges if edge["line"] == 3 and edge["column"] == 3]
        )
        self.assertIn(
            IntentionallyIgnored(
                next(
                    outcome.candidate
                    for outcome in outcomes
                    if isinstance(outcome, IntentionallyIgnored)
                    and outcome.reason == "indirect_callable_reference"
                ),
                "indirect_callable_reference",
            ),
            outcomes,
        )

    def test_callable_parameter_is_ignored_after_binding_confirmation(self) -> None:
        source = (
            "fn root(callback : (Array) -> Value) {\n"
            "  callback([])\n"
            "}\n"
        )
        root_entry = {
            "kind": ["Sym", "root"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "fixture.mbt",
            "range": [1, 1, 3, 2],
            "name_range": [1, 4, 1, 8],
        }

        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.mbt").write_text(source)

            def fake_run(_root: Path, *args: str, check: bool = True) -> object:
                del check
                if args[2] == "hover":
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps(
                            {"contents": ["```moonbit\n(Array) -> Value\n```"]}
                        ),
                        stderr="",
                    )
                return SimpleNamespace(
                    returncode=0,
                    stdout=json.dumps(
                        [{"path": str(root / "fixture.mbt"), "range": "1:9-1:17"}]
                    ),
                    stderr="",
                )

            with patch.object(
                audit_script,
                "load_symbols",
                return_value=({"root": root_entry}, {}, EMPTY_VALUE_DEFINITIONS),
            ), patch.object(audit_script, "run", side_effect=fake_run):
                edges, outcomes = audit_script.collect_semantic_edges(root, ("root",))

        self.assertFalse(edges)
        self.assertEqual(
            [
                outcome.reason
                for outcome in outcomes
                if isinstance(outcome, IntentionallyIgnored)
            ],
            ["indirect_callable_reference"],
        )

    def test_alias_cycle_is_a_fail_closed_diagnostic(self) -> None:
        source = (
            "fn root() {\n"
            "  let first = second\n"
            "  let second = first\n"
            "  first([])\n"
            "}\n"
        )
        root_entry = {
            "kind": ["Sym", "root"],
            "pkg": "dowdiness/js_engine/compiler",
            "path": "fixture.mbt",
            "range": [1, 1, 5, 2],
            "name_range": [1, 4, 1, 8],
        }

        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.mbt").write_text(source)

            def fake_run(_root: Path, *args: str, check: bool = True) -> object:
                del check
                command = args[2]
                location = args[args.index("--loc") + 1]
                line = int(location.rsplit(":", 1)[0].rsplit(":", 1)[1])
                if command == "hover":
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps(
                            {"contents": ["```moonbit\n(Array) -> Value\n```"]}
                        ),
                        stderr="",
                    )
                if command == "peek-def":
                    definition = {
                        4: "2:7-2:12",
                        2: "3:7-3:13",
                        3: "2:7-2:12",
                    }[line]
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps(
                            [{"path": str(root / "fixture.mbt"), "range": definition}]
                        ),
                        stderr="",
                    )
                raise AssertionError(args)

            with patch.object(
                audit_script,
                "load_symbols",
                return_value=({"root": root_entry}, {}, EMPTY_VALUE_DEFINITIONS),
            ), patch.object(audit_script, "run", side_effect=fake_run):
                with self.assertRaises(audit_script.SemanticResolutionError) as raised:
                    audit_script.semantic_edges_from_roots(root, ("root",))

        self.assertEqual(raised.exception.diagnostics[0].reason, "alias_cycle")

    def test_peek_def_provider_failures_remain_structured(self) -> None:
        candidate_value = candidate("alias")
        cases = {
            "nonzero": (1, "", "unavailable", "moon_ide_nonzero"),
            "invalid_json": (0, "{", "", "invalid_json"),
            "missing_json_field": (0, json.dumps({"path": "fixture.mbt"}), "", "missing_json_field"),
            "invalid_source_location": (
                0,
                json.dumps([{"path": "fixture.mbt", "range": "bad"}]),
                "",
                "invalid_source_location",
            ),
        }
        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.mbt").write_text("fn root() { alias([]) }\n")
            for name, (returncode, stdout, stderr, reason) in cases.items():
                with self.subTest(name=name):
                    def fake_run(_root: Path, *args: str, check: bool = True) -> object:
                        del check
                        if args[2] == "hover":
                            return SimpleNamespace(
                                returncode=0,
                                stdout=json.dumps(
                                    {"contents": ["```moonbit\n(Array) -> Value\n```"]}
                                ),
                                stderr="",
                            )
                        return SimpleNamespace(
                            returncode=returncode,
                            stdout=stdout,
                            stderr=stderr,
                        )

                    with patch.object(audit_script, "run", side_effect=fake_run):
                        outcome = audit_script.resolve_hover(
                            root,
                            candidate_value,
                            {},
                            {},
                        )
                    self.assertIsInstance(outcome, UnresolvedCandidate)
                    self.assertEqual(outcome.diagnostic.reason, reason)
                    self.assertEqual(outcome.diagnostic.candidate.line, candidate_value.line)
                    self.assertEqual(
                        outcome.diagnostic.candidate.resolver_phase,
                        "peek-def",
                    )

    def test_peek_def_ambiguity_is_structured(self) -> None:
        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.mbt").write_text("fn root() { alias([]) }\n")

            def fake_run(_root: Path, *args: str, check: bool = True) -> object:
                del check
                if args[2] == "hover":
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps(
                            {"contents": ["```moonbit\n(Array) -> Value\n```"]}
                        ),
                        stderr="",
                    )
                return SimpleNamespace(
                    returncode=0,
                    stdout=json.dumps(
                        [
                            {"path": str(root / "fixture.mbt"), "range": "1:4-1:8"},
                            {"path": str(root / "fixture.mbt"), "range": "1:10-1:15"},
                        ]
                    ),
                    stderr="",
                )

            with patch.object(audit_script, "run", side_effect=fake_run):
                outcome = audit_script.resolve_hover(root, candidate("alias"), {}, {})

        self.assertIsInstance(outcome, AmbiguousCandidate)
        self.assertEqual(outcome.diagnostic.reason, "peek_def_ambiguous_definition")

    def test_rhs_hover_failure_keeps_hover_phase_at_original_callsite(self) -> None:
        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.mbt").write_text(
                "fn root() {\n"
                "  let alias = @runtime.make_array\n"
                "  alias([])\n"
                "}\n"
            )
            root_entry = {
                "kind": ["Sym", "root"],
                "pkg": "dowdiness/js_engine/compiler",
                "path": "fixture.mbt",
                "range": [1, 1, 4, 2],
                "name_range": [1, 4, 1, 8],
            }
            by_name = {
                "make_array": [("@runtime.make_array", runtime_entry("make_array"))]
            }

            def fake_run(_root: Path, *args: str, check: bool = True) -> object:
                del check
                location = args[args.index("--loc") + 1]
                line = int(location.rsplit(":", 1)[0].rsplit(":", 1)[1])
                if args[2] == "hover" and line == 3:
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps(
                            {"contents": ["```moonbit\n(Array) -> Value\n```"]}
                        ),
                        stderr="",
                    )
                if args[2] == "peek-def":
                    return SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps(
                            [{"path": str(root / "fixture.mbt"), "range": "2:7-2:12"}]
                        ),
                        stderr="",
                    )
                return SimpleNamespace(
                    returncode=1,
                    stdout="",
                    stderr="rhs hover unavailable",
                )

            with patch.object(audit_script, "run", side_effect=fake_run):
                outcome = audit_script.resolve_hover(
                    root,
                    Candidate(
                        path="fixture.mbt",
                        line=3,
                        column=3,
                        enclosing="root",
                        spelling="alias",
                        resolver_phase="hover",
                    ),
                    {"root": root_entry},
                    by_name,
                )

        self.assertIsInstance(outcome, UnresolvedCandidate)
        self.assertEqual(outcome.diagnostic.reason, "moon_ide_nonzero")
        self.assertEqual(outcome.diagnostic.candidate.line, 3)
        self.assertEqual(outcome.diagnostic.candidate.resolver_phase, "hover")

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

    def test_function_type_hover_is_deferred_for_binding_resolution(self) -> None:
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

        self.assertIsInstance(outcome, CallableValue)
        self.assertEqual(outcome.candidate, candidate("BytecodeFrameSuspended", call_syntax=False))

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
                return_value=(
                    {"fixture_root": entry},
                    {},
                    EMPTY_VALUE_DEFINITIONS,
                ),
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


class ConstructorResolutionTests(unittest.TestCase):
    @staticmethod
    def callable_root(
        *,
        start_line: int,
        end_line: int,
        name: str = "root",
    ) -> dict[str, object]:
        return {
            "kind": ["Sym", name],
            "pkg": "dowdiness/js_engine/compiler",
            "tag": "0x1001",
            "path": "fixture.mbt",
            "range": [start_line, 1, end_line, 2],
            "name_range": [start_line, 4, start_line, 4 + len(name)],
        }

    def test_enum_constructor_is_ignored_from_loaded_value_metadata(self) -> None:
        source = (
            "enum Weird {\n"
            "  ConstructorLike(Int)\n"
            "}\n"
            "fn root() {\n"
            "  ConstructorLike(1)\n"
            "}\n"
        )
        root = self.callable_root(start_line=4, end_line=6)
        variant = {
            "kind": ["SymChild", "Weird", "ConstructorLike"],
            "pkg": "fixture/types",
            "tag": "0xd3",
            "path": "fixture.mbt",
            "range": [2, 3, 2, 18],
            "name_range": [2, 3, 2, 18],
        }
        edges, outcomes = semantic_fixture(
            source,
            [root, variant],
            function_type_locations={"fixture.mbt:5:3"},
            peek_payload=[
                {"path": "fixture.mbt", "range": "2:3-2:18"}
            ],
        )

        self.assertEqual(edges, [])
        self.assertEqual(
            [
                (type(outcome), outcome.reason)
                for outcome in outcomes
                if isinstance(outcome, IntentionallyIgnored)
            ],
            [(IntentionallyIgnored, "non_callable_reference")],
        )

    def test_unknown_symbol_tag_does_not_create_value_definition_evidence(self) -> None:
        source = (
            "fn FutureFn() {\n"
            "  ()\n"
            "}\n"
            "fn root() {\n"
            "  FutureFn()\n"
            "}\n"
        )
        root = self.callable_root(start_line=4, end_line=6)
        unknown_function = {
            "kind": ["Sym", "FutureFn"],
            "pkg": "fixture/types",
            "tag": "0x9999",
            "path": "fixture.mbt",
            "range": [1, 1, 3, 2],
            "name_range": [1, 4, 1, 12],
        }
        _, outcomes = semantic_fixture(
            source,
            [root, unknown_function],
            function_type_locations={"fixture.mbt:5:3"},
            peek_payload=[
                {"path": "fixture.mbt", "range": "1:4-1:12"}
            ],
        )

        unresolved = [
            outcome
            for outcome in outcomes
            if isinstance(outcome, UnresolvedCandidate)
        ]
        self.assertEqual(len(unresolved), 1)
        self.assertEqual(
            unresolved[0].diagnostic.reason,
            "peek_def_unverified_local",
        )

    def test_suberror_constructor_uses_declaration_range_without_child_entry(self) -> None:
        source = (
            "pub(all) suberror Failure {\n"
            "  InternalError(String)\n"
            "}\n"
            "fn root() {\n"
            "  InternalError(\"x\")\n"
            "}\n"
        )
        root = self.callable_root(start_line=4, end_line=6)
        suberror = {
            "kind": ["Sym", "Failure"],
            "pkg": "fixture/errors",
            "tag": "0x63",
            "path": "fixture.mbt",
            "range": [1, 1, 3, 2],
            "name_range": [1, 19, 1, 26],
        }
        edges, outcomes = semantic_fixture(
            source,
            [root, suberror],
            function_type_locations={"fixture.mbt:5:3"},
            peek_payload=[
                {"path": "fixture.mbt", "range": "2:3-2:16"}
            ],
        )

        self.assertEqual(edges, [])
        ignored = [
            outcome
            for outcome in outcomes
            if isinstance(outcome, IntentionallyIgnored)
        ]
        self.assertEqual(len(ignored), 1)
        self.assertEqual(ignored[0].reason, "non_callable_reference")

    def test_builtin_some_sentinel_is_ignored(self) -> None:
        source = "fn root() {\n  Some(1)\n}\n"
        root = self.callable_root(start_line=1, end_line=3)
        edges, outcomes = semantic_fixture(
            source,
            [root],
            function_type_locations={"fixture.mbt:2:3"},
            peek_payload=[{"path": "", "range": "0:0-0:0"}],
        )

        self.assertEqual(edges, [])
        ignored = [
            outcome
            for outcome in outcomes
            if isinstance(outcome, IntentionallyIgnored)
        ]
        self.assertEqual(len(ignored), 1)
        self.assertEqual(ignored[0].reason, "non_callable_reference")

    def test_empty_path_sentinel_for_unknown_name_stays_unresolved(self) -> None:
        source = "fn root() {\n  Missing()\n}\n"
        root = self.callable_root(start_line=1, end_line=3)
        _, outcomes = semantic_fixture(
            source,
            [root],
            function_type_locations={"fixture.mbt:2:3"},
            peek_payload=[{"path": "", "range": "0:0-0:0"}],
        )

        unresolved = [
            outcome
            for outcome in outcomes
            if isinstance(outcome, UnresolvedCandidate)
        ]
        self.assertEqual(len(unresolved), 1)
        self.assertEqual(
            unresolved[0].diagnostic.reason,
            "invalid_source_location",
        )

    def test_builtin_sentinel_with_another_definition_is_ambiguous(self) -> None:
        source = "fn root() {\n  Some(1)\n}\n"
        root = self.callable_root(start_line=1, end_line=3)
        _, outcomes = semantic_fixture(
            source,
            [root],
            function_type_locations={"fixture.mbt:2:3"},
            peek_payload=[
                {"path": "", "range": "0:0-0:0"},
                {"path": "fixture.mbt", "range": "1:4-1:8"},
            ],
        )

        ambiguous = [
            outcome
            for outcome in outcomes
            if isinstance(outcome, AmbiguousCandidate)
        ]
        self.assertEqual(len(ambiguous), 1)
        self.assertEqual(
            ambiguous[0].diagnostic.reason,
            "peek_def_ambiguous_definition",
        )

    def test_callable_function_with_constructor_like_name_remains_callable(self) -> None:
        source = (
            "fn Some() {\n"
            "  ()\n"
            "}\n"
            "fn root() {\n"
            "  Some()\n"
            "}\n"
        )
        root = self.callable_root(start_line=4, end_line=6)
        some = self.callable_root(start_line=1, end_line=3, name="Some")
        edges, _ = semantic_fixture(
            source,
            [root, some],
            function_type_locations={"fixture.mbt:5:3"},
            peek_payload=[
                {"path": "fixture.mbt", "range": "1:4-1:8"}
            ],
        )

        with TemporaryDirectory() as directory:
            fixture_root = Path(directory)
            (fixture_root / "fixture.mbt").write_text(source)
            symbols_jsonl = "\n".join(
                json.dumps(entry) for entry in (root, some)
            ) + "\n"

            def fake_run(
                _root: Path,
                *args: str,
                check: bool = True,
            ) -> object:
                del check
                if args[2] == "gen-symbols":
                    (fixture_root / "symbols.jsonl").write_text(symbols_jsonl)
                    return SimpleNamespace(returncode=0, stdout="", stderr="")
                raise AssertionError(args)

            with patch.object(audit_script, "run", side_effect=fake_run):
                _, by_name, value_definitions = audit_script.load_symbols(
                    fixture_root
                )

        self.assertIn("Some", by_name)
        self.assertNotIn(
            audit_script.SourceLocation("fixture.mbt", 1, 4, 1, 8),
            value_definitions.non_callable_names,
        )

        self.assertIn(
            ("root", "compiler", "Some"),
            {
                (edge["enclosing"], edge["kind"], edge["target"])
                for edge in edges
                if edge["line"] == 5 and edge["column"] == 3
            },
        )

    def test_qualified_alias_resolves_at_final_callable_name_column(self) -> None:
        for rhs, target in (
            ("Type::method", "@runtime.Type::method"),
            ("@runtime.Type::method", "@runtime.Type::method"),
            ("@runtime.make_array", "@runtime.make_array"),
        ):
            with self.subTest(rhs=rhs):
                source = (
                    "fn root() {\n"
                    f"  let alias = {rhs}\n"
                    "  alias([])\n"
                    "}\n"
                )
                root = self.callable_root(start_line=1, end_line=4)
                identity = (
                    ["SymChild", "Type", "method"]
                    if rhs.endswith("Type::method")
                    else ["Sym", "make_array"]
                )
                expected_target = (
                    target
                    if "::" in target
                    else "@dowdiness/js_engine/interpreter/runtime.make_array"
                )
                runtime = {
                    "kind": identity,
                    "pkg": "dowdiness/js_engine/interpreter/runtime",
                    "tag": "0x1001",
                    "path": "fixture.mbt",
                    "range": [1, 1, 1, 12],
                    "name_range": [1, 4, 1, 8],
                }
                rhs_column = source.splitlines()[1].index(rhs) + 1
                name_offset = max(
                    rhs.rfind("::") + 2 if "::" in rhs else 0,
                    rhs.rfind(".") + 1 if "." in rhs else 0,
                )
                final_name_location = (
                    f"fixture.mbt:2:{rhs_column + name_offset}"
                )
                edges, _ = semantic_fixture(
                    source,
                    [root, runtime],
                    function_type_locations={"fixture.mbt:3:3"},
                    hover_identities={final_name_location: target},
                    peek_payload=[
                        {"path": "fixture.mbt", "range": "2:7-2:12"}
                    ],
                )

                self.assertIn(
                    ("root", "runtime", expected_target),
                    {
                        (edge["enclosing"], edge["kind"], edge["target"])
                        for edge in edges
                        if edge["line"] == 3 and edge["column"] == 3
                    },
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
                _value_definitions: audit_script.ValueDefinitions,
            ) -> audit_script.ResolutionOutcome:
                if candidate.spelling == "helper":
                    return ResolvedCompiler(candidate, "wrapper")
                if candidate.spelling == "observe_execution_step":
                    return ResolvedRuntime(
                        candidate,
                        "@runtime.Interpreter::observe_execution_step",
                    )
                return IntentionallyIgnored(candidate, "test_non_callable")

            with patch.object(
                audit_script,
                "load_symbols",
                return_value=(symbols, symbols_by_name, EMPTY_VALUE_DEFINITIONS),
            ), patch.object(
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
                _value_definitions: audit_script.ValueDefinitions,
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
                return_value=(symbols, symbols_by_name, EMPTY_VALUE_DEFINITIONS),
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
                _value_definitions: audit_script.ValueDefinitions,
            ) -> audit_script.ResolutionOutcome:
                if candidate.spelling == "method":
                    return ResolvedRuntime(candidate, "@runtime.Type::method")
                if candidate.spelling == "semantic_edge_audit_cross_file_wrapper":
                    return ResolvedCompiler(candidate, "wrapper")
                return IntentionallyIgnored(candidate, "test_non_callable")

            with patch.object(
                audit_script,
                "load_symbols",
                return_value=(symbols, symbols_by_name, EMPTY_VALUE_DEFINITIONS),
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
        for tag in audit_script.MOON_IDE_VALUE_TAGS:
            with self.subTest(value_tag=tag):
                self.assertTrue(audit_script._symbol_entry_is_value({"tag": tag}))
        for tag in ("0x10", "0x53", "0xd3", "0xd8"):
            with self.subTest(tag=tag):
                self.assertFalse(audit_script._symbol_entry_is_callable({"tag": tag}))
        for tag in ("0x1201", "0x8000", "0x9999"):
            with self.subTest(unknown_tag=tag):
                self.assertFalse(audit_script._symbol_entry_is_value({"tag": tag}))

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
