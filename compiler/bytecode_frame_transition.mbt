///|
priv enum BytecodeActivationResumeDecision {
  BytecodeResumePushValue(Value)
  BytecodeResumeUpdateLocal(Int, Value, Value)
  BytecodeResumePushBindingReference(@runtime.ResolvedBindingReference)
  BytecodeResumePushReceiverAndValue(Value, Value)
  BytecodeResumeNoStackChange
  BytecodeResumeAppendArraySpread(Array[Value])
  BytecodeResumeAppendArgumentSpread(Array[Value])
}

///|
priv struct BytecodeSuspension {
  continuation : BytecodeContinuation
  request : @runtime.ExecutorActivationStep
}

///|
fn BytecodeSuspension::BytecodeSuspension(
  continuation~ : BytecodeContinuation,
  request~ : @runtime.ExecutorActivationStep,
) -> BytecodeSuspension {
  { continuation, request }
}

///|
fn suspend_bytecode(
  continuation~ : BytecodeContinuation,
  request~ : @runtime.ExecutorActivationStep,
) -> BytecodeFrameStep {
  BytecodeFrameSuspensionReady(BytecodeSuspension(continuation~, request~))
}

///|
fn plan_bytecode_local_update(
  op : @ast.UpdateOp,
  prefix : Bool,
  converted : Value,
) -> @runtime.NumericUpdatePlan raise Error {
  guard converted is Number(old_number) else {
    raise @errors.InternalError(
      message="numeric conversion completed without a Number",
    )
  }
  @runtime.plan_numeric_update(old_number, op, prefix)
}

///|
fn reduce_bytecode_local_update(
  slot : Int,
  op : @ast.UpdateOp,
  prefix : Bool,
  converted : Value,
) -> BytecodeActivationResumeDecision raise Error {
  let plan = plan_bytecode_local_update(op, prefix, converted)
  BytecodeResumeUpdateLocal(
    slot,
    plan.assigned_value(),
    plan.expression_value(),
  )
}

///|
fn reduce_bytecode_resume(
  continuation : BytecodeContinuation,
  completion : @runtime.ExecutorActivationCompletion,
) -> BytecodeActivationResumeDecision raise Error {
  match completion {
    @runtime.ExecutorActivationCompletionAbrupt(error) => raise error
    @runtime.ExecutorActivationCompletionReference(reference) =>
      match continuation {
        PushBindingReference => BytecodeResumePushBindingReference(reference)
        _ =>
          raise @errors.InternalError(
            message="bytecode frame received an unexpected binding reference completion",
          )
      }
    @runtime.ExecutorActivationCompletionNormal(value) =>
      match continuation {
        PushValue => BytecodeResumePushValue(value)
        UpdateLocalAfterNumericConversion(slot, op, prefix) =>
          reduce_bytecode_local_update(slot, op, prefix, value)
        PushBindingReference =>
          raise @errors.InternalError(
            message="bytecode binding reference resolution returned a value",
          )
        PushReceiverAndValue(receiver) =>
          BytecodeResumePushReceiverAndValue(receiver, value)
        NoStackChange => BytecodeResumeNoStackChange
        AppendArraySpread =>
          BytecodeResumeAppendArraySpread(
            @runtime.executor_iterable_spread_batch_values(value),
          )
        AppendArgumentSpread =>
          BytecodeResumeAppendArgumentSpread(
            @runtime.executor_iterable_spread_batch_values(value),
          )
      }
  }
}
