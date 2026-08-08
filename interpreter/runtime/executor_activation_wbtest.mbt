///|
priv struct ExecutorActivationTestCode {
  starts : Ref[Int]
  steps : Ref[Int]
}

///|
fn ExecutorActivationTestCode::ExecutorActivationTestCode(
  starts~ : Ref[Int],
  steps~ : Ref[Int],
) -> ExecutorActivationTestCode {
  { starts, steps }
}

///|
priv struct ExecutorActivationTestFrame {
  steps : Ref[Int]
}

///|
priv struct ExecutorActivationThrowCode {
  error : Error
}

///|
fn ExecutorActivationThrowCode::ExecutorActivationThrowCode(
  error~ : Error,
) -> ExecutorActivationThrowCode {
  { error, }
}

///|
priv struct ExecutorActivationThrowFrame {
  error : Error
}

///|
priv struct ExecutorActivationStartErrorCode {
  error : Error
}

///|
priv struct ExecutorActivationValueCode {
  starts : Ref[Int]
  value : Value
}

///|
priv struct ExecutorActivationValueFrame {
  value : Value
}

///|
priv struct ExecutorActivationCallCode {
  callee : Value
  this_value : Value
  args : Array[Value]
  loc : @token.Loc
}

///|
priv enum ExecutorActivationRecoverRequest {
  RecoverCall(Value)
  RecoverConstruct(Value)
  RecoverProperty(Value)
}

///|
priv struct ExecutorActivationRecoverCode {
  request : ExecutorActivationRecoverRequest
  expected : Error
}

///|
priv struct ExecutorActivationCallFrame {
  callee : Value
  this_value : Value
  args : Array[Value]
  loc : @token.Loc
  mut requested : Bool
  mut result : Value?
}

///|
priv struct ExecutorActivationConstructFrame {
  ctor : Value
  args : Array[Value]
  loc : @token.Loc
  mut requested : Bool
  mut result : Value?
}

///|
priv struct ExecutorActivationRecoverFrame {
  callee : Value
  expected : Error
  mut requested : Bool
  mut result : Value?
  mut abrupt : Error?
}

///|
priv struct ExecutorActivationRecoverRequestFrame {
  request : ExecutorActivationRecoverRequest
  expected : Error
  mut requested : Bool
  mut result : Value?
  mut abrupt : Error?
}

///|
priv struct ExecutorActivationDeliveryErrorFrame {
  request : ExecutorActivationRecoverRequest
  expected : Error
  delivery_count : Ref[Int]
  mut requested : Bool
}

///|
priv struct ExecutorActivationCleanupObservationFrame {
  callee : Value
  expected : Error
  events : Array[String]
  mut requested : Bool
  mut delivered : Bool
}

///|
priv struct ExecutorActivationPropertyGetFrame {
  target : Value
  property_name : String
  loc : @token.Loc
  mut requested : Bool
  mut result : Value?
}

///|
fn ExecutorActivationCallCode::ExecutorActivationCallCode(
  callee~ : Value,
  this_value~ : Value,
  args~ : Array[Value],
  loc~ : @token.Loc,
) -> ExecutorActivationCallCode {
  { callee, this_value, args: args.copy(), loc }
}

///|
fn ExecutorActivationRecoverCode::ExecutorActivationRecoverCode(
  request~ : ExecutorActivationRecoverRequest,
  expected~ : Error,
) -> ExecutorActivationRecoverCode {
  { request, expected }
}

///|
fn ExecutorActivationCallFrame::ExecutorActivationCallFrame(
  callee~ : Value,
  this_value~ : Value,
  args~ : Array[Value],
  loc~ : @token.Loc,
) -> ExecutorActivationCallFrame {
  { callee, this_value, args: args.copy(), loc, requested: false, result: None }
}

///|
fn ExecutorActivationConstructFrame::ExecutorActivationConstructFrame(
  ctor~ : Value,
  args~ : Array[Value],
  loc~ : @token.Loc,
) -> ExecutorActivationConstructFrame {
  { ctor, args: args.copy(), loc, requested: false, result: None }
}

///|
fn ExecutorActivationRecoverFrame::ExecutorActivationRecoverFrame(
  callee~ : Value,
  expected~ : Error,
) -> ExecutorActivationRecoverFrame {
  { callee, expected, requested: false, result: None, abrupt: None }
}

///|
fn ExecutorActivationRecoverRequestFrame::ExecutorActivationRecoverRequestFrame(
  request~ : ExecutorActivationRecoverRequest,
  expected~ : Error,
) -> ExecutorActivationRecoverRequestFrame {
  { request, expected, requested: false, result: None, abrupt: None }
}

///|
fn ExecutorActivationDeliveryErrorFrame::ExecutorActivationDeliveryErrorFrame(
  request~ : ExecutorActivationRecoverRequest,
  expected~ : Error,
  delivery_count~ : Ref[Int],
) -> ExecutorActivationDeliveryErrorFrame {
  { request, expected, delivery_count, requested: false }
}

///|
fn ExecutorActivationCleanupObservationFrame::ExecutorActivationCleanupObservationFrame(
  callee~ : Value,
  expected~ : Error,
  events~ : Array[String],
) -> ExecutorActivationCleanupObservationFrame {
  { callee, expected, events, requested: false, delivered: false }
}

///|
fn ExecutorActivationPropertyGetFrame::ExecutorActivationPropertyGetFrame(
  target~ : Value,
  property_name~ : String,
  loc~ : @token.Loc,
) -> ExecutorActivationPropertyGetFrame {
  { target, property_name, loc, requested: false, result: None }
}

///|
fn ExecutorActivationThrowFrame::ExecutorActivationThrowFrame(
  error~ : Error,
) -> ExecutorActivationThrowFrame {
  { error, }
}

///|
fn ExecutorActivationStartErrorCode::ExecutorActivationStartErrorCode(
  error~ : Error,
) -> ExecutorActivationStartErrorCode {
  { error, }
}

///|
fn ExecutorActivationValueCode::ExecutorActivationValueCode(
  starts~ : Ref[Int],
  value~ : Value,
) -> ExecutorActivationValueCode {
  { starts, value }
}

///|
fn ExecutorActivationValueFrame::ExecutorActivationValueFrame(
  value~ : Value,
) -> ExecutorActivationValueFrame {
  { value, }
}

///|
fn ExecutorActivationTestFrame::ExecutorActivationTestFrame(
  steps : Ref[Int],
) -> ExecutorActivationTestFrame {
  { steps, }
}

///|
fn make_direct_property_getter_target(
  getter : Value,
  arraybuffer_state : ArrayBufferState?,
  internal_slot? : (InternalSlotKey, Value),
  host_slot? : (Int, Value),
) -> Value {
  let bag = PropertyBag::PropertyBag()
  bag.descriptors["x"] = {
    writable: false,
    enumerable: true,
    configurable: true,
    getter: Some(getter),
    setter: None,
    is_accessor: true,
  }
  match internal_slot {
    Some((key, value)) => bag.internal_slots[key] = value
    None => ()
  }
  match host_slot {
    Some((key, value)) => bag.host_slots[key] = value
    None => ()
  }
  Object({
    bag,
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state,
  })
}

///|
fn install_executor_activation_probe(
  interp : Interpreter,
  events : Array[String],
  reject : Error?,
  control? : ExecutionControl? = None,
) -> Unit {
  let observer = make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("executor-probe", args => {
        match args {
          [String_(operation)] if operation == EXECUTION_CONTROL_ACTIVATION => {
            let realm = if interp.realm_state.active_overrides.val is None {
              "cleared"
            } else {
              "outer"
            }
            events.push("attempt:" + realm)
            match control {
              Some(control) =>
                match control.observe_activation() {
                  Ok(_) => ()
                  Err(failure) => raise ExecutionControlError(failure)
                }
              None => ()
            }
            match reject {
              Some(error) => raise error
              None => Undefined
            }
          }
          [String_(operation)] if operation == EXECUTION_CONTROL_RELEASE => {
            let realm = if interp.realm_state.active_overrides.val is None {
              "cleared"
            } else {
              "outer"
            }
            events.push("release:" + realm)
            match control {
              Some(control) =>
                match control.release_activation() {
                  Ok(_) => ()
                  Err(failure) => raise ExecutionControlError(failure)
                }
              None => ()
            }
            Undefined
          }
          _ => Undefined
        }
      }),
    ),
    "Object",
    Map([]),
    true,
  )
  interp.global.bindings[EXECUTION_CONTROL_BINDING] = {
    value: observer,
    kind: VarBinding,
    initialized: true,
    annex_b_hoisted: false,
    is_parameter: false,
  }
}

///|
test "static property getter admission rejects mutable exotic state" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let steps : Ref[Int] = { val: 0 }
  let getter = make_executor_function(
    Some("getter"),
    [],
    interp.global,
    false,
    ExecutorActivationTestCode(starts~, steps~),
    constructable=false,
  )
  let ordinary = make_direct_property_getter_target(getter, None)
  guard direct_executor_property_getter(ordinary, "x") is Some(_) else {
    fail("ordinary object getter should be admitted")
  }
  let with_arraybuffer = make_direct_property_getter_target(
    getter,
    Some(ArrayBufferState::ArrayBufferState()),
  )
  assert_true(direct_executor_property_getter(with_arraybuffer, "x") is None)
  let with_internal_slot = make_direct_property_getter_target(
    getter,
    None,
    internal_slot=(StringData, String_("state")),
  )
  assert_true(direct_executor_property_getter(with_internal_slot, "x") is None)
  let with_host_slot = make_direct_property_getter_target(
    getter,
    None,
    host_slot=(1, Number(1.0)),
  )
  assert_true(direct_executor_property_getter(with_host_slot, "x") is None)
}

///|
test "static property getter exotic fallback runs once and preserves identity" {
  let interp = Interpreter::new()
  let sentinel = Object({
    bag: PropertyBag::PropertyBag(),
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  let starts : Ref[Int] = { val: 0 }
  let getter = make_executor_function(
    Some("getter"),
    [],
    interp.global,
    false,
    ExecutorActivationValueCode(starts~, value=sentinel),
    constructable=false,
  )
  let target = make_direct_property_getter_target(
    getter,
    Some(ArrayBufferState::ArrayBufferState()),
  )
  let root = ExecutorActivationPropertyGetFrame(
      target~,
      property_name="x",
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(value) =>
      assert_true(physical_equal(value, sentinel))
    _ => fail("exotic property fallback must return the getter value")
  }
  inspect(starts.val, content="1")
}

///|
test "property activation lifecycle nests outer scope around inner call" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let starts : Ref[Int] = { val: 0 }
  let getter = make_executor_function(
    Some("getter"),
    [],
    interp.global,
    false,
    ExecutorActivationValueCode(starts~, value=Number(9.0)),
    constructable=false,
  )
  let target = make_direct_property_getter_target(getter, None)
  dispatch_shell_test_install_realm_sentinel(interp, 59)
  let root = ExecutorActivationPropertyGetFrame(
      target~,
      property_name="x",
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(value) => inspect(value.to_string(), content="9")
    _ => fail("property getter must complete normally")
  }
  inspect(starts.val, content="1")
  json_inspect(events, content=["attempt:cleared", "release:cleared"])
  dispatch_shell_test_expect_realm_sentinel(interp, 59)
}

///|
test "property activation setup rejection releases its outer scope" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let sentinel : Error = @errors.TypeError(message="property setup sentinel")
  let getter = make_executor_function(
    Some("getter"),
    [],
    interp.global,
    false,
    ExecutorActivationStartErrorCode(error=sentinel),
    constructable=false,
  )
  let target = make_direct_property_getter_target(getter, None)
  dispatch_shell_test_install_realm_sentinel(interp, 61)
  let root = ExecutorActivationPropertyGetFrame(
      target~,
      property_name="x",
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let caught : Error? = try {
    let _ = interp.run_executor_activation_coordinator(root)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("property setup failure must propagate")
  }
  json_inspect(events, content=["attempt:cleared", "release:cleared"])
  dispatch_shell_test_expect_realm_sentinel(interp, 61)
}

///|
test "property activation denied observation restores scope without release" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let sentinel : Error = @errors.TypeError(
    message="property observation sentinel",
  )
  install_executor_activation_probe(interp, events, Some(sentinel))
  let starts : Ref[Int] = { val: 0 }
  let getter = make_executor_function(
    Some("getter"),
    [],
    interp.global,
    false,
    ExecutorActivationValueCode(starts~, value=Number(11.0)),
    constructable=false,
  )
  let target = make_direct_property_getter_target(getter, None)
  dispatch_shell_test_install_realm_sentinel(interp, 63)
  let root = ExecutorActivationPropertyGetFrame(
      target~,
      property_name="x",
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let caught : Error? = try {
    let _ = interp.run_executor_activation_coordinator(root)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("property observation denial must propagate")
  }
  inspect(starts.val, content="0")
  json_inspect(events, content=["attempt:cleared"])
  dispatch_shell_test_expect_realm_sentinel(interp, 63)
}

///|
impl ExecutorCode for ExecutorActivationTestCode with fn start(
  self,
  interp,
  prepared,
) {
  self.starts.val += 1
  assert_false(prepared.context().strict)
  assert_true(
    physical_equal(prepared.environment().get("this"), interp.global_this),
  )
  match prepared.environment().get("x") {
    Number(value) => inspect(value, content="1")
    _ => fail("runtime must bind parameters before executor entry")
  }
  let arguments : ArrayView[Value] = prepared.arguments()
  match arguments {
    [Number(value)] => inspect(value, content="1")
    _ => fail("executor arguments must be exposed through an immutable view")
  }
  ExecutorActivationTestFrame(self.steps) as &ExecutorActivationFrame
}

///|
impl ExecutorActivationFrame for ExecutorActivationTestFrame with fn step(
  self,
  _interp,
) {
  self.steps.val += 1
  if self.steps.val < 3 {
    executor_activation_continue()
  } else {
    executor_activation_return(Number(7.0))
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationTestFrame with fn deliver_activation_completion(
  _self,
  _completion,
) {
  ()
}

///|
impl ExecutorCode for ExecutorActivationThrowCode with fn start(
  self,
  _interp,
  _prepared,
) {
  ExecutorActivationThrowFrame(error=self.error) as &ExecutorActivationFrame
}

///|
impl ExecutorCode for ExecutorActivationStartErrorCode with fn start(
  self,
  _interp,
  _prepared,
) {
  raise self.error
}

///|
impl ExecutorCode for ExecutorActivationValueCode with fn start(
  self,
  _interp,
  _prepared,
) {
  self.starts.val += 1
  ExecutorActivationValueFrame(value=self.value) as &ExecutorActivationFrame
}

///|
impl ExecutorCode for ExecutorActivationCallCode with fn start(
  self,
  _interp,
  _prepared,
) {
  ExecutorActivationCallFrame(
    callee=self.callee,
    this_value=self.this_value,
    args=self.args,
    loc=self.loc,
  )
  as &ExecutorActivationFrame
}

///|
impl ExecutorCode for ExecutorActivationRecoverCode with fn start(
  self,
  _interp,
  _prepared,
) {
  ExecutorActivationRecoverRequestFrame(
    request=self.request,
    expected=self.expected,
  )
  as &ExecutorActivationFrame
}

///|
impl ExecutorActivationFrame for ExecutorActivationCallFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    executor_activation_call(self.callee, self.this_value, self.args, self.loc)
  } else {
    match self.result {
      Some(value) => executor_activation_return(value)
      None =>
        raise @errors.InternalError(
          message="test call frame resumed without a result",
        )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationCallFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  guard self.requested && self.result is None else {
    raise @errors.InternalError(
      message="test call frame received a duplicate result",
    )
  }
  match completion {
    ExecutorActivationCompletionNormal(value) => self.result = Some(value)
    ExecutorActivationCompletionAbrupt(error) => raise error
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationConstructFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    executor_activation_construct(self.ctor, self.args, self.loc)
  } else {
    match self.result {
      Some(value) => executor_activation_return(value)
      None =>
        raise @errors.InternalError(
          message="test construct frame resumed without a result",
        )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationConstructFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  guard self.requested && self.result is None else {
    raise @errors.InternalError(
      message="test construct frame received a duplicate completion",
    )
  }
  match completion {
    ExecutorActivationCompletionNormal(value) => self.result = Some(value)
    ExecutorActivationCompletionAbrupt(error) => raise error
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationRecoverFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    executor_activation_call(self.callee, Undefined, [], @token.Loc::default())
  } else {
    match (self.result, self.abrupt) {
      (None, Some(error)) if physical_equal(error, self.expected) =>
        executor_activation_return(Number(9.0))
      (Some(_), None) =>
        raise @errors.InternalError(
          message="recovering frame received a value instead of an abrupt completion",
        )
      _ =>
        raise @errors.InternalError(
          message="recovering frame resumed without one child completion",
        )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationRecoverFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  guard self.requested && self.result is None && self.abrupt is None else {
    raise @errors.InternalError(
      message="recovering frame received a duplicate completion",
    )
  }
  match completion {
    ExecutorActivationCompletionNormal(value) => self.result = Some(value)
    ExecutorActivationCompletionAbrupt(error) => self.abrupt = Some(error)
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationRecoverRequestFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    match self.request {
      RecoverCall(callee) =>
        executor_activation_call(callee, Undefined, [], @token.Loc::default())
      RecoverConstruct(ctor) =>
        executor_activation_construct(ctor, [], @token.Loc::default())
      RecoverProperty(target) =>
        executor_activation_property_get(target, "x", @token.Loc::default())
    }
  } else {
    match (self.result, self.abrupt) {
      (None, Some(error)) if physical_equal(error, self.expected) =>
        executor_activation_return(Number(9.0))
      (Some(_), None) =>
        raise @errors.InternalError(
          message="request recovering frame received a value instead of an abrupt completion",
        )
      _ =>
        raise @errors.InternalError(
          message="request recovering frame resumed without one child completion",
        )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationRecoverRequestFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  guard self.requested && self.result is None && self.abrupt is None else {
    raise @errors.InternalError(
      message="request recovering frame received a duplicate completion",
    )
  }
  match completion {
    ExecutorActivationCompletionNormal(value) => self.result = Some(value)
    ExecutorActivationCompletionAbrupt(error) => self.abrupt = Some(error)
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationDeliveryErrorFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    match self.request {
      RecoverCall(callee) =>
        executor_activation_call(callee, Undefined, [], @token.Loc::default())
      RecoverConstruct(ctor) =>
        executor_activation_construct(ctor, [], @token.Loc::default())
      RecoverProperty(target) =>
        executor_activation_property_get(target, "x", @token.Loc::default())
    }
  } else {
    raise @errors.InternalError(
      message="delivery error frame resumed after a delivery failure",
    )
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationDeliveryErrorFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  self.delivery_count.val += 1
  match completion {
    ExecutorActivationCompletionNormal(_) => raise self.expected
    ExecutorActivationCompletionAbrupt(_) =>
      raise @errors.InternalError(
        message="delivery error frame received an abrupt completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationCleanupObservationFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    executor_activation_call(self.callee, Undefined, [], @token.Loc::default())
  } else {
    guard self.delivered else {
      raise @errors.InternalError(
        message="cleanup observation frame resumed without an abrupt delivery",
      )
    }
    executor_activation_return(Number(9.0))
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationCleanupObservationFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => {
      guard physical_equal(error, self.expected) else {
        raise @errors.InternalError(
          message="cleanup observation frame received the wrong error",
        )
      }
      guard self.events.length() == 2 &&
        self.events[0] == "attempt:cleared" &&
        self.events[1] == "release:cleared" else {
        raise @errors.InternalError(
          message="child release must precede abrupt completion delivery",
        )
      }
      self.delivered = true
    }
    ExecutorActivationCompletionNormal(_) =>
      raise @errors.InternalError(
        message="cleanup observation frame received a normal completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationPropertyGetFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    executor_activation_property_get(self.target, self.property_name, self.loc)
  } else {
    match self.result {
      Some(value) => executor_activation_return(value)
      None =>
        raise @errors.InternalError(
          message="test property frame resumed without a result",
        )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationPropertyGetFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  guard self.requested && self.result is None else {
    raise @errors.InternalError(
      message="test property frame received a duplicate result",
    )
  }
  match completion {
    ExecutorActivationCompletionNormal(value) => self.result = Some(value)
    ExecutorActivationCompletionAbrupt(error) => raise error
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationThrowFrame with fn step(
  self,
  _interp,
) {
  raise self.error
}

///|
impl ExecutorActivationFrame for ExecutorActivationThrowFrame with fn deliver_activation_completion(
  _self,
  _completion,
) {
  ()
}

///|
impl ExecutorActivationFrame for ExecutorActivationValueFrame with fn step(
  self,
  _interp,
) {
  executor_activation_return(self.value)
}

///|
impl ExecutorActivationFrame for ExecutorActivationValueFrame with fn deliver_activation_completion(
  _self,
  _completion,
) {
  ()
}

///|
test "executor-neutral shell prepares once and drives explicit frame steps" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let steps : Ref[Int] = { val: 0 }
  let function = make_executor_function(
    Some("stepper"),
    ["x"],
    interp.global,
    false,
    ExecutorActivationTestCode(starts~, steps~),
    constructable=false,
  )
  interp.in_nonarrow_param_default_eval = true
  let result = interp.call_value(
    function,
    Undefined,
    [Number(1.0)],
    @token.Loc::default(),
  )
  inspect(result.to_string(), content="7")
  inspect(starts.val, content="1")
  inspect(steps.val, content="3")
  assert_true(interp.in_nonarrow_param_default_eval)
}

///|
test "executor-neutral shell preserves abrupt error and restores dynamic gate" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(message="executor sentinel")
  let function = make_executor_function(
    Some("thrower"),
    [],
    interp.global,
    true,
    ExecutorActivationThrowCode(error=sentinel),
    constructable=false,
  )
  interp.in_nonarrow_param_default_eval = true
  let caught : Error? = try {
    let _ = interp.call_value(function, Undefined, [], @token.Loc::default())
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("expected executor frame to raise")
  }
  assert_true(interp.in_nonarrow_param_default_eval)
}

///|
test "executor function retains an inspectable neutral payload before entry" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let steps : Ref[Int] = { val: 0 }
  let function = make_executor_function(
    Some("inspectable"),
    ["x"],
    interp.global,
    false,
    ExecutorActivationTestCode(starts~, steps~),
    constructable=false,
  )
  match function {
    Object({ callable: Some(ExecutorCallable(executable)), .. }) => {
      inspect(starts.val, content="0")
      inspect(steps.val, content="0")
      let source_args = [Number(1.0)]
      let prepared = interp.prepare_executor_callable_call(
        executable,
        function,
        Undefined,
        source_args,
      )
      source_args[0] = Number(99.0)
      let _ = executable.start_frame(interp, prepared)
      inspect(starts.val, content="1")
      inspect(steps.val, content="0")
    }
    _ => fail("executor code must remain available as a neutral payload")
  }
}

///|
fn assert_executor_activation_delivery_error(
  request : ExecutorActivationRecoverRequest,
  sentinel : Error,
) -> Unit raise {
  let interp = Interpreter::new()
  let delivery_count : Ref[Int] = { val: 0 }
  let root = ExecutorActivationDeliveryErrorFrame(
      request~,
      expected=sentinel,
      delivery_count~,
    )
    as &ExecutorActivationFrame
  let caught : Error? = try {
    let _ = interp.run_executor_activation_coordinator(root)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("expected normal completion delivery to raise")
  }
  inspect(delivery_count.val, content="1")
}

///|
test "activation coordinator does not redeliver fallback completion failures" {
  let call = make_native_func(name="normal-call", _args => Number(1.0))
  assert_executor_activation_delivery_error(
    RecoverCall(call),
    @errors.RangeError(message="call delivery sentinel"),
  )
  let ctor = Object({
    bag: PropertyBag::PropertyBag(),
    prototype: Null,
    callable: Some(
      ConstructorOnlyCallable("normal-construct", fn(_interp, _args) {
        Number(2.0)
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
  assert_executor_activation_delivery_error(
    RecoverConstruct(ctor),
    @errors.RangeError(message="construct delivery sentinel"),
  )
  let getter = make_native_func(name="normal-property", _args => Number(3.0))
  let target = make_direct_property_getter_target(getter, None)
  assert_executor_activation_delivery_error(
    RecoverProperty(target),
    @errors.RangeError(message="property delivery sentinel"),
  )
}

///|
test "activation coordinator resumes one child result and normalizes it" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let steps : Ref[Int] = { val: 0 }
  let child = make_executor_function(
    Some("child"),
    ["x"],
    interp.global,
    false,
    ExecutorActivationTestCode(starts~, steps~),
    constructable=false,
  )
  let root = ExecutorActivationCallFrame(
      callee=child,
      this_value=Undefined,
      args=[Number(1.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(value) => inspect(value.to_string(), content="7")
    _ => fail("coordinator must return the root frame's child result")
  }
  inspect(starts.val, content="1")
  inspect(steps.val, content="3")
}

///|
test "activation coordinator delivers one normalized construct result" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let child = make_executor_function(
    Some("constructor"),
    [],
    interp.global,
    false,
    ExecutorActivationValueCode(starts~, value=Number(1.0)),
  )
  let root = ExecutorActivationConstructFrame(
      ctor=child,
      args=[],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(Object(_)) => ()
    _ => fail("constructor completion must deliver its allocated instance")
  }
  inspect(starts.val, content="1")
}

///|
test "activation coordinator delivers managed child setup errors to the requester" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(message="setup request sentinel")
  let child = make_executor_function(
    Some("setup-fails"),
    [],
    interp.global,
    false,
    ExecutorActivationStartErrorCode(error=sentinel),
    constructable=false,
  )
  let root = ExecutorActivationRecoverFrame(callee=child, expected=sentinel)
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="9")
    _ => fail("setup errors must be delivered to the requesting frame")
  }
}

///|
test "activation coordinator releases child before abrupt parent delivery" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let sentinel : Error = @errors.RangeError(
    message="delivery lifecycle sentinel",
  )
  let child = make_executor_function(
    Some("lifecycle-thrower"),
    [],
    interp.global,
    false,
    ExecutorActivationThrowCode(error=sentinel),
    constructable=false,
  )
  let root = ExecutorActivationCleanupObservationFrame(
      callee=child,
      expected=sentinel,
      events~,
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="9")
    _ => fail("parent must resume after observing child cleanup")
  }
  json_inspect(events, content=["attempt:cleared", "release:cleared"])
}

///|
test "activation coordinator delivers synchronous fallback call errors to the requester" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(message="call request sentinel")
  let callee = make_native_func(name="call-error", fn(_args) raise {
    raise sentinel
  })
  let root = ExecutorActivationRecoverRequestFrame(
      request=RecoverCall(callee),
      expected=sentinel,
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="9")
    _ => fail("call errors must be delivered to the requesting frame")
  }
}

///|
test "activation coordinator delivers synchronous fallback construct errors to the requester" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(
    message="construct request sentinel",
  )
  let ctor = Object({
    bag: PropertyBag::PropertyBag(),
    prototype: Null,
    callable: Some(
      ConstructorOnlyCallable("construct-error", fn(_interp, _args) raise {
        raise sentinel
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
  let root = ExecutorActivationRecoverRequestFrame(
      request=RecoverConstruct(ctor),
      expected=sentinel,
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="9")
    _ => fail("construct errors must be delivered to the requesting frame")
  }
}

///|
test "activation coordinator delivers synchronous fallback property errors to the requester" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(message="property request sentinel")
  let getter = make_native_func(name="property-error", fn(_args) raise {
    raise sentinel
  })
  let target = make_direct_property_getter_target(getter, None)
  let root = ExecutorActivationRecoverRequestFrame(
      request=RecoverProperty(target),
      expected=sentinel,
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="9")
    _ => fail("property errors must be delivered to the requesting frame")
  }
}

///|
test "non-root requester handles fallback error before child cleanup" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let sentinel : Error = @errors.RangeError(message="nested request sentinel")
  let callee = make_native_func(name="nested-call-error", fn(_args) raise {
    raise sentinel
  })
  let child = make_executor_function(
    Some("requester"),
    [],
    interp.global,
    false,
    ExecutorActivationRecoverCode(
      request=RecoverCall(callee),
      expected=sentinel,
    ),
    constructable=false,
  )
  let root = ExecutorActivationCallFrame(
      callee=child,
      this_value=Undefined,
      args=[],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="9")
    _ => fail("non-root requester must remain resumable after request failure")
  }
  json_inspect(events, content=["attempt:cleared", "release:cleared"])
}

///|
test "nested abrupt delivery rethrows after managed cleanup and permits reuse" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=2,
    interruption=ExecutionInterruptionRequest(),
  )
  install_executor_activation_probe(interp, events, None, control=Some(control))
  let sentinel : Error = @errors.RangeError(message="nested lifecycle sentinel")
  let grandchild = make_executor_function(
    Some("grandchild-thrower"),
    [],
    interp.global,
    false,
    ExecutorActivationThrowCode(error=sentinel),
    constructable=false,
  )
  let parent_code = ExecutorActivationCallCode(
    callee=grandchild,
    this_value=Undefined,
    args=[],
    loc=@token.Loc::default(),
  )
  let parent = make_executor_function(
    Some("managed-parent"),
    [],
    interp.global,
    false,
    parent_code,
    constructable=false,
  )
  let root = ExecutorActivationCallFrame(
      callee=parent,
      this_value=Undefined,
      args=[],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let caught : Error? = try {
    let _ = interp.run_executor_activation_coordinator(root)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("nested parent must re-raise the grandchild error")
  }
  json_inspect(events, content=[
    "attempt:cleared", "attempt:outer", "release:outer", "release:cleared",
  ])
  inspect(control.active_depth(), content="0")
  assert_true(interp.realm_state.active_overrides.val is None)
  match control.with_activation(() => Number(1.0)) {
    Ok(Number(value)) => inspect(value, content="1")
    _ => fail("execution control must permit reuse after nested unwind")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "tree executor child abrupt completion preserves identity and cleanup" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(message="tree child sentinel")
  let child = make_executor_function(
    Some("tree_child_thrower"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationThrowCode(error=sentinel),
    constructable=false,
    activation_source_contract=Some(
      executor_activation_source_contract(@parser.parse("return 0;").stmts),
    ),
  )
  interp.global.def_builtin("tree_child_thrower", child)
  let _ = interp.run(
    @parser.parse(
      "function treeParent(n) { return tree_child_thrower(n - 1) + 1; }",
    ).stmts,
  )
  let tree_parent = interp.global.get("treeParent")
  let events : Array[String] = []
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=2,
    interruption=ExecutionInterruptionRequest(),
  )
  install_executor_activation_probe(interp, events, None, control=Some(control))
  let root = ExecutorActivationCallFrame(
      callee=tree_parent,
      this_value=Undefined,
      args=[Number(1.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let caught : Error? = try {
    let _ = interp.run_executor_activation_coordinator(root)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("tree parent must re-raise its child abrupt completion")
  }
  json_inspect(events, content=[
    "attempt:cleared", "attempt:outer", "release:outer", "release:cleared",
  ])
  inspect(control.active_depth(), content="0")
  match control.with_activation(() => Number(1.0)) {
    Ok(Number(value)) => inspect(value, content="1")
    _ => fail("execution control must permit reuse after tree unwind")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "unsupported tree body stays legacy before observable execution" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "var legacyCalls = 0; " +
      "function legacyNearMiss(n) { legacyCalls = legacyCalls + 1; return -n; }",
    ).stmts,
  )
  let legacy = interp.global.get("legacyNearMiss")
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=legacy,
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="-3")
    _ => fail("unsupported body must complete through the legacy evaluator")
  }
  inspect(interp.global.get("legacyCalls").to_string(), content="1")
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission rejects unsupported callees before earlier call effects" {
  let interp = Interpreter::new()
  let side_effects : Ref[Int] = { val: 0 }
  let side_effect = make_native_func(name="sideEffect", fn(args) {
    side_effects.val += 1
    args[0]
  })
  let native_leaf = make_native_func(name="nativeLeaf", fn(args) { args[0] })
  interp.global.def_builtin("sideEffect", side_effect)
  interp.global.def_builtin("nativeLeaf", native_leaf)
  let _ = interp.run(
    @parser.parse(
      "function unsafeParent(n) { sideEffect(n); return nativeLeaf(n) + 1; }",
    ).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("unsafeParent"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="4")
    _ =>
      fail("unsupported callees must keep the whole root on legacy execution")
  }
  inspect(side_effects.val, content="1")
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission rejects object coercion before valueOf effects" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "var coercions = 0; " +
      "var box = { valueOf: function() { coercions = coercions + 1; return 7; } }; " +
      "function coercionParent(x) { return x + 1; }",
    ).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("coercionParent"),
      this_value=Undefined,
      args=[interp.global.get("box")],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="8")
    _ => fail("object coercion must keep the whole root on legacy execution")
  }
  inspect(interp.global.get("coercions").to_string(), content="1")
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission rejects executor object results before parent effects" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let coercions : Ref[Int] = { val: 0 }
  let value_of = make_native_func(name="valueOf", fn(_args) {
    coercions.val += 1
    Number(7.0)
  })
  let object_result = make_object(
    { "valueOf": value_of },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let child = make_executor_function(
    Some("objectLeaf"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationValueCode(starts~, value=object_result),
    constructable=false,
    activation_source_contract=Some(
      executor_activation_source_contract(@parser.parse("return {};").stmts),
    ),
  )
  interp.global.def_builtin("objectLeaf", child)
  let _ = interp.run(
    @parser.parse(
      "function objectResultParent(n) { return objectLeaf(n) + 1; }",
    ).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("objectResultParent"),
      this_value=Undefined,
      args=[Number(1.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="8")
    _ =>
      fail(
        "object-returning executors must keep the parent on legacy execution",
      )
  }
  inspect(starts.val, content="1")
  inspect(coercions.val, content="1")
  inspect(control.active_depth(), content="0")
}

///|
test "activation coordinator unwinds child errors and restores dynamic state" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(message="coordinator sentinel")
  let child = make_executor_function(
    Some("thrower"),
    [],
    interp.global,
    false,
    ExecutorActivationThrowCode(error=sentinel),
    constructable=false,
  )
  let root = ExecutorActivationCallFrame(
      callee=child,
      this_value=Undefined,
      args=[],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let caught : Error? = interp.with_execution_control(control, () => {
    interp.in_nonarrow_param_default_eval = true
    try {
      let _ = interp.run_executor_activation_coordinator(root)
      None
    } catch {
      error => Some(error)
    }
  })
  match caught {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("expected child error to unwind the coordinator")
  }
  assert_true(interp.in_nonarrow_param_default_eval)
  inspect(control.active_depth(), content="0")
}

///|
test "activation coordinator can deliver one child abrupt completion to its caller" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(message="recoverable sentinel")
  let child = make_executor_function(
    Some("thrower"),
    [],
    interp.global,
    false,
    ExecutorActivationThrowCode(error=sentinel),
    constructable=false,
  )
  let root = ExecutorActivationRecoverFrame(callee=child, expected=sentinel)
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="9")
    _ => fail("caller frame must be able to handle the child abrupt completion")
  }
}

///|
test "handled child abrupt completion cleans activation before parent delivery" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let sentinel : Error = @errors.RangeError(message="lifecycle sentinel")
  let child = make_executor_function(
    Some("thrower"),
    [],
    interp.global,
    false,
    ExecutorActivationThrowCode(error=sentinel),
    constructable=false,
  )
  let root = ExecutorActivationRecoverFrame(callee=child, expected=sentinel)
    as &ExecutorActivationFrame
  let result = interp.run_executor_activation_coordinator(root)
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="9")
    _ => fail("handled abrupt completion must resume the parent")
  }
  json_inspect(events, content=["attempt:cleared", "release:cleared"])
}

///|
test "activation coordinator rejects depth before child preparation" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let steps : Ref[Int] = { val: 0 }
  let leaf = make_executor_function(
    Some("leaf"),
    [],
    interp.global,
    false,
    ExecutorActivationTestCode(starts~, steps~),
    constructable=false,
  )
  let middle = ExecutorActivationCallCode(
    callee=leaf,
    this_value=Undefined,
    args=[],
    loc=@token.Loc::default(),
  )
  let middle_value = make_executor_function(
    Some("middle"),
    [],
    interp.global,
    false,
    middle,
    constructable=false,
  )
  let root = ExecutorActivationCallFrame(
      callee=middle_value,
      this_value=Undefined,
      args=[],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let outcome = interp.with_execution_control(control, () => {
    let _ = interp.run_executor_activation_coordinator(root)
    "completed"
  }) catch {
    ExecutionControlError(StackDepthLimit) => "stack-depth-limit"
    _ => "other-error"
  }
  inspect(outcome, content="stack-depth-limit")
  inspect(starts.val, content="0")
  inspect(control.active_depth(), content="0")
}

///|
test "property activation rejects depth before body and releases for later leaf" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let getter = make_executor_function(
    Some("getter"),
    [],
    interp.global,
    false,
    ExecutorActivationValueCode(starts~, value=Number(7.0)),
    constructable=false,
  )
  let target = make_direct_property_getter_target(getter, None)
  dispatch_shell_test_install_realm_sentinel(interp, 47)
  interp.in_nonarrow_param_default_eval = true
  let rejected_control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let rejected = interp.with_execution_control(rejected_control, () => {
    let root = ExecutorActivationPropertyGetFrame(
        target~,
        property_name="x",
        loc=@token.Loc::default(),
      )
      as &ExecutorActivationFrame
    try {
      let _ = interp.run_executor_activation_coordinator(root)
      "completed"
    } catch {
      ExecutionControlError(StackDepthLimit) => "stack-depth-limit"
      _ => "other-error"
    }
  })
  inspect(rejected, content="stack-depth-limit")
  inspect(starts.val, content="0")
  inspect(rejected_control.active_depth(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 47)
  assert_true(interp.in_nonarrow_param_default_eval)
  let accepted_control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let accepted = interp.with_execution_control(accepted_control, () => {
    let root = ExecutorActivationPropertyGetFrame(
        target~,
        property_name="x",
        loc=@token.Loc::default(),
      )
      as &ExecutorActivationFrame
    match interp.run_executor_activation_coordinator(root) {
      ExecutorActivationReturn(value) => value
      _ => Undefined
    }
  })
  inspect(accepted.to_string(), content="7")
  inspect(starts.val, content="1")
  inspect(accepted_control.active_depth(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 47)
  assert_true(interp.in_nonarrow_param_default_eval)
}

///|
test "property activation abrupt getter restores outer realm and depth" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.TypeError(message="property getter sentinel")
  let getter = make_executor_function(
    Some("getter"),
    [],
    interp.global,
    false,
    ExecutorActivationThrowCode(error=sentinel),
    constructable=false,
  )
  let target = make_direct_property_getter_target(getter, None)
  dispatch_shell_test_install_realm_sentinel(interp, 53)
  interp.in_nonarrow_param_default_eval = true
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let caught = interp.with_execution_control(control, () => {
    let root = ExecutorActivationPropertyGetFrame(
        target~,
        property_name="x",
        loc=@token.Loc::default(),
      )
      as &ExecutorActivationFrame
    try {
      let _ = interp.run_executor_activation_coordinator(root)
      None
    } catch {
      error => Some(error)
    }
  })
  match caught {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("property getter must propagate its abrupt completion")
  }
  inspect(control.active_depth(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 53)
  assert_true(interp.in_nonarrow_param_default_eval)
}
