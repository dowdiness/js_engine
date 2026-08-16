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
