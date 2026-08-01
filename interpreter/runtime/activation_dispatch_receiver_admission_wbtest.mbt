///|
fn receiver_recursion_test_program(source : String) -> Array[@ast.Stmt] raise {
  @parser.parse(source).stmts
}

///|
fn receiver_recursion_exact_source() -> String {
  "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
  "let receiver={marker:0,step:step};receiver.step(256);"
}

///|
test "receiver recursion admission recognizes the exact own-data member call" {
  let stmts = receiver_recursion_test_program(receiver_recursion_exact_source())
  let plan = match classify_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact receiver-recursion shape to be admitted")
  }
  inspect(plan.function_name, content="step")
  inspect(plan.receiver_name, content="receiver")
  inspect(plan.parameter, content="n")
  inspect(plan.property_name, content="step")
  inspect(plan.marker_name, content="marker")
  inspect(plan.initial_argument, content="256")
  inspect(receiver_recursion_plan_is_dispatchable(plan), content="true")
  for index, stmt in stmts {
    guard receiver_recursion_root_statement_matches(plan, index, stmt) else {
      fail("expected every admitted receiver root statement to match")
    }
  }
  let body = match stmts[0] {
    @ast.FuncDecl(_, _, body, _, _) => body
    _ => fail("expected the admitted receiver function declaration")
  }
  for index, stmt in body {
    guard receiver_recursion_body_statement_matches(plan, index, stmt) else {
      fail("expected every admitted receiver body statement to match")
    }
  }
  guard classify_numeric_recursion_program(stmts) is None else {
    fail("receiver and numeric admission must remain disjoint")
  }
  guard classify_getter_recursion_program(stmts) is None else {
    fail("receiver and getter admission must remain disjoint")
  }
  guard classify_proxy_get_recursion_program(stmts) is None else {
    fail("receiver and Proxy admission must remain disjoint")
  }
}

///|
test "receiver recursion admission rejects excluded lookalikes" {
  for
    source in [
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step};receiver.step(255);",
      "function step(n){if(n===0)return this.step;return 1+this.step(n-1);}" +
      "let receiver={step:0,step:step};receiver.step(256);",
      "function __proto__(n){if(n===0)return this.marker;return 1+this.__proto__(n-1);}" +
      "let receiver={marker:0,__proto__:__proto__};receiver.__proto__(256);",
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step,extra:0};receiver.step(256);",
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,get step(){return step;}};receiver.step(256);",
      "let proto={step:step};" +
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,__proto__:proto};receiver.step(256);",
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step};receiver['step'](256);",
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step};receiver?.step(256);",
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver=new Proxy({marker:0,step:step},{});receiver.step(256);",
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,...{step:step}};receiver.step(256);",
      "let step=(n)=>{if(n===0)return this.marker;return 1+this.step(n-1);};" +
      "let receiver={marker:0,step:step};receiver.step(256);",
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step(n){return step(n);}};receiver.step(256);",
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step.bind(null)};receiver.step(256);",
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step.call};receiver.step(256);",
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step.apply};receiver.step(256);",
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:Math.max};receiver.step(256);",
      "async function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step};receiver.step(256);",
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step};receiver.step(256,0);",
      "function step(n){if(n==0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step};receiver.step(256);",
      "function step(n){if(n===0)return this.marker;0;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step};receiver.step(256);",
      "function step(n){if(n===0)return this.marker;return 2+this.step(n-1);}" +
      "let receiver={marker:0,step:step};receiver.step(256);",
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-2);}" +
      "let receiver={marker:0,step:step};receiver.step(256);",
    ] {
    guard classify_receiver_recursion_program(
        receiver_recursion_test_program(source),
      )
      is None else {
      fail("unexpectedly admitted receiver lookalike: " + source)
    }
  }
}
