# Activation continuation implementation notes

Date: 2026-07-29. Revised 2026-08-06 after reconciling the notes with the
result-fed ordinary direct-return plan in #817, following the ordered-argument
plan in #815 under #800.

This note maps the accepted
[activation and continuation contract](../decisions/engine-activation-continuation-contract.md)
to the tree-walking interpreter. The contract defines the general reducer and
ownership model. Production execution currently enters that model only through
the exact recipes recorded in the
[continuation-closure inventory](engine-activation-continuation-closure-inventory.md).
Code remains authoritative when names or call paths change.

Design acceptance is not a claim that the general may-call-user-code migration
is complete. A private reducer may represent more completion and continuation
states than production admission can currently reach. Core representation,
white-box coverage, and production stack-safety coverage must therefore be
reported separately.

## Current execution structure

Each admitted production slice follows the same boundary:

1. **Exact admission** classifies a callback-free source recipe and checks the
   initial runtime conditions before managed effects begin.
2. **Runtime sealing** captures the identities and provenance needed by that
   recipe. Later managed entries revalidate the sealed envelope rather than
   trusting mutable bindings or object graphs.
3. **Iterative dispatch** stores activations, value consumers, handlers,
   finalizers, property work, and cleanup as engine-owned data. A deterministic
   reducer selects the next decision; a thin shell performs evaluator and
   runtime effects and returns their results to the reducer.
4. **Completion routing** carries normal, return, break, continue, guest throw,
   and runtime-abrupt outcomes until a continuation consumes them or the root
   adapter translates the final outcome.
5. **Public adaptation** preserves the synchronous facade. An exact root enters
   the dispatcher; an ineligible root remains on the legacy path from its start.

Once managed execution begins, an unsupported edge is an internal invariant
failure. It is never permission to fall back to a recursive public adapter or
to replay an enclosing statement.

## Current exact production closure

The production claim is limited to these admitted recipes:

- exact numeric self and mutual recursion entered through a program root or an
  exact direct-call root, including the required return and binary consumers;
- the exact #809 non-strict named ordinary `UserFunc` program whose closed
  literal base return or throw is followed by `return f(n - 1)`, using the
  common call request, function-exit cleanup, and explicit return continuation;
- the exact #811 extension whose base activation returns one separately sealed
  zero-argument ordinary leaf call with a closed literal return or throw;
- the exact #813 extension whose sealed leaf accepts one closed literal
  argument and returns or throws its own prepared simple-parameter binding;
- the exact #815 extension whose sealed leaf accepts two ordered closed
  arguments and returns or throws the selected prepared parameter binding;
  scalar optional argument fields are replaced by owned parameter and argument
  plans, while production admission remains capped at this exact arity;
- the exact #817 extension whose recursive return is `id(f(n - 1))`: the inner
  recursive result is carried by a private reducer continuation into one
  separately sealed ordinary leaf call. The owned plan preserves the inner and
  outer source locations, copies the call template defensively, validates the
  actual argument snapshot with JavaScript value/identity semantics, and routes
  abrupt results around the helper; the depth-256 path observes 257 `f`
  activations plus 256 `id` activations;
- the exact #819 extension whose program root is either the existing direct
  entry call or a sealed zero-parameter ordinary `entry()` wrapper around
  `f(256)`. The wrapper owns its declaration index, call locations, UserFunc
  identity, global mirror, closure, body, and realm provenance; its inner call
  uses the existing `DispatchCompleteReturn` continuation. The wrapped
  result-fed path observes 1 wrapper, 257 `f`, and 256 `id` activations (514
  total) with a peak managed depth of 258;
- the exact #790 retained numeric second-argument comma workload entered
  through the tree-walker program root, including its iterative closed-argument
  observations and retained-parameter return;
- exact protected numeric recipes that exercise catch selection, saved
  completion resumption, normal finalization, abrupt replacement, guest throw,
  and runtime-abrupt routing;
- exact ordinary-object own getters and direct one-hop ordinary prototype
  getters, retaining the original receiver and enclosing property consumer;
- the exact Proxy `get` recursion recipe with an own data trap on the admitted
  handler, a callback-free ordinary target, captured trap inputs, and post-trap
  invariant work;
- exact labelled-break and bounded-continue program roots routed through a
  closed finalizer; and
- realm/value, source, simple-parameter, property-scope, and observation cleanup
  required by those recipes.

Invariant parity tests may use target descriptors broader than the exact Proxy
root admits. Those tests prove the shared post-trap continuation and error
ordering; they do not widen production admission.

Similarly, the reducer can model parameter-default resumption, but #630
production recipes only own and restore the simple-parameter lifecycle state.
Evaluation of a default expression that may enter guest code remains outside
the admitted closure.

## Cleanup and observation ownership

An admitted activation captures its caller-visible dynamic state before
installing callee state. Nested activations own distinct cleanup capabilities.
Property access owns a separate scope capability when its restoration must
survive a suspended getter or Proxy trap.

Completion routing retains activation cleanup while a handler or finalizer can
still run. On exit, the shell restores parameter, source, realm, and property
state before releasing the activation observation. Emergency unwinding follows
the same LIFO order. A rejected entry restores partial setup but has no release
event because no activation was acquired.

The observation port is policy-free and covers guest activations admitted by
the exact production recipes, including #809, #811, #813, #815, and #817. It
does not make legacy call paths observable or stack-safe. #617 owns the logical-depth policy,
configuration validation, and engine-created error that will consume this
seam.

## Residual migration retained by #608

The following paths remain outside #630 even when the reducer has a state that
could eventually represent their continuation:

- general interpreted functions outside the exact #809/#811/#813/#815/#817 direct-return recipes,
  arrow and extended callable forms, bound calls, and call/apply forwarding;
- general statements, expressions, loops, labels, catch/finally shapes, and
  parameter-default or destructuring evaluation;
- accessors on other object families, deeper or exotic prototype paths,
  handler accessors, nested Proxy handlers, and setters;
- callable Proxy application, callback-capable Proxy targets, and Proxy traps
  other than the exact admitted `get` recipe;
- constructors, conversion hooks, direct or indirect evaluation, generators,
  async execution, iteration, promises and jobs, timers, modules, and built-in
  callback loops; and
- native/runtime adapters whose implementation can re-enter guest code.

These are named #608 residuals, not recursive fallbacks inside the #630 managed
cycle. Adding one requires a focused failing test, a source-backed consumer and
effect inventory, an exact admission boundary, and a continuation/runtime
adapter before the production claim expands.

## Compatibility and adjacent work

The public synchronous run and call entry points, execution context, completion
signals, environments, source attribution, realm behavior, and JavaScript error
behavior remain compatible. Compatibility does not imply stack safety for an
ineligible legacy path.

#619 owns the permanent debug/release target matrix after #630 and #617 are
complete. The cross-target tests run while landing #630 are implementation
evidence, not a substitute for that final gate. #631 owns any bytecode-VM
adapter to the same root-request/final-completion seam; it need not share the
tree-walker continuation representation. Proper Tail Calls and activation
replacement remain separate downstream work.

## Verification and maintenance

The exact #616 programs, the retained-argument slice landed in #790, and the
exact #809/#811/#813/#815/#817 ordinary direct-return programs supply
end-to-end red-to-green evidence.
Reducer tests separately cover deterministic transition, pathological
continuation depth, handler/finalizer precedence, and one-time ownership. Shell
tests cover effect order, runtime provenance, cleanup restoration, and adapter
connection.

When production admission changes, update the closure inventory in the same
slice. Verify the exact public behavior first, then transition and shell
behavior, cleanup and observation order, legacy lookalike compatibility,
cross-target execution, public interfaces, formatting, and architecture
boundaries. Do not infer a generalized stack-safety claim from a passing core
test or from an unadmitted continuation variant.
