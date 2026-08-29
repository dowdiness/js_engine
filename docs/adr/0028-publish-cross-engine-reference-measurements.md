---
status: accepted
---

# Publish cross-engine reference measurements

## Context

The benchmark dashboard tracks js_engine's internal microbenchmarks. Those
measurements help maintainers locate regressions and evaluate isolated
optimizations, but they do not show how js_engine runs the same external
JavaScript workload as other engines.

The dashboard will therefore add Cross-Engine Reference as a separate
category. It will report selected JetStream workload results from js_engine and
standard engine shells under one reproducible measurement contract. This
category describes js_engine's current position and shell
compatibility. It is not an official whole-suite JetStream score, an
optimization selector, or a merge gate.

## Implementation status

The decision is accepted. Candidate compatibility probes and their pinned
inputs are implemented. The Cohort Lock, one-job cohort runner, balanced
schedule, A/A calibration, published dataset, and dashboard category are not
implemented. Until those parts exist and a round passes calibration, probe
timings remain diagnostic and no Reference Baseline exists.

## Terms

- A **reference candidate** is an engine considered for comparison.
- A **candidate probe** runs the selected workload with a pinned engine payload
  to determine whether that engine can participate.
- A **Reference Workload** is the pinned external program that every admitted
  engine runs and whose official correctness check every result must pass.
- A **comparison cohort** is the exact set of compatible engines and inputs
  measured together.
- A **Cohort Lock** is the immutable manifest that identifies one comparison
  cohort.
- A **measurement round** is one execution of every cohort member on one
  runner.
- **A/A calibration** measures identical inputs repeatedly to determine whether
  the runner and measurement profile are stable enough to publish.
- A **Reference Baseline** is a published measurement round that passed
  calibration and all correctness checks.

## Candidate admission

The reference candidates are js_engine, V8, JavaScriptCore, SpiderMonkey, and
QuickJS-ng. Each candidate uses its standard command-line shell in its ordinary
non-debug configuration. js_engine uses its default bytecode execution policy.
Repository-owned compatibility adapters do not make an otherwise incompatible
shell eligible.

A candidate probe produces exactly one outcome:

- `compatible`: discovery, execution, workload validation, and structured
  result validation succeeded;
- `incompatible`: the engine ran but could not satisfy the workload contract;
  or
- `probe_failed`: acquisition, launch, timeout, or infrastructure failure left
  compatibility undetermined.

An incompatible candidate remains visible in the compatibility table and has
no performance value. A `probe_failed` outcome is diagnostic evidence, not an
engine compatibility result.

The generation 1 evidence admits js_engine, V8, JavaScriptCore, and
SpiderMonkey. QuickJS-ng generation 1 is incompatible because its standard
shell does not provide the isolated global required by JetStream's shell
runner. QuickJS-ng remains in the compatibility table and outside the
generation 1 performance cohort.

## Cohort identity

One schema-versioned, content-addressed manifest is the Cohort Lock. It records:

- the cohort generation and ordered member list;
- the JetStream revision and selected-workload identity;
- the engine acquisition tool (`jsvu`) version where applicable;
- each engine's version, payload fingerprint, executable, flags, and loader
  environment;
- the runner label and measurement profile; and
- the expected correctness oracle and structured-result contract.

Each round records the manifest digest plus the actual runner image identity,
operating system, and architecture. Any manifest change creates a new cohort.
The policy does not prescribe when a new generation must be created.

## Workload contract

Only an upstream workload with an official correctness oracle can become a
Reference Workload. `navier-stokes` is the generation 1 workload. Every engine
runs the same pinned JetStream source with upstream normal iteration and
scoring settings.

The retained result contains the official workload score and its first,
average, and worst values. A selected-workload result must always be labelled
as such; it is not the overall JetStream 3 score.

## Measurement round

Every cohort member runs in one `ubuntu-24.04` job with the same locked inputs.
Each member runs the same number of times under a deterministic, balanced
schedule. The schedule prevents one engine from always occupying the same
ordinal position or preceding another, and the raw artifact records the exact
execution order.

Bounded A/A calibration selects the repetition count for the cohort and
profile. Calibration may instead report that GitHub-hosted measurement is too
noisy to publish. It does not establish a universal sample count or an
automatic regression threshold.

A performance round is valid only when every cohort member produces a valid
official result for every required repetition. Acquisition, launch, timeout,
and correctness failures are preserved, but they cannot produce a partial
performance comparison.

## Storage and publication

The weekly and manually requested dashboard publication paths must run Internal
Benchmarks and Cross-Engine Reference independently. Failure in one category
must not suppress valid evidence from the other.

Cross-engine evidence must use one dedicated, schema-versioned dataset on the
existing dashboard branch. The dataset must store the Cohort Lock, round
provenance, compatibility outcomes, official raw results, and repetitions. It
must not store a permanent reference-engine denominator, persistent rank, or
cross-cohort delta.

The dashboard may derive a ratio or ordering only from observations in the
same successful cohort round. Derived presentation remains separate from the
measurement evidence.

## Interpretation

A Reference Baseline is a dated snapshot of one cohort on one hosted runner.
GitHub's runner label fixes a software environment class, not physical
hardware. Absolute values from different dates or cohort generations are not a
stable performance trend.

Routine optimization and regression decisions continue to use isolated
microbenchmarks and same-purpose base/head comparisons. Candidate probes remain
compatibility evidence until their inputs are included in a Cohort Lock and the
round passes A/A calibration.

## Consequences

This design keeps compatibility, performance measurement, and dashboard
presentation as separate claims. It avoids a special reference engine, keeps
failed candidates visible without inventing scores, and preserves enough raw
evidence to change dashboard presentation without rewriting historical data.

The first Reference Baseline requires a cohort manifest, a one-job balanced
runner, and successful A/A calibration. A dedicated self-hosted performance
machine can replace the hosted-runner class later if measured variance or
publication goals justify its operational cost.
