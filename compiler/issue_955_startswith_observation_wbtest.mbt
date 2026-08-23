///|
test "RED: bounded String.startsWith search must reach execution limit" {
  let interp = @interpreter.new_interpreter()
  // Prepare the large receiver and search outside the bounded call so this
  // test measures only the startsWith comparison loop.
  ignore(
    run_executor_neutral_bytecode(
      interp,
      "var large = \"a\".repeat(100000) + \"b\"; " +
      "var needle = \"a\".repeat(100000) + \"c\"; " +
      "function startsWithLateMismatch() { return large.startsWith(needle); }",
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
          @parser.parse("startsWithLateMismatch();").stmts,
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
    None => fail("startsWith search must be interruptible")
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "default bounded String.startsWith search reaches execution limit" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(
      interp,
      "var large = \"a\".repeat(100000) + \"b\"; " +
      "var needle = \"a\".repeat(100000) + \"c\"; " +
      "function startsWithLateMismatch() { return large.startsWith(needle); }",
    ),
  )
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let caught : Error? = interp.with_execution_policy(policy, () => {
    try {
      ignore(interp.run(@parser.parse("startsWithLateMismatch();").stmts))
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
    None => fail("default startsWith search must be interruptible")
  }
}

///|
test "candidate String.startsWith keeps the search function on Bytecode" {
  let source = "var large = \"a\".repeat(100000) + \"b\"; " +
    "var needle = \"a\".repeat(100000) + \"c\"; " +
    "function startsWithLateMismatch() { return large.startsWith(needle); } " +
    "startsWithLateMismatch();"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.children.length() == 1 else {
    fail("startsWith fixture must contain one function candidate")
  }
  match program.root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) =>
      fail("String.startsWith function lost bytecode eligibility")
  }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "false")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}
