# Stack-safe engine activation and continuation contract

Date: 2026-07-29. Revised 2026-07-29 after validating the suspension seam
against the minimized #616 programs and the current evaluator.

## Status

Accepted. Acceptance of this contract is recorded by the merge that introduces
this document. The original #618 exploration is superseded: retaining only a
statement position could preserve where a callee started, but not the caller
computation waiting for the callee's result.

This contract remains narrower than Proper Tail Calls (#607) and the complete
may-call-user-code migration retained by #608. It does not classify tail
positions, require bytecode, or claim that every runtime path capable of
entering guest code is stack-safe.

## Context

The current tree-walking interpreter propagates nested call results through the
host call stack. A statement position appears to identify enough state to pause
execution. The #616 programs disprove that expectation: a call may suspend
inside an expression whose result still has to be combined, returned, checked,
or delivered to another language operation.

The pending work is observable. Re-entering the enclosing statement can repeat
an assignment, argument evaluation, accessor effect, or Proxy trap. Advancing
past it can discard a binary operation, a return, or an invariant check. The
state that must survive suspension is therefore the exact consumer of the
callee's completion. The surrounding statement identifies too little state.

Post-parse recursion is independent and landed in #614. Intra-expression tree
walking is not itself the claim addressed here. The failure occurs when a guest
activation is entered synchronously beneath evaluator and runtime-operation
frames that still owe semantic work.

How many such consumers lie on the four #616 paths is not established by the
examples alone. The implementation begins with those observed paths, but the
reachable-call inventory decides whether the focused slice must expand.

## Decision: one deep execution module

Introduce one private execution module whose interface accepts a root execution
request and returns a final completion. Behind that small interface, the module
owns guest activations, pending value consumers, handler and finalizer state,
and activation cleanup.

Existing synchronous entry points remain adapters at this seam. Once execution
has entered the managed module, an internal path that needs to invoke guest code
returns control to the dispatcher; it does not recursively enter a synchronous
adapter and wait on the host stack.

The module's state transitions are deterministic. Given the current execution
state and an observed event, the core returns the next state and a decision. It
does not perform evaluator calls, lifecycle mutation, error translation,
scheduling, or other effects. A thin imperative shell performs those effects
and feeds their results back to the core.

This separation fixes the correctness model and makes it testable. Handler
selection, finalizer precedence, and ownership release must produce the same
decision without depending on which host frames happen to exist.

## Completion model

A completed value and a completed guest computation are not interchangeable.
The model distinguishes at least:

- ordinary completion;
- function return;
- labelled and unlabelled break;
- labelled and unlabelled continue;
- a guest-catchable throw; and
- a runtime or engine failure that guest code cannot necessarily catch.

The representation may vary, but those distinctions must survive suspension
and resumption. In particular, engine control failure must not become a guest
throw merely because both paths stop ordinary evaluation.

Every completion is routed until one of three things happens: a construct
consumes it, a handler or finalizer changes it, or it reaches the root adapter.
A plain value cannot bypass that routing when the caller still owes semantic
work.

## Activation ownership

One activation owns all execution state needed by one interpreted guest
function. It also owns an immutable snapshot or opaque cleanup capability for
dynamically scoped interpreter state installed on entry.

Entry captures prior state before installing callee state. Nested activations
own separate cleanup capabilities, so releasing a callee cannot overwrite the
caller's restoration data. Internal mutable collections are not exposed through
the module interface.

The cleanup capability remains owned while a completion can still be handled
inside the activation. Ordinary completion, return, break, continue, guest
throw, and runtime failure may all pass through handlers or finalizers before
the activation ends. None of those intermediate transitions releases cleanup.

When completion routing finally leaves an activation, the shell consumes its
cleanup capability exactly once. A rejected entry restores any state installed
before rejection but does not release an activation that was never acquired.
Thus every attempted entry has one balanced outcome: no acquired activation, or
one acquired activation followed by one release.

## Semantic continuations

A semantic continuation records what remains after a suspended guest call
produces a completion. The execution module owns this data and captures no
host-language continuation.

The initial #630 slice must preserve the pending work for:

- returning a resumed expression result;
- combining the right operand of an expression with its saved left operand;
- delivering an accessor result to property access;
- enforcing Proxy result invariants before returning the trap result;
- delivering an ordinary call result to its enclosing expression;
- selecting an applicable catch handler;
- executing a pending finalizer for every completion category;
- replacing a saved completion when the finalizer completes abruptly; and
- propagating the surviving completion to its owning activation.

These continuations carry only the semantic data required to resume once. They
must not retain a host evaluator frame, depend on host tail-call optimization,
or repeat an already observed effect.

The implementation may divide the internal states among several private
modules. Callers still see one root-request/final-completion interface and do
not learn the internal frame taxonomy.

## Suspension and dispatch

When a managed evaluator or runtime operation would invoke interpreted guest
code, it yields a call request and the continuation that will consume the
result. The dispatcher retains that continuation, enters the callee activation,
and resumes the saved consumer after the callee completes.

A native operation that cannot enter guest code may complete in the shell. A
native or runtime adapter that can enter guest code cannot be treated this way
until the reachable-call inventory either brings it into the managed cycle or
proves it outside that cycle.

The dispatcher follows these ownership rules:

1. observe a requested effect without changing semantic state;
2. let the shell perform the effect;
3. reduce the observed result into the next deterministic state;
4. retain cleanup while handlers or finalizers can still resume the activation;
5. release an activation only when completion routing leaves it; and
6. translate only the final root completion through the public synchronous
   adapter.

No ordinary call is resumed by replaying its enclosing statement. Argument
evaluation, assignments, accessor effects, Proxy trap effects, handler entry,
and finalizer entry therefore occur in source order and at most once.

## Required semantic traces

### Value consumed by an enclosing expression

For a return expression that combines a local value with a recursive call:

1. evaluate the non-call operand and retain it in continuation state;
2. enter the callee without retaining the caller's host evaluator frame;
3. resume the pending combination from the callee's value; and
4. route the combined value through the saved return completion.

The mutation that prepared the recursive argument occurs once. If the design
cannot show where the saved operand and return completion live, it has only
moved the recursion rather than removed it.

### Accessor result

For an expression that consumes a getter result:

1. retain the property operation and its enclosing expression state;
2. enter the getter activation;
3. return the getter value to the property operation; and
4. resume each enclosing value consumer exactly once.

Prototype traversal and receiver selection remain those of the existing
property semantics. Suspension does not authorize a second lookup.

### Proxy result and invariant enforcement

For an expression that consumes a Proxy trap result:

1. retain the target, property key, receiver, and pending invariant work;
2. enter the trap activation;
3. run the required invariants once on the trap result; and
4. resume the enclosing property and expression continuations.

Returning directly from the trap would be stack-safe but wrong. The invariant
work after the call is part of the continuation and cannot be discarded.

## Abrupt completion and finalizers

Guest throws and runtime failures become distinct abrupt completions. The
dispatcher searches explicit handler state rather than unwinding through host
evaluator frames.

- A catchable guest completion enters the nearest applicable catch handler with
  the established binding and environment rules.
- Ordinary completion, return, break, continue, guest throw, and runtime failure
  all enter a pending finalizer.
- A normally completed finalizer resumes the saved completion.
- An abruptly completed finalizer replaces the saved completion.
- Only a completion that has no remaining owner leaves the activation and
  triggers cleanup release.

A break or continue handled after a finalizer may keep the same activation
alive. A return or throw may leave it. Ownership determines release. Cleanup
tests must therefore observe both the intermediate finalizer path and the
eventual activation exit.

## Reachable-call closure

Before implementation, inspect every guest-call edge reachable from the four
#616 programs. For each edge, record:

1. the possible categories of callee;
2. the value or abrupt completion consumed afterward;
3. effects that must not be replayed;
4. whether #630 migrates the edge, proves it outside the managed cycle, or
   retains it as a named #608 residual; and
5. the focused test that covers the classification.

The inventory includes ordinary calls, returns, binary expressions,
own/prototype accessors, Proxy result invariants, handler and finalizer routing,
realm state, and parameter-default state. If another guest-call edge or
host-stack-owned cleanup action is reachable, the migrated closure expands.
Recursive fallback is not an acceptable substitute.

Constructors, conversions, generators, async jobs, iterators, built-in
callbacks, setters, and other Proxy operations remain #608 work unless the
inventory proves that #630 reaches them. Until that inventory is complete, the
current evaluator determines the size of the first implementation slice. This
contract does not fix that size in advance.

## Migration and compatibility

Migration proceeds in behavioral slices. Each slice first establishes a failing
end-to-end case, then adds deterministic transition coverage, then replaces the
recursive path without changing evaluation order, error order, source identity,
realm behavior, or public synchronous behavior.

The public synchronous interface remains compatible. That compatibility does
not permit a migrated internal path to re-enter the adapter recursively. Direct
evaluation and generator behavior must not regress; if preserving either
requires another reachable edge to migrate, the inventory and scope record must
expand together.

The concrete current-code mapping and suggested implementation order live in
[the implementation notes](../design/engine-activation-continuation-implementation-notes.md).
Those notes may change with the source tree without changing this contract's
ownership and completion invariants.

## Scope boundary

| In scope (#630) | Retained by later work |
|---|---|
| One activation dispatcher behind a private continuation seam | Complete may-call-user-code migration (#608) |
| Ordinary and mutual non-tail calls | Proper Tail Calls and activation replacement (#611) |
| Return and binary-result continuation required by #616 | Constructors and conversion hooks not reached by the slice |
| Own/prototype getter result continuation | Generator and async suspension integration |
| Proxy `get` trap result and invariant continuation | Other Proxy traps and built-in callback loops |
| Handler, finalizer, and completion continuation | Full bytecode call convention (#631) |
| Realm, parameter-default, normal, and abrupt cleanup | Direct evaluation paths not reached by the slice |
| Activation-depth observation seam for #617 | Final target/profile CI gate (#619) |

The first unresolved edge decides the boundary. If a required #616 path cannot
preserve existing semantics without another migration, that dependency joins
#630; it is not hidden behind an unsupported recursive escape.

## Rejected alternatives

### Statement position plus result slot

This cannot represent work nested inside expressions or runtime operations. It
either loses the pending consumer or replays observable effects.

### Host-language closures as continuations

These retain the host stack behavior the design must remove and make ownership
and cleanup difficult to inspect deterministically.

### Partial trampoline with recursive fallback

A fallback on any edge reachable from the managed cycle preserves stack growth
and makes the stack-safety claim input-dependent.

### Bytecode-only replacement

Bytecode may provide a natural instruction pointer and operand stack, but making
it mandatory would change current interpreter behavior and adoption scope. The
tree walker needs its own valid continuation model.

### Proper Tail Calls as the first fix

The #616 programs consume callee results after the call and are not tail calls.
Tail-call replacement cannot repair them.

## Interaction with adjacent work

#617 owns the logical activation-depth policy and the JavaScript error exposed
when its budget rejects entry. #630 owns the sole observation seam and balanced
entry/release lifecycle. A rejected activation is never partially acquired.

Future #611 work may replace the current activation for a valid tail call
without increasing retained depth. #630 reserves room for that transition but
does not implement it.

The bytecode VM may later adapt its instruction pointer and operand stack to the
same root-request/final-completion seam without sharing the tree-walker
continuation representation. #631 owns that adapter.

## Acceptance criteria

- The four exact #616 programs are committed as failing tests before
  implementation and pass afterward with exact results and side-effect order.
- No host evaluator frame is retained across a managed guest activation.
- Return, binary, getter, and Proxy results resume through explicit, one-time
  semantic continuations.
- Proxy result invariants execute after the trap result and preserve existing
  error behavior.
- Handler and finalizer routing preserves catchability, return, break, continue,
  completion replacement, and source order.
- Cleanup remains owned during handler and finalizer processing and is released
  exactly once when the activation ends.
- Focused lifecycle tests cover ordinary completion, return, break and continue
  through a finalizer, guest throw, runtime failure, and rejected entry. Each
  test observes balanced acquisition and exactly one release for every acquired
  activation.
- The reachable-call inventory names every migrated and residual path; no
  migrated path silently falls back to recursive guest entry.
- Activation-depth observation occurs only at the dispatcher-owned lifecycle
  seam.
- Existing evaluation order, source identity, realm behavior, JavaScript errors,
  and bytecode-equivalence behavior do not regress.

## Related issues

| Issue | Role |
|---|---|
| #615 | Milestone 10 tracking |
| #616 | Minimized pre-fix reproducer matrix (closed) |
| #618 | Original contract exploration (closed as superseded, not accepted) |
| #630 | Continuation-aware activation implementation |
| #614 | Post-parse iterative traversal (closed) |
| #617 | Logical activation-depth policy |
| #619 | Permanent cross-target gate |
| #608 | Residual complete may-call-user-code migration |
| #631 | Future bytecode call convention |
