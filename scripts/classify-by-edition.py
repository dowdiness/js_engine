#!/usr/bin/env python3
"""
Classify test262 results by ECMAScript edition.

Reads a test262-*-results.json produced by test262-runner.py, parses the
test262 frontmatter `features:` field for each test, and buckets tests by
the edition in which they first became Stage 4.

Usage:
    scripts/classify-by-edition.py test262-non-strict-results.json
    scripts/classify-by-edition.py --markdown test262-strict-results.json test262-non-strict-results.json

The feature -> edition map is curated (see FEATURE_EDITION below). Unmapped
features are reported so the map can be updated.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from typing import Iterable

# ---------------------------------------------------------------------------
# Curated feature -> ECMAScript edition map
# ---------------------------------------------------------------------------
# Each feature string is a tag from test262/features.txt. Edition = year the
# feature reached Stage 4 and shipped in an ECMA-262 edition. Intl.* features
# are routed to "Intl (ECMA-402)" because they belong to a separate spec.
# Stage 3 / not-yet-finished proposals use "Stage 3".

FEATURE_EDITION: dict[str, str] = {
    # --- ES2015 (ES6) ---
    "arrow-function": "ES2015",
    "class": "ES2015",
    "computed-property-names": "ES2015",
    "const": "ES2015",
    "default-parameters": "ES2015",
    "destructuring-assignment": "ES2015",
    "destructuring-binding": "ES2015",
    "for-of": "ES2015",
    "generators": "ES2015",
    "let": "ES2015",
    "new.target": "ES2015",
    "rest-parameters": "ES2015",
    "super": "ES2015",
    "template": "ES2015",
    "tail-call-optimization": "ES2015",
    "ArrayBuffer": "ES2015",
    "DataView": "ES2015",
    "DataView.prototype.getFloat32": "ES2015",
    "DataView.prototype.getFloat64": "ES2015",
    "DataView.prototype.getInt16": "ES2015",
    "DataView.prototype.getInt32": "ES2015",
    "DataView.prototype.getInt8": "ES2015",
    "DataView.prototype.getUint16": "ES2015",
    "DataView.prototype.getUint32": "ES2015",
    "DataView.prototype.setUint8": "ES2015",
    "Int8Array": "ES2015",
    "Int16Array": "ES2015",
    "Int32Array": "ES2015",
    "Uint8Array": "ES2015",
    "Uint16Array": "ES2015",
    "Uint32Array": "ES2015",
    "Uint8ClampedArray": "ES2015",
    "Float32Array": "ES2015",
    "Float64Array": "ES2015",
    "TypedArray": "ES2015",
    "Map": "ES2015",
    "Set": "ES2015",
    "WeakMap": "ES2015",
    "WeakSet": "ES2015",
    "Promise": "ES2015",
    "Proxy": "ES2015",
    "Reflect": "ES2015",
    "Reflect.construct": "ES2015",
    "Reflect.set": "ES2015",
    "Reflect.setPrototypeOf": "ES2015",
    "proxy-missing-checks": "ES2015",
    "Symbol": "ES2015",
    "Symbol.hasInstance": "ES2015",
    "Symbol.isConcatSpreadable": "ES2015",
    "Symbol.iterator": "ES2015",
    "Symbol.match": "ES2015",
    "Symbol.replace": "ES2015",
    "Symbol.search": "ES2015",
    "Symbol.species": "ES2015",
    "Symbol.split": "ES2015",
    "Symbol.toPrimitive": "ES2015",
    "Symbol.toStringTag": "ES2015",
    "Symbol.unscopables": "ES2015",
    "String.fromCodePoint": "ES2015",
    "String.prototype.includes": "ES2015",
    "u180e": "ES2015",
    "cross-realm": "ES2015",
    "caller": "ES2015",

    # --- ES2016 ---
    "exponentiation": "ES2016",
    "Array.prototype.includes": "ES2016",

    # --- ES2017 ---
    "async-functions": "ES2017",
    "Atomics": "ES2017",
    "SharedArrayBuffer": "ES2017",

    # --- ES2018 ---
    "async-iteration": "ES2018",
    "object-rest": "ES2018",
    "object-spread": "ES2018",
    "Promise.prototype.finally": "ES2018",
    "regexp-dotall": "ES2018",
    "regexp-lookbehind": "ES2018",
    "regexp-named-groups": "ES2018",
    "regexp-unicode-property-escapes": "ES2018",
    "Symbol.asyncIterator": "ES2018",

    # --- ES2019 ---
    "Array.prototype.flat": "ES2019",
    "Array.prototype.flatMap": "ES2019",
    "Object.fromEntries": "ES2019",
    "optional-catch-binding": "ES2019",
    "String.prototype.trimEnd": "ES2019",
    "String.prototype.trimStart": "ES2019",
    "string-trimming": "ES2019",
    "Symbol.prototype.description": "ES2019",
    "json-superset": "ES2019",
    "well-formed-json-stringify": "ES2019",
    "stable-array-sort": "ES2019",

    # --- ES2020 ---
    "BigInt": "ES2020",
    "coalesce-expression": "ES2020",
    "optional-chaining": "ES2020",
    "dynamic-import": "ES2020",
    "export-star-as-namespace-from-module": "ES2020",
    "for-in-order": "ES2020",
    "globalThis": "ES2020",
    "import.meta": "ES2020",
    "Promise.allSettled": "ES2020",
    "String.prototype.matchAll": "ES2020",

    # --- ES2021 ---
    "Promise.any": "ES2021",
    "AggregateError": "ES2021",
    "WeakRef": "ES2021",
    "FinalizationRegistry": "ES2021",
    "logical-assignment-operators": "ES2021",
    "numeric-separator-literal": "ES2021",
    "String.prototype.replaceAll": "ES2021",

    # --- ES2022 ---
    "class-fields-public": "ES2022",
    "class-fields-private": "ES2022",
    "class-fields-private-in": "ES2022",
    "class-methods-private": "ES2022",
    "class-static-fields-public": "ES2022",
    "class-static-fields-private": "ES2022",
    "class-static-methods-private": "ES2022",
    "class-static-block": "ES2022",
    "top-level-await": "ES2022",
    "Array.prototype.at": "ES2022",
    "String.prototype.at": "ES2022",
    "TypedArray.prototype.at": "ES2022",
    "Object.hasOwn": "ES2022",
    "error-cause": "ES2022",
    "regexp-match-indices": "ES2022",
    "Array.prototype.values": "ES2022",  # reflexive test feature
    "Object.is": "ES2022",  # was ES6 but kept for safety
    "arbitrary-module-namespace-names": "ES2022",
    "nonextensible-applies-to-private": "ES2022",
    "String.prototype.endsWith": "ES2015",  # was ES6; kept at 2015
    "Symbol.matchAll": "ES2020",

    # --- ES2023 ---
    "array-find-from-last": "ES2023",
    "change-array-by-copy": "ES2023",
    "hashbang": "ES2023",
    "symbols-as-weakmap-keys": "ES2023",

    # --- ES2024 ---
    "arraybuffer-transfer": "ES2024",
    "promise-with-resolvers": "ES2024",
    "resizable-arraybuffer": "ES2024",
    "String.prototype.isWellFormed": "ES2024",
    "String.prototype.toWellFormed": "ES2024",
    "Atomics.waitAsync": "ES2024",
    "regexp-v-flag": "ES2024",
    "align-detached-buffer-semantics-with-web-reality": "ES2024",
    "stable-typedarray-sort": "ES2024",
    "Array.fromAsync": "ES2024",
    "array-grouping": "ES2024",

    # --- ES2025 ---
    "iterator-helpers": "ES2025",
    "set-methods": "ES2025",
    "promise-try": "ES2025",
    "RegExp.escape": "ES2025",
    "regexp-modifiers": "ES2025",
    "Float16Array": "ES2025",
    "json-modules": "ES2025",
    "import-attributes": "ES2025",
    "Math.sumPrecise": "ES2025",
    "uint8array-base64": "ES2025",
    "Error.isError": "ES2025",
    "json-parse-with-source": "ES2025",
    "regexp-duplicate-named-groups": "ES2025",
    "upsert": "ES2025",  # Map.prototype.getOrInsert / getOrInsertComputed

    # --- Annex B (legacy, cross-edition) ---
    "__proto__": "Annex B",
    "__getter__": "Annex B",
    "__setter__": "Annex B",

    # --- Intl (ECMA-402) ---
    "Intl-enumeration": "Intl (ECMA-402)",
    "intl-normative-optional": "Intl (ECMA-402)",
    "Intl.DateTimeFormat-datetimestyle": "Intl (ECMA-402)",
    "Intl.DateTimeFormat-dayPeriod": "Intl (ECMA-402)",
    "Intl.DateTimeFormat-extend-timezonename": "Intl (ECMA-402)",
    "Intl.DateTimeFormat-formatRange": "Intl (ECMA-402)",
    "Intl.DateTimeFormat-fractionalSecondDigits": "Intl (ECMA-402)",
    "Intl.DisplayNames": "Intl (ECMA-402)",
    "Intl.DisplayNames-v2": "Intl (ECMA-402)",
    "Intl.DurationFormat": "Intl (ECMA-402)",
    "Intl.ListFormat": "Intl (ECMA-402)",
    "Intl.Locale": "Intl (ECMA-402)",
    "Intl.Locale-info": "Intl (ECMA-402)",
    "Intl.NumberFormat-unified": "Intl (ECMA-402)",
    "Intl.RelativeTimeFormat": "Intl (ECMA-402)",
    "Intl.Segmenter": "Intl (ECMA-402)",
    "Intl.Era-monthcode": "Intl (ECMA-402)",

    # --- Stage 3 proposals (not yet in any ECMA-262 edition) ---
    "Temporal": "Stage 3",
    "decorators": "Stage 3",
    "source-phase-imports": "Stage 3",
    "source-phase-imports-module-source": "Stage 3",
    "explicit-resource-management": "Stage 3",
    "import-defer": "Stage 3",
    "joint-iteration": "Stage 3",
    "iterator-sequencing": "Stage 3",
    "ShadowRealm": "Stage 3",
    "immutable-arraybuffer": "Stage 3",
    "Atomics.pause": "Stage 3",
}

# Order for output tables. Lower = older.
EDITION_ORDER = [
    "Pre-ES2015 (baseline)",
    "ES2015", "ES2016", "ES2017", "ES2018", "ES2019",
    "ES2020", "ES2021", "ES2022", "ES2023", "ES2024", "ES2025",
    "Annex B",
    "Intl (ECMA-402)",
    "Stage 3",
    "Unmapped",
]

EDITION_RANK = {e: i for i, e in enumerate(EDITION_ORDER)}


# ---------------------------------------------------------------------------
# Frontmatter parsing
# ---------------------------------------------------------------------------

FRONTMATTER_RE = re.compile(r"/\*---\s*(.*?)\s*---\*/", re.DOTALL)
FEATURES_INLINE_RE = re.compile(r"^features:\s*\[([^\]]*)\]", re.MULTILINE)
FEATURES_BLOCK_RE = re.compile(
    r"^features:\s*\n((?:\s{2,}-\s*\S+.*\n)+)", re.MULTILINE
)


def extract_features(text: str) -> list[str]:
    m = FRONTMATTER_RE.search(text)
    if not m:
        return []
    fm = m.group(1)
    inline = FEATURES_INLINE_RE.search(fm)
    if inline:
        return [f.strip() for f in inline.group(1).split(",") if f.strip()]
    block = FEATURES_BLOCK_RE.search(fm)
    if block:
        return [
            line.strip().lstrip("-").strip()
            for line in block.group(1).splitlines()
            if line.strip()
        ]
    return []


def classify_path(path: str, features: list[str]) -> tuple[str, set[str]]:
    """Return (edition, unmapped_features_seen)."""
    # Path-based overrides take priority for organizational buckets.
    if "/annexB/" in path or path.startswith("annexB/") or "/test/annexB/" in path:
        return "Annex B", set()
    if "/intl402/" in path or "/test/intl402/" in path:
        return "Intl (ECMA-402)", set()

    if not features:
        return "Pre-ES2015 (baseline)", set()

    editions = []
    unmapped = set()
    for f in features:
        ed = FEATURE_EDITION.get(f)
        if ed is None:
            unmapped.add(f)
            continue
        editions.append(ed)

    if not editions:
        # All features unmapped — tag as Unmapped so they surface.
        return "Unmapped", unmapped

    # A test using a feature from multiple editions belongs to the newest one
    # (it can only pass if the engine supports that edition's work).
    best = max(editions, key=lambda e: EDITION_RANK.get(e, -1))
    return best, unmapped


# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------

class Bucket:
    __slots__ = ("total", "passed", "failed", "skipped", "timeout", "error")

    def __init__(self) -> None:
        self.total = 0
        self.passed = 0
        self.failed = 0
        self.skipped = 0
        self.timeout = 0
        self.error = 0

    def record(self, status: str) -> None:
        self.total += 1
        if status == "pass":
            self.passed += 1
        elif status == "fail":
            self.failed += 1
        elif status == "skip":
            self.skipped += 1
        elif status == "timeout":
            self.timeout += 1
        elif status == "error":
            self.error += 1

    @property
    def executed(self) -> int:
        """Matches CI convention: passed + failed only (timeouts/errors excluded)."""
        return self.passed + self.failed

    @property
    def attempted(self) -> int:
        """All non-skipped: executed + timeouts + errors."""
        return self.passed + self.failed + self.timeout + self.error

    @property
    def passed_over_executed(self) -> float:
        return (self.passed / self.executed * 100) if self.executed else 0.0

    @property
    def passed_over_discovered(self) -> float:
        return (self.passed / self.total * 100) if self.total else 0.0


def classify_results(
    results: Iterable[dict], test262_root: str
) -> tuple[dict[str, Bucket], dict[str, int]]:
    """Classify each result. Returns (buckets, unmapped_feature_counts)."""
    buckets: dict[str, Bucket] = defaultdict(Bucket)
    unmapped_counts: dict[str, int] = defaultdict(int)
    feature_cache: dict[str, list[str]] = {}

    for r in results:
        path = r["path"]
        status = r["status"]

        # Parse frontmatter features (cached per-path).
        if path in feature_cache:
            features = feature_cache[path]
        else:
            abs_path = (
                path if os.path.isabs(path)
                else os.path.join(test262_root, path)
                if not path.startswith("test262/")
                else path
            )
            try:
                with open(abs_path, "r", encoding="utf-8", errors="replace") as f:
                    text = f.read()
                features = extract_features(text)
            except FileNotFoundError:
                features = []
            feature_cache[path] = features

        edition, unmapped = classify_path(path, features)
        buckets[edition].record(status)
        for u in unmapped:
            unmapped_counts[u] += 1

    return buckets, dict(unmapped_counts)


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def render_table(mode: str, buckets: dict[str, Bucket]) -> str:
    lines = [
        f"### {mode}",
        "",
        "| Edition | Discovered | Skipped | Executed | Passed | Failed | Timeout/Err | Passed / Executed | Passed / Discovered |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    ordered = sorted(
        buckets.items(), key=lambda kv: EDITION_RANK.get(kv[0], len(EDITION_ORDER))
    )
    totals = Bucket()
    for edition, b in ordered:
        if b.total == 0:
            continue
        lines.append(
            f"| {edition} | {b.total:,} | {b.skipped:,} | {b.executed:,} | "
            f"{b.passed:,} | {b.failed:,} | {b.timeout + b.error:,} | "
            f"{b.passed_over_executed:.1f}% | "
            f"{b.passed_over_discovered:.1f}% |"
        )
        totals.total += b.total
        totals.passed += b.passed
        totals.failed += b.failed
        totals.skipped += b.skipped
        totals.timeout += b.timeout
        totals.error += b.error
    lines.append(
        f"| **Total** | **{totals.total:,}** | **{totals.skipped:,}** | "
        f"**{totals.executed:,}** | **{totals.passed:,}** | "
        f"**{totals.failed:,}** | **{totals.timeout + totals.error:,}** | "
        f"**{totals.passed_over_executed:.1f}%** | "
        f"**{totals.passed_over_discovered:.1f}%** |"
    )
    return "\n".join(lines)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("results", nargs="+", help="test262-*-results.json path(s)")
    p.add_argument(
        "--test262-root",
        default=".",
        help="Directory containing test262/ subdir (default: .)",
    )
    p.add_argument(
        "--markdown", action="store_true", help="Emit markdown tables (default)"
    )
    p.add_argument(
        "--show-unmapped",
        action="store_true",
        help="Print unmapped features seen (to extend FEATURE_EDITION)",
    )
    args = p.parse_args()

    all_unmapped: dict[str, int] = defaultdict(int)
    sections = []
    for rf in args.results:
        with open(rf) as f:
            data = json.load(f)
        results = data.get("results", [])
        mode = data["results"][0]["mode"] if results else os.path.basename(rf)
        buckets, unmapped = classify_results(results, args.test262_root)
        sections.append(render_table(mode, buckets))
        for k, v in unmapped.items():
            all_unmapped[k] += v

    print("\n\n".join(sections))

    if args.show_unmapped and all_unmapped:
        print("\n### Unmapped features (add to FEATURE_EDITION)\n")
        for feat, n in sorted(all_unmapped.items(), key=lambda kv: -kv[1]):
            print(f"- `{feat}` — {n} tests")
    return 0


if __name__ == "__main__":
    sys.exit(main())
