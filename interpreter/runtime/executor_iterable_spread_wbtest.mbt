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
  ) as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(batch) => executor_iterable_spread_batch_values(batch)
    _ =>
      fail("iterable spread root must return its completed batch")
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
  let iterator = make_object({ "next": next }, Null, None, "Object", Map([]), true)
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
  json_inspect(
    events,
    content=[
      "iterator",
      "next0",
      "done0",
      "value0",
      "next1",
      "done1",
      "value1",
      "next2",
    ],
  )
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
