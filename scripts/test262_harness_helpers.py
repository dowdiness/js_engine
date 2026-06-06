#!/usr/bin/env python3
"""Opt-in Test262 harness helper selection and source transforms.

These helpers intentionally stay out of the runner's default path. When enabled,
the runner labels the output as modified methodology so local performance-oriented
runs are not confused with official CI conformance artifacts.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


HELPER_CODE_POINT_RANGE = "codePointRange"
SUPPORTED_HELPERS = (HELPER_CODE_POINT_RANGE,)

CODE_POINT_RANGE_PREAMBLE = """
// Opt-in Test262 host helper for RegExp-heavy harness utilities. If the
// engine provides a native $262.codePointRange, keep it; otherwise install a
// spec-equivalent JavaScript fallback so helper-enabled runs remain portable.
if (typeof $262 !== "undefined" && typeof $262.codePointRange !== "function") {
  $262.codePointRange = function(start, end) {
    var CHUNK_SIZE = 10000;
    var result = "";
    var codePoints = [];
    for (var length = 0, codePoint = start; codePoint <= end; codePoint++) {
      codePoints[length++] = codePoint;
      if (length === CHUNK_SIZE) {
        result += String.fromCodePoint.apply(null, codePoints);
        codePoints.length = length = 0;
      }
    }
    return result + String.fromCodePoint.apply(null, codePoints);
  };
}
"""

REGEXP_UTILS_BUILD_STRING = """function buildString(args) {
  // Use member expressions rather than destructuring `args` for improved
  // compatibility with engines that only implement assignment patterns
  // partially or not at all.
  const loneCodePoints = args.loneCodePoints;
  const ranges = args.ranges;
  const CHUNK_SIZE = 10000;
  let result = String.fromCodePoint.apply(null, loneCodePoints);
  for (let i = 0; i < ranges.length; i++) {
    let range = ranges[i];
    let start = range[0];
    let end = range[1];
    let codePoints = [];
    for (let length = 0, codePoint = start; codePoint <= end; codePoint++) {
      codePoints[length++] = codePoint;
      if (length === CHUNK_SIZE) {
        result += String.fromCodePoint.apply(null, codePoints);
        codePoints.length = length = 0;
      }
    }
    result += String.fromCodePoint.apply(null, codePoints);
  }
  return result;
}
"""

REGEXP_UTILS_BUILD_STRING_WITH_HELPER = """function buildString(args) {
  // Use member expressions rather than destructuring `args` for improved
  // compatibility with engines that only implement assignment patterns
  // partially or not at all.
  const loneCodePoints = args.loneCodePoints;
  const ranges = args.ranges;
  const CHUNK_SIZE = 10000;
  let result = String.fromCodePoint.apply(null, loneCodePoints);
  for (let i = 0; i < ranges.length; i++) {
    let range = ranges[i];
    let start = range[0];
    let end = range[1];
    if (typeof $262 !== "undefined" && typeof $262.codePointRange === "function") {
      result += $262.codePointRange(start, end);
      continue;
    }
    let codePoints = [];
    for (let length = 0, codePoint = start; codePoint <= end; codePoint++) {
      codePoints[length++] = codePoint;
      if (length === CHUNK_SIZE) {
        result += String.fromCodePoint.apply(null, codePoints);
        codePoints.length = length = 0;
      }
    }
    result += String.fromCodePoint.apply(null, codePoints);
  }
  return result;
}
"""

HELPER_PREAMBLES = {
    HELPER_CODE_POINT_RANGE: CODE_POINT_RANGE_PREAMBLE,
}


@dataclass(frozen=True)
class HarnessOptions:
    helpers: tuple[str, ...] = ()

    @classmethod
    def from_cli(cls, values: Optional[list[str]]) -> "HarnessOptions":
        """Return validated helper options from repeated CLI flag values."""
        selected = []
        for raw in values or []:
            for name in raw.split(","):
                helper = name.strip()
                if not helper:
                    continue
                if helper not in SUPPORTED_HELPERS:
                    supported = ", ".join(SUPPORTED_HELPERS)
                    raise ValueError(
                        f"unknown harness helper '{helper}' (supported: {supported})"
                    )
                if helper not in selected:
                    selected.append(helper)
        return cls(tuple(selected))

    @property
    def is_modified(self) -> bool:
        return bool(self.helpers)

    @property
    def methodology_label(self) -> str:
        if not self.helpers:
            return "default"
        return f"modified harness (helpers: {', '.join(self.helpers)})"

    def preamble(self) -> str:
        """Return injected source for selected opt-in harness helpers."""
        return "\n".join(HELPER_PREAMBLES[name] for name in self.helpers)

    def methodology_json_record(self) -> Optional[dict]:
        """Return JSON methodology metadata for modified-harness runs."""
        if not self.helpers:
            return None
        return {
            "label": self.methodology_label,
            "harness": "modified",
            "harness_helpers": list(self.helpers),
        }

    def transform_include(self, include_name: str, source: str) -> str:
        """Return harness source transformed for the selected helper set.

        The checked-out Test262 tree is never modified. If a future Test262
        revision changes `regExpUtils.js`, the source is left untouched; the
        helper preamble still exposes `$262.codePointRange` for harnesses that
        know how to consume it directly.
        """
        if HELPER_CODE_POINT_RANGE not in self.helpers:
            return source
        if not include_name.endswith("regExpUtils.js"):
            return source
        return source.replace(
            REGEXP_UTILS_BUILD_STRING,
            REGEXP_UTILS_BUILD_STRING_WITH_HELPER,
            1,
        )


DEFAULT_HARNESS_OPTIONS = HarnessOptions()
