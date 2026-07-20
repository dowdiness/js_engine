# Releasing

Short checklist for cutting a new version. `tagpr` creates and updates the
release PR, bumps the release metadata, creates the tag, and creates the GitHub
Release. Conformance numbers and Mooncakes publication remain human-reviewed.

## One-time repository setup

Before enabling `.github/workflows/tagpr.yml`, a repository administrator must:

1. Set **Settings → Actions → General → Workflow permissions** to
   **Read and write permissions**, and enable **Allow GitHub Actions to create
   and approve pull requests**.
2. Protect `main` so the complete test262 workflow is a required, up-to-date
   check before a release PR can merge. tagpr creates the tag immediately after
   that merge, so this gate is the protection against tagging an unverified tip.

The workflow needs only `contents: write`, `pull-requests: write`, and
`issues: read`. The third-party action is pinned to an immutable commit SHA.
Configure the `Release PR / release_metadata` check as required for `main` as
well; it runs only for pull requests carrying tagpr's `tagpr` label.

## 1. Merge release-candidate PRs

Everything intended for the release must be in `main`. Each push causes tagpr to
create or update one release PR. It bumps `moon.mod` and runs
`scripts/sync_release_version.sh` to update only the js_engine dependency in
`integration/external_consumer/moon.mod`. The release-PR CI rejects a missing
CHANGELOG heading or a version mismatch before it can merge.

## 2. Wait for test262 CI on `main`

The release PR must contain a conformance block from the latest successful
`main` run. tagpr is configured not to generate a generic changelog.

```bash
gh run list --workflow=test262.yml --branch main --status success --limit 1
```

If it is still running, wait. If it failed, fix and re-merge.

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

Review the generated version changes, the external-consumer dependency, and the
hand-written release notes. Do **not** merge while the required checks are
running or failing.

## 4. Merge the release PR

Once its required, up-to-date checks pass, merge the tagpr release PR. tagpr
then creates the annotated `vX.Y.Z` tag and GitHub Release. Keep the GitHub
Release summary short — CHANGELOG is the canonical, editable record.

## 5. Re-verify numbers on the release tip

This is the step that catches release-prep vs. release-tip drift (see v0.2.0: CHANGELOG pinned 86.6% / 85.0% from a pre-release CI run, while CI on the actual tagged commit reported 86.7% / 85.1% — a one-point drift nobody noticed until later).

After the release-PR merge triggers a fresh test262 run on the release commit:

```bash
gh run list --workflow=test262.yml --branch main --status success --limit 1
# grab the run ID for the release commit
make test262-report ARGS="--format=changelog --run <run-id>"
```

If any number in the CHANGELOG differs from this output, amend the CHANGELOG in a follow-up commit (do **not** retag; the tag annotation is allowed to be one point stale, but the CHANGELOG file is not).

Also refresh the README conformance table from the same run:

```bash
make test262-report ARGS="--format=readme --run <run-id>"
```

Paste the output into `README.mbt.md` under the `## Conformance` section, replacing the old block.

## 6. Publish to mooncakes

The GitHub release is **not** the publish — mooncakes is a separate step, and it is the one that's easy to forget (v0.3.0 shipped on GitHub on 2026-06-09 while mooncakes sat at 0.2.3 until the next day). A mooncakes version is permanently immutable once published: no re-publish, only yank-and-bump.

1. Check out the release tag so the published bundle matches it exactly:

   ```bash
   git checkout vX.Y.Z
   ```

   Never publish from a tip that has moved past the tag. The registry records a checksum per version forever; a bundle that doesn't match the tag cannot be fixed retroactively.

2. Dry-run and inspect the bundle:

   ```bash
   moon publish --dry-run
   ```

   Trust the `Server status: 2xx` line, not the shell exit code — the dry-run can exit 255 even on success.

3. Publish, then verify the registry picked it up:

   ```bash
   moon publish
   curl -s https://mooncakes.io/api/v0/modules/dowdiness/js_engine | head -c 400
   ```

   `latest_version` must show the new version. Return your checkout to `main` afterwards.

## Anti-drift rules

- **Conformance numbers come from `make test262-report` (native `cmd/report_test262`), never from another doc.** See `AGENTS.md` "Test262 Reporting Convention" for why.
- **Always per-mode, always both denominators.** The `--format=changelog` template already enforces this; do not edit the bullets to omit one denominator.
- **If a release annotation and the CHANGELOG disagree on a number, trust the CHANGELOG.** The tag is frozen at creation; the file is the living record.
