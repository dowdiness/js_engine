///| Whitebox tests for stdlib Map/Set prototype ownership by RealmState.

///|
test "Map prototype is realm-isolated" {
  let default_realm = new_realm_state()
  let shifted_realm = shifted_realm_state()
  let default_env = @runtime.Environment::new()
  let shifted_env = @runtime.Environment::new()
  setup_map_set_builtins(default_env, default_realm)
  setup_map_set_builtins(shifted_env, shifted_realm)

  // Each realm must have an installed Map prototype.
  let default_proto = match default_realm.map_prototype.val {
    Some(v) => v
    None => fail("default realm Map.prototype missing")
  }
  let shifted_proto = match shifted_realm.map_prototype.val {
    Some(v) => v
    None => fail("shifted realm Map.prototype missing")
  }

  // The two prototypes must be physically distinct objects, not a shared
  // module-global value re-used across realms.
  let default_data = assert_object_value("default Map.prototype", default_proto)
  let shifted_data = assert_object_value("shifted Map.prototype", shifted_proto)
  if physical_equal(default_data, shifted_data) {
    fail("Map.prototype must not be shared across realms")
  }

  // The realm-state field must agree with the JS-visible Map.prototype
  // slot on the constructor object in BOTH realms. Decoupling these would
  // let a regression silently route dispatch through one source while user
  // code observes the other (cache-for-X invariant; Codex finding on PR #138).
  let default_ctor_proto = ctor_prototype_from_env(default_env, "Map")
  let default_ctor_proto_data = assert_object_value(
    "default Map constructor .prototype", default_ctor_proto,
  )
  if !physical_equal(default_data, default_ctor_proto_data) {
    fail(
      "realm_state.map_prototype must equal Map.prototype on the constructor (default realm)",
    )
  }
  let shifted_ctor_proto = ctor_prototype_from_env(shifted_env, "Map")
  let shifted_ctor_proto_data = assert_object_value(
    "shifted Map constructor .prototype", shifted_ctor_proto,
  )
  if !physical_equal(shifted_data, shifted_ctor_proto_data) {
    fail(
      "realm_state.map_prototype must equal Map.prototype on the constructor (shifted realm)",
    )
  }

  // get_map_method must dispatch through the supplied realm: the same
  // MapData and key must yield each realm's own get() function.
  let map_data = @runtime.MapData([])
  let default_get = get_map_method(map_data, "get", default_realm)
  let shifted_get = get_map_method(map_data, "get", shifted_realm)
  match default_get {
    Undefined => fail("expected Map.prototype.get in default realm")
    _ => ()
  }
  match shifted_get {
    Undefined => fail("expected Map.prototype.get in shifted realm")
    _ => ()
  }
  let default_get_obj = assert_object_value("default get", default_get)
  let shifted_get_obj = assert_object_value("shifted get", shifted_get)
  if physical_equal(default_get_obj, shifted_get_obj) {
    fail("Map.prototype.get must not be shared across realms")
  }
}

///|
test "Set prototype is realm-isolated" {
  let default_realm = new_realm_state()
  let shifted_realm = shifted_realm_state()
  let default_env = @runtime.Environment::new()
  let shifted_env = @runtime.Environment::new()
  setup_map_set_builtins(default_env, default_realm)
  setup_map_set_builtins(shifted_env, shifted_realm)

  let default_proto = match default_realm.set_prototype.val {
    Some(v) => v
    None => fail("default realm Set.prototype missing")
  }
  let shifted_proto = match shifted_realm.set_prototype.val {
    Some(v) => v
    None => fail("shifted realm Set.prototype missing")
  }
  let default_data = assert_object_value("default Set.prototype", default_proto)
  let shifted_data = assert_object_value("shifted Set.prototype", shifted_proto)
  if physical_equal(default_data, shifted_data) {
    fail("Set.prototype must not be shared across realms")
  }

  // Cache-for-X: per-realm symmetric pin to the constructor's .prototype slot.
  let default_ctor_proto = ctor_prototype_from_env(default_env, "Set")
  let default_ctor_proto_data = assert_object_value(
    "default Set constructor .prototype", default_ctor_proto,
  )
  if !physical_equal(default_data, default_ctor_proto_data) {
    fail(
      "realm_state.set_prototype must equal Set.prototype on the constructor (default realm)",
    )
  }
  let shifted_ctor_proto = ctor_prototype_from_env(shifted_env, "Set")
  let shifted_ctor_proto_data = assert_object_value(
    "shifted Set constructor .prototype", shifted_ctor_proto,
  )
  if !physical_equal(shifted_data, shifted_ctor_proto_data) {
    fail(
      "realm_state.set_prototype must equal Set.prototype on the constructor (shifted realm)",
    )
  }

  let set_data = @runtime.SetData([])
  let default_add = get_set_method(set_data, "add", default_realm)
  let shifted_add = get_set_method(set_data, "add", shifted_realm)
  match default_add {
    Undefined => fail("expected Set.prototype.add in default realm")
    _ => ()
  }
  match shifted_add {
    Undefined => fail("expected Set.prototype.add in shifted realm")
    _ => ()
  }
  let default_add_obj = assert_object_value("default add", default_add)
  let shifted_add_obj = assert_object_value("shifted add", shifted_add)
  if physical_equal(default_add_obj, shifted_add_obj) {
    fail("Set.prototype.add must not be shared across realms")
  }
}

///|
test "Map method lookup returns undefined for unknown keys" {
  let realm = new_realm_state()
  setup_map_set_builtins(@runtime.Environment::new(), realm)
  let map_data = @runtime.MapData([])
  match get_map_method(map_data, "no_such_method", realm) {
    Undefined => ()
    _ => fail("expected Undefined for unknown Map method")
  }
}

///|
test "Set method lookup returns undefined for unknown keys" {
  let realm = new_realm_state()
  setup_map_set_builtins(@runtime.Environment::new(), realm)
  let set_data = @runtime.SetData([])
  match get_set_method(set_data, "no_such_method", realm) {
    Undefined => ()
    _ => fail("expected Undefined for unknown Set method")
  }
}

///|
test "Map method lookup returns undefined when prototype is absent" {
  let realm = new_realm_state()
  // No setup_map_set_builtins call - realm.map_prototype.val stays None.
  let map_data = @runtime.MapData([])
  match get_map_method(map_data, "get", realm) {
    Undefined => ()
    _ => fail("expected Undefined without realm Map.prototype")
  }
}

///|
test "Set method lookup returns undefined when prototype is absent" {
  let realm = new_realm_state()
  let set_data = @runtime.SetData([])
  match get_set_method(set_data, "add", realm) {
    Undefined => ()
    _ => fail("expected Undefined without realm Set.prototype")
  }
}
