# Remaining lexical scope work

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

Local verification on the implementation branch:

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
CI and the merge gate remain pending.

## Switch lexical environments

The baseline shared validator already treats all case clauses as one lexical
statement list. The remaining Bytecode work is to instantiate that shared scope
after evaluating the discriminant and before evaluating case expressions, then
restore the destination environment on every normal or abrupt exit.

The implementation must preserve TDZ across cases, const writes, fallthrough,
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
rules remain explicit. Implementation starts only after the prerequisite merge.

## Resumption checklist

- Finish and independently review issue #1066.
- Verify unchanged public interfaces and final-head CI; squash merge.
- Update main while preserving pre-existing uncommitted changes.
- Accept the focused switch lowering/verifier design and create its next ticket.
- Implement and review switch scope behavior, then repeat the same merge gate.
- Remove only clean worktrees and branches created by these two deliveries.

Validation commands and final PR/commit references will be added as each delivery
completes. Local regression subsets are comparison evidence, not conformance
reports; conformance figures must come from authoritative CI artifacts.
