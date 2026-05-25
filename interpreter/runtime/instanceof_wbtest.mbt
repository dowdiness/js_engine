///| Whitebox tests for instanceof prototype-chain edge cases.

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
