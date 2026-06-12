# Architecture Redesign Findings — 2026-06-12

> Status: active analysis. This note replaces compatibility-preserving framing
> with a first-principles target. Backward compatibility for internal packages,
> experimental entry points, and undocumented public surface is not a design
> constraint. Functional correctness and ECMAScript semantics remain constraints.
>
> Code remains the source of truth. This document intentionally describes
> package and subsystem boundaries rather than specific fields or line-level
> implementation details. The companion execution contract is
> [architecture-execution-plan-2026-06-12.md](architecture-execution-plan-2026-06-12.md).

---

## 1. Change Pressures Driving Redesign

The confirmed pressure is no longer mutable realm state. The current
architecture-state audit reports no remaining runtime/stdlib module-level
mutable state. The active pressure is now boundary clarity as the project grows
from a tree-walking interpreter into a runtime plus optimization experiments.

Observed pressures:

- **Execution paths are multiplying.** The default tree-walker, the
  closure-conversion prototype, and the bytecode prototype all execute some
  JavaScript. Without a stricter semantic boundary, fixes can spread across
  execution paths.
- **Closure conversion is useful but not a good long-term execution shape.** It
  exposed real AST-dispatch overhead and remains useful as benchmark evidence
  and closure-analysis research. The risk is not that closure conversion is
  useless; the risk is that expanding a host-closure execution path duplicates
  JavaScript semantics already owned by the runtime.
- **Static semantics are scattered.** Strictness detection, early errors,
  declaration discovery, hoisting, eval preparation, function-constructor
  preparation, and bytecode planning are related transformations but currently
  live across runtime and compiler responsibilities.
- **Runtime representation is too easy to depend on.** The runtime package
  exposes a broad surface, including mutable implementation structures. That
  makes representation changes harder than necessary and lets compiler or
  stdlib code bypass semantic operations.
- **Builtin bootstrap is a gravity well.** Interpreter creation, realm setup,
  stdlib installation, global mirroring, harness setup, and intrinsic wiring are
  strongly coupled. This raises the cost of changing builtins or realm startup.
- **No-compatibility constraint changes the target.** The ideal design should
  not preserve accidental package APIs, experimental CLI flags, or internal
  helper names. Compatibility shims are acceptable only as temporary migration
  scaffolding, not as long-term architecture.

Non-pressures:

- The tree-walking interpreter is not obsolete. It is still the correctness
  oracle.
- The runtime/stdlib package direction is not the immediate problem; the
  existing one-way dependency remains valuable.
- A full rewrite is not justified by current evidence. The system has strong
  tests and can migrate through smaller correctness-preserving cuts.

## 2. Current Architecture Diagnosis

Major subsystems:

- **Frontend:** token definitions, lexer, parser, AST, and shared JavaScript
  errors. It turns source into AST.
- **Runtime:** value model, environments, property/proxy/descriptor algorithms,
  evaluation, calls, construction, modules, promises, host queues, and realm
  state. It owns JavaScript semantics.
- **Stdlib:** built-in constructors, prototypes, methods, timers, harness
  helpers, and family-specific builtin behavior. It depends on runtime
  semantics.
- **Wiring layer:** composes runtime and stdlib while keeping runtime from
  importing stdlib directly.
- **Compiler experiments:** closure conversion and bytecode. These are opt-in
  execution paths and benchmark vehicles, not the default semantic owner.
- **Facade, CLI, tooling, benchmarks:** user entry points, conformance tools,
  native tooling, and measurement support.

Current dependency direction is mostly intentional:

```text
facade / CLI / benchmarks -> frontend / interpreter / compiler
interpreter wiring        -> runtime + stdlib
stdlib                    -> runtime
runtime                   -> frontend + errors
compiler                  -> AST + runtime semantic helpers
```

State ownership is improved compared with earlier architecture notes:

- Durable interpreter and realm state is owned by interpreter/realm containers.
- Host side effects live behind host state and explicit event-loop checkpoints.
- The audit for runtime/stdlib module-level mutable state currently passes with
  no classified retained globals.

Ownership remains unclear at the boundaries between:

- static semantics and runtime execution;
- compiler lowering and runtime semantic operations;
- builtin installation and realm/global bootstrapping;
- representation storage and public runtime API.

Architectural bottlenecks:

- Runtime is the semantic center and also exposes many implementation details.
- Bytecode currently combines analysis, IR definition, lowering, and VM
  execution in one package area.
- Closure conversion contains valuable optimization evidence but is too close to
  being a parallel interpreter if expanded.
- Builtin setup is a coordination hotspot rather than a registry-style boundary.

## 3. Architectural Problems

These are system-level problems, not local code-style issues.

### P1 — No explicit script-preparation boundary

The engine lacks a first-class stage for preparing source or AST before
execution. Static semantics, declaration plans, strictness, eval/function
construction rules, and bytecode planning should be different consumers of a
shared preparation model. Today they are split across runtime and compiler
code.

Impact: changing strict-mode or declaration behavior can require edits in both
runtime execution and optimization paths.

### P2 — Execution operations are not narrow enough

The bytecode path correctly delegates many JavaScript operations back to the
runtime. However, the compiler can still observe or mutate runtime
representation in places where it should ask for a semantic operation.

Impact: representation changes can break compiler execution even when behavior
should be unchanged.

### P3 — Closure conversion has the wrong long-term ownership model

Closure conversion is not worthless. It has value as:

- evidence that AST dispatch matters;
- a benchmark comparison path;
- a source of lessons for closure analysis, locals, captures, and environment
  access.

It is unsuitable as the primary optimization architecture because a host-closure
execution path tends to reimplement semantics such as eval, constructors,
proxies, errors, completion values, and host behavior.

Impact: expanding it broadly increases the chance of two semantic owners.

### P4 — Runtime implementation details are API-shaped

The runtime package exposes too much of its internal representation. With
backward compatibility removed as a constraint, these surfaces should be
redesigned around semantic capabilities rather than preserved.

Impact: the current shape makes first-principles representation changes harder
than they should be.

### P5 — Builtin bootstrapping has too many reasons to change

Realm startup, global binding creation, intrinsic wiring, builtin registration,
function stamping, and test harness setup are coupled in one startup flow.

Impact: adding or reshaping builtins has a larger blast radius than necessary.

## 4. Target Architecture

The target is a correctness-first engine with one semantic runtime and one
optimization pipeline that lowers into runtime-owned operations.

```text
source
  -> frontend parse
  -> script preparation / static semantics
  -> execution
       -> tree-walker runtime   (correctness oracle)
       -> bytecode VM           (optimized representation)
```

Target subsystems:

- **Frontend:** parse only. It should not know runtime or compiler concerns.
- **Preparation/static-semantics layer:** pure AST analyses and preparation
  products. It owns strictness, early errors, declaration plans, eval/function
  source preparation, and analysis data needed by bytecode.
- **Runtime semantic operations:** the only API for JavaScript operations that
  have observable semantics: property access, assignment, deletion, calls,
  construction, conversion, operators, descriptors, proxy dispatch,
  iteration, completion handling, and error conversion.
- **Runtime representation internals:** private storage and data structures for
  values, realms, environments, objects, and host state.
- **Stdlib registry:** builtin families register constructors, prototypes,
  globals, hooks, and intrinsic metadata through an explicit setup protocol.
- **Bytecode compiler and VM:** the long-term optimization path. It may use
  closure analysis, but it must lower into explicit instructions and runtime
  semantic operations rather than host-language closures.
- **Closure-conversion archive path:** retained only while it provides benchmark
  evidence or migration lessons. It should not be expanded as a production
  execution architecture. Once bytecode covers its benchmark value, remove or
  archive it.

Because backward compatibility is not a constraint, the ideal end state may:

- delete experimental public entry points;
- rename or split internal packages;
- replace public mutable structures with opaque capabilities;
- intentionally change generated package interfaces;
- remove compatibility wrappers after each migration stage.

Behavioral correctness remains non-negotiable: the redesigned engine must still
implement the same JavaScript semantics for supported features.

## 5. Dependency And Boundary Rules

Hard rules:

1. Runtime must not import stdlib.
2. Frontend must not import runtime, stdlib, or compiler.
3. Static semantics must be pure over AST and shared metadata; it must not own
   interpreter state.
4. Runtime representation internals must not be imported by compiler or stdlib.
5. Compiler and bytecode may call runtime operations, but must not implement
   property, proxy, call, construct, descriptor, conversion, or JavaScript error
   semantics themselves.
6. Stdlib may define builtin behavior, but shared ECMAScript internal methods
   belong to runtime operations.
7. Closure conversion must not gain new semantic surface unless the same work is
   required to retire it or validate bytecode behavior.
8. Public package shape is allowed to change. Interface diffs are reviewed for
   intent, not compatibility preservation.

Preferred dependency direction:

```text
frontend  <- preparation <- runtime tree-walker
frontend  <- preparation <- bytecode compiler -> bytecode VM -> runtime ops
runtime ops -> runtime internals
stdlib -> runtime ops
wiring -> runtime + stdlib
facade / CLI -> chosen execution mode
```

## 6. Migration Strategy

The authoritative staged migration is
+[architecture-execution-plan-2026-06-12.md](architecture-execution-plan-2026-06-12.md).
This findings document records the rationale; the execution plan is the roadmap.
If the two disagree, update the execution plan first and then adjust this
summary.

The migration principles are:

- Add architecture guardrails before moving semantic code.
- Split bytecode responsibilities before making more semantic migrations through
  bytecode.
- Extract pure preparation/static-semantics facts before hiding runtime
  representation.
- Define the execution-context contract for runtime operations before routing
  direct eval, construction, completion, realm, or error behavior through them.
- Migrate by narrow semantic family, with bytecode/tree-walker equivalence tests
  for every supported construct touched.
- Delay broad builtin-registry work until descriptor, prototype, call, and
  construction operation seams are stable enough not to force a speculative
  registry shape.
- Retire closure conversion only after bytecode covers its useful benchmark and
  research role.

## 7. Verification And Observability Plan

Required invariants:

- Supported JavaScript behavior is preserved.
- Tree-walker remains the semantic oracle.
- Bytecode either matches tree-walker or rejects unsupported syntax explicitly.
- Compiler does not own JavaScript internal method semantics.
- Runtime/stdlib import direction remains one-way.
- No runtime/stdlib ambient mutable state reappears.
- Interface changes are intentional, not accidental.

Required checks:

```bash
moon check
moon test
make architecture-state-audit
moon info
git diff --check
```

Additional checks to add:

- Import-boundary scan.
- Runtime-representation-access scan for compiler and stdlib.
- Bytecode/tree-walker equivalence test matrix for supported constructs.
- Preparation-layer tests that run the same source through script, eval,
  Function-family constructors, and module entry points where applicable.

Observability principles:

- Preparation products should be inspectable in tests.
- Bytecode unsupported cases should fail with explicit rejection messages.
- Runtime operations should be narrow enough that tests can assert which
  semantic family owns a behavior.

## 8. Functional And Non-Functional Risk Analysis

Functional risks:

- Moving static semantics can regress strict mode, eval, modules, declaration
  conflicts, TDZ, or function-constructor behavior.
- Moving bytecode behind runtime operations can regress property/proxy/call
  semantics if wrappers are incomplete.
- Reworking builtin setup can regress descriptor attributes, global names,
  prototype identity, and cross-realm behavior.
- Deleting compatibility surfaces can break local tooling or benchmarks that
  still call experimental entry points.

Non-functional risks:

- Preparation products may allocate more memory if copied too eagerly.
- Runtime operation wrappers may add overhead in bytecode hot loops.
- More packages can increase navigation cost unless boundaries are named around
  responsibilities.
- Deleting compatibility layers can temporarily slow feature work while callers
  migrate.

Mitigations:

- Keep preparation data minimal and immutable where possible.
- Benchmark only after a reproducible bottleneck is isolated.
- Prefer explicit operation names over generic abstraction layers.
- Delete transitional wrappers quickly after internal callers move.

## 9. Trade-Offs And Alternatives

### Decision: bytecode is the long-term optimization path

Problem solved:

- Reduces dispatch overhead without making host-language closures the semantic
  unit.

Improves:

- Explicit execution state.
- Testability.
- Ability to use closure analysis without duplicating JavaScript semantics.

Cost:

- Requires IR/VM structure and more compiler tests.

Alternative considered:

- Expand closure conversion broadly.

Why rejected:

- It has already demonstrated semantic duplication pressure. It is useful as a
  measuring stick and research artifact, not as the ideal architecture.

### Decision: no backward-compatibility preservation for internals

Problem solved:

- Avoids entrenching accidental API and mutable representation leaks.

Improves:

- Freedom to design runtime operations and internal storage from first
  principles.

Cost:

- Downstream users of undocumented internals may break.
- Local tooling and benchmarks may need direct migration.

Alternative considered:

- Keep facade re-exports and deprecations for every old surface.

Why rejected:

- The user constraint for this redesign explicitly prioritizes ideal design over
  compatibility.

### Decision: staged migration, not rewrite

Problem solved:

- Preserves confidence while changing architecture.

Improves:

- Debuggability and reviewability.

Cost:

- Temporary mixed architecture during transition.

Alternative considered:

- Full rewrite into target packages.

Why rejected:

- No evidence shows the current behavior cannot be migrated safely. A rewrite
  would discard valuable conformance and regression coverage.

### Decision: static semantics becomes a shared layer

Problem solved:

- Removes duplicated AST preparation logic from runtime and compiler paths.

Improves:

- Lower blast radius for strict/eval/declaration changes.

Cost:

- Requires careful separation of pure analysis from runtime instantiation.

Alternative considered:

- Leave static semantics in runtime and let compiler duplicate what it needs.

Why rejected:

- That is the current pressure.

## 10. Scope Definition

Included:

- Preparation/static-semantics boundary.
- Runtime operation API.
- Runtime representation hiding.
- Bytecode package structure.
- Closure-conversion containment and eventual retirement.
- Builtin bootstrap registry.
- Architecture guardrails.

Excluded:

- New ECMAScript feature work.
- Parser rewrite.
- AST redesign unless required by preparation products.
- CLI UX polish.
- Test262 headline-number edits.
- Performance optimization without current benchmark evidence.
- Tooling redesign unrelated to enforcing architecture.

## 11. Constraints And Unknowns

Constraints:

- MoonBit package boundaries enforce visibility; files alone do not.
- Generated interface files must be regenerated, not edited manually.
- Internal package boundaries protect against external imports, but packages
  inside the same module still require discipline and scans.
- Functional correctness is still required even when API compatibility is not.

Unknowns:

- Exact downstream usage of runtime and compiler internals.
- Performance cost of operation wrappers until measured.
- Best shape of preparation products before a small prototype proves it.
- Which closure-conversion benchmarks remain uniquely useful once bytecode
  coverage grows.

## 12. Recommended Next Steps

1. Add Stage 0 guardrails for import direction and representation access.
2. Prototype a small preparation/static-semantics product with one low-risk
   analysis currently duplicated by runtime and bytecode.
3. Add tests that inspect the preparation result directly and compare execution
   behavior before/after.
4. Define the first runtime operation family to migrate bytecode away from
   representation access.
5. Freeze closure-conversion feature growth. Keep it as benchmark/research input
   until bytecode replaces its useful measurements, then remove or archive it.
6. Plan the builtin registry after the preparation and operation seams exist;
   avoid combining bootstrap redesign with compiler restructuring.

## Evidence Checked

This note is based on the current worktree state, package manifests, generated
interfaces, architecture documents, closure-conversion and bytecode notes,
MoonBit outlines/analyze output, the architecture-state audit, and local
`moon check` / `moon test` results on 2026-06-12.
