# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For changes before this file existed, see `git log`.

## [Unreleased]

### Changed (breaking, `interpreter/stdlib` package consumers)

- Stage 2c migration of the WeakMap/WeakSet prototype caches into `RealmState`
  changed three public stdlib signatures:
  - `setup_weakmap_set_builtins(env, well_known_symbols)` →
    `setup_weakmap_set_builtins(env, well_known_symbols, realm_state)`.
  - `get_weakmap_method(data, prop)` → `get_weakmap_method(prop, realm_state)`.
    Dropped the previously-unused `ObjectData` receiver param; the helper is
    a pure prototype-chain lookup against `realm_state.weakmap_prototype`
    (not a JS `[[Get]]` implementation — does NOT consult own properties).
  - `get_weakset_method(data, prop)` → `get_weakset_method(prop, realm_state)`,
    same shape as `get_weakmap_method`.

  In-tree, only `interpreter/stdlib/builtins.mbt` calls
  `setup_weakmap_set_builtins`; the two helper functions had no other callers
  before this change. Direct downstream consumers of `interpreter/stdlib`
  must update call sites.

## [0.2.3] — 2026-05-11

Conformance-focused patch release. Closes the strict-mode legacy octal /
non-octal-decimal early-error work queued from PR #91, plugs three
walker gaps that silently swallowed those violations, ships PerformEval
§19.2.1.1 step-8-14 early-error checks, accepts ES2017 trailing commas
in non-arrow function parameter lists, and rejects three leading-zero
numeric literal forms that the lexer previously misclassified.

| Mode | v0.2.2 P/E (tip `f8b760c`) | v0.2.3 P/E (tip `955ed21`) | Δ |
|---|---|---|---:|
| strict | 87.8% (23,365 / 26,599) | **89.4%** (23,798 / 26,607) | **+433** |
| non-strict | 86.3% (24,815 / 28,767) | **87.8%** (25,244 / 28,762) | **+429** |

CI runs: v0.2.2 baseline [24923229192]; v0.2.3 release-candidate tip
[25634627598]. The post-tag CI run on the actual release commit is the
authoritative source per `docs/RELEASING.md` step 5; if the numbers
above differ from the post-tag run, the CHANGELOG will be amended in a
follow-up commit (the tag annotation is allowed to remain at these
release-candidate numbers).

Unit tests: **1227 passing** (was 1036 at v0.2.2).

[24923229192]: https://github.com/dowdiness/js_engine/actions/runs/24923229192
[25634627598]: https://github.com/dowdiness/js_engine/actions/runs/25634627598

### Strict-mode legacy octal/non-octal-decimal early errors (PRs #95, #98)

ES262 §12.8.4.1 (NumericLiteral) and §12.9.4.1 (StringLiteral) static
early errors are now enforced in strict-mode code:

- **String escapes**: `\1`-`\7` (LegacyOctalEscapeSequence) and `\8`/`\9`
  /`\0`+digit (NonOctalDecimalEscapeSequence) now raise `SyntaxError` in
  strict mode. Bare `\0` (NUL) remains valid.
- **Numeric literals**: `0777` (LegacyOctalIntegerLiteral) and `08`/`09`
  (NonOctalDecimalIntegerLiteral) now raise `SyntaxError` in strict
  mode.
- **Coverage across all literal positions**: primary expressions,
  object property keys (string and numeric), class member keys
  (method/field, string and numeric), object-pattern destructuring
  keys, and module specifier strings (`import x from "\1"`).
- **Covered strict-mode entry points**: scripts and eval bodies
  (existing), module bodies (modules are always strict per §16.2.1.6),
  and `new Function` / `new GeneratorFunction` / `new AsyncFunction`
  constructor bodies with `"use strict"` directives. (`AsyncGeneratorFunction`
  remains a separate entry point, scoped out for now.)

Annex B compatibility is preserved in non-strict code: `\1` still
evaluates to `\u{0001}`, `0777` to `511`, `08` to `8`. The new
`Token.lex_form` field and AST `lex_form` propagation make the
provenance available to the existing `validate_block_early_errors_*`
walker; class member keys (previously unvisited) are now visited too.

### Walker completeness (PR #98)

Three positions in the early-error walker fell through the wildcard
arm and silently swallowed legacy-octal violations:

- `YieldExpr` argument (`yield "\1"` in strict generators)
- `SuperCall` arguments (`super("\1")` in derived constructors)
- `ClassExpr` / `ClassDecl` superclass expression (`extends ("\1", X)`)

All three now have explicit walker arms. The class-heritage arm
correctly enforces ES262 §15.7.1 — class definitions are strict-mode
code in their entirety, including the `extends` expression, regardless
of the surrounding script's strictness.

### PerformEval early-error checks (PR #100, §19.2.1.1)

Direct `eval(...)` calls now run §19.2.1.1 steps 8-14 against the
parsed eval body before evaluating it. A new `scan_eval_contains`
walker computes the four §15.2.12 Contains predicates in one pass:

- `super(...)` outside a derived constructor → `SyntaxError`
- `super.X` outside a method → `SyntaxError`
- `new.target` outside a function → `SyntaxError`
- `arguments` reference inside a class field initializer → `SyntaxError`

The walker descends through ordinary expressions and arrow function
bodies (which are transparent to `super`/`this`/`arguments`/`new.target`
per §15.2.12), but stops at non-arrow function/method/class-member
boundaries — including their `FormalParameters`. Arrow-parameter
defaults are visited so an `arguments`-reference in
`(x = arguments) => ...` is correctly diagnosed.

A new `[[InClassFieldInitializer]]` execution-context flag carries the
class-field-initializer position to the eval call so the
`arguments`-in-class-field check fires only when applicable.

### Leading-zero fractional/exponent numeric literals (PR #99)

Three numeric literal forms that the lexer previously mis-tokenised
are now rejected in line with ES262 §12.8.3 + Annex B §B.1.1:

- `01.2`, `01e2`, `00.5`, `001.2`, `07.5` → `SyntaxError` in **all
  modes**.  LegacyOctalIntegerLiteral is not a sub-production of
  DecimalLiteral, so these productions have no parse.
- `08.1`, `08e2` → valid in **sloppy**, `SyntaxError` in **strict**.
  NonOctalDecimalIntegerLiteral is an Annex B addition forbidden in
  strict mode.

`0.5`, `0.1e2`, and member-access on legacy-octal-prefix integers
(`01.toString()` evaluates to `"1"` in sloppy) remain valid. Codex
review caught a regression where the original "reject any `.` after a
LegacyOctal-prefix" rule broke `01.toString()` member-access; the
shipped narrowing rejects `.` only when followed by a `DecimalDigit`.

### Trailing comma in non-arrow function parameter lists (PR #103)

ES2017 trailing commas are now accepted in named function
declarations, function expressions, generators, and async functions:

```js
function f(a, b,) {}
function* g(a,) { yield a }
const h = function (a, b,) { return a + b };
```

The simple `parse_params` was missing a trailing-comma break that the
slow-path `parse_params_ext` (handling rest/default/destructure params)
already had. Three-line fix mirroring the existing break.

Codex review surfaced an adjacent pre-existing bug — `parse_params_ext`
accepts `function f(...rest,)` because the trailing-comma break runs
before the rest-rejection check. ES2017 forbids it; tracked for a
follow-up patch.

### CLI and tooling

- **CLI gains a `--version` flag** and a clean Wasm exit path. CLI
  argument parsing migrated to `@argparse` (was bespoke).
- **CI test262 job summary now includes a per-edition pass-rate table.**
  Generated by `scripts/classify-by-edition.py`; visible at a glance on
  every PR run.
- **Unicode `ID_Start` / `ID_Continue` tables generated from
  `DerivedCoreProperties`** rather than hand-maintained, eliminating
  drift against the active Unicode version.
- **actionlint workflow** added to catch shell-script errors in
  GitHub Actions YAML.
- **`make test262-report` pulls release-grade conformance numbers
  directly from CI artifacts** (per the test262-reporting convention
  documented in `AGENTS.md`).
- Repo scripts moved from root to `scripts/`; CI workflow paths updated
  to match.

### Internal API changes (pre-1.0, no known downstream callers)

These changes affect symbols exposed by `@interpreter/runtime`,
`@ast`, and `@token`. They are listed for transparency, but per pre-1.0
convention this remains a `patch` release because the symbols had no
known downstream consumers when v0.2.3 was cut. Direct consumers of
these packages will see source-breaking changes (renamed constructors,
extended enum variants, signature changes) and should review the list
below before upgrading.

- **Constructor convention rename**: `MapData::new`, `PropertyBag::new`,
  `SetData::new` renamed to `MapData::MapData`, `PropertyBag::PropertyBag`,
  `SetData::SetData` — matching the project's "custom constructor
  inside struct body" idiom (see `AGENTS.md` Quick Reference). Callers
  using the old names must rename.
- **`instanceof_prototype_chain` signature change**: from
  `(Value, Value, Environment) -> Value` to
  `(Value, Value, Interpreter) -> Value raise`.
- **AST enum payload extensions**: `Expr::NumberLit` and `Expr::StringLit`
  gained a `@token.LexForm` payload; `Stmt::ImportDecl`,
  `Stmt::ExportNamedDecl`, and `Stmt::ExportAllDecl` gained the same.
  External pattern matches on these variants must accept the new
  parameter.
- **AST: new `Expr::ArrayHole(@token.Loc)` variant** for elision in
  array literals (`[1,,3]`). Breaks exhaustive matches on `Expr` in
  external consumers.
- **AST: `PropPat` gained `key_lex_form: @token.LexForm` and
  `key_loc: @token.Loc` fields** (PR #99) for destructuring
  pattern-key strict-mode validation.
- **`@interpreter/runtime`: `ArrayData` gained `holes: Map[Int, Unit]`
  and `mut extensible: Bool` fields** (PR #91 + PR #101) — additive,
  but visible on `pub(all) struct ArrayData` field listings.
- **`@interpreter/runtime`: `ModuleLoader::inner` removed.** Marked
  `#deprecated` since v0.2.1; removal completes the standard two-release
  deprecation-then-removal cycle.
- **New `LexForm` enum** in `@token`: `LexNormal`,
  `StringLegacyOctalEscape`, `NumberLegacyOctalInt`,
  `NumberNonOctalDecimalInt`. Used by AST and the early-error walker
  to track strict-mode-relevant literal provenance.
- **`@token: Token` gained a `lex_form: LexForm` field; `Token::new`
  signature gained an optional `lex_form?: LexForm` labeled parameter.**
  The labeled parameter is backward-compatible — existing callers that
  omit it continue to compile.
- **`@interpreter/runtime` additions** (called cross-package by
  `interpreter/stdlib`, so correctly `pub`):
  `validate_function_constructor_params`,
  `Interpreter::validate_block_early_errors`,
  `format_if_js_error` (in `@errors`),
  `name_message_if_js_error` (in `@errors`).
- **Property descriptor refactor (PR #101)**: `PropDescriptor` gained a
  `mut is_accessor : Bool` field; descriptor construction goes through
  the runtime/property authority rather than ad-hoc bag writes at call
  sites.
- **`EvalContainsScan` struct + `scan_eval_contains` fn +
  `EvalContainsScan::new` ctor are private to `@interpreter/runtime`**
  (PR #105 — were briefly `pub(all)` / `pub` in PR #100 but had zero
  cross-package consumers; narrowed before downstream consumers
  could form).

### Tests

- 1227 passing (was 1036 at v0.2.2). The +191 unit tests cover:
  - Strict-mode legacy octal early-error positive/negative cases
    (string escapes, numeric literals, all literal positions and
    strict-mode entry points)
  - Walker visit positions (`YieldExpr`, `SuperCall`, class heritage)
  - Eval `super`/`new.target`/`arguments` early-error positive cases
    plus arrow-parameter-default coverage
  - Leading-zero fractional/exponent numeric literal positive cases
    (`0.5`, `0.1e2`, `01.toString()`) and negative cases (`01.2`,
    `01e2`, `00.5`, `08.1`/`08e2` in strict)
  - Trailing-comma params in named function, generator, and nameless
    function-expression positions; panic tests for `(,)` and `(a,,)`

[0.2.3]: https://github.com/dowdiness/js_engine/releases/tag/v0.2.3

## [0.2.2] — 2026-04-25

Conformance-focused patch release. Closes the three TypedArray
string-key follow-ups queued from the v0.2.1 wide-catch fix, replaces
the IteratorClose direct-bag walk with a [[Get]]-dispatcher call, and
extracts a shared key classifier.

All five queued commits passed CI on `main` before the tag was cut.
Unit tests: **1036 passing** (was 1031 at v0.2.1).

### Fixed

- **TypedArray string-key `"-0"` no longer creates expando properties.**
  Per §7.1.21 CanonicalNumericIndexString, `"-0"` is a canonical numeric
  string but not a valid integer index — element access must be
  intercepted (read returns `undefined`, write is a no-op) rather than
  falling through to ordinary property creation. `NaN`, `Infinity`,
  fractional, and negative canonical strings were already filtered by
  the existing IEEE round-trip check; only `"-0"` escaped.
- **TypedArray `[[Set]]` is now receiver-sensitive (§10.4.5.5,
  §10.4.5.16).** When the receiver differs from the TypedArray itself
  (e.g. `Reflect.set(ta, "0", 7, otherReceiver)`), an in-range index
  now defines on the receiver instead of writing through to the
  underlying buffer; an out-of-range index is a no-op. Three call sites
  in `property.mbt` were updated and consolidated through a new
  `typedarray_set_dispatch` helper.
- **IteratorClose (§7.4.10) routes `"return"` lookup through the
  `[[Get]]` dispatcher** instead of walking the `PropertyBag`
  directly. Accessor `return` getters now run; non-callable inherited
  `return` no longer crashes. (Full GetMethod (§7.3.10) including
  Proxy `get` trap on the iterator itself remains scoped out — Proxy
  iterator end-to-end is a separate engine limitation.)

### Changed

- **Internal:** new `classify_typedarray_string_key` helper in
  `string_utils.mbt` consolidates the three TypedArray indexed-element
  classifier sites in `property.mbt`. Package-private; the `-1`
  canonical-invalid sentinel is an implementation detail.
- **Internal:** `StdlibHooks` gains a `typedarray_is_valid_index`
  field (§10.4.5.18 IsValidIntegerIndex). Additive — existing hook
  constructors are source-compatible.
- Stale Stage-B.2 comments in `property.mbt` refreshed to match the
  current dispatcher surface (cosmetic).

### Tests

- +5 regression tests in `interpreter_test.mbt`: accessor `return`
  getter runs on iterator close, non-callable inherited `return` is a
  no-op, TypedArray `Reflect.set` same-receiver writes through, and
  different-receiver in-range / out-of-range cases.

[0.2.2]: https://github.com/dowdiness/js_engine/releases/tag/v0.2.2

## [0.2.1] — 2026-04-24

Conformance-focused patch release. Adds dispatcher infrastructure
(Stages B.2, C, B.3) that rewires several essential internal methods
through a single seam each, plus TypedArray, IteratorClose, parser, and
method-definition spec fixes.

Classified as `patch` under pre-1.0 conventions: most call sites are
additive, and the few tightened / removed runtime internals (listed
under **Internal API changes** below) had no known downstream consumers
when this release was cut. Review that list before upgrading if you
link against `@interpreter/runtime` directly.

test262 against v0.2.0 (both per-mode, both from CI artifacts; the
v0.2.0 row here is the **post-tag** CI run on `f89898a`, which is the
authoritative baseline per `docs/RELEASING.md` — slightly higher than
the pre-release numbers in the v0.2.0 CHANGELOG due to a mid-release
test262 suite update):

| Mode | v0.2.0 P/E (tip `f89898a`) | v0.2.1 P/E (tip `b225cda`) | Δ |
|---|---|---|---:|
| strict | 86.7% (23,054 / 26,601) | **87.8%** (23,359 / 26,598) | **+305** |
| non-strict | 85.1% (24,467 / 28,766) | **86.2%** (24,809 / 28,767) | **+342** |

CI runs: v0.2.0 baseline [24730849102]; v0.2.1 tip [24885185424].

Unit tests: **1031 passing** (was 978 at v0.2.0).

[24730849102]: https://github.com/dowdiness/js_engine/actions/runs/24730849102
[24885185424]: https://github.com/dowdiness/js_engine/actions/runs/24885185424

### Internal API changes (pre-1.0, no known downstream callers)

- `Environment::has`, `Environment::find_with_object`, and
  `Interpreter::has_property` now raise. The B.3 `[[HasProperty]]`
  dispatcher routes through Proxy traps, which can abrupt-complete; the
  non-raising surface was not spec-faithful.
- `Interpreter::construct_value` gained an optional `new_target?`
  parameter. Existing call sites are source-compatible (default
  `None`).
- `@errors` package: removed 10 convenience raise functions
  (`syntax_error(_msg)`, `type_error(_msg)`, `reference_error(_msg)`,
  `range_error_msg`, `uri_error_msg`, `internal_error_msg`) plus
  `JsError::debug` and `is_js_error`. All were zero-call sites
  (confirmed by exhaustive grep across the monorepo). The
  `@errors → @token` coupling is also gone.
- `ModuleLoader::inner` (previously `#deprecated`) removed from the
  public interface.

### TypedArray numeric-string-index correctness

- Fixed wide-catch anti-pattern at the three TypedArray numeric-index
  branches in `property.mbt` (`get_property`, `set_property`,
  `set_computed_property`). The old `try { parse_double + to_number +
  set_index } catch { _ => () }` absorbed `to_number`'s TypeError, so
  `typedArr[0] = Symbol()` in strict mode silently fell through instead
  of throwing. Only `parse_double`'s raise is caught now; `to_number`
  propagates as the spec requires.
- Added §7.1.21 step-1 `"-0"` canonical-invalid guard. Per spec, `"-0"`
  is a canonical numeric index string but `-0𝔽` is not a valid integer
  index, so `typedArr["-0"]` reads must return `undefined` and writes
  must succeed as no-op (no expando). Previously `ToString(-0) = "0" ≠
  "-0"` misclassified it as non-canonical, leaking into ordinary
  property creation.
- `NaN` / `Infinity` / `-Infinity` / fractional (`"1.5"`) canonical
  strings were already handled correctly by an IEEE inequality check
  (`NaN != NaN`, saturated `Inf.to_int() != Inf`) — empirical testing
  confirmed only `"-0"` needed an explicit guard.
- 7 new whitebox tests in `interpreter/interpreter_test.mbt`.

Two spec gaps deferred as follow-ups: receiver-sensitive TypedArray
write per §10.4.5.16 (`Reflect.set` with a distinct receiver), and a
`classify_typedarray_string_key` helper extraction to dedup the three
classifier sites in `property.mbt`.

### IteratorClose + `new.target` threading (PR #74)

- `IteratorClose` completion handling now follows §7.4.10's throw-vs-
  non-throw branching. For throw completions the original error is
  preserved and any error from `return()` is suppressed; for non-throw
  completions a `return()` that throws propagates, and a `return()`
  that returns a non-Object raises TypeError as the spec requires.
- Three missing close sites fixed in `ForOf` variants (`var_kind=None`,
  pattern binding, expression target) across `env.assign`, pattern
  bind/assign, and all abrupt signals.
- Known scope-out: the `"return"` method lookup in `exec_stmt.mbt`
  still walks object bags / prototypes directly rather than going
  through spec `GetMethod`, so iterators with Proxy-wrapped or accessor
  `return` properties are not covered by this fix.
- `construct_value` threads `new.target` through Proxy `construct` traps,
  Proxy no-trap recursion, `BoundFunc` (per §10.4.1.2), implicit `super()`
  via non-`ClassConstructor`, and `Reflect.construct`. The `SuperCall`
  path in `eval_expr.mbt` now binds `<new.target>` in the super-class
  constructor body to the derived constructor.

### Accessor descriptors in property lookup (PR #73)

- `[[Get]]` walks now return accessor descriptors (getters) correctly
  when the own slot stores `Undefined` as the data-property sentinel;
  previous code returned `Some(Undefined)` immediately and masked
  getters at descriptor-only slots.
- `has_property` no longer invokes getters during `[[HasProperty]]`; it
  uses pure `.contains()` checks (or a bare bag lookup when no
  interpreter is in scope) per §7.3.11.
- Consolidated three copies of the 15-entry ECMAScript
  WhiteSpace+LineTerminator codepoint list into a single canonical
  `is_es_whitespace_cp` helper in `interpreter/runtime`. Lexer's
  Unicode-Space-Separator helper deduped similarly. Net −76/+20 lines.
- Merged `parse_binary` + `parse_octal` into
  `parse_radix_literal(s, base)`.

### Strict reserved words as early errors

- Strict-mode `IdentifierReference`, binding, and assignment-target uses
  of reserved-word identifiers are now rejected by the AST early-error
  pass, covering unreachable branches (e.g.
  `"use strict"; if (false) { static; }`) and destructuring assignment
  targets (e.g. `({x: eval} = obj)`).
- Sloppy-mode `static` as an identifier remains accepted.

### Parser: reserved-word identifiers in permitted positions

- `async`, `static`, `get`, `set`, and other contextual keywords are now
  accepted as identifiers where the grammar permits, fixing
  `language/reserved-words` and `language/future-reserved-words`
  regressions.

### Method definitions correctly non-constructable

- Object-literal and class method-shorthand functions now carry
  `is_method : Bool` on `FuncData` / `FuncDataExt`, so
  `new ({m() {}}).m()` and `new (class { m() {} }).prototype.m()` throw
  TypeError per spec MethodDefinitionEvaluation.
- Method-def functions no longer receive an own `prototype` property
  (spec MethodDefinitionEvaluation explicitly skips MakeConstructor for
  methods).

### Stage B.2 — GetOwnProperty + DefineOwnProperty dispatchers

- Introduced `Interpreter::get_own_property` and
  `Interpreter::define_own_property` so §10.1.5, §10.1.6, §10.4.2.1 /
  §10.4.2.4, and §10.5.5 / §10.5.6 all route through one seam. The
  three B.1 approximations in `define_value_on_receiver` are
  behaviorally retired; a handful of B.2-era comments in `property.mbt`
  referencing "Stage B.2 will replace this" are stale and tracked for
  follow-up cleanup.
- Added `PartialDescriptor` to model ES "attribute-absent vs. default"
  correctly through `Object.defineProperty` and friends.
- Added `ArrayData.length_writable` to gate extensions / truncations on
  frozen arrays per §10.4.2; `Array.prototype.push/pop/shift/unshift`
  fast-path mutators now honor it.
- `to_property_key` (§7.1.19) used consistently by
  `Object.defineProperty`, `Object.defineProperties`, and
  `Reflect.defineProperty`.
- Stdlib simplification: net **−1,501 LoC** (347 additions / 1,848
  deletions) across `builtins_object_descriptors.mbt` and
  `builtins_reflect.mbt` as the dispatcher centralizes descriptor
  validation.

test262 delta against v0.2.0 (CI run [24777653260] on tip `a50d293`,
per-mode; compare with v0.2.0 section below for methodology):

| Mode | v0.2.0 P/E | Post-B.2 P/E | Δ | v0.2.0 P/D | Post-B.2 P/D |
|---|---|---|---:|---|---|
| strict | 86.6% (23,039 / 26,598) | **87.1%** (23,158 / 26,599) | +119 | 51.2% | **51.5%** |
| non-strict | 85.0% (24,452 / 28,769) | **85.4%** (24,571 / 28,763) | +119 | 51.3% | **51.5%** |

[24777653260]: https://github.com/dowdiness/js_engine/actions/runs/24777653260

### Stage C — ArrayData PropertyBag embedding

- Moved array named, symbol, length override, indexed descriptor, and
  prototype override state into `ArrayData.bag`.
- Removed the remaining legacy array property side tables so ordinary
  descriptor APIs and runtime lookup observe the same array property state.
- Preserved internal array slots with non-forgeable symbol ids rather than
  string properties.

### Stage B.3 — HasProperty dispatcher

- Added a key-aware `Interpreter::has_property_key` path shared by `in`,
  `Reflect.has`, Proxy `has`, prototype-chain traversal, arrays, and `with`
  binding lookup.
- Proxy `has` traps now receive the actual property key value, including
  Symbols, and trap-missing Proxy targets recurse through the target's
  `[[HasProperty]]`.
- `with` lookup now propagates Proxy `has` and `@@unscopables` abrupt
  completions instead of treating them as absent bindings.
- Array prototype overrides are now honored by ordinary reads and observable
  through `Object.getPrototypeOf`, `Reflect.getPrototypeOf`, and Proxy
  `getPrototypeOf`.
- Callable objects keep the `Function.prototype` fallback for
  `HasProperty`, preserving inherited `call`, `apply`, and `bind`.

## [0.2.0] — 2026-04-22

400 commits since v0.1.0 (~80 user-facing changes). Themes summarised
below; full list via `git log v0.1.0..v0.2.0`.

### Conformance

test262 (each file now run in both strict and non-strict modes and
reported separately — summing would double-count files):

- **Passed / executed**: 86.6% strict (23,039 / 26,598), 85.0%
  non-strict (24,452 / 28,769). This is the conventional "test262
  pass rate" but excludes ~40% of discovered files skipped for
  unimplemented features (Temporal, class-private, BigInt,
  async-iteration, …).
- **Passed / discovered**: 51.2% strict, 51.3% non-strict. Honest
  spec-coverage figure that counts skipped files as un-passed.

Direct comparison with v0.1.0's 39.4% is misleading: that figure was
single-mode passed / executed under the pre-Phase-24 runner, and
per-mode numbers were not computed then. Absolute passing tests rose
from 9,545 (single-mode) to 23,039 strict + 24,452 non-strict.

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
- **Proxy and Reflect** — 12 of 13 traps dispatched with invariant checks
  (`apply`, `construct`, `defineProperty`, `deleteProperty`, `get`,
  `getPrototypeOf`, `has`, `isExtensible`, `ownKeys`, `preventExtensions`,
  `set`, `setPrototypeOf`); full `Reflect` namespace; Map/Set/Promise
  conformance through proxies. The 13th trap
  (`getOwnPropertyDescriptor`) is not yet dispatched, and several
  `defineProperty` paths bypass the trap — see "Known limitations" below.
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
- **Stage B.1** — `[[Set]]` dispatcher with receiver threading and
  landing rule (+30 tests). Note: array-receiver landing has a known
  divergence pending Stage B.2 — see "Known limitations" below.
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

This release breaks substantially more than the original v0.2.0 notes
implied. The Stage A package split (`interpreter/` → `runtime/` +
`stdlib/`) is the largest single source of churn — almost every public
helper or type formerly at `@interpreter` has either moved or been
renamed. See the "Migration from 0.1.0" section below for path-by-path
guidance.

**Lib root** (`pkg.generated.mbti`):

- Removed demo `fib` and `sum` — placeholder scaffolding, unrelated to
  engine functionality.
- `run` / `run_with_event_loop` / `run_module` / `run_modules` gained
  optional `annex_b?` parameter — backward-compatible at call sites.

**`@interpreter` package surface** (Stage A split — heavy churn):

- Public **helpers** that were at `@interpreter` in v0.1.0 — `make_native_func`,
  `setup_builtins`, `regex_*`, `same_value`, `to_number`, `type_of`,
  `well_known_*`, and many others — have moved to `@interpreter/runtime`
  (alias `@runtime`) or `@interpreter/stdlib` (alias `@stdlib`).
- Public **types** that were at `@interpreter` — `ArrayData`, `Callable`,
  `ObjectData`, `PropDescriptor`, `PromiseData`, `Signal`, `SymbolData`,
  and others — are no longer exposed at `@interpreter`. Only
  `Environment`, `Interpreter`, and `Value` remain there as `pub using`
  re-exported aliases. Everything else moved to `@runtime`.
- `JsException` moved to `@runtime.JsException`.
- `make_native_func` signature: positional → labelled (`name~`, `length?`).

**Runtime data model** (`@runtime` consumers — exhaustive matches and
struct constructions need updates):

- `Value` enum gained `Proxy(ProxyData)` variant.
- `Callable` enum: `ClassConstructor` payload restructured into
  `ClassConstructorData` struct; new variant
  `NonConstructableInterpreterCallable`.
- `Signal::BreakSignal` / `ContinueSignal` payloads extended with
  `Value?` for generator-context labeled break/continue.
- `ObjectData` / `ArrayData` / `MapData` / `SetData` / `PromiseData` now
  embed `PropertyBag`; the previous flat `properties` /
  `symbol_properties` / `descriptors` fields are gone.
- `FuncData` / `FuncDataExt` gained `strict`, `has_name_binding`,
  `is_method` fields.

**AST / token / parser** (struct-shape changes — exhaustive matches and
struct construction break):

- `ast.Param` gained `pattern` field (function parameter destructuring).
- `ast.PropPat` gained `computed_key` field.
- `ast.Property` gained `is_method` field (method-shorthand detection).
- `ast.PropKind::Spread` and `ast.UnaryOp::Pos` variants added.
- `ast.StringLit` gained `Bool` payload (template-literal flag).
- `ast.TryCatchStmt` binding type: `String?` → `Pattern?` (catch-clause
  destructuring).
- `ast.ClassExpr` / `ClassDecl` body type:
  `Array[ClassMethod]` → `Array[ClassMember]`.
- `ast.Expr` gained many new variants for generators, async / await,
  tagged templates, `new.target`, `yield`.
- `ast.Stmt` gained variants for generator declarations, async function
  declarations, `with`, ES module declarations (`import` / `export`).
- `token.TokenKind` gained `Yield`, `Import`, `Export`, `From`, `As`
  variants.
- `parser.Parser` struct gained `allow_import_export`, `generator_depth`,
  `async_depth` fields.

### Migration from 0.1.0

If you depended on the `@interpreter` package, most public symbols moved
to two sub-packages:

- `@interpreter/runtime` (alias `@runtime`) — types (`Value`,
  `Interpreter`, `Environment`, `ObjectData`, `ArrayData`, `Callable`, …)
  and low-level helpers (`make_native_func`, `same_value`, `to_number`,
  `type_of`, …).
- `@interpreter/stdlib` (alias `@stdlib`) — built-ins setup
  (`setup_builtins`, regex helpers, Date setup, TypedArray setup, …).

Top-level `@interpreter` now re-exports only `Environment`, `Interpreter`,
and `Value` as aliases (plus the `new_interpreter()` factory function);
anything else must be imported from its new home.

Mechanical migration in `moon.pkg.json`:

```diff
 import {
   "dowdiness/js_engine" @lib,
-  "dowdiness/js_engine/interpreter",
+  "dowdiness/js_engine/interpreter/runtime" @runtime,
+  "dowdiness/js_engine/interpreter/stdlib" @stdlib,
 }
```

Then update qualified paths in source files:

- `@interpreter.make_native_func` → `@runtime.make_native_func`
  (also: signature changed — positional → labelled, `name~` and `length?`)
- `@interpreter.JsException` → `@runtime.JsException`
- `@interpreter.{ArrayData, ObjectData, Callable, Signal, ...}` →
  `@runtime.{ArrayData, ObjectData, Callable, Signal, ...}`
- `@interpreter.setup_builtins` → `@stdlib.setup_builtins`

If you constructed `ObjectData` / `ArrayData` / `MapData` / `SetData` /
`PromiseData` directly with literal field syntax, switch to the
factories or wrap your fields in a `PropertyBag` — the flat field layout
is gone:

```diff
-ObjectData {
-  properties: { ... },
-  symbol_properties: { ... },
-  descriptors: { ... },
-  symbol_descriptors: { ... },
-  prototype: ...,
-  ...
-}
+ObjectData {
+  bag: PropertyBag::new(),  // or populate via the bag
+  prototype: ...,
+  ...
+}
```

### Known limitations at 0.2.0

- **Proxy `getOwnPropertyDescriptor` trap is not dispatched** —
  `Reflect.getOwnPropertyDescriptor` and `Object.getOwnPropertyDescriptor`
  read target data directly rather than going through the proxy handler.
- **`Reflect.defineProperty` and `Object.defineProperty` paths mostly
  bypass the Proxy `defineProperty` trap.** Class-field installation
  does invoke the trap, but the public reflection APIs do not.
- **`[[Set]]` dispatcher: array-receiver landing divergence** is tracked
  for Stage B.2. The receiver threading and general landing rule are
  correct; only the array sub-path is known to diverge.
- **test262 conformance is 86.6% strict / 85.0% non-strict
  passed / executed** (51.2% / 51.3% passed / discovered — ~40% of
  discovered files are skipped for unimplemented features and are
  excluded from the passed / executed figure). See `docs/ROADMAP.md`
  and `docs/supported-features.md` for the per-category breakdown of
  remaining failures, and `docs/agent-todo.md` for the active work
  queue.

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
failed, 56 timeouts. These are **single-mode, passed / executed**
figures under the pre-Phase-24 runner (one run per file, strict vs
non-strict not split); not directly comparable with the per-mode
rates reported from v0.2.0 onward. Unit tests: 507 passing on both
WASM-GC and JS targets.

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

[Unreleased]: https://github.com/dowdiness/js_engine/compare/v0.2.1...main
[0.2.1]: https://github.com/dowdiness/js_engine/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/dowdiness/js_engine/compare/v0.1.0...v0.2.0
[0.1.0]: https://mooncakes.io/docs/dowdiness/js_engine@0.1.0
[`fede44e`]: https://github.com/dowdiness/js_engine/commit/fede44e
