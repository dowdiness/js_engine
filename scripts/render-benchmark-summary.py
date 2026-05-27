#!/usr/bin/env python3
"""Render benchmark CSV output as GitHub-flavored Markdown.

The benchmark runner emits CSV with columns from benchmarks/runner.mbt:
name, category, stage, warmup, iterations, group_size, mean_ms, min_ms,
max_ms, stddev_ms, cv_pct, noisy.

This script keeps the GitHub Actions workflow focused on orchestration while
centralizing the human-readable report formats used by the job summary and PR
comment.
"""

from __future__ import annotations

import argparse
import csv
import math
import os
from pathlib import Path
from typing import Iterable

COMMENT_MARKER = "<!-- js-engine-benchmark-report -->"
GUARDRAIL_NOTE = (
    "> `startup/tiny_program` is the PR #153 / issue #141 guardrail for "
    "built-in realm-stamping startup cost."
)
STAGE_ORDER = ["startup", "frontend", "execution"]
CLOSURE_COMPARISON_PAIRS = [
    (
        "exec/closure_factory",
        "baseline/closure_conversion/closure_factory",
        "closure_factory",
    ),
    (
        "pipeline/exec/evaluate",
        "pipeline/closure_conversion/evaluate",
        "pipeline evaluate",
    ),
]


def load_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def is_noisy(row: dict[str, str]) -> bool:
    return row["noisy"] == "true"


def mean_ms(row: dict[str, str]) -> float:
    return float(row["mean_ms"])


def fmt_ms(value: str | float) -> str:
    return f"{float(value):.3f} ms"


def make_bar(width: int) -> str:
    return "#" * width


def chart_bar(value: str | float, max_log: float) -> str:
    scaled = math.log(float(value) + 1.0)
    width = max(1, int(scaled / max_log * 30)) if max_log > 0 else 1
    return make_bar(width)


def render_full_table(rows: Iterable[dict[str, str]]) -> list[str]:
    lines = [
        "| benchmark | category | stage | mean | min | max | CV |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        lines.append(
            f"| {row['name']} | {row['category']} | {row['stage']} | "
            f"{fmt_ms(row['mean_ms'])} | {fmt_ms(row['min_ms'])} | "
            f"{fmt_ms(row['max_ms'])} | {float(row['cv_pct']):.1f}% |"
        )
    return lines


def render_stage_summary(rows: list[dict[str, str]]) -> list[str]:
    lines = [
        "| stage | benchmarks | total mean | slowest benchmark | slowest mean | noisy rows |",
        "| --- | ---: | ---: | --- | ---: | ---: |",
    ]
    for stage in STAGE_ORDER:
        subset = [row for row in rows if row["stage"] == stage]
        if not subset:
            continue
        total = sum(mean_ms(row) for row in subset)
        slowest = max(subset, key=mean_ms)
        noisy_count = sum(1 for row in subset if is_noisy(row))
        lines.append(
            f"| {stage} | {len(subset)} | {total:.3f} ms | "
            f"{slowest['name']} | {fmt_ms(slowest['mean_ms'])} | {noisy_count} |"
        )
    return lines


def render_mean_time_chart(rows: list[dict[str, str]]) -> list[str]:
    lines = [
        "| benchmark | stage | mean | chart |",
        "| --- | --- | ---: | --- |",
    ]
    max_log = max((math.log(mean_ms(row) + 1.0) for row in rows), default=0.0)
    for row in rows:
        note = " ⚠" if is_noisy(row) else ""
        lines.append(
            f"| {row['name']} | {row['stage']} | {fmt_ms(row['mean_ms'])}{note} | "
            f"`{chart_bar(row['mean_ms'], max_log)}` |"
        )
    return lines


def render_closure_comparisons(
    rows: list[dict[str, str]], *, style: str
) -> list[str]:
    by_name = {row["name"]: row for row in rows}
    lines = []
    for normal_name, converted_name, label in CLOSURE_COMPARISON_PAIRS:
        normal = by_name.get(normal_name)
        converted = by_name.get(converted_name)
        if normal is None or converted is None:
            continue
        normal_mean = mean_ms(normal)
        converted_mean = mean_ms(converted)
        ratio = normal_mean / converted_mean
        noisy = is_noisy(normal) or is_noisy(converted)
        if style == "summary":
            note = " (interpret cautiously: noisy row)" if noisy else ""
            lines.append(
                f"- {label}: {normal_mean:.3f} ms normal vs "
                f"{converted_mean:.3f} ms closure-converted ({ratio:.2f}x){note}"
            )
        elif style == "pr-comment":
            note = " ⚠" if noisy else ""
            lines.append(
                f"- {label}: {normal_mean:.3f} ms normal vs "
                f"{converted_mean:.3f} ms closure-converted (**{ratio:.2f}x**){note}"
            )
        else:
            raise ValueError(f"unknown comparison style: {style}")
    return lines


def append_section(lines: list[str], title: str, body: Iterable[str]) -> None:
    lines.extend(["", f"### {title}", "", *body])


def render_github_summary(
    rows: list[dict[str, str]],
    *,
    commit: str,
    runner_name: str,
    runner_os: str,
    trigger: str,
    moonbit_version: str,
    artifact_name: str,
) -> str:
    lines = [
        "## Benchmark Results",
        "",
        "| | |",
        "| --- | --- |",
        f"| Commit | `{commit}` |",
        f"| Runner | `{runner_name}` ({runner_os}) |",
        f"| Trigger | `{trigger}` |",
        f"| MoonBit | `{moonbit_version}` |",
        "",
        GUARDRAIL_NOTE,
        "",
        *render_full_table(rows),
    ]
    append_section(lines, "Stage summary", render_stage_summary(rows))
    append_section(lines, "Mean-time chart (log scale)", render_mean_time_chart(rows))
    append_section(
        lines,
        "Closure-conversion comparison",
        render_closure_comparisons(rows, style="summary"),
    )
    lines.extend(
        [
            "",
            f"Full CSV uploaded as artifact `{artifact_name}`.",
            "To compare two baselines: `diff old.csv new.csv`",
        ]
    )
    return "\n".join(lines) + "\n"


def render_pr_comment(rows: list[dict[str, str]], *, run_url: str) -> str:
    lines = [
        COMMENT_MARKER,
        "## Benchmark Results",
        "",
        f"Run: {run_url}",
        "",
        GUARDRAIL_NOTE,
    ]
    append_section(lines, "Stage summary", render_stage_summary(rows))
    append_section(lines, "Mean-time chart (log scale)", render_mean_time_chart(rows))
    comparisons = render_closure_comparisons(rows, style="pr-comment")
    append_section(lines, "Closure-conversion comparison", comparisons or ["- unavailable"])
    return "\n".join(lines) + "\n"


def env_default(name: str, fallback: str = "") -> str:
    return os.environ.get(name, fallback)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path", type=Path, help="Benchmark CSV file to render")
    parser.add_argument(
        "--format",
        choices=["github-summary", "pr-comment"],
        required=True,
        help="Markdown format to emit",
    )
    parser.add_argument("--commit", default=env_default("GITHUB_SHA"))
    parser.add_argument("--runner-name", default=env_default("RUNNER_NAME"))
    parser.add_argument("--runner-os", default=env_default("RUNNER_OS"))
    parser.add_argument("--trigger", default=env_default("GITHUB_EVENT_NAME"))
    parser.add_argument("--moonbit-version", default=env_default("MOONBIT_VERSION"))
    parser.add_argument("--artifact-name", default="")
    parser.add_argument("--run-url", default=env_default("RUN_URL"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rows = load_rows(args.csv_path)
    artifact_name = args.artifact_name or f"bench-results-{args.commit}"
    if args.format == "github-summary":
        print(
            render_github_summary(
                rows,
                commit=args.commit,
                runner_name=args.runner_name,
                runner_os=args.runner_os,
                trigger=args.trigger,
                moonbit_version=args.moonbit_version,
                artifact_name=artifact_name,
            ),
            end="",
        )
    else:
        print(render_pr_comment(rows, run_url=args.run_url), end="")


if __name__ == "__main__":
    main()
