# JetStream 3 Adoption Strategy

**Status:** initial non-gating admission slice implemented
**Research date:** 2026-08-27
**Pinned upstream:** [WebKit/JetStream `7769b693502fa80f28a97bbfacd3296e0513acc5`](https://github.com/WebKit/JetStream/tree/7769b693502fa80f28a97bbfacd3296e0513acc5), authored 2026-08-03

## Recommendation

Adopt a small, pinned **official JetStream 3 shell-runner admission ladder**.
Begin with exact selected-test discovery and then the `raytrace` workload
through upstream `cli.js`, not with a copied workload and not with the full
suite. Treat the initial result strictly as compatibility evidence. It is not
yet a macro trend signal, an official JetStream 3 score, or a merge-gating
performance baseline.

The runner is part of the benchmark contract: it creates a fresh benchmark
realm, loads workload sources, measures every iteration, invokes the workload
oracle, derives first/worst/average results, and can emit structured JSON.
Extracting JavaScript files would fork those semantics. It remains useful later
for a deliberately named internal microbenchmark, but not for the first
external-workload integration.

Keep the existing isolated `benchmarks/` suite as the evidence required before
an optimization. JetStream must not replace a microbenchmark which reproduces
a proposed hot path.

## Why JetStream 3

JetStream identifies itself as a JavaScript and WebAssembly benchmark suite and
documents direct shell execution with `cli.js` in its
[README](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/README.md).
The entry point parses `globalThis.arguments` and supports `--test`,
`--iteration-count`, `--worst-case-count`, `--dump-json-results`,
`--dump-test-list`, `--no-prefetch`, and related controls
([`cli.js`](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/cli.js)).

The shell driver is not merely command-line glue:

- [`ShellScripts.run`](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/JetStreamDriver.js#L763-L809)
  uses `runString("")` for a generic engine shell, then installs a copied
  `console`, `self`, `top.currentResolve`, and `performance` in that realm.
- [`ShellFileLoader`](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/JetStreamDriver.js#L156-L188)
  reads source with `readFile`, and reads compressed resources with
  `read(path, "binary")`, zlib, and `TextDecoder` when prefetching is enabled.
- [`Benchmark.runnerCode`](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/JetStreamDriver.js#L950-L970)
  measures each iteration with `performance.now()`, runs optional
  `benchmark.validate`, and resolves per-iteration timings.
- [`DefaultBenchmark.processResults`](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/JetStreamDriver.js#L1487-L1534)
  preserves first iteration, worst-case, and average values; the first sample
  is excluded from the average.

The upstream [in-depth methodology](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/in-depth.html)
defines an aggregate for the complete configured suite. A selected subset has
no legitimate overall JetStream score.

## Current js_engine fit

`Shell` provides `load`, `read`, `readFile`, `runString`, and, when supplied
by its host, `performance.now`, `mark`, and `measure`
([`js_engine.mbt`](../../js_engine.mbt)). The CLI constructs it with filesystem
loaders, a monotonic clock, and JavaScript-visible arguments
([`cmd/main/main.mbt`](../../cmd/main/main.mbt)). That covers the generic-shell
path required by the upstream driver. `runString` creates a child realm and
returns its global object, which is the runner's critical nonstandard need.

This is compatibility evidence, not a claim of support for the full suite.
Worker, Wasm, compressed assets, BigInt, Intl, and async workloads each add
separate language or host requirements. JetStream shell conventions must remain
in the CLI/test adapter and must not expand the capability-selected embedding
API.

## Empirical probe on current `main`

The pinned runner was exercised with a native release build of `js_engine` on
2026-08-27. With `--no-prefetch`, the initial `hash-map` discovery succeeded,
but workload execution first exposed an environment-slot correctness bug:

```text
cli.js -- --no-prefetch --dump-test-list --test=hash-map
cli.js -- --test=hash-map --iteration-count=2 \
  --worst-case-count=1 --no-prefetch --dump-json-results

InternalError: bytecode env slot binding missing for 'HashMap'
```

Running `simple/hash-map.js` directly produced the same error. After reducing
and fixing that bug, `hash-map` no longer failed immediately but did not finish
within the 180-second compatibility timeout. It is therefore too expensive for
the first smoke workload on the current engine.

The smaller `raytrace` workload then exposed two general correctness bugs in
the official driver's cross-Realm Promise-resolution path: reactions were
queued on the resolving Realm instead of the Promise owner's Realm, and strict
identifier assignment did not update an existing global Object Environment
Record binding. Both were reduced to local CLI tests and fixed without adding
JetStream-specific runtime behavior. The official command now completes in
about 24 seconds on the investigation host and emits a structured result for
two iterations:

```text
cli.js -- --test=raytrace --iteration-count=2 \
  --worst-case-count=1 --no-prefetch --dump-json-results
```

The recorded times were approximately 12 seconds per iteration. They are only
diagnostic observations from one run, not a baseline. Earlier failing official
commands also exited with status zero, so process status alone is not sufficient
evidence. The adapter requires both a clean process outcome and the expected
structured result containing only the selected workload with a valid score.
Human-readable error output is retained for diagnosis but is not parsed as part
of the admission contract.

## Options considered

| Option | Result |
|---|---|
| Official JetStream `cli.js`, curated workload | **Choose.** It retains upstream realm setup, oracle, iteration semantics, and JSON schema. |
| Directly copy selected workload files | Reject for the initial slice. It forks setup and validation, and stops being an upstream workload result. |
| ARES-6 alone | Defer. Its official CLI needs `load`, `readFile`, `currentTime`, and a realm-returning `runString`; its ES2015-heavy workloads would confound host compatibility with feature gaps. [ARES-6 CLI](https://github.com/WebKit/WebKit/blob/main/PerformanceTests/ARES-6/cli.js) and [methodology](https://github.com/WebKit/WebKit/blob/main/PerformanceTests/ARES-6/about.html). |
| Octane 2 alone | Reject. Chromium's own repository calls it retired and no longer maintained: [chromium/octane](https://github.com/chromium/octane). `navier-stokes` can instead be selected through the maintained JetStream driver. |
| SunSpider alone | Do not add separately. It is already a grouped subset in the JetStream source tree, so another supplier/harness has no first-slice advantage. |
| Test262 | Retain only as independent semantic evidence. TC39 defines it as an ECMAScript conformance suite, not a timing suite: [test262 README](https://github.com/tc39/test262/blob/main/README.md). |
| Browser suites such as Speedometer | Out of scope: a browser/document benchmark does not validate a general engine shell. |

No primary source identifies a universally standardized engine-shell performance
harness that is materially better for this first purpose. The official
JetStream shell driver is the authoritative contract for JetStream workloads.

## First integration slice

Prepare a sparse checkout of the exact pinned upstream revision containing the
official runner and selected workload. Admit the runner in this order:

```text
cli.js -- --no-prefetch --dump-test-list --test=raytrace
cli.js -- --test=raytrace --iteration-count=2 \
  --worst-case-count=1 --no-prefetch --dump-json-results
```

The final command is equivalent to:

```text
<native-release-js_engine> <absolute-jetstream>/cli.js -- \
  --test=raytrace --iteration-count=2 --worst-case-count=1 \
  --no-prefetch --dump-json-results
```

The host-side command syntax may be adapted to the CLI parser, but the
JavaScript-visible argument list must be equivalent. `--no-prefetch` avoids the
driver's Wasm zlib prefetch path. Do not interpret two iterations as a
performance sample.

`raytrace` is selected because the driver registers it as a synchronous,
non-Wasm, no-preload `DefaultBenchmark`
([driver registration](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/JetStreamDriver.js#L2071-L2077)).
It completes quickly enough for a scheduled compatibility smoke and exercises
ES6 classes, allocation, numeric code, arrays, and control flow
([`Octane/raytrace.js`](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/Octane/raytrace.js)).
It does not provide an explicit checksum oracle, so result admission proves
runner/workload completion and structured result production, not independent
semantic validation of the rendered scene.

Next, investigate `navier-stokes`, which carries a checksum oracle and
exercises numeric arrays and loops. Defer JSON inspector workloads because the
driver registers their `.z` payload dependency; defer async work until the
Promise/job-drain path has its own compatibility investigation.

## Phased acceptance criteria

### Phase 0 — provenance

1. Verify the exact upstream commit before execution and record its URL, SHA,
   commit date, and checkout/archive hash.
2. Keep the checkout outside the production dependency graph; cache it in CI
   from the pinned revision, never from `main` at benchmark time.
3. Do not vendor workload sources.

Acceptance: revision mismatch or missing source fails before the engine starts.

### Phase 1 — compatibility smoke

1. Build the native release CLI and separately record exact selected-test
   discovery, workload execution, workload-result validation, and result
   serialization.
2. Require successful process exit, no workload assertion/error, parseable
   `--dump-json-results` output containing only `raytrace`, and a positive
   reported duration/score field. Process exit alone is insufficient.
3. Archive stdout, stderr, JSON, upstream SHA, engine SHA, MoonBit version,
   target/profile, command, OS/architecture, and wall-clock duration.

Acceptance: two independent clean processes on one host meet every check.
Timings are diagnostic only.

The initial slice now reaches structured result production. Keep the admission
report capable of representing compatibility failures, and keep the scheduled
workflow non-gating until repeated clean-process measurements establish a
variance policy.

### Phase 2 — compatibility matrix

Add one workload at a time through the same official driver: `navier-stokes`,
then a deliberately investigated async workload, then a compressed-resource
workload. Worker, Wasm, BigInt, Intl, and browser-dependent work require an
explicit support decision and dedicated tests first.

Acceptance: every added workload documents its host and language prerequisites,
passes its upstream oracle repeatedly, and reports failures as compatibility
failures rather than silently excluding them.

### Phase 3 — non-gating performance baseline

Only after Phase 2, collect at least five independent clean-process samples
per workload. Freeze upstream/engine commits, MoonBit version, target/profile,
command and parameters, CPU/OS/architecture, power policy, timeout, memory
limit, raw iteration data, and oracle result. Report median and dispersion;
compare base and head on the same runner. Keep the threshold non-gating until
unchanged builds and a deliberately slower build prove the variance policy.

Do not combine external JetStream results with the repository's internal CSV
microbenchmarks. The latter already distinguish regression, component, and
workflow measurements and verify correctness outside their timed regions.

## Licensing and supplier policy

The JetStream root [LICENSE](https://github.com/WebKit/JetStream/blob/7769b693502fa80f28a97bbfacd3296e0513acc5/LICENSE)
is a BSD-style two-clause Apple license. Individual workload provenance and
notices differ. Reference a pinned checkout at first. If a later change vendors
any source or asset, preserve each notice, record upstream path and SHA, and
audit the complete copied dependency set rather than assuming the root license
covers all workload files.

## Final recommendation

Retain the implemented Phase 0 and Phase 1 diagnostic: pinned sparse-source
acquisition, exact selected-test discovery, a fixed two-iteration `raytrace`
run, and a non-gating structured admission report. Use `raytrace` only as a
compatibility smoke until repeated clean-process measurements and an oracle-
bearing workload justify Phase 2 or Phase 3.

Do not claim a JetStream score, vendor assets, alter the embedding interface,
or use this result as proof for an optimization. The next useful addition is an
oracle-bearing workload, not more iterations of the current smoke test.
