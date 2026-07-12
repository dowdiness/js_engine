# Plan 005: Unify native tooling command tokenization

> **Executor instructions**: Follow the contract-first and test-first sequence.
> Do not add shell execution or expansion. Stop if package dependency direction
> cannot stay clean. Update this plan's row in `plans/README.md` when complete.
>
> **Drift check (run first)**:
> `git diff --stat f806f28..HEAD -- tooling/test262_runner/runtime.mbt tooling/test262_runner/runner_wbtest.mbt tooling/test262_runner/moon.pkg tooling/subprocess_helpers/bench_focus.mbt tooling/subprocess_helpers/bench_focus_wbtest.mbt tooling/subprocess_helpers/moon.pkg`
> Re-read both tokenizers on any drift.

## Status

- **Priority**: P2
- **Effort**: S–M
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug, tech-debt
- **Planned at**: commit `f806f28`, 2026-07-13

## Why this matters

The Test262 runner and benchmark/report tooling independently tokenize command
strings before calling the safe argv-based process API. Their semantics differ:
the runner consumes backslashes inside single quotes, while the helper follows
POSIX-like single-quote preservation and selective double-quote escaping. A
quoted engine path or argument can therefore reach a different argv depending
on which tool invokes it. One shared, tested tokenizer removes the divergence
without introducing a shell.

## Current state

- `tooling/test262_runner/runtime.mbt:2-53` defines private `shlex_split`.
  At `:12-20`, backslash escapes the next character under either quote type.
- `tooling/test262_runner/runtime.mbt:266` uses it to parse the configured
  `--engine` command before launching tests.
- `tooling/subprocess_helpers/bench_focus.mbt:162-224` defines another private
  `shlex_split`. At `:176-187`, escapes are special only in double quotes and
  only before `"`, `\`, `$`, backtick, or newline.
- `tooling/subprocess_helpers/bench_focus.mbt:231` uses it before argv-based
  process execution.
- `tooling/subprocess_helpers/bench_focus_wbtest.mbt:22-25` has one quoted-command
  test; the Test262 runner has no direct tokenizer contract test.
- Both packages are native-only. `tooling/test262_runner/moon.pkg` does not
  import `tooling/subprocess_helpers`; the latter has broader async/http/process
  dependencies, so dependency cost and cycles must be checked before reuse.
- Process launch itself already uses argument arrays and must remain shell-free.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Caller audit | `grep -R -n 'shlex_split(' tooling/test262_runner tooling/subprocess_helpers` | exactly two definitions and their known callers before migration |
| Runner tests | `moon test --target native tooling/test262_runner` | all pass |
| Helper tests | `moon test --target native tooling/subprocess_helpers` | all pass |
| Typecheck after each edit | `moon check` | exit 0 |
| Full tests | `moon test` | exit 0 |
| Interfaces/format | `moon info && moon fmt && moon check` | all exit 0; interface changes reviewed |

## Suggested executor toolkit

- Use `skill://moonbit-agent-guide` and `skill://moonbit-verification` if
  available.
- Use `moon ide` for callsites when it recognizes native-only tooling packages;
  otherwise record the IDE failure and use a tightly scoped content search.

## Scope

**In scope**:

- `tooling/test262_runner/runtime.mbt`
- `tooling/test262_runner/runner_wbtest.mbt`
- `tooling/test262_runner/moon.pkg`
- `tooling/subprocess_helpers/bench_focus.mbt`
- `tooling/subprocess_helpers/bench_focus_wbtest.mbt`
- `tooling/subprocess_helpers/moon.pkg`
- A new focused test/source file inside `tooling/subprocess_helpers/` if moving
  the tokenizer out of the benchmark file improves responsibility.
- Generated interfaces produced by `moon info`, never hand-edited.

**Out of scope**:

- Changing process-launch APIs, engine command configuration, CLI flags, or
  benchmark behavior beyond tokenization parity.
- Shell expansion, environment-variable expansion, globbing, command
  substitution, redirection, or pipelines.
- Windows `cmd.exe`/PowerShell grammar unless existing documented requirements
  explicitly demand it.
- Creating a new package without stopping for boundary review.
- General CLI-parser consolidation.

## Git workflow

- Branch: `refactor/tooling-command-tokenizer`.
- Prefer separate commits if the shared helper extraction and caller migration
  are independently reviewable: `refactor(tooling): centralize command tokenization`
  followed by `test(tooling): pin command tokenization contract` only when tests
  remain green per commit. Otherwise use one focused refactor commit.
- Do not push/open a PR unless instructed.

## Steps

### Step 1: Audit callers, targets, and package dependencies

1. Enumerate every tokenizer definition/caller and the possible command-string
   origins. Confirm both callers receive trusted configuration strings, not
   already-tokenized arrays.
2. Inspect `moon.pkg` dependencies for both packages and every current importer
   of `tooling/subprocess_helpers`.
3. Determine whether importing `subprocess_helpers` into `test262_runner` creates
   a cycle, pulls an incompatible target, or adds disproportionate dependencies.
4. State assumptions in at most three lines: tokenization is POSIX shell-word
   splitting only; no expansion/execution occurs; both consumers need identical
   argv.

**Verify**: draw the before/after package edge. Preferred path: expose one
function from the existing `tooling/subprocess_helpers` package and import it in
the runner. If the broad package causes a cycle or unacceptable coupling, STOP;
do not invent a new package without review.

### Step 2: Define the shared observable contract

Write a short contract in the shared helper's doc comment and map each case to
expected argv:

1. Spaces/tabs/newlines separate unquoted words.
2. Empty single- or double-quoted text creates an empty argument.
3. Adjacent quoted and unquoted segments concatenate into one argument.
4. Backslashes inside single quotes are literal.
5. Inside double quotes, backslash is special only for the agreed POSIX set.
6. Outside quotes, backslash quotes the next character.
7. A trailing unquoted backslash follows the existing chosen behavior; pin it
   explicitly rather than guessing.
8. Unmatched single or double quote raises a catchable failure with stable error
   class, not necessarily stable prose.
9. No `$`, backtick, wildcard, or redirection expansion occurs.

If repository docs establish a non-POSIX contract, STOP and reconcile before
writing tests.

### Step 3: Add failing parity tests before moving code

Add the full matrix to the canonical helper whitebox tests. Add runner-facing
characterization tests that exercise engine command parsing through the nearest
available configuration/runner boundary, not a copied private tokenizer test.
At minimum, the single-quoted backslash case must demonstrate the current
behavioral mismatch.

Use `json_inspect` for argv arrays and `Result` assertions for unmatched quotes.

**Verify before implementation**:

- `moon test --target native tooling/subprocess_helpers`
- `moon test --target native tooling/test262_runner`

Expected: canonical/helper tests reflect the chosen contract; at least one
runner parity test fails because its local parser consumes a literal backslash.
If no consumer-level seam exists without launching a process, use a whitebox
runner test but state why.

### Step 4: Extract and expose one helper

Within `tooling/subprocess_helpers`:

- Move the tokenizer into a cohesive source block/file independent of benchmark
  state.
- Give it a descriptive snake_case public name that states it splits a command
  string into argv; do not call it a shell executor.
- Preserve catchable unmatched-quote failure.
- Keep the implementation allocation-conscious: one output array and one
  reusable builder; no regex, intermediate substring array, or shell process.
- Delete the private benchmark copy and migrate its caller.

**Verify immediately after each edited source file**: `moon check` before editing
another source file. Then run helper package tests.

### Step 5: Migrate the Test262 runner

- Add the existing helper-package import with a clear alias.
- Replace the local tokenizer call with the shared API.
- Delete the runner's duplicate implementation completely; leave no alias or
  compatibility wrapper.
- Preserve existing validation for empty engine command and process argv.

**Verify immediately after each file edit**: `moon check`. Then run runner and
helper focused native tests. Expected: all parity cases pass.

### Step 6: Prove clean cutover and no scope expansion

1. Search both packages for the old private name and duplicated quote-state
   implementation. Exactly one canonical implementation should remain.
2. Inspect process calls to confirm no shell invocation was added.
3. Run both focused native package suites.
4. Run `moon test`.

Expected: identical tokenization contract for both consumers and unchanged
process execution mechanism.

### Step 7: Finalize interfaces and formatting

Run:

1. `moon info`; review generated interface diffs. The shared helper's exposure is
   intentional only to direct dependents; do not use `pub(all)` without need.
2. `moon fmt`.
3. `moon check`.
4. Re-run both focused native package tests.
5. `moon test`.
6. `git diff --check` and verify only in-scope files changed.

## Test plan

Use table-style cases or compact grouped `json_inspect` assertions for the nine
contract categories. Include commands with spaces, empty args, concatenated
segments, literal single-quote backslashes, selective double-quote escapes,
unquoted escapes, trailing backslash, both unmatched quote types, and literal
shell metacharacters. Test both the helper and a runner-facing parse boundary so
future callers cannot silently reintroduce a local variant.

## Done criteria

- [ ] Caller/type/dependency audit and three-line assumptions are recorded.
- [ ] A runner parity test demonstrates the pre-fix single-quote/backslash defect.
- [ ] One documented tokenizer implementation serves both consumers.
- [ ] Both duplicate private implementations and wrappers are removed.
- [ ] The contract covers all nine named quote/escape/error cases.
- [ ] No shell execution or expansion was introduced.
- [ ] Focused native package tests and `moon test` pass.
- [ ] `moon info` interface changes are minimal and reviewed.
- [ ] `moon fmt`, final `moon check`, and `git diff --check` pass.
- [ ] Only in-scope files changed and the plan index status is updated.

## STOP conditions

Stop and report if:

- Existing documentation or callers require non-POSIX/Windows command grammar.
- Importing `tooling/subprocess_helpers` creates a cycle, incompatible target,
  or unacceptable dependency fan-out.
- A shared implementation requires a new package to preserve boundaries.
- The runner accepts an argv array elsewhere, making string tokenization
  removable rather than shareable; propose that cleaner contract for review.
- A source file cannot pass `moon check` before the next source edit.
- A focused test fails twice after a reasonable correction.

## Maintenance notes

Keep tokenization separate from execution. New tooling should prefer explicit
argv at API boundaries; command-string splitting exists only for user-facing
configuration that cannot supply arrays. Reviewers should reject new local
quote parsers and any attempt to “complete” this helper into a shell.
