///| Whitebox tests for conversions.mbt: private parsing helpers,

///| is_truthy, to_number, and to_js_string.

///|
fn expect_double(
  actual : Double,
  expected : Double,
  label : String,
) -> Unit raise Error {
  guard actual == expected else {
    fail(
      label +
      ": expected " +
      expected.to_string() +
      ", got " +
      actual.to_string(),
    )
  }
}

///|
fn expect_nan(actual : Double, label : String) -> Unit raise Error {
  guard actual.is_nan() else {
    fail(label + ": expected NaN, got " + actual.to_string())
  }
}

///|
test "parse_hex_string - lowercase digits" {
  expect_double(parse_hex_string("ff"), 255.0, "ff")
}

///|
test "parse_hex_string - uppercase digits" {
  expect_double(parse_hex_string("FF"), 255.0, "FF")
}

///|
test "parse_hex_string - mixed case" {
  expect_double(parse_hex_string("aB"), 171.0, "aB")
}

///|
test "parse_hex_string - single digit" {
  expect_double(parse_hex_string("f"), 15.0, "f")
}

///|
test "parse_hex_string - zero" {
  expect_double(parse_hex_string("0"), 0.0, "0")
}

///|
test "parse_hex_string - multi digit" {
  expect_double(parse_hex_string("10"), 16.0, "10")
}

///|
test "parse_hex_string - empty string returns NaN" {
  expect_nan(parse_hex_string(""), "empty hex")
}

///|
test "parse_hex_string - invalid char returns NaN" {
  expect_nan(parse_hex_string("fg"), "fg")
}

///|
test "parse_hex_string - invalid char mid-string returns NaN" {
  expect_nan(parse_hex_string("1g2"), "1g2")
}

///|
test "parse_binary_string - valid" {
  expect_double(parse_binary_string("101"), 5.0, "101")
}

///|
test "parse_binary_string - zero" {
  expect_double(parse_binary_string("0"), 0.0, "0")
}

///|
test "parse_binary_string - one" {
  expect_double(parse_binary_string("1"), 1.0, "1")
}

///|
test "parse_binary_string - all zeros" {
  expect_double(parse_binary_string("000"), 0.0, "000")
}

///|
test "parse_binary_string - empty string returns NaN" {
  expect_nan(parse_binary_string(""), "empty binary")
}

///|
test "parse_binary_string - digit 2 returns NaN" {
  expect_nan(parse_binary_string("102"), "102")
}

///|
test "parse_binary_string - letter returns NaN" {
  expect_nan(parse_binary_string("1a0"), "1a0")
}

///|
test "parse_octal_string - valid" {
  expect_double(parse_octal_string("17"), 15.0, "17")
}

///|
test "parse_octal_string - zero" {
  expect_double(parse_octal_string("0"), 0.0, "0")
}

///|
test "parse_octal_string - max digit 7" {
  expect_double(parse_octal_string("7"), 7.0, "7")
}

///|
test "parse_octal_string - multi digit" {
  expect_double(parse_octal_string("10"), 8.0, "10")
}

///|
test "parse_octal_string - empty string returns NaN" {
  expect_nan(parse_octal_string(""), "empty octal")
}

///|
test "parse_octal_string - digit 8 returns NaN" {
  expect_nan(parse_octal_string("18"), "18")
}

///|
test "parse_octal_string - digit 9 returns NaN" {
  expect_nan(parse_octal_string("19"), "19")
}

///|
test "parse_octal_string - letter returns NaN" {
  expect_nan(parse_octal_string("1a"), "1a")
}

// ── Helpers for is_truthy / to_number / to_js_string tests ──────────────────

///|
fn expect_bool(
  actual : Bool,
  expected : Bool,
  label : String,
) -> Unit raise Error {
  guard actual == expected else {
    fail(
      label +
      ": expected " +
      expected.to_string() +
      ", got " +
      actual.to_string(),
    )
  }
}

///|
fn expect_str(
  actual : String,
  expected : String,
  label : String,
) -> Unit raise Error {
  guard actual == expected else {
    fail(label + ": expected \"" + expected + "\", got \"" + actual + "\"")
  }
}

// ── is_truthy ────────────────────────────────────────────────────────────────

///|
test "is_truthy - zero is falsy" {
  expect_bool(is_truthy(Number(0.0)), false, "0")
}

///|
test "is_truthy - negative zero is falsy" {
  expect_bool(is_truthy(Number(-0.0)), false, "-0")
}

///|
test "is_truthy - NaN is falsy" {
  expect_bool(is_truthy(Number(0.0 / 0.0)), false, "NaN")
}

///|
test "is_truthy - positive number is truthy" {
  expect_bool(is_truthy(Number(1.0)), true, "1")
}

///|
test "is_truthy - negative number is truthy" {
  expect_bool(is_truthy(Number(-1.0)), true, "-1")
}

///|
test "is_truthy - empty string is falsy" {
  expect_bool(is_truthy(String_("")), false, "empty string")
}

///|
test "is_truthy - string zero is truthy" {
  // JS: "0" is truthy (non-empty string), unlike the number 0
  expect_bool(is_truthy(String_("0")), true, "\"0\"")
}

///|
test "is_truthy - string false is truthy" {
  // JS: "false" is truthy (non-empty string), unlike the bool false
  expect_bool(is_truthy(String_("false")), true, "\"false\"")
}

///|
test "is_truthy - bool true is truthy" {
  expect_bool(is_truthy(Bool(true)), true, "true")
}

///|
test "is_truthy - bool false is falsy" {
  expect_bool(is_truthy(Bool(false)), false, "false")
}

///|
test "is_truthy - null is falsy" {
  expect_bool(is_truthy(Null), false, "null")
}

///|
test "is_truthy - undefined is falsy" {
  expect_bool(is_truthy(Undefined), false, "undefined")
}

// ── to_number ────────────────────────────────────────────────────────────────

///|
test "to_number - number passthrough" {
  let n = to_number(Number(42.0))
  expect_double(n, 42.0, "42")
}

///|
test "to_number - bool true is 1" {
  let n = to_number(Bool(true))
  expect_double(n, 1.0, "true")
}

///|
test "to_number - bool false is 0" {
  let n = to_number(Bool(false))
  expect_double(n, 0.0, "false")
}

///|
test "to_number - null is 0" {
  let n = to_number(Null)
  expect_double(n, 0.0, "null")
}

///|
test "to_number - undefined is NaN" {
  let n = to_number(Undefined)
  expect_nan(n, "undefined")
}

///|
test "to_number - empty string is 0" {
  let n = to_number(String_(""))
  expect_double(n, 0.0, "empty string")
}

///|
test "to_number - whitespace-only string is 0" {
  let n = to_number(String_("   "))
  expect_double(n, 0.0, "whitespace")
}

///|
test "to_number - decimal string" {
  let n = to_number(String_("42"))
  expect_double(n, 42.0, "\"42\"")
}

///|
test "to_number - decimal string with surrounding whitespace" {
  let n = to_number(String_("  42  "))
  expect_double(n, 42.0, "\" 42 \"")
}

///|
test "to_number - hex string lowercase prefix" {
  let n = to_number(String_("0xff"))
  expect_double(n, 255.0, "0xff")
}

///|
test "to_number - hex string uppercase prefix" {
  let n = to_number(String_("0XFF"))
  expect_double(n, 255.0, "0XFF")
}

///|
test "to_number - binary string" {
  let n = to_number(String_("0b101"))
  expect_double(n, 5.0, "0b101")
}

///|
test "to_number - octal string" {
  let n = to_number(String_("0o17"))
  expect_double(n, 15.0, "0o17")
}

///|
test "to_number - Infinity string" {
  let n = to_number(String_("Infinity"))
  expect_double(n, 1.0 / 0.0, "Infinity")
}

///|
test "to_number - negative Infinity string" {
  let n = to_number(String_("-Infinity"))
  expect_double(n, -1.0 / 0.0, "-Infinity")
}

///|
test "to_number - numeric separator rejected" {
  // Numeric separators are only valid in source code, not in Number()
  let n = to_number(String_("1_000"))
  expect_nan(n, "1_000")
}

///|
test "to_number - non-numeric string is NaN" {
  let n = to_number(String_("abc"))
  expect_nan(n, "abc")
}

///|
test "to_number - symbol raises TypeError" {
  let raised = try {
    let _ = to_number(Symbol({ id: 1, description: None }))
    false
  } catch {
    @errors.TypeError(_) => true
    _ => false
  }
  guard raised else {
    fail("expected TypeError when converting Symbol to number")
  }
}

///|
test "subtraction observes an Array own valueOf hook" {
  let interp = Interpreter::new()
  let result = interp.run(
    @parser.parse("let array=[1];array.valueOf=()=>2;array-1;").stmts,
  )
  match result {
    Number(value) => inspect(value, content="1")
    _ => fail("expected Array subtraction to produce Number(1)")
  }
}

///|
test "subtraction uses Number coercion for primitive operands" {
  let interp = Interpreter::new()
  let result = interp.run(
    @parser.parse(
      "5-2===3&&'7'-'2'===5&&true-null===1&&" + "(undefined-1)!==(undefined-1);",
    ).stmts,
  )
  inspect(result, content="true")
}

///|
test "subtraction passes the number hint through Array @@toPrimitive" {
  let interp = Interpreter::new()
  let array = make_array([Number(1.0)])
  let hook = make_method_func(
    name="array @@toPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, args) raise {
      match args {
        [String_(hint)] => inspect(hint, content="number")
        _ => fail("expected the number hint argument")
      }
      Number(3.0)
    },
  )
  match array {
    Array(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = hook
    _ => fail("expected an array fixture")
  }
  let result = eval_binary_op(
    @ast.BinOp::Sub,
    array,
    Number(1.0),
    @token.Loc::default(),
    interp=Some(interp),
  )
  inspect(result.to_string(), content="2")
}

///|
test "subtraction falls back from Array valueOf to its toString hook" {
  let interp = Interpreter::new()
  let result = interp.run(
    @parser.parse(
      "let array=[1];array.valueOf=()=>({});array.toString=()=>\"3\";" +
      "array-1===2;",
    ).stmts,
  )
  inspect(result, content="true")
}

///|
test "subtraction observes inherited Array conversion hooks" {
  let interp = Interpreter::new()
  let receiver : Ref[Value] = { val: Undefined }
  let value_of = make_method_func(
    name="inheritedValueOf",
    realm_state=Some(interp.realm_state),
    fn(this_value, _args) raise {
      assert_true(physical_equal(this_value, receiver.val))
      Number(4.0)
    },
  )
  let proto = make_object(
    { "valueOf": value_of },
    Null,
    None,
    "ArrayPrototype",
    Map([]),
    true,
  )
  let array = make_array_with_prototype([Number(1.0)], proto)
  receiver.val = array
  let result = eval_binary_op(
    @ast.BinOp::Sub,
    array,
    Number(1.0),
    @token.Loc::default(),
    interp=Some(interp),
  )
  inspect(result.to_string(), content="3")

  let fallback = make_object(Map([]), Null, None, "Fallback", Map([]), true)
  let inherited_value_of = make_method_func(
    name="inheritedObjectValueOf",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { fallback },
  )
  let inherited_to_string = make_method_func(
    name="inheritedToString",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { String_("5") },
  )
  let fallback_proto = make_object(
    { "valueOf": inherited_value_of, "toString": inherited_to_string },
    Null,
    None,
    "ArrayPrototype",
    Map([]),
    true,
  )
  let fallback_array = make_array_with_prototype([Number(1.0)], fallback_proto)
  let fallback_result = eval_binary_op(
    @ast.BinOp::Sub,
    fallback_array,
    Number(1.0),
    @token.Loc::default(),
    interp=Some(interp),
  )
  inspect(fallback_result.to_string(), content="4")
}

///|
test "subtraction observes inherited Array @@toPrimitive" {
  let interp = Interpreter::new()
  let hook = make_method_func(
    name="inherited@@toPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, args) raise {
      match args {
        [String_(hint)] => inspect(hint, content="number")
        _ => fail("expected the number hint argument")
      }
      Number(6.0)
    },
  )
  let proto = make_object(Map([]), Null, None, "ArrayPrototype", Map([]), true)
  match proto {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = hook
    _ => fail("expected an array prototype fixture")
  }
  let array = make_array_with_prototype([Number(1.0)], proto)
  let result = eval_binary_op(
    @ast.BinOp::Sub,
    array,
    Number(1.0),
    @token.Loc::default(),
    interp=Some(interp),
  )
  inspect(result.to_string(), content="5")
}

///|
test "subtraction observes valueOf hooks on Map Set and Promise" {
  let interp = Interpreter::new()
  let value_of = make_method_func(
    name="collectionValueOf",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { Number(4.0) },
  )
  let map = Map(MapData([]))
  match map {
    Map(data) => data.bag.properties["valueOf"] = value_of
    _ => fail("expected a Map fixture")
  }
  let set = Set(SetData([]))
  match set {
    Set(data) => data.bag.properties["valueOf"] = value_of
    _ => fail("expected a Set fixture")
  }
  let promise = Promise(new_promise_data())
  match promise {
    Promise(data) => data.bag.properties["valueOf"] = value_of
    _ => fail("expected a Promise fixture")
  }
  for value in [map, set, promise] {
    let result = eval_binary_op(
      @ast.BinOp::Sub,
      value,
      Number(1.0),
      @token.Loc::default(),
      interp=Some(interp),
    )
    inspect(result.to_string(), content="3")
  }
}

// ── to_js_string ─────────────────────────────────────────────────────────────

///|
test "to_js_string - string passthrough" {
  let s = to_js_string(String_("hello"))
  expect_str(s, "hello", "string")
}

///|
test "to_js_string - integer number has no decimal point" {
  let s = to_js_string(Number(42.0))
  expect_str(s, "42", "42")
}

///|
test "to_js_string - float number preserves decimal" {
  let s = to_js_string(Number(3.14))
  expect_str(s, "3.14", "3.14")
}

///|
test "to_js_string - zero" {
  let s = to_js_string(Number(0.0))
  expect_str(s, "0", "0")
}

///|
test "to_js_string - negative zero formats as zero" {
  // JS spec: String(-0) === "0"
  let s = to_js_string(Number(-0.0))
  expect_str(s, "0", "-0")
}

///|
test "to_js_string - NaN" {
  let s = to_js_string(Number(0.0 / 0.0))
  expect_str(s, "NaN", "NaN")
}

///|
test "to_js_string - Infinity" {
  let s = to_js_string(Number(1.0 / 0.0))
  expect_str(s, "Infinity", "Infinity")
}

///|
test "to_js_string - negative Infinity" {
  let s = to_js_string(Number(-1.0 / 0.0))
  expect_str(s, "-Infinity", "-Infinity")
}

///|
test "to_js_string - bool true" {
  let s = to_js_string(Bool(true))
  expect_str(s, "true", "true")
}

///|
test "to_js_string - bool false" {
  let s = to_js_string(Bool(false))
  expect_str(s, "false", "false")
}

///|
test "to_js_string - null" {
  let s = to_js_string(Null)
  expect_str(s, "null", "null")
}

///|
test "to_js_string - undefined" {
  let s = to_js_string(Undefined)
  expect_str(s, "undefined", "undefined")
}

///|
test "to_js_string - symbol raises TypeError" {
  let raised = try {
    let _ = to_js_string(Symbol({ id: 1, description: None }))
    false
  } catch {
    @errors.TypeError(_) => true
    _ => false
  }
  guard raised else {
    fail("expected TypeError when converting Symbol to string")
  }
}

///|
test "to_index keeps max-safe index as Int64" {
  let idx = to_index(Number(9007199254740991.0))
  guard idx == 9007199254740991L else {
    fail("expected max-safe index, got " + idx.to_string())
  }
}

///|
test "to_index rejects values at 2^53" {
  let raised = try {
    let _ = to_index(Number(9007199254740992.0))
    false
  } catch {
    @errors.RangeError(_) => true
    _ => false
  }
  guard raised else { fail("expected RangeError for 2^53 index") }
}

///|
test "to_index rejects negative indexes" {
  let raised = try {
    let _ = to_index(Number(-1.0))
    false
  } catch {
    @errors.RangeError(_) => true
    _ => false
  }
  guard raised else { fail("expected RangeError for negative index") }
}
