///|
fn resume_normal(
  continuation : BytecodeContinuation,
  value : Value,
) -> BytecodeActivationResumeDecision raise Error {
  reduce_bytecode_resume(
    continuation,
    @runtime.executor_activation_completion_normal(value),
  )
}

///|
test "normal completion follows its bytecode continuation" {
  guard resume_normal(PushValue, Number(7.0))
    is BytecodeResumePushValue(Number(7.0)) else {
    fail("PushValue did not push the completed value")
  }
  guard resume_normal(
      UpdateLocalAfterNumericConversion(2, Increment, false),
      Number(7.0),
    )
    is BytecodeResumeUpdateLocal(2, Number(8.0), Number(7.0)) else {
    fail("postfix UpdateLocal did not preserve its expression value")
  }
  guard resume_normal(
      PushReceiverAndValue(String_("receiver")),
      String_("callee"),
    )
    is BytecodeResumePushReceiverAndValue(
      String_("receiver"),
      String_("callee")
    ) else {
    fail("PushReceiverAndValue did not preserve stack order")
  }
  guard resume_normal(NoStackChange, Undefined) is BytecodeResumeNoStackChange else {
    fail("NoStackChange produced an observable resume action")
  }
}
