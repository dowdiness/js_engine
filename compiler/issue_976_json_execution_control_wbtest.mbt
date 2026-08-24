///|
fn assert_candidate_json_boundary_976(
  interp : @interpreter.Interpreter,
  call_source : String,
) -> Unit raise Error {
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded JSON execution-control policy")
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
    None =>
      fail(
        "JSON native work must stop bounded execution before unobserved work",
      )
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate JSON execution-control boundaries stop before native work" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(
      interp,
      (
        #|var issue976ParseText = '"' + 'a'.repeat(100000) + '"';
        #|var issue976LargeString = 'a'.repeat(100000);
        #|var issue976LargeArray = Array(100000);
        #|var issue976List = new Proxy(['x'], { get(t, k) { return t[k]; } });
        #|function parseLarge() { return JSON.parse(issue976ParseText); }
        #|function stringifyLarge() { return JSON.stringify(issue976LargeString); }
        #|function stringifyArray() { return JSON.stringify(issue976LargeArray); }
        #|function stringifyList() { return JSON.stringify({x: 1}, issue976List); }
      ),
    ),
  )
  for
    call_source in [
      "parseLarge();", "stringifyLarge();", "stringifyArray();", "stringifyList();",
    ] {
    assert_candidate_json_boundary_976(interp, call_source)
  }
}

///|
test "candidate JSON parse function remains bytecode eligible" {
  let source = "var issue976ParseText = '\"' + 'a'.repeat(100000) + '\"'; " +
    "function parseLarge() { return JSON.parse(issue976ParseText); } " +
    "parseLarge();"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.children.length() == 1 else {
    fail("JSON.parse fixture must contain one function candidate")
  }
  match program.root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("JSON.parse function lost bytecode eligibility")
  }
}
