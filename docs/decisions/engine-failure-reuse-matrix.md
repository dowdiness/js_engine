# Reusing an Engine after synchronous failure

Date: 2026-07-17

## Status

Accepted as a baseline for the current `Engine` facade. It records behavior; it
does not change the runtime or public API.

## Context

An embedding host needs to know whether an `Engine` is still usable after
`eval` or `call_json` fails. It also needs to know what happens to state changes
and queued jobs. This baseline must be clear before adding callbacks, execution
budgets, or re-entry.

## Decision

The same `Engine` remains usable after the characterized parse, JavaScript, and
JSON conversion failures.

Three rules define the contract:

1. Completed JavaScript work is not rolled back.
2. `eval` and `call_json` do not run queue checkpoints, even when they fail.
3. `call_json` finds the callee before converting arguments. A lookup getter
   can therefore change state or queue jobs even if conversion later fails.
   The target itself does not run in that case.

The tests in `engine_test.mbt` are the source of truth for individual cases.
The [embedding guide](../EMBEDDING.md#reusing-an-engine-after-failure) gives
hosts the reader-facing summary.

## Non-goals

This decision does not cover:

- `InternalError` recovery
- failures raised by microtask or timer checkpoints
- `define_json`, host callbacks, or same-`Engine` re-entry
- execution budgets, structured errors, or concurrency

## Consequences

Hosts may recover from the characterized failures without rebuilding the
`Engine`. They must still account for retained state and pending jobs.

Any future change to this behavior must update the tests, the embedding guide,
and this record together. Callback and re-entry designs must also preserve this
baseline or replace it through an explicit decision.
