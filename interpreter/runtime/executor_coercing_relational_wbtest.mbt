///|
priv struct ExecutorCoercingLessThanOrEqualRootFrame {
  left : Value
  right : Value
  loc : @token.Loc
  mut requested : Bool
  mut result : Value?
}

///|
fn ExecutorCoercingLessThanOrEqualRootFrame::ExecutorCoercingLessThanOrEqualRootFrame(
  left~ : Value,
  right~ : Value,
  loc~ : @token.Loc,
) -> ExecutorCoercingLessThanOrEqualRootFrame {
  { left, right, loc, requested: false, result: None }
}

///|
impl ExecutorActivationFrame for ExecutorCoercingLessThanOrEqualRootFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    executor_activation_coercing_less_than_or_equal(
      self.left,
      self.right,
      self.loc,
    )
  } else {
    match self.result {
      Some(value) => ExecutorActivationReturn(value)
      None =>
        raise @errors.InternalError(
          message="coercing less-than-or-equal root resumed without a result",
        )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorCoercingLessThanOrEqualRootFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionNormal(value) => self.result = Some(value)
    ExecutorActivationCompletionAbrupt(error) => raise error
  }
}

///|
fn run_executor_coercing_less_than_or_equal_root_for_wb(
  interp : Interpreter,
  left : Value,
  right : Value,
) -> Value raise Error {
  let root = ExecutorCoercingLessThanOrEqualRootFrame(
    left~,
    right~,
    loc=@token.Loc::default(),
  ) as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(result) => result
    _ => fail("coercing less-than-or-equal root must return its result")
  }
}

///|
fn coercing_less_than_or_equal_error_for_wb(
  interp : Interpreter,
  left : Value,
  right : Value,
) -> Error? {
  try {
    let _ = run_executor_coercing_less_than_or_equal_root_for_wb(
      interp,
      left,
      right,
    )
    None
  } catch {
    error => Some(error)
  }
}

///|
test "coercing less-than-or-equal start completes primitives and suspends objects" {
  let loc = @token.Loc::default()
  match begin_executor_coercing_less_than_or_equal(Number(0.0), Number(1.0), loc) {
    ExecutorCoercingLessThanOrEqualCompleted(Bool(true)) => ()
    ExecutorCoercingLessThanOrEqualCompleted(_) =>
      fail("number <= must complete true")
    ExecutorCoercingLessThanOrEqualSuspended(_) =>
      fail("primitive <= must not create a child frame")
  }
  match begin_executor_coercing_less_than_or_equal(
    String_("2"),
    String_("10"),
    loc,
  ) {
    ExecutorCoercingLessThanOrEqualCompleted(Bool(false)) => ()
    ExecutorCoercingLessThanOrEqualCompleted(_) =>
      fail("String <= must use ECMAScript lexicographic order")
    ExecutorCoercingLessThanOrEqualSuspended(_) =>
      fail("primitive String <= must not create a child frame")
  }
  let object = make_object(Map([]), Null, None, "Object", Map([]), true)
  match begin_executor_coercing_less_than_or_equal(object, Number(1.0), loc) {
    ExecutorCoercingLessThanOrEqualSuspended(_) => ()
    ExecutorCoercingLessThanOrEqualCompleted(_) =>
      fail("object <= must request a child frame")
  }
  let symbol_error : Error? = try {
    let _ = begin_executor_coercing_less_than_or_equal(
      Symbol({ id: 9010, description: None }),
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
    None => fail("Symbol <= must throw synchronously")
  }
}

///|
test "coercing less-than-or-equal completes object String primitives in source order" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let left_receiver : Ref[Value] = { val: Undefined }
  let right_receiver : Ref[Value] = { val: Undefined }
  let left_hook = make_method_func(
    name="left @@toPrimitive",
    realm_state=Some(interp.realm_state),
    fn(this_value, args) raise {
      assert_true(physical_equal(this_value, left_receiver.val))
      match args {
        [String_(hint)] => inspect(hint, content="number")
        _ => fail("expected number hint")
      }
      events.push("left")
      String_("2")
    },
  )
  let right_hook = make_method_func(
    name="right @@toPrimitive",
    realm_state=Some(interp.realm_state),
    fn(this_value, args) raise {
      assert_true(physical_equal(this_value, right_receiver.val))
      match args {
        [String_(hint)] => inspect(hint, content="number")
        _ => fail("expected number hint")
      }
      events.push("right")
      String_("10")
    },
  )
  let left = make_object(Map([]), Null, None, "Left", Map([]), true)
  let right = make_object(Map([]), Null, None, "Right", Map([]), true)
  match left {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = left_hook
    _ => fail("expected left object")
  }
  match right {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = right_hook
    _ => fail("expected right object")
  }
  left_receiver.val = left
  right_receiver.val = right
  let result = run_executor_coercing_less_than_or_equal_root_for_wb(
    interp,
    left,
    right,
  )
  inspect(result, content="false")
  json_inspect(events, content=["left", "right"])
}

///|
test "coercing less-than-or-equal uses object Number and ordinary fallback" {
  let interp = Interpreter::new()
  let value_of = make_method_func(
    name="valueOf number",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { Number(4.0) },
  )
  let number_object = make_object(
    { "valueOf": value_of },
    Null,
    None,
    "NumberObject",
    Map([]),
    true,
  )
  let number_result = run_executor_coercing_less_than_or_equal_root_for_wb(
    interp,
    number_object,
    Number(5.0),
  )
  inspect(number_result, content="true")

  let fallback_result_object = make_object(
    Map([]),
    Null,
    None,
    "FallbackResult",
    Map([]),
    true,
  )
  let fallback_value_of = make_method_func(
    name="valueOf object",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { fallback_result_object },
  )
  let fallback_to_string = make_method_func(
    name="toString number",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { String_("3") },
  )
  let fallback_object = make_object(
    { "valueOf": fallback_value_of, "toString": fallback_to_string },
    Null,
    None,
    "FallbackObject",
    Map([]),
    true,
  )
  let fallback_result = run_executor_coercing_less_than_or_equal_root_for_wb(
    interp,
    fallback_object,
    Number(3.0),
  )
  inspect(fallback_result, content="true")

  let mixed_object = make_object(Map([]), Null, None, "MixedObject", Map([]), true)
  match mixed_object {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = make_method_func(
        name="mixed @@toPrimitive",
        realm_state=Some(interp.realm_state),
        fn(_this_value, _args) { String_("2") },
      )
    _ => fail("expected mixed object")
  }
  let mixed_result = run_executor_coercing_less_than_or_equal_root_for_wb(
    interp,
    mixed_object,
    Number(10.0),
  )
  inspect(mixed_result, content="true")
}

///|
test "coercing less-than-or-equal preserves left-before-right abrupt effects" {
  let interp = Interpreter::new()
  let right_calls : Ref[Int] = { val: 0 }
  let right_hook = make_method_func(
    name="right @@toPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      right_calls.val += 1
      Number(2.0)
    },
  )
  let right_object = make_object(Map([]), Null, None, "Right", Map([]), true)
  match right_object {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = right_hook
    _ => fail("expected right object")
  }
  let left_symbol_error = coercing_less_than_or_equal_error_for_wb(
    interp,
    Symbol({ id: 9011, description: None }),
    right_object,
  )
  match left_symbol_error {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("expected left Symbol TypeError, got " + error.to_string())
    None => fail("left Symbol <= must throw")
  }
  inspect(right_calls.val, content="0")

  let events : Array[String] = []
  let left_hook = make_method_func(
    name="left effect",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      events.push("left")
      Number(4.0)
    },
  )
  let throwing_right_hook = make_method_func(
    name="right throw",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) raise {
      events.push("right")
      raise @errors.TypeError(message="right conversion failed")
    },
  )
  let left_object = make_object(Map([]), Null, None, "Left", Map([]), true)
  let throwing_right = make_object(Map([]), Null, None, "ThrowingRight", Map([]), true)
  match left_object {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = left_hook
    _ => fail("expected left object")
  }
  match throwing_right {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = throwing_right_hook
    _ => fail("expected throwing right object")
  }
  let right_error = coercing_less_than_or_equal_error_for_wb(
    interp,
    left_object,
    throwing_right,
  )
  match right_error {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("expected right TypeError, got " + error.to_string())
    None => fail("right conversion must throw")
  }
  json_inspect(events, content=["left", "right"])
}

///|
test "coercing less-than-or-equal propagates conversion hook errors" {
  let interp = Interpreter::new()
  let non_callable = make_object(Map([]), Null, None, "NonCallable", Map([]), true)
  match non_callable {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = Number(1.0)
    _ => fail("expected non-callable object")
  }
  match coercing_less_than_or_equal_error_for_wb(interp, non_callable, Number(1.0)) {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("non-callable @@toPrimitive changed error: " + error.to_string())
    None => fail("non-callable @@toPrimitive must throw")
  }

  let getter = make_method_func(
    name="throwing @@toPrimitive getter",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) raise {
      raise @errors.TypeError(message="@@toPrimitive getter failed")
    },
  )
  let getter_object = make_object(Map([]), Null, None, "GetterObject", Map([]), true)
  match getter_object {
    Object(data) =>
      data.bag.symbol_descriptors[interp.realm_state.well_known_symbols.to_primitive.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: Some(getter),
        setter: None,
        is_accessor: true,
      }
    _ => fail("expected getter object")
  }
  match coercing_less_than_or_equal_error_for_wb(interp, getter_object, Number(1.0)) {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("getter error changed type: " + error.to_string())
    None => fail("@@toPrimitive getter must throw")
  }

  let value_of_throw = make_method_func(
    name="throwing valueOf",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) raise {
      raise @errors.TypeError(message="valueOf call failed")
    },
  )
  let call_object = make_object({ "valueOf": value_of_throw }, Null, None, "CallObject", Map([]), true)
  match coercing_less_than_or_equal_error_for_wb(interp, call_object, Number(1.0)) {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("valueOf error changed type: " + error.to_string())
    None => fail("valueOf call must throw")
  }

  let result_object = make_object(Map([]), Null, None, "ResultObject", Map([]), true)
  let object_result_hook = make_method_func(
    name="object @@toPrimitive result",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { result_object },
  )
  let object_result = make_object(Map([]), Null, None, "ObjectResult", Map([]), true)
  match object_result {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = object_result_hook
    _ => fail("expected object-result fixture")
  }
  match coercing_less_than_or_equal_error_for_wb(interp, object_result, Number(1.0)) {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("object result error changed type: " + error.to_string())
    None => fail("object @@toPrimitive result must throw")
  }
}

///|
test "coercing less-than-or-equal propagates ordinary fallback errors" {
  let interp = Interpreter::new()
  let to_string_getter = make_method_func(
    name="throwing toString getter",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) raise {
      raise @errors.TypeError(message="toString getter failed")
    },
  )
  let getter_object = make_object(Map([]), Null, None, "ToStringGetter", Map([]), true)
  match getter_object {
    Object(data) =>
      data.bag.descriptors["toString"] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: Some(to_string_getter),
        setter: None,
        is_accessor: true,
      }
    _ => fail("expected toString getter object")
  }
  match coercing_less_than_or_equal_error_for_wb(interp, getter_object, Number(1.0)) {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("toString getter error changed type: " + error.to_string())
    None => fail("toString getter must throw")
  }

  let fallback_object = make_object(Map([]), Null, None, "FallbackResult", Map([]), true)
  let value_of = make_method_func(
    name="object valueOf",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { fallback_object },
  )
  let to_string = make_method_func(
    name="throwing toString",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) raise {
      raise @errors.TypeError(message="toString call failed")
    },
  )
  let call_object = make_object(
    { "valueOf": value_of, "toString": to_string },
    Null,
    None,
    "ToStringCall",
    Map([]),
    true,
  )
  match coercing_less_than_or_equal_error_for_wb(interp, call_object, Number(1.0)) {
    Some(@errors.TypeError(_)) => ()
    Some(error) => fail("toString call error changed type: " + error.to_string())
    None => fail("toString call must throw")
  }
}

///|
test "coercing less-than-or-equal observes Array own and inherited hooks" {
  let interp = Interpreter::new()
  let own_receiver : Ref[Value] = { val: Undefined }
  let own_hook = make_method_func(
    name="array own @@toPrimitive",
    realm_state=Some(interp.realm_state),
    fn(this_value, args) raise {
      assert_true(physical_equal(this_value, own_receiver.val))
      match args {
        [String_(hint)] => inspect(hint, content="number")
        _ => fail("Array own hook must receive the number hint")
      }
      String_("2")
    },
  )
  let own_array = make_array([Number(1.0)])
  match own_array {
    Array(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = own_hook
    _ => fail("expected own Array fixture")
  }
  own_receiver.val = own_array
  let own_result = run_executor_coercing_less_than_or_equal_root_for_wb(
    interp,
    own_array,
    Number(10.0),
  )
  inspect(own_result, content="true")

  let inherited_receiver : Ref[Value] = { val: Undefined }
  let inherited_hook = make_method_func(
    name="array inherited @@toPrimitive",
    realm_state=Some(interp.realm_state),
    fn(this_value, args) raise {
      assert_true(physical_equal(this_value, inherited_receiver.val))
      match args {
        [String_(hint)] => inspect(hint, content="number")
        _ => fail("Array inherited hook must receive the number hint")
      }
      Number(6.0)
    },
  )
  let proto = make_object(Map([]), Null, None, "ArrayPrototype", Map([]), true)
  match proto {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = inherited_hook
    _ => fail("expected Array prototype fixture")
  }
  let inherited_array = make_array_with_prototype([Number(1.0)], proto)
  inherited_receiver.val = inherited_array
  let inherited_result = run_executor_coercing_less_than_or_equal_root_for_wb(
    interp,
    inherited_array,
    Number(10.0),
  )
  inspect(inherited_result, content="true")
}

///|
test "coercing less-than-or-equal routes Proxy conversion through get" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let receiver : Ref[Value] = { val: Undefined }
  let value_of = make_method_func(
    name="proxy valueOf",
    realm_state=Some(interp.realm_state),
    fn(this_value, _args) raise {
      assert_true(physical_equal(this_value, receiver.val))
      events.push("call:valueOf")
      Number(7.0)
    },
  )
  let get_trap = make_method_func(
    name="proxy get",
    realm_state=Some(interp.realm_state),
    fn(_this_value, args) raise {
      match args {
        [_, Symbol(symbol), proxy_receiver] => {
          assert_true(physical_equal(proxy_receiver, receiver.val))
          assert_true(symbol.id == interp.realm_state.well_known_symbols.to_primitive.id)
          events.push("get:@@toPrimitive")
          Undefined
        }
        [_, String_(name), proxy_receiver] => {
          assert_true(physical_equal(proxy_receiver, receiver.val))
          if name == "valueOf" {
            events.push("get:valueOf")
            value_of
          } else {
            fail("unexpected Proxy conversion key: " + name)
          }
        }
        _ => fail("Proxy get trap received unexpected arguments")
      }
    },
  )
  let target = make_object(Map([]), Null, None, "Target", Map([]), true)
  let handler = make_object({ "get": get_trap }, Null, None, "Handler", Map([]), true)
  let proxy = Proxy({
    target: Some(target),
    handler: Some(handler),
    is_callable: false,
    is_constructor: false,
  })
  receiver.val = proxy
  let result = run_executor_coercing_less_than_or_equal_root_for_wb(
    interp,
    proxy,
    Number(10.0),
  )
  inspect(result, content="true")
  json_inspect(events, content=["get:@@toPrimitive", "get:valueOf", "call:valueOf"])
}
