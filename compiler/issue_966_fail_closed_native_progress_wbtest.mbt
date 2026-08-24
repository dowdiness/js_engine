///|
test "issue 966 candidate native guard fails closed without route fallback" {
  let interp = @interpreter.new_interpreter()
  let native_guard : Value = Value::Object({
    bag: PropertyBag::PropertyBag(),
    prototype: Value::Null,
    callable: Some(
      Callable::NonConstructableCallable("issue-966-native-progress", fn(
        _args,
      ) raise {
        interp.reject_unobserved_native_progress()
        Value::Undefined
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
  interp.global.def_builtin("testNativeGuard", native_guard)
  let source = "testNativeGuard();"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  match program.root.selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("native guard fixture must start through Bytecode")
  }
  let policy = match
    @runtime.ExecutionPolicy::new(100L, 100L, @runtime.InterruptionHandle()) {
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
          @parser.parse(source).stmts,
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
    None => fail("bounded native guard must reject before native work")
  }
  let starts = candidate_started_executors_for_wb(evidence)
  assert_eq(starts.length(), 1)
  match starts[0] {
    CandidateBytecodeExecutor => ()
    CandidateTreeWalkerExecutor =>
      fail("bounded native guard unexpectedly started Tree-walker")
  }
  assert_eq(evidence.val.summary.bytecode_starts, 1)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}
