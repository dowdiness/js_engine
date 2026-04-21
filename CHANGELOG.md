# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For changes before this file existed, see `git log`.

## [Unreleased]

### Added

- Implement Annex B §B.3.2.1 function-body hoisting with spec skip check
  (+82 test262 passes). [`38beeba`]
- Implement Annex B §B.3.3.3 eval-scope hoisting (+67 test262 passes). [`5eded5e`]
- Implement §10.2.11 parameter-environment / body-environment split for Ext
  callables (+27 test262 passes). [`b2b8ad3`]
- Implement §19.2.1.3 eval-declared-arguments early error
  (+58 test262 passes in eval-code/direct mode). [`d909522`]
- Resolve sibling `_FIXTURE.js` imports in the test262 module-test runner.
  [`43f258c`]
- Register `InternalError` constructor alongside the other NativeErrors.
  [`99705b2`]

### Fixed

- Add four spec-compliant `TypeError` gates that were missing for non-object
  targets, non-callable callbacks, and invalid descriptors (PR #70). [`e9622a6`]
- Method-shorthand functions are now correctly marked as non-constructors
  (PR #71). [`0eadc5a`]
- Implement `[[Set]]` dispatcher with correct receiver threading and landing
  rule, Stage B.1 (PR #69, +30 test262 passes). [`ab5c009`]
- Apply §10.2.11 split in the implicit-`super()` constructor path. [`51548b6`]
- Limit §15.2.5 self-name binding to named `FunctionExpression` only
  (was incorrectly applied more broadly). [`b800a2e`]
- Install `arguments` object before evaluating class-constructor defaults.
  [`6834bdd`]
- Install named-function-expression self-name binding on a dedicated wrapper
  environment, not the outer scope (§15.2.5). [`9a935af`]
- Refine §10.2.11 split gate and function-name binding edge cases. [`b56f169`]
- Static built-in functions are now non-constructable
  (`new Array.isArray()` rejects). [`2c911bc`]
- `Error.isError` now uses a per-Environment registry instead of a hardcoded
  class-name allowlist, fixing false negatives for user-defined Error
  subclasses. [`576efd7`]
- Include `InternalError` in the `Error.isError` class-name list. [`6c98043`]
- Reflect bundle: fix Symbol keys, receiver data reads, and Map/Set/Promise
  handling (PRs #17–#19/#60, +18 test262 passes). [`cda3a2f`]
- Restore WHATWG-compliant `length=1` on timer/microtask builtins. [`d587c33`]
- Restore explicit `length=1` on one-arg `$262` helpers. [`51ff34c`]
- `Number.prototype.toString`: set `length=1` and treat `undefined` radix as
  10. [`6aca142`]
- Reorder user-function and bound-function properties so `length` precedes
  `name`, matching the spec. [`0157c03`, `9319403`]

### Changed

- Consolidate five duplicate pattern-walker functions into a single
  `walk_pattern_idents` helper. [`a265b22`]
- Extract `bind_ext_params_and_exec_body` and port it to `construct.mbt` as a
  shared helper for external callables. [`fc40b7c`, `32ee9f0`]

### Internal

- Rename local `bench/` package to `benchmarks/` to clear an alias collision
  with `moonbitlang/core/bench`. [`8ee575a`]
- Clear 49 of 50 `moon check` warnings (unused `using` aliases, missing core
  imports, deprecated `fn(..) {}` callbacks, unused `raise` annotations).
  [`27ca2f1`]
- Refresh `test262` figures in README to per-mode reporting (86.6% strict /
  85.0% non-strict). [`8b878f5`]

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

Driving the post-0.1.0 work under [Unreleased]:
`Object.defineProperty`/`defineProperties` (1,350 fails), RegExp (671),
DataView / TypedArray (311), eval-code (205), generator functions (160),
Unicode escapes in identifiers (479). See `docs/ROADMAP.md` at this
release for the full failure breakdown.

[Unreleased]: https://github.com/dowdiness/js_engine/compare/fede44e...main
[0.1.0]: https://mooncakes.io/docs/dowdiness/js_engine@0.1.0
[`fede44e`]: https://github.com/dowdiness/js_engine/commit/fede44e
[`0157c03`]: https://github.com/dowdiness/js_engine/commit/0157c03
[`27ca2f1`]: https://github.com/dowdiness/js_engine/commit/27ca2f1
[`2c911bc`]: https://github.com/dowdiness/js_engine/commit/2c911bc
[`32ee9f0`]: https://github.com/dowdiness/js_engine/commit/32ee9f0
[`38beeba`]: https://github.com/dowdiness/js_engine/commit/38beeba
[`43f258c`]: https://github.com/dowdiness/js_engine/commit/43f258c
[`51548b6`]: https://github.com/dowdiness/js_engine/commit/51548b6
[`51ff34c`]: https://github.com/dowdiness/js_engine/commit/51ff34c
[`576efd7`]: https://github.com/dowdiness/js_engine/commit/576efd7
[`5eded5e`]: https://github.com/dowdiness/js_engine/commit/5eded5e
[`6834bdd`]: https://github.com/dowdiness/js_engine/commit/6834bdd
[`6aca142`]: https://github.com/dowdiness/js_engine/commit/6aca142
[`6c98043`]: https://github.com/dowdiness/js_engine/commit/6c98043
[`8b878f5`]: https://github.com/dowdiness/js_engine/commit/8b878f5
[`8ee575a`]: https://github.com/dowdiness/js_engine/commit/8ee575a
[`9319403`]: https://github.com/dowdiness/js_engine/commit/9319403
[`99705b2`]: https://github.com/dowdiness/js_engine/commit/99705b2
[`9a935af`]: https://github.com/dowdiness/js_engine/commit/9a935af
[`a265b22`]: https://github.com/dowdiness/js_engine/commit/a265b22
[`ab5c009`]: https://github.com/dowdiness/js_engine/commit/ab5c009
[`b2b8ad3`]: https://github.com/dowdiness/js_engine/commit/b2b8ad3
[`b56f169`]: https://github.com/dowdiness/js_engine/commit/b56f169
[`b800a2e`]: https://github.com/dowdiness/js_engine/commit/b800a2e
[`cda3a2f`]: https://github.com/dowdiness/js_engine/commit/cda3a2f
[`d587c33`]: https://github.com/dowdiness/js_engine/commit/d587c33
[`d909522`]: https://github.com/dowdiness/js_engine/commit/d909522
[`e9622a6`]: https://github.com/dowdiness/js_engine/commit/e9622a6
[`fc40b7c`]: https://github.com/dowdiness/js_engine/commit/fc40b7c
