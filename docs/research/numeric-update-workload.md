# Numeric-update workload measurement

Measured 2026-09-05. PR #1020 reduced Navier–Stokes whole-process time in all
five paired comparisons: median paired reduction **4.93%**, range **2.31–12.04%**.
This supports retaining the optimization, not further numeric-update restructuring.

## Conditions

- Before: `1f68173c0a9eec5e8381847f9d2940e61a35bf19`.
- After: `c7d68b74e4dfbdac2ab17141821874e4b1292184`.
- Unmodified JetStream `Octane/navier-stokes.js` at
  `7769b693502fa80f28a97bbfacd3296e0513acc5`.
- Native release CLI: `moon build --target native --release cmd/main`.
- AMD Ryzen 7 6800H; Linux/WSL2 6.18.33.2; CPU affinity 7.
  Moon 0.1.20260819 (fc2a4ee), moonc v0.10.9+6e6c44045.
- Invocation, with `ENGINE` the corresponding executable and `JETSTREAM`
  the pinned checkout:

```sh
taskset -c 7 ENGINE JETSTREAM/cli.js -- --test=navier-stokes --iteration-count=15 --worst-case-count=1 --no-prefetch --dump-json-results
```

Each run starts a fresh process. Wall time uses Node v24.14.1
`process.hrtime.bigint()` around the synchronous child process, including startup,
loading, parsing, execution and output. One warmup per revision is excluded,
followed by five alternating before/after and after/before pairs.

## Evidence and limits

[Raw timings](numeric-update-workload/measurements.json) preserve all 12 runs
in execution order; `elapsedMs` is milliseconds and measured pair indices are
zero-based. No outliers were removed. Compute each reduction as
`100 * (before - after) / before`, then take the median of the five reductions.
The separate revision medians are 32.494 s and 31.154 s; their ratio gives
4.12%, a different statistic.

All runs exited successfully with valid workload results. An untimed,
instrumented executable confirmed the changed synchronous numeric-update path
inside `lin_solve`. A separate untimed 15-frame run returned
`NAVIER_ORACLE:15:77`; the original workload checks checksum 77 at frame 15.
Instrumentation was absent from both timed binaries.

This shared machine had neither exclusive CPU ownership nor locked frequency;
pair 3 showed substantial variation. Five pairs on one native numerical workload
do not establish a precise general speedup. JS and wasm-gc were not measured.
The 15-iteration override is not an official JetStream score.
