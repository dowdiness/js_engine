///|
fn candidate_starts_with_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid candidate startsWith execution policy")
  }
}

///|
fn expect_candidate_starts_with_result(
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
test "candidate String.startsWith observes the bounded execution budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"a\".repeat(100000) + \"b\"; " +
    "var needle = \"a\".repeat(100000) + \"c\"; " +
    "function startsWithLateMismatch() { return large.startsWith(needle); }",
  )
  match
    engine.call_json_bounded(
      "startsWithLateMismatch",
      [],
      candidate_starts_with_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("expected candidate String.startsWith to exhaust the budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "candidate String.startsWith preserves comparison boundaries and position clamping" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function firstHit() { return \"abc\".startsWith(\"a\"); } " +
    "function fullMatch() { return \"abc\".startsWith(\"abc\"); } " +
    "function firstMismatch() { return \"abc\".startsWith(\"z\"); } " +
    "function offsetMatch() { return \"abc\".startsWith(\"bc\", 1); } " +
    "function emptySearch() { return \"abc\".startsWith(\"\", 99); } " +
    "function negativePosition() { return \"abc\".startsWith(\"a\", -1); } " +
    "function positiveClamp() { return \"abc\".startsWith(\"a\", 99); } " +
    "function impossible() { return \"abc\".startsWith(\"abcd\"); }",
  )
  expect_candidate_starts_with_result(
    engine.call_json_bounded(
      "firstHit",
      [],
      candidate_starts_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_candidate_starts_with_result(
    engine.call_json_bounded(
      "fullMatch",
      [],
      candidate_starts_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_candidate_starts_with_result(
    engine.call_json_bounded(
      "firstMismatch",
      [],
      candidate_starts_with_guardrail_policy(1000L),
    ),
    false,
  )
  expect_candidate_starts_with_result(
    engine.call_json_bounded(
      "offsetMatch",
      [],
      candidate_starts_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_candidate_starts_with_result(
    engine.call_json_bounded(
      "emptySearch",
      [],
      candidate_starts_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_candidate_starts_with_result(
    engine.call_json_bounded(
      "negativePosition",
      [],
      candidate_starts_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_candidate_starts_with_result(
    engine.call_json_bounded(
      "positiveClamp",
      [],
      candidate_starts_with_guardrail_policy(1000L),
    ),
    false,
  )
  expect_candidate_starts_with_result(
    engine.call_json_bounded(
      "impossible",
      [],
      candidate_starts_with_guardrail_policy(1000L),
    ),
    false,
  )
}

///|
test "candidate String.startsWith preserves coercion and error precedence" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var events = "";
      #|var receiver = { toString() { events = events + "this"; return "abc"; } };
      #|var search = { toString() { events = events + "search"; return "a"; } };
      #|Object.defineProperty(search, Symbol.match, {
      #|  get() { events = events + "match"; return false; }
      #|});
      #|var position = { valueOf() { events = events + "position"; return 0; } };
      #|function startsWithWithCoercion() {
      #|  return String.prototype.startsWith.call(receiver, search, position);
      #|}
      #|function readEvents() { return events; }
      #|function precedence() {
      #|  var result = [];
      #|  try { String.prototype.startsWith.call(null, "x"); } catch (error) { result.push(error instanceof TypeError); }
      #|  try { "abc".startsWith(/x/); } catch (error) { result.push(error instanceof TypeError); }
      #|  var throwingSearch = { toString() { throw "search"; } };
      #|  try { "abc".startsWith(throwingSearch); } catch (error) { result.push(error === "search"); }
      #|  var throwingPosition = { valueOf() { throw "position"; } };
      #|  try { "abc".startsWith("a", throwingPosition); } catch (error) { result.push(error === "position"); }
      #|  return result;
      #|}
    ),
  )
  expect_candidate_starts_with_result(
    engine.call_json_bounded(
      "startsWithWithCoercion",
      [],
      candidate_starts_with_guardrail_policy(1000L),
    ),
    true,
  )
  json_inspect(
    engine.call_json("readEvents", []),
    content="thismatchsearchposition",
  )
  json_inspect(engine.call_json("precedence", []), content=[
    true, true, true, true,
  ])
}

///|
test "candidate String.startsWith completes with sufficient budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"a\".repeat(100000) + \"b\"; " +
    "var needle = \"a\".repeat(100000) + \"c\"; " +
    "function startsWithLateMismatch() { return large.startsWith(needle); }",
  )
  expect_candidate_starts_with_result(
    engine.call_json_bounded(
      "startsWithLateMismatch",
      [],
      candidate_starts_with_guardrail_policy(200000L),
    ),
    false,
  )
}

///|
test "candidate String.startsWith remains reusable after exhaustion" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"a\".repeat(100000) + \"b\"; " +
    "var needle = \"a\".repeat(100000) + \"c\"; " +
    "function startsWithLateMismatch() { return large.startsWith(needle); } " +
    "function smallStartsWith() { return \"abc\".startsWith(\"bc\", 1); }",
  )
  match
    engine.call_json_bounded(
      "startsWithLateMismatch",
      [],
      candidate_starts_with_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("large candidate String.startsWith unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("smallStartsWith", []), content=true)
}
