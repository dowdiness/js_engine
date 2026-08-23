///|
fn candidate_ends_with_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid candidate endsWith execution policy")
  }
}

///|
fn expect_candidate_ends_with_result(
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
test "candidate String.endsWith observes the bounded execution budget" {
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
      candidate_ends_with_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("expected candidate String.endsWith to exhaust the budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "candidate String.endsWith preserves comparison boundaries" {
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
  expect_candidate_ends_with_result(
    engine.call_json_bounded(
      "firstHit",
      [],
      candidate_ends_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_candidate_ends_with_result(
    engine.call_json_bounded(
      "fullMatch",
      [],
      candidate_ends_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_candidate_ends_with_result(
    engine.call_json_bounded(
      "firstMismatch",
      [],
      candidate_ends_with_guardrail_policy(1000L),
    ),
    false,
  )
  expect_candidate_ends_with_result(
    engine.call_json_bounded(
      "emptySearch",
      [],
      candidate_ends_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_candidate_ends_with_result(
    engine.call_json_bounded(
      "negativePosition",
      [],
      candidate_ends_with_guardrail_policy(1000L),
    ),
    false,
  )
  expect_candidate_ends_with_result(
    engine.call_json_bounded(
      "positiveClamp",
      [],
      candidate_ends_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_candidate_ends_with_result(
    engine.call_json_bounded(
      "impossible",
      [],
      candidate_ends_with_guardrail_policy(1000L),
    ),
    false,
  )
}

///|
test "candidate String.endsWith completes with sufficient budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"a\".repeat(100000) + \"b\"; " +
    "var needle = \"a\".repeat(100000) + \"c\"; " +
    "function endsWithLateMismatch() { return large.endsWith(needle); }",
  )
  expect_candidate_ends_with_result(
    engine.call_json_bounded(
      "endsWithLateMismatch",
      [],
      candidate_ends_with_guardrail_policy(200000L),
    ),
    false,
  )
}

///|
test "candidate String.endsWith remains reusable after exhaustion" {
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
      candidate_ends_with_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("large candidate String.endsWith unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("smallEndsWith", []), content=true)
}
