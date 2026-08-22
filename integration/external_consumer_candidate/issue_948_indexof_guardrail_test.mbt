///|
fn candidate_index_of_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid candidate indexOf execution policy")
  }
}

///|
fn expect_candidate_index_of_result(
  result : Result[Json, @js_engine.EngineDiagnostic],
  expected : Int,
) -> Unit raise Error {
  match result {
    Ok(value) => json_inspect(value, content=Json::number(expected.to_double()))
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "candidate String.indexOf observes the bounded execution budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"x\".repeat(100000); " +
    "function indexOfMissing() { return large.indexOf(\"z\"); }",
  )
  match
    engine.call_json_bounded(
      "indexOfMissing",
      [],
      candidate_index_of_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("expected candidate String.indexOf to exhaust the budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "candidate String.indexOf preserves boundaries and UTF-16 positions" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function firstHit() { return \"abc\".indexOf(\"a\"); } " +
    "function nearEndHit() { return \"abc\".indexOf(\"bc\"); } " +
    "function emptySearch() { return \"abc\".indexOf(\"\", 99); } " +
    "function impossible() { return \"abc\".indexOf(\"abcd\"); } " +
    "function regexpSearch() { return \"abc\".indexOf(/b/); } " +
    "function utf16Position() { return \"😀x\".indexOf(\"x\"); }",
  )
  expect_candidate_index_of_result(
    engine.call_json_bounded(
      "firstHit",
      [],
      candidate_index_of_guardrail_policy(1000L),
    ),
    0,
  )
  expect_candidate_index_of_result(
    engine.call_json_bounded(
      "nearEndHit",
      [],
      candidate_index_of_guardrail_policy(1000L),
    ),
    1,
  )
  expect_candidate_index_of_result(
    engine.call_json_bounded(
      "emptySearch",
      [],
      candidate_index_of_guardrail_policy(1000L),
    ),
    3,
  )
  expect_candidate_index_of_result(
    engine.call_json_bounded(
      "impossible",
      [],
      candidate_index_of_guardrail_policy(1000L),
    ),
    -1,
  )
  expect_candidate_index_of_result(
    engine.call_json_bounded(
      "regexpSearch",
      [],
      candidate_index_of_guardrail_policy(1000L),
    ),
    -1,
  )
  expect_candidate_index_of_result(
    engine.call_json_bounded(
      "utf16Position",
      [],
      candidate_index_of_guardrail_policy(1000L),
    ),
    2,
  )
}

///|
test "candidate String.indexOf observes long common-prefix comparisons" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var haystack = \"a\".repeat(2000) + \"b\"; " +
    "var needle = \"a\".repeat(2000) + \"c\"; " +
    "function lateMismatch() { return haystack.indexOf(needle); }",
  )
  match
    engine.call_json_bounded(
      "lateMismatch",
      [],
      candidate_index_of_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("long candidate String.indexOf unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "candidate String.indexOf preserves coercion order and RegExp conversion" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var events = "";
      #|var receiver = { toString() { events = events + "this"; return "abc"; } };
      #|var search = { toString() { events = events + "search"; return "bc"; } };
      #|var position = { valueOf() { events = events + "position"; return 0; } };
      #|function indexWithCoercion() { return String.prototype.indexOf.call(receiver, search, position); }
      #|function readEvents() { return events; }
      #|function precedence() {
      #|  var result = [];
      #|  try { String.prototype.indexOf.call(null, "x"); } catch (error) { result.push(error instanceof TypeError); }
      #|  var throwingSearch = { toString() { throw "search"; } };
      #|  try { "abc".indexOf(throwingSearch); } catch (error) { result.push(error === "search"); }
      #|  var throwingPosition = { valueOf() { throw "position"; } };
      #|  try { "abc".indexOf("a", throwingPosition); } catch (error) { result.push(error === "position"); }
      #|  return result;
      #|}
    ),
  )
  expect_candidate_index_of_result(
    engine.call_json_bounded(
      "indexWithCoercion",
      [],
      candidate_index_of_guardrail_policy(1000L),
    ),
    1,
  )
  json_inspect(engine.call_json("readEvents", []), content="thissearchposition")
  json_inspect(engine.call_json("precedence", []), content=[true, true, true])
}

///|
test "candidate String.indexOf remains reusable after exhaustion" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"x\".repeat(100000); " +
    "function indexOfMissing() { return large.indexOf(\"z\"); } " +
    "function smallIndexOf() { return \"abc\".indexOf(\"bc\"); }",
  )
  match
    engine.call_json_bounded(
      "indexOfMissing",
      [],
      candidate_index_of_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("large candidate String.indexOf unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("smallIndexOf", []), content=1)
}
