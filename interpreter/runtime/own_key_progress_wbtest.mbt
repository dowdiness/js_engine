///| Runtime-only RED evidence for native own-key and CopyDataProperties paths.

///|
const OWN_KEY_RUNTIME_SOURCE_SIZE = 5000

///|
fn own_key_runtime_typedarray_hooks() -> StdlibHooks {
  {
    ..default_stdlib_hooks(),
    typedarray_is_valid_index: fn(data, index, _realm_state) {
      let length = match data.bag.internal_slots.get(ArrayLength) {
        Some(Number(n)) => n.to_int()
        _ => 0
      }
      guard index >= 0 && index < length else { return false }
      let buffer_id = match data.bag.internal_slots.get(ArrayBufferID) {
        Some(Number(n)) => n.to_int()
        _ => return false
      }
      match data.arraybuffer_state {
        Some(state) => !state.detached.contains(buffer_id)
        None => false
      }
    },
  }
}

///|
fn own_key_runtime_large_object(class_name : String) -> Value {
  let bag = PropertyBag()
  for i in 0..<OWN_KEY_RUNTIME_SOURCE_SIZE {
    bag.properties["key-" + i.to_string()] = Number(i.to_double())
  }
  Object({
    bag,
    prototype: Null,
    callable: None,
    class_name,
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
fn own_key_runtime_large_map() -> Value {
  let data = MapData([])
  for i in 0..<OWN_KEY_RUNTIME_SOURCE_SIZE {
    data.bag.properties["key-" + i.to_string()] = Number(i.to_double())
  }
  Map(data)
}

///|
fn own_key_runtime_large_set() -> Value {
  let data = SetData([])
  for i in 0..<OWN_KEY_RUNTIME_SOURCE_SIZE {
    data.bag.properties["key-" + i.to_string()] = Number(i.to_double())
  }
  Set(data)
}

///|
fn own_key_runtime_large_promise() -> Value {
  let data = new_promise_data()
  for i in 0..<OWN_KEY_RUNTIME_SOURCE_SIZE {
    data.bag.properties["key-" + i.to_string()] = Number(i.to_double())
  }
  Promise(data)
}

///|
fn own_key_runtime_module_namespace(interp : Interpreter) -> Value {
  let exports : Map[String, Value] = Map([])
  for i in 0..<OWN_KEY_RUNTIME_SOURCE_SIZE {
    exports["export-" + i.to_string()] = Number(i.to_double())
  }
  interp.create_module_namespace_object(exports)
}

///|
fn own_key_runtime_sparse_array() -> Value {
  let source = make_array(
    Array::makei(OWN_KEY_RUNTIME_SOURCE_SIZE, _ => Undefined),
  )
  match source {
    Array(data) =>
      for i in 0..<(OWN_KEY_RUNTIME_SOURCE_SIZE - 1) {
        data.holes[i] = ()
      }
    _ => ()
  }
  source
}

///|
fn own_key_runtime_typed_array(detached : Bool) -> Value {
  let storage = ArrayBufferState()
  if detached {
    storage.detached[0] = true
  }
  let bag = PropertyBag()
  bag.internal_slots[ArrayBufferID] = Number(0.0)
  bag.internal_slots[ArrayLength] = Number(
    OWN_KEY_RUNTIME_SOURCE_SIZE.to_double(),
  )
  Object({
    bag,
    prototype: Null,
    callable: None,
    class_name: "Uint8Array",
    extensible: true,
    arraybuffer_state: Some(storage),
  })
}

///|
fn own_key_runtime_budget_outcome(
  interp : Interpreter,
  source : Value,
) -> String {
  let policy = ExecutionPolicy::new(1000L, 100L, InterruptionHandle()).unwrap()
  let result : Result[Int, Error] = Ok(
    interp.with_execution_policy(policy, () => {
      interp.own_property_keys(source).length()
    }),
  ) catch {
    error => Err(error)
  }
  match result {
    Ok(length) => "completed:" + length.to_string()
    Err(error) =>
      match execution_control_failure_code(error) {
        Some(code) => code
        None => "error:" + error.to_string()
      }
  }
}

///|
fn own_key_runtime_large_trap_result(
  interp : Interpreter,
  events : Array[String],
  label : String,
) -> Value {
  let result = make_array(
    Array::makei(OWN_KEY_RUNTIME_SOURCE_SIZE, i => {
      String_("trap-" + i.to_string())
    }),
  )
  let getter = make_method_func(
    name=label + " index",
    realm_state=Some(interp.realm_state),
    fn(_receiver, _args) {
      events.push(label + "-index")
      String_("trap-0")
    },
  )
  match result {
    Array(data) =>
      data.bag.descriptors["0"] = {
        writable: false,
        enumerable: true,
        configurable: true,
        getter: Some(getter),
        setter: None,
        is_accessor: true,
      }
    _ => ()
  }
  result
}

///|
fn own_key_runtime_nested_proxy(
  interp : Interpreter,
  events : Array[String],
) -> Value {
  let base = make_object(
    { "trap-0": Number(9.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let inner_result = own_key_runtime_large_trap_result(interp, events, "inner")
  let inner_trap = make_native_func(
    name="inner ownKeys",
    realm_state=Some(interp.realm_state),
    fn(_args) {
      events.push("inner-trap")
      inner_result
    },
  )
  let inner_handler = make_object(
    { "ownKeys": inner_trap },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let inner = Proxy({
    target: Some(base),
    handler: Some(inner_handler),
    is_callable: false,
    is_constructor: false,
  })
  let outer_result = own_key_runtime_large_trap_result(interp, events, "outer")
  let outer_trap = make_native_func(
    name="outer ownKeys",
    realm_state=Some(interp.realm_state),
    fn(_args) {
      events.push("outer-trap")
      outer_result
    },
  )
  let outer_handler = make_object(
    { "ownKeys": outer_trap },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  Proxy({
    target: Some(inner),
    handler: Some(outer_handler),
    is_callable: false,
    is_constructor: false,
  })
}

///|
test "native own-key collection covers Module bags and typed arrays" {
  let interp = Interpreter::new(stdlib_hooks=own_key_runtime_typedarray_hooks())
  let sources : Array[(String, Value)] = [
    ("module", own_key_runtime_module_namespace(interp)),
    ("map", own_key_runtime_large_map()),
    ("set", own_key_runtime_large_set()),
    ("promise", own_key_runtime_large_promise()),
    ("object", own_key_runtime_large_object("Object")),
    ("sparse-array", own_key_runtime_sparse_array()),
    ("typed-array", own_key_runtime_typed_array(false)),
    ("detached-typed-array", own_key_runtime_typed_array(true)),
  ]
  for case in sources {
    let length = interp.own_property_keys(case.1).length()
    if case.0 == "detached-typed-array" {
      assert_eq(length, 0)
    } else if case.0 == "sparse-array" {
      assert_eq(length, 2)
    } else {
      assert_true(length > 1000)
    }
  }
  assert_eq(interp.own_property_keys(sources[7].1).length(), 0)
  let outcomes = sources.map(case => {
    case.0 + "=" + own_key_runtime_budget_outcome(interp, case.1)
  })
  let reuse = make_object(
    { "reuse": Number(1.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  assert_eq(interp.own_property_keys(reuse).length(), 1)
  assert_eq(
    outcomes.join("|"),
    "module=execution-limit|map=execution-limit|set=execution-limit|promise=execution-limit|object=execution-limit|sparse-array=execution-limit|typed-array=execution-limit|detached-typed-array=execution-limit",
  )
}

///|
test "nested Proxy ownKeys classifies a native prebuilt result" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let source = own_key_runtime_nested_proxy(interp, events)
  let unbounded = interp.own_property_keys(source)
  assert_true(unbounded.length() > 1000)
  assert_true(events.contains("outer-trap"))
  assert_true(events.contains("outer-index"))
  assert_true(events.contains("inner-trap"))
  assert_true(events.contains("inner-index"))
  let outcome = own_key_runtime_budget_outcome(interp, source)
  let reuse = make_object(
    { "reuse": Number(1.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  assert_eq(interp.own_property_keys(reuse).length(), 1)
  assert_eq(outcome, "execution-limit")
}

///|
fn own_key_runtime_interrupting_source(
  interp : Interpreter,
  interruption : InterruptionHandle,
  calls : Ref[Int],
) -> Value {
  let getter = make_method_func(
    name="interrupting source getter",
    realm_state=Some(interp.realm_state),
    fn(_receiver, _args) {
      calls.val += 1
      interruption.request()
      Number(7.0)
    },
  )
  make_object(
    { "0": Number(1.0), "x": Undefined },
    Null,
    None,
    "Object",
    {
      "x": {
        writable: false,
        enumerable: true,
        configurable: true,
        getter: Some(getter),
        setter: None,
        is_accessor: true,
      },
    },
    true,
  )
}

///|
fn own_key_runtime_result_code(result : Result[Unit, Error]) -> String {
  match result {
    Ok(_) => "completed"
    Err(error) =>
      match execution_control_failure_code(error) {
        Some(code) => code
        None => "error:" + error.to_string()
      }
  }
}

///|
fn own_key_runtime_value_result_code(result : Result[Value, Error]) -> String {
  match result {
    Ok(_) => "completed"
    Err(error) =>
      match execution_control_failure_code(error) {
        Some(code) => code
        None => "error:" + error.to_string()
      }
  }
}

///|
fn own_key_runtime_descriptor_cancel_proxy(
  interp : Interpreter,
  interruption : InterruptionHandle,
  calls : Ref[Int],
  returned_keys : Array[Value],
) -> Value {
  let base = make_object(
    { "x": Number(1.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let descriptor_trap = make_native_func(
    name="interrupting getOwnPropertyDescriptor",
    realm_state=Some(interp.realm_state),
    fn(_args) {
      calls.val += 1
      interruption.request()
      make_object(
        {
          "enumerable": Bool(true),
          "configurable": Bool(true),
          "value": Number(1.0),
          "writable": Bool(true),
        },
        Null,
        None,
        "Object",
        Map([]),
        true,
      )
    },
  )
  let inner_handler = make_object(
    { "getOwnPropertyDescriptor": descriptor_trap },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let inner = Proxy({
    target: Some(base),
    handler: Some(inner_handler),
    is_callable: false,
    is_constructor: false,
  })
  let outer_own_keys = make_native_func(
    name="descriptor cancellation ownKeys",
    realm_state=Some(interp.realm_state),
    fn(_args) { make_array(returned_keys.copy()) },
  )
  let outer_handler = make_object(
    { "ownKeys": outer_own_keys },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  Proxy({
    target: Some(inner),
    handler: Some(outer_handler),
    is_callable: false,
    is_constructor: false,
  })
}

///|
fn own_key_runtime_symbol_only_consumer_proxy(
  interp : Interpreter,
  interruption : InterruptionHandle,
) -> Value {
  let calls : Ref[Int] = { val: 0, }
  let symbol = interp.realm_state.well_known_symbols.iterator
  own_key_runtime_descriptor_cancel_proxy(interp, interruption, calls, [
    Symbol(symbol),
  ])
}

///|
fn own_key_runtime_interrupting_index_proxy(
  interp : Interpreter,
  interruption : InterruptionHandle,
) -> Value {
  let trap_result = make_array([Undefined])
  let index_getter = make_method_func(
    name="interrupting ownKeys index",
    realm_state=Some(interp.realm_state),
    fn(_receiver, _args) {
      interruption.request()
      Number(1.0)
    },
  )
  match trap_result {
    Array(data) =>
      data.bag.descriptors["0"] = {
        writable: false,
        enumerable: true,
        configurable: true,
        getter: Some(index_getter),
        setter: None,
        is_accessor: true,
      }
    _ => ()
  }
  let own_keys = make_native_func(
    name="indexed ownKeys",
    realm_state=Some(interp.realm_state),
    fn(_args) { trap_result },
  )
  let handler = make_object(
    { "ownKeys": own_keys },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  Proxy({
    target: Some(make_object(Map([]), Null, None, "Object", Map([]), true)),
    handler: Some(handler),
    is_callable: false,
    is_constructor: false,
  })
}

///|
test "enumerable consumer propagates descriptor interruption" {
  let interp = Interpreter::new()
  let interruption = InterruptionHandle()
  let source = own_key_runtime_symbol_only_consumer_proxy(interp, interruption)
  let policy = ExecutionPolicy::new(1000L, 100L, interruption).unwrap()
  let result : Result[Value, Error] = Ok(
    interp.with_execution_policy(policy, () => object_keys(interp, source)),
  ) catch {
    error => Err(error)
  }
  assert_eq(own_key_runtime_value_result_code(result), "interrupted")
}

///|
test "synchronous proxy ownKeys stops before native index classification" {
  let sync_interruption = InterruptionHandle()
  let managed_interruption = InterruptionHandle()
  let interp = Interpreter::new()
  let sync_source = own_key_runtime_interrupting_index_proxy(
    interp, sync_interruption,
  )
  let managed_source = own_key_runtime_interrupting_index_proxy(
    interp, managed_interruption,
  )
  let sync_policy = ExecutionPolicy::new(1000L, 100L, sync_interruption).unwrap()
  let managed_policy = ExecutionPolicy::new(1000L, 100L, managed_interruption).unwrap()
  let sync_control = sync_policy.to_execution_control()
  let managed_control = managed_policy.to_execution_control()
  let sync_result : Result[Value, Error] = Ok(
    interp.with_execution_control(sync_control, () => {
      make_array(interp.own_property_keys(sync_source))
    }),
  ) catch {
    error => Err(error)
  }
  let managed_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let managed_result : Result[Unit, Error] = Ok(
    interp.with_execution_control(managed_control, () => {
      run_executor_copy_data_properties_for_wb(
        interp, managed_target, managed_source,
      )
    }),
  ) catch {
    error => Err(error)
  }
  assert_eq(sync_control.active_depth(), 0L)
  assert_eq(managed_control.active_depth(), 0L)
  assert_eq(own_key_runtime_value_result_code(sync_result), "interrupted")
  assert_eq(own_key_runtime_result_code(managed_result), "interrupted")
}

///|
test "Proxy ownKeys observes the final target descriptor cancellation" {
  let interp = Interpreter::new()
  let unbounded_interruption = InterruptionHandle()
  let unbounded_calls : Ref[Int] = { val: 0, }
  let unbounded_source = own_key_runtime_descriptor_cancel_proxy(
    interp,
    unbounded_interruption,
    unbounded_calls,
    [],
  )
  let unbounded_keys = interp.own_property_keys(unbounded_source)
  assert_eq(unbounded_keys.length(), 0)
  assert_eq(unbounded_calls.val, 1)

  let sync_interruption = InterruptionHandle()
  let managed_interruption = InterruptionHandle()
  let sync_calls : Ref[Int] = { val: 0, }
  let managed_calls : Ref[Int] = { val: 0, }
  let sync_source = own_key_runtime_descriptor_cancel_proxy(
    interp,
    sync_interruption,
    sync_calls,
    [],
  )
  let managed_source = own_key_runtime_descriptor_cancel_proxy(
    interp,
    managed_interruption,
    managed_calls,
    [],
  )
  let sync_policy = ExecutionPolicy::new(1000L, 100L, sync_interruption).unwrap()
  let managed_policy = ExecutionPolicy::new(1000L, 100L, managed_interruption).unwrap()
  let sync_control = sync_policy.to_execution_control()
  let managed_control = managed_policy.to_execution_control()
  let sync_result : Result[Value, Error] = Ok(
    interp.with_execution_control(sync_control, () => {
      make_array(interp.own_property_keys(sync_source))
    }),
  ) catch {
    error => Err(error)
  }
  let managed_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let managed_result : Result[Unit, Error] = Ok(
    interp.with_execution_control(managed_control, () => {
      run_executor_copy_data_properties_for_wb(
        interp, managed_target, managed_source,
      )
    }),
  ) catch {
    error => Err(error)
  }
  assert_eq(sync_control.active_depth(), 0L)
  assert_eq(managed_control.active_depth(), 0L)
  assert_eq(sync_calls.val, 1)
  assert_eq(managed_calls.val, 1)
  let managed_target_status = match
    interp.get_own_property(managed_target, String_("x")) {
    None => "untouched"
    Some(_) => "written"
  }
  let outcomes = [
    "sync=" + own_key_runtime_value_result_code(sync_result),
    "managed=" + own_key_runtime_result_code(managed_result),
    "managed-target=" + managed_target_status,
  ]
  assert_eq(
    outcomes.join("|"),
    "sync=interrupted|managed=interrupted|managed-target=untouched",
  )
}

///|
test "native getter interruption stops before synchronous and managed writes" {
  let interp = Interpreter::new()
  let sync_interruption = InterruptionHandle()
  let managed_interruption = InterruptionHandle()
  let sync_calls : Ref[Int] = { val: 0, }
  let managed_calls : Ref[Int] = { val: 0, }
  let sync_source = own_key_runtime_interrupting_source(
    interp, sync_interruption, sync_calls,
  )
  let managed_source = own_key_runtime_interrupting_source(
    interp, managed_interruption, managed_calls,
  )
  let sync_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let managed_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let sync_policy = ExecutionPolicy::new(1000L, 100L, sync_interruption).unwrap()
  let managed_policy = ExecutionPolicy::new(1000L, 100L, managed_interruption).unwrap()
  let sync_result : Result[Unit, Error] = Ok(
    interp.with_execution_policy(sync_policy, () => {
      interp.copy_object_spread_properties(
        sync_target,
        sync_source,
        @token.Loc::default(),
      )
    }),
  ) catch {
    error => Err(error)
  }
  let managed_result : Result[Unit, Error] = Ok(
    interp.with_execution_policy(managed_policy, () => {
      run_executor_copy_data_properties_for_wb(
        interp, managed_target, managed_source,
      )
    }),
  ) catch {
    error => Err(error)
  }
  let outcomes = [
    "sync=" + own_key_runtime_result_code(sync_result),
    "managed=" + own_key_runtime_result_code(managed_result),
  ]
  assert_eq(sync_calls.val, 1)
  assert_eq(managed_calls.val, 1)
  let sync_prefix_status = interp
    .get_property(sync_target, "0", @token.Loc::default())
    .to_string()
  let managed_prefix_status = interp
    .get_property(managed_target, "0", @token.Loc::default())
    .to_string()
  assert_eq(sync_prefix_status, "1")
  assert_eq(managed_prefix_status, "1")
  outcomes.push("sync-prefix=" + sync_prefix_status)
  outcomes.push("managed-prefix=" + managed_prefix_status)
  let sync_target_status = match
    interp.get_own_property(sync_target, String_("x")) {
    Some(_) => "written"
    None => "untouched"
  }
  let managed_target_status = match
    interp.get_own_property(managed_target, String_("x")) {
    Some(_) => "written"
    None => "untouched"
  }
  outcomes.push("sync-target=" + sync_target_status)
  outcomes.push("managed-target=" + managed_target_status)
  let reuse_source = make_object(
    { "x": Number(9.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let reuse_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  interp.copy_object_spread_properties(
    reuse_target,
    reuse_source,
    @token.Loc::default(),
  )
  assert_true(interp.get_own_property(reuse_target, String_("x")) is Some(_))
  assert_eq(
    outcomes.join("|"),
    "sync=interrupted|managed=interrupted|sync-prefix=1|managed-prefix=1|sync-target=untouched|managed-target=untouched",
  )
}

///|
test "managed native ownKeys result respects budget and reuses interpreter" {
  let interp = Interpreter::new()
  let unbounded_events : Array[String] = []
  let unbounded_result = own_key_runtime_large_trap_result(
    interp, unbounded_events, "managed-unbounded",
  )
  let unbounded_trap = make_native_func(
    name="managed unbounded ownKeys",
    realm_state=Some(interp.realm_state),
    fn(_args) {
      unbounded_events.push("managed-unbounded-trap")
      unbounded_result
    },
  )
  let unbounded_handler = make_object(
    { "ownKeys": unbounded_trap },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let unbounded_source = Proxy({
    target: Some(
      make_object(
        { "trap-0": Number(9.0) },
        Null,
        None,
        "Object",
        Map([]),
        true,
      ),
    ),
    handler: Some(unbounded_handler),
    is_callable: false,
    is_constructor: false,
  })
  let unbounded_target = make_object(
    Map([]),
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  run_executor_copy_data_properties_for_wb(
    interp, unbounded_target, unbounded_source,
  )
  assert_eq(
    unbounded_events.join("|"),
    "managed-unbounded-trap|managed-unbounded-index",
  )
  match interp.get_own_property(unbounded_target, String_("trap-0")) {
    Some((_, value)) => assert_eq(value.to_string(), "9")
    None => fail("unbounded managed copy did not write trap-0")
  }

  let bounded_events : Array[String] = []
  let bounded_result = own_key_runtime_large_trap_result(
    interp, bounded_events, "managed-bounded",
  )
  let bounded_trap = make_native_func(
    name="managed bounded ownKeys",
    realm_state=Some(interp.realm_state),
    fn(_args) {
      bounded_events.push("managed-bounded-trap")
      bounded_result
    },
  )
  let bounded_handler = make_object(
    { "ownKeys": bounded_trap },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let bounded_source = Proxy({
    target: Some(
      make_object(
        { "trap-0": Number(9.0) },
        Null,
        None,
        "Object",
        Map([]),
        true,
      ),
    ),
    handler: Some(bounded_handler),
    is_callable: false,
    is_constructor: false,
  })
  let bounded_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let policy = ExecutionPolicy::new(1000L, 100L, InterruptionHandle()).unwrap()
  let control = policy.to_execution_control()
  let bounded_outcome : Result[Unit, Error] = Ok(
    interp.with_execution_control(control, () => {
      run_executor_copy_data_properties_for_wb(
        interp, bounded_target, bounded_source,
      )
    }),
  ) catch {
    error => Err(error)
  }
  let bounded_code = own_key_runtime_result_code(bounded_outcome)
  assert_eq(control.active_depth(), 0L)
  assert_eq(
    bounded_events.join("|"),
    "managed-bounded-trap|managed-bounded-index",
  )
  let reuse_source = make_object(
    { "small": Number(4.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let reuse_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  run_executor_copy_data_properties_for_wb(interp, reuse_target, reuse_source)
  assert_true(
    interp.get_own_property(reuse_target, String_("small")) is Some(_),
  )
  let bounded_target_status = match
    interp.get_own_property(bounded_target, String_("trap-0")) {
    Some(_) => "written"
    None => "untouched"
  }
  assert_eq(
    bounded_code + "|" + bounded_target_status,
    "execution-limit|untouched",
  )
}
