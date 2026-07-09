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
fn map_iterator_internal_slot_descriptor() -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}
