# Agent Runtime feasibility contract

Date: 2026-07-28

## Status

Accepted as the entry gate for Milestone 11. The milestone is a sequence of
throwaway experiments, not authorization to add an Agent Runtime to the stable
engine. Prototype branches and commits remain off `main`.

## Question and assumptions

Can `js_engine` remain the portable JavaScript core of a single-node Agent Code
Runtime while authority, durability, process control, model access, and
deployment isolation stay outside the engine?

This decision starts from three assumptions:

1. The existing stable `Engine`, `eval`, `call_json`, and strict JSON boundary
   remain unchanged throughout the discovery.
2. The first deployment is single-node Linux for one tenant operated by a
   trusted host. Generated programs are not trusted with host authority, but
   this milestone does not claim hostile-code isolation.
3. Stack-safe execution remains owned by #615. Worker killability is required
   before generated programs are used in the model experiment, but it is not a
   substitute for the engine work tracked there.

## Product boundary

`js_engine` remains a pure MoonBit, four-target embedded JavaScript runtime for
trusted scripts. Its stable responsibility ends at deterministic JavaScript
execution, persistent realm state, explicit queue advancement, strict JSON data
conversion, and structured engine diagnostics. Instruction accounting and
interruption are availability controls, not an isolation boundary.

The proposed Agent Runtime is an upper, host-owned system. It treats generated
source and yielded requests as untrusted data, grants no ambient host
capabilities, and mediates every effect outside the `Engine`. Its initial
deployment profile is one host, one tenant, and one disposable worker per
session on Linux.

If the experiments justify production work, the Agent Runtime belongs in a
separate repository. Platform process APIs, model SDKs, persistence, credential
handling, and deployment policy must not become dependencies of the portable
engine package. Any engine-core gap found by a prototype must be proposed as a
separate focused engine issue rather than implemented on a prototype branch.

## Vocabulary and responsibility matrix

| Component | Owns | Must not own |
|---|---|---|
| **Engine** (`js_engine`) | ECMAScript semantics; one persistent realm; stable evaluation and strict JSON calls; explicit queue progress; engine diagnostics and integrity classification | Tool credentials or authority; approval; model calls; event persistence; process lifecycle; filesystem or network isolation |
| **Agent Executor** | Session orchestration; generated-source validation; start/resume/discard decisions; conversion between generator results and the broker protocol | Direct tool effects; credential storage inside source or requests; claims that an Engine is a sandbox |
| **ToolBroker** | Tool catalog and argument validation; host capability lookup; approval state; budgets; host-owned call IDs and idempotency keys; result delivery | Script-selected authority; ambient adapters; generated or worker-visible credentials; JavaScript execution |
| **Sandbox Supervisor** | Worker creation, deadlines, output bounds, termination, reap confirmation, audit classification, and the selected deployment-isolation configuration | ECMAScript semantics; tool-policy decisions; treating process killability alone as security isolation |
| **Worker** | One disposable Engine and the generated program for one session; line-delimited prototype IPC | Credentials; direct filesystem or network access; model calls; cross-session reuse; durable state |
| **Event Store** | Ordered immutable session events, source and runtime identity, approval and tool-result records, replay cursor | Engine heap snapshots; re-executing recorded effects; deciding tool authority |

The functional core is the ToolBroker/session/replay reducer. Terminal,
process, model, adapter, clock, and network operations are thin imperative
shells. Prototype state stays in memory except that P3 explicitly validates an
append-only event-log representation.

## Generated-program and tool protocol profile

The v1 generated program is plain JavaScript accepted by `js_engine` and uses a
generator to yield tool requests. It has no npm modules, Node.js APIs, DOM,
ambient filesystem, ambient network, host callbacks, timers, or Promise-aware
tool calls. One Engine belongs to one prototype session and retains the
generator between start and resume operations.

The program may exchange only JSON-shaped data through the stable facade. A
`ToolRequest` contains a tool name and JSON arguments. A `ToolResult` contains
tagged JSON success or failure data. Exactly one request may be outstanding in
v1. Request IDs, approval decisions, capabilities, idempotency keys, adapters,
and credentials are host-owned; script-controlled fields cannot raise
authority or bypass approval.

An Engine is discarded after cancellation, an unsupported integrity result, a
worker failure, or a replay identity mismatch. The host never serializes or
restores an Engine heap. JavaScript-visible mutations and completed external
effects are not rolled back.

## Threat model

### Actors, assets, and trust

The trusted computing base for the discovery consists of the host Agent
Executor, ToolBroker, Event Store reducer, Sandbox Supervisor, tool adapters,
and their configuration. For properties claimed by P5, it also includes the
selected isolation runtime, operating-system kernel, and relevant host
configuration. The operator and fixed test fixtures are trusted.

The attacker model controls the language-model output, generated JavaScript,
every script-selected ToolRequest field, and potentially adversarial data
returned by a tool. It may issue arbitrary requests, loop forever, panic the
Worker, flood or truncate IPC, and try to read every capability visible inside
the Worker. A compromised operator, host kernel, isolation runtime, ToolBroker,
or tool adapter is outside this discovery; those components require separate
hardening and review. The Worker and all attacker-controlled values are
untrusted inputs to the trusted computing base.

Protected assets are host and tool credentials, host files and environment,
network authority, adapter effects, approval decisions, event-log integrity,
resource availability, other sessions, and the correctness of the audit
record. P0 through P3 use only fixed fixtures and fake effects. P4 may use a
separately authorized model-provider credential and endpoint only in the host
model client; its task inputs remain fixed and non-secret and every tool effect
remains fake. No production tool credential or production tool endpoint is
permitted in any prototype.

The discovery grants only these capabilities:

- pure JavaScript computation and realm-local memory inside one Worker;
- JSON input supplied by the host;
- requests for catalogued tools through the ToolBroker;
- automatic execution of explicitly allowed read operations;
- execution of write operations only after a host approval transition; and
- JSON results returned by the host after adapter execution.

### Threat treatment

| Threat | Treatment in this milestone | Remaining boundary |
|---|---|---|
| Generated code names an unknown tool, sends malformed arguments, or asks for stronger authority | P1 validates catalog, schema, host capability, approval, and budgets before adapter execution. Authority is never derived from request fields. | Production schemas, policy administration, and adapter review are deferred. |
| Generated source or a request attempts to obtain credentials | Tool credentials exist only in host adapters, while an authorized P4 provider credential exists only in the host model client. Both are excluded from source, Worker environment, requests, results, and transcripts. P1 and P4 record violations. | Secret-store integration and redaction review are deferred. |
| A write is executed without approval or is duplicated by retry/replay | P1 separates approval from execution. P3 records host IDs, idempotency keys, and completed results and must replay without invoking the fake write again. | This is not an exactly-once or transactional guarantee for real services. |
| Generated JavaScript hangs, panics, floods output, or corrupts IPC | P2 runs it only in a child, bounds time and output, kills and reaps it, and proves the supervisor can start a new Worker. | Process control is not filesystem, network, or tenant isolation. |
| A program consumes CPU, memory, storage, processes, or network outside the broker | P0 through P3 use fixed source fixtures. P4 runs model-generated source only inside the P2 killable-Worker boundary, with fixed non-secret inputs and fake effects in a disposable environment. P5 then probes one established isolation configuration with predeclared limits and canaries. | P2 is only a process-lifecycle boundary. A P5 GO applies only to the named configuration and still requires hardening, fuzzing, and external security review. |
| A Worker reads host files, environment secrets, localhost, or unrestricted egress | P5 must deny canary file, canary environment, localhost, and disallowed test endpoint access while brokered tools still work. | No hostile-code or multi-tenant claim follows from this discovery. |
| Event, source, or runtime drift changes replay behavior | P3 binds replay to source hash, runtime version, ordered request identity, and append-only events; mismatches fail closed. | Durable storage integrity, migration, and recovery operations are deferred. |
| Tool output or model output injects new instructions or malformed protocol data | Both are parsed as data and must pass the fixed JSON protocol. One diagnostic repair is the P4 maximum. | Prompt-injection resistance in real tool content is not established. |
| Engine failure leaves unknown integrity or pending effects | The Agent Executor uses structured diagnostics where available and discards the Engine on unsupported integrity. It never assumes rollback or safe retry. | Completion of engine guardrails and stack-safe execution remains separately tracked. |
| One tenant or session observes another | Initial scope is one tenant and no Worker reuse. P5 distinguishes and destroys instances after each run. | Cross-tenant scheduling and multi-tenant isolation are out of scope. |
| Model or provider access leaks prompts, fixtures, or credentials | P4 requires separate external-access and cost authorization. Provider credentials and endpoint configuration stay in the host model client and never enter source, Worker environment, protocol records, or transcripts. The Worker receives only generated source plus fixed non-secret JSON inputs and ToolResults. | Provider retention, legal, and production data policy require a separate decision. |

## Sequential prototype gates

The order is fixed: #620, P0 #626, P1 #623, P2 #625, P3 #622, P4 #627,
P5 #624, then synthesis in #628. A prototype starts only from the latest
`origin/main` or the explicitly identified dependency prototype commit, in its
own worktree and branch.

| Gate | Primary evidence required | Claim permitted by GO | Claim still prohibited |
|---|---|---|---|
| **#620 scope** | This reviewed boundary, responsibility matrix, threat treatment, dependency graph, and measurable gates | The discovery has a bounded question and test plan | Technical viability or security |
| **P0: stable-facade generator** | One persistent Engine; inactive/active/failure/malformed/resume/discard/restart scenarios; identical machine-readable transcripts from native, JavaScript, Wasm, and Wasm-GC | The exact deterministic generator coroutine scenario fits behind the current stable JSON facade on the four measured targets | Tool authority, generated-model reliability, nontermination control, or isolation |
| **P1: ToolBroker** | Pure transition transcript covering read, write, unknown/malformed, approve/reject, failure, cancellation, and count/byte exhaustion; zero unauthorized adapter effects | The fixed in-memory protocol separates validation, authority, approval, execution, and result delivery | Real adapter security, durable approval, or exactly-once writes |
| **P2: native supervisor** | Normal, hang, panic, output overflow, malformed/truncated IPC, deadline race, and restart scenarios using the declared one-second deadline, one-MiB output cap, and two-second kill confirmation; every child killed when required and reaped | The named native Linux/WSL supervisor configuration regains control from each fixed failure fixture | Hostile-code containment or cross-target process control |
| **P3: event replay** | Required post-write crash; fresh Engine; fixed IDs/results; effect counter remains one; approval and completion recovery; source/runtime mismatch rejection | The fixed deterministic scenario can recover from an append-only log without Engine snapshots or re-executing the fake write | Transactional rollback, arbitrary nondeterminism, durable storage, or real-service exactly-once behavior |
| **P4: model comparison** | Fixed 20-task corpus; same model/catalog/fixtures; two-strategy smoke then at least three repetitions per task and strategy; all failures retained; request/token/cost limits; hashes and sampling recorded | Only the measured provider, exact model revision, corpus, prompts, date, and budget comparison | General model superiority, permanent provider choice, or GO from directional data |
| **P5: deployment isolation** | One pinned established primitive; canary probes for host-file and environment reads, outbound network, localhost, memory and CPU exhaustion, process spawning, oversized IPC, and worker-to-worker access; Worker and Supervisor limits; broker seam success; exact cleanup inventory with no leftovers | Only the named configuration on the named platform passed the recorded canary probes | Security certification, portable hostile-code safety, or multi-tenant isolation |

P4 may begin only if P0 through P3 are all GO and generated programs run only
inside the killable Worker proven by P2. It also requires separate authorization
for external model access and cost. Before any model call it must record
provider, exact model ID or revision, sampling and seed, prompt/catalog/fixture
hashes, maximum requests, separate input and output token limits, total tokens,
currency spend, and a non-trivial minimum token reduction. If any provider,
model, budget, credential, or authorization value is unset, no call is allowed.
A two-task smoke probe may consume at most ten percent of the approved budget.
If the budget cannot support three repetitions for every task under both
strategies, the result is directional and cannot be GO.

A P4 GO additionally requires at least 80 percent first-pass parse and protocol
success, at least 95 percent success after no more than one diagnostic repair,
zero unauthorized tool executions, task success no more than five percentage
points below the direct-tool baseline, lower median total model tokens on the
multi-tool corpus, and one generation driving multiple sequential tools without
returning intermediate data to the model.

P5 chooses exactly one already available isolation primitive for a named,
disposable single-node Linux test environment. Before exhaustion probes it
records CPU, memory, storage, process count, output bytes, and wall-clock limits
for both Worker and Supervisor, including the Supervisor headroom that keeps the
host test boundary responsive. Only canary files, canary environment values,
fake credentials, and test-only endpoints may be probed. The matrix includes
host-file reads, environment reads, outbound network, localhost, memory and CPU
exhaustion, process spawning, oversized IPC, worker-to-worker access, and a
successful brokered tool call. A run is incomplete until every Worker,
background process, namespace, container or microVM, temporary credential, and
network rule that it created is proven absent.

## Verdict rules and dependency handling

Each issue receives exactly one `GO`, `PIVOT`, or `STOP` verdict against its
predeclared gate:

- **GO** means every required observation for the exact tested boundary passed.
  Unmeasured targets or threats remain explicit. The next issue may start
  without another design decision.
- **PIVOT** means a narrower architecture remains plausible, but the current
  dependency chain or claim does not. Dependent later prototypes do not run.
  The evidence and narrower product are synthesized in #628.
- **STOP** means a safety condition, stable-facade boundary, budget, timebox, or
  core feasibility requirement failed. Dependent prototypes do not run and
  #628 records the milestone STOP.

The goal is a supported decision, not a completed checklist. A first non-GO
verdict ends the current sequence unless #628 can show that a later experiment
is independent and necessary for the narrower decision; running it then
requires an explicit revised scope. Exceeding a prototype timebox or external
budget is evidence for PIVOT or STOP, never permission to generalize the code.

P0 through P3 have a maximum of two working days each from first code edit to
written verdict. P4 and P5 have a maximum of three working days each, excluding
time waiting for explicit external-access or cost approval.

## Evidence and publication contract

Every prototype is clearly marked `PROTOTYPE`, reproducible from the repository
root with one command, and kept on its own throwaway branch. It begins with a
minimal end-to-end scenario that demonstrably fails before implementation.
Production abstractions and general-purpose test suites are not prototype
deliverables.

An issue verdict is complete only after its evidence comment records:

- the exact question, assumptions, predeclared timebox, and actual effort;
- reproduction command, base commit, prototype commit, branch, operating
  system, target, MoonBit and relevant tool versions;
- every scenario and a raw JSONL, transcript, benchmark, or other artifact;
- one decisive human-readable walkthrough;
- successes, failures, parse/repair/timeout/rejection observations, and the
  denominator used for aggregate results;
- explicitly unmeasured boundaries and the responsibility split among
  `js_engine`, the host runtime, and deployment isolation;
- the GO, PIVOT, or STOP verdict and its issue-specific rationale; and
- a verified link to the pushed prototype branch and commit.

Commit, push, issue comment, tracker update, issue close, and eventual cleanup
are distinct publication actions. Prototype code is never merged into `main`
through this milestone. After an authorized push, the branch and commit are
read back from GitHub before the evidence comment is posted. Only then may the
matching #628 checkbox be checked and a final-verdict issue be closed.

## Consequences

P0 may proceed without exposing `Interpreter`, runtime values, generator
handles, or callbacks through the root facade. The experiments may reject the
Agent Runtime direction without changing the existing embedded-runtime
product. A successful discovery still authorizes only a separately scoped
production plan; it does not authorize a new public API, production repository,
release, hostile-code claim, or multi-tenant backlog.
