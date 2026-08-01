# Receiver-preserving ordinary method calls: first #608 slice research

Date: 2026-08-01

## Recommendation and boundary

For [#705](https://github.com/dowdiness/js_engine/issues/705), graduate one
closed family from [#608](https://github.com/dowdiness/js_engine/issues/608): a
tree-walker `Member` call whose receiver is an ordinary `Object`, whose named
property is an **own data property**, and whose stored value is the admitted
interpreted function.  The continuation owns the already-resolved receiver,
callee, and completed non-spread argument list until the call completion is
consumed.  This is a proposal, not a claim that the family is currently
admitted.

This is the smallest receiver-bearing call family with a public semantic
contract.  Unlike a direct call, it must retain the Reference-derived receiver;
unlike accessor/prototype/Proxy calls, an own data-property lookup has no
additional guest-call edge.  The current #608 inventory explicitly leaves
general `UserFunc`/method calls, arbitrary arguments, property paths, and
call/apply forwarding residual; this proposal narrows only one intersection of
those residuals.

### Exact first admission

- Non-optional, non-computed `Member` call only (`receiver.name(args...)`).
- Receiver is a non-callable ordinary `Object`; `name` resolves to an own data
  property, with no descriptor getter/setter and no prototype lookup.
- Property value is a sealed interpreted function with the slice's separately
  admitted simple parameter/body recipe.  The receiver is passed unchanged as
  its call `this` argument.
- Arguments are a finite, non-spread list; their existing evaluator runs once,
  from left to right, before callability validation/call.  A later expansion
  may admit a tightly specified argument recipe, but must not replay one.
- The dispatcher carries normal and abrupt completion back to the exact waiting
  consumer, then restores lifecycle state once.  No migrated edge may re-enter
  legacy `call_value` while waiting.

The existing exact direct-call admission is intentionally not evidence for this
family: it requires `this_value is Undefined` and a single numeric argument in
[`activation_dispatch_direct_call_admission.mbt`](../../interpreter/runtime/activation_dispatch_direct_call_admission.mbt).
The normal method path in [`call.mbt`](../../interpreter/runtime/call.mbt)
currently evaluates the base, reads the property, evaluates arguments, then
calls with `obj`; its generic `call_value` path is still the legacy path unless
the unrelated exact direct-numeric preflight accepts it.  The own-data fast
path in [`property.mbt`](../../interpreter/runtime/property.mbt) returns the
stored value directly; the slower property paths can invoke getters and are
not part of this slice.

## Normative semantics

The current ECMA-262 algorithms, rather than nearby interpreter code, fix the
observable contract:

1. Call-expression evaluation evaluates the member expression to a Reference,
   obtains its value, and invokes `EvaluateCall` with both the value and the
   Reference ([CallExpression evaluation](https://tc39.es/ecma262/multipage/ecmascript-language-expressions.html#sec-runtime-semantics-evaluation)).
2. `EvaluateCall` derives `thisValue` from a property Reference with
   `GetThisValue`, evaluates `ArgumentListEvaluation`, then performs the
   callable check and `Call` ([§13.3.6.2](https://tc39.es/ecma262/multipage/ecmascript-language-expressions.html#sec-evaluatecall)).
   `GetThisValue` returns the reference base for an ordinary property
   reference, so `obj.m()` supplies exactly `obj`, not the fetched function,
   as `this` ([§6.2.5.7](https://tc39.es/ecma262/multipage/ecmascript-data-types-and-values.html#sec-getthisvalue)).
3. Property-reference `GetValue` calls `[[Get]]` with that same receiver
   ([§6.2.5.5](https://tc39.es/ecma262/multipage/ecmascript-data-types-and-values.html#sec-getvalue)).
   `OrdinaryGet` returns an own data descriptor's stored value directly; only
   an accessor descriptor calls its getter ([§10.1.8.1](https://tc39.es/ecma262/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ordinaryget)).
4. `ArgumentListEvaluation` evaluates the preceding list before the next
   argument, fixing left-to-right order ([§13.3.8.1](https://tc39.es/ecma262/multipage/ecmascript-language-expressions.html#sec-runtime-semantics-argumentlistevaluation)).
   Therefore callee/reference resolution precedes all arguments, and a
   non-callable member still evaluates its arguments before the required
   TypeError.
5. `Call` delegates to `func.[[Call]]` and propagates its abrupt completion
   ([§7.3.13](https://tc39.es/ecma262/multipage/abstract-operations.html#sec-call)).
   An ECMAScript function call establishes the callee execution context,
   binds `this`, evaluates its body as a completion, restores the caller, and
   turns a return completion into the call result ([§10.2.1](https://tc39.es/ecma262/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ecmascript-function-objects-call-thisargument-argumentslist)).
   The specification's `?` shorthand immediately propagates an abrupt
   completion, so later argument/call/consumer work cannot run
   ([§5.2.4.3](https://tc39.es/ecma262/multipage/notational-conventions.html#sec-algorithm-conventions)).

| Observable semantics that must remain true | Private mechanics that may change |
|---|---|
| Evaluate base/property and preserve the property Reference before any argument. | Whether the dispatcher stores a `MemberCall` continuation, a sealed request, or another private frame. |
| Use the identical receiver object as call `this`; do not substitute callee, property holder, or a copy. | Frame layout, reducer event names, and the representation of the saved receiver/callee/arguments. |
| Evaluate every argument once, left-to-right; do it even when the fetched value is non-callable, then throw TypeError. | Whether arguments are accumulated in a private array or slots, provided ownership is private and replay is impossible. |
| Return/throw completion reaches the original caller once; cleanup is LIFO and exactly once. | Suspension points, iterative scheduling, and an opaque cleanup capability. |
| No getter, prototype step, Proxy trap, coercion, or iterator effect is silently introduced by this own-data slice. | Preflight/provenance sealing performed before JavaScript-visible managed execution. |

Suspension is therefore an implementation technique, not a semantic event.  It
must preserve the pending consumer and object identity; re-evaluating the
member expression or any argument after a callee resumes would repeat visible
effects.  This follows both from the sequential algorithms above and from the
accepted local continuation contract, which forbids recursive fallback after
managed execution starts ([contract](../decisions/engine-activation-continuation-contract.md),
[closure inventory](engine-activation-continuation-closure-inventory.md)).

## Explicit exclusions

Do not include in the first child issue:

- computed, private, `super`, optional-chain, direct-`eval`, `call`, `apply`,
  bound, native/interpreter-backed, callable-Proxy, constructor, or arrow
  call forms;
- accessors, setters, inherited/deeper/exotic/Proxy property paths, handler
  accessors, and all Proxy traps;
- spread, iterator/destructuring, default-parameter, coercing, or
  callback-capable argument preparation;
- general function bodies or arbitrary expression/statement consumers,
  protected control, conversion, iteration, async/jobs/timers/modules; and
- bytecode activation suspension/resumption, which the local inventory assigns
  to #631 rather than #608.

These exclusions match the residual inventory in the local
[closure inventory](engine-activation-continuation-closure-inventory.md#explicit-residuals-transferred-to-608)
and #608's operation-family rule.  They prevent the attractive but invalid
shortcut of treating a host-implemented property or callable as a synchronous
leaf without a no-guest-entry proof.

## RED-test implications

The child must begin with a public end-to-end RED test, then add separate
admission/provenance and continuation/cleanup evidence.  Its public fixture
should make all four facts observable:

- a method returns/records `this === obj`, establishing receiver identity;
- a side-effecting base expression, then side-effecting arguments, then method
  body record `base, arg1, arg2, body` in that order;
- `obj.notCallable(arg())` records `arg` before TypeError, proving the
  `EvaluateCall` check position; and
- a throwing argument prevents method-body entry, while a method throw reaches
  the surrounding `catch` once and skips the normal post-call consumer.

For stack depth, use the same closed member-call recipe recursively and assert
the guest result and original receiver identity at a depth above the affected
host-call threshold.  Keep the order/identity fixture shallow and independent:
it distinguishes a stack-safe implementation that preserves semantics from one
that merely avoids overflow.  Any test requiring a getter, a computed key,
spread, or a second callable family is evidence for a later #608 child, not a
reason to widen this RED.
