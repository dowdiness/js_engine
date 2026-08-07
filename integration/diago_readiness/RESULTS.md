# Current-release readiness result

This report records the one-attempt target/profile matrix for the engine at
`31c1fef8323792e554bd077f2119612121ac600a` using the checked-in pinned fixture.
The readiness change does not alter production engine sources, so that commit
identifies the evaluated engine implementation.

- Recorded: 2026-08-07 (Asia/Tokyo)
- MoonBit: `moon 0.1.20260713 (75c7e1f 2026-07-13)`
- Pinned Diago source: `bd03f8a9ccb396e809c858adf874fe290e3a98e8`

| Target | Debug | Release |
| --- | --- | --- |
| native | **Rejected:** SIGSEGV while rendering the minimal AMSCD arrow | 6/6 passed |
| js | 6/6 passed | 6/6 passed |
| wasm | 6/6 passed | 6/6 passed |
| wasm-gc | 6/6 passed | 6/6 passed |

The native debug failure is the recorded cell result; it was not replaced by a
retry. Diagnostic runs reduced the input to `\begin{CD} @>>> \end{CD}`. The
same focused test passed in native release and passed in native debug when the
host stack limit was raised from the default 8 MiB to 64 MiB. A symbolized
backtrace repeatedly crossed the general
`eval_call -> call_value -> UserFunc exec_stmts` path, with ordinary expression
evaluation and construction frames between activations.

This is evidence of residual tree-walker host-stack dependence, not a missing
MathJax API or a Diago-specific semantic failure. The readiness command does
not raise the native stack limit because doing so would hide the required-cell
failure. The current engine therefore does **not** satisfy the accepted
all-cells Diago Restoration Readiness criterion. The seven passing cells remain
useful practical evidence, but they are not a product-restoration guarantee.
