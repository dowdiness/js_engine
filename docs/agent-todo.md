# Agent Task Queue

Tasks are ordered by effort/impact. Each is self-contained enough to complete in one session.
Completed tasks should be struck through and dated.

---

## ~~Next PR: Small Compliance Wins~~ — DONE (2026-04-12, PR #45)

**Branch**: `claude/compliance-quick-wins`
**Result**: Unlocked 4 feature flags: `regexp-dotall`, `async-functions`, `promise-with-resolvers`, `promise-try`

### Task 1 — Unlock `regexp-dotall` (already implemented, zero-code change)

The `s` flag is fully implemented in `interpreter/builtins_regex.mbt`:
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

**Action**: In `test262-runner.py`, remove `"regexp-dotall"` from `SKIP_FEATURES`.
Run `python3 test262-runner.py --filter "built-ins/RegExp" --summary` to confirm pass rate improves.

---

### Task 2 — Add `Promise.withResolvers()`

**Spec**: https://tc39.es/ecma262/#sec-promise.withresolvers
**Feature flag**: `"promise-with-resolvers"` in `SKIP_FEATURES`
**File**: `interpreter/builtins_promise.mbt`

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

After implementing: remove `"promise-with-resolvers"` from `SKIP_FEATURES` and run
`python3 test262-runner.py --filter "built-ins/Promise" --summary`.

---

### Task 3 — Add `Promise.try()`

**Spec**: https://tc39.es/ecma262/#sec-promise.try
**Feature flag**: `"promise-try"` in `SKIP_FEATURES`
**File**: `interpreter/builtins_promise.mbt`

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

Same file and pattern as `withResolvers`. After implementing: remove `"promise-try"` from `SKIP_FEATURES`.

---

### Task 4 — Audit and unlock `async-functions`

**Feature flag**: `"async-functions"` in `SKIP_FEATURES`

**Current state** (verified 2026-04-12):
- `async function`, `async () =>`, `await expr` all parse and execute correctly
- `async function f(x) { return x * 2; }` and multi-level `await` work
- `for await...of` does NOT parse (that's `async-iteration`, separate flag — keep skipped)

**Investigation steps**:
1. Run the async-functions subset:
   ```bash
   python3 test262-runner.py --filter "language/statements/async-function" --summary
   python3 test262-runner.py --filter "language/expressions/async-arrow-function" --summary
   python3 test262-runner.py --filter "built-ins/AsyncFunction" --summary
   ```
   Do this BEFORE removing the flag — re-enable temporarily in test code or run with `--include-skipped` if supported.

   Alternatively: temporarily comment out `"async-functions"` from `SKIP_FEATURES`, run the filter, restore.

2. Review failures. Common gaps:
   - `AsyncFunction` constructor (`new AsyncFunction(...)`)
   - `async function*.length` / `.name` property descriptors
   - Top-level return value from async functions (should always be a Promise)
   - Rejected promise on thrown error propagation timing

3. Fix whatever is failing, then remove `"async-functions"` from `SKIP_FEATURES`.

**Note**: Keep `"async-iteration"` in `SKIP_FEATURES` — `for await` is not yet parsed
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
11. **Mapped arguments not implemented** — `make_arguments_object` in `construct.mbt` creates a plain copy, not a spec-compliant mapped arguments object. Affects both sync and async functions in sloppy mode.

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
- 6: `verifyProperty`/`getOwnPropertyDescriptor` on array named props (side table not visible)
- 4: RegExp subclass exec/match forwarding
- 8: Unicode identifiers (`π`, `𝑓`) in JS lexer (lexer can't parse non-ASCII identifiers)

---

## Pre-existing gaps exposed by named-groups (2026-04-15)

Cross-cutting issues discovered during PR #47 that affect more than just named groups.

### 1. Array named props invisible to `getOwnPropertyDescriptor`

**Impact**: ~6 named-groups tests + many regex/array tests across the suite
**File**: `interpreter/array_side_tables.mbt`, `interpreter/builtins_object_descriptors.mbt`

`set_array_named_prop` stores properties (like `index`, `input`, `groups` on regex match arrays) in a side table (`array_named_props`). `Object.getOwnPropertyDescriptor` doesn't check this side table, so these properties are invisible to descriptor inspection. The `verifyProperty` test262 helper fails for all array named props.

**Fix**: Make `getOwnPropertyDescriptor` for `Array` values check the side table. Also consider migrating match arrays to `Object` with indexed elements instead of `Array` with named prop side table.

### ~~2. Regex callback replace not implemented~~ — DONE (2026-04-16)

`[Symbol.replace]` now supports function replacements via `string_replace_regex_func` and `call_replace_fn`. Callback receives `(match, ...captures, offset, string, groups)` per spec. `String.prototype.replace` delegates to `Symbol.replace` for RegExp arguments, which handles the function case.

### 3. JS lexer rejects non-ASCII identifiers

**Impact**: 8 named-groups tests + general Unicode identifier support
**File**: `lexer/lexer.mbt`

The lexer's identifier scanning only accepts ASCII `[a-zA-Z_$]` starts. Unicode letters like `π` (U+03C0) or mathematical italics like `𝑓` (U+1D453) are rejected as unexpected characters. These are valid JS identifiers and appear in test262 as regex literal group names like `/(?<π>x)/`.

### 4. RegExp subclass exec/match forwarding

**Impact**: 4 named-groups tests
**File**: `interpreter/builtins_regex.mbt`

RegExp subclass tests expect `exec()` to be called on the subclass instance (which may override `exec`), but the engine calls internal regex functions directly. Needs `Symbol.match` / `Symbol.replace` to call `this.exec()` through the prototype chain.

---

## Later PR: `for-await` / `async-iteration`

**Feature flag**: `"async-iteration"` in `SKIP_FEATURES`
**Estimated tests**: ~200+

**Current state**: `for await (const v of iterable)` fails to parse.
The parser (`parser/`) needs a `ForAwait` AST node and the interpreter needs to handle
async iteration protocol (`Symbol.asyncIterator`, `next()` returning Promises).

This is a medium-effort feature. The generator/iterator infrastructure in
`interpreter/generator.mbt` and `interpreter/iterators.mbt` is the foundation — read
those first.

---

## ~~Later PR: Stage 3/4 Sub-package Extraction~~ — DONE (2026-04-15, branch `claude/restructure-architecture-VkLTl`)

All four stages shipped. See [docs/architecture-redesign-2026-04-15.md](architecture-redesign-2026-04-15.md) for the full analysis.

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

#### A. Annex B eval-scope hoisting — ~346 tests

**Impact**: `language/eval-code` 62.6% → est. 90%+
**File**: `interpreter/runtime/hoisting.mbt`

Failure classification of all 389 `language/eval-code` failures: 282
assertion mismatches + 64 binding-creation-order + 25 duplicate-declaration
— all trace to Annex B §B.3.3 (block-level function declarations in eval
contexts) and §B.3.5 (VariableStatements in eval). Existing sloppy-mode
hoisting handles global and function scopes; eval-scope needs the same
treatment. NOT an architectural problem.

#### B. test262 runner `_FIXTURE.js` path resolver — ~91 tests

**Impact**: `language/module-code` 61.9% → est. 80%+
**File**: `test262-runner.py`

91 of 119 module-code failures are `SyntaxError: Cannot find module
'./xxx_FIXTURE.js'`. The runner's module-path resolver doesn't handle
fixture imports. One hour of work. NOT an interpreter bug.

### Architectural track (multi-PR; see architecture-redesign-2026-04-17-probes.md)

Redesign targeting CP-1 (proxy access protocol) and CP-2 (ArrayData
representation). Staged:

- ~~**Stage A — PropertyBag extraction.**~~ ✅ DONE (2026-04-17, PR #49).
  Pure refactor landed in 3 commits: core consolidation (b00a76d),
  `PropertyBag::new` custom constructor (3ef1192), `MapData::new` /
  `SetData::new` custom constructors (29f6164). 0 test262 delta, 884/884
  unit tests, CodeRabbit surfaced 4 pre-existing bugs (tracked below, not
  regressions).
- **Stage B.1 — `[[Set]]` dispatcher.** ~22 Proxy tests.
- **Stage B.2 — `[[GetOwnProperty]]` + `[[DefineOwnProperty]]`.** ~35–45
  Proxy tests.
- **Stage C — ArrayData.bag.** ~700+ Array tests; unlocks Issue #1
  (descriptor visibility). Ship BEFORE Stage B.3 (shared read site).
- **Stage B.3 — `[[HasProperty]]` dispatcher.** ~15 Proxy tests.
- **Stage D — Realm hermeticity.** 0 tests; ship when convenient.

Independent of Stage B (parallel PRs):
- `construct` NewTarget threading (~12 Proxy).
- `revocable` `typeof` post-revoke (~8 Proxy).

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

#### 2. Iterator close on abrupt completion

**Impact**: ~20-30 tests across `language/statements/for-of`
**Files**: `interpreter/runtime/exec_stmt.mbt`

For-of body errors (`body-dstr-assign-error`, `body-put-error`) show `IteratorClose` not being called when the body throws. The spec requires calling `iterator.return()` when for-of exits early (break, throw, return).

#### 3. Mapped arguments object

**Impact**: 3+ for-of tests + sloppy-mode function tests broadly
**Files**: `interpreter/runtime/construct.mbt`

`make_arguments_object` creates a plain copy, not a spec-compliant mapped arguments object where mutations to `arguments[i]` reflect in named parameters and vice versa. Known issue #11 from PR #45.

### Medium effort (multi-session)

#### 4. Proxy internal operation forwarding (partially done)

**Impact**: Subset of remaining 170 Proxy failures
**Files**: `interpreter/runtime/property.mbt`, `interpreter/runtime/eval_expr.mbt`, `interpreter/runtime/exec_stmt.mbt`

Remaining deferred items from Phase 15 (3 of 6 now done):
- ~~`Object.getPrototypeOf` doesn't invoke the trap~~ ✅ Fixed 2026-04-16
- `for-in` doesn't invoke `ownKeys` trap (delegates to target directly)
- `instanceof` doesn't invoke `getPrototypeOf` trap for prototype chain walk
- `create_list_from_array_like` bypasses Proxy traps (reads `.properties` directly)
- `Reflect.construct` rewires newTarget prototype after construction instead of before
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

#### 14. User-function property insertion order: `prototype, name, length` → `prototype, length, name`

**Impact**: For functions declared in JavaScript (`function f() {}`), `Reflect.ownKeys(f)` / `Object.getOwnPropertyNames(f)` currently reports `["prototype", "name", "length", ...]`. The spec order is `["prototype", "length", "name", ...]` (OrdinaryFunctionCreate runs MakeConstructor → SetFunctionLength → SetFunctionName). Likely affects a handful of test262 tests under `built-ins/Function`, `language/statements/function`, and similar that enumerate own keys.
**File**: `interpreter/runtime/factories.mbt` — `make_func` and `make_func_ext`, in the `properties: { ... }` literal.

Both `make_func` and `make_func_ext` construct the properties map as:
```moonbit
properties: {
  "prototype": proto,
  "name": String_(func_name),
  "length": Number(...),
}
```
Swap `"name"` and `"length"` entries (and the matching `descriptors` map). Surfaced 2026-04-18 during PR #51 insertion-order review — the fix for built-in functions (`build_func_object`) addressed only the `make_*_func` path. This is the user-function counterpart.

**Why not bundled with #51**: PR #51 scope was the `make_*_func` consolidation. Touching `make_func`/`make_func_ext` is a separate behavior-preserving-intent change with potential test262 delta. Keep as its own small PR so any test262 movement is attributable.

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

### 15. Register `InternalError` constructor

**Impact**: `@errors.InternalError` routes through `make_error_value_with_env`, but no `InternalError` constructor is registered in the environment, so `e.get("InternalError")` returns `Null` and the prototype chain never links — every engine-raised InternalError ends up with `proto: Null`. Currently masked by the fallback in `errors.mbt:49` that re-attaches `name` as an own property when proto resolution fails. Remove the special case once `InternalError` is registered alongside `TypeError`/`RangeError`/etc.
**File**: `interpreter/stdlib/builtins_error.mbt` (constructor table), `interpreter/runtime/errors.mbt:49` (fallback to retire)

Surfaced in PR #52/#53 review comment.

### 16. Bound-function property insertion order: `name, length` → `length, name`

**Impact**: `Function.prototype.bind` constructs its result with `bprops["name"]` before `bprops["length"]`, so `Reflect.ownKeys(f.bind(x))` reports `["name", "length", ...]`. Spec order is `[..., "length", "name", ...]` (SetFunctionLength runs before SetFunctionName).
**File**: `interpreter/stdlib/builtins_function.mbt:177-184`

Swap the two `bprops[...] = ...` lines and reverse the `descriptors` map to `{ "length": nf_desc, "name": nf_desc }`. Same class of bug as #14 (user functions) and `build_func_object` (fixed in #51); the bind path was missed because it builds the object inline.

### 17. `Reflect.set` stringifies Symbol keys

**Impact**: `Reflect.set(obj, sym, value)` coerces `sym` via `args[1].to_string()`, dropping the Symbol and hitting a stringified key like `"Symbol(foo)"`. Symbol-keyed sets silently land on the wrong slot.
**File**: `interpreter/stdlib/builtins_reflect.mbt:727-761`

Preserve the raw `args[1]` value (bind once to `let key = args[1]`); pre-check lookups against `data.bag.symbol_descriptors` / `data.bag.symbol_properties` when `key is Symbol`, else against the string variants; pass the original key into `interp.set_property` so computed-property dispatch handles Symbol routing.

### 18. `Reflect.get` skips plain data reads on non-Object targets

**Impact**: `try_get_with_receiver` only matches `Object(data)`. For non-Object targets (Array, Map, Set, Promise) the helper returns `None`, and when `receiver != target` the code returns `Undefined` without ever reading the property. Receiver should only gate *accessor* fallback, not data reads.
**File**: `interpreter/stdlib/builtins_reflect.mbt:428-502`

After the prototype walk, when `try_get_with_receiver` hasn't yielded a value, fall through to `interp.get_computed_property(target, key, loc)` (Symbol) or `interp.get_property(target, key_str, loc)` (string) unconditionally for data lookups; reserve the `Undefined` short-circuit for the accessor path.

### 19. `Reflect.has` rejects Map/Set/Promise and other object variants

**Impact**: `Reflect.has(target, key)` currently matches only `Object(_) | Array(_) | Proxy(_)`, raising `TypeError` for `Map`, `Set`, `Promise`, and any other object-like variant. `Reflect.has(new Map(), "size")` throws where it should return `true`.
**File**: `interpreter/stdlib/builtins_reflect.mbt:634-640`

Add `Map(_) | Set(_) | Promise(_)` (and any other object variants) to the non-Proxy arm that calls `interp.has_property`, or collapse the object-like variants into a single arm.

### 20. `Number.prototype.toString` (lookup-path): `length` and `undefined` radix

**Impact**: The `toString` method registered via the `match prop` lookup path in `builtins_number.mbt:748-752` declares `length=0` (spec: 1) and eagerly calls `to_number(args[0])` — coercing an explicit `undefined` radix to `NaN`, then `to_int() = 0`, which triggers `RangeError`. Spec §21.1.3.6 step 2: "If radix is undefined, let radixMV be 10."
**File**: `interpreter/stdlib/builtins_number.mbt:749`

Change `length=0` → `length=1`. Gate radix coercion on `args.length() > 0 && !(args[0] is Undefined)`; otherwise default to 10. (The prototype-level `toString` at the top of the file already uses `length=1` — this is a second registration that drifted.)

### 21. Timer/microtask builtins: `length` should be 1

**Impact**: `queueMicrotask`, `setTimeout`, `clearTimeout`, `setInterval`, `clearInterval` all declare `length=0`. Per WHATWG these take at least one argument; `.length` should be 1. Visible via `setTimeout.length === 1` tests.
**File**: `interpreter/stdlib/builtins_promise.mbt:1395, 1472, 1521, 1542, 1589`

Change the `length=0` argument to `length=1` in each `make_interp_method_func(name=..., length=0, ...)` call.

### 22. `$262` one-argument helpers: restore explicit `length=1`

**Impact**: `evalScript`, `detachArrayBuffer`, `createRealm`'s `evalScript`, and other one-arg `$262` helpers are created via `make_native_func(name=..., fn(...))`, which defaults `length` to 0. `$262.evalScript.length === 1` tests fail.
**File**: `interpreter/stdlib/builtins.mbt:2056, 2076, 2188, 2204` (and realm-variant at 2056-2094)

Add `length=1` to each one-arg helper's `make_native_func` / `make_interp_method_func` call.

### 23. (Nitpick) Non-constructable `InterpreterCallable` for static builtins

**Impact**: `make_interp_static_func` uses `InterpreterCallable`, which is constructible — so `new Reflect.ownKeys({})` etc. don't throw `TypeError` as the spec requires for static built-ins.
**File**: `interpreter/runtime/factories.mbt:277-289`

Two options: (a) add a `NonConstructableInterpreterCallable(name, func)` variant and update the call-site match arms (construction dispatch, `to_string`, etc.); (b) extend `InterpreterCallable` with a `constructible: Bool` flag and check it at the `new` site. Either way update `make_interp_static_func` to produce a non-constructable variant and audit existing `make_method_func`-based static methods (e.g. `Object.preventExtensions`, `Object.keys`) for the same class of bug.

### 24. `Error.isError` uses a hardcoded class-name allowlist (structural)

**Impact**: `Error.isError` in `interpreter/stdlib/builtins.mbt:737` checks `data.class_name` against a literal OR chain of error type names ("Error", "TypeError", "SyntaxError", ..., "AggregateError", "InternalError"). Every new native error requires updating two places in sync — the constructor registration AND the allowlist. PR #59 review caught this: adding `InternalError` as a constructor left `Error.isError(new InternalError())` returning `false` until the allowlist was patched.
**File**: `interpreter/stdlib/builtins.mbt:737-758`

The proper fix is to maintain a registry: at each `register_error_ctor` call site, record the class name in a set (e.g., `error_class_names : Set[String]`) on the environment or a module-level ref. `Error.isError` then checks `error_class_names.contains(data.class_name)`. New error types (SuppressedError from ES2024, future adds) become automatically recognized.

**Why not today**: The refactor crosses file boundaries (registry needs to be accessible from `register_error_ctor` in `builtins_error.mbt` and `Error.isError` in `builtins.mbt`) and touches an intrinsic's implementation. Tracked as a follow-up because the allowlist will keep drifting otherwise. Surfaced 2026-04-17 during PR #59 review.
