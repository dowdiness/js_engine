# Development

This document is for maintainers. User-facing quick start material belongs in
the root README; agent-specific workflow belongs in `AGENTS.md`.

## Package Map

Run the live package overview before broad changes:

```bash
scripts/package-overview.sh
```

Current package responsibilities, verified from `moon.pkg` files and generated
interfaces:

| Package | Responsibility |
|---|---|
| `.` | User-facing facade over parse, interpreter execution, module execution, and the opt-in compiled path. |
| `token` | Token kinds, source locations, and literal provenance tags. |
| `errors` | JavaScript error variants and formatting helpers. |
| `ast` | Public AST node definitions consumed by parser, static semantics, compiler, and runtime. |
| `lexer` | Source text to token stream. |
| `parser` | Token stream to AST. |
| `static_semantics` | Early-error checks and declaration-fact analysis. |
| `compiler` | Opt-in closure-conversion prototype used by benchmarks and `run_compiled`. |
| `interpreter` | Wiring layer that creates a runtime interpreter with stdlib hooks. |
| `interpreter/runtime` | Tree-walking evaluator, value model, environments, property dispatch, modules, event-loop state. |
| `interpreter/stdlib` | JavaScript built-ins and stdlib/runtime hook implementations. |
| `benchmarks` | Benchmark workloads, benchmark tests, and benchmark CLI. |
| `cmd/main` | User-facing CLI executable. |
| `cmd/test262_runner` | Authoritative native Test262 runner. |
| `cmd/report_test262` | CI-artifact conformance report generator. |
| `cmd/test262_analyze`, `cmd/test262_validate_skips`, `cmd/classify_by_edition` | Test262 metadata, skip validation, and reporting helpers. |
| `cmd/architecture_*`, `tooling/architecture_*` | Architecture state/boundary audit CLIs and libraries. |
| `cmd/bench_focus` | Native repeated-benchmark helper for lower-noise local timing. |
| `tooling/test262_*`, `tooling/subprocess_helpers` | Shared native tooling libraries for Test262 and subprocess handling. |

Use `moon ide outline <package>` or `pkg.generated.mbti` for the current public
API. Do not infer public API from file names.

## Routine Commands

```bash
moon check
moon test
moon info
moon fmt
moon build
```

MoonBit coding conventions (including arrow functions for higher-order callbacks)
live in `AGENTS.md` / `CLAUDE.md` — update those files when adding project-wide
style rules.

`moon info` regenerates `pkg.generated.mbti` files. Review those diffs as API
changes, especially for `@js_engine`, `@js_engine/token`, `@js_engine/ast`,
and `@js_engine/interpreter/runtime`.

## Test262

The authoritative full-suite workflow is `.github/workflows/test262.yml`.
It builds the JS target with `moon build --target js --release` and runs the
native MoonBit runner (`cmd/test262_runner`) in a matrix of two modes (`strict`,
`non-strict`) × four shards. Each shard uses 4 threads and a 5-second per-test
timeout. The GitHub Actions job timeout is set in the workflow file.

Generate release-grade conformance text from CI artifacts:

```bash
make test262-report                         # includes edition tables by default
make test262-report ARGS="--format=changelog"
```

Do not hand-copy headline conformance numbers between docs. If a table needs
refreshing, regenerate it with `make test262-report` (native) or state clearly
that it is a dated snapshot.

For local focused runs:

```bash
make test262-quick
make test262-filter FILTER=language/expressions
make test262-filter FILTER=built-ins/Promise
```

The native MoonBit runner (`cmd/test262_runner`) is authoritative for execution
and skip decisions. Shared skip metadata lives in
`scripts/test262_skip_metadata.json` (the `.py` alongside it is a shared
reader/classifier, not the data) to keep runner and analyzer classifications
from drifting. The static analyzer is still only a
rough metadata census; it does not execute tests and must not be treated as
conformance data or the skip-list source of truth.

After editing shared skip metadata, run:

```bash
make test262-validate-skips
```

This target checks that skip features, flags, and path suffixes still match the
checked-out Test262 suite. It does not run tests or produce conformance numbers.

When removing a blanket feature skip, also update the active intent docs listed
in `scripts/docs_skip_policy_manifest.json` and add the feature to
`graduated_features` there. Then run:

```bash
make validate-docs-skip-policy
```

This fast check ensures active docs do not still claim the feature is blanket-
skipped or wholly unimplemented. CI runs it on docs/metadata changes via
`.github/workflows/docs-skip-policy.yml` and on every main/PR unit-test job when
skip metadata or tooling changes.

## Benchmarks

CI runs benchmark tests on the JS target:

```bash
moon test benchmarks/ --target js
```

The benchmark CLI is also the `benchmarks` package:

```bash
moon run benchmarks --target js -- --list
moon run benchmarks --target js -- --all --csv
```

Timing is meaningful only on the JS target; the WASM and WASM-GC timer files
return `0.0` by design.

Benchmark output has both a category and a stage. Category answers when the
benchmark should run (`regression`, `component`, `workflow`); stage answers what
part of the engine it measures (`startup`, `frontend`, `execution`). Keep those
separate when interpreting results: a frontend lexer regression and an execution
property-lookup regression need different follow-up work.

The scheduled and manual benchmark workflow uploads the raw CSV, writes a
GitHub Actions summary with a full table, per-stage totals, a log-scale text
chart, and closure-conversion comparisons, and publishes historical trend data
with `benchmark-action/github-action-benchmark` on the `gh-pages` branch. The
published `benchmarks/data.js` file stays generated by benchmark-action; after
that update, the workflow replaces `benchmarks/index.html` with the
source-controlled responsive dashboard template at
`benchmarks/dashboard/index.html`. The CSV-to-Markdown renderer lives in
`scripts/render-benchmark-summary.py` so the summary and PR comment share one
formatter. Same-repository PRs additionally run the CSV benchmark CLI at the PR
base SHA and head SHA on the same runner,
upload both raw CSVs, and render reporting-only base-vs-head tables with base
mean, PR mean, delta percent, PR/base ratio, CV, and noisy flags. These PR
comparisons do not gate the workflow and do not update the historical baseline;
fork PRs skip write-token benchmark reporting for safety. PR comment Markdown
is rendered in the read-only benchmark execution job before the publish job
posts it. Repository-write permissions are scoped to the publish job; the
benchmark execution job runs with read-only repository contents permission.

For less-noisy local timing on a focused set of rows, repeat full CSV snapshots
and compare medians instead of a single process run:

```bash
make bench-focus ARGS="--runs 5"
make bench-focus ARGS="--runs 3 --rows isolate/bytecode/property_get,pipeline/bytecode/evaluate"
```

(`make bench-focus` runs the native `cmd/bench_focus`.)

The helper saves each raw CSV under `_build/bench-focus/<timestamp>/` and
reports median/mean/range across runs plus the median in-run CV. Use this for
post-merge baselines or exploratory follow-up work; use same-runner base/head
PR reports for optimization claims.

The `startup/tiny_program` benchmark is the low-noise guardrail for interpreter
startup and built-in installation. It intentionally measures `run("1 + 1")` in
process so CI trend data is not dominated by Node process spawn time. To split
that in-process path into independently measured phases on the JS target, run:

```bash
moon run --target js --release benchmarks -- --startup-phases --csv
```

The phase breakdown reports the full `startup/tiny_program` workload plus tiny
parse, `new_interpreter`, already-parsed execution, empty event-loop drain, and
result stringification/output handling. Treat the phase timings as separate
microbenchmarks, not as an additive profile.

To split `new_interpreter` itself into focused JS-target subphases before
designing lazy or cached runtime initialization, run:

```bash
moon run --target js --release benchmarks -- --startup-new-interpreter-subphases --csv
```

Those rows isolate realm/symbol setup, global environment/object setup,
stdlib hook and host setup, `setup_builtins_with_realm_state`, its builtin-family
subphases, global mirroring, generator/async constructors, test262 harness setup,
and the harness's own print/agent/$262/stamping slices. They are also separate
microbenchmarks, not an additive profile.

Benchmark-only public profiling hooks are allowed only when a separate package
(such as `benchmarks`) cannot call a private helper. Name them with a
`profile_*` prefix, keep them in `*_profile.mbt`, and document that they return
measurement data rather than JavaScript semantics. The startup subphase mirror
intentionally duplicates the production final realm-stamp traversal; when that
production traversal changes, update the mirror and its comments in the same
patch.

Engine-private hidden metadata uses negative symbol IDs in `PropertyBag` symbol
maps. Reserve IDs in code comments before adding new hidden slots:

- `-1..-2`: Array exotic length/prototype override slots in
  `interpreter/runtime/value.mbt`.
- `-3..-5`: Array iterator next-index, iterated-object, and kind slots in
  `interpreter/runtime/iterators.mbt`.
- `-101`: function home-realm intrinsic prototype bundle slot in
  `interpreter/runtime/factories.mbt`.
- `-111`: final realm-stamp traversal marker in
  `interpreter/stdlib/builtins.mbt`, mirrored by
  `benchmarks/startup_new_interpreter_subphases.mbt`.
- `-112`: realm-owned `%ArrayProto_values%` intrinsic cache on
  `Array.prototype` in `interpreter/runtime/iterators.mbt`.
- `-120..-122`: RegExp original source/flags and intrinsic constructor slots in
  `interpreter/stdlib/builtins_regex.mbt`.
- `-123..-128`: RegExp String Iterator brand, regexp, string, global, unicode,
  and done slots in `interpreter/stdlib/builtins_regex.mbt`.
- `-130..-132`: Map/Set iterator next-index, iterated collection, and kind slots
  in `interpreter/stdlib/builtins_map_set.mbt`.

Runtime-created user and well-known symbols must stay non-negative. Traversal
code treats negative symbol IDs as engine-private metadata and must not expose
them as ordinary JavaScript symbol properties.

For hosted process-level startup snapshots, use the manual-only Startup
Hyperfine workflow (`.github/workflows/startup-hyperfine.yml`). It builds the JS
release CLI, times repeated invocations of
`node _build/js/release/build/cmd/main/main.js "1 + 1"` against Node.js and Bun,
uploads the raw Hyperfine artifacts, and writes a reporting-only job summary.
It does not publish `gh-pages`, comment on PRs, or enforce thresholds.

For reproducible local startup decomposition, use the checked-in helper:

```bash
scripts/startup-hyperfine-decompose.sh --warmup 10 --min-runs 50
# Fast smoke test before sending changes:
scripts/startup-hyperfine-decompose.sh --warmup 1 --min-runs 2
```

The helper builds `moon build cmd/main --target js --release`, captures the
expected expression stdout from `node -p <source>` (default source: `1 + 1`),
verifies that `js_engine` and any included Bun expression probes match that
stdout, records the release bundle byte size and line count, and writes
Markdown/JSON artifacts under `_build/startup-hyperfine-decompose/<UTC
timestamp>/` by default. Its probes separate empty host startup, native host
expression evaluation, `js_engine` load/no-source, full `js_engine` expression
evaluation, and Bun-hosted `js_engine` when Bun is available (or required with
`--include-bun`). Like the hosted workflow, it is reporting-only: no thresholds,
publishing, or PR comments.

## Release Workflow

Use [RELEASING.md](RELEASING.md). The release checklist makes CI artifacts the
source of truth for conformance numbers and explains how to handle tag-vs-file
drift after the release tip runs.
