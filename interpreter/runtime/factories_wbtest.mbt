///| Whitebox tests for realm-aware factory helpers.

///|
fn test_proto(label : String) -> Value {
  make_object({ "label": String_(label) }, Null, None, "Object", Map([]), true)
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
test "constructor realm intrinsic falls back for an unstamped callable" {
  let fallback = test_proto("current realm Object.prototype")
  let resolved = constructor_realm_intrinsic_prototype(
    unmarked_callable(),
    "Object",
    fallback,
  )
  if !strict_equal(resolved, fallback) {
    fail("unstamped callable should use the current-realm fallback")
  }
}

///|
test "constructor realm intrinsic preserves explicit Object realm stamps" {
  let function_proto = test_proto("foreign Function.prototype")
  let object_proto = test_proto("foreign Object.prototype")
  let fallback = test_proto("current realm Object.prototype")
  let callable = stamp_function_realm_with(
    unmarked_callable(),
    function_proto,
    object_proto,
  )
  let resolved = constructor_realm_intrinsic_prototype(
    callable, "Object", fallback,
  )
  if !strict_equal(resolved, object_proto) {
    fail("explicit realm stamp should supply %Object.prototype%")
  }
}

///|
test "function realm packed array has Null slots for absent prototypes" {
  let failure : Ref[String?] = { val: None }
  with_active_realm_state_unit(RealmState(), fn() {
    let func = make_native_func(name="early", fn(_args) { Undefined })
    match func {
      Object(data) =>
        match
          data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID) {
          Some(Array(arr_data)) => {
            let e = arr_data.elements
            if e.length() != FUNCTION_REALM_PROTO_SLOT_COUNT {
              failure.val = Some(
                "identity-free metadata should contain only realm slots",
              )
              return
            }
            match e[REALM_PROTO_IDX_FUNCTION] {
              Null => ()
              _ =>
                failure.val = Some(
                  "expected Null at FUNCTION slot for null Function.prototype",
                )
            }
            match e[REALM_PROTO_IDX_OBJECT] {
              Null => ()
              _ =>
                failure.val = Some(
                  "expected Null at OBJECT slot for null Object.prototype",
                )
            }
          }
          _ =>
            failure.val = Some(
              "expected packed array at FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID",
            )
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
test "source identity shares the packed function metadata lookup" {
  let realm_state = RealmState()
  realm_state.active_source_identity.val = Some("source.js")
  let func = make_native_func(
    name="identified",
    realm_state=Some(realm_state),
    fn(_args) { Undefined },
  )
  match func {
    Object(data) => {
      if data.bag.symbol_properties.contains(-102) {
        fail("source identity must not require a second symbol-property lookup")
      }
      match
        data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID) {
        Some(Array(arr_data)) => {
          let e = arr_data.elements
          if e.length() != FUNCTION_METADATA_SLOT_COUNT {
            fail("expected realm slots plus one source-identity slot")
          }
          match e[FUNCTION_SOURCE_IDENTITY_IDX] {
            String_(identity) if identity == "source.js" => ()
            _ => fail("expected source identity in packed function metadata")
          }
        }
        _ => fail("expected packed function metadata")
      }
    }
    _ => fail("expected function object")
  }
  if function_source_identity(func) != Some("source.js") {
    fail("expected packed source identity to remain observable")
  }
  if realm_fast_path_allowed(func, realm_state) {
    fail("source-attributed functions must use the observation-aware call path")
  }
}

///|
test "source observation blocks the fast path and restores its barrier" {
  let realm_state = RealmState()
  let func = make_native_func(
    name="identity-free",
    realm_state=Some(realm_state),
    fn(_args) { Undefined },
  )
  if !realm_fast_path_allowed(func, realm_state) {
    fail("identity-free same-realm function should start on the fast path")
  }
  let fast_path_allowed_during_observation : Ref[Bool] = { val: false }
  let observed = observe_source_failure(realm_state, fn() {
    fast_path_allowed_during_observation.val = realm_fast_path_allowed(
      func, realm_state,
    )
    Undefined
  })
  guard observed is Ok(_) else { fail("observation should succeed") }
  if fast_path_allowed_during_observation.val {
    fail("source observation must force the failure-recording call path")
  }
  if realm_state.active_overrides.val is Some(_) {
    fail("source observation must restore the previous override state")
  }
  if !realm_fast_path_allowed(func, realm_state) {
    fail("fast path should be restored after source observation")
  }
}

///|
test "unattributed nested failure is claimed by an identified outer frame" {
  let realm_state = RealmState()
  realm_state.active_source_identity.val = Some("outer.js")
  let identified = make_native_func(
    name="identified",
    realm_state=Some(realm_state),
    fn(_args) { Undefined },
  )
  realm_state.active_source_identity.val = None
  let observed = observe_source_failure(realm_state, fn() raise {
    with_active_callee_realm_value(realm_state, identified, fn() raise {
      with_active_callee_realm_value(realm_state, unmarked_callable(), fn() raise {
        fail("nested failure")
      })
    })
  })
  match observed {
    Err(failure) =>
      if failure.source_identity() != Some("outer.js") {
        fail("identified outer frame should claim the nested failure")
      }
    Ok(_) => fail("expected nested failure")
  }
}

///|
test "unmarked callees clear inherited active realm overrides" {
  let realm_state = RealmState()
  let base_function_proto = test_proto("base function")
  let base_object_proto = test_proto("base object")
  let base_string_proto = test_proto("base string")
  let override_function_proto = test_proto("override function")
  let override_object_proto = test_proto("override object")
  let override_string_proto = test_proto("override string")
  realm_state.function_prototype.val = Some(base_function_proto)
  realm_state.object_prototype.val = Some(base_object_proto)
  realm_state.string_prototype.val = Some(base_string_proto)
  let failure : Ref[String?] = { val: None }
  with_active_realm_state_unit(realm_state, fn() {
    apply_active_realm_protos(
      realm_state,
      FunctionRealmProtos(
        function_proto=Some(override_function_proto),
        object_proto=Some(override_object_proto),
        string_proto=Some(override_string_proto),
      ),
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
      if !strict_equal(
          get_string_proto(realm_state=Some(realm_state)),
          base_string_proto,
        ) {
        fail("expected unstamped callee to use active String.prototype")
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
    if !strict_equal(
        get_string_proto(realm_state=Some(realm_state)),
        override_string_proto,
      ) {
      failure.val = Some("expected string override to be restored after call")
    }
  })
  match failure.val {
    Some(message) => fail(message)
    None => ()
  }
}

///|
// Calibration: set active_array_prototype_override while Array slot is None.
// The OLD single-proto check (sampling only Function.prototype) would have
// allowed the fast path even with a live override on Array. This verifies the
// full check correctly routes to the slow path.
test "active override on non-function slot blocks fast path" {
  let realm_state = RealmState()
  let foreign_array_proto = test_proto("foreign array")
  realm_state.function_prototype.val = Some(test_proto("func proto"))
  realm_state.object_prototype.val = Some(test_proto("obj proto"))
  let func = make_native_func(name="fn", realm_state=Some(realm_state), fn(
    _args,
  ) {
    Undefined
  })
  // Activate a non-function override while the function slot is None
  apply_active_realm_protos(
    realm_state,
    FunctionRealmProtos(array_proto=Some(foreign_array_proto)),
  )
  // Fast path must NOT be allowed: override is active
  if realm_fast_path_allowed(func, realm_state) {
    fail(
      "fast path must be blocked when active_array_prototype_override is set",
    )
  }
}

///|
test "apply_active_realm_protos with all-None clears an existing override" {
  let realm_state = RealmState()
  let base_map_proto = test_proto("base map")
  let active_map_proto = test_proto("active map")
  realm_state.map_prototype.val = Some(base_map_proto)
  // Stamp the func now so Part 2 of realm_fast_path_allowed stays green
  let func = make_native_func(name="fn", realm_state=Some(realm_state), fn(
    _args,
  ) {
    Undefined
  })
  apply_active_realm_protos(
    realm_state,
    FunctionRealmProtos(map_proto=Some(active_map_proto)),
  )
  // Override active: Part 1 blocks fast path; getter returns override
  if realm_fast_path_allowed(func, realm_state) {
    fail("fast path must be blocked when map override is active")
  }
  if !strict_equal(
      get_map_proto(realm_state=Some(realm_state)),
      active_map_proto,
    ) {
    fail("expected get_map_proto to return the active override")
  }
  // Clear all overrides with all-None protos
  apply_active_realm_protos(realm_state, FunctionRealmProtos())
  // No override active: fast path allowed; getter falls back to base
  if !realm_fast_path_allowed(func, realm_state) {
    fail("fast path must be allowed after clearing all overrides")
  }
  if !strict_equal(get_map_proto(realm_state=Some(realm_state)), base_map_proto) {
    fail("expected get_map_proto to return base proto after override cleared")
  }
}

///|
// Calibration: stamp a function with a foreign Array.prototype while keeping
// Function.prototype and Object.prototype matching the realm. The OLD single-
// proto check would have allowed the fast path. The full check must reject it.
test "mixed stamp with foreign array proto blocks fast path" {
  let realm_state = RealmState()
  let func_proto = test_proto("func proto")
  let obj_proto = test_proto("obj proto")
  let foreign_array_proto = test_proto("foreign array")
  realm_state.function_prototype.val = Some(func_proto)
  realm_state.object_prototype.val = Some(obj_proto)
  realm_state.array_prototype.val = Some(test_proto("realm array"))
  let func = make_native_func(name="fn", realm_state=Some(realm_state), fn(
    _args,
  ) {
    Undefined
  })
  // Re-stamp only the array slot with a foreign proto, keeping function/object matching
  let _ = stamp_function_realm_with(
    func,
    func_proto,
    obj_proto,
    array_proto=foreign_array_proto,
  )
  // Fast path must NOT be allowed: array slot is foreign
  if realm_fast_path_allowed(func, realm_state) {
    fail("fast path must be blocked when array proto is foreign")
  }
}
