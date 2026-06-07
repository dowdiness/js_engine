#!/usr/bin/env python3
"""Parity fixture checks for shared Test262 utility helpers."""

from __future__ import annotations

import json
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import test262_utils


FIXTURE_PATH = SCRIPT_DIR / "test262_utils_parity_cases.json"


def parity_cases() -> dict:
    with FIXTURE_PATH.open(encoding="utf-8") as f:
        data = json.load(f)
    assert isinstance(data, dict)
    return data


def main() -> int:
    cases = parity_cases()

    assert test262_utils.parse_yaml_frontmatter("/*---\nflags: [onlyStrict]\n---*/\n") == {
        "flags": ["onlyStrict"]
    }

    # These fixtures pin the lightweight fallback subset that MoonBit shadows.
    # Keep Python authoritative by invoking the public entry point with PyYAML
    # disabled, regardless of whether PyYAML happens to be installed locally.
    original_yaml = test262_utils.yaml
    test262_utils.yaml = None
    try:
        for case in cases["parse_yaml_frontmatter"]:
            actual = test262_utils.parse_yaml_frontmatter(case["source"])
            assert actual == case["expected"], case["name"]
    finally:
        test262_utils.yaml = original_yaml

    for case in cases["as_list"]:
        actual = test262_utils.as_list(case["input"])
        assert actual == case["expected"], case["name"]

    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
