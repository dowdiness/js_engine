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
