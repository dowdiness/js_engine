# Candidate readiness result

The pinned six-test fixture passes in candidate mode on all eight target/profile
cells. This establishes readiness for these inputs under the mixed candidate
policy; it does not establish bytecode-only execution or general stack safety.

- Recorded: 2026-09-05 (Asia/Tokyo)
- Engine HEAD: `c7d68b74e4dfbdac2ab17141821874e4b1292184`
- MoonBit: `moon 0.1.20260819 (fc2a4ee 2026-08-19)`
- Pinned Diago source: `bd03f8a9ccb396e809c858adf874fe290e3a98e8`
- Checkout: dirty; this change adds readiness configuration and documentation,
  with no production engine or original fixture changes. Existing unrelated
  local documentation changes were present during validation.

## Results

| Target | Candidate debug | Candidate release |
| --- | --- | --- |
| js | 6/6 passed | 6/6 passed |
| wasm | 6/6 passed | 6/6 passed |
| wasm-gc | 6/6 passed | 6/6 passed |
| native | 6/6 passed | 6/6 passed |

The explicit Tree-walker comparison on JS debug also passed 6/6. The other seven
Tree-walker cells were not measured in this investigation.

Each cell used one invocation of:

```bash
make diago-readiness TARGET=js PROFILE=debug EXECUTOR=candidate
```

Substitute the table's target and profile; use `EXECUTOR=treewalker` for the
comparison. Every invocation retained the 900-second command bound, without
retry or host-stack overrides. Some commands waited for the shared Moon build
lock within that bound. Full command output is in
[candidate-validation.txt](candidate-validation.txt).

The historical native-debug rejection in [RESULTS.md](RESULTS.md) remains a
valid record of its earlier engine/toolchain and Tree-walker configuration.
This run changes all three variables, so it cannot attribute the difference
solely to bytecode or establish that current Tree-walker native debug is fixed.

## Execution evidence and next work

The candidate package explicitly overrides the build-time policy with
`engine_candidate_mode_enabled`. Inspection of its generated JS debug test
artifact confirmed that `candidate_mode_enabled()` returns `true` and
`Engine.eval` routes to `run_candidate_program`. The comparison artifact returns
`false`. Both packages execute the same six tests through the stable facade,
using relative symlinks to the original assets and test sources.

This confirms the configured entry policy, not per-function runtime coverage.
Eligible activations may use verified bytecode while unsupported activations
select Tree-walker before execution. No per-activation counts or fallback
reasons were collected, and no engine fix was needed for this matrix.

The next bytecode investigation should use the existing
`compiler/candidate_route_plan_profile.mbt` diagnostic to inventory prepared
selections and fallback reasons for the pinned sources. Keep that static plan
inventory separate from runtime evidence: it cannot show which functions were
actually called. Use the existing private route-evidence machinery to establish
executed paths before choosing a general operation family to expand. Preserve
the stable-facade readiness tests as the behavioral oracle.
