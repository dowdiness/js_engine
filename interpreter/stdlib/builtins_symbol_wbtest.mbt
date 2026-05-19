///| Whitebox tests for Symbol builtins setup.

///|
test "setup_builtins reserves well-known symbols in provided SymbolState" {
  let env = @runtime.Environment::new()
  let output : Array[String] = []
  let symbols = @runtime.SymbolState::new()
  setup_builtins(env, output, symbols)
  let iterator_sym = @runtime.get_iterator_symbol()
  match symbols.get_symbol_by_id(iterator_sym.id) {
    Some(found) =>
      if found.description != Some("Symbol.iterator") {
        fail("expected Symbol.iterator registered in provided SymbolState")
      }
    None => fail("expected Symbol.iterator in provided SymbolState")
  }
  let user_sym = symbols.new_symbol(Some("user"))
  if user_sym.id <= symbols.well_known_symbols().async_iterator.id {
    fail("expected user symbols to allocate after well-known symbols")
  }
}
