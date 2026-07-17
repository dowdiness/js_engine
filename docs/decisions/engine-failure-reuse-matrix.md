# Engine failure/reuse matrix

Date: 2026-07-17

## Status

Accepted as a characterization baseline for the current synchronous `Engine`
facade. This records observed behavior only; it does not add new runtime or API
features.

## Context

Stage 2 embedding work needs a stable answer for what a host may do after a
synchronous `Engine` operation fails. The important questions are whether the
same `Engine` can be reused, whether JavaScript-visible mutations before the
failure survive, and whether queued microtasks or timers are discarded or left
for explicit checkpoints.

## Decision

Characterization tests in `engine_test.mbt` define this baseline:

| Failure category | Reusable afterward? | State before the failure | Pending microtasks/timers |
|---|---:|---|---|
| Parse failure from `Engine::eval` | Yes | Prior state is retained; the rejected source does not run. | Existing queues remain pending. |
| JavaScript throw from `Engine::eval` or `Engine::call_json` | Yes | Mutations completed before the throw are retained. | Jobs queued before the throw remain pending. |
| JSON argument conversion failure in `Engine::call_json` | Yes | Callee lookup completes before argument conversion. The target function is not called, but lookup getter mutations are retained along with prior state. | Existing jobs and jobs queued by a lookup getter remain pending. |
| JSON result conversion failure in `Engine::call_json` | Yes | Target function already ran; mutations completed before conversion failure are retained. | Jobs queued by the target remain pending. |

`Engine::eval` and `Engine::call_json` continue to avoid implicit event-loop
checkpointing. Hosts must call `run_microtask_checkpoint` and
`run_timer_checkpoint` to advance pending jobs after both successful and failed
synchronous operations.

## Non-goals

This decision does not implement or specify `define_json`, host callbacks,
execution budgets, structured errors, concurrency, or same-`Engine` re-entry.
It also does not characterize `InternalError` recovery or failures that occur
while explicitly running microtask or timer checkpoints.

## Consequences

The current `Engine` contract is non-transactional: hosts can reuse it after the
characterized synchronous failure categories, but they must account for retained
mutations and pending jobs. Future features that introduce host callbacks or
re-entry must be checked against this baseline before they are added.
