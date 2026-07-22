# Engine checkpoint failure matrix

Date: 2026-07-22

## Status

Observed, non-contractual baseline. This record characterizes current behavior;
it does not make checkpoint recovery a supported contract or change the runtime
or public API.

## Context

Before separating queue policy into a functional core and callback execution
into an imperative shell, the existing failure state must be measurable. The
observations use only the stable `Engine` facade and JavaScript exceptions. They
do not manufacture an `InternalError` path.

## Observations

| Failure point | State after failure | Observation on retry |
|---|---|---|
| A microtask throws once | Mutations from the successful prefix and throwing job remain. The queue retains the prefix, throwing job, and the nested job appended before the throw. | The prefix and throwing job replay. Nested jobs appended by the first and retry attempts then run in insertion order, and the queue becomes empty. |
| A timer callback throws | The failing timer has been consumed. A microtask and new timer queued by the callback remain beside the existing later timer. | After an explicit microtask drain, the existing later timer runs before the new timer. The failing timer does not replay. |
| A timer's microtask checkpoint throws | The current timer has been consumed. The microtask queue and next timer remain. | The next timer runs first. Its checkpoint replays the retained microtask prefix and throwing job, then drains nested jobs. |
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

## Non-goals

This record does not define:

- recovery from `InternalError`
- at-most-once checkpoint execution
- a poisoned `Engine` state
- extracted queue policy or a runtime refactor
- callbacks, re-entry, execution budgets, or concurrency

Any future runtime change that alters these observations must intentionally
replace the tests and documentation. A supported recovery contract requires a
separate decision.
