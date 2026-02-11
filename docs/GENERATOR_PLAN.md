# Generator Implementation Plan (Corrected Phase Sequence)

## Implementation Status: COMPLETE

All phases (0-8) are implemented. 746 unit tests are currently passing; see
[ROADMAP.md](../ROADMAP.md) for the latest Test262 totals. GeneratorPrototype:
26/58 (44.8%).

### Actual Architecture vs Plan

The plan below specified a **frame-stack/step-engine** model with explicit
`GenFrame`, `Frame` variants, and a trampoline loop. The actual implementation
used a simpler **statement replay** model:

- Generator body is re-executed from the top on each `.next()` call
- Past statements are fast-forwarded via a saved program counter (`pc`)
- The existing direct-style interpreter is reused entirely (no separate step engine)
- Control flow uses MoonBit suberrors (`YieldSignal`, `GeneratorReturnSignal`)
- `try/catch/finally` state tracked via `try_resume_phase` for correct resumption
- Loop environments saved in `loop_env_stack` for per-iteration `let` bindings

This approach traded replay overhead for dramatically simpler implementation,
avoiding the "frame variant explosion" risk identified in the plan below. The
original plan is preserved as-is for reference.

---

## Goal

Add ES6 generator support (`function*`, `yield`, `yield*`) to `js_engine` with
spec-correct runtime behavior while preserving existing direct-style evaluation
for non-generator code.

This plan replaces the prior sequence with stricter phase dependencies to avoid
semantic regressions.

---

## Design Constraints

1. Regular functions remain on the current interpreter path for performance.
2. Generator execution must preserve current control-flow semantics (`return`,
   `break`, `continue`, `throw`) used in `interpreter/interpreter.mbt`.
3. `generator.next/throw/return` must be spec-consistent, including `finally`
   behavior.
4. `yield` can appear in expression positions inside generator bodies, so
   evaluation strategy cannot assume subexpressions are always direct-evaluable.
5. Avoid unbounded recursion in resume paths; use trampoline/step-loop from the
   start rather than as a late optional refactor.
6. Generator instances must be real `Value::Object` (with `ObjectData` carrying
   an internal generator-kind payload) so they participate in property access,
   `Object.prototype.toString`, `in`, `hasOwnProperty`, etc.
7. `IteratorResult` objects returned by `next/throw/return` must be fresh
   `Value::Object` instances each call (two `next()` results must not be the
   same object).

---

## Runtime Model

Use an explicit generator execution state machine.

```moonbit
enum ResumeKind {
  Next(Value)
  Throw(Value)
  Return(Value)
}

enum Completion {
  Normal(Value)
  Return(Value)
  Throw(Value)
  Break(String?)
  Continue(String?)
}

enum GenState {
  SuspendedStart(GenFrame)
  Executing
  SuspendedYield(GenFrame)
  Completed
}

struct GeneratorObject {
  mut state : GenState
}
```

Generator instances are represented as `Value::Object(ObjectData)` where
`ObjectData` carries the `GeneratorObject` as an internal slot. This ensures
generators are real JS objects that support property access, prototype chain
lookups, and standard object operations.

### GenFrame — Continuation Representation

Since MoonBit has no first-class continuations, the generator must capture its
full execution state explicitly. `GenFrame` is the core data structure that
makes suspension and resumption possible without host-stack recursion.

```moonbit
enum Frame {
  EvalStmt(stmt: Stmt, pc: Int, env: Env, locals: Array[Value])
  EvalExpr(expr: Expr, pc: Int, env: Env, temps: Array[Value])
  FinallyFrame(body: Array[Stmt], pending: Completion?)
  LoopFrame(kind: LoopKind, label: String?, test: Expr?, update: Expr?, body: Stmt, pc: Int)
  TryCatchFrame(catch_param: String?, catch_body: Array[Stmt], finally_body: Array[Stmt]?)
}

struct GenFrame {
  stack : Array[Frame]
  env : Env
  this_value : Value
  strict : Bool
  handler_stack : Array[HandlerEntry]
  pending_resume : ResumeKind?
  pending_completion : Completion?
}
```

Key design decisions:

1. **Frame stack with per-node program counters (PC) and saved intermediates:**
   Every AST node type that can contain `yield` must have a resumable evaluation
   strategy. The `pc` field tracks "where to resume" within a node, and `temps`
   / `locals` hold partially-evaluated subexpression results.

2. **Explicit completion records:** The interpreter's current `Signal` type
   works via recursive host-stack unwinding. Inside the generator step engine,
   use `Completion` instead — an explicit value carried across frames, especially
   critical for `finally` blocks that can themselves `yield`.

3. **`pending_resume` field:** On resume, `.next(v)` / `.throw(e)` / `.return(v)`
   is stored here. The next step consumes it: `Next(v)` makes `yield` evaluate
   to `v`, `Throw(e)` injects a throw at the suspension point, `Return(v)`
   triggers an injected `Return` completion that must run active `finally` blocks.

4. **`pending_completion` field:** Used when entering `finally` — the original
   abrupt completion (return/throw/break) is saved here and restored after
   `finally` completes (unless `finally` itself produces an abrupt completion).

5. **Heap-allocated environments:** Block/loop iteration environments must be
   heap objects referenced by frames. Frames store the *current env pointer* at
   suspension rather than reconstructing it on resume. This is critical for
   `for (let ...)` + yield where each iteration has its own binding.

### State Transition Rules

```
SuspendedStart:
  .next(arg)   → ignore arg, start body execution
  .throw(e)    → complete generator, throw e to caller (no body runs)
  .return(v)   → complete generator, return {value: v, done: true} (no body runs)

Executing:
  .next/throw/return → throw TypeError (re-entrancy guard)

SuspendedYield:
  .next(v)     → resume, yield expression evaluates to v
  .throw(e)    → resume, inject throw at suspension point
  .return(v)   → inject Return completion, execute active finally blocks

Completed:
  .next()      → {value: undefined, done: true}
  .return(v)   → {value: v, done: true}
  .throw(e)    → throw e to caller
```

---

## Corrected Phase Sequence

## Phase 0 — Spec Baseline and Harness ✅

### Scope

1. Add generator-focused test file(s) under existing interpreter/js_engine tests.
2. Add helpers for asserting iterator records (`{ value, done }`).
3. Add TODO-marked pending tests for not-yet-implemented semantics.

### Required Tests (initially failing)

1. `function*` returns an object with `next`.
2. First `next(arg)` ignores `arg`.
3. Re-entrancy throws `TypeError`.
4. `return()` runs `finally`.
5. `yield*` forwards `throw/return`.
6. `.throw(e)` on `SuspendedStart` completes generator and throws without
   running body.
7. `.return(v)` on `SuspendedStart` returns `{value: v, done: true}` without
   running body.
8. `.throw(e)` on `Completed` throws `e` to caller.
9. `.return(v)` on `Completed` returns `{value: v, done: true}`.
10. Two `next()` results are not the same object.
11. Parameter initializer side effects do not run until first `.next()`.

### Checkpoint

Failing tests document target behavior before implementation.

---

## Phase 1 — AST and Parser Semantics ✅

### Scope

1. Add AST nodes:
   - `GeneratorDeclaration`
   - `GeneratorExpression`
   - `YieldExpression(argument?, delegate)`
2. Parse `function*` declarations/expressions.
3. Parse `yield` and `yield*` only when parser context allows it.
4. Implement parser context stack (not a single global bool) so nested function
   parsing restores correct `yield` legality.
5. Enforce `yield` operator precedence: very low, near assignment level.
6. Enforce no LineTerminator between `yield` and `*` — `yield\n*foo` must parse
   as `yield; *foo` (or a syntax error), not `yield* foo`.

### Required Tests

1. `yield` rejected in non-generator function bodies.
2. `yield` accepted in generator expression/decl bodies.
3. Nested regular function inside generator rejects `yield` unless it is also
   a generator.
4. `yield` inside arrow functions within generators is SyntaxError (arrows
   cannot be generators; `function* g(){ (() => yield 1) }` must fail).
5. `yield` in parameter default expressions is SyntaxError:
   - `function* g(a = yield 1) {}` → SyntaxError
   - `function* g({x = yield 1}) {}` → SyntaxError
6. `yield\n*expr` does not parse as `yield* expr` (LineTerminator restriction).
7. `yield` precedence: `yield a + b` parses as `yield (a + b)`, not
   `(yield a) + b`.

### Checkpoint

Parser/AST green, no runtime generator execution yet.

---

## Phase 2 — Generator Object Wiring (No Yield Semantics Yet) ✅

### Scope

1. Calling a generator function returns a `Value::Object` with internal
   `GeneratorObject` payload instead of executing body immediately.
2. Install methods: `next`, `throw`, `return` on `%GeneratorPrototype%`.
3. Set up prototype chain:
   - Generator function → `GeneratorFunction.prototype`
   - Generator instance → generator function's `.prototype` → `%GeneratorPrototype%`
     → `%IteratorPrototype%`
4. Add state transitions:
   - `SuspendedStart -> Executing -> SuspendedYield/Completed`
   - throw TypeError on resume when state is `Executing`.
5. Implement `@@iterator` so generator objects are self-iterable.
6. Generator functions are **not constructible**: `new (function*(){})` must
   throw `TypeError`.
7. Parameter initializer side effects must not run until first `.next()` starts
   execution.
8. Handle `.throw(e)` and `.return(v)` on `SuspendedStart`:
   - `.throw(e)` → transition to `Completed`, throw `e` to caller.
   - `.return(v)` → transition to `Completed`, return `{value: v, done: true}`.
9. Handle `.throw(e)` and `.return(v)` on `Completed`:
   - `.throw(e)` → throw `e` to caller.
   - `.return(v)` → return `{value: v, done: true}`.

### Required Tests

1. `g[Symbol.iterator]() === g`.
2. Re-entrant `next` throws `TypeError`.
3. Completed generator keeps returning `{ value: undefined, done: true }` on
   `next`.
4. `Object.getPrototypeOf(gen())` is `gen.prototype`.
5. `new (function*(){})` throws `TypeError`.
6. Two `next()` results are different objects.
7. Generator instance supports property assignment (`g.x = 1; g.x === 1`).
8. `.throw(e)` on fresh (never started) generator throws without running body.
9. `.return(v)` on fresh generator returns done without running body.
10. Parameter side effects deferred:
    ```js
    let log = [];
    function side(){ log.push(1); return 0; }
    function* g(a = side()) { yield 1; }
    let it = g();
    assert(log.length === 0);
    it.next();
    assert(log.length === 1);
    ```
11. `%GeneratorPrototype%.next/throw/return` are non-enumerable, writable,
    configurable.

### Checkpoint

Protocol shell exists and state machine invariants are enforced.

---

## Phase 2.5 — Design Appendix: Concrete Continuation Model ✅ (Superseded)

The frame-stack/step-engine model described here was superseded by the statement
replay approach. The step engine, `GenFrame`, `Frame`, and `Completion` types
were not needed. Instead, the generator reuses the existing interpreter with
`YieldSignal`/`GeneratorReturnSignal` suberrors for suspension control flow.

### Scope (original, not implemented as described)

1. Enumerate every AST node type that can contain `yield` and determine its
   resumable evaluation strategy (PC positions + which temporaries to save).
2. Implement `GenFrame`, `Frame`, `Completion`, and `HandlerEntry` types.
3. Implement the trampoline loop skeleton (`step_gen`) that dispatches on the
   top frame, runs one step, and returns `Yield(value)` or `Done(completion)`.
4. Implement `make_iterator_result(value, done) -> Value::Object` helper that
   returns a fresh object each call.
5. Verify that block/loop environments are heap-allocated and frame-storable.

### Deliverables

1. Compiling type definitions for all frame/completion types.
2. Skeleton `step_gen` function that handles a trivial generator (empty body,
   single `yield`).
3. Design doc or comments listing PC positions per AST node kind.

### Checkpoint

Frame model compiles and handles the simplest generator; no expression-position
yield yet.

---

## Phase 3 — Step Engine and `yield` in Expression Positions ✅ (Adapted)

Statement replay model handles yield in expression positions via re-execution.

### Scope

1. Build generator-only step evaluator (`eval_gen_step`) using the frame model
   from Phase 2.5, with explicit continuation/frame data (trampoline-friendly).
2. Implement `yield` suspension/resumption for expression contexts, including:
   - assignment RHS (`x = yield 1`)
   - call args (`f(yield 1)`)
   - condition tests (`if (yield v)`, `while (yield v)`)
   - loop update/test locations where valid
3. Preserve first-`next` semantics (input ignored before first suspension).
4. Reuse the same helper functions for primitive ops (GetValue, ToBoolean, etc.)
   as the direct-style interpreter. The step engine handles *control/evaluation
   order* only, not reimplemented JS semantics.

### Required Tests

1. `let x = yield 1;` receives value from second `next(v)`.
2. `if (yield 0) ...` resumes correctly.
3. `for (; yield i < 3; )` executes correctly.

### Checkpoint

Core suspension model works across expression positions, not just flat
statements.

---

## Phase 4 — Exceptions, `try/catch/finally`, `.throw()`, `.return()` ✅

**Previously Phase 5. Moved before control-flow integration because `for-of`
requires `IteratorClose` on abrupt completion, which depends on the handler
stack and finally semantics.**

### Scope

1. Add exception/finally handler stack to generator frame context.
2. Implement `.throw(e)` as injected abrupt throw at suspension point.
3. Implement `.return(v)` as injected abrupt return that still executes active
   `finally` blocks.
4. Ensure `finally` may itself `yield`, and completion remains correct after
   resumption (use `pending_completion` field).
5. Implement `IteratorClose` runtime helper as a shared utility for use by both
   `for-of` (Phase 5) and `yield*` (Phase 6).

### Required Tests

1. `.throw()` caught by generator `catch` and continues/yields.
2. Uncaught `.throw()` completes generator and rethrows to caller.
3. `.return()` inside `try` executes `finally`.
4. `.return()` when `finally` yields: intermediate `{ done: false }` then final
   `{ done: true }`.
5. `finally` that yields multiple times before completing preserves pending
   completion correctly.

### Checkpoint

Full generator protocol behavior for abrupt completions is correct.
`IteratorClose` helper is available for subsequent phases.

---

## Phase 5 — Control-Flow Integration with Existing Signal Semantics ✅

**Previously Phase 4. Moved after exception/finally support because `for-of`
requires `IteratorClose` on abrupt completion (break/throw/return).**

### Scope

1. Reuse/adapt current interpreter control model (`Signal`) for generator step
   evaluation rather than introducing a conflicting mechanism.
2. Implement loop + label behavior in generator bodies:
   - `while`, `do-while`, `for`, `for-in`
   - labeled `break`/`continue`
3. Implement `for-of` in generator bodies, using the `IteratorClose` helper from
   Phase 4 for abrupt completion paths.
4. Ensure abrupt completions are propagated through generator frames exactly once.
5. Handle per-iteration lexical environments for `for (let ...)` + yield
   correctly (each iteration gets its own binding, preserved across yield).

### Required Tests

1. Labeled break/continue inside generator loops.
2. `for-of` in generators with `yield` in body.
3. `return` from inside nested loop in generator.
4. `break` inside `for-of` in generator triggers `IteratorClose` on the
   iterable.
5. `for (let i = 0; ...)` with yield inside — captured `i` per iteration.

### Checkpoint

Generator control-flow behavior matches non-generator semantics plus suspension.

---

## Phase 6 — `yield*` Delegation (Full Semantics) ✅

### Scope

1. Implement delegated iteration with forwarding rules:
   - caller `next(v)` -> delegate `.next(v)`
   - caller `throw(e)` -> delegate `.throw(e)` if present, otherwise
     `IteratorClose` + throw
   - caller `return(v)` -> delegate `.return(v)` if present, otherwise
     `IteratorClose` + return
2. On delegate completion, `yield*` expression value becomes delegate final
   `value`.
3. Use the shared `IteratorClose` helper from Phase 4 (not a separate
   implementation).

### Required Tests

1. Basic nested generator delegation.
2. Delegated `.throw()` path.
3. Delegated `.return()` path.
4. `yield*` over non-generator iterables.

### Checkpoint

`yield*` behavior is spec-aligned for normal and abrupt resumption paths.

---

## Phase 7 — Language Integration and Regression Sweep ✅

### Scope

1. Verify generators work through existing iteration consumers:
   - `for...of`
   - spread
   - destructuring
2. Add mixed-feature tests (modules/classes/arrow callbacks interacting with
   generators where applicable).
3. Run targeted test262-like cases for generators.

### Required Tests

1. `for (const x of gen())`.
2. `[...gen()]`.
3. `const [a, b] = gen();`.
4. Existing non-generator suite remains green.

### Checkpoint

Generators are integrated into current language features without regressions.

---

## Phase 8 — Hardening and Performance ✅

### Scope

1. Add stress tests for deep iteration/resume to validate step-loop stack
   safety.
2. Benchmark hot paths for non-generator functions to confirm no performance
   regression from generator support.
3. Clean up internal API boundaries and document invariants.

### Checkpoint

Implementation is stable, maintainable, and performance-safe.

---

## Dependency Rules (Important)

1. **Phase 2.5 before Phase 3**: The concrete frame/continuation model must be
   finalized before building the step engine, otherwise Phase 3 will either
   reintroduce host-stack recursion or require an invasive rewrite.
2. **Phase 4 (exceptions/finally) before Phase 5 (control-flow/for-of)**:
   `for-of` requires `IteratorClose` on abrupt completion, which depends on the
   handler stack and finally semantics from Phase 4.
3. **Phase 4 before Phase 6**: `yield*` requires correct abrupt completion
   forwarding and the shared `IteratorClose` helper.
4. Phase 3 must cover expression-position `yield` before loop/control-flow work,
   otherwise later fixes become invasive.
5. Phase 2 state invariants (`Executing` guard) are mandatory before exposing
   protocol methods broadly.

---

## Risks and Guardrails

1. **Risk: step engine becomes a second interpreter** with divergent semantics.
   Guardrail: reuse the same helper functions for primitive ops
   (GetValue/ToBoolean/etc.) and keep generator stepping limited to
   "control/evaluation order", not reimplementing JS semantics.

2. **Risk: try/finally correctness with yields** — pending completions lost or
   applied twice. Guardrail: require an explicit `pending_completion` field and
   tests where `finally` yields multiple times before completing.

3. **Risk: lexical env per-iteration bugs** — especially `for (let ...)` + yield.
   Guardrail: add tests asserting captured loop variables behave like spec with
   yields inside the loop.

4. **Risk: frame variant explosion** — if implementing resumable evaluation for
   all expressions via frame PCs becomes unmanageable (dozens of variants with
   repeated boilerplate), consider the alternative approach below.

### Alternative Approach: Bytecode IR

If the frame-per-AST-node approach hits complexity limits (signals: dozens of
frame variants, bugs clustering around evaluation order and temporary storage),
consider lowering generator bodies into a small bytecode/IR at creation time:

- Emit ops with explicit stack discipline and jump targets at yield points.
- Store `pc`, operand stack, env pointer, handler stack.
- Non-generator code stays direct-style.

More work up-front but dramatically reduces the surface area of "resumable
evaluation" because you resume a VM, not half-evaluated AST nodes.

---

## PR Strategy

1. One PR per phase.
2. Each PR must include new tests and passing `moon test`.
3. Run `moon info && moon fmt` before merge.
4. Keep `pkg.generated.mbti` diffs intentional and reviewed.
