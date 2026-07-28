# PROTOTYPE: Stable-facade generator coroutine

## Question

Can the current stable Engine, eval, and call_json interface retain a JavaScript generator across host calls and express a multi-tool Code Mode session without exposing interpreter internals?

This issue-only prototype answers that question at the external-consumer boundary. It is not production Agent Runtime code and must stay off `main`.

## Working assumptions

1. The JavaScript generator remains reachable only through lexical state inside one persistent `Engine` realm.
2. The host observes and supplies strict JSON only: tool requests, tool results, completions, and protocol errors.
3. A target mismatch, an advanced runtime import, a public API change, or generated-interface churn ends the experiment with PIVOT or STOP.

The first prototype code edit is dated 2026-07-28 JST. The verdict deadline is 2026-07-30 JST (at most two working days).

## Required scenarios

- inactive user: `get_user`, `update_user_status`, complete;
- active user: `get_user`, complete;
- read failure and write failure as tagged JSON data;
- malformed `ToolResult` without consuming the suspended generator;
- resume after completion;
- discard while waiting;
- restart with a fresh `Engine`.

## Boundary

Only the stable root facade (`Engine`, `eval`, and `call_json`) may be imported from `dowdiness/js_engine`. No raw interpreter, runtime value, generator handle, or host callback may cross the interface. The protocol state is pure; terminal I/O is confined to the disposable native viewer.

## Run

From the repository root:

```bash
bash integration/agent_runtime_prototype/coroutine/run.sh
```

The command will run deterministic probes on native, JavaScript, Wasm, and Wasm-GC, export diffable JSONL transcripts, compare them, and then make the native terminal state viewer available. The implementation and evidence are added incrementally from a RED end-to-end probe.

For a non-interactive reproduction of the same viewer actions:

```bash
bash integration/agent_runtime_prototype/coroutine/run.sh --scripted-viewer
```

## Verdict: GO for P0

The stable facade is sufficient for this bounded experiment. One persistent `Engine` retains a synchronous JavaScript generator between `start_agent_session` and repeated `resume_agent_session` calls. The generator, its handle, and runtime values remain inside the JavaScript realm; every facade argument and reply is strict `Json`.

The probe covers eight named scenarios and emits 23 complete-state JSONL records per target. All four artifacts are byte-for-byte identical:

```text
78b2bac61ceed2737e3e03d700aa4017d6730fce9aa6434b0646f5485d145ec7  native.jsonl
78b2bac61ceed2737e3e03d700aa4017d6730fce9aa6434b0646f5485d145ec7  js.jsonl
78b2bac61ceed2737e3e03d700aa4017d6730fce9aa6434b0646f5485d145ec7  wasm.jsonl
78b2bac61ceed2737e3e03d700aa4017d6730fce9aa6434b0646f5485d145ec7  wasm-gc.jsonl
```

Exact evidence is under [`artifacts/`](artifacts/):

- `native.jsonl`, `js.jsonl`, `wasm.jsonl`, and `wasm-gc.jsonl` are the machine-readable transcripts;
- `transcript-sha256.txt` and `parity.txt` record the comparison;
- `inactive-user-walkthrough.txt` is the human-readable native viewer walkthrough.

The semantic edge decisions are explicit:

- malformed result validation happens in the JavaScript wrapper before `.next()`, so the session remains `waiting` and a corrected result resumes the same suspension;
- a tool failure is tagged JSON data consumed by the generator and becomes a terminal error completion;
- resume after completion is rejected without replacing the original completion;
- discard removes the host's only `Engine` reference and does not call generator `.return()`;
- restart constructs and evaluates a fresh `Engine`, increments `engine_epoch`, rejects a stale resume as `not_started`, and starts from a fresh `get_user` request.

Request IDs, approval, capability, idempotency, and adapter metadata are intentionally deferred to P1. P0 does not claim deterministic Engine destruction, in-realm cancellation, timeout control, tool authority, queue behavior, isolation, persistence, or hostile-code safety.

## RED/GREEN evidence

The external-consumer probe was added first. Its initial check failed at the intended seam:

```text
$ moon check cmd/probe
Value required_transcript not found in package `coroutine`.
```

The completed reproduction commands are:

```bash
cd integration/agent_runtime_prototype/coroutine
PATH=/home/antisatori/.moon/bin:$PATH moon check --deny-warn
cd ../../../..
bash integration/agent_runtime_prototype/coroutine/run.sh --scripted-viewer
```

Measured environment:

```text
dependency commit: e3dff6e35d2f412922431e5ba4e216fec4700f8b (#620 verdict)
origin/main at dependency creation: 03748040a66c8b361811c981c34687c7906e776c
moon: 0.1.20260713 (75c7e1f, 2026-07-13)
moonc: v0.10.4+2cc641edf (2026-07-15)
moonrun: 0.1.20260713 (75c7e1f, 2026-07-13)
host: Linux 6.6.114.1-microsoft-standard-WSL2 x86_64
```

Repository validation also passed `moon check --deny-warn` and the existing test suite (`2621 / 2621`). `moon info` generated only the new standalone prototype interfaces; the stable root `pkg.generated.mbti` did not change. The architecture state audit and its tests passed, as did all 39 boundary-audit tests. The final repository boundary scan intentionally reports four unclassified imports under this new nested standalone module (stable root plus its own prototype packages); production boundary rules were not broadened for an off-main prototype. Direct inspection confirms there are no advanced interpreter/runtime imports.

## Non-goals

No LLM calls, generated source, async callbacks, promises, timers, MCP, network, persistence, hostile-code execution, public Engine changes, shipping, or merge work belongs in this prototype.
