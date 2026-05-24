///| Whitebox test for stdlib Array prototype ownership by RealmState.
///
/// Pins the cache-for-X invariant: `realm_state.array_prototype` must agree
/// with the Array constructor's `.prototype` slot in *every* realm. Without
/// this pin, a regression where one site reads `realm_state.array_prototype`
/// and another resolves `globalThis.Array.prototype` would silently observe
/// different prototype objects depending on which API the user called.

///|
fn new_array_realm_state() -> @runtime.RealmState {
  @runtime.RealmState::from_symbols(@runtime.SymbolState::new())
}

///|
fn shifted_array_realm_state() -> @runtime.RealmState {
  let symbols = @runtime.SymbolState::new()
  let _ = symbols.new_symbol(Some("offset"))
  @runtime.RealmState::from_symbols(symbols)
}

///|
fn assert_array_object(label : String, value : Value) -> ObjectData raise Error {
  match value {
    Object(data) => data
    _ => fail(label + " expected object value")
  }
}

///|
test "Array prototype is realm-isolated" {
  let default_realm = new_array_realm_state()
  let shifted_realm = shifted_array_realm_state()
  let default_env = @runtime.Environment::new()
  let shifted_env = @runtime.Environment::new()
  setup_builtins_with_realm_state(default_env, [], default_realm)
  setup_builtins_with_realm_state(shifted_env, [], shifted_realm)
  let default_proto = match default_realm.array_prototype.val {
    Some(v) => v
    None => fail("default realm Array.prototype missing")
  }
  let shifted_proto = match shifted_realm.array_prototype.val {
    Some(v) => v
    None => fail("shifted realm Array.prototype missing")
  }
  let default_data = assert_array_object(
    "default Array.prototype", default_proto,
  )
  let shifted_data = assert_array_object(
    "shifted Array.prototype", shifted_proto,
  )
  if physical_equal(default_data, shifted_data) {
    fail("Array.prototype must not be shared across realms")
  }

  // Cache-for-X: realm_state.array_prototype must equal the JS-visible
  // Array.prototype slot on the constructor in BOTH realms. Decoupling
  // these would let a regression silently route Object.getPrototypeOf
  // through one source while user code observes the other.
  let default_ctor_proto = ctor_prototype_from_env(default_env, "Array")
  let default_ctor_proto_data = assert_array_object(
    "default Array constructor .prototype", default_ctor_proto,
  )
  if !physical_equal(default_data, default_ctor_proto_data) {
    fail(
      "realm_state.array_prototype must equal Array.prototype on the constructor (default realm)",
    )
  }
  let shifted_ctor_proto = ctor_prototype_from_env(shifted_env, "Array")
  let shifted_ctor_proto_data = assert_array_object(
    "shifted Array constructor .prototype", shifted_ctor_proto,
  )
  if !physical_equal(shifted_data, shifted_ctor_proto_data) {
    fail(
      "realm_state.array_prototype must equal Array.prototype on the constructor (shifted realm)",
    )
  }
}

///|
test "Array prototype field remains None without setup" {
  // Mirror map_set_prototype_realm_wbtest "remains None" guard: without
  // setup_builtins_with_realm_state, `realm_state.array_prototype.val` MUST
  // stay None. Catches an accidental side-effect that lazily writes the
  // field outside the setup pipeline.
  let realm = new_array_realm_state()
  match realm.array_prototype.val {
    Some(_) =>
      fail(
        "realm_state.array_prototype must be None before setup_builtins_with_realm_state runs",
      )
    None => ()
  }
}
