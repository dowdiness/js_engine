# Numeric leaf realm fast path: adoption evidence

Date: 2026-09-05. Status: adoption deferred.

The realm-scope optimization in PR #1016 has a measured benefit in a synthetic
root-to-leaf activation benchmark, but has not demonstrated a benefit in the
existing plain-call and method-call workloads. Do not use its approximately
25.7% synthetic improvement as a general function-call or JetStream speedup.

## Experiment

Baseline: `105a8b4654ed9c8fa9a8cfa6ad5126cc6adc351e`.
Original candidate: `8f7bbc855007a2c4b9f2dbff9c0a726336c2eb22`.
The reordered trial changed only the conjunction order in activation entry:
realm eligibility before numeric leaf eligibility. It was not retained.

Environment: MoonBit `0.1.20260819` (`fc2a4ee`), Node `v24.14.1`, Linux under
Microsoft virtualization, AMD Ryzen 7 6800H, process affinity CPU 7.
Each series used five pairs, in AB, BA, AB, BA, AB order. Each selected row ran
in a fresh process. Compilation was outside timing. All benchmark result
checks passed. The existing runner used 3 warmups, 15 iterations and group size 3.

Build each checkout with `moon run benchmarks --target js --release --build-only`
and run its generated `benchmarks.js` with:

```sh
taskset -c 7 node --stack-size=8192 --enable-source-maps \
  _build/js/release/build/benchmarks/benchmarks.js \
  --rows isolate/bytecode/plain_call --csv
```

Repeat for `plain_call_control` and `method_call`, alternating checkouts per
pair. For debug, omit `--release` and select the `js/debug` output directory.
The CI report used debug output with all rows sharing a process, so these
isolated-row measurements are not an exact replay of CI's process history.

## Results

Numbers below are medians of the five paired percentage changes
`100 * (candidate_mean / baseline_mean - 1)`. Negative means faster.

| Series | plain_call_control | plain_call | method_call |
| --- | ---: | ---: | ---: |
| Original candidate, release | +0.35% | +3.28% | -0.76% |
| Reordered trial, release | +1.34% | -2.99% | -1.08% |
| Reordered trial, debug | -0.95% | -2.17% | +4.55% |

The original plain-call candidate was slower in all five pairs. The reordered
debug method-call trial was slower in four of five pairs. Noise was material:
one reordered release control pair changed by +52.84%, and several process CVs
exceeded 15%. These results neither establish a precise causal regression size
nor demonstrate that changing the predicate order resolves the adoption concern.
Method calls include property lookup and addition, so their cost must not be
estimated by subtracting the plain-call control.

Process mean times in milliseconds, rounded to six decimals; arrays are in pair
order, not execution order. Retaining both sides avoids relying on percentage
summaries alone.

| Series / row | Baseline means | Candidate means |
| --- | --- | --- |
| Original release / control | 31.643088, 29.471553, 32.587825, 32.069495, 32.215207 | 30.150135, 29.573849, 28.773486, 36.234424, 32.668360 |
| Original release / plain | 82.613520, 80.197358, 84.729674, 91.399952, 88.303866 | 82.824150, 82.348036, 102.618867, 94.753003, 91.201023 |
| Original release / method | 22.965241, 22.058937, 22.579974, 25.148666, 28.121371 | 22.789757, 22.502595, 23.137984, 24.869092, 26.988491 |
| Reordered release / control | 36.589340, 31.097068, 31.775937, 31.132135, 30.171381 | 37.331372, 47.529337, 31.631091, 31.009744, 30.576011 |
| Reordered release / plain | 89.254649, 87.509190, 98.091548, 83.093771, 90.325155 | 89.808345, 88.869424, 88.140829, 80.610960, 83.128556 |
| Reordered release / method | 23.499331, 23.599742, 22.798359, 22.939337, 22.696497 | 24.669953, 23.336033, 24.305772, 22.495184, 22.450340 |
| Reordered debug / control | 28.480972, 27.407812, 31.415226, 31.883501, 29.839068 | 29.550079, 28.534955, 28.680023, 31.580721, 28.988339 |
| Reordered debug / plain | 84.502463, 95.339288, 83.138590, 83.045878, 81.093149 | 80.619090, 82.594754, 81.336379, 86.692959, 85.683872 |
| Reordered debug / method | 20.106960, 23.781267, 20.412143, 22.349010, 20.048581 | 22.489792, 23.289547, 21.732581, 23.364961, 20.929171 |

## Reachability and decision

A separate untimed diagnosis instrumented a copy of the reordered release JS
artifact at activation entry and at the branch that omits the realm scope.
Running the existing plain-call and method-call rows together recorded
3,360,110 entries and **zero scope omissions**. Instrumented timings were not
used in the comparisons above; the instrumentation is not production code.

Both workloads call their leaf from an enclosing JavaScript function. The
parent's active realm state prevents realm fast-path admission. The synthetic
benchmark has a different root context and therefore exercises an opportunity
that these workloads do not reach.

Keep PR #1016 as a deferred experiment. The predicate-order trial does not
justify adoption. Any replacement optimization should first show a repeatable
benefit in the existing plain-call workload and no repeatable method-call
regression. Preserve nested activation realm barriers, prototype selection,
source attribution, and normal/abrupt cleanup. No additional permanent
profiling hooks or benchmark orchestration are needed for this decision.
