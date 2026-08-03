///|
fn constructor_activation_test_fixture(
  probe : DispatchObservationProbe,
) -> (
  Interpreter,
  PrimitiveProgramDispatchShell,
  DispatchActivationCleanup,
  DispatchStatementCursor,
  ConstructorRecursionPlan,
) raise {
  let interp = Interpreter::new()
  let source =
    "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}}" +
    "new Node(4).value;"
  let stmts = @parser.parse(source).stmts
  let plan = match classify_constructor_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact constructor-recursion plan")
  }
  let preflight = match interp.preflight_constructor_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free constructor preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let ctx : ExecContext = { strict: false, current_generator: None }
  let _ = interp.exec_stmt(ctx, stmts[0], interp.global)
  let registry = interp.seal_constructor_recursion_registry(preflight, stmts)
  let shell = PrimitiveProgramDispatchShell(
    interp,
    constructor_registry=Some(registry),
    activation_observation_port=probe.port(),
  )
  let root = registry.require_root_function(interp)
  let request = DispatchConstructRequest(
    ctor=root.callee,
    args=[Number(4.0)],
    loc=plan.root_member_loc,
  )
  dispatch_shell_test_install_realm_sentinel(interp, 81)
  match shell.perform_effect(DispatchEnterActivation(DispatchConstructActivation(request))) {
    DispatchCallAccepted(cleanup, DispatchConstructorCall(cursor, _)) =>
      (interp, shell, cleanup, cursor, plan)
    _ => fail("expected a trusted constructor activation")
  }
}

///|
fn constructor_activation_test_release(
  shell : PrimitiveProgramDispatchShell,
  cleanup : DispatchActivationCleanup,
  completion : DispatchCompletion,
) -> Unit raise {
  match shell.perform_effect(DispatchReleaseActivation(cleanup, completion)) {
    DispatchCleanupCompleted => ()
    _ => fail("expected constructor activation cleanup")
  }
}

///|
test "constructor recursive edge observes five steps before construct" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (interp, shell, cleanup, cursor, _) =
    constructor_activation_test_fixture(probe)
  let control = ExecutionControl(
    remaining_steps=4,
    maximum_active_depth=10,
    interruption=ExecutionInterruptionRequest(),
  )
  let _ = interp.with_execution_control(control, () => {
    let result = shell.execute_constructor_body_statement({
      ctx: cursor.ctx,
      stmt: cursor.stmts[1],
      env: cursor.env,
      index: 1,
    }) catch {
      InvalidActivationDispatchShell(message) =>
        fail("constructor body dispatch rejected the trusted cursor: " + message)
    }
    let completion = match result {
      DispatchWorkCompleted(
        DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)),
      ) => DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit))
      _ => fail("expected the fifth constructor expression step to hit the limit")
    }
    inspect(control.remaining_steps(), content="0")
    constructor_activation_test_release(shell, cleanup, completion)
    inspect(shell.cleanup_stack.length(), content="0")
    dispatch_shell_test_expect_realm_sentinel(interp, 81)
    completion
  })
  inspect(probe.attempts, content="1")
  inspect(probe.acquired, content="1")
  inspect(probe.accepted, content="1")
  inspect(probe.rejected, content="0")
  inspect(probe.released, content="1")
  inspect(probe.active, content="0")
  inspect(probe.release_ordinals[0], content="1")
  inspect(probe.release_state_restored[0], content="true")
}

///|
test "constructor changed body stays legacy before managed effect" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (_, shell, cleanup, cursor, _) =
    constructor_activation_test_fixture(probe)
  let changed = @parser.parse(
    "function Node(n){this.value=n;if(n>0){this.child=new Node(n-2);}}" +
    "new Node(4).value;",
  ).stmts
  let changed_statement = match changed[0] {
    @ast.FuncDecl(_, _, body, _, _) => body[1]
    _ => fail("expected the changed constructor declaration")
  }
  let result = try {
    let _ = shell.execute_constructor_body_statement({
      ctx: cursor.ctx,
      stmt: changed_statement,
      env: cursor.env,
      index: 1,
    })
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(result, content="rejected")
  constructor_activation_test_release(shell, cleanup, DispatchNormal(Undefined))
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "constructor guest and runtime abrupt exits preserve identity and cleanup" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (interp, shell, cleanup, _, _) =
    constructor_activation_test_fixture(probe)
  let thrown : Error = JsException(String_("constructor guest throw"))
  let guest_completion = DispatchThrow(thrown)
  match guest_completion {
    DispatchThrow(found) => inspect(physical_equal(found, thrown), content="true")
    _ => fail("expected a guest throw completion")
  }
  constructor_activation_test_release(shell, cleanup, guest_completion)
  inspect(shell.cleanup_stack.length(), content="0")
  inspect(probe.released, content="1")
  inspect(probe.active, content="0")
  match
    interp.run(
      @parser.parse(
        "function Safe(n){this.value=n;if(n>0){this.child=new Safe(n-1);}}" +
        "new Safe(0).value;",
      ).stmts,
    ) {
    Number(value) => inspect(value, content="0")
    other => fail("expected a later shallow constructor, got " + other.to_string())
  }

  let runtime_interp = Interpreter::new()
  let runtime_probe = DispatchObservationProbe(observed_interp=Some(runtime_interp))
  let (runtime_interp, runtime_shell, runtime_cleanup, _, _) =
    constructor_activation_test_fixture(runtime_probe)
  let runtime_error : Error = ExecutionControlError(ExecutionLimit)
  let runtime_completion = DispatchRuntimeAbrupt(runtime_error)
  match runtime_completion {
    DispatchRuntimeAbrupt(found) =>
      inspect(physical_equal(found, runtime_error), content="true")
    _ => fail("expected a runtime-abrupt completion")
  }
  constructor_activation_test_release(
    runtime_shell,
    runtime_cleanup,
    runtime_completion,
  )
  inspect(runtime_shell.cleanup_stack.length(), content="0")
  inspect(runtime_probe.released, content="1")
  inspect(runtime_probe.active, content="0")
  match
    runtime_interp.run(
      @parser.parse(
        "function Safe(n){this.value=n;if(n>0){this.child=new Safe(n-1);}}" +
        "new Safe(0).value;",
      ).stmts,
    ) {
    Number(value) => inspect(value, content="0")
    other => fail("expected a later shallow constructor, got " + other.to_string())
  }
  ignore(interp)
  ignore(runtime_interp)
}
