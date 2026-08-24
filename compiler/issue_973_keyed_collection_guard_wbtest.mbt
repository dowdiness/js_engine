///|
fn assert_candidate_keyed_collection_guard_973(
  interp : @interpreter.Interpreter,
  call_source : String,
) -> Unit raise Error {
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid keyed-collection guard policy")
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
    None => fail("keyed collection native work must fail closed")
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate keyed collection guards select Bytecode before native work" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(
      interp,
      (
        #|var pairSource = new Array(2000);
        #|var valueSource = new Array(2000);
        #|for (var i = 0; i < 2000; i += 1) {
        #|  pairSource[i] = [0, 0];
        #|  valueSource[i] = 0;
        #|}
        #|var largeSet = new Set(valueSource);
        #|var has = function(value) { return false; };
        #|var keys = function() {
        #|  return { next: function() { return { done: true, value: 0 }; },
        #|    return: function() { return {}; } };
        #|};
        #|var largeOther = { size: 3000, has: has, keys: keys };
        #|var emptyOther = { size: 0, has: has, keys: keys };
        #|function mapConstructLarge() { return new Map(pairSource).size; }
        #|function setConstructLarge() { return new Set(valueSource).size; }
        #|function mapGroupLarge() {
        #|  return Map.groupBy(valueSource, function(value) { return value; }).size;
        #|}
        #|function unionLarge() { return largeSet.union(largeOther).size; }
        #|function intersectionLarge() { return largeSet.intersection(largeOther).size; }
        #|function differenceLarge() { return largeSet.difference(largeOther).size; }
        #|function symmetricLarge() { return largeSet.symmetricDifference(largeOther).size; }
        #|function subsetLarge() { return largeSet.isSubsetOf(largeOther); }
        #|function supersetLarge() { return largeSet.isSupersetOf(emptyOther); }
        #|function disjointLarge() { return largeSet.isDisjointFrom(largeOther); }
      ),
    ),
  )
  for
    call_source in [
      "mapConstructLarge();", "setConstructLarge();", "mapGroupLarge();", "unionLarge();",
      "intersectionLarge();", "differenceLarge();", "symmetricLarge();", "subsetLarge();",
      "supersetLarge();", "disjointLarge();",
    ] {
    assert_candidate_keyed_collection_guard_973(interp, call_source)
  }
}
