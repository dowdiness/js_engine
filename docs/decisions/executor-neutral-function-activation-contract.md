# Executor-neutral function activation contract

Date: 2026-07-31.

## Status

Accepted for the executor-neutral seam. This contract separates observable
JavaScript function activation from executor-private body state. It is a
prerequisite for, not a claim of, stack-safe mixed bytecode execution.

## Decision

Represent an executable function body as an opaque capability that creates an
executor-private frame from a runtime-prepared activation. The capability may
select and initialize body state, but it may not run the body to completion or
hide a nested guest activation. A coordinator repeatedly asks the frame for an
explicit progress or completion decision.

Runtime remains the sole owner of the observable work around the body:

- call versus construct entry;
- receiver normalization and binding;
- closure, parameter, rest, `arguments`, and `new.target` setup;
- realm-sensitive prototype selection;
- call and constructor-result normalization; and
- restoration and error propagation at the synchronous public boundary.

Executors own only their code representation and resumable body state. A frame
does not expose its instruction pointer, operand stack, tree cursor, locals, or
other representation through the neutral contract. Mutable collections handed
across the boundary use owned snapshots or defensive copies.

The runtime function object retains a runtime-owned `ExecutorCallableData`
payload rather than erasing the capability into a final-value callback. Direct
dependents can classify that neutral callable, ask runtime to prepare an
ordinary activation, and start its private frame without executing the body.
The payload exposes no compiler representation; observable activation metadata
remains runtime-owned.

The existing synchronous API is a root adapter around this explicit
activation. The adapter is not a continuation and is not evidence that nested
bytecode calls are stack-safe. Once downstream work admits a nested operation
to the managed dispatcher, that operation must yield rather than re-enter the
synchronous adapter.

## Package and ownership boundary

The dependency remains one-way from executor code toward runtime. Runtime never
imports an executor representation. The coordinator operates only on opaque
code and frame capabilities plus runtime-owned activation and completion data.

Closure conversion is a compatibility consumer, not the owner of this seam.
Removing that implementation later must not require redesigning bytecode
activation or moving observable call semantics into the bytecode executor.

The neutral surface is internal package architecture. It does not enlarge the
root facade or make executor frames part of the supported embedding API.

## Adjacent activation work

The accepted activation-continuation contract from #630 supplies the
root-request/final-completion shape, exactly-once continuation rule, and the
requirement that managed nested calls yield instead of recursively entering a
synchronous adapter. Its tree-walker recipe and continuation taxonomy remain
private and are not reused as the executor-neutral representation.

Root admission from #690 decides which existing tree programs enter the managed
dispatcher. It neither identifies executable function bodies nor selects a
bytecode frame.

Production-work exhaustiveness from #691 closes the effect surface within that
tree dispatcher. Those production variants remain private; the neutral
activation contract does not export or mirror them.

#631 owns the next boundary: saving a bytecode caller's pending instruction and
value consumer, entering bytecode/tree/native targets without host-recursive
re-entry, and routing return, throw, getter, Proxy, conversion, and rejection
outcomes exactly once. Until those slices land, mixed calls may preserve
semantics through the synchronous compatibility boundary but are not claimed
stack-safe.

## Alternatives considered

### Bare opaque code handle

A handle preserves package direction and representation privacy, but does not
say who prepares `this`, parameters, `arguments`, construction state, realm, or
cleanup. A handle alone is therefore only the body-selection part of the
contract.

### Runtime-prepared activation plus opaque frame capability

Selected. It gives observable activation semantics one runtime owner while
letting each executor retain private resumable state. Explicit frame decisions
also provide the point where #631 can replace the synchronous root adapter with
managed suspension and resumption.

### Callback returning the final value

Rejected as the semantic seam. A final-value callback erases the activation,
hides intermediate guest entry, and cannot identify the pending consumer that
must resume after a nested call. A compatibility callback may enter the neutral
coordinator only at a synchronous root boundary; it cannot itself be the body
representation or be used recursively by a managed activation.

## Invariants

- Runtime preparation happens once before the executor observes the activation.
- The executable capability creates one private frame and does not execute a
  nested guest call during frame creation.
- Progress and completion cross the seam as closed decisions, not host-language
  continuations.
- Call and construct outcomes remain distinct until runtime normalizes them.
- Guest throws remain guest-catchable; engine failures are not silently
  translated into JavaScript values.
- Cleanup and dynamically scoped runtime state are restored on both normal and
  abrupt exit.
- No stack-safety claim extends beyond the call edges explicitly migrated to
  the managed dispatcher.

## Verification boundary

Focused tests must cover runtime preparation and multi-step frame driving, plus
ordinary/method receivers, strict and sloppy `this`, parameters and
`arguments`, construction and `new.target`, realm-sensitive prototype fallback,
mixed target return, native arguments, and guest throw propagation. These tests
protect semantic compatibility of the seam. Deep mixed-call stack safety and
runtime-operation suspension remain downstream acceptance criteria.
