# Tooling migration contracts

This document is the Phase 0 contract for migrating repository scripts from
Python to MoonBit. It exists to keep the current Python tools authoritative
until MoonBit replacements produce compatible outputs.

Related tracking issues: #249 through #255.

## Principles

1. **Python stays authoritative until parity.** A MoonBit tool may be added as a
   shadow command, but Makefile and CI promotion require explicit parity checks.
2. **Native-only tooling is isolated.** MoonBit script packages that use
   `moonbitlang/async` filesystem or process APIs must declare
   `supported_targets = "+native"`. Do not make the whole interpreter module
   native-only.
3. **No hidden Test262 methodology changes.** The first MoonBit Test262 runner
   must preserve the current external engine subprocess model. An in-process
   runner can be a later optimization only after artifact parity exists.
4. **Strict and non-strict are separate modes.** Test262 files are run per mode;
   reports and artifacts must not sum the modes.
5. **Contracts are data, not prose.** Shared skip metadata and result schemas
   must be parser-stable across Python and MoonBit.

## CLI compatibility contract

Migrated tools must preserve the existing command-line surface until a separate
promotion issue documents a breaking change.

For every migrated command, record and test:

- option names, aliases, default values, and allowed enum values;
- positional argument behavior;
- invalid-argument diagnostics and exit codes;
- `--help` behavior;
- stdout/stderr routing for normal output and errors;
- generated file paths and overwrite/append behavior.

MoonBit package names may use underscores, but user-facing wrappers and Makefile
targets should preserve existing hyphenated tool names.

## Test262 result artifact contract

The machine-readable schema lives at
`scripts/test262_result_contract.schema.json`.

The Test262 runner artifact is a JSON object with these top-level fields:

- `engine`: string, currently `"moonbit-js-engine"`.
- `date`: UTC timestamp string. Parity tools ignore this value.
- `summary`: aggregate run counts.
- `categories`: object keyed by category name.
- `results`: array of per-task result records.
- `methodology`: optional object, present only for modified-harness runs.

### Summary fields

`summary` must contain:

- `total`: discovered expanded tasks in this run;
- `passed`;
- `failed`;
- `skipped`;
- `timeout`;
- `error`;
- `pass_rate`: `passed / (passed + failed) * 100`, rounded to two decimals.

When modified harness helpers are used, `summary.methodology` is the methodology
label string and the top-level `methodology` object contains the structured
metadata.

The executed denominator is always `passed + failed`. Timeouts and runner errors
are tracked separately.

### Category fields

Each category record must contain:

- `total`;
- `passed`;
- `failed`;
- `skipped`;
- `pass_rate`.

The current Python runner does not include per-category `timeout` or `error`
fields, so MoonBit shadow output must not add them to the compatibility artifact.
A future schema version may add fields only after consumers are updated.

### Result fields

Each result record must contain:

- `path`: repository-relative or Test262-root-relative path as emitted by the
  authoritative runner;
- `status`: one of `pass`, `fail`, `skip`, `timeout`, `error`;
- `reason`: string, empty when not applicable;
- `duration_ms`: number rounded to one decimal. Parity tools ignore this value;
- `mode`: `strict` or `non-strict`.

The stable comparison key is `(normalized path, mode)`. Result array order is
not a compatibility guarantee because the Python runner can complete threaded
jobs out of order.

## Status semantics

- `pass`: the test matched the expected outcome.
- `fail`: the engine completed but did not satisfy Test262 expectations.
- `skip`: metadata or path rules excluded the task from execution.
- `timeout`: engine execution exceeded the per-task timeout.
- `error`: runner infrastructure failed before a normal test outcome could be
  determined.

A completed result log may contain all five statuses. Merged logs contain only
`fail`, `timeout`, and `error` records.

## Exit-code contract

For `scripts/test262-runner.py`, the authoritative behavior is:

- invalid CLI arguments exit non-zero through argparse;
- missing Test262 directory, unreadable tests file, missing engine command, or
  unreadable resume/log files exit non-zero;
- after a completed run, any failed tests cause a non-zero exit;
- skips, timeouts, and runner errors are represented in JSON counts. Promotion
  work must decide explicitly whether timeout/error counts should also force a
  non-zero exit before changing behavior.

## Shared Test262 metadata contract

Skip metadata must migrate to a strict data file before both Python and MoonBit
consume it. The shared data must represent:

- unsupported `features` entries;
- unsupported `flags` entries;
- path suffix skip reasons.

Both implementations must produce identical `skip_reason(path, features, flags,
mode)` values for fixture cases and for the checked-out Test262 tree.

## Parity comparison rules

The comparison harness for Python-vs-MoonBit Test262 artifacts must:

- ignore top-level `date`;
- ignore `duration_ms` by default;
- ignore result array order;
- compare summary counts and pass rates exactly;
- compare category keys and counts exactly;
- compare result keys and statuses exactly;
- compare result reasons unless an invocation explicitly allows reason drift.

Any approved difference must be documented in the PR that introduces it.

## Promotion gates

A migrated MoonBit tool can replace its Python target only when:

1. CLI behavior is covered by fixture tests.
2. JSON or text output matches Python on deterministic fixtures.
3. The relevant Makefile shadow target passes locally.
4. CI runs the MoonBit command in shadow mode without hiding Python failures.
5. For the Test262 runner, full strict and non-strict artifacts match Python
   except for documented approved differences.
