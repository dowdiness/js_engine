///| Whitebox tests for Symbol builtins setup.

///|
test "setup_builtins reserves well-known symbols in provided SymbolState" {
  let env = @runtime.Environment::new()
  let output : Array[String] = []
  let symbols = @runtime.SymbolState::new()
  let realm_state = setup_builtins(env, output, symbols)
  let well_known_symbols = symbols.well_known_symbols()
  if realm_state.well_known_symbols.iterator.id !=
    well_known_symbols.iterator.id {
    fail("expected setup_builtins to return the created RealmState")
  }
  let iterator_sym = well_known_symbols.iterator
  match symbols.get_symbol_by_id(iterator_sym.id) {
    Some(found) =>
      if found.description != Some("Symbol.iterator") {
        fail("expected Symbol.iterator registered in provided SymbolState")
      }
    None => fail("expected Symbol.iterator in provided SymbolState")
  }
  let user_sym = symbols.new_symbol(Some("user"))
  if user_sym.id <= well_known_symbols.async_iterator.id {
    fail("expected user symbols to allocate after well-known symbols")
  }
}

///|
test "standalone setup_builtins_with_realm_state activates provided realm" {
  let env = @runtime.Environment::new()
  let output : Array[String] = []
  let realm_state = @runtime.RealmState()
  setup_builtins_with_realm_state(env, output, realm_state)
  let object_proto = realm_state.get_obj_proto()
  let object_ctor = env.get("Object") catch {
    err => fail("expected Object constructor: " + err.to_string())
  }
  let from_entries = match object_ctor {
    Object(data) =>
      match data.bag.properties.get("fromEntries") {
        Some(func) => func
        None => fail("expected Object.fromEntries")
      }
    _ => fail("expected Object constructor object")
  }
  let result = @runtime.call_callable_direct(from_entries, Undefined, [
    @runtime.make_array([]),
  ]) catch {
    err => fail("Object.fromEntries call failed: " + err.to_string())
  }
  match result {
    Object(data) =>
      if !@runtime.strict_equal(data.prototype, object_proto) {
        fail("expected Object.fromEntries result to use standalone realm")
      }
    _ => fail("expected Object.fromEntries result object")
  }
}
