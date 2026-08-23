///|
fn candidate_last_index_of_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid candidate lastIndexOf execution policy")
  }
}

///|
fn expect_candidate_last_index_of_result(
  result : Result[Json, @js_engine.EngineDiagnostic],
  expected : Int,
) -> Unit raise Error {
  match result {
    Ok(value) => json_inspect(value, content=Json::number(expected.to_double()))
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "candidate String.lastIndexOf observes the bounded execution budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"x\".repeat(100000); " +
    "function lastIndexOfMissing() { return large.lastIndexOf(\"z\"); }",
  )
  match
    engine.call_json_bounded(
      "lastIndexOfMissing",
      [],
      candidate_last_index_of_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("expected candidate String.lastIndexOf to exhaust the budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "candidate String.lastIndexOf preserves boundaries and UTF-16 positions" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function firstHit() { return \"abc\".lastIndexOf(\"a\"); } " +
    "function nearEndHit() { return \"abcabc\".lastIndexOf(\"bc\"); } " +
    "function emptySearch() { return \"abc\".lastIndexOf(\"\", -Infinity); } " +
    "function emptyClamped() { return \"abc\".lastIndexOf(\"\", Infinity); } " +
    "function impossible() { return \"abc\".lastIndexOf(\"abcd\"); } " +
    "function negativeStart() { return \"abc\".lastIndexOf(\"b\", -3); } " +
    "function regexpSearch() { return \"abc\".lastIndexOf(/b/); } " +
    "function utf16Position() { return \"😀x\".lastIndexOf(\"x\"); }",
  )
  expect_candidate_last_index_of_result(
    engine.call_json_bounded(
      "firstHit",
      [],
      candidate_last_index_of_guardrail_policy(1000L),
    ),
    0,
  )
  expect_candidate_last_index_of_result(
    engine.call_json_bounded(
      "nearEndHit",
      [],
      candidate_last_index_of_guardrail_policy(1000L),
    ),
    4,
  )
  expect_candidate_last_index_of_result(
    engine.call_json_bounded(
      "emptySearch",
      [],
      candidate_last_index_of_guardrail_policy(1000L),
    ),
    0,
  )
  expect_candidate_last_index_of_result(
    engine.call_json_bounded(
      "emptyClamped",
      [],
      candidate_last_index_of_guardrail_policy(1000L),
    ),
    3,
  )
  expect_candidate_last_index_of_result(
    engine.call_json_bounded(
      "impossible",
      [],
      candidate_last_index_of_guardrail_policy(1000L),
    ),
    -1,
  )
  expect_candidate_last_index_of_result(
    engine.call_json_bounded(
      "negativeStart",
      [],
      candidate_last_index_of_guardrail_policy(1000L),
    ),
    -1,
  )
  expect_candidate_last_index_of_result(
    engine.call_json_bounded(
      "regexpSearch",
      [],
      candidate_last_index_of_guardrail_policy(1000L),
    ),
    -1,
  )
  expect_candidate_last_index_of_result(
    engine.call_json_bounded(
      "utf16Position",
      [],
      candidate_last_index_of_guardrail_policy(1000L),
    ),
    2,
  )
}

///|
test "candidate String.lastIndexOf interrupts long common-prefix comparisons" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var haystack = \"a\".repeat(2000) + \"b\"; " +
    "var needle = \"a\".repeat(2000) + \"c\"; " +
    "function lateMismatch() { return haystack.lastIndexOf(needle); }",
  )
  match
    engine.call_json_bounded(
      "lateMismatch",
      [],
      candidate_last_index_of_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("long candidate String.lastIndexOf unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "candidate String.lastIndexOf preserves coercion order and reuse" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var events = "";
      #|var receiver = { toString() { events = events + "this"; return "abc"; } };
      #|var search = { toString() { events = events + "search"; return "bc"; } };
      #|var position = { valueOf() { events = events + "position"; return 2; } };
      #|function lastWithCoercion() { return String.prototype.lastIndexOf.call(receiver, search, position); }
      #|function readEvents() { return events; }
      #|function precedence() {
      #|  var result = [];
      #|  try { String.prototype.lastIndexOf.call(null, "x"); } catch (error) { result.push(error instanceof TypeError); }
      #|  var throwingSearch = { toString() { throw "search"; } };
      #|  try { "abc".lastIndexOf(throwingSearch); } catch (error) { result.push(error === "search"); }
      #|  var throwingPosition = { valueOf() { throw "position"; } };
      #|  try { "abc".lastIndexOf("a", throwingPosition); } catch (error) { result.push(error === "position"); }
      #|  return result;
      #|}
      #|function smallLastIndexOf() { return "abc".lastIndexOf("bc"); }
    ),
  )
  expect_candidate_last_index_of_result(
    engine.call_json_bounded(
      "lastWithCoercion",
      [],
      candidate_last_index_of_guardrail_policy(1000L),
    ),
    1,
  )
  json_inspect(engine.call_json("readEvents", []), content="thissearchposition")
  json_inspect(engine.call_json("precedence", []), content=[true, true, true])
  expect_candidate_last_index_of_result(
    engine.call_json_bounded(
      "smallLastIndexOf",
      [],
      candidate_last_index_of_guardrail_policy(1000L),
    ),
    1,
  )
}

///|
test "candidate String.lastIndexOf remains reusable after exhaustion" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"x\".repeat(100000); " +
    "function largeLastIndexOf() { return large.lastIndexOf(\"z\"); } " +
    "function smallLastIndexOf() { return \"abc\".lastIndexOf(\"bc\"); }",
  )
  match
    engine.call_json_bounded(
      "largeLastIndexOf",
      [],
      candidate_last_index_of_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("large candidate String.lastIndexOf unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("smallLastIndexOf", []), content=1)
}
