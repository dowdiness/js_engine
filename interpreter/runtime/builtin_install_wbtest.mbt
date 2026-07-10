///| Whitebox tests for the cache-for-X built-in constructor install contract.

///|
fn pinned_install_proto(label : String) -> Value {
  make_object({ "label": String_(label) }, Null, None, "Object", {}, true)
}

///|
fn pinned_install_ctor(name : String) -> Value {
  make_native_func(name~, fn(_args) { Undefined })
}

///|
fn pinned_ctor_prototype(ctor : Value) -> Value raise Error {
  match ctor {
    Object(data) =>
      match data.bag.properties.get("prototype") {
        Some(proto) => proto
        None => fail("constructor .prototype missing")
      }
    _ => fail("constructor is not an object")
  }
}

///|
fn pinned_ctor_prototype_descriptor(ctor : Value) -> PropDescriptor raise Error {
  match ctor {
    Object(data) =>
      match data.bag.descriptors.get("prototype") {
        Some(desc) => desc
        None => fail("constructor .prototype descriptor missing")
      }
    _ => fail("constructor is not an object")
  }
}

///|
fn pinned_proto_constructor(proto : Value) -> Value raise Error {
  match proto {
    Object(data) =>
      match data.bag.properties.get("constructor") {
        Some(ctor) => ctor
        None => fail("prototype .constructor missing")
      }
    _ => fail("prototype is not an object")
  }
}

///|
fn pinned_assert_same_object(
  label : String,
  left : Value,
  right : Value,
) -> Unit raise Error {
  match (left, right) {
    (Object(left_data), Object(right_data)) =>
      if !physical_equal(left_data, right_data) {
        fail(label + " expected same object")
      }
    _ => fail(label + " expected object values")
  }
}

///|
fn pinned_assert_distinct_object(
  label : String,
  left : Value,
  right : Value,
) -> Unit raise Error {
  match (left, right) {
    (Object(left_data), Object(right_data)) =>
      if physical_equal(left_data, right_data) {
        fail(label + " expected distinct objects")
      }
    _ => fail(label + " expected object values")
  }
}

///|
test "install_realm_pinned_builtin_constructor aligns cache and ctor prototype" {
  let env = Environment::new()
  let cache : Ref[Value?] = { val: None }
  let proto = pinned_install_proto("PinnedProto")
  let ctor = pinned_install_ctor("PinnedCtor")
  install_realm_pinned_builtin_constructor(
    env, cache, "PinnedCtor", ctor, proto,
  )

  match cache.val {
    Some(cached) => pinned_assert_same_object("realm cache", cached, proto)
    None => fail("realm proto cache must be populated")
  }
  let installed_ctor = match env.bindings.get("PinnedCtor") {
    Some(binding) => binding.value
    None => fail("constructor must be registered in env")
  }
  pinned_assert_same_object(
    "constructor .prototype",
    pinned_ctor_prototype(installed_ctor),
    proto,
  )
  let desc = pinned_ctor_prototype_descriptor(installed_ctor)
  if desc.writable || desc.enumerable || desc.configurable {
    fail("constructor .prototype must use frozen data descriptor")
  }
}

///|
test "install_realm_pinned_builtin_constructor_with_proto_constructor wires proto.constructor" {
  let env = Environment::new()
  let cache : Ref[Value?] = { val: None }
  let proto = pinned_install_proto("LinkedProto")
  let ctor = pinned_install_ctor("LinkedCtor")
  install_realm_pinned_builtin_constructor_with_proto_constructor(
    env, cache, "LinkedCtor", ctor, proto,
  )

  let installed_ctor = match env.bindings.get("LinkedCtor") {
    Some(binding) => binding.value
    None => fail("constructor must be registered in env")
  }
  pinned_assert_same_object(
    "proto.constructor",
    pinned_proto_constructor(proto),
    installed_ctor,
  )
  match cache.val {
    Some(cached) => pinned_assert_same_object("realm cache", cached, proto)
    None => fail("realm proto cache must be populated")
  }
}

///|
test "pinned install is isolated per env and cache ref" {
  let env_a = Environment::new()
  let env_b = Environment::new()
  let cache_a : Ref[Value?] = { val: None }
  let cache_b : Ref[Value?] = { val: None }
  let proto_a = pinned_install_proto("RealmA")
  let proto_b = pinned_install_proto("RealmB")
  let ctor_a = pinned_install_ctor("CtorA")
  let ctor_b = pinned_install_ctor("CtorB")
  install_realm_pinned_builtin_constructor_with_proto_constructor(
    env_a, cache_a, "CtorA", ctor_a, proto_a,
  )
  install_realm_pinned_builtin_constructor_with_proto_constructor(
    env_b, cache_b, "CtorB", ctor_b, proto_b,
  )

  match (cache_a.val, cache_b.val) {
    (Some(a), Some(b)) => pinned_assert_distinct_object("realm caches", a, b)
    _ => fail("each realm cache must hold its own prototype")
  }
  pinned_assert_same_object(
    "env_a ctor prototype",
    pinned_ctor_prototype(
      match env_a.bindings.get("CtorA") {
        Some(binding) => binding.value
        None => fail("CtorA missing from env_a")
      },
    ),
    proto_a,
  )
  pinned_assert_same_object(
    "env_b ctor prototype",
    pinned_ctor_prototype(
      match env_b.bindings.get("CtorB") {
        Some(binding) => binding.value
        None => fail("CtorB missing from env_b")
      },
    ),
    proto_b,
  )
}

///|
fn bagged_install_ctor(proto : Value, name : String) -> Value {
  let props : Map[String, Value] = { "prototype": proto, "name": String_(name) }
  let descs : Map[String, PropDescriptor] = {
    "prototype": {
      writable: false,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
      is_accessor: false,
    },
    "name": builtin_method_desc(),
  }
  make_object(
    props,
    Null,
    Some(NonConstructableCallable(name, fn(_args) { Undefined })),
    "Function",
    descs,
    true,
  )
}

///|
test "install_realm_pinned_builtin_constructor_bagged_prototype aligns cache and ctor prototype" {
  let env = Environment::new()
  let cache : Ref[Value?] = { val: None }
  let proto = pinned_install_proto("BaggedProto")
  let ctor = bagged_install_ctor(proto, "BaggedCtor")
  install_realm_pinned_builtin_constructor_bagged_prototype(
    env, cache, "BaggedCtor", ctor, proto,
  )

  match cache.val {
    Some(cached) => pinned_assert_same_object("realm cache", cached, proto)
    None => fail("realm proto cache must be populated")
  }
  let installed_ctor = match env.bindings.get("BaggedCtor") {
    Some(binding) => binding.value
    None => fail("constructor must be registered in env")
  }
  pinned_assert_same_object(
    "constructor .prototype",
    pinned_ctor_prototype(installed_ctor),
    proto,
  )
}

///|
test "install_realm_pinned_builtin_constructor_bagged_prototype_with_proto_constructor wires proto.constructor" {
  let env = Environment::new()
  let cache : Ref[Value?] = { val: None }
  let proto = pinned_install_proto("BaggedLinkedProto")
  let ctor = bagged_install_ctor(proto, "BaggedLinkedCtor")
  install_realm_pinned_builtin_constructor_bagged_prototype_with_proto_constructor(
    env, cache, "BaggedLinkedCtor", ctor, proto,
  )

  let installed_ctor = match env.bindings.get("BaggedLinkedCtor") {
    Some(binding) => binding.value
    None => fail("constructor must be registered in env")
  }
  pinned_assert_same_object(
    "proto.constructor",
    pinned_proto_constructor(proto),
    installed_ctor,
  )
}

///|
fn assign_install_ctor(_proto : Value, name : String) -> Value {
  let descs : Map[String, PropDescriptor] = {
    "prototype": {
      writable: false,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
      is_accessor: false,
    },
    "name": builtin_method_desc(),
  }
  make_object(
    { "name": String_(name) },
    Null,
    Some(NonConstructableCallable(name, fn(_args) { Undefined })),
    "Function",
    descs,
    true,
  )
}

///|
test "install_realm_pinned_builtin_constructor_assign_prototype aligns cache and ctor prototype" {
  let env = Environment::new()
  let cache : Ref[Value?] = { val: None }
  let proto = pinned_install_proto("AssignedProto")
  let ctor = assign_install_ctor(proto, "AssignedCtor")
  install_realm_pinned_builtin_constructor_assign_prototype(
    env, cache, "AssignedCtor", ctor, proto,
  )

  match cache.val {
    Some(cached) => pinned_assert_same_object("realm cache", cached, proto)
    None => fail("realm proto cache must be populated")
  }
  let installed_ctor = match env.bindings.get("AssignedCtor") {
    Some(binding) => binding.value
    None => fail("constructor must be registered in env")
  }
  pinned_assert_same_object(
    "constructor .prototype",
    pinned_ctor_prototype(installed_ctor),
    proto,
  )
}

///|
test "install_realm_pinned_builtin_constructor_assign_prototype_with_proto_constructor wires proto.constructor" {
  let env = Environment::new()
  let cache : Ref[Value?] = { val: None }
  let proto = pinned_install_proto("AssignedLinkedProto")
  let ctor = assign_install_ctor(proto, "AssignedLinkedCtor")
  install_realm_pinned_builtin_constructor_assign_prototype_with_proto_constructor(
    env, cache, "AssignedLinkedCtor", ctor, proto,
  )

  let installed_ctor = match env.bindings.get("AssignedLinkedCtor") {
    Some(binding) => binding.value
    None => fail("constructor must be registered in env")
  }
  pinned_assert_same_object(
    "proto.constructor",
    pinned_proto_constructor(proto),
    installed_ctor,
  )
}
