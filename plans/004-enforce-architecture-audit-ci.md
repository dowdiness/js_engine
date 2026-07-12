# Plan 004: Enforce the full architecture audit in CI

> **Executor instructions**: This plan is blocked until plan 002 has restored a
> green local `make architecture-audit`. Follow every verification gate and
> update this plan's row in `plans/README.md` when complete.
>
> **Drift check (run first)**:
> `git diff --stat f806f28..HEAD -- .github/workflows/test262.yml Makefile scripts/architecture_representation_access.json interpreter/stdlib/builtins_json.mbt`
> Re-check the dependency and current CI step if any path changed.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/002-json-stringify-semantic-ops.md`
- **Category**: dx
- **Planned at**: commit `f806f28`, 2026-07-13

## Why this matters

The repository defines a combined architecture gate, but CI invokes only its
mutable-state subset. Current `main` demonstrates the consequence: `moon check`
and all 2,317 unit tests pass while the representation-access audit fails on
new JSON boundary violations. Once plan 002 restores the baseline, CI should run
the same full gate maintainers are required to run locally.

## Current state

- `Makefile:37-45` defines `architecture-state-audit` and its focused tests.
- `Makefile:48-58` defines `architecture-audit` as
  `architecture-state-audit architecture-boundary-audit`; the boundary target
  runs representation-access, import-boundary, and surface-taxonomy checks.
- `.github/workflows/test262.yml:97-109` runs only
  `make architecture-state-audit` before metadata tests and `moon check`/
  `moon test`.
- `docs/design/architecture-redesign-2026-06-12.md:290-318` requires
  `make architecture-audit` and names all boundary scans as guardrails.
- `docs/design/architecture-execution-plan-2026-06-12.md:447-484` says Stage 0
  is done only when new unapproved representation access fails visibly.
- At planning time, the combined command fails only its representation-access
  portion on `interpreter/stdlib/builtins_json.mbt`; therefore wiring it now
  would knowingly redline CI. Plan 002 must land first.
- `.github/workflows/actionlint.yml:19-47` is the workflow-syntax check and is
  triggered for workflow changes.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Dependency gate | `make architecture-audit` | exit 0 before any workflow edit |
| Workflow search | `grep -nE 'Architecture|architecture-(state-)?audit' .github/workflows/test262.yml` | one combined architecture gate, no redundant state-only gate |
| Workflow lint | `actionlint -color` or the repository's documented actionlint invocation | exit 0, no findings |
| YAML parse fallback | `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/test262.yml"))'` | exit 0 only if PyYAML is already installed; do not install it for this plan |
| Typecheck/tests | `moon check && moon test` | both exit 0 |
| Final architecture gate | `make architecture-audit` | exit 0 |

## Scope

**In scope**:

- `.github/workflows/test262.yml` — replace the state-only CI step with the
  combined architecture audit.
- `Makefile` — read-only by default; modify only if the existing combined target
  cannot be called cleanly from CI without duplicate work.

**Read-only dependency evidence**:

- `interpreter/stdlib/builtins_json.mbt`
- `scripts/architecture_representation_access.json`
- Plan 002 completion evidence.

**Out of scope**:

- Fixing or allowlisting architecture violations.
- Changing audit rules, inventories, fingerprints, scanner implementation, or
  architecture design documents.
- Reorganizing the Test262 matrix, caches, permissions, timeouts, or triggers.
- Adding a new workflow when the existing unit-test job already owns this gate.
- Installing new lint dependencies locally.

## Git workflow

- Branch: `ci/enforce-architecture-audit`.
- One focused commit: `ci: run full architecture audit`.
- Do not push/open a PR unless instructed.

## Steps

### Step 1: Prove the dependency is satisfied

1. Verify plan 002 is marked DONE and inspect its architecture-audit evidence.
2. Run `make architecture-audit` yourself on current HEAD.
3. Confirm all four responsibilities pass: mutable state, import boundaries,
   representation access, and surface taxonomy.
4. State assumptions in at most three lines: the Make target is authoritative;
   the existing unit-test job has native tooling prerequisites; the combined
   target does not mutate tracked files.

**Verify**: `make architecture-audit` exits 0. Any failure is an immediate STOP;
do not edit YAML or metadata to bypass it.

### Step 2: Audit workflow call paths and prerequisites

Inspect the `unit-test` job from checkout through the current architecture step.
Confirm:

- MoonBit is on PATH.
- Dependencies are installed before the step.
- Native build artifacts/toolchain are available to both architecture tools.
- Existing permissions remain read-only.
- The workflow cache keys already include relevant MoonBit source/package files.
- No later step depends on the exact current step name.

**Verify**: document the job prerequisites and possible target/runtime types in
the work log. If the boundary audit needs an unavailable system dependency,
stop and report rather than broadening CI setup speculatively.

### Step 3: Write the smallest failing detector check

Before editing the workflow, run a search/assertion showing that the unit-test
job contains `make architecture-state-audit` but not `make architecture-audit`.
This is the plan's pre-change failing contract: CI is not invoking the combined
gate.

Use a read-only script or grep assertion; do not add a source-text unit test to
the repository.

**Verify**: the assertion fails specifically because the combined target is
absent.

### Step 4: Switch the existing CI step to the combined target

In `.github/workflows/test262.yml`:

- Keep the gate in the existing unit-test job before metadata and unit tests.
- Rename the step to “Architecture audit” or an equally explicit combined name.
- Replace the command with `make architecture-audit`.
- Do not leave a separate `make architecture-state-audit`, because the combined
  target already runs it.
- Preserve checkout, caches, permissions, triggers, and all unrelated commands.

**Verify immediately after the file edit**: run `moon check` before any further
file edit. Then run the workflow search. Expected: exactly one combined target
invocation in the unit-test job and no redundant state-only invocation.

### Step 5: Validate workflow syntax and behavior

1. Run `actionlint -color` if the binary is available. If not, use the exact
   installation/invocation documented in `.github/workflows/actionlint.yml`
   only in a disposable location; do not commit binaries.
2. Run `make architecture-audit` locally.
3. Run `moon check` and `moon test`.
4. Inspect the workflow diff to ensure only the step name/command changed.

Expected: every command exits 0 and actionlint reports no YAML/expression/shell
finding.

### Step 6: Finalize

Run:

1. `moon info`; expect no public API change.
2. `moon fmt`; it should not rewrite YAML.
3. `moon check`.
4. `make architecture-audit`.
5. `git diff --check`.
6. Confirm only `.github/workflows/test262.yml` changed unless the pre-approved
   Makefile escape was necessary.

## Test plan

The observable contract is that CI invokes the authoritative combined Make
target. Validate it at three layers: pre/post workflow search, actionlint syntax,
and successful local execution of the exact target. Do not add a brittle test
that parses workflow source in the MoonBit suite.

## Done criteria

- [ ] Plan 002 is complete and `make architecture-audit` was green before YAML
      editing.
- [ ] Caller/prerequisite audit and three-line assumptions are recorded.
- [ ] Pre-change detector proved the combined target was absent.
- [ ] The unit-test job runs `make architecture-audit` exactly once.
- [ ] No redundant state-only audit invocation remains in that job.
- [ ] Workflow permissions, caches, triggers, matrix, and unrelated steps are
      unchanged.
- [ ] Actionlint exits 0.
- [ ] `moon check`, `moon test`, and `make architecture-audit` exit 0.
- [ ] `moon info` shows no API change; `moon fmt` and `git diff --check` pass.
- [ ] Only in-scope files changed and the plan index status is updated.

## STOP conditions

Stop and report if:

- Plan 002 is incomplete or `make architecture-audit` is red for any reason.
- The combined target mutates tracked files or requires secrets/network access.
- CI lacks a native prerequisite and adding it would change caches/toolchain
  setup beyond this one step.
- Making CI green appears to require weakening an audit or expanding an
  allowlist.
- A workflow verification fails twice after a reasonable correction.

## Maintenance notes

The Make target, not duplicated workflow commands, is the source of truth for
architecture guardrails. Future sub-audits should join `architecture-audit` so
local and CI behavior remain identical. Reviewers must reject any change that
replaces the combined gate with a narrower subset for speed without measured CI
data and an explicit architecture decision.
