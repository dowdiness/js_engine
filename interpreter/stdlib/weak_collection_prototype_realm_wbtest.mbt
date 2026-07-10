///| Whitebox tests for stdlib WeakMap/WeakSet prototype ownership by RealmState.

///|
test "WeakMap prototype is realm-isolated" {
  let default_realm = new_realm_state()
  let shifted_realm = shifted_realm_state()
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
  let default_data = assert_object_value(
    "default WeakMap.prototype", default_proto,
  )
  let shifted_data = assert_object_value(
    "shifted WeakMap.prototype", shifted_proto,
  )
  if physical_equal(default_data, shifted_data) {
    fail("WeakMap.prototype must not be shared across realms")
  }

  // The realm-state field must agree with the JS-visible WeakMap.prototype
  // slot on the constructor object in BOTH realms. Decoupling these would let
  // a regression silently route dispatch through one source while user code
  // observes the other (cache-for-X invariant; Codex finding on PR #138).
  let default_ctor_proto = ctor_prototype_from_env(default_env, "WeakMap")
  let default_ctor_proto_data = assert_object_value(
    "default WeakMap constructor .prototype", default_ctor_proto,
  )
  if !physical_equal(default_data, default_ctor_proto_data) {
    fail(
      "realm_state.weakmap_prototype must equal WeakMap.prototype on the constructor (default realm)",
    )
  }
  let shifted_ctor_proto = ctor_prototype_from_env(shifted_env, "WeakMap")
  let shifted_ctor_proto_data = assert_object_value(
    "shifted WeakMap constructor .prototype", shifted_ctor_proto,
  )
  if !physical_equal(shifted_data, shifted_ctor_proto_data) {
    fail(
      "realm_state.weakmap_prototype must equal WeakMap.prototype on the constructor (shifted realm)",
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
  let default_get_obj = assert_object_value("default get", default_get)
  let shifted_get_obj = assert_object_value("shifted get", shifted_get)
  if physical_equal(default_get_obj, shifted_get_obj) {
    fail("WeakMap.prototype.get must not be shared across realms")
  }
}

///|
test "WeakSet prototype is realm-isolated" {
  let default_realm = new_realm_state()
  let shifted_realm = shifted_realm_state()
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
  let default_data = assert_object_value(
    "default WeakSet.prototype", default_proto,
  )
  let shifted_data = assert_object_value(
    "shifted WeakSet.prototype", shifted_proto,
  )
  if physical_equal(default_data, shifted_data) {
    fail("WeakSet.prototype must not be shared across realms")
  }

  // Realm-state proto field must agree with the constructor's .prototype in
  // BOTH realms (cache-for-X invariant; Codex finding on PR #138).
  let default_ctor_proto = ctor_prototype_from_env(default_env, "WeakSet")
  let default_ctor_proto_data = assert_object_value(
    "default WeakSet constructor .prototype", default_ctor_proto,
  )
  if !physical_equal(default_data, default_ctor_proto_data) {
    fail(
      "realm_state.weakset_prototype must equal WeakSet.prototype on the constructor (default realm)",
    )
  }
  let shifted_ctor_proto = ctor_prototype_from_env(shifted_env, "WeakSet")
  let shifted_ctor_proto_data = assert_object_value(
    "shifted WeakSet constructor .prototype", shifted_ctor_proto,
  )
  if !physical_equal(shifted_data, shifted_ctor_proto_data) {
    fail(
      "realm_state.weakset_prototype must equal WeakSet.prototype on the constructor (shifted realm)",
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
  let default_add_obj = assert_object_value("default add", default_add)
  let shifted_add_obj = assert_object_value("shifted add", shifted_add)
  if physical_equal(default_add_obj, shifted_add_obj) {
    fail("WeakSet.prototype.add must not be shared across realms")
  }
}

///|
test "WeakMap method lookup returns undefined for unknown keys" {
  let realm = new_realm_state()
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
  let realm = new_realm_state()
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
  let realm = new_realm_state()
  // No setup_weakmap_set_builtins call - realm.weakmap_prototype.val stays None.
  match get_weakmap_method("get", realm) {
    Undefined => ()
    _ => fail("expected Undefined without realm WeakMap.prototype")
  }
}

///|
test "WeakSet method lookup returns undefined when prototype is absent" {
  let realm = new_realm_state()
  match get_weakset_method("add", realm) {
    Undefined => ()
    _ => fail("expected Undefined without realm WeakSet.prototype")
  }
}

///|
/// Build a bare ObjectData for use as a stand-in for a WeakMap/WeakSet instance.
/// Tests use this with set_weakmap_id/set_weakset_id to drive the side table
/// without going through the JS-level constructor.
fn fresh_object_data() -> ObjectData {
  {
    bag: @runtime.PropertyBag(),
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  }
}

///|
test "WeakMap storage is realm-isolated" {
  let realm_a = new_realm_state()
  let realm_b = new_realm_state()

  // Both realms start with an empty counter.
  assert_eq(realm_a.weakmap_id_counter.val, 0)
  assert_eq(realm_b.weakmap_id_counter.val, 0)

  // Counters and id_tables must be physically distinct between realms.
  if physical_equal(realm_a.weakmap_id_counter, realm_b.weakmap_id_counter) {
    fail("weakmap_id_counter must not be shared across realms")
  }
  if physical_equal(realm_a.weakmap_id_table, realm_b.weakmap_id_table) {
    fail("weakmap_id_table must not be shared across realms")
  }
  if physical_equal(realm_a.weakmap_storage, realm_b.weakmap_storage) {
    fail("weakmap_storage must not be shared across realms")
  }

  // Writing to realm_a's id table must not be visible from realm_b.
  let data = fresh_object_data()
  set_weakmap_id(realm_a, data, 7)
  match get_weakmap_id(realm_a, data) {
    Some(id) => assert_eq(id, 7)
    None => fail("realm_a should hold the WeakMap id we just installed")
  }
  match get_weakmap_id(realm_b, data) {
    None => ()
    Some(_) => fail("realm_b must not see WeakMap ids installed in realm_a")
  }

  // Advancing realm_a's counter must not advance realm_b's.
  realm_a.weakmap_id_counter.val = 42
  assert_eq(realm_b.weakmap_id_counter.val, 0)

  // Storage maps populated in one realm must not surface in the other.
  realm_a.weakmap_storage[7] = [(Value::Number(1.0), Value::Number(2.0))]
  match realm_b.weakmap_storage.get(7) {
    None => ()
    Some(_) => fail("realm_b must not see WeakMap storage entries from realm_a")
  }
}

///|
test "WeakSet storage is realm-isolated" {
  let realm_a = new_realm_state()
  let realm_b = new_realm_state()

  assert_eq(realm_a.weakset_id_counter.val, 0)
  assert_eq(realm_b.weakset_id_counter.val, 0)

  if physical_equal(realm_a.weakset_id_counter, realm_b.weakset_id_counter) {
    fail("weakset_id_counter must not be shared across realms")
  }
  if physical_equal(realm_a.weakset_id_table, realm_b.weakset_id_table) {
    fail("weakset_id_table must not be shared across realms")
  }
  if physical_equal(realm_a.weakset_storage, realm_b.weakset_storage) {
    fail("weakset_storage must not be shared across realms")
  }

  let data = fresh_object_data()
  set_weakset_id(realm_a, data, 3)
  match get_weakset_id(realm_a, data) {
    Some(id) => assert_eq(id, 3)
    None => fail("realm_a should hold the WeakSet id we just installed")
  }
  match get_weakset_id(realm_b, data) {
    None => ()
    Some(_) => fail("realm_b must not see WeakSet ids installed in realm_a")
  }

  realm_a.weakset_id_counter.val = 99
  assert_eq(realm_b.weakset_id_counter.val, 0)

  realm_a.weakset_storage[3] = [Value::Number(1.0)]
  match realm_b.weakset_storage.get(3) {
    None => ()
    Some(_) => fail("realm_b must not see WeakSet storage entries from realm_a")
  }
}
