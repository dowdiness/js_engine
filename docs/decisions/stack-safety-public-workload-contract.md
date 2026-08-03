# Stack-safe public acceptance workload contract

Date: 2026-08-03. Reconciled by #790 from the public workload boundary in #692.

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

## Public acceptance workload ownership

Each row has one evidence class and one owning issue. #616 is closed provenance
for the historical reproducers, not an additional owner. #619 consumes the
required public rows as a cross-target/profile gate; it does not widen the
production scope of another issue. This table is limited to #692's four public
acceptance evidence classes. It is not a complete inventory of the supporting
focused and core evidence that #619 also requires.

| Workload | Evidence class | Owning issue | #619 disposition |
|---|---|---|---|
| Exact numeric self recursion at depth 256, returning `256` | Production-admitted exact slice | #630 | Required |
| Exact numeric mutual recursion at depth 256, returning `256` | Production-admitted exact slice | #630 | Required |
| Exact ordinary getter re-entry at depth 256, returning `256` | Production-admitted exact slice | #630 | Required |
| Exact Proxy `get` re-entry at depth 256, returning `256` | Production-admitted exact slice | #630 | Required |
| Exact protected normal/abrupt completion, control, and lifecycle cases | Production-admitted exact slice | #630 | Required |
| Strict-mode source `"use strict"; ` + `nested_comma_source(512, "eval = 0")`, with `SyntaxError: Unexpected eval or arguments in strict mode` before runtime evaluation | Post-parse phase-isolation | #614 | Required |
| Finite-below-limit execution and engine-owned exhaustion at the logical activation boundary | Production-admitted exact slice (policy pending) | #617 | Required after #617 lands; pending before then |
| Shallow release-profile controls for unchanged legacy behavior | Legacy compatibility control | #619 | Required |
| The exact #790 mixed call-plus-expression generator (`"0,"` repeated 263 times, followed by `"7"`) with the recursive `step(256, ...)` wrapper, expected guest value `263` | Production-admitted retained-argument slice | #790 | Required |
| The success-valued 512-comma runtime case (`"0,"` repeated 512 times, followed by `"7"`), expected guest value `7` | Production-admitted direct-comma expression slice | #772 | Required |

## Supporting required evidence outside the public workload classes

The following evidence is required by #619 but is deliberately not another
public workload class:

| Supporting evidence | Evidence owner | #619 disposition |
|---|---|---|
| A continuation-only chain of at least 10,000 frames, including representative statement, numeric-resume, handler/finalizer, abrupt-replacement, and exactly-once cleanup routing, drained with a source-backed progress argument | #661 | Required focused/core evidence; not a public workload and not production-admitted behavior |
| One resource-bounded production dispatcher/shell depth stress exercising the actual production path, with its exact bounded depth and source fixed by #619's gate contract and measured CI cost | #619 | Required gate evidence; not a separate public workload class |

The #661 chain must remain independent of guest activation depth. Its passing
result is core evidence for the reducer and does not make a public workload or
an unadmitted runtime path production-admitted. The production-path stress is a
separate #619 shell check; this contract records its ownership without
inventing a second depth or source that could drift from the gate.

The post-parse 512-level traversal, the success-valued 512-comma runtime case,
and the retained-argument mixed runtime case are deliberately different
workloads. #614 owns the former's early-error phase evidence. #772 owns the
direct-comma runtime evaluation, and #790 owns the exact retained-argument
slice; both are required by #619. Broader dynamic call and expression paths
remain #608 residuals. Passing one exact workload does not graduate those
broader paths.

## Gate and independence rules

- Required rows use identical JavaScript source and expected outcomes across
  every supported target and profile. Target-specific rewrites and host stack
  flags are not evidence.
- A deferred row has no required-test skip marker. It joins #619 only when its
  owning child supplies a red public test, exact admission/provenance, iterative
  execution, and cleanup evidence.
- #689's URI timeout/concurrency investigation is an independent CI-stability
  workload. It neither satisfies nor weakens this focused stack-safety gate.
- Closing #630 does not reopen it: its exact slices remain required evidence,
  while the broader residuals stay under #608.

The accepted activation/continuation model remains the architectural source of
truth; this document fixes only the public workload and ownership boundary.
