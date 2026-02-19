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
3. Run all ~48,000 tests (~27,000 executed, ~20,000 skipped)
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

The runner prints a conformance report with:
- **Total tests discovered**: All `.js` files in the test262 suite
- **Skipped**: Tests requiring unimplemented features (async/await, BigInt, Temporal, etc.)
- **Executed**: Tests actually run
- **Passed / Failed / Timeouts**: Outcome counts
- **Pass rate**: `Passed / Executed`

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

Tests requiring these unimplemented features are automatically skipped:

- **async/await**: `async-functions`, `async-iteration`, `top-level-await`
- **Class fields**: `class-fields-public`, `class-fields-private`, `class-methods-private`, `class-static-*`
- **BigInt**, **Temporal**, **SharedArrayBuffer**, **Atomics**
- **Advanced RegExp**: `regexp-lookbehind`, `regexp-named-groups`, `regexp-v-flag`
- **Dynamic import**: `dynamic-import`, `import.meta`, `import-assertions`

See `SKIP_FEATURES` in `test262-runner.py` for the complete list.

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

As of 2026-02-18: **88.8% pass rate** (24,519 / 27,599 executed). See [ROADMAP.md](../ROADMAP.md) for detailed category breakdowns and phase history.
