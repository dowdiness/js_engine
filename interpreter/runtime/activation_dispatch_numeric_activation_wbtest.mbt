///|
fn numeric_activation_test_fixture(
  source : String,
) -> (
  Interpreter,
  PrimitiveProgramDispatchShell,
  TrustedNumericRecursionRegistry,
  NumericRecursionPlan,
) raise {
  let interp = Interpreter::new()
  let stmts = @parser.parse(source).stmts
  let plan = match classify_numeric_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact numeric-recursion plan")
  }
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_numeric_recursion_registry(preflight, stmts)
  let shell = PrimitiveProgramDispatchShell(
    interp,
    numeric_registry=Some(registry),
  )
  (interp, shell, registry, plan)
}

///|
fn numeric_activation_test_enter(
  shell : PrimitiveProgramDispatchShell,
  registry : TrustedNumericRecursionRegistry,
  name : String,
  argument : Double,
  loc : @token.Loc,
) -> (DispatchActivationCleanup, DispatchNumericCallStart) raise {
  let callee = registry.require_named(shell.interp, name)
  let request = DispatchCallRequest(
    callee~,
    this_value=Undefined,
    args=[Number(argument)],
    loc~,
  )
  match
    shell.perform_effect(
      DispatchEnterActivation(DispatchCallActivation(request)),
    ) {
    DispatchCallAccepted(cleanup, DispatchNumericCall(start)) =>
      (cleanup, start)
    _ => fail("expected a trusted numeric call activation")
  }
}

///|
fn numeric_activation_test_release(
  shell : PrimitiveProgramDispatchShell,
  cleanup : DispatchActivationCleanup,
  completion : DispatchCompletion,
) -> Unit raise {
  match shell.perform_effect(DispatchReleaseActivation(cleanup, completion)) {
    DispatchCleanupCompleted => ()
    _ => fail("expected numeric activation cleanup")
  }
}

///|
test "trusted numeric call entry returns capability-only activation state" {
  let (_, shell, registry, plan) = numeric_activation_test_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let (cleanup, start) = numeric_activation_test_enter(
    shell,
    registry,
    "f",
    7.0,
    plan.root_call_loc,
  )
  inspect(start.parameter.id == cleanup.id, content="true")
  inspect(start.recursive_callee.id == cleanup.id, content="true")
  inspect(
    start.recipe.recursive_call_loc ==
    plan.entry.expression_recipe.recursive_call_loc,
    content="true",
  )
  numeric_activation_test_release(shell, cleanup, DispatchReturn(Number(7.0)))
}

///|
test "numeric parameter and callee capabilities enforce live one-owner use" {
  let (_, shell, registry, plan) = numeric_activation_test_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let (cleanup, start) = numeric_activation_test_enter(
    shell,
    registry,
    "f",
    7.0,
    plan.root_call_loc,
  )
  match
    shell.perform_effect(
      DispatchRun(DispatchReadNumericParameter(start.parameter)),
    ) {
    DispatchWorkCompleted(DispatchNormal(Number(value))) =>
      inspect(value, content="7")
    _ => fail("expected the live numeric parameter")
  }
  let capabilities = shell.require_numeric_capabilities(start.parameter.id)
  let parameter = match capabilities.parameter {
    Some(found) => found
    None => fail("expected an activation-owned parameter")
  }
  guard parameter.env.bindings.get(parameter.name) is Some(binding) else {
    fail("expected the prepared parameter binding")
  }
  binding.value = Number(6.0)
  match
    shell.perform_effect(
      DispatchRun(DispatchReadNumericParameter(start.parameter)),
    ) {
    DispatchWorkCompleted(DispatchNormal(Number(value))) =>
      inspect(value, content="6")
    _ => fail("parameter reads must not use an entry-time snapshot")
  }

  let foreign_read = try {
    let _ = shell.perform_effect(
      DispatchRun(
        DispatchReadNumericParameter(
          DispatchParameterBindingToken(id=start.parameter.id + 1),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(foreign_read, content="rejected")
  let before_capture = try {
    let _ = shell.perform_effect(
      DispatchRun(
        DispatchStartCapturedNumericCall(
          start.recursive_callee,
          5.0,
          plan.entry.expression_recipe.recursive_call_loc,
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(before_capture, content="rejected")
  match
    shell.perform_effect(
      DispatchRun(DispatchCaptureTrustedCallee(start.recursive_callee)),
    ) {
    DispatchWorkCompleted(DispatchNormal(Undefined)) => ()
    _ => fail("expected trusted callee capture")
  }
  let duplicate_capture = try {
    let _ = shell.perform_effect(
      DispatchRun(DispatchCaptureTrustedCallee(start.recursive_callee)),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(duplicate_capture, content="rejected")
  let child_request = match
    shell.perform_effect(
      DispatchRun(
        DispatchStartCapturedNumericCall(
          start.recursive_callee,
          5.0,
          plan.entry.expression_recipe.recursive_call_loc,
        ),
      ),
    ) {
    DispatchWorkSuspended(
      DispatchSuspendCall(request, DispatchDeliverCallResult)
    ) => request
    _ => fail("expected a captured numeric call request")
  }
  let expected_callee = registry.require_named(shell.interp, "f")
  inspect(strict_equal(child_request.callee, expected_callee), content="true")
  inspect(child_request.this_value is Undefined, content="true")
  guard child_request.args.length() == 1 &&
    child_request.args[0] is Number(child_argument) else {
    fail("expected one numeric child argument")
  }
  inspect(child_argument, content="5")
  inspect(
    child_request.loc == plan.entry.expression_recipe.recursive_call_loc,
    content="true",
  )
  let duplicate_start = try {
    let _ = shell.perform_effect(
      DispatchRun(
        DispatchStartCapturedNumericCall(
          start.recursive_callee,
          4.0,
          plan.entry.expression_recipe.recursive_call_loc,
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(duplicate_start, content="rejected")
  numeric_activation_test_release(shell, cleanup, DispatchReturn(Number(7.0)))
  let stale_read = try {
    let _ = shell.perform_effect(
      DispatchRun(DispatchReadNumericParameter(start.parameter)),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(stale_read, content="rejected")
}

///|
test "mutual numeric calls retain child-to-parent LIFO ownership" {
  let (_, shell, registry, plan) = numeric_activation_test_fixture(
    "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
    "function g(m){if(m===0)return 0;return 1+f(m-1);}" +
    "f(256);",
  )
  let peer = match plan.peer {
    Some(found) => found
    None => fail("expected the mutual peer")
  }
  let (parent_cleanup, parent_start) = numeric_activation_test_enter(
    shell,
    registry,
    "f",
    3.0,
    plan.root_call_loc,
  )
  let _ = shell.perform_effect(
    DispatchRun(DispatchCaptureTrustedCallee(parent_start.recursive_callee)),
  )
  let child_request = match
    shell.perform_effect(
      DispatchRun(
        DispatchStartCapturedNumericCall(
          parent_start.recursive_callee,
          2.0,
          plan.entry.expression_recipe.recursive_call_loc,
        ),
      ),
    ) {
    DispatchWorkSuspended(DispatchSuspendCall(request, _)) => request
    _ => fail("expected the mutual peer call request")
  }
  let expected_peer = registry.require_named(shell.interp, "g")
  inspect(strict_equal(child_request.callee, expected_peer), content="true")
  let (child_cleanup, child_start) = match
    shell.perform_effect(
      DispatchEnterActivation(DispatchCallActivation(child_request)),
    ) {
    DispatchCallAccepted(cleanup, DispatchNumericCall(start)) =>
      (cleanup, start)
    _ => fail("expected the peer activation")
  }
  inspect(
    child_start.recipe.recursive_call_loc ==
    peer.expression_recipe.recursive_call_loc,
    content="true",
  )
  match
    shell.perform_effect(
      DispatchRun(DispatchReadNumericParameter(child_start.parameter)),
    ) {
    DispatchWorkCompleted(DispatchNormal(Number(value))) =>
      inspect(value, content="2")
    _ => fail("expected the peer parameter")
  }
  let shadowed_parent_token = try {
    let _ = shell.perform_effect(
      DispatchRun(DispatchReadNumericParameter(parent_start.parameter)),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(shadowed_parent_token, content="rejected")
  let out_of_order = try {
    numeric_activation_test_release(
      shell,
      parent_cleanup,
      DispatchReturn(Number(3.0)),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
    _ => "wrong error"
  }
  inspect(out_of_order, content="rejected")
  let _ = shell.perform_effect(
    DispatchRun(DispatchCaptureTrustedCallee(child_start.recursive_callee)),
  )
  let grandchild_request = match
    shell.perform_effect(
      DispatchRun(
        DispatchStartCapturedNumericCall(
          child_start.recursive_callee,
          1.0,
          peer.expression_recipe.recursive_call_loc,
        ),
      ),
    ) {
    DispatchWorkSuspended(DispatchSuspendCall(request, _)) => request
    _ => fail("expected the entry call request from the peer")
  }
  let expected_entry = registry.require_named(shell.interp, "f")
  inspect(
    strict_equal(grandchild_request.callee, expected_entry),
    content="true",
  )
  numeric_activation_test_release(
    shell,
    child_cleanup,
    DispatchReturn(Number(2.0)),
  )
  numeric_activation_test_release(
    shell,
    parent_cleanup,
    DispatchReturn(Number(3.0)),
  )
}

///|
fn numeric_activation_test_cleanup_completion(
  completion : DispatchCompletion,
  sentinel : Int,
) -> Unit raise {
  let (interp, shell, registry, plan) = numeric_activation_test_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  dispatch_shell_test_install_realm_sentinel(interp, sentinel)
  let saved_conflicts : @set.Set[String] = @set.Set::default()
  saved_conflicts.add("saved")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(saved_conflicts)
  let (cleanup, _) = numeric_activation_test_enter(
    shell,
    registry,
    "f",
    1.0,
    plan.root_call_loc,
  )
  inspect(interp.in_nonarrow_param_default_eval, content="false")
  inspect(interp.param_default_eval_var_conflicts is None, content="true")
  numeric_activation_test_release(shell, cleanup, completion)
  dispatch_shell_test_expect_realm_sentinel(interp, sentinel)
  inspect(interp.in_nonarrow_param_default_eval, content="true")
  match interp.param_default_eval_var_conflicts {
    Some(found) =>
      inspect(physical_equal(found, saved_conflicts), content="true")
    None => fail("expected parameter-gate state to be restored")
  }
}

///|
test "numeric activation cleanup restores normal and abrupt dynamic state" {
  numeric_activation_test_cleanup_completion(DispatchNormal(Number(1.0)), 31)
  numeric_activation_test_cleanup_completion(
    DispatchThrow(JsException(Number(2.0))),
    32,
  )
  numeric_activation_test_cleanup_completion(
    DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)),
    33,
  )
}

///|
test "numeric setup rejection retains state until exactly one rollback" {
  let (interp, shell, registry, plan) = numeric_activation_test_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  dispatch_shell_test_install_realm_sentinel(interp, 36)
  let saved_conflicts : @set.Set[String] = @set.Set::default()
  saved_conflicts.add("rejected")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(saved_conflicts)
  let callee = registry.require_named(interp, "f")
  let id = shell.reserve_program_cleanup_id()
  let cleared_realm = begin_cleared_active_callee_realm(interp.realm_state)
  let active_realm = begin_active_callee_realm_value(interp.realm_state, callee)
  let parameter_gate = interp.begin_simple_user_func_parameter_gate()
  let resources = DispatchNumericCallRealmCleanup::DispatchNumericCallRealmCleanup(
    cleared_realm~,
    active_realm~,
    parameter_gate~,
  )
  let setup_error : Error = @errors.SyntaxError(message="numeric setup failed")
  let rejected = shell.complete_numeric_call_preparation(
    id,
    plan.entry,
    resources,
    Err(setup_error),
  )
  let cleanup = match rejected {
    DispatchActivationRejected(
      cleanup,
      DispatchEntryGuestThrow(@errors.SyntaxError(message~))
    ) => {
      inspect(message, content="numeric setup failed")
      cleanup
    }
    _ => fail("expected a rejected numeric entry")
  }
  inspect(shell.cleanup_stack.length(), content="1")
  inspect(interp.in_nonarrow_param_default_eval, content="false")
  inspect(interp.param_default_eval_var_conflicts is None, content="true")
  let wrong_release = try {
    let _ = shell.perform_effect(
      DispatchReleaseActivation(
        DispatchActivationCleanup(cleanup.id),
        DispatchThrow(setup_error),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(wrong_release, content="rejected")
  inspect(shell.cleanup_stack.length(), content="1")
  inspect(interp.in_nonarrow_param_default_eval, content="false")
  let rollback = DispatchRollbackRejectedEntry(
    cleanup,
    DispatchThrow(setup_error),
  )
  match shell.perform_effect(rollback) {
    DispatchCleanupCompleted => ()
    _ => fail("expected rejected numeric rollback")
  }
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 36)
  inspect(interp.in_nonarrow_param_default_eval, content="true")
  match interp.param_default_eval_var_conflicts {
    Some(found) =>
      inspect(physical_equal(found, saved_conflicts), content="true")
    None => fail("expected the rejected parameter gate to be restored")
  }
  let duplicate = try {
    let _ = shell.perform_effect(rollback)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(duplicate, content="rejected")
}

///|
test "numeric abrupt cleanup records callee source before restoring its caller" {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = Some("numeric.js")
  let stmts = @parser.parse(
      "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
    ).stmts
  let plan = match classify_numeric_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact numeric-recursion plan")
  }
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_numeric_recursion_registry(preflight, stmts)
  let shell = PrimitiveProgramDispatchShell(
    interp,
    numeric_registry=Some(registry),
  )
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let thrown : Error = @errors.TypeError(message="numeric failure")
  let observed : Result[Unit, SourceObservedFailure] = observe_source_failure(
    interp.realm_state,
    () => {
      let (cleanup, _) = numeric_activation_test_enter(
        shell,
        registry,
        "f",
        1.0,
        plan.root_call_loc,
      )
      numeric_activation_test_release(shell, cleanup, DispatchThrow(thrown))
      raise thrown
    },
  )
  match observed {
    Err(failure) => {
      inspect(physical_equal(failure.cause(), thrown), content="true")
      match failure.source_identity() {
        Some(source) => inspect(source, content="numeric.js")
        None => fail("expected the numeric callee source identity")
      }
    }
    Ok(_) => fail("expected the numeric source failure")
  }
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected the caller source identity to be restored")
  }
}

///|
test "numeric cleanup restores every nested activation after a shell failure" {
  let (interp, shell, registry, plan) = numeric_activation_test_fixture(
    "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
    "function g(m){if(m===0)return 0;return 1+f(m-1);}" +
    "f(256);",
  )
  dispatch_shell_test_install_realm_sentinel(interp, 34)
  let saved_conflicts : @set.Set[String] = @set.Set::default()
  saved_conflicts.add("outer")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(saved_conflicts)
  let (_, parent_start) = numeric_activation_test_enter(
    shell,
    registry,
    "f",
    2.0,
    plan.root_call_loc,
  )
  let _ = shell.perform_effect(
    DispatchRun(DispatchCaptureTrustedCallee(parent_start.recursive_callee)),
  )
  let child_request = match
    shell.perform_effect(
      DispatchRun(
        DispatchStartCapturedNumericCall(
          parent_start.recursive_callee,
          1.0,
          plan.entry.expression_recipe.recursive_call_loc,
        ),
      ),
    ) {
    DispatchWorkSuspended(DispatchSuspendCall(request, _)) => request
    _ => fail("expected the nested numeric request")
  }
  let _ = shell.perform_effect(
    DispatchEnterActivation(DispatchCallActivation(child_request)),
  )
  inspect(shell.cleanup_stack.length(), content="2")
  shell.restore_all_cleanup(
    failure=Some(InvalidActivationDispatchShell("test failure")),
  )
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 34)
  inspect(interp.in_nonarrow_param_default_eval, content="true")
  match interp.param_default_eval_var_conflicts {
    Some(found) =>
      inspect(physical_equal(found, saved_conflicts), content="true")
    None => fail("expected the outer parameter gate after full restoration")
  }
}

///|
test "numeric expression observation consumes exactly one execution step" {
  let interp = Interpreter::new()
  let shell = PrimitiveProgramDispatchShell(interp)
  let control = ExecutionControl(
    remaining_steps=1,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  interp.with_execution_control(control, () => {
    match
      shell.perform_effect(
        DispatchRun(
          DispatchObserveExpressionStep(DispatchNumericObserveNumber(1.0)),
        ),
      ) {
      DispatchWorkCompleted(DispatchNormal(Undefined)) => ()
      _ => fail("expected the first expression observation")
    }
    inspect(control.remaining_steps(), content="0")
    match
      shell.perform_effect(
        DispatchRun(
          DispatchObserveExpressionStep(DispatchNumericObserveNumber(2.0)),
        ),
      ) {
      DispatchWorkCompleted(
        DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit))
      ) => ()
      _ => fail("expected one execution-limit completion")
    }
    inspect(control.remaining_steps(), content="0")
  })
}

///|
test "invalid numeric call envelopes do not acquire cleanup ownership" {
  let (interp, shell, registry, plan) = numeric_activation_test_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  dispatch_shell_test_install_realm_sentinel(interp, 35)
  let callee = registry.require_named(interp, "f")
  let bad_receiver = try {
    let _ = shell.perform_effect(
      DispatchEnterActivation(
        DispatchCallActivation(
          DispatchCallRequest(
            callee~,
            this_value=Null,
            args=[Number(1.0)],
            loc=plan.root_call_loc,
          ),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(bad_receiver, content="rejected")
  let bad_argument = try {
    let _ = shell.perform_effect(
      DispatchEnterActivation(
        DispatchCallActivation(
          DispatchCallRequest(
            callee~,
            this_value=Undefined,
            args=[String_("1")],
            loc=plan.root_call_loc,
          ),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(bad_argument, content="rejected")
  let untrusted = try {
    let _ = shell.perform_effect(
      DispatchEnterActivation(
        DispatchCallActivation(
          DispatchCallRequest(
            callee=make_native_func(name="untrusted", _args => Undefined),
            this_value=Undefined,
            args=[Number(1.0)],
            loc=plan.root_call_loc,
          ),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(untrusted, content="rejected")
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 35)
}
