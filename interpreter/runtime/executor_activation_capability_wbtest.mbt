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
      inspect(first.direct_calls.length(), content="0")
      inspect(second.direct_calls.length(), content="0")
    }
    _ => fail("the numeric no-call form must be admitted")
  }

  match
    classify_executor_capability_for_test(
      ["n"],
      "if (n === 0) return 0; else return n + 1;",
    ) {
    Some(summary) => inspect(summary.direct_calls.length(), content="0")
    None => fail("the current if form must be admitted")
  }

  match
    classify_executor_capability_for_test(["n"], "return leaf(n - 1) + 1;") {
    Some(summary) => {
      inspect(summary.direct_calls.length(), content="1")
      let edge = summary.direct_calls[0]
      inspect(edge.callee, content="leaf")
      inspect(edge.argument_count, content="1")
    }
    None => fail("the direct numeric call form must be admitted")
  }

  let rejected = [
    "return n * 2;", "return -n;", "var x = n; return n;", "return;", "return eval(n);",
    "return missing;",
  ]
  for source in rejected {
    assert_true(classify_executor_capability_for_test(["n"], source) is None)
  }
}

///|
test "executor activation capability preserves ordered sibling call requirements" {
  match
    classify_executor_capability_for_test(["n"], "return first(n) + second(n);") {
    Some(summary) => {
      inspect(summary.direct_calls.length(), content="2")
      let first_edge = summary.direct_calls[0]
      let second_edge = summary.direct_calls[1]
      inspect(first_edge.callee, content="first")
      inspect(second_edge.callee, content="second")
    }
    None => fail("sibling direct calls must be admitted")
  }

  match
    classify_executor_capability_for_test(["n"], "return first(n) + first(n);") {
    Some(summary) => {
      inspect(summary.direct_calls.length(), content="2")
      let first_edge = summary.direct_calls[0]
      let second_edge = summary.direct_calls[1]
      inspect(first_edge.callee, content="first")
      inspect(second_edge.callee, content="first")
    }
    None => fail("duplicate direct call sites must be retained")
  }

  match
    classify_executor_capability_for_test(
      ["n"],
      "if (n === 0) return first(n); else return second(n);",
    ) {
    Some(summary) => {
      inspect(summary.direct_calls.length(), content="2")
      let first_edge = summary.direct_calls[0]
      let second_edge = summary.direct_calls[1]
      inspect(first_edge.callee, content="first")
      inspect(second_edge.callee, content="second")
    }
    None => fail("branch-separated direct calls must be admitted")
  }

  assert_true(
    classify_executor_capability_for_test(["n"], "return first(second(n));")
    is Some(_),
  )
}

///|
test "executor activation capability preserves ordered nested call requirements" {
  match
    classify_executor_capability_for_test(
      ["n"],
      "return outer(middle(inner(n)));",
    ) {
    Some(summary) => {
      inspect(summary.direct_calls.length(), content="3")
      inspect(summary.direct_calls[0].callee, content="inner")
      inspect(summary.direct_calls[1].callee, content="middle")
      inspect(summary.direct_calls[2].callee, content="outer")
    }
    None => fail("deep nested direct calls must be admitted")
  }

  match
    classify_executor_capability_for_test(
      ["n"],
      "return outer(first(n), second(n));",
    ) {
    Some(summary) => {
      inspect(summary.direct_calls.length(), content="3")
      inspect(summary.direct_calls[0].callee, content="first")
      inspect(summary.direct_calls[1].callee, content="second")
      inspect(summary.direct_calls[2].callee, content="outer")
      inspect(summary.direct_calls[2].argument_count, content="2")
    }
    None => fail("multiple direct call arguments must be admitted")
  }

  match
    classify_executor_capability_for_test(
      ["n"],
      "return outer(inner(n), inner(n));",
    ) {
    Some(summary) => {
      inspect(summary.direct_calls.length(), content="3")
      inspect(summary.direct_calls[0].callee, content="inner")
      inspect(summary.direct_calls[1].callee, content="inner")
      inspect(summary.direct_calls[2].callee, content="outer")
    }
    None => fail("duplicate nested call sites must be retained")
  }

  assert_true(
    classify_executor_capability_for_test(["n"], "return outer(-n);") is None,
  )
}
