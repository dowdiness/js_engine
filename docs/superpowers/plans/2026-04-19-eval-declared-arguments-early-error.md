# §19.2.1.3 eval-declared-arguments early error (#A.6) — Implementation Plan

**Date:** 2026-04-19
**Status:** Design — awaiting Codex design-validation before implementation
**Spec anchor:** ECMA-262 §19.2.1.3 *EvalDeclarationInstantiation* (`esid: sec-evaldeclarationinstantiation` in test262)

---

## Goal

Raise `SyntaxError` at call time when a direct `eval(...)` inside a non-arrow function's parameter default would declare an `arguments` binding. Flip 106 test262 fails to passes, zero regressions, no env-model change.

## Why (revised scope)

Initial reading was that body-level `var/let/function arguments` decls become visible too late for the step 5.d walk, and we'd need a 3-env lift (param / varEnv / lexEnv) to fix it. **That read was wrong.** Empirical baseline of all four test shapes:

| Shape | Filter | Body contents | Pass | Fail |
|---|---|---|---|---|
| `cntns-arguments-*` | `cntns-arguments` | body decls `arguments` (3 kinds × 22) | 30 | 66 |
| `no-pre-existing-arguments-bindings-*` | `no-pre-existing` | **empty body** | 10 | 22 |
| `preceding-parameter-is-named-arguments-*` | `preceding-parameter` | `(arguments, p = eval(...))` | ~22 | ~10 |
| `following-parameter-is-named-arguments-*` | `following-parameter` | `(p = eval(...), arguments)` | ~24 | ~8 |
| **Total** | `arguments` in `eval-code/direct/` | | **86** | **106** |

All passing cases are **arrow** variants (arrow functions have no `arguments` binding; eval's `var arguments` can't collide). All failing cases are **non-arrow** — `function`, `function*`, `async function`, `async function*`, named/nameless expressions, methods, generator methods.

Key observation: the **no-pre-existing** shape with an **empty body** also fails. There is no body decl to be visible, yet SyntaxError is required. This rules out the body-visibility hypothesis. The real trigger is a single invariant:

> **A direct eval inside a non-arrow parameter default that declares `arguments` is always a SyntaxError.**

The reason: a non-arrow function's parameter scope always has `arguments` bound — either from the arguments-object install (§10.2.11 step 21) or from an explicit `arguments` parameter. Eval's `var arguments` would attempt to shadow that binding in a way the spec disallows for non-arrows.

## Probes (already landed; confirm via `moon test`)

Three failing probes in `interpreter/interpreter_test.mbt` (lines 9684–9783) — one per body-decl shape. All three fail with the same signature (no error raised), serving as a regression guard for the three cohorts post-fix.

Additional probe to add alongside the fix: `function f(p = eval("var arguments")) {} f();` — the no-pre-existing empty-body case, which proves body shape is irrelevant.

---

## Design

### Core mechanism

Add a scoped "in parameter-default evaluation" signal, visible to `perform_eval`. When a direct eval, while that signal is active and the enclosing function is non-arrow, encounters `arguments` in its var names, raise SyntaxError before running the declaration instantiation.

**Why a scoped signal and not an AST scan:**
- An AST scan of each param default for `eval("…arguments…")` literal strings would work for test262's generated shapes (all use string-literal eval), but would silently miss dynamic eval (`eval(name_of_decl)`) that future tests or real code could exercise. The runtime signal handles both cases uniformly.
- An AST scan also can't distinguish a live eval call from code inside an inner function literal whose defaults are never evaluated. A runtime signal is naturally flow-sensitive.

### Where the signal lives

Two candidates, both one mutable `Bool`:

1. **On `Interpreter`** — a single `mut in_nonarrow_param_default_eval : Bool` field on the interpreter struct. Caller-side (`bind_ext_params_and_exec_body`) saves the previous value, sets true around each default eval, restores. Nested function calls (which re-enter `bind_ext_params_and_exec_body`) correctly nest the save/restore.
2. **On `Environment`** — add `mut arguments_guarded : Bool` to `param_env`. `perform_eval` walks caller_env to find the nearest var scope and reads the flag.

**Pick option 1.** It avoids mutating `Environment` (our single most-touched struct) for a narrow concern, and the save/restore discipline is easier to audit locally in `call.mbt` than a field on a struct that's created and destroyed along multiple code paths.

### Where to set / clear the signal

The signal must be active **only** while the *current* function frame is evaluating one of its own parameter default expressions. Any nested function invocation (IIFE in a default, arrow called from a default, recursive call) must start with signal=false, so its own body does not inherit the outer frame's default-eval-in-progress state. Without this reset, a direct eval inside an IIFE body would falsely trigger when the IIFE is invoked from within another function's default.

**Save / reset / scope pattern** inside `bind_ext_params_and_exec_body` (`interpreter/runtime/call.mbt:176`):

1. **At helper entry** (before the param loop): save `saved = self.in_nonarrow_param_default_eval`; unconditionally set `self.in_nonarrow_param_default_eval = false`. This is the "reset on every function entry" step — it ensures nested calls do not inherit outer state.
2. **Around each default expression** (the `match param.default_val { Some(default_expr) => { ... } }` branch, line ~196): if `!is_arrow`, set signal to `true` immediately before `self.eval_expr(func_ctx, default_expr, param_env)`; set back to `false` immediately after the eval returns (regardless of which default it was). For arrow, do not touch the signal within the loop.
3. **At helper exit** (normal or abnormal completion of body execution): restore `self.in_nonarrow_param_default_eval = saved`. MoonBit does not have try/finally; the restore must run on both the normal and raise paths. Idiomatic approach: inline the restore at every `raise` site reachable from the helper, OR refactor the body into an inner function whose `raise Error` is caught at the outer level just to run the restore. For clarity, pick whichever produces fewer duplicated lines — document which was chosen at implementation time.

Pseudocode:
```
fn bind_ext_params_and_exec_body(..., is_arrow: Bool) {
  let saved = self.in_nonarrow_param_default_eval
  self.in_nonarrow_param_default_eval = false   // reset on entry
  // ... param loop ...
  for each param with default:
    if !is_arrow { self.in_nonarrow_param_default_eval = true }
    let v = self.eval_expr(..., default_expr, param_env)
    self.in_nonarrow_param_default_eval = false
    // ... bind ...
  // ... rest, split, hoist, body exec ...
  self.in_nonarrow_param_default_eval = saved   // restore on exit
}
```

This design correctly handles every nesting case:
- IIFE or nested non-arrow called in a default: IIFE's own entry resets signal to false; its body runs with signal=false; restores to true (the default-eval frame's state) on return.
- Arrow called in a default: arrow's entry also resets; arrow body runs with signal=false. Consistent with the observation that arrows do not trigger the gate for evals in their own body.
- Recursive invocation via default: each frame's reset is independent.
- Arrow frames themselves: reset at entry is unconditional; the `if !is_arrow` guard only affects the *setting* inside the default loop, not the reset. Arrow frames pay a redundant-but-harmless reset.

**Non-arrow gating.** The helper is shared by `UserFuncExt` and `ArrowFuncExt` callers (per #A.8). The `is_arrow : Bool` must be threaded in as a parameter so the helper knows whether to set true around each default. Options:

- (a) Thread `is_arrow : Bool` parameter into `bind_ext_params_and_exec_body`. Two call sites to update (`call.mbt` UserFuncExt branch + ArrowFuncExt branch).
- (b) Let the callers own the signal. Caller wraps `bind_ext_params_and_exec_body` in `set/restore`. Requires exposing the flag-setting surface publicly.
- (c) Move only the default-eval loop out of `bind_ext_params_and_exec_body` into a variant-specific step. Larger refactor, rolls back part of #A.8.

**Pick (a).** One extra bool parameter, changes self-documenting, matches how `data.strict` already flows.

### `perform_eval` check

In `perform_eval` (`interpreter/runtime/call.mbt:294`), add one block just after `let var_names = collect_eval_var_names(stmts)` (line 343):

- If `direct && self.in_nonarrow_param_default_eval && var_names.contains("arguments")`, raise `SyntaxError("Identifier 'arguments' has already been declared")`.

This runs before the existing step 5.d walk and before hoisting. One new branch, ~5 lines.

### What this change does NOT do

- **No change to env model.** 2-env (param_env + body_env) stays as-is.
- **No change to step 5.d walk.** The existing walk remains correct for the let/const-outside-eval cohort it already handles.
- **No change to hoisting.** Body decls still materialize in body_env after defaults evaluate.
- **Does not resolve item 7's 3-env divergence probe** (`['b','b']` vs `['e','b']`). That remains a separate, independently-scoped follow-up.

---

## Failure-mode analysis

| Scenario | Our fix fires? | Should it? | Rationale |
|---|---|---|---|
| `function f(p = eval("var arguments")) {}` | yes | yes | canonical no-pre-existing non-arrow case |
| `function f(p = eval("var arguments")) { var arguments; }` | yes | yes | cntns-arguments var-bind |
| `function f(p = eval("var arguments")) { let arguments; }` | yes | yes | cntns-arguments lex-bind |
| `function f(p = eval("var arguments")) { function arguments(){} }` | yes | yes | cntns-arguments func-decl |
| `function f(arguments, p = eval("var arguments")) {}` | yes | yes | preceding-param case |
| `function f(p = eval("var arguments"), arguments) {}` | yes | yes | following-param case |
| `const f = (p = eval("var arguments")) => {}` | no | no | arrow, signal never set |
| `function f(p = eval("var x")) { var arguments; }` | no | no | eval doesn't declare `arguments` |
| `function f() { eval("var arguments"); }` | no | no | eval in body, not default |
| `function f(p = 1) { eval("var arguments"); }` | no | no | eval in body, not default |
| `function f(p = (() => eval("var arguments"))()) {}` | no | no | inner arrow body runs with signal=false (reset at arrow entry). Eval's var "arguments" goes to the arrow's inherited varEnv (which is f's param_env), but the signal-based gate is what produces SyntaxError, and arrow bodies are spec-exempt from the gate. No test262 coverage of this shape; this is the behavior-preserving choice. |
| `function f(p = (function() { eval("var arguments"); return 1; })()) {}` | no | no | IIFE body runs with signal=false (reset at IIFE entry). IIFE's eval has varEnv = IIFE body_env, no arguments collision. Matches spec step 5.d walk, which exits before reaching any env with `arguments`. |

The last two rows were the motivation for the reset-on-entry pattern in the signal design. Earlier I considered a simpler save+set pattern; that would have falsely fired on the IIFE row above. It does NOT affect *indirect* eval (`(0, eval)("var arguments")`), which doesn't use the caller's var scope — our check is gated on `direct`.

## Under-/over-approximation gaps

- **Dynamic eval with runtime string:** `function f(p = eval(`var ${name}`)) {}` where `name = "arguments"`. Our fix fires because the runtime signal catches the actual eval call with `arguments` in its var_names — the var_names come from parsing the eval-input at runtime, which is what spec does. **Covered.**
- **`new Function("var arguments")` in a param default:** Not a direct eval; spec doesn't require the same gate. **Correctly not fired.** No test262 coverage.
- **`eval("`${`${"var"} arguments`}`")`:** Parses as `var arguments`; the var_names list will contain `"arguments"`. Same as dynamic case. **Covered.**

## Tests to add (new regression guards in `interpreter_test.mbt`)

Alongside the three existing probes, add at least:

- **Empty-body non-arrow case:** `function f(p = eval("var arguments")) {} f();` → SyntaxError. Covers the no-pre-existing-arguments-bindings cohort.
- **Preceding-param case:** `function f(arguments, p = eval("var arguments")) {} f();` → SyntaxError. Covers the preceding-parameter cohort.
- **Following-param case:** `function f(p = eval("var arguments"), arguments) {} f();` → SyntaxError. Covers the following-parameter cohort.
- **Negative regression — arrow:** `const f = (p = eval("var arguments")) => { let arguments = "ok"; return arguments; }; f();` → returns `"ok"`, no error. Protects the 40 passing arrow tests.
- **Negative regression — body eval:** `function f() { eval("var arguments"); return arguments; } f();` → returns arguments object, no error. Confirms signal is scoped to param defaults only.
- **Negative regression — non-`arguments` eval var:** `function f(p = eval("var x = 1")) { var x; return x; } f();` → returns 1, no error. Confirms the check is `arguments`-specific.
- **Negative regression — indirect eval:** `function f(p = (0, eval)("var arguments")) {} f();` → currently passes (per spec, indirect eval doesn't use caller var scope). Confirms signal is gated on `direct`.
- **Negative regression — nested IIFE in default:** `function f(p = (function() { eval("var arguments"); return 1; })()) {} f();` → no error. The IIFE's entry resets the signal to false; its body's eval runs spec-normally and var-declares `arguments` into the IIFE's own body env. Protects against the signal-leakage bug identified in self-review.
- **Negative regression — nested arrow invocation in default:** `function f(p = (() => 1)()) { return p; } f();` → returns 1, no error. Baseline check that nested arrows in defaults don't somehow trigger the gate for unrelated reasons.

All seven go into the §19.2.1.3 test block following the existing probes (after line ~9783 currently).

## File map

| File | Action | Responsibility |
|---|---|---|
| `interpreter/runtime/interpreter.mbt` | Modify | Add `in_nonarrow_param_default_eval : Bool` field to Interpreter struct; initialize to `false`. |
| `interpreter/runtime/call.mbt` `bind_ext_params_and_exec_body` | Modify | Add `is_arrow : Bool` parameter; save/set/restore signal around each default eval when non-arrow. |
| `interpreter/runtime/call.mbt` UserFuncExt branch | Modify | Pass `is_arrow=false` to helper. |
| `interpreter/runtime/call.mbt` ArrowFuncExt branch | Modify | Pass `is_arrow=true` to helper. |
| `interpreter/runtime/call.mbt` `perform_eval` | Modify | Add the one-branch check after `collect_eval_var_names`. |
| `interpreter/interpreter_test.mbt` | Modify | Add the seven new regression tests. |
| `docs/agent-todo.md` | Modify | Mark #A.6 DONE on merge; update pass counts; confirm item 7 remains open and independent. |

Estimated net diff: ~80–120 lines (signal plumbing + tests + doc).

## Validation

1. `moon check` clean.
2. `moon test -p interpreter` — all existing §10.2.11 tests (`interpreter_test.mbt:9464–9682`) remain green. Three existing probes flip green. Seven new regression tests pass.
3. `moon build --target js --release`.
4. Filter baseline before and after:
   - `python3 test262-runner.py --filter "cntns-arguments"` — 30/96 → 96/96.
   - `python3 test262-runner.py --filter "no-pre-existing-arguments"` — 10/32 → 32/32.
   - `python3 test262-runner.py --filter "preceding-parameter-is-named-arguments"` — expected to flip from ~22/32 to 32/32.
   - `python3 test262-runner.py --filter "following-parameter-is-named-arguments"` — expected to flip from ~24/32 to 32/32.
   - `python3 test262-runner.py --filter "arguments"` (broad) — 86/192 → 192/192 for the arguments-related direct-eval cohort, with no other category moving.
5. `moon info && moon fmt` — verify `.mbti` unchanged except for Interpreter struct field.
6. `git diff --stat` — expect changes limited to the file-map above.

## Interaction with item 7 (3-env divergence)

Item 7's runtime-divergence probe (`f(a = eval("var x = 'e'"), b = () => x) { var x = 'b'; return [b(), x]; }` → spec says `['b','b']`, ours `['e','b']`) is orthogonal:

- This PR does **not** change the runtime env model, so the probe stays `['e','b']` — unchanged, no regression.
- A future 3-env lift PR could stand alone, scoped to its own ~few test-count gains around capture-divergence shapes, without being entangled with the early-error work.

This keeps #A.6 small, auditable, and independently reviewable.

## Open questions (Codex unavailable; resolved by self-review)

1. **Signal placement** — is the `Interpreter` struct the right owner, or would an explicit parameter threaded through `eval_expr → perform_eval` be cleaner? **Resolved:** `Interpreter` struct. Parameter threading would touch every `eval_expr` call site for a narrow concern; the save/reset/restore discipline is localized to `bind_ext_params_and_exec_body` and auditable in one place.

2. **Nested invocation in defaults** — originally I read the spec as "direct eval during defaults-eval-phase is gated regardless of which function literal hosts the eval call," implying signal should stay live through inner invocations. **Resolved during self-review: wrong read.** The spec's mechanism is per-function-frame: a direct eval is subject to the gate based on *the current function's* context at eval call time. An inner function (arrow or non-arrow) invoked in a default gets its own execution context with its own var/lex env; eval inside it is bound to *that* function's env, not the outer default-eval context. The reset-on-entry pattern in the signal design produces this behavior correctly. Without this correction, the design would false-fire on `function f(p = (function(){ eval("var arguments"); return 1; })()) {}`.

3. **Strict mode** — in strict mode, `var arguments` in eval body is already a parse-time SyntaxError from `validate_block_early_errors` at `call.mbt:317`, which runs before `collect_eval_var_names` at line 343. **Resolved:** no double-report risk. The new check is effectively unreachable in strict evals because parsing fails earlier. Still gate on `direct &&` as planned; no need to also gate on `!strict`.

4. **Generator/async interactions** — 12 of the 66 `cntns-arguments` fails are `gen-func-expr-*`, plus 12 async-gen. **Resolved (tentative, verify at implementation):** `bind_ext_params_and_exec_body` is shared across `function`, `function*`, `async function`, `async function*` via `UserFuncExt` — all take the is_arrow=false path. No generator-specific handling expected. Will confirm by running the generator-filter subset before merging.

5. **`collect_eval_var_names` and function declarations** (surfaced during self-review) — does our current `collect_eval_var_names` include BoundNames from top-level FunctionDeclarations in eval input? Spec says yes (function decls hoist to varEnv). Test262 doesn't probe this for the `arguments` check (all eval inputs are `var arguments` or `var arguments = 'param'`), so even if our walker missed function-decl names here, the 106 target tests still flip green. Worth verifying and adding a dedicated probe if the walker is incomplete. Not blocking.

---

## Not in scope

- 3-env env model lift (item 7). Tracked separately.
- Catch-env transparency for step 5.d (tracked in agent-todo #A.7).
- Param TDZ pre-declaration, arguments-in-paramNames install suppression, super() double-init (item 7 remaining bullets).
- eval-code/indirect cohort fixes.
- module-code self-import/cycle handling.
