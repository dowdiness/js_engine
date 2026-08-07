# Current-release readiness result

This report records the one-attempt target/profile matrix for the engine at
`2575c1afc458fe441a9758678bea60e9f8ec68ea` using the checked-in pinned fixture.
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
retry or a stack-limit override. This one-attempt matrix does not assign a cause
beyond the observed SIGSEGV. The current engine therefore does **not** satisfy
the accepted all-cells Diago Restoration Readiness criterion. The seven passing
cells remain useful practical evidence, but they are not a product-restoration
guarantee.
