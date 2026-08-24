///|
fn assert_candidate_promise_guard_977(
  interp : @interpreter.Interpreter,
  call_source : String,
) -> Unit raise Error {
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid Promise combinator guard policy")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let caught : Error? = interp.with_execution_policy(policy, () => {
    try {
      ignore(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse(call_source).stmts,
          evidence,
        ),
      )
      None
    } catch {
      error => Some(error)
    }
  })
  match caught {
    Some(error) =>
      assert_eq(
        @runtime.execution_control_failure_code(error),
        Some("execution-limit"),
      )
    None => fail("Promise combinator native work must fail closed")
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate Promise combinator guards preserve Bytecode route integrity" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(
      interp,
      (
        #|var issue977LargeArray = new Array(100000);
        #|function issue977All() { return Promise.all(issue977LargeArray); }
        #|function issue977Race() { return Promise.race(issue977LargeArray); }
        #|function issue977AllSettled() {
        #|  return Promise.allSettled(issue977LargeArray);
        #|}
        #|function issue977Any() { return Promise.any(issue977LargeArray); }
      ),
    ),
  )
  for
    call_source in [
      "issue977All();", "issue977Race();", "issue977AllSettled();", "issue977Any();",
    ] {
    assert_candidate_promise_guard_977(interp, call_source)
  }
}
