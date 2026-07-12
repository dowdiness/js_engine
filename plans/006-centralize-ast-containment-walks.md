# Plan 006: Centralize AST containment traversal mechanics without erasing semantics

> **Executor instructions**: This is a correctness-sensitive refactor. Plan 001
> must be DONE first. Characterize every consumer before designing the shared
> primitive, obtain design review before implementation, and stop rather than
> forcing incompatible semantic walks into one abstraction. Update this plan's
> row in `plans/README.md` when complete.
>
> **Drift check (run first)**:
> `git diff --stat f806f28..HEAD -- ast parser/early_errors.mbt parser/parser_test.mbt interpreter/runtime/eval_expr.mbt interpreter/runtime/generator.mbt interpreter/interpreter_test.mbt interpreter/async_iteration_test.mbt docs/design/architecture-execution-plan-2026-06-12.md`
> Rebuild the consumer matrix on any AST/scanner drift.

## Status

- **Priority**: P2
- **Effort**: M–L
- **Risk**: MED–HIGH
- **Depends on**: `plans/001-private-member-early-errors.md`
- **Category**: tech-debt
- **Planned at**: commit `f806f28`, 2026-07-13

## Why this matters

Yield/pattern containment recursion is independently implemented in parser early
errors, expression evaluation, and generator replay. Plan 001 is a concrete
drift example: new private-member variants were handled in one runtime scanner
but omitted from parser containment. The shared opportunity is the mechanical
knowledge of AST child relationships; each consumer's boundary policy remains
its own semantic responsibility. A correct refactor makes new variants visible
to all consumers without allocating child arrays or pretending the walkers have
identical meaning.

## Current state

- `parser/early_errors.mbt:46-277` defines four private recursive functions for
  yield/await over expressions and patterns. It has special rules for arrow
  parameter defaults, full function boundaries, class heritage/computed keys,
  and destructuring expressions.
- `interpreter/runtime/eval_expr.mbt:26-170` defines
  `pattern_may_contain_yield` and `expr_may_contain_yield` for evaluator routing.
- `interpreter/runtime/generator.mbt:118-267` defines
  `expr_contains_yield`, `pattern_contains_yield`, and parameter scanning for
  replay/resumption behavior.
- The functions share large match trees but are not interchangeable. In
  particular, whether to descend into arrow defaults, function bodies, class
  members, and static blocks is context-dependent.
- `ast/ast.mbt:101-189,200-207,231-254` defines expression, pattern, parameter,
  and class-member child shapes. The `ast` package is already a production
  dependency of parser, runtime, and compiler, so a representation-neutral child
  traversal primitive there preserves the allowed dependency matrix.
- `static_semantics/moon.pkg` depends on AST and errors; the architecture target
  at `docs/design/architecture-execution-plan-2026-06-12.md:145-176` forbids
  parser/front-end dependence on static semantics.
- The same design document's Stage 5 at `:613-643` calls for moving one complete
  early-error family across all source kinds with pinned error order/location.
  This plan does **not** perform that broader preparation migration.
- Compiler scans such as `compiler/bytecode_lower.mbt:2969` have different
  predicates and unsupported-syntax responsibilities. They are evidence of the
  general pressure, not automatic scope.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| AST/package map | `moon ide outline ast/ && moon ide outline parser/ && moon ide outline interpreter/runtime/` | current symbols listed, or a documented IDE limitation for a package |
| Parser regressions | `moon test parser --filter '*private*early*error*'` | plan 001 tests pass before and after refactor |
| Runtime/generator tests | `moon test interpreter --filter '*yield*'` | selected yield/generator tests pass |
| Typecheck after every source edit | `moon check` | exit 0 |
| Full tests | `moon test` | exit 0 |
| Architecture gate | `make architecture-audit` | exit 0; no forbidden dependency/representation change |
| Interfaces/format | `moon info && moon fmt && moon check` | all exit 0; interface diff reviewed |

## Suggested executor toolkit

- Use `skill://moonbit-agent-guide`, `skill://moonbit-traits`,
  `skill://moonbit-refactoring-safety`, and `skill://moonbit-verification` if
  available.
- Before implementation, obtain a fresh design review answering: “Does this
  child-traversal API preserve every boundary axis without per-node allocation?
  Which unseen AST variant would falsify the design?”

## Scope

**In scope**:

- `ast/ast.mbt` or one new cohesive `ast/traversal.mbt` file in the same package
  — shared non-allocating child traversal mechanics.
- `parser/early_errors.mbt` and `parser/parser_test.mbt`.
- `interpreter/runtime/eval_expr.mbt`.
- `interpreter/runtime/generator.mbt`.
- Existing focused interpreter/generator test files, preferably
  `interpreter/interpreter_test.mbt` and
  `interpreter/async_iteration_test.mbt`, only for behavior characterization.
- Generated interfaces from `moon info` only when the API must be public to
  direct package dependents; never hand-edit them.

**Conditionally in scope**:

- A compiler scanner only if the exact same child primitive fits after the
  consumer matrix proves it, with no changed unsupported-case semantics. Default
  is to leave compiler unchanged.
- Architecture docs only if implementation changes a documented package
  boundary; ordinary conformance with the existing dependency matrix needs no
  prose edit.

**Out of scope**:

- Moving parser early errors into `static_semantics/` or implementing Stage 5
  preparation/source-kind migration.
- Changing JavaScript acceptance, error ordering/location, generator replay, or
  evaluator routing.
- A generic pull iterator returning allocated `Array[Expr]` children.
- Trait hierarchies, associated-type emulation, or a full extensible visitor
  framework without a demonstrated need.
- AST representation changes, compiler feature expansion, or closure/bytecode
  semantic work.

## Git workflow

- Branch: `refactor/ast-containment-traversal`.
- Separate concerns in commits:
  1. characterization tests;
  2. shared AST traversal primitive with one migrated consumer;
  3. remaining consumer migrations and duplicate deletion.
- Suggested final messages: `test: characterize AST containment boundaries` and
  `refactor(ast): centralize containment traversal`.
- Do not push/open a PR unless instructed.

## Steps

### Step 1: Verify dependency and complete the impact audit

1. Confirm plan 001 is DONE and its private-node parser tests pass.
2. Enumerate every caller of all six yield-containment functions and the possible
   expression/pattern types at each call path.
3. Inspect generated package interfaces to determine the minimum visibility the
   shared primitive needs. Prefer `pub` to `pub(all)`.
4. Confirm parser, runtime, and AST package dependencies against the documented
   allowed matrix.
5. State assumptions in at most three lines: child traversal is syntax-only;
   consumers own match/descend policy; no child collection allocation occurs.

**Verify**: the caller/type list is complete and plan 001 focused tests pass. If
plan 001 is not present, stop.

### Step 2: Build the cross-consumer semantic matrix

For parser, evaluator, and generator scanners, record expected match/descent for
at least these axes:

- Direct `YieldExpr` and `AwaitExpr`.
- Unary/binary/member/computed/private read and assignment children.
- Destructuring defaults, computed keys, rest, and assignment targets.
- Arrow parameter defaults evaluated in the enclosing scope.
- Ordinary, async, generator, and async-generator function boundaries.
- Class heritage, computed method/field keys, field initializers, and static
  blocks.
- Nested arrows and full functions.
- Object/array literals, templates, calls/new/super, optional chains.
- New AST variants added after `f806f28`.

For every differing cell, name the reason. Do not label a difference duplicate
until the spec/runtime responsibility confirms it.

**Verify**: a second reviewer can predict each current scanner's Boolean for the
matrix without reading its implementation. Missing or unexplained cells are a
STOP condition.

### Step 3: Find and pin a current observable drift before refactoring

Use the cross-consumer matrix to identify at least one current AST shape for
which duplicated traversal produces an observable disagreement after plan 001
has landed. Probe through public parser/interpreter behavior, not private helper
return values. Candidate areas to investigate include:

- Generator yield/resume behavior for yields under member, assignment,
  destructuring, arrow-default, class-computed-key, and nested-function
  boundaries.
- Evaluator routing where `expr_may_contain_yield` selects a different execution
  path from generator replay containment.
- Newly added AST variants not covered uniformly after `f806f28`.

Write the smallest end-to-end regression test for the confirmed disagreement.
The test must assert observable parse acceptance, output, completion, thrown
error, or generator resume behavior. Add passing boundary controls alongside it,
including plan 001's private cases, but do not substitute passing
characterization coverage for the required failing regression.

**Verify before implementation**: the new end-to-end regression fails for the
predicted containment-drift reason, while the boundary controls pass. Calibrate
any comparison detector with a temporary known-positive control, then remove the
control before commit. If the matrix and probes reveal no current observable
failure after plan 001, STOP and report that the proposed refactor lacks the
repository-required failing test; do not implement it.

### Step 4: Design the minimal non-allocating traversal primitive

Design a syntax-layer API in the AST package that centralizes immediate child
relationships while letting each consumer decide:

- whether the current node matches;
- whether to descend through a semantic boundary;
- how expression children embedded in patterns/parameters/class members are
  visited;
- whether short-circuiting is supported.

Preferred shape is callback/fold-style push traversal over concrete AST types,
not a child array and not a trait with fake associated types. The API should
short-circuit without copying expressions or allocating an array per node.
Do not prescribe a trait if plain functions/callback records suffice.

Write the design in prose and have a fresh reviewer attack it. The review must
check new-variant maintenance, recursion/short-circuit behavior, closure
allocation, visibility, and all differing matrix axes.

**Verify**: reviewer approves the design with no unresolved semantic axis. If
any consumer needs a structurally incompatible traversal, narrow scope rather
than adding flags until everything fits.

### Step 5: Implement the AST primitive and migrate one consumer

1. Add the shared traversal in the cohesive AST source file.
2. Keep it representation-neutral and free of JavaScript semantic decisions.
3. Migrate the smallest parser containment scanner first while retaining its
   explicit policy.
4. Delete only recursion mechanics replaced by the primitive; keep named
   semantic policy local and readable.

**Verify immediately after each source-file edit**: `moon check`. Do not edit the
next source file until it passes. Then run parser focused tests and full parser
tests. Expected: identical results.

### Step 6: Migrate evaluator and generator consumers independently

For each consumer, one at a time:

1. Express its matrix policy against the shared syntax traversal.
2. Preserve short-circuit behavior and avoid per-node containers/copies.
3. Delete its duplicate mechanical recursion only after focused tests pass.
4. Run `moon check` immediately after that file edit.
5. Run its focused behavior suite before moving to the next consumer.

Do not migrate compiler scans by analogy. If a compiler scan demonstrably fits,
request explicit review before expanding scope.

### Step 7: Prove equivalence and clean cutover

1. Run every matrix-focused test.
2. Search for the old recursive helper definitions and identify any retained
   one with a semantic reason.
3. Run `moon test parser`, focused interpreter yield tests, and `moon test`.
4. Run `make architecture-audit` to confirm dependency direction and surface
   taxonomy remain valid.
5. Inspect allocations/code shape; reject a design that constructs child arrays
   or copies AST nodes during traversal.

Expected: no observable behavior changes and no unexplained duplicate recursion.

### Step 8: Finalize interfaces and formatting

Run:

1. `moon info`; review `.mbti` diffs. Expose only the minimum direct-dependent
   API and document why it is public.
2. `moon fmt`.
3. `moon check`.
4. Re-run parser private early-error tests and focused generator/evaluator tests.
5. `moon test`.
6. `make architecture-audit`.
7. `git diff --check` and scope review.

## Test plan

The required first test is a current end-to-end containment-drift regression
that fails before implementation and passes after it. The broader cross-consumer
matrix then supplies boundary controls for observable parser acceptance,
interpreter output/completion, and generator resume behavior. Existing
integration tests remain valuable; add whitebox tests only for policy cells that
cannot be observed externally, and never use them as a substitute for the
failing end-to-end proof. No test should assert source text, helper count, or
incidental function names.

## Done criteria

- [ ] Plan 001 is DONE and its regressions remain green.
- [ ] Complete caller/type audit and three-line assumptions are recorded.
- [ ] Cross-consumer matrix names every shared and differing semantic axis.
- [ ] Characterization tests cover all high-risk boundary differences.
- [ ] A current observable containment drift is captured by an end-to-end test
      that fails before the refactor for the predicted reason and passes after.
- [ ] Fresh design review approves a non-allocating, syntax-only primitive.
- [ ] Parser, evaluator, and generator share child traversal mechanics while
      retaining explicit local policies.
- [ ] No per-node child arrays, AST copies, or speculative visitor hierarchy were
      introduced.
- [ ] Compiler scans remain unchanged unless separately reviewed and justified.
- [ ] Focused tests, `moon test`, and `make architecture-audit` pass.
- [ ] `moon info` API changes are minimal/intentional; `moon fmt`, final
      `moon check`, and `git diff --check` pass.
- [ ] Only in-scope files changed and the plan index status is updated.

## STOP conditions

Stop and report if:

- Plan 001 is incomplete or its focused tests fail.
- No current observable containment failure can be reproduced after plan 001;
  passing characterization tests alone do not authorize this refactor.
- The three walkers' semantics cannot be represented without hiding a named
  policy difference behind Boolean flags.
- The design allocates child arrays/copies per node or adds avoidable work to
  hot evaluator/generator paths.
- Parser would need to import `static_semantics`, contradicting the allowed
  dependency matrix.
- Correctness requires the broader Stage 5 source-kind/error-order migration.
- A new trait/visitor framework has only one meaningful consumer.
- A source edit cannot pass `moon check` before the next source edit.
- Any equivalence gate fails twice after a reasonable correction.

## Maintenance notes

The shared primitive owns syntax topology only. Every new AST variant must update
that topology once and add a matrix case; each consumer still owns whether the
node matches and whether a semantic boundary is traversed. Reviewers should pay
special attention to arrow defaults, class computed keys, nested functions, and
private expressions—the places where superficially similar walkers diverge.
Stage 5 preparation migration remains separate because it changes validation
ownership, source-kind coverage, error ordering, and package boundaries.
