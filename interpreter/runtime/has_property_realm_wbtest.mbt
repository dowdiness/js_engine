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
  apply_active_realm_protos(
    interp.realm_state,
    FunctionRealmProtos(map_proto=Some(active_proto)),
  )
  let target = Map(MapData([], prototype=Some(target_proto)))
  assert_true(interp.has_property_key(target, String_("marker")))
}

///|
test "has_property_key uses target Set prototype, not active callee realm" {
  let interp = Interpreter::new()
  let target_proto = has_marker_proto()
  let active_proto = make_object({}, Null, None, "Object", {}, true)
  apply_active_realm_protos(
    interp.realm_state,
    FunctionRealmProtos(set_proto=Some(active_proto)),
  )
  let target = Set(SetData([], prototype=Some(target_proto)))
  assert_true(interp.has_property_key(target, String_("marker")))
}

///|
test "has_property_key uses base Promise prototype, not active callee realm" {
  let interp = Interpreter::new()
  let base_proto = has_marker_proto()
  let active_proto = make_object({}, Null, None, "Object", {}, true)
  interp.realm_state.promise_prototype.val = Some(base_proto)
  apply_active_realm_protos(
    interp.realm_state,
    FunctionRealmProtos(promise_proto=Some(active_proto)),
  )
  let target = Promise(new_promise_data())
  assert_true(interp.has_property_key(target, String_("marker")))
}
