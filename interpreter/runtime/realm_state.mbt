///|
/// Per-realm engine state owned by an Interpreter.
///
/// Stage 1 seeds the ownership container and threading point only. Ambient
/// module-level intrinsic caches, backing stores, and side tables remain where
/// they are until their individual migrations are covered by focused tests.
pub(all) struct RealmState {
  symbols : SymbolState
  well_known_symbols : WellKnownSymbols
}

///|
#alias(new)
pub fn RealmState::RealmState() -> RealmState {
  let symbols = SymbolState::new()
  { symbols, well_known_symbols: symbols.well_known_symbols() }
}
