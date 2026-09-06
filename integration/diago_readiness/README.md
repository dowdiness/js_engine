# Diago restoration-readiness fixture

This standalone module checks whether the repository checkout can execute the
former Diago MathJax and Rough.js workloads through the stable root
`dowdiness/js_engine` facade. It is engine-readiness evidence, not a Diago
integration test and not a general stack-safety claim.

The harness replaces Diago parsing, layout, and final SVG assembly. It retains
the former source-loading order and runs microtask and timer checkpoints after
each evaluated source and public JSON call. The behavioral oracle covers:

- MathJax rendering `x^2` as a math SVG measuring `19 × 17`;
- the former CD, bra/ket, and cancel inputs producing math SVG with positive
  finite dimensions; and
- a fixed-seed Rough.js rectangle producing multiple non-empty paths.

## Pinned sources

The generated MoonBit source comes from Diago commit
`bd03f8a9ccb396e809c858adf874fe290e3a98e8`, immediately before LaTeX and sketch
support were removed.

| Upstream path | Bytes | SHA-256 |
| --- | ---: | --- |
| `latex/latex_assets.mbt` | 1,903,173 | `d1778271a6f978e3287a1b88a2890b309100c85c5bf5212a757e028c52aea739` |
| `renderer_svg/sketch_assets.mbt` | 108,794 | `ab4a10fe828940c03060d3f51f6ecdcaa84e17a8f99a95bbd3f5fdcdc52c2450` |

Regenerate either checked-in fixture from the repository root:

```bash
node scripts/generate_diago_readiness_fixture.mjs latex
node scripts/generate_diago_readiness_fixture.mjs sketch
```

The generator verifies the upstream bytes before exposing only the source
bindings needed by this black-box test module. The embedded JavaScript strings
are unchanged. Normal tests never access the network.

## Run readiness

Both configurations run the same six assertions and pinned inputs through the
stable `Engine` facade:

| Package | Execution policy |
| --- | --- |
| `.` | Explicit Tree-walker; the default for this readiness command |
| `candidate/` | Verified bytecode where eligible, with pre-execution Tree-walker fallback |

The policy is a build-time virtual-package override. `candidate/` contains only
that configuration and relative links to the four shared asset/test files.
There is one copy of each input and assertion to maintain.

Run one explicit target/profile cell from the repository root:

```bash
make diago-readiness TARGET=js PROFILE=debug
make diago-readiness TARGET=native PROFILE=release EXECUTOR=candidate
```

`TARGET` and `PROFILE` must be supplied on the command line. Targets are `js`,
`wasm`, `wasm-gc`, and `native`; profiles are `debug` and `release`.
`EXECUTOR` accepts `treewalker` (default) or `candidate`.

Make validates those choices and runs `moon test --deny-warn` once for the
selected package. Type checking and test compilation are part of that command;
compiler warnings and test failures fail the cell. The command has a 900-second
bound, without retries or host-stack overrides. It remains outside the
permanent required PR gate.

## Execution routing and recorded results

The maintained [compiler route regressions](../../compiler/named_function_candidate_wbtest.mbt)
check that named-expression fallback preserves eligible sibling and descendant
execution. The [Engine regression](../../engine_named_function_test.mbt) checks
bindings and callbacks across later evaluations. Readiness tests check the
resulting workload behavior; they do not measure speed or count activations.

The named-expression fix and all eight passing candidate cells are recorded in
[the implementation results](archive/LOCAL_NAMED_FALLBACK_RESULTS.md).
Earlier evidence is retained in the [initial candidate matrix](archive/CANDIDATE_RESULTS.md),
[route investigation](archive/ROUTE_PROFILE.md), and
[2026-08-07 Tree-walker matrix](RESULTS.md).

The detailed generated-JS profiler was a one-off investigation. Its raw results
are archived, and its source remains linked from the investigation's historical
commit. It is not a maintained command or a dependency of readiness testing.
