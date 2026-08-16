///|
// ToPrimitive is a runtime-owned child operation.  Its state is deliberately
// independent of any executor frame so property updates and coercing addition
// share the same lookup/call/fallback pipeline.
priv enum ExecutorToPrimitiveHint {
  ExecutorToPrimitiveDefault
  ExecutorToPrimitiveNumber
  ExecutorToPrimitiveString
}

///|
fn executor_to_primitive_hint_string(hint : ExecutorToPrimitiveHint) -> String {
  match hint {
    ExecutorToPrimitiveDefault => "default"
    ExecutorToPrimitiveNumber => "number"
    ExecutorToPrimitiveString => "string"
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
  ExecutorToPrimitiveAwaitToStringCall(Value)
  ExecutorToPrimitiveHaveToStringResult(Value, Value)
  ExecutorToPrimitiveComplete(Value)
}

///|
priv struct ExecutorToPrimitiveOperation {
  hint : ExecutorToPrimitiveHint
  loc : @token.Loc
  mut tried_value_of : Bool
  mut phase : ExecutorToPrimitivePhase
}

///|
fn ExecutorToPrimitiveOperation::ExecutorToPrimitiveOperation(
  input : Value,
  hint : ExecutorToPrimitiveHint,
  loc : @token.Loc,
) -> ExecutorToPrimitiveOperation {
  {
    hint,
    loc,
    tried_value_of: false,
    phase: ExecutorToPrimitiveNeedInput(input),
  }
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
        Undefined | Null =>
          match self.hint {
            ExecutorToPrimitiveString => self.begin_to_string_lookup(current)
            ExecutorToPrimitiveDefault | ExecutorToPrimitiveNumber => {
              self.tried_value_of = true
              self.phase = ExecutorToPrimitiveAwaitValueOfLookup(current)
              executor_activation_managed_property_get(
                current,
                "valueOf",
                self.loc,
              )
            }
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
      } else if self.hint is ExecutorToPrimitiveString {
        raise @errors.TypeError(
          message="Cannot convert object to primitive value",
        )
      } else {
        self.tried_value_of = true
        self.begin_to_string_lookup(current)
      }
    ExecutorToPrimitiveHaveValueOfResult(current, value_of_result) =>
      if is_js_object(value_of_result) {
        if self.hint is ExecutorToPrimitiveString {
          raise @errors.TypeError(
            message="Cannot convert object to primitive value",
          )
        } else {
          self.tried_value_of = true
          self.begin_to_string_lookup(current)
        }
      } else {
        self.phase = ExecutorToPrimitiveComplete(value_of_result)
        ExecutorActivationNormal(value_of_result)
      }
    ExecutorToPrimitiveHaveToStringMethod(current, to_string) =>
      if is_callable(to_string) {
        self.phase = ExecutorToPrimitiveAwaitToStringCall(current)
        ExecutorActivationCall(
          ExecutorCallRequest(
            callee=to_string,
            this_value=current,
            args=[],
            loc=self.loc,
          ),
        )
      } else if self.hint is ExecutorToPrimitiveString && !self.tried_value_of {
        self.tried_value_of = true
        self.phase = ExecutorToPrimitiveAwaitValueOfLookup(current)
        executor_activation_managed_property_get(current, "valueOf", self.loc)
      } else {
        raise @errors.TypeError(
          message="Cannot convert object to primitive value",
        )
      }
    ExecutorToPrimitiveHaveToStringResult(current, result) =>
      if is_js_object(result) {
        if self.hint is ExecutorToPrimitiveString && !self.tried_value_of {
          self.tried_value_of = true
          self.phase = ExecutorToPrimitiveAwaitValueOfLookup(current)
          executor_activation_managed_property_get(current, "valueOf", self.loc)
        } else {
          raise @errors.TypeError(
            message="Cannot convert object to primitive value",
          )
        }
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
    | ExecutorToPrimitiveAwaitToStringCall(_) =>
      raise @errors.InternalError(
        message="ToPrimitive operation stepped while awaiting a child completion",
      )
  }
}

///|
// ToPropertyKey is kept as a runtime child operation so computed deletion
// never performs guest-capable key conversion from the VM.  The operation
// deliberately returns Symbols unchanged and applies ToString only after the
// String-hint ToPrimitive result is known to be non-Symbol.
priv enum ExecutorToPropertyKeyPhase {
  ExecutorToPropertyKeyNeedInput(Value)
  ExecutorToPropertyKeyAwaitToPrimitive(ExecutorToPrimitiveOperation)
  ExecutorToPropertyKeyComplete(Value)
}

///|
priv struct ExecutorToPropertyKeyOperation {
  loc : @token.Loc
  mut phase : ExecutorToPropertyKeyPhase
}

///|
fn ExecutorToPropertyKeyOperation::ExecutorToPropertyKeyOperation(
  input : Value,
  loc : @token.Loc,
) -> ExecutorToPropertyKeyOperation {
  { loc, phase: ExecutorToPropertyKeyNeedInput(input) }
}

///|
fn finish_executor_to_property_key(
  value : Value,
  interp : Interpreter,
) -> Value raise Error {
  match value {
    Symbol(_) => value
    _ => String_(to_js_string(value, interp=Some(interp)))
  }
}

///|
fn ExecutorToPropertyKeyOperation::step(
  self : ExecutorToPropertyKeyOperation,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorToPropertyKeyNeedInput(input) =>
      match input {
        Symbol(_) => {
          self.phase = ExecutorToPropertyKeyComplete(input)
          ExecutorActivationNormal(input)
        }
        _ if is_js_object(input) => {
          let operation = ExecutorToPrimitiveOperation(
            input,
            ExecutorToPrimitiveString,
            self.loc,
          )
          match operation.step(interp) {
            ExecutorActivationNormal(value) => {
              let key = finish_executor_to_property_key(value, interp)
              self.phase = ExecutorToPropertyKeyComplete(key)
              ExecutorActivationNormal(key)
            }
            step => {
              self.phase = ExecutorToPropertyKeyAwaitToPrimitive(operation)
              step
            }
          }
        }
        _ => {
          let key = finish_executor_to_property_key(input, interp)
          self.phase = ExecutorToPropertyKeyComplete(key)
          ExecutorActivationNormal(key)
        }
      }
    ExecutorToPropertyKeyAwaitToPrimitive(operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          let key = finish_executor_to_property_key(value, interp)
          self.phase = ExecutorToPropertyKeyComplete(key)
          ExecutorActivationNormal(key)
        }
        step => {
          self.phase = ExecutorToPropertyKeyAwaitToPrimitive(operation)
          step
        }
      }
    ExecutorToPropertyKeyComplete(value) => {
      ignore(value)
      raise @errors.InternalError(
        message="ToPropertyKey operation stepped after completion",
      )
    }
  }
}

///|
fn ExecutorToPropertyKeyOperation::deliver_activation_completion(
  self : ExecutorToPropertyKeyOperation,
  completion : ExecutorActivationCompletion,
) -> Unit raise Error {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorToPropertyKeyAwaitToPrimitive(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorToPropertyKeyNeedInput(_) | ExecutorToPropertyKeyComplete(_) =>
          raise @errors.InternalError(
            message="ToPropertyKey received an unexpected child completion",
          )
      }
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
        ExecutorToPrimitiveAwaitToStringCall(current) =>
          self.phase = ExecutorToPrimitiveHaveToStringResult(current, value)
        ExecutorToPrimitiveNeedInput(_)
        | ExecutorToPrimitiveHaveToPrimitiveMethod(_, _)
        | ExecutorToPrimitiveHaveToPrimitiveResult(_)
        | ExecutorToPrimitiveHaveValueOfMethod(_, _)
        | ExecutorToPrimitiveHaveValueOfResult(_, _)
        | ExecutorToPrimitiveHaveToStringMethod(_, _)
        | ExecutorToPrimitiveHaveToStringResult(_, _)
        | ExecutorToPrimitiveComplete(_) =>
          raise @errors.InternalError(
            message="ToPrimitive operation received an unexpected child completion",
          )
      }
  }
}

///|
// The synchronous boundary is decided by runtime-owned value semantics. A
// primitive pair can finish without entering the activation coordinator;
// object-like operands still use the resumable request below so every
// conversion hook follows the managed guest-entry path.
pub enum ExecutorCoercingAdditionStart {
  ExecutorCoercingAdditionCompleted(Value)
  ExecutorCoercingAdditionSuspended(ExecutorCoercingAdditionRequest)
}

///|
pub fn begin_executor_coercing_addition(
  left : Value,
  right : Value,
  loc : @token.Loc,
) -> ExecutorCoercingAdditionStart raise Error {
  if is_js_object(left) || is_js_object(right) {
    ExecutorCoercingAdditionSuspended(
      ExecutorCoercingAdditionRequest(left~, right~, loc~),
    )
  } else {
    ExecutorCoercingAdditionCompleted(
      finish_primitive_addition(None, left, right, loc),
    )
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
