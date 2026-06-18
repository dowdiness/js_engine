# Documentation

Use this index to find the right `js_engine` document. Code is the source of
truth; when a doc and the code disagree, trust the code.

## Start here

- [../README.md](../README.md) — project overview, quick start, supported language
- [ROADMAP.md](ROADMAP.md) — headline status and current next targets
- [supported-features.md](supported-features.md) — per-category pass rates, Annex B, missing features
- [TEST262.md](TEST262.md) — how to run the test262 conformance suite
- [decisions/tooling-migration-contracts.md](decisions/tooling-migration-contracts.md) — parity contract for migrating Python scripts to MoonBit

## Reference

- [decisions/README.md](decisions/README.md) — architecture-decision-record-style documents and project contracts
- [development.md](development.md) — maintainer workflow, generated files, Test262, benchmarks, releases
- [design/architecture.md](design/architecture.md) — design principles, package boundaries, value model, host integration
- [GLOSSARY.md](GLOSSARY.md) — terminology used in the code and docs
- [RELEASING.md](RELEASING.md) — release checklist (test262-number minting, tag/CHANGELOG drift rules)
- [../AGENTS.md](../AGENTS.md) — MoonBit conventions and tooling guide (also used by AI agents)
- [agent-todo.md](agent-todo.md) — queue of small, self-contained tasks for contributors

## Deep design

Long-form research and design analysis. These explain design history and may
lag the code. Start with [design/README.md](design/README.md) for the design-folder index.

- [closure-conversion-and-bytecode.md](design/closure-conversion-and-bytecode.md) — closure-conversion prototype status, research notes, and bytecode/IR direction
- [SELF_HOST_JS_RESEARCH.md](design/SELF_HOST_JS_RESEARCH.md) — self-hosting analysis (compiling the engine to JS)
- [architecture-redesign-2026-06-12.md](design/architecture-redesign-2026-06-12.md) — current first-principles architecture redesign findings
- [architecture-execution-plan-2026-06-12.md](design/architecture-execution-plan-2026-06-12.md) — staged execution contract for the current redesign
- [architecture-stage0-implementation-spec-2026-06-12.md](design/architecture-stage0-implementation-spec-2026-06-12.md) — concrete Stage 0 guardrail/inventory implementation specs
- [architecture-redesign-2026-05-19.md](design/architecture-redesign-2026-05-19.md) — migration record for realm state ownership, runtime surface control, and execution boundaries
- [architecture-redesign-2026-04-17-probes.md](design/architecture-redesign-2026-04-17-probes.md) — exploratory sizing probes for earlier restructuring work

## Historical / archived

<!-- Do not read files in this section unless the user explicitly asks for historical context. -->

Completed or superseded material, kept for record only. Do not treat these as current guidance.

- [archive/executed-roadmap-history.md](archive/executed-roadmap-history.md) — completed roadmap plans and stale planning snapshots moved out of `ROADMAP.md`
- [archive/phase-history.md](archive/phase-history.md) — implementation notes for completed phases
- [archive/implementation-priority-snapshot.md](archive/implementation-priority-snapshot.md) — phase-planning snapshot (superseded by `ROADMAP.md`)
- [archive/generator-plan.md](archive/generator-plan.md) — generator implementation plan (COMPLETE)
- [archive/architecture-redesign-2026-04-15.md](archive/architecture-redesign-2026-04-15.md) — shipped restructuring analysis (COMPLETE)
- [archive/2026-04-09-structural-refactoring.md](archive/2026-04-09-structural-refactoring.md) — earlier structural refactor notes
- [superpowers/plans/](superpowers/plans/), [superpowers/specs/](superpowers/specs/) — per-feature plan and spec artifacts
