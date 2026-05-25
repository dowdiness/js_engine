///| Whitebox tests for realm-aware factory helpers.

///|
fn test_proto(label : String) -> Value {
  make_object({ "label": String_(label) }, Null, None, "Object", {}, true)
}

///|
fn unmarked_callable() -> Value {
  Object({
    bag: PropertyBag(),
    prototype: Null,
    callable: Some(
      NonConstructableCallable("unmarked", fn(_args) { Undefined }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
test "function realm markers omit null prototypes" {
  let failure : Ref[String?] = { val: None }
  with_active_realm_state_unit(RealmState(), fn() {
    let func = make_native_func(name="early", fn(_args) { Undefined })
    match func {
      Object(data) => {
        if data.bag.symbol_properties.contains(
            FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID,
          ) {
          failure.val = Some(
            "expected no function realm marker for null Function.prototype",
          )
        }
        if data.bag.symbol_properties.contains(
            FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID,
          ) {
          failure.val = Some(
            "expected no object realm marker for null Object.prototype",
          )
        }
        if data.bag.symbol_descriptors.contains(
            FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID,
          ) {
          failure.val = Some(
            "expected no function realm descriptor for null Function.prototype",
          )
        }
        if data.bag.symbol_descriptors.contains(
            FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID,
          ) {
          failure.val = Some(
            "expected no object realm descriptor for null Object.prototype",
          )
        }
      }
      _ => failure.val = Some("expected function object")
    }
  })
  match failure.val {
    Some(message) => fail(message)
    None => ()
  }
}

///|
test "unmarked callees clear inherited active realm overrides" {
  let realm_state = RealmState()
  let base_function_proto = test_proto("base function")
  let base_object_proto = test_proto("base object")
  let override_function_proto = test_proto("override function")
  let override_object_proto = test_proto("override object")
  realm_state.function_prototype.val = Some(base_function_proto)
  realm_state.object_prototype.val = Some(base_object_proto)
  let failure : Ref[String?] = { val: None }
  with_active_realm_state_unit(realm_state, fn() {
    realm_state.active_function_prototype_override.val = Some(
      override_function_proto,
    )
    realm_state.active_object_prototype_override.val = Some(
      override_object_proto,
    )
    let _ = with_active_callee_realm_value(realm_state, unmarked_callable(), fn() raise {
      if !strict_equal(
          get_func_proto(realm_state=Some(realm_state)),
          base_function_proto,
        ) {
        fail("expected unstamped callee to use active Function.prototype")
      }
      if !strict_equal(
          get_obj_proto(realm_state=Some(realm_state)),
          base_object_proto,
        ) {
        fail("expected unstamped callee to use active Object.prototype")
      }
      Undefined
    }) catch {
      err => {
        failure.val = Some("unexpected call failure: " + err.to_string())
        Undefined
      }
    }
    if !strict_equal(
        get_func_proto(realm_state=Some(realm_state)),
        override_function_proto,
      ) {
      failure.val = Some("expected function override to be restored after call")
    }
    if !strict_equal(
        get_obj_proto(realm_state=Some(realm_state)),
        override_object_proto,
      ) {
      failure.val = Some("expected object override to be restored after call")
    }
  })
  match failure.val {
    Some(message) => fail(message)
    None => ()
  }
}
