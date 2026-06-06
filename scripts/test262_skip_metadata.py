#!/usr/bin/env python3
"""
Shared Test262 skip metadata for js_engine tooling.

This module has no runner side effects. It loads strict JSON metadata and
provides pure classification used by scripts/test262-runner.py and
scripts/test262-analyze.py.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
import json
from pathlib import Path
from typing import Any


SKIP_METADATA_SCHEMA_VERSION = 1
SKIP_METADATA_PATH = Path(__file__).with_name("test262_skip_metadata.json")


def _object_pairs_without_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate key in Test262 skip metadata: {key}")
        out[key] = value
    return out


def _load_json_object(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as f:
        data = json.load(f, object_pairs_hook=_object_pairs_without_duplicates)
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return data


def _string_set(data: Mapping[str, Any], key: str, path: Path) -> set[str]:
    value = data.get(key)
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError(f"{path}: {key} must be an array of strings")
    out = set(value)
    if len(out) != len(value):
        raise ValueError(f"{path}: {key} must not contain duplicate entries")
    return out


def _string_map(data: Mapping[str, Any], key: str, path: Path) -> dict[str, str]:
    value = data.get(key)
    if not isinstance(value, dict) or not all(
        isinstance(map_key, str) and isinstance(map_value, str)
        for map_key, map_value in value.items()
    ):
        raise ValueError(f"{path}: {key} must be an object of string reasons")
    return dict(value)


def load_skip_metadata(path: Path = SKIP_METADATA_PATH) -> tuple[set[str], set[str], dict[str, str]]:
    """Load and validate the strict JSON Test262 skip metadata file."""
    data = _load_json_object(path)
    allowed_keys = {
        "schema_version",
        "skip_features",
        "skip_flags",
        "skip_path_suffixes",
    }
    extra_keys = set(data) - allowed_keys
    missing_keys = allowed_keys - set(data)
    if extra_keys:
        raise ValueError(f"{path}: unknown keys: {', '.join(sorted(extra_keys))}")
    if missing_keys:
        raise ValueError(f"{path}: missing keys: {', '.join(sorted(missing_keys))}")
    if data["schema_version"] != SKIP_METADATA_SCHEMA_VERSION:
        raise ValueError(
            f"{path}: schema_version must be {SKIP_METADATA_SCHEMA_VERSION}"
        )
    return (
        _string_set(data, "skip_features", path),
        _string_set(data, "skip_flags", path),
        _string_map(data, "skip_path_suffixes", path),
    )


SKIP_FEATURES, SKIP_FLAGS, SKIP_PATH_SUFFIXES = load_skip_metadata()


def skip_reason(
    filepath: str,
    features: Iterable[str] = (),
    flags: Iterable[str] = (),
    mode: str | None = None,
) -> str | None:
    """Return the metadata skip reason, or None if metadata does not skip it.

    `mode` should be "strict" or "non-strict" for runner execution. Pass None
    for analyzer-style file census where onlyStrict/noStrict do not imply that
    the file is globally inapplicable.
    """
    features = list(features)
    flags = list(flags)

    if "_FIXTURE" in filepath:
        return "fixture file"

    normalized_path = filepath.replace("\\", "/")
    for suffix, reason in SKIP_PATH_SUFFIXES.items():
        if normalized_path.endswith(suffix):
            return reason

    for flag in flags:
        if flag in SKIP_FLAGS:
            return f"unsupported flag: {flag}"

    if mode == "non-strict" and "onlyStrict" in flags:
        return "requires strict mode"
    if mode == "strict" and "noStrict" in flags:
        return "cannot run in strict mode"

    for feature in features:
        if feature in SKIP_FEATURES:
            return f"unsupported feature: {feature}"

    return None
