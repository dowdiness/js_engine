///| Whitebox tests for stdlib iterator prototype cache ownership.

///|
fn new_realm_state() -> @runtime.RealmState {
  @runtime.RealmState::from_symbols(@runtime.SymbolState::new())
}

///|
fn shifted_realm_state() -> @runtime.RealmState {
  let symbols = @runtime.SymbolState::new()
  let _ = symbols.new_symbol(Some("offset"))
  @runtime.RealmState::from_symbols(symbols)
}

///|
fn assert_same_object(
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
fn assert_distinct_object(
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
test "map and set method lookup backfills direct data from active realm state" {
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
  match default_realm.map_prototype.val {
    Some(proto) => {
      assert_same_object("backfilled map prototype", map_data.prototype, proto)
      let derived_map_proto = Value::Object({
        bag: @runtime.PropertyBag(),
        prototype: proto,
        callable: None,
        class_name: "DerivedMapPrototype",
        extensible: true,
      })
      let derived_map_data = @runtime.MapData([], prototype=derived_map_proto)
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
  match default_realm.set_prototype.val {
    Some(proto) => {
      assert_same_object("backfilled set prototype", set_data.prototype, proto)
      let derived_set_proto = Value::Object({
        bag: @runtime.PropertyBag(),
        prototype: proto,
        callable: None,
        class_name: "DerivedSetPrototype",
        extensible: true,
      })
      let derived_set_data = @runtime.SetData([], prototype=derived_set_proto)
      match get_set_method(derived_set_data, "values", default_realm) {
        Undefined => fail("expected inherited Set.prototype.values method")
        _ => ()
      }
    }
    None => fail("expected default realm Set.prototype")
  }
}

///|
test "regexp factories ignore module global prototype fallback without realm prototype" {
  let previous_regexp_prototype = regexp_prototype_ref.val
  let sentinel = Value::Object({
    bag: @runtime.PropertyBag(),
    prototype: Value::Null,
    callable: None,
    class_name: "RegExp.prototype sentinel",
    extensible: true,
  })
  regexp_prototype_ref.val = Some(sentinel)
  let realm = new_realm_state()

  try {
    assert_null_prototype(
      "realm regexp without prototype",
      make_regexp_object_with_realm_state("a", "", realm),
    )
    assert_null_prototype(
      "legacy regexp without realm",
      make_regexp_object("a", ""),
    )
    regexp_prototype_ref.val = previous_regexp_prototype
  } catch {
    e => {
      regexp_prototype_ref.val = previous_regexp_prototype
      raise e
    }
  }
}
