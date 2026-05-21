///| Whitebox tests for iterator prototype cache behavior.

///|
fn shifted_well_known_symbols() -> WellKnownSymbols {
  let symbols = SymbolState::new()
  let _ = symbols.new_symbol(Some("offset"))
  symbols.well_known_symbols()
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
test "iterator prototypes are cached per well-known symbol ids" {
  let default_symbols = SymbolState::new().well_known_symbols()
  let shifted_symbols = shifted_well_known_symbols()
  if default_symbols.iterator.id == shifted_symbols.iterator.id {
    fail("expected shifted symbols to use different ids")
  }

  let _ = get_iterator_proto(default_symbols)
  let _ = get_array_iterator_proto(default_symbols)
  let _ = get_string_iterator_proto(default_symbols)

  assert_symbol_prop(
    "iterator prototype",
    get_iterator_proto(shifted_symbols),
    shifted_symbols.iterator,
  )
  let array_proto = get_array_iterator_proto(shifted_symbols)
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
  let string_proto = get_string_iterator_proto(shifted_symbols)
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
