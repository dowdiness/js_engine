///|
fn array_index_of_observation_probe_961(
  trace : Ref[Array[String]],
  raises : Bool,
) -> Value {
  @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-961-array-index-of-observer", fn(
        _args,
      ) raise {
        trace.val.push("observe")
        if raises {
          raise @errors.TypeError(message="issue-961 observer interrupted")
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
fn call_array_index_of_with_observation_probe_961(
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
    array_index_of_observation_probe_961(trace, raises),
    VarBinding,
  )
  let index_of = interp.get_property(array, "indexOf", @token.Loc::default())
  let call_args = Array::makei(args.length() + 1, i => {
    if i == 0 {
      search
    } else {
      args[i - 1]
    }
  })
  interp.call_value(index_of, array, call_args, @token.Loc::default())
}

///|
test "Array.indexOf sparse holes observe each logical index" {
  let trace : Ref[Array[String]] = { val: [] }
  let sparse = @runtime.make_array_with_holes(
    [Undefined, Undefined, Undefined],
    [0, 1, 2],
  )
  match
    call_array_index_of_with_observation_probe_961(
      sparse,
      Number(1.0),
      [],
      trace,
      false,
    ) {
    Number(value) => inspect(value, content="-1")
    _ => fail("Array.indexOf must return a number")
  }
  inspect(trace.val.length(), content="3")
}

///|
test "Array.indexOf observes before indexed getter work" {
  let trace : Ref[Array[String]] = { val: [] }
  let getter = @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-961-array-indexof-getter", fn(_args) {
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
    call_array_index_of_with_observation_probe_961(
      array,
      Number(1.0),
      [],
      trace,
      false,
    ) {
    Number(value) => inspect(value, content="0")
    _ => fail("Array.indexOf must return a number")
  }
  json_inspect(trace.val, content=["observe", "get"])
}

///|
test "Array.indexOf observation interrupts before indexed property work" {
  let trace : Ref[Array[String]] = { val: [] }
  let getter = @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-961-array-indexof-raising-getter", fn(
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
      call_array_index_of_with_observation_probe_961(
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
    None => fail("execution observation must interrupt the indexOf loop")
  }
  json_inspect(trace.val, content=["observe"])
}

///|
test "Array.indexOf observation interrupts before Proxy has/get" {
  let trace : Ref[Array[String]] = { val: [] }
  let proxy_events : Ref[Array[String]] = { val: [] }
  let target = @runtime.make_array([Number(1.0)])
  let interp = @runtime.Interpreter::new(setup_builtins=fn(env, args, rs, ab) {
    setup_builtins_with_realm_state(env, args, rs, annex_b=ab)
  })
  interp.global.def(
    "[[ExecutionControl]]",
    array_index_of_observation_probe_961(trace, true),
    VarBinding,
  )
  let get_trap = @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-961-array-indexof-proxy-get", fn(
        args,
      ) raise {
        let key = match args[1] {
          String_(value) => value
          _ => "<non-string>"
        }
        if key != "indexOf" && key != "length" {
          proxy_events.val.push("get:" + key)
        }
        interp.get_property(args[0], key, @token.Loc::default())
      }),
    ),
    "Function",
    Map([]),
    true,
  )
  let has_trap = @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-961-array-indexof-proxy-has", fn(args) {
        let key = match args[1] {
          String_(value) => value
          _ => "<non-string>"
        }
        proxy_events.val.push("has:" + key)
        Bool(true)
      }),
    ),
    "Function",
    Map([]),
    true,
  )
  let handler = @runtime.make_object(
    Map([("get", get_trap), ("has", has_trap)]),
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let proxy = Value::Proxy({
    target: Some(target),
    handler: Some(handler),
    is_callable: false,
    is_constructor: false,
  })
  let completion : Error? = try {
    ignore(
      interp.call_value(
        interp.get_property(proxy, "indexOf", @token.Loc::default()),
        proxy,
        [Number(1.0)],
        @token.Loc::default(),
      ),
    )
    None
  } catch {
    error => Some(error)
  }
  match completion {
    Some(_) => ()
    None => fail("execution observation must interrupt the indexOf loop")
  }
  json_inspect(trace.val, content=["observe"])
  json_inspect(proxy_events.val, content=[])
}

///|
test "Array.indexOf fast returns do not observe" {
  let empty_trace : Ref[Array[String]] = { val: [] }
  let empty = @runtime.make_array([])
  match
    call_array_index_of_with_observation_probe_961(
      empty,
      Undefined,
      [],
      empty_trace,
      false,
    ) {
    Number(value) => inspect(value, content="-1")
    _ => fail("Array.indexOf must return a number")
  }
  json_inspect(empty_trace.val, content=[])

  let bounded_trace : Ref[Array[String]] = { val: [] }
  let array = @runtime.make_array([Undefined, Undefined])
  match
    call_array_index_of_with_observation_probe_961(
      array,
      Undefined,
      [Number(2.0)],
      bounded_trace,
      false,
    ) {
    Number(value) => inspect(value, content="-1")
    _ => fail("Array.indexOf must return a number")
  }
  json_inspect(bounded_trace.val, content=[])

  let infinite_trace : Ref[Array[String]] = { val: [] }
  let infinite_start = @runtime.make_array([Undefined])
  match
    call_array_index_of_with_observation_probe_961(
      infinite_start,
      Undefined,
      [Number(1.0 / 0.0)],
      infinite_trace,
      false,
    ) {
    Number(value) => inspect(value, content="-1")
    _ => fail("Array.indexOf must return a number")
  }
  json_inspect(infinite_trace.val, content=[])
}
