# Activation continuation implementation notes

Date: 2026-07-29.

This note maps the accepted
[activation and continuation contract](../decisions/engine-activation-continuation-contract.md)
to the current tree-walking interpreter. It supplies concrete implementation
guidance for #630, while the linked decision holds the architecture contract.
Code remains authoritative when names or call paths change.

## Current synchronous paths

The return-and-binary reproducer in #616 currently retains a chain of MoonBit
frames while the callee runs:

```text
exec_stmt(ReturnStmt)
  -> eval_expr(Binary)
  -> eval_expr(Call or Member)
  -> call_value
  -> call_value_impl
  -> exec_stmts
  -> exec_stmt(...)
```

Accessor and Proxy paths retain different result consumers after invoking guest
code:

```text
get_property_of_object -> call_value(getter) -> Value
proxy_get_key -> call_value(trap) -> invariant checks -> Value
```

Advancing only the statement index loses the pending binary operation and
`ReturnSignal`. Replaying the statement repeats effects such as `n = n - 1`.
The Proxy path cannot return the trap result before its invariant checks have
run. These consumers therefore belong in the first continuation-closure
inventory.

## Candidate private representation

The names below make the required distinctions visible during implementation;
they are not prescribed by the architecture contract.

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

`RuntimeAbrupt` may map to one private variant or several. In either case, the
implementation must retain whether a failure is guest-catchable, an engine
control failure, or a non-catchable host/runtime failure.

A possible activation record starts with the state currently retained by the
recursive evaluator:

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

The record must not retain a `Ref[Value]` whose writer belongs to an abandoned
host frame. Returned values and completions instead travel through dispatcher-
owned continuation state.

## Cleanup inventory

The initial cleanup token must account for the state currently restored by
host-stack callbacks:

- active value and active callee realm overrides;
- `in_nonarrow_param_default_eval`;
- `param_default_eval_var_conflicts`;
- whether #617 activation observation completed; and
- any additional per-call state discovered while tracing the #616 paths.

Entry captures the prior state before installing overrides. Nested activations
own separate tokens. A rejected entry restores installed state without
releasing an activation that was never pushed.

Cleanup tests must count acquisition and release. A matching final environment
cannot detect a duplicate release that happened to restore the same values.
The tests cover ordinary completion, explicit return, break and continue
through `finally`, guest throw, runtime abrupt completion, and rejected entry.
Handler and finalizer cases must show that cleanup remains owned while the
activation is resumable and is consumed once when that activation ends.

## Continuation-closure inventory

Start from every `call_value` reference reachable from the four #616 programs.
For each caller, record:

1. the possible callee kinds (`Object` interpreted/native callable, `Proxy`, or
   non-callable error);
2. the value or abrupt completion consumed after the call;
3. effects that must not be replayed;
4. whether #630 migrates the caller, proves it outside the managed cycle, or
   retains it as a named #608 residual; and
5. the focused test that covers the classification.

The first pass includes ordinary calls, `ReturnStmt`, binary expressions,
own/prototype getters, Proxy `get` invariant processing, `exec_try_catch`,
active-value and callee-realm scopes, and parameter-default save/restore.
Finding another guest-call edge or host-stack-owned cleanup action on one of
these paths expands the migrated closure; it does not justify a recursive
fallback.

Unmigrated constructors, conversions, generators, async jobs, iterators,
built-in callbacks, setters, and other Proxy traps remain #608 work unless the
inventory proves that #630 reaches them.

## Adapter compatibility

The public `Interpreter::run(...) -> Value raise Error` and
`Interpreter::call_value(...) -> Value raise Error` entry points remain
synchronous adapters, while `ExecContext`, `Signal`, and `Environment` remain
compatible during #630; migrated internal paths cannot recursively re-enter
either public adapter.

The bytecode VM may later adapt its instruction pointer and operand stack to the
same root-request/final-completion seam without sharing the tree-walker frame
representation. That adapter remains #631 work.

## Implementation sequence

1. Commit the four exact #616 programs as red end-to-end tests.
2. Add pure transition tests for entry, resume, handler selection, finalizer
   precedence, release, and one-time continuation and cleanup consumption.
3. Move activation lifecycle state out of host-stack callbacks.
4. Migrate ordinary and mutual non-tail calls, including binary and return
   resumption.
5. Migrate `try`/`catch`/`finally` handler and finalizer state.
6. Migrate getter result resumption.
7. Migrate Proxy `get` result resumption and invariant checks.
8. Connect #617 activation observation at the sole entry and release owner.
9. Run interpreter, bytecode-equivalence, error-ordering, focused cleanup, and
   cross-target tests after every slice.
