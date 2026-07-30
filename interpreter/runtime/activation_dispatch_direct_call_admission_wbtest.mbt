///|
fn direct_numeric_recursion_test_callee(
  source : String,
  name : String,
) -> Value raise {
  let interp = Interpreter::new()
  let stmts = @parser.parse(source).stmts
  interp.prepare_root_program_execution(stmts, interp.global, false)
  interp.global.get(name)
}

///|
fn expect_direct_numeric_recursion_entry(
  plan : DirectNumericRecursionCallPlan,
  name : String,
  parameter : String,
  recursive_callee : String,
) -> Unit raise {
  inspect(plan.entry.name, content=name)
  inspect(plan.entry.parameter, content=parameter)
  inspect(plan.entry.recursive_callee, content=recursive_callee)
  inspect(plan.initial_argument, content="256")
}

///|
test "direct numeric call admission recognizes the exact self root" {
  let callee = direct_numeric_recursion_test_callee(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}", "f",
  )
  let loc = @token.Loc::default()
  let plan = match
    classify_direct_numeric_recursion_call(
      callee,
      Undefined,
      [Number(256.0)],
      loc,
    ) {
    Some(found) => found
    None => fail("expected the exact direct self-recursion call to be admitted")
  }
  expect_direct_numeric_recursion_entry(plan, "f", "n", "f")
  match plan.cycle {
    DirectNumericSelf => ()
    DirectNumericMutualPeer(_) => fail("self recursion must not require a peer")
  }
  inspect(plan.root_call_loc == loc, content="true")
}

///|
test "direct numeric call admission records the mutual peer candidate name" {
  let loc = @token.Loc::default()
  let f_plan = match
    classify_direct_numeric_recursion_call(
      direct_numeric_recursion_test_callee(
        "function f(n){if(n===0)return 0;return 1+g(n-1);}", "f",
      ),
      Undefined,
      [Number(256.0)],
      loc,
    ) {
    Some(found) => found
    None => fail("expected the direct mutual-recursion entry candidate")
  }
  expect_direct_numeric_recursion_entry(f_plan, "f", "n", "g")
  match f_plan.cycle {
    DirectNumericMutualPeer(name) => inspect(name, content="g")
    DirectNumericSelf => fail("mutual recursion must retain its peer name")
  }

  let g_plan = match
    classify_direct_numeric_recursion_call(
      direct_numeric_recursion_test_callee(
        "function g(m){if(m===0)return 0;return 1+f(m-1);}", "g",
      ),
      Undefined,
      [Number(256.0)],
      loc,
    ) {
    Some(found) => found
    None => fail("expected the reverse mutual-recursion entry candidate")
  }
  expect_direct_numeric_recursion_entry(g_plan, "g", "m", "f")
  match g_plan.cycle {
    DirectNumericMutualPeer(name) => inspect(name, content="f")
    DirectNumericSelf =>
      fail("reverse mutual recursion must retain its peer name")
  }
}

///|
test "direct numeric call admission rejects non-exact public call inputs" {
  let callee = direct_numeric_recursion_test_callee(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}", "f",
  )
  let non_exact_callees = match callee {
    Object(object_data) =>
      match object_data.callable {
        Some(UserFunc(data)) =>
          [
            Object({ ..object_data, callable: Some(ArrowFunc(data)) }),
            Object({
              ..object_data,
              callable: Some(UserFunc({ ..data, strict: true })),
            }),
            Object({
              ..object_data,
              callable: Some(UserFunc({ ..data, has_name_binding: true })),
            }),
            Object({
              ..object_data,
              callable: Some(UserFunc({ ..data, is_method: true })),
            }),
            Object({ ..object_data, class_name: "Callable" }),
          ]
        _ => fail("expected the exact fixture to contain a UserFunc")
      }
    _ => fail("expected the exact fixture to contain a function object")
  }
  let loc = @token.Loc::default()
  for candidate in non_exact_callees {
    guard classify_direct_numeric_recursion_call(
        candidate,
        Undefined,
        [Number(256.0)],
        loc,
      )
      is None else {
      fail("a non-exact callable representation was admitted")
    }
  }
  for
    candidate_input in [
      (Undefined, Undefined, [Number(256.0)]),
      (callee, Null, [Number(256.0)]),
      (callee, Undefined, []),
      (callee, Undefined, [Number(255.0)]),
      (callee, Undefined, [String_("256")]),
      (callee, Undefined, [Number(256.0), Number(0.0)]),
    ] {
    let (candidate, this_value, args) = candidate_input
    guard classify_direct_numeric_recursion_call(
        candidate, this_value, args, loc,
      )
      is None else {
      fail("a non-exact direct call input was admitted")
    }
  }
}

///|
test "direct numeric call admission rejects near-match function bodies" {
  let loc = @token.Loc::default()
  for
    source in [
      "function f(n){if(n===1)return 0;return 1+f(n-1);}", "function f(n){if(n===0)return 0;return 2+f(n-1);}",
      "function f(n){if(n===0)return 0;return 1+f(n-2);}", "function f(n){if(n===0)return 0;n;return 1+f(n-1);}",
      "function f(n){if(n===0)return 0;return 1+n(n-1);}",
    ] {
    let callee = direct_numeric_recursion_test_callee(source, "f")
    guard classify_direct_numeric_recursion_call(
        callee,
        Undefined,
        [Number(256.0)],
        loc,
      )
      is None else {
      fail("a near-match direct function body was admitted: " + source)
    }
  }
}

///|
test "direct numeric call admission keeps protected return-finalizer bodies outside its slice" {
  let loc = @token.Loc::default()
  for
    source in [
      "function f(n){if(n===0)return 0;" + "try{return 1+f(n-1);}finally{0;}}",
      "function f(n){if(n===0)return 0;" +
      "try{return 1+f(n-1);}finally{throw 7;}}",
    ] {
    let callee = direct_numeric_recursion_test_callee(source, "f")
    guard classify_direct_numeric_recursion_call(
        callee,
        Undefined,
        [Number(256.0)],
        loc,
      )
      is None else {
      fail("protected function body entered direct public-call admission")
    }
  }
}
