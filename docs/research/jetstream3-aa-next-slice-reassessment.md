# What should follow the Cohort Lock reassessment?

**Status:** research reassessment; not an ADR or an implementation plan

## Decision

Do **not** build a production cross-engine runner, a reusable round-result
contract, or an ADR amendment before observing one bounded two-pass experiment.
The next slice should be a manually dispatched, one-job experiment that reuses
the existing pinned probe adapters, executes the admitted engines in a
deterministic forward/reverse schedule, and uploads the raw reports plus a small
run index. It is a feasibility experiment about whether the hosted-CI caller is
usable, not A/A calibration and not the first release of a measurement
platform.

The common caller is GitHub Actions: it needs one command to acquire the
pinned source and payloads, invoke the existing adapters, and retain evidence.
It does not yet need a caller-facing generic cohort interface. Existing probe
specifications are already a suitable seam: their adapters validate the
JetStream revision, checkout cleanliness, exact engine version, executable
location, and payload digest before an execution begins
([`jetstream3_reference_probe_core.js`](../../scripts/jetstream3_reference_probe_core.js#L25-L64),
[`jetstream3_reference_probe_core.js`](../../scripts/jetstream3_reference_probe_core.js#L184-L249)).

## What is known already

The checked-in external probe specifications pin a generation, `jsvu` version,
JetStream commit, workload, engine version, executable, and payload SHA-256.
The shared adapter then records the resolved payload digest, environment,
scope, assessment, and complete process output in JSON
([`jetstream3_reference_probe_core.js`](../../scripts/jetstream3_reference_probe_core.js#L259-L287)).
The native admission command records analogous engine, toolchain, environment,
scope, assessment, and probe facts
([`jetstream3_admission.js`](../../scripts/jetstream3_admission.js#L287-L342)).

The missing question is consequently experimental: can repetitions made in a
single GitHub-hosted job distinguish normal run-to-run variation from a result
worth publishing? ADR 0028 already says that A/A calibration may conclude that
GitHub-hosted measurement is too noisy, and does not prescribe a universal
sample count ([ADR 0028](../adr/0028-publish-cross-engine-reference-measurements.md#L102-L118)).
That question cannot be settled by a more elaborate schema.

The proposal is consistent with established tools, but deliberately much
smaller than any of them:

- Chromium Pinpoint uses repeated, balanced base/experiment runs on the same
  device precisely to remove across-device variation; it randomizes which arm
  runs first and balances first position. That is evidence for testing order
  and repetition before interpreting a comparison, not evidence for copying
  Pinpoint's platform. [Chromium Perf Try Bots](https://chromium.googlesource.com/chromium/src/%2B/main/docs/speed/perf_trybots.md)
- Google Benchmark has a one-repetition dry-run for fast validity checks,
  supports repeated runs and randomized interleaving, and keeps contextual
  machine/run facts beside machine-readable results. This supports a bounded
  first experiment with raw samples and provenance. [Google Benchmark User
  Guide](https://google.github.io/benchmark/user_guide.html)
- Firefox's Talos converts timing logs into structured Perfherder data and
  archives individual base/reference replicates; Mozilla recommends CI try
  runs for performance comparison because local and CI hardware differ.
  This supports retaining raw repetitions before a dashboard summary.
  [Talos](https://firefox-source-docs.mozilla.org/testing/perfdocs/talos.html)
  and [Mozilla performance testing](https://firefox-source-docs.mozilla.org/testing/perfdocs/perftest-in-a-nutshell.html)
- BenchExec and ReBench use a declarative run definition and retain individual
  execution results. They demonstrate that a definition plus evidence is a
  useful eventual shape, but their multi-tool configuration interfaces solve a
  broader problem than this first fixed cohort. [BenchExec
  documentation](https://github.com/sosy-lab/benchexec/blob/main/doc/benchexec.md)
  and [ReBench configuration](https://rebench.readthedocs.io/en/latest/config/)

GitHub Actions already supplies the essential CI facts: `GITHUB_SHA`,
`GITHUB_WORKFLOW_SHA`, run ID/attempt, and runner OS/architecture/environment.
The upload-artifact action also produces a SHA-256 digest for every uploaded
artifact. [GitHub Actions variables](https://docs.github.com/en/actions/reference/workflows-and-actions/variables)
and [artifact validation](https://docs.github.com/en/actions/tutorials/store-and-share-data)
make an additional custom signing or canonicalization layer unnecessary for
this experiment.

## Sequences compared

| Sequence | First change | What it learns | Cost before evidence | Result |
| --- | --- | --- | --- | --- |
| A. Platform first | Generic cohort module, schema/versioning, contract tests, balanced scheduler, ADR rewrite | Only that a proposed abstraction is internally consistent | Commits a wide interface before knowing whether hosted measurement is viable | Reject. It creates a shallow caller interface whose parameters mirror implementation choices. |
| B. Standalone lock first | Content-addressed manifest, canonicalization, validators, and a new definition source | That a document can be hashed | Does not test noise, ordering, or acquisition/run interaction; duplicates the current probe seam | Reject. |
| C. Raw feasibility workflow only | Manually dispatched single job, existing adapters, mirrored two-pass order, raw reports and run index | Correctness, completion, artifact size, variation, and missing facts | Small and reversible; its fixed caller may be deleted or promoted | Choose. |
| D. Manual reuse of today's separate jobs | Re-run existing admission and individual probe jobs | Candidate compatibility only | Cannot observe a coherent same-runner cohort, because candidates run in distinct jobs | Reject as insufficient. The workflow currently separates candidate probes into manual-dispatch jobs ([workflow](../../.github/workflows/jetstream3-admission.yml#L111-L154)). |

Sequence C has the best depth for its only caller: *run one specified feasibility
experiment and emit evidence*. Its implementation may contain acquisition,
invocation, failure preservation, and indexing complexity, but the workflow
interface remains one fixed manual dispatch. Existing candidate adapters remain
the only engine-specific adapters. This preserves locality: an engine shell
difference stays with its current probe, rather than leaking into a generic
cohort abstraction.

## Reversible and irreversible decisions

Reversible now:

- fixed mirrored order, two passes, one workload, and manual dispatch;
- a run index local to this experiment;
- deleting the experiment if observed variation makes hosted publication untenable;
- promoting its observed fields into a later definition/evidence schema.

Expensive to reverse, so defer:

- a public, schema-versioned dataset and dashboard reader;
- a generic runner interface or scheduler that every future workload must use;
- a standalone lock document, canonical JSON, or content-address identity;
- a published ranking, ratio, regression threshold, or scheduled publication;
- wording in ADR 0028 that presents one unmeasured implementation as policy.

The current workflow proves the repository can retain ordinary raw reports for
90 days ([workflow](../../.github/workflows/jetstream3-admission.yml#L99-L109)).
The experiment should use the same artifact mechanism and add the GitHub run
facts above; it should not change retention, dashboard storage, or publication
paths.

## Branch-first validation

The experiment does not require a pull request before it can run. The existing
JetStream workflow is already present on the default branch and declares
`workflow_dispatch`. GitHub requires the workflow to exist on the default
branch, but permits the caller to select another Git ref for the run. The
implementation branch can therefore be pushed and dispatched with `--ref`
before the project decides whether its code and contract deserve a pull
request. [GitHub manual workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)

Current evidence also makes a complete-cohort feasibility run inexpensive
enough to prefer over a js_engine-only proxy. In workflow run
[`33247167047`](https://github.com/dowdiness/js_engine/actions/runs/33247167047),
the native admission job completed in under three minutes, and its retained
`navier-stokes` report recorded 7,058 ms for workload execution. Each external
shell probe job completed in under 35 seconds. Acquisition and build dominate
the current job, so invoking all admitted engines twice after one setup is a
small incremental cost and exercises the actual cross-engine seam.

## Exact first branch

Create one **measurement-only, manually dispatched feasibility branch** with
this deliberately narrow scope:

1. Add one `workflow_dispatch`-only, `ubuntu-24.04` job to the existing
   JetStream workflow (or a clearly experiment-named adjacent workflow). It
   installs the already pinned toolchain/source and acquires the existing
   admitted external payloads once.
2. Add a private experiment script and its deterministic test. The script reads
   the existing V8, JavaScriptCore, and SpiderMonkey probe specifications and
   invokes their existing adapters plus the existing js_engine admission path.
   It executes one forward pass and one reverse pass and emits one run-index
   JSON. Mirroring gives every candidate one early and one late position without
   pretending that two observations estimate a stable variance threshold.
3. The index contains source/workflow commit, run ID/attempt, runner facts,
   exact probe-spec bytes SHA-256 and paths, actual order, output paths, and
   validity. The individual existing reports retain each raw JetStream result.
4. Upload one evidence artifact containing the index and all individual raw
   reports. A missing, failed, timed-out, or invalid member marks the experiment
   invalid without fabricating a partial comparison.

The evidence grain is one candidate invocation. Its candidate key is
`(workflow run, pass, member)`: the fixed generation-1 experiment therefore
expects eight unique observations. Completeness, unique keys, shared
JetStream/workload identity, a recorded result-or-failure for every observation,
and monotonic start/end times are stable checks worth automating now. Score
spread, order effects, and acceptable variance are findings to inspect, not
hard-coded gates in this experiment.

Push the branch and manually dispatch the existing workflow at that ref. Run it
at least twice and inspect both artifacts before opening a pull request. If the
experiment is not viable, stop without merging measurement machinery. If it is
viable, refine the same branch into one focused implementation-and-documentation
pull request; update ADR 0028 only from the observed evidence fields and
remaining publication requirements.

Do **not** add a generalized measurement-definition file, Cohort Lock,
balanced scheduler, dashboard dataset, publication schedule, performance gate,
or cross-engine ratio. Do **not** modify ADR 0028 or user-facing development
documentation before the branch runs: the current text correctly calls all diagnostic
timings non-baseline evidence ([ADR 0028](../adr/0028-publish-cross-engine-reference-measurements.md#L21-L28);
[`development.md`](../development.md#L165-L202)). A short in-code comment and
the branch description must state that this is a feasibility experiment. Amend
the ADR on the same branch only after the artifact shows which provenance fields
and schedule properties are actually required for publication.

After two or more manual runs, review correctness, per-engine raw-score spread,
the effect of first/second pass, runner facts, and artifact size. If the data is
stable enough to justify publication work, then introduce the smallest stable
definition/evidence interface based on those observations; otherwise stop or
move the measurement to dedicated hardware. This order tests the actual seam
before making it a public module.

## Observed feasibility result

The experiment was executed twice from commit
`bfd595532a34c0ac51c0c64e10b6a29d5057bbf2`:

- [workflow run 33301938499](https://github.com/dowdiness/js_engine/actions/runs/33301938499)
- [workflow run 33301946501](https://github.com/dowdiness/js_engine/actions/runs/33301946501)

Both experiments were complete and valid: every candidate produced its two raw
reports, all official correctness checks passed, and both indexes recorded the
same source/workflow commit, JetStream revision, OS release, architecture, and
Node version. Each compressed artifact was approximately 9.4 KB.

The four scores per engine are descriptive feasibility data, not a calibrated
sample. They nevertheless identify a profile problem:

| Engine | Minimum score | Maximum score | Population CV | Relative range |
| --- | ---: | ---: | ---: | ---: |
| js_engine | 1.5402 | 1.5671 | 0.68% | 1.73% |
| V8 | 640.1288 | 708.6151 | 4.20% | 10.36% |
| JavaScriptCore | 639.5803 | 726.0148 | 5.47% | 12.79% |
| SpiderMonkey | 624.8925 | 670.2674 | 2.83% | 6.91% |

The raw external-shell workload executions lasted only 39–76 ms, while each
js_engine execution lasted approximately 6.5 seconds. The current candidate
adapters intentionally force two iterations and one worst-case sample
([V8 adapter](../../scripts/jetstream3_v8_probe.js#L42-L53)); the pinned
JetStream source defines normal defaults of 120 iterations and four worst-case
samples
([JetStreamDriver.js](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/JetStreamDriver.js#L30-L31)).

Consequently, these runs do not show that the hosted runner is too noisy. They
show that a compatibility probe profile is too short to assess hosted-runner
noise for fast engines. The experiment therefore stops before a pull request.
The next evidence-driven slice is to separate the existing compatibility
profile from an upstream-normal measurement profile, repeat the same two-run
experiment, and only then decide whether the runner and evidence contract merit
promotion.
