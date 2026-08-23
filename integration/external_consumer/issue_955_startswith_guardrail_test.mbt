///|
fn starts_with_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid startsWith execution policy")
  }
}

///|
test "RED: default String.startsWith search must reach execution limit" {
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
      starts_with_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("startsWith search must be interruptible")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
}

///|
fn expect_starts_with_result(
  result : Result[Json, @js_engine.EngineDiagnostic],
  expected : Bool,
) -> Unit raise Error {
  match result {
    Ok(value) => {
      if expected {
        json_inspect(value, content=true)
      } else {
        json_inspect(value, content=false)
      }
    }
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "default String.startsWith preserves comparison boundaries and position clamping" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function firstHit() { return \"abc\".startsWith(\"a\"); } " +
    "function fullMatch() { return \"abc\".startsWith(\"abc\"); } " +
    "function firstMismatch() { return \"abc\".startsWith(\"z\"); } " +
    "function offsetMismatch() { return \"abc\".startsWith(\"bc\", 1); } " +
    "function emptySearch() { return \"abc\".startsWith(\"\", 99); } " +
    "function negativePosition() { return \"abc\".startsWith(\"a\", -1); } " +
    "function positiveClamp() { return \"abc\".startsWith(\"a\", 99); } " +
    "function impossible() { return \"abc\".startsWith(\"abcd\"); }",
  )
  expect_starts_with_result(
    engine.call_json_bounded(
      "firstHit",
      [],
      starts_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_starts_with_result(
    engine.call_json_bounded(
      "fullMatch",
      [],
      starts_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_starts_with_result(
    engine.call_json_bounded(
      "firstMismatch",
      [],
      starts_with_guardrail_policy(1000L),
    ),
    false,
  )
  expect_starts_with_result(
    engine.call_json_bounded(
      "offsetMismatch",
      [],
      starts_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_starts_with_result(
    engine.call_json_bounded(
      "emptySearch",
      [],
      starts_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_starts_with_result(
    engine.call_json_bounded(
      "negativePosition",
      [],
      starts_with_guardrail_policy(1000L),
    ),
    true,
  )
  expect_starts_with_result(
    engine.call_json_bounded(
      "positiveClamp",
      [],
      starts_with_guardrail_policy(1000L),
    ),
    false,
  )
  expect_starts_with_result(
    engine.call_json_bounded(
      "impossible",
      [],
      starts_with_guardrail_policy(1000L),
    ),
    false,
  )
}

///|
test "default String.startsWith preserves coercion and error precedence" {
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
  expect_starts_with_result(
    engine.call_json_bounded(
      "startsWithWithCoercion",
      [],
      starts_with_guardrail_policy(1000L),
    ),
    true,
  )
  json_inspect(engine.call_json("readEvents", []), content="thismatchsearchposition")
  json_inspect(engine.call_json("precedence", []), content=[true, true, true, true])
}

///|
test "default String.startsWith completes with sufficient budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"a\".repeat(100000) + \"b\"; " +
    "var needle = \"a\".repeat(100000) + \"c\"; " +
    "function startsWithLateMismatch() { return large.startsWith(needle); }",
  )
  expect_starts_with_result(
    engine.call_json_bounded(
      "startsWithLateMismatch",
      [],
      starts_with_guardrail_policy(200000L),
    ),
    false,
  )
}

///|
test "default String.startsWith remains reusable after exhaustion" {
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
      starts_with_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("large String.startsWith unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("smallStartsWith", []), content=true)
}
