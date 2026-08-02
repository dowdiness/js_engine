///|
fn constructor_recursion_test_program(
  source : String,
) -> Array[@ast.Stmt] raise {
  @parser.parse(source).stmts
}

///|
test "constructor recursion admission recognizes the exact self recipe" {
  let stmts = constructor_recursion_test_program(
    "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}}" +
    "new Node(1024).value;",
  )
  let plan = match classify_constructor_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact ordinary-constructor recipe")
  }
  inspect(plan.root_name, content="Node")
  inspect(plan.parameter, content="n")
  inspect(plan.value_property, content="value")
  inspect(plan.initial_argument, content="1024")
  inspect(plan.functions.length(), content="1")
  guard constructor_recursion_root_statement_matches(plan, 0, stmts[0]) else {
    fail("the admitted declaration must retain its source identity")
  }
  guard constructor_recursion_root_expression_matches(plan, stmts[1]) else {
    fail("the admitted root construction must retain its source identity")
  }
}

///|
test "constructor recursion admission closes the exact mutual recipe" {
  let stmts = constructor_recursion_test_program(
    "function A(n){this.value=n;if(n>0){this.child=new B(n-1);}}" +
    "function B(n){this.value=n;if(n>0){this.child=new A(n-1);}}" +
    "new A(1024).value;",
  )
  let plan = match classify_constructor_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact mutual ordinary-constructor recipe")
  }
  inspect(plan.functions.length(), content="2")
  inspect(plan.functions[0].name, content="A")
  inspect(plan.functions[0].recursive_callee, content="B")
  inspect(plan.functions[1].name, content="B")
  inspect(plan.functions[1].recursive_callee, content="A")
}

///|
test "constructor recursion admission rejects near-match shapes" {
  for
    source in [
      "function Node(n){this.value=n;if(n>=0){this.child=new Node(n-1);}}" +
      "new Node(1024).value;",
      "function Node(n){this.value=n;if(n>0){this.child=new Node(n-2);}}" +
      "new Node(1024).value;",
      "function Node(n){this.value=n;n;if(n>0){this.child=new Node(n-1);}}" +
      "new Node(1024).value;",
      "function Node(n,m){this.value=n;if(n>0){this.child=new Node(n-1);}}" +
      "new Node(1024).value;",
      "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}}" +
      "new Node(n).value;",
    ] {
    guard classify_constructor_recursion_program(
        constructor_recursion_test_program(source),
      )
      is None else {
      fail("near-match constructor recipe was admitted: " + source)
    }
  }
}

///|
test "constructor recursion admission retains terminal return recipes" {
  let object_return = constructor_recursion_test_program(
    "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}" +
    "return {value:n};}new Node(4).value;",
  )
  let primitive_return = constructor_recursion_test_program(
    "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}" +
    "return n;}new Node(4).value;",
  )
  for stmts in [object_return, primitive_return] {
    let plan = match classify_constructor_recursion_program(stmts) {
      Some(found) => found
      None => fail("expected terminal return recipe admission")
    }
    match plan.functions[0].terminal {
      ConstructorRecursionReturn => ()
      _ => fail("expected the terminal return to be retained by admission")
    }
  }
}
