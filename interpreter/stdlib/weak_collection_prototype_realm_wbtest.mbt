///| Whitebox tests for stdlib WeakMap/WeakSet prototype ownership by RealmState.

///|
fn new_weak_realm_state() -> @runtime.RealmState {
  @runtime.RealmState::from_symbols(@runtime.SymbolState::new())
}

///|
fn shifted_weak_realm_state() -> @runtime.RealmState {
  let symbols = @runtime.SymbolState::new()
  let _ = symbols.new_symbol(Some("offset"))
  @runtime.RealmState::from_symbols(symbols)
}

///|
fn assert_weak_object(label : String, value : Value) -> ObjectData raise Error {
  match value {
    Object(data) => data
    _ => fail(label + " expected object value")
  }
}

///|
/// Look up the named constructor's `prototype` property from an environment.
///
/// This bridges the realm-state proto field to the JS-visible proto: a
/// regression that decouples `realm_state.{weakmap,weakset}_prototype` from
/// the constructor's `.prototype` slot would otherwise be invisible to a
/// realm-only test.
fn ctor_prototype_from_env(
  env : @runtime.Environment,
  ctor_name : String,
) -> Value raise Error {
  let ctor = match env.bindings.get(ctor_name) {
    Some(binding) => binding.value
    None => fail(ctor_name + " constructor missing from environment")
  }
  let ctor_data = match ctor {
    Object(data) => data
    _ => fail(ctor_name + " constructor is not an object")
  }
  match ctor_data.bag.properties.get("prototype") {
    Some(p) => p
    None => fail(ctor_name + ".prototype property missing from constructor")
  }
}

///|
test "WeakMap prototype is realm-isolated" {
  let default_realm = new_weak_realm_state()
  let shifted_realm = shifted_weak_realm_state()
  let default_env = @runtime.Environment::new()
  let shifted_env = @runtime.Environment::new()
  setup_weakmap_set_builtins(
    default_env,
    default_realm.well_known_symbols,
    default_realm,
  )
  setup_weakmap_set_builtins(
    shifted_env,
    shifted_realm.well_known_symbols,
    shifted_realm,
  )

  // Each realm must have an installed WeakMap prototype.
  let default_proto = match default_realm.weakmap_prototype.val {
    Some(v) => v
    None => fail("default realm WeakMap.prototype missing")
  }
  let shifted_proto = match shifted_realm.weakmap_prototype.val {
    Some(v) => v
    None => fail("shifted realm WeakMap.prototype missing")
  }

  // The two prototypes must be physically distinct objects, not a shared
  // module-global value re-used across realms.
  let default_data = assert_weak_object(
    "default WeakMap.prototype", default_proto,
  )
  let shifted_data = assert_weak_object(
    "shifted WeakMap.prototype", shifted_proto,
  )
  if physical_equal(default_data, shifted_data) {
    fail("WeakMap.prototype must not be shared across realms")
  }

  // The realm-state field must agree with the JS-visible WeakMap.prototype
  // slot on the constructor object. Decoupling these would let a regression
  // silently route dispatch through one source while user code observes the
  // other.
  let default_ctor_proto = ctor_prototype_from_env(default_env, "WeakMap")
  let default_ctor_proto_data = assert_weak_object(
    "default WeakMap constructor .prototype", default_ctor_proto,
  )
  if !physical_equal(default_data, default_ctor_proto_data) {
    fail(
      "realm_state.weakmap_prototype must equal WeakMap.prototype on the constructor",
    )
  }

  // get_weakmap_method must dispatch through the supplied realm: the same
  // key must yield each realm's own get() function.
  let default_get = get_weakmap_method("get", default_realm)
  let shifted_get = get_weakmap_method("get", shifted_realm)
  match default_get {
    Undefined => fail("expected WeakMap.prototype.get in default realm")
    _ => ()
  }
  match shifted_get {
    Undefined => fail("expected WeakMap.prototype.get in shifted realm")
    _ => ()
  }
  let default_get_obj = assert_weak_object("default get", default_get)
  let shifted_get_obj = assert_weak_object("shifted get", shifted_get)
  if physical_equal(default_get_obj, shifted_get_obj) {
    fail("WeakMap.prototype.get must not be shared across realms")
  }
}

///|
test "WeakSet prototype is realm-isolated" {
  let default_realm = new_weak_realm_state()
  let shifted_realm = shifted_weak_realm_state()
  let default_env = @runtime.Environment::new()
  let shifted_env = @runtime.Environment::new()
  setup_weakmap_set_builtins(
    default_env,
    default_realm.well_known_symbols,
    default_realm,
  )
  setup_weakmap_set_builtins(
    shifted_env,
    shifted_realm.well_known_symbols,
    shifted_realm,
  )

  let default_proto = match default_realm.weakset_prototype.val {
    Some(v) => v
    None => fail("default realm WeakSet.prototype missing")
  }
  let shifted_proto = match shifted_realm.weakset_prototype.val {
    Some(v) => v
    None => fail("shifted realm WeakSet.prototype missing")
  }
  let default_data = assert_weak_object(
    "default WeakSet.prototype", default_proto,
  )
  let shifted_data = assert_weak_object(
    "shifted WeakSet.prototype", shifted_proto,
  )
  if physical_equal(default_data, shifted_data) {
    fail("WeakSet.prototype must not be shared across realms")
  }

  // Realm-state proto field must agree with the constructor's .prototype.
  let default_ctor_proto = ctor_prototype_from_env(default_env, "WeakSet")
  let default_ctor_proto_data = assert_weak_object(
    "default WeakSet constructor .prototype", default_ctor_proto,
  )
  if !physical_equal(default_data, default_ctor_proto_data) {
    fail(
      "realm_state.weakset_prototype must equal WeakSet.prototype on the constructor",
    )
  }

  let default_add = get_weakset_method("add", default_realm)
  let shifted_add = get_weakset_method("add", shifted_realm)
  match default_add {
    Undefined => fail("expected WeakSet.prototype.add in default realm")
    _ => ()
  }
  match shifted_add {
    Undefined => fail("expected WeakSet.prototype.add in shifted realm")
    _ => ()
  }
  let default_add_obj = assert_weak_object("default add", default_add)
  let shifted_add_obj = assert_weak_object("shifted add", shifted_add)
  if physical_equal(default_add_obj, shifted_add_obj) {
    fail("WeakSet.prototype.add must not be shared across realms")
  }
}

///|
test "WeakMap method lookup returns undefined for unknown keys" {
  let realm = new_weak_realm_state()
  setup_weakmap_set_builtins(
    @runtime.Environment::new(),
    realm.well_known_symbols,
    realm,
  )
  match get_weakmap_method("no_such_method", realm) {
    Undefined => ()
    _ => fail("expected Undefined for unknown WeakMap method")
  }
}

///|
test "WeakSet method lookup returns undefined for unknown keys" {
  let realm = new_weak_realm_state()
  setup_weakmap_set_builtins(
    @runtime.Environment::new(),
    realm.well_known_symbols,
    realm,
  )
  match get_weakset_method("no_such_method", realm) {
    Undefined => ()
    _ => fail("expected Undefined for unknown WeakSet method")
  }
}

///|
test "WeakMap method lookup returns undefined when prototype is absent" {
  let realm = new_weak_realm_state()
  // No setup_weakmap_set_builtins call - realm.weakmap_prototype.val stays None.
  match get_weakmap_method("get", realm) {
    Undefined => ()
    _ => fail("expected Undefined without realm WeakMap.prototype")
  }
}

///|
test "WeakSet method lookup returns undefined when prototype is absent" {
  let realm = new_weak_realm_state()
  match get_weakset_method("add", realm) {
    Undefined => ()
    _ => fail("expected Undefined without realm WeakSet.prototype")
  }
}
