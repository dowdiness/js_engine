# Cross-engine reference measurement design

**Status:** supporting rationale for ADR 0028

## Purpose

[ADR 0028](../adr/0028-publish-cross-engine-reference-measurements.md) defines
the normative contract for publishing selected JetStream workload results from
multiple JavaScript engine shells. This document explains why that contract
uses compatibility admission, immutable cohorts, one-job measurement rounds,
balanced execution order, and raw result storage.

The design answers one public question: how does js_engine run the same pinned
external workload as a small set of standard JavaScript engine shells under one
recorded environment? It does not identify optimization targets or replace the
repository's internal microbenchmarks.

## Implementation status

The candidate-probe stage is implemented. The immutable cohort, calibrated
measurement round, and dashboard snapshot stages are planned work governed by
ADR 0028. Probe timings are compatibility diagnostics and cannot be published
as cross-engine performance measurements.

## Measurement lifecycle

The system has four stages:

```text
candidate probe
    -> immutable comparison cohort
    -> calibrated measurement round
    -> published cohort snapshot
```

A candidate probe establishes shell compatibility. Compatible candidates and
their exact inputs form a comparison cohort. A/A calibration determines whether
the runner and repetition profile are stable enough to measure that cohort. A
successful round then becomes a dated dashboard snapshot.

Each stage produces evidence for the next stage. A timing observed during a
candidate probe cannot bypass calibration and become a public performance
value.

## JetStream boundary

JetStream 3 supports execution in engine shells and owns workload setup,
iteration timing, correctness validation, and result serialization. The
repository runs the pinned upstream shell runner instead of copying a workload
or implementing a separate timing loop.
[Pinned JetStream shell runner](https://github.com/WebKit/JetStream/tree/7769b693502fa80f28a97bbfacd3296e0513acc5#shell-runner).

For most JavaScript workloads, JetStream combines startup, average, and
worst-case performance into a dimensionless score using a geometric mean. It
also states that scores from different JetStream versions are not comparable.
The dataset therefore retains the official score and its component values and
keeps each JetStream revision in a separate cohort.
[JetStream methodology](https://browserbench.org/JetStream/in-depth.html).

`navier-stokes` is the generation 1 Reference Workload because it has an
upstream checksum oracle and runs through the official shell driver. The
dashboard labels its result as a selected-workload score rather than an overall
JetStream 3 score.

## Candidate compatibility

Every candidate uses its standard command-line shell in its ordinary non-debug
configuration. js_engine uses its default bytecode execution policy. A probe
pins the engine version and payload fingerprint (a checksum of the acquired
engine package), runs selected-test discovery, executes `navier-stokes`, checks
its oracle, and validates the structured result.

Generation 1 has the following eligibility evidence:

| Candidate | Outcome | Cohort eligibility | Source-controlled input |
| --- | --- | --- | --- |
| js_engine | compatible | eligible | [admission runner](../../scripts/jetstream3_admission.js) |
| V8 | compatible | eligible | [probe specification](../../scripts/jetstream3_v8_probe.json) |
| JavaScriptCore | compatible | eligible | [probe specification](../../scripts/jetstream3_javascriptcore_probe.json) |
| SpiderMonkey | compatible | eligible | [probe specification](../../scripts/jetstream3_spidermonkey_probe.json) |
| QuickJS-ng | incompatible | compatibility table only | [probe specification](../../scripts/jetstream3_quickjs_probe.json) |

The [admission workflow](../../.github/workflows/jetstream3-admission.yml) runs
these inputs and preserves each structured report as a CI artifact. The pinned
inputs remain in the repository after the time-limited CI artifacts expire.

QuickJS-ng's standard shell does not expose the isolated global required by
JetStream's generic shell path. An isolated global is a clean JavaScript global
object kept separate from the runner itself. Running the workload in the
runner's global object would change that isolation rule, so the comparison does
not add a repository-owned adapter. This keeps all candidates on the same
policy: use the standard shell contract or report incompatibility.

Acquisition, process launch, signal termination, and timeout failures produce
`probe_failed`. This outcome leaves compatibility undetermined and prevents an
infrastructure fault from becoming an engine claim.

## Cohort provenance

The Cohort Lock is one schema-versioned, content-addressed manifest. It contains
all inputs needed to interpret a round:

- JetStream revision and Reference Workload identity;
- cohort generation and ordered members;
- acquisition tool version;
- engine versions, payload fingerprints, executables, flags, and loader
  environments;
- runner label and execution profile; and
- correctness and structured-result requirements.

The manifest digest is the cohort identity. Each result also records facts that
are known only after a hosted runner starts, including the runner image,
operating system, and architecture. Changing a locked input creates another
cohort and preserves the earlier results as a separate snapshot.

GitHub provisions a new virtual machine for each standard hosted-runner job and
updates runner images over time. `ubuntu-24.04` fixes an environment class but
does not identify stable physical hardware.
[GitHub-hosted runner model](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners#runner-images).

## Experimental design

All cohort members run in one job so they share the same virtual machine and
time window. Separate jobs would introduce avoidable differences in host and
start time before any engine executes.

Sequential execution can still be affected by temperature, background load,
and monotonic drift. The runner therefore gives every engine the same number of
observations and uses a deterministic balanced schedule. Across the complete
schedule, every engine occupies each required ordinal position and engine pairs
occur in both orders. The raw artifact records the schedule actually used.

Chromium Pinpoint provides the closest operational precedent: it runs control
and experiment on the same device, balances which arm runs first, repeats both
arms, and aggregates the observations.
[Chromium performance try jobs](https://chromium.googlesource.com/chromium/src/+/main/docs/speed/perf_trybots.md).
Randomized-block guidance reaches the same general principle: hold a major
nuisance factor constant within a block and balance or randomize treatment
order inside that block.
[NIST randomized block designs](https://www.itl.nist.gov/div898/handbook/pri/section3/pri332.htm).

A/A calibration runs identical inputs through the planned job shape. It selects
a bounded repetition count or rejects publication as too noisy. The project
does not copy a universal count or significance threshold from another system.
Mozilla's performance tooling supports this evidence-first approach by keeping
raw replicates, spread, deltas, and confidence information available beneath
summary views.
[Mozilla PerfCompare](https://firefox-source-docs.mozilla.org/testing/perfdocs/perfcompare.html).

## Round validity

A performance comparison requires a complete block: every cohort member must
produce a valid official result for every required repetition. A missing member
would change the comparison set and could make a partial result look stronger
than the locked cohort.

Failures remain useful evidence. The system stores acquisition, launch,
timeout, correctness, and serialization failures with their provenance. The
compatibility view may display those outcomes, while the performance view marks
the round invalid and publishes no partial comparison.

## Public data model

The dataset stores facts from each invocation:

- Cohort Lock and runner provenance;
- candidate outcome and correctness evidence;
- official score and first, average, and worst values;
- repetition number and execution order; and
- raw structured result and diagnostic output references.

The dataset has no permanent reference-engine denominator. QuickJS-ng cannot
serve that role because generation 1 has no valid performance score, and any
single permanent denominator would couple the schema to one engine's continued
eligibility.

The dashboard may calculate a ratio or ordering from members of one successful
round. That display value is reproducible from raw facts and is not stored as
measurement evidence. Results from different cohort generations remain
separate snapshots.

## Alternatives

| Alternative | Reason not selected |
| --- | --- |
| One job per engine | Different virtual machines and start times confound the comparison. |
| A permanent V8 or QuickJS-ng denominator | The schema would depend on one engine remaining eligible. |
| Floating engine versions | A later run could not reproduce the same cohort. |
| Browser automation | It compares browser products and host APIs instead of the standard engine shells in scope. |
| A self-hosted performance fleet | It provides stronger hardware control but adds machine operations, trust, security, and availability work. |
| Automatic regression thresholds | The project has no calibrated noise model or performance laboratory to support them. |

The hosted one-job design controls the environment factors available to this
project without introducing a benchmark service. A self-hosted runner remains
an option if calibration shows that hosted snapshots are not publishable.

## Delivery units

Implementation proceeds as independent changes:

1. define and validate the immutable cohort manifest;
2. execute all eligible engines in one job and retain raw results;
3. add the deterministic balanced schedule;
4. run bounded A/A calibration; and
5. publish a cohort snapshot only after calibration and round validation pass.

Keeping these units separate prevents compatibility, measurement policy, and
dashboard presentation from becoming one inseparable workflow.
