///| Focused whitebox coverage for the managed multiplicative operation.

///|
priv struct MultiplicativeRootFrame {
  left : Value
  right : Value
  operator : ExecutorMultiplicativeOperator
  loc : @token.Loc
  mut requested : Bool
  mut result : Value?
}

///|
fn MultiplicativeRootFrame::MultiplicativeRootFrame(
  left~ : Value,
  right~ : Value,
  operator~ : ExecutorMultiplicativeOperator,
  loc~ : @token.Loc,
) -> MultiplicativeRootFrame {
  { left, right, operator, loc, requested: false, result: None }
}

///|
impl ExecutorActivationFrame for MultiplicativeRootFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    executor_activation_coercing_multiplicative(
      self.left,
      self.right,
      self.operator,
      self.loc,
    )
  } else {
    match self.result {
      Some(value) => ExecutorActivationReturn(value)
      None =>
        raise @errors.InternalError(
          message="multiplicative root resumed without a result",
        )
    }
  }
}

///|
impl ExecutorActivationFrame for MultiplicativeRootFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="multiplicative root received an unexpected reference completion",
      )
    ExecutorActivationCompletionNormal(value) => self.result = Some(value)
    ExecutorActivationCompletionAbrupt(error) => raise error
  }
}

///|
fn run_multiplicative_root_for_wb(
  interp : Interpreter,
  left : Value,
  right : Value,
  operator : ExecutorMultiplicativeOperator,
) -> Value raise Error {
  let root = MultiplicativeRootFrame(
      left~,
      right~,
      operator~,
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(value) => value
    _ => fail("multiplicative root must return its result")
  }
}

///|
fn expect_multiplicative_number(
  actual : Value,
  expected : Double,
  label : String,
) -> Unit raise Error {
  match actual {
    Number(value) => {
      guard value == expected else {
        fail(
          label +
          ": expected " +
          expected.to_string() +
          ", got " +
          value.to_string(),
        )
      }
    }
    _ => fail(label + ": expected a Number")
  }
}

///|
test "coercing multiplicative primitive paths complete synchronously" {
  let loc = @token.Loc::default()
  match
    begin_executor_coercing_multiplicative(
      ExecutorMultiplicativeOperator::ExecutorMultiplicativeMultiply,
      Number(2.0),
      Number(3.0),
      loc,
    ) {
    ExecutorCoercingMultiplicativeCompleted(value) =>
      expect_multiplicative_number(value, 6.0, "multiply")
    ExecutorCoercingMultiplicativeSuspended(_) =>
      fail("Number/Number multiplication must not create a child")
  }
  match
    begin_executor_coercing_multiplicative(
      ExecutorMultiplicativeOperator::ExecutorMultiplicativeDivide,
      String_("6"),
      Bool(true),
      loc,
    ) {
    ExecutorCoercingMultiplicativeCompleted(value) =>
      expect_multiplicative_number(value, 6.0, "divide")
    ExecutorCoercingMultiplicativeSuspended(_) =>
      fail("primitive division must not create a child")
  }
  match
    begin_executor_coercing_multiplicative(
      ExecutorMultiplicativeOperator::ExecutorMultiplicativeRemainder,
      Null,
      String_("2"),
      loc,
    ) {
    ExecutorCoercingMultiplicativeCompleted(value) =>
      expect_multiplicative_number(value, 0.0, "remainder")
    ExecutorCoercingMultiplicativeSuspended(_) =>
      fail("primitive remainder must not create a child")
  }
}

///|
test "coercing multiplicative Number edge cases" {
  let interp = Interpreter::new()
  let nan_product = run_multiplicative_root_for_wb(
    interp,
    Number(1.0 / 0.0),
    Number(0.0),
    ExecutorMultiplicativeOperator::ExecutorMultiplicativeMultiply,
  )
  match nan_product {
    Number(value) => assert_true(value.is_nan())
    _ => fail("Infinity times zero must be NaN")
  }
  let negative_zero = run_multiplicative_root_for_wb(
    interp,
    Number(-0.0),
    Number(3.0),
    ExecutorMultiplicativeOperator::ExecutorMultiplicativeMultiply,
  )
  match negative_zero {
    Number(value) => assert_true(1.0 / value == -1.0 / 0.0)
    _ => fail("negative zero multiplication must preserve its sign")
  }
  let divide_by_zero = run_multiplicative_root_for_wb(
    interp,
    Number(-1.0),
    Number(0.0),
    ExecutorMultiplicativeOperator::ExecutorMultiplicativeDivide,
  )
  expect_multiplicative_number(divide_by_zero, -1.0 / 0.0, "divide by zero")
  let zero_by_zero = run_multiplicative_root_for_wb(
    interp,
    Number(0.0),
    Number(0.0),
    ExecutorMultiplicativeOperator::ExecutorMultiplicativeDivide,
  )
  match zero_by_zero {
    Number(value) => assert_true(value.is_nan())
    _ => fail("zero divided by zero must be NaN")
  }
  expect_multiplicative_number(
    run_multiplicative_root_for_wb(
      interp,
      Number(-5.0),
      Number(2.0),
      ExecutorMultiplicativeOperator::ExecutorMultiplicativeRemainder,
    ),
    -1.0,
    "remainder sign",
  )
  let remainder_infinity = run_multiplicative_root_for_wb(
    interp,
    Number(5.0),
    Number(1.0 / 0.0),
    ExecutorMultiplicativeOperator::ExecutorMultiplicativeRemainder,
  )
  expect_multiplicative_number(
    remainder_infinity, 5.0, "finite remainder infinity",
  )
}

///|
test "coercing multiplicative converts left before right exactly once" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let left_hook = make_method_func(
    name="multiplicative left @@toPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      events.push("left")
      Number(6.0)
    },
  )
  let right_hook = make_method_func(
    name="multiplicative right @@toPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      events.push("right")
      Number(2.0)
    },
  )
  let left = make_object(Map([]), Null, None, "Left", Map([]), true)
  let right = make_object(Map([]), Null, None, "Right", Map([]), true)
  match left {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = left_hook
    _ => fail("expected object left operand")
  }
  match right {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = right_hook
    _ => fail("expected object right operand")
  }
  let result = run_multiplicative_root_for_wb(
    interp,
    left,
    right,
    ExecutorMultiplicativeOperator::ExecutorMultiplicativeMultiply,
  )
  expect_multiplicative_number(result, 12.0, "object multiplication")
  json_inspect(events, content=["left", "right"])
}

///|
test "coercing multiplicative left Symbol failure leaves right untouched" {
  let interp = Interpreter::new()
  let right_calls : Ref[Int] = { val: 0 }
  let right_hook = make_method_func(
    name="multiplicative right hook",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      right_calls.val += 1
      Number(2.0)
    },
  )
  let right = make_object(Map([]), Null, None, "Right", Map([]), true)
  match right {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = right_hook
    _ => fail("expected object right operand")
  }
  let error : Error? = try {
    let _ = run_multiplicative_root_for_wb(
      interp,
      Symbol({ id: 93801, description: None }),
      right,
      ExecutorMultiplicativeOperator::ExecutorMultiplicativeMultiply,
    )
    None
  } catch {
    error => Some(error)
  }
  match error {
    Some(@errors.TypeError(_)) => ()
    Some(other) => fail("expected Symbol TypeError, got " + other.to_string())
    None => fail("Symbol multiplication must throw")
  }
  assert_eq(right_calls.val, 0)
}

///|
test "coercing multiplicative retains left effects when right throws" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let left_hook = make_method_func(
    name="multiplicative left effect",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      events.push("left")
      Number(7.0)
    },
  )
  let right_hook = make_method_func(
    name="multiplicative right throw",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) raise {
      events.push("right")
      raise @errors.TypeError(message="right conversion failed")
    },
  )
  let left = make_object(Map([]), Null, None, "Left", Map([]), true)
  let right = make_object(Map([]), Null, None, "Right", Map([]), true)
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
  let error : Error? = try {
    let _ = run_multiplicative_root_for_wb(
      interp,
      left,
      right,
      ExecutorMultiplicativeOperator::ExecutorMultiplicativeMultiply,
    )
    None
  } catch {
    error => Some(error)
  }
  match error {
    Some(@errors.TypeError(_)) => ()
    Some(other) => fail("expected right TypeError, got " + other.to_string())
    None => fail("right conversion must throw")
  }
  json_inspect(events, content=["left", "right"])
}

///|
test "multiplicative object conversion falls back from valueOf toString" {
  let interp = Interpreter::new()
  let value_of_result = make_object(
    Map([]),
    Null,
    None,
    "ValueOfResult",
    Map([]),
    true,
  )
  let value_of = make_method_func(
    name="multiplicative valueOf",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { value_of_result },
  )
  let to_string = make_method_func(
    name="multiplicative toString",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { String_("4") },
  )
  let object = make_object(Map([]), Null, None, "Object", Map([]), true)
  match object {
    Object(data) => {
      data.bag.properties["valueOf"] = value_of
      data.bag.properties["toString"] = to_string
    }
    _ => fail("expected object operand")
  }
  let result = run_multiplicative_root_for_wb(
    interp,
    object,
    Number(2.0),
    ExecutorMultiplicativeOperator::ExecutorMultiplicativeMultiply,
  )
  expect_multiplicative_number(result, 8.0, "valueOf toString fallback")
}

///|
test "coercing multiplicative observes Array own and inherited hooks" {
  let interp = Interpreter::new()
  let own_receiver : Ref[Value] = { val: Undefined }
  let own_hook = make_method_func(
    name="multiplicative Array own @@toPrimitive",
    realm_state=Some(interp.realm_state),
    fn(this_value, args) raise {
      assert_true(physical_equal(this_value, own_receiver.val))
      match args {
        [String_(hint)] => inspect(hint, content="number")
        _ => fail("Array own hook must receive the number hint")
      }
      Number(3.0)
    },
  )
  let own_array = make_array([Number(1.0)])
  match own_array {
    Array(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = own_hook
    _ => fail("expected own Array fixture")
  }
  own_receiver.val = own_array
  expect_multiplicative_number(
    run_multiplicative_root_for_wb(
      interp,
      own_array,
      Number(2.0),
      ExecutorMultiplicativeOperator::ExecutorMultiplicativeMultiply,
    ),
    6.0,
    "Array own hook",
  )

  let inherited_receiver : Ref[Value] = { val: Undefined }
  let inherited_hook = make_method_func(
    name="multiplicative Array inherited @@toPrimitive",
    realm_state=Some(interp.realm_state),
    fn(this_value, args) raise {
      assert_true(physical_equal(this_value, inherited_receiver.val))
      match args {
        [String_(hint)] => inspect(hint, content="number")
        _ => fail("Array inherited hook must receive the number hint")
      }
      Number(4.0)
    },
  )
  let proto = make_object(
    Map([]),
    Null,
    None,
    "MultiplicativeArrayPrototype",
    Map([]),
    true,
  )
  match proto {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = inherited_hook
    _ => fail("expected Array prototype fixture")
  }
  let inherited_array = make_array_with_prototype([Number(1.0)], proto)
  inherited_receiver.val = inherited_array
  expect_multiplicative_number(
    run_multiplicative_root_for_wb(
      interp,
      inherited_array,
      Number(2.0),
      ExecutorMultiplicativeOperator::ExecutorMultiplicativeMultiply,
    ),
    8.0,
    "Array inherited hook",
  )
}

///|
test "coercing multiplicative routes Proxy conversion through get" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let receiver : Ref[Value] = { val: Undefined }
  let value_of = make_method_func(
    name="multiplicative Proxy valueOf",
    realm_state=Some(interp.realm_state),
    fn(this_value, _args) raise {
      assert_true(physical_equal(this_value, receiver.val))
      events.push("call:valueOf")
      Number(7.0)
    },
  )
  let get_trap = make_method_func(
    name="multiplicative Proxy get",
    realm_state=Some(interp.realm_state),
    fn(_this_value, args) raise {
      match args {
        [_, Symbol(symbol), proxy_receiver] => {
          assert_true(physical_equal(proxy_receiver, receiver.val))
          assert_true(
            symbol.id == interp.realm_state.well_known_symbols.to_primitive.id,
          )
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
  let target = make_object(
    Map([]),
    Null,
    None,
    "MultiplicativeTarget",
    Map([]),
    true,
  )
  let handler = make_object(
    { "get": get_trap },
    Null,
    None,
    "MultiplicativeHandler",
    Map([]),
    true,
  )
  let proxy = Proxy({
    target: Some(target),
    handler: Some(handler),
    is_callable: false,
    is_constructor: false,
  })
  receiver.val = proxy
  expect_multiplicative_number(
    run_multiplicative_root_for_wb(
      interp,
      proxy,
      Number(2.0),
      ExecutorMultiplicativeOperator::ExecutorMultiplicativeMultiply,
    ),
    14.0,
    "Proxy conversion",
  )
  json_inspect(events, content=[
    "get:@@toPrimitive", "get:valueOf", "call:valueOf",
  ])
}

///|
test "default multiplicative Array coercion matches the managed owner" {
  let interp = Interpreter::new()
  let result = interp.run(
    @parser.parse("let array=[1];array.valueOf=()=>2;array*2===4;").stmts,
  )
  inspect(result, content="true")
  let fallback_result = interp.run(
    @parser.parse(
      "let array=[1];array.valueOf=()=>({});array.toString=()=>\"3\";" +
      "array*2===6;",
    ).stmts,
  )
  inspect(fallback_result, content="true")
}

///|
test "default and managed multiplicative results agree for primitive operands" {
  let interp = Interpreter::new()
  let cases : Array[(@ast.BinOp, Value, Value, Double)] = [
    (@ast.BinOp::Mul, String_("6"), Bool(true), 6.0),
    (@ast.BinOp::Div, Number(-1.0), Number(0.0), -1.0 / 0.0),
    (@ast.BinOp::Mod, Number(-5.0), Number(2.0), -1.0),
  ]
  for case in cases {
    let (op, left, right, expected) = case
    let default_result = eval_binary_op(
      op,
      left,
      right,
      @token.Loc::default(),
      interp=Some(interp),
    )
    match op {
      @ast.BinOp::Mul => {
        let managed = run_multiplicative_root_for_wb(
          interp,
          left,
          right,
          ExecutorMultiplicativeOperator::ExecutorMultiplicativeMultiply,
        )
        expect_multiplicative_number(
          default_result, expected, "default multiply",
        )
        expect_multiplicative_number(managed, expected, "managed multiply")
      }
      @ast.BinOp::Div => {
        let managed = run_multiplicative_root_for_wb(
          interp,
          left,
          right,
          ExecutorMultiplicativeOperator::ExecutorMultiplicativeDivide,
        )
        expect_multiplicative_number(default_result, expected, "default divide")
        expect_multiplicative_number(managed, expected, "managed divide")
      }
      @ast.BinOp::Mod => {
        let managed = run_multiplicative_root_for_wb(
          interp,
          left,
          right,
          ExecutorMultiplicativeOperator::ExecutorMultiplicativeRemainder,
        )
        expect_multiplicative_number(
          default_result, expected, "default remainder",
        )
        expect_multiplicative_number(managed, expected, "managed remainder")
      }
      _ => fail("unexpected multiplicative test operator")
    }
  }
}
