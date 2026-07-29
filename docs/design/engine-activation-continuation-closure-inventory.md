# Activation-continuation closure inventory

Date: 2026-07-29.

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

Each edge has one of three dispositions:

- **migrate in #630**: the dispatcher owns the activation, continuation, or
  cleanup before the edge may suspend;
- **synchronous leaf**: the observed runtime type cannot enter interpreted
  guest code and may complete in the imperative shell; or
- **#608 residual**: the broader may-call-user-code path remains explicitly
  outside the Milestone 10 stack-safety claim.

A residual must stay named at its call site or adapter boundary. It must not be
presented as a migrated path or hidden behind a generic recursive fallback.
Finding a residual on one of the four concrete paths invalidates this inventory
and stops implementation until the closure or design is revised.

### Managed-cycle admission invariant

A named residual is not a permitted fallback after managed execution starts.
Before any JavaScript-visible effect, a conservative eligibility check must
prove that the root request and every activation admitted to the managed cycle
use only classified continuations and synchronous leaves. An ineligible root
stays on the existing synchronous path from its beginning; execution never
switches from managed state back to that path after observing effects.

The proof may use syntax shape, callable family, and already-established
runtime types, but it may not speculatively execute guest code. If the proof
cannot exclude a residual before admission, that edge joins #630's migrated
closure. Encountering a residual after admission is an implementation
invariant failure that blocks integration, not a new JavaScript-visible error
or authorization for recursive `call_value`.

## Concrete path and runtime-type proof

| Reproducer | Interpreted activation edge | Values consumed after the edge | Other reachable call-capable operations | Runtime-type proof for this slice |
|---|---|---|---|---|
| Self recursion | `eval_call` invokes an `Object(UserFunc)` for `f` | The recursive result is the right operand of numeric `+`, then the value of `ReturnStmt` | None | The callee is the hoisted declaration, both operands are `Number`, and the argument expression is numeric `n - 1` |
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

## Migrated continuation closure

| Source edge or state owner | Possible callee or completion kinds | Consumer retained across suspension | Effects that must not replay | Disposition and focused coverage |
|---|---|---|---|---|
| `Interpreter::run` and direct `Interpreter::call_value` | Root program; interpreted or synchronous callable root; final normal or abrupt completion | Public synchronous result/error translation | Early-error validation, hoisting, source observation, and root realm setup | **Migrate in #630** as the only root-request/final-completion adapters; existing public signatures remain unchanged |
| `eval_call` to `call_value` | `Object` callable, callable `Proxy`, or non-callable `Value` | The call result as the enclosing expression value | Callee evaluation, receiver selection, and argument evaluation | **Migrate in #630** for interpreted `UserFunc`, `ArrowFunc`, `UserFuncExt`, and `ArrowFuncExt`; exact self/mutual tests cover direct functions |
| Interpreted branch of `call_value_impl` | The four interpreted callable forms; normal, return, guest throw, or runtime abrupt completion | Function-call return rule and owning activation | Environment creation, `this`, `arguments`, name binding, hoisting, and body effects | **Migrate in #630** into explicit activation preparation/body states; lifecycle tests cover normal, return, throw, and runtime abrupt exit |
| `BoundFunc` and `FuncCallMethod` forwarding | Interpreted, synchronous-native, Proxy, or non-callable target | Forwarded result with adjusted receiver/arguments | Bound argument concatenation and receiver selection | **Migrate in #630** when the resolved target is otherwise in the migrated closure; shallow forwarding regressions pin compatibility |
| `FuncApplyMethod` argument-list construction | Array-like data slots or observable getters/Proxy reads | Materialized argument list for a separate target-call continuation | Array-like length/index reads | Plain, non-observable construction is a **synchronous leaf**; observable traversal is a named **#608 residual** and makes the activation ineligible unless migrated |
| `FuncApplyMethod` target forwarding | Interpreted, synchronous-native, Proxy, or non-callable target | Forwarded result after the argument list is fixed | Target/receiver selection and completed argument construction | **Migrate in #630** when the target belongs to the migrated call closure; it is never classified as a leaf merely because argument construction was synchronous |
| `ReturnStmt` expression | Any completion produced by the expression | `Return(value)` for the owning activation | The expression and any preceding effects in the statement | **Migrate in #630** as a one-time return continuation; direct, mutual, getter, Proxy, and return-from-try tests cover it |
| `ThrowStmt` expression | Normal value, guest throw, or runtime abrupt completion from the expression | A resumed normal value wrapped as `Throw(value)` for handler routing | The expression and every effect before its result | **Migrate in #630** as a one-time throw continuation; `throw f()` crossing an activation into `catch` covers call-result-to-throw routing |
| `eval_binary` right operand | Primitive result, guest throw, or runtime abrupt completion | Saved operator, left value, location, and enclosing continuation | Left evaluation and all effects before the right operand | **Migrate in #630** for the primitive operator paths reached by #616; exact tests cover numeric `+` and `-` |
| `eval_binary_op` coercion | `Object`/`Proxy` conversion methods may be interpreted, native, Proxy, or non-callable | Operator work after each conversion result | `@@toPrimitive`, `valueOf`, `toString`, and their property lookups | Primitive-only branches are **synchronous leaves**; user-code conversion is a named **#608 residual** with its current shallow semantics retained |
| In-scope `exec_stmts` and `exec_stmt` states | Normal, return, labelled/unlabelled break/continue, guest throw, runtime abrupt | Statement-list position, last completion value, environment, and owning activation | Completed statements and `UpdateEmpty` state | **Migrate in #630** for the #616 statement shapes and required non-generator handler/finalizer traces; iterator, setter, and other residual-bearing shapes are excluded by admission unless their continuations migrate |
| `exec_try_catch` | Catchable guest throw, non-catchable runtime abrupt, or any `Signal` | Applicable catch, saved completion, and pending finalizer | Try/catch effects, catch binding, and finalizer entry | **Migrate in #630** for non-generator execution with explicit handler/finalizer continuations; generator resume state remains #608 |
| Simple parameter-default evaluation | Interpreted/native/Proxy call result, getter result, or abrupt completion from the default expression | Parameter cursor, target binding, remaining parameters, and body-entry continuation | Earlier parameter declarations/defaults and default-expression effects | **Migrate in #630** for admitted simple bindings; resumed values initialize exactly once before parameter progress continues |
| Own accessor lookup in `property.mbt` | Interpreted/native/Proxy getter or invalid callable value | Getter result delivered to the original property operation and its enclosing expression | Descriptor lookup and original receiver selection | **Migrate in #630** for ordinary `Object`, `Array`, `Map`, `Set`, and `Promise` own accessors; getter exact and receiver-order tests cover it |
| Prototype accessor lookup in `property.mbt` | Same getter categories | Getter result delivered with the original receiver | Traversed prototype prefix and descriptor selection | **Migrate in #630** through the receiver-aware property continuation; prototype getter order tests cover it |
| `with_active_property_access_value` | Normal getter/trap result or abrupt completion | Restoration of the caller's active realm before property continuation resume | Clearing and restoring active callee-realm overrides | **Migrate in #630** into property-operation cleanup data; normal and abrupt getter/Proxy tests assert source and realm behavior |
| `get_proxy_trap` handler data/accessor lookup for `get` | Own/prototype data value, interpreted/native getter, or abrupt completion | Trap value validation and the pending Proxy `get` operation | Handler lookup, getter effect, revocation checks, and receiver | Reuse the **migrated #630 getter continuation**; focused own/prototype handler-accessor order coverage is required |
| Proxy handler `get` lookup and trap-less forwarding | Handler Proxy with an in-scope `get` trap or a nested trap-less Proxy chain | The outer trap lookup, original receiver, and eventual trap value validation | Every handler-Proxy lookup/trap and traversed forwarding prefix | **Migrate in #630** through the same iterative Proxy-`get` continuation; focused trapped and trap-less nested-handler tests prevent recursive fallback |
| `proxy_get_key` trap call | Interpreted/native/Proxy callable or non-callable trap | Target, canonical key, receiver, trap result, and pending invariant work | Revocation checks, handler lookup, trap arguments, and trap body | **Migrate in #630** for interpreted traps and synchronous native leaves; the exact Proxy test covers recursive interpreted traps |
| Proxy `get` invariant processing | Ordinary/exotic target descriptor/value pair or abrupt completion | Trap result after invariant validation | Trap execution and target/key/receiver capture | **Migrate in #630** for ordinary non-Proxy targets; frozen data/accessor tests prove invariant errors occur after the trap exactly once |
| `call_value` realm wrappers | Normal or abrupt activation completion | Previous realm overrides, source identity, callee identity, and failure-observation state | Installing the callee realm and recording source failure | **Migrate in #630** into activation cleanup; borrowed-realm and source-identity regressions cover normal and abrupt exits |
| Parameter-default save/restore | Simple/extended interpreted call; normal, guest throw, or runtime abrupt default evaluation | Previous `in_nonarrow_param_default_eval` and conflict set | Reset on entry, default-expression effects, and exact restoration | **Migrate in #630** into activation/setup cleanup and explicit parameter progress; nested-default and rejected/abrupt cleanup tests cover it |
| #617 observation seam | Entry accepted, entry rejected, or activation released | Whether acquisition completed and the opaque cleanup/observer token | Entry observation and exactly one matching release | **Migrate in #630** as policy-free entry/release decisions; pure counter probes cover acquired/rejected/duplicate-consume behavior before #617 wires policy |

## Explicit residuals transferred to #608

These paths occur in the shared runtime but are not reached with a
may-call-user-code runtime type by the four concrete #616 programs:

- callable Proxy `apply` and Proxy traps other than the in-scope `get` trap;
- a Proxy target reached by post-`get` invariant `[[GetOwnProperty]]`, which may
  invoke `getOwnPropertyDescriptor` guest code;
- constructors other than the exact native Proxy-constructor setup leaf;
- setters, destructuring/iterator closure, spread arguments, iterator methods,
  and built-in callback loops;
- `InterpreterCallable`, `InterpreterCallableWithContext`, and
  `NonConstructableInterpreterCallable` branches whose native algorithm may
  invoke guest code before it returns;
- conversion hooks reached by `ToPrimitive`, `ToPropertyKey`, `ToNumber`, or
  string conversion;
- direct/indirect `eval`, generators, async functions/jobs, promises, timers,
  and module execution;
- catch-parameter or formal-parameter destructuring whose property/iterator
  operations enter guest code; an activation containing such a pattern is not
  admissible until #608 or an inventory expansion supplies its continuations;
- bytecode activation suspension/resumption, owned by #631.

Native callable variants without a guest-entry capability may finish in the
imperative shell. A callable that receives or captures an `Interpreter` is not
assumed to be a leaf merely because its body is implemented in MoonBit. Before
adding one to a managed path, the implementation must either prove that exact
callable cannot invoke guest code or add its post-call work to this inventory.

## Cleanup snapshot

An acquired activation owns one immutable snapshot or opaque shell token with:

- the previous packed active realm-prototype overrides;
- the previous active source identity and the callee source identity needed for
  failure observation;
- any enclosing property-operation realm-clear state still pending;
- the previous parameter-default flag and conflict set;
- the activation environment/context and continuation owner; and
- whether the #617 observation accepted entry.

Handler and finalizer routing does not consume this token. Leaving the owning
activation consumes it once. Rejected entry restores state installed while
preparing the attempt but never emits a release for an activation that was not
acquired.

## Focused test ledger

| Slice | Required observable tests |
|---|---|
| Red evidence | The four exact #616 sources fail before implementation and later return `256` through `Interpreter::run` |
| Transition core | Entry/rejection, value resume, every completion category, catch selection, normal-finally resume, abrupt-finally replacement, and duplicate continuation/cleanup consumption |
| Ordinary activation | Direct and mutual depth 256, nested ordinary result delivery, explicit return, non-callable error, and shallow bound/call/apply forwarding |
| Lifecycle | Normal, return, guest throw, runtime abrupt, rejected entry, realm/source restoration, simple parameter-default call/resume/restoration, exactly one release per acquired activation, and release occurring only after finalizer effects |
| Handlers/finalizers | Call returning from `try`, `throw f()` crossing an activation into `catch`, break and continue through `finally`, normal/return/throw/runtime-abrupt finalization, runtime-abrupt plus abrupt-finally replacement, and general abrupt-finally replacement |
| Getter | Own and prototype receiver identity, depth 256, exact effect order, abrupt getter, and realm/source restoration |
| Proxy `get` | Depth 256, own/prototype handler accessor order, trapped and trap-less nested-handler forwarding, exact trap side-effect order, frozen-data and getter-less-accessor invariants after the trap, and abrupt trap/invariant behavior |
| Compatibility | Existing interpreter, error-ordering, borrowed-realm, source-identity, and bytecode-equivalence suites |

## Stop conditions

Implementation stops and this inventory is revised if any edge admitted to the
managed cycle:

- reaches one of the named residuals with a may-call-user-code runtime type;
- needs statement replay, a host callback continuation, or a `Ref[Value]`
  result slot owned by an unwound host frame;
- recursively re-enters a public synchronous adapter from a migrated edge;
- releases cleanup before catch/finally routing finishes; or
- requires tree-walker semantics to be duplicated in the bytecode VM.
