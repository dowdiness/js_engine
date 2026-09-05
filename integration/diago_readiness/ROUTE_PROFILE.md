# Diago bytecode route investigation

MathJax and Rough.js pass the readiness oracle, but their main bundles enter
the ordinary Tree-walker path as whole programs. The next useful bytecode task
is to localize fallback around named function expressions while preserving
their self-name binding and source ownership. Adding more eligible opcodes
alone would leave this whole-program routing decision in place.

## Evidence and scope

Recorded on 2026-09-05 (Asia/Tokyo), JS debug, with engine HEAD
`7756b4c9dfd79dcebe06da8d98f1b080afb56444`, MoonBit
`0.1.20260819 (fc2a4ee)`, and Node `v24.14.1`. This change modifies no production
engine source. The engine implementation is the same as the previous readiness
matrix; the working tree also contained unrelated local documentation edits.

The instrumented run passed all six unchanged readiness assertions. It is a
separate diagnostic run, not a replacement or retry of a recorded readiness
cell. No timings or speedup claims are derived from the instrumentation.

- [Complete measurement JSON, gzip](route-profile-2026-09-05.json.gz)
- [Raw test-driver output](route-profile-validation.txt)
- Uncompressed JSON SHA-256:
  `973d68920faecca0678261d878755a36b9318e3127c6992bed3c24322d294572`

The JSON includes input SHA-256 identities, source labels, every static candidate
path and selected reason, source locations, observed routes by test and phase,
Tree-walker body entries, and hashes of the generated JS, profiler, and bridge.

## Static selection

These are candidate units, including each script root. They are neither executed
function counts nor supported-syntax percentages. The ten distinct inputs are
counted once, even though the MathJax inputs are loaded in five fresh engines.

| Source | Candidate units | Bytecode selected | Lowering fallback | Activation fallback |
| --- | ---: | ---: | ---: | ---: |
| LaTeX polyfills | 436 | 311 | 8 | 117 |
| MathJax bundle | 3,940 | 2,546 | 922 | 472 |
| Rough.js runtime | 180 | 54 | 109 | 17 |
| Seven prelude/setup/harness inputs | 15 | 15 | 0 | 0 |
| Total | 4,571 | 2,926 | 1,039 | 606 |

MathJax's selected lowering reasons include 531 `for-in var declaration`,
384 `try/catch statement`, and seven `named function expression` records.
Rough.js has 107 `named function expression` records and two `try/catch statement`
records. Reasons can propagate to enclosing candidates: the named-expression
records correspond to **three distinct source locations in MathJax and 89 in
Rough.js**, not seven and 107 distinct expressions.

## Executed paths

The existing candidate lifecycle recorder observed the following successful
starts. Each had a matching normal completion; no recorded abrupt completions
occurred. Counts include source loading, rendering, and queue checkpoints.

| Test | Recorded bytecode starts | Recorded Tree-walker starts |
| --- | ---: | ---: |
| MathJax `x^2` | 175 | 45 |
| Former CD formula | 176 | 45 |
| Minimal AMSCD arrow | 176 | 45 |
| Bra/ket formula | 176 | 45 |
| Cancel formula | 176 | 45 |
| Rough.js rectangle | 12 | 1 |

The MathJax bundle itself contributed exactly one recorded Tree-walker root
start per test and **zero recorded bytecode starts**. Rough.js likewise
contributed one Tree-walker root start and zero bytecode starts. Both were
observed entering `run_candidate_plain_tree_program`. The bytecode starts in
the table came from polyfills, preludes, setup, and readiness harness functions.

The plain-tree branch does not install candidate materializers for the bundle's
descendants, so its root lifecycle record cannot count their later calls. A
second observation matched full prepared AST statement-list identity at
`Interpreter::exec_stmts` to see bodies executing inside that branch:

| Bundle/test | Matched Tree-walker body entries | Entries whose static candidate selected bytecode |
| --- | ---: | ---: |
| MathJax `x^2` | 21,360 | 16,330 |
| Former CD formula | 39,044 | 28,246 |
| Minimal AMSCD arrow | 25,064 | 18,826 |
| Bra/ket formula | 25,547 | 19,181 |
| Cancel formula | 24,729 | 18,561 |
| Rough.js rectangle | 502 | 210 |

Across the five MathJax tests, 2,229 distinct candidate bodies were observed in
Tree-walker statement-list execution, including 1,272 statically bytecode-selected
bodies. Of 135,744 matched entries, 12,025 occurred at microtask checkpoints.
Rough.js had 42 distinct matched bodies, including 11 statically bytecode-selected
bodies. This establishes executed opportunities; it does not estimate their
execution cost or the benefit of changing their executor.

These two tables overlap and **must not be added together**. Body entries are
statement-list observations, not a second activation counter. Empty bodies,
unmatched/copied AST nodes, dispatcher-managed Tree-walker recipes, and other
execution seams are outside this body observation. A candidate absent from the
body table is not proved uncalled. The profiler does not report total guest-call
coverage.

## Why the whole bundle falls back

[`candidate_requires_plain_tree_execution`](../../compiler/candidate_execution.mbt)
recursively tests selected fallback reasons. `NamedFunctionExpression` is one
of the reasons that forces ordinary tree execution for the whole program.
Among the selected reasons in these two bundle plans, named function expressions
are the matching trigger. Runtime observation confirms entry into that branch.

MathJax's three distinct blocker locations, in the decoded JavaScript input,
are line 4, columns 41,814, 1,737,222, and 1,748,574. They begin with
`function t(e,Q,r)`, `function n()`, and `function e(Q,r)` respectively. The
second and third retain their self-name in Promise/retry callbacks.

One Rough.js example is the named `getPrototypeOf` expression inside
`_get_prototype_of`, at JavaScript line 42, column 73 (the checked-in
[asset](sketch_assets.mbt) includes the MoonBit wrapper lines). Its presence in
the selected plan participates in the whole-program decision independently of
whether that particular function expression is evaluated in a test.

The selected reason at MathJax's root is `for-in var declaration`; looking only
at the root would therefore miss the nested named-expression trigger. The
complete source/path inventory is necessary here.

## Proposed next implementation slice

Investigate **retaining mixed candidate execution when a named function
expression requires Tree-walker fallback**. The named expression may remain
tree-backed; the objective is to retain eligible siblings and descendants.
This is a proposed slice, not an assertion that deleting the guard is sufficient.

Acceptance criteria for that slice:

1. First reproduce the whole-program fallback with a small source containing
   an eligible sibling and a named function expression. Assert actual started
   executors as well as the returned value.
2. Preserve the existing runtime owner of named-function semantics: recursive
   self-reference, parameter/local shadowing of the self-name, closure escape,
   later `Engine.eval`, and Promise callbacks must retain the correct binding
   and source identity. Compare the affected cases with explicit Tree-walker.
3. Make fallback local before execution starts. Do not retry a failed activation
   in another executor, expose private runtime data through the stable facade,
   or admit other excluded generator/async families in the same change.
4. Rerun this diagnostic and demonstrate executed bytecode functions from the
   MathJax/Rough.js bundle identities themselves, not just their harnesses.
   Keep the six assertions unchanged and repeat the eight readiness cells for
   the new implementation head.

Only after that boundary is addressed should this workload's remaining
`for-in`, `try/catch`, or conversion fallback counts select the next operation
family. Performance optimization would require a separate reproducing benchmark.

## Reproduce and maintain the diagnostic

From the repository root, choose a new output path:

```bash
node scripts/test_diago_route_profile.cjs
node scripts/diago_route_profile.cjs /tmp/diago-routes.json
```

The runner checks and builds the separate `profile/` package, whose four fixture
files are relative links to the original assets/tests. Its test-only bridge
calls the existing `profile_candidate_route_plan_json`. A temporary copy of the
generated JS receives observer wrappers; the generated original, production
sources, and guest source strings are not patched. Builds and the diagnostic
child each have a 900-second timeout, without automatic retry or stack overrides.
Existing evidence paths are rejected instead of overwritten.

The JS observer relies on the current unoptimized MoonBit function names, result
tags, and private field layout. It rejects missing/ambiguous symbols, mismatched
static identities, missing candidate preparation, invalid lifecycle transitions,
unfinished activations, and anything other than the six distinct passing tests.
Compiler changes may require an explicit adapter update. The observer aggregates
by source/path/test/phase and returns detached JSON; it does not retain a full
per-call trace in the report.

Validation for this change: six observer tests, the MoonBit projection-bridge
test, all six instrumented readiness assertions, strict JS type checking,
interface generation, formatting, and the architecture boundary audit passed.
The final diagnostic agrees with the preceding expanded diagnostic on every
source selection and runtime observation; only tool metadata differs.
