# Decisions

Architecture-decision-record-style documents and project contracts.

- [engine-failure-reuse-matrix.md](engine-failure-reuse-matrix.md) — when an Engine can be reused after a synchronous failure.
- [engine-checkpoint-failure-matrix.md](engine-checkpoint-failure-matrix.md) — observed queue state after a JavaScript exception during an Engine checkpoint; recovery remains unsupported.
- [engine-checkpoint-failure-policy.md](engine-checkpoint-failure-policy.md) — accepted target policy for at-most-once queue dispatch and the functional-core boundary; not yet implemented.
- [tooling-migration-contracts.md](tooling-migration-contracts.md) — parity contract for migrating Python scripts to MoonBit.
