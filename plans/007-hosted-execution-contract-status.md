# Plan 007: Hosted Execution Contract Status and Fixed Completion Criteria

- Original inventory date: 2026-09-22
- Prototype baseline: `5c87fea9fc5905f9446a851529ed9d760c5862d3`
- R1 implementation base: freshly fetched `origin/main`, `a7f4121a9042759019d17467f8412515942cca81`
- R1 integration: [PR #1060](https://github.com/dowdiness/js_engine/pull/1060), main commit `985dd1b8c30f4de2585bbe3ad3d7d1315d70f5be`; required CI passed before merge.
- R2 implementation base: `985dd1b8c30f4de2585bbe3ad3d7d1315d70f5be`
- R2 integration: [PR #1062](https://github.com/dowdiness/js_engine/pull/1062), main commit `e28dc678916daabfbe58adc5b056651251ced1cb`; independent Terra review and required CI passed before merge.
- R3 implementation base: `e28dc678916daabfbe58adc5b056651251ced1cb`
- R3 implementation commit: `f2c06f2b59b7e95f1ec69e485dfd2005c174e16a`
- Branch: `fix/hosted-diagnostics-r3`
- Worktree: `.worktrees/hosted-diagnostics-r3`
- Status: **R1/R2 merged; R3 locally verified on all three targets; independent review and CI pending. R4/R5 remain.** The user authorized autonomous implementation/review/integration through R5, with one isolated PR per unit and at most three correction cycles per unit. Required CI success and integration gate each dependent unit.
- Authority: The *Exception and Nested Execution Contract* agreed on 2026-09-20. Its original text is preserved in the appendix.

## Purpose and Boundaries

Complete the new embedding API's contract for synchronous MoonBit → JS → Host callback → JS
reentry, keeping guest throws, Host Failures, execution limits, and admission rejections distinct.
Implementing the entire JavaScript specification, rewriting the interpreter, and providing a
security sandbox are not goals.

`HostedProbe` is currently a prototype. Do not change the existing `Engine`, `ExecutionSession`,
or `ProbeRuntime` contracts wholesale. Reuse the runtime's observation, exception, and queue
mechanisms. This inventory does not settle final type or API names.

### R1 prerequisite migration

The implementation base did not contain `HostedProbe`, `HostedCall`, or `HostedValue`.
The user approved carrying forward the necessary prototype before implementing R1.
The imported prerequisite consists of the Hosted facade, its 17 existing BB/WB tests,
the shared terminal carrier and policy hooks, direct activation depth observation,
and the benchmark's interpreter initializer. Latest-main executor changes are preserved.
Generated interfaces and explicit experimental-public surface classifications accompany
the import. R1 admission/lifetime changes add five BB tests. The review follow-up
also corrects prerequisite runtime depth accounting and adds three BB regressions.

The older `ProbeRuntime` / `ProbeValue`, `embedding_research.mbt`, experimental CLIs,
and recorded research output were **not** imported. They remain available in the prototype
baseline named above; R4 must inspect those adapters before selecting its migration.
The old worktree and its original plan are unchanged.

### Classification Rules

| Status | Evidence required | Next action |
|---|---|---|
| Verified | Tests exercise the listed Hosted paths, assert their behavior, and pass on all three targets | Preserve the behavior; do not generalize beyond the exercised paths |
| Not implemented | Source inspection establishes a gap between the agreed behavior and the current implementation | Add a minimal failing regression before implementing the missing behavior |
| Unverified | An implementation or supporting mechanism exists, but evidence at the required Hosted boundary is insufficient | Verify first; do not change the implementation if the test passes |
| Out of scope | An explicit contract exclusion or a separate decision unnecessary for this work's completion | Do not add it to this backlog |

**Unverified does not mean broken. A passing full suite does not establish the entire contract.**
Experiments using the older `ProbeRuntime` and runtime unit tests provide supporting evidence,
not substitutes for Hosted integration tests.

## Verified

Evidence abbreviations: **BB** = [hosted_execution_probe_test.mbt](../hosted_execution_probe_test.mbt),
**WB** = [hosted_execution_probe_wbtest.mbt](../hosted_execution_probe_wbtest.mbt).
K1–K7 line numbers refer to the prototype baseline, not the updated test-file positions.
Their 17 tests were rerun after migration. Verification does not extend to APIs with
different execution paths.

| ID | Verified behavior | Contract reference | Executed evidence |
|---|---|---|---|
| K1 | `throw_value` and nested rethrow preserve the same JS value. JS can catch it; uncaught values are also retained, and the session remains usable | §2, B, C | WB:253 `intentional and rethrown guest values retain identity and availability` |
| K2 | Unexpected callback failures and foreign return values become Host Failures. Unexpected callback failure prevents guest catch/finally, subsequent JS, and checkpoint execution | §2, C | WB:54 `unexpected host failure stops guest catch finally and checkpoint immediately`; WB:99 `foreign host return terminates but handled foreign argument stays available` |
| K3 | Host-side catching of termination cannot restore success. After Host Failure, effects, reentry, and the next Turn are rejected. Depth termination also bypasses catch/finally/checkpoint. Later Host failures do not replace the first cause | §4, D | BB:15, 164, 278; WB:2, 135, 205, 223. Depth tests check the specific `stack-depth-limit` cause |
| K4 | The configured depth boundary terminates execution even with a large step budget. JS→Host→JS retains the outer depth. Calls within the boundary and sequential calls succeed; normal completion and guest throws release depth. Materializer-backed script roots do not consume function depth | §4, depth portion of E | BB:164, 215, 242, 265, plus `hosted evaluate counts function depth without counting script roots`. Step budget 100,000; depth limits 0/1/2/16 |
| K5 | Getter access through an ancestor HostCall is rejected. The parent's `record_effect` works after a nested call. HostCall expires after normal return. Public `global` rejects a Running session as Busy; handling that rejection in the Host permits continued execution | §3, parts of H/I | BB:61, 118, 242. This does not cover every expiry path or public entry point |
| K6 | When both the `evaluate` body and checkpoint throw guest values, the body value remains primary, the job value is retained as secondary, and the session returns to Available | §5–6, part of G | BB:94 `body guest throw remains primary over checkpoint guest throw` |
| K7 | `HostedCall.call` rejects foreign arguments before guest-function side effects. Handling the rejection in the Host preserves Available. A foreign return failure does not damage the donor session | §2–3, part of H | WB:99. Getter-before-validation ordering in `call_property` is tracked separately as M2 |

## Resolved in R1

| ID | Implemented behavior | Executed evidence |
|---|---|---|
| M2 | `HostedCall.call_property` checks current authority and argument owners before property lookup; the lookup checks the target/receiver owner before a getter runs. Both public `HostedValue.call_property` and nested `HostedCall.call_property` validate argument owners again after the getter, since Host argument arrays are mutable | BB `R1 foreign property arguments reject before getters or pending jobs` covers primitive, Object, Map, Set, and Promise arguments; `R1 foreign property receiver rejects without entering its getter` covers the receiver. `R1 public property call rejects arguments replaced by its getter` covers replacement with a Closed donor's object. Rejection preserves availability, legitimate calls preserve `this`, and pending jobs wait for outer completion |
| M3 | `expect_number`, `expect_bool`, and `expect_string` require a live owner: Available/Running succeeds; Closed/Faulted rejects without guest execution or a checkpoint | BB `R1 pure extraction rejects closed and faulted retained primitives`; `R1 live pure extraction and conversion rejection preserve pending jobs`. All three extraction methods are exercised; strict mismatch does not call guest coercion methods |

Before the fix, the property-call trace contained an extra `getter` before `rejected`,
and all six Closed/Faulted primitive extractions returned `accepted`. After the fix,
all five R1 tests, three runtime-depth regressions, and the 17 imported regressions pass on native, js, and wasm-gc.
This resolves M2/M3 and the exercised portions of V5/V6/V7, not those groups in full.

### Review corrections

The public property-call regression first reproduced a getter's Host callback replacing
an already-validated argument with an object from a Closed foreign session. The callee
could read that object's property. Argument ownership is now checked again after lookup;
the regression asserts `HostedForeignValue`, no callee side effect, and continued
session availability.

The depth regression first reproduced `(function f() { return 42; })()` failing at
depth 1 while `(() => 42)()` succeeded. Script roots now share materializer lifecycle
hooks without entering the function-depth wrapper. Both forms succeed at depth 1 and
terminate with `stack-depth-limit` at depth 0. Merely creating a named function at
the script root succeeds at depth 0; calling it does not. Existing Host-reentry,
sibling-call, and guest-throw depth regressions remain passing.

Independent Terra review of prerequisite commit `c45e7fb7` found synchronous
generator calls and resumes missing Hosted depth observation. Before correction,
`(function*(){ yield 1 })().next()` succeeded at depth 0 on all three targets.
The synchronous parameter-initialization and body-resume boundaries now acquire
and release depth, including yield, delegation, and exceptional unwind. This
generator correction skips async instances; the prerequisite's existing initial
async-call activation wrapper is unchanged by it. The initial guest invocation
still consumes depth, including at limit 0. Async suspension/resumption guarantees
remain out of scope. Legacy non-Hosted execution is unchanged.

Two generator regressions failed before the correction and pass afterward.
Executable smoke on native, js, and wasm-gc confirmed depth-0 termination,
depth-1 sibling completion after yield/guest throw, nested resume termination at
depth 1, and generator → Host → guest reentry success at depth 2. Temporary
generator executables were removed.

## Resolved in R2

| ID | Implemented behavior | Executed evidence |
|---|---|---|
| M1 | `evaluate`, public `get`, `call`, and `call_property` use one shared completion boundary inside the same Hosted execution-control scope. Normal completion and ordinary guest throws receive one outer checkpoint phase. Nested HostCall, direct global inspection, strict extraction, parse failure, admission rejection, and terminal body completion do not start that phase | Five BB `R2` tests on native/js/wasm-gc exercise all three public Value entries, body/checkpoint outcome combinations, FIFO including newly queued jobs, nested continuation, checkpoint HostCall reentry without recursive drain, retained jobs across pure inspection/parse/rejection, and body/checkpoint interruption |

Before the completion fix, `R2 public guest operations checkpoint normal and guest
throw outcomes` observed only `body`, not the queued `job-1`, `job-2`, `job-3`.
Afterward, all six normal/throw × public-entry cases produce the expected FIFO
trace. Ordinary language errors reuse the runtime's catchable-error conversion;
unexpected callback failures and latched control termination are never converted
into guest errors or allowed to checkpoint. R3 adds the structured provenance and
concrete public raising types described below.

## Implemented in R3

| ID | Implemented behavior | Executed evidence |
|---|---|---|
| M4 | Every fallible Hosted facade operation and constructor raises `HostedProbeError`; callback parameters still admit application errors at the classification seam. Busy/Closed close errors are facade categories. Guest admission rejects Faulted; disposal preserves the existing Faulted→Closed transition without restoring execution | Generated facade interface; BB `R3 Busy close uses the facade category without cancelling the active turn` and `R3 Faulted cleanup closes without reopening admission or dispatching jobs`; public executable smokes exercise evaluate/get/call/property-call errors and lifecycle rejection |
| M5 | Parse and guest outcomes retain immutable `EngineDiagnostic` data alongside actual guest values. Terminal/Host Failure outcomes retain the first cause and optional data-only secondary diagnostics; Host Failure retains the original application error without invoking its formatter | BB `R3` cases cover parser positions/snapshot independence, formatter/getter exclusion, thrown Proxy identity, earlier guest failure followed by checkpoint Host Failure/control termination. WB cases cover nested carrier preservation, trusted body/nested/checkpoint/checkpoint-nested origins, fresh throws of caught values, intentional Host throws, and immutable terminal snapshots |

Source identity is retained when supplied by trusted function metadata. Bare script
throws and parser failures do not acquire an invented source identity. A later
trusted unwind may fill a missing identity without replacing a known origin or
mutating a diagnostic already retained by a Host. Reuse matches the actual error
carrier, not the thrown value: a fresh throw of the same value has fresh provenance.

The three selected script execution envelopes now preserve existing guest exception
carriers; ordinary engine errors still use the established guest conversion. This
avoids losing a nested diagnostic association during script normalization. It does
not promise public physical identity of wrapper objects or change the legacy
compiled-script compatibility adapter.

The runtime remains the sole termination latch. Facade failure fields retain
diagnostics only, and are cleared after a public outcome. Secondary arrays are
copied when a nested error can be retained before later Host cleanup. Terminal
outcomes do not retain usable guest handles as secondary information.

## Not Implemented

This classification identifies a remaining contract gap, not necessarily the absence of the
entire feature.

| ID | Missing contract behavior | Current source evidence | Work unit |
|---|---|---|---|
| M6 | Connect the selected typed adapters to Hosted Turn/HostCall, reporting argument mismatches as JS TypeError before entering the user's MoonBit function | `research_host1/2/function1` in `embedding_research.mbt` at prototype baseline `5c87fea9` use `ProbeRuntime/ProbeValue`. Those adapters are not part of this migration. Raising a strict-extraction error directly from a Hosted callback currently classifies it as Host Failure | R4 |

The resolved M3–M5 and remaining M6 are not additional convenience features. They are
required by the appendix's §2 public types, diagnostics, and typed adapters; §3 value
lifetime; and §4/§6 secondary information and provenance.

## Unverified

Bound verification to the following **seven groups**. Add tests or executable evidence for
the listed conditions, and fix only failures of the existing contract. Test count and coverage
percentage are not goals.

| ID | Fixed verification scope | Existing evidence and remaining gap | Work unit |
|---|---|---|---|
| V1 | Outer JS continues after Host→JS returns; nested return does not drain jobs, and checkpoint runs only after outer completion | R2 public-entry tests establish checkpoints after body completion; `R2 nested returns never recursively checkpoint including checkpoint Host calls` establishes outer continuation and no recursive drain, including Host reentry during checkpoint. R5 will consolidate this evidence with the original A–J scenarios | R2→R5 |
| V2 | Nested calls and checkpoint share steps already spent by the body; reentry and unwinding do not replenish them. Simultaneously applicable limits follow interruption→depth→steps priority | [with_hosted_execution_policy](../interpreter/runtime/execution_policy.mbt) shares a carrier. BB:43 asserts only that low-budget recursion terminates; it could pass even with a fresh budget. Exact sharing and competing-limit precedence remain unproven | R5 |
| V3 | A self-extending Promise job chain terminates under the same budget. Host callbacks during checkpoint receive valid HostCall authority, and nested calls do not recursively checkpoint | R2 verifies current HostCall authority and nested non-drain during checkpoint. Self-extending Promise-chain termination under a shared finite budget remains unverified | R5 |
| V4 | Remaining normal/guest-throw/terminal body-and-checkpoint combinations; FIFO including newly queued jobs; no retry of the failed job; retention of unselected jobs and resumption in the next eligible Turn; no dispatch after terminal failure | R2 verifies normal/guest body × normal/guest checkpoint, interruption in body/checkpoint, FIFO/new jobs, no automatic retry, and later eligible resumption. Structured secondary diagnostics and the remaining Host Failure/control combinations remain R3/R5 work | R2/R3→R5 |
| V5 | HostCall expires on guest throw, Host Failure, and terminal unwind, and cannot revive in later Turns. Owner rejection precedes side effects in getter/call/property-call paths. Receiver/callee realm state restores on normal and exceptional exits. Every JS-capable public entry point rejects Running as Busy | K5/K7 and R1 cover some authority and ownership paths, including property-call receiver/argument rejection. Exceptional expiry, realm restoration, and the complete public Busy matrix remain unverified | R1→R5 |
| V6 | Close while Running is Busy without cancelling or faulting the session. Closed/Faulted admission is rejected. Explicit interruption is observed at admission, Host return, reentry/job dispatch, and other required boundaries. Invalid policy is rejected before admission, and bounded-policy rejection of unobserved native progress is classified as terminal | R1 verifies Closed/Faulted pure-extraction rejection. `close` delegates to [ExecutionSession.close](../hosting.mbt), but Busy close and the remaining interruption/configuration admission cases are not established by these tests | R1/R3→R5 |
| V7 | With jobs already pending, parse failure, pure extraction, and admission/conversion rejection do not drain jobs or unnecessarily fault the session. Strict extraction does not run getters/valueOf/toString | R1 verifies strict extraction and handled foreign-argument rejection. R2 verifies retained jobs across parse failure, strict/direct-global inspection, and public foreign-argument rejection, then drains them on a later eligible getter turn. R4/R5 cover typed-adapter mismatch and final assessment | R1/R2→R5 |

## Out of Scope

| ID | Excluded from this backlog | Reason |
|---|---|---|
| X1 | Async suspension/resumption, cross-thread reentry, and later reuse of expired HostCall authority | Not authorized by §3. Checkpoint processing of existing guest Promises remains in scope under V3/V4 |
| X2 | Sandbox guarantees, wall-clock preemption, stopping arbitrary Host loops/blocking I/O, and recovery from OOM/abort/process crashes | Excluded by §1/§4. Distinguish cooperative interruption from Host responsibilities |
| X3 | Rollback of JS/Host side effects that have already occurred | Not promised by §1. Effects before failure remain |
| X4 | Rewriting the engine, general stack safety across every language path, redesigning the entire activation-observation model, or adding a separate termination state machine | This work concerns contract compliance at Hosted boundaries and reuses the existing observation model |
| X5 | API renaming, wholesale legacy API replacement, release, main merge, push, CI-baseline changes, and performance optimization | These are separate decisions. Verification can finish under the current prototype names |
| X6 | New conversion families, a general codec framework, unbounded type/arity expansion, or a new unhandled-rejection policy | The agreement covers strict conversion and explicit mapping within the selected scope. Broader custom conversions and rejection policy are separate |

## Mapping to Original Scenarios A–J

This mapping prevents partially verified compound scenarios from being marked complete as a whole.

| Original scenario | Inventory rows |
|---|---|
| A: Continuation after nested callback and outer checkpoint | V1 |
| B: Identity of nested guest throws | K1 |
| C: Intentional guest mapping and noncatchable Host Failure | K1, K2; typed argument mismatch is M6 |
| D: Termination and Faulted state despite Host-side catching | K3; unverified job/entry-point differences are V3/V6 |
| E: Shared steps/depth and interruption precedence | K4, V2 |
| F: Self-extending Promise chain | V3 |
| G: Primary/secondary/terminal body-and-checkpoint outcomes | K6, M5, V4 |
| H: HostCall authority, ownership, and restoration | K5, K7, M2, V5 |
| I: Busy close versus cancellation | Public-global Busy coverage in K5; M4, V6 |
| J: Parse/pure inspection with pending jobs | M3, V7 |

## Fixed Remaining Work: R1–R5

The backlog consists of four implementation units and one verification unit. If a newly found
issue cannot be assigned to these IDs with a reference to the original contract, stop and
present it as a separate proposal.

### R1 — Admission, Ownership, and Value Lifetime

Status: **MERGED** in [PR #1060](https://github.com/dowdiness/js_engine/pull/1060),
main commit `985dd1b8c30f4de2585bbe3ad3d7d1315d70f5be`, including the prerequisite
migration. Terra review findings were resolved/adjudicated, and required CI passed.

- Covers: M2, M3, and the admission portions of V5/V6/V7.
- Primary files: `hosted_execution_probe.mbt` and its BB/WB tests.
- Regressions to establish first: a property call with foreign arguments executes a getter; pure extraction accepts Faulted/Closed values.
- Acceptance: validate target/receiver/argument ownership before getter execution. Preserve permitted pure extraction in Available/Running and reject it in Closed/Faulted. Rejection causes no guest side effects, checkpoint, or automatic transition to Faulted.
- Do not invent a new precedence rule for simultaneous Busy/Expired/Foreign conditions or break existing rules.

### R2 — Public Turn Completion and Checkpoint

Status: **Implemented and verified locally; independent review and PR CI pending.**

- Covers: M1, V1, and the checkpoint portions of V4/V7.
- Primary files: `hosted_execution_probe.mbt` and its BB/WB tests.
- Regression to establish first: a public getter/function queues a job and completes normally or with a guest throw, but no outer checkpoint runs.
- Acceptance: only public operations that started JS receive one outer checkpoint phase after normal completion or a guest throw. That phase processes newly queued jobs in FIFO order as well. Nested HostCall, pure inspection, parse failure, rejection, and terminal outcomes do not trigger a checkpoint.
- Move completion handling currently confined to `evaluate` into a reusable boundary. Do not add separate checkpoint implementations to each entry point.

### R3 — Public Failure Types, Diagnostics, and Secondary Information

- Covers: M4, M5, and the outcome-classification portions of V4/V6.
- Primary files: `hosted_execution_probe.mbt`, BB/WB tests, and, if necessary, diagnostic-retention boundaries in the existing `engine_diagnostic.mbt` and runtime `execution_control.mbt` / `execution_policy.mbt`.
- Regressions to establish first: raw errors escape public get/call/close; nested/checkpoint provenance or secondary information on terminal outcomes is lost.
- Acceptance: public operations use concrete raising types and preserve the existing distinguishable failure categories. Guest values retain identity. Parse, body, nested, and checkpoint provenance is distinguishable. The first terminal remains primary while safe secondary information is retained.
- Do not execute guest getters/toString/Proxy traps for diagnostics. Inspect and reuse existing diagnostic mechanisms before adding code; do not introduce a general logging/telemetry system. Renaming types is not a goal.

### R4 — Connect Existing Typed Adapters to Hosted Execution

- Covers: M6 and the Busy guarantee for saved typed JS closures.
- Primary files: the selected adapters in `embedding_research.mbt`, `hosted_execution_probe.mbt`, and related tests. Do not change the older `ProbeRuntime` behavior wholesale.
- Scope: the current numeric `Double` conversion, unary/binary Host adapters, and unary retained JS closure. New types, arities, and codec families belong to X6.
- Regressions to establish first: conversion mismatch becomes Host Failure on the Hosted path, or typed callbacks cannot use that path.
- Acceptance: preserve valid numeric calls. Missing or mismatched arguments produce a catchable, actual JS TypeError before entering the user's MoonBit function, leaving the session Available. No valueOf/toString executes. Unmapped errors from the user function remain Host Failures. Saved closures do not implicitly reenter a Running session.
- Reuse existing conversion and function-retention mechanisms; do not introduce a general binding framework.

### R5 — Verify the Seven Outstanding Groups and Assess Completion

- Covers: V1–V7. Reuse tests added under R1–R4 instead of duplicating the same conditions.
- For cases that already pass, add the evidence and stop. Apply minimal fixes only to failing cases.
- Changes are limited to the facade/adapters above and the runtime observation, queue, or exception boundary directly implicated by a reproduction. Do not expand into general stack safety, compiler-wide changes, or another product's requirements.
- Verify the same behavior on `native`, `js`, and `wasm-gc`. Use separate step and depth oracles; do not hide a depth defect by lowering the step budget.

Dependencies: establish admission behavior with R1 first. Integrate R2 and R3 sequentially because
they modify the same facade completion boundary. R4 uses the resulting failure classification.
R5 test design can accompany each unit, but final assessment follows R1–R4. The user
authorized autonomous execution through R5; each unit remains a separate isolated
PR, with independent review and successful required CI before the next dependent unit.

## Verification Commands and Current Evidence

Run from the worktree root. The focused commands below passed after the R1 and R2 changes.

```sh
moon test --target native hosted_execution_probe_test.mbt hosted_execution_probe_wbtest.mbt
moon test --target js hosted_execution_probe_test.mbt hosted_execution_probe_wbtest.mbt
moon test --target wasm-gc hosted_execution_probe_test.mbt hosted_execution_probe_wbtest.mbt
```

### R1 integration evidence

Each target passed BB **18/18** and WB **7/7**, **25 tests per target**. The imported
17-test baseline passed before the original four R1 regressions were added. Those
regressions reproduced M2/M3; all four review regressions also failed before their
respective fixes and now pass.

For the initial R1 implementation, a temporary `cmd/hosted_r1_smoke` executable was run with `moon run --target native`,
`--target js`, and `--target wasm-gc`. All three runs produced:

```text
property: rejected,getter,callee,job
result: 43, state: available
extraction: closed,closed,closed
extraction: faulted,faulted,faulted
R1 smoke passed
```

The executable asserted these results and was removed after the smoke runs.
The `.mbti` additions are the prerequisite Hosted facade and runtime hooks; R1 does
not alter their signatures. These are project tests and smoke runs, not Test262
conformance figures.

After the review fixes, a separate temporary `cmd/hosted_review_smoke` executable
passed on native, js, and wasm-gc. It asserted foreign-argument rejection after getter
mutation, no callee execution, and continued availability. Declared functions, arrow
IIFEs, and named-function IIFEs all returned 42 at depth 1 and 2, and all terminated
with `stack-depth-limit` at depth 0. A materialized script root that only creates a
named function remained Available at depth 0. The executable was removed after verification.

Full project suites passed after all four review regressions and the generator correction:

| Target | Passed / Executed |
|---|---:|
| native | 4,532 / 4,532 |
| js | 4,400 / 4,400 |
| wasm-gc | 4,398 / 4,398 |

`moon info`, `moon fmt`, `moon fmt --check`, and `moon check --target all --deny-warn`
passed after the review fixes.
Regeneration left the facade and runtime `.mbti` files unchanged, verified by SHA-256.

For the initial R1 implementation, all `architecture-audit` component checks passed:
state inventory, import and
representation boundaries, public surface taxonomy, semantic lifecycle edges,
typed executable-AST boundaries, opaque destructuring plans, and continuation
ownership, including their self-tests. Aggregate commands hit execution deadlines;
completed components were retained and the remaining targets were run separately.
Temporary smoke and audit fixture files were removed.

### R2 local evidence

The five added R2 BB tests passed on native, js, and wasm-gc. Focused suites passed
BB **23/23** and WB **7/7**, **30 tests per target**. Full suites passed:

| Target | Passed / Executed |
|---|---:|
| native | 4,537 / 4,537 |
| js | 4,405 / 4,405 |
| wasm-gc | 4,403 / 4,403 |

`moon info`, `moon fmt`, `moon fmt --check`, and `moon check --target all --deny-warn`
passed. Facade/runtime `.mbti` checksums were unchanged by R2.

A temporary `cmd/hosted_r2_smoke` executable ran using `moon run --target native`,
`--target js`, and `--target wasm-gc`; all three runs asserted and printed:

```text
public-call: nested,host-return,outer,job-1,job-2,job-3
public-properties: getter,getter-job,method,method-job
throws: primary=7, secondary=42, retained-after-eligible-turn, state=available
R2 smoke passed
```

The executable was removed. Independent Terra review passed for both completion/
precedence and queue/reentry/exclusion slices. Reviewers recovered from unavailable
LSP using compiler semantic navigation. Required CI passed on reviewed head
`e1aaf1cc3fc99bd590485eb81c84b02a8893b0b8`; PR #1062 was squash-merged as
`e28dc678916daabfbe58adc5b056651251ced1cb`. Deployment and CodeRabbit's automatic
OSS review were skipped, not passed. R2 results do not prove R3–R5.

### R3 local verification record

Before the Busy-close fix, the facade exposed a Session Busy error. Before structured
parse reporting, the payload was a string with no location API. Before safe Host
capture, the formatter sentinel ran once and entered a donor's guest getter.
Before carrier preservation, uncaught nested rethrows reported `body` instead of
`nested`. Before source enrichment, an intentional Host throw retained its nested
phase but lost the trusted `intentional.js` origin. Each regression passed after
its corresponding correction.

A temporary `cmd/hosted_r3_smoke` executable ran with `moon run --target native`,
`--target js`, and `--target wasm-gc`. All three runs asserted and printed:

```text
parse: evaluate/parse, line=2 column=5 offset=5, state=available
guest: evaluate/get/call/call-property preserve identity; nested phase retained
checkpoint: primary=7/body, secondary=42/checkpoint, state=available
close: Busy does not cancel; repeated close is HostedSessionClosed
Host failure: original cause retained, formatter=0, prior guest/body retained, state=faulted
control: execution-limit/checkpoint, prior guest/body retained, state=faulted
R3 smoke passed
```

The executable was removed. For each target, the focused command
`moon test --target <target> hosted_execution_probe_test.mbt hosted_execution_probe_wbtest.mbt`
passed **42/42** after the disposal clarification; `moon test --target <target>` passed:

| Target | Passed / Executed |
|---|---:|
| native | 4,549 / 4,549 |
| js | 4,417 / 4,417 |
| wasm-gc | 4,415 / 4,415 |

`moon info`, `moon fmt`, `moon fmt --check`, and
`moon check --target all --deny-warn` passed. Generated interface changes are
confined to the intended Hosted error payloads and concrete raising types.
Independent provenance/terminal-retention review passed on the implementation
commit. Category review requested rejecting Faulted `close`; the parent rejected
that source change: the pre-existing disposal operation closes Faulted sessions,
whereas the frozen contract rejects subsequent guest admission and permits no
recovery. The M4 record above previously conflated these operations and is corrected.
The original agreed appendix is unchanged.

The added disposal regression passed on native/js/wasm-gc: guest admission is
Faulted before close, disposal moves to Closed, later guest admission and retained
value extraction are Closed, and no retained job dispatches. A temporary
`cmd/hosted_r3_disposal_smoke` also ran with `moon run --target native`,
`--target js`, and `--target wasm-gc`; each asserted and printed:

```text
Faulted admission rejected; disposal=Closed; later admission/value rejected; jobs=0
R3 disposal smoke passed
```

The disposal executable was removed. No implementation behavior changed during
this clarification. The final suites and all-target warning/interface/format checks
passed with the counts above. Independent re-review and integration remain pending.

During implementation, follow the repository workflow: identify affected callers and argument
types, state assumptions in no more than three lines, and establish a minimal failing end-to-end
test before fixing the behavior. Run `moon check` after each source-file edit. Finish with the
following commands and inspect generated `.mbti` changes.

```sh
moon info
moon fmt
moon check --deny-warn
moon test --target native
moon test --target js
moon test --target wasm-gc
```

Both focused and full suites must have zero failures. Future test counts are not fixed.
Distinguish prerequisite interface additions from R3/R4 contract changes; do not modify
unrelated legacy APIs.

## Completion Criteria and Scope Control

This work is complete only when all of the following hold:

1. R1–R4 implement and verify M1–M6, and evidence exists for V1–V7.
2. No in-scope item in the A–J mapping or the supplementary requirements of §1–6 remains Not implemented or Unverified.
3. K1–K7 remain valid, and focused/full suites pass on all three targets.
4. Scope has not expanded into X1–X6. No separate termination state machine or competing checkpoint rules have been introduced.
5. Every row records the implementation commit, execution command, and observed result. Code existence or a green full suite alone does not justify Verified status.

Do not automatically add improvements absent from the original contract. Map failures of the
existing contract to R1–R5. If a large out-of-scope change appears necessary, report the reproduction
and why that change is needed, then stop. Reducing the contract also requires an explicit user
decision; do not relabel Unverified items as Out of scope to declare completion. Saving the
prototype without publishing it is a valid decision, but its status would be "stopped at prototype,"
not "contract complete."

## Audit Exclusions

The original inventory did not repeat a repository-wide audit, inspect dependency
vulnerabilities, execute Test262, or investigate performance. R1 changes are confined
to the authorized prerequisite migration, admission/lifetime fixes, and verification.
Existing `plans/001`–`006` remain a separate, completed backlog.

## Appendix: Original Agreed Contract

The original session artifact `local://embedding-execution-contract.txt` is preserved verbatim below.
Its "implementation pending" and "not yet passed" statements describe the historical state on
2026-09-20. The classification tables above describe the current state. The original text has
not been rewritten into a new contract.

```text
js_engine — Exception and Nested Execution Contract
Status: DECIDED; implementation pending. 2026-09-20.
This fixes the contract for the selected new value-embedding interface. It does not claim that legacy Engine/ExecutionSession APIs or the experimental wrappers already implement every rule. The previous research note is subordinate to this contract for exceptions and nested execution.

1. Scope and invariants
One Execution Session owns one Hosted Realm and admits one Hosted Turn at a time. A Hosted Turn includes its synchronous body and eligible microtask checkpoint. Nested Host Callback Calls are inside the existing turn, not additional turns. No rollback is promised: JS mutations, host I/O and already-run jobs remain effective even when the operation fails. This is in-process trusted-script embedding, not a security sandbox.

2. Failure classes at the public embedding seam
- Admission/conversion rejection: Busy, Closed, Faulted, ForeignValue, ExpiredHostCall, and strict extraction mismatch. The rejected operation performs no JS work and starts no checkpoint; it does not independently poison the session. Earlier effects of an already-running turn are not undone. Invalid execution configuration is also rejected before starting.
- Parse failure: no JS body starts; report a structured parse error, preserve availability, do not drain previously pending jobs just because parsing failed.
- Guest throw: retain the actual thrown JS Value and structured diagnostic provenance. This includes intentional Host-to-JS throws. It is catchable by JS; if uncaught after body/checkpoint settlement, return it to MoonBit and leave the session available unless terminal failure also occurred. Preserve JS identity, not necessarily physical identity of wrapper objects.
- Expected Host/domain failure: becomes a guest throw only through an explicit mapping/throw operation. No blanket translation of arbitrary MoonBit Error/Failure into JS Error.
- Typed adapter argument mismatch: reject before entering the user MoonBit function with a real JS TypeError. Strict conversion does not run valueOf/toString. Broader custom conversion rules remain separately scoped.
- Host Failure: unexpected error escaping an application callback, invalid foreign return handle, or internal invariant failure. Terminal, host-visible, not guest-catchable; faults the session. Host messages, paths, stack traces and arbitrary error objects are not automatically exposed to JS.
- Control termination: observed interruption, configured step exhaustion, configured active-depth exhaustion, or inability to execute a native path under the selected bounded policy. Terminal, typed, not guest-catchable; faults the session. A JS RangeError thrown by ordinary language/library semantics is still an ordinary guest throw. Configured host depth exhaustion is not to be translated into such a recoverable RangeError in this new interface.

A known guest exception escaping a Host callback is rethrown as the same guest value, not relabelled Host Failure. Known terminal outcomes preserve their original category. Other embedding misuse/errors escaping the Host callback rather than being handled there are Host Failure: only intentional guest failures cross into JS. An error caught and handled entirely inside application code does not automatically fault the engine.

Public operations use a concrete typed raising interface, not a public catch-all Error. Exact type spelling is not frozen by this note; the above distinguishable categories and payload behavior are frozen. Host callbacks may raise application errors; the adapter is the classification seam. Diagnostic capture/formatting must not implicitly execute guest getters, toString, Proxy traps, or allocate JS Error objects after terminal failure. Explicit user formatting may execute JS only through normal admission.

3. Authorized synchronous reentry
HostCall carries runtime-checked authority for its session, its Hosted Turn, and its callback frame. JS-capable HostCall operations are allowed only while that frame is the current active Host callback frame and the turn has no terminal latch. The callback's authority is suspended while its nested guest call or child Host callback executes; it resumes when that nested call returns. Child callbacks receive their own authority. Ancestor authority cannot be used from a child callback. This is deliberately stronger than a single active=true bit.

Ordinary public evaluate/get/call/call_property or a saved top-level typed JS closure called against the Running session still raises Busy. Intentional nesting must use the current HostCall path; merely seeing state Running is not authorization. Nested calls use the same interpreter call/property semantics, including receiver and callee realm, with save/restore on both normal and exceptional exits.

HostCall expires on normal callback return, guest throw, host failure, and terminal unwind. An escaped/expired authority cannot be revived, even during a later turn. Values extracted from callback arguments may be retained under their ordinary session lifetime; this does not retain the callback's execution authority. Same-session pure strict extraction requires no nested execution authority, but respects the selected value lifecycle rule.

Before guest lookup/call, validate authority, target/receiver/argument owners, and terminal state. Foreign handles do not trigger getters. close while running is Busy and is not cancellation. Async suspension/resumption, cross-thread use, and implicit scheduling are not authorized by this contract. A later application-scheduled callback is a new Hosted Turn, never continuation of an escaped HostCall.

4. Shared execution control
The outermost turn owns exactly one execution-control instance for the body, nested calls, and its checkpoint. Nested Host calls cannot replace the policy, reset spent steps, replenish budget, clear interruption, or reset active depth. Limit policy is selected at outer admission, not on HostCall operations.

Step accounting reuses the existing runtime observation model. The same activation is not charged once by the adapter and again by the interpreter. Active depth includes outstanding guest activation across Host crossings and newly entered guest activation; an arbitrary-length JS→Host→JS chain cannot reset its depth at each boundary. Unwinding releases depth exactly once but does not refund consumed steps. Host-only MoonBit recursion/instruction work is not charged as guest execution.

Interruption is cooperative, not wall-clock preemption. Check at turn admission, before reentry/job dispatch, after Host callback return, at existing runtime observation points, and before committing the turn outcome. No promise to stop blocking I/O, arbitrary Host loops, native abort, OOM, or a process crash. Application code is responsible for cancellable Host operations. These hard failures are outside the typed raise/catch guarantee.

At a single observation point where several limits already apply, priority is interruption, then configured depth (where activation is being observed), then steps. Once a terminal cause is observed, latch it. Host-side catch of the raised carrier cannot clear that latch or restore success. At every subsequent engine transition, reject JS execution; no guest catch/finally or new job is run after the terminal outcome is observed. Host cleanup still unwinds, but cleanup cannot call back into this terminated turn. First observed terminal cause remains primary; later cleanup failures are secondary host diagnostics. Return from the outermost call always reports terminal failure and leaves Faulted. Only creation of a new session recovers execution.

5. Microtask checkpoint
No checkpoint on pure inspection, rejected admission, parse failure, or nested HostCall return. A body that started guest execution and completed normally or with an ordinary guest throw gets one outer checkpoint phase, provided no terminal cause has been observed. That phase drains FIFO, including newly queued jobs, under the same execution budget. Host callbacks reached during checkpoint get valid child authority; their nested calls do not recursively checkpoint.

An ordinary exception escaping a microtask stops that checkpoint. The selected failing job is not automatically retried; unselected jobs stay queued. If the session remains available, a later eligible turn's checkpoint may process them. Terminal failure stops dispatch permanently for that session and invalidates scheduled turn authority; it does not imply immediate reclamation of all queue memory. Promise rejection captured by ordinary Promise machinery is not automatically an escaping microtask exception; this contract does not invent an unhandled-rejection policy.

6. Outcome precedence
- Any terminal outcome overrides a prior guest throw or normal result. Preserve prior failures only as safe secondary diagnostic information; do not execute guest code to render them. Handles into a faulted session remain unusable under the value lifetime policy.
- If body and checkpoint both fail with ordinary guest throws, the body throw is primary and the checkpoint throw is retained as secondary, including its value and phase. Neither silently overwrites the other.
- If body succeeds but checkpoint throws, the public operation fails with the checkpoint throw. Do not additionally return the body's successful result; its already-completed effects remain.
- If body throws and checkpoint succeeds, return the body's guest throw.
- Only body success plus checkpoint success returns a value.
Structured provenance distinguishes body, nested callback and checkpoint failure. Completion occurs after checkpoint settlement, not before.

7. Required implementation acceptance scenarios (not yet passed as a full suite)
A. Host invokes a JS callback, then outer JS continues; no checkpoint until outer completion.
B. Nested callback throws token; Host rethrows; JS catches the identical token. Uncaught token crosses to MoonBit without stringification.
C. Intentional domain error is JS-catchable and leaves Available; unmapped Host error faults and does not enter guest catch/finally.
D. Host catches a termination carrier and returns a value; outer operation still terminates, no further JS/jobs run, later turn is Faulted.
E. Nested calls exhaust a shared step/depth budget rather than receiving a fresh one; interruption wins when observed alongside exhaustion.
F. A self-extending Promise chain consumes the outer turn's remaining budget and cannot evade the bound.
G. Body and checkpoint throws preserve primary/secondary values; terminal checkpoint failure instead faults and wins.
H. HostCall escape, ancestor-token use from a child callback, and cross-owner args fail before guest effects. A legitimate outer authority works again after child return.
I. Busy close and overlapping entry do not cancel or fault the active turn when handled by the Host; explicit cancellation does.
J. Parse failure and pure extraction do not unexpectedly drain a previously retained job queue.

8. Evidence and implementation deltas
Existing evidence: the earlier disposable real-engine probes on native/js/wasm-gc demonstrated typed adapters, callback reentry, outer checkpoint ordering, guest thrown identity, and basic expired-authority checks. They did NOT prove ancestor-frame admission, sticky terminal cancellation, noncatchable depth limits, or shared budget accounting.
Current source reviewed: hosting.mbt 670-795 uses integrity-based checkpointing and lets checkpoint diagnostics replace body diagnostics; engine_diagnostic.mbt 540-598 stringifies guest throws; execution_control.mbt 102-159 specifies existing observation precedence; call.mbt contains depth-to-JS-error translations on some paths; promise_core.mbt 70-117 stops a checkpoint on escaping failure. These are implementation inputs, not proof of this new contract. The new interface must integrate through existing Session/runtime control, not add a parallel state machine or silently alter legacy guarantees.
Glossary updated in CONTEXT.md for Nested Host Callback Call, Host Call Authority, Execution Limit Termination and faulted-session terminology. moon check after the glossary update passed. No engine implementation changes were made in this contract-finalization step.
```
