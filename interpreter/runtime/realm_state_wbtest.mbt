///| Whitebox tests for the Stage 1 RealmState ownership seed.

///|
test "realm_state owns symbol state" {
  let realm_state = RealmState()
  let sym = realm_state.symbols.new_symbol(Some("stage1"))
  match realm_state.symbols.get_symbol_by_id(sym.id) {
    Some(found) =>
      if found.description != Some("stage1") {
        fail("expected symbol visible through RealmState symbols")
      }
    None => fail("expected RealmState to own symbol table")
  }
}

///|
test "realm_state symbols are isolated between realm states" {
  let realm_a = RealmState()
  let realm_b = RealmState()
  let sym_a = realm_a.symbols.new_symbol(Some("a"))
  match realm_b.symbols.get_symbol_by_id(sym_a.id) {
    None => ()
    Some(_) => fail("expected fresh RealmState to own a distinct symbol table")
  }
}
