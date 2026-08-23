///|
fn ends_with_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid endsWith execution policy")
  }
}

///|
fn expect_ends_with_result(
  result : Result[Json, @js_engine.EngineDiagnostic],
  expected : Bool,
) -> Unit raise Error {
  match result {
    Ok(value) =>
      if expected {
        json_inspect(value, content=true)
      } else {
        json_inspect(value, content=false)
      }
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "default String.endsWith search reaches execution limit" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"a\".repeat(100000) + \"b\"; " +
    "var needle = \"a\".repeat(100000) + \"c\"; " +
    "function endsWithLateMismatch() { return large.endsWith(needle); }",
  )
  match
    engine.call_json_bounded(
      "endsWithLateMismatch",
      [],
      ends_with_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("endsWith search must be interruptible")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
}

///|
test "default String.endsWith preserves comparison boundaries" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function firstHit() { return \"abc\".endsWith(\"c\"); } " +
    "function fullMatch() { return \"abc\".endsWith(\"abc\"); } " +
    "function firstMismatch() { return \"abc\".endsWith(\"z\"); } " +
    "function emptySearch() { return \"abc\".endsWith(\"\", 99); } " +
    "function negativePosition() { return \"abc\".endsWith(\"a\", -1); } " +
    "function positiveClamp() { return \"abc\".endsWith(\"c\", 99); } " +
    "function impossible() { return \"abc\".endsWith(\"abcd\"); }",
  )
  expect_ends_with_result(
    engine.call_json_bounded("firstHit", [], ends_with_guardrail_policy(1000L)),
    true,
  )
  expect_ends_with_result(
    engine.call_json_bounded("fullMatch", [], ends_with_guardrail_policy(1000L)),
    true,
  )
  expect_ends_with_result(
    engine.call_json_bounded(
      "firstMismatch",
      [],
      ends_with_guardrail_policy(1000L),
    ),
    false,
  )
  expect_ends_with_result(
    engine.call_json_bounded(
      "emptySearch",
      [],
      ends_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_ends_with_result(
    engine.call_json_bounded(
      "negativePosition",
      [],
      ends_with_guardrail_policy(1000L),
    ),
    false,
  )
  expect_ends_with_result(
    engine.call_json_bounded(
      "positiveClamp",
      [],
      ends_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_ends_with_result(
    engine.call_json_bounded(
      "impossible",
      [],
      ends_with_guardrail_policy(1000L),
    ),
    false,
  )
}

///|
test "default String.endsWith completes with sufficient budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"a\".repeat(100000) + \"b\"; " +
    "var needle = \"a\".repeat(100000) + \"c\"; " +
    "function endsWithLateMismatch() { return large.endsWith(needle); }",
  )
  expect_ends_with_result(
    engine.call_json_bounded(
      "endsWithLateMismatch",
      [],
      ends_with_guardrail_policy(200000L),
    ),
    false,
  )
}

///|
test "default String.endsWith remains reusable after exhaustion" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"a\".repeat(100000) + \"b\"; " +
    "var needle = \"a\".repeat(100000) + \"c\"; " +
    "function endsWithLateMismatch() { return large.endsWith(needle); } " +
    "function smallEndsWith() { return \"abc\".endsWith(\"bc\"); }",
  )
  match
    engine.call_json_bounded(
      "endsWithLateMismatch",
      [],
      ends_with_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("large String.endsWith unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("smallEndsWith", []), content=true)
}
