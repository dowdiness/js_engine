# Issue #852 current-main tree-activation frontier

Recorded: 2026-08-09 (Asia/Tokyo)

Toolchain: `moon 0.1.20260713 (75c7e1f 2026-07-13)`

## Scope

This report measures the current implementation at
`3ce843cdf1caddc1292296e88325de86c0fb3704`. It does not widen production
admission, change a public interface, or make a broader Stack Safety claim.

The acceptance seam is the stable root `dowdiness/js_engine` facade. Focused
runtime tests and the private capability classifier are explanatory evidence
only.

## Existing workload results

`make stack-safety-test TARGET=<target> PROFILE=<profile>` passed in every
target/profile cell without host-stack overrides.

| Target | Debug | Release |
| --- | --- | --- |
| native | core 139/139; external 41/41 | core 139/139; external 41/41 |
| js | core 139/139; external 41/41 | core 139/139; external 41/41 |
| wasm | core 139/139; external 41/41 | core 139/139; external 41/41 |
| wasm-gc | core 139/139; external 41/41 | core 139/139; external 41/41 |

`make diago-readiness TARGET=<target> PROFILE=<profile>` reproduced the
checked-in Current Release result with one attempt per cell.

| Target | Debug | Release |
| --- | --- | --- |
| native | rejected by SIGSEGV | 6/6 |
| js | 6/6 | 6/6 |
| wasm | 6/6 | 6/6 |
| wasm-gc | 6/6 | 6/6 |

The native/debug failure was not retried and was not replaced by a larger host
stack. This run observes only the test executable's SIGSEGV and does not
establish a more specific JavaScript semantic cause.

## Minimal public safe-island probe

The retained public probe defines two ordinary functions:

- `legacyEntry(n)` performs one observable assignment and then returns
  `recurse(n)`;
- `recurse(n)` is the already-admitted exact numeric self-recursion shape.

The assignment keeps the wrapper outside the pure tree capability subset. Its
callee receives one JSON number, which becomes one runtime numeric value. The
callee category is an ordinary user function, and the wrapper's return is the
completion consumer. A global entry counter is the effect that must not replay.

The retained bounded test passes on native/debug: a depth limit of one
produces the engine-owned `stack-depth-limit` diagnostic, retains the source
identity, and increments the wrapper counter exactly once. This proves that the
call is observed and rejected deterministically; it does not prove iterative
execution.

During measurement, a temporary unbounded depth-4096 assertion was RED in seven
cells:

| Target | Debug | Release |
| --- | --- | --- |
| native | SIGSEGV | 1/1 passed |
| js | host `RangeError` | host `RangeError` |
| wasm | host `RangeError` | host `RangeError` |
| wasm-gc | host `RangeError` | host `RangeError` |

The unbounded assertion is not retained as a normal #852 test because it would
make the evidence change unmergeable and can terminate the native/debug test
executable before other tests report. #858 must reintroduce the depth-4096 RED
through `Engine::call_json_bounded` with explicit step and logical-depth bounds
before implementing the coordinator-root transition.

The JavaScript-target trace remains in the legacy evaluator through expression
evaluation, statement execution, and ordinary call execution. Current code can
admit an ordinary user function requested by an existing executor activation,
but the legacy ordinary-call path does not start a newly admitted callee as a
coordinator root. The practical safe-island entry is therefore missing.

## Observed frontier

| Field | Current-main evidence |
| --- | --- |
| First unsupported surrounding family | assignment expression statement in an ordinary wrapper |
| Candidate island | exact numeric ordinary self-recursion |
| Callee category | ordinary user function with one numeric parameter |
| Completion consumer | legacy wrapper return statement |
| Effect that must not replay | one increment before the child call |
| Missing capability | legacy ordinary-call to admitted coordinator-root transition |
| Failure without the capability | host stack exhaustion at depth 4096 in seven cells |

This is an activation-routing gap, not evidence that function-scoped locals,
local assignment, direct throw, or native-leaf admission is the next blocker.
Dynamic property, coercion, iteration, Proxy, eval, construction,
handler/finalizer, async/job, and reentrant-host families remain outside this
probe.

## Candidate decision table

| Candidate | Observed blocker evidence | Decision |
| --- | --- | --- |
| #853 sealed function-scoped locals | none | defer |
| #854 activation-local assignment | none; the observed assignment stays in the legacy wrapper | defer |
| #855 direct throw completion | none | defer |
| #856 non-reentrant native leaf capability | none | defer |
| safe-island entry child | measured depth-4096 public RED in seven cells | activate first |

The next implementation ticket should be limited to entering an already-proven
ordinary callee as a coordinator root from the legacy call path. It must not
make the rejected wrapper executable by the tree frame, replay wrapper effects,
or broaden the pure capability classifier.
