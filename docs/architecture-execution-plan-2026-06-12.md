# Architecture Execution Plan — 2026-06-12

> Companion to [architecture-redesign-2026-06-12.md](architecture-redesign-2026-06-12.md).
>
> This is the authoritative execution contract for the redesign. The findings
> document explains why the redesign exists; this file defines the roadmap,
> guardrails, target boundaries, stages, and stop conditions. If the two drift,
> update this file first and then adjust the findings summary.
>
> Internal backward compatibility is not a constraint. ECMAScript behavior,
> conformance tests, observability, and maintainability are constraints.

---

## 1. Execution Principles

1. **One semantic owner.** Runtime operations own JavaScript semantics. Tree-walk
   and bytecode are execution strategies, not separate semantic authorities.
2. **Tree-walker remains the oracle.** Bytecode must match tree-walker behavior
   for every supported construct or reject unsupported constructs explicitly.
3. **Closure conversion is evidence, not destination.** Keep it only while it
   provides benchmark signal or implementation lessons. Do not broaden it into a
   second interpreter.
4. **Break accidental APIs freely.** Generated interface diffs are acceptable
   when they remove internal leakage or clarify boundaries.
5. **Migrate by semantic fault line.** Separate stages for preparation,
   bytecode structure, object creation, property/descriptors/proxy, calls/direct
   eval, construction/`new.target`, conversions/operators, completion/errors,
   builtin setup, and representation hiding.
6. **Guardrails before motion.** Add audits before moving code so boundary
   regressions are visible.
7. **No speculative abstraction.** Create a boundary only when at least two
   current consumers need the same responsibility or when it prevents proven
   semantic duplication.
8. **Package boundaries matter.** MoonBit file splits improve navigation, but
   package splits and audits enforce architecture.

## 2. Target Package Shape

This is the desired end-state shape. Exact package names may change during
implementation, but the responsibility boundaries should not.

```text
token/                         lexical tokens and source locations
errors/                        JavaScript error taxonomy and formatting
ast/                           syntax tree definitions
lexer/                         source -> tokens
parser/                        tokens/source -> AST

static_semantics/              pure AST preparation and validation
  script preparation           strictness, early errors, declaration plan
  function preparation         parameter/body validation, strict body facts
  eval preparation             direct/indirect eval preparation facts
  module preparation           module-level validation and declarations
  bytecode facts               analysis shared by bytecode lowering

interpreter/runtime/           runtime public semantic facade
  ops                          JavaScript semantic operation families
  treewalker                   default AST evaluator
  bootstrap                    realm/global/host setup coordinator
  host                         event-loop and host integration

interpreter/runtime/internal/  representation and algorithms hidden from compiler/stdlib
  values                       value storage and object representation
  env                          environment records and bindings
  realm                        realm-owned state and intrinsics
  property                     ordinary/proxy/descriptor algorithms
  call_construct               call and construction internals
  modules                      module graph internals
  async                        promise/generator/async internals

interpreter/stdlib/            builtin families and registration
  registry                     builtin installation protocol
  families                     Array/Object/String/etc. behavior
  harness                      test harness host extensions

interpreter/                   composition/wiring only

compiler/bytecode/             long-term optimization pipeline
  ir                           bytecode instruction representation
  lower                        AST/preparation -> bytecode IR
  vm                           bytecode execution using runtime ops
  tests                        bytecode-vs-tree-walker equivalence

compiler/closure_legacy/       temporary closure-conversion benchmark path
```

Notes:

- `static_semantics/` must not depend on runtime state.
- `interpreter/runtime/internal/` exists to make representation access a
  deliberate violation rather than the easiest path.
- `compiler/closure_legacy/` is temporary. It should disappear once bytecode
  replaces its useful benchmark role.
- The target shape implies real package work, not only moving code between
  files inside the existing packages.

## 3. Allowed Dependency Matrix

Allowed directions:

```text
token                  -> none
errors                 -> none
ast                    -> token
lexer                  -> token, errors
parser                 -> lexer, ast, token, errors
static_semantics       -> ast, token, errors
runtime/internal       -> ast, token, errors, static_semantics where needed
runtime/ops            -> runtime/internal, ast/token/errors as needed
runtime/treewalker     -> runtime/ops, static_semantics
stdlib                 -> runtime/ops, runtime public facade
interpreter wiring     -> runtime public facade, stdlib
compiler/bytecode/ir   -> ast/token/runtime public handles only if unavoidable
compiler/bytecode/lower-> ast, static_semantics, bytecode/ir
compiler/bytecode/vm   -> bytecode/ir, runtime/ops
facade/CLI/benchmarks  -> public facade or explicit experimental packages
```

Forbidden directions:

```text
frontend               -> runtime, stdlib, compiler
static_semantics       -> runtime, stdlib, compiler
runtime/internal       -> stdlib, compiler
runtime/ops            -> stdlib, compiler
stdlib                 -> runtime/internal representation packages
compiler/bytecode      -> runtime/internal representation packages
closure_legacy         -> new runtime semantics or new language-feature ownership
```

Enforcement target:

- Package manifests should make forbidden imports impossible where MoonBit can
  enforce the boundary.
- Boundary audits should fail on forbidden imports before code review.
- Representation-symbol access from compiler/stdlib should be allowlisted only
  during migration and removed as each operation family lands.
- `.mbti` diffs should be reviewed for intentionality, not compatibility.

## 4. Surface Taxonomy And Deletion Rules

No internal backward compatibility does not mean every surface is equally cheap
to break. Classify surfaces before deleting or moving them.

| Surface | Examples | Rule |
|---|---|---|
| Stable user facade | root `run`, module APIs, event-loop APIs | Preserve unless an explicit product decision says otherwise. |
| Experimental public entry point | closure-conversion facade/CLI flag, bytecode prototype APIs | May rename/delete when the execution plan says their role is over. |
| Internal package API | runtime helpers, stdlib setup helpers, compiler internals | May break freely when replacing with a better boundary. |
| Generated interface artifact | `.mbti` exposure caused by `pub`/`pub(all)` | Review and shrink intentionally; do not preserve by default. |
| Benchmark/tooling hook | benchmark-only entry points, native tool helpers | May break if the benchmark/tool is migrated in the same stage. |

Before a representation-hiding PR:

1. classify each removed symbol into this table;
2. state whether any stable user facade changes;
3. regenerate interfaces with `moon info`;
4. explain every public-surface deletion in the PR notes.

This taxonomy prevents the no-compatibility stance from accidentally breaking
user-facing behavior while still allowing ideal internal design.

## 5. Proposed Preparation Boundary

The preparation layer should produce inspectable, immutable facts about code
before execution.

Preparation products should answer these questions:

- Is this body strict?
- What early errors apply before execution?
- What declarations must be instantiated?
- Which names participate in lexical/var conflicts?
- What eval-specific restrictions apply?
- What function-constructor parameter/body restrictions apply?
- Which facts can bytecode lowering reuse without repeating AST walks?
- Which constructs are unsupported by bytecode and why?

Required products:

```text
ScriptPreparation      facts for top-level script execution
ModulePreparation      facts for module execution
EvalPreparation        facts for direct/indirect eval execution
FunctionPreparation    facts for Function-family constructors and function bodies
BytecodePreparation    lowering facts and explicit unsupported reasons
```

Preparation inputs must be explicit. At minimum each preparation request needs:

- source kind: script, module, direct eval, indirect eval, Function constructor,
  GeneratorFunction constructor, AsyncFunction constructor, AsyncGeneratorFunction
  constructor, or bytecode lowering;
- parsed AST plus source locations from tokens/AST;
- Annex B mode;
- inherited strictness where the ECMAScript entry point inherits it;
- source name/specifier when diagnostics or module behavior need it;
- caller facts for direct eval: caller strictness, caller environment category,
  parameter-default-eval conflict facts, and whether `super` / `new.target` /
  `arguments` are legal in the caller context;
- function-constructor facts: parameter strings, body source, rest/default
  parameter facts, and expected early-error order;
- bytecode mode facts: supported-subset policy and explicit unsupported-case
  diagnostics.

Preparation outputs should include:

- strictness facts;
- ordered diagnostics / early errors with source locations;
- declaration facts separated from runtime environment mutation;
- eval/function/module-specific legality facts;
- bytecode unsupported diagnostics, distinct from runtime JavaScript errors.

Rules:

- Preparation may validate and describe; it must not mutate an interpreter or
  environment.
- Runtime tree-walking consumes preparation for execution setup.
- Bytecode lowering consumes preparation for planning and rejection decisions.
- Unsupported bytecode cases belong in preparation/lowering diagnostics, not in
  ad-hoc VM behavior.
- Error ordering and source-location behavior are part of the contract. Do not
  move early errors unless tests pin the relevant ordering and location class.

First extraction candidates:

1. Strictness/directive facts.
2. Declaration-name collection.
3. One early-error validation family shared by script/eval/function/module paths.
4. Bytecode unsupported-case classification.

## 6. Proposed Runtime Operation Boundary

Runtime operations are the only cross-boundary way to perform observable
JavaScript behavior.

Operation families:

```text
PropertyOps       get, set, delete, has, own property, own keys
DescriptorOps     descriptor conversion and validate/apply rules
CallOps           ordinary calls, receiver handling, direct eval routing
ConstructOps      construction, new.target, prototype resolution
ConversionOps     ToPrimitive, ToNumber, ToString, ToObject, ToPropertyKey
OperatorOps       unary, binary, update, compound assignment
IteratorOps       GetIterator, IteratorStep/Value/Close, spread collection
ObjectCreateOps   ordinary object/array/function creation through semantic builders
CompletionOps     normal/return/break/continue/throw handling
ErrorOps          JS exception wrapping and host error conversion
RealmOps          intrinsic lookup, realm-owned caches, cross-realm creation
HostOps           enqueue/drain boundaries for host queues when explicitly needed
```

### Execution context contract

The operation boundary must not become a bag of helpers that secretly depends on
ambient interpreter state. Every operation family must state what execution
context it needs.

A conceptual runtime-operation context should make these inputs explicit:

- active interpreter;
- active realm state;
- lexical environment when name lookup, eval, `this`, or `new.target` can be
  observed;
- current strictness and generator/async context when control flow can observe
  it;
- source location for error construction;
- call context: call vs construct, receiver, new target, and direct-eval status;
- host policy: whether an operation may enqueue jobs/timers and whether it may
  drain queues. Most semantic operations may enqueue but must not drain; facade
  and explicit event-loop operations drain;
- error wrapping policy: whether a MoonBit error should become a JavaScript
  exception value at this boundary or propagate as an internal defect.

Rules:

- Tree-walker may call operation families directly with its execution context.
- Bytecode VM must call operation families rather than representation internals.
- Stdlib must call operation families for shared ECMAScript internal methods.
- Direct eval, `new.target`, completion values, realm selection, host queue
  checkpoints, and JavaScript error wrapping require explicit context-bearing
  operations; do not hide them behind generic helpers.
- Runtime internals can remain optimized, but the operation boundary is the
  contract visible to compiler and stdlib.

First operation migrations:

1. Object and array literal construction helpers used by bytecode.
2. Property get/set/delete used by bytecode.
3. Descriptor/proxy operations used by Object/Reflect/Proxy paths.
4. Call/direct-eval operations used by bytecode.
5. Construct/`new.target` operations used by bytecode.
6. Conversion/operator/completion/error operations where bytecode still contains
   local semantic decisions.

## 7. Bytecode Equivalence Harness

The architecture depends on bytecode matching the tree-walker for every
supported construct. Define this harness before semantic migrations rely on it.

The harness should compare:

- result value string or structured value snapshot;
- host output array;
- JavaScript exception class and message where an exception is expected;
- completion behavior for scripts, functions, loops, and blocks where supported;
- explicit unsupported bytecode diagnostics for unsupported constructs;
- whether host queues are drained or left pending according to the tested entry
  point.

The harness should distinguish outcomes:

```text
TreeAndBytecodeMatch(value, output)
TreeAndBytecodeThrowSame(name, message, output)
BytecodeUnsupported(kind)
TreeWalkerRegression
BytecodeMismatch
```

Coverage matrix before operation migrations:

- literals and expression completion;
- object and array literals, including holes/spread where supported;
- property/computed get/set/delete;
- calls with receiver preservation;
- direct eval cases already supported by bytecode;
- construction and `new.target` cases already supported by bytecode;
- conversions/operators that bytecode lowers;
- throw vs return/break/continue handling for supported control flow;
- host output behavior for supported console/print paths.

Focused Test262 or equivalent local tests should be required per semantic
family when a migration touches eval, Proxy, descriptors, constructors, sparse
arrays, modules, cross-realm builtins, or host queues.

## 8. Closure-Conversion Policy

Closure conversion is useful in three ways:

- It proved that AST-dispatch overhead matters.
- It provides benchmark comparison for closure-heavy workloads.
- It offers lessons for closure analysis, capture detection, and environment
  access.

Closure conversion is harmful if it becomes:

- a second general-purpose interpreter;
- the owner of eval/proxy/constructor/error/completion semantics;
- the place where new JavaScript syntax support lands first;
- a public recommended execution mode.

Allowed work:

- Bug fixes required to keep existing tests meaningful.
- Benchmark maintenance while it remains a useful comparison.
- Extraction of analysis ideas into bytecode preparation.
- Documentation of lessons learned.

Forbidden work:

- New syntax coverage unless needed to retire or compare it.
- New public entry points.
- New semantic special cases except to preserve existing benchmark/test meaning
  while the path is being retired.
- Performance work that does not also advance bytecode or shared runtime ops.
- Additional semantic special cases that should belong to runtime operations.

Mechanical freeze requirements:

- Mark closure conversion as legacy experimental in docs, tests, benchmarks, and
  CLI help if the CLI flag remains temporarily.
- Require a note in any PR that touches it explaining whether the change is a
  bug fix, benchmark maintenance, or retirement work.
- Add a review checklist item rejecting feature broadening in closure conversion.

Retirement criteria:

1. Bytecode covers the primary benchmark scenarios currently used to justify
   closure conversion.
2. Bytecode has compare-against-tree-walker tests for those scenarios.
3. Bytecode performance is at least competitive on the measured workloads, or
   closure conversion no longer answers a unique performance question.
4. Closure-analysis lessons have been ported into preparation/lowering docs or
   code.
5. The facade and CLI no longer need a closure-conversion entry point.

End state:

- Delete the closure-conversion execution path, or archive it outside the active
  compiler pipeline if a historical benchmark artifact is still desired.

## 9. Stage Plan

### Stage 0 — Architecture guardrails and inventories

Goal: make boundary drift visible before moving code.

Work items:

- Add an import-boundary audit for package manifests.
- Extend or complement the mutable-state audit with representation-access checks
  for compiler and stdlib.
- Add an allowlist file for temporary violations.
- Inventory generated-interface exposure by surface category.
- Inventory known compiler semantic duplication and stdlib representation access.
- Add CI or Makefile entry for the combined architecture audit.

Done when:

- The audit passes on current main with known violations recorded by category.
- Adding a forbidden import fails locally.
- Adding new unapproved representation access fails locally.
- The allowlist is narrow enough to distinguish new debt from existing debt.

Verification:

```bash
moon check
moon test
make architecture-state-audit
# new architecture boundary audit command
moon info
git diff --check
```

Stop conditions:

- The audit cannot distinguish current debt from new debt.
- The allowlist is too broad to make new violations visible.

### Stage 1 — Freeze and label closure conversion

Goal: prevent accidental expansion while preserving its evidence value.

Work items:

- Move closure conversion under an explicit legacy/experimental namespace or
  label in package docs.
- Add a short policy note near its tests and benchmarks.
- Make benchmark names distinguish closure legacy from bytecode.
- Stop adding new syntax support except for retirement-enabling work.

Done when:

- A contributor can tell from package/doc names that closure conversion is not
  the long-term optimization path.
- Existing closure-conversion tests still pass.
- Reviews have a clear rule for rejecting feature broadening there.

Verification:

```bash
moon check
moon test compiler
moon test
```

Stop conditions:

- Moving names would force unrelated benchmark redesign.
- The change starts modifying JavaScript semantics.

### Stage 2 — Split bytecode into IR, lowering, and VM

Goal: make bytecode responsibilities navigable before threading more semantic
boundaries through it.

Work items:

- Move instruction representation to an IR-focused file/package.
- Move AST-to-bytecode lowering into a lowering-focused file/package.
- Move VM execution into a VM-focused file/package.
- Keep behavior and supported syntax unchanged.
- Keep closure legacy out of the bytecode package.

Done when:

- Each bytecode area has one reason to change.
- Generated compiler interface exposes only intentional entry points.
- Tests are unchanged except for import/path adjustments.

Verification:

```bash
moon check
moon test compiler
moon test
moon info
```

Stop conditions:

- Syntax support expands during the split.
- VM starts depending on lowering internals.

### Stage 3 — Seed the bytecode equivalence harness

Goal: make future semantic migrations observable.

Work items:

- Add a shared helper for tree-walker vs bytecode comparison.
- Capture value/result, host output, JavaScript exception class/message, and
  unsupported bytecode diagnostics.
- Add a minimal matrix for constructs bytecode already supports.

Done when:

- New bytecode tests can be added by describing source and expected comparison
  mode.
- Unsupported cases are asserted as unsupported, not hidden as failures.

Verification:

```bash
moon check
moon test compiler
moon test
```

Stop conditions:

- The harness cannot express exception or host-output mismatches.
- The harness depends on closure conversion.

### Stage 4 — Extract strictness and preparation input model

Goal: create the first pure preparation product without moving high-risk early
errors yet.

Work items:

- Add `static_semantics/` package.
- Define source-kind and preparation-input records.
- Move strictness/directive facts into it.
- Update script, eval, function-constructor, module, and bytecode callers where
  they only need strictness facts.

Done when:

- The new package has no runtime dependency.
- Tests can inspect strictness/preparation inputs independently of execution.
- Old duplicate strictness helpers are deleted or reduced to wrappers.

Verification:

```bash
moon check
moon test
moon test compiler
```

Stop conditions:

- Preparation starts mutating environment/interpreter state.
- The extraction requires broad behavior changes in the same patch.

### Stage 5 — Extract one early-error preparation family

Goal: validate the static-semantics boundary on a real correctness-sensitive
case.

Work items:

- Move one early-error validation family into preparation.
- Preserve source-location and error-ordering behavior.
- Update all relevant script/eval/function/module/bytecode callers.
- Add direct tests for preparation diagnostics plus execution tests.

Done when:

- The moved error is reported from preparation for every relevant source kind.
- Error class/order/location behavior is pinned.
- Runtime no longer owns that pure validation logic.

Verification:

```bash
moon check
moon test
# focused strict/eval/function/module tests for the moved error family
```

Stop conditions:

- Error ordering changes without an explicit test and rationale.
- Preparation needs runtime state to decide the error.

### Stage 6 — Extract declaration and hoisting facts

Goal: separate declaration discovery from environment mutation.

Work items:

- Add preparation products for declaration facts and hoisting plans.
- Runtime consumes the plan to instantiate declarations.
- Bytecode lowering consumes the same facts for local/env planning.
- Remove duplicated declaration/name scans from bytecode where replaced.

Done when:

- Declaration facts are computed once for a prepared body.
- Runtime instantiation remains responsible for environment mutation.
- Bytecode no longer repeats migrated scans.

Verification:

```bash
moon check
moon test
# focused strict/eval/TDZ/function-hoisting tests
```

Stop conditions:

- A plan mixes pure facts with mutable runtime handles.
- Bytecode behavior changes without a compare-against-tree-walker test.

### Stage 7 — Introduce object and array creation operations

Goal: remove compiler reliance on representation construction for common
literal paths without mixing in function creation semantics.

Work items:

- Add runtime operations for ordinary object and array creation needed by
  bytecode and stdlib.
- Migrate bytecode object/array literal and accumulator paths to those
  operations.
- Remove direct representation mutation from migrated bytecode paths.

Done when:

- Bytecode creates common objects and arrays through runtime operations.
- Representation-access audit shrinks.
- Tree-walker and bytecode still match for object/array literal tests.

Verification:

```bash
moon check
moon test compiler
moon test
# focused Array/Object literal equivalence tests
```

Stop conditions:

- Function creation, iterator result objects, or descriptor/proxy behavior sneaks
  into this stage.
- A hot path slows down and no benchmark exists to evaluate the trade-off.

### Stage 8 — Migrate property, descriptor, and proxy operations

Goal: put the highest-risk object internal methods behind runtime operations.

Work items:

- Migrate property get/set/delete/has operations used by bytecode.
- Migrate own-property, own-keys, descriptor conversion, and validate/apply
  operations used by stdlib Object/Reflect/Proxy paths.
- Add equivalence tests and focused descriptor/proxy tests.

Done when:

- Proxy, descriptor, receiver, and property landing behavior remain runtime-owned.
- Bytecode VM dispatches property instructions through runtime operations.
- Stdlib does not duplicate migrated descriptor/proxy semantics.

Verification:

```bash
moon check
moon test compiler
moon test
# focused Proxy/Object/Reflect/descriptor tests where changed
```

Stop conditions:

- Bytecode duplicates a runtime semantic branch instead of calling an operation.
- Descriptor/proxy invariants are not covered by focused tests.

### Stage 9 — Migrate calls and direct eval operations

Goal: make call semantics explicit without hiding direct-eval context.

Work items:

- Define call operation context for receiver, strictness, caller env, realm, and
  source location.
- Migrate bytecode call instructions to the call operation.
- Route direct eval through an explicit context-bearing operation.
- Add equivalence tests for ordinary calls, receiver preservation, and supported
  direct eval cases.

Done when:

- Direct eval does not rely on hidden ambient state.
- Bytecode call instructions contain stack mechanics, not call semantics.
- Tree-walker and bytecode agree for migrated supported call cases.

Verification:

```bash
moon check
moon test compiler
moon test
# focused eval/function call tests where changed
```

Stop conditions:

- Direct eval context is implicit.
- Host output or error wrapping behavior cannot be compared in tests.

### Stage 10 — Migrate construction and `new.target` operations

Goal: make construction semantics explicit and shared.

Work items:

- Define construct operation context for constructor, args, realm, source
  location, prototype override, and new target.
- Migrate bytecode construct instructions.
- Keep function creation separate unless required by construction context.
- Add equivalence tests for supported construction and `new.target` cases.

Done when:

- Constructor return rules, prototype resolution, and `new.target` are
  runtime-owned.
- Bytecode contains no local construction semantics beyond dispatch/stack work.

Verification:

```bash
moon check
moon test compiler
moon test
# focused constructor/new.target tests where changed
```

Stop conditions:

- `new.target` behavior is inferred from VM state instead of explicit context.
- Function creation semantics are broadened without tests.

### Stage 11 — Migrate conversions, operators, completion, and errors

Goal: finish bytecode semantic routing for non-object internal methods.

Work items:

- Migrate conversion and operator decisions still local to bytecode.
- Define completion and JavaScript error wrapping boundaries.
- Ensure throw/return/break/continue behavior is represented explicitly in tests.

Done when:

- Bytecode owns dispatch, stack/frame, and control transfer mechanics only.
- Runtime operations own conversion/operator/error semantics.

Verification:

```bash
moon check
moon test compiler
moon test
# focused operator/conversion/throw/control-flow tests where changed
```

Stop conditions:

- JavaScript `throw` and runtime defects are conflated.
- Completion values cannot be compared against tree-walker behavior.

### Stage 12 — Hide runtime representation internals

Goal: make representation mutation impossible outside approved runtime code.

Work items:

- Move representation-heavy code under runtime internal packages.
- Expose only semantic operation families and deliberately public value handles.
- Delete or privatize accidental constructors and mutable structures.
- Remove allowlist entries as package boundaries enforce the rule.

Done when:

- Compiler and stdlib cannot import representation internals.
- Generated runtime interface is meaningfully smaller.
- Remaining public surface is intentional under the surface taxonomy.

Verification:

```bash
moon check
moon test
make architecture-state-audit
# architecture boundary audit
moon info
```

Stop conditions:

- Runtime operations are not complete enough to replace direct access.
- Hiding representation forces semantic changes in the same patch.

### Stage 13 — Builtin registry pilot

Goal: reduce startup coupling after descriptor/prototype/call/construct seams are
stable enough to avoid speculative registry design.

Work items:

- Define a minimal registry protocol for one low-risk builtin family.
- Registry data must cover installed globals, descriptors, prototype links,
  intrinsic identity, realm-local caches if needed, hooks if needed, and setup
  order constraints.
- Keep harness setup as an explicit host/test extension.

Done when:

- One low-risk family installs through the registry.
- Global descriptors and prototype identity are unchanged for that family.
- The pattern is clear enough to decide whether to migrate more families.

Verification:

```bash
moon check
moon test
# focused tests for migrated builtin family
```

Stop conditions:

- Registry requires each family to know unrelated startup details.
- Startup behavior changes outside the migrated family.
- The selected family drags in descriptor/prototype/cross-realm complexity before
  those operation seams are stable.

### Stage 14 — Retire closure conversion

Goal: remove the second host-closure execution path.

Work items:

- Confirm retirement criteria are met.
- Remove closure-conversion entry points, CLI flag, benchmarks, and tests, or
  move them to an archive not built by default.
- Keep lessons in bytecode/preparation documentation.
- Ensure bytecode benchmarks cover the optimization evidence that closure
  conversion used to provide.

Done when:

- No active execution path compiles AST nodes into host-language closures.
- Bytecode is the only optimization pipeline.
- Tree-walker remains the default correctness path until bytecode is ready to
  replace it by evidence, not by architecture preference.

Verification:

```bash
moon check
moon test
moon info
git diff --check
# benchmark comparison if retirement is justified by performance coverage
```

Stop conditions:

- Closure conversion still answers a unique measured question that bytecode does
  not.
- Removal would hide a known correctness comparison gap.

## 10. First PR Sequence

Recommended first ten PR-sized slices:

1. **Boundary audit skeleton.** Import-direction scan plus allowlist.
2. **Representation-access inventory.** Detect compiler/stdlib direct
   representation access and record current debt.
3. **Surface taxonomy inventory.** Classify current public/runtime/compiler
   surfaces into stable facade, experimental, internal, interface artifact, and
   tooling/benchmark hook.
4. **Closure-conversion label/freeze.** Rename docs/tests/benchmarks to mark it
   legacy experimental; no semantic changes.
5. **Bytecode split, no behavior change.** IR/lowering/VM split inside compiler.
6. **Equivalence harness seed.** Add tree-walker/bytecode comparison helpers and
   a minimal existing-supported matrix.
7. **Static-semantics package seed.** Move strictness/directive facts and define
   preparation inputs.
8. **Early-error preparation slice.** Move one validation family and update all
   consumers.
9. **Declaration-facts slice.** Extract pure declaration/name collection.
10. **Object/array creation ops.** Migrate bytecode literal construction.

Each PR should include:

- one stated boundary improvement;
- one rollback path;
- exact verification commands;
- generated interface diff review when interfaces change;
- no unrelated conformance feature work.

## 11. Review Checklist

For every architecture PR, reviewers should ask:

- Which boundary does this strengthen?
- Which old path does this delete or make impossible?
- Does compiler or stdlib gain new representation access?
- Does bytecode duplicate runtime semantics?
- Does the runtime operation have an explicit execution-context contract?
- Does closure conversion grow rather than shrink?
- Is the tree-walker still the correctness oracle?
- Are unsupported bytecode cases explicit?
- Does the equivalence harness cover the touched bytecode behavior?
- Does the interface diff reflect an intentional ideal design change?
- Are tests inspecting the new boundary rather than only incidental behavior?

## 12. Done Definition For The Redesign

The redesign is complete when:

- Static semantics has a pure preparation boundary consumed by runtime and
  bytecode.
- Preparation inputs and outputs explicitly preserve source kind, strictness,
  Annex B, source locations, and early-error ordering.
- Runtime operations are the only cross-boundary owner of observable JavaScript
  semantics.
- Runtime operations that touch direct eval, `new.target`, completions, realm
  selection, host queues, or error wrapping have explicit execution-context
  contracts.
- Bytecode is split into IR, lowering, and VM responsibilities.
- Compiler and stdlib cannot import or mutate runtime representation internals.
- Builtin setup uses a registry-style protocol only after the operation seams it
  depends on are stable.
- Closure conversion is removed from the active execution architecture or kept
  only as archived research outside default builds.
- Architecture audits enforce the dependency and representation rules.
- Unit tests, focused equivalence tests, targeted semantic tests, and
  generated-interface review are part of the normal workflow.
