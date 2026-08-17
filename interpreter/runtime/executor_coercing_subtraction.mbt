///|
// A managed Number-domain subtraction operation. The runtime owns the complete
// ToPrimitive(number) sequence; the bytecode executor only supplies operands.

///|
pub enum ExecutorCoercingSubtractionStart {
  ExecutorCoercingSubtractionCompleted(Value)
  ExecutorCoercingSubtractionSuspended(ExecutorCoercingSubtractionRequest)
}

///|
pub fn begin_executor_coercing_subtraction(
  left : Value,
  right : Value,
  loc : @token.Loc,
) -> ExecutorCoercingSubtractionStart raise Error {
  if is_js_object(left) || is_js_object(right) {
    ExecutorCoercingSubtractionSuspended(
      ExecutorCoercingSubtractionRequest(left~, right~, loc~),
    )
  } else {
    ExecutorCoercingSubtractionCompleted(finish_subtraction(left, right, loc))
  }
}

///|
priv enum ExecutorCoercingSubtractionPhase {
  ExecutorCoercingSubtractionNeedLeft
  ExecutorCoercingSubtractionAwaitLeft(ExecutorToPrimitiveOperation)
  ExecutorCoercingSubtractionHaveLeft(Double)
  ExecutorCoercingSubtractionAwaitRight(Double, ExecutorToPrimitiveOperation)
  ExecutorCoercingSubtractionComplete(Value)
}

///|
priv struct ExecutorCoercingSubtractionFrame {
  request : ExecutorCoercingSubtractionRequest
  mut phase : ExecutorCoercingSubtractionPhase
}

///|
fn ExecutorCoercingSubtractionFrame::ExecutorCoercingSubtractionFrame(
  request : ExecutorCoercingSubtractionRequest,
) -> ExecutorCoercingSubtractionFrame {
  { request, phase: ExecutorCoercingSubtractionNeedLeft }
}

///|
fn ExecutorCoercingSubtractionFrame::finish_right(
  self : ExecutorCoercingSubtractionFrame,
  interp : Interpreter,
  left : Double,
  right : Value,
) -> ExecutorActivationStep raise Error {
  let result = finish_subtraction(
    Number(left),
    right,
    self.request.loc,
    interp=Some(interp),
  )
  self.phase = ExecutorCoercingSubtractionComplete(result)
  ExecutorActivationNormal(result)
}

///|
fn ExecutorCoercingSubtractionFrame::step_frame(
  self : ExecutorCoercingSubtractionFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorCoercingSubtractionNeedLeft => {
      let operation = ExecutorToPrimitiveOperation(
        self.request.left,
        ExecutorToPrimitiveNumber,
        self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          let left_number = to_number(value, interp=Some(interp))
          self.phase = ExecutorCoercingSubtractionHaveLeft(left_number)
          self.step_frame(interp)
        }
        step => {
          self.phase = ExecutorCoercingSubtractionAwaitLeft(operation)
          step
        }
      }
    }
    ExecutorCoercingSubtractionAwaitLeft(operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          let left_number = to_number(value, interp=Some(interp))
          self.phase = ExecutorCoercingSubtractionHaveLeft(left_number)
          self.step_frame(interp)
        }
        step => {
          self.phase = ExecutorCoercingSubtractionAwaitLeft(operation)
          step
        }
      }
    ExecutorCoercingSubtractionHaveLeft(left_number) => {
      let operation = ExecutorToPrimitiveOperation(
        self.request.right,
        ExecutorToPrimitiveNumber,
        self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          self.finish_right(interp, left_number, value)
        step => {
          self.phase = ExecutorCoercingSubtractionAwaitRight(
            left_number, operation,
          )
          step
        }
      }
    }
    ExecutorCoercingSubtractionAwaitRight(left_number, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          self.finish_right(interp, left_number, value)
        step => {
          self.phase = ExecutorCoercingSubtractionAwaitRight(
            left_number, operation,
          )
          step
        }
      }
    ExecutorCoercingSubtractionComplete(value) => {
      ignore(value)
      raise @errors.InternalError(
        message="coercing subtraction frame stepped after completion",
      )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorCoercingSubtractionFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for ExecutorCoercingSubtractionFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match self.phase {
    ExecutorCoercingSubtractionAwaitLeft(operation)
    | ExecutorCoercingSubtractionAwaitRight(_, operation) =>
      operation.deliver_activation_completion(completion)
    ExecutorCoercingSubtractionNeedLeft
    | ExecutorCoercingSubtractionHaveLeft(_)
    | ExecutorCoercingSubtractionComplete(_) =>
      raise @errors.InternalError(
        message="coercing subtraction received an unexpected child completion",
      )
  }
}
