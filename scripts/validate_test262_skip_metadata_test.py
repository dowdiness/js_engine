#!/usr/bin/env python3
"""Tests for Test262 skip metadata validation."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_validator():
    spec = importlib.util.spec_from_file_location(
        "validate_test262_skip_metadata",
        SCRIPT_DIR / "validate-test262-skip-metadata.py",
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("failed to load validate-test262-skip-metadata.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["validate_test262_skip_metadata"] = module
    spec.loader.exec_module(module)
    return module


def write_test262_file(root: Path, rel: str, frontmatter: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"/*---\n{frontmatter}\n---*/\n", encoding="utf-8")


def main() -> int:
    validator = load_validator()

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "test262"
        write_test262_file(
            root,
            "test/language/types/bigint.js",
            "features: [BigInt]\nflags: [CanBlockIsFalse]",
        )

        suite = validator.collect_suite_metadata(root)
        assert suite.files_scanned == 1

        no_issues = validator.validate_skip_metadata(
            suite,
            skip_features={"BigInt"},
            skip_flags={"CanBlockIsFalse"},
            skip_path_suffixes={"test/language/types/bigint.js": "covered"},
        )
        assert no_issues == []

        issues = validator.validate_skip_metadata(
            suite,
            skip_features={"BigInt", "missing-feature"},
            skip_flags={"CanBlockIsFalse", "missingFlag"},
            skip_path_suffixes={
                "test/language/types/bigint.js": "covered",
                "test/missing.js": "not covered",
            },
        )
        assert [(issue.kind, issue.entry) for issue in issues] == [
            ("dead feature", "missing-feature"),
            ("dead flag", "missingFlag"),
            ("dead path suffix", "test/missing.js"),
        ]

    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
