///|
fn repeat_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid repeat execution policy")
  }
}

///|
test "candidate String.repeat observes the bounded execution budget" {
  let engine = @js_engine.Engine()
  engine.eval("function repeatLength() { return \"x\".repeat(100000).length; }")
  match
    engine.call_json_bounded("repeatLength", [], repeat_guardrail_policy(1000L)) {
    Ok(_) => fail("expected String.repeat to exhaust the execution budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "candidate String.repeat preserves coercion and error precedence" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var events = "";
      #|var receiver = { toString() { events = events + "s"; return "x"; } };
      #|var count = { valueOf() { events = events + "n"; return 100000; } };
      #|function repeatWithCoercion() {
      #|  return String.prototype.repeat.call(receiver, count);
      #|}
      #|function readEvents() { return events; }
      #|function precedence() {
      #|  var result = [];
      #|  try { "x".repeat(-1); } catch (error) { result.push(error instanceof RangeError); }
      #|  try { "x".repeat(Infinity); } catch (error) { result.push(error instanceof RangeError); }
      #|  try { String.prototype.repeat.call(null, 1); } catch (error) { result.push(error instanceof TypeError); }
      #|  var throwingCount = { valueOf() { throw "count"; } };
      #|  try { "x".repeat(throwingCount); } catch (error) { result.push(error === "count"); }
      #|  return result;
      #|}
    ),
  )
  match
    engine.call_json_bounded(
      "repeatWithCoercion",
      [],
      repeat_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("coercing String.repeat unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("readEvents", []), content="sn")
  json_inspect(engine.call_json("precedence", []), content=[
    true, true, true, true,
  ])
}

///|
test "candidate String.repeat completes at zero and with sufficient budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function emptyRepeat() { return \"x\".repeat(0); } " +
    "function smallRepeat() { return \"ab\".repeat(3); }",
  )
  match
    engine.call_json_bounded("emptyRepeat", [], repeat_guardrail_policy(1000L)) {
    Ok(value) => json_inspect(value, content="")
    Err(diagnostic) => fail(diagnostic.message())
  }
  match
    engine.call_json_bounded("smallRepeat", [], repeat_guardrail_policy(1000L)) {
    Ok(value) => json_inspect(value, content="ababab")
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "candidate String.repeat leaves the Engine reusable after exhaustion" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function largeRepeat() { return \"x\".repeat(100000); } " +
    "function smallRepeat() { return \"ab\".repeat(3); }",
  )
  match
    engine.call_json_bounded("largeRepeat", [], repeat_guardrail_policy(1000L)) {
    Ok(_) => fail("large String.repeat unexpectedly completed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("smallRepeat", []), content="ababab")
}
