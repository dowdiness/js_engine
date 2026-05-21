///|
/// Lazy iterator prototype caches owned by a RealmState.
pub(all) struct RuntimeIteratorPrototypeCaches {
  iterator_proto : Ref[Value?]
  array_iterator_proto : Ref[Value?]
  string_iterator_proto : Ref[Value?]
  map_iterator_proto : Ref[Value?]
  set_iterator_proto : Ref[Value?]
  regexp_string_iterator_proto : Ref[Value?]
}

///|
pub fn RuntimeIteratorPrototypeCaches::RuntimeIteratorPrototypeCaches() -> RuntimeIteratorPrototypeCaches {
  {
    iterator_proto: { val: None },
    array_iterator_proto: { val: None },
    string_iterator_proto: { val: None },
    map_iterator_proto: { val: None },
    set_iterator_proto: { val: None },
    regexp_string_iterator_proto: { val: None },
  }
}

///|
/// Per-realm engine state owned by an Interpreter.
///
/// Some ambient module-level intrinsic caches, backing stores, and side tables
/// remain where they are until their individual migrations are covered by
/// focused tests.
pub(all) struct RealmState {
  symbols : SymbolState
  well_known_symbols : WellKnownSymbols
  runtime_iterator_prototypes : RuntimeIteratorPrototypeCaches
  map_prototype : Ref[Value?]
  set_prototype : Ref[Value?]
  regexp_prototype : Ref[Value?]
}

///|
#alias(new)
pub fn RealmState::RealmState() -> RealmState {
  let symbols = SymbolState::new()
  RealmState::from_symbols(symbols)
}

///|
pub fn RealmState::from_symbols(symbols : SymbolState) -> RealmState {
  {
    symbols,
    well_known_symbols: symbols.well_known_symbols(),
    runtime_iterator_prototypes: RuntimeIteratorPrototypeCaches(),
    map_prototype: { val: None },
    set_prototype: { val: None },
    regexp_prototype: { val: None },
  }
}
