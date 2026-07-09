///| Whitebox tests for stdlib boxed-primitive prototype ownership by RealmState.
///
/// Pins the cache-for-X invariant for the four boxed primitives (String,
/// Number, Boolean, Symbol): the `realm_state.{string,number,boolean,symbol}_prototype`
/// field must agree with each constructor's `.prototype` slot in *every*
/// realm. Without this pin, a regression where one site reads stale state
/// and another reads fresh state would silently observe different prototype
/// objects depending on which API the user called.

///|
test "String prototype is realm-isolated" {
  let default_realm = new_realm_state()
  let shifted_realm = shifted_realm_state()
  let default_env = @runtime.Environment::new()
  let shifted_env = @runtime.Environment::new()
  setup_builtins_with_realm_state(default_env, [], default_realm)
  setup_builtins_with_realm_state(shifted_env, [], shifted_realm)
  let default_proto = match default_realm.string_prototype.val {
    Some(v) => v
    None => fail("default realm String.prototype missing")
  }
  let shifted_proto = match shifted_realm.string_prototype.val {
    Some(v) => v
    None => fail("shifted realm String.prototype missing")
  }
  let default_data = assert_object_value(
    "default String.prototype", default_proto,
  )
  let shifted_data = assert_object_value(
    "shifted String.prototype", shifted_proto,
  )
  if physical_equal(default_data, shifted_data) {
    fail("String.prototype must not be shared across realms")
  }

  // Cache-for-X: realm_state.string_prototype must equal the JS-visible
  // String.prototype slot on the constructor in BOTH realms. Decoupling
  // these would let a regression silently route Object.getPrototypeOf
  // through one source while user code observes the other.
  let default_ctor_proto = ctor_prototype_from_env(default_env, "String")
  let default_ctor_proto_data = assert_object_value(
    "default String constructor .prototype", default_ctor_proto,
  )
  if !physical_equal(default_data, default_ctor_proto_data) {
    fail(
      "realm_state.string_prototype must equal String.prototype on the constructor (default realm)",
    )
  }
  let shifted_ctor_proto = ctor_prototype_from_env(shifted_env, "String")
  let shifted_ctor_proto_data = assert_object_value(
    "shifted String constructor .prototype", shifted_ctor_proto,
  )
  if !physical_equal(shifted_data, shifted_ctor_proto_data) {
    fail(
      "realm_state.string_prototype must equal String.prototype on the constructor (shifted realm)",
    )
  }
}

///|
test "Number prototype is realm-isolated" {
  let default_realm = new_realm_state()
  let shifted_realm = shifted_realm_state()
  let default_env = @runtime.Environment::new()
  let shifted_env = @runtime.Environment::new()
  setup_builtins_with_realm_state(default_env, [], default_realm)
  setup_builtins_with_realm_state(shifted_env, [], shifted_realm)
  let default_proto = match default_realm.number_prototype.val {
    Some(v) => v
    None => fail("default realm Number.prototype missing")
  }
  let shifted_proto = match shifted_realm.number_prototype.val {
    Some(v) => v
    None => fail("shifted realm Number.prototype missing")
  }
  let default_data = assert_object_value(
    "default Number.prototype", default_proto,
  )
  let shifted_data = assert_object_value(
    "shifted Number.prototype", shifted_proto,
  )
  if physical_equal(default_data, shifted_data) {
    fail("Number.prototype must not be shared across realms")
  }
  let default_ctor_proto = ctor_prototype_from_env(default_env, "Number")
  let default_ctor_proto_data = assert_object_value(
    "default Number constructor .prototype", default_ctor_proto,
  )
  if !physical_equal(default_data, default_ctor_proto_data) {
    fail(
      "realm_state.number_prototype must equal Number.prototype on the constructor (default realm)",
    )
  }
  let shifted_ctor_proto = ctor_prototype_from_env(shifted_env, "Number")
  let shifted_ctor_proto_data = assert_object_value(
    "shifted Number constructor .prototype", shifted_ctor_proto,
  )
  if !physical_equal(shifted_data, shifted_ctor_proto_data) {
    fail(
      "realm_state.number_prototype must equal Number.prototype on the constructor (shifted realm)",
    )
  }
}

///|
test "Boolean prototype is realm-isolated" {
  let default_realm = new_realm_state()
  let shifted_realm = shifted_realm_state()
  let default_env = @runtime.Environment::new()
  let shifted_env = @runtime.Environment::new()
  setup_builtins_with_realm_state(default_env, [], default_realm)
  setup_builtins_with_realm_state(shifted_env, [], shifted_realm)
  let default_proto = match default_realm.boolean_prototype.val {
    Some(v) => v
    None => fail("default realm Boolean.prototype missing")
  }
  let shifted_proto = match shifted_realm.boolean_prototype.val {
    Some(v) => v
    None => fail("shifted realm Boolean.prototype missing")
  }
  let default_data = assert_object_value(
    "default Boolean.prototype", default_proto,
  )
  let shifted_data = assert_object_value(
    "shifted Boolean.prototype", shifted_proto,
  )
  if physical_equal(default_data, shifted_data) {
    fail("Boolean.prototype must not be shared across realms")
  }
  let default_ctor_proto = ctor_prototype_from_env(default_env, "Boolean")
  let default_ctor_proto_data = assert_object_value(
    "default Boolean constructor .prototype", default_ctor_proto,
  )
  if !physical_equal(default_data, default_ctor_proto_data) {
    fail(
      "realm_state.boolean_prototype must equal Boolean.prototype on the constructor (default realm)",
    )
  }
  let shifted_ctor_proto = ctor_prototype_from_env(shifted_env, "Boolean")
  let shifted_ctor_proto_data = assert_object_value(
    "shifted Boolean constructor .prototype", shifted_ctor_proto,
  )
  if !physical_equal(shifted_data, shifted_ctor_proto_data) {
    fail(
      "realm_state.boolean_prototype must equal Boolean.prototype on the constructor (shifted realm)",
    )
  }
}

///|
test "Symbol prototype is realm-isolated" {
  let default_realm = new_realm_state()
  let shifted_realm = shifted_realm_state()
  let default_env = @runtime.Environment::new()
  let shifted_env = @runtime.Environment::new()
  setup_builtins_with_realm_state(default_env, [], default_realm)
  setup_builtins_with_realm_state(shifted_env, [], shifted_realm)
  let default_proto = match default_realm.symbol_prototype.val {
    Some(v) => v
    None => fail("default realm Symbol.prototype missing")
  }
  let shifted_proto = match shifted_realm.symbol_prototype.val {
    Some(v) => v
    None => fail("shifted realm Symbol.prototype missing")
  }
  let default_data = assert_object_value(
    "default Symbol.prototype", default_proto,
  )
  let shifted_data = assert_object_value(
    "shifted Symbol.prototype", shifted_proto,
  )
  if physical_equal(default_data, shifted_data) {
    fail("Symbol.prototype must not be shared across realms")
  }
  let default_ctor_proto = ctor_prototype_from_env(default_env, "Symbol")
  let default_ctor_proto_data = assert_object_value(
    "default Symbol constructor .prototype", default_ctor_proto,
  )
  if !physical_equal(default_data, default_ctor_proto_data) {
    fail(
      "realm_state.symbol_prototype must equal Symbol.prototype on the constructor (default realm)",
    )
  }
  let shifted_ctor_proto = ctor_prototype_from_env(shifted_env, "Symbol")
  let shifted_ctor_proto_data = assert_object_value(
    "shifted Symbol constructor .prototype", shifted_ctor_proto,
  )
  if !physical_equal(shifted_data, shifted_ctor_proto_data) {
    fail(
      "realm_state.symbol_prototype must equal Symbol.prototype on the constructor (shifted realm)",
    )
  }
}
