///|
test "candidate Reflect.ownKeys traversal must honor the operation budget" {
  let interp = @interpreter.new_interpreter()
  let prepared = run_executor_neutral_bytecode(
    interp,
    "var source = {}; " +
    "for (var i = 0; i < 5000; i++) source['key' + i] = i; " +
    "function enumerate() { return Reflect.ownKeys(source).length; } " +
    "enumerate();",
  )
  assert_eq(prepared.to_string(), "5000")
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid own-key execution policy")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let outcome : Result[@runtime.Value, Error] = interp.with_execution_policy(
    policy,
    () => {
      Ok(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse("enumerate();").stmts,
          evidence,
        ),
      ) catch {
        error => Err(error)
      }
    },
  )
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  match outcome {
    Err(error) =>
      assert_eq(
        @runtime.execution_control_failure_code(error),
        Some("execution-limit"),
      )
    Ok(value) =>
      fail("Reflect.ownKeys traversal completed with " + value.to_string())
  }
}
