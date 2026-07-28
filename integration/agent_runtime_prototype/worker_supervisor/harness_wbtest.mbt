///|
test "P2 matrix keeps each failure adjacent to its recovery" {
  let labels = required_attempts().map(spec => {
    "\{spec.scenario}|\{spec.fixture}|\{spec.expected_classification}|" +
    "\{spec.is_failure}|\{spec.is_recovery}"
  })
  json_inspect(labels, content=[
    "normal|normal|normal_completion|false|false", "infinite_js|infinite_js|deadline_exceeded|true|false",
    "recovery_after_infinite_js|recovery|recovery_completion|false|true", "worker_panic|worker_panic|worker_panic|true|false",
    "recovery_after_worker_panic|recovery|recovery_completion|false|true", "worker_abrupt_exit|worker_abrupt_exit|abrupt_exit|true|false",
    "recovery_after_worker_abrupt_exit|recovery|recovery_completion|false|true",
    "oversized_output|oversized_output|output_limit_exceeded|true|false", "recovery_after_oversized_output|recovery|recovery_completion|false|true",
    "malformed_json|malformed_json|malformed_json|true|false", "recovery_after_malformed_json|recovery|recovery_completion|false|true",
    "pipe_close_mid_message|pipe_close_mid_message|pipe_closed_mid_message|true|false",
    "recovery_after_pipe_close|recovery|recovery_completion|false|true", "near_deadline|near_deadline|near_deadline_completion|false|false",
  ])
}

///|
test "late pipe trigger cannot signal an already-reaped PID" {
  let start = @bench.monotonic_clock_start()
  let state = ScenarioState(
    supervisor_pid(),
    start,
    _ => (),
    "late_pipe_event",
    "malformed_json",
    1,
    2_147_483_647,
  )
  state.reaped = true
  state.active_children = 0
  let transcript : Array[String] = []
  let sequence = Ref(0)
  set_trigger(transcript, sequence, state, start, "malformed_json")
  json_inspect(
    [
      state.trigger == Some("malformed_json"),
      state.kill_requested,
      state.reaped,
    ],
    content=[true, false, true],
  )
}

///|
test "valid natural exit can win the deadline kill race" {
  let start = @bench.monotonic_clock_start()
  let state = ScenarioState(
    supervisor_pid(),
    start,
    _ => (),
    "near_deadline",
    "near_deadline",
    1,
    2_147_483_647,
  )
  state.last_valid_message = Some(
    expected_worker_message("near_deadline").stringify(),
  )
  state.valid_message_us = Some(800_000)
  state.trigger = Some("deadline_exceeded")
  state.kill_requested = true
  state.kill_request_us = Some(0)
  state.requested_signal = Some(SIGKILL)
  state.stdout_eof = true
  state.stderr_eof = true
  store_terminal(state, Exited(0), start)
  let classification = classify_terminal(state, Exited(0))
  verify_attempt_state(state, Exited(0), classification)
  json_inspect([classification, state.kill_outcome.unwrap_or("missing")], content=[
    "near_deadline_completion", "other_terminal_observed",
  ])
}

///|
test "P2 completion message contract is exact" {
  json_inspect(expected_worker_message("recovery"), content={
    "kind": "completed",
    "scenario": "recovery",
    "value": "js_engine_evaluated",
  })
  json_inspect(expected_worker_message("near_deadline"), content={
    "kind": "completed",
    "scenario": "near_deadline",
    "value": "js_engine_evaluated",
  })
}
