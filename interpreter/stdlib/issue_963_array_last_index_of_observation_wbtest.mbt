///|
fn array_last_index_of_observation_probe_963(
  trace : Ref[Array[String]],
  raises : Bool,
) -> Value {
  @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-963-array-last-index-of-observer", fn(
        _args,
      ) raise {
        trace.val.push("observe")
        if raises {
          raise @errors.TypeError(message="issue-963 observer interrupted")
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
fn call_array_last_index_of_with_observation_probe_963(
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
    array_last_index_of_observation_probe_963(trace, raises),
    VarBinding,
  )
  let last_index_of = interp.get_property(
    array,
    "lastIndexOf",
    @token.Loc::default(),
  )
  let call_args = Array::makei(args.length() + 1, i => {
    if i == 0 {
      search
    } else {
      args[i - 1]
    }
  })
  interp.call_value(last_index_of, array, call_args, @token.Loc::default())
}

///|
test "Array.lastIndexOf observes every reverse logical index including holes" {
  let trace : Ref[Array[String]] = { val: [] }
  let sparse = @runtime.make_array_with_holes(
    [Undefined, Undefined, Undefined],
    [0, 1, 2],
  )
  match
    call_array_last_index_of_with_observation_probe_963(
      sparse,
      Number(1.0),
      [],
      trace,
      false,
    ) {
    Number(value) => inspect(value, content="-1")
    _ => fail("Array.lastIndexOf must return a number")
  }
  inspect(trace.val.length(), content="3")
}

///|
test "Array.lastIndexOf observes before indexed getter work" {
  let trace : Ref[Array[String]] = { val: [] }
  let getter = @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-963-array-lastindexof-getter", fn(_args) {
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
  match
    call_array_last_index_of_with_observation_probe_963(
      array,
      Number(1.0),
      [],
      trace,
      false,
    ) {
    Number(value) => inspect(value, content="0")
    _ => fail("Array.lastIndexOf must return a number")
  }
  json_inspect(trace.val, content=["observe", "get"])
}

///|
test "Array.lastIndexOf observation interrupts before indexed property work" {
  let trace : Ref[Array[String]] = { val: [] }
  let completion : Error? = try {
    ignore(
      call_array_last_index_of_with_observation_probe_963(
        @runtime.make_array([Number(1.0)]),
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
    None => fail("execution observation must interrupt the lastIndexOf loop")
  }
  json_inspect(trace.val, content=["observe"])
}

///|
test "Array.lastIndexOf observation interrupts before Proxy has and get" {
  let trace : Ref[Array[String]] = { val: [] }
  let has_calls : Ref[Int] = { val: 0 }
  let get_calls : Ref[Int] = { val: 0 }
  let interp = @runtime.Interpreter::new(setup_builtins=fn(env, args, rs, ab) {
    setup_builtins_with_realm_state(env, args, rs, annex_b=ab)
  })
  let target = @runtime.make_array([Number(1.0), Number(2.0)])
  let get_trap = @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-963-array-lastindexof-proxy-get", fn(
        args,
      ) raise {
        let key = match args[1] {
          String_(value) => value
          _ => "<non-string>"
        }
        if key == "0" || key == "1" {
          get_calls.val += 1
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
      NonConstructableCallable("issue-963-array-lastindexof-proxy-has", fn(
        args,
      ) {
        let key = match args[1] {
          String_(value) => value
          _ => "<non-string>"
        }
        if key == "0" || key == "1" {
          has_calls.val += 1
        }
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
  let last_index_of = interp.get_property(
    proxy,
    "lastIndexOf",
    @token.Loc::default(),
  )
  interp.global.def(
    "[[ExecutionControl]]",
    array_last_index_of_observation_probe_963(trace, true),
    VarBinding,
  )
  let completion : Error? = try {
    ignore(
      interp.call_value(
        last_index_of,
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
    None => fail("execution observation must interrupt the lastIndexOf loop")
  }
  json_inspect(trace.val, content=["observe"])
  inspect(has_calls.val, content="0")
  inspect(get_calls.val, content="0")
}
