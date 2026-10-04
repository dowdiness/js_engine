///| Whitebox tests for Async-from-Sync next argument forwarding.

///|
fn async_from_sync_next_arguments_test_iterator() -> Value {
  make_object(Map([]), Null, None, "Object", Map([]), true)
}

///|
fn async_from_sync_next_arguments_test_call(
  interp : Interpreter,
  wrapper : Value,
  args : Array[Value],
) -> Value raise Error {
  let next = interp.get_property(wrapper, "next", @token.Loc::default())
  interp.call_value(next, wrapper, args, @token.Loc::default())
}

///|
fn async_from_sync_next_arguments_test_promise(
  promise : Value,
) -> Unit raise Error {
  match promise {
    Promise(_) => ()
    _ => fail("expected Async-from-Sync next to return a Promise")
  }
}

///|
test "Async-from-Sync next omits an absent argument" {
  let interp = Interpreter::new()
  let iterator = async_from_sync_next_arguments_test_iterator()
  let receiver : Ref[Value] = { val: Undefined, }
  let argument_count : Ref[Int] = { val: -1, }
  let next = make_method_func(
    name="original next",
    realm_state=Some(interp.realm_state),
    fn(this_val, args) {
      receiver.val = this_val
      argument_count.val = args.length()
      make_iterator_result_object(String_("absent"), false)
    },
  )
  let wrapper = create_async_from_sync_iterator(
    interp,
    iterator,
    next,
    @token.Loc::default(),
  )
  let result = async_from_sync_next_arguments_test_call(interp, wrapper, [])
  assert_true(physical_equal(receiver.val, iterator))
  assert_eq(argument_count.val, 0)
  async_from_sync_next_arguments_test_promise(result)
}

///|
test "Async-from-Sync next forwards an explicit undefined argument" {
  let interp = Interpreter::new()
  let iterator = async_from_sync_next_arguments_test_iterator()
  let receiver : Ref[Value] = { val: Undefined, }
  let argument_count : Ref[Int] = { val: -1, }
  let first_argument : Ref[Value] = { val: Null, }
  let next = make_method_func(
    name="original next",
    realm_state=Some(interp.realm_state),
    fn(this_val, args) {
      receiver.val = this_val
      argument_count.val = args.length()
      first_argument.val = if args.length() > 0 { args[0] } else { Undefined }
      make_iterator_result_object(String_("undefined"), false)
    },
  )
  let wrapper = create_async_from_sync_iterator(
    interp,
    iterator,
    next,
    @token.Loc::default(),
  )
  let result = async_from_sync_next_arguments_test_call(interp, wrapper, [
    Undefined,
  ])
  assert_true(physical_equal(receiver.val, iterator))
  assert_eq(argument_count.val, 1)
  assert_true(first_argument.val is Undefined)
  async_from_sync_next_arguments_test_promise(result)
}

///|
test "Async-from-Sync next forwards only its first argument to the saved method" {
  let interp = Interpreter::new()
  let iterator = async_from_sync_next_arguments_test_iterator()
  let receiver : Ref[Value] = { val: Undefined, }
  let argument_count : Ref[Int] = { val: -1, }
  let first_argument : Ref[Value] = { val: Null, }
  let original_calls : Ref[Int] = { val: 0, }
  let replacement_calls : Ref[Int] = { val: 0, }
  let original_next = make_method_func(
    name="original next",
    realm_state=Some(interp.realm_state),
    fn(this_val, args) {
      original_calls.val += 1
      receiver.val = this_val
      argument_count.val = args.length()
      first_argument.val = if args.length() > 0 { args[0] } else { Undefined }
      make_iterator_result_object(String_("original"), false)
    },
  )
  let replacement_next = make_method_func(
    name="replacement next",
    realm_state=Some(interp.realm_state),
    fn(_this_val, _args) {
      replacement_calls.val += 1
      make_iterator_result_object(String_("replacement"), false)
    },
  )
  let wrapper = create_async_from_sync_iterator(
    interp,
    iterator,
    original_next,
    @token.Loc::default(),
  )
  match iterator {
    Object(data) => data.bag.properties["next"] = replacement_next
    _ => fail("expected sync iterator object")
  }
  let first = make_object(Map([]), Null, None, "First", Map([]), true)
  let extra = make_object(Map([]), Null, None, "Extra", Map([]), true)
  let result = async_from_sync_next_arguments_test_call(interp, wrapper, [
    first, extra,
  ])
  assert_true(physical_equal(receiver.val, iterator))
  assert_eq(original_calls.val, 1)
  assert_eq(replacement_calls.val, 0)
  assert_eq(argument_count.val, 1)
  assert_true(physical_equal(first_argument.val, first))
  async_from_sync_next_arguments_test_promise(result)
}

///|
test "Async-from-Sync next turns a saved method throw into rejection" {
  let interp = Interpreter::new()
  let iterator = async_from_sync_next_arguments_test_iterator()
  let reason = Object({
    bag: PropertyBag(),
    prototype: Null,
    callable: None,
    class_name: "Reason",
    extensible: true,
    arraybuffer_state: None,
  })
  let next = make_method_func(
    name="throwing next",
    realm_state=Some(interp.realm_state),
    fn(_this_val, _args) raise { raise JsException(reason) },
  )
  let wrapper = create_async_from_sync_iterator(
    interp,
    iterator,
    next,
    @token.Loc::default(),
  )
  let promise = async_from_sync_next_arguments_test_call(interp, wrapper, [])
  match promise {
    Promise(data) =>
      match data.state {
        Rejected => assert_true(physical_equal(data.result, reason))
        _ => fail("expected saved next throw to reject the Promise")
      }
    _ => fail("expected throwing next to return a Promise")
  }
}
