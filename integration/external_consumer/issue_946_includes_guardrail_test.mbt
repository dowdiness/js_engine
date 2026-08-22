///|
fn default_includes_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid includes execution policy")
  }
}

///|
fn expect_default_includes_result(
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
test "default String.includes observes the bounded execution budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"x\".repeat(100000); " +
    "function includesMissing() { return large.includes(\"z\"); }",
  )
  match
    engine.call_json_bounded(
      "includesMissing",
      [],
      default_includes_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("expected String.includes to exhaust the execution budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "default String.includes preserves coercion and error precedence" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var events = "";
      #|var receiver = { toString() { events = events + "this"; return "abc"; } };
      #|var search = { toString() { events = events + "search"; return "bc"; } };
      #|Object.defineProperty(search, Symbol.match, {
      #|  get() { events = events + "match"; return false; }
      #|});
      #|var position = { valueOf() { events = events + "position"; return 0; } };
      #|function includesWithCoercion() {
      #|  return String.prototype.includes.call(receiver, search, position);
      #|}
      #|function readEvents() { return events; }
      #|function precedence() {
      #|  var result = [];
      #|  try { String.prototype.includes.call(null, "x"); } catch (error) { result.push(error instanceof TypeError); }
      #|  try { "abc".includes(/x/); } catch (error) { result.push(error instanceof TypeError); }
      #|  var throwingSearch = { toString() { throw "search"; } };
      #|  try { "abc".includes(throwingSearch); } catch (error) { result.push(error === "search"); }
      #|  var throwingPosition = { valueOf() { throw "position"; } };
      #|  try { "abc".includes("a", throwingPosition); } catch (error) { result.push(error === "position"); }
      #|  return result;
      #|}
    ),
  )
  expect_default_includes_result(
    engine.call_json_bounded(
      "includesWithCoercion",
      [],
      default_includes_guardrail_policy(1000L),
    ),
    true,
  )
  json_inspect(engine.call_json("readEvents", []), content="thismatchsearchposition")
  json_inspect(engine.call_json("precedence", []), content=[
    true, true, true, true,
  ])
}

///|
test "default String.includes preserves normal search boundaries" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function firstHit() { return \"abc\".includes(\"a\"); } " +
    "function nearEndHit() { return \"abc\".includes(\"bc\"); } " +
    "function emptySearch() { return \"abc\".includes(\"\"); } " +
    "function clampedPosition() { return \"abc\".includes(\"a\", 99); } " +
    "function longNeedle() { return \"abc\".includes(\"abcd\"); }",
  )
  expect_default_includes_result(
    engine.call_json_bounded(
      "firstHit",
      [],
      default_includes_guardrail_policy(1000L),
    ),
    true,
  )
  expect_default_includes_result(
    engine.call_json_bounded(
      "nearEndHit",
      [],
      default_includes_guardrail_policy(1000L),
    ),
    true,
  )
  expect_default_includes_result(
    engine.call_json_bounded(
      "emptySearch",
      [],
      default_includes_guardrail_policy(1000L),
    ),
    true,
  )
  expect_default_includes_result(
    engine.call_json_bounded(
      "clampedPosition",
      [],
      default_includes_guardrail_policy(1000L),
    ),
    false,
  )
  expect_default_includes_result(
    engine.call_json_bounded(
      "longNeedle",
      [],
      default_includes_guardrail_policy(1000L),
    ),
    false,
  )
}

///|
test "default String.includes observes a late long-needle mismatch" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var haystack = \"x\".repeat(1000) + \"y\"; " +
    "var needle = \"x\".repeat(1000) + \"z\"; " +
    "function lateMismatch() { return haystack.includes(needle); }",
  )
  match
    engine.call_json_bounded(
      "lateMismatch",
      [],
      default_includes_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("late long-needle mismatch unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "default String.includes remains reusable after exhaustion" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = \"x\".repeat(100000); " +
    "function includesMissing() { return large.includes(\"z\"); } " +
    "function smallIncludes() { return \"abc\".includes(\"bc\"); }",
  )
  match
    engine.call_json_bounded(
      "includesMissing",
      [],
      default_includes_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("large String.includes unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("smallIncludes", []), content=true)
}
