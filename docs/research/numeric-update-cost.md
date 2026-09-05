# Numeric update cost after PR #1015

Measured 2026-09-05. The synchronous local-update path can avoid constructing
and dispatching a general activation-resume decision while preserving the
runtime-owned numeric semantics introduced by #1015. The implemented change
improves the update-dense fixture on all three measured targets. It does not
establish an application-wide speedup or eliminate every cost of #1015.

## Reproduction of the original claim

Compare parent `105a8b4654ed9c8fa9a8cfa6ad5126cc6adc351e` with merge commit
`9317888c8b1a36b696de0c6a1491c4e35dcc4ead`. Both received the identical
`compiler/numeric_update_cost_benchmark_wbtest.mbt` fixture. The compiled child
function uses local slots and rejects unexpected environment allocation.
Parsing and compilation occur before timing; each invocation creates a fresh
frame and varies its numeric argument. Setup checks three seeds against the
expected result before benchmarking.

The [exact measured fixture](numeric-update-cost/measured-fixture.mbt.txt) is
archived to preserve the recorded source hash; the maintained benchmark was
subsequently formatted without changing its behavior.

Four scenarios are compared on each revision:

- 256 consecutive `x++` statements, followed by returning `x`.
- 4,096 loop iterations executing `x++`.
- The same loop executing `++x`.
- The same loop executing `x=x+1` as a control.

The loop counter uses `i=i+1` in every loop, so the counter does not itself
exercise UpdateLocal. Update expression values are discarded in these timing
fixtures; the correctness test separately retains prefix/postfix results for
increment/decrement after immediate and suspended conversion.

All runs use release mode, four process pairs per target, alternating A/B and
B/A order. The bench library warms each case and takes ten batches. The table
reports medians of process means in microseconds, and the median of the four
paired percentage changes (positive means slower). These are distinct
statistics; the percentage need not equal the ratio of the displayed medians.

| Target | Case | Parent µs | Merged µs | Paired change |
|---|---|---:|---:|---:|
| wasm-gc | 256 consecutive updates | 17.29 | 20.38 | +20.7% |
| wasm-gc | postfix loop | 1360.00 | 1385.00 | +0.1% |
| wasm-gc | prefix loop | 1350.00 | 1380.00 | +2.3% |
| wasm-gc | addition control | 1730.00 | 1680.00 | -2.3% |
| JS | 256 consecutive updates | 18.24 | 21.25 | +15.5% |
| JS | postfix loop | 2030.00 | 2050.00 | +0.8% |
| JS | prefix loop | 2220.00 | 2110.00 | -3.7% |
| JS | addition control | 2710.00 | 2570.00 | -3.7% |
| native | 256 consecutive updates | 16.70 | 21.29 | +27.1% |
| native | postfix loop | 951.91 | 982.17 | +2.9% |
| native | prefix loop | 918.04 | 945.74 | +3.0% |
| native | addition control | 1040.00 | 1010.00 | -2.9% |

The consecutive-update regression occurred in all wasm-gc/native pairs and
three of four JS pairs. Ordinary-loop results are smaller and variable.
[Raw observations and environment metadata](numeric-update-cost/before-after.json)
include the original text output, rounded by the benchmark CLI.

## Isolation and change

On the unmodified merge revision, a diagnostic fixture compares three local
update implementations in the same process, in forward and reverse order.
Each batch constructs a fresh frame, varies converted numbers across 4,096
updates, exercises both operators and both prefix flags, and consumes the
expression result and final local value.

| Path | wasm-gc forward / reverse µs | JS forward / reverse µs |
|---|---:|---:|
| Pre-#1015 formula and frame writes | 66.92 / 70.71 | 102.08 / 144.37 |
| Runtime plan and direct frame writes | 88.38 / 91.43 | 155.10 / 147.72 |
| Runtime plan, resume decision, decision application | 125.68 / 131.60 | 190.35 / 180.61 |

This comparison identifies extra cost in the decision path, but is not a
precise allocation profile: function calls, dispatch, allocations, inlining,
and JIT effects can all contribute. Generated release JavaScript retains both
the plan construction and a separate resume-decision construction/application.
The JS legacy row also shows substantial order sensitivity.

The [diagnostic fixture](numeric-update-delivery-fixture.mbt.txt) is archived
outside the compiled package to avoid maintaining a duplicate semantic
implementation in production or running a historical model in ordinary tests.
Run it on the unmodified merge revision with the cost fixture present.

The [measured patch](numeric-update-cost/measured.patch) extracts the existing
converted-Number validation and runtime plan construction into a compiler-private
pure helper. A completed numeric conversion applies that plan directly to the
local and operand stack. Suspended conversion still uses the resume reducer,
which obtains the same plan from the same helper. No runtime public interface,
coercion behavior, continuation ownership, or admission rule changes.

## Validation of the change

Save release benchmark artifacts from the merge revision and the patched
revision, then execute those artifacts serially in alternating order. This
second series uses the benchmark driver's unrounded JSON summaries and records
artifact hashes. No compilation runs alongside these timed processes.

| Target | Case | Merged µs | Patched µs | Paired change | Paired range |
|---|---|---:|---:|---:|---:|
| wasm-gc | 256 consecutive updates | 16.39 | 15.24 | -5.6% | -9.1…-1.6% |
| wasm-gc | postfix loop | 1166.90 | 1154.48 | -0.4% | -7.3…+4.8% |
| wasm-gc | prefix loop | 1158.40 | 1168.30 | +1.9% | -1.3…+6.2% |
| wasm-gc | addition control | 1466.49 | 1473.64 | +1.7% | -1.4…+4.8% |
| JS | 256 consecutive updates | 18.91 | 16.53 | -12.8% | -14.2…-11.5% |
| JS | postfix loop | 1844.41 | 1792.25 | -2.6% | -3.2…+0.5% |
| JS | prefix loop | 1906.43 | 1885.05 | -0.1% | -2.6…+3.3% |
| JS | addition control | 2351.18 | 2384.14 | +0.8% | -0.4…+3.0% |
| native | 256 consecutive updates | 20.23 | 15.98 | -22.0% | -29.8…-20.1% |
| native | postfix loop | 941.98 | 859.58 | -8.7% | -21.5…-4.0% |
| native | prefix loop | 914.09 | 829.40 | -8.7% | -15.1…-2.1% |
| native | addition control | 970.29 | 985.86 | +0.1% | -0.2…+5.3% |

[Raw patched comparison](numeric-update-cost/merged-patched.json) contains all
process results, batch statistics, and artifact hashes. All twelve consecutive
update comparisons improve. Native loop improvements are also consistent.
The wasm-gc/JS loop results do not establish a consistent improvement.

Machine: AMD Ryzen 7 6800H, Linux/WSL2 6.18.33.2, Node v24.14.1,
moon 0.1.20260819, moonc v0.10.9+6e6c44045, moonrun 0.1.20260819.
This is a shared development machine without CPU pinning or clock locking.
Do not compare absolute timings across the two series or infer complete
recovery against the original parent from the second series. Four pairs are
directional evidence, not a statistical confidence interval. Navier and other
applications were not remeasured in this investigation.

## Correctness and architecture checks

- `moon check --deny-warn`: passed.
- `moon test --release` (wasm-gc): 4,360 passed, zero failed.
- `moon test compiler/local_update_graduation_wbtest.mbt --target js --release`:
  all three tests passed, including agreement between immediate and suspended
  numeric conversion.
- `make architecture-audit`: passed, including typed AST boundaries and
  continuation ownership self-tests. The semantic-edge inventory was updated
  only for the shared plan helper and direct synchronous delivery.
- `moon info`: no generated public interface changes. `moon fmt` and
  `git diff --check`: passed.

## Reproduce

For historical reproduction of the first series, copy the cost fixture
identically into clean checkouts of the two revisions and run
`node docs/research/numeric-update-cost/measure_original_regression.cjs BEFORE AFTER OUTPUT 4`.
This research-only script preserves the original rounded-CLI measurement method;
it is not the ongoing measurement runner.

Use `node scripts/summarize_numeric_update_cost.cjs OUTPUT 4` to regenerate
either archived table. The explicit expected pair count is required because
these historical files predate recorded measurement plans. The raw files and
their original metadata have not been rewritten.

For artifact comparison, build the selected fixture with
`moon bench compiler/numeric_update_cost_benchmark_wbtest.mbt --target TARGET --release --build-only`.
Save the reported whitebox artifact from each revision as
`merged.wasm/js/exe` and `patched.wasm/js/exe` in an artifact directory, then run
`node scripts/compare_numeric_update_artifacts.cjs ARTIFACT_DIR OUTPUT 4`.
The JSON test filter targets only the cost fixture; native uses the generated
driver's file/range argument. Build all artifacts before starting comparison.

## Measurement tool boundaries

- `scripts/compare_numeric_update_artifacts.cjs` owns artifact preflight,
  subprocess execution, and incremental persistence. It records the expected
  number of pairs before running and consumes unrounded structured results.
- `scripts/numeric_update_results.cjs` is the deterministic validation and
  aggregation core. It requires exactly one before/after run per planned pair
  on all three targets, exactly the four known cases per run, and finite positive
  timings. Missing or duplicate runs/cases, unknown labels, invalid pair indices,
  and non-finite derived changes are errors.
- `scripts/summarize_numeric_update_cost.cjs` only reads JSON and renders the
  validated summary. Invalid input exits nonzero with a diagnostic on stderr and
  no partial table on stdout. New reports supply their pair count; historical
  reports require the explicit expected count shown above. A count supplied for
  a new report must agree with its recorded plan.

Run `node --test scripts/test_numeric_update_results.cjs` to check these
contracts using small fixed datasets and an actual CLI invocation. The benchmark
workflow also runs these tests. This does not launch performance measurements.

The retained change is limited to synchronous local-update delivery. Further
changes to the runtime plan representation require a separate measured benefit;
these results do not justify weakening runtime semantic ownership.
