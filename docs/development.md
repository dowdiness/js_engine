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
| `.` | User-facing facade over parse + interpreter execution. |
| `token` | Token kinds, source locations, and literal provenance tags. |
| `errors` | JavaScript error variants and formatting helpers. |
| `ast` | Public AST node definitions consumed by parser and runtime. |
| `lexer` | Source text to token stream. |
| `parser` | Token stream to AST. |
| `interpreter` | Wiring layer that creates a runtime interpreter with stdlib hooks. |
| `interpreter/runtime` | Tree-walking evaluator, value model, environments, property dispatch, modules, event-loop state. |
| `interpreter/stdlib` | JavaScript built-ins and stdlib/runtime hook implementations. |
| `cmd/main` | CLI executable package. |
| `benchmarks` | Benchmark workloads, benchmark tests, and benchmark CLI. |

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

`moon info` regenerates `pkg.generated.mbti` files. Review those diffs as API
changes, especially for `@js_engine`, `@js_engine/token`, `@js_engine/ast`,
and `@js_engine/interpreter/runtime`.

## Test262

The authoritative full-suite workflow is `.github/workflows/test262.yml`.
It currently builds the JS target with `moon build --target js --release` and
runs `scripts/test262-runner.py` once per mode (`strict`, `non-strict`) with
4 threads and a 5-second per-test timeout. The GitHub Actions job timeout is
set in the workflow file.

Generate release-grade conformance text from CI artifacts:

```bash
make test262-report
make test262-report ARGS="--format=changelog"
make test262-report ARGS="--with-editions"
```

Do not hand-copy headline conformance numbers between docs. If a table needs
refreshing, regenerate it with `scripts/report-test262.py` or state clearly
that it is a dated snapshot.

For local focused runs:

```bash
make test262-quick
make test262-filter FILTER=language/expressions
python3 scripts/test262-runner.py --test262 ./test262 --filter built-ins/Promise --summary
```

`scripts/test262-runner.py` is authoritative for execution and skip decisions.
Shared skip metadata lives in `scripts/test262_skip_metadata.py` to keep runner
and analyzer classifications from drifting. The static analyzer is still only a
rough metadata census; it does not execute tests and must not be treated as
conformance data or the skip-list source of truth.

After editing shared skip metadata, run:

```bash
make test262-validate-skips
```

This target checks that skip features, flags, and path suffixes still match the
checked-out Test262 suite. It does not run tests or produce conformance numbers.

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
CSV-to-Markdown renderer lives in `scripts/render-benchmark-summary.py` so the
summary and PR comment share one formatter. Same-repository PRs additionally
run the CSV benchmark CLI at the PR base SHA and head SHA on the same runner,
upload both raw CSVs, and render reporting-only base-vs-head tables with base
mean, PR mean, delta percent, PR/base ratio, CV, and noisy flags. These PR
comparisons do not gate the workflow and do not update the historical baseline;
fork PRs skip write-token benchmark reporting for safety. PR comment Markdown
is rendered in the read-only benchmark execution job before the publish job
posts it. Repository-write permissions are scoped to the publish job; the
benchmark execution job runs with read-only repository contents permission.

The `startup/tiny_program` benchmark is the low-noise guardrail for interpreter
startup and built-in installation. It intentionally measures `run("1 + 1")` in
process so CI trend data is not dominated by Node process spawn time. When
investigating process-level startup, build the JS release binary and time
repeated invocations of `node _build/js/release/build/cmd/main/main.js "1 + 1"`.

## Release Workflow

Use [RELEASING.md](RELEASING.md). The release checklist makes CI artifacts the
source of truth for conformance numbers and explains how to handle tag-vs-file
drift after the release tip runs.
