---
status: accepted
---

# Keep resumable property mutation runtime-owned

Property mutation that can invoke interpreted code belongs behind one runtime-owned activation interface. The runtime decides admission and fallback before observable execution, owns JavaScript property semantics and result normalization, and initially admits only a closed direct-own ordinary setter slice. Simple assignment may use a specialized private completion internally; multi-stage update later adds a private state machine behind the same interface rather than exposing getter, coercion, setter, or executor details to callers.

## Considered options

A standalone setter-call interface was rejected because it would make callers own setter discovery and assignment-result semantics. A fully generic mutation state machine in the first implementation was rejected because it would commit to unproven update, computed-key, prototype, proxy, and super behavior. The chosen interface stays small while allowing those families to deepen the same module only after separate semantic evidence.

## Consequences

Fallback is permitted only before admitted observable execution begins. Once an admitted child activation starts, normal or abrupt completion must remain within the resumable runtime path. Bytecode and other executors retain evaluated operands but do not reproduce property lookup, receiver, strictness, invariant, realm, or result-selection rules.
