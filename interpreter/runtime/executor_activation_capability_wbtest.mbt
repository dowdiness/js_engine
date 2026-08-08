///|
fn classify_executor_capability_for_test(
  params : Array[String],
  source : String,
) -> ExecutorActivationCapabilitySummary? raise Error {
  executor_activation_capability_summary(params, @parser.parse(source).stmts)
}

///|
test "executor activation capability shares direct callee classification" {
  match @parser.parse("return ((leaf))(n);").stmts {
    [ReturnStmt(Some(Call(callee, _, _)), _)] =>
      match executor_activation_direct_call_target_name(callee) {
        Some(name) => inspect(name, content="leaf")
        None => fail("grouped direct callees must retain their identifier")
      }
    _ => fail("expected one direct return call")
  }
}

///|
test "executor activation capability summary classifies only the closed subset" {
  let first = classify_executor_capability_for_test(["n"], "return n + 1;")
  let second = classify_executor_capability_for_test(["n"], "return n + 1;")
  match (first, second) {
    (Some(first), Some(second)) => {
      inspect(first.parameter_count, content="1")
      inspect(second.parameter_count, content="1")
      assert_true(first.direct_call is None)
      assert_true(second.direct_call is None)
    }
    _ => fail("the numeric no-call form must be admitted")
  }

  match
    classify_executor_capability_for_test(
      ["n"],
      "if (n === 0) return 0; else return n + 1;",
    ) {
    Some(summary) =>
      match summary.direct_call {
        None => ()
        Some(_) => fail("the if form must not invent a call edge")
      }
    None => fail("the current if form must be admitted")
  }

  match
    classify_executor_capability_for_test(["n"], "return leaf(n - 1) + 1;") {
    Some(summary) =>
      match summary.direct_call {
        Some(edge) => {
          inspect(edge.callee, content="leaf")
          inspect(edge.argument_count, content="1")
        }
        None => fail("the direct call edge must be retained")
      }
    None => fail("the direct numeric call form must be admitted")
  }

  let rejected = [
    "return n * 2;", "return -n;", "var x = n; return n;", "return;", "return first(n) + second(n);",
    "return first(second(n));", "return eval(n);", "return missing;",
  ]
  for source in rejected {
    assert_true(classify_executor_capability_for_test(["n"], source) is None)
  }
}
