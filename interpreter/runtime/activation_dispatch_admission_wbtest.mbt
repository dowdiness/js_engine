///|
fn numeric_recursion_test_program(source : String) -> Array[@ast.Stmt] raise {
  @parser.parse(source).stmts
}

///|
fn expect_numeric_recursion_function_plan(
  plan : NumericRecursionFunctionPlan,
  name : String,
  parameter : String,
  recursive_callee : String,
  declaration_index : Int,
) -> Unit raise {
  inspect(plan.syntax.name, content=name)
  inspect(plan.syntax.parameter, content=parameter)
  inspect(plan.syntax.recursive_callee, content=recursive_callee)
  inspect(plan.declaration_index, content=declaration_index.to_string())
}

///|
test "numeric recursion admission recognizes only the exact self shape" {
  let plan = match
    classify_numeric_recursion_program(
      numeric_recursion_test_program(
        "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
      ),
    ) {
    Some(found) => found
    None => fail("expected the exact #616 self-recursion shape to be admitted")
  }
  expect_numeric_recursion_function_plan(plan.entry, "f", "n", "f", 0)
  guard plan.peer is None else { fail("self recursion must not have a peer") }
  inspect(plan.initial_argument, content="256")
  inspect(plan.root_call_loc.line, content="1")
  guard classify_numeric_recursion_program(
      numeric_recursion_test_program("f(256);"),
    )
    is None else {
    fail("a root call without its declaration shape must be rejected")
  }
}

///|
test "numeric recursion admission normalizes the exact mutual shape" {
  let plan = match
    classify_numeric_recursion_program(
      numeric_recursion_test_program(
        "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
        "function g(m){if(m===0)return 0;return 1+f(m-1);}" +
        "f(256);",
      ),
    ) {
    Some(found) => found
    None =>
      fail("expected the exact #616 mutual-recursion shape to be admitted")
  }
  expect_numeric_recursion_function_plan(plan.entry, "f", "n", "g", 0)
  match plan.peer {
    Some(peer) => expect_numeric_recursion_function_plan(peer, "g", "m", "f", 1)
    None => fail("mutual recursion must retain its peer plan")
  }
  inspect(plan.initial_argument, content="256")
  inspect(plan.root_call_loc.line, content="1")
}

///|
test "numeric recursion admission classifies closed protected root shapes" {
  for
    source in [
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{f(256);}finally{0;}",
      "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
      "function g(m){if(m===0)return 0;return 1+f(m-1);}" +
      "try{throw f(256);}catch(e){e;}finally{0;}",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{throw f(256);}catch{1;}finally{throw 7;}",
    ] {
    guard classify_numeric_recursion_program(
        numeric_recursion_test_program(source),
      )
      is Some(_) else {
      fail(
        "expected the closed protected root shape to be classified: " + source,
      )
    }
  }
}

///|
test "numeric recursion admission classifies every closed handler recipe" {
  for
    source in [
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{throw f(256);}catch(e){throw e;}",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{throw f(256);}catch{}",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{f(256);}finally{}",
    ] {
    guard classify_numeric_recursion_program(
        numeric_recursion_test_program(source),
      )
      is Some(_) else {
      fail("expected the closed handler recipe to be classified: " + source)
    }
  }
}

///|
test "numeric recursion admission retains normalized protected control recipes" {
  let self_plan = match
    classify_numeric_recursion_program(
      numeric_recursion_test_program(
        "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
        "try{f(256);}finally{0;}",
      ),
    ) {
    Some(found) => found
    None => fail("expected the protected self plan")
  }
  match self_plan.root_control {
    NumericRecursionProtectedRoot(
      {
        try_completion: NumericRecursionRootCallValue,
        catch_recipe: NumericRecursionNoCatch,
        finalizer_recipe: NumericRecursionFinalizer(
          NumericRecursionClosedNumberValue(value)
        ),
      }
    ) => inspect(value, content="0")
    _ => fail("unexpected protected self root recipe")
  }

  let mutual_plan = match
    classify_numeric_recursion_program(
      numeric_recursion_test_program(
        "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
        "function g(m){if(m===0)return 0;return 1+f(m-1);}" +
        "try{throw f(256);}catch(e){e;}finally{0;}",
      ),
    ) {
    Some(found) => found
    None => fail("expected the protected mutual plan")
  }
  match mutual_plan.root_control {
    NumericRecursionProtectedRoot(
      {
        try_completion: NumericRecursionRootCallThrow,
        catch_recipe: NumericRecursionCatch(
          Some("e"),
          NumericRecursionClosedBindingValue
        ),
        finalizer_recipe: NumericRecursionFinalizer(
          NumericRecursionClosedNumberValue(value)
        ),
      }
    ) => inspect(value, content="0")
    _ => fail("unexpected protected mutual root recipe")
  }

  let bindingless_plan = match
    classify_numeric_recursion_program(
      numeric_recursion_test_program(
        "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
        "try{throw f(256);}catch{1;}finally{throw 7;}",
      ),
    ) {
    Some(found) => found
    None => fail("expected the protected bindingless-catch plan")
  }
  match bindingless_plan.root_control {
    NumericRecursionProtectedRoot(
      {
        try_completion: NumericRecursionRootCallThrow,
        catch_recipe: NumericRecursionCatch(
          None,
          NumericRecursionClosedNumberValue(catch_value)
        ),
        finalizer_recipe: NumericRecursionFinalizer(
          NumericRecursionClosedNumberThrow(finalizer_value)
        ),
      }
    ) => {
      inspect(catch_value, content="1")
      inspect(finalizer_value, content="7")
    }
    _ => fail("unexpected protected bindingless-catch recipe")
  }

  inspect(numeric_recursion_plan_is_dispatchable(self_plan), content="true")
  let direct_plan = match
    classify_numeric_recursion_program(
      numeric_recursion_test_program(
        "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
      ),
    ) {
    Some(found) => found
    None => fail("expected the direct plan")
  }
  inspect(numeric_recursion_plan_is_dispatchable(direct_plan), content="true")
}

///|
test "numeric recursion admission rejects open protected root effects" {
  for
    source in [
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{f(256);0;}finally{0;}",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{f(256);}catch({x}){x;}finally{0;}",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{throw f(256);}catch(e){f(1);}finally{0;}",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{throw f(256);}catch(eval){eval;}",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{f(256);}finally{f(1);}",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{f(256);}finally{010;}",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{f(256);}finally{({valueOf(){return 0;}});}",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{try{f(256);}finally{0;}}finally{0;}",
    ] {
    guard classify_numeric_recursion_program(
        numeric_recursion_test_program(source),
      )
      is None else {
      fail("unexpectedly admitted an open protected root effect: " + source)
    }
  }
}

///|
test "numeric recursion admission retains an array-free expression location recipe" {
  let stmts = numeric_recursion_test_program(
    "function f(n) {\n" +
    "  if (n\n" +
    "    === 0) return 0;\n" +
    "  return 1\n" +
    "    + f\n" +
    "      (\n" +
    "        n\n" +
    "        - 1\n" +
    "      );\n" +
    "}\n" +
    "f(256);",
  )
  let plan = match classify_numeric_recursion_program(stmts) {
    Some(found) => found
    None =>
      fail("expected the multiline numeric-recursion shape to be admitted")
  }
  stmts.clear()
  let recipe = plan.entry.syntax.expression_recipe
  json_inspect(
    [
      recipe.base_condition_loc.line.to_string() +
      ":" +
      recipe.base_condition_loc.col.to_string(),
      recipe.recursive_add_loc.line.to_string() +
      ":" +
      recipe.recursive_add_loc.col.to_string(),
      recipe.recursive_call_loc.line.to_string() +
      ":" +
      recipe.recursive_call_loc.col.to_string(),
      recipe.recursive_subtract_loc.line.to_string() +
      ":" +
      recipe.recursive_subtract_loc.col.to_string(),
      plan.root_call_loc.line.to_string() +
      ":" +
      plan.root_call_loc.col.to_string(),
    ],
    content=["3:5", "5:5", "6:7", "8:9", "11:2"],
  )
}

///|
test "numeric recursion admission rejects residual and lookalike shapes" {
  for
    source in [
      "",
      "f(256);",
      "0;function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);0;",
      "function f(n=0){if(n===0)return 0;return 1+f(n-1);}f(256);",
      "function f(n,m){if(n===0)return 0;return 1+f(n-1);}f(256);",
      "function f(...n){if(n===0)return 0;return 1+f(n-1);}f(256);",
      "function f({n}){if(n===0)return 0;return 1+f(n-1);}f(256);",
      "function* f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
      "function f(f){if(f===0)return 0;return 1+f(f-1);}f(256);",
      "function f(arguments){if(arguments===0)return 0;return 1+f(arguments-1);}f(256);",
      "function eval(n){if(n===0)return 0;return 1+eval(n-1);}eval(256);",
      "function arguments(n){if(n===0)return 0;return 1+arguments(n-1);}arguments(256);",
      "function f(n){if(n==0)return 0;return 1+f(n-1);}f(256);",
      "function f(n){if(0===n)return 0;return 1+f(n-1);}f(256);",
      "function f(n){if((n===0))return 0;return 1+f(n-1);}f(256);",
      "function f(n){if(n===0){return 0;}return 1+f(n-1);}f(256);",
      "function f(n){if(n===0)return 0;else return 1;return 1+f(n-1);}f(256);",
      "function f(n){if(n===0)return 1;return 1+f(n-1);}f(256);",
      "function f(n){if(n===0)return 0;return f(n-1)+1;}f(256);",
      "function f(n){if(n===0)return 0;return 2+f(n-1);}f(256);",
      "function f(n){if(n===0)return 0;return 1+f(n-2);}f(256);",
      "function f(n){if(n===0)return 0;return 1+(f)(n-1);}f(256);",
      "function f(n){if(n===0)return 0;return 1+f(...[n-1]);}f(256);",
      "function f(n){if(n===0)return 0;return 1+globalThis.f(n-1);}f(256);",
      "function f(n){if(n===0)return 0;return 1+eval(\"f(n-1)\");}f(256);",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "function g(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
      "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
      "function f(m){if(m===0)return 0;return 1+f(m-1);}f(256);",
      "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
      "function g(f){if(f===0)return 0;return 1+f(f-1);}f(256);",
      "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
      "function g(n){if(n===0)return 0;return 1+f(n-1);}g(256);",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}f(255);",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}(f)(256);",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256,0);",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}f(0400);",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "function g(n){if(n===0)return 0;return 1+f(n-1);}" +
      "function h(n){if(n===0)return 0;return 1+h(n-1);}f(256);",
      "let n=256;let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};o.x;",
      "let n=256;let p;p=new Proxy({},{get(t,k,r){if(n===0)return 0;n=n-1;return 1+p.x;}});p.x;",
    ] {
    guard classify_numeric_recursion_program(
        numeric_recursion_test_program(source),
      )
      is None else {
      fail("unexpectedly admitted residual or lookalike source: " + source)
    }
  }
}

///|
fn getter_recursion_test_program(source : String) -> Array[@ast.Stmt] raise {
  @parser.parse(source).stmts
}

///|
test "getter recursion admission recognizes only the exact own accessor shape" {
  let source = "let n=256;" +
    "let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
    "o.x;"
  let stmts = getter_recursion_test_program(source)
  let plan = match classify_getter_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact #616 getter shape to be admitted")
  }
  inspect(plan.counter_name, content="n")
  inspect(plan.object_name, content="o")
  inspect(plan.property_name, content="x")
  inspect(plan.initial_count, content="256")
  inspect(getter_recursion_plan_is_dispatchable(plan), content="true")
  guard classify_numeric_recursion_program(stmts) is None else {
    fail("getter and numeric admission must remain disjoint")
  }
}

///|
test "getter recursion admission recognizes the exact direct prototype accessor shape" {
  let source = "let n=256;" +
    "let p={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
    "let o={__proto__:p};" +
    "o.x;"
  let stmts = getter_recursion_test_program(source)
  let plan = match classify_getter_recursion_program(stmts) {
    Some(found) => found
    None =>
      fail("expected the exact direct prototype getter shape to be admitted")
  }
  inspect(plan.counter_name, content="n")
  inspect(plan.object_name, content="o")
  inspect(plan.property_name, content="x")
  inspect(plan.initial_count, content="256")
  inspect(getter_recursion_plan_is_dispatchable(plan), content="true")
  for index, stmt in stmts {
    guard getter_recursion_root_statement_matches(plan, index, stmt) else {
      fail("expected every admitted prototype getter root statement to match")
    }
  }
  guard classify_numeric_recursion_program(stmts) is None else {
    fail("getter and numeric admission must remain disjoint")
  }
  let explicit_proto_binding = getter_recursion_test_program(
    "let n=256;" +
    "let __proto__={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
    "let o={__proto__:__proto__};" +
    "o.x;",
  )
  guard classify_getter_recursion_program(explicit_proto_binding) is Some(_) else {
    fail("expected an explicit __proto__ initializer to remain admissible")
  }
}

///|
test "getter recursion admission rejects residual and lookalike shapes" {
  for
    source in [
      "let n=256;let o={x(){if(n===0)return 0;n=n-1;return 1+o.x;}};o.x;", "let n=256;let o={get ['x'](){if(n===0)return 0;n=n-1;return 1+o.x;}};o.x;",
      "let n=256;let o={get x(){if(n===0)return 0;n=n-1;return 1+o['x'];}};o.x;",
      "let n=256;let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};o['x'];",
      "let n=255;let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};o.x;", "let n=256;let o={get x(){if(n===0)return 1;n=n-1;return 1+o.x;}};o.x;",
      "let n=256;let o={get x(){if(n===0)return 0;n=n-2;return 1+o.x;}};o.x;", "let n=256;let o={get x(){if(n===0)return 0;n=n-1;return 2+o.x;}};o.x;",
      "let n=256;let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};0;o.x;",
      "let n=256;let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;},y:0};o.x;",
      "let n=256;let p={get x(){if(n===0)return 0;n=n-1;return 1+o.x;},y:0};let o={__proto__:p};o.x;",
      "let n=256;let p={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};let q={__proto__:p};let o={__proto__:q};o.x;",
      "let n=256;let p={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};let o={['__proto__']:p};o.x;",
      "let n=256;let __proto__={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};let o={__proto__};o.x;",
      "let n=256;let p={get x(){if(n===0)return 0;n=n-1;return 1+p.x;}};let o={__proto__:p};o.x;",
      "let n=256;let p={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};let o={__proto__:p,y:0};o.x;",
      "let n=256;let p;p=new Proxy({},{get(t,k,r){if(n===0)return 0;n=n-1;return 1+p.x;}});p.x;",
    ] {
    guard classify_getter_recursion_program(
        getter_recursion_test_program(source),
      )
      is None else {
      fail("unexpectedly admitted getter lookalike: " + source)
    }
  }
}
