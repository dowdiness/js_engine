#!/usr/bin/env python3
"""Compare two Test262 runner JSON artifacts for migration parity.

The comparator implements the Phase 0 contract documented in
``docs/tooling-migration-contracts.md``. It intentionally ignores fields that
are expected to vary between two executions (`date`, `duration_ms`, and result
array order) while checking the fields consumed by CI/reporting.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

TOP_LEVEL_REQUIRED = ("engine", "date", "summary", "categories", "results")
TOP_LEVEL_ALLOWED = TOP_LEVEL_REQUIRED + ("methodology",)

SUMMARY_REQUIRED = (
    "total",
    "passed",
    "failed",
    "skipped",
    "timeout",
    "error",
    "pass_rate",
)
SUMMARY_ALLOWED = SUMMARY_REQUIRED + ("methodology",)

CATEGORY_FIELDS = ("total", "passed", "failed", "skipped", "pass_rate")
RESULT_FIELDS = ("path", "status", "reason", "duration_ms", "mode")
METHODOLOGY_FIELDS = ("label", "harness", "harness_helpers")

RESULT_STATUSES = {"pass", "fail", "skip", "timeout", "error"}
RESULT_MODES = {"strict", "non-strict"}


def normalize_path(path: str) -> str:
    """Return a stable slash-separated path key for Test262 result records."""
    normalized = os.path.normpath(str(path).strip()).replace("\\", "/")
    if normalized.startswith("./"):
        normalized = normalized[2:]
    for prefix in ("test262/test/", "test/"):
        if normalized.startswith(prefix):
            return normalized[len(prefix) :]
    marker = "/test262/test/"
    marker_index = normalized.find(marker)
    if marker_index >= 0:
        return normalized[marker_index + len(marker) :]
    return normalized


def load_artifact(path: Path) -> dict[str, Any]:
    try:
        with path.open(encoding="utf-8") as f:
            data = json.load(f)
    except OSError as e:
        raise SystemExit(f"error: failed to read {path}: {e}") from e
    except json.JSONDecodeError as e:
        raise SystemExit(f"error: invalid JSON in {path}: {e}") from e
    if not isinstance(data, dict):
        raise SystemExit(f"error: {path} must contain a JSON object")
    return data


def is_nonnegative_int(value: Any) -> bool:
    return type(value) is int and value >= 0


def is_nonnegative_number(value: Any) -> bool:
    return type(value) in (int, float) and value >= 0


def is_pass_rate(value: Any) -> bool:
    return type(value) in (int, float) and 0 <= value <= 100


def check_keys(
    label: str,
    obj: dict[str, Any],
    required: tuple[str, ...],
    allowed: tuple[str, ...],
    diffs: list[str],
) -> None:
    keys = set(obj)
    for field in required:
        if field not in keys:
            diffs.append(f"{label}: missing required field {field!r}")
    for field in sorted(keys - set(allowed)):
        diffs.append(f"{label}: unexpected field {field!r}")


def validate_count_fields(label: str, obj: dict[str, Any], fields: tuple[str, ...], diffs: list[str]) -> None:
    for field in fields:
        if field == "pass_rate":
            if field in obj and not is_pass_rate(obj[field]):
                diffs.append(f"{label}.{field}: expected number in range 0..100")
        elif field in obj and not is_nonnegative_int(obj[field]):
            diffs.append(f"{label}.{field}: expected non-negative integer")


def validate_summary(label: str, value: Any, diffs: list[str]) -> None:
    if not isinstance(value, dict):
        diffs.append(f"{label}: expected object")
        return
    check_keys(label, value, SUMMARY_REQUIRED, SUMMARY_ALLOWED, diffs)
    validate_count_fields(label, value, SUMMARY_REQUIRED, diffs)
    if "methodology" in value and not isinstance(value["methodology"], str):
        diffs.append(f"{label}.methodology: expected string")


def validate_category(label: str, value: Any, diffs: list[str]) -> None:
    if not isinstance(value, dict):
        diffs.append(f"{label}: expected object")
        return
    check_keys(label, value, CATEGORY_FIELDS, CATEGORY_FIELDS, diffs)
    validate_count_fields(label, value, CATEGORY_FIELDS, diffs)


def validate_result(label: str, value: Any, diffs: list[str]) -> None:
    if not isinstance(value, dict):
        diffs.append(f"{label}: expected object")
        return
    check_keys(label, value, RESULT_FIELDS, RESULT_FIELDS, diffs)

    path = value.get("path")
    if "path" in value and (not isinstance(path, str) or not path):
        diffs.append(f"{label}.path: expected non-empty string")
    status = value.get("status")
    if "status" in value and status not in RESULT_STATUSES:
        diffs.append(f"{label}.status: invalid value {status!r}")
    reason = value.get("reason")
    if "reason" in value and not isinstance(reason, str):
        diffs.append(f"{label}.reason: expected string")
    duration = value.get("duration_ms")
    if "duration_ms" in value and not is_nonnegative_number(duration):
        diffs.append(f"{label}.duration_ms: expected non-negative number")
    mode = value.get("mode")
    if "mode" in value and mode not in RESULT_MODES:
        diffs.append(f"{label}.mode: invalid value {mode!r}")


def validate_methodology(label: str, value: Any, diffs: list[str]) -> None:
    if not isinstance(value, dict):
        diffs.append(f"{label}: expected object")
        return
    check_keys(label, value, METHODOLOGY_FIELDS, METHODOLOGY_FIELDS, diffs)
    if "label" in value and not isinstance(value["label"], str):
        diffs.append(f"{label}.label: expected string")
    if "harness" in value and not isinstance(value["harness"], str):
        diffs.append(f"{label}.harness: expected string")
    helpers = value.get("harness_helpers")
    if "harness_helpers" in value:
        if not isinstance(helpers, list) or not all(isinstance(item, str) for item in helpers):
            diffs.append(f"{label}.harness_helpers: expected array of strings")
        elif len(set(helpers)) != len(helpers):
            diffs.append(f"{label}.harness_helpers: expected unique strings")


def validate_artifact(data: dict[str, Any], label: str) -> list[str]:
    """Return schema-contract violations for one Test262 artifact."""
    diffs: list[str] = []
    check_keys(label, data, TOP_LEVEL_REQUIRED, TOP_LEVEL_ALLOWED, diffs)

    if data.get("engine") != "moonbit-js-engine":
        diffs.append(f"{label}.engine: expected 'moonbit-js-engine'")
    if "date" in data and not isinstance(data["date"], str):
        diffs.append(f"{label}.date: expected string")

    if "summary" in data:
        validate_summary(f"{label}.summary", data["summary"], diffs)

    categories = data.get("categories")
    if "categories" in data:
        if not isinstance(categories, dict):
            diffs.append(f"{label}.categories: expected object")
        else:
            for category, record in categories.items():
                validate_category(f"{label}.categories[{category!r}]", record, diffs)

    results = data.get("results")
    if "results" in data:
        if not isinstance(results, list):
            diffs.append(f"{label}.results: expected array")
        else:
            for index, record in enumerate(results):
                validate_result(f"{label}.results[{index}]", record, diffs)

    if "methodology" in data:
        validate_methodology(f"{label}.methodology", data["methodology"], diffs)

    return diffs


def result_map(data: dict[str, Any], label: str) -> tuple[dict[tuple[str, str], dict[str, Any]], list[str]]:
    records = data.get("results")
    if not isinstance(records, list):
        return {}, [f"{label}: results must be an array"]

    out: dict[tuple[str, str], dict[str, Any]] = {}
    diffs: list[str] = []
    for index, record in enumerate(records):
        if not isinstance(record, dict):
            diffs.append(f"{label}: results[{index}] must be an object")
            continue
        path = record.get("path")
        mode = record.get("mode")
        status = record.get("status")
        if not isinstance(path, str) or not path:
            diffs.append(f"{label}: results[{index}].path must be a non-empty string")
            continue
        if mode not in RESULT_MODES:
            diffs.append(f"{label}: results[{index}].mode has invalid value {mode!r}")
            continue
        if status not in RESULT_STATUSES:
            diffs.append(f"{label}: results[{index}].status has invalid value {status!r}")
            continue
        key = (normalize_path(path), mode)
        if key in out:
            diffs.append(f"{label}: duplicate result key {key[0]} [{key[1]}]")
            continue
        out[key] = record
    return out, diffs


def compare_scalar(path: str, left: Any, right: Any, diffs: list[str]) -> None:
    if left != right:
        diffs.append(f"{path}: {left!r} != {right!r}")


def compare_required_object(
    name: str,
    left: Any,
    right: Any,
    fields: tuple[str, ...],
    diffs: list[str],
) -> None:
    if not isinstance(left, dict):
        diffs.append(f"left {name}: expected object")
        return
    if not isinstance(right, dict):
        diffs.append(f"right {name}: expected object")
        return
    for field in fields:
        if field in left or field in right:
            compare_scalar(f"{name}.{field}", left.get(field), right.get(field), diffs)


def has_broken_python_categories(data: dict[str, Any]) -> bool:
    """Return true for the current Python CI category path bug.

    When scripts/test262-runner.py is invoked from the repository root, it
    groups every result under ../.. because category aggregation is hardcoded
    relative to scripts/test262/test. MoonBit shadow artifacts should keep their
    normalized Test262 categories instead of copying that broken shape.
    """

    categories = data.get("categories")
    return isinstance(categories, dict) and set(categories) == {"../.."}


def category_for_result_path(path: str) -> str:
    normalized = normalize_path(path)
    parts = [part for part in normalized.split("/") if part]
    if len(parts) >= 2:
        return f"{parts[0]}/{parts[1]}"
    if parts:
        return parts[0]
    return ""


def expected_categories_from_results(
    data: dict[str, Any],
    label: str,
    diffs: list[str],
) -> dict[str, dict[str, Any]]:
    records = data.get("results")
    if not isinstance(records, list):
        diffs.append(f"{label} results: expected array")
        return {}

    expected: dict[str, dict[str, Any]] = {}
    for index, record in enumerate(records):
        if not isinstance(record, dict):
            diffs.append(f"{label} results[{index}]: expected object")
            continue
        path = record.get("path")
        status = record.get("status")
        if not isinstance(path, str) or not path or status not in RESULT_STATUSES:
            continue
        category = category_for_result_path(path)
        if category not in expected:
            expected[category] = {
                "total": 0,
                "passed": 0,
                "failed": 0,
                "skipped": 0,
                "pass_rate": 0.0,
            }
        stats = expected[category]
        stats["total"] += 1
        if status == "pass":
            stats["passed"] += 1
        elif status == "fail":
            stats["failed"] += 1
        elif status == "skip":
            stats["skipped"] += 1

    for stats in expected.values():
        executed = stats["passed"] + stats["failed"]
        stats["pass_rate"] = round((stats["passed"] / executed) * 100, 2) if executed else 0.0
    return expected


def compare_categories_to_results(data: dict[str, Any], label: str, diffs: list[str]) -> None:
    categories = data.get("categories")
    if not isinstance(categories, dict):
        diffs.append(f"{label} categories: expected object")
        return

    expected = expected_categories_from_results(data, label, diffs)
    if expected and not categories:
        diffs.append(f"{label} categories: missing normalized category output")
    actual_keys = set(categories)
    expected_keys = set(expected)
    for key in sorted(expected_keys - actual_keys):
        diffs.append(f"{label} categories: missing normalized category {key}")
    for key in sorted(actual_keys - expected_keys):
        diffs.append(f"{label} categories: unexpected category {key}")
    for key in sorted(actual_keys & expected_keys):
        compare_required_object(
            f"{label} categories[{key!r}]",
            categories[key],
            expected[key],
            CATEGORY_FIELDS,
            diffs,
        )


def compare_categories(left: dict[str, Any], right: dict[str, Any], diffs: list[str]) -> None:
    left_categories = left.get("categories")
    right_categories = right.get("categories")
    if not isinstance(left_categories, dict):
        diffs.append("left categories: expected object")
        return
    if not isinstance(right_categories, dict):
        diffs.append("right categories: expected object")
        return

    left_keys = set(left_categories)
    right_keys = set(right_categories)
    for key in sorted(left_keys - right_keys):
        diffs.append(f"categories: missing from right: {key}")
    for key in sorted(right_keys - left_keys):
        diffs.append(f"categories: extra in right: {key}")
    for key in sorted(left_keys & right_keys):
        compare_required_object(
            f"categories[{key!r}]",
            left_categories[key],
            right_categories[key],
            CATEGORY_FIELDS,
            diffs,
        )


def compare_results(
    left: dict[str, Any],
    right: dict[str, Any],
    diffs: list[str],
    ignore_reason: bool,
) -> None:
    left_results, left_shape_diffs = result_map(left, "left")
    right_results, right_shape_diffs = result_map(right, "right")
    diffs.extend(left_shape_diffs)
    diffs.extend(right_shape_diffs)

    left_keys = set(left_results)
    right_keys = set(right_results)
    for key in sorted(left_keys - right_keys):
        diffs.append(f"results: missing from right: {key[0]} [{key[1]}]")
    for key in sorted(right_keys - left_keys):
        diffs.append(f"results: extra in right: {key[0]} [{key[1]}]")
    for key in sorted(left_keys & right_keys):
        left_record = left_results[key]
        right_record = right_results[key]
        label = f"results[{key[0]} {key[1]}]"
        compare_scalar(f"{label}.status", left_record.get("status"), right_record.get("status"), diffs)
        if not ignore_reason:
            compare_scalar(
                f"{label}.reason",
                left_record.get("reason"),
                right_record.get("reason"),
                diffs,
            )


def compare_artifacts(
    left: dict[str, Any],
    right: dict[str, Any],
    ignore_reason: bool,
    allow_python_broken_categories: bool = False,
) -> list[str]:
    diffs: list[str] = []

    diffs.extend(validate_artifact(left, "left"))
    diffs.extend(validate_artifact(right, "right"))
    compare_scalar("engine", left.get("engine"), right.get("engine"), diffs)
    compare_required_object("summary", left.get("summary"), right.get("summary"), SUMMARY_ALLOWED, diffs)
    compare_scalar("methodology", left.get("methodology"), right.get("methodology"), diffs)
    if allow_python_broken_categories and has_broken_python_categories(left):
        compare_categories_to_results(right, "right", diffs)
    else:
        compare_categories(left, right, diffs)
    compare_results(left, right, diffs, ignore_reason)

    return diffs


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare two Test262 result artifacts for migration parity."
    )
    parser.add_argument("left", type=Path, help="authoritative result JSON")
    parser.add_argument("right", type=Path, help="candidate result JSON")
    parser.add_argument(
        "--ignore-reason",
        action="store_true",
        help="compare per-result status but allow reason text drift",
    )
    parser.add_argument(
        "--allow-python-broken-categories",
        action="store_true",
        help=(
            "when the left artifact has the Python CI category bug (a singleton '../..' category), "
            "discard only that category comparison while preserving MoonBit's normalized categories"
        ),
    )
    parser.add_argument(
        "--max-diffs",
        type=int,
        default=50,
        help="maximum number of differences to print (default: 50)",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.max_diffs <= 0:
        raise SystemExit("error: --max-diffs must be positive")

    left = load_artifact(args.left)
    right = load_artifact(args.right)
    diffs = compare_artifacts(
        left,
        right,
        ignore_reason=args.ignore_reason,
        allow_python_broken_categories=args.allow_python_broken_categories,
    )

    if not diffs:
        print("ok: Test262 result artifacts match migration parity contract")
        return 0

    print(f"mismatch: {len(diffs)} difference(s) found", file=sys.stderr)
    for diff in diffs[: args.max_diffs]:
        print(f"- {diff}", file=sys.stderr)
    remaining = len(diffs) - args.max_diffs
    if remaining > 0:
        print(f"... and {remaining} more", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
