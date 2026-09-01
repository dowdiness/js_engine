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
priv struct ExecutorActivationProxyAdditionGetCode {
  events : Array[String]
  expected_receiver : Ref[Value]
  to_primitive_id : Int
  value_of : Value
  to_string : Value
}

///|
priv struct ExecutorActivationOrderedValueCode {
  events : Array[String]
  label : String
  value : Value
}

///|
priv struct ExecutorActivationOrderedIncrementCode {
  events : Array[String]
  label : String
  increment : Double
}

///|
priv struct ExecutorActivationMutateBindingCode {
  closure : Environment
  binding_name : String
  replacement : Value
  value : Value
}

///|
priv struct ExecutorActivationThisValueCode {
  expected : Value
  value : Value
}

///|
priv struct ExecutorActivationRecursivePropertySetCode {
  target : Ref[Value]
  remaining : Ref[Int]
  starts : Ref[Int]
}

///|
fn ExecutorActivationThisValueCode::ExecutorActivationThisValueCode(
  expected~ : Value,
  value~ : Value,
) -> ExecutorActivationThisValueCode {
  { expected, value }
}

///|
fn ExecutorActivationOrderedValueCode::ExecutorActivationOrderedValueCode(
  events~ : Array[String],
  label~ : String,
  value~ : Value,
) -> ExecutorActivationOrderedValueCode {
  { events, label, value }
}

///|
fn ExecutorActivationOrderedIncrementCode::ExecutorActivationOrderedIncrementCode(
  events~ : Array[String],
  label~ : String,
  increment~ : Double,
) -> ExecutorActivationOrderedIncrementCode {
  { events, label, increment }
}

///|
fn ExecutorActivationMutateBindingCode::ExecutorActivationMutateBindingCode(
  closure~ : Environment,
  binding_name~ : String,
  replacement~ : Value,
  value~ : Value,
) -> ExecutorActivationMutateBindingCode {
  { closure, binding_name, replacement, value }
}

///|
priv struct ExecutorActivationValueFrame {
  value : Value
}

///|
priv struct ExecutorActivationCoercingAdditionRootFrame {
  left : Value
  right : Value
  loc : @token.Loc
  mut requested : Bool
  mut result : Value?
}

///|
priv struct ExecutorActivationCoercingSubtractionRootFrame {
  left : Value
  right : Value
  loc : @token.Loc
  mut requested : Bool
  mut result : Value?
}

///|
fn ExecutorActivationCoercingAdditionRootFrame::ExecutorActivationCoercingAdditionRootFrame(
  left~ : Value,
  right~ : Value,
  loc~ : @token.Loc,
) -> ExecutorActivationCoercingAdditionRootFrame {
  { left, right, loc, requested: false, result: None }
}

///|
fn ExecutorActivationCoercingSubtractionRootFrame::ExecutorActivationCoercingSubtractionRootFrame(
  left~ : Value,
  right~ : Value,
  loc~ : @token.Loc,
) -> ExecutorActivationCoercingSubtractionRootFrame {
  { left, right, loc, requested: false, result: None }
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
priv struct ExecutorActivationPropertySetFrame {
  target : Value
  property_name : String
  value : Value
  loc : @token.Loc
  strict : Bool
  mut requested : Bool
  mut result : Value?
}

///|
priv struct ExecutorActivationPropertySetDeliveryErrorFrame {
  target : Value
  value : Value
  expected : Error
  delivery_count : Ref[Int]
  mut requested : Bool
}

///|
priv struct ExecutorActivationRecursivePropertySetFrame {
  target : Ref[Value]
  remaining : Ref[Int]
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
fn ExecutorActivationPropertySetFrame::ExecutorActivationPropertySetFrame(
  target~ : Value,
  property_name~ : String,
  value~ : Value,
  loc~ : @token.Loc,
  strict~ : Bool,
) -> ExecutorActivationPropertySetFrame {
  { target, property_name, value, loc, strict, requested: false, result: None }
}

///|
fn ExecutorActivationPropertySetDeliveryErrorFrame::ExecutorActivationPropertySetDeliveryErrorFrame(
  target~ : Value,
  value~ : Value,
  expected~ : Error,
  delivery_count~ : Ref[Int],
) -> ExecutorActivationPropertySetDeliveryErrorFrame {
  { target, value, expected, delivery_count, requested: false }
}

///|
fn ExecutorActivationRecursivePropertySetFrame::ExecutorActivationRecursivePropertySetFrame(
  target~ : Ref[Value],
  remaining~ : Ref[Int],
) -> ExecutorActivationRecursivePropertySetFrame {
  { target, remaining, requested: false, result: None }
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
fn ExecutorActivationProxyAdditionGetCode::ExecutorActivationProxyAdditionGetCode(
  events~ : Array[String],
  expected_receiver~ : Ref[Value],
  to_primitive_id~ : Int,
  value_of~ : Value,
  to_string~ : Value,
) -> ExecutorActivationProxyAdditionGetCode {
  { events, expected_receiver, to_primitive_id, value_of, to_string }
}

///|
fn ExecutorActivationRecursivePropertySetCode::ExecutorActivationRecursivePropertySetCode(
  target~ : Ref[Value],
  remaining~ : Ref[Int],
  starts~ : Ref[Int],
) -> ExecutorActivationRecursivePropertySetCode {
  { target, remaining, starts }
}

///|
fn ExecutorActivationValueFrame::ExecutorActivationValueFrame(
  value~ : Value,
) -> ExecutorActivationValueFrame {
  { value, }
}

///|
impl ExecutorActivationFrame for ExecutorActivationCoercingAdditionRootFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    executor_activation_coercing_addition(self.left, self.right, self.loc)
  } else {
    match self.result {
      Some(value) => ExecutorActivationReturn(value)
      None =>
        raise @errors.InternalError(
          message="coercing addition root resumed without a result",
        )
    }
  }
}

///|
test "issue 936 ordinary array numeric computed call completes synchronously" {
  let callee = make_native_func(name="array element", _args => Number(7.0))
  let array = make_array([callee])
  match
    begin_executor_computed_call_preparation(
      array,
      Number(0.0),
      @token.Loc::default(),
    ) {
    ExecutorComputedCallPreparationCompleted(value) =>
      assert_true(physical_equal(value, callee))
    ExecutorComputedCallPreparationSuspended(_) =>
      fail("ordinary Array + numeric key must not create a child activation")
  }
}

///|
test "property key conversion has a dedicated activation request" {
  let key = make_object(Map([]), Null, None, "Object", Map([]), true)
  match begin_executor_property_key(key, @token.Loc::default()) {
    ExecutorPropertyKeyCompleted(_) =>
      fail("object property key must suspend for guest conversion")
    ExecutorPropertyKeySuspended(request) =>
      match executor_activation_property_key_request(request) {
        ExecutorActivationPropertyKey(_) => ()
        _ => fail("property key conversion used an unrelated activation")
      }
  }
}

///|
test "computed call preparation suspends on a computed property get" {
  let target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let key = make_object(Map([]), Null, None, "Object", Map([]), true)
  match
    begin_executor_computed_call_preparation(target, key, @token.Loc::default()) {
    ExecutorComputedCallPreparationCompleted(_) =>
      fail("object property key must suspend computed property lookup")
    ExecutorComputedCallPreparationSuspended(request) =>
      match executor_activation_computed_property_get_request(request) {
        ExecutorActivationComputedPropertyGet(_) => ()
        _ => fail("computed property get used an unrelated activation")
      }
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationCoercingAdditionRootFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="test coercing addition frame received an unexpected binding reference completion",
      )
    ExecutorActivationCompletionNormal(value) => self.result = Some(value)
    ExecutorActivationCompletionAbrupt(error) => raise error
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationCoercingSubtractionRootFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    executor_activation_coercing_subtraction(self.left, self.right, self.loc)
  } else {
    match self.result {
      Some(value) => ExecutorActivationReturn(value)
      None =>
        raise @errors.InternalError(
          message="coercing subtraction root resumed without a result",
        )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationCoercingSubtractionRootFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="test coercing subtraction frame received an unexpected binding reference completion",
      )
    ExecutorActivationCompletionNormal(value) => self.result = Some(value)
    ExecutorActivationCompletionAbrupt(error) => raise error
  }
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
fn make_direct_property_setter_target(
  setter : Value,
  arraybuffer_state : ArrayBufferState?,
  internal_slot? : (InternalSlotKey, Value),
  host_slot? : (Int, Value),
) -> Value {
  let bag = PropertyBag::PropertyBag()
  bag.descriptors["x"] = {
    writable: false,
    enumerable: true,
    configurable: true,
    getter: None,
    setter: Some(setter),
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
fn run_executor_property_set_root_for_wb(
  interp : Interpreter,
  target : Value,
  property_name : String,
  value : Value,
  strict : Bool,
) -> Value raise Error {
  let root = ExecutorActivationPropertySetFrame(
      target~,
      property_name~,
      value~,
      loc=@token.Loc::default(),
      strict~,
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(result) => result
    _ => fail("property-set root must return its assignment result")
  }
}

///|
fn run_executor_coercing_addition_root_for_wb(
  interp : Interpreter,
  left : Value,
  right : Value,
) -> Value raise Error {
  let root = ExecutorActivationCoercingAdditionRootFrame(
      left~,
      right~,
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(result) => result
    _ => fail("coercing-addition root must return its result")
  }
}

///|
fn run_executor_coercing_subtraction_root_for_wb(
  interp : Interpreter,
  left : Value,
  right : Value,
) -> Value raise Error {
  let root = ExecutorActivationCoercingSubtractionRootFrame(
      left~,
      right~,
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(result) => result
    _ => fail("coercing-subtraction root must return its result")
  }
}

///|
fn coercing_subtraction_error_for_wb(
  interp : Interpreter,
  left : Value,
  right : Value,
) -> Error? {
  try {
    let _ = run_executor_coercing_subtraction_root_for_wb(interp, left, right)
    None
  } catch {
    error => Some(error)
  }
}

///|
fn make_coercing_addition_object_for_wb(
  to_primitive_id : Int,
  symbol_value : Value?,
  symbol_getter : Value?,
  value_of : Value?,
  value_of_getter : Value?,
  to_string : Value?,
  to_string_getter : Value?,
) -> Value raise Error {
  let object = make_object(Map([]), Null, None, "Object", Map([]), true)
  match object {
    Object(data) => {
      match symbol_value {
        Some(value) => data.bag.symbol_properties[to_primitive_id] = value
        None => ()
      }
      match symbol_getter {
        Some(getter) =>
          data.bag.symbol_descriptors[to_primitive_id] = {
            writable: false,
            enumerable: true,
            configurable: true,
            getter: Some(getter),
            setter: None,
            is_accessor: true,
          }
        None => ()
      }
      match value_of {
        Some(value) => data.bag.properties["valueOf"] = value
        None => ()
      }
      match value_of_getter {
        Some(getter) =>
          data.bag.descriptors["valueOf"] = {
            writable: false,
            enumerable: true,
            configurable: true,
            getter: Some(getter),
            setter: None,
            is_accessor: true,
          }
        None => ()
      }
      match to_string {
        Some(value) => data.bag.properties["toString"] = value
        None => ()
      }
      match to_string_getter {
        Some(getter) =>
          data.bag.descriptors["toString"] = {
            writable: false,
            enumerable: true,
            configurable: true,
            getter: Some(getter),
            setter: None,
            is_accessor: true,
          }
        None => ()
      }
    }
    _ => fail("expected an object fixture")
  }
  object
}

///|
fn coercing_addition_error_for_wb(
  interp : Interpreter,
  left : Value,
  right : Value,
) -> Error? {
  try {
    let _ = run_executor_coercing_addition_root_for_wb(interp, left, right)
    None
  } catch {
    error => Some(error)
  }
}

///|
fn make_coercing_addition_thrower_for_wb(
  interp : Interpreter,
  name : String,
  error : Error,
) -> Value {
  make_executor_function(
    Some(name),
    [],
    interp.global,
    false,
    ExecutorActivationThrowCode(error~),
    constructable=false,
  )
}

///|
fn assert_coercing_addition_type_error_for_wb(
  interp : Interpreter,
  left : Value,
  right : Value,
  label : String,
) -> Unit raise Error {
  match coercing_addition_error_for_wb(interp, left, right) {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail(label + " raised " + error.to_string())
    None => fail(label + " unexpectedly completed")
  }
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
test "computed property admission seals only primitive string own accessors" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let getter = make_executor_function(
    Some("getter"),
    [],
    interp.global,
    false,
    ExecutorActivationValueCode(starts~, value=Number(1.0)),
    constructable=false,
  )
  let target = make_direct_property_getter_target(getter, None)
  match
    executor_activation_computed_property_get_if_admitted(
      target,
      String_("x"),
      @token.Loc::default(),
    ) {
    Some(ExecutorActivationPropertyGet(request)) =>
      match request.admission {
        Some({ getter: admitted_getter, .. }) =>
          assert_true(physical_equal(admitted_getter, getter))
        None => fail("computed property admission must retain sealed proof")
      }
    _ => fail("primitive string own accessor should be admitted")
  }
  let symbol_key = Symbol({ id: 101, description: None })
  let object_key = Object({
    bag: PropertyBag::PropertyBag(),
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  let proxy_receiver = Proxy({
    target: Some(target),
    handler: Some(object_key),
    is_callable: false,
    is_constructor: false,
  })
  let inherited_receiver = Object({
    bag: PropertyBag::PropertyBag(),
    prototype: target,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  let data_bag = PropertyBag::PropertyBag()
  data_bag.properties["x"] = Number(2.0)
  let data_receiver = Object({
    bag: data_bag,
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  let array_receiver = make_array([])
  assert_true(
    executor_activation_computed_property_get_if_admitted(
      target,
      Number(1.0),
      @token.Loc::default(),
    )
    is None,
  )
  assert_true(
    executor_activation_computed_property_get_if_admitted(
      target,
      symbol_key,
      @token.Loc::default(),
    )
    is None,
  )
  assert_true(
    executor_activation_computed_property_get_if_admitted(
      target,
      object_key,
      @token.Loc::default(),
    )
    is None,
  )
  assert_true(
    executor_activation_computed_property_get_if_admitted(
      inherited_receiver,
      String_("x"),
      @token.Loc::default(),
    )
    is None,
  )
  assert_true(
    executor_activation_computed_property_get_if_admitted(
      data_receiver,
      String_("x"),
      @token.Loc::default(),
    )
    is None,
  )
  assert_true(
    executor_activation_computed_property_get_if_admitted(
      proxy_receiver,
      String_("x"),
      @token.Loc::default(),
    )
    is None,
  )
  assert_true(
    executor_activation_computed_property_get_if_admitted(
      array_receiver,
      String_("x"),
      @token.Loc::default(),
    )
    is None,
  )
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
impl ExecutorCode for ExecutorActivationProxyAdditionGetCode with fn start(
  self,
  _interp,
  prepared,
) {
  let receiver = prepared.environment().get("receiver")
  assert_true(physical_equal(receiver, self.expected_receiver.val))
  let value = match prepared.environment().get("key") {
    Symbol(symbol) if symbol.id == self.to_primitive_id => {
      self.events.push("get:@@toPrimitive")
      Undefined
    }
    String_("valueOf") => {
      self.events.push("get:valueOf")
      self.value_of
    }
    String_("toString") => {
      self.events.push("get:toString")
      self.to_string
    }
    key => fail("unexpected Proxy get key: " + key.to_string())
  }
  ExecutorActivationValueFrame(value~) as &ExecutorActivationFrame
}

///|
impl ExecutorCode for ExecutorActivationOrderedValueCode with fn start(
  self,
  _interp,
  _prepared,
) {
  self.events.push(self.label)
  ExecutorActivationValueFrame(value=self.value) as &ExecutorActivationFrame
}

///|
impl ExecutorCode for ExecutorActivationOrderedIncrementCode with fn start(
  self,
  _interp,
  prepared,
) {
  let value = match prepared.environment().get("n") {
    Number(number) => Number(number + self.increment)
    _ => fail("ordered increment code requires a numeric n binding")
  }
  self.events.push(self.label)
  ExecutorActivationValueFrame(value~) as &ExecutorActivationFrame
}

///|
impl ExecutorCode for ExecutorActivationMutateBindingCode with fn start(
  self,
  _interp,
  _prepared,
) {
  self.closure.bindings[self.binding_name].value = self.replacement
  ExecutorActivationValueFrame(value=self.value) as &ExecutorActivationFrame
}

///|
impl ExecutorCode for ExecutorActivationThisValueCode with fn start(
  self,
  _interp,
  prepared,
) {
  assert_true(physical_equal(prepared.environment().get("this"), self.expected))
  ExecutorActivationValueFrame(value=self.value) as &ExecutorActivationFrame
}

///|
impl ExecutorCode for ExecutorActivationRecursivePropertySetCode with fn start(
  self,
  _interp,
  _prepared,
) {
  self.starts.val += 1
  ExecutorActivationRecursivePropertySetFrame(
    target=self.target,
    remaining=self.remaining,
  )
  as &ExecutorActivationFrame
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
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="test call frame received an unexpected binding reference completion",
      )
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
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="test construct frame received an unexpected binding reference completion",
      )
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
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="recovering frame received an unexpected binding reference completion",
      )
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
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="request recovering frame received an unexpected binding reference completion",
      )
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
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="delivery error frame received an unexpected binding reference completion",
      )
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
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="cleanup observation frame received an unexpected binding reference completion",
      )
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
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="test property frame received an unexpected binding reference completion",
      )
    ExecutorActivationCompletionNormal(value) => self.result = Some(value)
    ExecutorActivationCompletionAbrupt(error) => raise error
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationPropertySetFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    executor_activation_property_set(
      self.target,
      self.property_name,
      self.value,
      self.loc,
      self.strict,
    )
  } else {
    match self.result {
      Some(value) => executor_activation_return(value)
      None =>
        raise @errors.InternalError(
          message="test property-set frame resumed without a result",
        )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationPropertySetFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  guard self.requested && self.result is None else {
    raise @errors.InternalError(
      message="test property-set frame received a duplicate result",
    )
  }
  match completion {
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="test property-set frame received an unexpected binding reference completion",
      )
    ExecutorActivationCompletionNormal(value) => self.result = Some(value)
    ExecutorActivationCompletionAbrupt(error) => raise error
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationPropertySetDeliveryErrorFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    executor_activation_property_set(
      self.target,
      "x",
      self.value,
      @token.Loc::default(),
      false,
    )
  } else {
    raise @errors.InternalError(
      message="property-set delivery error frame resumed after delivery failure",
    )
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationPropertySetDeliveryErrorFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  self.delivery_count.val += 1
  match completion {
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="property-set delivery error frame received an unexpected binding reference completion",
      )
    ExecutorActivationCompletionNormal(_) => raise self.expected
    ExecutorActivationCompletionAbrupt(_) =>
      raise @errors.InternalError(
        message="property-set delivery error frame received an abrupt completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationRecursivePropertySetFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    if self.remaining.val > 0 {
      self.remaining.val -= 1
      self.requested = true
      executor_activation_property_set(
        self.target.val,
        "x",
        Number(self.remaining.val.to_double()),
        @token.Loc::default(),
        false,
      )
    } else {
      executor_activation_return(Undefined)
    }
  } else {
    match self.result {
      Some(value) => executor_activation_return(value)
      None =>
        raise @errors.InternalError(
          message="recursive property-set frame resumed without a result",
        )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationRecursivePropertySetFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  guard self.requested && self.result is None else {
    raise @errors.InternalError(
      message="recursive property-set frame received a duplicate result",
    )
  }
  match completion {
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="recursive property-set frame received an unexpected binding reference completion",
      )
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
test "cleanup failure still releases every remaining owned activation" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=3,
    interruption=ExecutionInterruptionRequest(),
  )
  install_executor_activation_probe(interp, events, None, control=Some(control))
  let sentinel : Error = @errors.RangeError(message="cleanup source sentinel")
  let leaf = make_executor_function(
    Some("cleanupLeaf"),
    [],
    interp.global,
    false,
    ExecutorActivationThrowCode(error=sentinel),
    constructable=false,
  )
  let parent = make_executor_function(
    Some("cleanupParent"),
    [],
    interp.global,
    false,
    ExecutorActivationCallCode(
      callee=leaf,
      this_value=Undefined,
      args=[],
      loc=@token.Loc::default(),
    ),
    constructable=false,
  )
  let root = make_executor_function(
    Some("cleanupRoot"),
    [],
    interp.global,
    false,
    ExecutorActivationCallCode(
      callee=parent,
      this_value=Undefined,
      args=[],
      loc=@token.Loc::default(),
    ),
    constructable=false,
  )
  let leaf_executable = match leaf {
    Object({ callable: Some(ExecutorCallable(executable)), .. }) => executable
    _ => fail("cleanup leaf must retain executor data")
  }
  let parent_executable = match parent {
    Object({ callable: Some(ExecutorCallable(executable)), .. }) => executable
    _ => fail("cleanup parent must retain executor data")
  }
  let root_executable = match root {
    Object({ callable: Some(ExecutorCallable(executable)), .. }) => executable
    _ => fail("cleanup root must retain executor data")
  }
  let root_entry = interp.start_executor_activation(
    root_executable,
    ExecutorStartCall(
      ExecutorCallRequest(
        callee=root,
        this_value=Undefined,
        args=[],
        loc=@token.Loc::default(),
      ),
    ),
    None,
  )
  let parent_entry = interp.start_executor_activation(
    parent_executable,
    ExecutorStartCall(
      ExecutorCallRequest(
        callee=parent,
        this_value=Undefined,
        args=[],
        loc=@token.Loc::default(),
      ),
    ),
    None,
  )
  let leaf_entry = interp.start_executor_activation(
    leaf_executable,
    ExecutorStartCall(
      ExecutorCallRequest(
        callee=leaf,
        this_value=Undefined,
        args=[],
        loc=@token.Loc::default(),
      ),
    ),
    None,
  )
  let parent_cleanup = match parent_entry.cleanup {
    Some(cleanup) => cleanup
    None => fail("managed parent must own cleanup")
  }
  parent_cleanup.observation.release()
  let caught : Error? = try {
    let _ = interp.drive_executor_activation_stack([
      root_entry, parent_entry, leaf_entry,
    ])
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@errors.InternalError(message~)) =>
      assert_true(message.contains("executor activation release is invalid"))
    Some(error) => fail("expected cleanup failure, got " + error.to_string())
    None => fail("the stale parent release must fail cleanup")
  }
  json_inspect(events, content=[
    "attempt:cleared", "attempt:outer", "attempt:outer", "release:outer", "release:outer",
    "release:cleared",
  ])
  assert_eq(control.active_depth(), 0L)
  assert_true(interp.realm_state.active_overrides.val is None)
}

///|
test "tree executor child abrupt completion preserves identity and cleanup" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(message="tree child sentinel")
  let child = make_classified_executor_function(
    Some("tree_child_thrower"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationThrowCode(error=sentinel),
    @parser.parse("return 0;").stmts,
    constructable=false,
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
test "legacy call enters an admitted child without replaying abrupt effects" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=2,
    interruption=ExecutionInterruptionRequest(),
  )
  install_executor_activation_probe(interp, events, None, control=Some(control))
  let guest_value = Object({
    bag: PropertyBag::PropertyBag(),
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  let sentinel : Error = JsException(guest_value)
  let child = make_classified_executor_function(
    Some("bridgeThrow"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationThrowCode(error=sentinel),
    @parser.parse("return n;").stmts,
    constructable=false,
  )
  interp.global.def_builtin("bridgeThrow", child)
  let _ = interp.run(
    @parser.parse(
      "var before = 0; var after = 0; " +
      "function bridgeTree(n) { return bridgeThrow(n) + 1; } " +
      "function legacyBridge(n) { " +
      "before = before + 1; bridgeTree(n); " +
      "after = after + 1; return n; } " +
      "function bridgeReuse(n) { return n + 1; }",
    ).stmts,
  )
  let caught : Error? = try {
    let _ = interp.call_value(
      interp.global.get("legacyBridge"),
      Undefined,
      [Number(1.0)],
      @token.Loc::default(),
    )
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(JsException(value)) => assert_true(physical_equal(value, guest_value))
    Some(error) =>
      fail("expected the original guest value, got " + error.to_string())
    None => fail("the admitted child must propagate its abrupt completion")
  }
  json_inspect(events, content=[
    "attempt:cleared", "attempt:outer", "release:outer", "release:cleared",
  ])
  assert_eq(control.active_depth(), 0L)
  assert_true(interp.global.get("before") is Number(1.0))
  assert_true(interp.global.get("after") is Number(0.0))
  match
    interp.call_value(
      interp.global.get("bridgeReuse"),
      Undefined,
      [Number(1.0)],
      @token.Loc::default(),
    ) {
    Number(value) => assert_true(value == 2.0)
    _ => fail("the interpreter must remain reusable after abrupt completion")
  }
}

///|
test "legacy call releases one admitted leaf activation on normal completion" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "var entries = 0; " +
      "function bridgeLeaf(n) { return n + 1; } " +
      "function legacyLeaf(n) { " +
      "entries = entries + 1; return bridgeLeaf(n); }",
    ).stmts,
  )
  let events : Array[String] = []
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  install_executor_activation_probe(interp, events, None, control=Some(control))
  let result = interp.call_value(
    interp.global.get("legacyLeaf"),
    Undefined,
    [Number(1.0)],
    @token.Loc::default(),
  )
  match result {
    Number(value) => assert_true(value == 2.0)
    _ => fail("the admitted leaf must return through its legacy consumer")
  }
  json_inspect(events, content=["attempt:cleared", "release:cleared"])
  assert_eq(control.active_depth(), 0L)
  assert_true(interp.global.get("entries") is Number(1.0))
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
test "tree admission rejects an unsupported native callee on an otherwise supported body" {
  let interp = Interpreter::new()
  let native_leaf = make_native_func(name="nativeLeaf", args => args[0])
  interp.global.def_builtin("nativeLeaf", native_leaf)
  let _ = interp.run(
    @parser.parse("function nativeParent(n) { return nativeLeaf(n) + 1; }").stmts,
  )
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("nativeParent"),
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
      fail(
        "an unsupported native callee must keep the root on legacy execution",
      )
  }
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission rejects unsupported earlier calls before effects" {
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
fn executor_activation_deep_acyclic_tree_call_graph(
  interp : Interpreter,
  depth : Int,
) -> Value raise Error {
  let parameter = "n"
  let leaf_name = "iterativeAdmission" + depth.to_string()
  let leaf_data : FuncData = {
    name: Some(leaf_name),
    params: [parameter],
    body: @parser.parse("return n;").stmts,
    closure: interp.global,
    strict: false,
    has_name_binding: false,
    is_method: false,
    source_text: None,
    materializer: None,
  }
  interp.global.def_builtin(leaf_name, make_func(leaf_data))
  for index = depth - 1; index >= 0; index = index - 1 {
    let name = "iterativeAdmission" + index.to_string()
    let next_name = "iterativeAdmission" + (index + 1).to_string()
    let data : FuncData = {
      name: Some(name),
      params: [parameter],
      body: @parser.parse("return " + next_name + "(n) + 1;").stmts,
      closure: interp.global,
      strict: false,
      has_name_binding: false,
      is_method: false,
      source_text: None,
      materializer: None,
    }
    interp.global.def_builtin(name, make_func(data))
  }
  interp.global.get("iterativeAdmission0")
}

///|
test "tree admission handles a deep acyclic callable graph without host recursion" {
  let interp = Interpreter::new()
  let root_callable = executor_activation_deep_acyclic_tree_call_graph(
    interp, 8192,
  )
  let control = ExecutionControl(
    remaining_steps=10,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=root_callable,
      this_value=Undefined,
      args=[Number(1.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let outcome = interp.with_execution_control(control, () => {
    let _ = interp.run_executor_activation_coordinator(root)
    "completed"
  }) catch {
    ExecutionControlError(StackDepthLimit) => "stack-depth-limit"
    _ => "other-error"
  }
  inspect(outcome, content="stack-depth-limit")
  inspect(control.active_depth(), content="0")
}

///|
test "iterative tree admission terminates on a mutual callable cycle" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "function iterativeCycleLeft(n) { " +
      "if (n === 0) return 0; " +
      "return iterativeCycleRight(n - 1) + 1; } " +
      "function iterativeCycleRight(n) { " +
      "if (n === 0) return 0; " +
      "return iterativeCycleLeft(n - 1) + 1; }",
    ).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=10,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("iterativeCycleLeft"),
      this_value=Undefined,
      args=[Number(2.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let outcome = interp.with_execution_control(control, () => {
    let _ = interp.run_executor_activation_coordinator(root)
    "completed"
  }) catch {
    ExecutionControlError(StackDepthLimit) => "stack-depth-limit"
    _ => "other-error"
  }
  inspect(outcome, content="stack-depth-limit")
  inspect(control.active_depth(), content="0")
}

///|
test "generic executor code cannot gain tree admission" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let child = make_executor_function(
    Some("missingSummaryLeaf"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationValueCode(starts~, value=Number(7.0)),
    constructable=false,
  )
  interp.global.def_builtin("missingSummaryLeaf", child)
  let _ = interp.run(
    @parser.parse(
      "function missingSummaryParent(n) { return missingSummaryLeaf(n) + 1; }",
    ).stmts,
  )
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("missingSummaryParent"),
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
    _ => fail("missing child summaries must keep the root on legacy execution")
  }
  inspect(starts.val, content="1")
  json_inspect(events, content=[])
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission rejects native target resolution without preflight effects" {
  let interp = Interpreter::new()
  let native_calls : Ref[Int] = { val: 0 }
  let native_leaf = make_native_func(name="nativeResolutionLeaf", fn(args) {
    native_calls.val += 1
    args[0]
  })
  interp.global.def_builtin("nativeResolutionLeaf", native_leaf)
  let _ = interp.run(
    @parser.parse(
      "function nativeResolutionParent(n) { " +
      "return nativeResolutionLeaf(n) + 1; }",
    ).stmts,
  )
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("nativeResolutionParent"),
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
    _ => fail("native target resolution must keep the root on legacy execution")
  }
  inspect(native_calls.val, content="1")
  json_inspect(events, content=[])
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission accepts supported numeric expression statements" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse("function numericStatement(n) { n + 1; return n + 2; }").stmts,
  )
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("numericStatement"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let outcome = interp.with_execution_control(control, () => {
    try {
      let _ = interp.run_executor_activation_coordinator(root)
      "legacy"
    } catch {
      ExecutionControlError(StackDepthLimit) => "admitted"
      _ => "other-error"
    }
  })
  inspect(outcome, content="admitted")
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission accepts two direct numeric callees" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "function multiCallFirst(n) { return n + 1; } " +
      "function multiCallSecond(n) { return n + 2; } " +
      "function multiCallParent(n) { " +
      "return multiCallFirst(n) + multiCallSecond(n); }",
    ).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("multiCallParent"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let outcome = interp.with_execution_control(control, () => {
    try {
      let _ = interp.run_executor_activation_coordinator(root)
      "legacy"
    } catch {
      ExecutionControlError(StackDepthLimit) => "admitted"
      _ => "other-error"
    }
  })
  inspect(outcome, content="admitted")
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission accepts a result-fed direct call" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "function resultFedInner(n) { return n + 1; } " +
      "function resultFedOuter(n) { return n + 2; } " +
      "function resultFedRoot(n) { return resultFedOuter(resultFedInner(n)); }",
    ).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("resultFedRoot"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let outcome = interp.with_execution_control(control, () => {
    try {
      let _ = interp.run_executor_activation_coordinator(root)
      "legacy"
    } catch {
      ExecutionControlError(StackDepthLimit) => "admitted"
      _ => "other-error"
    }
  })
  inspect(outcome, content="admitted")
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission seals the receiver of a static own-data member call" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "var holder = {}; var replacementHolder = {}; " +
      "function memberParent(n) { return holder.outer(inner(n)); }",
    ).stmts,
  )
  let holder = interp.global.get("holder")
  let replacement_holder = interp.global.get("replacementHolder")
  let inner = make_classified_executor_function(
    Some("inner"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationMutateBindingCode(
      closure=interp.global,
      binding_name="holder",
      replacement=replacement_holder,
      value=Number(1.0),
    ),
    @parser.parse("return n;").stmts,
    constructable=false,
  )
  interp.global.def_builtin("inner", inner)
  let outer = make_executor_callable_with_capability(
    "outer",
    ["n"],
    interp.global,
    false,
    ExecutorActivationThisValueCode(expected=holder, value=Number(9.0))
    as &ExecutorCode,
    None,
    false,
    None,
    false,
    OrdinaryExecutorCallable,
    Some(
      ExecutorActivationCapabilitySummary(parameter_count=1, direct_calls=[]),
    ),
    None,
  )
  match holder {
    Object(data) => data.bag.properties["outer"] = outer
    _ => fail("holder fixture must be an object")
  }
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("memberParent"),
      this_value=Undefined,
      args=[Number(1.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="9")
    _ => fail("the admitted member call must preserve its sealed receiver")
  }
  assert_true(physical_equal(interp.global.get("holder"), replacement_holder))
}

///|
test "tree admission keeps a parameter-shadowed member receiver on legacy execution" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "var shadowedHolder = {}; " +
      "function shadowedParent(shadowedHolder) { " +
      "return shadowedHolder.outer(1); }",
    ).stmts,
  )
  let starts : Ref[Int] = { val: 0 }
  let outer = make_classified_executor_function(
    Some("shadowedOuter"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationValueCode(starts~, value=Number(9.0)),
    @parser.parse("return n;").stmts,
    constructable=false,
  )
  match interp.global.get("shadowedHolder") {
    Object(data) => data.bag.properties["outer"] = outer
    _ => fail("shadowed holder fixture must be an object")
  }
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("shadowedParent"),
      this_value=Undefined,
      args=[Number(3.0)],
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
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("expected legacy TypeError, got " + error.to_string())
    None => fail("a parameter receiver must shadow its closure binding")
  }
  inspect(starts.val, content="0")
}

///|
test "tree admission rejects a static accessor member without preflight effects" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "function memberLeaf(n) { return n + 1; } " +
      "var accessorHolder = {}; " +
      "function accessorParent(n) { return accessorHolder.outer(n); }",
    ).stmts,
  )
  let getter_reads : Ref[Int] = { val: 0 }
  let getter = make_native_func(name="memberGetter", _args => {
    getter_reads.val += 1
    interp.global.get("memberLeaf")
  })
  match interp.global.get("accessorHolder") {
    Object(data) =>
      data.bag.descriptors["outer"] = {
        writable: false,
        enumerable: true,
        configurable: true,
        getter: Some(getter),
        setter: None,
        is_accessor: true,
      }
    _ => fail("accessor holder fixture must be an object")
  }
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("accessorParent"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.run_executor_activation_coordinator(root)
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="4")
    _ => fail("an accessor member must remain on legacy execution")
  }
  inspect(getter_reads.val, content="1")
}

///|
test "tree admission rejects dynamic member keys without preflight effects" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "function dynamicMemberLeaf(n) { return n + 1; } " +
      "var dynamicHolder = {}; " +
      "function dynamicMemberParent(n) { " +
      "return dynamicHolder[dynamicMemberKey()](n); }",
    ).stmts,
  )
  let key_reads : Ref[Int] = { val: 0 }
  let dynamic_key = make_native_func(name="dynamicMemberKey", _args => {
    key_reads.val += 1
    String_("outer")
  })
  interp.global.def_builtin("dynamicMemberKey", dynamic_key)
  match interp.global.get("dynamicHolder") {
    Object(data) =>
      data.bag.properties["outer"] = interp.global.get("dynamicMemberLeaf")
    _ => fail("dynamic holder fixture must be an object")
  }
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("dynamicMemberParent"),
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
    _ => fail("a dynamic member key must keep the root on legacy execution")
  }
  inspect(key_reads.val, content="1")
  inspect(control.active_depth(), content="0")
}

///|
test "tree execution preserves result-fed call result and order" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let inner = make_classified_executor_function(
    Some("resultFedInner"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationOrderedIncrementCode(
      events~,
      label="inner",
      increment=1.0,
    ),
    @parser.parse("return n + 1;").stmts,
    constructable=false,
  )
  let outer = make_classified_executor_function(
    Some("resultFedOuter"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationOrderedIncrementCode(
      events~,
      label="outer",
      increment=2.0,
    ),
    @parser.parse("return n + 2;").stmts,
    constructable=false,
  )
  interp.global.def_builtin("resultFedInner", inner)
  interp.global.def_builtin("resultFedOuter", outer)
  let _ = interp.run(
    @parser.parse(
      "function resultFedOrderedRoot(n) { " +
      "return resultFedOuter(resultFedInner(n)); }",
    ).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=200,
    maximum_active_depth=20,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("resultFedOrderedRoot"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="6")
    _ => fail("result-fed direct calls must return the outer numeric result")
  }
  json_inspect(events, content=["inner", "outer"])
  inspect(control.active_depth(), content="0")
}

///|
test "closed result-fed tree plan keeps outer target after inner mutation" {
  let interp = Interpreter::new()
  let legacy_calls : Ref[Int] = { val: 0 }
  let native_replacement = make_native_func(name="resultFedLegacy", fn(_args) {
    legacy_calls.val += 1
    Number(100.0)
  })
  let inner = make_classified_executor_function(
    Some("resultFedMutationInner"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationMutateBindingCode(
      closure=interp.global,
      binding_name="resultFedMutationOuter",
      replacement=native_replacement,
      value=Number(4.0),
    ),
    @parser.parse("return n;").stmts,
    constructable=false,
  )
  interp.global.def_builtin("resultFedMutationInner", inner)
  let _ = interp.run(
    @parser.parse(
      "function resultFedMutationOuter(n) { return n + 2; } " +
      "function resultFedMutationRoot(n) { " +
      "return resultFedMutationOuter(resultFedMutationInner(n)); }",
    ).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=200,
    maximum_active_depth=20,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("resultFedMutationRoot"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="6")
    _ => fail("closed result-fed graph must retain the prevalidated outer")
  }
  inspect(legacy_calls.val, content="0")
  inspect(control.active_depth(), content="0")
}

///|
test "result-fed inner abrupt completion preserves identity and cleanup" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(message="result-fed inner sentinel")
  let inner = make_classified_executor_function(
    Some("resultFedInnerThrow"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationThrowCode(error=sentinel),
    @parser.parse("return n;").stmts,
    constructable=false,
  )
  interp.global.def_builtin("resultFedInnerThrow", inner)
  let _ = interp.run(
    @parser.parse(
      "function resultFedInnerOuter(n) { return n + 2; } " +
      "function resultFedInnerRoot(n) { " +
      "return resultFedInnerOuter(resultFedInnerThrow(n)); }",
    ).stmts,
  )
  let events : Array[String] = []
  let control = ExecutionControl(
    remaining_steps=200,
    maximum_active_depth=20,
    interruption=ExecutionInterruptionRequest(),
  )
  install_executor_activation_probe(interp, events, None, control=Some(control))
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("resultFedInnerRoot"),
      this_value=Undefined,
      args=[Number(3.0)],
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
    None => fail("result-fed inner throw must preserve its error")
  }
  json_inspect(events, content=[
    "attempt:cleared", "attempt:outer", "release:outer", "release:cleared",
  ])
  inspect(control.active_depth(), content="0")
  assert_true(interp.realm_state.active_overrides.val is None)
  match control.with_activation(() => Number(1.0)) {
    Ok(Number(value)) => inspect(value, content="1")
    _ => fail("execution control must permit reuse after inner abrupt unwind")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "result-fed outer abrupt completion preserves identity and cleanup" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(message="result-fed outer sentinel")
  let outer = make_classified_executor_function(
    Some("resultFedOuterThrow"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationThrowCode(error=sentinel),
    @parser.parse("return n;").stmts,
    constructable=false,
  )
  interp.global.def_builtin("resultFedOuterThrow", outer)
  let _ = interp.run(
    @parser.parse(
      "function resultFedOuterInner(n) { return n + 1; } " +
      "function resultFedOuterRoot(n) { " +
      "return resultFedOuterThrow(resultFedOuterInner(n)); }",
    ).stmts,
  )
  let events : Array[String] = []
  let control = ExecutionControl(
    remaining_steps=200,
    maximum_active_depth=20,
    interruption=ExecutionInterruptionRequest(),
  )
  install_executor_activation_probe(interp, events, None, control=Some(control))
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("resultFedOuterRoot"),
      this_value=Undefined,
      args=[Number(3.0)],
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
    None => fail("result-fed outer throw must preserve its error")
  }
  json_inspect(events, content=[
    "attempt:cleared", "attempt:outer", "release:outer", "attempt:outer", "release:outer",
    "release:cleared",
  ])
  inspect(control.active_depth(), content="0")
  assert_true(interp.realm_state.active_overrides.val is None)
  match control.with_activation(() => Number(1.0)) {
    Ok(Number(value)) => inspect(value, content="1")
    _ => fail("execution control must permit reuse after outer abrupt unwind")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "result-fed inner native target keeps the root legacy" {
  let interp = Interpreter::new()
  let native_calls : Ref[Int] = { val: 0 }
  let native_inner = make_native_func(name="resultFedNativeInner", args => {
    native_calls.val += 1
    match args {
      [Number(value)] => Number(value + 1.0)
      _ => fail("result-fed native inner must receive one number")
    }
  })
  interp.global.def_builtin("resultFedNativeInner", native_inner)
  let _ = interp.run(
    @parser.parse(
      "function resultFedNativeInnerOuter(n) { return n + 2; } " +
      "function resultFedNativeInnerRoot(n) { " +
      "return resultFedNativeInnerOuter(resultFedNativeInner(n)); }",
    ).stmts,
  )
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let control = ExecutionControl(
    remaining_steps=200,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("resultFedNativeInnerRoot"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="6")
    _ => fail("native inner rejection must complete through the legacy path")
  }
  inspect(native_calls.val, content="1")
  json_inspect(events, content=[])
  inspect(control.active_depth(), content="0")
}

///|
test "result-fed outer native target keeps the root legacy" {
  let interp = Interpreter::new()
  let native_calls : Ref[Int] = { val: 0 }
  let native_outer = make_native_func(name="resultFedNativeOuter", args => {
    native_calls.val += 1
    match args {
      [Number(value)] => Number(value + 2.0)
      _ => fail("result-fed native outer must receive one number")
    }
  })
  interp.global.def_builtin("resultFedNativeOuter", native_outer)
  let _ = interp.run(
    @parser.parse(
      "function resultFedNativeOuterInner(n) { return n + 1; } " +
      "function resultFedNativeOuterRoot(n) { " +
      "return resultFedNativeOuter(resultFedNativeOuterInner(n)); }",
    ).stmts,
  )
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let control = ExecutionControl(
    remaining_steps=200,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("resultFedNativeOuterRoot"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="6")
    _ => fail("native outer rejection must complete through the legacy path")
  }
  inspect(native_calls.val, content="1")
  json_inspect(events, content=[])
  inspect(control.active_depth(), content="0")
}

///|
test "result-fed inner unresolved target rejects the whole root before admission" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "function resultFedUnresolvedInnerOuter(n) { return n + 2; } " +
      "function resultFedUnresolvedInnerRoot(n) { " +
      "return resultFedUnresolvedInnerOuter(resultFedMissingInner(n)); }",
    ).stmts,
  )
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let control = ExecutionControl(
    remaining_steps=200,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("resultFedUnresolvedInnerRoot"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let caught : Error? = try {
    let _ = interp.with_execution_control(control, () => {
      interp.run_executor_activation_coordinator(root)
    })
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(ExecutionControlError(StackDepthLimit)) =>
      fail("unresolved inner must reject before managed execution")
    Some(_) => ()
    None => fail("unresolved inner must fail through the legacy path")
  }
  json_inspect(events, content=[])
  inspect(control.active_depth(), content="0")
}

///|
test "result-fed outer unresolved target rejects the whole root before admission" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "function resultFedUnresolvedOuterInner(n) { return n + 1; } " +
      "function resultFedUnresolvedOuterRoot(n) { " +
      "return resultFedMissingOuter(resultFedUnresolvedOuterInner(n)); }",
    ).stmts,
  )
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let control = ExecutionControl(
    remaining_steps=200,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("resultFedUnresolvedOuterRoot"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let caught : Error? = try {
    let _ = interp.with_execution_control(control, () => {
      interp.run_executor_activation_coordinator(root)
    })
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(ExecutionControlError(StackDepthLimit)) =>
      fail("unresolved outer must reject before managed execution")
    Some(_) => ()
    None => fail("unresolved outer must fail through the legacy path")
  }
  json_inspect(events, content=[])
  inspect(control.active_depth(), content="0")
}

///|
test "result-fed inner arity mismatch keeps the root legacy" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "function resultFedArityInner(n, extra) { return n; } " +
      "function resultFedArityInnerOuter(n) { return n + 2; } " +
      "function resultFedArityInnerRoot(n) { " +
      "return resultFedArityInnerOuter(resultFedArityInner(n)); }",
    ).stmts,
  )
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let control = ExecutionControl(
    remaining_steps=200,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("resultFedArityInnerRoot"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="5")
    _ => fail("inner arity rejection must complete through the legacy path")
  }
  json_inspect(events, content=[])
  inspect(control.active_depth(), content="0")
}

///|
test "result-fed outer arity mismatch keeps the root legacy" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "function resultFedArityOuterInner(n) { return n + 1; } " +
      "function resultFedArityOuter(n, extra) { return n + 2; } " +
      "function resultFedArityOuterRoot(n) { " +
      "return resultFedArityOuter(resultFedArityOuterInner(n)); }",
    ).stmts,
  )
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let control = ExecutionControl(
    remaining_steps=200,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("resultFedArityOuterRoot"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="6")
    _ => fail("outer arity rejection must complete through the legacy path")
  }
  json_inspect(events, content=[])
  inspect(control.active_depth(), content="0")
}

///|
test "tree execution preserves two direct call result and order" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let first = make_classified_executor_function(
    Some("orderedFirst"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationOrderedValueCode(
      events~,
      label="first",
      value=Number(4.0),
    ),
    @parser.parse("return n;").stmts,
    constructable=false,
  )
  let second = make_classified_executor_function(
    Some("orderedSecond"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationOrderedValueCode(
      events~,
      label="second",
      value=Number(4.0),
    ),
    @parser.parse("return n;").stmts,
    constructable=false,
  )
  interp.global.def_builtin("orderedFirst", first)
  interp.global.def_builtin("orderedSecond", second)
  let _ = interp.run(
    @parser.parse(
      "function orderedParent(n) { " +
      "return orderedFirst(n) + orderedSecond(n); }",
    ).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=10,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("orderedParent"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="8")
    _ => fail("two admitted direct calls must return their numeric result")
  }
  json_inspect(events, content=["first", "second"])
  inspect(control.active_depth(), content="0")
}

///|
test "closed tree plan keeps nested targets after sibling mutation" {
  let interp = Interpreter::new()
  let legacy_calls : Ref[Int] = { val: 0 }
  let native_replacement = make_native_func(name="closedLegacy", fn(_args) {
    legacy_calls.val += 1
    Number(100.0)
  })
  let mutator = make_classified_executor_function(
    Some("closedMutator"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationMutateBindingCode(
      closure=interp.global,
      binding_name="closedNested",
      replacement=native_replacement,
      value=Number(0.0),
    ),
    @parser.parse("return n;").stmts,
    constructable=false,
  )
  interp.global.def_builtin("closedMutator", mutator)
  let _ = interp.run(
    @parser.parse(
      "function closedNested(n) { return n + 1; } " +
      "function closedSibling(n) { return closedNested(n); } " +
      "function closedRoot(n) { " +
      "return closedMutator(n) + closedSibling(n); }",
    ).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=200,
    maximum_active_depth=20,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("closedRoot"),
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
    _ => fail("closed graph must retain the prevalidated nested target")
  }
  inspect(legacy_calls.val, content="0")
  inspect(control.active_depth(), content="0")
}

///|
test "tree execution preserves duplicate direct call sites" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let duplicate = make_classified_executor_function(
    Some("duplicateLeaf"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationOrderedValueCode(
      events~,
      label="duplicate",
      value=Number(5.0),
    ),
    @parser.parse("return n;").stmts,
    constructable=false,
  )
  interp.global.def_builtin("duplicateLeaf", duplicate)
  let _ = interp.run(
    @parser.parse(
      "function duplicateRoot(n) { " +
      "return duplicateLeaf(n) + duplicateLeaf(n); }",
    ).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=200,
    maximum_active_depth=20,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("duplicateRoot"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="10")
    _ => fail("duplicate direct calls must execute in source order")
  }
  json_inspect(events, content=["duplicate", "duplicate"])
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission rejects an unsupported unselected branch without preflight effects" {
  let interp = Interpreter::new()
  let native_calls : Ref[Int] = { val: 0 }
  let native_branch = make_native_func(name="branchNative", fn(args) {
    native_calls.val += 1
    args[0]
  })
  interp.global.def_builtin("branchNative", native_branch)
  let _ = interp.run(
    @parser.parse(
      "function branchSafe(n) { return n + 1; } " +
      "function branchRoot(n) { " +
      "if (n === 0) return branchSafe(n); " +
      "else return branchNative(n); }",
    ).stmts,
  )
  let probe_events : Array[String] = []
  install_executor_activation_probe(interp, probe_events, None)
  let control = ExecutionControl(
    remaining_steps=200,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("branchRoot"),
      this_value=Undefined,
      args=[Number(0.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let outcome = interp.with_execution_control(control, () => {
    try {
      match interp.run_executor_activation_coordinator(root) {
        ExecutorActivationReturn(Number(value)) => "legacy:" + value.to_string()
        _ => "other"
      }
    } catch {
      ExecutionControlError(StackDepthLimit) => "admitted"
      _ => "error"
    }
  })
  inspect(outcome, content="legacy:1")
  inspect(native_calls.val, content="0")
  json_inspect(probe_events, content=[])
  inspect(control.active_depth(), content="0")
}

///|
fn executor_activation_deep_branching_tree_source(depth : Int) -> String {
  let definitions : Array[String] = []
  let mut leaf_count = 1
  for _ in 0..<depth {
    leaf_count *= 2
  }
  for index in 0..<leaf_count {
    let name = "deepBranch" + depth.to_string() + "_" + index.to_string()
    definitions.push("function " + name + "(n) { return n; } ")
  }
  for level = depth - 1; level >= 0; level = level - 1 {
    let mut node_count = 1
    for _ in 0..<level {
      node_count *= 2
    }
    for index in 0..<node_count {
      let name = "deepBranch" + level.to_string() + "_" + index.to_string()
      let left = "deepBranch" +
        (level + 1).to_string() +
        "_" +
        (index * 2).to_string()
      let right = "deepBranch" +
        (level + 1).to_string() +
        "_" +
        (index * 2 + 1).to_string()
      definitions.push(
        "function " +
        name +
        "(n) { " +
        "if (n === 0) return " +
        left +
        "(n); " +
        "else return " +
        right +
        "(n); } ",
      )
    }
  }
  definitions.join("")
}

///|
test "iterative tree admission handles a deep branching graph" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(executor_activation_deep_branching_tree_source(10)).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=5000,
    maximum_active_depth=100,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("deepBranch0_0"),
      this_value=Undefined,
      args=[Number(0.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="0")
    _ => fail("deep branching admission must complete without host recursion")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission rejects a supported and native callee together" {
  let interp = Interpreter::new()
  let native_calls : Ref[Int] = { val: 0 }
  let native_leaf = make_native_func(name="multiNative", fn(args) {
    native_calls.val += 1
    args[0]
  })
  interp.global.def_builtin("multiNative", native_leaf)
  let _ = interp.run(
    @parser.parse(
      "function multiSupported(n) { return n + 1; } " +
      "function multiRejected(n) { " +
      "return multiSupported(n) + multiNative(n); }",
    ).stmts,
  )
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("multiRejected"),
      this_value=Undefined,
      args=[Number(3.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="7")
    _ => fail("an unsupported sibling callee must keep the whole root legacy")
  }
  inspect(native_calls.val, content="1")
  json_inspect(events, content=[])
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission rejects a direct callee with mismatched arity" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "function arityLeaf(n, extra) { return n; } " +
      "function arityParent(n) { return arityLeaf(n) + 1; }",
    ).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("arityParent"),
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
    _ => fail("arity mismatch must keep the root on legacy execution")
  }
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
  let child = make_classified_executor_function(
    Some("objectLeaf"),
    ["n"],
    interp.global,
    false,
    ExecutorActivationValueCode(starts~, value=object_result),
    @parser.parse("return {};").stmts,
    constructable=false,
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
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
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
  json_inspect(events, content=[])
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission rejects with getter closures without preflight effects" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "var withReads = 0; var savedWithCall; " +
      "function withPeer(n) { return n; } " +
      "var withScope = { get withPeer() { withReads = withReads + 1; return withPeer; } }; " +
      "with (withScope) { " +
      "savedWithCall = function(n) { " +
      "if (n === 0) return 0; return withPeer(n - 1) + 1; }; }",
    ).stmts,
  )
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("savedWithCall"),
      this_value=Undefined,
      args=[Number(1.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="1")
    _ => fail("with closures must stay on legacy execution before admission")
  }
  inspect(interp.global.get("withReads").to_string(), content="1")
  inspect(control.active_depth(), content="0")
}

///|
test "tree admission rejects with proxy closures without preflight traps" {
  let interp = Interpreter::new()
  let _ = interp.run(
    @parser.parse(
      "function proxyPeer(n) { return n; } " +
      "function proxyTemplate(n) { " +
      "if (n === 0) return 0; return proxyPeer(n - 1) + 1; }",
    ).stmts,
  )
  let peer = interp.global.get("proxyPeer")
  let template = match interp.global.get("proxyTemplate") {
    Object({ callable: Some(UserFunc(data)), .. }) => data
    _ => fail("expected proxy closure template")
  }
  let has_calls : Ref[Int] = { val: 0 }
  let get_calls : Ref[Int] = { val: 0 }
  let has_trap = make_native_func(name="has", fn(args) {
    match args[1] {
      String_("proxyPeer") => {
        has_calls.val += 1
        Bool(true)
      }
      _ => Bool(false)
    }
  })
  let get_trap = make_native_func(name="get", fn(args) {
    match args[1] {
      String_("proxyPeer") => {
        get_calls.val += 1
        peer
      }
      _ => Undefined
    }
  })
  let proxy_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let proxy_handler = make_object(
    { "has": has_trap, "get": get_trap },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let proxy_closure = Environment::new(parent=Some(interp.global))
  proxy_closure.with_object = Some(
    Proxy({
      target: Some(proxy_target),
      handler: Some(proxy_handler),
      is_callable: false,
      is_constructor: false,
    }),
  )
  let saved = make_func({
    name: Some("savedProxyCall"),
    params: template.params,
    body: template.body,
    closure: proxy_closure,
    strict: template.strict,
    has_name_binding: false,
    is_method: false,
    source_text: template.source_text,
    materializer: None,
  })
  interp.global.def_builtin("savedProxyCall", saved)
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let root = ExecutorActivationCallFrame(
      callee=interp.global.get("savedProxyCall"),
      this_value=Undefined,
      args=[Number(1.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let result = interp.with_execution_control(control, () => {
    interp.run_executor_activation_coordinator(root)
  })
  match result {
    ExecutorActivationReturn(Number(value)) => inspect(value, content="1")
    _ => fail("with proxy closures must stay on legacy execution")
  }
  inspect(has_calls.val, content="2")
  inspect(get_calls.val, content="1")
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

///|
test "static property setter admission rejects mutable exotic state" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let setter = make_executor_function(
    Some("setter"),
    ["value"],
    interp.global,
    false,
    ExecutorActivationValueCode(starts~, value=Number(1.0)),
    constructable=false,
  )
  let ordinary = make_direct_property_setter_target(setter, None)
  match direct_executor_property_setter(ordinary, "x") {
    Some((admitted, _)) => assert_true(physical_equal(admitted, setter))
    None => fail("ordinary object setter should be admitted")
  }
  let with_arraybuffer = make_direct_property_setter_target(
    setter,
    Some(ArrayBufferState::ArrayBufferState()),
  )
  assert_true(direct_executor_property_setter(with_arraybuffer, "x") is None)
  let with_internal_slot = make_direct_property_setter_target(
    setter,
    None,
    internal_slot=(StringData, String_("state")),
  )
  assert_true(direct_executor_property_setter(with_internal_slot, "x") is None)
  let with_host_slot = make_direct_property_setter_target(
    setter,
    None,
    host_slot=(1, Number(1.0)),
  )
  assert_true(direct_executor_property_setter(with_host_slot, "x") is None)
}

///|
test "property activation setter returns original RHS and releases scope" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let setter = make_executor_function(
    Some("setter"),
    ["value"],
    interp.global,
    false,
    ExecutorActivationValueCode(starts~, value=Number(99.0)),
    constructable=false,
  )
  let target = make_direct_property_setter_target(setter, None)
  let rhs = Object({
    bag: PropertyBag::PropertyBag(),
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  let events : Array[String] = []
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  install_executor_activation_probe(interp, events, None, control=Some(control))
  let result = run_executor_property_set_root_for_wb(
    interp, target, "x", rhs, false,
  )
  assert_true(physical_equal(result, rhs))
  inspect(starts.val, content="1")
  json_inspect(events, content=["attempt:cleared", "release:cleared"])
  inspect(control.active_depth(), content="0")
}

///|
test "property update core plans results and reduces completions deterministically" {
  let loc = @token.Loc::default()
  let increment = ExecutorPropertyUpdateRequest(
    target=String_("target"),
    property_name="x",
    operator=ExecutorPropertyIncrement,
    prefix=false,
    member_loc=loc,
    loc~,
    strict=false,
  )
  let (increment_phase, increment_step) = plan_executor_property_update_set(
    increment, 4.0,
  )
  match increment_phase {
    ExecutorPropertyUpdateAwaitSet(Number(result)) =>
      inspect(result, content="4")
    _ => fail("postfix increment must retain the old numeric result")
  }
  match increment_step {
    ExecutorActivationPropertySet(request) =>
      match request.value {
        Number(value) => inspect(value, content="5")
        _ => fail("increment must set the next numeric value")
      }
    _ => fail("increment planning must request a property set")
  }
  let decrement = ExecutorPropertyUpdateRequest(
    target=String_("target"),
    property_name="x",
    operator=ExecutorPropertyDecrement,
    prefix=true,
    member_loc=loc,
    loc~,
    strict=false,
  )
  let (decrement_phase, decrement_step) = plan_executor_property_update_set(
    decrement, 4.0,
  )
  match decrement_phase {
    ExecutorPropertyUpdateAwaitSet(Number(result)) =>
      inspect(result, content="3")
    _ => fail("prefix decrement must retain the next numeric result")
  }
  match decrement_step {
    ExecutorActivationPropertySet(request) =>
      match request.value {
        Number(value) => inspect(value, content="3")
        _ => fail("decrement must set the next numeric value")
      }
    _ => fail("decrement planning must request a property set")
  }
  let delivered = reduce_executor_property_update_completion(
    ExecutorPropertyUpdateAwaitGet,
    ExecutorActivationCompletionNormal(Number(7.0)),
  )
  match delivered {
    ExecutorPropertyUpdateHaveCurrent(Number(value)) =>
      inspect(value, content="7")
    _ => fail("get completion must become the current update value")
  }
}

///|
test "coercing addition frame completes primitive operands" {
  let interp = Interpreter::new()
  let number_result = run_executor_coercing_addition_root_for_wb(
    interp,
    Number(2.0),
    Number(3.0),
  )
  match number_result {
    Number(value) => inspect(value, content="5")
    _ => fail("primitive numeric addition must return a number")
  }
  let string_result = run_executor_coercing_addition_root_for_wb(
    interp,
    String_("left"),
    Number(3.0),
  )
  match string_result {
    String_(value) => inspect(value, content="left3")
    _ => fail("a primitive string must select string addition")
  }
}

///|
test "coercing addition start selects completion or suspension" {
  let loc = @token.Loc::default()
  match begin_executor_coercing_addition(Number(1.0), Number(2.0), loc) {
    ExecutorCoercingAdditionCompleted(Number(value)) =>
      inspect(value, content="3")
    ExecutorCoercingAdditionCompleted(_) =>
      fail("number addition must complete with a number")
    ExecutorCoercingAdditionSuspended(_) =>
      fail("primitive number addition must not create a child frame")
  }
  match begin_executor_coercing_addition(String_("x"), String_("y"), loc) {
    ExecutorCoercingAdditionCompleted(String_(value)) =>
      inspect(value, content="xy")
    ExecutorCoercingAdditionCompleted(_) =>
      fail("string addition must complete with a string")
    ExecutorCoercingAdditionSuspended(_) =>
      fail("primitive string addition must not create a child frame")
  }
  let object = make_object(Map([]), Null, None, "Object", Map([]), true)
  match begin_executor_coercing_addition(object, Number(2.0), loc) {
    ExecutorCoercingAdditionSuspended(_) => ()
    ExecutorCoercingAdditionCompleted(_) =>
      fail("object + primitive must request a child frame")
  }
  match begin_executor_coercing_addition(Number(2.0), object, loc) {
    ExecutorCoercingAdditionSuspended(_) => ()
    ExecutorCoercingAdditionCompleted(_) =>
      fail("primitive + object must request a child frame")
  }
  let symbol_error : Error? = try {
    let _ = begin_executor_coercing_addition(
      Symbol({ id: 9002, description: None }),
      Number(1.0),
      loc,
    )
    None
  } catch {
    error => Some(error)
  }
  match symbol_error {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("expected Symbol TypeError, got " + error.to_string())
    None => fail("Symbol numeric addition must throw synchronously")
  }
}

///|
test "coercing subtraction frame completes primitive operands" {
  let interp = Interpreter::new()
  let number_result = run_executor_coercing_subtraction_root_for_wb(
    interp,
    Number(5.0),
    Number(2.0),
  )
  match number_result {
    Number(value) => inspect(value, content="3")
    _ => fail("primitive numeric subtraction must return a number")
  }
  let string_result = run_executor_coercing_subtraction_root_for_wb(
    interp,
    String_("7"),
    String_("2"),
  )
  match string_result {
    Number(value) => inspect(value, content="5")
    _ => fail("string subtraction must return a number")
  }
  let bool_result = run_executor_coercing_subtraction_root_for_wb(
    interp,
    Bool(true),
    Null,
  )
  match bool_result {
    Number(value) => inspect(value, content="1")
    _ => fail("boolean subtraction must use Number conversion")
  }
}

///|
test "coercing subtraction start selects completion or suspension" {
  let loc = @token.Loc::default()
  match begin_executor_coercing_subtraction(Number(5.0), Number(2.0), loc) {
    ExecutorCoercingSubtractionCompleted(Number(value)) =>
      inspect(value, content="3")
    ExecutorCoercingSubtractionCompleted(_) =>
      fail("number subtraction must complete with a number")
    ExecutorCoercingSubtractionSuspended(_) =>
      fail("primitive subtraction must not create a child frame")
  }
  match begin_executor_coercing_subtraction(String_("7"), String_("2"), loc) {
    ExecutorCoercingSubtractionCompleted(Number(value)) =>
      inspect(value, content="5")
    ExecutorCoercingSubtractionCompleted(_) =>
      fail("string subtraction must complete with a number")
    ExecutorCoercingSubtractionSuspended(_) =>
      fail("primitive string subtraction must not create a child frame")
  }
  let object = make_object(Map([]), Null, None, "Object", Map([]), true)
  match begin_executor_coercing_subtraction(object, Number(2.0), loc) {
    ExecutorCoercingSubtractionSuspended(_) => ()
    ExecutorCoercingSubtractionCompleted(_) =>
      fail("object subtraction must request a child frame")
  }
  let symbol_error : Error? = try {
    let _ = begin_executor_coercing_subtraction(
      Symbol({ id: 9002, description: None }),
      Number(1.0),
      loc,
    )
    None
  } catch {
    error => Some(error)
  }
  match symbol_error {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("expected Symbol TypeError, got " + error.to_string())
    None => fail("Symbol subtraction must throw synchronously")
  }
}

///|
test "coercing subtraction uses number hint and original receiver" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let receiver : Ref[Value] = { val: Undefined }
  let hook = make_method_func(
    name="@@toPrimitive",
    realm_state=Some(interp.realm_state),
    fn(this_value, args) raise {
      assert_true(physical_equal(this_value, receiver.val))
      match args {
        [String_(hint)] => events.push(hint)
        _ => fail("expected the number hint argument")
      }
      Number(7.0)
    },
  )
  let object = make_object(Map([]), Null, None, "Object", Map([]), true)
  receiver.val = object
  match object {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = hook
    _ => fail("expected an object fixture")
  }
  let result = run_executor_coercing_subtraction_root_for_wb(
    interp,
    object,
    Number(2.0),
  )
  match result {
    Number(value) => inspect(value, content="5")
    _ => fail("toPrimitive result must feed numeric subtraction")
  }
  json_inspect(events, content=["number"])
}

///|
test "coercing subtraction converts left before right without duplicates" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let left_hook = make_method_func(
    name="leftToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      events.push("left")
      Number(7.0)
    },
  )
  let right_hook = make_method_func(
    name="rightToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      events.push("right")
      Number(2.0)
    },
  )
  let left = make_object(Map([]), Null, None, "Object", Map([]), true)
  let right = make_object(Map([]), Null, None, "Object", Map([]), true)
  match left {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = left_hook
    _ => fail("expected left object fixture")
  }
  match right {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = right_hook
    _ => fail("expected right object fixture")
  }
  let result = run_executor_coercing_subtraction_root_for_wb(
    interp, left, right,
  )
  match result {
    Number(value) => inspect(value, content="5")
    _ => fail("object subtraction must return a number")
  }
  json_inspect(events, content=["left", "right"])
}

///|
test "coercing subtraction uses valueOf then toString fallback" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let fallback = make_object(Map([]), Null, None, "Fallback", Map([]), true)
  let value_of = make_method_func(
    name="valueOf",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      events.push("valueOf")
      fallback
    },
  )
  let to_string = make_method_func(
    name="toString",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      events.push("toString")
      String_("7")
    },
  )
  let object = make_object(
    { "valueOf": value_of, "toString": to_string },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let result = run_executor_coercing_subtraction_root_for_wb(
    interp,
    object,
    Number(2.0),
  )
  match result {
    Number(value) => inspect(value, content="5")
    _ => fail("toString fallback must feed numeric subtraction")
  }
  json_inspect(events, content=["valueOf", "toString"])
}

///|
test "coercing subtraction leaves right untouched after left throw" {
  let interp = Interpreter::new()
  let right_calls : Ref[Int] = { val: 0 }
  let left_hook = make_method_func(
    name="leftToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) raise {
      raise @errors.TypeError(message="left conversion failed")
    },
  )
  let right_hook = make_method_func(
    name="rightToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      right_calls.val += 1
      Number(2.0)
    },
  )
  let left = make_object(Map([]), Null, None, "Object", Map([]), true)
  let right = make_object(Map([]), Null, None, "Object", Map([]), true)
  match left {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = left_hook
    _ => fail("expected left object fixture")
  }
  match right {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = right_hook
    _ => fail("expected right object fixture")
  }
  let caught : Error? = try {
    let _ = run_executor_coercing_subtraction_root_for_wb(interp, left, right)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("expected left TypeError, got " + error.to_string())
    None => fail("left conversion must throw")
  }
  inspect(right_calls.val, content="0")
}

///|
test "coercing subtraction leaves right untouched after left Symbol TypeError" {
  let interp = Interpreter::new()
  let right_calls : Ref[Int] = { val: 0 }
  let right_hook = make_method_func(
    name="rightToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      right_calls.val += 1
      Number(2.0)
    },
  )
  let right = make_object(Map([]), Null, None, "Object", Map([]), true)
  match right {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = right_hook
    _ => fail("expected right object fixture")
  }
  match
    coercing_subtraction_error_for_wb(
      interp,
      Symbol({ id: 9003, description: None }),
      right,
    ) {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("expected Symbol TypeError, got " + error.to_string())
    None => fail("Symbol conversion must throw")
  }
  inspect(right_calls.val, content="0")
}

///|
test "coercing subtraction retains left effects when right throws" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let left_hook = make_method_func(
    name="leftToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      events.push("left")
      Number(7.0)
    },
  )
  let right_hook = make_method_func(
    name="rightToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) raise {
      events.push("right")
      raise @errors.TypeError(message="right conversion failed")
    },
  )
  let left = make_object(Map([]), Null, None, "Object", Map([]), true)
  let right = make_object(Map([]), Null, None, "Object", Map([]), true)
  match left {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = left_hook
    _ => fail("expected left object fixture")
  }
  match right {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = right_hook
    _ => fail("expected right object fixture")
  }
  let caught : Error? = try {
    let _ = run_executor_coercing_subtraction_root_for_wb(interp, left, right)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("expected right TypeError, got " + error.to_string())
    None => fail("right conversion must throw")
  }
  json_inspect(events, content=["left", "right"])
}

///|
test "coercing subtraction rejects an object ToPrimitive result" {
  let interp = Interpreter::new()
  let result_object = make_object(Map([]), Null, None, "Object", Map([]), true)
  let hook = make_method_func(
    name="objectToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { result_object },
  )
  let object = make_object(Map([]), Null, None, "Object", Map([]), true)
  match object {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = hook
    _ => fail("expected object fixture")
  }
  let caught : Error? = try {
    let _ = run_executor_coercing_subtraction_root_for_wb(
      interp,
      object,
      Number(1.0),
    )
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@errors.TypeError(_)) => ()
    Some(error) =>
      fail("expected object-result TypeError, got " + error.to_string())
    None => fail("object ToPrimitive result must throw")
  }
}

///|
test "coercing subtraction propagates conversion getter and call errors" {
  let interp = Interpreter::new()
  let symbol_getter = make_method_func(
    name="throwing@@toPrimitive getter",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) raise {
      raise @errors.TypeError(message="symbol getter failed")
    },
  )
  let getter_object = make_coercing_addition_object_for_wb(
    interp.realm_state.well_known_symbols.to_primitive.id,
    None,
    Some(symbol_getter),
    None,
    None,
    None,
    None,
  )
  match coercing_subtraction_error_for_wb(interp, getter_object, Number(1.0)) {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("getter error changed type: " + error.to_string())
    None => fail("@@toPrimitive getter must throw")
  }

  let value_of = make_method_func(
    name="throwing valueOf",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) raise {
      raise @errors.TypeError(message="valueOf call failed")
    },
  )
  let call_object = make_coercing_addition_object_for_wb(
    interp.realm_state.well_known_symbols.to_primitive.id,
    None,
    None,
    Some(value_of),
    None,
    None,
    None,
  )
  match coercing_subtraction_error_for_wb(interp, call_object, Number(1.0)) {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("call error changed type: " + error.to_string())
    None => fail("valueOf call must throw")
  }
}

///|
test "coercing subtraction reuses one interpreter after a suspended run" {
  let interp = Interpreter::new()
  let make_numeric_object = value => {
    let hook = make_method_func(
      name="reused@@toPrimitive",
      realm_state=Some(interp.realm_state),
      fn(_this_value, args) raise {
        match args {
          [String_(hint)] => inspect(hint, content="number")
          _ => fail("expected the number hint argument")
        }
        value
      },
    )
    let object = make_object(Map([]), Null, None, "Object", Map([]), true)
    match object {
      Object(data) =>
        data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = hook
      _ => fail("expected an object fixture")
    }
    object
  }
  let first = run_executor_coercing_subtraction_root_for_wb(
    interp,
    make_numeric_object(Number(7.0)),
    Number(2.0),
  )
  let second = run_executor_coercing_subtraction_root_for_wb(
    interp,
    make_numeric_object(Number(8.0)),
    Number(3.0),
  )
  inspect(first.to_string(), content="5")
  inspect(second.to_string(), content="5")
}

///|
test "coercing subtraction routes Proxy conversion lookups through guest activation" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let receiver : Ref[Value] = { val: Undefined }
  let value_of = make_executor_function(
    Some("proxy valueOf"),
    [],
    interp.global,
    false,
    ExecutorActivationOrderedValueCode(
      events~,
      label="call:valueOf",
      value=Number(7.0),
    ),
    constructable=false,
  )
  let to_string = make_executor_function(
    Some("proxy toString"),
    [],
    interp.global,
    false,
    ExecutorActivationOrderedValueCode(
      events~,
      label="call:toString",
      value=String_("proxy"),
    ),
    constructable=false,
  )
  let to_primitive_id = interp.realm_state.well_known_symbols.to_primitive.id
  let get_trap = make_executor_function(
    Some("proxy get"),
    ["target", "key", "receiver"],
    interp.global,
    false,
    ExecutorActivationProxyAdditionGetCode(
      events~,
      expected_receiver=receiver,
      to_primitive_id~,
      value_of~,
      to_string~,
    ),
    constructable=false,
  )
  let proxy_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let proxy_handler = make_object(
    { "get": get_trap },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let proxy = Proxy({
    target: Some(proxy_target),
    handler: Some(proxy_handler),
    is_callable: false,
    is_constructor: false,
  })
  receiver.val = proxy
  let result = run_executor_coercing_subtraction_root_for_wb(
    interp,
    proxy,
    Number(2.0),
  )
  match result {
    Number(value) => inspect(value, content="5")
    _ => fail("Proxy conversion must use its numeric valueOf result")
  }
  json_inspect(events, content=[
    "get:@@toPrimitive", "get:valueOf", "call:valueOf",
  ])
}

///|
test "coercing addition routes Proxy conversion lookups through guest activation" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let receiver : Ref[Value] = { val: Undefined }
  let fallback = make_object(Map([]), Null, None, "Object", Map([]), true)
  let value_of = make_executor_function(
    Some("proxy valueOf"),
    [],
    interp.global,
    false,
    ExecutorActivationOrderedValueCode(
      events~,
      label="call:valueOf",
      value=fallback,
    ),
    constructable=false,
  )
  let to_string = make_executor_function(
    Some("proxy toString"),
    [],
    interp.global,
    false,
    ExecutorActivationOrderedValueCode(
      events~,
      label="call:toString",
      value=String_("proxy"),
    ),
    constructable=false,
  )
  let to_primitive_id = interp.realm_state.well_known_symbols.to_primitive.id
  let get_trap = make_executor_function(
    Some("proxy get"),
    ["target", "key", "receiver"],
    interp.global,
    false,
    ExecutorActivationProxyAdditionGetCode(
      events~,
      expected_receiver=receiver,
      to_primitive_id~,
      value_of~,
      to_string~,
    ),
    constructable=false,
  )
  let proxy_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let proxy_handler = make_object(
    { "get": get_trap },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let proxy = Proxy({
    target: Some(proxy_target),
    handler: Some(proxy_handler),
    is_callable: false,
    is_constructor: false,
  })
  receiver.val = proxy
  let result = run_executor_coercing_addition_root_for_wb(
    interp,
    proxy,
    Number(2.0),
  )
  match result {
    String_(value) => inspect(value, content="proxy2")
    _ => fail("Proxy conversion must select string addition")
  }
  json_inspect(events, content=[
    "get:@@toPrimitive", "get:valueOf", "call:valueOf", "get:toString", "call:toString",
  ])
}

///|
test "coercing addition uses default hint and original receiver" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let receiver : Ref[Value] = { val: Undefined }
  let hook = make_method_func(
    name="@@toPrimitive",
    realm_state=Some(interp.realm_state),
    fn(this_value, args) raise {
      assert_true(physical_equal(this_value, receiver.val))
      match args {
        [String_(hint)] => events.push(hint)
        _ => events.push("wrong-args")
      }
      Number(4.0)
    },
  )
  let object = make_object(Map([]), Null, None, "Object", Map([]), true)
  receiver.val = object
  match object {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = hook
    _ => fail("expected an object fixture")
  }
  let result = run_executor_coercing_addition_root_for_wb(
    interp,
    object,
    Number(2.0),
  )
  match result {
    Number(value) => inspect(value, content="6")
    _ => fail("toPrimitive result must feed numeric addition")
  }
  json_inspect(events, content=["default"])
}

///|
test "coercing addition uses valueOf then toString fallback" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let fallback = make_object(Map([]), Null, None, "Object", Map([]), true)
  let value_of = make_method_func(
    name="valueOf",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      events.push("valueOf")
      fallback
    },
  )
  let to_string = make_method_func(
    name="toString",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      events.push("toString")
      String_("fallback")
    },
  )
  let object = make_object(
    { "valueOf": value_of, "toString": to_string },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let result = run_executor_coercing_addition_root_for_wb(
    interp,
    object,
    Number(2.0),
  )
  match result {
    String_(value) => inspect(value, content="fallback2")
    _ => fail("toString fallback must select string addition")
  }
  json_inspect(events, content=["valueOf", "toString"])
}

///|
test "ToPrimitive default and number preserve valueOf then toString fallback" {
  let interp = Interpreter::new()
  let default_events : Array[String] = []
  let default_fallback = make_object(
    Map([]),
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let default_value_of = make_method_func(
    name="defaultValueOf",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      default_events.push("valueOf")
      default_fallback
    },
  )
  let default_to_string = make_method_func(
    name="defaultToString",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      default_events.push("toString")
      String_("default")
    },
  )
  let default_object = make_object(
    { "valueOf": default_value_of, "toString": default_to_string },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let default_result = run_executor_coercing_addition_root_for_wb(
    interp,
    default_object,
    Number(1.0),
  )
  match default_result {
    String_(value) => inspect(value, content="default1")
    _ => fail("default ToPrimitive must fall back to toString")
  }
  json_inspect(default_events, content=["valueOf", "toString"])

  let number_events : Array[String] = []
  let number_fallback = make_object(
    Map([]),
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let number_value_of = make_method_func(
    name="numberValueOf",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      number_events.push("valueOf")
      number_fallback
    },
  )
  let number_to_string = make_method_func(
    name="numberToString",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      number_events.push("toString")
      String_("4")
    },
  )
  let number_object = make_object(
    { "valueOf": number_value_of, "toString": number_to_string },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let target = make_object(
    { "x": number_object },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let request = ExecutorPropertyUpdateRequest(
    target~,
    property_name="x",
    operator=ExecutorPropertyIncrement,
    prefix=false,
    member_loc=@token.Loc::default(),
    loc=@token.Loc::default(),
    strict=false,
  )
  let root = ExecutorPropertyUpdateFrame(request) as &ExecutorActivationFrame
  let number_result = match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(result) => result
    ExecutorActivationNormal(result) => result
    _ => fail("number ToPrimitive update must return its old value")
  }
  match number_result {
    Number(value) => inspect(value, content="4")
    _ => fail("number ToPrimitive must return the numeric old value")
  }
  json_inspect(number_events, content=["valueOf", "toString"])
}

///|
test "coercing addition rejects non-callable @@toPrimitive without fallback" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let value_of = make_executor_function(
    Some("unused valueOf"),
    [],
    interp.global,
    false,
    ExecutorActivationOrderedValueCode(
      events~,
      label="valueOf",
      value=Number(1.0),
    ),
    constructable=false,
  )
  let to_string = make_executor_function(
    Some("unused toString"),
    [],
    interp.global,
    false,
    ExecutorActivationOrderedValueCode(
      events~,
      label="toString",
      value=String_("unused"),
    ),
    constructable=false,
  )
  let object = make_coercing_addition_object_for_wb(
    interp.realm_state.well_known_symbols.to_primitive.id,
    Some(Number(1.0)),
    None,
    Some(value_of),
    None,
    Some(to_string),
    None,
  )
  assert_coercing_addition_type_error_for_wb(
    interp,
    object,
    Number(1.0),
    "non-callable @@toPrimitive",
  )
  json_inspect(events, content=[])
}

///|
test "coercing addition propagates @@toPrimitive getter throw" {
  let interp = Interpreter::new()
  let sentinel = @errors.TypeError(message="@@toPrimitive getter")
  let getter = make_coercing_addition_thrower_for_wb(
    interp, "@@toPrimitive getter", sentinel,
  )
  let object = make_coercing_addition_object_for_wb(
    interp.realm_state.well_known_symbols.to_primitive.id,
    None,
    Some(getter),
    None,
    None,
    None,
    None,
  )
  match coercing_addition_error_for_wb(interp, object, Number(1.0)) {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("@@toPrimitive getter unexpectedly completed")
  }
}

///|
test "coercing addition propagates valueOf getter throw" {
  let interp = Interpreter::new()
  let sentinel = @errors.TypeError(message="valueOf getter")
  let getter = make_coercing_addition_thrower_for_wb(
    interp, "valueOf getter", sentinel,
  )
  let events : Array[String] = []
  let to_string = make_executor_function(
    Some("unused toString"),
    [],
    interp.global,
    false,
    ExecutorActivationOrderedValueCode(
      events~,
      label="toString",
      value=String_("unused"),
    ),
    constructable=false,
  )
  let object = make_coercing_addition_object_for_wb(
    interp.realm_state.well_known_symbols.to_primitive.id,
    None,
    None,
    None,
    Some(getter),
    Some(to_string),
    None,
  )
  match coercing_addition_error_for_wb(interp, object, Number(1.0)) {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("valueOf getter unexpectedly completed")
  }
  json_inspect(events, content=[])
}

///|
test "coercing addition propagates valueOf call throw" {
  let interp = Interpreter::new()
  let sentinel = @errors.TypeError(message="valueOf call")
  let value_of = make_coercing_addition_thrower_for_wb(
    interp, "valueOf call", sentinel,
  )
  let events : Array[String] = []
  let to_string = make_executor_function(
    Some("unused toString"),
    [],
    interp.global,
    false,
    ExecutorActivationOrderedValueCode(
      events~,
      label="toString",
      value=String_("unused"),
    ),
    constructable=false,
  )
  let object = make_coercing_addition_object_for_wb(
    interp.realm_state.well_known_symbols.to_primitive.id,
    None,
    None,
    Some(value_of),
    None,
    Some(to_string),
    None,
  )
  match coercing_addition_error_for_wb(interp, object, Number(1.0)) {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("valueOf call unexpectedly completed")
  }
  json_inspect(events, content=[])
}

///|
test "coercing addition propagates toString getter throw" {
  let interp = Interpreter::new()
  let sentinel = @errors.TypeError(message="toString getter")
  let getter = make_coercing_addition_thrower_for_wb(
    interp, "toString getter", sentinel,
  )
  let object = make_coercing_addition_object_for_wb(
    interp.realm_state.well_known_symbols.to_primitive.id,
    None,
    None,
    Some(Undefined),
    None,
    None,
    Some(getter),
  )
  match coercing_addition_error_for_wb(interp, object, Number(1.0)) {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("toString getter unexpectedly completed")
  }
}

///|
test "coercing addition propagates toString call throw" {
  let interp = Interpreter::new()
  let sentinel = @errors.TypeError(message="toString call")
  let to_string = make_coercing_addition_thrower_for_wb(
    interp, "toString call", sentinel,
  )
  let object = make_coercing_addition_object_for_wb(
    interp.realm_state.well_known_symbols.to_primitive.id,
    None,
    None,
    Some(Undefined),
    None,
    Some(to_string),
    None,
  )
  match coercing_addition_error_for_wb(interp, object, Number(1.0)) {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("toString call unexpectedly completed")
  }
}

///|
test "coercing addition rejects object result from toString fallback" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let result_object = make_object(Map([]), Null, None, "Object", Map([]), true)
  let to_string = make_executor_function(
    Some("object toString"),
    [],
    interp.global,
    false,
    ExecutorActivationOrderedValueCode(
      events~,
      label="toString",
      value=result_object,
    ),
    constructable=false,
  )
  let object = make_coercing_addition_object_for_wb(
    interp.realm_state.well_known_symbols.to_primitive.id,
    None,
    None,
    Some(Undefined),
    None,
    Some(to_string),
    None,
  )
  assert_coercing_addition_type_error_for_wb(
    interp,
    object,
    Number(1.0),
    "object toString result",
  )
  json_inspect(events, content=["toString"])
}

///|
test "coercing addition stops on left abrupt completion" {
  let interp = Interpreter::new()
  let right_calls : Ref[Int] = { val: 0 }
  let left_hook = make_method_func(
    name="leftToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) raise {
      raise @errors.TypeError(message="left conversion failed")
    },
  )
  let right_hook = make_method_func(
    name="rightToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      right_calls.val += 1
      Number(2.0)
    },
  )
  let left = make_object(Map([]), Null, None, "Object", Map([]), true)
  let right = make_object(Map([]), Null, None, "Object", Map([]), true)
  match left {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = left_hook
    _ => fail("expected left object fixture")
  }
  match right {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = right_hook
    _ => fail("expected right object fixture")
  }
  let caught : Error? = try {
    let _ = run_executor_coercing_addition_root_for_wb(interp, left, right)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("expected left TypeError, got " + error.to_string())
    None => fail("left conversion must throw")
  }
  inspect(right_calls.val, content="0")
}

///|
test "coercing addition keeps left effects when right throws" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let left_hook = make_method_func(
    name="leftToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      events.push("left")
      Number(1.0)
    },
  )
  let right_hook = make_method_func(
    name="rightToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) raise {
      events.push("right")
      raise @errors.TypeError(message="right conversion failed")
    },
  )
  let left = make_object(Map([]), Null, None, "Object", Map([]), true)
  let right = make_object(Map([]), Null, None, "Object", Map([]), true)
  match left {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = left_hook
    _ => fail("expected left object fixture")
  }
  match right {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = right_hook
    _ => fail("expected right object fixture")
  }
  let caught : Error? = try {
    let _ = run_executor_coercing_addition_root_for_wb(interp, left, right)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("expected right TypeError, got " + error.to_string())
    None => fail("right conversion must throw")
  }
  json_inspect(events, content=["left", "right"])
}

///|
test "coercing addition converts both operands before Symbol TypeError" {
  let interp = Interpreter::new()
  let right_calls : Ref[Int] = { val: 0 }
  let right_hook = make_method_func(
    name="rightToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      right_calls.val += 1
      Number(2.0)
    },
  )
  let right = make_object(Map([]), Null, None, "Object", Map([]), true)
  match right {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = right_hook
    _ => fail("expected right object fixture")
  }
  let caught : Error? = try {
    let _ = run_executor_coercing_addition_root_for_wb(
      interp,
      Symbol({ id: 9001, description: None }),
      right,
    )
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("expected Symbol TypeError, got " + error.to_string())
    None => fail("Symbol numeric conversion must throw")
  }
  inspect(right_calls.val, content="1")
}

///|
test "coercing addition rejects an object ToPrimitive result" {
  let interp = Interpreter::new()
  let result_object = make_object(Map([]), Null, None, "Object", Map([]), true)
  let hook = make_method_func(
    name="objectToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { result_object },
  )
  let object = make_object(Map([]), Null, None, "Object", Map([]), true)
  match object {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = hook
    _ => fail("expected object fixture")
  }
  let caught : Error? = try {
    let _ = run_executor_coercing_addition_root_for_wb(
      interp,
      object,
      Number(1.0),
    )
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@errors.TypeError(_)) => ()
    Some(error) =>
      fail("expected object-result TypeError, got " + error.to_string())
    None => fail("object ToPrimitive result must throw")
  }
}

///|
test "coercing addition frame rejects post-completion stepping" {
  let interp = Interpreter::new()
  let request = ExecutorCoercingAdditionRequest(
    left=Number(1.0),
    right=Number(2.0),
    loc=@token.Loc::default(),
  )
  let frame = ExecutorCoercingAdditionFrame(request)
  match frame.step_frame(interp) {
    ExecutorActivationNormal(Number(value)) => inspect(value, content="3")
    _ => fail("primitive frame must complete synchronously")
  }
  let caught : Error? = try {
    let _ = frame.step_frame(interp)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@errors.InternalError(_)) => ()
    Some(error) =>
      fail("expected post-completion InternalError, got " + error.to_string())
    None => fail("post-completion step must be rejected")
  }
}

///|
test "property activation setter setup error preserves identity and cleanup" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.TypeError(
    message="property setter setup sentinel",
  )
  let setter = make_executor_function(
    Some("setter"),
    ["value"],
    interp.global,
    false,
    ExecutorActivationStartErrorCode(error=sentinel),
    constructable=false,
  )
  let target = make_direct_property_setter_target(setter, None)
  let events : Array[String] = []
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  install_executor_activation_probe(interp, events, None, control=Some(control))
  let caught : Error? = try {
    let _ = run_executor_property_set_root_for_wb(
      interp,
      target,
      "x",
      Number(1.0),
      false,
    )
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("property setter setup failure must propagate")
  }
  json_inspect(events, content=["attempt:cleared", "release:cleared"])
  inspect(control.active_depth(), content="0")
  match control.with_activation(() => Number(1.0)) {
    Ok(Number(value)) => inspect(value, content="1")
    _ => fail("execution control must permit reuse after setter setup failure")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "property activation setter delivery error cleans child once" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(
    message="property setter delivery sentinel",
  )
  let starts : Ref[Int] = { val: 0 }
  let setter = make_executor_function(
    Some("setter"),
    ["value"],
    interp.global,
    false,
    ExecutorActivationValueCode(starts~, value=Number(9.0)),
    constructable=false,
  )
  let target = make_direct_property_setter_target(setter, None)
  let deliveries : Ref[Int] = { val: 0 }
  let root = ExecutorActivationPropertySetDeliveryErrorFrame(
      target~,
      value=Number(1.0),
      expected=sentinel,
      delivery_count=deliveries,
    )
    as &ExecutorActivationFrame
  let events : Array[String] = []
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  install_executor_activation_probe(interp, events, None, control=Some(control))
  let caught : Error? = try {
    let _ = interp.run_executor_activation_coordinator(root)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("property setter delivery failure must propagate")
  }
  inspect(deliveries.val, content="1")
  inspect(starts.val, content="1")
  json_inspect(events, content=["attempt:cleared", "release:cleared"])
  inspect(control.active_depth(), content="0")
  match control.with_activation(() => Number(1.0)) {
    Ok(Number(value)) => inspect(value, content="1")
    _ =>
      fail("execution control must permit reuse after setter delivery failure")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "property activation setter rejects depth before over-limit body and reuses" {
  let interp = Interpreter::new()
  let target_ref : Ref[Value] = { val: Undefined }
  let remaining : Ref[Int] = { val: 4 }
  let starts : Ref[Int] = { val: 0 }
  let setter = make_executor_function(
    Some("recursiveSetter"),
    ["value"],
    interp.global,
    false,
    ExecutorActivationRecursivePropertySetCode(
      target=target_ref,
      remaining~,
      starts~,
    ),
    constructable=false,
  )
  let target = make_direct_property_setter_target(setter, None)
  target_ref.val = target
  let events : Array[String] = []
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=2,
    interruption=ExecutionInterruptionRequest(),
  )
  install_executor_activation_probe(interp, events, None, control=Some(control))
  let outcome = try {
    let _ = run_executor_property_set_root_for_wb(
      interp,
      target,
      "x",
      Number(4.0),
      false,
    )
    "completed"
  } catch {
    ExecutionControlError(StackDepthLimit) => "stack-depth-limit"
    _ => "other-error"
  }
  inspect(outcome, content="stack-depth-limit")
  inspect(starts.val, content="2")
  inspect(remaining.val, content="2")
  json_inspect(events, content=[
    "attempt:cleared", "attempt:cleared", "attempt:cleared", "release:cleared", "release:cleared",
  ])
  inspect(control.active_depth(), content="0")
  remaining.val = 0
  let reused = run_executor_property_set_root_for_wb(
    interp,
    target,
    "x",
    Number(0.0),
    false,
  )
  inspect(reused.to_string(), content="0")
  inspect(starts.val, content="3")
  inspect(control.active_depth(), content="0")
}

///|
test "property-set fallback covers native inherited proxy data getter primitive array and typed array" {
  let interp = Interpreter::new()
  let rhs = Object({
    bag: PropertyBag::PropertyBag(),
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  let native_calls : Ref[Int] = { val: 0 }
  let native_setter = make_native_func(name="nativeSetter", fn(_args) {
    native_calls.val += 1
    Undefined
  })
  let native_target = make_direct_property_setter_target(native_setter, None)
  let native_result = run_executor_property_set_root_for_wb(
    interp, native_target, "x", rhs, false,
  )
  assert_true(physical_equal(native_result, rhs))
  inspect(native_calls.val, content="1")

  let inherited_proto = make_direct_property_setter_target(native_setter, None)
  let inherited_target = Object({
    bag: PropertyBag::PropertyBag(),
    prototype: inherited_proto,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  let inherited_result = run_executor_property_set_root_for_wb(
    interp, inherited_target, "x", rhs, false,
  )
  assert_true(physical_equal(inherited_result, rhs))
  inspect(native_calls.val, content="2")

  let proxy_calls : Ref[Int] = { val: 0 }
  let proxy_setter = make_native_func(name="proxySetter", fn(args) raise {
    proxy_calls.val += 1
    match args {
      [_, String_(property_name), value, _] => {
        assert_true(property_name == "x")
        assert_true(physical_equal(value, rhs))
        Bool(true)
      }
      _ => fail("proxy set trap must receive target, key, value, receiver")
    }
  })
  let proxy_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let proxy_handler = make_object(
    { "set": proxy_setter },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let proxy = Proxy({
    target: Some(proxy_target),
    handler: Some(proxy_handler),
    is_callable: false,
    is_constructor: false,
  })
  let proxy_result = run_executor_property_set_root_for_wb(
    interp, proxy, "x", rhs, false,
  )
  assert_true(physical_equal(proxy_result, rhs))
  inspect(proxy_calls.val, content="1")

  let data_bag = PropertyBag::PropertyBag()
  data_bag.properties["x"] = Number(0.0)
  let data_target = Object({
    bag: data_bag,
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  let data_result = run_executor_property_set_root_for_wb(
    interp, data_target, "x", rhs, false,
  )
  assert_true(physical_equal(data_result, rhs))
  match data_target {
    Object(data) =>
      match data.bag.properties.get("x") {
        Some(value) => assert_true(physical_equal(value, rhs))
        None => fail("data-property fallback must update the own value")
      }
    _ => fail("data-property target must remain an object")
  }

  let getter_only = make_direct_property_getter_target(
    make_native_func(name="getterOnly", _args => Number(1.0)),
    None,
  )
  let getter_result = run_executor_property_set_root_for_wb(
    interp, getter_only, "x", rhs, false,
  )
  assert_true(physical_equal(getter_result, rhs))

  let primitive_result = run_executor_property_set_root_for_wb(
    interp,
    Number(3.0),
    "x",
    rhs,
    false,
  )
  assert_true(physical_equal(primitive_result, rhs))

  let array_target = make_array([])
  let array_result = run_executor_property_set_root_for_wb(
    interp, array_target, "x", rhs, false,
  )
  assert_true(physical_equal(array_result, rhs))
  match array_target {
    Array(data) =>
      match data.bag.properties.get("x") {
        Some(value) => assert_true(physical_equal(value, rhs))
        None => fail("array fallback must update the named value")
      }
    _ => fail("array target must remain an array")
  }

  let typed_target = Object({
    bag: PropertyBag::PropertyBag(),
    prototype: Null,
    callable: None,
    class_name: "Uint8Array",
    extensible: true,
    arraybuffer_state: Some(ArrayBufferState::ArrayBufferState()),
  })
  let typed_result = run_executor_property_set_root_for_wb(
    interp, typed_target, "x", rhs, false,
  )
  assert_true(physical_equal(typed_result, rhs))
  match typed_target {
    Object(data) =>
      match data.bag.properties.get("x") {
        Some(value) => assert_true(physical_equal(value, rhs))
        None => fail("typed-array fallback must update a named value")
      }
    _ => fail("typed-array target must remain an object")
  }
}
