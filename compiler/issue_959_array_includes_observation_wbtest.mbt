///|
test "candidate Array.includes interruption starts Bytecode only" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(
      interp,
      "var sparse = Array(100000); " +
      "function missing() { return sparse.includes(1); }",
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
          @parser.parse("missing();").stmts,
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
    None => fail("Array.includes traversal must be interruptible")
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate Array.includes function remains bytecode-eligible" {
  let source = "var sparse = Array(100000); " +
    "function missing() { return sparse.includes(1); } " +
    "missing();"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.children.length() == 1 else {
    fail("Array.includes fixture must contain one function candidate")
  }
  match program.root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) =>
      fail("Array.includes function lost bytecode eligibility")
  }
}

///|
test "candidate generic Array.includes caller remains bytecode-eligible" {
  let source =
    #|var later = { length: 2, 0: 0, 1: 0 };
    #|function mutation() {
    #|  return Array.prototype.includes.call(later, 1);
    #|}
    #|mutation();
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  let mut found = false
  for child in program.root.children {
    match child.name {
      Some("mutation") => {
        found = true
        match child.selection {
          UseBytecode(_) => ()
          UseTreeWalker(_) =>
            fail("generic Array.includes caller lost bytecode eligibility")
        }
      }
      _ => ()
    }
  }
  assert_true(found)
}
