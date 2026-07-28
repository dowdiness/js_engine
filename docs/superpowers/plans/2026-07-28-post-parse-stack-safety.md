# Post-parse Stack Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every guest-depth-sensitive post-parse validation, fact-collection, and preparation traversal covered by issue #614 iterative without changing ECMAScript behavior or diagnostics.

**Architecture:** Early-error validation becomes one private heterogeneous LIFO work machine whose tasks carry strictness and traversal role. Pattern BoundNames become one stack-safe static-semantic fact operation; declaration, Annex B, auxiliary eval/function/block scans, and module algorithms remain separate operation-specific machines.

**Tech Stack:** MoonBit, the existing `@ast` immediate-child APIs, MoonBit package tests, public CLI target/profile checks.

## Global Constraints

- Base all work on `origin/main` commit `03748040a66c8b361811c981c34687c7906e776c` or a descendant.
- Preserve diagnostic kind, exact message, source location, first-error ordering, strictness, and function/class/module boundaries.
- Keep parser recursion separate and keep dynamic `eval_expr`/`exec_stmt`/runtime re-entry work in issues #608 and #617.
- Write each focused regression first and record its pre-fix failure before editing the owning traversal.
- Run `moon check` after every edited file before editing another file.
- Internal work arrays stay private; returned fact arrays are newly owned and source ordered.

## Caller inventory

| Family | Normal reachability | Current recursive entry | Disposition |
|---|---|---|---|
| Early errors | script, eval, function constructors, async/generator preparation, compiled scripts, modules | former expression/statement/pattern/parameter recursion | Iterative heterogeneous early-error machine |
| Statement-list declaration conflicts | every early-error entry | declaration-name collection | Iterative operation-specific collectors; only flat `StmtList` and one export wrapper remain grammar-bounded |
| Pattern BoundNames | validation, hoisting, params, constructors, generators, exports | all pattern name consumers | Shared iterative `bound_names` fact operation |
| Eval var names | direct eval | eval var-name collection | Iterative static declaration collector |
| Global var preflight and hoisting | script/eval/function preparation | var-name and declaration preparation | Separate source-ordered statement work stacks |
| Annex B | sloppy script/eval preparation | candidate and lexical-frame traversal | Iterative enter/leave frame machine |
| TDZ preparation | script, function, block and loop entry | block/pattern/loop preparation | Iterative statement walkers plus iterative BoundNames |
| Eval containment | direct eval | PerformEval Contains over statements, expressions, and patterns | Iterative heterogeneous predicate machine with all expression-bearing pattern edges scheduled |
| Yield predicates | class/generator preparation | expression, parameter, pattern, and class-member yield facts | Dedicated iterative short-circuit work stacks |
| Module AST facts | module linking/execution | export/import/name carriers and exported patterns | Iterative carrier flattening plus BoundNames |
| Module graph | module linking | dependencies, ExportedNames, and export resolution | Indexed DFS and explicit continuation machines |
| Parser early errors | parser, before AST handoff | `parser/early_errors.mbt` | Parser phase; follow up separately if a parser-phase reproducer exists |
| Runtime execution | after preparation | `eval_expr` ↔ `exec_stmt` ↔ calls | Issues #608/#617 |
| Closure/bytecode compilers | explicit compiler entrypoints, not tree-walker `Interpreter::run` | compiler expression/statement recursion | Separate compiler work |

---

### Task 1: Pin the Early-error Failure and Ordering Contract

**Files:**
- Create: `interpreter/stack_safety_test.mbt`
- Modify: `docs/superpowers/plans/2026-07-28-post-parse-stack-safety.md`

**Interfaces:**
- Consumes: existing package-private `run(source : String) -> Value raise Error` and `run_throws(source : String) -> String` test helpers.
- Produces: focused tests named with the `post-parse stack safety` prefix.

- [x] **Step 1: Add the minimized end-to-end comma regression**

```moonbit
///|
fn nested_comma_source(depth : Int) -> String {
  let mut source = "7"
  for _ in 0..<depth {
    source = "0," + source
  }
  source
}

///|
test "post-parse stack safety: 512 comma expressions" {
  inspect(run(nested_comma_source(512)), content="7")
}
```

- [x] **Step 2: Run the test and record the red failure**

Run: `moon test --target js interpreter --filter '*post-parse stack safety: 512 comma*'`

Expected pre-fix result on debug JS: host-generated `RangeError: Maximum call stack size exceeded`, with repeating `validate_block_early_errors_expr` frames. Parsing must have completed.

Observed on debug JS: the 512-comma test fails with `RangeError: Maximum call stack size exceeded` in repeated `validate_block_early_errors_expr` frames.

- [x] **Step 3: Add shallow competing-error tests**

Add tests using `run_throws` that pin the current exact first error for:

```javascript
"use strict"; (eval = 0, function() { let x; var x; })
function f(a = (eval = 0)) { let x; var x; }
class C extends (eval = 0) { m() { let x; var x; } }
switch (eval = 0) { case 0: let x; var x; }
```

Before writing expectations, run each source through the current checkout and copy its existing `run_throws` result verbatim. Also add a pattern-order fixture and a template-quasi-before-substitution fixture using the same method.

- [x] **Step 4: Verify only the deep regression is red**

Run: `moon test interpreter --filter '*post-parse stack safety*'`

Expected: shallow ordering tests pass; the 512-comma test fails in post-parse validation.

Observed on debug JS: all six shallow tests pass; only the 512-comma test fails, in repeated `validate_block_early_errors_expr` frames.

- [ ] **Step 5: Commit the eventual green test with its owning implementation**

Option A preserves this exact contract fixture under
`#skip("blocked by #608 runtime evaluator stack safety")`. The Task 3 validator
rewrite lets it pass post-parse validation, but the recursive runtime evaluator
still raises a JS `RangeError`; the skipped test remains type-checked and can be
run with `--include-skipped`. This step stays pending until #608 is integrated
and the exact `0,` repeated 512 times followed by `7` fixture runs green.

### Task 2: Introduce Stack-safe BoundNames

**Files:**
- Modify: `static_semantics/declarations.mbt`
- Modify: `static_semantics/declarations_test.mbt`
- Regenerate: `static_semantics/pkg.generated.mbti`

**Interfaces:**
- Produces: `pub fn bound_names(pattern : @ast.Pattern) -> Array[String]`.
- Consumes later: interpreter hoisting, parameter validation, TDZ preparation, and module export collectors.

- [ ] **Step 1: Add a deep direct-AST BoundNames test**

Construct an `IdentPat("x")`, wrap it 512 times in `DefaultPat`, call `bound_names`, and assert with `json_inspect` that the result is `["x"]`. Also assert an `AssignTarget` contributes no name and object properties retain source order.

- [ ] **Step 2: Verify the new API test is red**

Run: `moon test static_semantics --filter '*bound names*'`

Expected: compile failure because `bound_names` is undefined.

- [ ] **Step 3: Implement the iterative operation**

Use a private `Array[@ast.Pattern]` stack. Push array/object pattern children in reverse source order, visit only pattern-valued edges, emit `IdentPat`, and ignore `AssignTarget` and embedded expressions. Return the newly allocated output array.

- [ ] **Step 4: Verify and regenerate the interface**

Run: `moon check && moon test static_semantics --filter '*bound names*' && moon info`

Expected: all commands pass; the `.mbti` diff contains only the new direct-dependency API.

- [ ] **Step 5: Commit**

```bash
git add static_semantics/declarations.mbt static_semantics/declarations_test.mbt static_semantics/pkg.generated.mbti
git commit -m "refactor(static-semantics): make BoundNames iterative"
```

### Task 3: Replace Recursive Early-error Validation

**Files:**
- Modify: `interpreter/runtime/hoisting.mbt`
- Test: `interpreter/stack_safety_test.mbt`

**Interfaces:**
- Preserves: `pub fn Interpreter::validate_block_early_errors(Interpreter, Array[@ast.Stmt], Bool) -> Unit raise Error`.
- Adds only private work-item types and scheduling helpers.

- [ ] **Step 1: Define closed private task roles**

Add private variants for expression, statement, pattern with binding role, parameter, statement-list check, and lex-form check. Every relevant task carries strictness. Do not export the task enum or its stack.

- [ ] **Step 2: Implement reverse scheduling helpers**

Helpers append statement arrays, expression arrays, parameter arrays, and class members to a task stack in reverse index order. Empty arrays do nothing. No helper recursively calls itself.

- [ ] **Step 3: Transcribe expression order exhaustively**

Replace recursive expression calls with task scheduling. Preserve special order for function statement-list checks, parameter defaults, class heritage/members, template quasis, assignment-target name checks, destructuring patterns, and short-circuiting raised diagnostics. Do not use a wildcard generic-child fallback.

- [ ] **Step 4: Run `moon check` before continuing**

Run: `moon check`

Expected: pass before statement/pattern migration continues.

- [ ] **Step 5: Transcribe statement and pattern order exhaustively**

Schedule switch discriminant before its deferred CaseBlock declaration check; schedule strict `with` failure before children; schedule object-pattern lex form, computed key, value pattern, and default in that order. Function and class child strictness must equal the old implementation.

- [ ] **Step 6: Remove recursive private entries and drive one loop**

`validate_block_early_errors` initializes the private stack with the root statement-list check and source-ordered root statements, then pops until empty or an existing `Error` is raised.

- [ ] **Step 7: Verify focused behavior**

Run:

```bash
moon check
moon test interpreter --filter '*post-parse stack safety*'
moon test interpreter --filter '*early error*'
```

Option A result: normal focused JS and native runs exclude the skipped contract
fixture and pass the active tests. The separately named `phase isolation`
fixture traverses all 512 comma levels during early-error validation and reaches
the existing strict-assignment `SyntaxError` before runtime evaluation. Running
only the skipped success-valued contract with `--include-skipped --target js`
currently reaches the #608 dependency and raises the expected host `RangeError`.

- [ ] **Step 8: Commit**

```bash
git add interpreter/runtime/hoisting.mbt interpreter/stack_safety_test.mbt
git commit -m "fix(interpreter): make early-error validation stack-safe"
```

### Task 4: Convert Declaration, Hoisting, TDZ, and Annex B Walkers

**Files:**
- Modify: `static_semantics/declarations.mbt`
- Modify: `static_semantics/declarations_test.mbt`
- Modify: `interpreter/runtime/hoisting.mbt`
- Modify: `interpreter/runtime/interpreter.mbt`
- Test: `interpreter/stack_safety_test.mbt`

**Interfaces:**
- Consumes: `@static_semantics.bound_names`.
- Preserves existing public declaration and interpreter APIs.

- [ ] **Step 1: Add red deep-shape tests**

Add direct-AST tests for 512 nested statement containers ending in a `var`, 512 nested parameter patterns in a declared-but-never-called function, and an Annex B candidate behind non-executed control flow. Assert ordered names or preparation success so runtime statement recursion is not exercised.

- [ ] **Step 2: Make `collect_var_declared_names` iterative**

Use `(Stmt, in_block)` work items, reverse-schedule children in the current arm order, stop at function/class boundaries, and use `bound_names` for destructuring patterns.

- [ ] **Step 3: Verify static semantics**

Run: `moon check && moon test static_semantics`

Expected: pass with existing name order unchanged.

- [ ] **Step 4: Migrate name-only pattern consumers**

Replace `walk_pattern_idents` recursion in duplicate/strict-name, var preflight, hoisting, TDZ, call, construct, and generator preparation with loops over `bound_names`. Run `moon check` after each edited file.

- [ ] **Step 5: Convert statement hoisting walkers**

Give global var-name preflight, eval var names, actual var hoisting, and top-level TDZ separate stacks. First test whether eval-var collection exactly matches `collect_var_declared_names`; share only if parity tests prove identical output and boundaries.

- [ ] **Step 6: Convert Annex B with enter/leave tasks**

Represent lexical-frame lifetime explicitly. Push a leave-frame task before reverse-pushing block/case/catch children. Preserve labeled-function, loop-head, switch-shared-frame, catch, `with`, and function/class stop rules.

- [ ] **Step 7: Verify and commit coherent slices**

After each independently green collector, run its focused tests and commit it separately. Before the final Task 4 commit run `moon check && moon test interpreter --filter '*post-parse stack safety*'`.

### Task 5: Convert Auxiliary Post-parse Predicates

**Files:**
- Modify: `interpreter/runtime/eval_contains.mbt`
- Modify: `interpreter/runtime/eval_expr.mbt`
- Modify: `interpreter/runtime/generator.mbt`
- Modify as proven by inventory: `interpreter/runtime/call.mbt`, `interpreter/runtime/construct.mbt`, `interpreter/runtime/exec_stmt.mbt`, `interpreter/runtime/operators.mbt`
- Test: `interpreter/stack_safety_test.mbt`

**Interfaces:**
- Preserves all existing private/public predicate signatures.
- Uses separate work machines where arrow, function, class, or pattern-expression boundaries differ.

- [ ] **Step 1: Add one red test per proven recursive shape**

Cover direct eval containment, generator yield detection, deep grouping unwrap, function parameter preparation, and block/loop name preparation. Keep execution shallow or unreachable.

- [ ] **Step 2: Convert each predicate independently**

Preserve each predicate's exact arrow/function/class boundary. For multi-bit eval containment, visit all scheduled tasks; for boolean predicates, return immediately on the first true result.

- [ ] **Step 3: Verify after every file**

Run `moon check` after each edit, then the nearest focused tests. Do not copy traversal policy from a sibling predicate without comparing every AST variant.

- [ ] **Step 4: Commit each green predicate family**

Use one commit per independently testable semantic predicate family.

### Task 6: Convert Module AST and Graph Traversals

**Files:**
- Modify: `interpreter/runtime/module_graph.mbt`
- Modify: `interpreter/runtime/modules.mbt`
- Test: `interpreter/interpreter_test.mbt`
- Test: `interpreter/stack_safety_test.mbt`

**Interfaces:**
- Preserves module public APIs and error representation.
- Consumes: stack-safe BoundNames for exported destructuring declarations.

- [ ] **Step 1: Add red module tests**

Programmatically construct deep `StmtList` metadata, a long dependency chain, a weak re-export cycle, and ambiguous/missing export competitors. Pin the existing first diagnostic and source location for shallow competitors.

- [ ] **Step 2: Flatten module statement carriers iteratively**

Create one private source-ordered flatten helper returning a newly owned statement array. Reuse it in module import/export/name collectors instead of recursive `StmtList` walkers.

- [ ] **Step 3: Convert dependency traversal to indexed DFS frames**

Each frame stores the current module and next dependency index. Mark visiting before descent, resume the same frame after a child, and perform postorder actions only after all dependencies.

- [ ] **Step 4: Convert export resolution to continuation frames**

Carry direct/indirect/star phase, next source index, accumulated resolution, and the existing monotonic resolve set. Do not replace the algorithm with BFS or a new SCC linker.

- [ ] **Step 5: Verify module behavior and commit**

Run `moon check`, focused module tests, and `moon test interpreter --filter '*post-parse stack safety*'`. Commit AST flattening and graph traversal separately when each is independently green.

### Task 7: Final Audit and Cross-target Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-07-28-post-parse-stack-safety.md` inventory dispositions only.
- Regenerate intentionally changed `pkg.generated.mbti` files with `moon info`.

**Interfaces:**
- Produces the final issue #614 caller inventory and verification evidence.

- [x] **Step 1: Repeat the recursion inventory**

Search recursive references involving `@ast.Expr`, `@ast.Stmt`, `@ast.Pattern`, `@ast.Param`, class members, module records, and module export resolution. Update every inventory row to `iterative`, `bounded with proof`, or a linked issue.

Final audit result: all normally reachable issue #614 traversals are iterative.
The remaining statement helper recursion is bounded to parser-flat `StmtList`
carriers and at most one module export wrapper. Parser and compiler recursion are
separate entrypoint phases; dynamic evaluator recursion remains tracked by
#608/#617. The audit also found and closed missing PerformEval pattern edges and
the recursive ExportedNames star-graph traversal.

- [x] **Step 2: Run repository verification**

```bash
moon check
moon test
moon prove
moon info
git diff -- '**/pkg.generated.mbti'
```

Expected: all applicable commands pass; interface changes are limited to intentional static-semantic APIs.

Result: `moon check --deny-warn`, `moon test` (2685/2685), `moon prove`,
and `moon info` passed. The only generated interface change is the intentional
`static_semantics.bound_names` API.

- [x] **Step 3: Format only touched MoonBit files**

Run `moon fmt` as required, then discard unrelated formatter migration changes created outside the touched-file set. Re-run `moon check` and `moon test` afterward.

Result: touched MoonBit files were formatted incrementally; no repository-wide
manifest migration was applied. The final check and test commands passed.

- [x] **Step 4: Run the required target/profile matrix**

Run the fixed comma and additional focused workloads on debug/release JS and every supported Wasm target without host stack flags. Record success per target/profile; do not record threshold bisections as behavior.

Result: the active post-parse stack-safety suite (9/9), PerformEval traversal
suite (7/7), and ExportedNames suite (4/4) passed in debug and release modes on
JS, Wasm, and Wasm-GC. The exact 512-comma success contract remains skipped
under Option A until runtime evaluator issue #608 is integrated; its active
phase-isolation counterpart traverses the same validation depth.

- [x] **Step 5: Review final diff**

Run `git diff --stat origin/main...HEAD` and `git status --short`. Confirm only issue #614 implementation, tests, plan/spec, and intentional generated interfaces are present.

Result: the final diff contains 25 issue-scoped implementation, test,
design/plan, and generated-interface files. The worktree is clean. The branch is
one disjoint release-contract commit behind `origin/main`; that commit touches no
file in this change and was intentionally not rebased into the implementation
worktree.
