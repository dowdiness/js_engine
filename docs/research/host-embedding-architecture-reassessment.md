# Host embedding architecture reassessment

## Decision

Keep the current external shape:

```text
HostEnvironment (immutable Capability Set)
        |
        | create_session(SessionBindings)
        v
ExecutionSession (one Hosted Realm and its mutable host state)
```

No researched alternative provides a better replacement for this ownership
model. It matches ECMAScript terminology and the repeated distinction made by
V8, QuickJS, SpiderMonkey, GraalVM, Boa, and Deno between reusable engine or
installation state and Context/Realm-owned mutable state.

The implementation should **not**, however, continue immediately with more
Capabilities. The validating Console slice exposed four corrections that must
become the next implementation slice:

1. add an internal `Running` state and one private Hosted Turn driver before
   any callback can re-enter a Session;
2. preserve the existing operation-aware `EngineDiagnostic` information and
   fault a Session when engine integrity is `Discard` or cannot safely be
   established;
3. decide and implement the high-level Session's Promise-job checkpoint policy
   in the Hosted Turn driver rather than exposing queue mechanics accidentally;
4. remove the interpreter/compiler special case for the identifier `console`
   so selected Host Capabilities are ordinary Realm-installed globals.

This refinement keeps Capability contracts typed and explicit. A generic
plugin framework should wait until at least a second genuinely different
Capability has been implemented.

## Research question

The reassessment asked whether a more established or deeper embedding
Interface should replace `HostEnvironment + SessionBindings +
ExecutionSession` before the project implements lifecycle, resource loading,
jobs, timers, and additional host-defined globals.

The candidate replacements were:

1. an `Engine + ContextBuilder` model following common engine naming;
2. one public `request(SessionRequest) -> SessionReply` command interface;
3. a generic capability registry with string or erased-type lookup;
4. a one-Realm convenience `ApplicationEngine` layered over the current
   Interface;
5. the current model, strengthened internally and kept explicit externally.

## What the standards actually require

ECMAScript does not prescribe a C, Rust, Java, or MoonBit embedding API. It
defines a Host as the source that supplies the Host Hooks listed in Annex D,
and defines a Host Environment as one particular choice for all host-defined
facilities. A Host Environment typically supplies input/output functions or
objects on the global object. This makes `HostEnvironment` an accurate project
term rather than an invented synonym for an output callback. [ECMA-262, Hosts
and Implementations](https://tc39.es/ecma262/multipage/overview.html#sec-hosts-and-implementations)

Annex D includes Realm initialization, Promise and generic job enqueueing,
module loading, rejection tracking, timeout jobs, host-defined global objects,
and `[[HostDefined]]` fields on Realm, Script, Module, and JobCallback records.
These are internal semantic integration points; they are not evidence for one
universal application callback or one universal data type. [ECMA-262, Host
Layering Points](https://tc39.es/ecma262/multipage/host-layering-points.html)

Consequently, the public application Interface may be smaller and more typed
than the internal Host Hook implementation. Runtime Values, Realm records, and
Jobs need not cross the high-level seam.

## Evidence from established embedders

### Reusable state and Realm-owned state are consistently separate

V8 describes a Context as a separate execution environment with its own
built-ins and global objects. Reusable templates are blueprints instantiated
inside each Context. V8 also requires explicit lifetime management for handles
that outlive a local scope. [V8 embedding guide](https://v8.dev/docs/embed)

QuickJS separates `JSRuntime`, which owns an object heap, from `JSContext`,
which it explicitly calls a Realm and which owns its own global and system
objects. `JSValue` ownership is reference-counted and explicit. [QuickJS C API](https://bellard.org/quickjs/quickjs.html#3.4-quickjs-c-api)

SpiderMonkey provides Context-private data and a Context-owned Job Queue, while
Realm creation takes explicit Realm options. This supports associating host
state with the execution container rather than with process-global callbacks.
[SpiderMonkey JSAPI source](https://searchfox.org/mozilla-central/source/js/src/jsapi.cpp)

GraalVM permits several Contexts to use one explicit Engine so they can share
ASTs or optimized code, while streams, host-access policy, resource limits,
and other concrete configuration are supplied through each Context builder.
[GraalVM `Context.Builder`](https://www.graalvm.org/sdk/javadoc/org/graalvm/polyglot/Context.Builder.html)

Boa similarly constructs a Context with explicit Host Hooks, Clock,
JobExecutor, and ModuleLoader. Those dependencies are Context-owned from the
caller's perspective rather than exposed through one untyped host callback.
[Boa `ContextBuilder`](https://docs.rs/boa_engine/latest/boa_engine/context/struct.ContextBuilder.html)

Deno core constructs one `JsRuntime` from `RuntimeOptions`, installs only the
selected Extensions, and maintains operation resources in runtime-owned
`OpState`. It exposes event-loop progress separately from simple script
execution. [Deno core `RuntimeOptions`](https://docs.rs/deno_core/latest/deno_core/struct.RuntimeOptions.html)
and [`JsRuntime`](https://docs.rs/deno_core/latest/deno_core/struct.JsRuntime.html)

**Inference:** the project's immutable environment plan plus a concrete
per-Session binding is well supported. The application may deliberately pass
the same sink, loader, clock, or scheduler to several Sessions, but Realm
wrappers, callbacks, queues, lifecycle, and fault attribution remain
Session-owned.

### Job checkpoint policy is an embedding decision

ECMAScript defines the ordering and Realm preparation requirements for Jobs,
but does not require every public `eval` call in every embedding API to drain
all jobs. V8 offers explicit, scoped, and automatic microtask policies.
[V8 `MicrotasksPolicy`](https://v8.github.io/api/head/namespacev8.html)
QuickJS exposes pending-job execution through its runtime API, Boa documents
that `Context::eval` does not run scheduled Promise jobs, and Deno exposes an
event-loop driver. [Boa `Context`](https://docs.rs/boa_engine/latest/boa_engine/context/struct.Context.html)
[Deno core `JsRuntime`](https://docs.rs/deno_core/latest/deno_core/struct.JsRuntime.html)

**Inference:** `ExecutionSession` may define a convenient automatic checkpoint
for each accepted Hosted Turn, while the low-level Runtime Interpreter remains
explicit. The policy must be intentional and tested. Queue methods should not
leak into the general embedding Interface merely because the current low-level
Engine exposes them.

### Lifecycle and cancellation need more than `Available/Faulted`

V8 permits only one thread to enter an Isolate at a time. GraalVM rejects
unsupported concurrent Context access, rejects ordinary close while another
thread is executing, distinguishes destructive cancellation from a reusable
soft interrupt, and rejects use after close. [V8 `Isolate`](https://v8.github.io/api/head/classv8_1_1Isolate.html)
[GraalVM `Context`](https://www.graalvm.org/25.0/javadoc/sdk/org/graalvm/polyglot/Context.html)

The project's conservative decision that cancellation faults a Session is
still defensible because interrupted JavaScript may have partially committed
state. The immediate missing state is `Running`: without it, an Output Sink or
future Host Capability callback can call the same Session recursively.

The private state machine should therefore begin as:

```text
Available --accept turn--> Running --normal/script failure--> Available
                              |
                              +--unsafe internal/Host failure--> Faulted

Available --close--> Closed
Running   --new request or close--> reject as Busy
Faulted/Closed --run request--> reject before JavaScript starts
```

This transition belongs in one private functional core used by every public
entry point. It does not require replacing typed methods with a command bus.

### Console is richer than rendered text

The WHATWG Console Standard passes a log level and a list of values through
`Logger` and `Formatter` to an implementation-defined `Printer`. Printer may
receive JavaScript objects or implementation-specific printable
representations; Console also owns group, count, and timer state. [WHATWG
Console, Logger and Printer](https://console.spec.whatwg.org/#logging)

The current `ConsoleOutput { kind, text }` is a safe first copy boundary but is
not a complete Console Standard Printer interface. Exposing raw Runtime Values
to the application would preserve information but would also leak Realm and
GC lifetime. The stronger long-term shape is:

```text
Realm-owned Console implementation
  -> applies Console formatting and snapshots any required display data
  -> emits an immutable, Realm-independent Console Event
  -> application Output Sink chooses routing/rendering
```

Do not claim full Console Standard compatibility while output is implemented
as `Value::to_string()` joined with spaces. Also do not make shell `print` a
Console event; it remains a separate shell compatibility contract.

## Local implementation findings

### The new Session facade currently loses established diagnostics

The repository already has `EngineDiagnostic`, including operation, phase,
source identity/location, retained effects, pending jobs, and whether the
underlying Engine is reusable or must be discarded. The current
`ExecutionSession::evaluate` and `call_json` use the older raised `EngineError`
path and wrap it as `ExecutionSessionError::ExecutionError`.

This loses information and treats an internal Engine failure like an ordinary
script failure. `finish_turn` returns the Session to availability for every
`EngineError`; only a captured Output Sink failure faults it. That contradicts
the existing `EngineIntegrity::Discard` diagnostic contract.

The next slice should route Session execution through the diagnostic path and
derive the next Session state from the diagnostic's integrity. It should not
create a third parallel error taxonomy.

### A Hosted Turn is not yet implemented

`ExecutionSession` currently checks `Available` before execution but never
transitions to `Running`. It also does not run a Promise-job checkpoint, while
the lower-level `Engine` exposes checkpoint methods separately. Therefore the
current Console slice validates ownership and fault attribution, but not the
complete Hosted Turn contract described by the ADRs.

### Console still bypasses ordinary identifier lookup

The interpreter and bytecode compiler contain dedicated `console` recognition
and a `LoadConsoleMember` instruction. Installing a real global object while
retaining this path can disagree with lexical shadowing and normal property
semantics. New Host Capabilities should be ordinary objects/functions installed
in the Session's Realm. A capability-specific bytecode instruction should be
introduced only after a measured performance need, not as its semantic basis.

### The public surface already has two competing stateful engines

The older public `Engine` and the new `ExecutionSession` both expose repeated
evaluation, JSON calls, output/job behavior, and errors. Adding lifecycle only
to `ExecutionSession` without deciding which Module is authoritative will
duplicate rules and tests.

`ExecutionSession` should become the authoritative high-level application
Module. The older `Engine` may remain temporarily as a compatibility facade or
become internal after migration. The low-level Runtime Interpreter remains the
intentional raw-Value seam.

## Alternative Interface comparison

### 1. Rename to `Engine + ContextBuilder`

This is familiar to V8, GraalVM, Boa, and QuickJS users, but it is not a
semantic improvement. The repository already uses `Engine` for a mutable
one-Realm facade, while ECMAScript uses "execution context" for stack/runtime
machinery. Renaming now would create ambiguity without changing ownership.

**Decision:** reject. Keep the accurate project terms `HostEnvironment` and
`ExecutionSession`.

### 2. Replace typed methods with `request(SessionRequest)`

A request/reply union centralizes dispatch but does not actually reduce what a
caller must learn. It moves `evaluate`, `call_json`, and `close` into variants,
adds reply variants that can be mismatched with requests, and weakens the
static relationship between input and return type. The lifecycle/checkpoint
duplication can be removed by one private Hosted Turn function while retaining
typed public methods.

**Decision:** reject the public command bus. Use a private turn driver.

### 3. Add a generic Capability registry now

A string-keyed or erased-type registry makes arbitrary extension easy but
pushes name conflicts, binding validation, value conversion, exception
classification, Realm lifetime, scheduling, and teardown rules onto every
Capability author. It is broad but shallow. MoonBit callers also lose the
clarity of labelled typed construction.

**Decision:** reject now. Implement two or three typed Capability contracts,
then extract only repeated private installation/binding machinery.

Application-defined RPC can later use an explicitly named JSON Data Copy
profile. Console, timers, and module loading must not be forced through JSON.

### 4. Add a convenience `ApplicationEngine` wrapper

This shortens the smallest example, but it would initially be a pass-through
over one private `HostEnvironment`, one `SessionBindings`, and one
`ExecutionSession`. Deleting it would merely move its few constructor calls
back to the caller. It also creates a third stateful execution name beside
`Engine` and `ExecutionSession`.

**Decision:** reject until real application callers demonstrate repeated
setup complexity. First make the authoritative Module correct and deep.

### 5. Refine the current model

This preserves typed return values, explicit capability authority, deliberate
service sharing, and accurate ECMAScript vocabulary. A private turn driver,
private capability installers, and one diagnostic model hide the difficult
behavior without widening the public Interface.

**Decision:** adopt.

## Recommended Interface direction

Keep the public concepts small:

```moonbit
pub struct HostEnvironment
pub struct SessionBindings
pub struct ExecutionSession

pub fn HostEnvironment::create_session(
  self : HostEnvironment,
  bindings? : SessionBindings,
) -> ExecutionSession raise SessionCreationError

pub fn ExecutionSession::evaluate(
  self : ExecutionSession,
  source : String,
) -> Result[Unit, SessionDiagnostic]

pub fn ExecutionSession::call_json(
  self : ExecutionSession,
  name : String,
  arguments : Array[Json],
) -> Result[Json, SessionDiagnostic]

pub fn ExecutionSession::close(
  self : ExecutionSession,
) -> Result[Unit, SessionDiagnostic]
```

This is conceptual pseudocode, not a final naming decision. The important
constraint is one diagnostic family that preserves the existing engine detail
and distinguishes:

- rejection before JavaScript starts (`busy`, `closed`, `faulted`);
- JavaScript/parse/data-copy failure with the Session still reusable;
- Host Failure associated with the active Capability and Session;
- internal failure whose integrity requires discarding the Session;
- cancellation as its own typed outcome.

The private Implementation should look like:

```text
typed public method
  -> private begin_turn (Available -> Running)
  -> execute through diagnostic Engine path
  -> apply selected microtask policy
  -> classify outcome and retained effects
  -> private finish_turn (Available or Faulted)
```

Capability-specific Realm adapters install ordinary globals and call private
Session bindings. ECMAScript Host Hooks remain internal and use the Realm/Job
types required by the specification.

## Implementation order

### Slice 1: lifecycle and diagnostic spine

Write public-seam tests first for:

- Output Sink re-entry being rejected as `busy` before nested JavaScript runs;
- close from `Available`, close while `Running`, and use after close;
- parse/JavaScript exceptions returning the Session to `Available`;
- an injected internal error faulting the Session according to engine
  integrity;
- a Host Failure faulting only the invoking Session;
- retained effects and pending-job information remaining available in the
  Session diagnostic.

Then implement one private Hosted Turn driver and route both `evaluate` and
`call_json` through it.

### Slice 2: explicit high-level Promise-job policy

Choose automatic checkpointing for the high-level Session only if tests define
its exact ordering and failure precedence. Keep the Runtime Interpreter and
specialized embedders capable of explicit queue control. Do not combine timer
tasks with ECMAScript Promise jobs.

### Slice 3: ordinary Console global

Remove semantic dependence on special AST/bytecode Console paths. Test lexical
shadowing, reassignment/property behavior, absence when not selected, and
tree-walker/bytecode equivalence. Then deepen Console formatting and replace
the current text-only claim with an accurately named immutable Console Event
contract.

### Slice 4: second typed Capability

Implement one Capability with meaningfully different behavior, preferably
Script Resource/module loading rather than another output function. Only then
extract a private common installer/binding protocol from demonstrated
duplication.

### Slice 5: application scheduling

Keep Promise jobs Session-owned. Let a Timer or resource Capability give the
application scheduler an opaque, Session-owned resumption token rather than a
Runtime Value or JavaScript callback. Define close/fault invalidation and
one-shot behavior before exposing it.

## Final assessment

The research found no better wholesale architecture than the adopted
capability-plan-plus-session-bindings model. It did find a better **next step**
than simply implementing `close` and then adding more capabilities: first
unify lifecycle, diagnostics, integrity, reentrancy, and the Hosted Turn policy
behind `ExecutionSession`.

After that correction, the current direction should scale. Without it, every
new callback, loader, job, or timer would multiply inconsistent lifecycle and
error behavior and make the public Module shallow.

## Implementation outcome

The five slices were implemented in the order above. `ExecutionSession` now
uses one lifecycle and diagnostic path with explicit running, closed, and
faulted states. High-level Hosted Turns automatically drain Promise jobs but
do not run timer tasks. Console is an ordinary global and no longer has AST,
closure-conversion, or bytecode instructions that bypass identifier and member
semantics.

Script Resources validate the second typed Capability shape: the application
receives opaque requests and referrers, expected unavailability is catchable by
JavaScript, and resolver failure is a Session-faulting Host Failure. Timers
validate scheduling and retained lifetime: the application receives an opaque
`ScheduledTurn`, while the Session retains the Realm callback, enforces
ownership and one-shot use, and invalidates outstanding turns on close or
fault. This evidence supports the selected architecture without introducing a
generic capability registry, universal command bus, or public Runtime Values.
