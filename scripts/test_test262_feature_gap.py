"""Tests for test262_feature_gap.py."""

from __future__ import annotations

import pathlib
import re
import sys
import textwrap
import unittest

# Ensure the scripts/ directory is on sys.path so this file can be run from
# either the repo root or the scripts/ directory directly.
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from test262_feature_gap import build_report, parse_features_config

# Small fixture simulating a [features] section from an external Test262 config
# that uses both bare tokens (external runs) and token=skip (external skips).
FIXTURE_CONFIG = textwrap.dedent("""\
    # External Test262 config fixture
    [features]
    Array.fromAsync        # external runs this
    async-iteration=skip   # external explicitly skips
    class-fields-private=skip  // external explicitly skips
    BigInt=skip            # external explicitly skips — was the P2 bug
    Promise.allSettled     # external runs this
    regexp-lookbehind=skip # external explicitly skips

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
    def test_parses_bare_tokens_into_runs(self) -> None:
        runs, _ = parse_features_config(FIXTURE_CONFIG)
        self.assertIn("Array.fromAsync", runs)
        self.assertIn("Promise.allSettled", runs)

    def test_skip_marker_excluded_from_runs(self) -> None:
        # BigInt=skip must NOT appear in runs — this was the P2 bug.
        runs, _ = parse_features_config(FIXTURE_CONFIG)
        self.assertNotIn("BigInt", runs)
        self.assertNotIn("BigInt=skip", runs)

    def test_skip_marker_included_in_skips(self) -> None:
        # BigInt=skip must appear in skips with the bare feature name.
        _, skips = parse_features_config(FIXTURE_CONFIG)
        self.assertIn("BigInt", skips)
        self.assertIn("async-iteration", skips)
        self.assertIn("class-fields-private", skips)
        self.assertIn("regexp-lookbehind", skips)

    def test_bare_tokens_not_in_skips(self) -> None:
        _, skips = parse_features_config(FIXTURE_CONFIG)
        self.assertNotIn("Array.fromAsync", skips)
        self.assertNotIn("Promise.allSettled", skips)

    def test_non_skip_value_treated_as_run(self) -> None:
        # A =<value> other than "skip" should not be treated as a skip marker.
        runs, skips = parse_features_config("[features]\nSomeFeature=enabled\n")
        self.assertIn("SomeFeature", runs)
        self.assertNotIn("SomeFeature", skips)

    def test_skip_case_insensitive(self) -> None:
        # "=SKIP", "=Skip", "=skip" should all be treated as explicit skip.
        _, skips = parse_features_config(
            "[features]\nFoo=SKIP\nBar=Skip\nBaz=skip\n"
        )
        self.assertIn("Foo", skips)
        self.assertIn("Bar", skips)
        self.assertIn("Baz", skips)

    def test_strips_inline_hash_comments(self) -> None:
        runs, _ = parse_features_config(FIXTURE_CONFIG)
        # "Array.fromAsync        # external runs this" → "Array.fromAsync"
        self.assertIn("Array.fromAsync", runs)
        self.assertNotIn("Array.fromAsync        # external runs this", runs)

    def test_strips_inline_slash_comments(self) -> None:
        _, skips = parse_features_config(FIXTURE_CONFIG)
        # "class-fields-private=skip  // external explicitly skips" → skip
        self.assertIn("class-fields-private", skips)

    def test_stops_at_next_section(self) -> None:
        runs, skips = parse_features_config(FIXTURE_CONFIG)
        # [flags] section items should not appear in either set.
        self.assertNotIn("module", runs)
        self.assertNotIn("module", skips)

    def test_empty_config_returns_empty_sets(self) -> None:
        runs, skips = parse_features_config(CONFIG_EMPTY)
        self.assertEqual(runs, set())
        self.assertEqual(skips, set())

    def test_no_features_section_returns_empty_sets(self) -> None:
        runs, skips = parse_features_config(CONFIG_NO_FEATURES)
        self.assertEqual(runs, set())
        self.assertEqual(skips, set())

    def test_blank_lines_ignored(self) -> None:
        # Blank line between entries shouldn't produce empty-string feature.
        runs, skips = parse_features_config(FIXTURE_CONFIG)
        self.assertNotIn("", runs)
        self.assertNotIn("", skips)

    def test_case_sensitive_feature_names(self) -> None:
        # Feature names are case-sensitive in Test262 metadata.
        runs, _ = parse_features_config("[features]\nBigInt\nbigint\n")
        self.assertIn("BigInt", runs)
        self.assertIn("bigint", runs)


class TestBuildReport(unittest.TestCase):
    def _report(self, ext_runs: set[str], ext_skips: set[str] | None = None) -> str:
        return build_report(
            OUR_SKIP,
            ext_runs,
            ext_skips or set(),
            "fixture.ini",
            now_iso="2026-01-01T00:00:00Z",
        )

    def test_we_skip_they_run_section(self) -> None:
        # Features in OUR_SKIP that are also in ext_runs belong in
        # "Features we skip that the external config runs".
        ext_runs = {"async-iteration", "class-fields-private", "BigInt"}
        report = self._report(ext_runs)
        self.assertIn("async-iteration", report)
        self.assertIn("class-fields-private", report)
        self.assertIn("BigInt", report)

    def test_skip_marker_appears_in_explicitly_skipped_subsection(self) -> None:
        # BigInt from BigInt=skip should land in "Explicitly skipped by the
        # external config", not in the "ext runs that we also run" section.
        report = self._report(set(), {"BigInt", "async-iteration"})
        self.assertIn("Explicitly skipped by the external config", report)
        self.assertIn("BigInt", report)

    def test_skip_marker_not_counted_in_ext_runs_section(self) -> None:
        # =skip features must not appear under "the external config runs" — this was the bug.
        report = self._report(set(), {"BigInt"})
        # The "Features we skip that the external config runs" section should show (0).
        self.assertIn(
            "Features we skip that the external config runs (0)", report
        )

    def test_unmentioned_features_go_to_not_mentioned_subsection(self) -> None:
        # Temporal and WeakRef are in OUR_SKIP but absent from both ext_runs
        # and ext_skips — they belong in "Not mentioned in the external config".
        report = self._report(set(), set())
        self.assertIn("Not mentioned in the external config", report)
        self.assertIn("Temporal", report)
        self.assertIn("WeakRef", report)

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
        # OUR_SKIP ∩ ext_runs = {async-iteration, BigInt} → (2) in the
        # "we skip they run" header.
        ext_runs = {"async-iteration", "BigInt"}
        report = self._report(ext_runs)
        self.assertIn("(2)", report)

    def test_empty_ext_config_shows_none_placeholder(self) -> None:
        report = self._report(set())
        self.assertIn("*(none)*", report)

    def test_no_conformance_numbers_in_output(self) -> None:
        # The report must not emit numeric conformance data.
        report = self._report({"async-iteration"})
        for banned in ("P/E", "P/D", "Passed / Executed", "Passed / Discovered"):
            self.assertNotIn(banned, report)
        # No percentage figures in the data body (the disclaimer may mention
        # "pass rates" as a concept but must not print numeric values).
        self.assertIsNone(re.search(r"\d+\.\d+%", report))


if __name__ == "__main__":
    unittest.main()
