///|
// Issue #889 runtime-operation RED. The request/frame is intentionally absent
// at the entry-gate baseline; this test becomes the first runtime GREEN slice.

///|
priv struct ExecutorCopyDataPropertiesTestRootFrame {
  target : Value
  source : Value
  excluded_keys : Array[Value]
  loc : @token.Loc
  mut requested : Bool
}

///|
fn ExecutorCopyDataPropertiesTestRootFrame::ExecutorCopyDataPropertiesTestRootFrame(
  target~ : Value,
  source~ : Value,
  excluded_keys~ : Array[Value],
  loc~ : @token.Loc,
) -> ExecutorCopyDataPropertiesTestRootFrame {
  { target, source, excluded_keys: excluded_keys.copy(), loc, requested: false }
}

///|
impl ExecutorActivationFrame for ExecutorCopyDataPropertiesTestRootFrame with fn step(
  self,
  interp,
) {
  if self.requested {
    ExecutorActivationReturn(Undefined)
  } else {
    self.requested = true
    match begin_executor_copy_data_properties(
      interp,
      self.target,
      self.source,
      self.excluded_keys,
      self.loc,
    ) {
      ExecutorCopyDataPropertiesCompleted => ExecutorActivationReturn(Undefined)
      ExecutorCopyDataPropertiesSuspended(request) =>
        executor_activation_copy_data_properties_request(request)
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorCopyDataPropertiesTestRootFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  ignore(self)
  match completion {
    ExecutorActivationCompletionNormal(_) => ()
    ExecutorActivationCompletionAbrupt(error) => raise error
  }
}

///|
fn run_executor_copy_data_properties_for_wb(
  interp : Interpreter,
  target : Value,
  source : Value,
) -> Unit raise Error {
  run_executor_copy_data_properties_for_wb_excluded(interp, target, source, [])
}

///|
fn run_executor_copy_data_properties_for_wb_excluded(
  interp : Interpreter,
  target : Value,
  source : Value,
  excluded_keys : Array[Value],
) -> Unit raise Error {
  let root = ExecutorCopyDataPropertiesTestRootFrame(
    target~,
    source~,
    excluded_keys~,
    loc=@token.Loc::default(),
  ) as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(_) => ()
    _ => fail("CopyDataProperties root did not return normally")
  }
}

///|
test "RED managed CopyDataProperties copies one enumerable own property" {
  let interp = Interpreter::new()
  let target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let source = make_object(
    { "a": Number(1.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  run_executor_copy_data_properties_for_wb(interp, target, source)
  inspect(
    interp.get_computed_property(target, String_("a"), @token.Loc::default()),
    content="1",
  )
}

///|
test "managed CopyDataProperties skips null undefined and non-enumerable values" {
  let interp = Interpreter::new()
  let target = make_object(Map([]), Null, None, "Object", Map([]), true)
  run_executor_copy_data_properties_for_wb(interp, target, Null)
  run_executor_copy_data_properties_for_wb(interp, target, Undefined)
  let source = make_object(
    { "hidden": Number(1.0), "shown": Number(2.0) },
    Null,
    None,
    "Object",
    {
      "hidden": {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      },
    },
    true,
  )
  run_executor_copy_data_properties_for_wb(interp, target, source)
  assert_true(interp.get_own_property(target, String_("hidden")) is None)
  assert_true(interp.get_own_property(target, String_("shown")) is Some(_))
  inspect(
    interp.get_computed_property(target, String_("shown"), @token.Loc::default()),
    content="2",
  )
}

///|
test "managed CopyDataProperties applies immutable exclusions before descriptor reads" {
  let interp = Interpreter::new()
  let target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let source = make_object(
    { "a": Number(1.0), "b": Number(2.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  run_executor_copy_data_properties_for_wb_excluded(
    interp,
    target,
    source,
    [String_("a")],
  )
  assert_true(interp.get_own_property(target, String_("a")) is None)
  inspect(
    interp.get_computed_property(target, String_("b"), @token.Loc::default()),
    content="2",
  )
}

///|
test "managed CopyDataProperties copies string primitive own enumerable indices" {
  let interp = Interpreter::new()
  let target = make_object(Map([]), Null, None, "Object", Map([]), true)
  run_executor_copy_data_properties_for_wb(interp, target, String_("ab"))
  inspect(
    interp.get_computed_property(target, String_("0"), @token.Loc::default()),
    content="a",
  )
  inspect(
    interp.get_computed_property(target, String_("1"), @token.Loc::default()),
    content="b",
  )
  assert_true(interp.get_own_property(target, String_("length")) is None)
}

///|
test "managed CopyDataProperties preserves Proxy ownKeys descriptor get write order" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let target = make_object(
    { "a": Number(1.0), "b": Number(2.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let own_keys = make_native_func(name="ownKeys", fn(_args) {
    events.push("ownKeys")
    make_array([String_("a"), String_("b")])
  })
  let get_own = make_native_func(name="getOwnPropertyDescriptor", fn(args) {
    let key = match args[1] {
      String_(name) => name
      _ => "?"
    }
    events.push("descriptor:" + key)
    make_object(
      { "enumerable": Bool(true), "configurable": Bool(true) },
      Null,
      None,
      "Object",
      Map([]),
      true,
    )
  })
  let get = make_native_func(name="get", fn(args) {
    let key = match args[1] {
      String_(name) => name
      _ => "?"
    }
    events.push("get:" + key)
    if key == "a" { Number(10.0) } else { Number(20.0) }
  })
  let handler = make_object(
    {
      "ownKeys": own_keys,
      "getOwnPropertyDescriptor": get_own,
      "get": get,
    },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let source = Proxy({
    target: Some(target),
    handler: Some(handler),
    is_callable: false,
    is_constructor: false,
  })
  let output = make_object(Map([]), Null, None, "Object", Map([]), true)
  run_executor_copy_data_properties_for_wb(interp, output, source)
  json_inspect(
    events,
    content=[
      "ownKeys",
      "descriptor:a",
      "get:a",
      "descriptor:b",
      "get:b",
    ],
  )
  inspect(
    interp.get_computed_property(output, String_("a"), @token.Loc::default()),
    content="10",
  )
  inspect(
    interp.get_computed_property(output, String_("b"), @token.Loc::default()),
    content="20",
  )
}

///|
test "managed CopyDataProperties rejects duplicate Proxy ownKeys entries" {
  let interp = Interpreter::new()
  let own_keys = make_native_func(name="ownKeys", _args => {
    make_array([String_("a"), String_("a")])
  })
  let target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let handler = make_object(
    { "ownKeys": own_keys },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let source = Proxy({
    target: Some(target),
    handler: Some(handler),
    is_callable: false,
    is_constructor: false,
  })
  let output = make_object(Map([]), Null, None, "Object", Map([]), true)
  try {
    run_executor_copy_data_properties_for_wb(interp, output, source)
    fail("duplicate ownKeys entries must raise")
  } catch {
    @errors.TypeError(_) => ()
    error => raise error
  }
}
