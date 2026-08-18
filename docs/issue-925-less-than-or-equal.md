# Issue #925 less-than-or-equal ownership and evidence

This note records the source-verified boundary for issue #925. The
implementation branch starts at `7c9e5937349a9f0ae49a8baa97525c85fed5d7e5`.

## Preserved assumptions

1. Source expressions are already evaluated left-to-right before the binary
   runtime operation receives their values.
2. Runtime owns conversion, comparison, abrupt completion, and continuation;
   the VM owns only evaluated operands, location, and one `PushValue` result.
3. Admission changes only plain `BinaryOp(LtEq, BinaryExpression)`; defaults,
   public `Engine` APIs, siblings, compounds, BigInt, and #926 stay unchanged.

## Ownership boundary

The tree-walker `<=` path enters one runtime Abstract Relational Comparison
owner. It reverses the semantic operands for `IsLessThan`, visits the original
source left before the original source right, compares two strings by UTF-16
code units, converts all other primitive pairs to Number, and maps
`Unordered` (including NaN) to `false`.

Managed bytecode uses the same runtime comparison after a resumable pair of
`ExecutorToPrimitiveOperation(Number)` children. Primitive pairs return
`Completed` synchronously. Object-like operands return a sealed
`Suspended` request; the VM does not inspect value variants or perform
conversion phases. Abrupt conversion leaves the existing effects and never
replays a completed child.

## Admission and exclusions

The compiler contract and VM admit only `(LtEq, BinaryExpression)`. `<`, `>`,
`>=`, abstract equality, arithmetic/relational siblings, and every compound
origin remain `UnsupportedBeforeActivation(BinaryOperation)`. The canonical
Fibonacci workload therefore keeps its root and `fib` activations on bytecode,
while unrelated unsupported forms remain Tree-walker candidates.

## Evidence

Focused runtime and compiler tests cover primitive completion, UTF-16 string
ordering (`"2" <= "10"` is `false`), Number/NaN/infinity cases, object
`@@toPrimitive`/valueOf/toString fallback, non-callable hooks, getters and
calls that throw, object-valued hooks, Array own/inherited hooks, Proxy `get`
dispatch, source-order abrupt completion, and exactly-once result delivery.

The pre-fast-path isolated runtime benchmark (preparation outside timing)
measured Number/Number `<=` at `16.48 ns ± 0.81 ns`, versus a direct Boolean
control at `11.43 ns ± 1.28 ns`; this established the child-activation risk
without measuring parsing or setup. After managed admission, the route-proven
bytecode benchmark measured `595.26 ns ± 4.34 ns`; its direct control measured
`10.95 ns ± 1.76 ns`. The corresponding bytecode frame test proves primitive
Number/Number `<=` creates no child activation.

Candidate evidence verifies one prepare/start/complete lifecycle, no fallback,
no replay, and zero active activations for plain `<=`. Fibonacci 10 keeps full
trace evidence and returns `55`; the unchanged Fibonacci 30 source returns
`832040` through bounded aggregate evidence with zero Tree-walker starts,
fallbacks, replays, retained events, retained lifecycles, or active
activations. A same-interpreter queue/error/reuse matrix preserves left effects,
drains one queued microtask, and successfully reuses the candidate engine.

## Scope exclusions

No BigInt representation or route is introduced. No default routing change,
public Engine API change, VM-side conversion/comparison phase, compiler type in
runtime, sibling admission, or #926 property-chain work is part of this issue.
