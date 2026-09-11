///|
test "startup realm stamp initializes public accessors without calling them" {
  let core = prepare_startup_core_after_setup_builtins()
  for key in ["string", "symbol", "internal"] {
    let accessors = ["get", "set"].map(name => {
      @runtime.make_native_func(name~, _ => {
        fail("realm stamping must not invoke accessors")
      })
    })
    let bag = @runtime.PropertyBag()
    let descriptor : PropDescriptor = {
      writable: false,
      enumerable: false,
      configurable: true,
      getter: Some(accessors[0]),
      setter: Some(accessors[1]),
      is_accessor: true,
    }
    match key {
      "string" => bag.descriptors["accessor"] = descriptor
      "symbol" => bag.symbol_descriptors[1] = descriptor
      _ => bag.symbol_descriptors[-1] = descriptor
    }
    let visited = []
    startup_stamp_realm_functions_in_bag(bag, core.realm_state, 4, visited)
    startup_clear_realm_stamp_markers(visited)
    let expected = if key == "internal" {
      Value::Null
    } else {
      @runtime.get_func_proto(realm_state=Some(core.realm_state))
    }
    for accessor in accessors {
      guard accessor is Value::Object(data) else { fail("expected function") }
      assert_true(@runtime.strict_equal(data.prototype, expected), msg=key)
    }
  }
}
