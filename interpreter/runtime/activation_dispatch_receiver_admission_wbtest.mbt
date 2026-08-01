///|
fn receiver_recursion_test_program(source : String) -> Array[@ast.Stmt] raise {
  @parser.parse(source).stmts
}

///|
fn receiver_recursion_source_is_admitted(source : String) -> Bool {
  try (
    classify_receiver_recursion_program(receiver_recursion_test_program(source))
    is Some(_)
  ) catch {
    _ => false
  }
}

///|
fn receiver_recursion_exact_source() -> String {
  "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
  "let receiver={marker:0,step:step};receiver.step(256);"
}

///|
fn receiver_recursion_exact_computed_source() -> String {
  "function step(n){if(n===0)return this[\"marker\"];return 1+this[\"step\"](n-1);}" +
  "let receiver={[\"marker\"]:0,[\"step\"]:step};receiver[\"step\"](256);"
}

///|
fn receiver_recursion_exact_escaped_computed_source() -> String {
  "function step(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x73tep\"](n-1);}" +
  "let receiver={[\"\\x6darker\"]:0,[\"\\x73tep\"]:step};receiver[\"\\x73tep\"](256);"
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
test "receiver recursion admission recognizes all-escaped computed literals" {
  let stmts = receiver_recursion_test_program(
    receiver_recursion_exact_escaped_computed_source(),
  )
  let plan = match classify_receiver_recursion_program(stmts) {
    Some(found) => found
    None =>
      fail(
        "expected the escaped computed receiver-recursion shape to be admitted",
      )
  }
  let accesses = [
    plan.recipe.marker_property_access,
    plan.recipe.property_access,
    plan.recipe.marker_access,
    plan.recipe.recursive_access,
    plan.recipe.root_access,
  ]
  for access in accesses {
    match access {
      ReceiverRecursionComputedLiteral(_, has_escape) =>
        inspect(has_escape, content="true")
      ReceiverRecursionStatic =>
        fail("expected every escaped receiver access to be computed")
    }
  }
  inspect(receiver_recursion_plan_is_dispatchable(plan), content="true")
}

///|
test "receiver recursion admission accepts decoded Unicode escaped literals" {
  let source = "function step(n){if(n===0)return this[\"\\u006darker\"];return 1+this[\"\\u0073tep\"](n-1);}" +
    "let receiver={[\"\\u006darker\"]:0,[\"\\u0073tep\"]:step};receiver[\"\\u0073tep\"](256);"
  let stmts = receiver_recursion_test_program(source)
  let plan = match classify_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected decoded Unicode escaped names to be admitted")
  }
  inspect(plan.marker_name, content="marker")
  inspect(plan.property_name, content="step")
  inspect(receiver_recursion_plan_is_dispatchable(plan), content="true")
}

///|
test "receiver recursion admission rejects mixed access provenance modes" {
  let sources = [
    "function step(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x73tep\"](n-1);}" +
    "let receiver={marker:0,[\"\\x73tep\"]:step};receiver[\"\\x73tep\"](256);",
    "function step(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"step\"](n-1);}" +
    "let receiver={[\"\\x6darker\"]:0,[\"step\"]:step};receiver[\"step\"](256);",
    "function step(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x73tep\"](n-1);}" +
    "let receiver={[\"\\x6darker\"]:0,[\"\\x73tep\"]:step};receiver[\"step\"](256);",
    "function step(n){if(n===0)return this.marker;return 1+this[\"\\x73tep\"](n-1);}" +
    "let receiver={[\"\\x6darker\"]:0,[\"\\x73tep\"]:step};receiver[\"\\x73tep\"](256);",
  ]
  for source in sources {
    guard !receiver_recursion_source_is_admitted(source) else {
      fail("unexpectedly admitted mixed receiver access modes: " + source)
    }
  }
}

///|
test "receiver recursion admission rejects escaped noncomputed object keys" {
  let stmts = receiver_recursion_test_program(
    "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
    "let receiver={marker:0,step:step};receiver.step(256);",
  )
  guard stmts[1] is @ast.VarDecl(_, _, Some(@ast.ObjectLit(properties, _)), _) else {
    fail("expected the receiver object declaration")
  }
  let property = properties[0]
  match property.key {
    @ast.StringLit(name, _, lex_form, key_loc) =>
      properties[0] = {
        ..property,
        key: @ast.StringLit(name, true, lex_form, key_loc),
      }
    _ => fail("expected a noncomputed string key")
  }
  inspect(classify_receiver_recursion_program(stmts) is None, content="true")
}

///|
test "receiver recursion admission recognizes the exact computed-literal member call" {
  let stmts = receiver_recursion_test_program(
    receiver_recursion_exact_computed_source(),
  )
  let plan = match classify_receiver_recursion_program(stmts) {
    Some(found) => found
    None =>
      fail(
        "expected the exact computed receiver-recursion shape to be admitted",
      )
  }
  match plan.recipe.marker_property_access {
    ReceiverRecursionComputedLiteral(_, _) => ()
    ReceiverRecursionStatic => fail("expected a computed object marker key")
  }
  match plan.recipe.property_access {
    ReceiverRecursionComputedLiteral(_, _) => ()
    ReceiverRecursionStatic => fail("expected a computed object call key")
  }
  match plan.recipe.marker_access {
    ReceiverRecursionComputedLiteral(_, _) => ()
    ReceiverRecursionStatic => fail("expected a computed marker access")
  }
  match plan.recipe.recursive_access {
    ReceiverRecursionComputedLiteral(_, _) => ()
    ReceiverRecursionStatic => fail("expected a computed recursive access")
  }
  match plan.recipe.root_access {
    ReceiverRecursionComputedLiteral(_, _) => ()
    ReceiverRecursionStatic => fail("expected a computed root access")
  }
  inspect(receiver_recursion_plan_is_dispatchable(plan), content="true")
  for index, stmt in stmts {
    guard receiver_recursion_root_statement_matches(plan, index, stmt) else {
      fail("expected every computed receiver root statement to match")
    }
  }
  let body = match stmts[0] {
    @ast.FuncDecl(_, _, body, _, _) => body
    _ => fail("expected the computed receiver function declaration")
  }
  for index, stmt in body {
    guard receiver_recursion_body_statement_matches(plan, index, stmt) else {
      fail("expected every computed receiver body statement to match")
    }
  }
}

///|
test "receiver recursion admission rejects excluded lookalikes" {
  for
    source in [
      "function step(n){if(n===0)return this[marker];return 1+this[key](n-1);}" +
      "let receiver={[marker]:0,[step]:step};receiver[key](256);",
      "function step(n){if(n===0)return this[getKey()];return 1+this[getKey()](n-1);}" +
      "let receiver={[getKey()]:0,[getKey()]:step};receiver[getKey()](256);",
      "function step(n){if(n===0)return this[\"mar\"+\"ker\"];return 1+this[\"st\"+\"ep\"](n-1);}" +
      "let receiver={[\"mar\"+\"ker\"]:0,[\"st\"+\"ep\"]:step};receiver[\"st\"+\"ep\"](256);",
      "function step(n){if(n===0)return this[`marker`];return 1+this[`step`](n-1);}" +
      "let receiver={[`marker`]:0,[`step`]:step};receiver[`step`](256);",
      "function step(n){if(n===0)return this[Symbol(\"marker\")];return 1+this[Symbol(\"step\")](n-1);}" +
      "let receiver={[Symbol(\"marker\")]:0,[Symbol(\"step\")]:step};receiver[Symbol(\"step\")](256);",
      "function step(n){if(n===0)return this[0];return 1+this[1](n-1);}" +
      "let receiver={[0]:0,[1]:step};receiver[1](256);",
      "function step(n){if(n===0)return this[\"marker\"];return 1+this[\"step\"](n-1);}" +
      "let receiver={marker:0,[\"step\"]:step};receiver[\"step\"](256);",
      "function step(n){if(n===0)return this[\"marker\"];return 1+this.step(n-1);}" +
      "let receiver={[\"marker\"]:0,step:step};receiver.step(256);",
      "function step(n){if(n===0)return this?.[\"marker\"];return 1+this?.[\"step\"](n-1);}" +
      "let receiver={[\"marker\"]:0,[\"step\"]:step};receiver?.[\"step\"](256);",
      "function step(n){if(n===0)return this[\"marker\"];return 1+this[\"step\"]?.(n-1);}" +
      "let receiver={[\"marker\"]:0,[\"step\"]:step};receiver[\"step\"]?.(256);",
      "function step(n){if(n===0)return super[\"marker\"];return 1+super[\"step\"](n-1);}" +
      "let receiver={[\"marker\"]:0,[\"step\"]:step};receiver[\"step\"](256);",
      "function step(n){if(n===0)return this.#marker;return 1+this.#step(n-1);}" +
      "let receiver={[\"marker\"]:0,[\"step\"]:step};receiver[\"step\"](256);",
      "function step(n){if(n===0)return this[\"marker\"];return 1+this[\"step\"](n-1);}" +
      "let receiver={[\"marker\"]:0,get \"step\"(){return step;}};receiver[\"step\"](256);",
      "function step(n){if(n===0)return this[\"marker\"];return 1+this[\"step\"](n-1);}" +
      "let receiver={[\"marker\"]:0,[\"step\"](){return step;}};receiver[\"step\"](256);",
      "function step(n){if(n===0)return this[\"marker\"];return 1+this[\"step\"](n-1);}" +
      "let receiver={[\"marker\"]:0,...{[\"step\"]:step}};receiver[\"step\"](256);",
      "function step(n){if(n===0)return this[\"marker\"];return 1+this[\"step\"](n-1);}" +
      "let receiver={[\"marker\"]:0,[\"step\"]:step,[\"extra\"]:0};receiver[\"step\"](256);",
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
    guard !receiver_recursion_source_is_admitted(source) else {
      fail("unexpectedly admitted receiver lookalike: " + source)
    }
  }
}
