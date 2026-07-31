# Stack-safe public acceptance workload contract

Date: 2026-07-31. Reconciled by #693 from the public workload boundary in #692.

## Purpose

The permanent stack-safety gate must state exactly which finite programs are
covered by the implementation that has landed. The final observable seam is
the external-consumer suite through the root `@js_engine` facade. A focused
interpreter or reducer fixture is supporting evidence; it is not a substitute
for the public gate.

This contract separates production-admitted behavior, post-parse phase
isolation, compatibility controls, and residual runtime work. A workload is
required only when its owning implementation has supplied the evidence for its
class. A deferred workload is absent from the required set; it is never encoded
as a skipped required test or replaced by a lookalike source.

## Workload ownership

Each row has one evidence class and one owning issue. #616 is closed provenance
for the historical reproducers, not an additional owner. #619 consumes the
required rows as a cross-target/profile gate; it does not widen the production
scope of another issue.

| Workload | Evidence class | Owning issue | #619 disposition |
|---|---|---|---|
| Exact numeric self recursion at depth 256, returning `256` | Production-admitted exact slice | #630 | Required |
| Exact numeric mutual recursion at depth 256, returning `256` | Production-admitted exact slice | #630 | Required |
| Exact ordinary getter re-entry at depth 256, returning `256` | Production-admitted exact slice | #630 | Required |
| Exact Proxy `get` re-entry at depth 256, returning `256` | Production-admitted exact slice | #630 | Required |
| Exact protected normal/abrupt completion, control, and lifecycle cases | Production-admitted exact slice | #630 | Required |
| Deep comma input traversed by post-parse early-error validation, including the 512-level phase-isolation case | Post-parse phase-isolation | #614 | Required |
| Finite-below-limit execution and engine-owned exhaustion at the logical activation boundary | Activation-depth policy | #617 | Required after #617 lands; pending before then |
| Shallow release-profile controls for unchanged legacy behavior | Legacy compatibility control | #619 | Required |
| The #616 mixed call-plus-expression generator (`"0,"` repeated 263 times, followed by `"7"`) with the recursive `step(256, ...)` wrapper, expected guest value `263` | #608 residual; deferred public graduation evidence | #608 | Deferred; absent from the required set |
| The success-valued 512-comma runtime case (`"0,"` repeated 512 times, followed by `"7"`), expected guest value `7` | #608 residual; deferred public graduation evidence | #608 | Deferred; absent from the required set |

The post-parse 512-level traversal and the success-valued 512-comma runtime
case are deliberately different workloads. #614 owns the former's early-error
phase evidence. #608 owns the latter's complete runtime evaluation, and also
owns the exact mixed workload until its dynamic call and expression paths are
production-admitted. Passing post-parse validation does not graduate either
runtime workload.

## Gate and independence rules

- Required rows use identical JavaScript source and expected outcomes across
  every supported target and profile. Target-specific rewrites and host stack
  flags are not evidence.
- A deferred row has no required-test skip marker. It joins #619 only when its
  #608 child supplies a red public test, exact admission/provenance, iterative
  execution, and cleanup evidence.
- #689's URI timeout/concurrency investigation is an independent CI-stability
  workload. It neither satisfies nor weakens this focused stack-safety gate.
- Closing #630 does not reopen it: its exact slices remain required evidence,
  while the broader residuals stay under #608.

The accepted activation/continuation model remains the architectural source of
truth; this document fixes only the public workload and ownership boundary.
