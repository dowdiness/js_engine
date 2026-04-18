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
6. **§19.2.1.3 step 5.d early-error for `cntns-arguments` cohort
   (~66 tests).** Shapes: `*-cntns-arguments-func-decl-*`,
   `*-cntns-arguments-var-bind-*`, `*-cntns-arguments-lex-bind-*`. Tests
   assert a SyntaxError when `eval("var arguments")` in a default collides
   with a body-level `function arguments() {}` / `var arguments =` /
   `let arguments =` declaration. Implementation requires a walk of
   body-level function / lex declarations that compares against the
   param env's eval-introduced names. The §10.2.11 split shipped in #66
   is a prerequisite (eval's `var` now lands in param_env, body decls
   in body_env — the two envs are what the early-error check compares).
   Will likely need to lift the 2-env collapse to a 3-env model during
   the same PR; see item 7.
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
   - **`arguments` in parameterNames.** `function f(arguments = 1)`
     should suppress the arguments-object install per step 17.
     Currently collides — the arguments-object install throws on
     re-def of `arguments`. Gate the install on
     `!parameter_names.contains("arguments")`.
   - **`super()` double-init check.** `Environment::initialize_in_chain`
     overwrites unconditionally; spec `BindThisValue` (§9.1.1.3.1) throws
     on re-init. Add an initialized-guard in `initialize_in_chain` at
     the binding-write site, or route super() through a dedicated
     `initialize_this_once` helper.
8. **Refactor: extract shared Ext-callable param/body helper.** Codex
   nitpick on PR #66. `call.mbt` UserFuncExt and ArrowFuncExt branches
   duplicate ~100 lines of parameter binding, rest handling, default
   evaluation, destructuring, body_env split gating, hoist_declarations
   threading, and the exec_stmts-to-completion match. Extract to
   `bind_ext_params_and_body` with small caller-specific differences
   (UserFuncExt installs `this` / `arguments` / self-name wrapper; arrow
   skips them). Pure refactor, zero behavior change — kept out of #66
   per the behavior-preserving charter. Code-quality improvement only,
   not a test-count lever.

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

#### ~~14. User-function property insertion order: `prototype, name, length` → `prototype, length, name`~~ — DONE (2026-04-17, PR #55)

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

### 25. `lookup_property_chain` ignores `bag.descriptors` (accessor + non-data blind spot)

**Impact**: `lookup_property_chain` walks `bag.properties` on the target and every prototype step but never consults `bag.descriptors`. Any property that lives only in the descriptor map — accessors (getter/setter), or data descriptors registered without a mirror in `bag.properties` — is invisible to the chain walk. This makes all six callers subtly spec-wrong for accessor-only properties.
**File**: `interpreter/runtime/conversions.mbt:156-200` (definition); callers at lines 113, 142 (presence checks) and 307, 336, 613, 642 (value retrieval).

**Two failure shapes**:

1. *Presence checks* (lines 113, 142) — used by the free `has_property` → `Interpreter::has_property` for Object/Array. A getter-only property on `Object.prototype` returns `false` from `"x" in obj`, violating ES §7.3.11 step 3 (`OrdinaryHasProperty` must inspect both data and accessor descriptors). PR #60 worked around this for Map/Set/Promise by duplicating the prototype-walk in `Interpreter::has_bag_or_builtin_proto` (explicitly checks both `properties` and `descriptors` at each step). That helper is the reference shape for the fix — backport it to `lookup_property_chain` and drop the duplication.

2. *Value retrieval* (lines 307, 336, 613, 642) — `to_primitive` / `to_string` / `to_number` look up `toString` / `valueOf`. If either is defined as an accessor on a user-defined prototype, the lookup misses, fallback kicks in, and coercion uses the default `Object.prototype.toString` instead of the user getter's return value. Observable when `({ get toString() { return () => "x"; } }).toString()` returns `"[object Object]"` instead of `"x"`. Fix requires: on a descriptor hit with `getter`, invoke the getter with the current value as receiver and return its result; fall back to `properties` only when neither descriptor nor direct property exists.

**Why not today**: touches coercion fast paths; each caller has distinct receiver and error-handling semantics. A survey pass is needed before unifying — some callers want Some/None (presence), others want the resolved value-or-callable. Likely unlocks a scattered handful of accessor-related test262 tests. Surfaced 2026-04-18 during PR #60 cleanup — the agent bypassed it cleanly within its scope, which is how it got flagged explicitly rather than silently propagating.
