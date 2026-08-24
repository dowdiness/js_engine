///|
fn candidate_locale_compare_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid candidate localeCompare policy")
  }
}

///|
test "candidate String.localeCompare fails closed before opaque comparison" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var localeLeft = 'a'.repeat(2000) + 'b'; " +
    "var localeRight = 'a'.repeat(2000) + 'c'; " +
    "function compareLocaleLarge() { return localeLeft.localeCompare(localeRight); }",
  )
  match
    engine.call_json_bounded(
      "compareLocaleLarge",
      [],
      candidate_locale_compare_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("candidate localeCompare must fail closed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "candidate String.localeCompare preserves unbounded ordering" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function compareLocaleValues() { return [" +
    "'a'.localeCompare('b'), " +
    "'b'.localeCompare('a'), " +
    "'a'.localeCompare('a')" +
    "]; }",
  )
  json_inspect(engine.call_json("compareLocaleValues", []), content=[-1, 1, 0])
}

///|
test "candidate String.localeCompare preserves coercion order" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var events = ''; " +
    "var receiver = { toString() { events += 'r'; return 'a'; } }; " +
    "var argument = { toString() { events += 'a'; return 'b'; } }; " +
    "function compareCoercions() { " +
    "return String.prototype.localeCompare.call(receiver, argument); } " +
    "function readEvents() { return events; }",
  )
  match
    engine.call_json_bounded(
      "compareCoercions",
      [],
      candidate_locale_compare_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("candidate guard must follow both conversions")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(engine.call_json("readEvents", []), content="ra")
}

///|
test "candidate String.localeCompare leaves the Engine reusable" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var localeLeft = 'a'.repeat(2000) + 'b'; " +
    "var localeRight = 'a'.repeat(2000) + 'c'; " +
    "function compareLocaleLarge() { return localeLeft.localeCompare(localeRight); } " +
    "function compareLocaleSmall() { return 'a'.localeCompare('b'); }",
  )
  match
    engine.call_json_bounded(
      "compareLocaleLarge",
      [],
      candidate_locale_compare_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("large candidate localeCompare unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("compareLocaleSmall", []), content=-1)
}

///|
test "candidate String.normalize remains its bounded identity stub" {
  let engine = @js_engine.Engine()
  engine.eval("function normalizeValue() { return 'abc'.normalize(); }")
  match
    engine.call_json_bounded(
      "normalizeValue",
      [],
      candidate_locale_compare_guardrail_policy(1000L),
    ) {
    Ok(value) => json_inspect(value, content="abc")
    Err(diagnostic) => fail(diagnostic.message())
  }
}
