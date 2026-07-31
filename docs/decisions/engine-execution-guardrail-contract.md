# Stable Engine execution guardrail contract

Date: 2026-07-26

## Status

Accepted for staged implementation. Private execution-control state transitions
and statement/expression dispatch observation are implemented internally. The
bounded operations, complete execution accounting, stack-depth wiring, and
public interruption control described here are not available yet. Existing
operations remain unbounded.

## Context

The stable `Engine` facade lets a host evaluate source, call synchronous
JSON-boundary functions, and explicitly advance microtask and timer queues. The
[embedding guide](../EMBEDDING.md) currently states that it provides neither an
execution budget nor interruption. The [roadmap](../ROADMAP.md) requires the
execution contract to be decided before the Stage 4 implementation and before
synchronous host capabilities are added in Stage 5.

The current execution paths do not pass through one universal helper:

- evaluation dispatches statements and expressions and can enter functions,
  constructors, property accessors, Proxy traps, generators, and native
  implementations of JavaScript built-ins;
- `call_json` performs global lookup before argument conversion, so lookup can
  execute a getter before the target function is called;
- a microtask checkpoint consumes each selected job before calling it; and
- a timer checkpoint consumes a timer or interval, calls it, and then runs a
  microtask checkpoint before selecting the next timer.

Function calls are widely reached from built-ins as well as expressions.
Constructors and generator body start or resume have distinct execution paths.
Runtime and standard-library algorithms also contain loops whose amount of
work is controlled by JavaScript values and which need not re-enter statement
or expression dispatch on every iteration. The implementation must therefore
install a shared execution-control context at all of the semantic observation
points defined below; it must not assume that instrumenting one current helper
covers all JavaScript work.

This decision extends the existing
[diagnostic contract](engine-diagnostic-contract.md),
[synchronous failure baseline](engine-failure-reuse-matrix.md), and
[checkpoint failure policy](engine-checkpoint-failure-policy.md). It does not
replace any of them.

## Decision summary

Add an immutable execution policy that is supplied to a new bounded variant of
each persistent `Engine` operation that can execute JavaScript. A bounded
operation creates one fresh execution-control context from that policy. The
context owns a remaining-step counter and active JavaScript-frame depth and
observes a host-owned interruption request.

The first bounded surface covers:

- evaluation with structured diagnostics;
- JSON-boundary call with structured diagnostics;
- microtask checkpoint with structured diagnostics; and
- timer checkpoint with structured diagnostics.

The policy is passed for each operation; it is not a default captured by the
Engine and is not mutable Engine configuration. The bounded variants return the
existing `EngineDiagnostic` model.

The public shape is fixed by this decision:

```moonbit nocheck
pub struct ExecutionPolicy
pub struct ExecutionPolicyError
pub struct InterruptionHandle

pub fn InterruptionHandle::InterruptionHandle() -> InterruptionHandle
pub fn InterruptionHandle::request(Self) -> Unit
pub fn InterruptionHandle::is_requested(Self) -> Bool

pub fn ExecutionPolicy::new(
  step_budget : Int64,
  stack_depth_limit : Int64,
  interruption : InterruptionHandle,
) -> Result[ExecutionPolicy, ExecutionPolicyError]

MoonBit constructor naming correction for #702: the public constructor is
`ExecutionPolicy::new(...)`; `ExecutionPolicy::ExecutionPolicy(...)` is not a
valid callable constructor form for this struct shape.

pub fn ExecutionPolicyError::parameter_code(Self) -> String
pub fn ExecutionPolicyError::message(Self) -> String

pub fn Engine::eval_bounded(
  Self,
  source : String,
  policy : ExecutionPolicy,
  source_id? : String,
) -> Result[Unit, EngineDiagnostic]

pub fn Engine::call_json_bounded(
  Self,
  name : String,
  args : Array[Json],
  policy : ExecutionPolicy,
) -> Result[Json, EngineDiagnostic]

pub fn Engine::run_microtask_checkpoint_bounded(
  Self,
  policy : ExecutionPolicy,
) -> Result[Bool, EngineDiagnostic]

pub fn Engine::run_timer_checkpoint_bounded(
  Self,
  policy : ExecutionPolicy,
) -> Result[Unit, EngineDiagnostic]
```

The three public types are opaque. An `InterruptionHandle` is a shared,
monotonic request cell: copying the handle or a policy aliases the same request
state, `request` is idempotent, and a requested handle cannot be cleared. A host
that needs a clear request creates a new handle and policy. This prevents one
consumer from withdrawing an interruption already requested by another and
avoids an active-operation clear race.

The existing unbounded `eval`, `call_json`, checkpoint, and diagnostic methods
retain their current signatures and behavior. `run`, `run_diagnostic`,
`inject_json`, compatibility APIs, and advanced/internal execution APIs do not
gain implicit limits in the first implementation. A separately named bounded
one-shot operation would require its own explicit queue-drain scope.

## Policy values and validation

The policy contains three inputs:

1. a step budget;
2. a maximum active JavaScript-frame depth; and
3. an interruption request handle, initially either clear or requested.

Both numeric inputs are accepted as `Int64` and use the portable non-negative
range `0` through `2,147,483,647`, inclusive. Policy construction returns an
opaque `ExecutionPolicyError` for a negative value or a value above that
ceiling before an Engine operation starts. `parameter_code` is `step-budget`
or `stack-depth`; the message is human-readable but its exact wording is not a
classification API. Invalid policy construction is not `execution-limit` or
`stack-depth-limit`, and cannot execute JavaScript, select a queue job, or
change Engine state.

The runtime stores the step budget as **remaining** steps. At a charge point it
first checks whether the value is zero; if so, it raises `execution-limit`
without changing the counter or starting the guarded action. Otherwise it
subtracts exactly one and continues. The counter never increments, so neither
the consumed count nor arithmetic overflow is part of the contract. A zero
budget permits an operation that reaches no charge point, such as an empty
checkpoint, but rejects the first attempted JavaScript or queue-dispatch step.

The frame-depth value is also checked without arithmetic overflow: an entry is
rejected when the current active depth equals the configured maximum; only a
permitted entry increments the active depth, and every normal or abrupt exit
decrements it. A depth limit of zero permits top-level execution but rejects
the first JavaScript call, construct, or generator-body activation.

The fixed ceiling uses operations with exact integer behavior on native,
JavaScript, Wasm, and Wasm-GC. Larger counters, saturating counters, wrapping
counters, and target-dependent numeric ranges are rejected.

## Deterministic step model

One execution step is one successful passage through any of these observation
points:

1. before dispatching an ECMAScript statement node;
2. before dispatching an ECMAScript expression node;
3. before entering a JavaScript-visible call, construct, or generator-body
   start/resume activation;
4. before selecting and consuming a microtask job, and before inspecting and
   popping each timer or interval queue entry, including a cancelled entry; or
5. at the header of every iteration of an execution-time runtime or
   standard-library algorithm whose iteration count is controlled by
   JavaScript values, object shape, collection size, iterator results,
   regular-expression input, or another script-observable condition, when that
   iteration is not already guaranteed to cross one of points 1 through 4.

Each applicable point costs one step even when multiple categories occur close
together. For example, a call expression costs its expression-dispatch step
and, if the call is entered, its activation step. A queued callback costs a
queue-entry dispatch step and then a call-activation step. A cancelled timer
entry costs only its queue-entry step because no callback is entered. This
deliberate accounting makes the queue states around exhaustion unambiguous.

The fifth category closes native-loop bypasses. It includes JavaScript
built-ins and runtime algorithms such as iterator and array-like traversal,
property or prototype traversal, dynamic `eval` execution after parsing, and
regular-expression processing when their work is script-controlled. It
excludes parsing and fixed-size runtime bookkeeping that cannot grow with
script input. The implementation must audit runtime and standard-library loop
back-edges and demonstrate that no unbounded or script-controlled execution
path can continue indefinitely without reaching an observation point.

The unit is deterministic for a given engine version and must produce the same
limit decision on all four supported targets. It is not elapsed time, an
ECMAScript-spec operation count, or a promise that an implementation refactor
will preserve the exact step count across releases. Hosts should treat a
budget as an availability bound with headroom, not as a portable performance
measurement.

Wall-clock time is not a budget unit because scheduling, clock resolution,
garbage collection, host load, and JavaScript/Wasm embedding differ by target.
A time budget would make the same program fail at different points and would
not provide deterministic retained-state or queue semantics.

## Check order at an observation point

Observation uses this fixed precedence:

1. if the interruption request is visible as requested, fail with
   `interrupted`;
2. at a call, construct, or generator activation, reject a frame that would
   exceed the stack-depth limit with `stack-depth-limit`; and
3. if no step remains, fail with `execution-limit`; otherwise charge one step.

The guarded statement, expression, activation, queue selection, or loop
iteration starts only after all applicable checks pass. This order determines
the failure kind when more than one limit is simultaneously eligible and does
not change across targets.

## Public-operation scope

Every bounded public call creates and clears exactly one execution-control
context. Remaining steps never carry into the next host call.

| Bounded operation | Reset point and included work | Excluded work |
|---|---|---|
| Evaluation | Reset after the host source has parsed successfully and immediately before program execution. Includes all JavaScript work reached from that program, including functions, accessors, Proxy traps, constructors, generators, JavaScript built-ins, and execution of code produced by dynamic `eval`. | Parsing, including parsing source supplied to direct or indirect JavaScript `eval`. A host-source parse failure remains `parse-error` and consumes no execution steps. |
| JSON-boundary call | Reset immediately before global lookup. Includes a lookup getter, argument-dependent coercion performed by JavaScript execution, the target call, and all nested JavaScript work. The same counter continues across lookup and call. | Direct host-`Json` to realm conversion and direct result-to-`Json` conversion. These conversions remain non-executing boundary work. |
| Microtask checkpoint | Reset at checkpoint entry. The first charge occurs only when a pending job is about to be selected. The one counter covers every dispatched microtask and all JavaScript and script-controlled built-in work reached by them. | Empty-queue detection and private queue bookkeeping that is fixed-size and not script-controlled. |
| Timer checkpoint | Reset at checkpoint entry. One counter covers every timer or interval queue entry inspected, including cancelled entries, every eligible callback, and every timer-following microtask checkpoint. It is not reset per queue entry, callback, or nested microtask checkpoint. | Detection that the physical timer queue is empty and fixed-size private queue bookkeeping. |

`eval` and `call_json` still do not run microtasks or timers implicitly. A
bounded checkpoint runs only the queue named by its existing contract; the
timer checkpoint continues to include the existing microtask checkpoint after
each timer. Parsing and direct host JSON conversion are outside the execution
budget, so a bounded operation is not an end-to-end wall-clock or input-size
bound.

## Private staged carrier and re-entry boundary

During staged implementation, statement and expression dispatch need access to
one mutable execution-control context without changing the generated shape of
`Interpreter` or `ExecContext`, exposing the private control type, or adding
module-level mutable state. The current private wiring therefore uses a
reserved binding in the interpreter-owned global environment as an internal
carrier. The binding stores only an internal observation capability; it is not
a `globalThis` property, a JavaScript-visible host binding, persistent Engine
configuration, or part of the public contract.

The carrier has operation scope. Installing it saves any previous internal
binding, and both normal and raised exits restore that previous state. Its
absence is the unbounded state. Because the environment is owned by one
interpreter, separate interpreters do not share the active control. Recursive
statement/expression dispatch and code reached through dynamic `eval` are
continuations of the same operation: they observe the installed control and do
not create or reset a budget.

Same-Engine re-entry means starting another host-visible Engine operation while
an earlier operation on that Engine remains active. The save/restore behavior
also makes a mechanically nested private scope clean up correctly, but that
mechanism does **not** define same-Engine re-entry semantics. In particular, it
does not promise that a host may start another bounded or unbounded Engine
operation while one is active, that an inner policy replaces the outer policy,
or that either budget resets. No public entry point may treat nested
installation as authorization for re-entry. Before host callbacks can initiate
Engine operations, the public operation boundary must explicitly reject or
otherwise decide same-Engine re-entry and test that choice without deriving it
from this private carrier.

## Queue semantics at a guardrail failure

The accepted at-most-once queue policy remains unchanged:

1. for microtasks, a dispatch observation occurs before selection and logical
   consumption;
2. for timers and intervals, a dispatch observation occurs before each queue
   entry is inspected and popped, including an entry marked cancelled;
3. after that observation succeeds, a microtask is consumed or a timer entry is
   popped; a cancelled timer is discarded and the scan continues;
4. an eligible callback's activation observation occurs after consumption and
   before the callback body; and
5. a failure never restores a consumed job or a discarded cancelled entry.

This defines the required boundary cases:

- **Limit or interruption before checkpoint progress.** If the physical queue
  is empty, the checkpoint succeeds without a charge. If an entry is pending
  but the first dispatch observation fails, no entry is selected, inspected, or
  consumed and the queue remains unchanged.
- **Failure immediately before a callback body.** The job-dispatch observation
  succeeded, so the selected job is already consumed. If interruption,
  stack-depth, or step exhaustion rejects callback activation, the callback
  body does not run, the selected job is not restored, and unstarted jobs keep
  their existing order.
- **Failure during a callback.** The selected job remains consumed. Mutations
  and enqueues completed before the failing observation remain. Unstarted and
  newly enqueued jobs keep FIFO microtask order or timer
  `(delay, insertion_order)` order.

Cancelled timer scanning is also non-transactional. Each inspected entry costs
one step before it is popped. If the entry is cancelled, it is discarded and
does not incur a callback-activation step. If a later observation fails,
cancelled entries already discarded are not restored, while the entry whose
observation failed and every later entry remain queued. A queue containing only
cancelled entries therefore succeeds after spending one step per entry; with a
zero budget it fails before discarding the first entry.

The existing timer safety limit remains independent of the execution budget and
continues to count every popped timer entry, including cancelled entries. The
physical-empty and safety-limit checks first decide whether another entry may be
inspected. If so, the dispatch observation checks interruption and execution
budget before the pop; stack depth is not applicable until an eligible callback
activation. If the safety limit stops the scan, the checkpoint returns with its
existing successful result and leaves later timer entries pending. It does not
synthesize a guardrail diagnostic or reset the remaining execution budget.

A failed interval invocation is not re-registered unless its callback and
following microtask checkpoint both completed successfully, exactly as in the
current policy. No guardrail failure rolls back JavaScript-visible mutation,
host-visible output, queue consumption, or enqueue operations completed before
the failure.

## Stack-depth guard

Stack depth is independent of the step budget. It counts active
JavaScript-visible callable, constructor, and generator-body activations, not
MoonBit implementation stack frames and not top-level script execution.

The check occurs before an activation begins. It must cover ordinary and arrow
functions, extended-parameter functions, native and interpreter-backed
built-ins, bound-call targets without double-counting wrapper forwarding,
class and ordinary constructors, Proxy `apply` and `construct` traps,
accessor getters and setters, and generator or async-generator body start and
resume. An activation rejected by the guard cannot bind parameters, allocate a
constructor instance, change generator execution state, or execute body code.

An implementation is accepted only after call and construct dispatch,
accessor and Proxy internal operations, generator entry/resume, and all other
JavaScript call-entry routes have been audited. Tests must show equivalent
depth-limit decisions for direct recursion, getter/setter recursion, Proxy
traps, constructors, and generator resume on native, JavaScript, Wasm, and
Wasm-GC. Instrumenting only the current general call helper is insufficient.

## Cooperative interruption

Interruption is cooperative. The policy references a host-owned request handle
whose requested state is read at every step observation point. Once a request
is visible, the next observation fails as `interrupted` before charging or
starting the guarded action. The handle is monotonic and remains requested for
its lifetime. Starting another operation does not silently clear host intent;
the host must construct a new handle and policy for later non-interrupted work.

The same observation points are used for interruption and step accounting.
There is no separate, less complete interruption path. A pre-requested handle
must therefore interrupt before the first JavaScript or queue-dispatch step on
all four targets, while still allowing an empty checkpoint to return normally
because it reaches no observation point.

The portable implementation is a synchronous state read in target-neutral
runtime code. The contract does not promise that a host can mutate the handle
from an external thread while synchronous JavaScript is running, that such a
write is atomic or immediately visible on every target, or that a browser or
Wasm host can schedule another task during the call. If a target environment
makes a request visible during execution, it is observed at the next point;
the mechanism is still cooperative rather than preemptive. Signals, worker
termination, wall-clock timers, and forced unwinding are not part of this API.

## Structured diagnostics and Engine state

Guardrail failures extend the existing open diagnostic vocabularies. They do
not add an `EngineError` variant or a second diagnostic type.

| Condition | Failure kind |
|---|---|
| No step remains at an observation point | `execution-limit` |
| A callable, constructor, or generator activation would exceed the configured depth | `stack-depth-limit` |
| The interruption request is observed | `interrupted` |

The diagnostic preserves the outer public operation: `eval`, `call-json`,
`microtask-checkpoint`, or `timer-checkpoint`. Its phase is the phase containing
the observation: `execute` for evaluation and target execution;
`lookup` for a `call_json` lookup getter; `microtask-dispatch` for a microtask
dispatch or callback; the new open phase `timer-queue-dispatch` for an expected
guard observation before a timer entry is inspected or popped;
`timer-callback` or `interval-callback` inside those callbacks; and
`timer-microtask-checkpoint` inside the following microtask drain. The existing
`timer-dispatch` phase remains reserved for an unexpected failure while the
timer queue policy selects or advances work. Existing source-identity and
source-location rules continue to apply.

Every guardrail failure reports `RetainedEffects::MayRemain`, including a
failure at the first observation point. This conservative value avoids making
the kind or remaining counter a rollback claim and keeps diagnostics uniform
when prior Engine state or outer work exists.

Pending jobs are determined at the outer operation boundary after control has
unwound. If both queues can be inspected without another runtime failure, the
diagnostic snapshots them as `PendingJobs::None` or `PendingJobs::Present` by
the existing both-queue rule. This snapshot reflects consumption and enqueues
that occurred before the failure and does not authorize retry. If unwinding or
inspection encounters an internal failure, pending jobs are `Unknown` and the
failure follows the `internal-error` integrity policy.

Engine integrity is intentionally not inferred from a cooperative control-flow
error:

- for bounded evaluation and `call_json`, the first implementation reports
  `EngineIntegrity::Unknown` until native, JavaScript, Wasm, and Wasm-GC tests
  characterize invariants and subsequent operations after each failure kind;
- a stronger `Reusable` classification is allowed only when those tests cover
  retained mutation, pending jobs, call/construct/generator unwind, and the
  exact observation phases involved; and
- every guardrail failure from a microtask or timer checkpoint reports
  `EngineIntegrity::Discard`, preserving the accepted checkpoint-failure host
  policy. Narrowing that value requires a separate decision replacing that
  policy, not merely passing a diagnostic probe.

Hosts must discard an Engine whose integrity is `Unknown` or `Discard`.
`Reusable`, if later established by the required characterization, means only
that runtime invariants remain valid; effects are not rolled back and retry is
not promised.

## Relationship to future host callbacks

A synchronous host callback reached during a bounded operation does not reset
or replace the outer execution-control context. JavaScript work before the
callback and JavaScript work resumed after it share the same remaining budget,
active depth, and interruption request. The diagnostic continues to preserve
the outer public operation.

Stage 5 must separately decide callback ownership and lifetime, same-Engine
re-entry rejection, callback error conversion, whether a fixed boundary charge
is added, and whether or how time spent executing host code is accounted. Host
wall-clock time is not silently converted into steps by this decision. Stage 5
may refine the host-boundary charge, but it may not reset the outer budget and
thereby let callbacks escape the operation bound.

This record does not implement callbacks or same-Engine re-entry.

## Alternatives considered

| Model | Existing API compatibility | Operation clarity and queues | Host callbacks and four targets | Decision |
|---|---|---|---|---|
| Engine-construction default policy | Can be additive only by adding another constructor shape, but silently applies one lifetime policy to unlike calls. | A default obscures which call resets the budget and whether a timer checkpoint receives one budget or one per callback. | A persistent default encourages accidental reset or inheritance rules at callbacks; implementation is portable but the contract is ambiguous. | Rejected. |
| Policy supplied to each bounded operation | Leaves every existing operation unchanged and adds explicit opt-in variants. | The host-visible call is the reset boundary; one timer or microtask checkpoint clearly receives one budget. | The outer context can cross future callbacks without reset, and the counter/flag checks are target-neutral. | Selected. |
| Mutable budget configuration stored on Engine | Setter methods can be additive, but later calls depend on hidden mutable state and partial consumption. | It is unclear whether failure, a checkpoint, or a subsequent operation resumes or resets the stored counter. Re-entry would make mutation order observable. | Callbacks could mutate the active policy; target synchronization would become part of the API. | Rejected. |

## Implementation acceptance

Stage 4 remains unimplemented until all of the following hold:

- bounded variants are additive and existing unbounded APIs and `EngineError`
  behavior are unchanged;
- the opaque policy, validation error, monotonic interruption handle, and four
  bounded operation signatures match the public shape in this decision;
- a static audit covers statement and expression dispatch, call and construct
  entry, getters, setters, every Proxy trap, generator start/resume, queue
  dispatch, and all script-controlled runtime and standard-library loop
  back-edges;
- infinite statement/expression loops, a long native built-in loop, and dynamic
  `eval` execution after parsing terminates at deterministic steps;
- direct recursion, getter/setter recursion, Proxy traps, constructors, and
  generator resume hit the independent depth guard;
- pre-requested interruption and requests made visible during an operation are
  observed only at the documented points;
- queue tests cover failure before selection, after consumption but before
  callback body, and during callback, including an all-cancelled timer queue, a
  partially discarded cancelled prefix, timer safety-limit precedence,
  interval behavior, and timer-following microtasks;
- diagnostics assert failure kind, outer operation, phase,
  `RetainedEffects::MayRemain`, actual pending-job snapshot when safe, and the
  evidence-gated integrity value, with `Discard` required for checkpoints; and
- equivalent observable results pass on native, JavaScript, Wasm, and Wasm-GC.

Tests must assert exact boundary effects and queue contents, not merely that an
infinite loop or recursion no longer aborts the process.

## Non-goals

This decision does not provide or promise:

- a security sandbox or safety for hostile JavaScript;
- wall-clock timeout, preemptive cancellation, signals, or thread scheduling;
- process, address-space, memory, or capability isolation;
- synchronous host callbacks, callback lifetime management, or same-Engine
  re-entry;
- transactional rollback of JavaScript mutation, output, or queue changes;
- a change to queue ordering, consumption, timer, or interval semantics;
- a change to existing `EngineError`, existing operation behavior, or existing
  generated interfaces;
- guardrails for compatibility or advanced/internal APIs in the first
  implementation;
- a VM, JIT, bytecode migration, snapshot, compile cache, or performance
  optimization; or
- a cross-version performance metric based on exact step counts.

## Consequences

- Hosts opt into a bounded operation explicitly and can choose a different
  policy for each call without hidden Engine mutation.
- Budget exhaustion, depth exhaustion, and interruption have deterministic
  failure precedence, retained-state, and queue consequences.
- Four-target parity is feasible without a target clock or preemption API.
- The implementation must instrument more than statement execution or the
  general call helper; native algorithms and distinct construct/generator paths
  are part of the acceptance boundary.
- Current users receive no new availability guarantee until the Stage 4 runtime
  and public API implementation passes the acceptance criteria above.
