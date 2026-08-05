# Activation-continuation closure inventory

Date: 2026-07-29. Reconciled against the production admission boundary on
2026-08-05 after the first cross-callee ordinary direct-return slice in #811
under #800.

This is the source-backed implementation inventory required by #630. It maps
the accepted
[activation-continuation contract](../decisions/engine-activation-continuation-contract.md)
to the current tree walker. It is an implementation record, not an architecture
contract; source code remains authoritative when a symbol or path changes.

## Claim boundary and method

The inventory starts from the four execution-phase programs characterized by
#616 and follows every value consumer and guest-call edge that those concrete
programs reach. The survey used `moon ide outline`, `moon ide peek-def`, and
`moon ide find-references` for semantic discovery, plus a complete textual
audit of `call_value` references under `interpreter/`.

The inventory uses four labels rather than treating reducer support as
production migration. The first is an evidence qualifier; the remaining three
are production dispositions. A core-representable edge remains a #608 residual
until exact production admission is added:

- **core-representable only**: the deterministic reducer has state for the
  continuation or completion, but no production admission, imperative-shell
  implementation, or public adapter proves that a real program uses it;
- **production-admitted exact slice**: callback-free classification, runtime
  provenance sealing, shell execution, and a public root adapter all agree on
  one closed input family;
- **synchronous proven leaf**: the exact observed runtime value cannot enter
  interpreted guest code and may complete in the imperative shell; or
- **#608 residual**: the broader may-call-user-code path remains outside the
  Milestone 10 stack-safety claim.

Reducer transitions and white-box fixtures are not production coverage by
themselves. A path is production-admitted only when it is selected before
JavaScript-visible effects, sealed against runtime identity and shape, executed
without recursive fallback, and reachable through `Interpreter::run` or the
exact direct `Interpreter::call_value` adapter.

The authoritative root ordering and legacy disposition live in
[`activation_dispatch_root_admission.mbt`](../../interpreter/runtime/activation_dispatch_root_admission.mbt).
The exact recipe boundaries remain the classifiers in
[`activation_dispatch_admission.mbt`](../../interpreter/runtime/activation_dispatch_admission.mbt),
[`activation_dispatch_direct_call_admission.mbt`](../../interpreter/runtime/activation_dispatch_direct_call_admission.mbt),
[`activation_dispatch_direct_return_admission.mbt`](../../interpreter/runtime/activation_dispatch_direct_return_admission.mbt),
[`activation_dispatch_getter_admission.mbt`](../../interpreter/runtime/activation_dispatch_getter_admission.mbt),
[`activation_dispatch_proxy_admission.mbt`](../../interpreter/runtime/activation_dispatch_proxy_admission.mbt),
and
[`activation_dispatch_control_admission.mbt`](../../interpreter/runtime/activation_dispatch_control_admission.mbt),
together with their trust modules, the production shell, and the public
selection in [`interpreter.mbt`](../../interpreter/runtime/interpreter.mbt) and
[`call.mbt`](../../interpreter/runtime/call.mbt).

### Managed-cycle admission invariant

A named residual is not a permitted fallback after managed execution starts.
Before any JavaScript-visible effect, an exact eligibility check must prove that
the root request and every activation admitted to the managed cycle use only
sealed continuations and synchronous proven leaves. An ineligible root stays on
the existing synchronous path from its beginning and is outside the #630
stack-safety claim; execution never switches to that path after managed effects
have started.

The proof may use syntax shape, callable family, and already-established
runtime types, but it may not speculatively execute guest code. Encountering an
unsealed edge after admission is an implementation invariant failure that
blocks integration, not a new JavaScript-visible error or a basis for recursive
`call_value`.

## Concrete path and runtime-type proof

| Reproducer | Interpreted activation edge | Values consumed after the edge | Other reachable call-capable operations | Runtime-type proof for this slice |
|---|---|---|---|---|
| Self recursion | `eval_call` invokes an `Object(UserFunc)` for `f` | The recursive result is the right operand of numeric `+`, then the value of `ReturnStmt` | None | The callee is the hoisted declaration, both operands are `Number`, and the argument expression is numeric `n - 1` |
| Direct-return self recursion | The root and recursive `DispatchCallRequest` values enter the sealed ordinary `Object(UserFunc)` for `f` | The recursive result crosses function-exit cleanup and resumes the saved return consumer exactly once | None | The non-strict named callee is the hoisted declaration; `this` is `Undefined`; the sole argument is a finite integer `Number`; the base return or throw is a closed literal; and the recursive expression is exactly `f(n - 1)` |
| Direct-return leaf call | At the base activation, the saved return consumer enters one separately sealed zero-argument ordinary function | Its closed literal return resumes the entry function's return consumer once; its throw or runtime abrupt bypasses that consumer | None | Both named callees are canonical global declarations with sealed identity, closure, body, source, and realm provenance; the leaf body is exactly one closed literal return or throw |
| Mutual recursion | `eval_call` alternates `Object(UserFunc)` values for `f` and `g` | The recursive result is the right operand of numeric `+`, then the value of `ReturnStmt` | None | Both callees are hoisted declarations, both operands are `Number`, and the argument expression is numeric `n - 1` |
| Getter re-entry | `get_property_of_object` invokes the own getter stored as `Object(UserFunc)` | The getter result completes `o.x`, then numeric `+`, then `ReturnStmt` | The property slow path temporarily clears the caller's active callee realm | `o` is an ordinary `Object`, `x` is an own accessor, the receiver is `o`, and all binary operands are `Number` |
| Proxy `get` re-entry | `proxy_get_key` invokes the handler's `get` trap stored as `Object(UserFunc)` | The trap result first passes ordinary-target invariant checks, then completes `p.x`, numeric `+`, and `ReturnStmt` | Native `Proxy` construction; handler `get` lookup; target own-property invariant lookup | Construction is a native no-callback leaf; the handler has an own data property; the key is `String_("x")`; the target is an ordinary empty `Object` |

The exact sources were committed before implementation as `1f72bdc` on
`codex/issue-630-red-evidence`. Running
`moon test --target js interpreter/stack_safety_test.mbt` at that commit
reported 20 tests, 16 passed and exactly these four failed with the host
`RangeError: Maximum call stack size exceeded`. The branch intentionally has no
PR while red. The tests ultimately live in `interpreter/stack_safety_test.mbt`
and must return the exact value `256`.

## Production-admitted exact slice

| Boundary | Production claim | What remains outside the claim |
|---|---|---|
| `Interpreter::run` | Literal-only leaf programs and the exact numeric, ordinary direct-return, getter, Proxy `get`, and protected-control classifiers enter `PrimitiveProgramDispatchShell` from the root | Every program rejected by those preflights starts on the legacy `exec_stmt` path |
| Direct `Interpreter::call_value` | `this` is `Undefined`, the sole argument is `Number(256)`, and the sealed callee is the exact self/mutual numeric `Object(UserFunc)` recipe | Every other direct call uses the legacy `call_value_impl` path |
| Managed guest activation | A sealed registry admits only the exact `Object(UserFunc)` identities created by the admitted numeric or direct-return declarations, ordinary getter, or Proxy handler method | General `UserFunc`, `ArrowFunc`, `UserFuncExt`, `ArrowFuncExt`, callable Proxy, and interpreter-backed native callables are not admitted |
| Call, return, and binary work | The exact numeric recipe retains the left `Number`, performs `+`, `-`, or `===` in the closed numeric set, delivers the callee result once, and routes the admitted return. The exact ordinary direct-return recipes route recursive and closed leaf calls through explicit return continuations | Arbitrary calls, arguments, operators, coercions, return expressions, and throw expressions outside those exact recipes are residuals |
| Protected numeric completion | The admitted root may evaluate or throw the exact `f(256)` call; catch/finally bodies are empty or one closed numeric/binding value or throw. A recursive function return may cross one closed finalizer | General statement bodies, catch bindings, handlers, and finalizers are not production-admitted merely because the reducer can represent their completions |
| Protected structural control | Exactly `label: try { break label; } finally { 1; } 9;` and `do try { continue; } finally { 2; } while (false); 8;` use the control lifecycle shell | Other labels, loops, conditions, catch clauses, finalizer bodies, and break/continue shapes remain on the legacy path |
| Ordinary getter | One ordinary non-callable `Object` owns the exact accessor, or another ordinary `Object` has that holder as its direct prototype. The getter is the sealed zero-argument `Object(UserFunc)` recipe | `Array`, `Map`, `Set`, `Promise`, deeper or exotic prototype chains, Proxy receivers, and other getter callable families are residuals |
| Proxy `get` | The canonical native Proxy constructor creates a non-callable Proxy with an extensible empty ordinary `Object` target and an ordinary handler whose sole `get` entry is an own data property containing the sealed `Object(UserFunc)` trap | Handler accessors/prototypes, nested handler Proxies, trap-less Proxy forwarding, other trap callable families, and non-empty or exotic targets are residuals |
| Activation cleanup | Exact admitted `UserFunc` activations own LIFO restoration of active realm prototypes, source/callee identity, and the simple-parameter gate. Return, guest throw, runtime abrupt completion, and admitted protected routing consume the activation cleanup once | Generic `call_value` and `construct_value` realm wrappers still own their cleanup on the host stack |
| Property cleanup | Exact getter and Proxy property operations own separate dispatcher-managed LIFO scopes, restored before their owning activation is released | General `with_active_property_access_value` remains the legacy host wrapper |
| #617 observation seam | Entry attempt, acceptance/rejection, and exactly one release are observed for exact admitted guest activations; cleanup restoration precedes release observation | Legacy activations do not pass through this seam yet; #617 may add policy but does not broaden admission |
| Synchronous leaves | Literal expression/throw statements in the closed leaf set and the canonical native Proxy-construction setup cannot enter guest code | A MoonBit/native callable is not a leaf merely because it is host-implemented; it needs an exact no-guest-entry proof |

## Core-representable only

[`activation_dispatch_core.mbt`](../../interpreter/runtime/activation_dispatch_core.mbt)
deliberately models more than the current production shell admits. Its state can
represent all completion categories, parameter-default progress, statement and
loop cursors, catch/finalizer routing, nested property scopes, Proxy trap result
work, and abrupt replacement. Those states establish the continuation contract
and make transition rules testable; they do not establish a production path.

In particular:

- parameter-default call/resume state has reducer coverage, while production
  still evaluates `UserFuncExt` and `ArrowFuncExt` defaults through the legacy
  evaluator;
- general label, loop, switch, try/catch/finally, and abrupt-replacement tests
  establish completion semantics, while production admits only the closed
  numeric recipes and the two exact protected-control roots above;
- nested Proxy-handler lookup and frozen-data/getter-less invariant fixtures
  establish ordering in the core or shared invariant helper, while production
  Proxy admission still requires an own-data handler and an empty ordinary
  target; and
- shallow bound/call/apply, accessor, or Proxy lookalike tests prove legacy
  compatibility and fallback selection, not managed stack-safe execution.

## Explicit residuals transferred to #608

The following paths exist in the shared runtime but are outside the exact
production admission above:

- root programs and direct calls outside the sealed recipes, including general
  `UserFunc`, `ArrowFunc`, `UserFuncExt`, and `ArrowFuncExt` activations;
- `BoundFunc`, `FuncCallMethod`, and `FuncApplyMethod` target forwarding;
  observable `apply` length/index reads are residual too, while a separately
  proven plain argument-list construction may remain a synchronous leaf;
- arbitrary call arguments, return/throw expressions, binary/coercing
  operators, statement lists, labels, loops, switches, and try/catch/finally
  bodies outside the exact recipes;
- default-expression evaluation, rest and destructuring parameters, and catch
  destructuring whose property or iterator operations may enter guest code;
- own accessors on `Array`, `Map`, `Set`, and `Promise`, plus deeper ordinary,
  exotic, or Proxy prototype chains and the general active-property realm
  wrapper;
- Proxy `get` through a handler accessor or prototype, a nested handler Proxy,
  trap-less nested forwarding, a non-`UserFunc` or callable-Proxy trap, or a
  non-empty/frozen/getter-less/exotic target;
- post-`get` invariant `[[GetOwnProperty]]` on a Proxy target, which may invoke
  the `getOwnPropertyDescriptor` trap, callable Proxy `apply`, and every Proxy
  trap other than the exact `get` slice;
- constructors other than the canonical no-callback Proxy setup leaf, including
  user constructors, Proxy `construct`, `super`, species, and reflective
  construction;
- setters, conversion hooks reached by `ToPrimitive`, `ToPropertyKey`,
  `ToNumber`, or string conversion, spread arguments, iterator acquisition,
  iterator step/value/close, and destructuring iteration;
- `InterpreterCallable`, `InterpreterCallableWithContext`, and
  `NonConstructableInterpreterCallable` branches whose native algorithm may
  invoke guest code, together with built-in callback loops in Array, TypedArray,
  Map, Set, JSON, Promise, and related libraries; and
- direct/indirect `eval`, generator and async resume, async jobs, promises and
  reaction jobs, microtasks, timers, and module execution.

Bytecode activation suspension/resumption remains owned by #631 rather than
#608. Native callable variants without a guest-entry capability may finish in
the imperative shell, but each exact callable needs a no-guest-entry proof
before it is classified as a synchronous leaf.

## Cleanup snapshot

For an exact admitted guest activation, reducer frames own the activation
environment, execution context, and pending semantic continuations. Separately,
one immutable snapshot or opaque shell cleanup token owns:

- the previous packed active realm-prototype overrides;
- the previous active source identity and the callee source identity needed for
  failure observation;
- the previous simple-parameter gate flag and conflict set;
- whether the #617 observation accepted entry.

Handler and finalizer routing within an admitted recipe does not consume this
token. Leaving the owning activation consumes it once. Rejected entry restores
state installed while preparing the attempt but never emits a release for an
activation that was not acquired. This snapshot does not imply that
parameter-default expressions themselves are production-dispatched.

An exact admitted getter or Proxy property operation owns a separate
dispatcher-managed LIFO scope token for its active-callee-realm clear. That
token survives the admitted handler lookup, a suspended getter or Proxy trap
activation, and post-trap invariant work. Normal or abrupt completion consumes
it once. Outstanding property scopes unwind in LIFO order before activation
cleanup and release observation. General property operations still use the
legacy `with_active_property_access_value` wrapper and remain #608 work.

## Focused test evidence

| Evidence class | What it proves | What it does not prove |
|---|---|---|
| Public production | The exact #616 depth-256 programs (including the #790 retained-argument comma workload), exact direct numeric `call_value`, exact #809/#811 ordinary direct-return recipes, admitted protected numeric completions, and the two exact protected-control roots pass through public adapters | General programs or callable families are stack-safe |
| Direct shell and lifecycle | Exact admission/sealing, activation identity, normal/return/guest-throw/runtime-abrupt cleanup, property-scope LIFO restoration, observation acceptance/rejection/release, and finalizer-before-release ordering | A shell state without public admission is production reachable |
| Core representability | Every completion category, parameter-default resume, general handler/finalizer precedence, loop/label routing, nested property cleanup, and Proxy invariant ordering reduce deterministically | The production shell implements or admits every represented state |
| Legacy compatibility | Shallow bound/call/apply, accessor/Proxy lookalikes, existing interpreter behavior, error ordering, borrowed realm, source identity, and bytecode equivalence do not regress | Those fallback paths use managed continuation execution |

## Stop conditions

Implementation stops and this inventory is revised if any edge admitted to the
managed cycle:

- reaches one of the named residuals with a may-call-user-code runtime type;
- needs statement replay, a host callback continuation, or a `Ref[Value]`
  result slot owned by an unwound host frame;
- recursively re-enters a public synchronous adapter from a migrated edge;
- releases cleanup before catch/finally routing finishes; or
- requires tree-walker semantics to be duplicated in the bytecode VM.
