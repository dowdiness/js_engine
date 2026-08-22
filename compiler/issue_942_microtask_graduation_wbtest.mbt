///|
fn issue942_assert_clean_route(
  evidence : Ref[CandidateRouteEvidence],
) -> Unit raise {
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
fn issue942_activation_id(event : CandidateRouteEvent) -> Int {
  match event {
    CandidateRoutePreparedEvent(event) => event.activation_id
    CandidateRouteStartedEvent(event) => event.activation_id
    CandidateRouteCompletedEvent(event) => event.activation_id
  }
}

///|
fn issue942_assert_complete_lifecycle(
  events : Array[CandidateRouteEvent],
  activation_id : Int,
) -> Unit raise {
  let offset = activation_id * 3
  assert_true(events[offset] is CandidateRoutePreparedEvent(_))
  assert_true(events[offset + 1] is CandidateRouteStartedEvent(_))
  assert_true(events[offset + 2] is CandidateRouteCompletedEvent(_))
  assert_eq(issue942_activation_id(events[offset]), activation_id)
  assert_eq(issue942_activation_id(events[offset + 1]), activation_id)
  assert_eq(issue942_activation_id(events[offset + 2]), activation_id)
}

///|
test "issue 942 canonical microtask source keeps its accepted hash" {
  let source_hash = @crypto.bytes_to_hex_string(
    @crypto.sha256(
      @encoding.encode(UTF8, @benchmark_workloads.MICROTASK_DRAIN_200_SRC),
    ),
  )
  assert_eq(
    source_hash, "2501874aef97eb3ba53a551e16df551478f17fbe30453d32f96b1d363886782f",
  )
  assert_eq(@benchmark_workloads.MICROTASK_DRAIN_200_OUTPUT, "200")
}

///|
test "issue 942 graduates canonical microtask_drain_200 and reuses Engine" {
  let source = @benchmark_workloads.MICROTASK_DRAIN_200_SRC
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  assert_true(program.root.selection is UseBytecode(ManagedSuspension))
  assert_eq(program.root.children.length(), 2)
  for child in program.root.children {
    assert_true(child.selection is UseBytecode(ManagedSuspension))
  }

  let interp = @interpreter.new_interpreter()
  let (_, evidence) = run_candidate_program_with_summary(
    interp,
    @parser.parse(source).stmts,
  )
  assert_eq(evidence.val.events.length(), 0)
  assert_eq(evidence.val.summary.bytecode_starts, 1)
  assert_eq(evidence.val.summary.normal_completions, 1)
  assert_eq(interp.host.microtask_queue.length(), 200)
  assert_eq(interp.host.timer_queue.length(), 1)
  interp.run_microtasks()
  assert_eq(interp.global.get("counter").to_string(), "200")
  assert_eq(evidence.val.summary.bytecode_starts, 201)
  assert_eq(evidence.val.summary.normal_completions, 201)
  assert_eq(interp.host.microtask_queue.length(), 0)
  assert_eq(interp.host.timer_queue.length(), 1)
  interp.run_timers()
  assert_eq(interp.host.output, ["200"])
  assert_eq(interp.host.microtask_queue.length(), 0)
  assert_eq(interp.host.timer_queue.length(), 0)
  assert_eq(evidence.val.summary.verified_decisions, 202)
  assert_eq(evidence.val.summary.bytecode_starts, 202)
  assert_eq(evidence.val.summary.normal_completions, 202)
  assert_eq(evidence.val.summary.abrupt_completions, 0)
  assert_eq(evidence.val.summary.maximum_concurrent_activations, 1)
  issue942_assert_clean_route(evidence)

  let reuse_source =
    #|Promise.resolve().then(function() { counter = counter + 1; });
  let (_, reuse_evidence) = run_candidate_program_with_summary(
    interp,
    @parser.parse(reuse_source).stmts,
  )
  assert_eq(reuse_evidence.val.summary.bytecode_starts, 1)
  assert_eq(reuse_evidence.val.summary.normal_completions, 1)
  assert_eq(interp.host.microtask_queue.length(), 1)
  assert_eq(interp.host.timer_queue.length(), 0)
  interp.run_microtasks()
  assert_eq(interp.global.get("counter").to_string(), "201")
  assert_eq(interp.host.microtask_queue.length(), 0)
  assert_eq(interp.host.timer_queue.length(), 0)
  assert_eq(reuse_evidence.val.summary.bytecode_starts, 2)
  assert_eq(reuse_evidence.val.summary.normal_completions, 2)
  assert_eq(reuse_evidence.val.summary.maximum_concurrent_activations, 1)
  issue942_assert_clean_route(reuse_evidence)
}

///|
test "issue 942 preserves mixed microtask FIFO before timer checkpoint" {
  let source =
    #|var events = "";
    #|queueMicrotask(function() { events = events + "A"; });
    #|Promise.resolve().then(function() {
    #|  events = events + "B";
    #|  queueMicrotask(function() { events = events + "D"; });
    #|});
    #|queueMicrotask(function() { events = events + "C"; });
    #|setTimeout(function() { events = events + "T"; }, 0);
  let interp = @interpreter.new_interpreter()
  let (_, evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(source).stmts,
  )
  assert_eq(interp.host.microtask_queue.length(), 3)
  assert_eq(interp.host.timer_queue.length(), 1)
  interp.run_microtasks()
  assert_eq(interp.global.get("events").to_string(), "ABCD")
  assert_eq(interp.host.microtask_queue.length(), 0)
  assert_eq(interp.host.timer_queue.length(), 1)
  interp.run_timers()
  assert_eq(interp.global.get("events").to_string(), "ABCDT")
  assert_eq(interp.host.timer_queue.length(), 0)
  assert_eq(evidence.val.summary.bytecode_starts, 6)
  assert_eq(evidence.val.summary.normal_completions, 6)
  assert_eq(evidence.val.summary.maximum_concurrent_activations, 1)
  assert_eq(evidence.val.events.length(), 18)
  for activation_id in 0..<6 {
    issue942_assert_complete_lifecycle(evidence.val.events, activation_id)
  }
  issue942_assert_clean_route(evidence)
}

///|
test "issue 942 drains a finite 1000 stage Promise reaction chain" {
  let source =
    #|var chainValue = 0;
    #|var chain = Promise.resolve(0);
    #|for (var i = 0; i < 1000; i++) {
    #|  chain = chain.then(function(value) { return value + 1; });
    #|}
    #|chain.then(function(value) { chainValue = value; });
  let interp = @interpreter.new_interpreter()
  let (_, evidence) = run_candidate_program_with_summary(
    interp,
    @parser.parse(source).stmts,
  )
  assert_eq(evidence.val.events.length(), 0)
  assert_eq(evidence.val.summary.bytecode_starts, 1)
  assert_eq(evidence.val.summary.normal_completions, 1)
  assert_eq(interp.host.microtask_queue.length(), 1)
  interp.run_microtasks()
  assert_eq(interp.global.get("chainValue").to_string(), "1000")
  assert_eq(interp.host.microtask_queue.length(), 0)
  assert_eq(interp.host.timer_queue.length(), 0)
  assert_eq(evidence.val.summary.verified_decisions, 1002)
  assert_eq(evidence.val.summary.bytecode_starts, 1002)
  assert_eq(evidence.val.summary.normal_completions, 1002)
  assert_eq(evidence.val.summary.abrupt_completions, 0)
  assert_eq(evidence.val.summary.maximum_concurrent_activations, 1)
  issue942_assert_clean_route(evidence)
}
