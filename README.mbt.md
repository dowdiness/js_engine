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

| Edition | Strict P/E | Non-strict P/E |
|---|---:|---:|
| Pre-ES2015 (baseline) | 97.8% | 96.7% |
| ES2015 | 97.7% | 97.5% |
| ES2016 | 100.0% | 100.0% |
| ES2017 | 99.2% | 99.3% |
| ES2018 | 95.7% | 95.7% |
| ES2019 | 82.8% | 82.7% |
| ES2020 | 98.4% | 98.9% |
| ES2021 | 95.6% | 95.3% |
| ES2022 | 99.3% | 99.2% |
| ES2023 | 98.6% | 98.6% |
| ES2024 | 52.4% | 52.7% |
| ES2025 | 80.2% | 80.1% |
| Annex B | 82.3% | 83.8% |
| Stage 3 | 50.0% | 9.7% |
| **Total** | **96.9%** | **95.7%** |

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
