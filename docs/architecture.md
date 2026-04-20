# Architecture

> **Status:** principles only. Specific struct names, field names, and internal file paths are intentionally omitted — they drift from the code faster than docs update. For the current public API use `moon ide outline interpreter/`; for the completed restructuring analyses see [archive/](archive/).

## Shape

`js_engine` is a tree-walking interpreter over a three-stage pipeline:

- **Lexer** (`lexer/`) — source to tokens
- **Parser** (`parser/`) — tokens to AST, recursive descent with Pratt precedence for expressions
- **Interpreter** (`interpreter/`) — AST evaluated directly; no bytecode, no JIT

The CLI (`cmd/main/`) wraps the pipeline. Library consumers use the facade exported from the top-level `js_engine` package.

## Package Boundaries

Three conceptual groups live inside `interpreter/`, and since the April-2026 restructure the compiler enforces a one-way dependency between the first two:

- **Runtime** (`interpreter/runtime/`) — execution engine, value model, environment, property descriptors, host integration.
- **Stdlib** (`interpreter/stdlib/`) — the JavaScript standard library (Array, Object, Promise, Proxy, Reflect, TypedArray, …).
- **Rule:** `stdlib → runtime` is allowed; `runtime → stdlib` is not. A hooks struct lets stdlib register callbacks that the runtime invokes at well-defined points, breaking what would otherwise be a cycle.

This boundary exists so that spec-level concerns (property descriptor invariants, scope resolution, operator semantics) can be reasoned about without considering any particular built-in.

## Design Principles

1. **Functions are objects.** Callability is an attribute of an object, not a separate kind. The spec requires functions to carry arbitrary properties; conflating the two categories would force a wrapper everywhere.

2. **Exceptions piggyback on MoonBit's error channel.** JavaScript `throw` compiles to a MoonBit `raise` carrying a typed suberror for JS exceptions. `try/catch/finally` maps cleanly onto MoonBit's error-handling constructs. Unrecoverable defects go through `abort`, which is intentionally uncatchable — the two channels don't mix.

3. **Non-exceptional control flow uses a typed signal, not exceptions.** `return`, `break`, and `continue` propagate through the evaluator as values, not via the error channel. This separates "loop exited normally" from "the program faulted" at the type level: the former is cheap, the latter routes through the catchable error channel.

4. **Property descriptor semantics live in one place.** The runtime is the sole authority for `[[DefineOwnProperty]]` constraint checks (writable/configurable/accessor coherence). Built-ins call into shared helpers rather than re-implementing invariant checks per method. Spec fixes land once.

5. **Exotic variants share a single property bag.** Array, Map, Set, Promise, and plain Object each carry the same bag abstraction covering string-keyed properties, symbol-keyed properties, and their descriptors. A fix made for one exotic variant applies to all.

6. **Generators use statement replay.** A generator body is re-executed from the top on each `.next()` call, replaying past statements and resuming at the saved program counter. Avoids maintaining a separate frame stack and tagged suspension points; trades re-execution cost for simpler state management.

## Host Integration

The interpreter is parameterized over a host environment responsible for side effects: `console` output, the microtask queue, the timer queue, and the module registry. Hosts drive the event loop via explicit microtask and timer checkpoints.

The `@js_engine.run` facade drains both queues before returning, matching the WHATWG checkpoint model. `@js_engine.run_with_event_loop` hands the interpreter back to the caller so hosts can schedule microtasks and timers on their own cadence — useful for integrating into existing event loops.

## Value Model

JavaScript values are represented as a MoonBit enum whose variants cover:

- primitives (number, string, boolean, null, undefined, symbol)
- ordinary objects
- the exotic object kinds with distinct internal semantics (arrays, maps, sets, promises, proxies)

The variant-level distinction between "ordinary object" and each exotic kind exists because the spec gives each exotic its own internal method overrides. Rather than a single polymorphic object with an exotic tag, the spec's per-kind semantics map naturally onto a sum type. Use `moon ide outline interpreter/runtime/` for the current variant list.

## Related Documents

- [ROADMAP.md](ROADMAP.md) — current conformance status and in-progress structural work
- [archive/architecture-redesign-2026-04-15.md](archive/architecture-redesign-2026-04-15.md) — completed April-2026 restructuring (ExecContext, runtime/stdlib split, timer API, descriptor consolidation)
- [archive/2026-04-09-structural-refactoring.md](archive/2026-04-09-structural-refactoring.md) — earlier structural work that produced the current file layout
- [architecture-redesign-2026-04-17-probes.md](architecture-redesign-2026-04-17-probes.md) — exploratory pressures for the next phase
