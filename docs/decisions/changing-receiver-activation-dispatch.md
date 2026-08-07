# Changing-receiver activation dispatch

## Status

Accepted for the closed ordinary-data-property slice tracked by #831.

## Context

A tree-walker can preserve JavaScript results while still exhausting the host
stack when one ordinary interpreted method calls itself on a different receiver
at each step. Increasing the host stack, recognizing a library bundle, or
selecting bytecode would hide the execution-boundary problem rather than solve
it.

The engine already owns an explicit activation dispatcher. The useful change is
therefore to deepen that boundary for one semantic operation family, not to add
another evaluator.

## Decision

Admission is split into two deterministic questions:

1. Can the function body be lowered into the supported value-producing
   operations and continuations?
2. Does the reachable runtime graph consist only of the ordinary receivers,
   data descriptors, prototype-resolved callable identity, arguments, closure,
   realm, and source provenance required by that plan?

Source text, identifier spellings, fixture names, and call counts are not
admission inputs. Validation performs no guest callbacks. Work is bounded to a
maximum admitted depth of 4096 so classification cannot introduce an unbounded
host-side traversal.

Once admitted, the common dispatcher owns every activation and completion. Its
state records receiver, argument, return target, binary-result consumer, and
cleanup order. Deterministic transitions decide the next work; the runtime
shell performs environment preparation, realm mutation, observation, ordinary
data reads, and cleanup. An admitted call never falls back to recursive guest
execution.

Unsupported syntax or runtime shapes stay on the legacy path only when rejected
before dispatcher ownership transfers. Accessors, proxies, exotic receivers,
callable drift, computed/coercing keys, and unsupported control forms are not
partially executed by this slice.

## Invariants

- The public evaluation and JSON-call contracts do not change.
- Each activation result is consumed once by an explicit continuation.
- Guest throw and runtime abrupt completion preserve their identity.
- Realm state, parameter-call state, execution observations, and cleanup are
  restored exactly once in LIFO order.
- The functional core contains decisions, not arbitrary host closures or I/O.
- The imperative shell contains effects, not a parallel semantic state machine.
- Rejection precedes any irreversible admitted effect.

## Consequences

The closed slice becomes independent of host stack size on every supported
target/profile. Admission performs bounded linear validation and retains the
validated receiver sequence for the duration of the dispatch.

Broader property semantics remain separate work. Future slices should extend
the common plan and continuation vocabulary, especially for observable
property access, rather than growing a family-specific driver.

The same explicit activation, continuation, completion, and cleanup concepts
can be reused by a future bytecode VM. This decision neither requires bytecode
nor treats the tree-walker plan as public bytecode.
