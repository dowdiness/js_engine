# Closed receiver-call ownership

## Status

Accepted for Issue #833.

## Context

The dispatcher supports three receiver-call families whose trusted payloads
cannot be combined. Representing those families as independent optional state
allows impossible combinations and spreads family selection, validation, and
release decisions across the imperative boundary.

## Decision

Receiver-call execution has one private closed ownership sum with one case for
each currently admitted family: fixed receiver, changing receiver, and mutual
receiver. The owner contains exactly one already-sealed family payload, or is
absent before a receiver root has been admitted. Multiple receiver families
are therefore unrepresentable after construction.

Each family keeps its own trust rules, lowering, provenance checks, and
admission boundary. The ownership layer only wraps a sealed payload and
centralizes the family-specific call-location, identity, argument, and
callable validation needed to enter a managed activation. It does not expose
a trait, callback, plugin registry, or general operation interface.

After transfer, the dispatcher owns activation preparation, continuation and
completion routing, observation, realm and parameter state, and exactly-once
LIFO cleanup. An admitted call cannot return to legacy recursive execution.
Legacy execution remains available only when rejection happens before
ownership transfer.

## Consequences

Receiver entry, managed-call selection, statement routing, and root release
share one ownership boundary while family-private trust remains explicit.
Normal completion, abrupt completion, source identity, observation accounting,
state restoration, and same-interpreter reuse retain their existing contracts.

The broader all-family operation abstraction is deferred. It becomes a
separate decision only after non-receiver families demonstrate the same stable
ownership and transition interface; three receiver variants alone do not
justify widening the abstraction.

No public API, package dependency, engine selection, bytecode behavior, or
admitted receiver syntax changes.
