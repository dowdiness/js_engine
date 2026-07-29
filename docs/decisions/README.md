# Decisions

Architecture-decision-record-style documents and project contracts.

- [engine-failure-reuse-matrix.md](engine-failure-reuse-matrix.md) — when an Engine can be reused after a synchronous failure.
- [engine-checkpoint-failure-matrix.md](engine-checkpoint-failure-matrix.md) — observed queue state after a JavaScript exception during an Engine checkpoint; recovery remains unsupported.
- [engine-checkpoint-failure-policy.md](engine-checkpoint-failure-policy.md) — accepted at-most-once queue-dispatch policy; private policy extraction is complete for microtasks, timers, and intervals.
- [engine-diagnostic-contract.md](engine-diagnostic-contract.md) — accepted and implemented operation-aware structured diagnostic contract and source-compatible public API evolution.
- [engine-json-injection-contract.md](engine-json-injection-contract.md) — immutable host-owned JSON injection, collision policy, and structured failure contract.
- [engine-execution-guardrail-contract.md](engine-execution-guardrail-contract.md) — accepted operation-scoped guardrail contract; private state transitions and statement/expression observation are staged, while bounded APIs and complete accounting remain pending.
- [engine-activation-continuation-contract.md](engine-activation-continuation-contract.md) — accepted continuation-aware activation dispatcher contract for #630, including explicit handler/finalizer and activation-cleanup ownership.
- [tooling-migration-contracts.md](tooling-migration-contracts.md) — parity contract for migrating Python scripts to MoonBit.
- [bytecode-execution-representation-contract.md](bytecode-execution-representation-contract.md) — proposed bytecode execution representation contract for #601: deepen existing stack bytecode as the sole long-term compiled executable representation; reject separate ExecutionIR and register/basic-block alternatives.
