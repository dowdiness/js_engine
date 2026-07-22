# Engine checkpoint failure policy

Date: 2026-07-22

## Status

Accepted target policy, not yet implemented. This record guides follow-up
queue-boundary work without changing the current runtime or public API in this
PR.

## Context

The [checkpoint failure matrix](engine-checkpoint-failure-matrix.md) shows that
failure currently commits queue progress at different points. A failed
microtask checkpoint retains and replays jobs that already ran, while a timer
is removed before its callback runs and an interval is re-registered only after
successful work.

These differences follow from control flow in the imperative runtime rather
than from an explicit queue policy. A functional core / imperative shell split
needs a chosen target before code is moved, so that structural refactoring and
behavior changes can be reviewed separately.

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

Each queued job instance will use at-most-once dispatch:

1. Select and consume the next job before invoking its callback.
2. Run the callback outside the queue-policy core.
3. If the callback fails, stop the checkpoint and propagate the failure without
   restoring the consumed job.
4. Leave jobs that have not started, including jobs enqueued before the throw,
   in their current order. Their presence is internal state, not a supported
   recovery mechanism while discard-on-failure remains the public contract.

An interval is eligible for re-registration only after its callback and the
following microtask checkpoint both complete successfully, and only if it was
not cancelled. A failed interval invocation is consumed and is not scheduled
again.

### Architecture boundary

Queue selection, consumption, ordering, and interval re-registration decisions
belong to a functional core expressed as explicit state transitions. Invoking a
JavaScript callback and translating its result or error belong to the
imperative shell.

The core must not invoke JavaScript. The shell must not decide whether a job was
consumed or should be re-registered. Callback results are inputs to the next
queue-policy transition.

## Rationale

At-most-once dispatch prevents a retry from duplicating already completed
effects. It also gives microtasks and timers one explicit consumption rule while
preserving their ordering differences. Keeping discard-on-failure as the host
contract avoids promising recovery before runtime integrity, callbacks,
re-entry, and execution limits have been designed together.

## Implementation sequence

Follow-up work should remain split into narrow changes:

1. Extract queue-policy transitions without changing observed behavior.
2. Change microtask dispatch to the chosen at-most-once policy and intentionally
   update the characterization tests and documentation.
3. Move timer and interval bookkeeping behind the same policy boundary while
   preserving timer order.

Each behavior-changing step must pass the stable `Engine` tests on `native`,
`js`, `wasm`, and `wasm-gc`.

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
