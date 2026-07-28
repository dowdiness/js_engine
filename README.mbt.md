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

The [stable embedding guide](docs/EMBEDDING.md) defines the JSON boundary,
lookup rules, queue checkpoints, retained-state behavior, error reuse limits,
and four-target contract.

For one-shot evaluation, the existing facade remains available:

```mbt check
///|
test "README one-shot facade" {
  let (output, _) = @js_engine.run("console.log(1 + 2)")
  json_inspect(output, content=["3"])
}
```

The public entry points are defined in [`js_engine.mbt`](js_engine.mbt) and
classified in the stable guide:

- **Stable embedding:** `run`, `Engine`, `EngineError`, and the `Engine::*`
  methods.
- **Compatibility:** `run_module` / `run_modules`; their export maps expose
  raw runtime values.
- **Advanced/internal:** `run_compiled` and the module-level event-loop APIs
  that expose or accept a raw interpreter.

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

Full advanced cookbook (`make_*_func` + `realm_state`, errors, host slots,
`globalThis`, custom `setup_builtins`):
[docs/advanced-embedding.md](docs/advanced-embedding.md).

## Supported Language

Core ES5 plus selected ES6+ features: `let` / `const` / `var`, arrow functions, closures, classes, `for` / `while` / `for-in` / `for-of`, `try` / `catch` / `finally`, template literals, destructuring, spread / rest, ES Modules, Promises + microtasks, `setTimeout` / `setInterval`, ES6 Proxy (13 traps) + Reflect API (13 methods), TypedArrays (9 types), ArrayBuffer, DataView, RegExp, JSON, Map / Set / WeakMap / WeakSet, generators, Symbols.

For the full per-category breakdown, see [docs/supported-features.md](docs/supported-features.md).

## Conformance

<!-- Refresh: make test262-report ARGS="--format=readme" -->

Test262 conformance by edition — CI run [30346236658](https://github.com/dowdiness/js_engine/actions/runs/30346236658), tip `265bbfd`, 2026-07-28. P/E = passed ÷ executed (excludes skipped tests). Refresh: `make test262-report ARGS="--format=readme"`.

### strict

| Edition | Discovered | Skipped | Executed | Passed | Failed | Timeout/Err | Passed / Executed | Passed / Discovered |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Pre-ES2015 (baseline) | 22,919 | 2,682 | 20,225 | 19,622 | 603 | 12 | 97.0% | 85.6% |
| ES2015 | 15,420 | 1,471 | 13,948 | 11,590 | 2,358 | 1 | 83.1% | 75.2% |
| ES2017 | 694 | 481 | 213 | 207 | 6 | 0 | 97.2% | 29.8% |
| ES2018 | 109 | 2 | 107 | 91 | 16 | 0 | 85.0% | 83.5% |
| ES2020 | 77 | 76 | 1 | 1 | 0 | 0 | 100.0% | 1.3% |
| ES2021 | 101 | 77 | 24 | 16 | 8 | 0 | 66.7% | 15.8% |
| ES2025 | 510 | 505 | 5 | 5 | 0 | 0 | 100.0% | 1.0% |
| Annex B | 293 | 44 | 247 | 205 | 42 | 2 | 83.0% | 70.0% |
| **Total** | **44,986** | **10,201** | **34,770** | **31,737** | **3,033** | **15** | **91.3%** | **70.5%** |

_Fully-skipped buckets (no tests executed) folded into Total: Stage 3 (4,863)._

### non-strict

| Edition | Discovered | Skipped | Executed | Passed | Failed | Timeout/Err | Passed / Executed | Passed / Discovered |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Pre-ES2015 (baseline) | 23,915 | 2,834 | 21,065 | 20,302 | 763 | 16 | 96.4% | 84.9% |
| ES2015 | 16,311 | 1,786 | 14,524 | 12,059 | 2,465 | 1 | 83.0% | 73.9% |
| ES2017 | 718 | 481 | 237 | 231 | 6 | 0 | 97.5% | 32.2% |
| ES2018 | 109 | 2 | 107 | 91 | 16 | 0 | 85.0% | 83.5% |
| ES2020 | 77 | 76 | 1 | 1 | 0 | 0 | 100.0% | 1.3% |
| ES2021 | 101 | 77 | 24 | 16 | 8 | 0 | 66.7% | 15.8% |
| ES2025 | 510 | 505 | 5 | 5 | 0 | 0 | 100.0% | 1.0% |
| Annex B | 1,084 | 44 | 1,038 | 849 | 189 | 2 | 81.8% | 78.3% |
| **Total** | **47,692** | **10,672** | **37,001** | **33,554** | **3,447** | **19** | **90.7%** | **70.4%** |

_Fully-skipped buckets (no tests executed) folded into Total: Stage 3 (4,867)._

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
