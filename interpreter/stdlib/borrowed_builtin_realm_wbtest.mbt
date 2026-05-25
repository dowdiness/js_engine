///| Whitebox tests for borrowed built-in functions using their home realm.

///|
fn make_borrowed_builtin_realm_interp() -> @runtime.Interpreter {
  @runtime.Interpreter::new(setup_builtins=fn(env, args, rs, ab) {
    setup_builtins_with_realm_state(env, args, rs, annex_b=ab)
  })
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
  let result = realm_b.call_value(
    get_prototype_of,
    Undefined,
    [String_("from realm B call")],
    @token.Loc::default(),
  )
  if !@runtime.strict_equal(result, realm_a.realm_state.get_string_proto()) {
    fail(
      "borrowed Object.getPrototypeOf must return the callee realm String.prototype",
    )
  }
  if @runtime.strict_equal(result, realm_b.realm_state.get_string_proto()) {
    fail(
      "borrowed Object.getPrototypeOf must not return the caller realm String.prototype",
    )
  }
}
