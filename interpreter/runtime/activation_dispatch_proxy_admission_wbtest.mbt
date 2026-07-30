///|
fn proxy_get_recursion_test_program(source : String) -> Array[@ast.Stmt] raise {
  @parser.parse(source).stmts
}

///|
fn proxy_get_recursion_exact_source() -> String {
  "let n=256;" +
  "let p;" +
  "p=new Proxy({},{get(t,k,r){" +
  "if(n===0)return 0;n=n-1;return 1+p.x;" +
  "}});" +
  "p.x;"
}

///|
test "Proxy get recursion admission recognizes only the exact trap shape" {
  let stmts = proxy_get_recursion_test_program(
    proxy_get_recursion_exact_source(),
  )
  let plan = match classify_proxy_get_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact #616 Proxy get shape to be admitted")
  }
  inspect(plan.counter_name, content="n")
  inspect(plan.proxy_name, content="p")
  inspect(plan.property_name, content="x")
  inspect(plan.target_parameter, content="t")
  inspect(plan.key_parameter, content="k")
  inspect(plan.receiver_parameter, content="r")
  inspect(plan.initial_count, content="256")
  inspect(proxy_get_recursion_plan_is_dispatchable(plan), content="false")
  inspect(proxy_get_recursion_seal_statement_index(plan), content="2")
  inspect(proxy_get_recursion_root_statement_index(plan), content="3")
  for index, stmt in stmts {
    guard proxy_get_recursion_root_statement_matches(plan, index, stmt) else {
      fail("expected every admitted Proxy root statement to match")
    }
  }
  let handler = match stmts[2] {
    @ast.ExprStmt(@ast.Assign(_, @ast.NewExpr(_, args, _), _), _) if args.length() ==
      2 => args[1]
    _ => fail("expected admitted Proxy construction")
  }
  let trap_body = match handler {
    @ast.ObjectLit(properties, _) if properties.length() == 1 =>
      match properties[0].value {
        @ast.FuncExpr(_, _, body, _, _) => body
        _ => fail("expected admitted Proxy get method")
      }
    _ => fail("expected admitted Proxy handler")
  }
  for index, stmt in trap_body {
    guard proxy_get_recursion_body_statement_matches(plan, index, stmt) else {
      fail("expected every admitted Proxy trap statement to match")
    }
  }
  guard classify_numeric_recursion_program(stmts) is None else {
    fail("Proxy and numeric admission must remain disjoint")
  }
  guard classify_getter_recursion_program(stmts) is None else {
    fail("Proxy and getter admission must remain disjoint")
  }
}

///|
test "Proxy get recursion admission rejects residual and lookalike shapes" {
  for
    source in [
      "let n=255;let p;p=new Proxy({},{get(t,k,r){if(n===0)return 0;n=n-1;return 1+p.x;}});p.x;",
      "let Proxy=256;let p;p=new Proxy({},{get(t,k,r){if(Proxy===0)return 0;Proxy=Proxy-1;return 1+p.x;}});p.x;",
      "let n=256;let Proxy;Proxy=new Proxy({},{get(t,k,r){if(n===0)return 0;n=n-1;return 1+Proxy.x;}});Proxy.x;",
      "let n=256;let p=new Proxy({},{get(t,k,r){if(n===0)return 0;n=n-1;return 1+p.x;}});p.x;",
      "let n=256;let p;p=new Proxy({x:0},{get(t,k,r){if(n===0)return 0;n=n-1;return 1+p.x;}});p.x;",
      "let n=256;let p;p=new Proxy({},{});p.x;", "let n=256;let p;p=new Proxy({},{get(t,k,r){if(n===0)return 0;n=n-1;return 1+p.x;},x:0});p.x;",
      "let n=256;let p;p=new Proxy({},{get get(){return 0;}});p.x;", "let n=256;let p;p=new Proxy({},{['get'](t,k,r){if(n===0)return 0;n=n-1;return 1+p.x;}});p.x;",
      "let n=256;let p;p=new Proxy({},{get:function(t,k,r){if(n===0)return 0;n=n-1;return 1+p.x;}});p.x;",
      "let n=256;let p;p=new Proxy({},{get(t,k){if(n===0)return 0;n=n-1;return 1+p.x;}});p.x;",
      "let n=256;let p;p=new Proxy({},{get(t,t,r){if(n===0)return 0;n=n-1;return 1+p.x;}});p.x;",
      "let n=256;let p;p=new Proxy({},{get(t,k,r){if(n==0)return 0;n=n-1;return 1+p.x;}});p.x;",
      "let n=256;let p;p=new Proxy({},{get(t,k,r){if(n===0)return 1;n=n-1;return 1+p.x;}});p.x;",
      "let n=256;let p;p=new Proxy({},{get(t,k,r){if(n===0)return 0;n=n-2;return 1+p.x;}});p.x;",
      "let n=256;let p;p=new Proxy({},{get(t,k,r){if(n===0)return 0;n=n-1;return 2+p.x;}});p.x;",
      "let n=256;let p;p=new Proxy({},{get(t,k,r){if(n===0)return 0;n=n-1;return 1+p.y;}});p.x;",
      "let n=256;let p;p=new Proxy({},{get(t,k,r){if(n===0)return 0;n=n-1;return 1+p.x;}});p['x'];",
      "let n=256;let p;p=new Proxy({},{get(t,k,r){if(n===0)return 0;n=n-1;return 1+p.x;}});0;p.x;",
    ] {
    guard classify_proxy_get_recursion_program(
        proxy_get_recursion_test_program(source),
      )
      is None else {
      fail("unexpectedly admitted Proxy get lookalike: " + source)
    }
  }
}
