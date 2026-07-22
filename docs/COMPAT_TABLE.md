# compat-table feature-coverage diagnostic

This repository uses [compat-table](https://github.com/compat-table/compat-table)
as a second, deliberately different view of JavaScript support.

- Test262 is the authoritative ECMAScript conformance and regression suite.
- compat-table is a coarse feature-coverage diagnostic intended to answer
  which recognizable language and built-in feature groups are available.

Never describe the compat-table percentage as ECMAScript conformance.

## Run locally

```bash
make compat-table
```

The target:

1. runs the deterministic runner tests;
2. downloads the pinned compat-table archive when it is not cached;
3. builds the native release CLI;
4. executes each compat-table subtest in a fresh engine process; and
5. writes `compat-table-results.json` and `compat-table-summary.md`.

Both output files and the downloaded archive are ignored by Git. The JSON file
contains every subtest result; the Markdown file contains paste-ready suite and
category tables.

## Default scope

The default run covers `es5`, `es6`, and `es2016plus`, which currently span
ES5 through finished ES2025 features in the pinned upstream data. ESNext
proposals, Intl, and non-standard extensions are excluded by default.

Annex B categories are detected from compat-table metadata and run separately
with the CLI's `--annex-b` flag. They do not contribute to the standard
headline.

To run an additional upstream suite, forward a repeated runner argument:

```bash
make compat-table COMPAT_TABLE_ARGS="--suite esnext"
```

Passing a suite replaces the default suite list, so repeat `--suite` when more
than one suite is wanted.

## Reading the report

Every table reports both:

- **Weighted coverage** — compat-table's top-level feature weighting: large =
  1, medium = 0.5, small = 0.25, and tiny = 0.125. A feature with subtests earns
  its weight in proportion to the subtests that pass.
- **Passed / Executed** — the unweighted passing subtest count and denominator.
  Skipped tests are shown separately, and timeouts are included in Executed.

These values must stay together. A weighted percentage without the raw
denominator hides how much evidence produced the headline.

Each subtest has a five-second default timeout. Override it only for a focused
investigation:

```bash
make compat-table COMPAT_TABLE_TIMEOUT_MS=10000
```

Expected feature failures are report data and do not make the command fail.
Invalid inputs, an unavailable engine, download failures, or a runner failure
return a non-zero status.

## CI behavior

`.github/workflows/compat-table.yml` runs the same `make compat-table` command
for relevant pull requests, pushes to `main`, and manual dispatches. It places
the Markdown report in the GitHub Actions job summary and uploads both report
files for 90 days.

The workflow is diagnostic rather than a pass-count baseline gate. A later
change may add a regression baseline after the result contract has proved
stable, without changing the rule that expected unsupported features are data.

## Updating compat-table

The single pinned revision is stored in
`scripts/compat_table_version.txt`. To update it:

1. replace that file's commit with a reviewed immutable upstream commit;
2. run `make compat-table-test`;
3. run `make compat-table`; and
4. review both the methodology metadata and the result changes before commit.

The cache path includes the commit, so updating the pin cannot silently reuse
the previous revision's data. Downloads are extracted in a unique temporary
directory, checked for the required suites and harness files, and marked
complete only after publication. An interrupted or incomplete download is
therefore retried instead of being reused. compat-table is MIT-licensed; retain
its upstream license and attribution in the downloaded source archive.
