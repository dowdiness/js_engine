///|
fn assert_candidate_typedarray_complex_guard_971(
  interp : @interpreter.Interpreter,
  call_source : String,
) -> Unit raise Error {
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded TypedArray guard policy")
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
    None => fail("TypedArray complex native work must fail closed")
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate TypedArray complex guards reject before native work" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(
      interp,
      (
        #|var large = new Uint8Array(100000);
        #|var largeArray = Array(100000);
        #|var iterator = {
        #|  next: function() { return { done: true, value: 0 }; },
        #|  return: function() { return {}; }
        #|};
        #|var source = {};
        #|source[Symbol.iterator] = function() { return iterator; };
        #|function sortLarge() { large.sort(); return large.length; }
        #|function toSortLarge() { return large.toSorted().length; }
        #|function fromEmptyIterator() { return Uint8Array.from(source).length; }
        #|function constructFromArray() { return new Uint8Array(largeArray).length; }
        #|function constructFromObject() { return new Uint8Array(source).length; }
      ),
    ),
  )
  for
    call_source in [
      "sortLarge();", "toSortLarge();", "fromEmptyIterator();", "constructFromArray();",
      "constructFromObject();",
    ] {
    assert_candidate_typedarray_complex_guard_971(interp, call_source)
  }
}
