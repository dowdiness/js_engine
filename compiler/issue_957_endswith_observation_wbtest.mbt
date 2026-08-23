///|
test "candidate String.endsWith interruption starts Bytecode only" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(
      interp,
      "var large = \"a\".repeat(100000) + \"b\"; " +
      "var needle = \"a\".repeat(100000) + \"c\"; " +
      "function endsWithLateMismatch() { return large.endsWith(needle); }",
    ),
  )
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let caught : Error? = interp.with_execution_policy(policy, () => {
    try {
      ignore(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse("endsWithLateMismatch();").stmts,
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
    None => fail("endsWith search must be interruptible")
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate String.endsWith function remains bytecode-eligible" {
  let source = "var large = \"a\".repeat(100000) + \"b\"; " +
    "var needle = \"a\".repeat(100000) + \"c\"; " +
    "function endsWithLateMismatch() { return large.endsWith(needle); } " +
    "endsWithLateMismatch();"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.children.length() == 1 else {
    fail("endsWith fixture must contain one function candidate")
  }
  match program.root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) =>
      fail("String.endsWith function lost bytecode eligibility")
  }
}
