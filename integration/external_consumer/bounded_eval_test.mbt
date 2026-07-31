///| 
test "external consumer can call the bounded eval facade" {
  let interruption = @js_engine.InterruptionHandle()
  let policy_result = @js_engine.ExecutionPolicy(
    step_budget=256L,
    stack_depth_limit=1L,
    interruption~,
  )
  let policy = match policy_result {
    Ok(policy) => policy
    Err(_) => fail("expected valid bounded policy")
  }
  let engine = @js_engine.Engine()
  assert_true(
    engine.eval_bounded("1;", policy, source_id="bounded.js") is Ok(_),
  )
}
