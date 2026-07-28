# PROTOTYPE: In-memory ToolBroker

## Question

Can an in-memory ToolBroker represent validation, authority, approval,
execution, and result delivery without leaking credentials or letting generated
code choose its own authority?

This issue-only prototype answers that question with a native MoonBit state
machine. It is not production Agent Runtime code and must stay off `main`.

## Working assumptions

1. The Worker can submit only an exact JSON `{tool, arguments}` envelope; every authority and control decision is host-owned.
2. Exactly one call is outstanding, and every adapter is a fixed fake shell outside the pure reducer.
3. Count budget means adapter dispatches; byte budget means cumulative UTF-8 bytes of the schema-normalized request, excluding results and IPC framing.

The first prototype code edit is dated 2026-07-28 JST. The verdict deadline is
2026-07-30 JST (at most two working days).

## Canonical language

- **Authority** is the immutable set of host-granted capabilities for this
  broker session. Approval never adds authority.
- **Effect class** is `Read` or `Write` and comes only from the host catalog.
- **Approval** is per-call operator consent for an authorized write. It never
  dispatches an adapter by itself.
- **Dispatch** is a separate trusted-host action that rechecks authority,
  approval, cancellation, and budgets before emitting one credential-free
  adapter directive.
- **Adapter effect count** counts emitted adapter directives. It is not an
  exactly-once or transactional guarantee for an external service.
- **Adapter result observation** counts a typed adapter result returned to the
  reducer; it is not evidence that an in-flight adapter completed when no
  result arrived.
- **Completed** means one tool-call lifecycle completed; the in-memory broker
  may accept the next call until its cumulative budget is exhausted.
- **Cancelled** is session-terminal. The host observes it and discards the P0
  Engine; no cancellation `ToolResult` is delivered back to the Worker.

The host catalog contains only `get_user` (`user.read`, read, no approval) and
`update_user_status` (`user.write`, write, approval required). Worker JSON may
not select capabilities, effect class, approval, IDs, idempotency keys,
credentials, adapter routes, or budget accounting.

## State-machine boundary

The pure core has the shape `reduce(state, action) -> { after, effects }` and
uses the exact phases `Ready`, `ValidatingRequest`, `Rejected`,
`WaitingApproval`, `Executing`, `ReturningResult`, `Completed`, and
`Cancelled`. Worker ingress is untyped JSON accepted only by `SubmitRequest`.
Validation, approval, rejection, cancellation, dispatch, adapter completion,
result preparation, and result delivery are typed host actions and cannot be
decoded from Worker JSON.

A valid request reserves one call and its canonical request bytes before either
entering `Executing(dispatched=false)` for a read or `WaitingApproval` for a
write. Operator rejection or cancellation before dispatch releases the
reservation. `Approve` moves only to `Executing(dispatched=false)` and emits no
effect. A later matching `Dispatch` atomically converts the reservation to used
budget and may emit one `InvokeAdapter` directive. Duplicate or stale host
actions emit no effect.

The thin native shell owns the fake credential, invokes the fake adapter only
for an emitted directive, and feeds a typed adapter result back to the reducer.
Raw adapter results and internal adapter errors are not rendered as actions.
Successful data must match the fixed result schema and the request identity
before it enters state or becomes the P0-compatible tagged `ToolResult`
`{tag:"ok",value}` or `{tag:"error",error}`. Requests, state, directives,
results, and transcripts must contain no copy of the credential canary.

The same-host-call retry fixture deliberately presents one already-emitted
write directive twice to a shell-owned in-memory idempotency registry. Both
attempts return the same cached result and only the first commits. This is the
only retry boundary measured here; P3 owns crash/replay recovery.

## Required evidence

The deterministic probe records every action, complete `before` and `after`
state, and all declarative effects as JSONL. It covers successful reads and
approved writes, operator rejection, unknown tools, malformed arguments,
script-selected authority/control fields, missing capability, adapter failure,
cancellation during validation, while waiting, and immediately after approval,
exact and exhausted count/byte budgets, duplicate dispatch and adapter retry,
credential-bearing invalid adapter data, and stale host call IDs.

Every rejected, cancelled, stale, duplicate, or budget-exhausted transition
must emit no adapter directive and leave adapter invocation and committed-write
counters unchanged. The viewer includes human-readable authority-escalation and
approve-then-cancel walkthroughs with the same full state.

## Run

From the repository root:

```bash
bash integration/agent_runtime_prototype/tool_broker/run.sh
```

The command checks the standalone native module, emits the deterministic JSONL
artifact, verifies the credential canary is absent, hashes the transcript, and
launches the native terminal viewer. For automated reproduction of the same
viewer actions:

```bash
bash integration/agent_runtime_prototype/tool_broker/run.sh --scripted-viewer
```

Artifact hashes are relative to their directory and can be checked with:

```bash
cd integration/agent_runtime_prototype/tool_broker/artifacts
sha256sum -c artifact-sha256.txt
```

## Verdict

**GO.** Within the measured single-process, native, in-memory boundary, a pure
reducer can keep Worker requests separate from host-owned authority, approval,
dispatch, and credentials while enforcing pre-dispatch budgets and returning a
typed result. This is a feasibility result for the P1 question, not a claim of
production readiness, durable exactly-once execution, or hostile-code safety.

The TDD sequence was:

1. **RED (compile):** the probe failed with `Value required_transcript not
   found` before the harness seam existed.
2. **RED (behavior):** the minimal seam compiled and then aborted with
   `required ToolBroker transcript is empty`.
3. **GREEN:** the deterministic probe, native viewer checks, and two harness
   tests all passed after the reducer and thin fake-adapter shell were added.

Recorded evidence on Ubuntu 24.04.4 LTS under WSL2, MoonBit
`0.1.20260713`, native target, branch `prototype/agent-runtime-p1-623`, base
commit `e1d70e36543210a267fae31e8a26baccb6a0ce6e`:

- 19/19 scenarios and 97/97 recorded transitions passed; all eight required
  phases occur in the JSONL transcript.
- 16 `DeliverResult` actions produced exactly 16 `DeliverToolResult` effects
  and 16 matching `WorkerReceivedToolResult` observations.
- Four call-bound cancellations were accepted across the three required timing
  boundaries plus one cleanup cancellation in the stale-call scenario; one
  stale cancellation was rejected. Every cancelled scenario recorded zero
  adapter effects.
- Duplicate broker dispatch emitted one directive. Presenting that same
  directive twice to the shell-owned registry recorded two attempts, one
  committed write, and one idempotency-cache hit with the same result.
- The host credential canary occurred zero times in requests, rendered state,
  directives, results, and published artifacts. Invalid adapter data containing
  the canary was rejected before publication.
- The default PTY viewer was driven command by command after the scripted run;
  both produced the same deterministic walkthrough output.

Final artifact SHA-256 values:

```text
6fa0067ab6f23926eb2bd3fbf348ed4d53ef68bf4e317df34258ffa19ad53a65  transitions.jsonl
5bab55fef05275e6e0a34f725b578578d9601440873320ab19273985717701ff  human-walkthrough.txt
39c398bbb841e43fab3b88ab7af81d528c04e39306405ea557c591d2e64a8fac  probe-summary.txt
```

The Worker owns only `{tool, arguments}` selection. The broker owns catalog
lookup, capability checks, approval state, cancellation, budgets, call IDs,
idempotency keys, dispatch directives, result validation, and delivery. The
operator owns write approval/rejection and pre-dispatch cancellation. The thin
adapter shell owns credentials, I/O, and the measured in-memory idempotency
registry. On terminal cancellation the host owns discarding the P0 Engine; P3
owns durable replay and crash recovery.

The prototype began and reached this verdict on 2026-07-28 JST, within the
two-working-day limit.

## Unmeasured boundaries

Real adapter security, durable approvals, concurrent outstanding calls, crash
recovery, cross-process retry, external exactly-once effects, result/output byte
limits, Engine integration, network or filesystem isolation, hostile-code
safety, and non-native targets are outside P1. The input seam starts from an
already-decoded `Json`; duplicate keys in serialized JSON are therefore not
measured because the JSON decoder has already collapsed them. Raw serialized
ingress/parse size, malformed-request memory use, arbitrary-scale integer
rollover, and call-ID exhaustion are also unmeasured; the byte gate applies to
accepted schema-normalized requests. P3 owns replay after crashes; P5 owns
deployment isolation. This prototype changes no `js_engine` production code or
public API.
