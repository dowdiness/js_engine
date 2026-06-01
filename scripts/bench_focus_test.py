#!/usr/bin/env python3
"""Tests for the focused benchmark median summarizer."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent


def load_bench_focus():
    spec = importlib.util.spec_from_file_location(
        "bench_focus",
        SCRIPT_DIR / "bench-focus.py",
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("failed to load bench-focus.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["bench_focus"] = module
    spec.loader.exec_module(module)
    return module


def make_csv(mean: float, cv: float) -> str:
    return (
        "name,category,stage,warmup,iterations,group_size,mean_ms,min_ms,max_ms,stddev_ms,cv_pct,noisy\n"
        f"isolate/bytecode/property_get,component,execution,3,15,3,{mean},1,2,0,{cv},false\n"
    )


def main() -> int:
    bench_focus = load_bench_focus()

    mixed_output = "warning before csv\n" + make_csv(34.0, 2.0)
    csv_text = bench_focus.csv_text_from_stdout(mixed_output)
    rows = bench_focus.parse_rows(csv_text)
    assert rows["isolate/bytecode/property_get"]["mean_ms"] == "34.0"

    rows_by_run = [
        bench_focus.parse_rows(make_csv(34.0, 2.0)),
        bench_focus.parse_rows(make_csv(36.0, 3.0)),
        bench_focus.parse_rows(make_csv(35.0, 1.0)),
    ]
    summary = bench_focus.summarize_row(
        "isolate/bytecode/property_get",
        rows_by_run,
    )
    assert summary["runs"] == 3
    assert summary["median_ms"] == 35.0
    assert summary["mean_ms"] == 35.0
    assert summary["min_ms"] == 34.0
    assert summary["max_ms"] == 36.0
    assert summary["median_in_run_cv_pct"] == 2.0

    missing = bench_focus.summarize_row("missing", rows_by_run)
    assert missing == {"name": "missing", "runs": 0}

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
