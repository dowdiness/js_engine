#!/usr/bin/env python3
"""Run focused benchmark rows repeatedly and summarize median timings.

The MoonBit benchmark CLI emits one CSV snapshot per process. A single snapshot
can be noisy on the JS target because V8 warmup, GC, and shared-runner load move
whole rows together. This helper repeats the same command, saves raw CSVs under
_build/, and reports robust per-row medians across runs.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import shlex
import statistics
import subprocess
import sys
from pathlib import Path

DEFAULT_COMMAND = "moon run benchmarks --target js -- --all --csv"
DEFAULT_ROWS = [
    "isolate/bytecode/runtime_helpers",
    "isolate/bytecode/property_get",
    "isolate/bytecode/property_set",
    "isolate/bytecode/method_call",
    "pipeline/bytecode/evaluate",
]
CSV_HEADER = [
    "name",
    "category",
    "stage",
    "warmup",
    "iterations",
    "group_size",
    "mean_ms",
    "min_ms",
    "max_ms",
    "stddev_ms",
    "cv_pct",
    "noisy",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run the JS benchmark CSV command repeatedly and summarize selected "
            "rows with median/mean/range across runs."
        )
    )
    parser.add_argument(
        "--runs",
        type=int,
        default=5,
        help="number of CSV snapshots to collect (default: 5)",
    )
    parser.add_argument(
        "--rows",
        default=",".join(DEFAULT_ROWS),
        help="comma-separated benchmark row names to summarize",
    )
    parser.add_argument(
        "--command",
        default=DEFAULT_COMMAND,
        help=f"benchmark command to run (default: {DEFAULT_COMMAND!r})",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path("_build/bench-focus"),
        help="directory for timestamped raw CSV outputs",
    )
    parser.add_argument(
        "--timestamp",
        default=None,
        help="output directory name override (default: UTC timestamp)",
    )
    parser.add_argument(
        "--fail-on-missing",
        action="store_true",
        help="exit non-zero if any selected row is absent from any run",
    )
    return parser.parse_args()


def row_names(raw: str) -> list[str]:
    names = [part.strip() for part in raw.split(",") if part.strip()]
    if not names:
        raise SystemExit("error: --rows must select at least one benchmark row")
    return names


def output_dir(root: Path, timestamp: str | None) -> Path:
    name = timestamp or dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return root / name


def csv_text_from_stdout(stdout: str) -> str:
    lines = stdout.splitlines()
    for i, line in enumerate(lines):
        if line.split(",") == CSV_HEADER:
            return "\n".join(lines[i:]) + "\n"
    raise RuntimeError("benchmark output did not contain the expected CSV header")


def parse_rows(csv_text: str) -> dict[str, dict[str, str]]:
    return {row["name"]: row for row in csv.DictReader(csv_text.splitlines())}


def run_once(command: str) -> str:
    proc = subprocess.run(
        shlex.split(command),
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        if proc.stdout:
            print(proc.stdout, end="", file=sys.stdout)
        if proc.stderr:
            print(proc.stderr, end="", file=sys.stderr)
        raise RuntimeError(f"benchmark command failed with exit code {proc.returncode}")
    if proc.stderr:
        print(proc.stderr, end="", file=sys.stderr)
    return csv_text_from_stdout(proc.stdout)


def fmt_ms(value: float) -> str:
    return f"{value:.3f} ms"


def fmt_pct(value: float) -> str:
    return f"{value:.1f}%"


def sample_stdev(values: list[float]) -> float:
    return statistics.stdev(values) if len(values) > 1 else 0.0


def summarize_row(
    name: str, rows_by_run: list[dict[str, dict[str, str]]]
) -> dict[str, object]:
    present = [rows[name] for rows in rows_by_run if name in rows]
    means = [float(row["mean_ms"]) for row in present]
    cvs = [float(row["cv_pct"]) for row in present]
    if not means:
        return {"name": name, "runs": 0}
    avg = statistics.fmean(means)
    spread = sample_stdev(means)
    return {
        "name": name,
        "runs": len(means),
        "median_ms": statistics.median(means),
        "mean_ms": avg,
        "min_ms": min(means),
        "max_ms": max(means),
        "run_cv_pct": spread / avg * 100.0 if avg > 0.0 else 0.0,
        "median_in_run_cv_pct": statistics.median(cvs),
    }


def render_table(summaries: list[dict[str, object]], total_runs: int) -> str:
    lines = [
        "| benchmark | runs | median | mean | min | max | across-run CV | median in-run CV |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for summary in summaries:
        runs = int(summary["runs"])
        if runs == 0:
            lines.append(
                f"| `{summary['name']}` | 0/{total_runs} | — | — | — | — | — | — |"
            )
            continue
        lines.append(
            f"| `{summary['name']}` | {runs}/{total_runs} | "
            f"{fmt_ms(float(summary['median_ms']))} | "
            f"{fmt_ms(float(summary['mean_ms']))} | "
            f"{fmt_ms(float(summary['min_ms']))} | "
            f"{fmt_ms(float(summary['max_ms']))} | "
            f"{fmt_pct(float(summary['run_cv_pct']))} | "
            f"{fmt_pct(float(summary['median_in_run_cv_pct']))} |"
        )
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    if args.runs <= 0:
        raise SystemExit("error: --runs must be positive")
    names = row_names(args.rows)
    out_dir = output_dir(args.output_root, args.timestamp)
    out_dir.mkdir(parents=True, exist_ok=True)

    rows_by_run: list[dict[str, dict[str, str]]] = []
    print(f"Command: {args.command}")
    print(f"Runs: {args.runs}")
    print(f"Rows: {', '.join(names)}")
    print(f"Raw CSV output: {out_dir}")
    print("")

    for run in range(1, args.runs + 1):
        print(f"[{run}/{args.runs}] running benchmark command...", flush=True)
        csv_text = run_once(args.command)
        csv_path = out_dir / f"run-{run:02d}.csv"
        csv_path.write_text(csv_text)
        rows_by_run.append(parse_rows(csv_text))

    summaries = [summarize_row(name, rows_by_run) for name in names]
    print("")
    print(render_table(summaries, args.runs))

    missing = [summary["name"] for summary in summaries if summary["runs"] != args.runs]
    if missing:
        print("", file=sys.stderr)
        print(
            "warning: missing selected rows in at least one run: " + ", ".join(missing),
            file=sys.stderr,
        )
        if args.fail_on_missing:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
