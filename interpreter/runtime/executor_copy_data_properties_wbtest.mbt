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
    match
      begin_executor_copy_data_properties(
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
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(_) => ()
    _ => fail("CopyDataProperties root did not return normally")
  }
}

///|
fn expect_copy_data_properties_error_for_wb(
  interp : Interpreter,
  target : Value,
  source : Value,
  expected : Error,
) -> Unit raise Error {
  let caught : Error? = try {
    run_executor_copy_data_properties_for_wb(interp, target, source)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) => assert_true(physical_equal(error, expected))
    None => fail("CopyDataProperties unexpectedly completed")
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
    interp.get_computed_property(
      target,
      String_("shown"),
      @token.Loc::default(),
    ),
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
  run_executor_copy_data_properties_for_wb_excluded(interp, target, source, [
    String_("a"),
  ])
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
    if key == "a" {
      Number(10.0)
    } else {
      Number(20.0)
    }
  })
  let handler = make_object(
    { "ownKeys": own_keys, "getOwnPropertyDescriptor": get_own, "get": get },
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
  json_inspect(events, content=[
    "ownKeys", "descriptor:a", "get:a", "descriptor:b", "get:b",
  ])
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

///|
test "managed Proxy ownKeys reads array-like length and indices through Get" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let target = make_object(
    { "a": Number(7.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let array_like = make_object(
    Map([]),
    Null,
    None,
    "Object",
    {
      "length": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: Some(
          make_method_func(
            name="length getter",
            realm_state=Some(interp.realm_state),
            fn(_receiver, _args) {
              events.push("length")
              Number(1.0)
            },
          ),
        ),
        setter: None,
        is_accessor: true,
      },
      "0": {
        writable: false,
        enumerable: true,
        configurable: true,
        getter: Some(
          make_method_func(
            name="index getter",
            realm_state=Some(interp.realm_state),
            fn(_receiver, _args) {
              events.push("index")
              String_("a")
            },
          ),
        ),
        setter: None,
        is_accessor: true,
      },
    },
    true,
  )
  let own_keys = make_native_func(name="ownKeys", fn(_args) {
    events.push("ownKeys")
    array_like
  })
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
  run_executor_copy_data_properties_for_wb(interp, output, source)
  json_inspect(events, content=["ownKeys", "length", "index"])
  inspect(
    interp.get_computed_property(output, String_("a"), @token.Loc::default()),
    content="7",
  )
}

///|
test "managed CopyDataProperties handles nested Proxy ownKeys exactly once per layer" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let base = make_object(
    { "a": Number(3.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let inner_keys = make_native_func(name="inner ownKeys", _args => {
    events.push("inner")
    make_array([String_("a")])
  })
  let inner_handler = make_object(
    { "ownKeys": inner_keys },
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
  let outer_keys = make_native_func(name="outer ownKeys", _args => {
    events.push("outer")
    make_array([String_("a")])
  })
  let outer_handler = make_object(
    { "ownKeys": outer_keys },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let source = Proxy({
    target: Some(inner),
    handler: Some(outer_handler),
    is_callable: false,
    is_constructor: false,
  })
  let output = make_object(Map([]), Null, None, "Object", Map([]), true)
  run_executor_copy_data_properties_for_wb(interp, output, source)
  json_inspect(events, content=["outer", "inner"])
  inspect(
    interp.get_computed_property(output, String_("a"), @token.Loc::default()),
    content="3",
  )
}

///|
test "managed CopyDataProperties rejects revoked Proxy sources" {
  let interp = Interpreter::new()
  let source = Proxy({
    target: None,
    handler: None,
    is_callable: false,
    is_constructor: false,
  })
  let output = make_object(Map([]), Null, None, "Object", Map([]), true)
  try {
    run_executor_copy_data_properties_for_wb(interp, output, source)
    fail("revoked Proxy source must raise")
  } catch {
    @errors.TypeError(_) => ()
    error => raise error
  }
}

///|
test "managed CopyDataProperties enforces non-configurable Proxy ownKeys invariants" {
  let interp = Interpreter::new()
  let target = make_object(
    { "a": Number(1.0) },
    Null,
    None,
    "Object",
    {
      "a": {
        writable: false,
        enumerable: true,
        configurable: false,
        getter: None,
        setter: None,
        is_accessor: false,
      },
    },
    true,
  )
  let own_keys = make_native_func(name="ownKeys", _args => make_array([]))
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
    fail("missing non-configurable key must raise")
  } catch {
    @errors.TypeError(_) => ()
    error => raise error
  }
}

///|
test "managed CopyDataProperties keeps one key snapshot across source mutation" {
  let interp = Interpreter::new()
  let source_ref : Ref[Value] = { val: Undefined }
  let getter = make_method_func(
    name="mutating source getter",
    realm_state=Some(interp.realm_state),
    fn(_receiver, _args) {
      match source_ref.val {
        Object(data) => {
          data.bag.properties.remove("b")
          data.bag.properties["d"] = Number(4.0)
          match data.bag.descriptors.get("c") {
            Some(descriptor) => {
              let changed = descriptor
              changed.enumerable = false
              data.bag.descriptors["c"] = changed
            }
            None => ()
          }
        }
        _ => ()
      }
      Number(1.0)
    },
  )
  let source = make_object(
    { "a": Undefined, "b": Number(2.0), "c": Number(3.0) },
    Null,
    None,
    "Object",
    {
      "a": {
        writable: false,
        enumerable: true,
        configurable: true,
        getter: Some(getter),
        setter: None,
        is_accessor: true,
      },
      "c": {
        writable: true,
        enumerable: true,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      },
    },
    true,
  )
  source_ref.val = source
  let output = make_object(Map([]), Null, None, "Object", Map([]), true)
  run_executor_copy_data_properties_for_wb(interp, output, source)
  inspect(
    interp.get_computed_property(output, String_("a"), @token.Loc::default()),
    content="1",
  )
  assert_true(interp.get_own_property(output, String_("b")) is None)
  assert_true(interp.get_own_property(output, String_("c")) is None)
  assert_true(interp.get_own_property(output, String_("d")) is None)
}

///|
test "managed CopyDataProperties creates data properties for proto-named and symbol keys" {
  let interp = Interpreter::new()
  let setter_calls : Ref[Int] = { val: 0 }
  let inherited_setter = make_method_func(
    name="inherited proto setter",
    realm_state=Some(interp.realm_state),
    fn(_receiver, _args) {
      setter_calls.val += 1
      Undefined
    },
  )
  let prototype = make_object(
    Map([]),
    Null,
    None,
    "Object",
    {
      "__proto__": {
        writable: false,
        enumerable: true,
        configurable: true,
        getter: None,
        setter: Some(inherited_setter),
        is_accessor: true,
      },
    },
    true,
  )
  let target = make_object(Map([]), prototype, None, "Object", Map([]), true)
  let symbol = interp.realm_state.symbols.new_symbol(Some("copy"))
  let source = make_object(
    { "__proto__": Number(1.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  match source {
    Object(data) => data.bag.symbol_properties[symbol.id] = Number(2.0)
    _ => fail("source must be an object")
  }
  run_executor_copy_data_properties_for_wb(interp, target, source)
  inspect(setter_calls.val, content="0")
  inspect(
    interp.get_computed_property(
      target,
      String_("__proto__"),
      @token.Loc::default(),
    ),
    content="1",
  )
  inspect(
    interp.get_computed_property(target, Symbol(symbol), @token.Loc::default()),
    content="2",
  )
  match interp.get_own_property(target, String_("__proto__")) {
    Some((descriptor, _)) => assert_true(!descriptor.is_accessor)
    None => fail("proto-named source key must become an own data property")
  }
}

///|
test "managed CopyDataProperties preserves abrupt ownKeys failure without replay" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let sentinel = @errors.TypeError(message="ownKeys failed")
  let target = make_object(
    { "a": Number(0.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let own_keys = make_native_func(name="throwing ownKeys", fn(_args) raise {
    events.push("ownKeys")
    raise sentinel
  })
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
  expect_copy_data_properties_error_for_wb(interp, output, source, sentinel)
  json_inspect(events, content=["ownKeys"])
  assert_true(interp.get_own_property(output, String_("a")) is None)
}

///|
test "managed CopyDataProperties preserves abrupt trap-result Get failure" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let sentinel = @errors.TypeError(message="trap result length failed")
  let target = make_object(
    { "a": Number(0.0), "b": Number(0.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let length_getter = make_method_func(
    name="throwing ownKeys length",
    realm_state=Some(interp.realm_state),
    fn(_this, _args) raise {
      events.push("length")
      raise sentinel
    },
  )
  let trap_result = make_object(
    Map([]),
    Null,
    None,
    "Object",
    {
      "length": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: Some(length_getter),
        setter: None,
        is_accessor: true,
      },
    },
    true,
  )
  let own_keys = make_native_func(name="array-like ownKeys", fn(_args) {
    events.push("ownKeys")
    trap_result
  })
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
  expect_copy_data_properties_error_for_wb(interp, output, source, sentinel)
  json_inspect(events, content=["ownKeys", "length"])
  assert_true(interp.get_own_property(output, String_("a")) is None)
  assert_true(interp.get_own_property(output, String_("b")) is None)
}

///|
test "managed CopyDataProperties preserves abrupt trap-result index Get failure" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let sentinel = @errors.TypeError(message="trap result index failed")
  let target = make_object(
    { "a": Number(7.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let index_getter = make_method_func(
    name="throwing ownKeys index",
    realm_state=Some(interp.realm_state),
    fn(_this, _args) raise {
      events.push("index")
      raise sentinel
    },
  )
  let trap_result = make_object(
    Map([]),
    Null,
    None,
    "Object",
    {
      "length": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: Some(
          make_method_func(
            name="ownKeys length",
            realm_state=Some(interp.realm_state),
            fn(_this, _args) {
              events.push("length")
              Number(1.0)
            },
          ),
        ),
        setter: None,
        is_accessor: true,
      },
      "0": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: Some(index_getter),
        setter: None,
        is_accessor: true,
      },
    },
    true,
  )
  let own_keys = make_native_func(name="array-like ownKeys", fn(_args) {
    events.push("ownKeys")
    trap_result
  })
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
  expect_copy_data_properties_error_for_wb(interp, output, source, sentinel)
  json_inspect(events, content=["ownKeys", "length", "index"])
  assert_true(interp.get_own_property(output, String_("a")) is None)
}

///|
test "managed CopyDataProperties retains a after descriptor trap failure on b" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let sentinel = @errors.TypeError(message="descriptor trap failed on b")
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
  let get_own = make_native_func(name="descriptor trap", fn(args) raise {
    let key = match args[1] {
      String_(name) => name
      _ => "?"
    }
    events.push("descriptor:" + key)
    if key == "b" {
      raise sentinel
    }
    make_object(
      { "enumerable": Bool(true), "configurable": Bool(true) },
      Null,
      None,
      "Object",
      Map([]),
      true,
    )
  })
  let get = make_native_func(name="source get", fn(args) {
    let key = match args[1] {
      String_(name) => name
      _ => "?"
    }
    events.push("get:" + key)
    Number(10.0)
  })
  let handler = make_object(
    { "ownKeys": own_keys, "getOwnPropertyDescriptor": get_own, "get": get },
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
  expect_copy_data_properties_error_for_wb(interp, output, source, sentinel)
  json_inspect(events, content=[
    "ownKeys", "descriptor:a", "get:a", "descriptor:b",
  ])
  inspect(
    interp.get_computed_property(output, String_("a"), @token.Loc::default()),
    content="10",
  )
  assert_true(interp.get_own_property(output, String_("b")) is None)
}

///|
test "managed CopyDataProperties retains a after descriptor getter failure on b" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let sentinel = @errors.TypeError(message="descriptor getter failed on b")
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
  let enumerable_getter = make_method_func(
    name="descriptor enumerable getter",
    realm_state=Some(interp.realm_state),
    fn(_this, _args) raise {
      events.push("enumerable:b")
      raise sentinel
    },
  )
  let get_own = make_native_func(name="descriptor trap", fn(args) {
    let key = match args[1] {
      String_(name) => name
      _ => "?"
    }
    events.push("descriptor:" + key)
    if key == "b" {
      make_object(
        Map([]),
        Null,
        None,
        "Object",
        {
          "enumerable": {
            writable: false,
            enumerable: false,
            configurable: true,
            getter: Some(enumerable_getter),
            setter: None,
            is_accessor: true,
          },
        },
        true,
      )
    } else {
      make_object(
        { "enumerable": Bool(true), "configurable": Bool(true) },
        Null,
        None,
        "Object",
        Map([]),
        true,
      )
    }
  })
  let get = make_native_func(name="source get", fn(args) {
    let key = match args[1] {
      String_(name) => name
      _ => "?"
    }
    events.push("get:" + key)
    Number(10.0)
  })
  let handler = make_object(
    { "ownKeys": own_keys, "getOwnPropertyDescriptor": get_own, "get": get },
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
  expect_copy_data_properties_error_for_wb(interp, output, source, sentinel)
  json_inspect(events, content=[
    "ownKeys", "descriptor:a", "get:a", "descriptor:b", "enumerable:b",
  ])
  inspect(
    interp.get_computed_property(output, String_("a"), @token.Loc::default()),
    content="10",
  )
  assert_true(interp.get_own_property(output, String_("b")) is None)
}

///|
test "managed CopyDataProperties retains a after source Proxy get failure on b" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let sentinel = @errors.TypeError(message="source get failed on b")
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
  let get_own = make_native_func(name="descriptor trap", fn(args) {
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
  let get = make_native_func(name="source get", fn(args) raise {
    let key = match args[1] {
      String_(name) => name
      _ => "?"
    }
    events.push("get:" + key)
    if key == "b" {
      raise sentinel
    }
    Number(10.0)
  })
  let handler = make_object(
    { "ownKeys": own_keys, "getOwnPropertyDescriptor": get_own, "get": get },
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
  expect_copy_data_properties_error_for_wb(interp, output, source, sentinel)
  json_inspect(events, content=[
    "ownKeys", "descriptor:a", "get:a", "descriptor:b", "get:b",
  ])
  inspect(
    interp.get_computed_property(output, String_("a"), @token.Loc::default()),
    content="10",
  )
  assert_true(interp.get_own_property(output, String_("b")) is None)
}
