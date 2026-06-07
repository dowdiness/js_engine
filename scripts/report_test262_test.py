#!/usr/bin/env python3
"""Focused tests for test262 report formatting helpers."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent


def load_report_test262():
    spec = importlib.util.spec_from_file_location(
        "report_test262",
        SCRIPT_DIR / "report-test262.py",
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("failed to load report-test262.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["report_test262"] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    report = load_report_test262()
    run = {
        "id": 1234567,
        "sha": "abcdef123456",
        "created_at": "2026-06-07T12:34:56Z",
        "url": "https://example.invalid/runs/1234567",
    }
    strict = {
        "total": 1000,
        "passed": 800,
        "failed": 50,
        "skipped": 100,
        "timeout": 40,
        "error": 10,
    }
    nonstrict = {
        "total": 2000,
        "passed": 1200,
        "failed": 300,
        "skipped": 400,
        "timeout": 90,
        "error": 10,
    }

    assert report.pct(1, 0) == "—"

    regression_baseline = {
        "strict": {"passed_min": 790},
        "non-strict": {"passed_min": 1300},
        "updated": "2026-06-01",
    }
    expected_table = """**Test262** — CI run [1234567](https://example.invalid/runs/1234567) on tip `abcdef1`, 2026-06-07. Each test file is run twice (strict + non-strict); the two are reported separately because summing would double-count files.

| Mode | Discovered | Skipped | Executed | Passed | Failed | Timeouts | Passed / Executed | Passed / Discovered |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| strict | 1,000 | 100 | 850 | 800 | 50 | 40 | **94.1%** | 80.0% |
| non-strict | 2,000 | 400 | 1,500 | 1,200 | 300 | 90 | **80.0%** | 60.0% |

CI regression baseline: `test262-baseline.json` (min 1,300 non-strict / 790 strict passed, updated 2026-06-01; currently -100 / +10 above). **REGRESSION**

_Note: 20 runner error(s) excluded from the Timeouts column; inspect results JSON for details._"""
    assert report.render_report(run, strict, nonstrict, regression_baseline) == expected_table

    passing_baseline = {
        "strict": {"passed_min": 790},
        "non-strict": {"passed_min": 1100},
        "updated": "2026-06-01",
    }
    expected_changelog = """test262 (each file run in both strict and non-strict modes,
reported separately — summing would double-count files):

- **Passed / Executed**: 94.1% strict (800 / 850),
  80.0% non-strict (1,200 / 1,500). Excludes ~40% of
  discovered files skipped for unimplemented features.
- **Passed / Discovered**: 80.0% strict, 60.0%
  non-strict. Counts skipped files as un-passed.

Measured on CI run 1234567 (tip `abcdef1`, 2026-06-07).
Regression baseline: +100 non-strict / +10 strict vs `test262-baseline.json` (min 1,100 / 790)."""
    assert report.render_changelog(run, strict, nonstrict, passing_baseline) == expected_changelog
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
