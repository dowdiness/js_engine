///| Whitebox tests for make_host_object (#517).

///|
fn host_obj_data(obj : Value) -> ObjectData raise Error {
  match obj {
    Object(data) => data
    _ => fail("expected Object")
  }
}

///|
fn stub_method(label : String) -> Value {
  make_native_func(name=label, fn(_args) { String_(label) })
}

///|
test "make_host_object name-only shell" {
  let obj = make_host_object(name="Element")
  let data = host_obj_data(obj)
  guard data.class_name == "Element" else { fail("class_name") }
  guard data.extensible else { fail("extensible default") }
  guard data.prototype is Null else { fail("proto default Null") }
  guard data.bag.properties.length() == 0 else { fail("no own props") }
  guard data.bag.descriptors.length() == 0 else { fail("no descriptors") }
  guard data.bag.host_slots.length() == 0 else { fail("no host slots") }
}

///|
test "make_host_object installs methods with builtin method descriptors" {
  let m = stub_method("setAttribute")
  let obj = make_host_object(name="Element", methods={ "setAttribute": m })
  let data = host_obj_data(obj)
  match data.bag.properties.get("setAttribute") {
    Some(v) =>
      match (v, m) {
        (Object(a), Object(b)) =>
          if !physical_equal(a, b) {
            fail("method identity")
          }
        _ => fail("expected object method values")
      }
    None => fail("method missing")
  }
  match data.bag.descriptors.get("setAttribute") {
    Some(desc) => {
      if !(desc.writable && !desc.enumerable && desc.configurable) {
        fail("method descriptor flags")
      }
      if desc.is_accessor {
        fail("method must be data")
      }
    }
    None => fail("method descriptor missing")
  }
}

///|
test "make_host_object installs paired and one-sided accessors" {
  let get_tc = stub_method("get textContent")
  let set_tc = stub_method("set textContent")
  let get_ro = stub_method("get nodeType")
  let set_wo = stub_method("set only")
  let obj = make_host_object(name="Element", accessors={
    "textContent": (Some(get_tc), Some(set_tc)),
    "nodeType": (Some(get_ro), None),
    "writeOnly": (None, Some(set_wo)),
  })
  let data = host_obj_data(obj)
  match data.bag.descriptors.get("textContent") {
    Some(desc) => {
      if !(desc.is_accessor && desc.getter is Some(_) && desc.setter is Some(_)) {
        fail("textContent accessor")
      }
      if !(!desc.enumerable && desc.configurable) {
        fail("textContent flags")
      }
    }
    None => fail("textContent missing")
  }
  match data.bag.descriptors.get("nodeType") {
    Some(desc) =>
      if !(desc.is_accessor && desc.getter is Some(_) && desc.setter is None) {
        fail("nodeType getter-only")
      }
    None => fail("nodeType missing")
  }
  match data.bag.descriptors.get("writeOnly") {
    Some(desc) =>
      if !(desc.is_accessor && desc.getter is None && desc.setter is Some(_)) {
        fail("writeOnly setter-only")
      }
    None => fail("writeOnly missing")
  }
}

///|
test "make_host_object non_writable and frozen data props" {
  let obj = make_host_object(
    name="Element",
    non_writable={ "nw": Number(1.0) },
    frozen={ "fr": Number(2.0) },
  )
  let data = host_obj_data(obj)
  match data.bag.descriptors.get("nw") {
    Some(desc) =>
      if !(!desc.writable && !desc.enumerable && desc.configurable) {
        fail("non_writable flags")
      }
    None => fail("nw missing")
  }
  match data.bag.descriptors.get("fr") {
    Some(desc) =>
      if !(!desc.writable && !desc.enumerable && !desc.configurable) {
        fail("frozen flags")
      }
    None => fail("fr missing")
  }
  if !(data.bag.properties.get("nw") is Some(Number(1.0))) {
    fail("nw value")
  }
  if !(data.bag.properties.get("fr") is Some(Number(2.0))) {
    fail("fr value")
  }
}

///|
test "make_host_object host_slots round-trip and stay off properties" {
  let key = HostSlotKey::reserve()
  let slots : Map[HostSlotKey, Value] = {}
  slots[key] = Number(99.0)
  let obj = make_host_object(name="Element", host_slots=slots)
  let data = host_obj_data(obj)
  match get_host_slot(data, key) {
    Some(Number(n)) => if n != 99.0 { fail("slot value") }
    _ => fail("expected host slot")
  }
  if data.bag.properties.get("__crater_nid") is Some(_) {
    fail("must not invent JS property for host slot")
  }
  if data.bag.properties.length() != 0 {
    fail("host slots must not appear as properties")
  }
}

///|
test "make_host_object same-key later install step wins" {
  let as_method = stub_method("asMethod")
  let getter = stub_method("asGetter")
  // non_writable first, then methods overwrites same key
  let obj = make_host_object(
    name="Element",
    non_writable={ "x": Number(1.0) },
    methods={ "x": as_method },
  )
  let data = host_obj_data(obj)
  match data.bag.properties.get("x") {
    Some(v) =>
      match (v, as_method) {
        (Object(a), Object(b)) =>
          if !physical_equal(a, b) {
            fail("methods should win")
          }
        _ => fail("expected method object")
      }
    None => fail("x missing")
  }
  match data.bag.descriptors.get("x") {
    Some(desc) =>
      if !(desc.writable && !desc.is_accessor) {
        fail("expected method descriptor after overwrite")
      }
    None => fail("x descriptor missing")
  }
  // methods then accessors: accessors win
  let obj2 = make_host_object(name="Element", methods={ "y": as_method }, accessors={
    "y": (Some(getter), None),
  })
  let data2 = host_obj_data(obj2)
  match data2.bag.descriptors.get("y") {
    Some(desc) =>
      if !(desc.is_accessor && desc.getter is Some(_)) {
        fail("accessors should win over methods")
      }
    None => fail("y missing")
  }
}

///|
test "panic make_host_object rejects empty accessor pair" {
  let _ = make_host_object(name="Element", accessors={ "bad": (None, None) })
}

///|
test "panic install_builtin_accessor rejects empty accessor pair" {
  let data = host_obj_data(make_host_object(name="Element"))
  install_builtin_accessor(data, "bad", None, None)
}

///|
test "make_host_object setter-only [[Get]] returns Undefined" {
  let set_wo = stub_method("set only")
  let obj = make_host_object(name="Element", accessors={
    "writeOnly": (None, Some(set_wo)),
  })
  let interp = Interpreter::new()
  match interp.get_property(obj, "writeOnly", @token.Loc::default()) {
    Undefined => ()
    other => fail("expected Undefined, got " + other.to_string())
  }
}
