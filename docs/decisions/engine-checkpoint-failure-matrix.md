# Engine checkpoint failure matrix

Date: 2026-07-22

## Status

Observed, non-contractual baseline. This record characterizes current behavior,
including at-most-once microtask dispatch. It does not make checkpoint recovery
a supported contract or change the public API.

## Context

Microtask, timer, and interval queue policies are separated into private cores
while callback execution and error propagation remain in imperative shells.
The observations use only the stable `Engine` facade and JavaScript exceptions.
They do not manufacture an `InternalError` path. The timer policy extraction
does not change these observations.

## Observations

| Failure point | State after failure | Observation on retry |
|---|---|---|
| A microtask throws once | Mutations from the successful prefix and throwing job remain. The queue consumes that prefix and throwing job, retaining only unstarted jobs such as the nested job appended before the throw. | Only the retained nested job runs, and the queue becomes empty. The successful prefix and throwing job do not replay. |
| A timer callback throws | The failing timer has been consumed. A microtask and new timer queued by the callback remain beside the existing later timer. | After an explicit microtask drain, the existing later timer runs before the new timer. The failing timer does not replay. |
| A timer's microtask checkpoint throws | The current timer, successful microtask prefix, and throwing microtask have been consumed. Unstarted microtasks and the next timer remain. | The next timer runs first. Its checkpoint drains only the retained unstarted microtasks; the throwing job does not replay. |
| An interval callback throws | The interval invocation has been consumed and the interval is not re-registered. No timer remains pending. | Another timer checkpoint does not invoke the callback again. |

In every case, synchronous `call_json` snapshot reads remain possible after the
failure. The tests also record the corresponding microtask and timer pending
flags. Error assertions distinguish `JavaScriptException` without depending on
target-specific message text.

## Consequences

The matrix is evidence for a future queue-boundary design, not permission to
recover and continue production execution. Test retries and `call_json`
snapshots are diagnostic probes only. Hosts should continue to discard an
`Engine` after a checkpoint failure.

The tests in `engine_test.mbt` are the source of truth for these observations.
The [embedding guide](../EMBEDDING.md#checkpoint-failure-baseline) gives hosts a
reader-facing summary.

The [checkpoint failure policy](engine-checkpoint-failure-policy.md) chooses
at-most-once dispatch. Private microtask and timer policies now implement the
queue transitions, and diagnostic retry is still not a supported recovery
contract.

## Non-goals

This record does not define:

- recovery from `InternalError`
- a poisoned `Engine` state
- changes to timer or interval observable semantics
- callbacks, re-entry, execution budgets, or concurrency

Any future runtime change that alters these observations must intentionally
replace the tests and documentation. A supported recovery contract requires a
separate decision.
