# js_engine

A minimal JavaScript tree-walking interpreter written in [MoonBit](https://www.moonbitlang.com/).

- Conformance: 86.6% strict / 85.0% non-strict on test262 (each file is run in both modes, reported separately). See [docs/ROADMAP.md](docs/ROADMAP.md).
- Self-hosting: compiles to JavaScript via MoonBit's JS target and runs on Node.js.

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

```moonbit nocheck
let (output, result) = @js_engine.run("console.log(1 + 2)")
// output = ["3"], result = "undefined"
```

The public entry points are defined in [`js_engine.mbt`](js_engine.mbt):

- `run` — evaluate a script; drains microtasks and timers before returning
- `run_module` / `run_modules` — evaluate one or more ES modules and collect exports
- `run_with_event_loop`, `run_microtask_checkpoint`, `run_timer_checkpoint`,
  `has_pending_microtasks`, `has_pending_timers` — for hosts that want to drive the event loop themselves

## Supported Language

Core ES5 plus selected ES6+ features: `let` / `const` / `var`, arrow functions, closures, classes, `for` / `while` / `for-in` / `for-of`, `try` / `catch` / `finally`, template literals, destructuring, spread / rest, ES Modules, Promises + microtasks, `setTimeout` / `setInterval`, ES6 Proxy (13 traps) + Reflect API (13 methods), TypedArrays (9 types), ArrayBuffer, DataView, RegExp, JSON, Map / Set / WeakMap / WeakSet, generators, Symbols.

For current conformance per category, see [docs/ROADMAP.md](docs/ROADMAP.md).

## Package Structure

```
token/          Token types and source locations
lexer/          Tokenizer
ast/            AST node definitions
parser/         Recursive descent parser with Pratt precedence
interpreter/    Tree-walking evaluator with closures and scope chains
cmd/main/       CLI entry point
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
- [docs/ROADMAP.md](docs/ROADMAP.md) — current status, failure breakdown, next targets
- [docs/GLOSSARY.md](docs/GLOSSARY.md) — terminology used in the code and docs
- [AGENTS.md](AGENTS.md) — MoonBit coding conventions (also used by AI agents)

## License

Apache-2.0
