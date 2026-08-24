///|
fn locale_compare_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid localeCompare execution policy")
  }
}

///|
test "default String.localeCompare fails closed before opaque comparison" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var localeLeft = 'a'.repeat(2000) + 'b'; " +
    "var localeRight = 'a'.repeat(2000) + 'c'; " +
    "function compareLocaleLarge() { " +
    "return localeLeft.localeCompare(localeRight); }",
  )
  let policy = match
    @js_engine.ExecutionPolicy::new(
      1000L,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid issue-975 entry policy")
  }
  match engine.call_json_bounded("compareLocaleLarge", [], policy) {
    Ok(_) => fail("localeCompare must fail closed before opaque comparison")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "default String.localeCompare preserves unbounded ordering" {
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
test "default String.localeCompare leaves the Engine reusable after rejection" {
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
      locale_compare_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("large localeCompare unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("compareLocaleSmall", []), content=-1)
}

///|
test "default String.localeCompare coerces receiver and argument before guard" {
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
      locale_compare_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("localeCompare guard must run after both conversions")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(engine.call_json("readEvents", []), content="ra")
}

///|
test "default String.localeCompare conversion throws precede the guard" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var receiver = { toString() { throw 'receiver-conversion'; } }; " +
    "var argument = { toString() { throw 'argument-conversion'; } }; " +
    "function receiverThrows() { " +
    "return String.prototype.localeCompare.call(receiver, 'b'); } " +
    "function argumentThrows() { " +
    "return 'a'.localeCompare(argument); }",
  )
  for function_name in ["receiverThrows", "argumentThrows"] {
    match
      engine.call_json_bounded(
        function_name,
        [],
        locale_compare_guardrail_policy(1000L),
      ) {
      Ok(_) => fail("conversion throw must precede localeCompare guard")
      Err(diagnostic) =>
        inspect(diagnostic.failure_kind_code(), content="javascript-exception")
    }
  }
}

///|
test "default String.normalize remains its bounded identity stub" {
  let engine = @js_engine.Engine()
  engine.eval("function normalizeValue() { return 'abc'.normalize(); }")
  match
    engine.call_json_bounded(
      "normalizeValue",
      [],
      locale_compare_guardrail_policy(1000L),
    ) {
    Ok(value) => json_inspect(value, content="abc")
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "default String RegExp symbol protocols remain custom-dispatchable" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var custom = {}; " +
    "custom[Symbol.matchAll] = function(value) { return 'custom:' + value; }; " +
    "custom[Symbol.search] = function(value) { return 'search:' + value; }; " +
    "function customProtocols() { return [" +
    "String.prototype.matchAll.call('subject', custom), " +
    "String.prototype.search.call('subject', custom)" +
    "]; }",
  )
  json_inspect(
    engine.call_json("customProtocols", []),
    content=["custom:subject", "search:subject"],
  )
}
