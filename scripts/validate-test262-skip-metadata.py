#!/usr/bin/env python3
"""
Validate shared Test262 skip metadata against a checked-out Test262 suite.

This is a metadata coherence check only. It does not run the engine, read
result artifacts, or produce conformance numbers.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from test262_skip_metadata import SKIP_FEATURES, SKIP_FLAGS, SKIP_PATH_SUFFIXES
from test262_utils import as_list, parse_yaml_frontmatter


@dataclass
class SuiteMetadata:
    files_scanned: int
    features: set[str]
    flags: set[str]
    paths: list[str]


@dataclass
class ValidationIssue:
    kind: str
    entry: str
    detail: str


def collect_suite_metadata(test262_dir: Path) -> SuiteMetadata:
    test_root = test262_dir / "test"
    if not test_root.is_dir():
        raise FileNotFoundError(
            f"{test_root} does not exist; run `make test262-download` first"
        )

    features: set[str] = set()
    flags: set[str] = set()
    paths: list[str] = []
    files_scanned = 0

    for path in sorted(test_root.rglob("*.js")):
        files_scanned += 1
        normalized_path = path.as_posix()
        paths.append(normalized_path)
        try:
            rel_path = path.relative_to(test262_dir).as_posix()
        except ValueError:
            rel_path = normalized_path
        paths.append(rel_path)

        source = path.read_text(encoding="utf-8", errors="replace")
        data = parse_yaml_frontmatter(source) or {}
        features.update(str(feature) for feature in as_list(data.get("features", [])))
        flags.update(str(flag) for flag in as_list(data.get("flags", [])))

    return SuiteMetadata(
        files_scanned=files_scanned,
        features=features,
        flags=flags,
        paths=paths,
    )


def validate_skip_metadata(
    suite: SuiteMetadata,
    skip_features: set[str] = SKIP_FEATURES,
    skip_flags: set[str] = SKIP_FLAGS,
    skip_path_suffixes: Mapping[str, str] = SKIP_PATH_SUFFIXES,
) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []

    for feature in sorted(skip_features - suite.features):
        issues.append(
            ValidationIssue(
                kind="dead feature",
                entry=feature,
                detail="no Test262 file declares this value in features metadata",
            )
        )

    for flag in sorted(skip_flags - suite.flags):
        issues.append(
            ValidationIssue(
                kind="dead flag",
                entry=flag,
                detail="no Test262 file declares this value in flags metadata",
            )
        )

    for suffix in sorted(skip_path_suffixes):
        normalized_suffix = suffix.replace("\\", "/")
        if not any(path.endswith(normalized_suffix) for path in suite.paths):
            issues.append(
                ValidationIssue(
                    kind="dead path suffix",
                    entry=suffix,
                    detail="no Test262 file path matches this suffix",
                )
            )

    return issues


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate shared Test262 skip metadata without running tests or "
            "computing conformance numbers."
        )
    )
    parser.add_argument(
        "--test262",
        default="./test262",
        help="Path to the Test262 checkout (default: ./test262)",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        suite = collect_suite_metadata(Path(args.test262))
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    issues = validate_skip_metadata(suite)
    if issues:
        print("Test262 skip metadata validation failed:")
        for issue in issues:
            print(f"- {issue.kind}: {issue.entry} ({issue.detail})")
        print("\nNo conformance numbers were produced.")
        return 1

    print(
        "ok: shared Test262 skip metadata matches current Test262 "
        f"metadata/path usage ({suite.files_scanned} files scanned)"
    )
    print("No conformance numbers were produced.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
