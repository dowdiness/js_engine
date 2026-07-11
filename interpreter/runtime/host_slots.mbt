///| Embedder-owned host slots (#518). Separate from engine `internal_slots`.

///|
let host_slot_id_counter : Ref[Int] = { val: 0 }

///|
/// Embedder-owned slot identity. Construct only via `HostSlotKey::reserve`.
pub(all) struct HostSlotKey {
  priv id : Int
} derive(Eq, Hash, Debug)

///|
/// Allocate a unique key within this loaded runtime package instance.
/// Aborts if the allocator is exhausted — never wraps.
pub fn HostSlotKey::reserve() -> HostSlotKey {
  let id = host_slot_id_counter.val
  // Last valid id is 0x7FFFFFFE; refuse to wrap into negatives / reuse.
  guard id < 0x7FFFFFFF else { abort("HostSlotKey::reserve: exhausted") }
  host_slot_id_counter.val = id + 1
  { id, }
}

///|
pub fn PropertyBag::get_host_slot(self : PropertyBag, key : HostSlotKey) -> Value? {
  self.host_slots.get(key.id)
}

///|
pub fn PropertyBag::set_host_slot(
  self : PropertyBag,
  key : HostSlotKey,
  value : Value,
) -> Unit {
  self.host_slots[key.id] = value
}

///|
pub fn PropertyBag::delete_host_slot(self : PropertyBag, key : HostSlotKey) -> Unit {
  self.host_slots.remove(key.id)
}

///|
pub fn PropertyBag::has_host_slot(self : PropertyBag, key : HostSlotKey) -> Bool {
  match self.host_slots.get(key.id) {
    Some(_) => true
    None => false
  }
}

///|
pub fn get_host_slot(data : ObjectData, key : HostSlotKey) -> Value? {
  data.bag.get_host_slot(key)
}

///|
pub fn set_host_slot(data : ObjectData, key : HostSlotKey, value : Value) -> Unit {
  data.bag.set_host_slot(key, value)
}

///|
pub fn delete_host_slot(data : ObjectData, key : HostSlotKey) -> Unit {
  data.bag.delete_host_slot(key)
}

///|
pub fn has_host_slot(data : ObjectData, key : HostSlotKey) -> Bool {
  data.bag.has_host_slot(key)
}
