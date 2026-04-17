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

#### 6. Consolidate `make_*_func` factory variants

**Impact**: ~150 LoC of near-duplicate function-object construction in `interpreter/runtime/factories.mbt` — `make_native_func`, `make_native_func_with_length`, `make_static_func`, `make_static_func_with_length`, `make_method_func`, `make_interp_method_func`, `make_interp_static_func_with_length` all share the same ~25 LoC body (name/length descriptor, function-proto, `class_name: "Function"`) and differ only in the `Callable` variant and whether length is explicit. Extract a private `build_func_object(name, length, callable) -> Value` helper and reduce each public wrapper to a one-liner. Do this when no other work is in flight near `factories.mbt`. Surfaced by Stage A simplify review (2026-04-17).
