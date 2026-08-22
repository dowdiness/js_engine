///|
fn repeat_default_guardrail_policy(
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
test "default String.repeat observes the bounded execution budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function repeatLength() { return \"x\".repeat(100000).length; }",
  )
  match
    engine.call_json_bounded(
      "repeatLength",
      [],
      repeat_default_guardrail_policy(1000L),
    ) {
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
test "default String.repeat preserves normal completion" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function emptyRepeat() { return \"x\".repeat(0); } " +
    "function smallRepeat() { return \"ab\".repeat(3); }",
  )
  match
    engine.call_json_bounded(
      "emptyRepeat",
      [],
      repeat_default_guardrail_policy(1000L),
    ) {
    Ok(value) => json_inspect(value, content="")
    Err(diagnostic) => fail(diagnostic.message())
  }
  match
    engine.call_json_bounded(
      "smallRepeat",
      [],
      repeat_default_guardrail_policy(1000L),
    ) {
    Ok(value) => json_inspect(value, content="ababab")
    Err(diagnostic) => fail(diagnostic.message())
  }
}
