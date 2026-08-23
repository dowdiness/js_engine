///|
test "RED: bounded String.lastIndexOf search must reach execution limit" {
  let interp = @interpreter.new_interpreter()
  // Prepare the large haystack outside the bounded call so this test measures
  // only the reverse search loop.
  ignore(
    run_executor_neutral_bytecode(
      interp,
      "var large = \"x\".repeat(100000); " +
      "function lastIndexOfMissing() { return large.lastIndexOf(\"z\"); }",
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
          @parser.parse("lastIndexOfMissing();").stmts,
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
    None => fail("lastIndexOf search must be interruptible")
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "default bounded String.lastIndexOf search reaches execution limit" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(
      interp,
      "var large = \"x\".repeat(100000); " +
      "function lastIndexOfMissing() { return large.lastIndexOf(\"z\"); }",
    ),
  )
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let caught : Error? = interp.with_execution_policy(policy, () => {
    try {
      ignore(interp.run(@parser.parse("lastIndexOfMissing();").stmts))
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
    None => fail("default lastIndexOf search must be interruptible")
  }
}

///|
test "candidate String.lastIndexOf keeps the search function on Bytecode" {
  let source = "var large = \"x\".repeat(100000); " +
    "function lastIndexOfMissing() { return large.lastIndexOf(\"z\"); } " +
    "lastIndexOfMissing();"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.children.length() == 1 else {
    fail("lastIndexOf fixture must contain one function candidate")
  }
  match program.root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) =>
      fail("String.lastIndexOf function lost bytecode eligibility")
  }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "-1")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}
