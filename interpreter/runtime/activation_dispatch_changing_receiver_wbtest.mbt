///|
fn changing_receiver_fixture(
  next_property : String,
  method_property : String,
) -> (Interpreter, Value, Value) raise Error {
  let interp = Interpreter::new()
  let source = "function target(depth){" +
    "if(depth===0)return 0;" +
    "return 1+this." +
    next_property +
    "." +
    method_property +
    "(depth-1);}" +
    "function Link(next){this." +
    next_property +
    "=next;}" +
    "Link.prototype." +
    method_property +
    "=target;" +
    "var leaf=new Link(null);" +
    "var root=new Link(new Link(leaf));"
  ignore(interp.run(@parser.parse(source).stmts))
  (interp, interp.global.get("target"), interp.global.get("root"))
}

///|
test "changing-receiver lowering is independent of property spellings" {
  for properties in [("next", "walk"), ("tail", "move")] {
    let (next_property, method_property) = properties
    let (interp, callee, receiver) = changing_receiver_fixture(
      next_property, method_property,
    )
    guard interp.preflight_changing_receiver_call(
        callee,
        receiver,
        [Number(2.0)],
        @token.Loc::default(),
      )
      is Some(preflight) else {
      fail("expected semantic changing-receiver admission")
    }
    inspect(preflight.function.plan.next_property, content=next_property)
    inspect(preflight.function.plan.method_property, content=method_property)
  }
}

///|
test "changing-receiver admission rejects unsupported expression semantics" {
  let interp = Interpreter::new()
  ignore(
    interp.run(
      @parser.parse(
        "function target(depth){" +
        "if(depth===0)return 0;" +
        "return 1*this.next.walk(depth-1);}" +
        "function Link(next){this.next=next;}" +
        "Link.prototype.walk=target;" +
        "var root=new Link(new Link(null));",
      ).stmts,
    ),
  )
  inspect(
    interp.preflight_changing_receiver_call(
      interp.global.get("target"),
      interp.global.get("root"),
      [Number(1.0)],
      @token.Loc::default(),
    )
    is None,
    content="true",
  )
}

///|
test "changing-receiver admission rejects observable receiver shapes" {
  let accessor_interp = Interpreter::new()
  ignore(
    accessor_interp.run(
      @parser.parse(
        "function target(depth){" +
        "if(depth===0)return 0;" +
        "return 1+this.next.walk(depth-1);}" +
        "var leaf={};" +
        "var root={get next(){return leaf;}};",
      ).stmts,
    ),
  )
  inspect(
    changing_receiver_own_data_property(
      accessor_interp.global.get("root"),
      "next",
    )
    is None,
    content="true",
  )
  let cases = ["root.walk=target;"]
  for mutation in cases {
    let (interp, callee, receiver) = changing_receiver_fixture("next", "walk")
    let mutation_result : Result[Value, Error] = Ok(
      interp.run(@parser.parse(mutation).stmts),
    ) catch {
      error => Err(error)
    }
    guard mutation_result is Ok(_) else {
      fail("near-miss setup failed: " + mutation)
    }
    inspect(
      interp.preflight_changing_receiver_call(
        callee,
        receiver,
        [Number(2.0)],
        @token.Loc::default(),
      )
      is None,
      content="true",
    )
  }
  let (proxy_interp, proxy_callee, proxy_receiver) = changing_receiver_fixture(
    "next", "walk",
  )
  guard proxy_receiver is Object(proxy_root) else {
    fail("expected an ordinary root receiver")
  }
  let proxy_target = proxy_root.bag.properties["next"]
  let proxy_handler = make_object(Map([]), Null, None, "Object", Map([]), true)
  proxy_root.bag.properties["next"] = Proxy({
    target: Some(proxy_target),
    handler: Some(proxy_handler),
    is_callable: false,
    is_constructor: false,
  })
  inspect(
    proxy_interp.preflight_changing_receiver_call(
      proxy_callee,
      proxy_receiver,
      [Number(2.0)],
      @token.Loc::default(),
    )
    is None,
    content="true",
  )
}

///|
test "changing-receiver dispatch cleans up abrupt calls and supports reuse" {
  let (interp, callee, receiver) = changing_receiver_fixture("next", "walk")
  let first = interp.call_value(
    callee,
    receiver,
    [Number(2.0)],
    @token.Loc::default(),
  )
  inspect(first, content="2")

  let control = ExecutionControl(
    remaining_steps=4,
    maximum_active_depth=10,
    interruption=ExecutionInterruptionRequest(),
  )
  let abrupt = try {
    let _ = interp.with_execution_control(control, () => {
      interp.call_value(callee, receiver, [Number(2.0)], @token.Loc::default())
    })
    "completed"
  } catch {
    ExecutionControlError(ExecutionLimit) => "execution-limit"
    _ => "unexpected-error"
  }
  inspect(abrupt, content="execution-limit")
  inspect(control.active_depth(), content="0")

  let second = interp.call_value(
    callee,
    receiver,
    [Number(1.0)],
    @token.Loc::default(),
  )
  inspect(second, content="1")
}
