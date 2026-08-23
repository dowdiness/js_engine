///|
fn array_includes_observation_probe(
  trace : Ref[Array[String]],
  raises : Bool,
) -> Value {
  @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-959-array-includes-observer", fn(
        _args,
      ) raise {
        trace.val.push("observe")
        if raises {
          raise @errors.TypeError(message="issue-959 observer interrupted")
        }
        Undefined
      }),
    ),
    "Function",
    Map([]),
    true,
  )
}

///|
fn call_array_includes_with_observation_probe(
  array : Value,
  search : Value,
  args : Array[Value],
  trace : Ref[Array[String]],
  raises : Bool,
) -> Value raise Error {
  let interp = @runtime.Interpreter::new(setup_builtins=fn(env, args, rs, ab) {
    setup_builtins_with_realm_state(env, args, rs, annex_b=ab)
  })
  interp.global.def(
    "[[ExecutionControl]]",
    array_includes_observation_probe(trace, raises),
    VarBinding,
  )
  let includes = interp.get_property(array, "includes", @token.Loc::default())
  let call_args = Array::makei(args.length() + 1, i => {
    if i == 0 {
      search
    } else {
      args[i - 1]
    }
  })
  interp.call_value(includes, array, call_args, @token.Loc::default())
}

///|
test "Array.includes sparse holes observe each logical index" {
  let trace : Ref[Array[String]] = { val: [] }
  let sparse = @runtime.make_array_with_holes(
    [Undefined, Undefined, Undefined],
    [0, 1, 2],
  )
  match
    call_array_includes_with_observation_probe(
      sparse,
      Number(1.0),
      [],
      trace,
      false,
    ) {
    Bool(value) => inspect(value, content="false")
    _ => fail("Array.includes must return a boolean")
  }
  assert_eq(trace.val.length(), 3)
}

///|
test "Array.includes observes before indexed getter work" {
  let trace : Ref[Array[String]] = { val: [] }
  let getter = @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-959-array-includes-getter", fn(_args) {
        trace.val.push("get")
        Number(1.0)
      }),
    ),
    "Function",
    Map([]),
    true,
  )
  let bag = @runtime.PropertyBag::PropertyBag()
  bag.descriptors["0"] = {
    writable: false,
    enumerable: true,
    configurable: true,
    getter: Some(getter),
    setter: None,
    is_accessor: true,
  }
  let array = Value::Array({
    elements: [Undefined, Undefined],
    bag,
    length_writable: true,
    holes: Map([]),
    extensible: true,
  })
  match
    call_array_includes_with_observation_probe(
      array,
      Number(1.0),
      [],
      trace,
      false,
    ) {
    Bool(value) => inspect(value, content="true")
    _ => fail("Array.includes must return a boolean")
  }
  json_inspect(trace.val, content=["observe", "get"])
}

///|
test "Array.includes observation interrupts before indexed getter work" {
  let trace : Ref[Array[String]] = { val: [] }
  let getter = @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-959-array-includes-raising-getter", fn(
        _args,
      ) {
        trace.val.push("get")
        Number(1.0)
      }),
    ),
    "Function",
    Map([]),
    true,
  )
  let bag = @runtime.PropertyBag::PropertyBag()
  bag.descriptors["0"] = {
    writable: false,
    enumerable: true,
    configurable: true,
    getter: Some(getter),
    setter: None,
    is_accessor: true,
  }
  let array = Value::Array({
    elements: [Undefined],
    bag,
    length_writable: true,
    holes: Map([]),
    extensible: true,
  })
  let completion : Error? = try {
    ignore(
      call_array_includes_with_observation_probe(
        array,
        Number(1.0),
        [],
        trace,
        true,
      ),
    )
    None
  } catch {
    error => Some(error)
  }
  match completion {
    Some(_) => ()
    None => fail("execution observation must interrupt the includes loop")
  }
  json_inspect(trace.val, content=["observe"])
}

///|
test "Array.includes fast returns do not observe" {
  let empty_trace : Ref[Array[String]] = { val: [] }
  let empty = @runtime.make_array([])
  match
    call_array_includes_with_observation_probe(
      empty,
      Undefined,
      [],
      empty_trace,
      false,
    ) {
    Bool(value) => inspect(value, content="false")
    _ => fail("Array.includes must return a boolean")
  }
  json_inspect(empty_trace.val, content=[])

  let bounded_trace : Ref[Array[String]] = { val: [] }
  let array = @runtime.make_array([Undefined, Undefined])
  match
    call_array_includes_with_observation_probe(
      array,
      Undefined,
      [Number(2.0)],
      bounded_trace,
      false,
    ) {
    Bool(value) => inspect(value, content="false")
    _ => fail("Array.includes must return a boolean")
  }
  json_inspect(bounded_trace.val, content=[])

  let infinite_trace : Ref[Array[String]] = { val: [] }
  let infinite_start = @runtime.make_array([Undefined])
  match
    call_array_includes_with_observation_probe(
      infinite_start,
      Undefined,
      [Number(1.0 / 0.0)],
      infinite_trace,
      false,
    ) {
    Bool(value) => inspect(value, content="false")
    _ => fail("Array.includes must return a boolean")
  }
  json_inspect(infinite_trace.val, content=[])
}
