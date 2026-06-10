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
MoonBit shadow output should derive category keys from normalized Test262 paths;
do not copy the Python CI path bug that can collapse all categories into the
singleton key `../..` when the Python runner is invoked from the repository root.
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

The Test262 runner (native `cmd/test262_runner`, authoritative) follows
this exit-code contract:

- invalid CLI arguments exit non-zero through argparse;
- missing Test262 directory, unreadable tests file, missing engine command, or
  unreadable resume/log files exit non-zero;
- after a completed run, any failed tests cause a non-zero exit;
- skips, timeouts, and runner errors are represented in JSON counts. Promotion
  work must decide explicitly whether timeout/error counts should also force a
  non-zero exit before changing behavior.

## Shared Test262 metadata contract

Skip metadata lives in `scripts/test262_skip_metadata.json`, a strict JSON
object with these fields:

- `schema_version`: integer, currently `1`;
- `skip_features`: array of unsupported Test262 `features` strings;
- `skip_flags`: array of unsupported Test262 `flags` strings;
- `skip_path_suffixes`: object mapping Test262 path suffixes to skip reasons.

`make test262-metadata-test` runs the MoonBit metadata tests against shared parity fixtures. `make test262-validate-skips`
checks that the metadata entries still exist in the checked-out Test262 suite; it
does not run tests or produce conformance numbers.

Both implementations must produce identical `skip_reason(path, features, flags,
mode)` values for fixture cases and for the checked-out Test262 tree.

## Shared Test262 utility contract

The MoonBit `tooling/test262_utils` package is the authoritative implementation
for YAML frontmatter extraction and `as_list` coercion. `make test262-utils-test`
runs the MoonBit utility tests against `scripts/test262_utils_parity_cases.json`.

The shared fixtures pin the lightweight fallback YAML subset: scalar coercion,
inline lists and dictionaries, indented lists and dictionaries, block scalars,
inline comment stripping, missing frontmatter, and `as_list` null/scalar/list
coercion.

## Parity comparison rules

The comparison harness for Python-vs-MoonBit Test262 artifacts must:

- ignore top-level `date`;
- ignore `duration_ms` by default;
- ignore result array order;
- compare summary counts and pass rates exactly;
- compare category keys and counts exactly when the Python artifact has valid categories;
- for full CI artifact comparison, discard only the known broken Python
  singleton `../..` category shape and validate MoonBit's normalized category
  output against its own result records instead;
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

## Promotion status

**Phase 4 (Python dependency removal) — complete as of 2026-06-10.** All 26
transitional Python scripts have been deleted. The `*-py` Make targets have been
removed. CI no longer installs Python dependencies or runs the Python shadow.
The Python transitional phase is closed.

Issue #255 promoted the following tools from shadow to authoritative (Phase 3,
completed 2026-06-09):

- **Test262 runner** (`cmd/test262_runner`): authoritative in CI
  (`.github/workflows/test262.yml`) and in `make test262` / `test262-quick` /
  `test262-filter`.
- **Tier 1 utilities**: `make bench-focus`, `test262-analyze`,
  `test262-validate-skips`, `test262-report`, `unicode-tables`, and the
  per-edition classifier (`cmd/classify_by_edition`, used for the CI per-edition
  table).

**Gate #5 (full-artifact parity) — met.** The native runner's strict and
non-strict CI artifacts matched the Python runner except for non-deterministic
`timeout`/`pass` flips at the `--timeout 5` boundary on a small set of heavy
tests (`built-ins/encodeURI/S15.1.3.3_A2.3_T1.js`,
`built-ins/encodeURIComponent/S15.1.3.4_A2.3_T1.js`,
`annexB/built-ins/RegExp/RegExp-leading-escape-BMP.js`). These flips were
observed in opposite directions across CI runs `026b2c9` and `0fd7d3a`, sit well
within the regression baseline's `passed_min` margin, and were exhibited by the
Python runner too. They are an **approved difference** — wall-clock timeout
flakiness, not a runner divergence. The earlier CRLF/CR reason, embedded-NUL
status, and module source-order differences were fixed in PR #285.
