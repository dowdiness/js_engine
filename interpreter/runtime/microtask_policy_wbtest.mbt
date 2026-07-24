///|
/// Test-only microtask payload that never invokes JavaScript.
fn microtask_policy_test_job(id : String) -> Microtask {
  { callback: String_(id), args: [] }
}

///|
fn microtask_policy_test_id(job : Microtask?) -> String raise {
  match job {
    Some({ callback: String_(id), .. }) => id
    Some(_) => fail("expected a string-labelled microtask")
    None => fail("expected a microtask")
  }
}

///|
fn microtask_policy_test_queue_ids(
  queue : Array[Microtask],
) -> Array[String] raise {
  queue.map(job => {
    match job.callback {
      String_(id) => id
      _ => fail("expected a string-labelled microtask")
    }
  })
}

///|
fn expect_invalid_microtask_policy_transition(
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
  let expected = "invalid microtask policy transition: " + operation
  guard failure.has_suffix("FAILED: " + expected) else {
    fail("expected failure ending in '" + expected + "', got '" + failure + "'")
  }
}

///|
test "microtask policy selects jobs in FIFO order" {
  let queue = [microtask_policy_test_job("A"), microtask_policy_test_job("B")]
  let policy = MicrotaskQueuePolicy(queue)
  let first = microtask_policy_test_id(policy.select_next())
  policy.complete_selected()
  let second = microtask_policy_test_id(policy.select_next())
  policy.complete_selected()
  let selected = [first, second]
  json_inspect(selected, content=["A", "B"])
  inspect(policy.select_next() is None, content="true")
}

///|
test "microtask policy selects jobs appended during a drain" {
  let queue = [microtask_policy_test_job("A"), microtask_policy_test_job("B")]
  let policy = MicrotaskQueuePolicy(queue)
  let first = microtask_policy_test_id(policy.select_next())
  microtask_policy_enqueue(queue, microtask_policy_test_job("C"))
  policy.complete_selected()
  let second = microtask_policy_test_id(policy.select_next())
  policy.complete_selected()
  let third = microtask_policy_test_id(policy.select_next())
  policy.complete_selected()
  let remaining = [second, third]
  json_inspect([first], content=["A"])
  json_inspect(remaining, content=["B", "C"])
}

///|
test "microtask policy clears the queue after a successful drain" {
  let queue = [microtask_policy_test_job("A"), microtask_policy_test_job("B")]
  let policy = MicrotaskQueuePolicy(queue)
  let _ = policy.select_next()
  policy.complete_selected()
  let _ = policy.select_next()
  policy.complete_selected()
  inspect(policy.select_next() is None, content="true")
  policy.complete_drain()
  json_inspect(microtask_policy_test_queue_ids(queue), content=[])
}

///|
test "microtask policy consumes the failed job before retry" {
  let queue = [microtask_policy_test_job("A"), microtask_policy_test_job("B")]
  let policy = MicrotaskQueuePolicy(queue)
  inspect(microtask_policy_test_id(policy.select_next()), content="A")
  microtask_policy_enqueue(queue, microtask_policy_test_job("C"))
  policy.fail_selected()
  json_inspect(microtask_policy_test_queue_ids(queue), content=["B", "C"])
  expect_invalid_microtask_policy_transition("select_next requires Ready", () => {
    let _ = policy.select_next()
  })
  let retry = MicrotaskQueuePolicy(queue)
  inspect(microtask_policy_test_id(retry.select_next()), content="B")
}

///|
test "microtask policy rejects invalid transitions" {
  let queue = [microtask_policy_test_job("A")]
  let policy = MicrotaskQueuePolicy(queue)
  expect_invalid_microtask_policy_transition(
    "complete_selected requires Selected",
    () => policy.complete_selected(),
  )
  expect_invalid_microtask_policy_transition(
    "fail_selected requires Selected",
    () => policy.fail_selected(),
  )
  expect_invalid_microtask_policy_transition(
    "complete_drain requires an exhausted queue",
    () => policy.complete_drain(),
  )
  let _ = policy.select_next()
  expect_invalid_microtask_policy_transition("select_next requires Ready", () => {
    let _ = policy.select_next()
  })
  expect_invalid_microtask_policy_transition("complete_drain requires Ready", () => {
    policy.complete_drain()
  })
  policy.complete_selected()
  inspect(policy.select_next() is None, content="true")
  policy.complete_drain()
  expect_invalid_microtask_policy_transition("complete_drain requires Ready", () => {
    policy.complete_drain()
  })
}
