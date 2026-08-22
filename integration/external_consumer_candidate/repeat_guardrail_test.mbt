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
  engine.eval(
    "function repeatLength() { return \"x\".repeat(100000).length; }",
  )
  match
    engine.call_json_bounded(
      "repeatLength",
      [],
      repeat_guardrail_policy(1000L),
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
