# Embedded Runtime Vision

This document defines the long-term product direction for `js_engine` as an
embedded JavaScript runtime. It is a decision framework, not a claim that every
capability described here is available today. Current behavior belongs in the
embedding guide, current sequencing belongs in the roadmap, and concrete API
contracts belong in focused decision documents.

## Long-term objective

`js_engine` should let a MoonBit application run trusted JavaScript under an
explicit data boundary, authority boundary, execution policy, and failure
model, with equivalent observable behavior on MoonBit's native, JavaScript,
Wasm, and Wasm-GC targets.

The product is a controllable scripting runtime, not merely a JavaScript parser
and interpreter. Adoption depends on whether a host application can predict
what code may do, when execution returns, what state remains after failure, and
which host capabilities were granted.

## Intended users and workloads

The primary user is a MoonBit application author embedding application-owned or
otherwise trusted scripts for work such as rules, policy, configuration,
transformations, and automation.

Typical workloads should be able to:

- load a script once and call it repeatedly;
- keep intentional JavaScript state between calls;
- exchange plain data without importing runtime-internal value types;
- expose narrowly scoped host capabilities when needed;
- drive queued work explicitly; and
- bound or interrupt faulty execution without discarding the host process.

JavaScript source may still contain mistakes or receive unexpected data.
"Trusted" means the host is willing to grant the script the configured runtime
and capabilities. It does not mean that scripts are bug-free.

The default Hono core is a named reference workload for this direction. The
acceptance scenario pins the `hono` package, uses its default entry point and
`SmartRouter`, bundles it without syntax downleveling, and supplies a minimal
Web Standard shim inside the JavaScript fixture. The MoonBit host observes the
result through `Engine`, an explicit microtask checkpoint, and `call_json`.
This demonstrates useful framework-level compatibility without changing the
primary MoonBit embedder audience or promising Hono server adapters, Node.js
compatibility, a DOM, or a complete Web Platform implementation.

## Product promises

### A stable host boundary

The stable embedding surface must not require consumers to understand or retain
the interpreter's internal value representation, environment model, realm
storage, AST representation, or queue implementation. Those internals must be
free to evolve without forcing ordinary embedders to migrate.

Existing APIs that expose internal representations may remain for compatibility
or advanced integration, but they are not the model for new stable embedding
features. Stable, compatibility, and advanced surfaces must be identified
explicitly in documentation.

### Host-controlled execution

The host owns the lifetime and scheduling of an embedded runtime. It must be
possible to define when scripts run, when queued jobs run, and when execution
must return control to the host.

Execution limits and interruption are part of the runtime contract rather than
a security label. When a limit or interruption is requested, behavior should be
deterministic at the documented observation points across supported targets.
Persistent embedding calls do not advance queued work implicitly. Convenience
APIs may drain queues, but their scheduling behavior must be explicit in the API
contract and user documentation.

### A non-executing plain-data bridge

The first stable host ABI is strict JSON-shaped data. Crossing this boundary
must copy data directly rather than invoke mutable JavaScript facilities or
user-defined behavior. Conversion must not depend on getters, proxies,
serialization hooks, or user-replaced global objects.

Non-JSON capabilities, if added later, require separate explicit abstractions.
They must not be introduced by widening the stable API to expose raw runtime
values.

### Explicit host authority

A host function is a capability granted to JavaScript, not merely a convenient
foreign-function wrapper. Host integrations should make granted authority,
ownership, lifetime, error conversion, and re-entry behavior reviewable.

Stable host callbacks should begin with strict plain-data arguments and return
values. Asynchronous callbacks require a separate execution and lifetime model;
they are not an implicit extension of synchronous callbacks.

### Predictable failure and retained state

JavaScript-visible mutations completed before an exception, interruption, or
execution-limit failure are not transactionally rolled back. This must be
documented consistently.

The separate runtime-integrity question must always be answerable: after each
failure category, the host must know whether the runtime remains reusable,
whether queued jobs remain, and whether the runtime must be discarded. Ordinary
script failures should not corrupt runtime invariants.

### Cross-target behavioral consistency

Support for native, JavaScript, Wasm, and Wasm-GC means more than successful
compilation. The same embedding scenario should produce equivalent data,
failure classification, queue ordering, authority checks, and execution-limit
decisions on every supported target.

Target-dependent details that cannot be guaranteed, such as some diagnostic
formatting or platform services, must be separated from the portable contract.

### Actionable diagnostics

An embedder should be able to distinguish parse failures, JavaScript
exceptions, boundary conversion failures, host failures, interruption,
execution-limit exhaustion, and engine defects. Diagnostics should preserve
structured classification and source context for applications while still
providing useful human-readable output.

Engine integrity, retained side effects, and pending-job state are separate
diagnostic facts. A reusable Engine has intact runtime invariants; that label
does not promise rollback or make retrying the failed operation safe.

Error evolution must account for source compatibility. Adding a new error case
must not be treated as automatically harmless merely because it is additive in
the implementation.

## Execution-model principles

The long-term execution model follows these principles:

1. A persistent runtime owns one isolated JavaScript realm unless an explicitly
   different abstraction is introduced.
2. Parsing or compilation is conceptually separate from execution, even if an
   initial convenience API performs both.
3. The host explicitly drives asynchronous job progress.
4. Re-entry into an already executing runtime is rejected or detected according
   to a documented rule.
5. Execution accounting covers all JavaScript work reached through a bounded
   operation, including relevant queued work and host-boundary transitions as
   defined by the eventual contract.
6. Normal errors and execution limits preserve engine integrity; invariant
   failures are classified separately.
7. Deterministic providers should be possible for host-dependent facilities
   such as time and randomness when those facilities are part of an embedding.

These principles do not prescribe a tree-walking interpreter, bytecode VM, or
other internal execution strategy.

## Security boundary

`js_engine` is not a security sandbox. Execution budgets, interruption,
capability restriction, and a strict data bridge reduce operational risk from
buggy trusted scripts, but they do not establish isolation from hostile code.

Documentation and release notes must not describe these controls as making
arbitrary untrusted JavaScript safe. A future hostile-code isolation claim would
require a separate threat model, resource model, security review, and sustained
security process.

## Non-goals

The embedded-runtime direction does not require:

- browser compatibility, DOM, or Web Platform APIs;
- Node.js compatibility;
- crater-specific context lifecycle;
- a V8- or QuickJS-compatible host API;
- automatic conversion of arbitrary MoonBit values;
- an automatically running browser- or Node-style event loop;
- snapshots or runtime serialization;
- a bytecode VM as the default runtime;
- maximizing a headline Test262 percentage at the expense of embedder needs.

ECMAScript conformance remains important. It protects the language semantics on
which embedders rely, but it is one quality signal rather than the product
definition.

## Compatibility policy

New stable embedding features should be additive where possible and should not
expose internal representations for short-term convenience. Before changing a
stable contract, maintainers must consider external source compatibility,
failure behavior, target parity, and migration cost.

Concrete contracts with compatibility consequences belong in decision
documents before implementation. In particular, global injection, re-entry,
execution accounting, error evolution, and callback lifetime must be decided
explicitly rather than emerging from internal helper behavior.

## Success criteria

The direction is successful when an external MoonBit consumer can, using only
the stable root facade and current embedding documentation:

- load and repeatedly invoke trusted JavaScript;
- exchange strict plain data and inject host-owned configuration;
- grant narrowly scoped synchronous host capabilities;
- set an execution bound and interrupt work;
- understand queue progress and drive it deliberately;
- receive machine-readable failure classification, source context, Engine
  integrity, retained-effect status, and pending-job status through the stable
  facade;
- run the pinned default-Hono/`SmartRouter` scenario through the documented
  Engine/checkpoint/JSON protocol without source patches or syntax downleveling;
- avoid all dependency on interpreter-internal values and state; and
- run all portable acceptance scenarios on all four supported targets.

These criteria are stronger than "works inside this repository" and more useful
to adoption than a conformance percentage alone.
