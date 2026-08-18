///|
priv struct ExecutorIterableSpreadTestRootFrame {
  iterable : Value
  loc : @token.Loc
  mut requested : Bool
  mut result : Value?
}

///|
fn ExecutorIterableSpreadTestRootFrame::ExecutorIterableSpreadTestRootFrame(
  iterable~ : Value,
  loc~ : @token.Loc,
) -> ExecutorIterableSpreadTestRootFrame {
  { iterable, loc, requested: false, result: None }
}

///|
impl ExecutorActivationFrame for ExecutorIterableSpreadTestRootFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    match begin_executor_iterable_spread(self.iterable, self.loc) {
      ExecutorIterableSpreadCompleted(values) => {
        let batch = make_array(values)
        self.result = Some(batch)
        ExecutorActivationReturn(batch)
      }
      ExecutorIterableSpreadSuspended(request) =>
        executor_activation_iterable_spread_request(request)
    }
  } else {
    match self.result {
      Some(batch) => ExecutorActivationReturn(batch)
      None =>
        raise @errors.InternalError(
          message="iterable spread root resumed without a batch",
        )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorIterableSpreadTestRootFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="iterable spread root received an unexpected binding reference completion",
      )
    ExecutorActivationCompletionNormal(value) => self.result = Some(value)
    ExecutorActivationCompletionAbrupt(error) => raise error
  }
}

///|
fn run_executor_iterable_spread_for_wb(
  interp : Interpreter,
  iterable : Value,
) -> Array[Value] raise Error {
  let root = ExecutorIterableSpreadTestRootFrame(
      iterable~,
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(batch) =>
      executor_iterable_spread_batch_values(batch)
    _ => fail("iterable spread root must return its completed batch")
  }
}

///|
fn assert_spread_numbers_for_wb(
  values : Array[Value],
  expected : Array[Double],
) -> Unit raise Error {
  assert_eq(values.length(), expected.length())
  for i in 0..<expected.length() {
    match values[i] {
      Number(value) => assert_eq(value, expected[i])
      _ => fail("iterable spread batch contained a non-number")
    }
  }
}

///|
fn make_bare_collection_intrinsic_for_wb(
  name : String,
  realm_state : RealmState,
  receiver_ref : Ref[Value],
  calls : Ref[Int],
) -> Value {
  make_method_func(name~, realm_state=Some(realm_state), fn(
    this_value,
    _args,
  ) raise {
    calls.val += 1
    assert_true(physical_equal(this_value, receiver_ref.val))
    let next = make_method_func(
      name=name + " next",
      realm_state=Some(realm_state),
      fn(_iterator, _next_args) { create_iter_result(Undefined, true) },
    )
    make_object({ "next": next }, Null, None, "Object", Map([]), true)
  })
}

///|
fn bare_map_set_hooks_for_wb(
  map_ref : Ref[Value],
  set_ref : Ref[Value],
  map_calls : Ref[Int],
  set_calls : Ref[Int],
) -> StdlibHooks {
  {
    ..default_stdlib_hooks(),
    get_map_method: fn(_data, prop, realm_state) {
      guard prop == "entries" else { return Undefined }
      make_bare_collection_intrinsic_for_wb(
        "bare map entries", realm_state, map_ref, map_calls,
      )
    },
    get_set_method: fn(_data, prop, realm_state) {
      guard prop == "values" else { return Undefined }
      make_bare_collection_intrinsic_for_wb(
        "bare set values", realm_state, set_ref, set_calls,
      )
    },
  }
}

///|
test "managed iterable spread owns the built-in array protocol" {
  let interp = Interpreter::new()
  let values = run_executor_iterable_spread_for_wb(
    interp,
    make_array([Number(1.0), Number(2.0)]),
  )
  assert_spread_numbers_for_wb(values, [1.0, 2.0])
}

///|
test "managed iterable spread preserves receivers and protocol order" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let iterable_ref : Ref[Value] = { val: Undefined }
  let iterator_ref : Ref[Value] = { val: Undefined }
  let index : Ref[Int] = { val: 0 }
  let next = make_method_func(
    name="next",
    realm_state=Some(interp.realm_state),
    fn(this_value, _args) raise {
      assert_true(physical_equal(this_value, iterator_ref.val))
      let current = index.val
      index.val += 1
      events.push("next" + current.to_string())
      if current >= 2 {
        create_iter_result(Undefined, true)
      } else {
        let value = Number(current.to_double())
        let done_getter = make_method_func(
          name="done",
          realm_state=Some(interp.realm_state),
          fn(_receiver, _getter_args) {
            events.push("done" + current.to_string())
            Bool(false)
          },
        )
        let value_getter = make_method_func(
          name="value",
          realm_state=Some(interp.realm_state),
          fn(_receiver, _getter_args) {
            events.push("value" + current.to_string())
            value
          },
        )
        let descriptors : Map[String, PropDescriptor] = {
          "done": {
            writable: false,
            enumerable: true,
            configurable: true,
            getter: Some(done_getter),
            setter: None,
            is_accessor: true,
          },
          "value": {
            writable: false,
            enumerable: true,
            configurable: true,
            getter: Some(value_getter),
            setter: None,
            is_accessor: true,
          },
        }
        make_object(Map([]), Null, None, "Object", descriptors, true)
      }
    },
  )
  let iterator = make_object(
    { "next": next },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  iterator_ref.val = iterator
  let iterator_method = make_method_func(
    name="@@iterator",
    realm_state=Some(interp.realm_state),
    fn(this_value, _args) raise {
      assert_true(physical_equal(this_value, iterable_ref.val))
      events.push("iterator")
      iterator
    },
  )
  let iterable = make_plain_object()
  iterable_ref.val = iterable
  match iterable {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.iterator.id] = iterator_method
    _ => fail("iterable fixture must be an object")
  }
  let values = run_executor_iterable_spread_for_wb(interp, iterable)
  assert_spread_numbers_for_wb(values, [0.0, 1.0])
  json_inspect(events, content=[
    "iterator", "next0", "done0", "value0", "next1", "done1", "value1", "next2",
  ])
}

///|
test "managed iterable spread does not perform IteratorClose on abrupt steps" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let return_method = make_method_func(
    name="return",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      events.push("return")
      create_iter_result(Undefined, true)
    },
  )
  let next_method = make_method_func(
    name="next",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) raise {
      events.push("next")
      raise @errors.TypeError(message="next failed")
    },
  )
  let iterator = make_object(
    { "next": next_method, "return": return_method },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let iterator_method = make_method_func(
    name="@@iterator",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { iterator },
  )
  let iterable = make_plain_object()
  match iterable {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.iterator.id] = iterator_method
    _ => fail("iterable fixture must be an object")
  }
  try {
    let _ = run_executor_iterable_spread_for_wb(interp, iterable)
    fail("abrupt iterator step must raise")
  } catch {
    @errors.TypeError(_) => ()
    error => raise error
  }
  json_inspect(events, content=["next"])
}

///|
test "managed iterable spread rejects an explicit array iterator override" {
  let interp = Interpreter::new()
  let iterable = make_array([Number(1.0)])
  match iterable {
    Array(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.iterator.id] = Undefined
    _ => fail("array fixture must be an array")
  }
  try {
    let _ = run_executor_iterable_spread_for_wb(interp, iterable)
    fail("explicit undefined Symbol.iterator must raise")
  } catch {
    @errors.TypeError(_) => ()
    error => raise error
  }
}

///|
test "default symbol lookup honors Map and Set prototype overrides" {
  let interp = Interpreter::new()
  let iterator_sym = interp.realm_state.well_known_symbols.iterator
  let map_iterator = make_method_func(
    name="map iterator override",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { Undefined },
  )
  let set_iterator = make_method_func(
    name="set iterator override",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { Undefined },
  )
  let map_proto = make_plain_object()
  let set_proto = make_plain_object()
  match map_proto {
    Object(data) => data.bag.symbol_properties[iterator_sym.id] = map_iterator
    _ => fail("Map prototype fixture must be an object")
  }
  match set_proto {
    Object(data) => data.bag.symbol_properties[iterator_sym.id] = set_iterator
    _ => fail("Set prototype fixture must be an object")
  }
  let map = Map(MapData([], prototype=Some(map_proto)))
  let set = Set(SetData([], prototype=Some(set_proto)))
  let map_result = interp.get_computed_property(
    map,
    Symbol(iterator_sym),
    @token.Loc::default(),
  )
  let set_result = interp.get_computed_property(
    set,
    Symbol(iterator_sym),
    @token.Loc::default(),
  )
  assert_true(physical_equal(map_result, map_iterator))
  assert_true(physical_equal(set_result, set_iterator))
}

///|
test "default symbol lookup shadows getterless accessors" {
  let interp = Interpreter::new()
  let iterator_sym = interp.realm_state.well_known_symbols.iterator
  let inherited = make_method_func(
    name="inherited iterator",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { Undefined },
  )
  let proto = make_plain_object()
  match proto {
    Object(data) => data.bag.symbol_properties[iterator_sym.id] = inherited
    _ => fail("prototype fixture must be an object")
  }
  let setter = make_method_func(
    name="setter",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { Undefined },
  )
  let setter_only = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: Some(setter),
    is_accessor: true,
  }
  let getter_undefined = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: true,
  }
  let object_setter = make_object(Map([]), proto, None, "Object", Map([]), true)
  let object_getter_undefined = make_object(
    Map([]),
    proto,
    None,
    "Object",
    Map([]),
    true,
  )
  let array_setter = make_array([])
  let array_getter_undefined = make_array([])
  let map_setter = Map(MapData([]))
  let map_getter_undefined = Map(MapData([]))
  let set_setter = Set(SetData([]))
  let set_getter_undefined = Set(SetData([]))
  match object_setter {
    Object(data) => data.bag.symbol_descriptors[iterator_sym.id] = setter_only
    _ => fail("Object fixture must be an object")
  }
  match object_getter_undefined {
    Object(data) =>
      data.bag.symbol_descriptors[iterator_sym.id] = getter_undefined
    _ => fail("Object fixture must be an object")
  }
  match array_setter {
    Array(data) => data.bag.symbol_descriptors[iterator_sym.id] = setter_only
    _ => fail("Array fixture must be an array")
  }
  match array_getter_undefined {
    Array(data) =>
      data.bag.symbol_descriptors[iterator_sym.id] = getter_undefined
    _ => fail("Array fixture must be an array")
  }
  match map_setter {
    Map(data) => data.bag.symbol_descriptors[iterator_sym.id] = setter_only
    _ => fail("Map fixture must be a Map")
  }
  match map_getter_undefined {
    Map(data) => data.bag.symbol_descriptors[iterator_sym.id] = getter_undefined
    _ => fail("Map fixture must be a Map")
  }
  match set_setter {
    Set(data) => data.bag.symbol_descriptors[iterator_sym.id] = setter_only
    _ => fail("Set fixture must be a Set")
  }
  match set_getter_undefined {
    Set(data) => data.bag.symbol_descriptors[iterator_sym.id] = getter_undefined
    _ => fail("Set fixture must be a Set")
  }
  let key = Symbol(iterator_sym)
  let loc = @token.Loc::default()
  assert_true(
    interp.get_computed_property(object_setter, key, loc) is Undefined,
  )
  assert_true(
    interp.get_computed_property(object_getter_undefined, key, loc) is Undefined,
  )
  assert_true(interp.get_computed_property(array_setter, key, loc) is Undefined)
  assert_true(
    interp.get_computed_property(array_getter_undefined, key, loc) is Undefined,
  )
  assert_true(interp.get_computed_property(map_setter, key, loc) is Undefined)
  assert_true(
    interp.get_computed_property(map_getter_undefined, key, loc) is Undefined,
  )
  assert_true(interp.get_computed_property(set_setter, key, loc) is Undefined)
  assert_true(
    interp.get_computed_property(set_getter_undefined, key, loc) is Undefined,
  )
}

///|
test "bare Map and Set fallback cannot bypass getterless own iterators" {
  let iterator_marker = make_method_func(
    name="intrinsic fallback marker",
    realm_state=None,
    fn(_this_value, _args) { Undefined },
  )
  let hooks = {
    ..default_stdlib_hooks(),
    get_map_method: fn(_data, _prop, _realm_state) { iterator_marker },
    get_set_method: fn(_data, _prop, _realm_state) { iterator_marker },
  }
  let interp = Interpreter::new(stdlib_hooks=hooks)
  let iterator_sym = interp.realm_state.well_known_symbols.iterator
  let setter = make_method_func(
    name="setter",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { Undefined },
  )
  let setter_only = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: Some(setter),
    is_accessor: true,
  }
  let map = Map(MapData([]))
  let set = Set(SetData([]))
  match map {
    Map(data) => data.bag.symbol_descriptors[iterator_sym.id] = setter_only
    _ => fail("Map fixture must be a Map")
  }
  match set {
    Set(data) => data.bag.symbol_descriptors[iterator_sym.id] = setter_only
    _ => fail("Set fixture must be a Set")
  }
  let key = Symbol(iterator_sym)
  let loc = @token.Loc::default()
  assert_true(interp.get_computed_property(map, key, loc) is Undefined)
  assert_true(interp.get_computed_property(set, key, loc) is Undefined)
}

///|
test "tree-walker spread uses the bare Map iterator hook" {
  let map_ref : Ref[Value] = { val: Undefined }
  let method_calls : Ref[Int] = { val: 0 }
  let hooks = {
    ..default_stdlib_hooks(),
    get_map_method: fn(_data, prop, realm_state) {
      guard prop == "entries" else { return Undefined }
      make_method_func(name="bare map entries", realm_state=Some(realm_state), fn(
        this_value,
        _args,
      ) raise {
        method_calls.val += 1
        assert_true(physical_equal(this_value, map_ref.val))
        let next = make_method_func(
          name="bare map next",
          realm_state=Some(realm_state),
          fn(_iterator, _next_args) { create_iter_result(Undefined, true) },
        )
        make_object({ "next": next }, Null, None, "Object", Map([]), true)
      })
    },
  }
  let interp = Interpreter::new(stdlib_hooks=hooks)
  let map = Map(MapData([]))
  map_ref.val = map
  let values = interp.spread_iterable(map, @token.Loc::default())
  assert_eq(values.length(), 0)
  assert_eq(method_calls.val, 1)
}

///|
test "tree-walker spread uses the bare Set iterator hook" {
  let map_ref : Ref[Value] = { val: Undefined }
  let set_ref : Ref[Value] = { val: Undefined }
  let map_calls : Ref[Int] = { val: 0 }
  let set_calls : Ref[Int] = { val: 0 }
  let interp = Interpreter::new(
    stdlib_hooks=bare_map_set_hooks_for_wb(
      map_ref, set_ref, map_calls, set_calls,
    ),
  )
  let set = Set(SetData([]))
  set_ref.val = set
  let values = interp.spread_iterable(set, @token.Loc::default())
  assert_eq(values.length(), 0)
  assert_eq(set_calls.val, 1)
  assert_eq(map_calls.val, 0)
}

///|
test "managed iterable spread uses bare Map and Set iterator hooks" {
  let map_ref : Ref[Value] = { val: Undefined }
  let set_ref : Ref[Value] = { val: Undefined }
  let map_calls : Ref[Int] = { val: 0 }
  let set_calls : Ref[Int] = { val: 0 }
  let interp = Interpreter::new(
    stdlib_hooks=bare_map_set_hooks_for_wb(
      map_ref, set_ref, map_calls, set_calls,
    ),
  )
  let map = Map(MapData([]))
  let set = Set(SetData([]))
  map_ref.val = map
  set_ref.val = set
  let map_values = run_executor_iterable_spread_for_wb(interp, map)
  let set_values = run_executor_iterable_spread_for_wb(interp, set)
  assert_eq(map_values.length(), 0)
  assert_eq(set_values.length(), 0)
  assert_eq(map_calls.val, 1)
  assert_eq(set_calls.val, 1)
}

///|
test "managed bare Map fallback defers a Proxy method to call activation" {
  let map_ref : Ref[Value] = { val: Undefined }
  let method_ref : Ref[Value] = { val: Undefined }
  let method_calls : Ref[Int] = { val: 0 }
  let hooks = {
    ..default_stdlib_hooks(),
    get_map_method: fn(_data, prop, realm_state) {
      guard prop == "entries" else { return Undefined }
      let target = make_method_func(
        name="bare Map Proxy target",
        realm_state=Some(realm_state),
        fn(this_value, _args) raise {
          method_calls.val += 1
          assert_true(physical_equal(this_value, map_ref.val))
          let next = make_method_func(
            name="bare Map Proxy next",
            realm_state=Some(realm_state),
            fn(_iterator, _next_args) { create_iter_result(Undefined, true) },
          )
          make_object({ "next": next }, Null, None, "Object", Map([]), true)
        },
      )
      let proxy = Proxy({
        target: Some(target),
        handler: Some(make_plain_object()),
        is_callable: true,
        is_constructor: false,
      })
      method_ref.val = proxy
      proxy
    },
  }
  let interp = Interpreter::new(stdlib_hooks=hooks)
  let map = Map(MapData([]))
  map_ref.val = map
  let loc = @token.Loc::default()
  let request = ExecutorIterableSpreadRequest(iterable=map, loc~)
  let frame = ExecutorIterableSpreadFrame(request)
  frame.phase = ExecutorIterableSpreadHaveIteratorMethod(map, Undefined)
  let step = frame.step_frame(interp)
  match step {
    ExecutorActivationCall(call_request) => {
      assert_true(physical_equal(call_request.callee, method_ref.val))
      assert_true(physical_equal(call_request.this_value, map))
      assert_true(call_request.loc == loc)
    }
    _ => fail("bare Map fallback must defer callable invocation")
  }
  assert_eq(method_calls.val, 0)
  let values = run_executor_iterable_spread_for_wb(interp, map)
  assert_eq(values.length(), 0)
  assert_eq(method_calls.val, 1)
}

///|
test "tree-walker bare Map fallback invokes the deferred Proxy method" {
  let map_ref : Ref[Value] = { val: Undefined }
  let method_calls : Ref[Int] = { val: 0 }
  let hooks = {
    ..default_stdlib_hooks(),
    get_map_method: fn(_data, prop, realm_state) {
      guard prop == "entries" else { return Undefined }
      let target = make_method_func(
        name="tree bare Map Proxy target",
        realm_state=Some(realm_state),
        fn(this_value, _args) raise {
          method_calls.val += 1
          assert_true(physical_equal(this_value, map_ref.val))
          let next = make_method_func(
            name="tree bare Map Proxy next",
            realm_state=Some(realm_state),
            fn(_iterator, _next_args) { create_iter_result(Undefined, true) },
          )
          make_object({ "next": next }, Null, None, "Object", Map([]), true)
        },
      )
      Proxy({
        target: Some(target),
        handler: Some(make_plain_object()),
        is_callable: true,
        is_constructor: false,
      })
    },
  }
  let interp = Interpreter::new(stdlib_hooks=hooks)
  let map = Map(MapData([]))
  map_ref.val = map
  let values = interp.spread_iterable(map, @token.Loc::default())
  assert_eq(values.length(), 0)
  assert_eq(method_calls.val, 1)
}

///|
test "Map and Set spread fallback respects observable overrides" {
  let fallback_calls : Ref[Int] = { val: 0 }
  let hooks = {
    ..default_stdlib_hooks(),
    get_map_method: fn(_data, _prop, _realm_state) {
      fallback_calls.val += 1
      Undefined
    },
    get_set_method: fn(_data, _prop, _realm_state) {
      fallback_calls.val += 1
      Undefined
    },
  }
  let interp = Interpreter::new(stdlib_hooks=hooks)
  let iterator_sym = interp.realm_state.well_known_symbols.iterator
  let setter = make_method_func(
    name="override setter",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { Undefined },
  )
  let setter_only = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: Some(setter),
    is_accessor: true,
  }
  let map_own = Map(MapData([]))
  match map_own {
    Map(data) => data.bag.symbol_descriptors[iterator_sym.id] = setter_only
    _ => fail("Map fixture must be a Map")
  }
  let map_proto = make_plain_object()
  match map_proto {
    Object(data) => data.bag.symbol_properties[iterator_sym.id] = Undefined
    _ => fail("Map prototype fixture must be an object")
  }
  let map_inherited = Map(MapData([], prototype=Some(map_proto)))
  let getter_calls : Ref[Int] = { val: 0 }
  let getter = make_method_func(
    name="Set iterator getter",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      getter_calls.val += 1
      Undefined
    },
  )
  let set_proto = make_plain_object()
  match set_proto {
    Object(data) =>
      data.bag.symbol_descriptors[iterator_sym.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: Some(getter),
        setter: None,
        is_accessor: true,
      }
    _ => fail("Set prototype fixture must be an object")
  }
  let set_inherited = Set(SetData([], prototype=Some(set_proto)))
  let set_own = Set(SetData([]))
  match set_own {
    Set(data) => data.bag.symbol_properties[iterator_sym.id] = Undefined
    _ => fail("Set fixture must be a Set")
  }
  for value in [map_own, map_inherited, set_own, set_inherited] {
    try {
      let _ = interp.spread_iterable(value, @token.Loc::default())
      fail("observable collection override must raise")
    } catch {
      @errors.TypeError(_) => ()
      error => raise error
    }
  }
  assert_eq(fallback_calls.val, 0)
  assert_eq(getter_calls.val, 1)
}

///|
test "tree-walker spread deep Array accessor shadows higher iterator" {
  let interp = Interpreter::new()
  let iterator_sym = interp.realm_state.well_known_symbols.iterator
  let higher_calls : Ref[Int] = { val: 0 }
  let next = make_method_func(
    name="next",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { create_iter_result(Undefined, true) },
  )
  let iterator = make_object(
    { "next": next },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let higher_iterator = make_method_func(
    name="higher iterator",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      higher_calls.val += 1
      iterator
    },
  )
  let higher = make_plain_object()
  match higher {
    Object(data) =>
      data.bag.symbol_properties[iterator_sym.id] = higher_iterator
    _ => fail("higher prototype fixture must be an object")
  }
  let deep = make_plain_object()
  match deep {
    Object(data) => {
      data.prototype = higher
      let setter = make_method_func(
        name="setter",
        realm_state=Some(interp.realm_state),
        fn(_this_value, _args) { Undefined },
      )
      data.bag.symbol_descriptors[iterator_sym.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: Some(setter),
        is_accessor: true,
      }
    }
    _ => fail("deep prototype fixture must be an object")
  }
  let array_proto = make_plain_object()
  match array_proto {
    Object(data) => {
      data.prototype = deep
      interp.realm_state.array_prototype.val = Some(array_proto)
    }
    _ => fail("Array prototype fixture must be an object")
  }
  try {
    let _ = interp.spread_iterable(make_array([]), @token.Loc::default())
    fail("deep getterless Array iterator must raise")
  } catch {
    @errors.TypeError(_) => ()
    error => raise error
  }
  assert_eq(higher_calls.val, 0)
}

///|
test "tree-walker spread deep Array getterless iterator is absent" {
  let interp = Interpreter::new()
  let iterator_sym = interp.realm_state.well_known_symbols.iterator
  let higher_calls : Ref[Int] = { val: 0 }
  let higher_iterator = make_method_func(
    name="higher iterator",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      higher_calls.val += 1
      Undefined
    },
  )
  let higher = make_plain_object()
  match higher {
    Object(data) =>
      data.bag.symbol_properties[iterator_sym.id] = higher_iterator
    _ => fail("higher prototype fixture must be an object")
  }
  let deep = make_plain_object()
  match deep {
    Object(data) => {
      data.prototype = higher
      data.bag.symbol_descriptors[iterator_sym.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: true,
      }
    }
    _ => fail("deep prototype fixture must be an object")
  }
  let array_proto = make_plain_object()
  match array_proto {
    Object(data) => {
      data.prototype = deep
      interp.realm_state.array_prototype.val = Some(array_proto)
    }
    _ => fail("Array prototype fixture must be an object")
  }
  try {
    let _ = interp.spread_iterable(make_array([]), @token.Loc::default())
    fail("deep getterless Array iterator must raise")
  } catch {
    @errors.TypeError(_) => ()
    error => raise error
  }
  assert_eq(higher_calls.val, 0)
}

///|
test "tree-walker spread deep Array getter keeps receiver and returned iterator" {
  let interp = Interpreter::new()
  let iterator_sym = interp.realm_state.well_known_symbols.iterator
  let getter_calls : Ref[Int] = { val: 0 }
  let iterator_calls : Ref[Int] = { val: 0 }
  let array_ref : Ref[Value] = { val: Undefined }
  let next = make_method_func(
    name="next",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) { create_iter_result(Undefined, true) },
  )
  let iterator = make_object(
    { "next": next },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let iterator_method = make_method_func(
    name="deep iterator",
    realm_state=Some(interp.realm_state),
    fn(this_value, _args) raise {
      iterator_calls.val += 1
      assert_true(physical_equal(this_value, array_ref.val))
      iterator
    },
  )
  let deep = make_plain_object()
  match deep {
    Object(data) => {
      let getter = make_method_func(
        name="deep iterator getter",
        realm_state=Some(interp.realm_state),
        fn(this_value, _args) raise {
          getter_calls.val += 1
          assert_true(physical_equal(this_value, array_ref.val))
          iterator_method
        },
      )
      data.bag.symbol_descriptors[iterator_sym.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: Some(getter),
        setter: None,
        is_accessor: true,
      }
    }
    _ => fail("deep prototype fixture must be an object")
  }
  let array_proto = make_plain_object()
  match array_proto {
    Object(data) => {
      data.prototype = deep
      interp.realm_state.array_prototype.val = Some(array_proto)
    }
    _ => fail("Array prototype fixture must be an object")
  }
  let array = make_array([])
  array_ref.val = array
  let values = interp.spread_iterable(array, @token.Loc::default())
  assert_eq(values.length(), 0)
  assert_eq(getter_calls.val, 1)
  assert_eq(iterator_calls.val, 1)
}

///|
test "tree-walker spread Promise setter-only iterator shadows inherited callable" {
  let interp = Interpreter::new()
  let iterator_sym = interp.realm_state.well_known_symbols.iterator
  let inherited_calls : Ref[Int] = { val: 0 }
  let inherited_iterator = make_method_func(
    name="inherited promise iterator",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      inherited_calls.val += 1
      Undefined
    },
  )
  let promise_proto = make_plain_object()
  match promise_proto {
    Object(data) =>
      data.bag.symbol_properties[iterator_sym.id] = inherited_iterator
    _ => fail("Promise prototype fixture must be an object")
  }
  interp.realm_state.promise_prototype.val = Some(promise_proto)
  let promise = Promise(new_promise_data())
  match promise {
    Promise(data) => {
      let setter = make_method_func(
        name="promise setter",
        realm_state=Some(interp.realm_state),
        fn(_this_value, _args) { Undefined },
      )
      data.bag.symbol_descriptors[iterator_sym.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: Some(setter),
        is_accessor: true,
      }
    }
    _ => fail("Promise fixture must be a Promise")
  }
  try {
    let _ = interp.spread_iterable(promise, @token.Loc::default())
    fail("Promise getterless iterator must raise")
  } catch {
    @errors.TypeError(_) => ()
    error => raise error
  }
  assert_eq(inherited_calls.val, 0)
}
