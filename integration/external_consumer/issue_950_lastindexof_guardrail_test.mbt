///|
fn last_index_of_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid lastIndexOf execution policy")
  }
}

///|
fn expect_last_index_of_result(
  result : Result[Json, @js_engine.EngineDiagnostic],
  expected : Int,
) -> Unit raise Error {
  match result {
    Ok(value) => json_inspect(value, content=Json::number(expected.to_double()))
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "default String.lastIndexOf observes the bounded execution budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"x\".repeat(100000); " +
    "function lastIndexOfMissing() { return large.lastIndexOf(\"z\"); }",
  )
  match
    engine.call_json_bounded(
      "lastIndexOfMissing",
      [],
      last_index_of_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("expected String.lastIndexOf to exhaust the execution budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "default String.lastIndexOf preserves search boundaries and UTF-16 positions" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function firstHit() { return \"abc\".lastIndexOf(\"a\"); } " +
    "function nearEndHit() { return \"abcabc\".lastIndexOf(\"bc\"); } " +
    "function miss() { return \"abc\".lastIndexOf(\"z\"); } " +
    "function emptySearch() { return \"abc\".lastIndexOf(\"\", -Infinity); } " +
    "function emptyClamped() { return \"abc\".lastIndexOf(\"\", Infinity); } " +
    "function impossible() { return \"abc\".lastIndexOf(\"abcd\"); } " +
    "function negativeStart() { return \"abc\".lastIndexOf(\"b\", -3); } " +
    "function positiveClamp() { return \"abc\".lastIndexOf(\"a\", 99); } " +
    "function regexpSearch() { return \"abc\".lastIndexOf(/b/); } " +
    "function utf16Position() { return \"😀x\".lastIndexOf(\"x\"); }",
  )
  expect_last_index_of_result(
    engine.call_json_bounded("firstHit", [], last_index_of_guardrail_policy(1000L)),
    0,
  )
  expect_last_index_of_result(
    engine.call_json_bounded("nearEndHit", [], last_index_of_guardrail_policy(1000L)),
    4,
  )
  expect_last_index_of_result(
    engine.call_json_bounded("miss", [], last_index_of_guardrail_policy(1000L)),
    -1,
  )
  expect_last_index_of_result(
    engine.call_json_bounded(
      "emptySearch",
      [],
      last_index_of_guardrail_policy(1000L),
    ),
    0,
  )
  expect_last_index_of_result(
    engine.call_json_bounded(
      "emptyClamped",
      [],
      last_index_of_guardrail_policy(1000L),
    ),
    3,
  )
  expect_last_index_of_result(
    engine.call_json_bounded(
      "impossible",
      [],
      last_index_of_guardrail_policy(1000L),
    ),
    -1,
  )
  expect_last_index_of_result(
    engine.call_json_bounded(
      "negativeStart",
      [],
      last_index_of_guardrail_policy(1000L),
    ),
    -1,
  )
  expect_last_index_of_result(
    engine.call_json_bounded(
      "positiveClamp",
      [],
      last_index_of_guardrail_policy(1000L),
    ),
    0,
  )
  expect_last_index_of_result(
    engine.call_json_bounded(
      "regexpSearch",
      [],
      last_index_of_guardrail_policy(1000L),
    ),
    -1,
  )
  expect_last_index_of_result(
    engine.call_json_bounded(
      "utf16Position",
      [],
      last_index_of_guardrail_policy(1000L),
    ),
    2,
  )
}

///|
test "default String.lastIndexOf interrupts long common-prefix comparisons" {
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
      last_index_of_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("long String.lastIndexOf comparison unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "default String.lastIndexOf completes with sufficient budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"x\".repeat(100000); " +
    "function lastIndexOfMissing() { return large.lastIndexOf(\"z\"); }",
  )
  expect_last_index_of_result(
    engine.call_json_bounded(
      "lastIndexOfMissing",
      [],
      last_index_of_guardrail_policy(200000L),
    ),
    -1,
  )
}

///|
test "default String.lastIndexOf preserves coercion order and reuse" {
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
  expect_last_index_of_result(
    engine.call_json_bounded(
      "lastWithCoercion",
      [],
      last_index_of_guardrail_policy(1000L),
    ),
    1,
  )
  json_inspect(engine.call_json("readEvents", []), content="thissearchposition")
  json_inspect(engine.call_json("precedence", []), content=[true, true, true])
  match
    engine.call_json_bounded(
      "smallLastIndexOf",
      [],
      last_index_of_guardrail_policy(1000L),
    ) {
    Ok(value) => json_inspect(value, content=1)
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "default String.lastIndexOf remains reusable after exhaustion" {
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
      last_index_of_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("large String.lastIndexOf unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("smallLastIndexOf", []), content=1)
}
