#!/usr/bin/env python3
"""Compare this repo's Test262 skip metadata against an external feature config.

This is a *planning signal* only.  It does not execute tests, report pass rates,
or claim conformance.  Authoritative conformance numbers come from CI Test262
runs; see docs/TEST262.md and `make test262-report`.

Usage:
  python3 scripts/test262_feature_gap.py --ext-config /path/to/config.ini
  python3 scripts/test262_feature_gap.py \
      --ext-config /path/to/config.ini \
      --metadata scripts/test262_skip_metadata.json \
      --output docs/test262-feature-gap.md
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from datetime import datetime, timezone


def parse_features_config(text: str) -> tuple[set[str], set[str]]:
    """Parse a Test262 config's [features] section.

    Returns ``(runs, skips)`` where:

    - ``runs``  — features the external config runs (bare token, or ``=<non-skip>``).
    - ``skips`` — features the external config explicitly marks as skipped
                  (``feature=skip``, case-insensitive).

    Inline comments (``#`` and ``//``) and blank lines are stripped.
    Parsing stops at the next ``[…]`` section header.
    """
    runs: set[str] = set()
    skips: set[str] = set()
    in_features = False
    for raw_line in text.splitlines():
        line = raw_line.strip()
        # Strip inline comments
        for comment_char in ("#", "//"):
            idx = line.find(comment_char)
            if idx != -1:
                line = line[:idx].strip()
        if not line:
            continue
        if line.startswith("["):
            in_features = line.lower() in ("[features]", "[ features ]")
            continue
        if not in_features:
            continue
        if "=" in line:
            name, _, value = line.partition("=")
            name = name.strip()
            if not name:
                continue
            if value.strip().lower() == "skip":
                skips.add(name)
            else:
                # Other values (e.g., =enabled, =on) — treat as runs.
                runs.add(name)
        else:
            runs.add(line)
    return runs, skips


def build_report(
    our_skip: set[str],
    ext_runs: set[str],
    ext_skips: set[str],
    ext_config_label: str,
    now_iso: str | None = None,
) -> str:
    """Return a Markdown feature-gap report."""
    now_iso = now_iso or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Features the external config runs that we skip — highest planning value.
    we_skip_they_run = sorted(our_skip & ext_runs)
    # Features we skip that the external config explicitly marks as skipped.
    both_explicitly_skip = sorted(our_skip & ext_skips)
    # Features we skip that the external config doesn't mention at all.
    we_skip_unmentioned = sorted(our_skip - ext_runs - ext_skips)
    # Features the external config runs that aren't in our skip list.
    ext_only = sorted(ext_runs - our_skip)

    lines: list[str] = []
    lines.append("# Test262 Feature Gap Report\n")
    lines.append(
        "> **This report is non-authoritative.**  It compares skip metadata lists; "
        "it does not execute tests or measure pass rates.  "
        "Authoritative conformance figures come from CI Test262 artifacts "
        "(see `make test262-report` and `docs/TEST262.md`).\n"
    )
    lines.append(f"Generated: {now_iso}  ")
    lines.append(f"External config: `{ext_config_label}`  ")
    lines.append(f"Our skip metadata: `scripts/test262_skip_metadata.json`  \n")

    # Section 1 — planning priorities
    lines.append(
        f"## Features we skip that the external config runs ({len(we_skip_they_run)})\n"
    )
    lines.append(
        "These are implementation gaps relative to the external config.  "
        "Use as a planning signal only — the external config may have its own "
        "limitations or different test coverage.\n"
    )
    if we_skip_they_run:
        for f in we_skip_they_run:
            lines.append(f"- `{f}`")
    else:
        lines.append("*(none)*")
    lines.append("")

    # Section 2 — features we skip that external also doesn't run
    n_not_run = len(both_explicitly_skip) + len(we_skip_unmentioned)
    lines.append(f"## Features we skip that the external config does not run ({n_not_run})\n")

    lines.append(
        f"### Explicitly skipped by the external config ({len(both_explicitly_skip)})\n"
    )
    if both_explicitly_skip:
        for f in both_explicitly_skip:
            lines.append(f"- `{f}`")
    else:
        lines.append("*(none)*")
    lines.append("")

    lines.append(
        f"### Not mentioned in the external config ({len(we_skip_unmentioned)})\n"
    )
    lines.append(
        "May be unimplemented, differently handled, or out of scope for the external config.\n"
    )
    if we_skip_unmentioned:
        for f in we_skip_unmentioned:
            lines.append(f"- `{f}`")
    else:
        lines.append("*(none)*")
    lines.append("")

    # Section 3 — no gap
    lines.append(
        f"## Features the external config runs that we also run ({len(ext_only)})\n"
    )
    lines.append(
        "These features are not in our skip list, so both configs run their tests.\n"
    )
    if ext_only:
        for f in ext_only:
            lines.append(f"- `{f}`")
    else:
        lines.append("*(none)*")
    lines.append("")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--ext-config",
        required=True,
        metavar="FILE",
        help="External Test262 config file with a [features] section",
    )
    parser.add_argument(
        "--metadata",
        default=str(pathlib.Path(__file__).parent / "test262_skip_metadata.json"),
        metavar="FILE",
        help="Path to test262_skip_metadata.json (default: scripts/test262_skip_metadata.json)",
    )
    parser.add_argument(
        "--output",
        metavar="FILE",
        help="Write Markdown report to this file (default: stdout)",
    )
    args = parser.parse_args()

    ext_path = pathlib.Path(args.ext_config)
    if not ext_path.exists():
        print(f"error: external config not found: {ext_path}", file=sys.stderr)
        return 1

    meta_path = pathlib.Path(args.metadata)
    if not meta_path.exists():
        print(f"error: skip metadata not found: {meta_path}", file=sys.stderr)
        return 1

    ext_runs, ext_skips = parse_features_config(ext_path.read_text(encoding="utf-8"))
    data = json.loads(meta_path.read_text(encoding="utf-8"))
    our_skip = set(data.get("skip_features", []))

    report = build_report(our_skip, ext_runs, ext_skips, str(ext_path))

    if args.output:
        out_path = pathlib.Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(report, encoding="utf-8")
        print(f"Written to {out_path}")
    else:
        print(report, end="")

    return 0


if __name__ == "__main__":
    sys.exit(main())
