#!/usr/bin/env python3
"""Corpus parity check for Test262 utility frontmatter parsing.

Python remains authoritative. The MoonBit artifact is a shadow-only output used
only to detect drift in the fallback YAML subset before any promotion work.
"""

from __future__ import annotations

import argparse
import contextlib
import difflib
import json
import sys
from pathlib import Path
from typing import Any, Iterator


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import test262_utils


AS_LIST_FIELDS = ("features", "flags", "includes")
ARTIFACT_KIND = "test262-utils-corpus"
SCHEMA_VERSION = 1


@contextlib.contextmanager
def yaml_mode(mode: str) -> Iterator[None]:
    """Select the explicit PyYAML mode for authoritative Python parsing."""
    original_yaml = test262_utils.yaml
    if mode != "fallback":
        raise ValueError(f"unsupported YAML mode for MoonBit shadow parity: {mode}")
    test262_utils.yaml = None
    try:
        yield
    finally:
        test262_utils.yaml = original_yaml


def resolve_test_dir(test262_root: Path) -> Path:
    """Accept either a Test262 checkout root or its test/ directory."""
    root = test262_root.resolve()
    nested = root / "test"
    if nested.is_dir():
        return nested
    if root.is_dir():
        return root
    raise FileNotFoundError(f"Test262 test directory not found under: {test262_root}")


def iter_js_files(test_dir: Path) -> list[Path]:
    return sorted(path for path in test_dir.rglob("*.js") if path.is_file())


def relative_test_path(test_dir: Path, path: Path) -> str:
    return path.relative_to(test_dir).as_posix()


def parsed_as_list(data: dict[str, Any] | None, key: str) -> list[Any]:
    if data is None:
        return []
    return test262_utils.as_list(data.get(key, []))


def corpus_record(test_dir: Path, path: Path) -> dict[str, Any]:
    source = path.read_text(encoding="utf-8")
    data = test262_utils.parse_yaml_frontmatter(source)
    record = {
        "path": relative_test_path(test_dir, path),
        "frontmatter": data,
    }
    for field in AS_LIST_FIELDS:
        record[field] = parsed_as_list(data, field)
    return record


def build_python_artifact(test262_root: Path, mode: str) -> dict[str, Any]:
    test_dir = resolve_test_dir(test262_root)
    with yaml_mode(mode):
        files = [corpus_record(test_dir, path) for path in iter_js_files(test_dir)]
    return {
        "schema_version": SCHEMA_VERSION,
        "kind": ARTIFACT_KIND,
        "yaml_mode": mode,
        "files": files,
    }


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def stable_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True)


def artifact_by_path(artifact: dict[str, Any]) -> dict[str, dict[str, Any]]:
    files = artifact.get("files")
    if not isinstance(files, list):
        raise AssertionError("artifact field 'files' must be an array")
    out: dict[str, dict[str, Any]] = {}
    for record in files:
        if not isinstance(record, dict):
            raise AssertionError("artifact file entries must be objects")
        path = record.get("path")
        if not isinstance(path, str):
            raise AssertionError("artifact file entries must have string paths")
        if path in out:
            raise AssertionError(f"duplicate artifact path: {path}")
        out[path] = record
    return out


def diff_text(expected: Any, actual: Any) -> str:
    return "\n".join(
        difflib.unified_diff(
            stable_json(expected).splitlines(),
            stable_json(actual).splitlines(),
            fromfile="python-authoritative",
            tofile="moonbit-shadow",
            lineterm="",
        )
    )


def compare_artifacts(expected: dict[str, Any], actual: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    expected_header = {k: v for k, v in expected.items() if k != "files"}
    actual_header = {k: v for k, v in actual.items() if k != "files"}
    if expected_header != actual_header:
        errors.append("artifact header mismatch:\n" + diff_text(expected_header, actual_header))

    try:
        expected_by_path = artifact_by_path(expected)
        actual_by_path = artifact_by_path(actual)
    except AssertionError as exc:
        errors.append(str(exc))
        return errors

    expected_paths = sorted(expected_by_path)
    actual_paths = sorted(actual_by_path)
    if not expected_paths:
        errors.append("no Test262 .js files discovered for corpus parity")
        return errors
    if expected_paths != actual_paths:
        missing = sorted(set(expected_paths) - set(actual_paths))[:10]
        extra = sorted(set(actual_paths) - set(expected_paths))[:10]
        errors.append(
            "artifact path set mismatch: "
            f"python={len(expected_paths)} moonbit={len(actual_paths)} "
            f"missing={missing} extra={extra}"
        )
        return errors

    for path in expected_paths:
        expected_record = expected_by_path[path]
        actual_record = actual_by_path[path]
        if expected_record != actual_record:
            errors.append(f"first record mismatch at {path}:\n" + diff_text(expected_record, actual_record))
            break
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Compare Python authoritative Test262 utility parsing with the "
            "MoonBit shadow artifact over a checked-out test262/test corpus."
        )
    )
    parser.add_argument(
        "--test262",
        type=Path,
        default=Path("./test262"),
        help="Test262 checkout root, or its test directory (default: ./test262)",
    )
    parser.add_argument(
        "--moonbit-output",
        type=Path,
        required=True,
        help="JSON artifact emitted by cmd/test262_utils_corpus",
    )
    parser.add_argument(
        "--yaml-mode",
        choices=("fallback",),
        required=True,
        help=(
            "Authoritative Python YAML mode. Only 'fallback' is supported here "
            "so local PyYAML availability cannot alter expectations."
        ),
    )
    parser.add_argument(
        "--python-output",
        type=Path,
        help="Optional path for the deterministic Python artifact, for debugging",
    )
    args = parser.parse_args(argv)

    expected = build_python_artifact(args.test262, args.yaml_mode)
    if args.python_output:
        args.python_output.write_text(stable_json(expected) + "\n", encoding="utf-8")

    actual = load_json(args.moonbit_output)
    if not isinstance(actual, dict):
        print("MoonBit artifact must be a JSON object", file=sys.stderr)
        return 1

    errors = compare_artifacts(expected, actual)
    if errors:
        print("Test262 utility corpus parity failed", file=sys.stderr)
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print(f"ok - compared {len(expected['files'])} Test262 utility records (yaml_mode={args.yaml_mode})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
