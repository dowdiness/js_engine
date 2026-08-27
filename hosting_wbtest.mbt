///|
test "Execution Session integrity policy fails closed unless reusable" {
  assert_true(
    execution_session_state_after_integrity(EngineIntegrity::Reusable)
    is Available,
  )
  assert_true(
    execution_session_state_after_integrity(EngineIntegrity::Discard) is Faulted,
  )
  assert_true(
    execution_session_state_after_integrity(EngineIntegrity::Unknown) is Faulted,
  )
  assert_true(
    execution_session_state_after_integrity(EngineIntegrity::NotApplicable)
    is Faulted,
  )
}

///|
test "Execution Session does not retain delivered Console output" {
  let delivered : Array[String] = []
  let session = HostEnvironment(console=true).create_session(
    bindings=SessionBindings(
      console_output_sink=Some(output => delivered.push(output.text())),
    ),
  )
  let source =
    #|console.log("first");
    #|console.warn("second");
  session.evaluate(source)
  json_inspect(delivered, content=["first", "second"])
  assert_eq(session.engine.interp.host.output.length(), 0)

  let discard_session = HostEnvironment(console=true).create_session()
  discard_session.evaluate("console.log('discarded')")
  assert_eq(discard_session.engine.interp.host.output.length(), 0)
}

///|
test "Console debug output retains its distinct kind" {
  let delivered : Array[ConsoleOutputKind] = []
  let session = HostEnvironment(console=true).create_session(
    bindings=SessionBindings(
      console_output_sink=Some(output => delivered.push(output.kind())),
    ),
  )
  session.evaluate("console.debug('detail'); console.log('ordinary');")
  guard delivered is [debug, log] else {
    fail("expected one debug output followed by one log output")
  }
  assert_true(debug is ConsoleOutputKind::Debug)
  assert_true(log is ConsoleOutputKind::Log)
}

///|
test "Scheduled Turn ID exhaustion faults before scheduling or reuse" {
  let scheduled : Array[ScheduledTurn] = []
  let session = HostEnvironment(timers=true).create_session(
    bindings=SessionBindings(
      timer_scheduler=Some(schedule => scheduled.push(schedule.turn())),
    ),
  )
  session.host_binding.next_scheduled_turn_id = 0x7FFFFFFF - 1
  session.evaluate("setTimeout(() => {}, 0)")
  assert_eq(scheduled.length(), 1)
  assert_eq(session.host_binding.scheduled_callbacks.length(), 1)
  assert_eq(session.host_binding.next_scheduled_turn_id, 0x7FFFFFFF)
  let exhausted : ExecutionSessionError? = try {
    session.evaluate("setTimeout(() => {}, 0)")
    None
  } catch {
    error => Some(error)
  }
  match exhausted {
    Some(HostFailure(capability~, detail~)) => {
      inspect(capability, content="Timer Scheduler")
      assert_true(detail.contains("Scheduled Turn ID space is exhausted"))
    }
    Some(error) => fail("expected HostFailure, got " + Show::to_string(error))
    None => fail("Scheduled Turn allocator reused an exhausted ID")
  }
  assert_eq(scheduled.length(), 1)
  assert_eq(session.host_binding.scheduled_callbacks.length(), 0)
  assert_eq(session.host_binding.next_scheduled_turn_id, 0x7FFFFFFF)
  let rejected : ExecutionSessionError? = try {
    session.evaluate("1 + 1")
    None
  } catch {
    error => Some(error)
  }
  match rejected {
    Some(SessionFaulted) => ()
    Some(error) =>
      fail("expected SessionFaulted, got " + Show::to_string(error))
    None => fail("faulted Execution Session accepted another Hosted Turn")
  }
}
