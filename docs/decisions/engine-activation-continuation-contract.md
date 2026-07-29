# Stack-safe engine activation and continuation contract

Date: 2026-07-29. Revised 2026-07-29 after validating the suspension seam
against the minimized #616 programs and the current evaluator.

## Status

Accepted. Acceptance of this contract is recorded by the merge that introduces
this document. The original #618 exploration is superseded: its
statement-PC-only draft could push a callee frame, but it could not preserve the
caller computation that consumes the callee's value.

This contract remains narrower than Proper Tail Calls (#607) and the complete
may-call-user-code migration retained by #608. It does not classify tail
positions, perform `PrepareForTailCall`, make bytecode mandatory, or claim that
unmigrated runtime-operation paths are stack-safe.

## Context

The current tree-walking interpreter evaluates calls synchronously:

```text
exec_stmt(ReturnStmt)
  -> eval_expr(Binary)
  -> eval_expr(Call or Member)
  -> call_value
  -> call_value_impl
  -> exec_stmts
  -> exec_stmt(...)
```

The #616 self- and mutual-recursion programs call from the right operand of a
binary expression. The getter and Proxy programs add two more synchronous
result consumers:

```text
get_property_of_object -> call_value(getter) -> Value
proxy_get_key -> call_value(trap) -> invariant checks -> Value
```

Saving only the statement index cannot resume any of these computations. If the
dispatcher advances the index, it loses the pending binary operation and
`ReturnSignal`. If it replays the statement, it repeats observable effects such
as `n = n - 1`. A Proxy `get` result must also pass the invariant checks that
follow the trap call. Therefore a stack-safe design must preserve the exact
value-consuming continuation, not merely the enclosing statement.

Post-parse recursion is independent and landed in #614. Intra-expression
recursion is not the claim addressed here: the problem is guest-code activation
re-entry through synchronous evaluator and runtime-operation frames.

## Decision: activation dispatcher with explicit continuations

Introduce one private execution module whose interface is a root execution
request (program or call) and a final completion. The module owns an explicit
stack of guest activations and value-consuming continuations. Existing public
synchronous entry points remain adapters at this seam; internal migrated paths
do not recursively invoke those adapters.

Conceptually, the deterministic core has this shape:

```text
ExecutionState + DispatchEvent -> (ExecutionState, DispatchDecision)
```

The exact MoonBit type names are implementation details, but the model must
distinguish a complete guest completion from a plain value and represent at
least:

```moonbit
priv enum GuestCompletion {
  Normal(Value)
  Return(Value)
  Break(Value?, String?)
  Continue(Value?, String?)
  Throw(Value)
  RuntimeAbrupt(Error)
}

priv enum DispatchEvent {
  Start(ExecutionRequest)
  ValueReady(Value)
  CompletionReady(GuestCompletion)
  ActivationRejected(ExecutionControlFailure)
}

priv enum DispatchDecision {
  Evaluate(EvalWork)
  InvokeNative(NativeCall)
  EnterActivation(CallRequest)
  Resume(Continuation, GuestCompletion)
  ReleaseActivation(ActivationCleanup, GuestCompletion)
  Finish(GuestCompletion)
}
```

`RuntimeAbrupt` is conceptual: the implementation may use separate private
variants, but it must retain whether a failure is guest-catchable, an engine
control failure, or a non-catchable host/runtime failure. It must not translate
all failures into guest throws.

The core returns decisions and next state. It does not call the evaluator,
mutate lifecycle counters, throw JavaScript errors, or expose its internal
mutable work stack. Local mutation used only to construct the returned next
state is acceptable. The imperative dispatch shell performs evaluator/runtime
adapter calls, activation observation, environment lifecycle mutation, and
error translation.

### Activation frames

An activation frame holds the state owned by one interpreted guest function:

```moonbit
priv struct ActivationFrame {
  body : Array[@ast.Stmt]
  statement_index : Int
  env : Environment
  ctx : ExecContext
  last_value : Value
  cleanup : ActivationCleanup
}
```

`ActivationCleanup` is required, not optional. It is an immutable snapshot or
opaque shell token that owns every dynamically scoped value currently restored
by host-stack callbacks, including:

- active value and active callee realm overrides;
- `in_nonarrow_param_default_eval` and
  `param_default_eval_var_conflicts`;
- whether #617 activation observation completed; and
- any additional per-call state found by the continuation-closure inventory.

Entry captures this cleanup state before installing overrides. Normal return,
guest throw, runtime abrupt completion, and activation rejection consume it at
most once. A frame must not contain a `Ref[Value]` whose writer is an abandoned
host stack frame. Results are routed by explicit continuations owned by the
dispatcher.

### Continuations

A continuation records what must happen after a suspended guest call produces a
value. The initial #630 implementation needs, at minimum, equivalent states for:

- completing a `ReturnStmt` with the resumed value;
- applying a binary operator after its right operand completes;
- returning an accessor getter result to property access;
- validating and returning a Proxy `get` trap result;
- routing a completed ordinary call to its enclosing expression; and
- entering a `catch` handler for a catchable guest completion;
- executing `finally` after normal, return, break, continue, throw, or runtime
  abrupt completion;
- applying the ECMAScript rule that an abrupt `finally` completion replaces the
  completion being carried into it; and
- propagating the resulting completion to the owning activation.

These are semantic states, not callbacks. They carry only the operands, source
location, environment, and runtime-operation data required to resume exactly
once. They must not capture a MoonBit continuation or depend on TCO.

The implementation may use one internal continuation enum or several private
deep modules. The external seam remains one root execution request to one final
completion; callers must not learn the internal frame taxonomy.

### Suspension rule

When a migrated evaluator or runtime-operation path would invoke interpreted
guest code, it returns a call request plus a continuation to the dispatcher. It
does not call synchronous `call_value` and wait on the host stack.

Native callables that complete without creating a guest activation may execute
through the shell and return `ValueReady`. If a native/runtime adapter can
invoke guest code, the continuation-closure inventory must classify it before
the adapter is used inside a managed activation.

There is no statement replay for ordinary calls. A continuation resumes after
the completed operation, so argument evaluation, assignments, getter effects,
and Proxy trap effects occur exactly once.

### Dispatch loop

The shell repeatedly executes decisions until the root completion is produced:

```text
state = start(root_execution_request)
event = next_event

while true:
  (state, decision) = reduce(state, event)
  match decision:
    Evaluate(work)       -> event = evaluator_adapter(work)
    InvokeNative(call)   -> event = native_adapter(call)
    EnterActivation(call) -> capture cleanup, observe activation, then enter
    Resume(k, completion) -> event = resume_adapter(k, completion)
    ReleaseActivation(cleanup, completion)
                          -> restore once, then event = CompletionReady(completion)
    Finish(completion)   -> return/raise through the synchronous root adapter
```

Only this loop enters and releases managed activations. A resumed continuation
and an activation cleanup token are each consumed at most once.

## Worked traces required by #630

### Ordinary non-tail call

For `return 1 + f(n - 1)`:

1. evaluate `1` and the callee/arguments in source order;
2. save `ApplyBinary(Add, left=1, loc)` and `CompleteReturn` continuations;
3. push the `f(n - 1)` activation;
4. on its value, apply the binary operation once; and
5. complete the caller with `ReturnSignal(result)`.

No suspended host evaluator frame may remain between steps 2 and 4.

### Getter re-entry

For `return 1 + o.x`:

1. save the binary and return continuations;
2. property lookup discovers the getter and saves a property-result
   continuation;
3. push the getter activation;
4. feed its value through property-result, binary, and return continuations.

The mutation preceding the recursive `o.x` access runs once per activation.

### Proxy `get` re-entry

For `return 1 + p.x`:

1. save the binary and return continuations;
2. `proxy_get_key` saves the target, property key, receiver, and invariant-check
   continuation before requesting the trap call;
3. push the trap activation;
4. run the existing invariant checks exactly once on the trap result; and
5. resume the enclosing property, binary, and return continuations.

### Abrupt completion

A guest throw or runtime error becomes an abrupt completion. Within an
activation, the dispatcher searches explicit handler continuations rather than
MoonBit host frames:

1. a catchable guest completion enters the nearest applicable `catch` with the
   existing catch environment and binding rules;
2. normal, return, break, continue, throw, and runtime abrupt completion all
   enter a pending `finally`;
3. normal completion of `finally` resumes the previously saved completion;
4. abrupt completion of `finally` replaces the previously saved completion; and
5. only an unhandled completion releases the activation and continues unwinding.

The dispatcher releases each owned activation exactly once and must not rely on
recursive MoonBit `raise` hops between guest activations. The synchronous root
adapter translates only the final uncaught completion to the existing
`raise Error` interface.

Required worked tests cover a call that returns from `try`, a throw crossing
multiple activations into `catch`, `finally` after normal/return/break/continue/
throw, and an abrupt `finally` overriding the saved completion.

### Activation lifecycle cleanup

For slow-path cross-realm calls and parameter-default state:

1. the shell captures all previous dynamically scoped interpreter state;
2. it installs the callee state and records the cleanup token on the activation;
3. nested activations capture their own token without overwriting the caller's;
4. every normal or abrupt exit restores its token in LIFO order; and
5. a #617 rejection before entry restores any installed state without releasing
   an activation that was never pushed.

Focused tests cover normal return, parameter/default-binding failure, guest
throw, getter/Proxy re-entry, and a cross-realm callee on both normal and abrupt
exit.

## Continuation-closure inventory

Before implementation, start from every `call_value` reference reachable from
the four #616 programs. For each caller, record:

1. the possible callee kinds (`Object` interpreted/native callable, `Proxy`, or
   non-callable error);
2. the value or abrupt completion consumed after the call;
3. effects that must not be replayed;
4. whether the caller is migrated in #630, proven outside the managed cycle, or
   retained as a named #608 residual; and
5. the focused test that covers the classification.

The inventory must include the current ordinary call, `ReturnStmt`, binary
expression, own/prototype getter, Proxy `get` invariant paths,
`exec_try_catch`, active-value/callee-realm scopes, and parameter-default state
save/restore. Finding an additional may-call-user-code edge or host-stack-owned
cleanup on one of those paths expands the migrated closure; it is not grounds
for a recursive fallback.

Unmigrated constructors, conversions, generators, async jobs, iterators,
built-in callbacks, setters, and other Proxy traps remain #608 work unless the
inventory proves they are reached by the #630 vertical slice. The milestone and
documentation must not describe those residual paths as stack-safe.

## Migration and compatibility

Implementation proceeds in testable vertical slices:

1. add the four exact #616 end-to-end tests and demonstrate that they fail on
   the pre-implementation branch;
2. add pure transition tests for entry, resume, handler selection, finalizer
   precedence, release, and exactly-once continuation/cleanup consumption;
3. migrate activation lifecycle state currently owned by host-stack callbacks;
4. migrate ordinary and mutual non-tail calls, including binary/return resume;
5. migrate `try`/`catch`/`finally` handler and finalizer continuations;
6. migrate getter result resume;
7. migrate Proxy `get` result resume and invariant checks;
8. connect #617 activation observation at the sole entry/release owner; and
9. run existing interpreter, bytecode-equivalence, error-ordering, and focused
   cross-target tests after every slice.

The public `Interpreter::run(...) -> Value raise Error` and
`Interpreter::call_value(...) -> Value raise Error` adapters, `ExecContext`,
`Signal`, and `Environment` remain compatible. Compatibility at either public
synchronous adapter does not permit migrated internal paths to re-enter those
adapters recursively.

## Scope boundary

| In scope (#630) | Retained by later work |
|---|---|
| One activation dispatcher and private continuation seam | Complete may-call-user-code migration (#608) |
| Ordinary and mutual non-tail calls | Proper Tail Calls and frame replacement (#611) |
| Return and binary-result continuation required by #616 | Constructors and conversion hooks not reached by the slice |
| Own/prototype getter result continuation | Generator/async suspension integration |
| Proxy `get` trap result and invariant continuation | Other Proxy traps and built-in callback loops |
| `try`/`catch`/`finally` handler and completion continuation | Full bytecode call convention (#631) |
| Realm, parameter-default, normal, and abrupt activation cleanup | Direct `eval` continuation integration not reached by the slice |
| Activation-depth observation seam for #617 | Final target/profile CI gate (#619) |

Direct `eval` and generator replay must not regress. If a required #616 or
compatibility path cannot preserve them without migrating additional
continuations, stop and expand the inventory/design before coding around the
problem.

## Rejected alternatives

### Statement-PC-only frame

Rejected because it cannot represent the pending binary, return, getter, or
Proxy invariant work. Advancing loses work; replay duplicates effects.

### `Ref[Value]` result slot owned by a suspended caller

Rejected because a slot does not encode what consumes the value and assumes the
host caller remains available to continue execution.

### Nested synchronous dispatch loops

Rejected because each guest call would retain the outer evaluator host frames,
recreating proportional host-stack growth.

### CPS callbacks

Rejected because MoonBit provides no TCO guarantee and callback nesting would
retain the same host-recursive dependency.

### Mandatory bytecode execution

Rejected because the bytecode VM does not yet cover the interpreter's syntax
and semantic surface. #630 must not create a second semantic runtime.

### Statement replay or target-specific stack flags

Rejected because replay duplicates observable effects and host flags preserve
environment-dependent behavior rather than defining an engine-owned limit.

## Interaction with #617

The dispatcher emits one logical activation-entry decision immediately before a
guest frame is pushed and one release on every normal or abrupt exit. #617 owns
the policy and JavaScript `RangeError`; #630 owns the single observation seam.
An activation rejected by #617 is never partially initialized or pushed.

The future #611 tail transition replaces the top activation through a reserved
core decision and does not increase retained activation depth. #630 does not
implement that decision.

## Interaction with bytecode

The bytecode VM may later adapt its existing instruction pointer and operand
stack to the same root-execution-request/final-completion seam. It need not
reuse the tree-walker continuation representation. #631 owns that adapter; #630
neither makes bytecode mandatory nor changes bytecode equivalence ownership.

## Acceptance criteria

- The four exact #616 programs are committed as red tests before implementation
  and pass afterward with exact results and side-effect order.
- No host evaluator frame is retained across a managed guest activation.
- Return, binary, getter, and Proxy `get` results resume through explicit,
  exactly-once continuations.
- Proxy `get` invariant checks execute after the trap result and preserve current
  errors.
- `try`/`catch`/`finally` uses explicit handler/finalizer continuations and
  preserves catchability, return/break/continue propagation, completion
  replacement, and source order.
- Active realm/value overrides and parameter-default state are captured and
  restored exactly once on normal, abrupt, and rejected activation paths.
- Normal return, guest throw, and runtime abrupt completion release every owned
  activation exactly once.
- The continuation-closure inventory names every migrated and residual path; no
  migrated path silently falls back to recursive `call_value`.
- #617 observes activation entry/release only at the dispatcher owner.
- Existing evaluation order, source identity, realm behavior, `Signal` behavior,
  JavaScript errors, and bytecode-equivalence tests do not regress.
- `moon check`, `moon test`, `moon prove` where applicable, `moon info`, and
  `moon fmt` pass with intentional `.mbti` diffs reviewed.

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
