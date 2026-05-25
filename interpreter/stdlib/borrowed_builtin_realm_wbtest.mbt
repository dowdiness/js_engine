///| Whitebox tests for borrowed built-in functions using their home realm.

///|
fn make_borrowed_builtin_realm_interp() -> @runtime.Interpreter {
  @runtime.Interpreter::new(setup_builtins=fn(env, args, rs, ab) {
    setup_builtins_with_realm_state(env, args, rs, annex_b=ab)
  })
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
test "borrowed Object.getPrototypeOf uses built-in function realm for builtin families" {
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
  assert_borrowed_get_prototype_of(
    "Array exotic",
    realm_b,
    get_prototype_of,
    @runtime.make_array([Number(1.0)]),
    realm_a.realm_state.get_array_proto(),
    realm_b.realm_state.get_array_proto(),
  )
  assert_borrowed_get_prototype_of(
    "Map exotic",
    realm_b,
    get_prototype_of,
    Map(MapData([])),
    realm_a.realm_state.get_map_proto(),
    realm_b.realm_state.get_map_proto(),
  )
  assert_borrowed_get_prototype_of(
    "Set exotic",
    realm_b,
    get_prototype_of,
    Set(SetData([])),
    realm_a.realm_state.get_set_proto(),
    realm_b.realm_state.get_set_proto(),
  )
  assert_borrowed_get_prototype_of(
    "Promise exotic",
    realm_b,
    get_prototype_of,
    Promise(@runtime.new_promise_data()),
    realm_a.realm_state.get_promise_proto(),
    realm_b.realm_state.get_promise_proto(),
  )
}
