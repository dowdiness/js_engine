#!/usr/bin/env python3
"""Generate a human-readable Test262 skip-policy report from skip metadata.

The report is for auditability only; it does not change runner behavior.
"""

from __future__ import annotations

import argparse
import json
import pathlib
from datetime import datetime, timezone
from collections import defaultdict


REASON_MAP = {
    # Async / modules
    "async-iteration": "Async iteration/runtime protocol not enabled",
    "top-level-await": "Module/top-level await gating is not enabled",
    "dynamic-import": "Dynamic import not enabled",
    "import.meta": "import.meta host binding not enabled",
    "import-attributes": "Import attributes not enabled",
    "source-phase-imports": "Source-phase module imports not enabled",
    "json-modules": "JSON modules not enabled",
    "module-syntax": "Module-mode syntax support deferred",
    "source-phase-imports-module-source": "Source-phase module semantics not enabled",

    # Class / object model
    "class-fields-private": "Class private fields are not implemented",
    "class-methods-private": "Class private methods are not implemented",
    "class-static-fields-private": "Class static private fields are not implemented",
    "class-static-methods-private": "Class static private methods are not implemented",
    "class-static-block": "Class static blocks are not implemented",

    # BigInt / objects / temporal / memory
    "BigInt": "BigInt is currently out of scope",
    "Temporal": "Temporal is currently out of scope",
    "SharedArrayBuffer": "SharedArrayBuffer is currently out of scope",
    "ArrayBuffer-detach": "ArrayBuffer transfer/detach paths remain unsupported",
    "arraybuffer-transfer": "ArrayBuffer transfer/detach paths remain unsupported",
    "resizable-arraybuffer": "Resizable ArrayBuffer is not implemented",

    # RegExp suite
    "regexp-lookbehind": "RegExp lookbehind not yet implemented",
    "regexp-match-indices": "RegExp match indices not yet implemented",
    "regexp-modifiers": "ES2015+ RegExp modifiers not yet implemented",
    "regexp-unicode-property-escapes": "Unicode RegExp property escapes not yet implemented",
    "regexp-v-flag": "RegExp v-flag support not yet implemented",
    "RegExp.escape": "RegExp.escape helper is not yet implemented",

    # Frontmatter/flags
    "CanBlockIsFalse": "Frontmatter flag requires non-block/non-catch semantics currently unsupported",
    "CanBlockIsTrue": "Frontmatter flag requires non-block/non-catch semantics currently unsupported",

    # Advanced / experimental
    "Atomics": "Atomics API is not implemented",
    "ShadowRealm": "ShadowRealm is not implemented",
    "WeakRef": "WeakRef is not implemented",
    "FinalizationRegistry": "FinalizationRegistry is not implemented",
    "IsHTMLDDA": "IsHTMLDDA host behavior is not implemented",
    "CrossRealm": "Cross-realm behavior is not implemented",
    "cross-realm": "Cross-realm behavior is not implemented",
    "caller": "Caller/Caller restrictions are intentionally deferred",
    "decorators": "Decorators are not implemented",
    "explicit-resource-management": "Explicit Resource Management is not implemented",
    "iterator-helpers": "Iterator helpers are not implemented",
    "iterator-sequencing": "Iterator sequencing features are not implemented",
    "joint-iteration": "Joint iteration helpers are not implemented",
    "hashbang": "Hashbang support is deferred",
    "immutable-arraybuffer": "Immutable ArrayBuffer behavior is not implemented",
    "intl-normative-optional": "Intl normative optional behavior deferred",
    "for-in-order": "for-in order guarantees are not fully implemented",
    "tail-call-optimization": "Tail call optimization is not supported",
    "float16array": "Float16Array support is deferred",
    "Float16Array": "Float16Array support is deferred",
    "mutable-arraybuffer": "Mutable ArrayBuffer behavior not implemented",
    "set-methods": "Set methods helpers are not implemented",
    "resizable-arraybuffer": "Resizable ArrayBuffer is not implemented",
}


def _load_metadata(path: pathlib.Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(f"Metadata file not found: {path}")
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _group_by_reason(entries: list[str]) -> dict[str, list[str]]:
    groups: dict[str, list[str]] = defaultdict(list)
    for item in sorted(entries):
        reason = REASON_MAP.get(item, "Other spec gap")
        groups[reason].append(item)
    return groups


def _format_blocked_features(title: str, groups: dict[str, list[str]]) -> list[str]:
    lines = [f"## {title}\n"]
    for reason, features in sorted(groups.items(), key=lambda kv: kv[0].lower()):
        lines.append(f"### {reason}")
        lines.extend(f"- `{f}`" for f in sorted(features))
        lines.append("")
    if not groups:
        lines.append("- (none)\n")
    return lines


def build_report(data: dict, now_iso: str | None = None) -> str:
    now = now_iso or datetime.now(timezone.utc).isoformat(timespec="seconds")
    skip_features = data.get("skip_features", [])
    skip_flags = data.get("skip_flags", [])
    skip_path_suffixes = data.get("skip_path_suffixes", {}) or {}

    feature_groups = _group_by_reason(skip_features)

    lines: list[str] = []
    lines.append("# Test262 Skip Metadata Report")
    lines.append(f"Generated: {now}")
    lines.append("")

    lines.append("## Source of truth")
    lines.append("This report is generated from `scripts/test262_skip_metadata.json`.")
    lines.append("It is audit-oriented documentation and does not alter skip logic.")
    lines.append("")

    schema_version = data.get("schema_version", "unknown")
    lines.append(f"- schema_version: `{schema_version}`")
    lines.append(f"- skip_features: `{len(skip_features)}`")
    lines.append(f"- skip_flags: `{len(skip_flags)}`")
    lines.append(f"- skip_path_suffixes: `{len(skip_path_suffixes)}`")
    lines.append("")

    lines.append("## Runner policy")
    lines.append("- Execution mode: both `strict` and `non-strict` runs are performed by default.")
    lines.append("- fixture files and unsupported Test262 frontmatter (e.g., `assert` fixtures) remain policy-excluded before metadata application.")
    lines.append("- mode flags (`onlyStrict` / `noStrict`) are enforced by the runner in each mode.")
    lines.append("- module/async behavior is governed by fixture frontmatter + skip flags/features:")
    lines.append("  - if a test requires a skipped feature, it is excluded before execution.")
    lines.append("  - if a test is marked async-iteration/top-level-await-related, it is excluded under current runner policy.")
    lines.append("")

    lines.extend(_format_blocked_features("Skip features (by feature tag)", feature_groups))

    lines.append("## Skip flags")
    if skip_flags:
        lines.append("The following frontmatter flags cause static skip (before execution):")
        for flag in sorted(skip_flags):
            reason = REASON_MAP.get(flag, "Other unsupported flag")
            lines.append(f"- `{flag}` — {reason}")
        lines.append("")
    else:
        lines.append("- (none)\n")

    lines.append("## Path suffix exceptions")
    lines.append("These paths are force-skipped by fixture-path suffix policy with explicit per-file rationale:")
    if skip_path_suffixes:
        lines.append("")
        lines.append("| path suffix | reason |")
        lines.append("|---|---|")
        for suffix, reason in sorted(skip_path_suffixes.items(), key=lambda kv: kv[0]):
            reason_text = str(reason).replace("|", "\\|")
            lines.append(f"| {suffix} | {reason_text} |")
        lines.append("")
    else:
        lines.append("- (none)")

    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Render a human-readable test262 skip report")
    parser.add_argument(
        "--metadata",
        default=str(pathlib.Path(__file__).with_name("test262_skip_metadata.json")),
        help="Path to test262_skip_metadata.json",
    )
    parser.add_argument(
        "--output",
        default="-",
        help="Output file path. '-' prints to stdout.",
    )
    parser.add_argument("--json", action="store_true", help="Also print parsed metadata as JSON summary")
    args = parser.parse_args()

    data = _load_metadata(pathlib.Path(args.metadata))
    report = build_report(data)

    if args.output == "-":
        print(report)
    else:
        out = pathlib.Path(args.output)
        out.write_text(report, encoding="utf-8")
        print(f"Wrote {out}")

    if args.json:
        payload = {
            "feature_count": len(data.get("skip_features", [])),
            "flag_count": len(data.get("skip_flags", [])),
            "path_suffix_count": len(data.get("skip_path_suffixes", {})),
        }
        print(json.dumps(payload, indent=2, sort_keys=True))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
