///|
fn getter_activation_test_source() -> String {
  "let n=256;" +
  "let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
  "o.x;"
}

///|
fn getter_activation_test_fixture() -> (
  Interpreter,
  PrimitiveProgramDispatchShell,
  TrustedGetterRecursionRegistry,
  GetterRecursionPlan,
  Value,
  Value,
) raise {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = Some("getter.js")
  let stmts = @parser.parse(getter_activation_test_source()).stmts
  let plan = match classify_getter_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact getter-recursion plan")
  }
  let preflight = match interp.preflight_getter_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free getter preflight")
  }
  let ctx : ExecContext = { strict: false, current_generator: None }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  for index in 0..<2 {
    match interp.exec_stmt(ctx, stmts[index], interp.global) {
      Normal(_) => ()
      _ => fail("exact getter root setup must complete normally")
    }
  }
  let registry = interp.seal_getter_recursion_registry(preflight, stmts)
  let target = registry.require_target(interp)
  guard target is Object(target_data) &&
    target_data.bag.descriptors.get(plan.property_name) is Some(descriptor) &&
    descriptor.getter is Some(getter) else {
    fail("expected the sealed getter and receiver")
  }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    getter_registry=Some(registry),
  )
  (interp, shell, registry, plan, getter, target)
}

///|
fn getter_activation_test_enter(
  shell : PrimitiveProgramDispatchShell,
  plan : GetterRecursionPlan,
  getter : Value,
  target : Value,
) -> (DispatchActivationCleanup, DispatchStatementCursor) raise {
  let request = DispatchCallRequest(
    callee=getter,
    this_value=target,
    args=[],
    loc=plan.recipe.root_member_loc,
  )
  match
    shell.perform_effect(
      DispatchEnterActivation(DispatchCallActivation(request)),
    ) {
    DispatchCallAccepted(cleanup, DispatchCallBody(cursor)) => (cleanup, cursor)
    _ => fail("expected a trusted zero-argument getter activation")
  }
}

///|
fn getter_activation_test_release(
  shell : PrimitiveProgramDispatchShell,
  cleanup : DispatchActivationCleanup,
  completion : DispatchCompletion,
) -> Unit raise {
  match shell.perform_effect(DispatchReleaseActivation(cleanup, completion)) {
    DispatchCleanupCompleted => ()
    _ => fail("expected getter activation cleanup")
  }
}

///|
test "trusted getter entry owns its receiver and restores dynamic state" {
  let (interp, shell, _, plan, getter, target) = getter_activation_test_fixture()
  dispatch_shell_test_install_realm_sentinel(interp, 41)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let saved_conflicts : @set.Set[String] = @set.Set::default()
  saved_conflicts.add("caller")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(saved_conflicts)

  let (cleanup, cursor) = getter_activation_test_enter(
    shell, plan, getter, target,
  )
  inspect(shell.cleanup_stack.length(), content="1")
  inspect(cursor.index, content="0")
  inspect(cursor.stmts.length(), content="3")
  guard cursor.env.bindings.get("this") is Some(this_binding) else {
    fail("expected a getter this binding")
  }
  inspect(
    getter_recursion_target_identity_matches(target, this_binding.value),
    content="true",
  )
  inspect(interp.in_nonarrow_param_default_eval, content="false")
  inspect(interp.param_default_eval_var_conflicts is None, content="true")
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="getter.js")
    None => fail("expected the getter source identity")
  }

  getter_activation_test_release(shell, cleanup, DispatchReturn(Number(1.0)))
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 41)
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
test "getter entry rejects untrusted envelopes before acquiring cleanup" {
  let (interp, shell, _, plan, getter, target) = getter_activation_test_fixture()
  dispatch_shell_test_install_realm_sentinel(interp, 42)
  let loc = plan.recipe.root_member_loc
  let bad_receiver = try {
    let _ = shell.perform_effect(
      DispatchEnterActivation(
        DispatchCallActivation(
          DispatchCallRequest(
            callee=getter,
            this_value=Undefined,
            args=[],
            loc~,
          ),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  let bad_callee = try {
    let _ = shell.perform_effect(
      DispatchEnterActivation(
        DispatchCallActivation(
          DispatchCallRequest(callee=target, this_value=target, args=[], loc~),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  let bad_args = try {
    let _ = shell.perform_effect(
      DispatchEnterActivation(
        DispatchCallActivation(
          DispatchCallRequest(
            callee=getter,
            this_value=target,
            args=[Undefined],
            loc~,
          ),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  let registryless = PrimitiveProgramDispatchShell(interp)
  let no_registry = try {
    let _ = registryless.perform_effect(
      DispatchEnterActivation(
        DispatchCallActivation(
          DispatchCallRequest(callee=getter, this_value=target, args=[], loc~),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(bad_receiver, content="rejected")
  inspect(bad_callee, content="rejected")
  inspect(bad_args, content="rejected")
  inspect(no_registry, content="rejected")
  inspect(shell.cleanup_stack.length(), content="0")
  inspect(registryless.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 42)
}

///|
test "getter abrupt cleanup attributes the callee and restores its caller" {
  let (interp, shell, _, plan, getter, target) = getter_activation_test_fixture()
  dispatch_shell_test_install_realm_sentinel(interp, 43)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let thrown : Error = @errors.TypeError(message="getter failure")
  let observed : Result[Unit, SourceObservedFailure] = observe_source_failure(
    interp.realm_state,
    () => {
      let (cleanup, _) = getter_activation_test_enter(
        shell, plan, getter, target,
      )
      getter_activation_test_release(shell, cleanup, DispatchThrow(thrown))
      raise thrown
    },
  )
  match observed {
    Err(failure) => {
      inspect(physical_equal(failure.cause(), thrown), content="true")
      match failure.source_identity() {
        Some(source) => inspect(source, content="getter.js")
        None => fail("expected the getter source identity")
      }
    }
    Ok(_) => fail("expected the getter source failure")
  }
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 43)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected the caller source identity to be restored")
  }
}

///|
test "getter root owns and releases its registry and caller realm" {
  let interp = Interpreter::new()
  let stmts = @parser.parse(getter_activation_test_source()).stmts
  let plan = match classify_getter_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact getter-recursion plan")
  }
  let preflight = match interp.preflight_getter_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free getter preflight")
  }
  dispatch_shell_test_install_realm_sentinel(interp, 44)
  let ctx : ExecContext = { strict: false, current_generator: None }
  let result = activation_dispatch_root_value(
    interp.run_activation_dispatch_getter_program(stmts, ctx, preflight),
  )
  match result {
    Number(value) => inspect(value, content="256")
    _ => fail("expected the exact getter result")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 44)
}
