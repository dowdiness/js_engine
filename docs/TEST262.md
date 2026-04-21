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
3. Run every test file in **both strict and non-strict modes** (roughly ~45–48k discovered files per mode; ~18k skipped for unimplemented features, so ~27–29k actually executed per mode)
4. Save results to `test262-results.json`

**Estimated time**: ~12-16 minutes depending on CPU.

## Step-by-Step

### 1. Build the JS target

The test runner uses the JS-compiled engine via Node.js for best performance:

```bash
moon build --target js
```

This produces `_build/js/debug/build/cmd/main/main.js`.

### 2. Download Test262

```bash
make test262-download
```

Downloads the latest Test262 suite from `tc39/test262` into `./test262/`. Skips download if already present.

### 3. Run the test suite

```bash
# Auto-detect engine (recommended)
python3 test262-runner.py --test262 ./test262 --output test262-results.json

# Explicit engine command
python3 test262-runner.py \
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
python3 test262-runner.py --filter "built-ins/Promise" --summary

# Multiple patterns work too
python3 test262-runner.py --filter "built-ins/TypedArray" --verbose
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

## Alternative Engine Commands

```bash
# Use the WASM-GC backend (slower, ~3 tests/sec)
python3 test262-runner.py --engine "moon run cmd/main --" --test262 ./test262

# Use the JS backend via node (faster, ~60 tests/sec)
moon build --target js
python3 test262-runner.py --test262 ./test262
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

Always quote **both** denominators when reporting a pass rate so the skip context isn't hidden. A headline figure like "85% on test262" without a denominator is ambiguous; the two numbers today are ~85–86% (passed / executed) vs ~51% (passed / discovered).

### JSON Results

When `--output` is specified, results are saved as JSON with:
- `summary`: Overall pass/fail/skip counts
- `categories`: Per-category breakdown
- `results`: Individual test outcomes (pass/fail/skip/timeout with error details)

### Result Files

| File | Description |
|------|-------------|
| `test262-results.json` | Structured JSON with full results |
| `test262-latest-results.txt` | Human-readable log from the most recent run |

## Skipped Features

Tests requiring these unimplemented features are automatically skipped (excluded from the Passed / Executed ratio). Rough groupings — see `SKIP_FEATURES` in `test262-runner.py` for the authoritative list:

- **Async iteration / top-level await**: `async-iteration`, `top-level-await` (note: plain `async-functions` is implemented and no longer skipped)
- **Class private members**: `class-fields-private`, `class-methods-private`, `class-static-fields-private`, `class-static-methods-private`, `class-static-block` (public class fields are implemented)
- **BigInt**, **Temporal**, **ShadowRealm**, **SharedArrayBuffer**, **Atomics**, **Float16Array**, **FinalizationRegistry**, **WeakRef**
- **Advanced RegExp**: `regexp-lookbehind`, `regexp-unicode-property-escapes`, `regexp-match-indices`, `regexp-v-flag`, `regexp-modifiers`, `RegExp.escape` (named groups are implemented — see PR #47)
- **Dynamic / special imports**: `import.meta`, `dynamic-import`, `import-assertions`, `import-attributes`, `json-modules`, `source-phase-imports`
- **Intl / locale**, **decorators**, **iterator-helpers**, **set-methods**, **resizable-arraybuffer**, **arraybuffer-transfer**, **explicit-resource-management**, **tail-call-optimization**, **hashbang**

Summed together these account for the ~18k skipped files per mode (~40% of discovered). That skip fraction is the wedge between the Passed / Executed and Passed / Discovered rates — implementing any of the above will shrink the gap.

## Static Analysis (No Engine Required)

Analyze test262 coverage without building or running the engine:

```bash
make test262-analyze
```

This runs `test262-analyze.py` to classify tests as applicable, skip_feature, skip_flag, or skip_fixture, and generates `test262-analysis.json`.

## CI Integration

The GitHub Actions workflow (`.github/workflows/test262.yml`) runs the full suite automatically:
- Builds with `moon build --target js --release`
- Downloads test262 from tc39/test262
- Runs with 4 threads and 90-minute timeout
- Uploads `test262-results.json` as an artifact

## Current Status

As of CI run [24730849102](https://github.com/dowdiness/js_engine/actions/runs/24730849102) (2026-04-21, tip `f89898a`, v0.2.0):

- Strict: **86.7%** passed / executed (23,054 / 26,601); 51.2% passed / discovered (23,054 / 44,986). 18,270 skipped.
- Non-strict: **85.1%** passed / executed (24,467 / 28,766); 51.3% passed / discovered (24,467 / 47,692). 18,811 skipped.

Strict and non-strict are reported separately — summing them would double-count the ~45k underlying test files. The ~51% figure is the honest spec-coverage number; the ~86% / ~85% figures exclude ~40% of the suite that we skip for unimplemented features. See [ROADMAP.md](ROADMAP.md) for category breakdowns and phase history, and [supported-features.md](supported-features.md) for the skipped-feature list.
