# Architecture Redesign — 2026-04-15

> **Status: COMPLETE** — All four stages shipped 2026-04-15 on branch
> `claude/restructure-architecture-VkLTl`. This document is now a historical
> record of the analysis and migration plan that was executed.

This document is a point-in-time architectural analysis. It supersedes the
informal Stage 3/4 notes in ROADMAP.md. Code is the source of truth; if this
document and the code disagree, update this document.

---

## 1. Change Pressures

Four concrete pressures drive this analysis. Each is observed, not speculative.

**1.1 Compliance ceiling with no clear improvement path**
The bulk of remaining test262 failures cluster in stdlib categories: Array
(78.5%), Object (83.7%), TypedArray (51.6%), RegExp (65.3%). Fixing these
requires isolated changes to individual builtin files. Currently the stdlib
and the core execution engine share one flat MoonBit package — a stdlib change
can silently touch runtime internals, and there is no static barrier to catch
it.

**1.2 Known correctness bugs from global mutable state**
Two mutable fields on the `Interpreter` struct — `strict` and
`current_generator` — must be manually saved and restored at function
boundaries. `agent-todo.md` issue #10 (sloppy-mode `this` coercion broken in
async functions) traces to the strict flag not propagating reliably through the
async machinery. The same fragility affects generator nesting.

**1.3 Stage 3/4 package split is planned but has no execution path**
ROADMAP.md has identified splitting `interpreter/` into `runtime/` and
`stdlib/` sub-packages since at least Phase 24. The prerequisites named there
(coupling audit, field access review) have not been completed. This analysis
completes the audit and produces a concrete migration plan.

**1.4 Descriptor logic has unclear ownership**
Three files participate in property descriptor semantics: `property.mbt`,
`builtins_object_descriptors.mbt`, and `builtins_object.mbt`. When a descriptor
compliance bug appears, it is unclear which file owns the fix. Past descriptor
work has touched all three.

---

## 2. Current Architecture Diagnosis

### 2.1 Package structure

```
token/          Token definitions
errors/         JsError suberror enum
lexer/          Tokenizer
ast/            Expr, Stmt, Pattern, Program enums
parser/         Recursive-descent (expr.mbt, stmt.mbt, parser.mbt)
interpreter/    Single flat package — 48 .mbt files, ~52k lines (excl. tests)
cmd/main/       CLI entry point
```

The previous structural refactoring (archived in
`docs/archive/2026-04-09-structural-refactoring.md`) split the original
monolithic `interpreter.mbt` into focused files. That work is complete. The
remaining structural problem is one level up: every file in `interpreter/` is
in the same MoonBit package and therefore has unrestricted visibility to every
other file.

### 2.2 Conceptual groups within interpreter/ (unenforced)

| Group | Files | Role |
|-------|-------|------|
| Core types | `value.mbt`, `environment.mbt`, `errors.mbt`, `symbols.mbt`, `conversions.mbt`, `factories.mbt`, `iterators.mbt`, `array_side_tables.mbt` | Data definitions, coercion, construction helpers |
| Core execution | `interpreter.mbt`, `eval_expr.mbt`, `exec_stmt.mbt`, `call.mbt`, `property.mbt`, `class.mbt`, `construct.mbt`, `hoisting.mbt`, `destructuring.mbt`, `operators.mbt`, `modules.mbt`, `generator.mbt`, `async.mbt` | Evaluation, scope, control flow |
| Stdlib | `builtins.mbt` + 24 `builtins_*.mbt` files | JavaScript built-in library |

### 2.3 Dependency directions

Intended (correct in principle, unenforced):

```
Stdlib → Core execution → Core types
```

Observed violations:
- `builtins_promise.mbt` directly manipulates `interp.host.timer_queue`,
  `interp.host.timer_id_counter`, `interp.host.timer_insertion_counter`, and
  `interp.host.cancelled_timer_ids` (14 call sites, all timer-related).
  No other stdlib file accesses interpreter internals beyond the normal
  `Interpreter` method surface.

This is the entire coupling audit result. The violation is narrow and
localized, which makes the package split tractable.

### 2.4 State ownership

The `Interpreter` struct carries two categories of mutable state that have
different ownership semantics:

*Per-call execution context* — must be saved/restored at each function call
boundary:
- `mut strict: Bool`
- `mut current_generator: GeneratorObject?`

*Persistent runtime state* — legitimately lives on the struct for the lifetime
of the interpreter:
- `host: HostEnv` (I/O, queues)
- `global: Environment`
- `module_registry`, `module_exports`, `module_export_bindings`
- `generator_objects`, `gen_id_counter`, `symbols`

The first category is the problem. These fields are mutated inline during
evaluation and rely on callers to restore them. When the call stack unwinds
abnormally (thrown error, generator suspension, async resumption), there is no
guarantee of restoration.

### 2.5 Gravity wells

After the file split, no file is structurally overloaded. The largest
non-test files are in the 1,800–2,800 line range and each has a coherent
responsibility. The structural gravity-well problem has been solved.

What remains is the *semantic* concentration of descriptor logic across three
files described in §1.4.

---

## 3. Architectural Problems

The following are system-level architectural problems, not local code issues.

**P1 — No package boundary between runtime and stdlib**  
Severity: High. Blocks the goal of making isolated stdlib changes safe. Without
a boundary, a refactor to any builtin file can silently reach into core
execution state, and the compiler cannot catch it.

**P2 — Per-call execution context stored as global mutable state**  
Severity: Medium. Causes real correctness bugs today (agent-todo #10). Creates
a hidden invariant (all callers must save/restore) that is easy to violate when
adding new features.

**P3 — Descriptor semantics split across three files with no designated authority**  
Severity: Low-medium. No bugs attributed to this today, but each descriptor
compliance fix requires auditing three files. The boundary between
`property.mbt` and `builtins_object_descriptors.mbt` is informal.

The following are NOT architectural problems (excluded from scope):

- File sizes: resolved by the April 2026 structural refactoring.
- The eval_expr ↔ exec_stmt ↔ call_value circular dependency: this is
  inherent to tree-walking interpretation. It is not a problem to fix.
- Parser/AST structure: clean and stable.

---

## 4. Target Architecture

### 4.1 Package structure

```
interpreter/            Root package (integration layer)
  interpreter.mbt       Interpreter struct, new(), run(), event loop
  builtins.mbt          Stdlib registration coordinator
  moon.pkg.json         Imports both runtime and stdlib

interpreter/runtime/    Core execution engine
  moon.pkg.json         No imports from stdlib
  [core type files]
  [core execution files]

interpreter/stdlib/     JavaScript built-in library
  moon.pkg.json         Imports runtime
  [builtins_*.mbt files]
```

### 4.2 Per-call execution context

Replace the two per-call mutable fields on `Interpreter` with an `ExecContext`
value passed explicitly through `eval_expr`, `exec_stmt`, `call_value`, and
their callees:

```
ExecContext {
  strict: Bool
  current_generator: GeneratorObject?
}
```

`ExecContext` is created at each function entry and passed down. It is not
stored on the struct. Callers no longer need save/restore discipline; the
context is local to each call frame by construction.

### 4.3 Descriptor authority

Designate `property.mbt` as the sole authority for property descriptor
semantics. It owns the validation primitives (non-configurable transition
checks, accessor vs. data descriptor rules, writable enforcement).
`builtins_object_descriptors.mbt` becomes a public-facing API layer that
delegates to `property.mbt`. No descriptor validation logic lives outside
these two files.

---

## 5. Dependency and Boundary Rules

```
Rule 1: stdlib → runtime (one-way). runtime MUST NOT import any stdlib file.
Rule 2: The stdlib timer operations in builtins_promise.mbt MUST access the
        host event loop through explicit runtime API methods, not direct field
        access.
Rule 3: The execution triad (eval_expr, exec_stmt, call_value) is co-dependent
        by design. This is documented, intentional, and lives in runtime.
Rule 4: All descriptor validation primitives live in property.mbt. No
        descriptor validation logic in builtins_*.mbt files.
Rule 5: ExecContext is a value type, not a field on Interpreter. It is not
        stored; it is passed.
```

Enforcement mechanism: Rules 1 and 2 are enforced statically by the MoonBit
compiler once the `moon.pkg.json` files are in place. Rules 3–5 are enforced
by code review. There is no mechanism to enforce them statically within a
single package.

---

## 6. Migration Strategy

Each stage is independently shippable. Each stage leaves the test suite
passing before the next begins.

### Stage 0 — Coupling audit (complete as of this document)

The audit was performed as part of writing this document. Findings:

- 14 direct accesses to `interp.host.*` timer fields, all in
  `builtins_promise.mbt`, all for `setTimeout`/`setInterval`/`clearTimeout`/
  `clearInterval` implementation.
- No other stdlib file accesses interpreter internals beyond `Interpreter`
  struct methods.
- Accessing `interp.strict` and `interp.current_generator`: 27 sites in
  `eval_expr.mbt`, 21 in `call.mbt`.

The stdlib coupling surface is narrow. Stage 3 is cheaper than the ROADMAP
estimated.

**No code changes. Prerequisite complete.**

### Stage 1 — Per-call execution context (correctness fix)

*What changes*: Add `ExecContext` struct. Thread it through `eval_expr`,
`exec_stmt`, `call_value`, `class.mbt`, `construct.mbt`, `async.mbt`,
`generator.mbt`. Remove `mut strict` and `mut current_generator` from
`Interpreter`. Update the 14 stdlib call sites in `builtins_promise.mbt` that
read `interp.strict` indirectly.

*What stays the same*: All observable JavaScript semantics. Package structure.
Test suite.

*How correctness is verified*: `moon check && moon test` (881 unit tests).
Specifically, verify: strict mode propagation in class bodies, function
declarations, async functions; generator nesting; the specific scenario from
agent-todo #10 (sloppy-mode async function `this`).

*How risk is controlled*: The change is mechanical — every function that
currently reads `self.strict` instead receives `ctx.strict`. The compiler
enforces the change completely once `mut strict` is removed from the struct.
No partial states are possible.

*Risk*: **Medium**. Large signature change touching the core execution triad.
Mitigated by the fact that the change is compiler-guided and fully covered by
the test suite.

*Performance note*: `ExecContext` must be a value type (stack-allocated struct
in MoonBit). Verify that MoonBit does not heap-allocate it before committing.
If it heap-allocates, a different approach is needed (see §9).

### Stage 2 — Timer API on HostEnv (prerequisite for Stage 3)

*What changes*: Add explicit methods to `HostEnv` (or `Interpreter`) for timer
operations: `schedule_timer(...)`, `cancel_timer(id)`. Replace the 14 direct
field accesses in `builtins_promise.mbt` with calls to these methods.

*What stays the same*: Timer semantics. Package structure. Test suite.

*How correctness is verified*: Promise test subset. `moon test`.

*Risk*: **Low**. Purely mechanical API wrapping with no semantic change.

### Stage 3 — Runtime/stdlib package boundary

*What changes*: Create `interpreter/runtime/moon.pkg.json` and
`interpreter/stdlib/moon.pkg.json`. Move files to their respective
sub-packages. Add `import` declarations to `moon.pkg.json` files. Fix any
remaining visibility errors reported by `moon check`.

*What stays the same*: All behavior. The root `interpreter/` package continues
to exist as the integration layer.

*How correctness is verified*: `moon check` enforces the boundary statically.
`moon test` verifies no behavioral regression.

*How risk is controlled*: Stage 2 must complete first (eliminating the one
boundary violation). After that, the split is a file-move operation with
compiler-guided error fixing.

*Risk*: **Low-medium**. The coupling surface is narrow (Stage 0 confirmed).
The main unknown is MoonBit sub-package mechanics — verify that `moon check`
correctly reports cross-package visibility violations before moving files.

### Stage 4 — Descriptor authority consolidation

*What changes*: Define a stable internal API for descriptor primitives in
`property.mbt`. Identify all descriptor validation logic in
`builtins_object_descriptors.mbt` that duplicates or shadows these primitives.
Consolidate to single implementations. `builtins_object_descriptors.mbt`
becomes a delegation layer.

*What stays the same*: Descriptor semantics. All test262 Object and descriptor
test results.

*How correctness is verified*: `python3 test262-runner.py --filter
"built-ins/Object" --summary`. Pass rate must not regress.

*Risk*: **Low**. Behavioral equivalence is testable and the test suite for
Object/descriptors is comprehensive.

---

## 7. Verification and Observability Plan

| Stage | Gate | Command |
|-------|------|---------|
| 1 | 881 unit tests pass | `moon check && moon test` |
| 1 | Strict mode in async (agent-todo #10) | Manual smoke test |
| 2 | Promise tests pass | `moon test` |
| 3 | Package boundary enforced | `moon check` (compilation failure = violation) |
| 3 | No behavioral regression | `moon test` |
| 4 | Object/descriptor pass rate unchanged | `python3 test262-runner.py --filter "built-ins/Object" --summary` |
| All | No new test262 regressions | Full test262 run before merge |

**Invariants to preserve:**
- All 881 unit tests pass after every stage.
- test262 pass rate does not decrease after any stage.
- `ExecContext` does not heap-allocate (verify with profiling before Stage 1 merge).
- The root `interpreter/` package public API (the `Interpreter` struct, `run()`,
  `Value` type) is unchanged.

---

## 8. Functional and Non-Functional Risk Analysis

### Functional risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Stage 1 misses a `self.strict` save/restore site | Low | `mut strict` removal from struct makes all sites compiler errors |
| Stage 3 MoonBit visibility rules differ from expectation | Medium | Prototype the `moon.pkg.json` setup on a small file pair first |
| Stage 4 descriptor consolidation changes edge-case behavior | Low | Object test suite is comprehensive; run full filter before merge |

### Non-functional risks

**Performance (Stage 1)**: Passing `ExecContext` as a struct argument adds one
struct to every `eval_expr` / `exec_stmt` / `call_value` call frame. If
MoonBit heap-allocates it, this is a measurable regression on call-heavy
workloads. Verify before committing. Alternative: pass fields individually (see
§9).

**Memory**: No change expected. No additional allocations.

**Concurrency**: The interpreter is single-threaded. No concurrency risk.

**Observability**: No change to error reporting, stack traces, or diagnostics.

**API compatibility**: The public API exposed by `cmd/main` (`moon run cmd/main`)
is unchanged. The MoonBit package API of `interpreter/` changes internally but
the exported surface (`Interpreter`, `Value`, `run()`) is preserved.

---

## 9. Trade-offs and Alternatives

### ExecContext as struct vs. individual parameters

*Chosen*: Single `ExecContext` struct passed by value.  
*Alternative*: Pass `strict: Bool` and `current_generator: GeneratorObject?`
as separate parameters.  
*Trade-off*: The struct approach groups related context cleanly and is
extensible (future fields added without changing every signature). The
individual-parameter approach avoids struct allocation entirely.  
*Decision*: Use the struct. If profiling shows allocation cost, switch to
individual parameters — the mechanical change is the same either way.

### Package split: two sub-packages vs. three

*Chosen*: `runtime/` and `stdlib/` only. Root `interpreter/` package remains
as integration layer.  
*Alternative*: Also split runtime into `runtime/types/` and
`runtime/execution/` sub-packages.  
*Trade-off*: Splitting runtime further would enforce the types→execution
dependency direction. But the types and execution files are tightly
co-dependent (eval_expr uses Value, Value factories use Interpreter methods)
and splitting them would require interface shims. Insufficient benefit for the
cost.  
*Decision*: Two sub-packages only. Revisit if the runtime package becomes a
pain point independently.

### Descriptor consolidation: merge files vs. delegation layer

*Chosen*: Keep two files; define `property.mbt` as authority, make
`builtins_object_descriptors.mbt` a delegation layer.  
*Alternative*: Merge `builtins_object_descriptors.mbt` into `property.mbt`.  
*Trade-off*: Merging creates a very large `property.mbt` (~3,800 lines).
Delegation preserves file cohesion while clarifying ownership.  
*Decision*: Delegation layer. The boundary becomes: `property.mbt` owns
primitives, `builtins_object_descriptors.mbt` owns the public-facing
`defineProperty` / `getOwnPropertyDescriptor` algorithms that call those
primitives.

### Keep mutable state vs. ExecContext

*Alternative*: Keep `mut strict` and `mut current_generator` on `Interpreter`
but add assertion guards (debug-mode checks that save/restore is correctly
paired).  
*Trade-off*: Cheaper short-term; doesn't fix the bugs. Agent-todo #10 would
remain open.  
*Decision*: ExecContext is the right fix. The bugs are real and the mitigation
is well-scoped.

---

## 10. Scope Definition

### Included

- ExecContext refactor (Stage 1)
- Timer API encapsulation on HostEnv (Stage 2)
- runtime/stdlib package boundary creation (Stage 3)
- Descriptor authority consolidation (Stage 4)

### Explicitly excluded

- Parser or AST changes
- New JavaScript features (for-await, named groups, class fields)
- Bytecode compilation, optimization passes, or JIT
- Further splitting `eval_expr.mbt` or `exec_stmt.mbt` into smaller functions
  (not motivated — current sizes are reasonable)
- Changes to the test262 runner or skip list
- Any change to the `cmd/main` public interface

---

## 11. Constraints and Unknowns

**MoonBit sub-package visibility mechanics**: The exact behavior of `pub`,
`pub(all)`, and package-private visibility across sub-packages needs
verification. Specifically: can a type defined in `runtime/` be used in
`stdlib/` if it is `pub(all)` but the containing package is not explicitly
imported? Prototype this before Stage 3.

**ExecContext allocation cost**: Unknown without profiling. The bench/ package
exists but benchmarks are minimal. Before Stage 1 merge, profile a
call-heavy workload (e.g., a recursive Fibonacci) and compare allocations.

**MoonBit `moon.pkg.json` import path conventions**: The import path
`"dowdiness/js_engine/interpreter/runtime"` is the expected form for a
sub-package, but confirm this matches MoonBit's actual resolution.

**Generator nesting**: `current_generator` is a single optional field. If
generators can be nested (a generator body iterating another generator's
values), this field may need to become a stack. The current behavior should be
audited before Stage 1.

---

## 12. Recommended Next Steps

Ordered by value and safety:

1. **Stage 1 — ExecContext** (fixes real bugs, standalone PR, compiler-guided).
   Start here. The compiler enforces completeness once `mut strict` is removed
   from the struct.

2. **Stage 2 — Timer API on HostEnv** (prerequisite for Stage 3, low risk,
   small PR). Can be combined with Stage 1 if desired.

3. **Stage 3 — Package boundary** (now known to be cheap: one coupling
   violation to fix, rest is file moves). Do after Stage 2.

4. **Stage 4 — Descriptor consolidation** (lowest urgency, no active bugs).
   Tackle when a descriptor compliance fix surfaces the three-file problem.

All stages are independently verifiable with the existing test infrastructure.
No new test harness is needed. Each stage can ship as its own PR.
