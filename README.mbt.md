# js_engine

A minimal JavaScript tree-walking interpreter written in [MoonBit](https://www.moonbitlang.com/).

- Conformance on [test262](https://github.com/tc39/test262): each file is run in strict and non-strict modes and reported per mode. Do not sum the modes. Generate current numbers from CI artifacts with `make test262-report`; see [docs/TEST262.md](docs/TEST262.md).
- JavaScript target: the engine builds with MoonBit's JS target and runs on Node.js.
- Benchmark dashboard: https://dowdiness.github.io/js_engine/benchmarks/

## Quick Start

### CLI

```sh
moon run cmd/main -- 'console.log(1 + 2)'
# 3
```

```sh
moon run cmd/main -- '
function fib(n) {
  if (n <= 1) { return n; }
  return fib(n - 1) + fib(n - 2);
}
console.log(fib(10));
'
# 55
```

More sample programs live in [`example/`](example/).

### As a Library

```mbt check
///|
test "README run facade" {
  let (output, result) = @js_engine.run("console.log(1 + 2)")
  json_inspect(output, content=["3"])
  guard result == "undefined" else {
    fail("result: expected undefined, got " + result)
  }
}
```

The public entry points are defined in [`js_engine.mbt`](js_engine.mbt):

- `run` — evaluate a script; drains microtasks and timers before returning
- `run_compiled` — evaluate the supported script subset through the opt-in closure-conversion prototype
- `run_module` / `run_modules` — evaluate one or more ES modules and collect exports
- `run_with_event_loop`, `run_microtask_checkpoint`, `run_timer_checkpoint`,
  `has_pending_microtasks`, `has_pending_timers` — for hosts that want to drive the event loop themselves

## Supported Language

Core ES5 plus selected ES6+ features: `let` / `const` / `var`, arrow functions, closures, classes, `for` / `while` / `for-in` / `for-of`, `try` / `catch` / `finally`, template literals, destructuring, spread / rest, ES Modules, Promises + microtasks, `setTimeout` / `setInterval`, ES6 Proxy (13 traps) + Reflect API (13 methods), TypedArrays (9 types), ArrayBuffer, DataView, RegExp, JSON, Map / Set / WeakMap / WeakSet, generators, Symbols.

For the full per-category breakdown, see [docs/supported-features.md](docs/supported-features.md).

## Conformance

<!-- Refresh: make test262-report ARGS="--format=readme" -->

Test262 conformance by edition — CI run [28279305916](https://github.com/dowdiness/js_engine/actions/runs/28279305916), tip `39c6bc1`, 2026-06-27. P/E = passed ÷ executed (excludes skipped tests). Refresh: `make test262-report ARGS="--format=readme"`.
### strict
| Edition | Discovered | Skipped | Executed | Passed | Failed | Timeout/Err | Passed / Executed | Passed / Discovered |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Pre-ES2015 (baseline) | 13,281 | 0 | 13,273 | 12,976 | 297 | 8 | 97.8% | 97.7% |
| ES2015 | 10,300 | 160 | 10,131 | 9,895 | 236 | 9 | 97.7% | 96.1% |
| ES2016 | 100 | 0 | 99 | 99 | 0 | 1 | 100.0% | 99.0% |
| ES2017 | 736 | 344 | 392 | 389 | 3 | 0 | 99.2% | 52.9% |
| ES2018 | 4,725 | 4,326 | 399 | 382 | 17 | 0 | 95.7% | 8.1% |
| ES2019 | 128 | 0 | 128 | 106 | 22 | 0 | 82.8% | 82.8% |
| ES2020 | 1,784 | 1,537 | 247 | 243 | 4 | 0 | 98.4% | 13.6% |
| ES2021 | 468 | 128 | 340 | 325 | 15 | 0 | 95.6% | 69.4% |
| ES2022 | 5,065 | 4,352 | 713 | 708 | 5 | 0 | 99.3% | 14.0% |
| ES2023 | 254 | 33 | 221 | 218 | 3 | 0 | 98.6% | 85.8% |
| ES2024 | 1,072 | 866 | 206 | 108 | 98 | 0 | 52.4% | 10.1% |
| ES2025 | 1,148 | 779 | 369 | 296 | 73 | 0 | 80.2% | 25.8% |
| Annex B | 365 | 46 | 316 | 260 | 56 | 3 | 82.3% | 71.2% |
| Stage 3 | 5,531 | 5,519 | 12 | 6 | 6 | 0 | 50.0% | 0.1% |
| **Total** | **44,986** | **18,119** | **26,846** | **26,011** | **835** | **21** | **96.9%** | **57.8%** |

_Fully-skipped buckets (no tests executed) folded into Total: Unmapped (29)._
### non-strict
| Edition | Discovered | Skipped | Executed | Passed | Failed | Timeout/Err | Passed / Executed | Passed / Discovered |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Pre-ES2015 (baseline) | 13,917 | 0 | 13,909 | 13,452 | 457 | 8 | 96.7% | 96.7% |
| ES2015 | 10,788 | 159 | 10,620 | 10,353 | 267 | 9 | 97.5% | 96.0% |
| ES2016 | 100 | 0 | 99 | 99 | 0 | 1 | 100.0% | 99.0% |
| ES2017 | 775 | 344 | 431 | 428 | 3 | 0 | 99.3% | 55.2% |
| ES2018 | 4,781 | 4,384 | 397 | 380 | 17 | 0 | 95.7% | 7.9% |
| ES2019 | 127 | 0 | 127 | 105 | 22 | 0 | 82.7% | 82.7% |
| ES2020 | 1,984 | 1,610 | 374 | 370 | 4 | 0 | 98.9% | 18.6% |
| ES2021 | 444 | 128 | 316 | 301 | 15 | 0 | 95.3% | 67.8% |
| ES2022 | 5,361 | 4,628 | 733 | 727 | 6 | 0 | 99.2% | 13.6% |
| ES2023 | 277 | 56 | 221 | 218 | 3 | 0 | 98.6% | 78.7% |
| ES2024 | 1,077 | 870 | 207 | 109 | 98 | 0 | 52.7% | 10.1% |
| ES2025 | 1,180 | 813 | 367 | 294 | 73 | 0 | 80.1% | 24.9% |
| Annex B | 1,156 | 46 | 1,107 | 928 | 179 | 3 | 83.8% | 80.3% |
| Stage 3 | 5,696 | 5,593 | 103 | 10 | 93 | 0 | 9.7% | 0.2% |
| **Total** | **47,692** | **18,660** | **29,011** | **27,774** | **1,237** | **21** | **95.7%** | **58.2%** |

_Fully-skipped buckets (no tests executed) folded into Total: Unmapped (29)._

## Package Structure

```
token/          Token types and source locations
errors/         JavaScript error variants and formatting helpers
lexer/          Tokenizer
ast/            AST node definitions
parser/         Recursive descent parser with Pratt precedence
static_semantics/  Early-error and declaration-fact analysis
compiler/       Opt-in closure-conversion prototype
interpreter/    Wiring layer for runtime + standard library
interpreter/runtime/  Tree-walking evaluator, value model, host state
interpreter/stdlib/   JavaScript built-ins
cmd/main/       CLI entry point
cmd/test262_runner/  Native test262 runner
cmd/report_test262/  CI artifact report generator
benchmarks/     Benchmark workloads and runner
```

## Development

```sh
moon check        # Type check
moon test         # Run unit tests
moon fmt          # Format code
moon info         # Update .mbti interface files
moon build        # Build
```

Run the test262 conformance suite with `make test262`. See [docs/TEST262.md](docs/TEST262.md) for prerequisites, filtering, and options.

## Documentation

- [docs/README.md](docs/README.md) — start here for deeper material
- [docs/development.md](docs/development.md) — maintainer workflow and generated files
- [docs/ROADMAP.md](docs/ROADMAP.md) — current status and active roadmap
- [docs/supported-features.md](docs/supported-features.md) — per-category conformance, Annex B, and missing features
- [docs/GLOSSARY.md](docs/GLOSSARY.md) — terminology used in the code and docs
- [AGENTS.md](AGENTS.md) — MoonBit coding conventions (also used by AI agents)

## License

Apache-2.0
