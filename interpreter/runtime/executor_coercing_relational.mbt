///|
// A managed Abstract Relational Comparison operation. The runtime owns the
// source-order ToPrimitive(number) sequence and the canonical IsLessThan
// result; the VM only transfers already-evaluated operands.

///|
pub(all) enum ExecutorRelationalOperator {
  ExecutorRelationalLessThan
  ExecutorRelationalGreaterThan
  ExecutorRelationalGreaterThanOrEqual
  ExecutorRelationalLessThanOrEqual
}

///|
pub enum ExecutorCoercingRelationalStart {
  ExecutorCoercingRelationalCompleted(Value)
  ExecutorCoercingRelationalSuspended(ExecutorCoercingRelationalRequest)
}

///|
pub struct ExecutorCoercingRelationalRequest {
  priv left : Value
  priv right : Value
  priv operator : ExecutorRelationalOperator
  priv loc : @token.Loc
}

///|
fn ExecutorCoercingRelationalRequest::ExecutorCoercingRelationalRequest(
  left~ : Value,
  right~ : Value,
  operator~ : ExecutorRelationalOperator,
  loc~ : @token.Loc,
) -> ExecutorCoercingRelationalRequest {
  { left, right, operator, loc }
}

///|
fn executor_relational_primitive_result(
  operator : ExecutorRelationalOperator,
  left : Value,
  right : Value,
  interp? : Interpreter? = None,
) -> Value raise Error {
  let comparison = match operator {
    ExecutorRelationalLessThan | ExecutorRelationalGreaterThanOrEqual =>
      relational_is_less_than_primitives(left, right, interp~)
    ExecutorRelationalGreaterThan | ExecutorRelationalLessThanOrEqual =>
      relational_is_less_than_primitives(right, left, interp~)
  }
  match (operator, comparison) {
    (ExecutorRelationalLessThan, RelationalLess)
    | (ExecutorRelationalGreaterThan, RelationalLess)
    | (ExecutorRelationalGreaterThanOrEqual, RelationalNotLess)
    | (ExecutorRelationalLessThanOrEqual, RelationalNotLess) => Bool(true)
    _ => Bool(false)
  }
}

///|
pub fn begin_executor_coercing_relational(
  left : Value,
  right : Value,
  loc : @token.Loc,
  operator : ExecutorRelationalOperator,
) -> ExecutorCoercingRelationalStart raise Error {
  if is_js_object(left) || is_js_object(right) {
    ExecutorCoercingRelationalSuspended(
      ExecutorCoercingRelationalRequest(left~, right~, operator~, loc~),
    )
  } else {
    ExecutorCoercingRelationalCompleted(
      executor_relational_primitive_result(operator, left, right),
    )
  }
}

///|
priv enum ExecutorCoercingRelationalPhase {
  ExecutorCoercingRelationalNeedLeft
  ExecutorCoercingRelationalAwaitLeft(ExecutorToPrimitiveOperation)
  ExecutorCoercingRelationalHaveLeft(Value)
  ExecutorCoercingRelationalAwaitRight(Value, ExecutorToPrimitiveOperation)
  ExecutorCoercingRelationalComplete(Value)
}

///|
priv struct ExecutorCoercingRelationalFrame {
  request : ExecutorCoercingRelationalRequest
  mut phase : ExecutorCoercingRelationalPhase
}

///|
fn ExecutorCoercingRelationalFrame::ExecutorCoercingRelationalFrame(
  request : ExecutorCoercingRelationalRequest,
) -> ExecutorCoercingRelationalFrame {
  { request, phase: ExecutorCoercingRelationalNeedLeft }
}

///|
fn ExecutorCoercingRelationalFrame::finish_right(
  self : ExecutorCoercingRelationalFrame,
  interp : Interpreter,
  left : Value,
  right : Value,
) -> ExecutorActivationStep raise Error {
  let result = executor_relational_primitive_result(
    self.request.operator,
    left,
    right,
    interp=Some(interp),
  )
  self.phase = ExecutorCoercingRelationalComplete(result)
  ExecutorActivationNormal(result)
}

///|
fn ExecutorCoercingRelationalFrame::step_frame(
  self : ExecutorCoercingRelationalFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorCoercingRelationalNeedLeft => {
      let operation = ExecutorToPrimitiveOperation(
        self.request.left,
        ExecutorToPrimitiveNumber,
        self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          self.phase = ExecutorCoercingRelationalHaveLeft(value)
          self.step_frame(interp)
        }
        step => {
          self.phase = ExecutorCoercingRelationalAwaitLeft(operation)
          step
        }
      }
    }
    ExecutorCoercingRelationalAwaitLeft(operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          self.phase = ExecutorCoercingRelationalHaveLeft(value)
          self.step_frame(interp)
        }
        step => {
          self.phase = ExecutorCoercingRelationalAwaitLeft(operation)
          step
        }
      }
    ExecutorCoercingRelationalHaveLeft(left) => {
      let operation = ExecutorToPrimitiveOperation(
        self.request.right,
        ExecutorToPrimitiveNumber,
        self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          self.finish_right(interp, left, value)
        step => {
          self.phase = ExecutorCoercingRelationalAwaitRight(left, operation)
          step
        }
      }
    }
    ExecutorCoercingRelationalAwaitRight(left, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          self.finish_right(interp, left, value)
        step => {
          self.phase = ExecutorCoercingRelationalAwaitRight(left, operation)
          step
        }
      }
    ExecutorCoercingRelationalComplete(value) => {
      ignore(value)
      raise @errors.InternalError(
        message="coercing relational frame stepped after completion",
      )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorCoercingRelationalFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for ExecutorCoercingRelationalFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match self.phase {
    ExecutorCoercingRelationalAwaitLeft(operation)
    | ExecutorCoercingRelationalAwaitRight(_, operation) =>
      operation.deliver_activation_completion(completion)
    ExecutorCoercingRelationalNeedLeft
    | ExecutorCoercingRelationalHaveLeft(_)
    | ExecutorCoercingRelationalComplete(_) =>
      raise @errors.InternalError(
        message="coercing relational received an unexpected child completion",
      )
  }
}

///|
// This narrow start/request wrapper preserves the existing <= runtime seam for
// focused tests while delegating execution to the shared relational operation.
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
  match
    begin_executor_coercing_relational(
      left,
      right,
      loc,
      ExecutorRelationalLessThanOrEqual,
    ) {
    ExecutorCoercingRelationalCompleted(value) =>
      ExecutorCoercingLessThanOrEqualCompleted(value)
    ExecutorCoercingRelationalSuspended(request) =>
      ExecutorCoercingLessThanOrEqualSuspended(
        ExecutorCoercingLessThanOrEqualRequest(
          left=request.left,
          right=request.right,
          loc=request.loc,
        ),
      )
  }
}

///|
fn executor_coercing_relational_request_from_less_than_or_equal(
  request : ExecutorCoercingLessThanOrEqualRequest,
) -> ExecutorCoercingRelationalRequest {
  ExecutorCoercingRelationalRequest(
    left=request.left,
    right=request.right,
    operator=ExecutorRelationalLessThanOrEqual,
    loc=request.loc,
  )
}
