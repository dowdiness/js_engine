# Agent Task Queue

Tasks are ordered by effort/impact. Each is self-contained enough to complete in one session.
Completed tasks should be struck through and dated.

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

**Action**: In `test262-runner.py`, remove `"regexp-dotall"` from `SKIP_FEATURES`.
Run `python3 test262-runner.py --filter "built-ins/RegExp" --summary` to confirm pass rate improves.

---

### Task 2 — Add `Promise.withResolvers()`

**Spec**: https://tc39.es/ecma262/#sec-promise.withresolvers
**Feature flag**: `"promise-with-resolvers"` in `SKIP_FEATURES`
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

After implementing: remove `"promise-with-resolvers"` from `SKIP_FEATURES` and run
`python3 test262-runner.py --filter "built-ins/Promise" --summary`.

---

### Task 3 — Add `Promise.try()`

**Spec**: https://tc39.es/ecma262/#sec-promise.try
**Feature flag**: `"promise-try"` in `SKIP_FEATURES`
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

**Feature flag**: `"async-iteration"` in `SKIP_FEATURES`
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
10. **Second helper for class-ctor arms** (surfaced 2026-04-20 by
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
  - Three suspicious `try { … } catch { _ => () }` sites in
    `property.mbt` (TypedArray ops at lines 827, 1307, 2085): current
    code swallows `to_number(value)` TypeErrors, which the
    `typedArr[0] = Symbol()` case requires to propagate. Separate bug,
    not a Stage B.2 regression.
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

Independent of Stage B (parallel PRs):
- `construct` NewTarget threading (~12 Proxy).
- `revocable` `typeof` post-revoke (~8 Proxy).

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

#### 26. Consolidate Break/Continue → SyntaxError invariant across runtime

**Impact**: 0 test262 delta (pure refactor, zero behavior change). Medium-ROI tech-debt cleanup surfaced by PR #68 (#A.9) reviewer.

**Problem**: the invariant "Break/Continue signals escaping a function boundary raise `SyntaxError: break/continue statement outside of loop`" is inlined at ~8 sites with identical bodies but distinct callers:

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

**Fix**: Added `bag.descriptors` checks at own-property and every prototype step, mirroring `lookup_symbol_property_chain`. Signature changed to accept `obj_val : Value` as first param (receiver for getter invocation) and `raise Error`. When a getter is found and an interpreter is available the getter is invoked with `obj_val` as receiver; without an interpreter `Some(Undefined)` signals presence. All 6 callers updated; `has_property` callers wrap in `try/catch` since that function does not raise. Stale comment removed from `has_bag_or_builtin_proto_key` doc.

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

**Files**: `lexer/lexer.mbt` lines 12–48
**Impact**: ~−10 LoC, pure refactor, zero behavior change, no public API change
**Result**: Merged `parse_binary` and `parse_octal` into `parse_radix_literal(s, base)`. Three call sites updated: `parse_radix_literal(bin_str, 2.0)`, `parse_radix_literal(oct_str, 8.0)` ×2. `parse_hex` kept separate (three-branch digit extraction is fundamentally different).
**Effort**: 1 session

`parse_hex`, `parse_binary`, and `parse_octal` (lines 12–48) are structurally near-identical: each iterates a `String` as a `Char` array and accumulates a `Double` via weighted positional arithmetic. `parse_binary` and `parse_octal` are identical except for the base multiplier (`2.0` vs `8.0`).

**Proposed consolidation**:

1. Merge `parse_binary` and `parse_octal` into a single `fn parse_radix_literal(s: String, base: Double) -> Double`. Digit extraction (`c.to_int() - 48`) is identical for both.

2. `parse_hex` may be merged as a special case of the same function, or kept separate — its three-branch digit mapping for `0–9` / `a–f` / `A–F` is structurally different from the simple `c - '0'` of the other two.

**Call sites** (all pass clean digit-only strings; no separators):
- `parse_hex`: called from `parse_unicode_escape` (line ~235), `scan_template_string` (line ~307), and the main hex-literal path in `tokenize` (~line 949) — 3 sites
- `parse_binary`: 1 site in `tokenize` (binary literal path)
- `parse_octal`: 1 site in `tokenize` (octal literal path)

**Safety**: all three are private functions. The lexer's 60+ tests in `lexer_test.mbt` cover all three numeric literal formats and must pass after the change.
