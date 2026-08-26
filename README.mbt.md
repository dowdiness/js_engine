# js_engine

A pure [MoonBit](https://www.moonbitlang.com/), cross-target embedded JavaScript engine. The stateful engine and CLI use the verified bytecode candidate by default and fall back to the tree-walking executor for unsupported source. It runs on MoonBit's native, JavaScript, Wasm, and Wasm-GC targets.

- Conformance on [test262](https://github.com/tc39/test262): each file is run in strict and non-strict modes and reported per mode. Do not sum the modes. Generate current numbers from CI artifacts with `make test262-report`; see [docs/TEST262.md](docs/TEST262.md).
- Cross-target embedding: the same stateful `Engine` API is tested on native, JavaScript, Wasm, and Wasm-GC.
- Benchmark dashboard: https://dowdiness.github.io/js_engine/benchmarks/
- Interactive [JavaScript Playground](https://dowdiness.github.io/js_engine/playground/).

## Quick Start

### CLI

```sh
moon run cmd/main -- -e 'console.log(1 + 2)'
# 3
```

```sh
moon run cmd/main -- -e '
function fib(n) {
  if (n <= 1) { return n; }
  return fib(n - 1) + fib(n - 2);
}
console.log(fib(10));
'
# 55
```

Pass a script filename to run a file, and put script arguments after `--`:

```sh
moon run cmd/main -- path/to/script.js -- first --second
```

The shell provides `load()`, `read()` / `readFile()`, `print()`, `console`,
`arguments`, `scriptArgs`, and monotonic `performance.now()`. `load()` evaluates
in the current realm and resolves nested relative paths from the loading file.
`read(path, "binary")` returns an `ArrayBuffer`.

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

- **Stable embedding:** `run`, `Engine`, `EngineError`, and the unbounded
  persistent `Engine` methods listed in the guide.
- **Staged Stage 4 availability:** `Engine::eval_bounded`,
  `Engine::call_json_bounded`, `Engine::run_microtask_checkpoint_bounded`,
  `Engine::run_timer_checkpoint_bounded`, `ExecutionPolicy`,
  `ExecutionPolicyError`, and `InterruptionHandle`.
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
| Pre-ES2015 (baseline) | 13,281 | 0 | 13,277 | 13,057 | 220 | 4 | 98.3% | 98.3% |
| ES2015 | 10,300 | 161 | 10,131 | 10,033 | 98 | 8 | 99.0% | 97.4% |
| ES2016 | 100 | 0 | 99 | 99 | 0 | 1 | 100.0% | 99.0% |
| ES2017 | 736 | 344 | 392 | 392 | 0 | 0 | 100.0% | 53.3% |
| ES2018 | 4,725 | 727 | 3,998 | 3,822 | 176 | 0 | 95.6% | 80.9% |
| ES2019 | 128 | 0 | 128 | 106 | 22 | 0 | 82.8% | 82.8% |
| ES2020 | 1,784 | 1,537 | 247 | 244 | 3 | 0 | 98.8% | 13.7% |
| ES2021 | 468 | 128 | 340 | 326 | 14 | 0 | 95.9% | 69.7% |
| ES2022 | 5,065 | 34 | 5,031 | 2,765 | 2,266 | 0 | 55.0% | 54.6% |
| ES2023 | 254 | 33 | 221 | 218 | 3 | 0 | 98.6% | 85.8% |
| ES2024 | 1,072 | 866 | 206 | 108 | 98 | 0 | 52.4% | 10.1% |
| ES2025 | 1,148 | 779 | 369 | 296 | 73 | 0 | 80.2% | 25.8% |
| Annex B | 365 | 44 | 319 | 265 | 54 | 2 | 83.1% | 72.6% |
| Stage 3 | 5,531 | 5,519 | 12 | 6 | 6 | 0 | 50.0% | 0.1% |
| **Total** | **44,986** | **10,201** | **34,770** | **31,737** | **3,033** | **15** | **91.3%** | **70.5%** |

_Fully-skipped buckets (no tests executed) folded into Total: Unmapped (29)._

### non-strict

| Edition | Discovered | Skipped | Executed | Passed | Failed | Timeout/Err | Passed / Executed | Passed / Discovered |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Pre-ES2015 (baseline) | 13,917 | 0 | 13,909 | 13,544 | 365 | 8 | 97.4% | 97.3% |
| ES2015 | 10,788 | 160 | 10,620 | 10,498 | 122 | 8 | 98.9% | 97.3% |
| ES2016 | 100 | 0 | 99 | 99 | 0 | 1 | 100.0% | 99.0% |
| ES2017 | 775 | 344 | 431 | 431 | 0 | 0 | 100.0% | 55.6% |
| ES2018 | 4,781 | 735 | 4,046 | 3,870 | 176 | 0 | 95.7% | 80.9% |
| ES2019 | 127 | 0 | 127 | 105 | 22 | 0 | 82.7% | 82.7% |
| ES2020 | 1,984 | 1,604 | 380 | 377 | 3 | 0 | 99.2% | 19.0% |
| ES2021 | 444 | 128 | 316 | 302 | 14 | 0 | 95.6% | 68.0% |
| ES2022 | 5,361 | 296 | 5,065 | 2,788 | 2,277 | 0 | 55.0% | 52.0% |
| ES2023 | 277 | 56 | 221 | 218 | 3 | 0 | 98.6% | 78.7% |
| ES2024 | 1,077 | 870 | 207 | 109 | 98 | 0 | 52.7% | 10.1% |
| ES2025 | 1,180 | 813 | 367 | 294 | 73 | 0 | 80.1% | 24.9% |
| Annex B | 1,156 | 44 | 1,110 | 909 | 201 | 2 | 81.9% | 78.6% |
| Stage 3 | 5,696 | 5,593 | 103 | 10 | 93 | 0 | 9.7% | 0.2% |
| **Total** | **47,692** | **10,672** | **37,001** | **33,554** | **3,447** | **19** | **90.7%** | **70.4%** |

_Fully-skipped buckets (no tests executed) folded into Total: Unmapped (29)._

## Package Structure

```
token/          Token types and source locations
errors/         JavaScript error variants and formatting helpers
lexer/          Tokenizer
ast/            AST node definitions
parser/         Recursive descent parser with Pratt precedence
static_semantics/  Early-error and declaration-fact analysis
compiler/       Bytecode compiler plus legacy closure-conversion experiments
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
