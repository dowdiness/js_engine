# Stable Engine diagnostic contract

Date: 2026-07-24

## Status

Accepted and implemented by the root facade's additive detailed operations.
The existing `EngineError` surface remains unchanged. Source locations remain
absent until trustworthy parser/runtime location propagation is implemented.

## Context

The stable root facade currently reports failures through `EngineError`. Its
six public variants each carry only a `String`. That surface distinguishes
broad failure categories, but it cannot report which operation failed, attach
source identity without changing a variant payload, or distinguish a reusable
synchronous JavaScript exception from a JavaScript exception raised during a
checkpoint that requires the host to discard the `Engine`.

The [root facade](../../js_engine.mbt) and its
[generated interface](../../pkg.generated.mbti) define the current surface.
Behavior evidence comes from the
[Engine characterization tests](../../engine_test.mbt), the standalone
[external-consumer fixture](../../integration/external_consumer/), and the
existing [synchronous failure](engine-failure-reuse-matrix.md) and
[checkpoint failure](engine-checkpoint-failure-matrix.md) records.

The public contract must remain independent of parser, interpreter,
runtime-value, and queue representations.

## Decision summary

Add a new detailed operation surface that returns an opaque structured
`EngineDiagnostic`. Keep `EngineError`, all of its variants and payloads, and
every existing operation signature unchanged.

A diagnostic contains separate facts for failure kind, public entry operation,
failure phase, source context, Engine integrity, retained effects, and pending
jobs. Failure kind alone never determines the other fields. In particular, a
`javascript-exception` from `eval` can report `reusable`, while the same kind
from a microtask or timer checkpoint reports `discard`.

The diagnostic is a report about the completed failed operation. It is not a
retry token, a rollback record, or permission to continue using an Engine that
reports `discard`.

## Public API evolution

### Alternatives considered

| Alternative | Compatibility and contract result |
|---|---|
| Expand the payloads of existing `EngineError` variants | Rejected. Code constructing or matching variants such as `ParseError(String)` would no longer type-check. The current generated interface exposes those payloads. |
| Keep `EngineError` and retrieve a diagnostic from the Engine after an existing operation fails | Rejected as the primary surface. An out-of-band "last diagnostic" can be overwritten, cannot atomically pair a failure with its diagnostic, and cannot serve one-shot operations that expose no persistent Engine. Deriving a diagnostic from `EngineError` alone also loses operation context. |
| Add a detailed operation surface and retain all existing operations as a compatibility surface | Selected. Existing source keeps compiling and observing the same errors. New callers opt into a result that carries the complete operation-aware diagnostic. |

The selected design is additive: it adds types and entry points but does not add
variants to `EngineError`, alter its payloads, or change the raised error type of
an existing method. Adding a variant to the current public error must not be
called source-compatible: downstream exhaustive pattern matches can stop
compiling.

### Conceptual shape

The public type and accessor shape is fixed by this decision:

```moonbit nocheck
pub struct EngineDiagnostic
pub struct SourcePosition
pub struct SourceLocation

pub(all) enum EngineIntegrity {
  Reusable
  Discard
  Unknown
  NotApplicable
}

pub(all) enum RetainedEffects {
  None
  MayRemain
  Unknown
}

pub(all) enum PendingJobs {
  None
  Present
  Unknown
}

pub fn EngineDiagnostic::failure_kind_code(Self) -> String
pub fn EngineDiagnostic::message(Self) -> String
pub fn EngineDiagnostic::operation_code(Self) -> String
pub fn EngineDiagnostic::phase_code(Self) -> String
pub fn EngineDiagnostic::source_identity(Self) -> String?
pub fn EngineDiagnostic::source_location(Self) -> SourceLocation?
pub fn EngineDiagnostic::engine_integrity(Self) -> EngineIntegrity
pub fn EngineDiagnostic::retained_effects(Self) -> RetainedEffects
pub fn EngineDiagnostic::pending_jobs(Self) -> PendingJobs

pub fn SourceLocation::start(Self) -> SourcePosition
pub fn SourceLocation::end(Self) -> SourcePosition?
pub fn SourcePosition::line(Self) -> Int
pub fn SourcePosition::column(Self) -> Int
pub fn SourcePosition::offset(Self) -> Int

pub fn Engine::eval_diagnostic(
  Self,
  source : String,
  source_id? : String,
) -> Result[Unit, EngineDiagnostic]

pub fn Engine::call_json_diagnostic(
  Self,
  name : String,
  args : Array[Json],
) -> Result[Json, EngineDiagnostic]

pub fn Engine::run_microtask_checkpoint_diagnostic(
  Self,
) -> Result[Bool, EngineDiagnostic]

pub fn Engine::run_timer_checkpoint_diagnostic(
  Self,
) -> Result[Unit, EngineDiagnostic]

pub fn run_diagnostic(
  source : String,
  source_id? : String,
  annex_b? : Bool,
) -> Result[(Array[String], String), EngineDiagnostic]
```

`EngineDiagnostic`, `SourcePosition`, and `SourceLocation` are opaque. Consumers
read them through the listed accessors; their construction and representation
are not part of the stable contract.

The existing `Engine::eval(source)` remains source- and behavior-compatible and
acts as evaluation without a source identity. Existing methods may share
private implementation with the detailed methods, but their current
`EngineError` values and messages must not change accidentally.

### Evolution rules

Failure kinds, operations, and phases are open vocabularies exposed by accessors
as stable string codes. Callers compare known codes and must retain a fallback
for an unrecognized code. This allows execution-limit, interruption,
stack-depth, callback, and re-entry failures to join the same model without
adding a public enum variant that breaks exhaustive matching.

Engine integrity, retained effects, and pending jobs use the three public enums
shown above. Their value sets and variants are closed and frozen by this
decision. Adding a variant is a source-breaking change because it can break a
downstream exhaustive match. A future state that does not fit an existing value
requires a new compatibility decision rather than an enum extension described
as additive.

## Portable diagnostic semantics

Every detailed failure provides these fields:

| Field | Contract |
|---|---|
| Failure kind | A stable machine-readable code. Initial codes are `parse-error`, `javascript-exception`, `missing-global`, `not-callable`, `json-conversion-error`, `internal-error`, and `unknown`. |
| Message | A useful human-readable message. Its presence is portable; exact wording, value rendering, and punctuation are not classification APIs. |
| Operation | A stable code for the public operation whose boundary returns the diagnostic. Initial codes are listed below. |
| Phase | A stable code for the phase within that operation where the failure was observed. Initial codes are listed below. |
| Source identity | Optional host-supplied identity for attributable source. It is copied and returned unchanged. |
| Source location | Optional start position and optional end position within the identified source. |
| Engine integrity | Exactly one of `EngineIntegrity::Reusable`, `EngineIntegrity::Discard`, `EngineIntegrity::Unknown`, or `EngineIntegrity::NotApplicable`. |
| Retained effects | Exactly one of `RetainedEffects::None`, `RetainedEffects::MayRemain`, or `RetainedEffects::Unknown`. |
| Pending jobs | Exactly one of `PendingJobs::None`, `PendingJobs::Present`, or `PendingJobs::Unknown`. |

Initial operation codes are `eval`, `call-json`, `microtask-checkpoint`,
`timer-checkpoint`, and `run`. Initial phase codes are `parse`, `lookup`,
`argument-conversion`, `execute`, `result-conversion`, `microtask-dispatch`,
`timer-dispatch`, `timer-callback`, `timer-microtask-checkpoint`, and
`interval-callback`.

The operation records the host-visible entry point. The phase records the
failing work within it. For example, a microtask failure reached from
`Engine::run_timer_checkpoint` reports operation `timer-checkpoint` and phase
`timer-microtask-checkpoint`; the corresponding one-shot failure reports
operation `run` and the same phase. Implementations must not collapse these two
axes into an error-kind-only mapping.

`timer-dispatch` identifies an unexpected failure while selecting or advancing
the timer queue policy, before the failure can be attributed to a timer,
interval, or timer-following microtask callback. It is distinct from
`timer-callback` and `interval-callback`, and therefore reports no callback
source identity.

An implementation may carry additional target-dependent detail separately,
such as a rendered stack trace. That detail must not change the portable kind,
operation, phase, source coordinates, or state fields. Tests compare portable
fields, not rendered messages or stack traces, across native, JavaScript, Wasm,
and Wasm-GC.

### State-field meanings

- `reusable`: runtime invariants remain valid and the public contract permits
  later operations on the same Engine. It does not promise rollback, idempotent
  retry, or that repeating the failed operation is safe.
- `discard`: the host must stop using the Engine. It does not claim that every
  internal field is known to be corrupted; it expresses the supported host
  action.
- `unknown`: available evidence cannot establish the Engine state or it is not
  safe to inspect it.
- `not-applicable`: the failed operation exposes no persistent Engine to the
  caller.
- `none` retained effects: the failed operation performed no observable
  JavaScript or host effect before failing. It does not mean that an older
  Engine has no state.
- `may-remain`: observable work may have completed and is not rolled back.
- Pending `none` or `present` is a snapshot of both Engine job queues at the
  failure boundary. It is not inferred from failure kind. `unknown` is used
  when the state was not characterized or cannot safely be inspected.

Engine integrity alone governs whether a persistent Engine may be used again.
A host must treat `unknown` conservatively: it must stop using and discard the
Engine, as it does for `discard`. The values remain distinct because `discard`
records a characterized host policy, while `unknown` records that safe reuse
could not be established. Retained effects and pending jobs are descriptive;
their values never authorize reuse or retry and never override Engine
integrity. For `not-applicable`, there is no persistent Engine to discard.

## Source identity and location

The host supplies source identity as an optional opaque string on the
source-aware detailed evaluation entry point. The runtime does not interpret it
as a path or URL. The identity must remain associated with code originating
from that evaluation so a later `call_json` or checkpoint diagnostic can return
it when the runtime has retained a trustworthy association.

For lookup, execution, and callback failures, the implementation reports the
deepest attributable function whose unchanged error reaches the public
operation boundary. An error caught by JavaScript does not determine a later,
different failure's identity. Code loaded through identity-free evaluation
also does not inherit an identified caller's source. Result-conversion failures
omit source identity because the runtime does not yet retain provenance for the
returned value itself.

The existing `Engine::eval(source)` remains unchanged and supplies no identity.
The new entry point does not require identity: omitting it is equivalent to the
existing behavior for source attribution.

Portable coordinates use the following convention, matching the current lexer
coordinate model:

- lines are 1-based;
- columns are 1-based counts of Unicode scalar values from the start of the
  line;
- absolute offsets are 0-based counts of UTF-16 code units from the start of
  the source;
- a start position is inclusive; and
- an end position, when present, is exclusive.

A location is present only when it can be attributed to the reported source
identity, or to the anonymous source supplied directly to the failed detailed
operation. A source identity may be present while location is absent. If a
failure comes from generated code, a host callback, an internal invariant, or
another source that cannot be attributed faithfully, source identity and
location are omitted as appropriate.

Today, parser failures are converted to strings and runtime JavaScript errors
and thrown values do not carry a structured source location through the
`Engine` boundary. The first implementation must therefore omit unavailable
locations. It must not parse line or column text out of messages, inspect a
target-specific stack string, or guess from the current instruction. Later
location work requires the parser and runtime to preserve structured positions
explicitly.

## Current failure matrix

This table maps every current path into the future portable fields. "Dynamic"
means the diagnostic must snapshot the actual state; it is not a fixed
property of the kind. Locations are omitted today for all rows because the
current `Engine` boundary does not retain a trustworthy structured location.

| Current failure path | Kind | Operation | Phase | Source identity | Engine integrity | Retained effects | Pending jobs | Evidence |
|---|---|---|---|---|---|---|---|---|
| `ParseError` from `Engine::eval` | `parse-error` | `eval` | `parse` | Host identity when supplied; otherwise omitted | `reusable` | `none` | Dynamic; prior jobs can be `present` | Root facade; "parse failure keeps prior state and queues" test |
| `JavaScriptException` from `Engine::eval` | `javascript-exception` | `eval` | `execute` | Host identity when supplied; otherwise omitted | `reusable` | `may-remain` | Dynamic | "eval throw retains state and queues" test |
| `JavaScriptException` from `Engine::call_json` | `javascript-exception` | `call-json` | `lookup` or `execute` | Origin identity only when retained faithfully; otherwise omitted | `reusable` | `may-remain` | Dynamic | Lookup-throw and call-throw tests |
| `MissingGlobal` | `missing-global` | `call-json` | `lookup` | Omitted | `reusable` | `none` | Dynamic; an empty queue is `none`, and a prior microtask is `present` | Empty-queue reuse and pending-microtask preservation tests |
| `NotCallable` | `not-callable` | `call-json` | `lookup` | Omitted | `reusable` | `may-remain` because an accessor may have run | Dynamic; an empty queue is `none`, and a prior or accessor-enqueued microtask is `present` | Direct-value reuse and pending-microtask preservation tests; accessor-enqueued microtask test |
| Argument `JsonConversionError` | `json-conversion-error` | `call-json` | `argument-conversion` | Omitted | `reusable` | `may-remain` because lookup precedes conversion | Dynamic | Direct JSON bridge; argument-conversion reuse test |
| Result `JsonConversionError` | `json-conversion-error` | `call-json` | `result-conversion` | Omitted until returned-value provenance is retained faithfully | `reusable` | `may-remain` | Dynamic | Direct JSON bridge; result-conversion reuse test |
| `InternalError` | `internal-error` | The public entry operation | The phase that observed it | Only when attribution is trustworthy | `discard` | `unknown` | `unknown` | Runtime classifier; recovery is explicitly unsupported |
| Microtask checkpoint failure | Usually `javascript-exception` | `microtask-checkpoint` | `microtask-dispatch` | Callback origin only when retained faithfully | `discard` | `may-remain` | Dynamic | Microtask checkpoint characterization |
| Timer queue dispatch failure | `internal-error` | `timer-checkpoint` | `timer-dispatch` | Omitted because no callback origin is attributable | `discard` | `unknown` | `unknown` | Root diagnostic adapter classification test |
| Timer callback failure | Usually `javascript-exception` | `timer-checkpoint` | `timer-callback` | Callback origin only when retained faithfully | `discard` | `may-remain` | Dynamic | Timer callback characterization |
| Microtask failure after a timer | Usually `javascript-exception` | `timer-checkpoint` | `timer-microtask-checkpoint` | Callback origin only when retained faithfully | `discard` | `may-remain` | Dynamic | Timer-following-microtask characterization |
| Interval callback failure | Usually `javascript-exception` | `timer-checkpoint` | `interval-callback` | Callback origin only when retained faithfully | `discard` | `may-remain` | Dynamic | Interval characterization |
| One-shot facade failure with no persistent Engine | Best available current category; `unknown` only when no structural classification exists | `run` | The matching phase, preserving timer and microtask context | Host identity on the future detailed entry point | `not-applicable` | `none` for parse; `may-remain` for execution; otherwise `unknown` until characterized | `unknown` | Current `run` creates and retains no Engine for the host |

"Usually `javascript-exception`" preserves the current path while allowing a
future internal invariant failure during the same operation to use
`internal-error`. The operation and phase remain the checkpoint context; they
must not be collapsed into the kind.

The missing-global and not-callable characterization establishes the dynamic
queue snapshot through the public Engine facade. With no pending work, both
diagnostics report `none` and the Engine remains usable. A pre-existing
microtask makes either diagnostic report `present`; lookup does not consume the
job, and an explicit checkpoint runs it afterward. A global accessor that
enqueues a microtask before returning a non-callable value likewise reports
`present`, preserves the job after failure, and remains usable for the explicit
checkpoint. The same tests pass on native, JavaScript, Wasm, and Wasm-GC. The
one-shot facade still needs phase-specific characterization if its
retained-effects field is to be narrowed.

## Error-model evolution

Future failures extend the same diagnostic fields:

| Future failure | Failure kind | Operation, phase, and state rules |
|---|---|---|
| Execution-limit exhaustion | `execution-limit` | Preserve the active public operation and phase in which the limit was observed. Effects are `may-remain`; integrity requires characterization before it can be `reusable`. |
| Interruption | `interrupted` | Preserve the active public operation and observation phase. Effects are `may-remain`; integrity requires characterization. |
| Recursion or stack-depth limit | `stack-depth-limit` | Preserve the active public operation and phase. Effects and integrity require direct characterization. |
| Synchronous host callback failure | `host-callback` | Preserve the active outer public operation and use phase `host-callback`, together with attributable JavaScript call-site context when available. Effects and pending jobs reflect work completed on both sides of the boundary. |
| Same-Engine re-entry rejection | `reentry-rejected` | Report the attempted re-entry operation and phase `reentry-check`. A rejection before re-entered JavaScript runs can report `none` for that rejected attempt only after characterization. |
| Internal invariant failure | `internal-error` | Preserve the observing public operation and phase, report `discard` integrity, and use `unknown` effects/jobs unless safe evidence establishes more. |

Adding these open kind, operation, or phase codes does not require a second
diagnostic type or a new public enum variant. A re-entry diagnostic describes
the rejected attempt. If that rejection escapes a host callback, the enclosing
diagnostic still reports its outer operation with phase `host-callback`; it does
not replace the outer context with the attempted operation. Each feature still
needs cross-target classification and state tests before replacing `unknown`
with a stronger value.

## Implemented delivery

The first implementation:

1. added the opaque diagnostic and source-location types, the three frozen state
   enums, accessors, stable codes, and the parallel detailed operations;
2. preserved all existing `EngineError` signatures and behavior;
3. attached optional source identity without inventing a location;
4. captured operation and phase before the current error classification loses
   them;
5. reported the initial matrix values, retaining `unknown` where evidence was
   missing; and
6. added equivalent classification tests on native, JavaScript, Wasm, and
   Wasm-GC, including an external-consumer use of the new surface.

The subsequent missing/not-callable queue follow-up completed the dynamic
snapshot characterization described in the matrix without changing queue
execution or checkpoint policy. Parser/runtime location propagation and
one-shot retained-effects characterization remain separate follow-ups. In
particular, the first implementation's one-shot retained-effects values must
not be narrowed without phase-specific evidence.

## Consequences

- Existing consumers can continue to catch and pattern-match `EngineError`.
- New consumers receive one atomic result containing kind, operation, phase,
  and state without consulting runtime internals.
- Checkpoint diagnostics continue to say `discard` even when a diagnostic probe
  can observe queues or make another call.
- Messages remain useful for people without becoming the machine-readable
  protocol.
- Opaque diagnostic/location types, open kind/operation/phase codes, and frozen
  state enums make the intended compatibility boundary explicit.

## Non-goals

This implementation does not change:

- `EngineError` variants, payloads, formatting, or behavior;
- parser or runtime error representations;
- execution budgets, interruption, or recursion limits;
- host callbacks or same-Engine re-entry;
- checkpoint retry guarantees, a poisoned Engine state, or rollback;
- the stable exposure of raw `Interpreter` or `Value`; or
- a portable stack-trace format.
