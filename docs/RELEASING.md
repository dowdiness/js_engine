# Releasing

Short checklist for cutting a new version. The repo has no release automation — releases are human-driven, but the conformance numbers are machine-generated so CHANGELOG entries stay honest.

## 1. Merge all release-candidate PRs

Everything intended for the release must be in `main` before you start. Do **not** rely on the pre-release CI run for final numbers; see step 5.

## 2. Wait for test262 CI to go green on `main`

The test262 workflow runs on every push to `main`. Confirm the most recent run succeeded before proceeding:

```bash
gh run list --workflow=test262.yml --branch main --status success --limit 1
```

If it's still running, wait. If it failed, fix and re-merge.

## 3. Draft the CHANGELOG entry

Generate a paste-ready Conformance block from the latest CI run:

```bash
make test262-report ARGS="--format=changelog"
```

Paste the output into `CHANGELOG.md` under the new version heading's `### Conformance` subsection. The script emits **only** the numeric facts: per-mode Passed/Executed, per-mode Passed/Discovered, the CI run ID, the tip, and the baseline delta. You add:

- **Unit test count**: `moon test 2>&1 | grep -E "Total tests:" | tail -1`
- **Prior-release comparison**: how the absolute passing count moved since the previous version. Be explicit about methodology changes (e.g. v0.1.0 → v0.2.0 crossed the single-mode-to-per-mode runner change at Phase 24 and so rates are not directly comparable).
- **Major capabilities added**, **Spec-correctness sweeps**, **Breaking changes**, **Known limitations** — written by hand, not generated.

Do not hand-edit the generated numbers. If they look wrong, fix the upstream (runner, baseline, classifier), not the release note.

## 4. Bump version and tag

1. Update the version string in `moon.mod.json`.
2. Commit with message `release: vX.Y.Z`.
3. Annotate the tag with a summary of headline facts:

   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z — <one-line theme>"
   ```

   Keep the tag annotation short — it's frozen; CHANGELOG is the canonical, editable record.

4. Push both the commit and tag:

   ```bash
   git push origin main
   git push origin vX.Y.Z
   ```

## 5. Re-verify numbers on the release tip

This is the step that catches release-prep vs. release-tip drift (see v0.2.0: CHANGELOG pinned 86.6% / 85.0% from a pre-release CI run, while CI on the actual tagged commit reported 86.7% / 85.1% — a one-point drift nobody noticed until later).

After the tag push triggers a fresh test262 run on the release commit:

```bash
gh run list --workflow=test262.yml --branch main --status success --limit 1
# grab the run ID for the release commit
make test262-report ARGS="--format=changelog --run <run-id>"
```

If any number in the CHANGELOG differs from this output, amend the CHANGELOG in a follow-up commit (do **not** retag; the tag annotation is allowed to be one point stale, but the CHANGELOG file is not).

## 6. Publish

Mooncakes or wherever else the artifact goes. That step is outside the scope of this file.

## Anti-drift rules

- **Conformance numbers come from `scripts/report-test262.py`, never from another doc.** See `AGENTS.md` "Test262 Reporting Convention" for why.
- **Always per-mode, always both denominators.** The `--format=changelog` template already enforces this; do not edit the bullets to omit one denominator.
- **If a release annotation and the CHANGELOG disagree on a number, trust the CHANGELOG.** The tag is frozen at creation; the file is the living record.
