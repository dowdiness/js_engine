#!/usr/bin/env python3
"""Validate active intent docs against shared Test262 skip metadata.

Checks two invariants:

1. Graduated features (shipped; blanket skip removed) must not reappear in
   ``skip_features``.
2. Active intent docs must not claim graduated features are currently blanket-
   skipped or wholly unimplemented, except in clearly historical context.

This is a fast policy guard for maintainers and CI. It does not run Test262 or
produce conformance numbers.

Usage:
  python3 scripts/validate_docs_skip_policy.py
  make validate-docs-skip-policy
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys


def load_manifest(path: pathlib.Path) -> dict:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def load_skip_features(metadata_path: pathlib.Path) -> set[str]:
    with metadata_path.open(encoding="utf-8") as f:
        data = json.load(f)
    features = data.get("skip_features", [])
    if not isinstance(features, list):
        raise ValueError("skip_features must be a JSON array")
    return set(features)


def compile_allowed_patterns(feature: str, templates: list[str]) -> list[re.Pattern[str]]:
    escaped = re.escape(feature)
    patterns: list[re.Pattern[str]] = []
    for tmpl in templates:
        source = tmpl.replace("FEATURE", escaped)
        patterns.append(re.compile(source, re.IGNORECASE))
    return patterns


def line_allows_graduated_feature(
    line: str,
    feature: str,
    allowed_patterns: list[re.Pattern[str]],
) -> bool:
    if feature not in line:
        return True
    return any(p.search(line) for p in allowed_patterns)


def has_historical_context(
    lines: list[str],
    line_index: int,
    markers: list[str],
    *,
    window: int = 6,
) -> bool:
    start = max(0, line_index - window)
    chunk = "\n".join(lines[start : line_index + 1]).lower()
    return any(marker.lower() in chunk for marker in markers)


def validate_graduated_not_in_skip_features(
    graduated: list[str],
    skip_features: set[str],
) -> list[str]:
    errors: list[str] = []
    for feature in graduated:
        if feature in skip_features:
            errors.append(
                f"graduated feature `{feature}` is present in skip_features; "
                "remove it from scripts/test262_skip_metadata.json or drop it "
                "from scripts/docs_skip_policy_manifest.json if the graduation "
                "was reverted"
            )
    return errors


def validate_active_docs(
    repo_root: pathlib.Path,
    manifest: dict,
) -> list[str]:
    graduated: list[str] = manifest["graduated_features"]
    doc_paths: list[str] = manifest["active_intent_docs"]
    allowed_templates: list[str] = manifest["allowed_line_patterns"]
    historical_markers: list[str] = manifest["historical_context_markers"]

    errors: list[str] = []
    for rel in doc_paths:
        path = repo_root / rel
        if not path.is_file():
            errors.append(f"missing active intent doc: {rel}")
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        for line_index, line in enumerate(lines):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            historical = has_historical_context(
                lines,
                line_index,
                historical_markers,
            )
            for feature in graduated:
                if feature not in line:
                    continue
                if historical:
                    continue
                patterns = compile_allowed_patterns(feature, allowed_templates)
                if not line_allows_graduated_feature(line, feature, patterns):
                    errors.append(
                        f"{rel}:{line_index + 1}: stale blanket-skip or "
                        f"unimplemented claim for `{feature}` — use historical "
                        "wording or update scripts/docs_skip_policy_manifest.json "
                        "if this feature was reverted"
                    )
    return errors


def validate(
    repo_root: pathlib.Path,
    manifest_path: pathlib.Path,
    metadata_path: pathlib.Path,
) -> list[str]:
    manifest = load_manifest(manifest_path)
    skip_features = load_skip_features(metadata_path)
    errors = validate_graduated_not_in_skip_features(
        manifest["graduated_features"],
        skip_features,
    )
    errors.extend(validate_active_docs(repo_root, manifest))
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        type=pathlib.Path,
        default=pathlib.Path(__file__).resolve().parent.parent,
    )
    parser.add_argument(
        "--manifest",
        type=pathlib.Path,
        default=pathlib.Path(__file__).with_name("docs_skip_policy_manifest.json"),
    )
    parser.add_argument(
        "--metadata",
        type=pathlib.Path,
        default=pathlib.Path(__file__).with_name("test262_skip_metadata.json"),
    )
    args = parser.parse_args(argv)

    errors = validate(args.repo_root, args.manifest, args.metadata)
    if errors:
        print("docs skip policy validation failed:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(
        "ok: active intent docs align with shared skip metadata "
        f"({len(load_manifest(args.manifest)['graduated_features'])} graduated features checked)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
