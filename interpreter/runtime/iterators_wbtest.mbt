///| Whitebox tests for iterator prototype cache behavior.

///|
fn shifted_realm_state() -> RealmState {
  let symbols = SymbolState::new()
  let _ = symbols.new_symbol(Some("offset"))
  RealmState::from_symbols(symbols)
}

///|
fn assert_symbol_prop(
  label : String,
  proto : Value,
  sym : SymbolData,
) -> Unit raise Error {
  match proto {
    Object(data) =>
      if !data.bag.symbol_properties.contains(sym.id) {
        fail(label + " missing expected symbol property")
      }
    _ => fail(label + " expected object prototype")
  }
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
test "runtime iterator prototype getters reuse cached objects" {
  let realm_state = RealmState()
  let iterator_proto = realm_state.get_iterator_proto()
  assert_same_object(
    "iterator prototype",
    iterator_proto,
    realm_state.get_iterator_proto(),
  )

  let array_proto = realm_state.get_array_iterator_proto()
  assert_same_object(
    "array iterator prototype",
    array_proto,
    realm_state.get_array_iterator_proto(),
  )
  assert_object_prototype(
    "array iterator prototype", array_proto, iterator_proto,
  )

  let string_proto = realm_state.get_string_iterator_proto()
  assert_same_object(
    "string iterator prototype",
    string_proto,
    realm_state.get_string_iterator_proto(),
  )
  assert_object_prototype(
    "string iterator prototype", string_proto, iterator_proto,
  )
}

///|
test "runtime iterator prototype caches are isolated by realm state" {
  let default_realm = RealmState()
  let shifted_realm = shifted_realm_state()
  let default_symbols = default_realm.well_known_symbols
  let shifted_symbols = shifted_realm.well_known_symbols
  if default_symbols.iterator.id == shifted_symbols.iterator.id {
    fail("expected shifted symbols to use different ids")
  }

  assert_distinct_object(
    "iterator prototype",
    default_realm.get_iterator_proto(),
    shifted_realm.get_iterator_proto(),
  )
  assert_distinct_object(
    "array iterator prototype",
    default_realm.get_array_iterator_proto(),
    shifted_realm.get_array_iterator_proto(),
  )
  assert_distinct_object(
    "string iterator prototype",
    default_realm.get_string_iterator_proto(),
    shifted_realm.get_string_iterator_proto(),
  )
}

///|
test "iterator prototypes use their realm well-known symbol ids" {
  let default_realm = RealmState()
  let shifted_realm = shifted_realm_state()
  let default_symbols = default_realm.well_known_symbols
  let shifted_symbols = shifted_realm.well_known_symbols
  if default_symbols.iterator.id == shifted_symbols.iterator.id {
    fail("expected shifted symbols to use different ids")
  }

  let _ = default_realm.get_iterator_proto()
  let _ = default_realm.get_array_iterator_proto()
  let _ = default_realm.get_string_iterator_proto()

  assert_symbol_prop(
    "iterator prototype",
    shifted_realm.get_iterator_proto(),
    shifted_symbols.iterator,
  )
  let array_proto = shifted_realm.get_array_iterator_proto()
  assert_symbol_prop(
    "array iterator prototype",
    array_proto,
    shifted_symbols.iterator,
  )
  assert_symbol_prop(
    "array iterator prototype",
    array_proto,
    shifted_symbols.to_string_tag,
  )
  let string_proto = shifted_realm.get_string_iterator_proto()
  assert_symbol_prop(
    "string iterator prototype",
    string_proto,
    shifted_symbols.iterator,
  )
  assert_symbol_prop(
    "string iterator prototype",
    string_proto,
    shifted_symbols.to_string_tag,
  )
}
