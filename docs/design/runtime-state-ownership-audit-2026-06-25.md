# Runtime State Ownership Audit — 2026-06-25

Tracking note for issue #245 and PR1 of #392. This is an implementation inventory, not a principles document; keep the higher-level architecture docs focused on boundaries and use this note for concrete ownership mapping.

## Audit result

The module-level mutable-state inventory is empty:

- `scripts/architecture_state_classified_mutable_state.json` is `{}`.
- `make architecture-state-audit` reports `0 classified bindings` for `interpreter/runtime` and `interpreter/stdlib`.
- New runtime or stdlib module-level `let` bindings with mutable types (`Ref`, `Map`, `Array`) must either move behind an explicit owner or be classified with a process-global rationale and test-isolation note.

The full architecture audit remains the PR gate; this audit does not add runtime/stdlib mutable-state inventory entries.

## Current owner map

| State category | Current owner | Lifecycle and notes |
|---|---|---|
| Realm intrinsics, well-known symbols, prototype refs, realm-scoped side tables | `RealmState` and nested records such as `SymbolState` | Per realm/interpreter. Lazy intrinsic caches and backing stores belong here or in explicit nested records, not module globals. |
| Host queues, console output, timers, cancellation bookkeeping, module loading callback | `HostEnv` | Per interpreter host environment. Hosts drive checkpoints explicitly; timer and microtask state stays behind the host record. |
| Per-call execution facts | `ExecContext` where immutable and threaded; named frame records or explicit `Interpreter` fields when mutation is required | `strict` and generator context already use `ExecContext`. The parameter-default direct-eval conflict flags are explicit transient `Interpreter` fields and should move only with focused tests. |
| Lexical/environment state and metadata markers | `Environment` | Scope-chain owned. Environment markers remain out of JavaScript bindings via the dedicated marker map; #439 is conditional if marker kinds grow. |
| Module graph and module-evaluation state | `Interpreter` today; future async/module jobs should use explicit module-job records owned by the interpreter or host | `module_registry` is interpreter-owned. Transient export maps/bindings are interpreter fields rather than ambient globals. |
| Generator object registry and generator IDs | `Interpreter` | Per interpreter. No process-global generator registry. |
| Stdlib dispatch bridge | `StdlibHooks` stored on `Interpreter` | Wiring-layer function table; not mutable module state in runtime or stdlib. |
| Template object cache | `Interpreter` methods, stored as an internal global binding | Per interpreter/global lifetime, as required for tagged templates. Access stays behind `Interpreter::get_cached_tagged_template_object`. |
| Other caches | Owning semantic record plus explicit lifetime policy | Realm-lifetime caches belong in `RealmState`; host caches in `HostEnv`; feature caches need an owner and invalidation/lifetime note before landing. |

## Future-work checklist

Before adding mutable runtime or stdlib state:

1. Name the owner record (`RealmState`, `HostEnv`, `ExecContext`, `Environment`, `Interpreter`, or a new focused record).
2. State the lifecycle: realm, host, interpreter, call/frame, module job, or process.
3. For caches, state invalidation and isolation behavior.
4. Prefer one named record over scattered booleans/maps when a feature has multiple related fields.
5. Avoid module-level mutable state. If unavoidable, classify it in `scripts/architecture_state_classified_mutable_state.json` with why it is truly process-global and how tests isolate it.
6. Run `make architecture-state-audit` and the full `make architecture-audit` before review.

## Findings

No behavior-changing ownership move is required for this audit. The current code keeps mutable runtime/stdlib state behind explicit owner records, and the audit inventory remains empty. The remaining pressure is documentation and future-feature discipline, especially for module jobs, caches, and per-evaluation state.
