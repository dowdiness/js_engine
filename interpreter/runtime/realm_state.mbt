///|
/// Lazy iterator prototype caches owned by a RealmState.
pub(all) struct RuntimeIteratorPrototypeCaches {
  iterator_proto : Ref[Value?]
  array_iterator_proto : Ref[Value?]
  string_iterator_proto : Ref[Value?]
  map_iterator_proto : Ref[Value?]
  set_iterator_proto : Ref[Value?]
  regexp_string_iterator_proto : Ref[Value?]
  async_iterator_proto : Ref[Value?]
  async_from_sync_iterator_proto : Ref[Value?]
}

///|
fn RuntimeIteratorPrototypeCaches::RuntimeIteratorPrototypeCaches() -> RuntimeIteratorPrototypeCaches {
  {
    iterator_proto: { val: None },
    array_iterator_proto: { val: None },
    string_iterator_proto: { val: None },
    map_iterator_proto: { val: None },
    set_iterator_proto: { val: None },
    regexp_string_iterator_proto: { val: None },
    async_iterator_proto: { val: None },
    async_from_sync_iterator_proto: { val: None },
  }
}

///|
/// Per-realm engine state owned by an Interpreter.
///
/// Realm-scoped mutable engine state belongs here or in an explicit nested
/// owner record, not in module-level caches. This includes intrinsic/prototype
/// caches, symbol registries, backing stores, and side tables whose lifetime is
/// the lifetime of a realm.
priv enum ExecutionControlCarrierCache {
  UnresolvedExecutionControlCarrier
  ResolvedExecutionControlCarrier(Binding?)
}

///|
pub(all) struct RealmState {
  symbols : SymbolState
  well_known_symbols : WellKnownSymbols
  runtime_iterator_prototypes : RuntimeIteratorPrototypeCaches
  // Single Ref holds all active cross-realm prototype/registry overrides.
  // None means no cross-realm context is active; Some(protos) means at least
  // one override is set. Collapsing the individual values into one means the
  // "any active?" check is `active_overrides.val is Some(_)` — one Ref read —
  // with no separate Bool cache that could become stale.
  active_overrides : Ref[FunctionRealmProtos?]
  // Source identity active while evaluating or invoking attributable code.
  // Function factories copy this into engine-private function metadata.
  active_source_identity : Ref[String?]
  // Shared, engine-private lookup table for this realm's intrinsic constructor
  // prototypes. Function metadata retains this object so GetFunctionRealm-style
  // fallback can recover `%Name.prototype%` without another realm environment.
  constructor_prototype_registry : Value
  // Exact native Proxy constructor registered by the runtime factory. Managed
  // execution compares identity against this private per-realm capability.
  priv canonical_proxy_constructor : Ref[Value?]
  // Exact Array.prototype.forEach function captured before user mutation.
  // Managed execution compares identity against this private per-realm
  // capability rather than the mutable property currently exposed to JS.
  priv canonical_array_for_each : Ref[Value?]
  // Resolve the private execution-control carrier once on the unbounded hot
  // path. Scoped bounded execution replaces and restores this cache together
  // with the reserved environment binding.
  priv execution_control_carrier_cache : Ref[ExecutionControlCarrierCache]
  // Detailed operations enable this only while atomically observing a failure.
  // The error object distinguishes unhandled propagation from a later throw.
  observing_source_failure : Ref[Bool]
  observed_source_failure : Ref[Error?]
  observed_source_identity : Ref[String?]
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
  let constructor_prototype_registry = Object({
    bag: PropertyBag(),
    prototype: Null,
    callable: None,
    class_name: "ConstructorPrototypeRegistry",
    extensible: false,
    arraybuffer_state: None,
  })
  {
    symbols,
    well_known_symbols: symbols.well_known_symbols(),
    runtime_iterator_prototypes: RuntimeIteratorPrototypeCaches(),
    active_overrides: { val: None },
    active_source_identity: { val: None },
    constructor_prototype_registry,
    canonical_proxy_constructor: { val: None },
    canonical_array_for_each: { val: None },
    execution_control_carrier_cache: { val: UnresolvedExecutionControlCarrier },
    observing_source_failure: { val: false },
    observed_source_failure: { val: None },
    observed_source_identity: { val: None },
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
    weakmap_storage: Map([]),
    weakmap_id_table: [],
    weakset_id_counter: { val: 0 },
    weakset_storage: Map([]),
    weakset_id_table: [],
  }
}

///|
/// Record a builtin constructor's intrinsic prototype in this realm's private
/// table. The table is shared by functions created before and after setup.
pub fn RealmState::register_constructor_prototype(
  self : RealmState,
  name : String,
  constructor_value : Value,
) -> Unit {
  match constructor_value {
    Object(constructor_data) if constructor_data.callable is Some(_) =>
      match constructor_data.bag.properties.get("prototype") {
        Some(prototype) if is_object_value(prototype) =>
          match self.constructor_prototype_registry {
            Object(registry) => registry.bag.properties[name] = prototype
            _ => ()
          }
        _ => ()
      }
    _ => ()
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

///|
pub fn RealmState::get_async_iterator_proto(self : RealmState) -> Value {
  match self.runtime_iterator_prototypes.async_iterator_proto.val {
    Some(proto) => proto
    None => {
      let proto = make_async_iterator_proto_value(self.well_known_symbols, self)
      self.runtime_iterator_prototypes.async_iterator_proto.val = Some(proto)
      proto
    }
  }
}

///|
pub fn RealmState::get_async_from_sync_iterator_proto(
  self : RealmState,
) -> Value {
  match self.runtime_iterator_prototypes.async_from_sync_iterator_proto.val {
    Some(proto) => proto
    None => {
      let proto = make_async_from_sync_iterator_proto_value(
        self.well_known_symbols,
        self,
      )
      self.runtime_iterator_prototypes.async_from_sync_iterator_proto.val = Some(
        proto,
      )
      proto
    }
  }
}
