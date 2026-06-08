#!/usr/bin/env python3
"""Tests for the Test262 result parity comparator."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent


def load_compare_module():
    spec = importlib.util.spec_from_file_location(
        "compare_test262_results",
        SCRIPT_DIR / "compare-test262-results.py",
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("failed to load compare-test262-results.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["compare_test262_results"] = module
    spec.loader.exec_module(module)
    return module


def artifact(*, status: str = "pass", reason: str = "", duration: float = 1.0):
    return {
        "engine": "moonbit-js-engine",
        "date": "2026-06-06T00:00:00Z",
        "summary": {
            "total": 2,
            "passed": 1,
            "failed": 0,
            "skipped": 1,
            "timeout": 0,
            "error": 0,
            "pass_rate": 100.0,
        },
        "categories": {
            "language/literals": {
                "total": 2,
                "passed": 1,
                "failed": 0,
                "skipped": 1,
                "pass_rate": 100.0,
            }
        },
        "results": [
            {
                "path": "test262/test/language/literals/pass.js",
                "status": status,
                "reason": reason,
                "duration_ms": duration,
                "mode": "non-strict",
            },
            {
                "path": "language/literals/skip.js",
                "status": "skip",
                "reason": "unsupported feature: example",
                "duration_ms": 0.0,
                "mode": "strict",
            },
        ],
    }


def main() -> int:
    compare = load_compare_module()

    left = artifact(duration=1.0)
    right = artifact(duration=999.0)
    right["date"] = "2030-01-01T00:00:00Z"
    right["results"] = list(reversed(right["results"]))
    assert compare.compare_artifacts(left, right, ignore_reason=False) == []

    status_mismatch = artifact(status="fail", reason="boom")
    diffs = compare.compare_artifacts(left, status_mismatch, ignore_reason=False)
    assert any(".status" in diff for diff in diffs), diffs

    reason_mismatch = artifact(reason="different")
    diffs = compare.compare_artifacts(left, reason_mismatch, ignore_reason=False)
    assert any(".reason" in diff for diff in diffs), diffs
    assert compare.compare_artifacts(left, reason_mismatch, ignore_reason=True) == []

    summary_mismatch = artifact()
    summary_mismatch["summary"]["passed"] = 2
    diffs = compare.compare_artifacts(left, summary_mismatch, ignore_reason=False)
    assert any("summary.passed" in diff for diff in diffs), diffs

    duplicate = artifact()
    duplicate["results"].append(dict(duplicate["results"][0]))
    diffs = compare.compare_artifacts(left, duplicate, ignore_reason=False)
    assert any("duplicate result key" in diff for diff in diffs), diffs

    missing_mode = artifact()
    del missing_mode["results"][0]["mode"]
    diffs = compare.compare_artifacts(left, missing_mode, ignore_reason=False)
    assert any("missing required field 'mode'" in diff for diff in diffs), diffs

    missing_reason = artifact()
    del missing_reason["results"][0]["reason"]
    diffs = compare.compare_artifacts(left, missing_reason, ignore_reason=True)
    assert any("missing required field 'reason'" in diff for diff in diffs), diffs

    extra_category_field = artifact()
    extra_category_field["categories"]["language/literals"]["timeout"] = 1
    diffs = compare.compare_artifacts(left, extra_category_field, ignore_reason=False)
    assert any("unexpected field 'timeout'" in diff for diff in diffs), diffs

    python_broken_categories = artifact()
    python_broken_categories["categories"] = {
        "../..": {
            "total": 2,
            "passed": 1,
            "failed": 0,
            "skipped": 1,
            "pass_rate": 100.0,
        }
    }
    diffs = compare.compare_artifacts(left, python_broken_categories, ignore_reason=False)
    assert any("categories:" in diff for diff in diffs), diffs
    assert compare.compare_artifacts(
        python_broken_categories,
        left,
        ignore_reason=False,
        allow_python_broken_categories=True,
    ) == []
    copied_broken_category = compare.compare_artifacts(
        python_broken_categories,
        python_broken_categories,
        ignore_reason=False,
        allow_python_broken_categories=True,
    )
    assert any("missing normalized category language/literals" in diff for diff in copied_broken_category), copied_broken_category

    empty_categories = artifact()
    empty_categories["categories"] = {}
    empty_category_diffs = compare.compare_artifacts(
        python_broken_categories,
        empty_categories,
        ignore_reason=False,
        allow_python_broken_categories=True,
    )
    assert any("missing normalized category output" in diff for diff in empty_category_diffs), empty_category_diffs

    real_category_mismatch = artifact()
    real_category_mismatch["categories"] = dict(real_category_mismatch["categories"])
    real_category_mismatch["categories"]["built-ins/Array"] = real_category_mismatch["categories"].pop(
        "language/literals"
    )
    diffs = compare.compare_artifacts(
        left,
        real_category_mismatch,
        ignore_reason=False,
        allow_python_broken_categories=True,
    )
    assert any("categories:" in diff for diff in diffs), diffs

    assert compare.normalize_path("./test262/test/language/literals/pass.js") == "language/literals/pass.js"
    assert compare.normalize_path("test/language/literals/pass.js") == "language/literals/pass.js"

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
