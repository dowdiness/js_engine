///|
// ToPrimitive is a runtime-owned child operation.  Its state is deliberately
// independent of any executor frame so property updates and coercing addition
// share the same lookup/call/fallback pipeline.
priv enum ExecutorToPrimitiveHint {
  ExecutorToPrimitiveDefault
  ExecutorToPrimitiveNumber
}

///|
fn executor_to_primitive_hint_string(hint : ExecutorToPrimitiveHint) -> String {
  match hint {
    ExecutorToPrimitiveDefault => "default"
    ExecutorToPrimitiveNumber => "number"
  }
}

///|
priv enum ExecutorToPrimitivePhase {
  ExecutorToPrimitiveNeedInput(Value)
  ExecutorToPrimitiveAwaitToPrimitiveLookup(Value)
  ExecutorToPrimitiveHaveToPrimitiveMethod(Value, Value)
  ExecutorToPrimitiveAwaitToPrimitiveCall
  ExecutorToPrimitiveHaveToPrimitiveResult(Value)
  ExecutorToPrimitiveAwaitValueOfLookup(Value)
  ExecutorToPrimitiveHaveValueOfMethod(Value, Value)
  ExecutorToPrimitiveAwaitValueOfCall(Value)
  ExecutorToPrimitiveHaveValueOfResult(Value, Value)
  ExecutorToPrimitiveAwaitToStringLookup(Value)
  ExecutorToPrimitiveHaveToStringMethod(Value, Value)
  ExecutorToPrimitiveAwaitToStringCall
  ExecutorToPrimitiveHaveToStringResult(Value)
  ExecutorToPrimitiveComplete(Value)
}

///|
priv struct ExecutorToPrimitiveOperation {
  hint : ExecutorToPrimitiveHint
  loc : @token.Loc
  mut phase : ExecutorToPrimitivePhase
}

///|
fn ExecutorToPrimitiveOperation::ExecutorToPrimitiveOperation(
  input : Value,
  hint : ExecutorToPrimitiveHint,
  loc : @token.Loc,
) -> ExecutorToPrimitiveOperation {
  { hint, loc, phase: ExecutorToPrimitiveNeedInput(input) }
}

///|
fn ExecutorToPrimitiveOperation::begin_to_string_lookup(
  self : ExecutorToPrimitiveOperation,
  current : Value,
) -> ExecutorActivationStep {
  self.phase = ExecutorToPrimitiveAwaitToStringLookup(current)
  executor_activation_managed_property_get(current, "toString", self.loc)
}

///|
fn ExecutorToPrimitiveOperation::step(
  self : ExecutorToPrimitiveOperation,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorToPrimitiveNeedInput(input) =>
      if is_js_object(input) {
        let to_primitive = interp.realm_state.well_known_symbols.to_primitive
        self.phase = ExecutorToPrimitiveAwaitToPrimitiveLookup(input)
        executor_activation_symbol_property_get(input, to_primitive, self.loc)
      } else {
        self.phase = ExecutorToPrimitiveComplete(input)
        ExecutorActivationNormal(input)
      }
    ExecutorToPrimitiveHaveToPrimitiveMethod(current, to_primitive) =>
      match to_primitive {
        Undefined | Null => {
          self.phase = ExecutorToPrimitiveAwaitValueOfLookup(current)
          executor_activation_managed_property_get(current, "valueOf", self.loc)
        }
        _ if is_callable(to_primitive) => {
          self.phase = ExecutorToPrimitiveAwaitToPrimitiveCall
          ExecutorActivationCall(
            ExecutorCallRequest(
              callee=to_primitive,
              this_value=current,
              args=[String_(executor_to_primitive_hint_string(self.hint))],
              loc=self.loc,
            ),
          )
        }
        _ =>
          raise @errors.TypeError(
            message="Symbol.toPrimitive is not a function",
          )
      }
    ExecutorToPrimitiveHaveToPrimitiveResult(result) =>
      if is_js_object(result) {
        raise @errors.TypeError(
          message="Cannot convert object to primitive value",
        )
      } else {
        self.phase = ExecutorToPrimitiveComplete(result)
        ExecutorActivationNormal(result)
      }
    ExecutorToPrimitiveHaveValueOfMethod(current, value_of) =>
      if is_callable(value_of) {
        self.phase = ExecutorToPrimitiveAwaitValueOfCall(current)
        ExecutorActivationCall(
          ExecutorCallRequest(
            callee=value_of,
            this_value=current,
            args=[],
            loc=self.loc,
          ),
        )
      } else {
        self.begin_to_string_lookup(current)
      }
    ExecutorToPrimitiveHaveValueOfResult(current, value_of_result) =>
      if is_js_object(value_of_result) {
        self.begin_to_string_lookup(current)
      } else {
        self.phase = ExecutorToPrimitiveComplete(value_of_result)
        ExecutorActivationNormal(value_of_result)
      }
    ExecutorToPrimitiveHaveToStringMethod(current, to_string) =>
      if is_callable(to_string) {
        self.phase = ExecutorToPrimitiveAwaitToStringCall
        ExecutorActivationCall(
          ExecutorCallRequest(
            callee=to_string,
            this_value=current,
            args=[],
            loc=self.loc,
          ),
        )
      } else {
        raise @errors.TypeError(
          message="Cannot convert object to primitive value",
        )
      }
    ExecutorToPrimitiveHaveToStringResult(result) =>
      if is_js_object(result) {
        raise @errors.TypeError(
          message="Cannot convert object to primitive value",
        )
      } else {
        self.phase = ExecutorToPrimitiveComplete(result)
        ExecutorActivationNormal(result)
      }
    ExecutorToPrimitiveComplete(value) => {
      ignore(value)
      raise @errors.InternalError(
        message="ToPrimitive operation stepped after completion",
      )
    }
    ExecutorToPrimitiveAwaitToPrimitiveLookup(_)
    | ExecutorToPrimitiveAwaitToPrimitiveCall
    | ExecutorToPrimitiveAwaitValueOfLookup(_)
    | ExecutorToPrimitiveAwaitValueOfCall(_)
    | ExecutorToPrimitiveAwaitToStringLookup(_)
    | ExecutorToPrimitiveAwaitToStringCall =>
      raise @errors.InternalError(
        message="ToPrimitive operation stepped while awaiting a child completion",
      )
  }
}

///|
fn ExecutorToPrimitiveOperation::deliver_activation_completion(
  self : ExecutorToPrimitiveOperation,
  completion : ExecutorActivationCompletion,
) -> Unit raise Error {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorToPrimitiveAwaitToPrimitiveLookup(current) =>
          self.phase = ExecutorToPrimitiveHaveToPrimitiveMethod(current, value)
        ExecutorToPrimitiveAwaitToPrimitiveCall =>
          self.phase = ExecutorToPrimitiveHaveToPrimitiveResult(value)
        ExecutorToPrimitiveAwaitValueOfLookup(current) =>
          self.phase = ExecutorToPrimitiveHaveValueOfMethod(current, value)
        ExecutorToPrimitiveAwaitValueOfCall(current) =>
          self.phase = ExecutorToPrimitiveHaveValueOfResult(current, value)
        ExecutorToPrimitiveAwaitToStringLookup(current) =>
          self.phase = ExecutorToPrimitiveHaveToStringMethod(current, value)
        ExecutorToPrimitiveAwaitToStringCall =>
          self.phase = ExecutorToPrimitiveHaveToStringResult(value)
        ExecutorToPrimitiveNeedInput(_)
        | ExecutorToPrimitiveHaveToPrimitiveMethod(_, _)
        | ExecutorToPrimitiveHaveToPrimitiveResult(_)
        | ExecutorToPrimitiveHaveValueOfMethod(_, _)
        | ExecutorToPrimitiveHaveValueOfResult(_, _)
        | ExecutorToPrimitiveHaveToStringMethod(_, _)
        | ExecutorToPrimitiveHaveToStringResult(_)
        | ExecutorToPrimitiveComplete(_) =>
          raise @errors.InternalError(
            message="ToPrimitive operation received an unexpected child completion",
          )
      }
  }
}

///|
fn finish_primitive_addition(
  interp : Interpreter?,
  left : Value,
  right : Value,
  _loc : @token.Loc,
) -> Value raise Error {
  match (left, right) {
    (String_(a), String_(b)) => String_(a + b)
    (String_(a), b) => String_(a + to_js_string(b, interp~))
    (a, String_(b)) => String_(to_js_string(a, interp~) + b)
    (a, b) => Number(to_number(a, interp~) + to_number(b, interp~))
  }
}

///|
priv enum ExecutorCoercingAdditionPhase {
  ExecutorCoercingAdditionNeedLeft
  ExecutorCoercingAdditionAwaitLeft(ExecutorToPrimitiveOperation)
  ExecutorCoercingAdditionHaveLeft(Value)
  ExecutorCoercingAdditionAwaitRight(Value, ExecutorToPrimitiveOperation)
  ExecutorCoercingAdditionComplete(Value)
}

///|
priv struct ExecutorCoercingAdditionFrame {
  request : ExecutorCoercingAdditionRequest
  mut phase : ExecutorCoercingAdditionPhase
}

///|
fn ExecutorCoercingAdditionFrame::ExecutorCoercingAdditionFrame(
  request : ExecutorCoercingAdditionRequest,
) -> ExecutorCoercingAdditionFrame {
  { request, phase: ExecutorCoercingAdditionNeedLeft }
}

///|
fn ExecutorCoercingAdditionFrame::step_frame(
  self : ExecutorCoercingAdditionFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorCoercingAdditionNeedLeft => {
      let operation = ExecutorToPrimitiveOperation(
        self.request.left,
        ExecutorToPrimitiveDefault,
        self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          self.phase = ExecutorCoercingAdditionHaveLeft(value)
          self.step_frame(interp)
        }
        step => {
          self.phase = ExecutorCoercingAdditionAwaitLeft(operation)
          step
        }
      }
    }
    ExecutorCoercingAdditionAwaitLeft(operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          self.phase = ExecutorCoercingAdditionHaveLeft(value)
          self.step_frame(interp)
        }
        step => {
          self.phase = ExecutorCoercingAdditionAwaitLeft(operation)
          step
        }
      }
    ExecutorCoercingAdditionHaveLeft(left) => {
      let operation = ExecutorToPrimitiveOperation(
        self.request.right,
        ExecutorToPrimitiveDefault,
        self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(right) => {
          let result = finish_primitive_addition(
            Some(interp),
            left,
            right,
            self.request.loc,
          )
          self.phase = ExecutorCoercingAdditionComplete(result)
          ExecutorActivationNormal(result)
        }
        step => {
          self.phase = ExecutorCoercingAdditionAwaitRight(left, operation)
          step
        }
      }
    }
    ExecutorCoercingAdditionAwaitRight(left, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(right) => {
          let result = finish_primitive_addition(
            Some(interp),
            left,
            right,
            self.request.loc,
          )
          self.phase = ExecutorCoercingAdditionComplete(result)
          ExecutorActivationNormal(result)
        }
        step => {
          self.phase = ExecutorCoercingAdditionAwaitRight(left, operation)
          step
        }
      }
    ExecutorCoercingAdditionComplete(value) => {
      ignore(value)
      raise @errors.InternalError(
        message="coercing addition frame stepped after completion",
      )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorCoercingAdditionFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for ExecutorCoercingAdditionFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match self.phase {
    ExecutorCoercingAdditionAwaitLeft(operation) =>
      operation.deliver_activation_completion(completion)
    ExecutorCoercingAdditionAwaitRight(_, operation) =>
      operation.deliver_activation_completion(completion)
    ExecutorCoercingAdditionNeedLeft
    | ExecutorCoercingAdditionHaveLeft(_)
    | ExecutorCoercingAdditionComplete(_) =>
      raise @errors.InternalError(
        message="coercing addition received an unexpected child completion",
      )
  }
}
