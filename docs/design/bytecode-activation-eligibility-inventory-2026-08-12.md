# Bytecode activation-eligibility inventory

This is the source-backed inventory for issue #884. It records the current
main behavior at `4be8f711d374373476f1165404fa62cb9cd3af60`; it is review
evidence, not a second classifier. The sole typed authority is the exhaustive
`bytecode_instruction_contract` match in
[`compiler/bytecode_ir.mbt`](../../compiler/bytecode_ir.mbt), and function
selection recomputes that authority from the function's own verified `code`
array.

## Disposition counts

There are 102 `BytecodeInstr` constructors. Sixty-three constructors are
unconditionally `SynchronousLeaf`, twelve are unconditionally
`ManagedSuspension`, and twenty-five are unconditionally
`UnsupportedBeforeActivation`. Two constructors split by operand family:

| Operand family | SynchronousLeaf operands | UnsupportedBeforeActivation operands |
| --- | ---: | ---: |
| `BinaryOp` | 5 (`===`, `!==`, `&&`, `||`, `??`) | 20 coercive/relational/dispatch operators |
| `UnaryValueOp` | 4 (`!`, `typeof`, `void`, `delete`) | 3 numeric-conversion operators |

The contract also preserves `may_raise_js` independently of activation
disposition. Adding a `BytecodeInstr` constructor requires updates to both the
contract and the VM's exhaustive dispatch match.

## Source-backed instruction inventory

The VM dispatch is [`BytecodeFrame::step_bytecode`](../../compiler/bytecode_vm.mbt).
The continuation destination is set before every managed return and consumed
exactly once by [`BytecodeFrame::deliver_activation_completion`](../../compiler/bytecode_vm.mbt),
which clears `pending_activation_result` before delivering a normal value or
raising an abrupt completion.

| Instruction or operand family | VM operation and reachable helper | Guest-entry evidence | Disposition / reason |
| --- | --- | --- | --- |
| `ObserveStatement`, `ObserveExpression`; `LoadConst`, `LoadUndefined`, `LoadThis`, `LoadNewTarget`; `LoadLocal`, `StoreLocal`, `LoadEnvSlot`, `StoreEnvSlot`; `DefineBinding`, `DefineLocal`, `DefineEnvSlot`; `SetCompletion`, `SetCompletionValue`, `Pop`, `Dup`; `Jump`, `JumpIfFalse`, `JumpIfFalseKeep`, `JumpIfTrueKeep`, `JumpIfNotNullishKeep`; `BeginOptionalChain`, `MarkOptionalChainShortCircuit`, `JumpIfNotOptionalChainShortCircuitKeep`, `EndOptionalChain`; `ForInNext`, `EndForIn`; `MakeArray`, `MakeArrayWithHoles`, `StartArray`, `ArrayPushValue`, `ArrayPushHole`, `StartArgs`, `ArgPushValue`; `MakeObject`, `StartObject`, `ObjectSetStatic`, `ObjectSetStaticGetter`, `ObjectSetStaticSetter`, `ObjectSetComputedGetter`, `ObjectSetComputedSetter`, `ObjectSetComputed`, `ObjectSetProto`; `SetFunctionName`, `DeclareFunction`, `DropPropertyAssignReference`, `DropComputedAssignReference`, `Return` | Stack, control-flow, local/environment, object/array assembly, or frame bookkeeping in their exhaustive `step_bytecode` arms; helpers are host-owned value/collection operations. | No helper in these paths invokes a guest activation. A nested function is only materialized here; its body is selected independently when that function activation starts. | `SynchronousLeaf` |
| `LoadConsoleMember` | `Interpreter::get_console_member` in its `step_bytecode` arm; creates the host native `console.log` callable or raises a host error. | No JavaScript callable is entered while loading the member. | `SynchronousLeaf` |
| `LoadDirectEvalCallee`; `LoadName`, `LoadAssignmentName`, `StoreName`; `TypeofName` | Environment/name helpers in their `step_bytecode` arms. | `with` statements are rejected by the lowering contract (`BytecodeUnsupportedReason::WithStatement` in `bytecode_lower.mbt`); current bytecode name lookup and global fallback are direct environment/bag operations. Direct eval itself is a separate unsupported instruction below. | `SynchronousLeaf` |
| `LoadSuperProperty`, `LoadSuperComputed` | `Interpreter::eval_super_property` / `eval_super_computed_property` in their `step_bytecode` arms. | Super lookup can invoke user-defined accessors or proxy behavior; no typed activation request is returned. | `UnsupportedBeforeActivation(SuperPropertyAccess)` / `SuperComputedPropertyAccess` |
| `BinaryOp` strict/logical operands | `runtime.eval_binary_op` in the `BinaryOp` arm; strict equality and truthiness/logical operations do not coerce or enter guest code. | The helper path is value-local for these operands. | `SynchronousLeaf` |
| `BinaryOp` all other operands | Same helper, with `interp=Some(interp)`. | Numeric conversion, primitive conversion, relational comparison, `in`, and `instanceof` can reach guest conversion/proxy behavior synchronously. | `UnsupportedBeforeActivation(BinaryOperation)` |
| `UnaryValueOp` `!`, `typeof`, `void`, `delete` | `runtime.eval_unary_value_op` in the `UnaryValueOp` arm; these operand cases do not perform numeric conversion. | No guest activation is entered by the selected value-local operation. | `SynchronousLeaf` |
| `UnaryValueOp` `-`, `+`, `~` | Same helper. | Numeric conversion is a guest-capable operation; the VM path has no typed activation seam. | `UnsupportedBeforeActivation(UnaryNumericConversion)` |
| `DeleteName`, `DeleteProperty`, `DeleteComputed` | `eval_delete_identifier`, `eval_delete_property`, and `eval_delete_computed_property` in their dispatch arms. | Identifier deletion can inspect a dynamic environment/with boundary; property deletion can enter proxy traps. | `UnsupportedBeforeActivation(DeleteName)`, `DeleteProperty`, or `DeleteComputedProperty` |
| `AppendTemplate` | `runtime.to_js_string(..., interp=Some(interp))` in the `AppendTemplate` arm. | Template interpolation conversion can invoke guest conversion hooks. | `UnsupportedBeforeActivation(TemplateInterpolation)` |
| `MakeTemplateObject`, `MakeRegExp` | Template cache and the realm's regexp construction hook in their dispatch arms. | These are host object creation paths; they do not call a JavaScript function. | `SynchronousLeaf` |
| `UpdateName` | `Interpreter::update_compiled_name` in the `UpdateName` arm. | Name resolution/update and numeric conversion are synchronous; no activation request is produced. | `UnsupportedBeforeActivation(UpdateName)` |
| `UpdateLocal`, `UpdateEnvSlot` | `runtime.to_number(..., interp=Some(interp))` and local/env mutation in their dispatch arms. | Numeric conversion can invoke guest hooks; no suspension seam exists. | `UnsupportedBeforeActivation(UpdateLocal)` / `UpdateEnvSlot` |
| `UpdateProperty` | `executor_activation_property_increment/decrement` in the `UpdateProperty` arm; destination is `PushValue`. | Both increment and decrement branches always return a typed `ExecutorActivationStep`; the runtime-owned get/convert/set pipeline and completion are one managed request. | `ManagedSuspension` |
| `UpdateComputed` | String keys use the static update request; other keys call `Interpreter::eval_update_computed_property` in the same arm. | Runtime-value-dependent static-vs-synchronous behavior means the instruction is not always managed. | `UnsupportedBeforeActivation(ConditionalComputedUpdate)` |
| `StartForIn` | `runtime.collect_for_in_keys` in the `StartForIn` arm. | Enumeration can invoke proxy traps or other guest-capable property behavior synchronously. | `UnsupportedBeforeActivation(ForInEnumeration)` |
| `ArrayPushSpread`, `ArgPushSpread` | `Interpreter::spread_iterable` in their dispatch arms. | Iterable lookup and iterator execution are guest-capable and have no typed seam here. | `UnsupportedBeforeActivation(ArraySpread)` / `ArgumentSpread` |
| `ToObjectLiteralPropertyKey` | `Interpreter::to_object_literal_property_key` in its dispatch arm. | Property-key conversion can invoke guest conversion hooks. | `UnsupportedBeforeActivation(ObjectPropertyKey)` |
| `ObjectSpread` | `Interpreter::copy_object_spread_properties` in its dispatch arm. | Copying can invoke guest getters/proxy behavior synchronously. | `UnsupportedBeforeActivation(ObjectSpread)` |
| `MakeFunction`, `MakeNamedFunction`, `MakeMethodFunction`, `MakeComputedMethodFunction`, `MakeArrowFunction` | Closure materialization in their dispatch arms. | No child body is executed. Child eligibility is selected only when its own executor activation starts. | `SynchronousLeaf` |
| `GetProperty`, `ReadPropertyForAssign`, `SetProperty` | `executor_activation_property_get/set` in their dispatch arms; destination is `PushValue`. | Each dispatch path always creates an existing typed request; `deliver_activation_completion` consumes the one pending destination exactly once. | `ManagedSuspension` |
| `SetForInProperty` | Direct `Interpreter::set_property` in its dispatch arm. | This is synchronous guest-capable property mutation and has no typed request. | `UnsupportedBeforeActivation(SynchronousPropertyAssignment)` |
| `GetComputed` | Runtime admission may return a typed request for one sealed string-own-accessor shape; all other values use `interp.get_computed_property` in the same arm. | Runtime key/object shape determines whether the path suspends or remains synchronous. | `UnsupportedBeforeActivation(ConditionalComputedProperty)` |
| `ReadComputedForAssign` | Same conditional admission, with synchronous key conversion/read fallback in its dispatch arm. | The instruction is not always managed. | `UnsupportedBeforeActivation(ComputedAssignmentRead)` |
| `SetComputed` | String keys use `executor_activation_property_set`; other keys use `interp.set_computed_property` in the same arm. | Runtime key determines typed suspension versus synchronous mutation. | `UnsupportedBeforeActivation(ConditionalComputedAssignment)` |
| `SetForInComputed` | Direct `Interpreter::set_computed_property` in its dispatch arm. | Always synchronous and guest-capable for dynamic targets/keys. | `UnsupportedBeforeActivation(SynchronousComputedPropertyAssignment)` |
| `PreparePropertyCall`, `PreparePlainPropertyCall` | Static `executor_activation_property_get` in their dispatch arms; destination is `PushReceiverAndValue`. | Both paths always return the typed request and preserve the receiver in the exactly-once continuation destination. | `ManagedSuspension` |
| `PrepareComputedCall` | Conditional runtime admission or synchronous `interp.get_computed_property` in its dispatch arm. | Runtime key/object shape selects suspension versus synchronous lookup. | `UnsupportedBeforeActivation(ConditionalComputedCall)` |
| `AssignPattern` | `Interpreter::eval_destructure_assign` in its dispatch arm. | Destructuring can read/write guest properties and iterate synchronously; no activation seam exists. | `UnsupportedBeforeActivation(DestructuringAssignment)` |
| `PrepareSuperPropertyCall`, `PrepareSuperComputedCall` | `Interpreter::eval_super_*_call_reference` in their dispatch arms. | Super call reference preparation can enter guest property behavior synchronously. | `UnsupportedBeforeActivation(SuperPropertyCall)` / `SuperComputedPropertyCall` |
| `CallDirectEval` | `Interpreter::call_direct_eval_or_shadowed` in its dispatch arm. | Direct eval is a synchronous interpreter re-entry without an existing typed request. | `UnsupportedBeforeActivation(DirectEval)` |
| `Call`, `CallWithReceiver`, `CallSpread`, `CallSpreadWithReceiver` | `executor_activation_call` in their dispatch arms; destination is `PushValue`. | Every form returns an existing typed call request; spread iteration is separately rejected at `ArgPushSpread`, before this instruction. | `ManagedSuspension` |
| `Construct`, `ConstructSpread` | `executor_activation_construct` in their dispatch arms; destination is `PushValue`. | Every form returns an existing typed construct request; spread iteration is separately rejected before this instruction. | `ManagedSuspension` |
| `Throw` | `runtime.raise_js_exception` in the `Throw` arm. | It raises an abrupt JavaScript completion and does not enter a guest activation. | `SynchronousLeaf` |

## Function and verifier boundary

`finalize_bytecode_program` first runs the source, control-flow,
indexed-operand, shape-operand, and frame-shape verifiers over the raw
`BytecodeUnverifiedProgram`. Only after all of them succeed does it construct
the private `VerifiedBytecodeFunction` carrier retained by `BytecodeProgram`.
The formal activation selector accepts that carrier, not a raw
`BytecodeFunction`, and scans only its own `code` before any `BytecodeFrame` is
constructed. Executor code and frames retain the same carrier. Projecting a
child from it preserves verification provenance, while the child's disposition
is recomputed only when that child activation is selected. No eligibility
summary or child-folded cache is stored.

The architecture gate in
[`scripts/audit_bytecode_vm_semantic_edges.py`](../../scripts/audit_bytecode_vm_semantic_edges.py)
roots a resolved call graph at `BytecodeFrame::step_bytecode`. It asks
`moon ide hover` for symbol identity, follows reachable compiler helpers across
files, and inventories both compiler edges and runtime boundary calls with
their enclosing function and source location. Receiver aliases and calls in
ordinary or `$|` interpolation therefore remain executable semantic edges;
comments, escaped interpolation text, and raw `#|` content do not resolve as
calls. The checked baseline is generated evidence from MoonBit's typed symbol
graph, not a hand-maintained list of guest-capable helper names.

A new instruction must update both the exhaustive compiler contract and VM
dispatch before the project type-checks. A new or relocated synchronous call
edge reachable from dispatch changes the semantic graph and fails
`make architecture-audit` until the reviewed evidence is updated.

The intentionally unsupported families are the synchronous guest-capable
edges listed above: super access/reference preparation, coercive operators,
deletion, template conversion, identifier/local/environment updates,
conditional computed access/update/assignment/call, for-in enumeration,
spread, object-key/spread conversion, destructuring assignment, direct eval,
and synchronous property mutation. This issue does not add a suspension seam
for any of them.
