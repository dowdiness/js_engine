# Engine checkpoint failure policy

Date: 2026-07-22

## Status

Accepted. At-most-once dispatch and timer lifecycle bookkeeping are implemented
by private microtask and timer queue policies. The public API and
discard-on-checkpoint-failure host contract are unchanged.

## Context

The original [checkpoint failure matrix](engine-checkpoint-failure-matrix.md)
showed that failure committed queue progress at different points. A failed
microtask checkpoint retained and replayed jobs that already ran, while a timer
was removed before its callback ran and an interval was re-registered only
after successful work.

Microtask selection and failure compaction, together with timer selection,
consumption, cancellation, and interval re-registration, now follow explicit
private policies. JavaScript execution and error propagation remain outside
those policies.

## Decision

### Supported host behavior

When a microtask or timer checkpoint raises an error, the supported host action
remains to discard the `Engine`. Calls made after that failure have no recovery
guarantee. Diagnostic retries used by characterization tests do not establish a
public reuse contract.

Completed JavaScript-visible mutations are not rolled back. The original
failure continues to be reported through the existing `EngineError`
classification.

### Target queue policy

Each queued job instance uses at-most-once dispatch. The private microtask and
timer policies implement these steps:

1. Select and consume the next job before invoking its callback.
2. Run the callback outside the queue-policy core.
3. If the callback fails, stop the checkpoint and propagate the failure without
   restoring the consumed job.
4. Leave jobs that have not started, including jobs enqueued before the throw,
   ordered by their queue's existing rule: FIFO for microtasks and
   `(delay, insertion_order)` for timers. Jobs enqueued by the failing callback
   participate in that same rule. Their presence is internal state, not a
   supported recovery mechanism while discard-on-failure remains the public
   contract.

An interval is eligible for re-registration only after its callback and the
following microtask checkpoint both complete successfully, and only if it was
not cancelled. A failed interval invocation is consumed and is not scheduled
again.

### Target state examples

These examples define the policy independently of JavaScript callback
execution:

| Starting state | Callback outcome | Target state |
|---|---|---|
| Microtasks `[A, B]` | `A` enqueues `C`, then throws. | `A` is consumed. The remaining queue is `[B, C]`. |
| The next timer is `T1`; `T2` is also pending. | `T1` enqueues microtask `M` and timer `T3`, then throws. | `T1` is consumed. `M` remains pending. `T2` and `T3` remain ordered by `(delay, insertion_order)`. |
| Interval invocation `I` | `I` returns, but its following microtask checkpoint throws. | `I` is consumed and is not re-registered. |

### Architecture boundary

Queue selection, consumption, ordering, and interval re-registration decisions
belong to a functional core expressed as explicit state transitions. The
microtask core now owns selection, logical consumption, FIFO ordering, and
failure compaction. Invoking a JavaScript callback and translating its result or
error remain in the imperative shell.

The timer core now owns priority-queue selection and consumption, lazy
cancellation decisions, callback/checkpoint outcome transitions, interval
re-registration, and end-of-drain bookkeeping. The core must not invoke
JavaScript. The shell must not decide whether a job was consumed or should be
re-registered. Callback and checkpoint results are inputs to the next
queue-policy transition.

The microtask core must preserve an O(n) drain in the number of jobs. Consuming
before callback execution must not be implemented as repeated front removal
from an array. Timer dispatch must preserve the existing priority-queue
ordering and complexity.

## Rationale

At-most-once dispatch prevents a retry from duplicating already completed
effects. It also gives microtasks and timers one explicit consumption rule while
preserving their ordering differences. Keeping discard-on-failure as the host
contract avoids promising recovery before runtime integrity, callbacks,
re-entry, and execution limits have been designed together.

## Implementation sequence

The implementation remains split into narrow changes:

1. Completed: extract microtask queue-policy transitions without changing
   observed behavior.
2. Completed: change microtask dispatch to the chosen at-most-once policy and
   intentionally update the characterization tests and documentation.
3. Completed: move timer and interval bookkeeping behind the same policy
   boundary while preserving timer order and observed behavior.

Each step must pass the stable `Engine` tests on `native`, `js`, `wasm`, and
`wasm-gc`. Both extracted cores have direct tests that do not
invoke JavaScript. Timer tests cover priority ordering, consumption, lazy
cancellation, callback and checkpoint outcomes, interval re-registration,
safety-limit bookkeeping, and invalid transitions.

## Rejected alternatives

- Treating current microtask replay as supported retry behavior: it duplicates
  effects that completed before the throw.
- Transactional rollback: arbitrary JavaScript-visible mutations cannot be
  reliably reversed at this boundary.
- Inferring safe recovery from pending flags: queue presence does not establish
  runtime integrity or a supported continuation point.

## Non-goals

This decision does not add:

- an explicit poisoned-Engine state or new public error variant
- recovery from `InternalError`
- checkpoint retry or same-`Engine` reuse support
- host callbacks, re-entry, execution budgets, interruption, or concurrency
