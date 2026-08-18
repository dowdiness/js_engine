///|
fn fibonacci_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid Fibonacci execution policy")
  }
}

///|
test "candidate Fibonacci observes the bounded execution budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|function fib(n) {
      #|  if (n <= 1) return n;
      #|  return fib(n - 1) + fib(n - 2);
      #|}
    ),
  )
  match
    engine.call_json_bounded(
      "fib",
      [Json::number(30.0)],
      fibonacci_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("expected Fibonacci to exhaust the execution budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(
        diagnostic.engine_integrity() is @js_engine.EngineIntegrity::Unknown,
      )
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}
