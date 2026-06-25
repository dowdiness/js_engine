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
/// Realm-scoped mutable engine state belongs here or in an explicit nested
/// owner record, not in module-level caches. This includes intrinsic/prototype
/// caches, symbol registries, backing stores, and side tables whose lifetime is
/// the lifetime of a realm.
pub(all) struct RealmState {
  symbols : SymbolState
  well_known_symbols : WellKnownSymbols
  runtime_iterator_prototypes : RuntimeIteratorPrototypeCaches
  // Single Ref holds all 10 active cross-realm prototype overrides together.
  // None means no cross-realm context is active; Some(protos) means at least
  // one override is set. Collapsing 10 individual Refs into one means the
  // "any active?" check is `active_overrides.val is Some(_)` — one Ref read —
  // with no separate Bool cache that could become stale.
  active_overrides : Ref[FunctionRealmProtos?]
  object_prototype : Ref[Value?]
  function_prototype : Ref[Value?]
  string_prototype : Ref[Value?]
  number_prototype : Ref[Value?]
  boolean_prototype : Ref[Value?]
  symbol_prototype : Ref[Value?]
  array_prototype : Ref[Value?]
  map_prototype : Ref[Value?]
  set_prototype : Ref[Value?]
  regexp_prototype : Ref[Value?]
  promise_prototype : Ref[Value?]
  weakmap_prototype : Ref[Value?]
  weakset_prototype : Ref[Value?]
  arraybuffer_state : ArrayBufferState
  arraybuffer_id_counter : Ref[Int]
  arraybuffer_store : Map[Int, Array[Int]]
  detached_buffers : Map[Int, Bool]
  weakmap_id_counter : Ref[Int]
  weakmap_storage : Map[Int, Array[(Value, Value)]]
  weakmap_id_table : Array[(ObjectData, Int)]
  weakset_id_counter : Ref[Int]
  weakset_storage : Map[Int, Array[Value]]
  weakset_id_table : Array[(ObjectData, Int)]
}

///|
#alias(new)
pub fn RealmState::RealmState() -> RealmState {
  let symbols = SymbolState::new()
  RealmState::from_symbols(symbols)
}

///|
pub fn RealmState::from_symbols(symbols : SymbolState) -> RealmState {
  let arraybuffer_state = ArrayBufferState()
  {
    symbols,
    well_known_symbols: symbols.well_known_symbols(),
    runtime_iterator_prototypes: RuntimeIteratorPrototypeCaches(),
    active_overrides: { val: None },
    object_prototype: { val: None },
    function_prototype: { val: None },
    string_prototype: { val: None },
    number_prototype: { val: None },
    boolean_prototype: { val: None },
    symbol_prototype: { val: None },
    array_prototype: { val: None },
    map_prototype: { val: None },
    set_prototype: { val: None },
    regexp_prototype: { val: None },
    promise_prototype: { val: None },
    weakmap_prototype: { val: None },
    weakset_prototype: { val: None },
    arraybuffer_state,
    arraybuffer_id_counter: arraybuffer_state.id_counter,
    arraybuffer_store: arraybuffer_state.store,
    detached_buffers: arraybuffer_state.detached,
    weakmap_id_counter: { val: 0 },
    weakmap_storage: {},
    weakmap_id_table: [],
    weakset_id_counter: { val: 0 },
    weakset_storage: {},
    weakset_id_table: [],
  }
}

///|
pub fn RealmState::get_obj_proto(self : RealmState) -> Value {
  match self.object_prototype.val {
    Some(proto) => proto
    None => Null
  }
}

///|
pub fn RealmState::get_func_proto(self : RealmState) -> Value {
  match self.function_prototype.val {
    Some(proto) => proto
    None => Null
  }
}

///|
pub fn RealmState::get_string_proto(self : RealmState) -> Value {
  match self.string_prototype.val {
    Some(proto) => proto
    None => Null
  }
}

///|
pub fn RealmState::get_number_proto(self : RealmState) -> Value {
  match self.number_prototype.val {
    Some(proto) => proto
    None => Null
  }
}

///|
pub fn RealmState::get_boolean_proto(self : RealmState) -> Value {
  match self.boolean_prototype.val {
    Some(proto) => proto
    None => Null
  }
}

///|
pub fn RealmState::get_symbol_proto(self : RealmState) -> Value {
  match self.symbol_prototype.val {
    Some(proto) => proto
    None => Null
  }
}

///|
pub fn RealmState::get_array_proto(self : RealmState) -> Value {
  match self.array_prototype.val {
    Some(proto) => proto
    None => Null
  }
}

///|
pub fn RealmState::get_map_proto(self : RealmState) -> Value {
  match self.map_prototype.val {
    Some(proto) => proto
    None => Null
  }
}

///|
pub fn RealmState::get_set_proto(self : RealmState) -> Value {
  match self.set_prototype.val {
    Some(proto) => proto
    None => Null
  }
}

///|
pub fn RealmState::get_promise_proto(self : RealmState) -> Value {
  match self.promise_prototype.val {
    Some(proto) => proto
    None => Null
  }
}

///|
pub fn RealmState::get_weakmap_proto(self : RealmState) -> Value {
  match self.weakmap_prototype.val {
    Some(proto) => proto
    None => Null
  }
}

///|
pub fn RealmState::get_weakset_proto(self : RealmState) -> Value {
  match self.weakset_prototype.val {
    Some(proto) => proto
    None => Null
  }
}
