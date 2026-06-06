#!/usr/bin/env python3
"""Parity checks for shared Test262 skip metadata."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import test262_skip_metadata as skip_metadata


def load_script(module_name: str, filename: str):
    spec = importlib.util.spec_from_file_location(module_name, SCRIPT_DIR / filename)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load {filename}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def parity_cases() -> list[dict]:
    with (SCRIPT_DIR / "test262_skip_metadata_parity_cases.json").open(encoding="utf-8") as f:
        cases = json.load(f)
    assert isinstance(cases, list)
    return cases


def main() -> int:
    assert "test262_runner" not in sys.modules
    assert "test262_runner_for_parity" not in sys.modules
    assert "test262_analyze" not in sys.modules
    assert "test262_analyze_for_parity" not in sys.modules

    runner = load_script("test262_runner_for_parity", "test262-runner.py")
    analyzer = load_script("test262_analyze_for_parity", "test262-analyze.py")

    assert runner.SKIP_FEATURES is skip_metadata.SKIP_FEATURES
    assert runner.SKIP_FLAGS is skip_metadata.SKIP_FLAGS
    assert runner.SKIP_PATH_SUFFIXES is skip_metadata.SKIP_PATH_SUFFIXES
    assert analyzer.UNSUPPORTED_TEST262_FEATURES is skip_metadata.SKIP_FEATURES
    assert analyzer.UNSUPPORTED_FLAGS is skip_metadata.SKIP_FLAGS
    assert not hasattr(analyzer, "RUNNER_SKIP_FEATURES")

    feature_meta = runner.TestMetadata(features=["BigInt"], flags=[])
    assert runner.should_skip(feature_meta, "test/language/types/bigint.js") == (
        "unsupported feature: BigInt"
    )

    strict_meta = runner.TestMetadata(features=[], flags=["onlyStrict"])
    assert runner.should_skip(strict_meta, "test/language/example.js", mode="non-strict") == (
        "requires strict mode"
    )
    assert analyzer.classify_test(
        "test/language/example.js",
        {"features": [], "flags": ["onlyStrict"]},
    ) == ("applicable", "")

    loaded_features, loaded_flags, loaded_path_suffixes = skip_metadata.load_skip_metadata()
    assert loaded_features is not skip_metadata.SKIP_FEATURES
    assert loaded_features == skip_metadata.SKIP_FEATURES
    assert loaded_flags == skip_metadata.SKIP_FLAGS
    assert loaded_path_suffixes == skip_metadata.SKIP_PATH_SUFFIXES

    for case in parity_cases():
        reason = skip_metadata.skip_reason(
            case["filepath"],
            case.get("features", []),
            case.get("flags", []),
            mode=case.get("mode"),
        )
        assert reason == case["reason"], case["name"]

    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
