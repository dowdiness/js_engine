///|
// A managed Abstract Relational Comparison operation for <=. The runtime owns
// ToPrimitive(number) ordering and comparison; the VM only transfers values.

///|
pub enum ExecutorCoercingLessThanOrEqualStart {
  ExecutorCoercingLessThanOrEqualCompleted(Value)
  ExecutorCoercingLessThanOrEqualSuspended(
    ExecutorCoercingLessThanOrEqualRequest
  )
}

///|
pub struct ExecutorCoercingLessThanOrEqualRequest {
  priv left : Value
  priv right : Value
  priv loc : @token.Loc
}

///|
fn ExecutorCoercingLessThanOrEqualRequest::ExecutorCoercingLessThanOrEqualRequest(
  left~ : Value,
  right~ : Value,
  loc~ : @token.Loc,
) -> ExecutorCoercingLessThanOrEqualRequest {
  { left, right, loc }
}

///|
pub fn begin_executor_coercing_less_than_or_equal(
  left : Value,
  right : Value,
  loc : @token.Loc,
) -> ExecutorCoercingLessThanOrEqualStart raise Error {
  if is_js_object(left) || is_js_object(right) {
    ExecutorCoercingLessThanOrEqualSuspended(
      ExecutorCoercingLessThanOrEqualRequest(left~, right~, loc~),
    )
  } else {
    ExecutorCoercingLessThanOrEqualCompleted(
      relational_less_than_or_equal_primitives(left, right),
    )
  }
}

///|
priv enum ExecutorCoercingLessThanOrEqualPhase {
  ExecutorCoercingLessThanOrEqualNeedLeft
  ExecutorCoercingLessThanOrEqualAwaitLeft(ExecutorToPrimitiveOperation)
  ExecutorCoercingLessThanOrEqualHaveLeft(Value)
  ExecutorCoercingLessThanOrEqualAwaitRight(Value, ExecutorToPrimitiveOperation)
  ExecutorCoercingLessThanOrEqualComplete(Value)
}

///|
priv struct ExecutorCoercingLessThanOrEqualFrame {
  request : ExecutorCoercingLessThanOrEqualRequest
  mut phase : ExecutorCoercingLessThanOrEqualPhase
}

///|
fn ExecutorCoercingLessThanOrEqualFrame::ExecutorCoercingLessThanOrEqualFrame(
  request : ExecutorCoercingLessThanOrEqualRequest,
) -> ExecutorCoercingLessThanOrEqualFrame {
  { request, phase: ExecutorCoercingLessThanOrEqualNeedLeft }
}

///|
fn ExecutorCoercingLessThanOrEqualFrame::finish_right(
  self : ExecutorCoercingLessThanOrEqualFrame,
  interp : Interpreter,
  left : Value,
  right : Value,
) -> ExecutorActivationStep raise Error {
  let result = relational_less_than_or_equal_primitives(
    left,
    right,
    interp=Some(interp),
  )
  self.phase = ExecutorCoercingLessThanOrEqualComplete(result)
  ExecutorActivationNormal(result)
}

///|
fn ExecutorCoercingLessThanOrEqualFrame::step_frame(
  self : ExecutorCoercingLessThanOrEqualFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorCoercingLessThanOrEqualNeedLeft => {
      let operation = ExecutorToPrimitiveOperation(
        self.request.left,
        ExecutorToPrimitiveNumber,
        self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          self.phase = ExecutorCoercingLessThanOrEqualHaveLeft(value)
          self.step_frame(interp)
        }
        step => {
          self.phase = ExecutorCoercingLessThanOrEqualAwaitLeft(operation)
          step
        }
      }
    }
    ExecutorCoercingLessThanOrEqualAwaitLeft(operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          self.phase = ExecutorCoercingLessThanOrEqualHaveLeft(value)
          self.step_frame(interp)
        }
        step => {
          self.phase = ExecutorCoercingLessThanOrEqualAwaitLeft(operation)
          step
        }
      }
    ExecutorCoercingLessThanOrEqualHaveLeft(left) => {
      let operation = ExecutorToPrimitiveOperation(
        self.request.right,
        ExecutorToPrimitiveNumber,
        self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          self.finish_right(interp, left, value)
        step => {
          self.phase = ExecutorCoercingLessThanOrEqualAwaitRight(
            left, operation,
          )
          step
        }
      }
    }
    ExecutorCoercingLessThanOrEqualAwaitRight(left, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          self.finish_right(interp, left, value)
        step => {
          self.phase = ExecutorCoercingLessThanOrEqualAwaitRight(
            left, operation,
          )
          step
        }
      }
    ExecutorCoercingLessThanOrEqualComplete(value) => {
      ignore(value)
      raise @errors.InternalError(
        message="coercing less-than-or-equal frame stepped after completion",
      )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorCoercingLessThanOrEqualFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for ExecutorCoercingLessThanOrEqualFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match self.phase {
    ExecutorCoercingLessThanOrEqualAwaitLeft(operation)
    | ExecutorCoercingLessThanOrEqualAwaitRight(_, operation) =>
      operation.deliver_activation_completion(completion)
    ExecutorCoercingLessThanOrEqualNeedLeft
    | ExecutorCoercingLessThanOrEqualHaveLeft(_)
    | ExecutorCoercingLessThanOrEqualComplete(_) =>
      raise @errors.InternalError(
        message="coercing less-than-or-equal received an unexpected child completion",
      )
  }
}

///|
// A managed Abstract Relational Comparison operation for plain <. The runtime
// owns ToPrimitive(number) ordering and the canonical less-than result; the VM
// only transfers already-evaluated operands.
pub enum ExecutorCoercingLessThanStart {
  ExecutorCoercingLessThanCompleted(Value)
  ExecutorCoercingLessThanSuspended(ExecutorCoercingLessThanRequest)
}

///|
pub struct ExecutorCoercingLessThanRequest {
  priv left : Value
  priv right : Value
  priv loc : @token.Loc
}

///|
fn ExecutorCoercingLessThanRequest::ExecutorCoercingLessThanRequest(
  left~ : Value,
  right~ : Value,
  loc~ : @token.Loc,
) -> ExecutorCoercingLessThanRequest {
  { left, right, loc }
}

///|
pub fn begin_executor_coercing_less_than(
  left : Value,
  right : Value,
  loc : @token.Loc,
) -> ExecutorCoercingLessThanStart raise Error {
  if is_js_object(left) || is_js_object(right) {
    ExecutorCoercingLessThanSuspended(
      ExecutorCoercingLessThanRequest(left~, right~, loc~),
    )
  } else {
    ExecutorCoercingLessThanCompleted(
      match relational_is_less_than_primitives(left, right) {
        RelationalLess => Bool(true)
        RelationalNotLess | RelationalUnordered => Bool(false)
      },
    )
  }
}

///|
priv enum ExecutorCoercingLessThanPhase {
  ExecutorCoercingLessThanNeedLeft
  ExecutorCoercingLessThanAwaitLeft(ExecutorToPrimitiveOperation)
  ExecutorCoercingLessThanHaveLeft(Value)
  ExecutorCoercingLessThanAwaitRight(Value, ExecutorToPrimitiveOperation)
  ExecutorCoercingLessThanComplete(Value)
}

///|
priv struct ExecutorCoercingLessThanFrame {
  request : ExecutorCoercingLessThanRequest
  mut phase : ExecutorCoercingLessThanPhase
}

///|
fn ExecutorCoercingLessThanFrame::ExecutorCoercingLessThanFrame(
  request : ExecutorCoercingLessThanRequest,
) -> ExecutorCoercingLessThanFrame {
  { request, phase: ExecutorCoercingLessThanNeedLeft }
}

///|
fn ExecutorCoercingLessThanFrame::finish_right(
  self : ExecutorCoercingLessThanFrame,
  interp : Interpreter,
  left : Value,
  right : Value,
) -> ExecutorActivationStep raise Error {
  let result = match
    relational_is_less_than_primitives(left, right, interp=Some(interp)) {
    RelationalLess => Bool(true)
    RelationalNotLess | RelationalUnordered => Bool(false)
  }
  self.phase = ExecutorCoercingLessThanComplete(result)
  ExecutorActivationNormal(result)
}

///|
fn ExecutorCoercingLessThanFrame::step_frame(
  self : ExecutorCoercingLessThanFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorCoercingLessThanNeedLeft => {
      let operation = ExecutorToPrimitiveOperation(
        self.request.left,
        ExecutorToPrimitiveNumber,
        self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          self.phase = ExecutorCoercingLessThanHaveLeft(value)
          self.step_frame(interp)
        }
        step => {
          self.phase = ExecutorCoercingLessThanAwaitLeft(operation)
          step
        }
      }
    }
    ExecutorCoercingLessThanAwaitLeft(operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          self.phase = ExecutorCoercingLessThanHaveLeft(value)
          self.step_frame(interp)
        }
        step => {
          self.phase = ExecutorCoercingLessThanAwaitLeft(operation)
          step
        }
      }
    ExecutorCoercingLessThanHaveLeft(left) => {
      let operation = ExecutorToPrimitiveOperation(
        self.request.right,
        ExecutorToPrimitiveNumber,
        self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          self.finish_right(interp, left, value)
        step => {
          self.phase = ExecutorCoercingLessThanAwaitRight(left, operation)
          step
        }
      }
    }
    ExecutorCoercingLessThanAwaitRight(left, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          self.finish_right(interp, left, value)
        step => {
          self.phase = ExecutorCoercingLessThanAwaitRight(left, operation)
          step
        }
      }
    ExecutorCoercingLessThanComplete(value) => {
      ignore(value)
      raise @errors.InternalError(
        message="coercing less-than frame stepped after completion",
      )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorCoercingLessThanFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for ExecutorCoercingLessThanFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match self.phase {
    ExecutorCoercingLessThanAwaitLeft(operation)
    | ExecutorCoercingLessThanAwaitRight(_, operation) =>
      operation.deliver_activation_completion(completion)
    ExecutorCoercingLessThanNeedLeft
    | ExecutorCoercingLessThanHaveLeft(_)
    | ExecutorCoercingLessThanComplete(_) =>
      raise @errors.InternalError(
        message="coercing less-than received an unexpected child completion",
      )
  }
}
