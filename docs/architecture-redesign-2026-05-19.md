# Architecture Redesign Findings — 2026-05-19

> This is an active migration record.
>
> Stage 0 guardrails, the initial interpreter-owned `RealmState`, and the
> well-known symbol ownership and lookup cleanup slices have landed.
>
> The document tracks the maintainability pressure after the April 2026
> runtime/stdlib split and the later PropertyBag / internal-method dispatcher
> work. Code remains the source of truth.

---

## 1. Change Pressures Driving Redesign

The confirmed pressure is narrow. State ownership remains unclear in places
where the public API already exposes multiple interpreters and realms.

Observed pressures include these:

- The public facade can return an interpreter for host-driven event-loop
  control.
- The test262 harness can create fresh realms.
- Most durable state is now interpreter-owned, but ambient execution and
  construction context remain module-global.
- Runtime and stdlib expose mutable implementation details as public API, which
  makes future internal reshaping harder than it needs to be.
- The closure-conversion prototype is useful as a benchmark path, but it
  already demonstrates the maintenance risk of a second execution path that can
  duplicate JavaScript semantics.

This analysis is driven by realm hermeticity, public-surface containment, and
execution-boundary clarity. Parser shape, file naming, and broad cleanup are
outside scope.

## 2. Current Architecture Diagnosis

The major subsystems are:

- Front end: token definitions, lexer, parser, AST, and shared JavaScript
  errors.
- Runtime: value model, environments, execution, property algorithms, modules,
  promises, proxies, host queues, and standard-library hooks.
- Stdlib: built-in constructors, prototypes, methods, harness functions, and
  timer setup.
- Wiring layer: composes runtime and stdlib while preserving the one-way
  `stdlib -> runtime` dependency.
- Public facade: parses source, executes scripts or modules, and drains host
  queues for the simple `run` APIs.
- Experimental compiler: closure-conversion benchmark path.

The intended dependency direction is mostly sound:

```text
root facade -> parser / interpreter / compiler
interpreter wiring -> runtime + stdlib
stdlib -> runtime
runtime -> ast / token / parser / errors
compiler -> ast / token / runtime
```

The previous split prevents `runtime -> stdlib` imports. Package direction is
acceptable; mutable state still bypasses interpreter ownership.

State ownership is split across these places:

- Interpreter-owned state: host queues, global environment, global object,
  module registry, generator state, symbol state, stdlib hook table,
  prototype caches, prototype refs, WeakMap / WeakSet side tables, and
  ArrayBuffer backing stores / detached state.
- Module-global state: current interpreter fallback and construction flag.
- Side effects: host output and event-loop queues live in `HostEnv`.

## 3. Architectural Problems

These are system-level concerns rather than local style issues:

**P1 — Realm/interpreter ownership is incomplete.**
This affects long-term change because fresh interpreter and fresh realm
behavior cannot be reasoned about from a single state owner.

**P2 — Runtime and stdlib expose mutable internals as public API.**  
This creates accidental API commitments around implementation details and makes
package-level extraction riskier.

**P3 — Execution optimization does not yet have a narrow semantic boundary.**  
Closure conversion is opt-in, but it reaches across many runtime details. If it
continues to grow without a boundary, future fixes may need to be duplicated in
the tree-walker and compiled path.

**P4 — Current-interpreter fallback is hidden control flow.**  
It makes some native-call paths work without explicit interpreter threading, but
it is implicit, process-wide state and therefore conflicts with realm and
concurrency safety.

Not classified as current architectural problems:

- Parser and AST shape.
- The existing runtime/stdlib dependency split.
- CLI shape.
- File-level organization inside already-focused packages.

## 4. Target Architecture

Keep the existing pipeline and package split. Add a clearer ownership model
inside the runtime and stdlib boundary.

Target structure:

- `@js_engine`: stable public facade.
- Front end packages: source-to-AST pipeline, unchanged.
- Runtime facade: public execution/value API used by interpreter, stdlib,
  compiler experiments, tests, and documented consumers.
- Runtime internals: state, property algorithms, execution helpers, and object
  stores that should not be imported directly by downstream users.
- `RealmState`: interpreter-owned state object for per-realm intrinsics,
  well-known symbols, prototype caches, object backing stores, and side tables.
- Stdlib: built-in behavior parameterized by interpreter or realm context, with
  no mutable module-global state that affects realm identity.
- Execution experiments: bytecode/IR or closure-conversion paths call shared
  runtime semantic operations rather than owning JavaScript semantics.

The target is not a full rewrite. It is an incremental containment of mutable
state and public surface area.

## 5. Dependency And Boundary Rules

Rules to enforce or audit:

1. `runtime` must not import `stdlib`.
2. `stdlib` must not mutate runtime module globals.
3. Mutable engine state must be owned by `Interpreter`, `HostEnv`, or
   `RealmState`.
4. Public mutable refs are not stable API. Existing ones should become
   compatibility shims or move behind methods.
5. The compiler path may call runtime semantic operations, but must not own
   property, call, constructor, proxy, descriptor, or JavaScript error
   semantics.
6. Root facade compatibility takes priority over runtime-internal API
   stability.

Language-enforced boundaries should be preferred where practical. If internal
packages are introduced later, keep the existing public package as a facade and
verify `.mbti` stability before removing compatibility shims.

## 6. Migration Strategy

### Stage 0 — Add Guardrails

What changes:

- Add tests that create two interpreters / realms and verify isolation for
  symbols, prototypes, ArrayBuffer storage, WeakMap / WeakSet state, timers,
  microtasks, and module registry behavior.
- Add a static audit command or script for unapproved module-level mutable
  state in runtime and stdlib.
- Add an `.mbti` diff review expectation for any runtime public-surface change.

Implemented guardrail:

- `make architecture-state-audit` runs
  `scripts/architecture-state-audit.py`, which compares runtime/stdlib
  module-level mutable `Ref`, `Map`, and `Array` bindings against the
  2026-05-19 migration inventory. The classified globals are still debt; the
  guardrail prevents new ambient mutable state from appearing silently.
- CI runs the audit in the fast unit-test job so new runtime/stdlib ambient
  mutable state cannot bypass review by relying on local-only checks.

What stays the same:

- Public facade.
- Runtime/stdlib package direction.
- Existing behavior.

Verification:

- `moon check`
- `moon test`
- targeted tests for realm isolation and public facade behavior

Risk control:

- No behavior change yet; this stage exposes current coupling before moving it.

### Stage 1 — Introduce `RealmState`

What changes:

- Add an interpreter-owned state container for realm-specific intrinsics and
  backing stores.
- Thread this state through setup and lookup paths where new code can use it.
- Keep old globals temporarily as compatibility shims where immediate removal
  would be risky.

First slice:

- Introduce the state owner and threading point only.
- Do not move ArrayBuffer, WeakMap / WeakSet, prototype-cache, or well-known
  symbol storage in the same patch.
- Use the Stage 0 tests and audit as the compatibility boundary while the old
  globals remain in place.

What stays the same:

- Built-in behavior.
- Public root facade.
- Runtime package path.

Verification:

- Two-realm isolation tests.
- `moon info` review for unintended public API expansion.

Risk control:

- Move only ownership first; do not combine with semantic fixes.

### Stage 2 — Move Intrinsics And Well-Known Symbols

What changes:

- Move well-known symbol refs and prototype refs into realm-owned state.
- Change stdlib setup to populate the realm state through explicit APIs.
- Change property and method lookup paths to consult interpreter/realm state
  rather than module globals.

What stays the same:

- User-visible symbol names and prototype behavior.
- Standard-library method bodies unless a direct lookup API must change.

Verification:

- `built-ins/Symbol` targeted tests.
- `instanceof`, iterator, `Object.prototype.toString`, RegExp symbol method,
  and `$262.createRealm` smoke tests.

Risk control:

- Migrate one intrinsic family at a time.

Current state:

- Well-known symbol allocation and lookup now use realm-owned
  `WellKnownSymbols`, and standalone stdlib setup still reserves those IDs in
  the provided `SymbolState`.
- The temporary compatibility path and no-argument well-known symbol lookup
  helpers have been removed.
- Iterator/prototype caches, runtime factory prototype refs, stdlib Promise and
  RegExp prototype refs, dependent runtime prototype read paths, and WeakMap /
  WeakSet side-table storage have moved into `RealmState` through PR #147.

### Stage 3 — Move Remaining Backing Stores And Ambient Context

What changes:

- Move ArrayBuffer backing bytes, backing-store IDs, and detach state into
  realm-owned storage.
- Replace construction context globals with explicit call/construct context.
- Replace current-interpreter fallback with explicit interpreter/context
  threading.

What stays the same:

- Observable object identity and method behavior.
- Public facade APIs.

Verification:

- `built-ins/ArrayBuffer`, `built-ins/DataView`, and typed array targeted
  tests.
- Tests that mutate one realm and verify another realm does not observe it.

Risk control:

- Preserve existing storage algorithms during the move. Optimize only after
  behavior is pinned.

### Stage 4 — Reduce Runtime Public Surface

What changes:

- Move implementation-only helpers behind `internal/` packages or a narrower
  facade where MoonBit package boundaries make sense.
- Deprecate or replace accidental public mutable refs.
- Keep root facade stable.

What stays the same:

- External `@js_engine` entry points.
- Intended runtime methods used by stdlib and compiler experiments.

Verification:

- `moon info` and `.mbti` diff review.
- Build a small downstream smoke package if public API compatibility is
  uncertain.

Risk control:

- Use compatibility re-exports and deprecations before removal.

### Stage 5 — Define The Execution Operation Boundary

What changes:

- Introduce a narrow runtime operation surface for compiled/bytecode execution:
  property get/set, computed get/set, calls, construction, operators,
  descriptors, error wrapping, and completion handling.
- Keep closure conversion opt-in and limited.
- Prefer bytecode/IR work that calls runtime operations instead of duplicating
  semantics.

What stays the same:

- Tree-walking interpreter remains the correctness oracle.

Verification:

- For every supported compiled construct, compare compiled execution with the
  tree-walker.
- Run benchmark checks only after a microbenchmark reproduces the claimed
  performance pressure.

Risk control:

- Do not broaden compiled syntax until the operation boundary is stable.

## 7. Verification And Observability Plan

Invariants to preserve:

- Root `run`, `run_compiled`, module, and event-loop APIs keep their external
  behavior.
- Runtime/stdlib dependency remains one-way.
- Standard library methods use shared runtime semantic operations for property,
  call, construct, descriptor, proxy, and error behavior.
- Multiple interpreters and realms do not share mutable realm state unless the
  ECMAScript or host model explicitly requires it.

Required checks:

- `moon check`
- `moon test`
- `make architecture-state-audit`
- `moon info`
- `.mbti` diff review
- static scan for unapproved module-level mutable runtime/stdlib state
- targeted Test262 filters for affected built-ins or language areas

Useful targeted areas:

- `built-ins/Symbol`
- `built-ins/ArrayBuffer`
- `built-ins/DataView`
- `built-ins/WeakMap`
- `built-ins/WeakSet`
- `built-ins/Proxy`
- `language/eval-code`
- `$262.createRealm` harness smoke cases

Observability should stay explicit. Avoid invisible flows where a helper depends
on ambient current interpreter state.

## 8. Functional And Non-Functional Risk Analysis

Functional risks:

- Symbol identity and well-known symbol lookup can regress if realm migration
  changes initialization order.
- Prototype and iterator caches can regress `instanceof`, iteration, RegExp
  symbol methods, or `Object.prototype.toString`.
- Backing-store migration can regress ArrayBuffer detach, DataView, TypedArray,
  WeakMap, or WeakSet behavior.
- Replacing construction context globals can regress built-in constructors that
  distinguish call from construct.

Non-functional risks:

- Per-realm state can allocate more than module-global state. Use lazy
  initialization for caches and stores that are not always needed.
- More explicit context threading can add short-term code churn.
- Public runtime cleanup can inconvenience downstream users who depend on
  undocumented internals.

Expected improvements:

- Better isolation for multiple interpreters and realms.
- Lower blast radius for future stdlib and runtime changes.
- Clearer ownership of side effects and object backing stores.
- Safer execution optimization path.

## 9. Trade-Offs And Alternatives

**Chosen: targeted realm/state extraction.**  
Solves the confirmed pressure with lower risk than a broad rewrite. Adds a
state container and migration churn, but avoids disturbing parser, AST, CLI, and
the existing runtime/stdlib split.

**Alternative: document single-realm assumptions.**  
Lower implementation cost, but conflicts with existing APIs that already expose
multiple interpreters and realm creation.

**Alternative: split all runtime internals now.**  
May improve package hygiene, but does not by itself fix state ownership. Defer
until ownership is clearer.

**Alternative: expand closure conversion.**  
Useful for benchmarks, but broad expansion risks duplicating JavaScript
semantics. Prefer a compact bytecode/IR direction with shared runtime
operations.

## 10. Scope Definition

Included:

- Realm and interpreter state ownership.
- Mutable global removal or containment.
- Runtime public-surface reduction.
- Compiler/runtime execution boundary.
- Verification gates for multi-interpreter safety.

Excluded:

- Parser/AST redesign.
- New JavaScript language features.
- Full rewrite.
- CLI redesign.
- Hand-editing Test262 headline numbers.
- Performance optimization without a reproducing benchmark.

## 11. Constraints And Unknowns

Constraints:

- MoonBit package boundaries, not file names, enforce visibility.
- `internal/` packages can protect downstream users from importing internals,
  but code inside the same module can still import them.
- Generated `.mbti` files must be regenerated with `moon info`, not edited
  manually.
- The root public facade should remain stable.

Unknowns:

- How many downstream users directly import `interpreter/runtime`.
- Whether some module-global caches were intentionally shared for allocation
  reasons.
- Exact performance impact of per-realm storage until measured.
- Whether all current realm isolation bugs are observable through unit tests or
  require targeted Test262 harness cases.

## 12. Recommended Next Steps

Completed:

1. Add Stage 0 tests and static audits.
2. Add `RealmState` as an interpreter-owned container without moving behavior.
3. Move well-known symbol allocation into realm-owned state.
4. Migrate no-argument well-known symbol lookup paths to explicit realm-owned
   access and remove the temporary compatibility path.
5. Move the iterator/prototype caches used by protocol lookup into
   `RealmState` in PR #133.
6. Move runtime factory prototype refs into `RealmState` in PRs #134 and #135.
7. Move stdlib Promise and RegExp prototype refs, plus dependent runtime
   prototype read paths, into `RealmState` through PRs #136 through #146.
8. Move WeakMap / WeakSet side-table storage into `RealmState` in PR #147.
9. Move ArrayBuffer backing stores, id counter, and detach state into
   `RealmState`.

Current audit inventory:

`make architecture-state-audit` reports 2 classified bindings: `current_interpreter` and `is_constructing`.

Remaining:

1. Replace ambient construction/current-interpreter context with explicit
   context.
2. Only then reduce runtime public API surface and consider internal package
   extraction.
3. Keep closure conversion frozen as an opt-in benchmark path while the
   bytecode/IR prototype grows around shared runtime operations.

## Evidence Checked

This note was based on current package manifests, public `.mbti` surfaces,
MoonBit outlines, architecture docs, roadmap notes, and direct inspection of
runtime/stdlib/compiler files. Important source areas include:

- `moon.pkg` manifests for package dependency direction.
- `interpreter/runtime/interpreter.mbt` for interpreter-owned state.
- `interpreter/runtime/stdlib_hooks.mbt` and `interpreter/wiring.mbt` for the
  runtime/stdlib callback boundary.
- `interpreter/runtime/symbols.mbt`, `interpreter/runtime/factories.mbt`, and
  `interpreter/runtime/iterators.mbt` for mutable intrinsic refs.
- `interpreter/runtime/conversions.mbt` for current-interpreter fallback.
- `interpreter/stdlib/builtins_symbol.mbt`, `builtins_arraybuffer.mbt`,
  `builtins_weakmap_set.mbt`, `builtins_map_set.mbt`,
  `builtins_promise.mbt`, and `builtins_regex.mbt` for stdlib-owned mutable
  state.
- `compiler/closure_conversion.mbt` and
  `docs/closure-conversion-and-bytecode.md` for the execution optimization
  boundary.
