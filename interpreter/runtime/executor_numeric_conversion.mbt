///|
// Managed ToNumber for an already-evaluated value. Primitive values complete
// immediately; object conversion remains resumable because user-defined
// Symbol.toPrimitive, valueOf, or toString methods may execute guest code.
pub struct ExecutorNumericConversionRequest {
  priv value : Value
  priv loc : @token.Loc
}

///|
fn ExecutorNumericConversionRequest::ExecutorNumericConversionRequest(
  value~ : Value,
  loc~ : @token.Loc,
) -> ExecutorNumericConversionRequest {
  { value, loc }
}

///|
pub enum ExecutorNumericConversionStart {
  ExecutorNumericConversionCompleted(Value)
  ExecutorNumericConversionSuspended(ExecutorNumericConversionRequest)
}

///|
pub fn begin_executor_numeric_conversion(
  interp : Interpreter,
  value : Value,
  loc : @token.Loc,
) -> ExecutorNumericConversionStart raise Error {
  if is_js_object(value) {
    ExecutorNumericConversionSuspended(
      ExecutorNumericConversionRequest(value~, loc~),
    )
  } else {
    ExecutorNumericConversionCompleted(
      Number(to_number(value, interp=Some(interp))),
    )
  }
}

///|
pub fn executor_activation_numeric_conversion_request(
  request : ExecutorNumericConversionRequest,
) -> ExecutorActivationStep {
  ExecutorActivationNumericConversion(request)
}

///|
fn executor_numeric_conversion_completion(
  step : ExecutorActivationStep,
) -> ExecutorActivationCompletion {
  match step {
    ExecutorActivationNormal(value) | ExecutorActivationReturn(value) =>
      ExecutorActivationCompletionNormal(value)
    _ =>
      ExecutorActivationCompletionAbrupt(
        @errors.InternalError(
          message="numeric conversion completed with a pending activation",
        ),
      )
  }
}

///|
priv enum ExecutorNumericConversionPhase {
  ExecutorNumericConversionNeedInput
  ExecutorNumericConversionAwaitToPrimitive(ExecutorToPrimitiveOperation)
  ExecutorNumericConversionComplete
}

///|
priv struct ExecutorNumericConversionFrame {
  request : ExecutorNumericConversionRequest
  mut phase : ExecutorNumericConversionPhase
}

///|
fn ExecutorNumericConversionFrame::ExecutorNumericConversionFrame(
  request : ExecutorNumericConversionRequest,
) -> ExecutorNumericConversionFrame {
  { request, phase: ExecutorNumericConversionNeedInput }
}

///|
fn ExecutorNumericConversionFrame::finish(
  self : ExecutorNumericConversionFrame,
  interp : Interpreter,
  primitive : Value,
) -> ExecutorActivationStep raise Error {
  self.phase = ExecutorNumericConversionComplete
  ExecutorActivationNormal(Number(to_number(primitive, interp=Some(interp))))
}

///|
impl ExecutorActivationFrame for ExecutorNumericConversionFrame with fn step(
  self,
  interp,
) {
  match self.phase {
    ExecutorNumericConversionNeedInput => {
      let operation = ExecutorToPrimitiveOperation(
        self.request.value,
        ExecutorToPrimitiveNumber,
        self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) => self.finish(interp, value)
        step => {
          self.phase = ExecutorNumericConversionAwaitToPrimitive(operation)
          step
        }
      }
    }
    ExecutorNumericConversionAwaitToPrimitive(operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) => self.finish(interp, value)
        step => {
          self.phase = ExecutorNumericConversionAwaitToPrimitive(operation)
          step
        }
      }
    ExecutorNumericConversionComplete =>
      raise @errors.InternalError(
        message="numeric conversion frame stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorNumericConversionFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match self.phase {
    ExecutorNumericConversionAwaitToPrimitive(operation) =>
      operation.deliver_activation_completion(completion)
    ExecutorNumericConversionNeedInput | ExecutorNumericConversionComplete =>
      raise @errors.InternalError(
        message="numeric conversion received an unexpected child completion",
      )
  }
}
