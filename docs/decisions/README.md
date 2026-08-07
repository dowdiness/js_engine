# Decisions

Architecture-decision-record-style documents and project contracts.

- [engine-failure-reuse-matrix.md](engine-failure-reuse-matrix.md) — when an Engine can be reused after a synchronous failure.
- [engine-checkpoint-failure-matrix.md](engine-checkpoint-failure-matrix.md) — observed queue state after a JavaScript exception during an Engine checkpoint; recovery remains unsupported.
- [engine-checkpoint-failure-policy.md](engine-checkpoint-failure-policy.md) — accepted at-most-once queue-dispatch policy; private policy extraction is complete for microtasks, timers, and intervals.
- [engine-diagnostic-contract.md](engine-diagnostic-contract.md) — accepted and implemented operation-aware structured diagnostic contract and source-compatible public API evolution.
- [engine-json-injection-contract.md](engine-json-injection-contract.md) — immutable host-owned JSON injection, collision policy, and structured failure contract.
- [engine-execution-guardrail-contract.md](engine-execution-guardrail-contract.md) — accepted operation-scoped guardrail contract; bounded evaluation, JSON-call, microtask-checkpoint, and timer-checkpoint slices are implemented, while complete activation/native-loop/diagnostic accounting and final Stage 4 acceptance remain pending.
- [engine-activation-continuation-contract.md](engine-activation-continuation-contract.md) — accepted continuation-aware activation dispatcher contract for #630, including explicit handler/finalizer and activation-cleanup ownership.
- [executor-neutral-function-activation-contract.md](executor-neutral-function-activation-contract.md) — runtime-owned function preparation with opaque executor code and private resumable frames; mixed-call stack safety remains downstream work.
- [stack-safety-public-workload-contract.md](stack-safety-public-workload-contract.md) — reconciled #619 required workloads, #608 deferred graduation evidence, and one-owner evidence classification.
- [tooling-migration-contracts.md](tooling-migration-contracts.md) — parity contract for migrating Python scripts to MoonBit.
- [bytecode-execution-representation-contract.md](bytecode-execution-representation-contract.md) — proposed bytecode execution representation contract for #601: deepen existing stack bytecode as the sole long-term compiled executable representation; reject separate ExecutionIR and register/basic-block alternatives.
- [receiver-call-ownership.md](receiver-call-ownership.md) — private closed ownership boundary for fixed, changing, and mutual receiver-call families; broader all-family ownership remains deferred.
