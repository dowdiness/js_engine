///| Whitebox tests for instanceof prototype-chain edge cases.

///|
test "get_array_prototype ignores active callee realm without override" {
  let realm_state = RealmState()
  let base_proto = make_object({}, Null, None, "Object", {}, true)
  let active_proto = make_object({}, Null, None, "Object", {}, true)
  realm_state.array_prototype.val = Some(base_proto)
  apply_active_realm_protos(
    realm_state,
    FunctionRealmProtos(array_proto=Some(active_proto)),
  )
  let arr = make_array([Number(1.0)])
  match arr {
    Array(data) => {
      let proto = get_array_prototype(realm_state, data)
      if !strict_equal(proto, base_proto) {
        fail("array target prototype fallback must ignore active callee realm")
      }
    }
    _ => fail("expected array value")
  }
}

///|
test "instanceof honors per-array prototype override" {
  let interp = Interpreter::new()
  let custom_proto = make_object({}, Null, None, "Object", {}, true)
  let arr = make_array([Number(1.0)])
  match arr {
    Array(data) => set_array_prototype_override(data, custom_proto)
    _ => fail("expected array value")
  }
  match instanceof_prototype_chain(arr, custom_proto, interp) {
    Bool(true) => ()
    _ => fail("instanceof must walk an array's explicit prototype override")
  }
}
