///| Whitebox tests for stdlib iterator prototype cache ownership.

///|
fn assert_object_prototype(
  label : String,
  value : Value,
  expected : Value,
) -> Unit raise Error {
  match value {
    Object(data) =>
      assert_same_object(label + " prototype", data.prototype, expected)
    _ => fail(label + " expected object value")
  }
}

///|
fn assert_null_prototype(label : String, value : Value) -> Unit raise Error {
  match value {
    Object(data) =>
      match data.prototype {
        Null => ()
        _ => fail(label + " expected null prototype")
      }
    _ => fail(label + " expected object value")
  }
}

///|
test "stdlib iterator prototype caches are isolated by realm state" {
  let default_realm = new_realm_state()
  let shifted_realm = shifted_realm_state()
  let default_symbols = default_realm.well_known_symbols
  let shifted_symbols = shifted_realm.well_known_symbols
  if default_symbols.iterator.id == shifted_symbols.iterator.id {
    fail("expected shifted symbols to use different ids")
  }

  let default_iterator_proto = default_realm.get_iterator_proto()
  let shifted_iterator_proto = shifted_realm.get_iterator_proto()
  let default_map_proto = get_map_iterator_proto(default_realm)
  let shifted_map_proto = get_map_iterator_proto(shifted_realm)
  let default_set_proto = get_set_iterator_proto(default_realm)
  let shifted_set_proto = get_set_iterator_proto(shifted_realm)
  let default_regexp_proto = get_regexp_string_iterator_proto(default_realm)
  let shifted_regexp_proto = get_regexp_string_iterator_proto(shifted_realm)

  assert_same_object(
    "map iterator prototype",
    default_map_proto,
    get_map_iterator_proto(default_realm),
  )
  assert_same_object(
    "set iterator prototype",
    default_set_proto,
    get_set_iterator_proto(default_realm),
  )
  assert_same_object(
    "regexp string iterator prototype",
    default_regexp_proto,
    get_regexp_string_iterator_proto(default_realm),
  )

  assert_distinct_object(
    "map iterator prototype", default_map_proto, shifted_map_proto,
  )
  assert_distinct_object(
    "set iterator prototype", default_set_proto, shifted_set_proto,
  )
  assert_distinct_object(
    "regexp string iterator prototype", default_regexp_proto, shifted_regexp_proto,
  )

  assert_object_prototype(
    "default map iterator prototype", default_map_proto, default_iterator_proto,
  )
  assert_object_prototype(
    "shifted map iterator prototype", shifted_map_proto, shifted_iterator_proto,
  )
  assert_object_prototype(
    "default set iterator prototype", default_set_proto, default_iterator_proto,
  )
  assert_object_prototype(
    "shifted set iterator prototype", shifted_set_proto, shifted_iterator_proto,
  )
  assert_object_prototype(
    "default regexp string iterator prototype", default_regexp_proto, default_iterator_proto,
  )
  assert_object_prototype(
    "shifted regexp string iterator prototype", shifted_regexp_proto, shifted_iterator_proto,
  )
}

///|
test "map and set method lookup uses active realm state without rehoming direct data" {
  let default_realm = new_realm_state()
  let shifted_realm = shifted_realm_state()
  setup_map_set_builtins(@runtime.Environment::new(), default_realm)
  setup_map_set_builtins(@runtime.Environment::new(), shifted_realm)

  let map_data = @runtime.MapData([])
  let map_method = get_map_method(map_data, "entries", default_realm)
  match map_method {
    Undefined => fail("expected Map.prototype.entries method")
    _ => ()
  }
  match map_data.prototype {
    None => ()
    _ => fail("direct MapData lookup should not mutate prototype")
  }
  match get_map_method(map_data, "entries", shifted_realm) {
    Undefined => fail("expected shifted Map.prototype.entries method")
    _ => ()
  }
  match map_data.prototype {
    None => ()
    _ => fail("shifted direct MapData lookup should not mutate prototype")
  }
  match default_realm.map_prototype.val {
    Some(proto) => {
      let derived_map_proto = Value::Object({
        bag: @runtime.PropertyBag(),
        prototype: proto,
        callable: None,
        class_name: "DerivedMapPrototype",
        extensible: true,
        arraybuffer_state: None,
      })
      let derived_map_data = @runtime.MapData(
        [],
        prototype=Some(derived_map_proto),
      )
      match get_map_method(derived_map_data, "entries", default_realm) {
        Undefined => fail("expected inherited Map.prototype.entries method")
        _ => ()
      }
    }
    None => fail("expected default realm Map.prototype")
  }

  let set_data = @runtime.SetData([])
  let set_method = get_set_method(set_data, "values", default_realm)
  match set_method {
    Undefined => fail("expected Set.prototype.values method")
    _ => ()
  }
  match set_data.prototype {
    None => ()
    _ => fail("direct SetData lookup should not mutate prototype")
  }
  match get_set_method(set_data, "values", shifted_realm) {
    Undefined => fail("expected shifted Set.prototype.values method")
    _ => ()
  }
  match set_data.prototype {
    None => ()
    _ => fail("shifted direct SetData lookup should not mutate prototype")
  }
  match default_realm.set_prototype.val {
    Some(proto) => {
      let derived_set_proto = Value::Object({
        bag: @runtime.PropertyBag(),
        prototype: proto,
        callable: None,
        class_name: "DerivedSetPrototype",
        extensible: true,
        arraybuffer_state: None,
      })
      let derived_set_data = @runtime.SetData(
        [],
        prototype=Some(derived_set_proto),
      )
      match get_set_method(derived_set_data, "values", default_realm) {
        Undefined => fail("expected inherited Set.prototype.values method")
        _ => ()
      }
    }
    None => fail("expected default realm Set.prototype")
  }
}

///|
test "regexp factories return null prototype without realm prototype" {
  let realm = new_realm_state()
  assert_null_prototype(
    "realm regexp without prototype",
    make_regexp_object_with_realm_state("a", "", realm),
  )
  assert_null_prototype(
    "legacy regexp without realm",
    make_regexp_object("a", ""),
  )
}
