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

The VM dispatch is [`BytecodeFrame::step_bytecode`](../../compiler/bytecode_vm.mbt#L537).
The continuation destination is set before every managed return and consumed
exactly once by [`BytecodeFrame::deliver_activation_completion`](../../compiler/bytecode_vm.mbt#L152),
which clears `pending_activation_result` before delivering a normal value or
raising an abrupt completion.

| Instruction or operand family | VM operation and reachable helper | Guest-entry evidence | Disposition / reason |
| --- | --- | --- | --- |
| `ObserveStatement`, `ObserveExpression`; `LoadConst`, `LoadUndefined`, `LoadThis`, `LoadNewTarget`; `LoadLocal`, `StoreLocal`, `LoadEnvSlot`, `StoreEnvSlot`; `DefineBinding`, `DefineLocal`, `DefineEnvSlot`; `SetCompletion`, `SetCompletionValue`, `Pop`, `Dup`; `Jump`, `JumpIfFalse`, `JumpIfFalseKeep`, `JumpIfTrueKeep`, `JumpIfNotNullishKeep`; `BeginOptionalChain`, `MarkOptionalChainShortCircuit`, `JumpIfNotOptionalChainShortCircuitKeep`, `EndOptionalChain`; `ForInNext`, `EndForIn`; `MakeArray`, `MakeArrayWithHoles`, `StartArray`, `ArrayPushValue`, `ArrayPushHole`, `StartArgs`, `ArgPushValue`; `MakeObject`, `StartObject`, `ObjectSetStatic`, `ObjectSetStaticGetter`, `ObjectSetStaticSetter`, `ObjectSetComputedGetter`, `ObjectSetComputedSetter`, `ObjectSetComputed`, `ObjectSetProto`; `SetFunctionName`, `DeclareFunction`, `DropPropertyAssignReference`, `DropComputedAssignReference`, `Return` | Stack, control-flow, local/environment, object/array assembly, or frame bookkeeping in `bytecode_vm.mbt#L554-L626`, `#L784-L1009`, and `#L1251-L1255`; helpers are host-owned value/collection operations. | No helper in these paths invokes a guest activation. A nested function is only materialized here; its body is selected independently when that function activation starts. | `SynchronousLeaf` |
| `LoadConsoleMember` | `Interpreter::get_console_member` at `bytecode_vm.mbt#L568`; creates the host native `console.log` callable or raises a host error. | No JavaScript callable is entered while loading the member. | `SynchronousLeaf` |
| `LoadDirectEvalCallee`; `LoadName`, `LoadAssignmentName`, `StoreName`; `TypeofName` | Environment/name helpers at `bytecode_vm.mbt#L569-L575` and `#L646-L647`. | `with` statements are rejected by the lowering contract (`BytecodeUnsupportedReason::WithStatement` in `bytecode_lower.mbt`); current bytecode name lookup and global fallback are direct environment/bag operations. Direct eval itself is a separate unsupported instruction below. | `SynchronousLeaf` |
| `LoadSuperProperty`, `LoadSuperComputed` | `Interpreter::eval_super_property` / `eval_super_computed_property` at `bytecode_vm.mbt#L562-L567`. | Super lookup can invoke user-defined accessors or proxy behavior; no typed activation request is returned. | `UnsupportedBeforeActivation(SuperPropertyAccess)` / `SuperComputedPropertyAccess` |
| `BinaryOp` strict/logical operands | `runtime.eval_binary_op` at `bytecode_vm.mbt#L627-L640`; strict equality and truthiness/logical operations do not coerce or enter guest code. | The helper path is value-local for these operands. | `SynchronousLeaf` |
| `BinaryOp` all other operands | Same helper, with `interp=Some(interp)`. | Numeric conversion, primitive conversion, relational comparison, `in`, and `instanceof` can reach guest conversion/proxy behavior synchronously. | `UnsupportedBeforeActivation(BinaryOperation)` |
| `UnaryValueOp` `!`, `typeof`, `void`, `delete` | `runtime.eval_unary_value_op` at `bytecode_vm.mbt#L642-L645`; these operand cases do not perform numeric conversion. | No guest activation is entered by the selected value-local operation. | `SynchronousLeaf` |
| `UnaryValueOp` `-`, `+`, `~` | Same helper. | Numeric conversion is a guest-capable operation; the VM path has no typed activation seam. | `UnsupportedBeforeActivation(UnaryNumericConversion)` |
| `DeleteName`, `DeleteProperty`, `DeleteComputed` | `eval_delete_identifier`, `eval_delete_property`, and `eval_delete_computed_property` at `bytecode_vm.mbt#L648-L659`. | Identifier deletion can inspect a dynamic environment/with boundary; property deletion can enter proxy traps. | `UnsupportedBeforeActivation(DeleteName)`, `DeleteProperty`, or `DeleteComputedProperty` |
| `AppendTemplate` | `runtime.to_js_string(..., interp=Some(interp))` at `bytecode_vm.mbt#L661-L677`. | Template interpolation conversion can invoke guest conversion hooks. | `UnsupportedBeforeActivation(TemplateInterpolation)` |
| `MakeTemplateObject`, `MakeRegExp` | Template cache and the realm's regexp construction hook at `bytecode_vm.mbt#L679-L692`. | These are host object creation paths; they do not call a JavaScript function. | `SynchronousLeaf` |
| `UpdateName` | `Interpreter::update_compiled_name` at `bytecode_vm.mbt#L698-L700`. | Name resolution/update and numeric conversion are synchronous; no activation request is produced. | `UnsupportedBeforeActivation(UpdateName)` |
| `UpdateLocal`, `UpdateEnvSlot` | `runtime.to_number(..., interp=Some(interp))` and local/env mutation at `bytecode_vm.mbt#L700-L720`. | Numeric conversion can invoke guest hooks; no suspension seam exists. | `UnsupportedBeforeActivation(UpdateLocal)` / `UpdateEnvSlot` |
| `UpdateProperty` | `executor_activation_property_increment/decrement` at `bytecode_vm.mbt#L721-L746`; destination is `PushValue`. | Both increment and decrement branches always return a typed `ExecutorActivationStep`; the runtime-owned get/convert/set pipeline and completion are one managed request. | `ManagedSuspension` |
| `UpdateComputed` | String keys use the static update request; other keys call `Interpreter::eval_update_computed_property` at `bytecode_vm.mbt#L747-L782`. | Runtime-value-dependent static-vs-synchronous behavior means the instruction is not always managed. | `UnsupportedBeforeActivation(ConditionalComputedUpdate)` |
| `StartForIn` | `runtime.collect_for_in_keys` at `bytecode_vm.mbt#L820-L825`. | Enumeration can invoke proxy traps or other guest-capable property behavior synchronously. | `UnsupportedBeforeActivation(ForInEnumeration)` |
| `ArrayPushSpread`, `ArgPushSpread` | `Interpreter::spread_iterable` at `bytecode_vm.mbt#L864-L882`. | Iterable lookup and iterator execution are guest-capable and have no typed seam here. | `UnsupportedBeforeActivation(ArraySpread)` / `ArgumentSpread` |
| `ToObjectLiteralPropertyKey` | `Interpreter::to_object_literal_property_key` at `bytecode_vm.mbt#L965-L968`. | Property-key conversion can invoke guest conversion hooks. | `UnsupportedBeforeActivation(ObjectPropertyKey)` |
| `ObjectSpread` | `Interpreter::copy_object_spread_properties` at `bytecode_vm.mbt#L974-L976`. | Copying can invoke guest getters/proxy behavior synchronously. | `UnsupportedBeforeActivation(ObjectSpread)` |
| `MakeFunction`, `MakeNamedFunction`, `MakeMethodFunction`, `MakeComputedMethodFunction`, `MakeArrowFunction` | Closure materialization at `bytecode_vm.mbt#L982-L1008`. | No child body is executed. Child eligibility is selected only when its own executor activation starts. | `SynchronousLeaf` |
| `GetProperty`, `ReadPropertyForAssign`, `SetProperty` | `executor_activation_property_get/set` at `bytecode_vm.mbt#L1010-L1015`, `#L1031-L1037`, and `#L1079-L1091`; destination is `PushValue`. | Each dispatch path always creates an existing typed request; `deliver_activation_completion` consumes the one pending destination exactly once. | `ManagedSuspension` |
| `SetForInProperty` | Direct `Interpreter::set_property` at `bytecode_vm.mbt#L1122-L1128`. | This is synchronous guest-capable property mutation and has no typed request. | `UnsupportedBeforeActivation(SynchronousPropertyAssignment)` |
| `GetComputed` | Runtime admission may return a typed request for one sealed string-own-accessor shape at `bytecode_vm.mbt#L1017-L1029`; all other values use `interp.get_computed_property`. | Runtime key/object shape determines whether the path suspends or remains synchronous. | `UnsupportedBeforeActivation(ConditionalComputedProperty)` |
| `ReadComputedForAssign` | Same conditional admission, with synchronous key conversion/read fallback at `bytecode_vm.mbt#L1038-L1066`. | The instruction is not always managed. | `UnsupportedBeforeActivation(ComputedAssignmentRead)` |
| `SetComputed` | String keys use `executor_activation_property_set`; other keys use `interp.set_computed_property` at `bytecode_vm.mbt#L1093-L1120`. | Runtime key determines typed suspension versus synchronous mutation. | `UnsupportedBeforeActivation(ConditionalComputedAssignment)` |
| `SetForInComputed` | Direct `Interpreter::set_computed_property` at `bytecode_vm.mbt#L1129-L1135`. | Always synchronous and guest-capable for dynamic targets/keys. | `UnsupportedBeforeActivation(SynchronousComputedPropertyAssignment)` |
| `PreparePropertyCall`, `PreparePlainPropertyCall` | Static `executor_activation_property_get` at `bytecode_vm.mbt#L1141-L1153`; destination is `PushReceiverAndValue`. | Both paths always return the typed request and preserve the receiver in the exactly-once continuation destination. | `ManagedSuspension` |
| `PrepareComputedCall` | Conditional runtime admission or synchronous `interp.get_computed_property` at `bytecode_vm.mbt#L1155-L1171`. | Runtime key/object shape selects suspension versus synchronous lookup. | `UnsupportedBeforeActivation(ConditionalComputedCall)` |
| `AssignPattern` | `Interpreter::eval_destructure_assign` at `bytecode_vm.mbt#L1137-L1139`. | Destructuring can read/write guest properties and iterate synchronously; no activation seam exists. | `UnsupportedBeforeActivation(DestructuringAssignment)` |
| `PrepareSuperPropertyCall`, `PrepareSuperComputedCall` | `Interpreter::eval_super_*_call_reference` at `bytecode_vm.mbt#L1173-L1187`. | Super call reference preparation can enter guest property behavior synchronously. | `UnsupportedBeforeActivation(SuperPropertyCall)` / `SuperComputedPropertyCall` |
| `CallDirectEval` | `Interpreter::call_direct_eval_or_shadowed` at `bytecode_vm.mbt#L1188-L1200`. | Direct eval is a synchronous interpreter re-entry without an existing typed request. | `UnsupportedBeforeActivation(DirectEval)` |
| `Call`, `CallWithReceiver`, `CallSpread`, `CallSpreadWithReceiver` | `executor_activation_call` at `bytecode_vm.mbt#L1201-L1233`; destination is `PushValue`. | Every form returns an existing typed call request; spread iteration is separately rejected at `ArgPushSpread`, before this instruction. | `ManagedSuspension` |
| `Construct`, `ConstructSpread` | `executor_activation_construct` at `bytecode_vm.mbt#L1235-L1249`; destination is `PushValue`. | Every form returns an existing typed construct request; spread iteration is separately rejected before this instruction. | `ManagedSuspension` |
| `Throw` | `runtime.raise_js_exception` at `bytecode_vm.mbt#1252-L1255`. | It raises an abrupt JavaScript completion and does not enter a guest activation. | `SynchronousLeaf` |

## Function and verifier boundary

`select_bytecode_function_activation` scans only the supplied function's own
`code`, returning a typed `Result` before any `BytecodeFrame` is constructed.
`bytecode_function_activation_disposition` derives the summary from that same
scan; no mutable summary or child-folded cache exists. Closure-making
instructions therefore remain leaf operations in the parent, while the child
body is independently selected at child activation.

`finalize_bytecode_program` calls `verify_bytecode_activation_eligibility`
after all existing source, control-flow, indexed-operand, shape, and frame
verifiers have accepted the representation. That traversal recomputes each
function's disposition independently and reuses the existing verifier
structure rather than maintaining a manually synchronized instruction/helper
registry. A new instruction must therefore update both the compiler contract
and the VM dispatch before the project can type-check.

The intentionally unsupported families are the synchronous guest-capable
edges listed above: super access/reference preparation, coercive operators,
deletion, template conversion, identifier/local/environment updates,
conditional computed access/update/assignment/call, for-in enumeration,
spread, object-key/spread conversion, destructuring assignment, direct eval,
and synchronous property mutation. This issue does not add a suspension seam
for any of them.
