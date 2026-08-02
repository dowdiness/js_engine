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
fn expect_timer_guardrail(
  result : Result[Unit, @js_engine.EngineDiagnostic],
  kind : String,
  phase : String,
  pending : @js_engine.PendingJobs,
) -> @js_engine.EngineDiagnostic raise Error {
  match result {
    Ok(_) => fail("expected bounded timer checkpoint to reject")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content=kind)
      inspect(diagnostic.operation_code(), content="timer-checkpoint")
      inspect(diagnostic.phase_code(), content=phase)
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
test "empty bounded timer checkpoint succeeds with zero budget" {
  let engine = @js_engine.Engine()
  match
    engine.run_timer_checkpoint_bounded(
      bounded_timer_policy(0L, 0L, @js_engine.InterruptionHandle()),
    ) {
    Ok(_) => ()
    Err(diagnostic) => fail(diagnostic.message())
  }
  assert_false(engine.has_pending_timers())
}

///|
test "pre-requested interruption retains the pending timer" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let count = 0;
      #|setTimeout(() => { count += 1; }, 0);
      #|function readCount() { return count; }
    ),
  )
  let interruption = @js_engine.InterruptionHandle()
  interruption.request()
  ignore(
    expect_timer_guardrail(
      engine.run_timer_checkpoint_bounded(
        bounded_timer_policy(100L, 10L, interruption),
      ),
      "interrupted",
      "timer-queue-dispatch",
      @js_engine.PendingJobs::Present,
    ),
  )
  assert_true(engine.has_pending_timers())
  json_inspect(engine.call_json("readCount", []), content=0)
  engine.run_timer_checkpoint()
  json_inspect(engine.call_json("readCount", []), content=1)
}

///|
test "bounded timer checkpoint discards a cancelled prefix before rejection" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|let first = setTimeout(() => events.push("first"), 0);
      #|let second = setTimeout(() => events.push("second"), 1);
      #|clearTimeout(first);
      #|clearTimeout(second);
      #|function snapshot() { return events; }
    ),
  )
  ignore(
    expect_timer_guardrail(
      engine.run_timer_checkpoint_bounded(
        bounded_timer_policy(1L, 10L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      "timer-queue-dispatch",
      @js_engine.PendingJobs::Present,
    ),
  )
  assert_true(engine.has_pending_timers())
  engine.run_timer_checkpoint()
  assert_false(engine.has_pending_timers())
  json_inspect(engine.call_json("snapshot", []), content=[])
}

///|
test "timer activation guardrail consumes the timer before callback effects" {
  let engine = @js_engine.Engine()
  assert_true(
    engine.eval_diagnostic(
      (
        #|let events = [];
        #|function recurse(n) {
        #|  if (n === 0) return 0;
        #|  return 1 + recurse(n - 1);
        #|}
        #|setTimeout(() => recurse(256), 0);
        #|function snapshot() { return events; }
      ),
      source_id="timer-activation.js",
    )
    is Ok(_),
  )
  let diagnostic = expect_timer_guardrail(
    engine.run_timer_checkpoint_bounded(
      bounded_timer_policy(10000L, 0L, @js_engine.InterruptionHandle()),
    ),
    "stack-depth-limit",
    "timer-callback",
    @js_engine.PendingJobs::None,
  )
  assert_true(diagnostic.source_identity() == Some("timer-activation.js"))
  assert_false(engine.has_pending_timers())
  json_inspect(engine.call_json("snapshot", []), content=[])
}

///|
test "timer callback body guardrail consumes the callback" {
  let engine = @js_engine.Engine()
  engine.eval("setTimeout(() => { while (true) {} }, 0);")
  ignore(
    expect_timer_guardrail(
      engine.run_timer_checkpoint_bounded(
        bounded_timer_policy(100L, 100L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      "timer-callback",
      @js_engine.PendingJobs::None,
    ),
  )
  assert_false(engine.has_pending_timers())
}

///|
test "timer-following microtasks share the bounded timer control" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|setTimeout(() => {
      #|  events.push("timer");
      #|  queueMicrotask(() => { events.push("micro"); while (true) {} });
      #|}, 0);
      #|function snapshot() { return events; }
    ),
  )
  ignore(
    expect_timer_guardrail(
      engine.run_timer_checkpoint_bounded(
        bounded_timer_policy(100L, 100L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      "timer-microtask-checkpoint",
      @js_engine.PendingJobs::None,
    ),
  )
  json_inspect(engine.call_json("snapshot", []), content=["timer", "micro"])
  assert_false(engine.has_pending_timers())
}

///|
test "finite timer-following microtask consumes the shared remaining budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|setTimeout(() => {
      #|  events.push("timer");
      #|  queueMicrotask(() => {
      #|    events.push("micro-start");
      #|    events.push("micro-finish");
      #|  });
      #|}, 0);
      #|function snapshot() { return events; }
    ),
  )
  ignore(
    expect_timer_guardrail(
      engine.run_timer_checkpoint_bounded(
        bounded_timer_policy(15L, 100L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      "timer-microtask-checkpoint",
      @js_engine.PendingJobs::None,
    ),
  )
  json_inspect(engine.call_json("snapshot", []), content=["timer", "micro-start"])
  assert_false(engine.has_pending_timers())
}

///|
test "failed timer-following microtask does not re-register an interval" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|setInterval(() => {
      #|  events.push("interval");
      #|  queueMicrotask(() => { events.push("micro"); throw new Error("boom"); });
      #|}, 0);
      #|function snapshot() { return events; }
    ),
  )
  ignore(
    expect_timer_guardrail(
      engine.run_timer_checkpoint_bounded(
        bounded_timer_policy(1000L, 100L, @js_engine.InterruptionHandle()),
      ),
      "javascript-exception",
      "timer-microtask-checkpoint",
      @js_engine.PendingJobs::None,
    ),
  )
  assert_false(engine.has_pending_timers())
  json_inspect(engine.call_json("snapshot", []), content=["interval", "micro"])
}

///|
test "successful timer work re-registers an interval before later rejection" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let id = setInterval(() => {}, 0);
      #|function cancel() { clearInterval(id); return 0; }
    ),
  )
  ignore(
    expect_timer_guardrail(
      engine.run_timer_checkpoint_bounded(
        bounded_timer_policy(2L, 100L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      "timer-queue-dispatch",
      @js_engine.PendingJobs::Present,
    ),
  )
  assert_true(engine.has_pending_timers())
  ignore(engine.call_json("cancel", []))
  engine.run_timer_checkpoint()
  assert_false(engine.has_pending_timers())
}

///|
test "timer checkpoint retains appended microtasks after a later dispatch rejection" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|setTimeout(() => {
      #|  events.push("timer");
      #|  queueMicrotask(() => { events.push("A"); while (true) {} });
      #|  queueMicrotask(() => events.push("B"));
      #|}, 0);
      #|function snapshot() { return events; }
    ),
  )
  ignore(
    expect_timer_guardrail(
      engine.run_timer_checkpoint_bounded(
        bounded_timer_policy(100L, 100L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      "timer-microtask-checkpoint",
      @js_engine.PendingJobs::Present,
    ),
  )
  json_inspect(engine.call_json("snapshot", []), content=["timer", "A"])
  assert_true(engine.has_pending_microtasks())
  assert_false(engine.has_pending_timers())
  ignore(engine.run_microtask_checkpoint())
  json_inspect(engine.call_json("snapshot", []), content=["timer", "A", "B"])
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
