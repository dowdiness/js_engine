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

## Readiness command

Run one explicit target/profile cell from the repository root:

```bash
make diago-readiness TARGET=js PROFILE=debug
make diago-readiness TARGET=wasm PROFILE=release
make diago-readiness TARGET=js PROFILE=debug EXECUTOR=candidate
```

Valid targets are `native`, `js`, `wasm`, and `wasm-gc`; valid profiles are
`debug` and `release`. Each invocation has a 15-minute bound and no retry. This
command is intentionally outside the permanent required pull-request gate.

`EXECUTOR=treewalker` is the default and retains the explicit Tree-walker
oracle. `EXECUTOR=candidate` selects verified bytecode for eligible activations
and allows pre-execution Tree-walker fallback for unsupported activations,
through the same stable `Engine` facade. It is not a bytecode-only execution
claim. The `candidate/` package shares the four asset/test files through relative
symlinks, so both configurations use identical sources, expectations, and
checkpoint ordering. Run each executor separately; the command selects only its
package. Invalid executor names are rejected before compilation.

The recorded current-release matrix and its native-debug rejection are in
[RESULTS.md](RESULTS.md). A failed cell is evidence, not a reason to weaken the
command or replace the result with a larger host-stack setting.

The first candidate investigation is recorded separately in
[CANDIDATE_RESULTS.md](CANDIDATE_RESULTS.md); the historical Tree-walker matrix
does not establish candidate readiness.
