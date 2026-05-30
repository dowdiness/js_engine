# Agent Task Queue

Tasks are ordered by effort and impact. Each task should fit in one session.
Completed tasks should be struck through and dated.

---

## ~~Stage 2a well-known symbol ownership~~ — DONE (2026-05-19, branch `codex/stage2a-well-known-symbols`)

**Source:** [architecture-redesign-2026-05-19.md](architecture-redesign-2026-05-19.md),
after Stage 1 introduced `RealmState`.

**Goal:** Move well-known symbol identity allocation out of individual
module-global refs and into realm-owned state without changing observable
Symbol, iterator, `instanceof`, RegExp symbol-method, or `@@toStringTag`
behavior.

**Result:** Added a realm-owned well-known symbol bundle initialized from the
realm's `SymbolState`. Symbol setup now consumes those identities. The 13
per-symbol module globals were removed from the architecture audit inventory.

**Follow-up:** Stage 2b completed the no-argument lookup migration and removed
the temporary compatibility shim.

---

## ~~Stage 2b explicit well-known symbol lookup paths~~ — DONE (2026-05-21, branch `codex/stage2b-symbol-cleanup`)

**Source:** Stage 2a landed in PR #130 and PR #131 migrated the first runtime
lookup families, leaving one compatibility shim for legacy no-argument
well-known symbol getters.

**Pressure:** Well-known symbol identities are now allocated from realm-owned
state. Many runtime and stdlib lookup paths still reach them through ambient
no-argument helpers, which keeps a hidden process-wide dependency alive and
blocks removal of the compatibility shim.

**Goal:** Replace no-argument well-known symbol lookups with explicit access to
the active realm-owned symbol bundle. Work one caller family at a time. Keep
symbol identity, setup order, and public root facade behavior unchanged.

**Result:** Runtime/compiler lookup paths, string-method hooks, stdlib
setup-time symbol installation, RegExp symbol methods, collection constructors,
`Object.prototype.toString`, and the standalone `setup_builtins` whitebox path
now use explicit `WellKnownSymbols` from the active realm or provided
`SymbolState`. The `legacy_well_known_symbols` shim and public no-argument
`get_*_symbol()` helpers were removed.

**Completed slices:**

- Runtime call/construct/property paths that already have an `Interpreter` or
  nearby realm context.
- Iterator and `@@toStringTag` lookup helpers, because they have dense call
  sites and visible protocol behavior.
- Stdlib setup-time or method-family lookups where the relevant state is
  already available through setup parameters.

**Verification:** `moon check`, focused Symbol / iterator / `@@toStringTag` /
RegExp symbol-method coverage, `moon test`, `make architecture-state-audit`,
`moon info`, `.mbti` diff review, and `moon check --deny-warn`. Standalone
`setup_builtins(env, output, symbols, ...)` still reserves well-known symbol IDs
in the provided `SymbolState`.

**Risk control:** This did not combine with ArrayBuffer backing-store, WeakMap /
WeakSet side-table, or prototype-cache migration.

---

## ~~Stage 2c iterator/prototype cache slice~~ — DONE (2026-05-22, PR #133)

**Source:** [architecture-redesign-2026-05-19.md](architecture-redesign-2026-05-19.md),
Stage 2 after the well-known symbol ownership slice.

**Pressure:** The mutable-state audit classified lazy iterator/prototype caches
beside broader prototype refs, ArrayBuffer storage, WeakMap / WeakSet side
tables, and ambient context. Moving all of them together would have made
failures hard to localize.

**Goal:** Move the iterator/prototype caches used by protocol lookup into
realm-owned state without starting the ArrayBuffer or WeakMap / WeakSet storage
migrations.

**Result:** `%IteratorPrototype%`, `%ArrayIteratorPrototype%`,
`%StringIteratorPrototype%`, Map iterator, Set iterator, and RegExp string
iterator prototype caches now live in `RealmState`. Map, Set, and RegExp
prototype refs needed by iterator-producing closures are realm-owned where this
slice needed them. Standalone `setup_builtins(env, output, symbols, ...)` now
returns the created `RealmState`.

**Review follow-up handled before merge:** Map/Set method lookup now walks the
prototype chain, and direct `MapData` / `SetData` values with `Null` prototypes
use the active realm for lookup without mutating and permanently re-homing the
data.

**Verification:** Keep `make architecture-state-audit` as the inventory gate.
Added cross-realm iterator method tests and whitebox tests for iterator cache
ownership, Map/Set direct-data lookup, and RegExp no-fallback behavior. Final
CI passed `unit-test`, strict and non-strict Test262, `regression-check`,
CodeRabbit, and WIP.

**Risk control:** This did not combine with the remaining runtime factory
prototype refs, Promise / RegExp prototype refs outside the iterator path,
ArrayBuffer backing-store state, WeakMap / WeakSet side tables, or ambient
construction/current-interpreter context.

---

## ~~Stage 2c runtime factory prototype refs~~ — DONE (2026-05-23, PRs #134 and #135)

**Source:** PR #133 landed the iterator/prototype-cache slice, leaving runtime
factory prototype refs as the next narrow Stage 2c family.

**Pressure:** Factory helpers create observable intrinsic prototypes during
ordinary execution, standalone stdlib setup, host extension registration,
compiled closure execution, and cross-realm calls. Moving these refs without
realm-aware entry wrappers can silently allocate objects/functions with the
wrong `[[Prototype]]`.

**Goal:** Move the runtime factory prototype refs into `RealmState` without
starting Promise / RegExp prototype refs, ArrayBuffer storage, WeakMap / WeakSet
side tables, or ambient-context cleanup.

**Result:** PR #134 moved the primitive-wrapper refs (`String`, `Number`,
`Boolean`, and `Symbol`) into `RealmState`. PR #135 moved `Object` and
`Function` prototype refs into `RealmState`, stamped callable values with
callee-realm metadata, and installed active-realm envelopes for public
execution, setup, callback, and property-access entry points that still use
compatibility factory helpers.

**Review follow-up handled before merge:** The final PR #135 patch preserved
cross-realm function creation, borrowed builtin allocation realms, standalone
setup, host-installed functions, module execution, queued callbacks, direct
`call_value` / `construct_value`, direct compiled closures, direct property
access, indirect eval, `$262` realm handles, bound functions, and derived class
constructor allocation behavior.

**Verification:** Final PR #135 CI passed `unit-test`, strict and non-strict
Test262, `regression-check`, CodeRabbit, and WIP. Local validation included
`rtk moon check --deny-warn`, targeted runtime/interpreter JS tests, full
JS-target tests, `rtk make architecture-state-audit`, `rtk moon info`,
`rtk moon fmt`, and `rtk git diff --check`.

**Risk control:** This did not combine with stdlib Promise / remaining RegExp
prototype refs, ArrayBuffer backing-store state, WeakMap / WeakSet side tables,
or replacing the ambient current-interpreter / construction context.

---

## ~~Stage 2c remaining storage/context migration planning~~ — DONE (2026-05-25, commit `968c092`)

**Source:** PRs #133 through #147 landed the Stage 2c iterator/prototype-cache,
prototype-ref, and WeakMap / WeakSet side-table slices. Commit `968c092`
finished the last ambient-context slice by replacing the current-interpreter
fallback with explicit interpreter / realm threading.

**Goal:** Replace the ambient current-interpreter fallback with explicit context.

**Result:** Iterator/prototype caches and runtime factory prototype refs
(`Object`, `Function`, `String`, `Number`, `Boolean`, and `Symbol`) now live in
`RealmState`. Promise and RegExp prototype refs were completed through PRs
#136 through #146, and WeakMap / WeakSet side-table storage was completed in
PR #147. ArrayBuffer backing stores, backing-store IDs, and detached-state
storage now live in `RealmState`. Construction context is explicit, the
current-interpreter fallback has been removed, and the mutable-state audit now
reports 0 classified bindings.

**Verification:** Commit `968c092` passed local `rtk moon test`, `rtk moon test
--target js`, `rtk moon info`, `rtk moon check --deny-warn`, `rtk make
architecture-state-audit`, `rtk python3 scripts/architecture-state-audit.py
--list`, and `git diff --check`. CI passed `Benchmarks` and `Test262
Conformance` (unit-test plus strict and non-strict Test262 jobs).

---

## ~~Stage 1 RealmState seed~~ — DONE (2026-05-19, branch `codex/stage1-realmstate-seed`)

**Source:** [architecture-redesign-2026-05-19.md](architecture-redesign-2026-05-19.md)
after Stage 0 guardrails landed in PR #126.

**Goal:** Introduce the first interpreter-owned `RealmState` container without
moving observable built-in behavior yet. The first patch should establish the
state owner and threading point only; it should not migrate ArrayBuffer,
WeakMap/WeakSet, well-known symbols, or prototype caches.

**Scope for the first patch:**

- Define a small realm-state container owned from the interpreter/realm context.
- Thread it through setup paths where future state-family migrations will need
  it.
- Leave existing module-level globals as compatibility shims.
- Keep the root facade and generated public interfaces stable unless an
  intentional `.mbti` diff is reviewed.

**Verification:** Run `make architecture-state-audit`, `moon check`,
`moon test js_engine_test.mbt`, `moon test`, `moon info`, and review
`.mbti` diffs. The Stage 0 isolation tests must remain green.

**Explicit non-goals:** Do not combine this with semantic fixes, public runtime
surface reduction, storage migration, or compiler-path cleanup.

**Result:** Seeded the interpreter-owned realm-state container and initial
threading point while preserving compatibility with existing interpreter symbol
access. No ArrayBuffer, WeakMap/WeakSet, well-known-symbol, or prototype-cache
storage moved in this slice.

---

## ~~`conversions.mbt` incremental refactor~~ — DONE (2026-05-19, PR #124)

**Branch:** `claude/ecstatic-hopper-2xoZA`

**Goal:** Reduce duplication and increase test coverage in
`interpreter/runtime/conversions.mbt` without rewriting logic or touching
observable behaviour.

**Changes:**

1. **`is_js_object` helper** (`04dcbf4`) — extracted from 7 identical
   `Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_)` match
   arms scattered across `to_primitive_*` and `call_callable_direct`.
   All 7 sites replaced with `is_js_object(v)`.

2. **43 new whitebox tests** (`e0a38df`) — `conversions_wbtest.mbt` now
   covers `is_truthy`, `to_number`, and `to_js_string` with edge-case
   assertions: negative-zero falsy (`-0` → false), numeric-separator
   rejection (`"1_000"` → NaN), `String(-0)` → `"0"`, Symbol TypeError
   for both `to_number` and `to_js_string`.

3. **`lookup_ordinary_method` helper** (`112b3ce`) — named the 4×-repeated
   15-line method-lookup block (prototype chain walk + interpreter fallback).
   `ordinary_to_primitive_number` and `to_primitive_string` shrank by ~36
   lines combined.

4. **`call_symbol_to_primitive` helper** (`6318824`) — named the 3×-repeated
   @@toPrimitive preamble (symbol lookup → callability check → hint call →
   object-result rejection). Each of `to_primitive_number`,
   `to_primitive_default`, and `to_primitive_string` reduced to a 4-line
   body. ~22 lines removed.

**Verification:** `moon check && moon test` green after each commit.

---

## ~~Error handling idiom research~~ — DONE (2026-05-19)

### ~~`noraise` on `errors` and `token` helper functions~~ — DONE (2026-05-19, branch `claude/install-moon-refactor-yFqKV`)

Added `noraise` to all 9 eligible public functions across two packages:

- `errors/errors.mbt`: `JsError::name`, `JsError::get_message`, `JsError::format`, `format_if_js_error`, `name_message_if_js_error`
- `token/token.mbt`: `Loc::default`, `Token::Token`, `Token::new`, `Token::eof`

All are pure pattern matches or struct construction; none delegate to raising code. The compiler accepted all annotations, including `JsError::format` which calls `self.to_string()` via the `noraise` `Show` impl. `moon check` clean, 1439/1439 tests pass.

### Error polymorphism (`raise?`) + `noraise` interaction — finding: no practical sites

The JS interpreter domain forces all meaningful callbacks to raise. Every `each` call on `bag.properties` or `bag.symbol_properties` in `interpreter/runtime/destructuring.mbt` and `interpreter/stdlib/builtins_object.mbt` has a body that raises `JsError` (property access, coercion, interpreter calls). No `Array::map` / `Array::filter` callbacks are pure transformations — they all thread an `Interpreter` and can raise. The `raise?` + `noraise` combination has no practical payoff in this codebase today.

---

## Small follow-ups (2026-05-10)

### ~~Start bytecode/IR execution prototype~~ — DONE (2026-05-28, `50bcb94`)

**Source:** closure-conversion benchmark work and the decision recorded in
[closure-conversion-and-bytecode.md](closure-conversion-and-bytecode.md).

**Result:** The first opt-in stack-bytecode prototype shipped in `50bcb94`.
Default `run` remains on the tree-walking interpreter. The prototype exposes
`compile_script_to_bytecode`, `run_bytecode_script`, and `BytecodeProgram::run`;
adds compare-against-tree-walker tests for supported constructs and the primary
closure-factory / pipeline-evaluate workloads; and adds bytecode benchmark rows
for those workloads.

**Guardrails carried forward:** Keep bytecode opt-in, reuse runtime helpers, and
reject unsupported semantics explicitly. The current fail-fast rejection list is
tracked in [closure-conversion-and-bytecode.md](closure-conversion-and-bytecode.md#current-explicit-bytecode-rejections).

### Bytecode performance measurement follow-ups — OPEN (2026-05-30)

**Source:** PR #164 benchmark snapshot and
[closure-conversion-and-bytecode.md](closure-conversion-and-bytecode.md#current-bytecode-performance-snapshot).

**Finding:** On the current JS-target benchmark snapshot, bytecode is only a
small win over tree-walking: about 1.06x on `pipeline/*/evaluate` and about
1.01x on `closure_factory`. Do not start a broad optimization design from this
alone; first isolate costs with microbenchmarks.

**Issues:** Start with [#166](https://github.com/dowdiness/js_engine/issues/166)
under the roadmap [#165](https://github.com/dowdiness/js_engine/issues/165).
Only after measurement, consider [#167](https://github.com/dowdiness/js_engine/issues/167)
(local/upvalue slotting), [#168](https://github.com/dowdiness/js_engine/issues/168)
(call/frame setup), [#169](https://github.com/dowdiness/js_engine/issues/169)
(VM dispatch/stack overhead), and [#170](https://github.com/dowdiness/js_engine/issues/170)
(shared runtime helper hotspots).

**Guardrails:** Do not broaden bytecode syntax in these follow-ups. Keep `run`
on the tree-walker, keep bytecode opt-in, reuse runtime helpers, and keep
compare-against-tree-walker tests for every supported construct touched.

### ~~Migrate remaining deprecated `inspect` snapshots~~ — DONE (2026-05-14)

**Source:** PR #109 CI follow-up after MoonBit `0.1.20260512` changed `Show` rendering for `Array[String]`.

**Risk:** `inspect` snapshots depend on MoonBit `Show` formatting, not project behavior. PR #109 converted console-output string arrays and parser parameter arrays to `json_inspect`, but many unrelated tests still emit deprecation warnings and could drift again with future toolchains.

**Fix:** Audit remaining `inspect` calls. Use `json_inspect` for structured data and arrays where JSON semantics are intended; use `inspect` only where the MoonBit `Show` rendering itself is the intended assertion.

**Progress:** 2026-05-13 — migrated lexer token-kind array snapshots to
`json_inspect` over token debug strings (`9299bab`). 2026-05-14 — migrated
the remaining plain `inspect` assertions to direct string/value checks or
`json_inspect`; no plain `inspect(` calls remain in `.mbt` or `.mbt.md` files.

**Verification:** Run `moon check`, `moon test`, and, if available, repeat `moon test` with the current CI-installed MoonBit toolchain.

---

### ~~Mirror ExpectedArgumentCount in dynamic `Function(...)` constructor~~ — DONE (2026-05-15, PR #117)

Function() constructor `FuncDeclExt` branch at `interpreter/stdlib/builtins_function.mbt:404+` now mirrors the ES262 §10.2.4 ExpectedArgumentCount loop.

---

### ~~Complete ExpectedArgumentCount: stop on rest parameter across all factories~~ — DONE (2026-05-15, PR #117)

Rest-param check added across `factories.mbt`, `generator.mbt`, `eval_expr.mbt` (ArrowFuncExt arm), `async.mbt`, `class.mbt` class-constructor loop, and the new `builtins_function.mbt` loop. Convention is name-equality (`rest_param is Some(rn) && p.name == rn`), consistent with existing runtime sites at `call.mbt:277` and `construct.mbt:553`. See next item for the structural follow-up.

---

### ~~Structural fix: identify destructuring-rest by flag, not name~~ — DONE (2026-05-29, PR #163, `e26e730`)

Completed by adding `Param.is_rest_pattern`, setting it only for destructuring-rest params, and replacing rest-name equality consumers. Regressions cover runtime binding, function length, dynamic constructors, and class constructors.

**Source:** Codex review of PR #117 (2026-05-15).

**Bug:** The codebase identifies destructuring-rest Params by name equality with `rest_param` (`call.mbt:277`, `construct.mbt:553`, plus the five length-loops touched in PR #117). Codex's example: `function f({a}, ...$0) {}` — the parser assigns the destructuring `{a}` a synth name `"$" + synth_idx.to_string()` = `"$0"`, but the user's rest param is *also* named `$0`. Length-loops and runtime parameter binding both treat the destructuring `{a}` as the rest pattern.

No test262 cohort exercises this — `$0` is a valid but unusual identifier — but the runtime binding is observably wrong: the user's `a` would bind to the first element of the rest array instead of the first argument.

**Fix:** Add an explicit `is_rest_pattern : Bool` field to `@ast.Param`. Parser sets it to `true` only at the two destructuring-rest sites (`parser/stmt.mbt:316, :355`). All consumers — five length-loops, `call.mbt:277`, `construct.mbt:553`, plus the `Function`/`AsyncFunction`/`GeneratorFunction` dynamic-constructor duplicate-name validator — check the flag instead of comparing names.

**Co-fixes needed in the same PR:**
- The dynamic `Function(...)`, `AsyncFunction(...)`, and `GeneratorFunction(...)` constructors trip `validate_function_constructor_params` with "Duplicate parameter name" for any destructuring-rest source (e.g. `new Function("a", "...[b]", "")`) because they pass `params.map(p => p.name)` to the validator while `rest_param` is also `"$rest"`. The validator should skip Params marked `is_rest_pattern`.
- Class constructor destructuring rest hits the same validator bug (`class C { constructor(a, ...[b]) {} }` fails to parse). Same fix unblocks it.

**Estimated scope:** ~11 Param construction sites in parser + AST struct update + ~7 consumer sites. Larger than PR #117 alone but eliminates the entire ambiguity, not patches one symptom.

**Refactoring workflow (use `moonbit-refactoring`):** Treat this as one focused API/data-model refactor, not a drive-by cleanup. First add `is_rest_pattern : Bool` to `@ast.Param`, then run `moon check` to surface all construction sites. Update parser construction next, setting the flag to `true` only for destructuring rest (`...[pattern]`) and `false` everywhere else. Then replace consumer name-equality checks with the flag. Add black-box regressions for `function f({a}, ...$0) {}` runtime binding, length/counting behavior, dynamic constructor destructuring rest, and class constructor destructuring rest. Run `moon check` after each edit batch, then targeted tests, `moon test`, `moon info`, and `moon fmt`.

---

### Small cleanup: helper for ExpectedArgumentCount over extended params

**Source:** Follow-up after PR #163 (2026-05-29).

**Why:** PR #163 fixed the ambiguity by changing each length loop to stop on `p.default_val is Some(_) || p.is_rest_pattern`, but that logic is still duplicated across runtime factories (`factories.mbt`, `generator.mbt`, `async.mbt`, `eval_expr.mbt`, `class.mbt`), dynamic `Function` construction (`interpreter/stdlib/builtins_function.mbt`), and `compiler/closure_conversion.mbt`.

**Fix:** Add a small helper such as `expected_argument_count_ext(params : Array[@ast.Param]) -> Int` and use it at the duplicated call sites. If the helper must be shared outside `interpreter/runtime`, make the public API change explicit and regenerate `.mbti` with `moon info`; otherwise keep it package-local and leave the compiler with a local equivalent. This should be a no-behavior-change cleanup.

**Validation:** Run the existing function-length regression tests, then `moon check`, `moon test`, `moon info`, and targeted `moon fmt`.

---

### ~~Async generator length / name (latent gap)~~ — DONE (2026-05-29)

**Source:** Codex review of PR #117 (2026-05-15).

**Bug:** `make_async_gen_function_inner` at `interpreter/runtime/async.mbt:424` didn't set `length` or `name` on async generator function objects (the `fn_props` map only had `"prototype"`). Both `make_async_generator_function` (simple) and `make_async_generator_function_ext` (with defaults) delegate to it.

No test262 impact today because async-iteration is skipped via the feature flag. When async-iteration is unlocked, async generator function length and name would have been wrong.

**Fix:** Mirrored the length-and-name install logic from `make_generator_function_ext` into `make_async_gen_function_inner`, including the rest-param check. Branches on `params_ext is Some(_)` to choose simple-vs-ext counting.

---

### ~~Reject trailing comma after rest parameter~~ — DONE (2026-05-13, `183363f`)

**Source:** Codex review of PR #103 (trailing-comma in non-arrow params).

**Bug:** `parser/stmt.mbt:Parser::parse_params_ext` accepts `function f(...rest,) {}` and `function f(a, ...rest,) {}` — but the ES2017 grammar explicitly forbids it (`FunctionRestParameter` is the last production with no trailing comma). V8 rejects: "SyntaxError: Rest parameter must be last formal parameter."

**Cause:** Inside the `while self.eat(Comma)` loop in `parse_params_ext`, the `if self.at(RParen) { break }` trailing-comma check runs **before** the `if rest_param is Some(_) { raise SyntaxError(...) }` rejection. Swap the order — the rest-rejection must come first.

**Fix size:** ~1 line move + 2 panic tests in `parser/parser_test.mbt`. ~10 minutes.

**Pre-existing, not introduced by PR #103.** Codex tagged P2 (adjacent).

---

## Pre-ES2015 baseline push (2026-05-07 classification)

Source: CI run 25488893622, tip `a199669`. Strict 91.3% / non-strict 90.2% P/E on Pre-ES2015. Plan ranked by ROI; pick one cluster per PR. Memory: `project_pre_es2015_landscape_2026_05_07.md`.

**Verification rule:** Before opening any of these, sample 5–10 failing tests from the cluster's directory and confirm the shared root cause holds. The 04-21 TypeError drill is the template.

### ~~Cluster 4 — Over-throwing TypeError (smallest, highest signal)~~ — DONE (2026-05-13, PR #112)

**Result:** Fixed abrupt-completion ordering in built-ins, including `%TypedArray%.from`
receiver/map-function validation and WeakMap/WeakSet constructor adder checks.

23 strict + 23 non-strict failures sharing reason `Test262Error: Expected a Test262Error but got a TypeError`. Likely one shared coercion or property-access helper throws `TypeError` in a path where the spec expects normal completion or a different error.

- Find the failing tests: `python3 scripts/test262-runner.py --filter ... --output /tmp/x.json` then grep results JSON for the reason.
- Inspect 5 of them, locate the common throw site.
- Single fix; expect ~46 tests recovered.

### ~~Cluster 2 — Object descriptor metadata round-trip~~ — DONE (2026-05-15, PR #115, `894105b`)

**Result:** Fixed Object descriptor metadata round-trip behavior across
`Object.create`, `Object.defineProperties`, and
`Object.getOwnPropertyDescriptors`, including descriptor source key
snapshotting, user `[[...]]` property names, Map/Set expando descriptor
sources, array length truncation failure metadata, and built-in function /
RegExp prototype descriptor attributes.

Reasons: `obj['…'] descriptor should be configurable` (54/56), `should not be writable` (15), `Cannot redefine property: 0` (13 NS), `newObj.prop Expected SameValue(undefined, "…")` (11). Pattern: `Object.defineProperty` doesn't preserve attribute bits on round-trip, especially on integer-indexed properties.

- Audit `interpreter/runtime/property.mbt` (PropertyDescriptor → PropertyBag conversion).
- Check whether `defineProperty` with a partial descriptor merges correctly with existing descriptor.
- Verify the integer-key path (Cluster 1 overlap — likely Array-element defineProperty).

### ~~Cluster 5 — Unicode IdentifierStart/Part lexing (~35 each mode)~~ — DONE (2026-05-09, PR #93, `24d7498`)

**Result:** Generated `lexer/unicode_id.mbt` from `DerivedCoreProperties.txt`
(Unicode 17.0) with ECMAScript §11.6 `ID_Start` / `ID_Continue` range tables
and binary-search lookup. Replaced the prior "any non-ASCII non-whitespace
is ID-start" heuristic that mis-tokenized punctuation like `©` (U+00A9).
Closure verified 2026-05-15: `language/identifier` 100% pass; zero
"Unexpected character" failures in CI artifacts apart from one Stage 3
import-defer test using private-field `#` (separate `class-fields-private`
feature, not Unicode-ID).

### Cluster 1 — Array internals post-Stage-C audit

Largest cluster (390/399) but lowest individual-test confidence. With Stage C (ArrayData.bag) merged 2026-04-23, several Array fast-paths in `interpreter/stdlib/builtins_array.mbt` may now be redundant. See `feedback_fast_path_duplicates.md`.

- Step 1: enumerate all fast-paths in `builtins_array.mbt`.
- Step 2: for each, identify the test262 cohort it currently catches.
- Step 3: remove fast-path, re-run that cohort, compare.
- Likely splits into 2–3 PRs. Mechanical-ish — Sonnet delegation candidate per `feedback_delegation_mechanical_fixes.md`.

### Cluster 3 — Strict-mode TypeError residual re-triage

The 04-21 drill deferred ~27 tests pending Stage C. Stage C is now done.

- Re-run the original drill filter, classify what's left.
- Likely splits into a quick-win bundle (similar to PR #70/#71) and a smaller deferred set.

### Cluster 6 — Algorithmic timeouts (38 strict / 37 non-strict)

**Required:** invoke `moonbit-perf-investigation` skill — must reproduce in microbench before designing a fix. CLAUDE.md's performance optimization rule applies.

- Identify which Array (or other) method causes the timeouts.
- Hypothesis: O(n²) where O(n) is required.

### Deferred (not in this push)

- **Cluster 7 — RegExp** (113 each): pre-existing engine limits, separate project.
- **Cluster 8 — Sloppy `arguments` aliasing** (31 NS-only): structural; separate non-strict-only effort.
- **Cluster 9 — Spec-tail (JSON, encodeURI, Date, Number)** (~80 each): spread across small PRs as opportunistic cleanups.

**Estimated ceiling without deferred clusters:** ~700 strict / ~750 non-strict recovered → Pre-ES2015 P/E approaches ~96% / ~95%.

---

## ~~Next PR: Small Compliance Wins~~ — DONE (2026-04-12, PR #45)

**Branch**: `claude/compliance-quick-wins`
**Result**: Unlocked 4 feature flags: `regexp-dotall`, `async-functions`, `promise-with-resolvers`, `promise-try`

### Task 1 — Unlock `regexp-dotall` (already implemented, zero-code change)

The `s` flag is fully implemented in `interpreter/stdlib/builtins_regex.mbt`:
- `dot_all: Bool` in `RegexFlags` struct (line ~556)
- `dot_all` is set from `flags.contains("s")` at line ~899
- `.` matching logic already respects `dot_all` at line ~578
- The `dotAll` property on RegExp instances returns `true`/`false`
- The `flags` string includes `"s"` when set

**Test to confirm it works today:**
```bash
moon run cmd/main -- 'print(/foo.bar/s.test("foo\nbar")); print(/x/s.dotAll); print(/x/s.flags);'
# Expected: true / true / s
```

**Action**: In `scripts/test262_skip_metadata.py`, remove `"regexp-dotall"` from shared skip metadata if it is still present.
Run `python3 scripts/test262-runner.py --filter "built-ins/RegExp" --summary` to confirm pass rate improves.

---

### Task 2 — Add `Promise.withResolvers()`

**Spec**: https://tc39.es/ecma262/#sec-promise.withresolvers
**Feature flag**: `"promise-with-resolvers"` in shared skip metadata
**File**: `interpreter/stdlib/builtins_promise.mbt`

**Algorithm** (simple):
```js
Promise.withResolvers = function() {
  let resolve, reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}
```

**Implementation**: Add a `make_interp_static_func_with_length("withResolvers", 0, fn(interp, args) raise { ... })` entry in the Promise constructor's properties map. Use `interp.call_value` with the Promise constructor to create the promise, capturing the resolve/reject via a native closure.

Look at how `Promise.resolve` and `Promise.reject` are implemented in `builtins_promise.mbt` for the pattern.

After implementing: remove `"promise-with-resolvers"` from shared skip metadata and run
`python3 scripts/test262-runner.py --filter "built-ins/Promise" --summary`.

---

### Task 3 — Add `Promise.try()`

**Spec**: https://tc39.es/ecma262/#sec-promise.try
**Feature flag**: `"promise-try"` in shared skip metadata
**File**: `interpreter/stdlib/builtins_promise.mbt`

**Algorithm**:
```js
Promise.try = function(callbackFn, ...args) {
  // 1. Let C be this (the Promise constructor)
  // 2. If C is not an object, throw TypeError
  // 3. Return PromiseResolve(C, callbackFn(...args))
  //    - i.e. call callbackFn synchronously; if it throws, return a rejected promise
  try {
    return Promise.resolve(callbackFn(...args));
  } catch (e) {
    return Promise.reject(e);
  }
}
```

Same file and pattern as `withResolvers`. After implementing: remove `"promise-try"` from shared skip metadata.

---

### Task 4 — Audit and unlock `async-functions`

**Feature flag**: `"async-functions"` in shared skip metadata

**Current state** (verified 2026-04-12):
- `async function`, `async () =>`, `await expr` all parse and execute correctly
- `async function f(x) { return x * 2; }` and multi-level `await` work
- `for await...of` does NOT parse (that's `async-iteration`, separate flag — keep skipped)

**Investigation steps**:
1. Run the async-functions subset:
   ```bash
   python3 scripts/test262-runner.py --filter "language/statements/async-function" --summary
   python3 scripts/test262-runner.py --filter "language/expressions/async-arrow-function" --summary
   python3 scripts/test262-runner.py --filter "built-ins/AsyncFunction" --summary
   ```
   Do this BEFORE removing the flag — re-enable temporarily in test code or run with `--include-skipped` if supported.

   Alternatively: temporarily comment out `"async-functions"` from shared skip metadata, run the filter, restore.

2. Review failures. Common gaps:
   - `AsyncFunction` constructor (`new AsyncFunction(...)`)
   - `async function*.length` / `.name` property descriptors
   - Top-level return value from async functions (should always be a Promise)
   - Rejected promise on thrown error propagation timing

3. Fix whatever is failing, then remove `"async-functions"` from shared skip metadata.

**Note**: Keep `"async-iteration"` in shared skip metadata — `for await` is not yet parsed
(SyntaxError: `Expected LParen, got Ident("await")` at the `for await` statement).

---

## ~~Known Issues Quick Fixes~~ — DONE (2026-04-14, PR #46)

**Branch**: `claude/known-issues-quick-fixes`
**Result**: Fixed 3 known issues from PR #45 compliance audit

### ~~Issue #4 — Flag ordering not normalized~~ ✓
### ~~Issue #9 — GeneratorFunction fallback returns empty function~~ ✓
### ~~Issue #12 — `Function.prototype.toString` doesn't distinguish async~~ ✓

---

## Known Issues (remaining, discovered 2026-04-12, PR #45)

### RegExp pre-existing gaps (not dotall-specific)

1. **Supplementary plane `.` matching** — `/^.$/.test("\u{10300}")` returns `true` without `u` flag (should be `false`). `.` without `u` should not match surrogate pairs as a single character.
2. **`dotAll` getter on plain objects** — `Object.getOwnPropertyDescriptor(RegExp.prototype, 'dotAll').get.call({})` does not throw TypeError (should throw). Same issue affects other flag getters.
3. **`flags` getter doesn't coerce from plain objects** — `Object.getOwnPropertyDescriptor(RegExp.prototype, 'flags').get.call({dotAll: true})` should include `"s"` but doesn't. The getter only reads internal slots, not properties.

### Dynamic constructor shared gaps (Function, GeneratorFunction, AsyncFunction)

5. **`Value.to_string()` bypasses ES `ToString`** — Dynamic constructors use MoonBit's `.to_string()` instead of calling `@@toPrimitive`/`toString`/`valueOf`. `new Function(Symbol())` should throw `TypeError` during coercion but fails during parsing instead.
6. **Body coerced before parameters** — `CreateDynamicFunction` requires left-to-right coercion (`p1`, `p2`, ..., `body`). Our impl converts body first, reversing observable side-effect ordering.
7. **Constructor `[[Prototype]]` is `Function.prototype`** — Spec says `AsyncFunction.__proto__ === Function` (the constructor), not `Function.prototype`. Same for `GeneratorFunction`. Affects static property inheritance.
8. **`js_error_to_value` creates null-prototype errors** — When `Promise.try` rejects with an engine error, the rejection value lacks proper prototype chain (`instanceof TypeError` fails).

### Async function edge cases

10. **Sloppy-mode `this` coercion** — Async functions called without a receiver get `undefined` as `this` instead of `globalThis`. This is a general interpreter issue, not async-specific.
~~11. **Mapped arguments not implemented**~~ — DONE (2026-05-06, PR #81). `make_arguments_object` now creates spec-compliant live-mapped accessor slots for sloppy-mode simple-parameter functions per §10.4.4.1, with correct duplicate-param handling (last occurrence wins) per §10.4.4.7.

---

## ~~`regexp-named-groups`~~ — DONE (2026-04-15, PR #47)

**Branch**: `worktree-regexp-named-groups`
**Result**: Unlocked `regexp-named-groups` feature flag. 28/70 named-groups tests pass, 112/112 language literal tests pass. Annex B 100%.

**Implemented**:
- `(?<name>...)` named capture group parsing with Unicode identifier support
- `\k<name>` named backreferences with deferred resolution (forward refs work)
- `.groups` null-prototype object on match results
- `$<name>` in replacement strings
- Duplicate group name rejection (ES2018 SyntaxError)
- Annex B `\k` literal fallback in non-unicode mode

**Remaining failures (42, all pre-existing or out-of-scope)**:
- 20: Duplicate named groups (ES2024 — distinct from ES2018 rejection, allows same name in alternation branches)
- 4: Functional replace callback for regex (not implemented)
- ~~6: `verifyProperty`/`getOwnPropertyDescriptor` on array named props (side table not visible)~~ — fixed by Stage C ArrayData.bag migration.
- 4: RegExp subclass exec/match forwarding
- 8: Unicode identifiers (`π`, `𝑓`) in JS lexer (lexer can't parse non-ASCII identifiers)

---

## Pre-existing gaps exposed by named-groups (2026-04-15)

Cross-cutting issues discovered during PR #47 that affect more than just named groups.

### ~~1. Array named props invisible to `getOwnPropertyDescriptor`~~ — DONE (Stage C)

**Impact**: ~6 named-groups tests + many regex/array tests across the suite
**File**: `interpreter/runtime/value.mbt`, `interpreter/stdlib/builtins_object_descriptors.mbt`

`set_array_named_prop` now stores properties (like `index`, `input`, `groups` on regex match arrays) in `ArrayData.bag`. `Object.getOwnPropertyDescriptor`, `Object.getOwnPropertyNames`, `Object.getOwnPropertySymbols`, and `Object.getOwnPropertyDescriptors` observe the bag-backed array properties.

**Fix**: Stage C migrated named/symbol/length override helpers off the legacy side tables and into the embedded `PropertyBag`.

### ~~2. Regex callback replace not implemented~~ — DONE (2026-04-16)

`[Symbol.replace]` now supports function replacements via `string_replace_regex_func` and `call_replace_fn`. Callback receives `(match, ...captures, offset, string, groups)` per spec. `String.prototype.replace` delegates to `Symbol.replace` for RegExp arguments, which handles the function case.

### 3. JS lexer rejects non-ASCII identifiers

**Impact**: 8 named-groups tests + general Unicode identifier support
**File**: `lexer/lexer.mbt`

The lexer's identifier scanning only accepts ASCII `[a-zA-Z_$]` starts. Unicode letters like `π` (U+03C0) or mathematical italics like `𝑓` (U+1D453) are rejected as unexpected characters. These are valid JS identifiers and appear in test262 as regex literal group names like `/(?<π>x)/`.

### 4. RegExp subclass exec/match forwarding

**Impact**: 4 named-groups tests
**File**: `interpreter/stdlib/builtins_regex.mbt`

RegExp subclass tests expect `exec()` to be called on the subclass instance (which may override `exec`), but the engine calls internal regex functions directly. Needs `Symbol.match` / `Symbol.replace` to call `this.exec()` through the prototype chain.

---

## Later PR: `for-await` / `async-iteration`

**Feature flag**: `"async-iteration"` in shared skip metadata
**Estimated tests**: ~200+

**Current state**: `for await (const v of iterable)` fails to parse.
The parser (`parser/`) needs a `ForAwait` AST node and the interpreter needs to handle
async iteration protocol (`Symbol.asyncIterator`, `next()` returning Promises).

This is a medium-effort feature. The generator/iterator infrastructure in
`interpreter/runtime/generator.mbt` and `interpreter/runtime/iterators.mbt` is the foundation — read
those first.

---

## ~~Later PR: Stage 3/4 Sub-package Extraction~~ — DONE (2026-04-15, branch `claude/restructure-architecture-VkLTl`)

All four stages shipped. See [archive/architecture-redesign-2026-04-15.md](archive/architecture-redesign-2026-04-15.md) for the full analysis.

~~**Stage 1 — ExecContext**~~: `ExecContext` struct replaces `mut strict` / `mut current_generator`. ✅
~~**Stage 2 — Timer API**~~: `Interpreter::schedule_timer` / `cancel_timer` replace 14 direct field accesses. ✅
~~**Stage 3 — Package boundary**~~: `interpreter/runtime/` and `interpreter/stdlib/` sub-packages created; compiler enforces the boundary. ✅
~~**Stage 4 — Descriptor consolidation**~~: `validate_non_configurable` moved to `runtime/property.mbt`; shared helpers extracted. ✅

---

## Recommended Next Targets (2026-04-17 probes)

Four uncertainty probes sharpened the targets. Full analysis in
[architecture-redesign-2026-04-17-probes.md](architecture-redesign-2026-04-17-probes.md).
The 2026-04-16 analysis below is still valid; this section overrides it
where they disagree.

### Highest-ROI non-architectural items (discovered 2026-04-17)

#### ~~A. Annex B eval-scope + function-body hoisting~~ — PARTIAL (PRs #64 + #65, 2026-04-18)

**Merged**: `5eded5e` (PR #64, eval §B.3.2.3 + §B.3.4 walk), `38beeba`
(PR #65, function-body §B.3.2.1 reusing the same walker). Both green on
unit-test / test262 strict / non-strict / regression-check / CodeRabbit.
**Full-suite post-PR-#65**: `annexB/language` **73.5%** (up from 63.1%
post-PR-#64, net +88 tests from the function-body path); `language/eval-code`
**62.6%** (unchanged — eval path was PR #64's lane). Next big wedge is the
param-default `eval("var arguments")` case (~96 tests, out of scope #1 below).

**Shipped in PR #64** (initial + six post-review fixes):
- AST-syntactic skip check for §B.3.3.3 candidates in eval bodies
  (`hoist_eval_annex_b_candidates` in `hoisting.mbt`), walking enclosing
  block / for-head / switch-case / IfStmt / LabeledStmt lex frames.
- `TopLevelVarDeclaredNames` threading via new `in_block` flag on
  `collect_block_var_decl_names_from_stmt` — nested-block FunctionDecls no
  longer count as top-level VarDecls for the eval early-error gate.
- New `annex_b_hoisted` + `is_parameter` flags on `Binding`;
  `Environment::def_parameter` added and wired into all 11 JS parameter
  / rest-parameter sites across `call.mbt`, `construct.mbt`,
  `generator.mbt`, `eval_expr.mbt`. Runtime block-entry reinit in
  `exec_stmt.mbt` checks `annex_b_hoisted`, which lets the extension
  update reused parameter bindings (stored as `LetBinding`) while
  leaving genuine `let` / `const` untouched.
- `tag_annex_b_hoisted` gates on `kind == VarBinding || is_parameter` to
  prevent overwriting `const` / real `let` via the direct
  `binding.value = func_val` write in exec.
- Step 5.d walk in `perform_eval` now starts at `exec_env` (the fresh eval
  lex env), per §19.2.1.3, eliminating false-positive SyntaxErrors for
  indirect eval nested under a block with `let`.
- `add_stmt_lex_names` descends into `StmtList` so comma-separated
  declarations (`let f=1, g=2;`) are visible to `annex_b_candidate_conflicts`.
- `hoist_block_func_declarations` tags direct FuncDecl children under
  `LabeledStmt` (non-eval sloppy case) so the exec-time reinit fires.
- Simplify-review polish: `Map[String, Unit]` → `Map[String, Bool]`
  standardization; `tag_annex_b_hoisted` single-pass insert
  (no `raise Error`).

**Out of scope (follow-ups)**:

1. ~~**§10.2.11 param-env / body-env split for parameter defaults.**~~
   — DONE (2026-04-19, PR #66 `ebb256a`). Split landed for all Ext
   call-entry sites (`call.mbt` UserFuncExt + ArrowFuncExt, `construct.mbt`
   UserFuncExt + explicit class-ctor + implicit-super ctor,
   `generator.mbt` + async via the generator path). Gated on
   `has_parameter_expressions(params)` — plain-rest Ext shapes
   (`function f(...rest) { var rest }`) keep single-env semantics per
   step 26. `pattern_contains_expression` refines the gate so
   destructuring without defaults doesn't over-split
   (`function f({a}) { var a }`). `hoist_declarations` gained an optional
   `param_source` so its Annex B excluded set scans the param env when
   the caller is split. `Environment::initialize_in_chain` walks parents
   for `super()` writeback across the split envs.

   Post-merge Codex review drove four additional fixes on the same PR:
   - **§15.2.5 FunctionExpressionName binding** (`has_name_binding` flag
     on `FuncData` / `FuncDataExt`): only named FunctionExpressions get
     the self-name wrapper env so defaults can close over the self-name
     (`var g = function f(a = () => f) { return a(); }; g() === g`).
     Methods, class methods, function declarations, `new Function()`,
     and anonymous functions explicitly opt out. `is_method` added to
     `ast.Property` so object-literal method shorthand strips the flag
     via `strip_self_name_binding` post-eval.
   - **`arguments` installed before defaults** in both class-ctor paths
     (explicit `constructor(a = arguments.length)` + implicit super()).
   - **Implicit super() split** mirrors the explicit ctor: `class D extends B {}`
     with `class B { constructor(a = 1, q = () => x) { var x = 'b' } }`
     now ReferenceErrors like direct `new B()`.
   - **§10.2.11 plain-rest + plain-destructure gate correctness** — the
     split no longer fires for `function f(...rest)` or `function f({a})`
     without initializers.

   **Final delta (baseline = post-PR-#65):**
   - `language/statements/class` +22 tests (`scope-*-paramsbody-var-open`
     shapes — tests cite §10.2.11 step 27 directly).
   - `language/eval-code/direct` +3 tests (`arrow-fn-body-cntns-arguments-*-incl-def-param-arrow-arguments`).
   - `language/statements/function` +2 tests.
   - Zero regressions. 915/915 unit tests pass (with 6 new regression
     tests covering named FE vs method distinction, class-ctor
     arguments ordering, implicit-super split, and P1 gate refinements).
2. ~~**Function-body §B.3.2.1 skip check.**~~ — DONE (2026-04-18, PR #65).
   `hoist_declarations` now runs the shared `hoist_eval_annex_b_candidates`
   post-loop with the function body's TopLevelLexicallyDeclaredNames as
   `top_lex`, deleting the 132-line legacy `hoist_block_func_declarations`.
   Param / `arguments` carve-out threaded via an `excluded~` set built from
   `is_parameter` bindings + `"arguments"` (Codex-flagged pre-merge —
   §B.3.2.1 requires the skip check to exempt these, unlike §B.3.2.3 eval).
   **Result: annexB/language 63.1% → 73.5% (+88 tests)**; regression guards
   flat.
3. **Catch-env transparency in step 5.d walk (§B.3.4).** Our Environment
   model does not tag catch envs; the walk treats them as plain block envs,
   which can false-positive when eval is called inside a `catch` block that
   shadows an incoming var name. Narrow edge case.
4. **`CanDeclareGlobalFunction` atomicity for indirect eval.** Test
   `non-definable-function-with-function.js` expects all function decls in
   one eval body to be rejected together when any one would fail
   `CanDeclareGlobalFunction`. We emit them one-by-one. Separate issue.
5. ~~**Pattern-walker consolidation (pre-existing tech debt).**~~ — DONE
   2026-04-18 (commit `a265b22`). Introduced `walk_pattern_idents(pattern,
   on_ident : (String) -> Unit raise Error)`; the 5 walkers
   (`collect_pattern_var_names`, `collect_pattern_decl_names`,
   `collect_pattern_lex_names`, `hoist_pattern`, `hoist_pattern_tdz`)
   collapsed to two-line wrappers. Widened `collect_eval_var_names` chain +
   `add_stmt_lex_names` / `collect_stmts_lex_names` / `for_init_lex_names`
   to `raise Error`. Net -78 lines. `.mbti` unchanged.
6. ~~**§19.2.1.3 eval-declared-arguments early error.**~~ DONE 2026-04-19.
   Empirical investigation (see
   `docs/superpowers/plans/2026-04-19-eval-declared-arguments-early-error.md`)
   established the real rule is broader and the mechanism simpler than
   first hypothesised. A direct `eval(...)` in a function's parameter
   default whose eval input declares `arguments` raises SyntaxError
   whenever the function's parameter scope has an `arguments` binding —
   non-arrow always (via arguments-object install), arrow only when an
   explicit `arguments` formal parameter is present. No env-model
   change needed; the 3-env lift framing was a red herring. Four
   cohorts moved together: `cntns-arguments` 30→72 (+42),
   `no-pre-existing-arguments-bindings` 10→24 (+14),
   `preceding-parameter-is-named-arguments` 22→24 (+2),
   `following-parameter-is-named-arguments` 24→24 (+0).
   **Overall `eval-code/direct` 451/646 → 509/646 (+58, 69.8% → 78.8%)**;
   unit tests 733→745 (+12 new regression guards, 0 regressions).
   Implementation: new `Interpreter.in_nonarrow_param_default_eval`
   flag with save/reset/set/restore discipline across
   `bind_ext_params_and_exec_body`, `create_generator_instance`, and
   the `UserFunc` / `ArrowFunc` simple call paths, plus a one-branch
   check in `perform_eval` after `collect_eval_var_names`.
   **Remaining 48 fails across the four cohorts are all async
   `"async test did not call $DONE"`** — a microtask-drain harness gap
   unrelated to eval semantics; tracked separately.
7. **§10.2.11 remaining spec divergences (pre-existing, behavior
   preserved across PR #66).** Not regressions — none block the shipped
   test-count wins. Each is small surface, worth its own PR.
   - **3-env vs 2-env collapse.** Spec has `env → varEnv → lexEnv`;
     we collapse `varEnv ≡ lexEnv` into `param_env → body_env`.
     Observable for
     `f(a = eval("var x = 'e'"), b = () => x) { var x = 'b'; return [b(), x]; }`
     — spec says `['b', 'b']`, ours `['e', 'b']`. Not in the 96-test
     slice but likely prerequisite for item 6.
   - **Param TDZ pre-declaration.** Spec §10.2.11 step 22 creates all
     parameter bindings (as uninitialized) before step 27 evaluates
     defaults, so `function f(a = b, b = 1) {}` throws TDZ on `b`.
     We bind sequentially, so the forward reference silently resolves
     via parent scope. Fix: first pass `def_tdz` every parameter name
     on `param_env`, then swap `def_parameter` for `initialize` in the
     existing loop. Interacts with rest + destructuring.
   - ~~**`arguments` in parameterNames.** `function f(arguments = 1)`
     should suppress the arguments-object install per step 17.
     Currently collides — the arguments-object install throws on
     re-def of `arguments`. Gate the install on
     `!parameter_names.contains("arguments")`.~~ DONE (2026-05-29).
     Sloppy simple, extended, constructor, generator, and async call paths now
     suppress the arguments object when parameter names include `arguments`;
     strict-mode validations remain unchanged.
   - ~~**`super()` double-init check.** `Environment::initialize_in_chain`
     overwrote unconditionally; spec `BindThisValue` (§9.1.1.3.1) throws
     on re-init.~~ DONE (2026-05-29): `initialize_in_chain` now rejects a
     second `this` initialization before instance fields run again.
8. ~~**Refactor: extract shared Ext-callable param/body helper.**~~
   DONE (2026-04-19, PR #67 merge `9b97f4c`). `call.mbt` UserFuncExt
   and ArrowFuncExt now share `Interpreter::bind_ext_params_and_exec_body`
   for parameter binding + rest + default eval + destructuring + body_env
   split + hoist_declarations + exec→completion. Caller-specific setup
   stays at each branch: UserFuncExt creates the §15.2.5 self-name
   wrapper (when `has_name_binding` fires), runs strict duplicate/name
   validation, and installs `this` / `<new.target>` / `arguments`;
   ArrowFuncExt just parents `param_env` on `data.closure`.
   Net -79 lines (337 → 258). 915/915 unit tests pass, `.mbti`
   unchanged, test262 class / function-expression / arrow-function
   counts all preserved.
9. ~~**Port `bind_ext_params_and_exec_body` pattern to `construct.mbt`.**~~
   DONE (2026-04-20, PR #68 merge `95abfa4`). Split
   `Interpreter::bind_ext_params_and_exec_body` into a `Signal`-returning
   core (`_signal` variant) and a thin Value wrapper applying the
   call-mode ES §10.2.1 [[Call]] return rule (Normal→Undefined,
   ReturnSignal(v)→v). Break/Continue raise SyntaxError inside the
   core so both callers share the invariant. `construct.mbt`'s
   `UserFuncExt(data)` branch in `construct_value` migrated to call
   `_signal` directly, applying the ES §10.2.2 [[Construct]] steps 13-14
   return rule inline (object-like return replaces `new_obj`; anything
   else yields `new_obj`). Net **−53 LoC** (construct.mbt −100,
   call.mbt +47 wrapper). `.mbti` unchanged. 927/927 unit tests pass.
   test262 probes on `language/statements/class/scope` (24/30),
   `language/expressions/new` (134/140), `language/expressions/function`
   (442/468), `language/expressions/arrow-function` (620/635) all
   steady at post-PR-#66 rates.

   **Scope-excluded** (the "if their shapes align" qualifier): the
   class-ctor body arm (`construct.mbt` ~line 845) and the derived-class
   implicit-super arm (~line 1044) carry loose
   `(Array[@ast.Param], String?, Array[@ast.Stmt])` / `strict: Bool`
   fields rather than a packaged `FuncDataExt`; additionally they
   return `current_this` on Normal completion (not `Undefined`) and
   splice `install_instance_fields` / `maybe_set_promise_constructor`
   mid-match. A second helper shape would be needed — tracked as #A.10
   below rather than folded into this PR.
~~10. **Second helper for class-ctor arms**~~ — DONE (2026-05-06, PR #81, commit `f34e169`). (surfaced 2026-04-20 by
    #A.9 scope-out). The two class-ctor shapes — base-class
    constructor body (`construct.mbt` ~line 845) and derived-class
    implicit-super arm (~line 1044) — share shape with each other but
    not with `FuncDataExt`. Both take
    `(Array[@ast.Param], String?, Array[@ast.Stmt], strict: Bool)`
    sourced from `ClassConstructorData.ctor_fn` (see
    `interpreter/runtime/value.mbt:73`). Divergences from the Ext
    helper:

    - Normal completion returns `current_this` (read from
      `ctor_env.get("this")`), not `Undefined` or `new_obj`.
    - Derived ctor splices `install_instance_fields(this_arg, fields)`
      mid-match, after super()-resolved `this` is available but before
      the constructor body's return value is reduced.
    - No `has_name_binding` / self-name-env wrapper (class names are
      on the class's own environment, not threaded through `data.name`).
    - Strictness is always `true` (class bodies are strict-by-default
      per §15.7.2) rather than threaded through `data.strict`.

    Proposed shape: `Interpreter::bind_class_ctor_params_and_exec_body_signal`
    that takes the tuple + param_env + ctx and returns `Signal`,
    leaving caller-specific `current_this` readout and field-install
    splice outside. The base-class arm collapses its ~120 lines of
    param-binding / rest / split-scope / hoist / exec to a helper call
    plus a 5-line return-rule match. The derived-class arm absorbs
    similar savings but needs care around the implicit-super env
    shape — the helper can't see inside the super() resolution.

    Estimated net savings: −150 LoC once both arms are migrated.
    Pure refactor, zero behavior change; test262 class-scope +
    language/expressions/new expected to stay flat. Previously
    sequenced behind Stage B.1 (which shipped 2026-04-20 as PR #69);
    now queued alongside Stage B.2 — pick whichever fits the next
    session's appetite.

#### B. test262 runner `_FIXTURE.js` path resolver — sibling gap CLOSED (2026-04-18, +17 tests)

**Status**: sibling-fixture imports resolved on `fix/test262-fixture-resolver`
(commit 1cb83bb). `language/module-code` 61.9% → 64.7%.

**Remaining 62 "Cannot find module" failures are NOT runner gaps**:
- **Self-imports** (e.g. `instn-once.js` does `import './instn-once.js'`):
  the test imports its own filename. Engine evaluates then registers, so
  at import-time the test isn't in `module_registry`.
- **Cycles** (`*-cycle-1` ↔ `*-cycle-2`): same root cause.

Both need ES2020 module instantiation-phase support (pre-bind exports
before evaluation) — engine work, not runner.

### Architectural track (multi-PR; see architecture-redesign-2026-04-17-probes.md)

Redesign targeting CP-1 (proxy access protocol) and CP-2 (ArrayData
representation). Staged:

- ~~**Stage A — PropertyBag extraction.**~~ ✅ DONE (2026-04-17, PR #49).
  Pure refactor landed in 3 commits: core consolidation (b00a76d),
  `PropertyBag::new` custom constructor (3ef1192), `MapData::new` /
  `SetData::new` custom constructors (29f6164). 0 test262 delta, 884/884
  unit tests, CodeRabbit surfaced 4 pre-existing bugs (tracked below, not
  regressions).
- ~~**Stage B.1 — `[[Set]]` dispatcher.**~~ ✅ DONE (2026-04-20, PR #69,
  merge `ab5c009`). **Net +30 test262 tests** (Proxy 370→382 +12,
  Reflect 240→258 +18, Object 0 delta). 927→940 unit tests (+13 whitebox
  guards). Five review rounds expanded the PR past the 22-test probe:
  (a) writable-data short-circuit in the proto walk so a higher Proxy
  prototype's set trap doesn't fire after a data-descriptor stop;
  (b) `Reflect.set` setter-only accessor preflight — gate non-writable
  block on `setter is None` (accessor descriptors default `writable=false`);
  (c) `Map(rdata)` / `Set(rdata)` arms added to `define_value_on_receiver`
  (they carry `PropertyBag` since Stage A but were falling through to the
  primitive `_`); (d) shared `check_proxy_set_trap_invariants(target, key,
  value)` helper (handles String + Symbol keys) called from both `proxy_set`
  and `set_computed_property`'s Proxy-trap branch — previously only the
  string-key path ran §10.5.9 step 11-12; (e) `existing_receiver_desc_blocks`
  predicate pulled §10.1.9.2 step 3.e forward from B.2 — `Reflect.set({},
  "x", v, frozen)` was mutating frozen objects before this fix.

  **B.2 debt inherited from B.1's landing helper (flagged inline as `B.2:`
  comments in property.mbt):**
  - Array receiver landing delegates through `set_property`, re-firing
    Array `[[Set]]` exotic semantics instead of `[[DefineOwnProperty]]`.
    Observable: `Reflect.set({}, "length", 10, arr)` should return false
    (full-attributes redefine of non-configurable `length`) but truncates.
  - Proxy receiver arm unwraps targets rather than dispatching through
    `defineProperty` trap. The `Proxy/set/trap-is-missing-receiver-multiple-
    calls*` family (4 tests) remains failing; needs a real `[[DefineOwn
    Property]]` dispatcher to hit both getOwnPropertyDescriptor and
    defineProperty traps on the receiver chain.
  - Map/Set/Promise/Array proto-chain inherited-setter walks skipped
    entirely because those four structs carry no `prototype` field (only
    `ObjectData` does). Separate architectural item — adding prototype
    fields to the four structs or threading implicit builtin prototypes
    through the dispatcher. Rare user-observable case (`class D extends
    Map` with setters on Map.prototype).
- ~~**Stage B.2 — `[[GetOwnProperty]]` + `[[DefineOwnProperty]]`.**~~ ✅ DONE
  (PR [#72](https://github.com/dowdiness/js_engine/pull/72), merged
  2026-04-22 as `a50d293`). Introduces
  `Interpreter::get_own_property` / `Interpreter::define_own_property`
  dispatchers routing §10.1.5 / §10.1.6 / §10.4.2.1 / §10.4.2.4 / §10.5.5
  / §10.5.6 through one seam. `PartialDescriptor` type disambiguates
  "attribute absent" from "attribute present with default", enabling a
  faithful VAP (§10.1.6.3) implementation. `ArrayData.length_writable`
  added (new field) and gated on all four computed-[[Set]] paths
  (set_property + set_computed_property × Number/String-canonical/"length")
  per §10.4.2.1 step 3.b / §10.4.2.4 step 3. Proxy invariant set expanded
  for GOPD/DefineProperty: §10.5.5 step 17.a descriptor-kind invariance
  + 17.a enumerable-match + 17.b SameValue extension + 17.c non-extensible
  non-configurable + §10.5.6 step 18.c writable-to-non-writable + Symbol
  key-aware lookups. Object.defineProperty / defineProperties /
  getOwnPropertyDescriptor and Reflect.defineProperty /
  getOwnPropertyDescriptor migrated off B.1-era inline logic. Net
  stdlib simplification ≈ −762 LoC across the descriptor files.
  Six review rounds (Codex pre+post + 4 line-anchored, CodeRabbit 1)
  tightened spec ordering, invariants, key coercion, and surfaced one
  `try { stmt } catch { _ => () }` anti-pattern that was swallowing
  strict-mode TypeErrors.

  **Test262 delta (per-mode, authoritative from CI run 24772376529
  vs. main pre-B.2 run 24756618839):**

  | Mode       | Passed / Executed (before → after) | Δ   |
  |------------|------------------------------------|-----|
  | strict     | 23,066/26,611 → 23,158/26,599 (86.7→87.1%) | +92 |
  | non-strict | 24,479/28,765 → 24,571/28,767 (85.1→85.4%) | +92 |

  Largest filter-level movement: `built-ins/Object/defineProperty`
  1926→1960 (+34), driven by ToPropertyKey ordering + Symbol-key
  defineProperties + array mutator length_writable integration.
  `built-ins/Proxy` strict 210→213 (+3) from the §10.5.5 invariant
  extensions. Unit tests 995/995.

  **Three B.1 approximations retired** (define_value_on_receiver Array arm,
  Proxy arm, and the receiver-landing delegation path — inline comments
  marked `B.2:` in property.mbt are now gone).

  **Scope-outs carried forward to Stage C or beyond:**
  - Array-exotic indexed-element descriptor storage (§10.4.2.1 beyond
    length/defaults) — blocked on Stage C's PropertyBag-on-Array.
  - Array accepts `{value: 1}` as default data descriptor without the
    {writable: false, enumerable: false, configurable: false} defaults
    the spec demands (minor concern; low test262 impact).
  - Sparse-array physical/logical length delta — non-trivial refactor;
    tracked separately.
  - Map/Set/Promise/Array proto-chain inherited descriptors — same
    architectural block as B.1 approximation #3 (no `prototype` slot
    on the four structs).
  - Proxy-as-Properties in `Object.defineProperties` — needs the
    ownKeys + getOwnPropertyDescriptor trap chain on the source object.
  - `Array.prototype.push/pop/shift/unshift` (generic-this path in
    `builtins_array_init.mbt`) still bypass `length_writable`. The
    fast-path (Array-target only) in `builtins_array.mbt` now honors
    it, but the prototype versions fire for Array-like non-Array `this`
    values where `length_writable` as a concept doesn't apply — reclassify
    if/when adding per-instance length writability to non-Array objects.
  - ~~TypedArray string-key access bugs (wide-catch swallowing `to_number`
    TypeErrors, missing `"-0"` canonical-invalid guard, receiver-ignoring
    `[[Set]]`, missing classifier helper).~~ DONE — shipped across
    `1a29705` (wide-catch + `"-0"` guard, PR #75), `a807e9f`
    (`classify_typedarray_string_key` extraction), `c033837`
    (§10.4.5.5 receiver-sensitive `[[Set]]`); all three queued for v0.2.2.
- ~~**Stage C — ArrayData.bag.**~~ DONE (2026-04-23). Array named,
  symbol, length override, and array prototype override state now lives
  in `ArrayData.bag`; indexed descriptors persist their attributes
  there. This removed the remaining array property side tables.
- ~~**Stage B.3 — `[[HasProperty]]` dispatcher.**~~ DONE (2026-04-23).
  `in`, `Reflect.has`, Proxy `has` forwarding, Proxy-in-prototype chains,
  and `with` binding lookup now share the key-aware HasProperty path.
  Review follow-ups folded into the same patch:
  - setter-only indexed array accessors return `undefined`;
  - internal array override slots are symbol-keyed and not observable as
    string properties;
  - ordinary reads honor Proxy prototypes and array prototype overrides;
  - `with` binding lookup propagates Proxy `has` / `@@unscopables` abrupt
    completions;
  - callable objects preserve `Function.prototype` fallback for
    HasProperty;
  - `Object.getPrototypeOf`, `Reflect.getPrototypeOf`, and Proxy
    `getPrototypeOf` observe array prototype overrides consistently.
  Local validation: `moon check`, `moon test` (1002/1002), and targeted
  `make test262-filter FILTER=built-ins/Proxy/has` with zero failures
  across executed tasks.
- **Stage D — Realm hermeticity.** 0 tests; ship when convenient.

- ~~**`construct` NewTarget threading (~12 Proxy).**~~ — DONE (2026-04-24, branch `claude/agent-todo-task-8FZae`)

  Added `new_target? : Value? = None` to `construct_value`; effective value
  computed as `new_target.unwrap_or(ctor)`. Changes:
  - **Proxy trap call** (`construct.mbt`): third arg is now `new_target` instead of `ctor`.
  - **Proxy no-trap recursion**: forwards both `proto_override~` and `new_target=Some(new_target)`.
  - **UserFunc / UserFuncExt / ClassConstructor** `<new.target>` binds: use `new_target` instead of `ctor`.
  - **BoundFunc** (`construct.mbt`): per §10.4.1.2, if `new_target === ctor` (bound function), pass `None` so the recursive call defaults to `target`; else forward `Some(new_target)`. Uses `physical_equal`.
  - **Implicit super() via non-ClassConstructor path** (`construct.mbt`): passes `new_target=Some(new_target)` so a Proxy superclass trap receives the derived constructor.
  - **`SuperCall` in `eval_expr.mbt`**: the inline ClassConstructor super-body path now defines `<new.target>` in `call_env` from the calling env's `<new.target>` so `new.target` in a super-class constructor body correctly reflects the derived class.
  - **`Reflect.construct`** (`builtins_reflect.mbt`): now passes `new_target=Some(nt)` when a third arg is present, alongside the existing `proto_override~`.

  Regression guard: 5 new unit tests (Proxy trap receives BarCtor, no-trap path, direct new.target unchanged, Reflect.construct body binding, super() propagation).

- **`revocable` `typeof` post-revoke (~8 Proxy).** Investigation (2026-04-24)
  shows the implementation is already correct: `type_of` in
  `conversions.mbt:970-975` reads `proxy_data.is_callable` which is set at
  creation and persists after `revoke()` nullifies target/handler. Other
  operations correctly throw via `get_proxy_trap` → `get_proxy_handler`
  returning `None`. The ~8 tests likely cover adjacent behaviour (e.g. that
  `typeof` does **not** throw while `obj.x`, `delete`, `in` etc. do).
  **Action**: run `scripts/test262-runner.py --filter "built-ins/Proxy/revocable"` to
  confirm pass rate; if failures remain, check what operation they exercise.

Post-B.3 language follow-up:
- ~~**Strict reserved words as early errors.**~~ DONE (2026-04-23,
  `b79e2e9`). The parser still accepts sloppy-mode `static` as an
  identifier, but strict IdentifierReference / binding / assignment-target
  uses are now rejected by the AST early-error walk rather than only by
  runtime evaluators. This fixes unreachable strict code such as
  `"use strict"; if (false) { static; }` and destructuring assignment
  targets like `({x: eval} = obj)`. Local validation:
  `moon check`, `moon test` (1005/1005),
  `make test262-filter FILTER=language/reserved-words`
  (53 passed / 53 executed / 53 discovered), and
  `make test262-filter FILTER=language/future-reserved-words`
  (85 passed / 85 executed / 85 discovered).

B.3 follow-ups now worth isolating in later PRs:
- **General prototype slots for non-Object variants.** Array has a bag-backed
  prototype override as a stopgap, but Map/Set/Promise still expose only
  builtin constructor prototypes. A full model should give every object-typed
  variant a coherent observable `[[Prototype]]` used by
  `Object.getPrototypeOf`, `Reflect.getPrototypeOf`, `setPrototypeOf`,
  `isPrototypeOf`, `instanceof`, `[[Get]]`, `[[Set]]`, and `[[HasProperty]]`.
- **Array prototype override consumers still need audit.** B.3 fixed ordinary
  reads and `getPrototypeOf`; `Object.prototype.isPrototypeOf` and
  `instanceof` still use constructor prototypes for arrays and should be
  routed through the same helper.
- **Array extensibility remains approximate.** Proxy `getPrototypeOf` /
  `setPrototypeOf` invariants treat arrays as always extensible until
  `ArrayData` carries extensibility state.

---

## Recommended Next Targets (2026-04-16 analysis)

Remaining failures are widely distributed — no single fix unlocks 300+ tests. Progress requires many small, targeted fixes. Ordered by estimated ROI.

### Quick wins (1-session each, 10-50 tests each)

#### ~~1. Proxy trap invariant checks~~ — DONE (2026-04-16)

**Result**: Proxy/ overall 295/536 → 366/536 (+136 tests, 42.9% → 68.3%)

Centralized all proxy trap invariant validation in `interpreter/runtime/proxy_helpers.mbt` with 9 public helper functions. Updated `Object.*`, `Reflect.*`, `in` operator, and `delete` operator to use these helpers.

| Trap | Before | After | Status |
|------|--------|-------|--------|
| ownKeys | 2/50 | **50/50** | ✅ Full spec invariants |
| isExtensible | 2/22 | **20/22** | ✅ 2 remaining: Array extensibility tracking |
| preventExtensions | — | ✅ | Trap invocation + invariant |
| getPrototypeOf | — | ✅ | Trap invocation + invariant |
| setPrototypeOf | — | ✅ | Trap invocation + invariant |
| has | — | ✅ | Invariant checks added |
| deleteProperty | — | ✅ | Invariant checks added |
| get | — | ✅ | Invariant checks added |
| set | — | ✅ | Invariant checks added |

**Remaining Proxy failures** (170/536):
- **set receiver forwarding** (36 failures): when no trap, receiver must be forwarded through `target.[[Set]]`, not lost. Requires threading receiver through `set_property` chain.
- **setPrototypeOf** (12 failures): nested proxy + prototype chain interactions
- **getOwnPropertyDescriptor** (8 failures): descriptor result comparison invariants
- **isExtensible** (2 failures): Array values lack `extensible` field tracking
- **Misc** (4 failures): property-order, revoked function proxy

#### ~~2. Iterator close on abrupt completion~~ — DONE (2026-04-24, branch `claude/agent-todo-task-8FZae`)

**Impact**: ~20-30 tests across `language/statements/for-of`
**Files**: `interpreter/runtime/exec_stmt.mbt`

Three code paths were missing `IteratorClose` calls:
1. **`ForOfStmt` (`var_kind=None`)**: `env.assign` for `for (x of arr)` could throw (e.g. const target) without closing the iterator.
2. **`ForOfStmtPat`**: `bind_pattern` (for `let {x}`) and `assign_pattern` (for `{x}` without declaration) could throw without closing.
3. **`ForOfExpr`** (`for (obj.x of arr)`): `assign_to_expr` could throw, body execution not wrapped, and all abrupt signals (Return, Break, labeled-Break, non-matching-Continue) returned without calling `iterator.return()`.

Fix: wrap each missing throw site with catch→IteratorClose→re-raise; add `close_iterator` before every non-Normal signal exit in `ForOfExpr`. The `catch { _ => () }` on `close_iterator` itself is intentional: spec §7.4.10 step 5 says for throw completions the original error takes priority over any close error. 8 regression tests added.

**Follow-up (2026-04-24, branch `claude/agent-todo-task-8FZae`)**: Codex review on PR #74 identified a second gap: non-throw completions (Return, Break, non-matching-Continue) were also suppressing `return()` errors via `catch { _ => () }`. Per §7.4.10 steps 5 and 7, for non-throw completions: (a) if `return()` throws, that error replaces the completion; (b) if `return()` returns a non-Object, raise TypeError. Fix: removed `catch { _ => () }` from all three ForOf non-throw paths (ForOfStmt, ForOfStmtPat, ForOfExpr) and updated `close_iterator` to validate the `return()` result. Callers handling throw completions keep `catch { _ => () }` per step 4. 3 regression tests added.

#### ~~3. Mapped arguments object~~ — DONE (2026-05-06, PR #81)

`make_arguments_object` now creates a spec-compliant mapped arguments object per §10.4.4.1 / §10.4.4.7. Sloppy-mode simple-parameter functions get live accessor slots backed by closures over the parameter environment. Duplicate parameter names are handled correctly: a backwards scan ensures only the last occurrence of each name is mapped as an accessor; earlier occurrences become plain data properties. Known issue #11 from PR #45.

**Follow-up (not in PR #81): Arguments exotic object `[[GetOwnProperty]]` descriptor shape.**
Our implementation stores live-binding closures as accessor descriptors directly in `bag.descriptors`. Per §10.4.4.2, `[[GetOwnProperty]]` on an Arguments exotic object must return a **data descriptor** with the live value, not an accessor descriptor. `Object.getOwnPropertyDescriptor(arguments, "0")` currently leaks the internal getter/setter. Fixing this correctly requires:
- A separate `[[ParameterMap]]` internal slot on the arguments object (holding the accessor functions)
- Overrides for `[[GetOwnProperty]]`, `[[DefineOwnProperty]]`, `[[Get]]`, and `[[Set]]` that consult the map
- Likely a new `class_name` sentinel (e.g. `"Arguments"`) to gate the exotic behaviour in `get_own_property` / `set_property` / `get_property`

Estimated effort: medium (multi-surface, but contained to `construct.mbt` + `property.mbt`).

### Medium effort (multi-session)

#### 4. Proxy internal operation forwarding (partially done)

**Impact**: Subset of remaining 170 Proxy failures
**Files**: `interpreter/runtime/property.mbt`, `interpreter/runtime/eval_expr.mbt`, `interpreter/runtime/exec_stmt.mbt`

Remaining deferred items from Phase 15 (3 of 6 now done):
- ~~`Object.getPrototypeOf` doesn't invoke the trap~~ ✅ Fixed 2026-04-16
- ~~`for-in` doesn't invoke `ownKeys` trap~~ ✅ Fixed 2026-05-06 (PR #81): `collect_for_in_keys` now calls `proxy_own_property_keys`, filters via `proxy_get_own_property`, and walks via `proxy_get_prototype_of`
- ~~`instanceof` doesn't invoke `getPrototypeOf` trap for prototype chain walk~~ ✅ Fixed 2026-05-06 (PR #81): `instanceof_prototype_chain` now takes `Interpreter` and calls `proxy_get_prototype_of` for Proxy values in both the initial match and the chain walk
- `create_list_from_array_like` bypasses Proxy traps (reads `.properties` directly)
- ~~`Reflect.construct` rewires newTarget prototype after construction instead of before~~ — superseded by `construct` NewTarget threading item above (same root cause, broader fix)
- `unwrap_proxy_target` fails for non-Object types

#### 5. RegExp lookbehind assertions

**Impact**: Unlocks `regexp-lookbehind` feature flag (currently skipped)
**Files**: `interpreter/stdlib/builtins_regex.mbt`

`(?<=...)` positive lookbehind and `(?<!...)` negative lookbehind. Requires backward matching from current position — more complex than lookahead which is already implemented.

#### ~~6. Consolidate `make_*_func` factory variants~~ — DONE (2026-04-18)

Branch: `claude/factory-consolidation`. 8 factories (+ `make_interpreter_callable_with_length`) collapsed into 4 with labeled/optional `name~`/`length?` params plus a shared private `build_func_object(name, length, callable)` helper. 474 call sites migrated across 27 files via regex script; 1 manual fix for a concatenated-name case. Net: ~130 LoC removed from factories.mbt; public API contracted from 8 → 4 symbols. 884/884 unit tests pass; no test262 delta (no runtime semantics changed). Naturally absorbs agent-todo #9 (interpreter-callable prototype bug) via `build_func_object` → `get_func_proto()`.

**Deleted**: `make_native_func_with_length`, `make_static_func`, `make_static_func_with_length`, `make_interp_static_func_with_length`, `make_interpreter_callable_with_length`. **Kept** (with labeled params): `make_native_func`, `make_method_func`, `make_interp_method_func`, `make_interp_static_func`.

#### 12. PropertyDescriptor typestate builder (exploratory)

**Motivation**: The ES spec says a descriptor is *either* a data descriptor (has `writable`, optionally `value`) *or* an accessor descriptor (has `get`/`set`) — never both. Currently `PropDescriptor` is a struct with all five fields, so every combination compiles and invariants are enforced only by runtime checks scattered across `builtins_object_descriptors.mbt`. Stage A's CodeRabbit review surfaced two bugs rooted in this weakness: #10 (`revocable_descs` built but never wired into the object) and #7 (hasOwnProperty missing descriptor-only own props). A typestate builder would make data-vs-accessor a compile-time exclusion and could catch "built but not wired" patterns.

**Sketch**:
```moonbit
DescriptorBuilder::new(enumerable=false, configurable=true)
  .data(writable=true)                // → DataDescState; .getter/.setter not available
  .build()
// vs
DescriptorBuilder::new(configurable=true)
  .accessor(get=g, set=s)             // → AccessorDescState; .writable not available
  .build()
```

**Scope of exploration**: Prototype in a small sub-package; measure call-site ergonomics at a handful of representative sites (`builtins_error.mbt`, `builtins_proxy.mbt`, `builtins.mbt`); decide if full migration is worth the type-theoretic overhead. Not chosen for the 4-factory `make_*_func` consolidation (labeled params were sufficient) because that case had no "mutually-exclusive config" invariant for typestate to enforce. This *does*.

**Why not today**: Adds a non-trivial type-level construct to a codebase whose idiom is direct struct construction. Needs a design doc before implementation, with examples of which current bugs would have been caught. Surfaced 2026-04-18 during #6 consolidation brainstorm.

#### ~~14. User-function property insertion order: `prototype, name, length` → `prototype, length, name`~~ — DONE (2026-04-17, PR #55)

#### ~~26. Consolidate Break/Continue → SyntaxError invariant across runtime~~ — DONE (2026-05-06, PR #81, commit `d0c8243`)

**Impact**: 0 test262 delta (pure refactor, zero behavior change). Medium-ROI tech-debt cleanup surfaced by PR #68 (#A.9) reviewer.

**Problem** (line numbers below are pre-PR-#81; the duplication was consolidated by PR #81 commit `d0c8243`): the invariant "Break/Continue signals escaping a function boundary raise `SyntaxError: break/continue statement outside of loop`" was inlined at ~8 sites with identical bodies but distinct callers:

- `interpreter/runtime/call.mbt:306-309` — UserFuncExt/ArrowFuncExt shared core (now centralized by #A.9)
- `interpreter/runtime/call.mbt:494-496` — `perform_eval` Normal/Return completion handling
- `interpreter/runtime/call.mbt:707-714` — UserFunc call arm (old-style, non-Ext)
- `interpreter/runtime/call.mbt:749-756` — ArrowFunc call arm (old-style)
- `interpreter/runtime/construct.mbt:522-529` — UserFunc (non-Ext) ctor arm
- `interpreter/runtime/construct.mbt:861-868` — class-ctor body arm (covered by #A.10 when it lands)
- `interpreter/runtime/modules.mbt:319-323` — module top-level execution
- `interpreter/runtime/interpreter.mbt:505-510` — top-level script execution

**Why not a single helper**: top-level scripts (`modules.mbt`, `interpreter.mbt:505-510`) and `perform_eval` have **distinct completion rules**. `perform_eval` per §19.2.1 returns the `Normal(v)`'s value (not `Undefined`); top-level scripts per §16.1 can reach `ReturnSignal` only via Annex B (which we don't support yet, so it's currently a defect path). Unifying the Break/Continue raise requires splitting it from the Normal/Return mapping: a `enforce_no_break_continue(sig) -> Signal` helper that raises for Break/Continue and returns `sig` otherwise. Each caller then matches the remaining Normal/Return variants with its own rule.

**Why now not urgent**: zero test262 impact; the 8 sites are functionally correct today. The win is readability plus a single change-site if the SyntaxError message text ever needs to be spec-updated (e.g., `"break statement outside loop"` per current output vs `"Illegal break statement"` per V8/SpiderMonkey — spec doesn't mandate exact text).

**Estimated effort**: 1 session, ~−30 LoC. Recommend bundling with #A.10 (class-ctor helper port) since #A.10 already touches `construct.mbt:861-868`.

---

## Pre-existing bugs exposed by Stage A CodeRabbit review (2026-04-17, PR #49)

Four findings surfaced during CodeRabbit review of PR #49. All four are
pre-existing bugs that predate Stage A — the PropertyBag refactor only
moved the same literal shapes into `bag: { ... }` wrappers. Ordered by
expected test262 impact.

### ~~7. `hasOwnProperty` misses descriptor-only own properties~~ — DONE (2026-04-18)

### ~~8. Engine-thrown errors have empty descriptor maps~~ — DONE (2026-04-18, partial)

### ~~9. Interpreter-callable functions have `prototype: Null`~~ — DONE (2026-04-18)

### ~~10. `Proxy.revocable`: `revocable_descs` built but never wired~~ — DONE (2026-04-18)

All four landed on branch `claude/stage-a-coderabbit-bugfixes` (PR #50). Verified via direct interpreter probes: `Map.prototype.hasOwnProperty("size")` → `true`, `caughtErr instanceof TypeError` → `true`, `Object.getOwnPropertyDescriptor(caughtErr, "message").enumerable` → `false`, `Object.getOwnPropertyDescriptor(Proxy.revocable, "name")` now returns the correct descriptor, Promise resolve callbacks are `instanceof Function`. 884/884 unit tests pass.

**#8 status**: fully completed by stacked PR #13. Intermediate landing preserved `name` as own to avoid toString regressing; the spec-correct shape (name on prototype) lands once consumers are fixed.

#### ~~13. Move `name` off own-property on engine-created errors~~ — DONE (2026-04-18)

Branch: `claude/err-name-on-prototype` (stacked on PR #50). Two consumer fixes plus the `name` removal.

- `Error.prototype.toString` and `AggregateError.prototype.toString` switched from `make_method_func` to `make_interp_method_func` and now use `interp.get_property` for both `name` and `message` (per ES §20.5.3.4 Get semantics — walks prototype chain, invokes accessors).
- `Promise.try` rejection path (`builtins_promise.mbt:729`) now uses `js_error_to_value_with_env(err, Some(interp.global))` so the rejection value gets a proper prototype chain.
- `err_props["name"]` / `err_descs["name"]` removed from `make_error_value_with_env` and `make_aggregate_error_value`.

Result: engine-thrown errors match user-created shape. Probe: `(catch TypeError).toString()` → `"TypeError: …"`; `.name` → `"TypeError"`; `hasOwnProperty("name")` → `false`; `Promise.try(() => null.x).catch(e => e.name)` → `"TypeError"`. test262 gains: `built-ins/Error` +2 (95.0%), `built-ins/Promise` +14 (95.0%).

---

## Pre-existing bugs surfaced by PR #51 review (2026-04-18)

Seven findings + one nitpick. All verified against `main` — identical semantics
pre- and post-#51. None are regressions introduced by the factory consolidation
(which touched call syntax only, not runtime behavior). Kept out of #51 per the
behavior-preserving refactor charter; listed here for follow-up PRs.

### ~~15. Register `InternalError` constructor~~ — DONE (2026-04-17, PR #59)

### ~~16. Bound-function property insertion order: `name, length` → `length, name`~~ — DONE (2026-04-17, PR #54)

### ~~17. `Reflect.set` stringifies Symbol keys~~ — DONE (2026-04-18, PR #60)

### ~~18. `Reflect.get` skips plain data reads on non-Object targets~~ — DONE (2026-04-18, PR #60)

### ~~19. `Reflect.has` rejects Map/Set/Promise and other object variants~~ — DONE (2026-04-18, PR #60)

### ~~20. `Number.prototype.toString` (lookup-path): `length` and `undefined` radix~~ — DONE (2026-04-17, PR #56)

### ~~21. Timer/microtask builtins: `length` should be 1~~ — DONE (2026-04-17, PR #58)

### ~~22. `$262` one-argument helpers: restore explicit `length=1`~~ — DONE (2026-04-17, PR #57)

### ~~23. (Nitpick) Non-constructable `InterpreterCallable` for static builtins~~ — DONE (2026-04-18, PR #63)

**Follow-up**: The `make_method_func`-based static methods (e.g. `Object.preventExtensions`, `Object.keys`) still have the same class of bug — not addressed in PR #63 per scope fence.

### ~~24. `Error.isError` uses a hardcoded class-name allowlist (structural)~~ — DONE (2026-04-18, PR #62)

### ~~25. `lookup_property_chain` ignores `bag.descriptors` (accessor + non-data blind spot)~~ — DONE (2026-04-24, branch `claude/refactor-codebase-safety-tc3IY`)

**Fix**: Added `bag.descriptors` checks at own-property and every prototype step, mirroring `lookup_symbol_property_chain`. Signature changed to accept `obj_val : Value` as first param (receiver for getter invocation) and `raise Error`. When a getter is found and an interpreter is available the getter is invoked with `obj_val` as receiver; without an interpreter `Some(Undefined)` signals presence. All 6 callers updated; `has_property` callers use a new non-raising `lookup_property_chain_safe` wrapper. Stale comment removed from `has_bag_or_builtin_proto_key` doc.

**Post-fix correction (same session, Opus review)**: The initial implementation checked `bag.properties` before `bag.descriptors`. The storage invariant (`eval_expr.mbt` ObjectLit Get/Set arms and `apply_descriptor_to_bag`) always writes `Undefined` into `bag.properties` as a sentinel for every accessor slot. The wrong order returned `Some(Undefined)` immediately, silencing the getter and regressing `to_primitive_*` (the `ip.get_property` fallback was no longer triggered). Fixed by swapping to descriptor-first at both own and prototype steps, matching `get_property_of_object` (`property.mbt:240-248`). A comment documenting the sentinel invariant was added.

### ~~29. `has_property` invokes getters during `[[HasProperty]]` (latent spec issue)~~ — DONE (2026-04-24, same branch)

**Fix**: Replaced both `lookup_property_chain_safe` calls in `has_property` with `Interpreter::has_object_property` (which uses pure `.contains()` checks — no getter invocation) when an interpreter is available. When no interpreter is available the `Object` arm falls back to a bare `bag.properties.contains(name) || bag.descriptors.contains(name)` own-slot check. The Array prototype-walk arm reuses the `ip` already in scope. `lookup_property_chain_safe` remains available for future value-retrieval callers that do want getter invocation. Flagged by Codex (P1) and CodeRabbit during PR #73 review.

**Known remaining nit**: `is_unicode_space_cp` in `lexer/lexer.mbt` omits U+0020 (SP is technically Zs) but is functionally correct because `is_js_whitespace` adds SP separately. A rename to `is_unicode_non_ascii_space_cp` would be more precise but low priority.

---

## Follow-ups from Pre-Stage-C TypeError bundle (2026-04-21, PRs #70 + #71)

Two scope-fenced gaps carried forward from the method-shorthand / TypeError-gate work. Both landed on `main` 2026-04-21 (`e9622a6`, `0eadc5a`).

### ~~27. Class methods should be non-constructor (`class Foo { bar() {} }` → `new obj.bar()` throws TypeError)~~ — DONE (2026-04-22)

**Impact**: low single-digit test262 in `language/statements/class/method-*-invoke-ctor` and `language/expressions/class` cohorts that parallel the merged `language/expressions/object/method-definition/name-invoke-ctor` pair.

**Problem**: PR #71 added `is_method : Bool` to `FuncData` / `FuncDataExt` and set it to `true` for object-literal method shorthand in `Interpreter::eval_prop_value` via the new `mark_as_method` helper. Class methods flow through a **different path** — they bind in `class.mbt` as prototype entries with `is_method: false`, so `is_constructor_value` accepts them and `new obj.bar()` on a class method succeeds instead of throwing per §15.4.5 MethodDefinitionEvaluation.

**Fix sketch**: at the class-method binding site in `class.mbt` (where a `MethodDefinition` becomes a callable value on the class's prototype), create plain function methods with `is_method: true`. Generator and async-generator functions remain spec-visible generator functions with an own `.prototype` property, but `InterpreterCallable` constructability must reject `GeneratorFunction` and `AsyncGeneratorFunction`. Regression guards: mirror `§15.4.5: new ({method() {}}).method() throws TypeError` across `class { m() {} }`, `class { get m() {} }`, `class { set m(v) {} }`, `class { *m() {} }`, `class { async *m() {} }`.

### ~~28. Method-def functions shouldn't have an own `prototype` property~~ — DONE (2026-04-22)

**Impact**: correctness-adjacent follow-on in the same method-def cohort where test262 asserts `typeof obj.m.prototype === "undefined"`.

**Problem**: per §15.4.5 step 9, method definitions explicitly do NOT go through MakeConstructor — which is the step that adds the `prototype` own property for regular functions. Current user-function materialization adds `prototype` unconditionally. With the `is_method: true` flag now available from PR #71, the fix is a one-line gate.

**Fix sketch**: in `make_func` / `make_func_ext` in `factories.mbt` (or wherever the `prototype` property is assigned during user-function materialization), gate the assignment on `!func_data.is_method`. Regression guard: `typeof ({m() {}}).m.prototype === "undefined"` (currently `"object"`).

---

## ~~Codebase safety refactor (dead code + duplication)~~ — DONE (2026-04-24, branch `claude/refactor-codebase-safety-tc3IY`)

Three incremental passes. Each was scoped to a single package or file pair, verified by exhaustive grep before touching code, and committed independently with explicit impact documentation.

### ~~Pass 1 — `errors` dead public API removal~~

Removed 13 dead public functions from `errors/errors.mbt`: `JsError::debug`, `is_js_error`, and 11 convenience raise-functions (`syntax_error`, `syntax_error_msg`, `type_error`, `type_error_msg`, `reference_error`, `reference_error_msg`, `range_error_msg`, `uri_error_msg`, `internal_error_msg`). Zero callers confirmed by exhaustive grep across all 941 `@errors` usages — every call site raises variants directly (`raise @errors.SyntaxError(message=…)`).

Removing the three `@token.Loc`-bearing raise-functions also eliminated the `errors → token` package coupling. `errors/moon.pkg` is now empty.

**Kept**: `JsError::name`, `get_message`, `format` — uncalled internally but legitimate public library utilities. `JsError` type and all 8 variants: unchanged.

### ~~Pass 2 — Lexer Zs deduplication~~

Extracted private `fn is_unicode_space_cp(cp: Int) -> Bool` from the identical 7-entry Unicode Space Separator (Zs) codepoint list that appeared in both `is_js_whitespace` and `is_whitespace_or_line_terminator_cp` in `lexer/lexer.mbt`. Both now delegate to the shared helper. Net: −6 lines, zero behavior change, no public API change.

### ~~Pass 3 — ECMAScript whitespace canonical function~~

Consolidated three separate copies of the 15-entry ECMAScript WhiteSpace+LineTerminator codepoint list (across `interpreter/runtime/conversions.mbt`, `interpreter/stdlib/builtins_string.mbt`, `interpreter/stdlib/builtins_number.mbt`) into a single canonical `pub fn is_es_whitespace_cp(cp: Int) -> Bool` in `interpreter/runtime/conversions.mbt`. `is_js_whitespace_code(UInt16)` and `is_es_whitespace(Char)` now delegate via `.to_int()`; `is_parse_whitespace(Char)` deleted and its one call site renamed to `is_es_whitespace`. Net: −76 +20 lines across 4 files.

**Known remaining cross-dependency**: `is_js_whitespace(Char)` and `is_unicode_space_cp(Int)` in `lexer/lexer.mbt` cannot share code with `is_es_whitespace_cp` in `interpreter/runtime`. The lexer must not depend on the interpreter. `is_unicode_space_cp` is a deliberate subset (Zs only, no ASCII, no line terminators) and its separation is correct.

---

## ~~Lexer numeric parser consolidation~~ — DONE (2026-04-24, branch claude/refactor-codebase-safety-tc3IY)

**Result**: Merged `parse_binary` and `parse_octal` into `parse_radix_literal(s, base)`. Three call sites updated: `parse_radix_literal(bin_str, 2.0)`, `parse_radix_literal(oct_str, 8.0)` ×2. `parse_hex` kept separate — its three-branch digit mapping for `0–9` / `a–f` / `A–F` differs structurally from the simple `c.to_int() - 48` of the other two.

---

## Doc-infrastructure follow-ups (2026-05-08, from `5248ee3` doc refresh)

### `built-ins/TypedArray` 51.2% — regression vs. methodology, open question

**Context**: `5248ee3` refreshed `docs/supported-features.md` per-category tables from CI run `25538356718` on tip `c6a20dd` (2026-05-08). `built-ins/TypedArray` strict reads `398/379/653 (51.2% P/E, 27.8% P/D)`. ROADMAP Phase 17–19 (2026-02-14/15, pre-Phase-24 single-mode runner) cited `726/777 (93.4%)`. Both reports land on `Executed = 777` — methodology shift alone cannot explain a 42pp gap.

**Hypotheses to investigate** (in rough order of likelihood):

1. **Skip-list churn** — the 777 executed in Phase 17 and the 777 executed today may not be the same 777 files. The skip list has been edited many times since 2026-02-15 (PRs #49–#84). Diff `scripts/test262-runner.py` skip directives between `~Phase 19` and tip; map files in/out.
2. **Per-mode strict failures distinct from non-strict** — Phase 17's single-mode counted a file passing if it passed in *whatever* mode the runner ran. If many TypedArray tests pass non-strict but fail strict (or vice versa), per-mode counts both as failures while single-mode counted them as one pass.
3. **Genuine regression** — some PR between Phase 19 and `c6a20dd` regressed TypedArray semantics. Bisect candidates: Stage A (PR #49), Stage B.1 (#69), Stage B.2 (#72), Stage C (2026-04-23), Stage B.3 (2026-04-23), the v0.2.2 TypedArray fixes themselves (`1a29705`, `a807e9f`, `c033837`).

**How to investigate**:

- `make test262-quick ARGS="--filter built-ins/TypedArray --strict"` against tip and against a Phase-19-era ref, compare result JSONs.
- For hypothesis (2), filter `25538356718` artifact JSONs to TypedArray and count strict-only failures vs non-strict-only failures.
- For hypothesis (3), `git bisect run` with TypedArray-only filter once a target failure file is identified.

**Why this matters**: a public ROADMAP page citing `93.4%` next to a current `51.2%` is confusing without a resolved explanation. Either ROADMAP needs a methodology footnote, or the regression needs fixing — but we shouldn't ship v0.2.2 release notes without knowing which.

### Per-Edition tables in `supported-features.md` blocked on classifier schema change

**Context**: `5248ee3` left the Per-Edition tables (lines 23–61) on the older 2026-04-24 / `b225cda` run, with a "run-version mismatch (acknowledged)" note. The newer `classify-by-edition.py` output (run against 2026-05-08 / `c6a20dd` artifact JSONs) emits **9 edition rows** (Pre-ES2015, ES2015, ES2017, ES2018, ES2020, ES2021, ES2025, Annex B, Stage 3); the existing tables have **15 rows** (additionally: ES2016, ES2019, ES2022, ES2023, ES2024).

**Hypotheses for the missing rows**:

1. The `FEATURE_EDITION` map in `scripts/classify-by-edition.py` was simplified between the two runs and intermediate-edition features now fall through to a coarser bucket.
2. The fallback path-based reclassifier (added to address the "tests with no `features:` frontmatter" case) is dominating, pushing tests into Pre-ES2015 / ES2015 buckets that previously sat in ES2016+.
3. The empty-rows are present in the current run but with `Discovered = 0` and the `--markdown` formatter elides zero-rows.

**How to investigate**: read the current `classify-by-edition.py`, diff against `~b225cda`, run with `--show-unmapped` to see what's missing from the map. If hypothesis (3): patch the formatter to emit zero-rows when generating doc tables.

**Why this matters**: editions ES2016–ES2024 are precisely where partial-implementation drama lives (regexp-v-flag, array-grouping, BigInt, class-private). Collapsing them into an "ES2015 / Annex B / Stage 3" view loses the granularity that makes the doc useful for prioritization.
