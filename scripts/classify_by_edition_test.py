#!/usr/bin/env python3
"""Tests for classify-by-edition.py frontmatter feature extraction."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent


def load_classifier():
    spec = importlib.util.spec_from_file_location(
        "classify_by_edition",
        SCRIPT_DIR / "classify-by-edition.py",
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("failed to load classify-by-edition.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["classify_by_edition"] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    classifier = load_classifier()

    source = """/*---
features:
  - Promise
  - BigInt
---*/
"""
    features = classifier.extract_features(source)
    assert features == ["Promise", "BigInt"]

    edition, unmapped = classifier.classify_path(
        "test262/test/language/example.js",
        features,
    )
    assert edition == "ES2020"
    assert unmapped == set()

    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
