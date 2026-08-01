///|
fn bounded_timer_policy(
  step_budget : Int64,
  stack_depth_limit : Int64,
  interruption : @js_engine.InterruptionHandle,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      stack_depth_limit,
      interruption,
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded timer policy")
  }
}

///|
test "zero bounded timer budget retains a pending timeout" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let count = 0;
      #|setTimeout(() => { count += 1; }, 0);
      #|function readCount() { return count; }
    ),
  )
  let result = engine.run_timer_checkpoint_bounded(
    bounded_timer_policy(0L, 10L, @js_engine.InterruptionHandle()),
  )
  match result {
    Ok(_) => fail("expected bounded timer checkpoint to reject")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="timer-checkpoint")
      inspect(diagnostic.phase_code(), content="timer-queue-dispatch")
      assert_true(diagnostic.engine_integrity() is @js_engine.EngineIntegrity::Discard)
      assert_true(
        diagnostic.retained_effects() is @js_engine.RetainedEffects::MayRemain,
      )
      assert_true(
        diagnostic.pending_jobs() is @js_engine.PendingJobs::Present,
      )
    }
  }
  assert_true(engine.has_pending_timers())
  json_inspect(engine.call_json("readCount", []), content=0)
  engine.run_timer_checkpoint()
  assert_false(engine.has_pending_timers())
  json_inspect(engine.call_json("readCount", []), content=1)
}
