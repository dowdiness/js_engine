///|
/// Shared Map/Set built-in helpers: method dispatch, key canonicalization,
/// MapData entry helpers, and setup orchestration.

///|
fn lookup_prototype_method(proto : Value, prop : String) -> Value? {
  let mut current = proto
  while true {
    match current {
      Object(proto_data) =>
        match proto_data.bag.properties.get(prop) {
          Some(value) => return Some(value)
          None => current = proto_data.prototype
        }
      _ => return None
    }
  }
  None
}

///|
fn get_map_lookup_prototype(
  data : MapData,
  realm_state : @runtime.RealmState,
) -> Value {
  data.prototype.unwrap_or_else(fn() { realm_state.get_map_proto() })
}

///|
fn get_set_lookup_prototype(
  data : SetData,
  realm_state : @runtime.RealmState,
) -> Value {
  data.prototype.unwrap_or_else(fn() { realm_state.get_set_proto() })
}

///|
fn canonicalize_keyed_collection_key(key : Value) -> Value {
  match key {
    Number(n) if n == 0.0 => Number(0.0)
    _ => key
  }
}

///|
fn MapData::append_entry(self : MapData, key : Value, value : Value) -> Unit {
  self.entries.push((key, value))
  self.entry_ids.push(self.next_entry_id)
  self.next_entry_id += 1
}

///|
fn MapData::remove_entry_at(self : MapData, index : Int) -> Unit {
  let _ = self.entries.remove(index)
  let _ = self.entry_ids.remove(index)
}

///|
fn MapData::clear_entries(self : MapData) -> Unit {
  self.entries.clear()
  self.entry_ids.clear()
}

///|
/// Search an array while charging each logical probe before its predicate.
/// Built-in keyed-collection scans use this for SameValueZero comparisons,
/// tombstone inspection, and stable Map record-id lookup.
fn[T] observed_array_search(
  interp : @runtime.Interpreter,
  values : Array[T],
  predicate : (T) -> Bool,
) -> Int? raise Error {
  let mut index = 0
  while index < values.length() {
    interp.observe_execution_step()
    if predicate(values[index]) {
      return Some(index)
    }
    index += 1
  }
  None
}

///|
/// Charge every entry before a bulk clear mutates the backing array.
fn[T] observe_array_entries(
  interp : @runtime.Interpreter,
  values : Array[T],
) -> Unit raise Error {
  for _ in values {
    interp.observe_execution_step()
  }
}

///|
/// Search live Set slots, charging before tombstone inspection and
/// SameValueZero comparison.
fn observed_set_value_search(
  interp : @runtime.Interpreter,
  data : SetData,
  value : Value,
) -> Int? raise Error {
  let mut index = 0
  while index < data.values.length() {
    interp.observe_execution_step()
    let is_tombstoned = match data.tombstones {
      None => false
      Some(ts) => ts.contains(index)
    }
    if !is_tombstoned && same_value_zero(data.values[index], value) {
      return Some(index)
    }
    index += 1
  }
  None
}

///|
/// Find the next live Set slot for an iterator, charging before each
/// tombstone check and before advancing past a tombstone.
fn observed_set_live_index_from(
  interp : @runtime.Interpreter,
  data : SetData,
  start : Int,
) -> Int? raise Error {
  let mut index = start
  while index < data.values.length() {
    interp.observe_execution_step()
    let is_tombstoned = match data.tombstones {
      None => false
      Some(ts) => ts.contains(index)
    }
    if !is_tombstoned {
      return Some(index)
    }
    index += 1
  }
  None
}

///|
/// Get Map.prototype methods for a Map instance
pub fn get_map_method(
  data : MapData,
  prop : String,
  realm_state : @runtime.RealmState,
) -> Value {
  match
    lookup_prototype_method(get_map_lookup_prototype(data, realm_state), prop) {
    Some(m) => m
    None => Undefined
  }
}

///|
/// Get Set.prototype methods for a Set instance
pub fn get_set_method(
  data : SetData,
  prop : String,
  realm_state : @runtime.RealmState,
) -> Value {
  match
    lookup_prototype_method(get_set_lookup_prototype(data, realm_state), prop) {
    Some(m) => m
    None => Undefined
  }
}

///|
/// Setup Map and Set constructors and prototypes
pub fn setup_map_set_builtins(
  env : Environment,
  realm_state : @runtime.RealmState,
) -> Unit {
  setup_map_builtins(env, realm_state)
  setup_set_builtins(env, realm_state)
}

///|
priv struct KeyedCollectionIteratorSlots {
  next_index : Int
  target : Int
  kind : Int
}

///|
/// Engine-private negative symbol IDs for Map Iterator internal slots.
/// These IDs are not registered in SymbolState, so JavaScript cannot obtain
/// or enumerate keys for them via string or symbol property access.
let map_iterator_slots : KeyedCollectionIteratorSlots = {
  next_index: -130,
  target: -131,
  kind: -132,
}

///|
/// Engine-private negative symbol IDs for Set Iterator internal slots.
let set_iterator_slots : KeyedCollectionIteratorSlots = {
  next_index: -133,
  target: -134,
  kind: -135,
}

///|
fn keyed_collection_iterator_internal_slot_descriptor() -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
fn keyed_collection_iterator_type_error(
  iterator_name : String,
) -> Value raise Error {
  raise @errors.TypeError(
    message="\{iterator_name}.prototype.next requires that |this| be a \{iterator_name}",
  )
}

///|
/// Read [[NextIndex]], [[IteratedCollection]], and [[IterationKind]] slots.
fn read_keyed_collection_iterator_state(
  data : ObjectData,
  slots : KeyedCollectionIteratorSlots,
) -> (Int, Value, Int)? {
  match
    (
      @runtime.get_keyed_collection_iterator_next_index(data, slots.next_index),
      @runtime.get_keyed_collection_iterator_target(data, slots.target),
      @runtime.get_keyed_collection_iterator_kind(data, slots.kind),
    ) {
    (Some(Number(index)), Some(target), Some(Number(kind))) =>
      Some((index.to_int(), target, kind.to_int()))
    _ => None
  }
}

///|
/// Build a Map/Set iterator instance shell with hidden symbol slots for
/// [[NextIndex]], [[IteratedCollection]], and [[IterationKind]].
fn make_keyed_collection_iterator(
  iterator_proto : Value,
  iterator_name : String,
  slots : KeyedCollectionIteratorSlots,
  target : Value,
  kind : Int,
  before_create? : () -> Unit = () => (),
) -> Value {
  before_create()
  let iter_sym_props : Map[Int, Value] = Map([])
  iter_sym_props[slots.next_index] = Value::Number(0.0)
  iter_sym_props[slots.target] = target
  iter_sym_props[slots.kind] = Value::Number(kind.to_double())
  let iter_sym_descs : Map[Int, PropDescriptor] = Map([])
  let slot_desc = keyed_collection_iterator_internal_slot_descriptor()
  iter_sym_descs[slots.next_index] = slot_desc
  iter_sym_descs[slots.target] = slot_desc
  iter_sym_descs[slots.kind] = slot_desc
  Value::Object({
    bag: {
      properties: Map([]),
      symbol_properties: iter_sym_props,
      descriptors: Map([]),
      symbol_descriptors: iter_sym_descs,
      internal_slots: Map([]),
      host_slots: Map([]),
    },
    prototype: iterator_proto,
    callable: None,
    class_name: iterator_name,
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
/// Build a realm-owned %MapIteratorPrototype% / %SetIteratorPrototype% shell.
fn build_keyed_collection_iterator_proto(
  realm_state : @runtime.RealmState,
  iterator_name : String,
  next_handler : (@runtime.Interpreter, Value) -> Value raise Error,
) -> Value {
  let well_known_symbols = realm_state.well_known_symbols
  let tostringtag_sym = well_known_symbols.to_string_tag
  let proto_sym_props : Map[Int, Value] = Map([])
  proto_sym_props[tostringtag_sym.id] = Value::String_(iterator_name)
  let proto_props : Map[String, Value] = Map([])
  let proto_sym_descs : Map[Int, PropDescriptor] = Map([])
  proto_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  proto_props["next"] = @runtime.make_interp_method_func(
    name="next",
    length=0,
    realm_state=Some(realm_state),
    fn(interp, this_val, _args) raise { next_handler(interp, this_val) },
  )
  Value::Object({
    bag: {
      properties: proto_props,
      symbol_properties: proto_sym_props,
      descriptors: {
        "next": {
          writable: true,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
          is_accessor: false,
        },
      },
      symbol_descriptors: proto_sym_descs,
      internal_slots: Map([]),
      host_slots: Map([]),
    },
    prototype: realm_state.get_iterator_proto(),
    callable: None,
    class_name: iterator_name,
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
fn get_or_create_keyed_collection_iterator_proto(
  cache : Ref[Value?],
  realm_state : @runtime.RealmState,
  iterator_name : String,
  next_handler : (@runtime.Interpreter, Value) -> Value raise Error,
) -> Value {
  match cache.val {
    Some(proto) => proto
    None => {
      let proto = build_keyed_collection_iterator_proto(
        realm_state, iterator_name, next_handler,
      )
      cache.val = Some(proto)
      proto
    }
  }
}
