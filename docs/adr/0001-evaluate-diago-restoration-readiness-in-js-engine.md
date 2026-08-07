---
status: accepted
---

# Evaluate Diago restoration readiness in js_engine

The current restoration investigation will change and test only js_engine. It
will establish whether the current engine can practically execute representative
pre-removal Diago LaTeX and sketch workloads on every applicable target and
profile, but it will not modify Diago or claim that Diago has restored those
features. This keeps the execution evidence with the engine that owns the risk,
while leaving the later product-restoration decision to Diago.

The evidence will follow the existing external-consumer bundle-fixture pattern:
check in hash-identified pre-removal MathJax and Rough.js sources with only their
minimal execution adapters, and execute them through the root `@js_engine`
facade. CI will neither fetch live upstream content nor vendor or execute Diago's
library, CLI, or Wasm ABI, so the result is engine readiness evidence rather than
a Diago integration claim.

If a pinned workload fails, production changes will address only the smallest
general JavaScript operation family responsible for the failure and will deepen
the existing execution module at its established seam. Production code must not
recognize Diago, MathJax, Rough.js, an asset hash, or a bundle-specific source
shape. Work stops when the readiness evidence is green; broader residual
host-stack independence remains General Stack Safety work.

The pinned assets and a dedicated target/profile command will remain
reproducible in the repository, but this check will not join the permanent
required pull-request stack-safety gate. The assets are materially larger and
slower than the existing lightweight external-consumer bundle fixture, while
the decision concerns only the exact current revisions. All eight
target/profile cells will therefore be recorded for the readiness change's
exact head without imposing that bundle-specific cost on future pull requests.

Because the investigation cannot execute Diago itself, a test-only Diago
harness adapter will replace parsing, graph layout, and final SVG assembly. The
adapter must still execute the unmodified pinned JavaScript assets through the
root facade in the pre-removal order, including required microtask and timer
checkpoints, and inspect real returned metrics and drawing data. It may not
stub engine results, and its passing result must not be reported as the former
Diago integration fixtures passing.

The behavioral oracle is deliberately small: `x^2` must yield a MathJax math
SVG with the historical `19 × 17` dimensions; the former CD, bra/ket, and cancel
formula inputs must each yield real SVG with positive finite dimensions; and a
Rough.js rectangle must yield multiple real drawing paths. The harness preserves
the former microtask and timer checkpoint order. It does not assert Diago box
coordinates, final assembled SVG, or invalid D2 diagnostics.

Each target/profile cell gets one attempt with a 15-minute command-level bound
and no retry. Timeout, crash, or failed assertion rejects readiness. Rough.js
uses the former adapter's fixed seed so the structural path oracle is
deterministic; a later successful retry cannot replace a failed recorded cell.

Any production fix must remain private to the existing execution module. It may
not change the root facade interface, dependencies, executor selection, or
JavaScript behavior; make bytecode execution mandatory; or share private
tree-walker recipe types with bytecode. The enduring value of the change must be
the deeper general operation implementation, not a new restoration interface.

Each General Operation Slice will deepen the existing dispatcher rather than
introduce a parallel execution mechanism. Its deterministic core will express
`State + Event -> (State, Decision)` transitions; the imperative shell alone
owns guest calls, realm and source mutation, microtask and timer checkpoints,
observations, and cleanup. No Diago-specific driver, continuation family, or VM
will be added.
