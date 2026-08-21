///|
// A managed Number-domain multiplicative operation. Runtime owns the complete
// ToPrimitive(number) sequence, final Number operation, and abrupt completion;
// executors supply only already-evaluated operands and the source location.

///|
pub(all) enum ExecutorMultiplicativeOperator {
  ExecutorMultiplicativeMultiply
  ExecutorMultiplicativeDivide
  ExecutorMultiplicativeRemainder
}

///|
pub enum ExecutorCoercingMultiplicativeStart {
  ExecutorCoercingMultiplicativeCompleted(Value)
  ExecutorCoercingMultiplicativeSuspended(ExecutorCoercingMultiplicativeRequest)
}

///|
pub struct ExecutorCoercingMultiplicativeRequest {
  priv left : Value
  priv right : Value
  priv operator : ExecutorMultiplicativeOperator
  priv loc : @token.Loc
}

///|
fn ExecutorCoercingMultiplicativeRequest::ExecutorCoercingMultiplicativeRequest(
  left~ : Value,
  right~ : Value,
  operator~ : ExecutorMultiplicativeOperator,
  loc~ : @token.Loc,
) -> ExecutorCoercingMultiplicativeRequest {
  { left, right, operator, loc }
}

///|
fn finish_multiplicative(
  operator : ExecutorMultiplicativeOperator,
  left : Value,
  right : Value,
  _loc : @token.Loc,
  interp? : Interpreter? = None,
) -> Value raise Error {
  let left_number = to_number(left, interp~)
  let right_number = to_number(right, interp~)
  match operator {
    ExecutorMultiplicativeMultiply => Number(left_number * right_number)
    ExecutorMultiplicativeDivide => Number(left_number / right_number)
    ExecutorMultiplicativeRemainder => Number(left_number % right_number)
  }
}

///|
pub fn begin_executor_coercing_multiplicative(
  operator : ExecutorMultiplicativeOperator,
  left : Value,
  right : Value,
  loc : @token.Loc,
) -> ExecutorCoercingMultiplicativeStart raise Error {
  if is_js_object(left) || is_js_object(right) {
    ExecutorCoercingMultiplicativeSuspended(
      ExecutorCoercingMultiplicativeRequest(left~, right~, operator~, loc~),
    )
  } else {
    ExecutorCoercingMultiplicativeCompleted(
      finish_multiplicative(operator, left, right, loc),
    )
  }
}

///|
priv enum ExecutorCoercingMultiplicativePhase {
  ExecutorCoercingMultiplicativeNeedLeft
  ExecutorCoercingMultiplicativeAwaitLeft(ExecutorToPrimitiveOperation)
  ExecutorCoercingMultiplicativeHaveLeft(Double)
  ExecutorCoercingMultiplicativeAwaitRight(Double, ExecutorToPrimitiveOperation)
  ExecutorCoercingMultiplicativeComplete(Value)
}

///|
priv struct ExecutorCoercingMultiplicativeFrame {
  request : ExecutorCoercingMultiplicativeRequest
  mut phase : ExecutorCoercingMultiplicativePhase
}

///|
fn ExecutorCoercingMultiplicativeFrame::ExecutorCoercingMultiplicativeFrame(
  request : ExecutorCoercingMultiplicativeRequest,
) -> ExecutorCoercingMultiplicativeFrame {
  { request, phase: ExecutorCoercingMultiplicativeNeedLeft }
}

///|
fn ExecutorCoercingMultiplicativeFrame::finish_right(
  self : ExecutorCoercingMultiplicativeFrame,
  interp : Interpreter,
  left : Double,
  right : Value,
) -> ExecutorActivationStep raise Error {
  let result = finish_multiplicative(
    self.request.operator,
    Number(left),
    right,
    self.request.loc,
    interp=Some(interp),
  )
  self.phase = ExecutorCoercingMultiplicativeComplete(result)
  ExecutorActivationNormal(result)
}

///|
fn ExecutorCoercingMultiplicativeFrame::step_frame(
  self : ExecutorCoercingMultiplicativeFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorCoercingMultiplicativeNeedLeft => {
      let operation = ExecutorToPrimitiveOperation(
        self.request.left,
        ExecutorToPrimitiveNumber,
        self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          let left_number = to_number(value, interp=Some(interp))
          self.phase = ExecutorCoercingMultiplicativeHaveLeft(left_number)
          self.step_frame(interp)
        }
        step => {
          self.phase = ExecutorCoercingMultiplicativeAwaitLeft(operation)
          step
        }
      }
    }
    ExecutorCoercingMultiplicativeAwaitLeft(operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          let left_number = to_number(value, interp=Some(interp))
          self.phase = ExecutorCoercingMultiplicativeHaveLeft(left_number)
          self.step_frame(interp)
        }
        step => {
          self.phase = ExecutorCoercingMultiplicativeAwaitLeft(operation)
          step
        }
      }
    ExecutorCoercingMultiplicativeHaveLeft(left_number) => {
      let operation = ExecutorToPrimitiveOperation(
        self.request.right,
        ExecutorToPrimitiveNumber,
        self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          self.finish_right(interp, left_number, value)
        step => {
          self.phase = ExecutorCoercingMultiplicativeAwaitRight(
            left_number, operation,
          )
          step
        }
      }
    }
    ExecutorCoercingMultiplicativeAwaitRight(left_number, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          self.finish_right(interp, left_number, value)
        step => {
          self.phase = ExecutorCoercingMultiplicativeAwaitRight(
            left_number, operation,
          )
          step
        }
      }
    ExecutorCoercingMultiplicativeComplete(value) => {
      ignore(value)
      raise @errors.InternalError(
        message="coercing multiplicative frame stepped after completion",
      )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorCoercingMultiplicativeFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for ExecutorCoercingMultiplicativeFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match self.phase {
    ExecutorCoercingMultiplicativeAwaitLeft(operation)
    | ExecutorCoercingMultiplicativeAwaitRight(_, operation) =>
      operation.deliver_activation_completion(completion)
    ExecutorCoercingMultiplicativeNeedLeft
    | ExecutorCoercingMultiplicativeHaveLeft(_)
    | ExecutorCoercingMultiplicativeComplete(_) =>
      raise @errors.InternalError(
        message="coercing multiplicative received an unexpected child completion",
      )
  }
}
