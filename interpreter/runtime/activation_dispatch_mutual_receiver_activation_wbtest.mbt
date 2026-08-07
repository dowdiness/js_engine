///|
fn mutual_receiver_activation_test_fixture_for(
  source : String,
) -> (
  Interpreter,
  PrimitiveProgramDispatchShell,
  TrustedMutualReceiverRecursionRegistry,
) raise {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = Some("mutual.js")
  let stmts = @parser.parse(source).stmts
  let preflight = match
    interp.preflight_dispatchable_mutual_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected callback-free mutual receiver preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let ctx : ExecContext = { strict: false, current_generator: None }
  for index in 0..<3 {
    let _ = interp.exec_stmt(ctx, stmts[index], interp.global)
  }
  let registry = interp.seal_mutual_receiver_recursion_registry(
    preflight, stmts,
  )
  let shell = PrimitiveProgramDispatchShell(
    interp,
    owned_receiver_call=Some(owned_mutual_receiver_call(registry)),
  )
  (interp, shell, registry)
}

///|
fn mutual_receiver_activation_test_fixture() -> (
  Interpreter,
  PrimitiveProgramDispatchShell,
  TrustedMutualReceiverRecursionRegistry,
) raise {
  mutual_receiver_activation_test_fixture_for(MUTUAL_RECEIVER_RECURSION_SOURCE)
}

///|
fn mutual_receiver_activation_test_enter_root(
  shell : PrimitiveProgramDispatchShell,
  registry : TrustedMutualReceiverRecursionRegistry,
) -> (DispatchActivationCleanup, DispatchStatementCursor) raise {
  let receiver = registry.require_receiver(shell.interp)
  let callee = registry.require_function(shell.interp, registry.plan.root_node)
  let request = DispatchCallRequest(
    callee~,
    this_value=receiver,
    args=[Number(registry.plan.initial_argument)],
    loc=registry.plan.root_member_loc,
  )
  match
    shell.perform_effect(
      DispatchEnterActivation(DispatchCallActivation(request)),
    ) {
    DispatchCallAccepted(cleanup, DispatchCallBody(cursor)) => (cleanup, cursor)
    _ => fail("expected a trusted mutual receiver activation")
  }
}

///|
test "trusted mutual receiver entry owns its node and restores dynamic state" {
  let (interp, shell, registry) = mutual_receiver_activation_test_fixture()
  dispatch_shell_test_install_realm_sentinel(interp, 71)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let saved_conflicts : @set.Set[String] = @set.Set::default()
  saved_conflicts.add("caller")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(saved_conflicts)

  let (cleanup, cursor) = mutual_receiver_activation_test_enter_root(
    shell, registry,
  )
  let trusted = mutual_receiver_registry_function(
    registry,
    registry.plan.root_node,
  )
  inspect(shell.cleanup_stack.length(), content="1")
  inspect(cursor.index, content="0")
  inspect(cursor.stmts.length(), content="2")
  guard cursor.env.bindings.get("this") is Some(this_binding) else {
    fail("expected a mutual receiver this binding")
  }
  inspect(
    mutual_receiver_value_identity(trusted.receiver, this_binding.value),
    content="true",
  )
  guard cursor.env.bindings.get(trusted.plan.parameter)
    is Some(parameter_binding) else {
    fail("expected the mutual receiver parameter binding")
  }
  inspect(parameter_binding.value, content="256")
  inspect(interp.in_nonarrow_param_default_eval, content="false")
  inspect(interp.param_default_eval_var_conflicts is None, content="true")
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="mutual.js")
    None => fail("expected the mutual receiver source identity")
  }
  match
    shell.perform_effect(
      DispatchReleaseActivation(cleanup, DispatchReturn(Number(1.0))),
    ) {
    DispatchCleanupCompleted => ()
    _ => fail("expected mutual receiver activation cleanup")
  }
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 71)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected caller source identity restoration")
  }
  inspect(interp.in_nonarrow_param_default_eval, content="true")
  match interp.param_default_eval_var_conflicts {
    Some(found) =>
      inspect(physical_equal(found, saved_conflicts), content="true")
    None => fail("expected caller parameter-gate restoration")
  }
}

///|
test "mutual receiver body observes five expression steps before cross-call" {
  let (interp, shell, registry) = mutual_receiver_activation_test_fixture()
  let control = ExecutionControl(
    remaining_steps=4,
    maximum_active_depth=10,
    interruption=ExecutionInterruptionRequest(),
  )
  interp.with_execution_control(control, () => {
    let (cleanup, cursor) = mutual_receiver_activation_test_enter_root(
      shell, registry,
    )
    let owned = match shell.owned_receiver_call {
      Some(owned) => owned
      None => fail("expected a mutual receiver owner")
    }
    let result = shell.execute_mutual_receiver_body_statement(
      { ctx: cursor.ctx, stmt: cursor.stmts[1], env: cursor.env, index: 1 },
      owned,
    ) catch {
      InvalidActivationDispatchShell(message) =>
        fail(
          "mutual receiver body dispatch rejected trusted cursor: " + message,
        )
    }
    let completion = match result {
      DispatchWorkCompleted(
        DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit))
      ) => DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit))
      _ =>
        fail("expected the fifth mutual body expression step to hit the limit")
    }
    inspect(control.remaining_steps(), content="0")
    match shell.perform_effect(DispatchReleaseActivation(cleanup, completion)) {
      DispatchCleanupCompleted => ()
      _ => fail("expected mutual receiver cleanup after body rejection")
    }
    inspect(shell.cleanup_stack.length(), content="0")
  })
}

///|
test "mutual receiver root observes setup steps before first call" {
  let interp = Interpreter::new()
  let stmts = @parser.parse(MUTUAL_RECEIVER_RECURSION_SOURCE).stmts
  let preflight = match
    interp.preflight_dispatchable_mutual_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected callback-free mutual receiver preflight")
  }
  let ctx : ExecContext = { strict: false, current_generator: None }
  let control = ExecutionControl(
    remaining_steps=2,
    maximum_active_depth=1024,
    interruption=ExecutionInterruptionRequest(),
  )
  let completion = interp.with_execution_control(control, () => {
    let shell = PrimitiveProgramDispatchShell(
      interp,
      mutual_receiver_root_preflight=Some(preflight),
      mutual_receiver_root_stmts=Some(stmts),
      activation_observation_port=interp.execution_control_activation_observation_port(),
    )
    let completion = shell.drive_root_program(stmts, ctx)
    inspect(shell.cleanup_stack.length(), content="0")
    completion
  })
  match completion {
    DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)) => ()
    _ => fail("expected setup observation to reject before the first call")
  }
  let leaf = @parser.parse("7;").stmts
  match PrimitiveProgramDispatchShell(interp).drive_root_program(leaf, ctx) {
    DispatchNormal(Number(value)) => inspect(value, content="7")
    _ => fail("expected a later leaf after mutual setup rejection")
  }
}

///|
fn mutual_receiver_probe_run(
  source : String,
) -> (Value, Array[String]) raise Error {
  let interp = Interpreter::new()
  let stmts = @parser.parse(source).stmts
  let preflight = match
    interp.preflight_dispatchable_mutual_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected callback-free mutual receiver preflight")
  }
  let events : Array[String] = []
  let shell = PrimitiveProgramDispatchShell(
    interp,
    mutual_receiver_root_preflight=Some(preflight),
    mutual_receiver_root_stmts=Some(stmts),
    activation_observation_port=activation_observation_probe_port(events, true),
  )
  let completion = shell.drive_root_program(stmts, {
    strict: false,
    current_generator: None,
  })
  guard shell.owned_receiver_call is None else {
    fail("mutual receiver registry must be released after the root")
  }
  (activation_dispatch_root_value(completion), events)
}

///|
test "mutual receiver root and reversed root release every activation once" {
  for
    source in [
      MUTUAL_RECEIVER_RECURSION_SOURCE,
      REVERSED_MUTUAL_RECEIVER_RECURSION_SOURCE,
    ] {
    let (value, events) = mutual_receiver_probe_run(source)
    inspect(value, content="256")
    let mut attempts = 0
    let mut acquired = 0
    let mut accepted = 0
    let mut released = 0
    for event in events {
      match event {
        "attempt" => attempts += 1
        "acquired" => acquired += 1
        "accepted" => accepted += 1
        "released" => released += 1
        _ => fail("unexpected mutual receiver observation event")
      }
    }
    inspect(attempts, content="257")
    inspect(acquired, content="257")
    inspect(accepted, content="257")
    inspect(released, content="257")
  }
}
