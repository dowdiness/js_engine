# js_engine

A pure [MoonBit](https://www.moonbitlang.com/), cross-target embedded JavaScript engine. It uses a tree-walking interpreter and runs on MoonBit's native, JavaScript, Wasm, and Wasm-GC targets.

- Conformance on [test262](https://github.com/tc39/test262): each file is run in strict and non-strict modes and reported per mode. Do not sum the modes. Generate current numbers from CI artifacts with `make test262-report`; see [docs/TEST262.md](docs/TEST262.md).
- Cross-target embedding: the same stateful `Engine` API is tested on native, JavaScript, Wasm, and Wasm-GC.
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
test "README stateful rule engine" {
  let engine = @js_engine.Engine()
  let source =
    #|let evaluations = 0;
    #|function allow(request) {
    #|  evaluations += 1;
    #|  return { allowed: request.role === "admin", evaluations };
    #|}
  engine.eval(source)
  let admin = Json::object({ "role": Json::string("admin") })
  let member_request = Json::object({ "role": Json::string("member") })
  json_inspect(engine.call_json("allow", [admin]), content={
    "allowed": true,
    "evaluations": 1,
  })
  json_inspect(engine.call_json("allow", [member_request]), content={
    "allowed": false,
    "evaluations": 2,
  })
}
```

`Engine` keeps one global realm alive across calls. Its strict JSON boundary copies plain data directly: it does not consult a mutable global `JSON`, call getters or `toJSON`, or execute Proxy traps. Promise results and non-JSON values are rejected. This API is intended for trusted application scripts, not as a security sandbox. See [`example/rule_engine/`](example/rule_engine/) for the runnable example.

For one-shot evaluation, the existing facade remains available:

```mbt check
///|
test "README one-shot facade" {
  let (output, _) = @js_engine.run("console.log(1 + 2)")
  json_inspect(output, content=["3"])
}
```

The public entry points are defined in [`js_engine.mbt`](js_engine.mbt):

- `Engine`, `Engine::eval`, `Engine::call_json`, `Engine::take_output` — persistent JSON-oriented embedding
- `Engine::run_microtask_checkpoint`, `Engine::run_timer_checkpoint` — explicit job-queue control; `eval` and `call_json` do not drain queues automatically
- `run` — evaluate a script; drains microtasks and timers before returning
- `run_compiled` — evaluate the supported script subset through the opt-in closure-conversion prototype
- `run_module` / `run_modules` — evaluate one or more ES modules and collect exports
- `run_with_event_loop`, `run_microtask_checkpoint`, `run_timer_checkpoint`,
  `has_pending_microtasks`, `has_pending_timers` — for hosts that want to drive the event loop themselves

### Embedding (custom host objects)

For DOM-style globals and native methods, create a wired interpreter and inject
bindings — do not reverse-engineer `Interpreter::new` / `setup_builtins` unless
you need to replace builtin installation itself:

```moonbit nocheck
let interp = @interpreter.new_interpreter()
// Build query_selector with realm_state=Some(interp.realm_state) — see guide.
let document = @runtime.make_host_object(
  name="Document",
  proto=@runtime.get_obj_proto(realm_state=Some(interp.realm_state)),
  methods={ "querySelector": query_selector },
)
interp.global.def_builtin("document", document)
// Then parse, interp.run, interp.run_microtasks(), interp.run_timers().
```

Full cookbook (`make_*_func` + `realm_state`, errors, host slots, `globalThis`,
custom `setup_builtins`): [docs/embedding.md](docs/embedding.md).

## Supported Language

Core ES5 plus selected ES6+ features: `let` / `const` / `var`, arrow functions, closures, classes, `for` / `while` / `for-in` / `for-of`, `try` / `catch` / `finally`, template literals, destructuring, spread / rest, ES Modules, Promises + microtasks, `setTimeout` / `setInterval`, ES6 Proxy (13 traps) + Reflect API (13 methods), TypedArrays (9 types), ArrayBuffer, DataView, RegExp, JSON, Map / Set / WeakMap / WeakSet, generators, Symbols.

For the full per-category breakdown, see [docs/supported-features.md](docs/supported-features.md).

## Conformance

<!-- Refresh: make test262-report ARGS="--format=readme" -->

Test262 conformance by edition — CI run [29452024184](https://github.com/dowdiness/js_engine/actions/runs/29452024184), tip `71e07d0`, 2026-07-15. P/E = passed ÷ executed (excludes skipped tests). Refresh: `make test262-report ARGS="--format=readme"`.

### strict

| Edition | Discovered | Skipped | Executed | Passed | Failed | Timeout/Err | Passed / Executed | Passed / Discovered |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Pre-ES2015 (baseline) | 13,281 | 0 | 13,278 | 12,993 | 285 | 3 | 97.9% | 97.8% |
| ES2015 | 10,300 | 161 | 10,131 | 9,942 | 189 | 8 | 98.1% | 96.5% |
| ES2016 | 100 | 0 | 99 | 99 | 0 | 1 | 100.0% | 99.0% |
| ES2017 | 736 | 344 | 392 | 389 | 3 | 0 | 99.2% | 52.9% |
| ES2018 | 4,725 | 727 | 3,998 | 3,811 | 187 | 0 | 95.3% | 80.7% |
| ES2019 | 128 | 0 | 128 | 106 | 22 | 0 | 82.8% | 82.8% |
| ES2020 | 1,784 | 1,537 | 247 | 244 | 3 | 0 | 98.8% | 13.7% |
| ES2021 | 468 | 128 | 340 | 325 | 15 | 0 | 95.6% | 69.4% |
| ES2022 | 5,065 | 34 | 5,031 | 2,709 | 2,322 | 0 | 53.8% | 53.5% |
| ES2023 | 254 | 33 | 221 | 218 | 3 | 0 | 98.6% | 85.8% |
| ES2024 | 1,072 | 866 | 206 | 108 | 98 | 0 | 52.4% | 10.1% |
| ES2025 | 1,148 | 779 | 369 | 296 | 73 | 0 | 80.2% | 25.8% |
| Annex B | 365 | 44 | 321 | 267 | 54 | 0 | 83.2% | 73.2% |
| Stage 3 | 5,531 | 5,519 | 12 | 6 | 6 | 0 | 50.0% | 0.1% |
| **Total** | **44,986** | **10,201** | **34,773** | **31,513** | **3,260** | **12** | **90.6%** | **70.1%** |

_Fully-skipped buckets (no tests executed) folded into Total: Unmapped (29)._

### non-strict

| Edition | Discovered | Skipped | Executed | Passed | Failed | Timeout/Err | Passed / Executed | Passed / Discovered |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Pre-ES2015 (baseline) | 13,917 | 0 | 13,911 | 13,467 | 444 | 6 | 96.8% | 96.8% |
| ES2015 | 10,788 | 160 | 10,620 | 10,400 | 220 | 8 | 97.9% | 96.4% |
| ES2016 | 100 | 0 | 99 | 99 | 0 | 1 | 100.0% | 99.0% |
| ES2017 | 775 | 344 | 431 | 428 | 3 | 0 | 99.3% | 55.2% |
| ES2018 | 4,781 | 735 | 4,046 | 3,859 | 187 | 0 | 95.4% | 80.7% |
| ES2019 | 127 | 0 | 127 | 105 | 22 | 0 | 82.7% | 82.7% |
| ES2020 | 1,984 | 1,604 | 380 | 377 | 3 | 0 | 99.2% | 19.0% |
| ES2021 | 444 | 128 | 316 | 301 | 15 | 0 | 95.3% | 67.8% |
| ES2022 | 5,361 | 296 | 5,065 | 2,731 | 2,334 | 0 | 53.9% | 50.9% |
| ES2023 | 277 | 56 | 221 | 218 | 3 | 0 | 98.6% | 78.7% |
| ES2024 | 1,077 | 870 | 207 | 109 | 98 | 0 | 52.7% | 10.1% |
| ES2025 | 1,180 | 813 | 367 | 294 | 73 | 0 | 80.1% | 24.9% |
| Annex B | 1,156 | 44 | 1,110 | 933 | 177 | 2 | 84.1% | 80.7% |
| Stage 3 | 5,696 | 5,593 | 103 | 10 | 93 | 0 | 9.7% | 0.2% |
| **Total** | **47,692** | **10,672** | **37,003** | **33,331** | **3,672** | **17** | **90.1%** | **69.9%** |

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
example/rule_engine/  Canonical stateful JSON rule-engine embedding
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
