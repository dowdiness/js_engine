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
  inspect(plan.name, content=name)
  inspect(plan.parameter, content=parameter)
  inspect(plan.recursive_callee, content=recursive_callee)
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
