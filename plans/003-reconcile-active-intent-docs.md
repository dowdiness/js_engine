# Plan 003: Reconcile active intent docs with shipped feature state

> **Executor instructions**: Follow the source-verification sequence before
> editing prose. Never infer support from a commit title or stale result file.
> Stop on any conflict described below. Update this plan's status row in
> `plans/README.md` when done.
>
> **Drift check (run first)**:
> `git diff --stat f806f28..HEAD -- docs/agent-todo.md docs/ROADMAP.md docs/supported-features.md scripts/test262_skip_metadata.json README.mbt.md`
> If active claims or skip metadata changed, re-establish the facts before using
> this plan.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs
- **Planned at**: commit `f806f28`, 2026-07-13

## Why this matters

The active agent queue and roadmap still describe async iteration as blanket-
skipped and lookbehind/private classes as unimplemented feature projects. The
authoritative skip metadata no longer contains those feature flags; async
iteration now has targeted path exceptions instead. Active intent docs direct
future maintainers and agents, so stale “not implemented” text causes duplicate
work and hides the actual remaining failure cohorts.

## Current state

- `docs/agent-todo.md:7-13` already requires reproduction, exact Test262 `info`,
  narrow fixes, and benchmark-first performance work. Preserve these rules.
- `docs/agent-todo.md:75-85` marks for-await/async iteration done but says the
  `async-iteration` feature remains skipped. Current metadata contradicts the
  blanket-skip claim.
- `docs/agent-todo.md:87-96` presents lookbehind implementation as future work.
- `docs/agent-todo.md:112-119` presents private class parsing/brands/storage as
  wholly unimplemented.
- `docs/ROADMAP.md:64-75` calls private classes, async iteration, and RegExp
  lookbehind major skipped-feature buckets and describes implementation as the
  current direction.
- `scripts/test262_skip_metadata.json:3-40` is the authoritative shared feature
  skip list; it contains none of `async-iteration`, `regexp-lookbehind`, or the
  private-class feature tags at `f806f28`.
- `scripts/test262_skip_metadata.json:46-193` retains 146 path-specific async
  generator/destructuring exceptions plus one legacy-spec exception. These are
  the concrete async follow-up cohort.
- `README.mbt.md:81-127` and `docs/ROADMAP.md:7-26` contain generated CI-derived
  conformance blocks. Never hand-edit their numbers.
- Completed or superseded material belongs under `docs/archive/`; active docs
  should contain only unresolved work.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Validate skip metadata | `make test262-validate-skips` | exit 0; no unknown/dead metadata entries |
| Generate current report | `make test262-report ARGS='--format=table'` | exit 0; paste-ready CI-derived output, no hand calculations |
| Locate stale claims | `grep -nE 'async-iteration|regexp-lookbehind|class-fields-private|class-methods-private|static-block|Large skipped-feature bucket|not (yet )?implemented' docs/agent-todo.md docs/ROADMAP.md docs/supported-features.md` | after edits, only historically/accurately qualified matches remain |
| Documentation typecheck | `moon check` | exit 0 |
| Full docs examples/tests | `moon test` | exit 0 |
| Format/interfaces | `moon info && moon fmt && moon check` | all exit 0; no API change expected |

## Scope

**In scope**:

- `docs/agent-todo.md` — remove/archive shipped tasks and state precise remaining
  cohorts.
- `docs/ROADMAP.md` — update current priorities and feature-bucket wording.
- `docs/supported-features.md` — only if its dated-snapshot explanation or active
  links become factually inconsistent after the other edits.
- `docs/archive/agent-todo-history.md` — only if completed detail must be moved
  rather than deleted; preserve the archive warning/index convention.
- `docs/README.md` — only if moving content changes an index link.

**Read-only sources of truth**:

- `scripts/test262_skip_metadata.json`
- Current implementation/tests and generated CI report output.
- Latest successful `.github/workflows/test262.yml` run and its raw artifacts.

**Out of scope**:

- Source, tests, skip policy, or workflow changes.
- Hand-editing conformance numbers or claiming support from local result JSON.
- Rewriting dated historical snapshots to look current.
- Declaring a feature complete merely because its blanket skip was removed.
- Adding new roadmap features not supported by code, CI, issues, or design docs.

## Git workflow

- Branch: `docs/reconcile-feature-state`.
- One docs-only commit: `docs: reconcile active feature roadmap`.
- Do not push/open a PR unless instructed.

## Steps

### Step 1: Establish current facts from authoritative sources

1. Run `make test262-validate-skips`.
2. Run `make test262-report ARGS='--format=table'` and retain its output for
   verification; do not paste numbers into docs unless a generated block is
   explicitly being refreshed.
3. Inspect implementation and targeted tests for async iteration, RegExp
   lookbehind, and private classes. Record what exists and what remains missing.
4. Inspect the latest successful main-branch Test262 workflow artifacts. Report
   strict and non-strict separately, with both Passed/Executed and
   Passed/Discovered if any number is cited.
5. Count current path-specific exceptions by rationale from the shared metadata.
6. State assumptions in at most three lines: metadata is the skip source of
   truth; code/tests determine implementation state; CI artifacts determine
   conformance numbers.

**Verify**: each planned prose claim has one named source. If code, metadata, and
latest CI disagree, stop and report the disagreement instead of choosing one.

### Step 2: Reconcile `docs/agent-todo.md`

For each affected section:

- Move completed implementation narrative to
  `docs/archive/agent-todo-history.md` if it remains useful; otherwise delete
  derivable details.
- Replace the async blanket-skip statement with the current targeted exception
  cohort and the exact next validation objective. Do not claim all async
  iteration passes.
- Remove lookbehind as an unimplemented task. If current CI still has lookbehind
  failures, describe only the verified remaining cases.
- Replace the wholly-unimplemented private-class checklist with verified gaps,
  or remove the section if no AI-sized unresolved task can be stated honestly.
- Keep active tasks small and reproducible, matching the file's own rules.

**Verify after this file edit**: `moon check` → exit 0 before editing another
file. Then run the stale-claim search against `docs/agent-todo.md`; every match
must be accurate in present tense or explicitly historical.

### Step 3: Reconcile `docs/ROADMAP.md`

Update “Close large skipped-feature buckets” so its table matches current skip
policy and implementation state:

- Do not label a removed blanket feature flag as a current skipped bucket.
- Distinguish broad feature skip, targeted path exceptions, and executed-but-
failing tests.
- Keep BigInt, Temporal, Unicode property escapes, and other still-present
  feature skips only when confirmed in current metadata.
- For partially shipped private or async behavior, state the concrete remaining
  cohort and user/spec value without repeating completed implementation steps.
- Preserve the generated conformance block and its reporting-methodology rules.

**Verify after this file edit**: `moon check` → exit 0. Run the stale-claim search
against both active docs. Expected: no unqualified claim that shipped syntax is
wholly unimplemented or blanket-skipped.

### Step 4: Repair archive/index links only if needed

If Step 2 moved material:

- Add it to the existing historical section structure rather than creating a new
  root history file.
- Preserve the archive convention warning that historical files should not be
  read unless historical context is requested.
- Update `docs/README.md` links only when a live link changed.

Run `moon check` after each edited file before touching the next one.

### Step 5: Validate claims and generated-data discipline

1. Compare every changed factual sentence with its source recorded in Step 1.
2. Confirm no Test262 number was manually derived or copied from stale docs.
3. If a generated table needs refreshing, use only `make test262-report` output
   from the identified successful run and retain its run/SHA/date attribution.
4. Run `make test262-validate-skips` again.
5. Run the stale-claim search and manually classify every remaining match.

Expected: active docs describe current work; historical/datetime-qualified text
remains clearly labeled.

### Step 6: Final verification

Run:

1. `moon check`
2. `moon test`
3. `moon info`; expect no generated-interface semantic change.
4. `moon fmt`
5. `moon check`
6. Review `git diff --check` and confirm only in-scope documentation/archive
   files changed.

## Test plan

This is a source-backed docs change. Its behavioral checks are metadata
validation, current CI report generation, live-link/stale-phrase searches, and
MoonBit documentation/example checks. No source-text unit test should be added.
The executor must retain the report command output and metadata-validation result
as review evidence.

## Done criteria

- [ ] Current code, metadata, and latest successful CI artifacts were inspected.
- [ ] Assumptions are recorded in three lines or fewer.
- [ ] `docs/agent-todo.md` contains no obsolete blanket-skip or wholly-
      unimplemented claim for async iteration, lookbehind, or shipped private
      class work.
- [ ] `docs/ROADMAP.md` distinguishes feature skips, path skips, and executed
      failures using current sources.
- [ ] Completed detail is archived or removed according to repository convention.
- [ ] No generated/frequently changing Test262 number was hand-edited.
- [ ] `make test262-validate-skips`, `moon check`, and `moon test` pass.
- [ ] `moon info` shows no unintended API change; `moon fmt` and `git diff --check`
      pass.
- [ ] Only in-scope docs changed and `plans/README.md` status is updated.

## STOP conditions

Stop and report if:

- Latest successful main-branch CI artifacts are unavailable for a numerical
  claim that must change.
- Code, tests, metadata, or CI disagree on whether a feature is executed,
  skipped, or passing.
- An active roadmap statement depends on issue/PR intent that cannot be verified.
- A generated conformance block would need manual arithmetic.
- The change expands into source, skip-policy, or workflow behavior.
- A verification command fails twice after a reasonable correction.

## Maintenance notes

Blanket feature removal does not mean full conformance. Future docs should name
the remaining failure or path-exception cohort and its source. At each feature
merge, update active intent docs in the same PR or archive completed material;
do not leave a TODO as a second, stale source of truth. Reviewers must enforce
per-mode reporting with both denominators whenever conformance figures appear.
