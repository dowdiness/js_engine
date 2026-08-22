///|
fn receiver_activation_test_fixture() -> (
  Interpreter,
  PrimitiveProgramDispatchShell,
  TrustedReceiverRecursionRegistry,
  ReceiverRecursionPlan,
  Value,
  Value,
) raise {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = Some("receiver.js")
  let stmts = @parser.parse(
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step};receiver.step(256);",
    ).stmts
  let plan = match classify_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact receiver-recursion plan")
  }
  let preflight = match
    interp.preflight_dispatchable_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected callback-free receiver preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let ctx : ExecContext = { strict: false, current_generator: None }
  let _ = interp.exec_stmt(ctx, stmts[0], interp.global)
  let _ = interp.exec_stmt(ctx, stmts[1], interp.global)
  let registry = interp.seal_receiver_recursion_registry(preflight, stmts)
  let shell = PrimitiveProgramDispatchShell(
    interp,
    owned_receiver_call=Some(owned_fixed_receiver_call(registry)),
  )
  (
    interp,
    shell,
    registry,
    plan,
    registry.trusted.callee,
    registry.trusted.receiver,
  )
}

///|
fn receiver_activation_test_enter(
  shell : PrimitiveProgramDispatchShell,
  plan : ReceiverRecursionPlan,
  callee : Value,
  receiver : Value,
) -> (DispatchActivationCleanup, DispatchStatementCursor) raise {
  let request = DispatchCallRequest(
    callee~,
    this_value=receiver,
    args=[Number(256.0)],
    loc=plan.recipe.root_member_loc,
  )
  match
    shell.perform_effect(
      DispatchEnterActivation(DispatchCallActivation(request)),
    ) {
    DispatchCallAccepted(cleanup, DispatchCallBody(cursor)) => (cleanup, cursor)
    _ => fail("expected a trusted receiver activation")
  }
}

///|
fn receiver_activation_test_release(
  shell : PrimitiveProgramDispatchShell,
  cleanup : DispatchActivationCleanup,
  completion : DispatchCompletion,
) -> Unit raise {
  match shell.perform_effect(DispatchReleaseActivation(cleanup, completion)) {
    DispatchCleanupCompleted => ()
    _ => fail("expected receiver activation cleanup")
  }
}

///|
fn receiver_activation_test_cleanup_completion(
  completion : DispatchCompletion,
  sentinel : Int,
) -> Unit raise {
  let (interp, shell, _, plan, callee, receiver) = receiver_activation_test_fixture()
  dispatch_shell_test_install_realm_sentinel(interp, sentinel)
  let saved_conflicts : @set.Set[String] = Default::default()
  saved_conflicts.add("saved")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(saved_conflicts)
  let (cleanup, _) = receiver_activation_test_enter(
    shell, plan, callee, receiver,
  )
  inspect(interp.in_nonarrow_param_default_eval, content="false")
  inspect(interp.param_default_eval_var_conflicts is None, content="true")
  receiver_activation_test_release(shell, cleanup, completion)
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, sentinel)
  inspect(interp.in_nonarrow_param_default_eval, content="true")
  match interp.param_default_eval_var_conflicts {
    Some(found) =>
      inspect(physical_equal(found, saved_conflicts), content="true")
    None => fail("expected receiver parameter-gate state to be restored")
  }
}

///|
test "trusted receiver entry owns this and restores dynamic state" {
  let (interp, shell, _, plan, callee, receiver) = receiver_activation_test_fixture()
  dispatch_shell_test_install_realm_sentinel(interp, 61)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let saved_conflicts : @set.Set[String] = Default::default()
  saved_conflicts.add("caller")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(saved_conflicts)

  let (cleanup, cursor) = receiver_activation_test_enter(
    shell, plan, callee, receiver,
  )
  inspect(shell.cleanup_stack.length(), content="1")
  inspect(cursor.index, content="0")
  inspect(cursor.stmts.length(), content="2")
  guard cursor.env.bindings.get("this") is Some(this_binding) else {
    fail("expected a receiver this binding")
  }
  inspect(
    receiver_recursion_value_identity(receiver, this_binding.value),
    content="true",
  )
  guard cursor.env.bindings.get(plan.parameter) is Some(parameter_binding) else {
    fail("expected the receiver parameter binding")
  }
  inspect(parameter_binding.value, content="256")
  inspect(interp.in_nonarrow_param_default_eval, content="false")
  inspect(interp.param_default_eval_var_conflicts is None, content="true")
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="receiver.js")
    None => fail("expected the receiver source identity")
  }

  match
    shell.perform_effect(
      DispatchReleaseActivation(cleanup, DispatchReturn(Number(256.0))),
    ) {
    DispatchCleanupCompleted => ()
    _ => fail("expected receiver activation cleanup")
  }
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 61)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected the caller source identity to be restored")
  }
  inspect(interp.in_nonarrow_param_default_eval, content="true")
  match interp.param_default_eval_var_conflicts {
    Some(found) =>
      inspect(physical_equal(found, saved_conflicts), content="true")
    None => fail("expected the caller parameter gate to be restored")
  }
}

///|
test "trusted receiver entry rejects a mismatched this before cleanup" {
  let (_, shell, _, plan, callee, receiver) = receiver_activation_test_fixture()
  let result = try {
    let _ = shell.perform_effect(
      DispatchEnterActivation(
        DispatchCallActivation(
          DispatchCallRequest(
            callee~,
            this_value=Undefined,
            args=[Number(256.0)],
            loc=plan.recipe.root_member_loc,
          ),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(result, content="rejected")
  inspect(shell.cleanup_stack.length(), content="0")
  ignore(receiver)
}

///|
test "receiver activation rejects a call location outside its recipe" {
  let (_, shell, _, plan, callee, receiver) = receiver_activation_test_fixture()
  let result = try {
    let _ = shell.perform_effect(
      DispatchEnterActivation(
        DispatchCallActivation(
          DispatchCallRequest(
            callee~,
            this_value=receiver,
            args=[Number(256.0)],
            loc=@token.Loc::default(),
          ),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(result, content="rejected")
  inspect(shell.cleanup_stack.length(), content="0")
  ignore(plan)
}

///|
test "receiver activation cleanup preserves normal, guest, and runtime exits" {
  receiver_activation_test_cleanup_completion(DispatchReturn(Number(1.0)), 62)
  receiver_activation_test_cleanup_completion(
    DispatchThrow(JsException(Number(2.0))),
    63,
  )
  receiver_activation_test_cleanup_completion(
    DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)),
    64,
  )
}

///|
test "receiver abrupt cleanup records callee source before restoring caller" {
  let (interp, shell, _, plan, callee, receiver) = receiver_activation_test_fixture()
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let thrown : Error = @errors.TypeError(message="receiver failure")
  let observed : Result[Unit, SourceObservedFailure] = observe_source_failure(
    interp.realm_state,
    () => {
      let (cleanup, _) = receiver_activation_test_enter(
        shell, plan, callee, receiver,
      )
      receiver_activation_test_release(shell, cleanup, DispatchThrow(thrown))
      raise thrown
    },
  )
  match observed {
    Err(failure) => {
      inspect(physical_equal(failure.cause(), thrown), content="true")
      match failure.source_identity() {
        Some(source) => inspect(source, content="receiver.js")
        None => fail("expected the receiver callee source identity")
      }
    }
    Ok(_) => fail("expected the receiver source failure")
  }
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected the caller source identity to be restored")
  }
}

///|
test "receiver root runtime abrupt preserves identity and balances cleanup" {
  let interp = Interpreter::new()
  let stmts = @parser.parse(
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step};receiver.step(256);",
    ).stmts
  let preflight = match
    interp.preflight_dispatchable_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected callback-free receiver preflight")
  }
  let ctx : ExecContext = { strict: false, current_generator: None }
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let completion = interp.with_execution_control(control, () => {
    let shell = PrimitiveProgramDispatchShell(
      interp,
      receiver_root_preflight=Some(preflight),
      receiver_root_stmts=Some(stmts),
    )
    let completion = shell.drive_root_program(stmts, ctx)
    inspect(shell.cleanup_stack.length(), content="0")
    completion
  })
  match completion {
    DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)) => ()
    _ =>
      fail(
        "expected the receiver execution limit to preserve runtime abrupt identity",
      )
  }
}

///|
test "receiver body observes five expression steps before recursive call" {
  let (interp, shell, _, plan, callee, receiver) = receiver_activation_test_fixture()
  let control = ExecutionControl(
    remaining_steps=4,
    maximum_active_depth=10,
    interruption=ExecutionInterruptionRequest(),
  )
  interp.with_execution_control(control, () => {
    let (cleanup, cursor) = receiver_activation_test_enter(
      shell, plan, callee, receiver,
    )
    let owned = match shell.owned_receiver_call {
      Some(owned) => owned
      None => fail("expected a fixed receiver owner")
    }
    let result = shell.execute_receiver_body_statement(
      { ctx: cursor.ctx, stmt: cursor.stmts[1], env: cursor.env, index: 1 },
      owned,
    ) catch {
      InvalidActivationDispatchShell(message) =>
        fail("receiver body dispatch rejected the trusted cursor: " + message)
    }
    let completion = match result {
      DispatchWorkCompleted(
        DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit))
      ) => DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit))
      _ => fail("expected the fifth receiver expression step to hit the limit")
    }
    inspect(control.remaining_steps(), content="0")
    receiver_activation_test_release(shell, cleanup, completion)
    inspect(shell.cleanup_stack.length(), content="0")
  })
}
