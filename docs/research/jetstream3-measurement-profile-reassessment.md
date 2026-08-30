# JetStream 3 measurement-profile reassessment

**Status:** adopted on the experiment branch; not merged.

## Question

The completed feasibility experiment used `navier-stokes` with
`--iteration-count=2 --worst-case-count=1`. Should the next cross-engine
measurement hard-code JetStream's current `120/4` defaults, omit the two
overrides, or adopt another profile?

## Findings

JetStream's ordinary benchmark score is the geometric mean of its `First`,
`Worst`, and `Average` sub-scores. `First` is the first iteration; `Worst` is
the mean of the slowest *M* iterations after the first; and `Average` is the
mean of every iteration after the first. The project describes the normal
shape as often 120 iterations and usually four worst samples
([JetStream 3 in-depth analysis](https://browserbench.org/JetStream/in-depth.html#in-depth-analysis)).
The pinned driver implements that same shape: a benchmark score is the
geometric mean of its sub-scores, the first iteration is removed before the
worst/average calculations, and the slowest `worstCaseCount` remaining
iterations are averaged
([driver score](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/JetStreamDriver.js#L979-L982),
[result processing](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/JetStreamDriver.js#L1491-L1519)).

With two iterations, there is exactly one post-first result. Therefore the
current feasibility profile makes `Worst` and `Average` the same observation;
it cannot measure the normal worst-versus-average distinction. The two saved
experiments show the effect in practice: their external `navier-stokes`
executions lasted 39--76 ms and had 2.83--5.47% population CV over four
scores, whereas js_engine took about 6.5 s and had 0.68% CV. This is evidence
that the *profile* is short for the fast engines, not evidence that the hosted
runner is unusable. The raw reports and indices are retained by workflow runs
[33301938499](https://github.com/dowdiness/js_engine/actions/runs/33301938499)
and [33301946501](https://github.com/dowdiness/js_engine/actions/runs/33301946501).

For this pinned revision, `navier-stokes` supplies neither an `iterations` nor
a `worstCaseCount` value, so it resolves to the driver's `120` and `4`
defaults ([benchmark registration](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/JetStreamDriver.js#L2055-L2062),
[defaults](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/JetStreamDriver.js#L30-L31)).
The CLI flags are explicitly *default-count overrides*
([CLI definitions](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/cli.js#L28-L42)), and the driver gives those overrides precedence over a workload's own values
([iteration resolution](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/JetStreamDriver.js#L911-L928)).

## Options

| Profile | Comparability | Interface and maintenance consequence | Decision |
| --- | --- | --- | --- |
| Retain `2/1` | Only compares compatibility probes; collapses `Worst` and `Average` | Already available, but answers the wrong measurement question | Reject for cross-engine measurement |
| Hard-code `120/4` | Matches this pinned `navier-stokes` today | Copies upstream policy into every adapter and would override a future workload-specific choice | Reject |
| Omit both count overrides | Uses the selected JetStream revision's workload-aware normal profile; currently resolves to `120/4` | A fixed profile needs no public count parameters | **Choose** |
| Per-engine/adaptive time budget | Changes iteration populations and score semantics by engine | A shallow interface with incomparable results | Reject |

## Recommendation

Add no general count-setting interface. Keep the existing `2/1` compatibility
adapters unchanged and make the fixed cross-engine experiment's one
**upstream-default measurement profile** omit both count flags. Its seam is
the already-fixed experiment command, not each candidate adapter. That is a
deep module for its sole caller: acquisition, shell adaptation, order, raw
report retention, and validation stay inside; the caller learns only how to
run the fixed measurement. It maximizes leverage and locality without turning
two internal numbers into a long-lived caller contract.

The evidence must record: the profile name and absence of count overrides;
the exact JetStream commit and clean checkout; workload; complete command;
engine version/payload digest; runner and toolchain facts; timeout; order and
pass; duration; and the unmodified JSON report. The command plus pinned source
commit are the authoritative resolved-count evidence; do not duplicate a
second project-owned default table.

The observed 2-iteration js_engine duration implies roughly 6.5 minutes for
one 120-iteration invocation if iteration cost remains similar. Treat that as
a planning estimate, not a performance result: first run one non-comparative
upstream-default smoke pass with a timeout above that estimate. If every
candidate succeeds, run the existing forward/reverse two-pass experiment twice
with the same profile. Only then assess score spread and any promotion to
published comparison data.

## Implemented branch shape

The compatibility commands still default to their explicit `2/1` overrides.
The private reference experiment selects the fixed `upstream-default` profile
for every cohort member. Profile resolution is a deterministic function shared
by the native and external-shell runners; it returns the command arguments and
the corresponding evidence fields. The experiment records the selected profile
and null count overrides in both the run index and the individual reports.

The experiment-only process timeout is fifteen minutes and its manual workflow
job timeout is forty minutes. These are execution bounds, not performance gates
or published benchmark policy.

## Observed branch validation

The branch was dispatched twice at commit
`ee74c47a74b743595d754af1dc48fcf30a167774`:

- [workflow run 33306918682](https://github.com/dowdiness/js_engine/actions/runs/33306918682)
- [workflow run 33307441059](https://github.com/dowdiness/js_engine/actions/runs/33307441059)

Both experiments were complete and valid. All sixteen candidate observations
recorded `upstream-default`, null count overrides, commands without either count
flag, the same JetStream and repository commits, and complete raw results. The
first experiment job completed in 11 minutes 21 seconds; the second completed
in 19 minutes 31 seconds.

The two js_engine invocations in the slower job took about 8 minutes 28 seconds
and 8 minutes 21 seconds. That left too little operational headroom under the
initial ten-minute process timeout, so the bound was raised to fifteen minutes.
This changes failure containment only; it does not change the workload, score,
or accepted evidence.

The two scores within each workflow were reasonably close, but absolute scores
were not stable across the two GitHub-hosted jobs:

| Engine | Run 1 mean | Run 2 mean | Run 1 / Run 2 | Combined CV | Combined relative range |
| --- | ---: | ---: | ---: | ---: | ---: |
| js_engine | 2.1102 | 1.1874 | 1.777 | 27.99% | 56.98% |
| JavaScriptCore | 1105.8841 | 674.3918 | 1.640 | 24.31% | 52.04% |
| SpiderMonkey | 910.2236 | 558.8312 | 1.629 | 23.99% | 50.41% |
| V8 | 1081.8770 | 697.8260 | 1.550 | 22.25% | 52.52% |

The slowdown affected every engine, which is consistent with a materially
different hosted-runner execution environment. It did not scale every engine
equally. Even same-job external-engine-to-js_engine score ratios had relative
ranges of about 12% for JavaScriptCore, 12% for SpiderMonkey, and 22% for V8
over the four paired observations.

This result answers the feasibility question. The fixed experiment is useful
for compatibility and diagnostic evidence, and the standard profile is now
measured correctly. Ordinary GitHub-hosted jobs are not a defensible source for
an absolute-score dashboard, ranking, or regression threshold. Publication
would require a controlled runner or a separately validated paired methodology;
neither should be added to this branch without new evidence.
