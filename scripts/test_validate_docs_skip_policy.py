"""Tests for validate_docs_skip_policy.py."""

from __future__ import annotations

import json
import pathlib
import sys
import tempfile
import textwrap
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from validate_docs_skip_policy import validate


MANIFEST = {
    "schema_version": 1,
    "graduated_features": ["async-iteration", "regexp-lookbehind"],
    "active_intent_docs": ["docs/agent-todo.md"],
    "allowed_line_patterns": [
        "no `FEATURE`",
        "not in shared skip metadata",
        "shipped",
        "not claim full FEATURE",
        "FEATURE conformance",
    ],
    "historical_context_markers": ["snapshot", "feature skips included"],
}


class ValidateDocsSkipPolicyTest(unittest.TestCase):
    def test_passes_when_graduated_feature_not_in_skip_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self._write_files(
                root,
                skip_features=["BigInt", "Temporal"],
                doc=textwrap.dedent(
                    """\
                    ### Async iteration

                    There is no `async-iteration` blanket skip.
                    """
                ),
            )
            errors = validate(root, root / "manifest.json", root / "metadata.json")
            self.assertEqual(errors, [])

    def test_fails_when_graduated_feature_reappears_in_skip_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self._write_files(
                root,
                skip_features=["async-iteration", "BigInt"],
                doc="All good here.\n",
            )
            errors = validate(root, root / "manifest.json", root / "metadata.json")
            self.assertEqual(len(errors), 1)
            self.assertIn("skip_features", errors[0])

    def test_fails_on_stale_blanket_skip_claim(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self._write_files(
                root,
                skip_features=["BigInt"],
                doc=textwrap.dedent(
                    """\
                    ## Skipped

                    - **Async iteration**: `async-iteration`, `top-level-await`
                    """
                ),
            )
            errors = validate(root, root / "manifest.json", root / "metadata.json")
            self.assertEqual(len(errors), 1)
            self.assertIn("async-iteration", errors[0])

    def test_allows_historical_snapshot_wording(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self._write_files(
                root,
                skip_features=["BigInt"],
                doc=textwrap.dedent(
                    """\
                    ## Snapshot

                    At the time of this snapshot, feature skips included
                    `async-iteration` and `regexp-lookbehind`.
                    """
                ),
            )
            errors = validate(root, root / "manifest.json", root / "metadata.json")
            self.assertEqual(errors, [])

    def test_allows_conformance_caveat_wording(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self._write_files(
                root,
                skip_features=["BigInt"],
                doc="Do not claim full async-iteration conformance yet.\n",
            )
            errors = validate(root, root / "manifest.json", root / "metadata.json")
            self.assertEqual(errors, [])

    def _write_files(
        self,
        root: pathlib.Path,
        *,
        skip_features: list[str],
        doc: str,
    ) -> None:
        (root / "docs").mkdir()
        (root / "docs/agent-todo.md").write_text(doc, encoding="utf-8")
        (root / "manifest.json").write_text(
            json.dumps(MANIFEST),
            encoding="utf-8",
        )
        (root / "metadata.json").write_text(
            json.dumps({"skip_features": skip_features}),
            encoding="utf-8",
        )


if __name__ == "__main__":
    unittest.main()
