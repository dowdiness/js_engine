///|
// Array.prototype.forEach is the first callback-bearing Array method whose
// loop is owned by the runtime activation coordinator. The frame keeps the
// observable algorithm state here; the executor only supplies the ordinary
// call request that selected this exact intrinsic.

///|
priv struct ExecutorArrayForEachRequest {
  this_value : Value
  args : Array[Value]
  loc : @token.Loc
}

///|
fn ExecutorArrayForEachRequest::ExecutorArrayForEachRequest(
  this_value~ : Value,
  args~ : Array[Value],
  loc~ : @token.Loc,
) -> ExecutorArrayForEachRequest {
  { this_value, args: args.copy(), loc }
}

///|
// The setup-time realm capability is used only as an identity witness. No
// property lookup or name admission is performed on the call operand, so a
// replacement, sibling, or user-created "forEach" is excluded.
fn executor_array_for_each_identity_matches(
  interp : Interpreter,
  callee : Value,
) -> Bool {
  let intrinsic = interp.realm_state.canonical_array_for_each.val
  match (intrinsic, callee) {
    (Some(Object(expected)), Object(actual)) => physical_equal(expected, actual)
    _ => false
  }
}

///|
fn executor_array_for_each_request(
  interp : Interpreter,
  callee : Value,
  this_value : Value,
  args : Array[Value],
  loc : @token.Loc,
) -> ExecutorArrayForEachRequest? {
  guard executor_array_for_each_identity_matches(interp, callee) else {
    return None
  }
  Some(ExecutorArrayForEachRequest(this_value~, args~, loc~))
}

///|
priv enum ExecutorArrayForEachPhase {
  ExecutorArrayForEachNeedObject
  ExecutorArrayForEachAwaitLength(Value)
  ExecutorArrayForEachHaveLengthValue(Value, Value)
  ExecutorArrayForEachAwaitLengthPrimitive(Value, ExecutorToPrimitiveOperation)
  ExecutorArrayForEachNeedCallback(Value, Int64)
  ExecutorArrayForEachNeedIndex(Value, Int64, Value, Int64)
  ExecutorArrayForEachAwaitHasProperty(
    Value,
    Int64,
    Value,
    Int64,
    ExecutorDeleteHasPropertyOperation
  )
  ExecutorArrayForEachAwaitGet(Value, Int64, Value, Int64)
  ExecutorArrayForEachHaveGetValue(Value, Int64, Value, Int64, Value)
  ExecutorArrayForEachAwaitCallback(Value, Int64, Value, Int64)
  ExecutorArrayForEachComplete
}

///|
priv struct ExecutorArrayForEachFrame {
  request : ExecutorArrayForEachRequest
  mut phase : ExecutorArrayForEachPhase
}

///|
fn ExecutorArrayForEachFrame::ExecutorArrayForEachFrame(
  request : ExecutorArrayForEachRequest,
) -> ExecutorArrayForEachFrame {
  { request, phase: ExecutorArrayForEachNeedObject }
}

///|
fn executor_array_for_each_length(
  value : Value,
  interp : Interpreter,
) -> Int64 raise Error {
  to_length_from_value(Some(value), interp=Some(interp))
}

///|
fn ExecutorArrayForEachFrame::begin_length_value(
  self : ExecutorArrayForEachFrame,
  object : Value,
  value : Value,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  if is_js_object(value) {
    let operation = ExecutorToPrimitiveOperation(
      value,
      ExecutorToPrimitiveNumber,
      self.request.loc,
    )
    match operation.step(interp) {
      ExecutorActivationNormal(primitive) => {
        self.phase = ExecutorArrayForEachNeedCallback(
          object,
          executor_array_for_each_length(primitive, interp),
        )
        self.step_frame(interp)
      }
      step => {
        self.phase = ExecutorArrayForEachAwaitLengthPrimitive(object, operation)
        step
      }
    }
  } else {
    self.phase = ExecutorArrayForEachNeedCallback(
      object,
      executor_array_for_each_length(value, interp),
    )
    self.step_frame(interp)
  }
}

///|
fn ExecutorArrayForEachFrame::finish_has_property(
  self : ExecutorArrayForEachFrame,
  object : Value,
  length : Int64,
  callback : Value,
  index : Int64,
  has_property : Bool,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  if has_property {
    self.phase = ExecutorArrayForEachAwaitGet(object, length, callback, index)
    executor_activation_managed_property_get(
      object,
      index.to_string(),
      self.request.loc,
    )
  } else {
    self.phase = ExecutorArrayForEachNeedIndex(
      object,
      length,
      callback,
      index + 1L,
    )
    self.step_frame(interp)
  }
}

///|
fn ExecutorArrayForEachFrame::step_frame(
  self : ExecutorArrayForEachFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorArrayForEachNeedObject => {
      match self.request.this_value {
        Null | Undefined =>
          raise @errors.TypeError(
            message="Cannot convert undefined or null to object",
          )
        _ => ()
      }
      let object = box_primitive_call_this(
        self.request.this_value,
        interp.realm_state,
      )
      self.phase = ExecutorArrayForEachAwaitLength(object)
      executor_activation_managed_property_get(
        object,
        "length",
        self.request.loc,
      )
    }
    ExecutorArrayForEachAwaitLength(_) =>
      raise @errors.InternalError(
        message="forEach frame stepped while awaiting length",
      )
    ExecutorArrayForEachHaveLengthValue(object, value) =>
      self.begin_length_value(object, value, interp)
    ExecutorArrayForEachAwaitLengthPrimitive(object, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(primitive) => {
          self.phase = ExecutorArrayForEachNeedCallback(
            object,
            executor_array_for_each_length(primitive, interp),
          )
          self.step_frame(interp)
        }
        step => {
          self.phase = ExecutorArrayForEachAwaitLengthPrimitive(
            object, operation,
          )
          step
        }
      }
    ExecutorArrayForEachNeedCallback(object, length) => {
      let callback = if self.request.args.length() > 0 {
        self.request.args[0]
      } else {
        Undefined
      }
      guard is_callable(callback) else {
        raise @errors.TypeError(
          message=to_js_string(callback, interp=Some(interp)) +
            " is not a function",
        )
      }
      self.phase = ExecutorArrayForEachNeedIndex(object, length, callback, 0L)
      self.step_frame(interp)
    }
    ExecutorArrayForEachNeedIndex(object, length, callback, index) =>
      if index >= length {
        self.phase = ExecutorArrayForEachComplete
        ExecutorActivationNormal(Undefined)
      } else {
        // This is the sole loop-progress observation for this k. It happens
        // before HasProperty and is not repeated when a child suspends.
        interp.observe_execution_step()
        let operation = ExecutorDeleteHasPropertyOperation(
          target=object,
          key=String_(index.to_string()),
          loc=self.request.loc,
        )
        match operation.step(interp) {
          ExecutorActivationNormal(Bool(has_property)) =>
            self.finish_has_property(
              object, length, callback, index, has_property, interp,
            )
          step => {
            self.phase = ExecutorArrayForEachAwaitHasProperty(
              object, length, callback, index, operation,
            )
            step
          }
        }
      }
    ExecutorArrayForEachAwaitHasProperty(
      object,
      length,
      callback,
      index,
      operation
    ) =>
      match operation.step(interp) {
        ExecutorActivationNormal(Bool(has_property)) =>
          self.finish_has_property(
            object, length, callback, index, has_property, interp,
          )
        step => {
          self.phase = ExecutorArrayForEachAwaitHasProperty(
            object, length, callback, index, operation,
          )
          step
        }
      }
    ExecutorArrayForEachAwaitGet(_, _, _, _) =>
      raise @errors.InternalError(
        message="forEach frame stepped while awaiting Get",
      )
    ExecutorArrayForEachHaveGetValue(object, length, callback, index, value) => {
      let this_arg = if self.request.args.length() > 1 {
        self.request.args[1]
      } else {
        Undefined
      }
      self.phase = ExecutorArrayForEachAwaitCallback(
        object, length, callback, index,
      )
      ExecutorActivationCall(
        ExecutorCallRequest(
          callee=callback,
          this_value=this_arg,
          args=[value, Number(index.to_double()), object],
          loc=self.request.loc,
        ),
      )
    }
    ExecutorArrayForEachAwaitCallback(_, _, _, _) =>
      raise @errors.InternalError(
        message="forEach frame stepped while awaiting callback",
      )
    ExecutorArrayForEachComplete =>
      raise @errors.InternalError(
        message="forEach frame stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorArrayForEachFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for ExecutorArrayForEachFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorArrayForEachAwaitLength(object) =>
          self.phase = ExecutorArrayForEachHaveLengthValue(object, value)
        ExecutorArrayForEachAwaitLengthPrimitive(_, operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorArrayForEachAwaitHasProperty(_, _, _, _, operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorArrayForEachAwaitGet(object, length, callback, index) =>
          self.phase = ExecutorArrayForEachHaveGetValue(
            object, length, callback, index, value,
          )
        ExecutorArrayForEachAwaitCallback(object, length, callback, index) =>
          // The callback result is intentionally discarded exactly once.
          self.phase = ExecutorArrayForEachNeedIndex(
            object,
            length,
            callback,
            index + 1L,
          )
        ExecutorArrayForEachNeedObject
        | ExecutorArrayForEachHaveLengthValue(_, _)
        | ExecutorArrayForEachNeedCallback(_, _)
        | ExecutorArrayForEachNeedIndex(_, _, _, _)
        | ExecutorArrayForEachHaveGetValue(_, _, _, _, _)
        | ExecutorArrayForEachComplete =>
          raise @errors.InternalError(
            message="forEach frame received an unexpected child completion",
          )
      }
  }
}
