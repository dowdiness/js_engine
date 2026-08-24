///|
fn assert_candidate_array_complex_guard_969(
  interp : @interpreter.Interpreter,
  call_source : String,
) -> Unit raise Error {
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded Array guard policy")
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
    None => fail("Array complex native work must fail closed")
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate Array complex guards reject before native work" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(
      interp,
      (
        #|var sparse = Array(100000);
        #|function sortLarge() { sparse.sort(); return 1; }
        #|function toSortLarge() { return sparse.toSorted().length; }
        #|function flattenLarge() { return sparse.flat().length; }
        #|function flatMapLarge() { return sparse.flatMap(Array).length; }
        #|var iterator = {
        #|  next: function() { return { done: true, value: 0 }; },
        #|  return: function() { return {}; }
        #|};
        #|var source = {};
        #|source[Symbol.iterator] = function() { return iterator; };
        #|function fromEmptyIterator() { return Array.from(source).length; }
      ),
    ),
  )
  for
    call_source in [
      "sortLarge();", "toSortLarge();", "flattenLarge();", "flatMapLarge();", "fromEmptyIterator();",
    ] {
    assert_candidate_array_complex_guard_969(interp, call_source)
  }
}
