///|
/// Test-only timer payload that never invokes JavaScript.
fn timer_policy_test_task(
  id : Int,
  delay : Int,
  insertion_order : Int,
  period? : Int = 0,
  is_interval? : Bool = false,
) -> TimerTask {
  {
    id,
    callback: Undefined,
    args: [],
    delay,
    period,
    is_interval,
    insertion_order,
  }
}

///|
fn timer_policy_test_id(task : TimerTask?) -> Int raise {
  match task {
    Some(task) => task.id
    None => fail("expected a timer task")
  }
}

///|
fn expect_invalid_timer_queue_policy_transition(
  operation : String,
  action : () -> Unit raise,
) -> Unit raise {
  let failure = try {
    action()
    "no error"
  } catch {
    Failure::Failure(message) => message
    error => "wrong error: " + error.to_string()
  }
  let expected = "invalid timer queue policy transition: " + operation
  guard failure.has_suffix("FAILED: " + expected) else {
    fail("expected failure ending in '" + expected + "', got '" + failure + "'")
  }
}

///|
test "timer policy selects smaller delays first" {
  let queue = @priority_queue.PriorityQueue([
    timer_policy_test_task(1, 100, 0),
    timer_policy_test_task(2, 0, 1),
    timer_policy_test_task(3, 50, 2),
  ])
  let policy = TimerQueuePolicy(queue, Map([]), { val: 3 }, 10)
  let selected : Array[Int] = []
  for _ in 0..<3 {
    selected.push(timer_policy_test_id(policy.select_next()))
    policy.callback_succeeded()
    policy.checkpoint_succeeded()
  }
  json_inspect(selected, content=[2, 3, 1])
  inspect(policy.select_next() is None, content="true")
  policy.complete_run()
}

///|
test "timer policy preserves insertion order for equal delays" {
  let queue = @priority_queue.PriorityQueue([
    timer_policy_test_task(1, 10, 2),
    timer_policy_test_task(2, 10, 0),
    timer_policy_test_task(3, 10, 1),
  ])
  let policy = TimerQueuePolicy(queue, Map([]), { val: 3 }, 10)
  let selected : Array[Int] = []
  for _ in 0..<3 {
    selected.push(timer_policy_test_id(policy.select_next()))
    policy.callback_succeeded()
    policy.checkpoint_succeeded()
  }
  json_inspect(selected, content=[2, 3, 1])
}

///|
test "timer policy consumes the selected timer before callback outcome" {
  let queue = @priority_queue.PriorityQueue([
    timer_policy_test_task(1, 0, 0),
    timer_policy_test_task(2, 1, 1),
  ])
  let policy = TimerQueuePolicy(queue, Map([]), { val: 2 }, 10)
  inspect(timer_policy_test_id(policy.select_next()), content="1")
  inspect(queue.length(), content="1")
  inspect(timer_policy_test_id(queue.peek()), content="2")
}

///|
test "timer policy skips cancelled timers with lazy deletion" {
  let queue = @priority_queue.PriorityQueue([
    timer_policy_test_task(1, 0, 0),
    timer_policy_test_task(2, 1, 1),
  ])
  let cancelled : Map[Int, Bool] = Map([(1, true)])
  let policy = TimerQueuePolicy(queue, cancelled, { val: 2 }, 10)
  inspect(timer_policy_test_id(policy.select_next()), content="2")
  inspect(queue.length(), content="0")
}

///|
test "timer policy never re-registers one-shot timers" {
  let success_queue = @priority_queue.PriorityQueue([
    timer_policy_test_task(1, 0, 0),
  ])
  let success_policy = TimerQueuePolicy(success_queue, Map([]), { val: 1 }, 10)
  let _ = success_policy.select_next()
  success_policy.callback_succeeded()
  success_policy.checkpoint_succeeded()
  inspect(success_queue.length(), content="0")

  let failure_queue = @priority_queue.PriorityQueue([
    timer_policy_test_task(2, 0, 0),
  ])
  let failure_policy = TimerQueuePolicy(failure_queue, Map([]), { val: 1 }, 10)
  let _ = failure_policy.select_next()
  failure_policy.callback_failed()
  inspect(failure_queue.length(), content="0")
}

///|
test "timer policy re-registers intervals after callback and checkpoint success" {
  let queue = @priority_queue.PriorityQueue([
    timer_policy_test_task(1, 10, 0, period=5, is_interval=true),
  ])
  let insertion_counter : Ref[Int] = { val: 7 }
  let policy = TimerQueuePolicy(queue, Map([]), insertion_counter, 10)
  let _ = policy.select_next()
  policy.callback_succeeded()
  inspect(queue.length(), content="0")
  policy.checkpoint_succeeded()
  let repeated = match policy.select_next() {
    Some(task) => task
    None => fail("expected a re-registered interval")
  }
  json_inspect(
    [
      repeated.id,
      repeated.delay,
      repeated.period,
      repeated.insertion_order,
      insertion_counter.val,
    ],
    content=[1, 15, 5, 7, 8],
  )
}

///|
test "timer policy does not re-register an interval after callback failure" {
  let queue = @priority_queue.PriorityQueue([
    timer_policy_test_task(1, 0, 0, period=5, is_interval=true),
  ])
  let policy = TimerQueuePolicy(queue, Map([]), { val: 1 }, 10)
  let _ = policy.select_next()
  policy.callback_failed()
  inspect(queue.length(), content="0")
}

///|
test "timer policy does not re-register an interval after checkpoint failure" {
  let queue = @priority_queue.PriorityQueue([
    timer_policy_test_task(1, 0, 0, period=5, is_interval=true),
  ])
  let policy = TimerQueuePolicy(queue, Map([]), { val: 1 }, 10)
  let _ = policy.select_next()
  policy.callback_succeeded()
  policy.checkpoint_failed()
  inspect(queue.length(), content="0")
}

///|
test "timer policy does not re-register an interval cancelled in its callback" {
  let queue = @priority_queue.PriorityQueue([
    timer_policy_test_task(1, 0, 0, period=5, is_interval=true),
  ])
  let cancelled : Map[Int, Bool] = Map([])
  let policy = TimerQueuePolicy(queue, cancelled, { val: 1 }, 10)
  let _ = policy.select_next()
  cancelled[1] = true
  policy.callback_succeeded()
  policy.checkpoint_succeeded()
  inspect(queue.length(), content="0")
}

///|
test "timer policy clears cancellation bookkeeping only after a complete drain" {
  let queue = @priority_queue.PriorityQueue([timer_policy_test_task(1, 0, 0)])
  let cancelled : Map[Int, Bool] = Map([(1, true)])
  let policy = TimerQueuePolicy(queue, cancelled, { val: 1 }, 10)
  inspect(policy.select_next() is None, content="true")
  inspect(cancelled.contains(1), content="true")
  policy.complete_run()
  inspect(cancelled.contains(1), content="false")
}

///|
test "timer policy preserves cancellation bookkeeping at the safety limit" {
  let queue = @priority_queue.PriorityQueue([
    timer_policy_test_task(1, 0, 0),
    timer_policy_test_task(2, 1, 1),
  ])
  let cancelled : Map[Int, Bool] = Map([(1, true)])
  let policy = TimerQueuePolicy(queue, cancelled, { val: 2 }, 1)
  inspect(policy.select_next() is None, content="true")
  inspect(queue.length(), content="1")
  policy.complete_run()
  inspect(cancelled.contains(1), content="true")
}

///|
test "timer policy rejects invalid transitions" {
  let queue = @priority_queue.PriorityQueue([timer_policy_test_task(1, 0, 0)])
  let policy = TimerQueuePolicy(queue, Map([]), { val: 1 }, 10)
  expect_invalid_timer_queue_policy_transition(
    "callback_succeeded requires Selected",
    () => policy.callback_succeeded(),
  )
  expect_invalid_timer_queue_policy_transition(
    "callback_failed requires Selected",
    () => policy.callback_failed(),
  )
  expect_invalid_timer_queue_policy_transition(
    "checkpoint_succeeded requires CallbackSucceeded",
    () => policy.checkpoint_succeeded(),
  )
  expect_invalid_timer_queue_policy_transition(
    "checkpoint_failed requires CallbackSucceeded",
    () => policy.checkpoint_failed(),
  )
  let _ = policy.select_next()
  expect_invalid_timer_queue_policy_transition("select_next requires Ready", () => {
    let _ = policy.select_next()
  })
  expect_invalid_timer_queue_policy_transition("complete_run requires Ready", () => {
    policy.complete_run()
  })
  policy.callback_succeeded()
  expect_invalid_timer_queue_policy_transition(
    "callback_succeeded requires Selected",
    () => policy.callback_succeeded(),
  )
  policy.checkpoint_failed()
  expect_invalid_timer_queue_policy_transition("select_next requires Ready", () => {
    let _ = policy.select_next()
  })
  expect_invalid_timer_queue_policy_transition("complete_run requires Ready", () => {
    policy.complete_run()
  })

  let completed = TimerQueuePolicy(
    @priority_queue.PriorityQueue([]),
    Map([]),
    { val: 0 },
    10,
  )
  completed.complete_run()
  expect_invalid_timer_queue_policy_transition("select_next requires Ready", () => {
    let _ = completed.select_next()
  })
}
