///| Whitebox tests for embedder host-slot API (#518).

///|
fn empty_object_data() -> ObjectData {
  {
    bag: PropertyBag(),
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  }
}

///|
test "host slot round-trip set get has delete" {
  let data = empty_object_data()
  let key = HostSlotKey::reserve()
  guard !has_host_slot(data, key) else { fail("expected absent before set") }
  guard get_host_slot(data, key) is None else {
    fail("expected None before set")
  }
  set_host_slot(data, key, Number(42.0))
  guard has_host_slot(data, key) else { fail("expected present after set") }
  match get_host_slot(data, key) {
    Some(Number(n)) =>
      if n != 42.0 {
        fail("expected 42.0, got " + n.to_string())
      }
    _ => fail("expected Some(Number(42))")
  }
  delete_host_slot(data, key)
  guard !has_host_slot(data, key) else { fail("expected absent after delete") }
  guard get_host_slot(data, key) is None else {
    fail("expected None after delete")
  }
}

///|
test "host slot stores Undefined as present" {
  let data = empty_object_data()
  let key = HostSlotKey::reserve()
  set_host_slot(data, key, Undefined)
  guard has_host_slot(data, key) else {
    fail("Undefined must count as present")
  }
  guard get_host_slot(data, key) is Some(Undefined) else {
    fail("expected Some(Undefined)")
  }
}

///|
test "host slot keys from reserve are distinct" {
  let data = empty_object_data()
  let k1 = HostSlotKey::reserve()
  let k2 = HostSlotKey::reserve()
  guard k1 != k2 else { fail("reserve must yield unequal keys") }
  set_host_slot(data, k1, Number(1.0))
  set_host_slot(data, k2, Number(2.0))
  match (get_host_slot(data, k1), get_host_slot(data, k2)) {
    (Some(Number(a)), Some(Number(b))) => {
      guard a == 1.0 else { fail("k1 corrupted") }
      guard b == 2.0 else { fail("k2 corrupted") }
    }
    _ => fail("expected both slots present")
  }
}

///|
test "set_host_slot does not touch internal_slots" {
  let data = empty_object_data()
  data.bag.internal_slots[StringData] = String_("engine")
  let key = HostSlotKey::reserve()
  set_host_slot(data, key, Number(7.0))
  guard data.bag.internal_slots.get(StringData) is Some(String_("engine")) else {
    fail("engine internal slot must be unchanged")
  }
  guard data.bag.internal_slots.get(NumberData) is None else {
    fail("must not invent engine slots")
  }
}

///|
test "PropertyBag host slot methods round-trip" {
  let bag = PropertyBag()
  let key = HostSlotKey::reserve()
  bag.set_host_slot(key, Number(9.0))
  guard bag.has_host_slot(key) else { fail("bag.has expected true") }
  match bag.get_host_slot(key) {
    Some(Number(n)) => if n != 9.0 { fail("bag.get mismatch") }
    _ => fail("bag.get expected Some(9)")
  }
  bag.delete_host_slot(key)
  guard !bag.has_host_slot(key) else {
    fail("bag.has expected false after delete")
  }
}

///|
test "delete_host_slot on absent key is a no-op" {
  let data = empty_object_data()
  let key = HostSlotKey::reserve()
  delete_host_slot(data, key)
  guard !has_host_slot(data, key) else {
    fail("absent delete must stay absent")
  }
  guard get_host_slot(data, key) is None else {
    fail("expected None after absent delete")
  }
}
