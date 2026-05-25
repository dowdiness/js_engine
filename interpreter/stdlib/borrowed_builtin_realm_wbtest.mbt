///| Whitebox tests for borrowed built-in functions using their home realm.

///|
fn make_borrowed_builtin_realm_interp() -> @runtime.Interpreter {
  @runtime.Interpreter::new(setup_builtins=fn(env, args, rs, ab) {
    setup_builtins_with_realm_state(env, args, rs, annex_b=ab)
  })
}

///|
fn install_borrowed_marker(
  proto : Value,
  marker_name : String,
  marker_value : String,
) -> Unit raise Error {
  match proto {
    Object(data) => data.bag.properties[marker_name] = String_(marker_value)
    _ => fail("expected object prototype for marker install")
  }
}

///|
fn assert_string_marker(
  label : String,
  value : Value,
  expected : String,
) -> Unit raise Error {
  match value {
    String_(actual) =>
      if actual != expected {
        fail(label + ": expected " + expected + ", got " + actual)
      }
    _ => fail(label + ": expected string marker")
  }
}

///|
fn assert_borrowed_get_prototype_of(
  label : String,
  caller_realm : @runtime.Interpreter,
  get_prototype_of : Value,
  arg : Value,
  expected_home_proto : Value,
  caller_proto : Value,
) -> Unit raise Error {
  let result = caller_realm.call_value(
    get_prototype_of,
    Undefined,
    [arg],
    @token.Loc::default(),
  )
  if !@runtime.strict_equal(result, expected_home_proto) {
    fail(
      label +
      ": borrowed Object.getPrototypeOf must return the callee realm prototype",
    )
  }
  if @runtime.strict_equal(result, caller_proto) {
    fail(
      label +
      ": borrowed Object.getPrototypeOf must not return the caller realm prototype",
    )
  }
}

///|
test "borrowed Object.getPrototypeOf uses built-in function realm for primitive" {
  let realm_a = make_borrowed_builtin_realm_interp()
  let realm_b = make_borrowed_builtin_realm_interp()
  let object_ctor = realm_a.global.get("Object")
  let get_prototype_of = realm_a.get_property(
    object_ctor,
    "getPrototypeOf",
    @token.Loc::default(),
  )
  assert_borrowed_get_prototype_of(
    "String primitive",
    realm_b,
    get_prototype_of,
    String_("from realm B call"),
    realm_a.realm_state.get_string_proto(),
    realm_b.realm_state.get_string_proto(),
  )
}

///|
test "borrowed Object.prototype.isPrototypeOf honors array prototype override" {
  let realm_a = make_borrowed_builtin_realm_interp()
  let realm_b = make_borrowed_builtin_realm_interp()
  let is_prototype_of = realm_a.get_property(
    realm_a.realm_state.get_obj_proto(),
    "isPrototypeOf",
    @token.Loc::default(),
  )
  let custom_proto = @runtime.make_object({}, Null, None, "Object", {}, true)
  let arr = @runtime.make_array([Number(1.0)])
  match arr {
    Array(data) => @runtime.set_array_prototype_override(data, custom_proto)
    _ => fail("expected array value")
  }
  match
    realm_b.call_value(
      is_prototype_of,
      custom_proto,
      [arr],
      @token.Loc::default(),
    ) {
    Bool(true) => ()
    _ => fail("borrowed isPrototypeOf must walk the argument array prototype")
  }
}

///|
test "borrowed Object.getPrototypeOf uses built-in function realm for primitives" {
  let realm_a = make_borrowed_builtin_realm_interp()
  let realm_b = make_borrowed_builtin_realm_interp()
  let object_ctor = realm_a.global.get("Object")
  let get_prototype_of = realm_a.get_property(
    object_ctor,
    "getPrototypeOf",
    @token.Loc::default(),
  )
  assert_borrowed_get_prototype_of(
    "Number primitive",
    realm_b,
    get_prototype_of,
    Number(1.0),
    realm_a.realm_state.get_number_proto(),
    realm_b.realm_state.get_number_proto(),
  )
  assert_borrowed_get_prototype_of(
    "Boolean primitive",
    realm_b,
    get_prototype_of,
    Bool(true),
    realm_a.realm_state.get_boolean_proto(),
    realm_b.realm_state.get_boolean_proto(),
  )
  assert_borrowed_get_prototype_of(
    "Symbol primitive",
    realm_b,
    get_prototype_of,
    Symbol(realm_a.realm_state.symbols.new_symbol(Some("borrowed"))),
    realm_a.realm_state.get_symbol_proto(),
    realm_b.realm_state.get_symbol_proto(),
  )
}

///|
test "Map and Set property lookup uses target realm prototype" {
  let interp = make_borrowed_builtin_realm_interp()
  let active_map_proto = @runtime.make_object(
    {},
    Null,
    None,
    "Object",
    {},
    true,
  )
  let active_set_proto = @runtime.make_object(
    {},
    Null,
    None,
    "Object",
    {},
    true,
  )
  interp.realm_state.active_map_prototype_override.val = Some(active_map_proto)
  interp.realm_state.active_set_prototype_override.val = Some(active_set_proto)
  install_borrowed_marker(
    interp.realm_state.get_map_proto(),
    "__target_marker__",
    "map-target",
  )
  install_borrowed_marker(
    interp.realm_state.get_set_proto(),
    "__target_marker__",
    "set-target",
  )
  assert_string_marker(
    "Map target marker",
    get_map_method(MapData([]), "__target_marker__", interp.realm_state),
    "map-target",
  )
  assert_string_marker(
    "Set target marker",
    get_set_method(SetData([]), "__target_marker__", interp.realm_state),
    "set-target",
  )
}

///|
test "borrowed Object.getPrototypeOf uses target prototype for object exotics" {
  let realm_a = make_borrowed_builtin_realm_interp()
  let realm_b = make_borrowed_builtin_realm_interp()
  let object_ctor = realm_a.global.get("Object")
  let get_prototype_of = realm_a.get_property(
    object_ctor,
    "getPrototypeOf",
    @token.Loc::default(),
  )
  let cases = [
    (
      "Array exotic",
      @runtime.make_array([Number(1.0)]),
      realm_b.realm_state.get_array_proto(),
    ),
    (
      "Map exotic",
      Map(MapData([], prototype=realm_b.realm_state.get_map_proto())),
      realm_b.realm_state.get_map_proto(),
    ),
    (
      "Set exotic",
      Set(SetData([], prototype=realm_b.realm_state.get_set_proto())),
      realm_b.realm_state.get_set_proto(),
    ),
    (
      "Promise exotic",
      Promise(@runtime.new_promise_data()),
      realm_b.realm_state.get_promise_proto(),
    ),
  ]
  for item in cases {
    let (label, arg, expected) = item
    let result = realm_b.call_value(
      get_prototype_of,
      Undefined,
      [arg],
      @token.Loc::default(),
    )
    if !@runtime.strict_equal(result, expected) {
      fail(
        label + ": borrowed Object.getPrototypeOf must return target prototype",
      )
    }
    match label {
      "Map exotic" | "Set exotic" =>
        if @runtime.strict_equal(result, realm_a.realm_state.get_map_proto()) ||
          @runtime.strict_equal(result, realm_a.realm_state.get_set_proto()) {
          fail(
            label +
            ": borrowed Object.getPrototypeOf must not return callee realm prototype",
          )
        }
      _ => ()
    }
  }
}
