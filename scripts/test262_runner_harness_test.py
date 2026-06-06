#!/usr/bin/env python3
"""Tests for opt-in Test262 runner harness helpers and labels."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
RUNNER_PATH = SCRIPT_DIR / "test262-runner.py"


import test262_harness_helpers as harness_helpers


def load_runner():
    spec = importlib.util.spec_from_file_location("test262_runner", RUNNER_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"failed to load {RUNNER_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def assert_value_error(fn) -> None:
    try:
        fn()
    except ValueError:
        return
    raise AssertionError("expected ValueError")


def test_harness_helper_selection(_runner) -> None:
    assert harness_helpers.HarnessOptions.from_cli(None).helpers == ()
    assert harness_helpers.HarnessOptions.from_cli([]).helpers == ()
    assert harness_helpers.HarnessOptions.from_cli(["codePointRange"]).helpers == ("codePointRange",)
    assert harness_helpers.HarnessOptions.from_cli([" codePointRange, codePointRange "]).helpers == (
        "codePointRange",
    )
    assert harness_helpers.HarnessOptions.from_cli(["", "codePointRange", ""]).helpers == (
        "codePointRange",
    )
    assert_value_error(lambda: harness_helpers.HarnessOptions.from_cli(["unknownHelper"]))


def test_methodology_labels(_runner) -> None:
    default_options = harness_helpers.HarnessOptions()
    assert default_options.methodology_label == "default"
    assert default_options.methodology_json_record() is None

    options = harness_helpers.HarnessOptions(("codePointRange",))
    assert options.methodology_label == "modified harness (helpers: codePointRange)"
    assert options.methodology_json_record() == {
        "label": "modified harness (helpers: codePointRange)",
        "harness": "modified",
        "harness_helpers": ["codePointRange"],
    }


def test_load_harness_injects_selected_helpers(runner) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "test262"
        harness_dir = root / "harness"
        harness_dir.mkdir(parents=True, exist_ok=True)
        (harness_dir / "sta.js").write_text("// sta\n", encoding="utf-8")
        (harness_dir / "assert.js").write_text("// assert\n", encoding="utf-8")
        (harness_dir / "regExpUtils.js").write_text(
            harness_helpers.REGEXP_UTILS_BUILD_STRING,
            encoding="utf-8",
        )

        runner._harness_cache.clear()
        default_harness = runner.load_harness(str(root), ["regExpUtils.js"], False)
        assert "codePointRange" not in default_harness

        options = harness_helpers.HarnessOptions(("codePointRange",))
        runner._harness_cache.clear()
        modified_harness = runner.load_harness(
            str(root),
            ["regExpUtils.js"],
            False,
            harness_options=options,
        )
        assert "function print" in modified_harness
        assert "$262.codePointRange" in modified_harness
        assert "result += $262.codePointRange(start, end);" in modified_harness
        assert modified_harness.index("function print") < modified_harness.index("$262.codePointRange")
        assert modified_harness.index("$262.codePointRange") < modified_harness.index("// sta")

        raw_harness = runner.load_harness(
            str(root),
            [],
            True,
            harness_options=options,
        )
        assert raw_harness == ""


def test_save_results_labels_only_modified_harness_runs(runner) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        result = runner.TestResult(
            path=str(root / "test262" / "test" / "language" / "sample.js"),
            status="pass",
            mode="strict",
        )
        agg = runner.aggregate_results([result])

        default_output = root / "default.json"
        runner.save_results([result], agg, str(default_output))
        default_data = json.loads(default_output.read_text(encoding="utf-8"))
        assert "methodology" not in default_data
        assert "methodology" not in default_data["summary"]

        modified_output = root / "modified.json"
        runner.save_results(
            [result],
            agg,
            str(modified_output),
            harness_helpers.HarnessOptions(("codePointRange",)),
        )
        modified_data = json.loads(modified_output.read_text(encoding="utf-8"))
        assert modified_data["summary"]["methodology"] == "modified harness (helpers: codePointRange)"
        assert modified_data["methodology"] == {
            "label": "modified harness (helpers: codePointRange)",
            "harness": "modified",
            "harness_helpers": ["codePointRange"],
        }
        assert modified_data["results"] == [runner.result_json_record(result)]


def main() -> int:
    runner = load_runner()
    test_harness_helper_selection(runner)
    test_methodology_labels(runner)
    test_load_harness_injects_selected_helpers(runner)
    test_save_results_labels_only_modified_harness_runs(runner)
    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
