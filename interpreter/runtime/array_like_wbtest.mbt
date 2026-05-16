///| Whitebox tests for the Array iteration-model helpers.

///|
test "lookup: dense element returns Present" {
  let data : ArrayData = {
    elements: [Number(10.0), Number(20.0), Number(30.0)],
    bag: PropertyBag::PropertyBag(),
    length_writable: true,
    holes: {},
    extensible: true,
  }
  match array_index_lookup_result(data, 1) {
    Present(Number(n)) =>
      if n != 20.0 {
        fail("expected 20.0, got " + n.to_string())
      }
    _ => fail("expected Present(20)")
  }
}

///|
test "lookup: hole index returns Hole" {
  let data : ArrayData = {
    elements: [Number(10.0), Undefined, Number(30.0)],
    bag: PropertyBag::PropertyBag(),
    length_writable: true,
    holes: { 1: () },
    extensible: true,
  }
  match array_index_lookup_result(data, 1) {
    Hole => ()
    _ => fail("expected Hole")
  }
}

///|
test "lookup: out-of-range index returns OutOfRange" {
  let data : ArrayData = {
    elements: [Number(10.0)],
    bag: PropertyBag::PropertyBag(),
    length_writable: true,
    holes: {},
    extensible: true,
  }
  match array_index_lookup_result(data, 5) {
    OutOfRange => ()
    _ => fail("expected OutOfRange")
  }
  match array_index_lookup_result(data, -1) {
    OutOfRange => ()
    _ => fail("expected OutOfRange for negative")
  }
}

///|
test "lookup: own accessor with getter returns OwnAccessor(Some)" {
  let bag = PropertyBag::PropertyBag()
  let getter_value : Value = Undefined
  let desc : PropDescriptor = {
    writable: false,
    enumerable: true,
    configurable: true,
    getter: Some(getter_value),
    setter: None,
    is_accessor: true,
  }
  bag.descriptors["0"] = desc
  let data : ArrayData = {
    elements: [Number(10.0)],
    bag,
    length_writable: true,
    holes: {},
    extensible: true,
  }
  match array_index_lookup_result(data, 0) {
    OwnAccessor(Some(_)) => ()
    _ => fail("expected OwnAccessor(Some)")
  }
}

///|
test "cleanup_holes_above_length: drops keys >= new_len, keeps below" {
  let holes : Map[Int, Unit] = { 1: (), 3: (), 5: (), 7: () }
  cleanup_holes_above_length(holes, 5L)
  if holes.contains(5) || holes.contains(7) {
    fail("expected 5,7 dropped from holes")
  }
  if !holes.contains(1) || !holes.contains(3) {
    fail("expected 1,3 retained in holes")
  }
}

///|
test "cleanup_holes_above_length: new_len above Int max is a no-op (P1-C)" {
  // P1-C regression: prior code did `n64.to_int()` unconditionally,
  // wrapping a > 2^31 length to a negative Int, making `k >= new_len_int`
  // true for every Int-keyed hole and removing them all. With the
  // helper's Int-range guard, the cleanup must be a no-op.
  let holes : Map[Int, Unit] = { 0: (), 1000: (), 2000000000: () }
  cleanup_holes_above_length(holes, 3000000000L)
  if !holes.contains(0) || !holes.contains(1000) || !holes.contains(2000000000) {
    fail("expected all holes retained when new_len > Int max")
  }
}

///|
test "cleanup_holes_above_length: new_len at exactly Int max keeps boundary" {
  // Boundary: new_len == 2^31-1. Hole at 2^31-1 has key == new_len_int,
  // so `k >= new_len_int` is true and it must be dropped. Hole at
  // 2^31-2 must be retained.
  let holes : Map[Int, Unit] = { 0: (), 0x7FFFFFFE: (), 0x7FFFFFFF: () }
  cleanup_holes_above_length(holes, 0x7FFFFFFFL)
  if holes.contains(0x7FFFFFFF) {
    fail("expected hole at 2^31-1 dropped when new_len == 2^31-1")
  }
  if !holes.contains(0x7FFFFFFE) || !holes.contains(0) {
    fail("expected sub-boundary keys retained")
  }
}

///|
test "lookup: own write-only accessor returns OwnAccessor(None)" {
  let bag = PropertyBag::PropertyBag()
  let setter_value : Value = Undefined
  let desc : PropDescriptor = {
    writable: false,
    enumerable: true,
    configurable: true,
    getter: None,
    setter: Some(setter_value),
    is_accessor: true,
  }
  bag.descriptors["0"] = desc
  let data : ArrayData = {
    elements: [Number(10.0)],
    bag,
    length_writable: true,
    holes: {},
    extensible: true,
  }
  match array_index_lookup_result(data, 0) {
    OwnAccessor(None) => ()
    _ => fail("expected OwnAccessor(None)")
  }
}
