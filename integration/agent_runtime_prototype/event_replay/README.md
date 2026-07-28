# PROTOTYPE P3: append-only event-log replay

Can the current stable `Engine`, `eval`, and `call_json` facade reconstruct the
same pending request or completion from fixed source, input, and an append-only
event log after losing the Engine, without an Engine heap snapshot and without
executing an already-recorded external write again?

## Verdict

**GO, narrowly for the measured Engine-crash boundary.** A fresh native Engine
reproduced the exact ordered requests, consumed recorded successful results with adapter
execution suppressed, recovered approval waiting and terminal completion, and
kept the required scenario's independent fake external write counter at `1`.
Replay-time adapter invocations remained `0`.

This is not a durable workflow system and not an exactly-once claim. The
in-memory host event log and fake adapter idempotency registry survive while only
the Engine is discarded. Full host-process crash, database durability, torn
append recovery, client completion acknowledgement, hostile code, and deployment
isolation are unmeasured.

## Fixed premises

1. Source, input, catalog, runtime fingerprint, and synchronous generator order
   are fixed; only one request is outstanding.
2. Only the Engine/worker is lost; the host's in-memory event log and fake
   adapter idempotency registry remain alive.
3. Replay compares full request JSON, `call-N`, and idempotency key before using
   a result, and never interprets a replayed `InvokeAdapter` directive as I/O.

## Reproduce from the repository root

```bash
PATH=/home/antisatori/.moon/bin:$PATH \
  bash integration/agent_runtime_prototype/event_replay/run.sh --scripted-viewer
```

Omit `--scripted-viewer` for the interactive terminal controls. The command
checks the pure reducer and three native commands with warnings denied, runs the
single issue-sized end-to-end test, executes 46 action rows plus one summary row
twice and requires byte-identical output, validates the 9-event canonical log,
drives the terminal viewer, and hashes all six evidence artifacts.

Measured environment:

- WSL2 Linux `6.6.114.1-microsoft-standard-WSL2`, `x86_64`
- native target only
- `moon 0.1.20260713 (75c7e1f)`
- `moonc v0.10.4+2cc641edf`
- base commit `c249fbab15db305f345391bc72f1c4431138c207`
- branch `prototype/agent-runtime-p3-622`

No JavaScript, Wasm, or Wasm-GC result is claimed by P3.

## Prototype shape

The event reducer in `core/` is pure and imports no Engine, adapter, process,
filesystem, or terminal package. It accepts only contiguous, ordered domain
events and projects the complete replay state.

The root prototype is a disposable shell:

- `engine_shell.mbt` uses only the stable `Engine`, `eval`, and `call_json`
  facade. It never accesses interpreter values or snapshots.
- `broker_shell.mbt` composes the P1 pure ToolBroker API. During replay its
  regenerated `InvokeAdapter` value is checked for call ID, idempotency key, and
  full request equality, then suppressed.
- `adapter_shell.mbt` is an in-memory fake with independent counters for adapter
  attempts, write attempts, external write commits, idempotency cache hits,
  explicit reconciliation attempts, and replay adapter invocations.
- `replay_shell.mbt` verifies identity before Engine construction, creates a
  fresh Engine, and feeds only recorded tagged success results back to the
  generator. Tagged error-result replay is not measured by this fixture.
- `harness.mbt` owns append-only events and deterministic scenarios; the
  terminal viewer is only an I/O layer.

The host-owned runtime fingerprint is exactly:

```text
js_engine@0.7.0;event_replay_schema=v1;base=c249fbab15db305f345391bc72f1c4431138c207
```

It is a host-maintained prototype dependency identity, because the stable Engine
API has no runtime-version getter. It detects a declared mismatch only; the host
must pin or bump it whenever the Engine build or replay contract changes. The
exact embedded source bytes are SHA-256 hashed at runtime; the measured source hash is
`27aad268c066e0057182c3daa19ad959632d68276e8108144a69fb4d623fae58`.
The catalog/capability/budget configuration is hashed separately.

## Canonical event contract

The raw log is in-memory during execution and exported as append-only JSONL. A
sequence starts at `1`, is contiguous, and contains:

1. `SessionStarted` with session ID, source SHA-256, runtime fingerprint, host
   configuration SHA-256, and exact input.
2. `ToolRequestObserved` for `call-1` / `get_user`.
3. `DispatchIntentRecorded` before the read adapter call.
4. `ToolResultRecorded` before generator resume.
5. `ToolRequestObserved` for `call-2` / `update_user_status`.
6. `ApprovalGranted` for that exact call.
7. `DispatchIntentRecorded` before the write adapter call.
8. `ToolResultRecorded` with the tagged write result before generator resume.
9. `SessionCompleted` with the exact completion JSON.

Crash and replay are control rows, not domain events, so replay does not recreate
the crash itself. Every control row renders the entire event log, replay
projection, source hash, runtime fingerprint, request sequence, approval state,
broker state, all adapter counters, Engine epoch/status, and replay cursor.
`replay_state` is the pure projection of the entire recorded log; the top-level
`replay_cursor` is the prefix semantically verified against a fresh Engine. On a
semantic rejection, later recorded events may remain visible in the projection
but are not claimed as replayed or executed.

## Scenarios and observations

| Scenario | Observation |
|---|---|
| Uninterrupted oracle | Two requests, one approved fake write, exact successful completion. |
| Approval-wait recovery | Fresh Engine regenerated `call-1` and `call-2`; phase remained `WaitingApproval`, approval remained `pending`, write commits remained `0`. |
| Required post-result crash | Engine discarded after write result event 8 and before resume; fresh Engine reached the oracle completion, external write commits stayed `1`, replay adapter calls stayed `0`. |
| Repeated completed replay | Two further fresh replays retained the exact completion, event count `9`, cursor `9`, and write count `1`. |
| Read-only completion recovery | Active-user branch recovered exact completion with `0` writes. |
| Cancel recovery | Cancellation recorded at approval wait recovered as terminal `Cancelled`, with `0` writes. |
| Commit-before-result gap | Replay stopped at `AwaitingToolResult` with outcome unknown and no automatic adapter call. An explicit same-key reconciliation hit the surviving fake registry: write attempts `2`, cache hits `1`, commits still `1`. |
| Source/declared-runtime/declared-config/input drift | Each was rejected before Engine construction, cursor `0`, adapter attempts `0`. |
| Request payload divergence | Same `call-2` identity but different arguments was rejected at replay cursor `4`, before result delivery and with adapter attempts `0`. |
| Gapped sequence | Pure reducer rejected it before Engine construction. |
| Stale result identity | Pure reducer rejected `call-9` against pending `call-1` before Engine construction. |

The required completion was exactly:

```json
{"status":"ok","output":{"user_id":"user-1","status":"active","updated":true}}
```

The P1 broker's `adapter_reported_committed_writes` is a reconstructed projection,
not independent external truth. The GO decision uses the fake adapter shell's
separate `fake_external_write_commits` counter.

## Failure boundary and decision rule

`DispatchIntentRecorded` followed by a crash before `ToolResultRecorded` is an
unknown-outcome write. Replay itself fails closed at that tail and performs no
I/O. This fixture can recover only through an explicit retry with the same
idempotency key against a registry that survived the Engine crash.

- **GO:** fixed deterministic source/input/results, Engine-only crash, surviving
  host log and idempotency registry, exact request matching, recorded-result
  replay with zero adapter calls.
- **PIVOT:** a real adapter cannot retain/query the idempotency outcome, source or
  request order depends on uncontrolled inputs, or host-process crash and durable
  application state must be recovered. Persisted explicit workflow state may be
  more appropriate than generator replay.
- **STOP:** replay executes an unrecorded write, executes an already-recorded
  write again, silently accepts source/runtime/request drift, exposes interpreter
  values or Engine snapshots, or is described as rollback.

Controlled nondeterminism and the unmeasured list, including tagged error-result
replay, are preserved verbatim in
`artifacts/nondeterminism-and-boundaries.txt`.

## RED / GREEN evidence

The first command probe failed to compile with:

```text
Value required_transcript not found in package event_replay
```

After adding only a one-line not-implemented stub, the end-to-end test failed
`0 passed, 1 failed`. The final native result is `1 passed, 0 failed`. This is an
issue-sized scenario test, not a generalized production replay suite. The compact
record is `artifacts/red-probe.txt`.

## Responsibility boundary

- **js_engine:** deterministic execution through the existing stable JSON facade;
  no public API or interpreter representation change.
- **host runtime:** source/runtime/config identity, event ordering, request IDs,
  approval, idempotency keys, pure replay reducer, adapter suppression,
  reconciliation policy, and completion delivery semantics.
- **deployment isolation:** not measured by P3; P2's killable worker and P5's
  platform isolation remain separate gates.

## Artifacts

- `artifacts/actions.jsonl` — 46 full action-state rows plus one summary row
  across success and failure scenarios.
- `artifacts/required-events.jsonl` — 9 canonical append-only domain events.
- `artifacts/human-walkthrough.txt` — scripted terminal controls for completion,
  cancellation, and unknown-outcome reconciliation.
- `artifacts/probe-summary.txt` — machine-readable counts and narrow verdict.
- `artifacts/nondeterminism-and-boundaries.txt` — controlled and unmeasured
  nondeterminism.
- `artifacts/artifact-sha256.txt` — hashes for the generated artifacts.
- `artifacts/red-probe.txt` — initial compile/behavior RED and final GREEN record.

The generated hashes for this run are:

```text
484131318a1a6a1c3a8c31b9c60c5eb26ee42a4a9aafbb11c793340a14540107  actions.jsonl
74a8242031c21a6a9efa8510a0f35e8ebf3e6c9679d3b7973380525117a00f0c  required-events.jsonl
bd89e1c6953a10580dec0f00cddcb56b8eb7abe781fe9ccf73cfe98080044ff4  probe-summary.txt
086fa3d0400ff73585292334e5759cc3a98922944681af4ba7cd7ed5786391f0  nondeterminism-and-boundaries.txt
9a8e101b06d94e357cddb45551a50de29fb29e1a87d0adfed5280da8f2f9b893  human-walkthrough.txt
6a7ce1cb508b549d660d699a1a3e4740bcd8c1e9512afd82b0b413c29a38504c  red-probe.txt
```

Timebox: at most two business days. Actual work stayed within one uninterrupted
prototype session and produced one pure reducer, four thin host shells, one
issue-sized harness/test, three native commands, one reproduction script, and
these evidence artifacts.
