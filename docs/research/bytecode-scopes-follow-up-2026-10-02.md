# Bytecode lexical scope deliveries

## Delivery contract

This work follows the Bytecode semantic-completion specification in issue
#1042. It has two sequential deliveries: lexical loop declaration early errors,
then switch lexical environments. Each uses an isolated worktree and focused PR.
The second implementation starts after the first PR has passed required checks
on its rebased head and merged. No public API or default-executor policy change
is part of either delivery.

Tree and Bytecode share static declaration validation. Runtime operations own
binding creation, initialization and access. Lowering and structural verification
own control-flow structure; the VM owns its active environment and completion
unwinding. Neither delivery introduces another executable representation.

## Lexical loop declaration early errors

Baseline: main at `efc76eea8bd42c4066bd06e3cef11798754657fb`.
The shared validator traverses loop declarations and bodies but does not compare
header bound names with body var-declared names. Duplicate lexical names in a
C-style header also bypass the statement-list duplicate check. This can allow
script effects before an invalid, unreachable loop or never-called function is
rejected, or allow invalid source to execute without rejection.

The accepted design reuses existing declaration and pattern name collectors.
Check duplicate lexical header bound names and their intersection with the
body's var-declared names. Exclude nested function and class scopes and preserve
legal lexical shadowing, var redeclarations, and assignment targets. The same
rule applies to parsed lexical for-in, for-of and for-await-of headers without
changing which execution forms Bytecode admits.

References: [for early errors](https://tc39.es/ecma262/multipage/ecmascript-language-statements-and-declarations.html#sec-for-statement-static-semantics-early-errors),
[for-in/of early errors](https://tc39.es/ecma262/multipage/ecmascript-language-statements-and-declarations.html#sec-for-in-and-for-of-statements-static-semantics-early-errors),
and [lexical declaration early errors](https://tc39.es/ecma262/multipage/ecmascript-language-statements-and-declarations.html#sec-let-and-const-declarations-static-semantics-early-errors).

Issue #1066 records the fixed implementation criteria. The test seam checks
SyntaxError before script/eval effects, including unreachable bodies, and valid
shadowing through Tree and candidate execution. Valid admitted loops must also
show private Bytecode route evidence. Completion is not claimed until the final
review, cross-target tests, full suites, architecture audit and CI succeed.

Verification of the declaration delivery:

- The initial minimal test observed `effect=1` instead of `0`, demonstrating
  execution before rejection. The fixed implementation preserves `0`.
- `moon check --target all --deny-warn` passed.
- `moon test --deny-warn` and `moon test --target js --deny-warn` passed.
- Both new test files passed on native, Wasm and WasmGC, and release JS.
  Select files by positional paths; the current `-f` option filters test names.
- An independent Terra review found no material correctness or test issues.

The facade test constructs a function at runtime because the closure-compiled
facade does not admit top-level try statements. Within that function, direct
eval must reject an invalid never-called function before its first effect. Both
public facades assert the caught SyntaxError and unchanged effect. Candidate
tests separately prove static validation and an admitted Bytecode execution.
The full architecture audit passed when run independently. An initial attempt
failed to resolve an unchanged VM error constructor while Moon tooling ran
concurrently; the exact query and the standalone audit then succeeded. Generated
interfaces remained unchanged, and info, format and diff checks passed. Final-head
CI passed on rebased head `14a99e4de450c2f54058fccec892ad017c17ab3f`.
[PR #1067](https://github.com/dowdiness/js_engine/pull/1067) was squash-merged
as `edbf21052d4138ad3fe24ce22f44043d35419a25`. The required
`release_metadata`, `test262-required`, and `stack-safety-required` checks
succeeded on that head; all six workflows completed successfully, and the
conditional Playground deploy was skipped. The independent Terra review ran
locally; cloud review services skipped their reviews. The post-rebase full
default and JS suites passed 4,447 and 4,449 tests respectively. Root main was
fast-forwarded while retaining the existing tracked diff and untracked paths.

## Switch lexical environments

The baseline shared validator already treats all case clauses as one lexical
statement list. The remaining Bytecode work is to instantiate that shared scope
after evaluating the discriminant and before evaluating case expressions, then
restore the destination environment on every normal or abrupt exit.

The implementation preserves TDZ across cases, const writes, fallthrough,
default placement, side-effect order, escaped closures, activation-slot
shadowing, nested labels and finally completion replacement. Declaration
conflicts must fail before script effects. Function and destructuring declaration
admission remains governed by their separate capabilities.

The accepted design reuses the existing lexical-scope helpers and handler
unwinding. Handler entry requires an empty operand stack and no pending binding
reference or argument-list resources. Save the evaluated discriminant in an
anonymous private temporary slot before entering the shared case scope, reload
it and clear the temporary immediately, then use the existing selection and
fallthrough lowering. Normal exits leave the scope; outward completions use the
same handler machinery as blocks and loops. Source binding names and capture
maps remain separate from temporary storage, and the verifier checks storage
capacity and operand bounds without weakening handler rules.

Case declarations contribute Empty completion, including comma-separated
declarations represented by synthetic statement lists. They must preserve a
preceding case expression result. Function, class and destructuring admission
rules remain explicit. [Issue #1068](https://github.com/dowdiness/js_engine/issues/1068)
records the fixed implementation criteria and was marked ready only after the
prerequisite merge. Its worktree starts at `edbf21052d4138ad3fe24ce22f44043d35419a25`.

The Tree baseline also replaces a preceding case result with undefined when a
declaration executes. Its declaration predicate misses the synthetic statement
list used for comma declarations. The switch delivery preserves declaration
Empty completion in both execution paths, using iterative classification for
those carriers. A focused ordinary Tree comma-declaration regression first
returned undefined on the baseline and now preserves the preceding expression.
A repeated-entry test saves closures from three switch environments and reads
their distinct values after all three scopes have exited.
Empty-block and semicolon completion gaps observed before this delivery remain
separate work; this delivery does not claim complete statement conformance.

Local verification of the switch delivery:

- Strict all-target check passed. Switch/verifier/runtime tests passed 98/98
  separately on JS, native, Wasm and WasmGC; release JS switch tests passed 14/14.
- Full default and JS suites passed 4,465 and 4,467 tests respectively.
- The public Engine regression also passed on native and Wasm; full suites
  cover JS and the default WasmGC target.
- The full architecture audit passed. Public interfaces remain unchanged.
- Independent Terra review found a missing ordinary Tree completion regression;
  the regression and repeated-entry closure coverage were added and re-reviewed.
  No material correctness finding remained.
- [Issue #1068](https://github.com/dowdiness/js_engine/issues/1068) is the delivery
  record for the final PR, reviewed head, required CI and merge outcome.

References: [switch evaluation](https://tc39.es/ecma262/multipage/ecmascript-language-statements-and-declarations.html#sec-switch-statement),
[CaseBlock evaluation](https://tc39.es/ecma262/multipage/ecmascript-language-statements-and-declarations.html#sec-runtime-semantics-caseblockevaluation).

## Practical baseline and measurement limits

The existing candidate readiness Make command stops before runtime with five
`test_unqualified_package` warnings under the current compiler. The unchanged
pre-feature root reproduced the same failure. This is a fixture naming problem,
and the original command is recorded as failed.

For runtime verification, a scratch copy keeps the generated assets and original
six test bodies, qualifying only the five package API references. Reversing those
qualifiers reproduces the original test text exactly. Warnings remain errors.
On declaration head `14a99e4d`, release JS and Wasm each passed all six tests,
including MathJax rendering and the fixed Rough.js input. A supplementary test
on the same Engine renders `x^2`, then `y^3 + x^2`, then `x^2` again; both targets
passed that test. On the final switch implementation, the same seven test
bodies passed on release JS and Wasm (7/7 each), with warnings still treated
as errors. No upstream application or repository fixture was modified.
Candidate fallback remains allowed; these results do not measure whole-application
Bytecode coverage or establish application graduation.

Pinned generated asset SHA-256:

- LaTeX: `cf1769104b5aa28feb434392fdec15104f5f0b0845a611ffb3bc2bebdd40dba8`.
- Sketch: `8be6541fb8748f68b99fbafcf4e41c6f7212852d7f79206b839be0b73803d65a`.

A bounded release-JS comparison used unchanged benchmark rows in fresh Node
processes, five alternating base/head pairs per row. Base `efc76eea` and head
`14a99e4d` used Node v24.14.1 and Moon 0.1.20260920 / moonc 0.10.14. Repeated
execution excludes preparation; startup intentionally includes preparation.
The unpinned eight-CPU host was not idle (initial load averages 3.66/2.86/2.96).

| Row | Median paired mean change | Individual paired changes |
| --- | ---: | ---: |
| `isolate/bytecode/plain_call` | -0.56% | -6.72% to +1.40% |
| `isolate/bytecode/local_access` | -0.32% | -3.05% to +3.31% |
| `startup/tiny_program` | +1.84% | -17.75% to +22.51% |

These ordinary-path samples show no consistent degradation signal. Startup is
inconclusive: three of ten samples were noisy, with CV up to 24.43%. Whole-process
peak RSS ranges overlap; RSS includes Node and harness allocation and is not
isolated engine allocation. These observations are not performance guarantees.
The CI benchmark report also has broad positive deltas, including unchanged
lexer controls; its one-order comparison cannot establish a causal regression.
The frozen head benchmark artifact is also the switch baseline because squash
commit `edbf2105` has exactly the same Git tree as `14a99e4d`.

## Switch measurement and remaining work

The same five-pair release-JS protocol compares the exact declaration tree
(`edbf2105`) against the final switch sources, with no overlapping Moon build.
The unpinned eight-CPU host began at load averages 0.99/1.68/2.00.

| Row | Median paired mean change | Individual paired changes | Noisy samples |
| --- | ---: | ---: | ---: |
| `isolate/bytecode/plain_call` | +4.60% | -3.94% to +19.64% | 1/10 |
| `isolate/bytecode/local_access` | +1.65% | -1.72% to +3.10% | 0/10 |
| `startup/tiny_program` | +1.63% | -4.17% to +2.17% | 2/10 |

The positive medians are retained as a performance risk, not dismissed as proof
of no regression. Calls vary substantially between processes; these samples
cannot attribute the change to a specific operation. Whole-process peak RSS
ranges overlap (calls: baseline 168,672–175,760 KiB, switch 153,956–175,276 KiB;
reads: baseline 158,304–180,680 KiB, switch 164,112–180,552 KiB). This feature
expands semantic support; it does not claim a throughput or allocation win.
Reproduction uses unchanged `benchmarks`, `moon build --target js --release
benchmarks`, then fresh Node processes with `--rows <row> --csv`, alternating
base/head order. `/usr/bin/time` supplies whole-process peak RSS. The linked
delivery record identifies the final source head.


An isolated release-JS classifier comparison uses 192 separately parsed AST
statements from 12 forms, varying operands, one million calls per sample and
seven alternating pairs after warmup. Setup is outside timing. Both generated
functions run in the same ordinary function scope. Their median costs were
15.79 ns before and 15.91 ns after the change. This does not establish a
regression. An earlier vm.createContext harness exaggerated global lookup
overhead and is discarded as deployment evidence. A leaf-helper prototype was
withdrawn: it did not demonstrate a useful improvement. These measurements do
not establish allocation costs or guarantees for native or Wasm.

Empty-block and semicolon completion gaps remain outside these two deliveries.
The other Bytecode semantic stages in #1042 remain open: shared binding
initialization, iteration and IteratorClose, execution constraints, and later
generator/async/class/module support. Candidate fixture success permits Tree
fallback and does not graduate an application to full Bytecode execution.

Local regression subsets are comparison evidence, not conformance reports;
conformance figures must come from authoritative CI artifacts. Final CI and
merge status live in the linked delivery records.
