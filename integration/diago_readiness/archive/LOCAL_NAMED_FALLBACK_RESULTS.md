# Diago readiness after local named-expression fallback

MathJax and Rough.js now execute eligible functions from their main bundles
through bytecode. Named function expressions retain Tree-walker execution and
runtime-owned self-name binding; they no longer force the whole source onto
the plain-tree path.

Implementation: `2c91271ed04099d95f1ae45cd710a49e2537cc00`.
Recorded on 2026-09-05, with MoonBit `0.1.20260819 (fc2a4ee)` and Node
`v24.14.1`, using the unchanged pinned Diago fixtures.

## Execution evidence

The final JS debug diagnostic passed all six unchanged readiness assertions.
It observed no `run_candidate_plain_tree_program` entries. Every recorded
activation completed normally. The existing observer validates source/path
ownership, selected executor, and closed lifecycle; its six unit tests passed.

These counts include only the named bundle's own source identity, excluding
polyfills, setup, preludes, and harness functions:

| Bundle/test | Bytecode starts | Tree-walker starts |
| --- | ---: | ---: |
| MathJax `x^2` | 16,371 | 4,971 |
| Former CD formula | 28,426 | 10,611 |
| Minimal AMSCD arrow | 18,867 | 6,157 |
| Bra/ket formula | 19,205 | 6,279 |
| Cancel formula | 18,603 | 6,077 |
| Rough.js rectangle | 210 | 292 |

The previous diagnostic observed zero bytecode starts from either bundle.
MathJax now contributes 101,472 bytecode starts across its five cases; Rough.js
contributes 210. Static selections remain unchanged: this change makes the
existing plans participate in execution. These are activation counts, not
unique functions, timing measurements, or evidence of a speedup. The separate
AST body observations in the JSON overlap with lifecycle records and must not
be added to them; they still do not establish total guest-call coverage.

- [Complete final diagnostic JSON, gzip](route-profile-local-named-2026-09-05.json.gz)
- [Raw diagnostic test output](route-profile-local-named-validation.txt)
- Uncompressed JSON SHA-256:
  `0db7f4e41c0fa44a748971ce1f8b3b3b7fcfab60a975e43bbff4122c13c6b09f`
- [Previous investigation and observer methodology](ROUTE_PROFILE.md)

The final diagnostic records the implementation commit in its metadata.
Its generated JS hash and all source plans, route rows, body observations,
and test results agree with the initial experiment before the commit.

## Readiness matrix

Each cell uses one invocation of `make diago-readiness TARGET=... PROFILE=...
EXECUTOR=candidate`, retaining the 900-second bound, without retries or stack
overrides. The matrix started with the implementation in the working tree;
only test, comment, and formatting changes occurred before the implementation
commit. Existing unrelated documentation edits were present.

| Target | Debug | Release |
| --- | --- | --- |
| js | 6/6 passed | 6/6 passed |
| wasm | 6/6 passed | 6/6 passed |
| wasm-gc | 6/6 passed | 6/6 passed |
| native | 6/6 passed | 6/6 passed |

[Complete matrix command output](local-named-candidate-validation.txt).

This validates the pinned inputs under mixed candidate execution, not
bytecode-only execution or a general stack-safety guarantee.

## Regression coverage

The new minimal regression failed before the fix with only a tree root start,
then passed with `tree,bytecode`. Five compiler tests cover eligible siblings
and descendants, recursive self-reference, parameter/var/let shadowing,
default-parameter closures, escaped closures, later source evaluation,
Promise callbacks, and preservation of ten excluded async/generator forms.
The existing same-name sibling test now checks each executed source coordinate
as well as the result. A stable `Engine` test covers later `eval`, Promise
checkpoint execution, and the original function source text.

The full JS suite passed 4,370/4,370 tests. Strict JS checking, interface
generation, formatting, and the import/representation boundary audit passed.
Generated public interfaces are unchanged. Named-function binding and source
construction remain in the existing runtime implementation.

The semantic lifecycle, typed AST boundary, opaque destructuring-plan interface,
and continuation ownership audits also passed, including their supplied
self-tests. [Audit output](local-named-architecture-validation.txt).
The initial semantic audit stopped when one IDE hover for the existing
`ignore` call returned nonzero. A direct repeat resolved the symbol; rerunning
the audits without concurrent edits or type checks passed. No audit inventory
or engine source was changed to resolve that tooling failure.

## Next bounded investigation

MathJax's remaining recorded tree starts most often select `try/catch
statement` (17,686) or `binary operation` activation fallback (13,728).
`for-in var declaration` accounts for 1,822. Rough.js has 186 named-expression
tree starts and 88 unary-conversion tree starts.

These are the selected reasons for executed candidate functions, not counts
of execution of the unsupported operations themselves. Use the source/path
rows to reduce the binary-operation cases to a specific operator and operand
types before defining the next implementation ticket. A performance claim
would additionally require an isolated reproducing benchmark.
