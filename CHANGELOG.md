# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For changes before this file existed, see `git log`.

## [Unreleased]

_No unreleased changes._

## [0.2.0] — 2026-04-22

400 commits since v0.1.0 (~80 user-facing changes). Themes summarised
below; full list via `git log v0.1.0..v0.2.0`.

### Conformance

test262: **86.6% strict / 85.0% non-strict** (was 39.4% at v0.1.0).
Unit tests: **978 passing** (was 507).

### Major capabilities added

- **ES Modules** — `import`/`export` declarations, live bindings, default
  function hoisting, sibling-fixture resolution, module-code test262
  integration.
- **Generator functions** — `function*`, `yield`, `yield*`, iterator
  delegation, `.throw()` / `.return()` protocol, rest parameters in
  generators.
- **Date** — full constructor, prototype methods, static methods, and
  `JSON.stringify` interop.
- **Proxy and Reflect** — all 13 traps with invariant checks, full
  `Reflect` namespace, Map/Set/Promise conformance through proxies.
- **TypedArray, ArrayBuffer, DataView** — typed array views over buffers.
- **Class public fields** — instance and static fields with strict-mode
  initializers, `defineProperty` trap interaction, and derived-class field
  ordering.
- **`eval()`** — direct vs indirect call-site semantics, scope chain,
  `EvalDeclarationInstantiation`, constructability enforcement, nested
  grouping detection.
- **AggregateError** — used by `Promise.any`.
- **RegExp named capture groups** and `RegExpStringIteratorPrototype`,
  callback-form `String.prototype.replace`.
- **`$262` realm helpers** — `evalScript`, `createRealm`, realm isolation;
  `Function` constructor.
- **Annex B legacy** — function-body hoisting (§B.3.2.1, +82 tests),
  eval-scope hoisting (§B.3.3.3, +67 tests).
- **Module loader interface** — pluggable module resolution
  (`ModuleLoader`).

### Stage A / B / C architecture

- **Stage A** — `interpreter/` package split into `interpreter/runtime/`
  (types + helpers) and `interpreter/stdlib/` (built-ins setup), plus
  `HostEnv` extraction and a four-file split of `builtins_object.mbt`.
- **Stage B.1** — `[[Set]]` dispatcher with correct receiver threading
  and landing rule (+30 tests).
- **Stage C** — `PropertyBag` consolidation: `ObjectData`, `ArrayData`,
  `MapData`, `SetData`, `PromiseData` now share one property
  representation; previous side-table maps retired.

### Spec-correctness sweeps

- §10.2.11 parameter-environment / body-environment split for Ext
  callables (+27 tests); applied in implicit-`super()` constructor path.
- §15.2.5 named-function-expression self-name binding installed on a
  dedicated wrapper environment.
- §19.2.1.3 eval-declared-arguments early error (+58 tests).
- Reflect bundle: Symbol keys, receiver data reads, Map/Set/Promise
  conformance (+18 tests).
- `Error.isError` switched from hardcoded class-name allowlist to a
  per-Environment registry.
- Four pre-Stage-C `TypeError` gates for non-writable / non-extensible /
  getter-only / non-configurable property operations.
- Method-shorthand functions correctly marked non-constructors.
- User-function and bound-function property order: `length` precedes
  `name`, matching the spec.
- `Number.prototype.toString` `length=1`, `undefined` radix defaults to
  10.
- `length=1` restored on timer / microtask built-ins per WHATWG.
- Strict-mode prerequisite bundle: leak fixes, generator validation,
  reserved-word enforcement.
- P0–P4 compliance sweep: error diagnostics, generator methods,
  destructuring defaults, Symbol-keyed object descriptors, function
  property descriptors, `Array` defineProperty targets.
- ES spec evaluation order: callee resolved before arguments.
- Class field invariants, derived-class field ordering, Proxy
  `defineProperty` trap result checking.

### Performance

- Benchmarking foundation (`benchmarks/` package) with dual measurement
  surfaces (`@bench.T` blocks + CLI runner) and a GitHub Actions workflow
  producing weekly CSV snapshots.
- Removed fast-path duplicates for `Array.prototype` iteration methods
  (`forEach`, `map`, `filter`, `find`, `findIndex`, `some`, `every`) so
  prototype semantics are no longer bypassed.

### Breaking changes (pre-1.0, all intentional)

**External `pub` surface** (mooncakes consumers):

- Lib root: removed demo `fib` and `sum` (placeholder scaffolding,
  unrelated to engine functionality).
- `run` / `run_with_event_loop` / `run_module` / `run_modules` gained
  optional `annex_b?` parameter — backward-compatible at call sites.
- `JsException` moved from `interpreter/` to `interpreter/runtime/`.
  Code matching on `@interpreter.JsException` must update to
  `@runtime.JsException`.

**Internal interpreter consumers** (anyone embedding `interpreter/runtime/`
directly — exhaustive matches and pattern destructures need updates):

- `Value` enum gained `Proxy(ProxyData)` variant.
- `Callable` enum: `ClassConstructor` payload restructured into
  `ClassConstructorData` struct; new variant
  `NonConstructableInterpreterCallable`.
- `Signal::BreakSignal` / `ContinueSignal` payloads extended with
  `Value?` for generator-context labeled break/continue.
- `ObjectData` / `ArrayData` / `MapData` / `SetData` / `PromiseData` now
  embed `PropertyBag`; the previous flat `properties`/`symbol_properties`/
  `descriptors` fields are gone.
- `FuncData` / `FuncDataExt` gained `strict`, `has_name_binding`,
  `is_method` fields.
- AST: `StringLit` gained a `Bool` (template-literal flag);
  `TryCatchStmt` binding `String?` → `Pattern?`; `ClassExpr`/`ClassDecl`
  body `Array[ClassMethod]` → `Array[ClassMember]`. Many new
  expression/statement variants for generators, async/await, and ES
  modules.
- `make_native_func` signature: positional → labelled (`name~`,
  `length?`).

### Internal

- Cleared 49 of 50 `moon check` warnings; the remaining one was a
  structural alias collision resolved by renaming the local `bench/`
  package to `benchmarks/`.
- Refreshed test262 reporting to per-mode rates throughout docs.
- CHANGELOG.md introduced (this file); v0.1.0 retrospectively tagged.

## [0.1.0] — 2026-02-06

First published release on mooncakes.io, at commit [`fede44e`]. Minimal
JavaScript tree-walking interpreter written in MoonBit, self-hosting via
the JS target. Reconstructed retrospectively — original development
covered 192 commits between `ba59e1b` and `fede44e`; this section
summarises the end state rather than enumerating individual changes.

### Conformance at release

test262: **9,545 / 24,213 passed (39.4%)** — 25,381 skipped, 14,668
failed, 56 timeouts. Unit tests: 507 passing on both WASM-GC and JS
targets.

Built up over Phases 1–6L:

- **Phase 1–5** (6,351 passes) — core language, classes, promises,
  iterators, skip-list cleanup, object spread, `new.target`.
- **Phase 6A–6G** (+~2,350) — parser fixes, prototype-chain compliance,
  destructuring in more contexts, tagged templates, object method
  parameters.
- **Phase 6H** (+1,202) — error prototype chain for `instanceof Error`.
- **Phase 6I–6L** (+56) — leading decimal literals, canonical array
  indices, `Number.prototype` `this`-validation, `String.split` limit.

### Capabilities

- Lexer, parser, AST, and tree-walking interpreter over a tagged-union
  `Value` type.
- Classes with constructors, `super`, static members.
- Promises with a full event loop and microtask queue.
- Timer APIs: `setTimeout`, `clearTimeout`, `setInterval`,
  `clearInterval`.
- ES6 collections: `Map`, `Set`, `WeakMap`, `WeakSet`.
- `Symbol` primitive and well-known symbols (`Symbol.iterator`,
  `Symbol.hasInstance`, `Symbol.toPrimitive`, …).
- Iteration protocol via `Symbol.iterator`; `for-of`, `for-in`, and
  destructuring iteration.
- Error class hierarchy: `TypeError`, `RangeError`, `ReferenceError`,
  `SyntaxError`, `URIError`, `EvalError`.
- Unicode coverage for `String.prototype` methods.
- Tagged templates, rest/spread, optional chaining, nullish coalescing.
- `instanceof` with `Symbol.hasInstance`, `Object.setPrototypeOf`,
  `String.raw`.

### Self-hosting

Compiles to JavaScript via `moon build --target js` and runs on Node.js.
Backend-specific argv handling (`.js.mbt` / `.wasm.mbt` / `.wasm-gc.mbt`
files) and Error `toString` fixes landed to make the JS target correct.

### Known limitations at 0.1.0

Drove the post-0.1.0 work in v0.2.0:
`Object.defineProperty`/`defineProperties` (1,350 fails), RegExp (671),
DataView / TypedArray (311), eval-code (205), generator functions (160),
Unicode escapes in identifiers (479). See `docs/ROADMAP.md` at this
release for the full failure breakdown.

[Unreleased]: https://github.com/dowdiness/js_engine/compare/v0.2.0...main
[0.2.0]: https://github.com/dowdiness/js_engine/compare/v0.1.0...v0.2.0
[0.1.0]: https://mooncakes.io/docs/dowdiness/js_engine@0.1.0
[`fede44e`]: https://github.com/dowdiness/js_engine/commit/fede44e
