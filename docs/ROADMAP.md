# JS Engine Roadmap

This roadmap is for current direction only. Completed plans and stale planning
snapshots live in [archive/executed-roadmap-history.md](archive/executed-roadmap-history.md)
and the older [archive/phase-history.md](archive/phase-history.md).

## Current Status

**Test262** — CI run [29452024184](https://github.com/dowdiness/js_engine/actions/runs/29452024184) on tag tip `71e07d0`, 2026-07-15. Each test file is run twice (strict + non-strict); the two are reported separately because summing would double-count files.

| Mode | Discovered | Skipped | Executed | Passed | Failed | Timeouts/Err | Passed / Executed | Passed / Discovered |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| strict | 44,986 | 10,201 | 34,773 | 31,513 | 3,260 | 12 | **90.6%** | 70.1% |
| non-strict | 47,692 | 10,672 | 37,003 | 33,331 | 3,672 | 17 | **90.1%** | 69.9% |

CI regression baseline: `test262-baseline.json` (min 30,487 non-strict / 28,672 strict passed, updated 2026-07-05; currently +2,844 / +2,841 above).

_Note: the runner reports timeout and error outcomes together in the `Timeout/Err` column; inspect the results JSON for details._

To refresh this block, run `make test262-report`; do not copy numbers from
other documentation. For release notes, use `make test262-report
ARGS="--format=changelog"`.

ES2015 specifically: strict **98.1%** P/E (9,942 / 10,131; 161 skipped),
non-strict **97.9%** P/E (10,400 / 10,620; 160 skipped) — the roadmap 95%
ES2015 target is achieved.


**Unit tests**: run `moon test` for the current local count; this section only
tracks the checked-in Test262 snapshot.

### How to read these rates

Quote **both** denominators whenever you cite a test262 figure, and always say
which mode you mean.

| Column | What it means | Pitfall |
|---|---|---|
| **Passed / Executed** | The headline rate engines usually quote. Numerator and denominator both exclude skipped files. | Rises mechanically when more tests get skipped, so it is not a reliability signal on its own. A feature whose tests are 100% skipped contributes 0 to this ratio. |
| **Passed / Discovered** | Broader spec-coverage figure. Skipped files count as un-passed, so it only moves when the engine itself improves. | Falls when the test262 suite adds new-edition tests faster than we implement them, even if the engine is unchanged. |

Skips dominate the gap: Temporal, BigInt, RegExp Unicode property escapes,
iterator helpers, and other entries in `scripts/test262_skip_metadata.json`
`skip_features`. Async iteration and class-private syntax are no longer blanket-
skipped; remaining gaps show up as path-specific exceptions (146 async-generator
destructuring `for-await-of` paths) or executed-but-failing tests (for example
ES2022 at 53.8% strict Passed / Executed in the latest CI run). Implementing a
still-skipped feature narrows the gap between the two rates — and can briefly
lower Passed / Executed as previously skipped tests start executing and failing.

**Do not sum strict and non-strict figures.** Each file is run in both modes, so
adding them double-counts the underlying test files. Report per-mode or not at
all. See [TEST262.md](TEST262.md#output-format) for the runner-level definition
and [supported-features.md](supported-features.md) for per-category pass rates,
Annex B legacy features, and not-yet-implemented features.

---

## Adoption Roadmap

The primary direction after v0.6.0 is to make `js_engine` a dependable embedded
JavaScript runtime for MoonBit applications. An application author should be
able to embed trusted JavaScript on every supported target without depending on
internal `Interpreter` or `Value` representations.

Browser compatibility, DOM APIs, crater-specific context lifecycle, and a
security sandbox are outside this roadmap. Test262 improvement continues as a
quality stream, but adoption is evaluated by whether an external consumer can
understand, integrate, control, and diagnose the stable facade.

The durable product principles and non-goals are defined in
[Embedded Runtime Vision](design/embedded-runtime-vision.md).

### Completed baseline — v0.6.0 release

v0.6.0 established the release baseline:

- post-merge `main` conformance and unit-test results were recorded in the
  changelog;
- [`moon.mod`](../moon.mod) and the `v0.6.0` tag record the released package
  version; and
- the [Adoption foundation workflow](../.github/workflows/adoption.yml) checks
  and tests the repository on native, JavaScript, Wasm, and Wasm-GC.

The release process also included maintainer-reported Mooncakes publication and
installation from an empty external project. Those manual smoke results are not
independently verifiable from repository artifacts. The next stage therefore
treats reproducible external-consumer CI as required evidence rather than as an
already-complete gate.

### 1. Establish the adoption contract

Harden and document the existing facade before adding another host-integration
primitive.

- Audit every root-package entry point and classify it as **stable embedding**,
  **compatibility**, or **advanced/internal**. Existing APIs that expose runtime
  values may remain compatible, but they are not the model for new stable APIs.
- Maintain the stable [`docs/EMBEDDING.md`](EMBEDDING.md) from released and
  characterized behavior. The interpreter/value cookbook lives at
  [`docs/advanced-embedding.md`](advanced-embedding.md), avoiding filenames
  that differ only by case.
- Document the strict JSON acceptance and rejection matrix, queue checkpoint
  meaning and ordering, non-rollback after failure, Engine reuse expectations,
  target guarantees, and the trusted-script boundary.
- Add characterization tests for every documented lifecycle and failure claim.
- Maintain the standalone [external-consumer fixture](../integration/external_consumer/)
  that imports only the supported facade and runs the Rule Engine acceptance
  scenario on all four targets. Keep release smoke testing from Mooncakes
  distinct from PR testing of the checkout under review.
- Add focused baselines for one-shot execution and repeated calls through a
  persistent Engine. These establish usage costs; optimization still requires
  an isolated benchmark that reproduces a bottleneck.

Acceptance: a consumer starting from an empty module can follow only the stable
embedding guide and pass the portable Rule Engine scenario without importing
interpreter internals.

### 2. Decide the execution contract

Before host callbacks, record and test the runtime lifecycle contracts that are
expensive to retrofit:

- concurrent use and same-Engine re-entry;
- reusability after parse, JavaScript, JSON-boundary, interruption, and internal
  failures;
- pending-job state after each failure category;
- structured error evolution and compatibility of new error classifications;
- step accounting, recursion limits, interruption observation points, and the
  relationship between a bounded call and queued jobs; and
- target-dependent diagnostic details outside the portable contract.

These decisions belong under `docs/decisions/`. They must be settled from the
embedder contract rather than inherited accidentally from internal helpers.

### 3. Inject host-owned JSON data

Add stable JSON injection before exposing executable host capabilities. The
candidate remains an Engine operation taking a name and `Json`, but this
roadmap does not freeze its exact name or signature.

Decide before implementation:

- whether the value is visible as a global binding, a global-object property,
  or both;
- collision behavior with existing lexical and object bindings;
- writable, configurable, and enumerable attributes;
- host-side update and redefinition policy; and
- error classification and source-compatibility consequences.

Conversion must use the direct JSON-to-realm bridge. It must not invoke the
mutable global `JSON` object or execute user JavaScript.

### 4. Add minimum execution guardrails

Implement the minimum execution controls before granting JavaScript synchronous
host capabilities:

- a deterministic step budget;
- a recursion or stack-depth guard;
- explicit interruption at documented observation points;
- distinct structured failure classification;
- documented non-rollback of mutations before interruption; and
- Engine-integrity and reuse tests after limits are reached.

Infinite-loop and deep-recursion acceptance tests must terminate predictably on
native, JavaScript, Wasm, and Wasm-GC. These controls protect host availability
from faulty trusted scripts; they do not create a security sandbox.

### 5. Expose synchronous host capabilities

Add a stable synchronous callback boundary without exposing raw runtime values.
The contract must cover:

- strict JSON arguments and return values;
- conversion of expected host failures into catchable JavaScript exceptions;
- rejection or detection of same-Engine re-entry;
- callback ownership, lifetime, and removal;
- execution-budget treatment across the host boundary; and
- explicit non-support for Promise and asynchronous callbacks.

Prefer a model in which host functions are reviewable capabilities rather than
an unstructured collection of ambient globals. The Rule Engine acceptance
scenario should then cover configuration or data access and an observable host
operation, not only a pure decision function.

### 6. Improve operational maturity

Once the boundary and controls are stable, improve the embedder's ability to
reuse and operate the runtime:

- structured diagnostics with source context and runtime-reuse status;
- an opaque parse/compile-once script abstraction if benchmarks and consumer
  experience justify it;
- execution statistics useful for limits and diagnosis;
- deterministic providers for host-dependent facilities where needed; and
- compatibility tests that exercise released consumers across upgrades.

### Deferred

Defer these until concrete embedder demand appears:

- Promise-aware asynchronous calls;
- calling ES module exports through the stable facade;
- snapshots or serialization;
- a bytecode VM as the default runtime;
- DOM or browser APIs;
- a crater adapter; and
- a V8- or QuickJS-compatible runtime interface.

### Continuing quality streams

Test262 fixes remain welcome in parallel, especially narrow spec-anchored fixes
and justified removal of skip buckets. They do not reorder the adoption
sequence. Before changing release notes or public conformance claims, regenerate
per-mode figures from CI artifacts with `make test262-report`; never hand-edit
the numbers. For release notes, use `make test262-report
ARGS="--format=changelog"`.

Architecture-state ownership remains a maintenance invariant. Bytecode and
closure-conversion work remain measured optimization or research paths rather
than a second source of JavaScript semantics. Do not promote an internal
execution strategy without a benchmark that demonstrates the relevant embedder
bottleneck.

---

## History

- [archive/executed-roadmap-history.md](archive/executed-roadmap-history.md) — completed roadmap plans, stale planning snapshots, and executed structural stages moved out of this file.
- [archive/phase-history.md](archive/phase-history.md) — older detailed implementation notes for completed phases.
- [archive/](archive/) — completed or superseded design documents.

For design principles, value model, control flow, and host integration, see
[architecture.md](design/architecture.md).
