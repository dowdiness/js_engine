///|
fn index_of_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid indexOf execution policy")
  }
}

///|
test "default String.indexOf observes the bounded execution budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"x\".repeat(100000); " +
    "function indexOfMissing() { return large.indexOf(\"z\"); }",
  )
  match
    engine.call_json_bounded(
      "indexOfMissing",
      [],
      index_of_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("expected String.indexOf to exhaust the execution budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
fn expect_index_of_result(
  result : Result[Json, @js_engine.EngineDiagnostic],
  expected : Int,
) -> Unit raise Error {
  match result {
    Ok(value) => json_inspect(value, content=Json::number(expected.to_double()))
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "default String.indexOf preserves search boundaries and UTF-16 positions" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function firstHit() { return \"abc\".indexOf(\"a\"); } " +
    "function nearEndHit() { return \"abc\".indexOf(\"bc\"); } " +
    "function miss() { return \"abc\".indexOf(\"z\"); } " +
    "function emptySearch() { return \"abc\".indexOf(\"\", 99); } " +
    "function impossible() { return \"abc\".indexOf(\"abcd\"); } " +
    "function clampedStart() { return \"abc\".indexOf(\"a\", 99); } " +
    "function negativeStart() { return \"abc\".indexOf(\"b\", -3); } " +
    "function regexpSearch() { return \"abc\".indexOf(/b/); } " +
    "function utf16Position() { return \"😀x\".indexOf(\"x\"); }",
  )
  expect_index_of_result(
    engine.call_json_bounded("firstHit", [], index_of_guardrail_policy(1000L)),
    0,
  )
  expect_index_of_result(
    engine.call_json_bounded("nearEndHit", [], index_of_guardrail_policy(1000L)),
    1,
  )
  expect_index_of_result(
    engine.call_json_bounded("miss", [], index_of_guardrail_policy(1000L)),
    -1,
  )
  expect_index_of_result(
    engine.call_json_bounded(
      "emptySearch",
      [],
      index_of_guardrail_policy(1000L),
    ),
    3,
  )
  expect_index_of_result(
    engine.call_json_bounded(
      "impossible",
      [],
      index_of_guardrail_policy(1000L),
    ),
    -1,
  )
  expect_index_of_result(
    engine.call_json_bounded(
      "clampedStart",
      [],
      index_of_guardrail_policy(1000L),
    ),
    -1,
  )
  expect_index_of_result(
    engine.call_json_bounded(
      "negativeStart",
      [],
      index_of_guardrail_policy(1000L),
    ),
    1,
  )
  expect_index_of_result(
    engine.call_json_bounded(
      "regexpSearch",
      [],
      index_of_guardrail_policy(1000L),
    ),
    -1,
  )
  expect_index_of_result(
    engine.call_json_bounded(
      "utf16Position",
      [],
      index_of_guardrail_policy(1000L),
    ),
    2,
  )
}

///|
test "default String.indexOf interrupts long common-prefix comparisons" {
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
      index_of_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("long String.indexOf comparison unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "default String.indexOf completes with sufficient budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"x\".repeat(100000); " +
    "function indexOfMissing() { return large.indexOf(\"z\"); }",
  )
  expect_index_of_result(
    engine.call_json_bounded(
      "indexOfMissing",
      [],
      index_of_guardrail_policy(200000L),
    ),
    -1,
  )
}

///|
test "default String.indexOf preserves coercion order and RegExp conversion" {
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
  expect_index_of_result(
    engine.call_json_bounded(
      "indexWithCoercion",
      [],
      index_of_guardrail_policy(1000L),
    ),
    1,
  )
  json_inspect(engine.call_json("readEvents", []), content="thissearchposition")
  json_inspect(engine.call_json("precedence", []), content=[true, true, true])
}

///|
test "default String.indexOf remains reusable after exhaustion" {
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
      index_of_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("large String.indexOf unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("smallIndexOf", []), content=1)
}
