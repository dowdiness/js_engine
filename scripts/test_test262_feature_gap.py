"""Tests for test262_feature_gap.py."""

from __future__ import annotations

import pathlib
import sys
import textwrap
import unittest

# Ensure the scripts/ directory is on sys.path so this file can be run from
# either the repo root or the scripts/ directory directly.
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from test262_feature_gap import build_report, parse_features_config

# Small fixture simulating a [features] section from an external Test262 config.
FIXTURE_CONFIG = textwrap.dedent("""\
    # External Test262 config fixture
    [features]
    Array.fromAsync        # ES2024
    async-iteration        # skip in both
    class-fields-private   // both skip
    BigInt                 # both skip
    Promise.allSettled
    regexp-lookbehind      # both skip

    [flags]
    module
""")

# A config with no [features] section.
CONFIG_NO_FEATURES = textwrap.dedent("""\
    [flags]
    module
    async
""")

# A totally empty config.
CONFIG_EMPTY = ""

OUR_SKIP = {
    "async-iteration",
    "BigInt",
    "class-fields-private",
    "regexp-lookbehind",
    "Temporal",       # only in our skip, not in external config
    "WeakRef",        # only in our skip, not in external config
}


class TestParseFeatures(unittest.TestCase):
    def test_parses_features_section(self) -> None:
        result = parse_features_config(FIXTURE_CONFIG)
        self.assertIn("async-iteration", result)
        self.assertIn("class-fields-private", result)
        self.assertIn("BigInt", result)
        self.assertIn("Promise.allSettled", result)
        self.assertIn("Array.fromAsync", result)
        self.assertIn("regexp-lookbehind", result)

    def test_strips_inline_hash_comments(self) -> None:
        result = parse_features_config(FIXTURE_CONFIG)
        # "Array.fromAsync        # ES2024" → "Array.fromAsync"
        self.assertIn("Array.fromAsync", result)
        self.assertNotIn("Array.fromAsync        # ES2024", result)

    def test_strips_inline_slash_comments(self) -> None:
        result = parse_features_config(FIXTURE_CONFIG)
        # "class-fields-private   // both skip" → "class-fields-private"
        self.assertIn("class-fields-private", result)

    def test_stops_at_next_section(self) -> None:
        result = parse_features_config(FIXTURE_CONFIG)
        # [flags] section items should not appear
        self.assertNotIn("module", result)

    def test_empty_config_returns_empty_set(self) -> None:
        self.assertEqual(parse_features_config(CONFIG_EMPTY), set())

    def test_no_features_section_returns_empty_set(self) -> None:
        self.assertEqual(parse_features_config(CONFIG_NO_FEATURES), set())

    def test_blank_lines_ignored(self) -> None:
        # Blank line between entries shouldn't produce empty-string feature.
        result = parse_features_config(FIXTURE_CONFIG)
        self.assertNotIn("", result)

    def test_case_sensitive(self) -> None:
        # Feature names are case-sensitive in Test262 metadata.
        result = parse_features_config("[features]\nBigInt\nbigint\n")
        self.assertIn("BigInt", result)
        self.assertIn("bigint", result)


class TestBuildReport(unittest.TestCase):
    def _report(self, ext_features: set[str]) -> str:
        return build_report(
            OUR_SKIP, ext_features, "fixture.ini", now_iso="2026-01-01T00:00:00Z"
        )

    def test_we_skip_they_run_section(self) -> None:
        # async-iteration, class-fields-private, BigInt, regexp-lookbehind all
        # appear in both OUR_SKIP and the fixture ext_features, so they belong
        # in "both skip", not "we skip they run". Only Temporal/WeakRef are
        # purely ours.
        ext = {"async-iteration", "class-fields-private", "BigInt"}
        # Temporal and WeakRef in OUR_SKIP but NOT in ext → "we skip they run"
        # would be empty because we're comparing OUR_SKIP ∩ ext (they run what we skip)
        # Actually: "we skip they run" = OUR_SKIP ∩ ext_features
        # So ext={"async-iteration"...} means those are "we skip AND they run"
        report = build_report(
            OUR_SKIP, ext, "fixture.ini", now_iso="2026-01-01T00:00:00Z"
        )
        self.assertIn("async-iteration", report)
        self.assertIn("class-fields-private", report)

    def test_non_authoritative_disclaimer_present(self) -> None:
        report = self._report({"async-iteration"})
        self.assertIn("non-authoritative", report)
        self.assertIn("does not execute tests", report)

    def test_ext_config_label_in_report(self) -> None:
        report = self._report(set())
        self.assertIn("fixture.ini", report)

    def test_generated_timestamp_present(self) -> None:
        report = self._report(set())
        self.assertIn("2026-01-01T00:00:00Z", report)

    def test_counts_in_section_headers(self) -> None:
        ext = {"async-iteration", "BigInt"}  # both in OUR_SKIP → "we skip they run"
        report = build_report(
            OUR_SKIP, ext, "fixture.ini", now_iso="2026-01-01T00:00:00Z"
        )
        # "we skip they run" = OUR_SKIP ∩ ext = {async-iteration, BigInt}
        self.assertIn("(2)", report)

    def test_empty_ext_config(self) -> None:
        report = self._report(set())
        self.assertIn("*(none)*", report)

    def test_no_conformance_numbers_in_output(self) -> None:
        # The report must not emit numeric conformance data.
        report = self._report({"async-iteration"})
        for banned in ("P/E", "P/D", "Passed / Executed", "Passed / Discovered"):
            self.assertNotIn(banned, report)
        # No percentage figures in the data body (the disclaimer may mention
        # "pass rates" as a concept but must not print numeric values).
        import re
        self.assertIsNone(re.search(r"\d+\.\d+%", report))


if __name__ == "__main__":
    unittest.main()
