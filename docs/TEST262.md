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
# Auto-detect engine (recommended)
python3 scripts/test262-runner.py --test262 ./test262 --output test262-results.json

# Explicit engine command
python3 scripts/test262-runner.py \
    --engine "node _build/js/debug/build/cmd/main/main.js" \
    --test262 ./test262 \
    --output test262-results.json
```

## Filtering Tests

Run a specific category or subset of tests:

```bash
# Run only language/literals tests
make test262-quick

# Run a specific category
make test262-filter FILTER=language/expressions

# Use the runner directly with a filter
python3 scripts/test262-runner.py --filter "built-ins/Promise" --summary

# Multiple patterns work too
python3 scripts/test262-runner.py --filter "built-ins/TypedArray" --verbose
```

## Runner Options

| Option | Default | Description |
|--------|---------|-------------|
| `--engine CMD` | Auto-detect | Command to invoke the JS engine |
| `--test262 DIR` | `./test262` | Path to the test262 directory |
| `--filter PATTERN` | (all tests) | Only run tests whose path contains this string |
| `--timeout SECS` | `5` | Timeout per test in seconds |
| `--threads N` | Auto (CPU count) | Number of parallel workers |
| `--output FILE` | (none) | Write JSON results to this file |
| `--summary` | off | Print summary only, no individual failures |
| `--verbose` | off | Print each test result as it runs |
| `--mode MODE` | `both` | `strict`, `non-strict`, or `both` |

## Alternative Engine Commands

```bash
# Use the WASM-GC backend (slower, ~3 tests/sec)
python3 scripts/test262-runner.py --engine "moon run cmd/main --" --test262 ./test262

# Use the JS backend via node (faster, ~60 tests/sec)
moon build --target js
python3 scripts/test262-runner.py --test262 ./test262
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

When `--output` is specified, results are saved as JSON with:
- `summary`: Overall pass/fail/skip counts
- `categories`: Per-category breakdown
- `results`: Individual test outcomes (pass/fail/skip/timeout with error details)

### Result Files

| File | Description |
|------|-------------|
| `test262-results.json` | Structured JSON with full results |
| `test262-strict-results.json` | CI artifact produced by the strict-mode job |
| `test262-non-strict-results.json` | CI artifact produced by the non-strict-mode job |

## Skipped Features

Tests requiring these unimplemented features are automatically skipped (excluded from the Passed / Executed ratio). Rough groupings — see `SKIP_FEATURES` in `scripts/test262_skip_metadata.py` for the shared skip metadata applied by the runner:

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

This runs `scripts/test262-analyze.py`, which uses shared skip metadata from
`scripts/test262_skip_metadata.py` and classifies files as `applicable`,
`skip_feature`, `skip_flag`, or `skip_fixture`. It generates
`test262-analysis.json`.

Do not use this output as a conformance rate, pass/fail status, or skip-list
source of truth. Shared metadata prevents drift between tools, but the analyzer
does not execute the engine, expand strict/non-strict tasks, load harnesses,
resolve module fixtures, or observe runtime failures/timeouts. Use
`scripts/test262-runner.py` and CI artifacts for authoritative results.

To check that shared skip metadata still names features, flags, and path
suffixes present in the checked-out Test262 suite:

```bash
make test262-validate-skips
```

This runs `scripts/validate-test262-skip-metadata.py`. It only reports dead or
unknown skip metadata entries; it does not run tests or produce conformance
numbers.

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
