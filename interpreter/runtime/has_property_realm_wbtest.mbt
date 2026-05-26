///| Whitebox tests for HasProperty target prototype routing.

///|
fn has_marker_proto() -> Value {
  make_object({ "marker": String_("target") }, Null, None, "Object", {}, true)
}

///|
test "has_property_key uses target Map prototype, not active callee realm" {
  let interp = Interpreter::new()
  let target_proto = has_marker_proto()
  let active_proto = make_object({}, Null, None, "Object", {}, true)
  interp.realm_state.active_map_prototype_override.val = Some(active_proto)
  let target = Map(MapData([], prototype=target_proto))
  assert_true(interp.has_property_key(target, String_("marker")))
}

///|
test "has_property_key uses target Set prototype, not active callee realm" {
  let interp = Interpreter::new()
  let target_proto = has_marker_proto()
  let active_proto = make_object({}, Null, None, "Object", {}, true)
  interp.realm_state.active_set_prototype_override.val = Some(active_proto)
  let target = Set(SetData([], prototype=target_proto))
  assert_true(interp.has_property_key(target, String_("marker")))
}

///|
test "has_property_key uses base Promise prototype, not active callee realm" {
  let interp = Interpreter::new()
  let base_proto = has_marker_proto()
  let active_proto = make_object({}, Null, None, "Object", {}, true)
  interp.realm_state.promise_prototype.val = Some(base_proto)
  interp.realm_state.active_promise_prototype_override.val = Some(active_proto)
  let target = Promise(new_promise_data())
  assert_true(interp.has_property_key(target, String_("marker")))
}
