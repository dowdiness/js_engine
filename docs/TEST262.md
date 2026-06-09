# Running Test262

Test262 is the official ECMAScript conformance test suite maintained by TC39. This document explains how to run it against the MoonBit JS Engine.

## Prerequisites

- **MoonBit toolchain** (`moon` CLI) — install from [moonbitlang.com](https://www.moonbitlang.com/)
- **Node.js** — required to run the JS-compiled engine
- **Python 3** — required by the test runner

## Quick Start

```bash
# Full test262 run (build + download + run)
make test262
```

This single command will:
1. Build the engine (`moon build`)
2. Download the Test262 suite if not already present
3. Run every applicable test file in **both strict and non-strict modes**
4. Save results to `test262-results.json`

**Estimated time**: ~12-16 minutes depending on CPU.

## Step-by-Step

### 1. Build an engine

Local `make test262` runs the MoonBit CLI through `moon run cmd/main --`.
For direct runner use, you may also build the JS target and let the runner
auto-detect the compiled Node.js bundle:

```bash
moon build --target js
```

This produces `_build/js/debug/build/cmd/main/main.js`. CI uses the JS-compiled
engine through Node.js; the local Makefile does not.

### 2. Download Test262

```bash
make test262-download
```

Downloads the latest Test262 suite from `tc39/test262` into `./test262/`. Skips download if already present.

### 3. Run the test suite

```bash
# Recommended: native runner via make (authoritative)
make test262

# Or invoke the native runner binary directly (built by `make test262`)
./_build/native/debug/build/cmd/test262_runner/test262_runner.exe \
    --test262 ./test262 \
    --output test262-results.json
```

The native `cmd/test262_runner` is authoritative. `scripts/test262-runner.py`
(the `*-py` Make targets, e.g. `make test262-py`) is the transitional Python
fallback and accepts the same flags.

## Filtering Tests

Run a specific category or subset of tests:

```bash
# Run only language/literals tests
make test262-quick

# Run a specific category
make test262-filter FILTER=language/expressions

# Use the native runner directly with a filter
./_build/native/debug/build/cmd/test262_runner/test262_runner.exe --filter "built-ins/Promise" --summary

# Multiple patterns work too
./_build/native/debug/build/cmd/test262_runner/test262_runner.exe --filter "built-ins/TypedArray" --verbose
```

## Sharded and Resumable Local Runs

Long local investigations can be chunked without changing CI defaults. Task
selection happens **after** strict/non-strict mode expansion, so use
`--mode strict` or `--mode non-strict` when you want per-mode shards that match
CI jobs.

The examples below use the native runner binary. Define a shorthand (the
transitional Python fallback `python3 scripts/test262-runner.py` accepts the
same flags):

```bash
RUNNER=./_build/native/debug/build/cmd/test262_runner/test262_runner.exe

# Run an explicit file list. Relative entries are resolved under test262/test/.
$RUNNER \
    --test262 ./test262 \
    --tests-file /tmp/test262-list.txt \
    --mode non-strict \
    --summary

# Run one balanced shard of the expanded task list.
$RUNNER \
    --test262 ./test262 \
    --mode non-strict \
    --shard 2/8 \
    --output test262-non-strict-shard-2.json \
    --log logs/test262-non-strict-shard-2.jsonl \
    --merged-log logs/test262-failures.jsonl \
    --summary

# Resume the same shard by skipping (path, mode) records already in the JSON.
$RUNNER \
    --test262 ./test262 \
    --mode non-strict \
    --shard 2/8 \
    --resume-from test262-non-strict-shard-2.json \
    --output test262-non-strict-shard-2-retry.json \
    --summary

# Use an explicit 0-based task slice instead of --shard.
$RUNNER \
    --test262 ./test262 \
    --mode strict \
    --start 10000 \
    --count 2000 \
    --summary
```

`--shard` cannot be combined with `--start`/`--count`. `--log` writes every
completed task as JSON Lines and is overwritten for each invocation.
`--merged-log` appends fail/timeout/error records as JSON Lines, which is handy
when collecting failures across several shard runs. These task-selection flags
do not change the main `--output` JSON schema, which remains compatible with
the report (`make test262-report`) and classify-by-edition tooling.

## Opt-in Modified Harness Helpers

Official CI and default local runs do not enable modified harness helpers. For
local investigations, the runner can opt into explicitly labeled helpers:

```bash
python3 scripts/test262-runner.py \
    --test262 ./test262 \
    --filter "built-ins/RegExp" \
    --harness-helper codePointRange \
    --summary
```

`--harness-helper codePointRange` injects a `$262.codePointRange` helper before
Test262 harness files load and rewrites loaded `regExpUtils.js` source in memory
to use it when the checked-out harness matches the known Test262 helper shape.
If the engine already provides a native helper, the injected source leaves it in
place; otherwise it installs a JavaScript fallback. This is for RegExp-heavy
local diagnosis only: it does not change skip metadata, pass/fail/timeout
classification, the checked-out Test262 tree, or CI defaults. Modified-harness
runs print a methodology line and add `methodology` metadata to the output JSON
so their numbers are not confused with official CI results.

## Runner Options

| Option | Default | Description |
|--------|---------|-------------|
| `--engine CMD` | Auto-detect | Command to invoke the JS engine |
| `--test262 DIR` | `./test262` | Path to the test262 directory |
| `--filter PATTERN` | (all tests) | Only run tests whose path contains this string |
| `--tests-file FILE` | (none) | Run a newline-delimited explicit list of test files |
| `--start N` | `0` | Start at expanded task offset `N` (0-based) |
| `--count N` | (remaining) | Run at most `N` expanded tasks |
| `--shard I/N` | (none) | Run balanced contiguous shard `I` of `N` after mode expansion |
| `--resume-from FILE` | (none) | Skip `(path, mode)` tasks already present in a runner results JSON |
| `--log FILE` | (none) | Write every completed task as JSON Lines (overwrites per invocation) |
| `--merged-log FILE` | (none) | Append fail/timeout/error records as JSON Lines |
| `--timeout SECS` | `5` | Timeout per test in seconds |
| `--threads N` | Auto (CPU count) | Number of parallel workers |
| `--harness-helper NAME` | (none) | Opt into a modified harness helper; currently `codePointRange` |
| `--output FILE` | `test262-results.json` | Write JSON results to this file |
| `--summary` | off | Print summary only, no individual failures |
| `--verbose` | off | Print each test result as it runs |
| `--mode MODE` | `both` | `strict`, `non-strict`, or `both` |

## Alternative Engine Commands

The native runner auto-detects the engine. Pass `--engine` to override (the
transitional Python fallback `python3 scripts/test262-runner.py` accepts the
same flag):

```bash
RUNNER=./_build/native/debug/build/cmd/test262_runner/test262_runner.exe

# Use the WASM-GC backend (slower, ~3 tests/sec)
$RUNNER --engine "moon run cmd/main --" --test262 ./test262

# Use the JS backend via node (faster, ~60 tests/sec)
moon build --target js
$RUNNER --test262 ./test262
```

## Understanding Results

### Output Format

The runner prints a **per-mode** conformance report (strict and non-strict run separately — do **not** sum them, each file is tested twice):

- **Discovered**: all `.js` files applicable to the mode
- **Skipped**: tests requiring unimplemented features (Temporal, BigInt, async-iteration, class-private, regexp-v-flag, etc.) — excluded from the Passed / Executed figure
- **Executed**: `Discovered − Skipped`, i.e. tests actually run
- **Passed / Failed / Timeouts**: outcome counts among executed tests
- **Passed / Executed** — the conventional "test262 pass rate". Rises as failures are fixed; also rises mechanically when skipping more tests. **Does not reflect whether a feature is implemented at all** — a feature whose tests are 100% skipped contributes 0 to this ratio.
- **Passed / Discovered** — honest spec-coverage figure. Counts skipped files as un-passed. Falls when the suite adds new-edition tests we don't yet run, rises only when we actually implement more of the spec.

Always quote **both** denominators when reporting a pass rate so the skip context isn't hidden. A headline figure like "85% on test262" without a denominator is ambiguous.

### JSON Results

Results are saved as JSON with:
- `summary`: Overall pass/fail/skip counts
- `categories`: Per-category breakdown
- `results`: Individual test outcomes (pass/fail/skip/timeout with error details)
- `methodology`: Present only for modified-harness runs, describing the opt-in helpers used

### Result Files

| File | Description |
|------|-------------|
| `test262-results.json` | Structured JSON with full results |
| `test262-strict-results.json` | CI artifact produced by the strict-mode job |
| `test262-non-strict-results.json` | CI artifact produced by the non-strict-mode job |
| `*.jsonl` from `--log` | Per-invocation task progress log |
| `*.jsonl` from `--merged-log` | Append-only fail/timeout/error log for shard collection |

## Skipped Features

Tests requiring these unimplemented features are automatically skipped (excluded from the Passed / Executed ratio). Rough groupings — see the shared skip metadata in `scripts/test262_skip_metadata.json` (applied by the runner):

- **Async iteration / top-level await**: `async-iteration`, `top-level-await` (note: plain `async-functions` is implemented and no longer skipped)
- **Class private members**: `class-fields-private`, `class-methods-private`, `class-static-fields-private`, `class-static-methods-private`, `class-static-block` (public class fields are implemented)
- **BigInt**, **Temporal**, **ShadowRealm**, **SharedArrayBuffer**, **Atomics**, **Float16Array**, **FinalizationRegistry**, **WeakRef**
- **Advanced RegExp**: `regexp-lookbehind`, `regexp-unicode-property-escapes`, `regexp-match-indices`, `regexp-v-flag`, `regexp-modifiers`, `RegExp.escape` (named groups are implemented — see PR #47)
- **Dynamic / special imports**: `import.meta`, `dynamic-import`, `import-attributes`, `json-modules`, `source-phase-imports`
- **Intl normative optional**, **decorators**, **iterator-helpers**, **set-methods**, **resizable-arraybuffer**, **arraybuffer-transfer**, **explicit-resource-management**, **tail-call-optimization**, **hashbang**

Skipped files explain the gap between Passed / Executed and Passed / Discovered. Implementing skipped features generally shrinks that gap, but it can temporarily lower Passed / Executed while newly unskipped tests still fail.

## Static Metadata Analysis (Non-Authoritative)

For a rough metadata census without building or running the engine:

```bash
make test262-analyze
```

This runs the native `cmd/test262_analyze` (authoritative; `scripts/test262-analyze.py`
is retained as a cross-check shadow), which uses shared skip metadata from
`scripts/test262_skip_metadata.json` and classifies files as `applicable`,
`skip_feature`, `skip_flag`, or `skip_fixture`. It generates
`test262-analysis.json`.

Do not use this output as a conformance rate, pass/fail status, or skip-list
source of truth. Shared metadata prevents drift between tools, but the analyzer
does not execute the engine, expand strict/non-strict tasks, load harnesses,
resolve module fixtures, or observe runtime failures/timeouts. Use the native
runner (`cmd/test262_runner`, via `make test262`) and CI artifacts for
authoritative results.

To check that shared skip metadata still names features, flags, and path
suffixes present in the checked-out Test262 suite:

```bash
make test262-validate-skips
```

This runs the native `cmd/test262_validate_skips` (authoritative;
`make test262-validate-skips-py` is the transitional Python fallback). It only
reports dead or unknown skip metadata entries; it does not run tests or produce
conformance numbers.

## CI Integration

The GitHub Actions workflow (`.github/workflows/test262.yml`) runs the full suite automatically:
- Builds with `moon build --target js --release`
- Downloads test262 from tc39/test262
- Runs the JS-compiled engine through Node.js
- Runs strict and non-strict jobs with 4 threads, a 5-second per-test runner timeout, and the job timeout configured in the workflow file
- Uploads per-mode JSON result artifacts

## Current Status

Do not copy current conformance numbers from this file. Generate them from the
latest successful CI artifacts:

```bash
make test262-report
make test262-report ARGS="--with-editions"
```

Use [ROADMAP.md](ROADMAP.md) for the latest checked-in status snapshot and
[supported-features.md](supported-features.md) for dated per-category snapshots.
