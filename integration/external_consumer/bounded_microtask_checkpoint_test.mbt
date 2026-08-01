///|
fn bounded_microtask_policy(
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
    Err(_) => fail("expected a valid bounded microtask policy")
  }
}

///|
fn expect_microtask_guardrail(
  result : Result[Bool, @js_engine.EngineDiagnostic],
  kind : String,
  pending : @js_engine.PendingJobs,
) -> @js_engine.EngineDiagnostic raise Error {
  match result {
    Ok(_) => fail("expected bounded microtask checkpoint to reject")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content=kind)
      inspect(diagnostic.operation_code(), content="microtask-checkpoint")
      inspect(diagnostic.phase_code(), content="microtask-dispatch")
      assert_true(
        diagnostic.engine_integrity() is @js_engine.EngineIntegrity::Discard,
      )
      assert_true(
        diagnostic.retained_effects() is @js_engine.RetainedEffects::MayRemain,
      )
      assert_true(
        match (diagnostic.pending_jobs(), pending) {
          (@js_engine.PendingJobs::None, @js_engine.PendingJobs::None) => true
          (@js_engine.PendingJobs::Present, @js_engine.PendingJobs::Present) =>
            true
          (@js_engine.PendingJobs::Unknown, @js_engine.PendingJobs::Unknown) =>
            true
          _ => false
        },
      )
      diagnostic
    }
  }
}

///|
test "empty bounded microtask checkpoint succeeds with zero budget" {
  let engine = @js_engine.Engine()
  match
    engine.run_microtask_checkpoint_bounded(
      bounded_microtask_policy(0L, 0L, @js_engine.InterruptionHandle()),
    ) {
    Ok(has_more) => assert_false(has_more)
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "zero budget rejects before selecting a pending microtask" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|queueMicrotask(() => events.push("ran"));
      #|function snapshot() { return events; }
    ),
  )
  assert_true(engine.has_pending_microtasks())
  ignore(
    expect_microtask_guardrail(
      engine.run_microtask_checkpoint_bounded(
        bounded_microtask_policy(0L, 10L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      @js_engine.PendingJobs::Present,
    ),
  )
  assert_true(engine.has_pending_microtasks())
  json_inspect(engine.call_json("snapshot", []), content=[])
}

///|
test "pre-requested interruption rejects before selecting a microtask" {
  let engine = @js_engine.Engine()
  engine.eval("queueMicrotask(() => {});")
  let interruption = @js_engine.InterruptionHandle()
  interruption.request()
  ignore(
    expect_microtask_guardrail(
      engine.run_microtask_checkpoint_bounded(
        bounded_microtask_policy(0L, 0L, interruption),
      ),
      "interrupted",
      @js_engine.PendingJobs::Present,
    ),
  )
  assert_true(engine.has_pending_microtasks())
}

///|
test "activation rejection consumes the selected microtask" {
  let engine = @js_engine.Engine()
  assert_true(
    engine.eval_diagnostic(
      (
        #|function f(n) {
        #|  if (n === 0) return 0;
        #|  return 1 + f(n - 1);
        #|}
        #|queueMicrotask(() => f(256));
      ),
      source_id="activation-rejection.js",
    )
    is Ok(_),
  )
  let diagnostic = expect_microtask_guardrail(
      engine.run_microtask_checkpoint_bounded(
        bounded_microtask_policy(1000L, 0L, @js_engine.InterruptionHandle()),
      ),
      "stack-depth-limit",
      @js_engine.PendingJobs::None,
    )
  assert_true(diagnostic.source_identity() == Some("activation-rejection.js"))
  assert_false(engine.has_pending_microtasks())
}

///|
test "Promise reaction cannot swallow a checkpoint guardrail" {
  let engine = @js_engine.Engine()
  engine.eval("Promise.resolve().then(() => { while (true) {} });")
  ignore(
    expect_microtask_guardrail(
      engine.run_microtask_checkpoint_bounded(
        bounded_microtask_policy(5L, 100L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      @js_engine.PendingJobs::None,
    ),
  )
  assert_false(engine.has_pending_microtasks())
}

///|
test "thenable job cannot swallow a checkpoint guardrail" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|Promise.resolve({
      #|  then(resolve) { while (true) {} }
      #|});
    ),
  )
  ignore(
    expect_microtask_guardrail(
      engine.run_microtask_checkpoint_bounded(
        bounded_microtask_policy(5L, 100L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      @js_engine.PendingJobs::None,
    ),
  )
  assert_false(engine.has_pending_microtasks())
}

///|
test "then getter cannot swallow a checkpoint guardrail" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|Promise.resolve().then(() => ({
      #|  get then() { while (true) {} }
      #|}));
    ),
  )
  ignore(
    expect_microtask_guardrail(
      engine.run_microtask_checkpoint_bounded(
        bounded_microtask_policy(20L, 100L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      @js_engine.PendingJobs::None,
    ),
  )
  assert_false(engine.has_pending_microtasks())
}

///|
test "one microtask budget spans the complete drain" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|queueMicrotask(() => events.push("A"));
      #|queueMicrotask(() => events.push("B"));
      #|function snapshot() { return events; }
    ),
  )
  ignore(
    expect_microtask_guardrail(
      engine.run_microtask_checkpoint_bounded(
        bounded_microtask_policy(5L, 100L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      @js_engine.PendingJobs::Present,
    ),
  )
  json_inspect(engine.call_json("snapshot", []), content=["A"])
  // The first job is consumed, while the job whose dispatch was rejected is
  // retained. A per-job budget reset would have run both jobs instead.
  assert_false(engine.run_microtask_checkpoint())
  json_inspect(engine.call_json("snapshot", []), content=["A", "B"])
}

///|
test "bounded microtask checkpoint drains appended jobs in FIFO order" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|queueMicrotask(() => {
      #|  events.push("A");
      #|  queueMicrotask(() => events.push("C"));
      #|});
      #|queueMicrotask(() => events.push("B"));
      #|function snapshot() { return events; }
    ),
  )
  match
    engine.run_microtask_checkpoint_bounded(
      bounded_microtask_policy(
        10000L,
        100L,
        @js_engine.InterruptionHandle(),
      ),
    ) {
    Ok(has_more) => assert_false(has_more)
    Err(diagnostic) => fail(diagnostic.message())
  }
  json_inspect(engine.call_json("snapshot", []), content=["A", "B", "C"])
}

///|
test "failing callback retains unstarted and appended jobs in FIFO order" {
  let engine = @js_engine.Engine()
  assert_true(
    engine.eval_diagnostic(
      (
        #|let events = [];
        #|queueMicrotask(() => {
        #|  events.push("A");
        #|  queueMicrotask(() => events.push("C"));
        #|  throw new Error("boom");
        #|});
        #|queueMicrotask(() => events.push("B"));
        #|function snapshot() { return events; }
      ),
      source_id="bounded-microtask.js",
    )
    is Ok(_),
  )
  let diagnostic = expect_microtask_guardrail(
    engine.run_microtask_checkpoint_bounded(
      bounded_microtask_policy(
        10000L,
        100L,
        @js_engine.InterruptionHandle(),
      ),
    ),
    "javascript-exception",
    @js_engine.PendingJobs::Present,
  )
  assert_true(diagnostic.source_identity() == Some("bounded-microtask.js"))
  json_inspect(engine.call_json("snapshot", []), content=["A"])
  // Test-only characterization of the retained queue. Hosts must still honor
  // the Discard integrity classification rather than retry this Engine.
  assert_false(engine.run_microtask_checkpoint())
  json_inspect(engine.call_json("snapshot", []), content=["A", "B", "C"])
}
