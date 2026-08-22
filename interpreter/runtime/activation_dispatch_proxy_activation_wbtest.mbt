///|
test "exact Proxy get recursion runs through activation dispatch" {
  let interp = proxy_get_recursion_trust_test_interpreter()
  let stmts = @parser.parse(proxy_get_recursion_exact_source()).stmts
  match interp.preflight_dispatchable_proxy_get_recursion_program(stmts) {
    Some(_) => ()
    None => fail("expected exact Proxy get recursion to be dispatchable")
  }
  let result = interp.run(stmts)
  match result {
    Number(value) => inspect(value, content="256")
    _ => fail("expected the exact Proxy get recursion result")
  }
}

///|
fn proxy_activation_test_fixture() -> (
  Interpreter,
  PrimitiveProgramDispatchShell,
  TrustedProxyGetRecursionRegistry,
  ProxyGetRecursionPlan,
  TrustedProxyGetCapture,
  Value,
) raise {
  let interp = proxy_get_recursion_trust_test_interpreter()
  interp.realm_state.active_source_identity.val = Some("proxy.js")
  let (stmts, plan) = proxy_get_recursion_trust_test_plan()
  let registry = proxy_get_recursion_trust_test_registry(interp, stmts, plan)
  let proxy = registry.require_proxy(interp)
  let capture = registry.capture_get(
    interp,
    proxy,
    String_(plan.property_name),
    proxy,
  )
  let trap = proxy_get_recursion_trust_trap(capture)
  let shell = PrimitiveProgramDispatchShell(
    interp,
    proxy_registry=Some(registry),
  )
  (interp, shell, registry, plan, capture, trap)
}

///|
fn proxy_activation_test_enter(
  shell : PrimitiveProgramDispatchShell,
  plan : ProxyGetRecursionPlan,
  capture : TrustedProxyGetCapture,
  trap : Value,
) -> (DispatchActivationCleanup, DispatchStatementCursor) raise {
  let request = DispatchCallRequest(
    callee=trap,
    this_value=capture.handler,
    args=[capture.target, capture.property_key, capture.receiver],
    loc=plan.recipe.root_member_loc,
  )
  match
    shell.perform_effect(
      DispatchEnterActivation(DispatchCallActivation(request)),
    ) {
    DispatchCallAccepted(cleanup, DispatchCallBody(cursor)) => (cleanup, cursor)
    _ => fail("expected a trusted Proxy get trap activation")
  }
}

///|
fn proxy_activation_test_release(
  shell : PrimitiveProgramDispatchShell,
  cleanup : DispatchActivationCleanup,
  completion : DispatchCompletion,
) -> Unit raise {
  match shell.perform_effect(DispatchReleaseActivation(cleanup, completion)) {
    DispatchCleanupCompleted => ()
    _ => fail("expected Proxy get activation cleanup")
  }
}

///|
test "trusted Proxy get entry owns receiver arguments and dynamic state" {
  let (interp, shell, _, plan, capture, trap) = proxy_activation_test_fixture()
  dispatch_shell_test_install_realm_sentinel(interp, 51)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let saved_conflicts : @set.Set[String] = Default::default()
  saved_conflicts.add("caller")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(saved_conflicts)

  let (cleanup, cursor) = proxy_activation_test_enter(
    shell, plan, capture, trap,
  )
  inspect(shell.cleanup_stack.length(), content="1")
  inspect(cursor.index, content="0")
  inspect(cursor.stmts.length(), content="3")
  guard cursor.env.bindings.get("this") is Some(this_binding) else {
    fail("expected the Proxy handler receiver binding")
  }
  inspect(same_value(this_binding.value, capture.handler), content="true")
  for
    entry in [
      (plan.target_parameter, capture.target),
      (plan.key_parameter, capture.property_key),
      (plan.receiver_parameter, capture.receiver),
    ] {
    let (name, expected) = entry
    inspect(
      proxy_activation_parameter_matches(cursor.env, name, expected),
      content="true",
    )
  }
  inspect(interp.in_nonarrow_param_default_eval, content="false")
  inspect(interp.param_default_eval_var_conflicts is None, content="true")
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="proxy.js")
    None => fail("expected the Proxy trap source identity")
  }

  proxy_activation_test_release(shell, cleanup, DispatchReturn(Number(1.0)))
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 51)
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
test "Proxy get entry rejects mismatched envelopes before cleanup" {
  let (interp, shell, _, plan, capture, trap) = proxy_activation_test_fixture()
  dispatch_shell_test_install_realm_sentinel(interp, 52)
  let rejected_receiver = try {
    let _ = shell.perform_effect(
      DispatchEnterActivation(
        DispatchCallActivation(
          DispatchCallRequest(
            callee=trap,
            this_value=Undefined,
            args=[capture.target, capture.property_key, capture.receiver],
            loc=plan.recipe.root_member_loc,
          ),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  let rejected_callee = try {
    let _ = shell.perform_effect(
      DispatchEnterActivation(
        DispatchCallActivation(
          DispatchCallRequest(
            callee=capture.target,
            this_value=capture.handler,
            args=[capture.target, capture.property_key, capture.receiver],
            loc=plan.recipe.root_member_loc,
          ),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  let rejected_args = try {
    let _ = shell.perform_effect(
      DispatchEnterActivation(
        DispatchCallActivation(
          DispatchCallRequest(
            callee=trap,
            this_value=capture.handler,
            args=[capture.target, capture.property_key],
            loc=plan.recipe.root_member_loc,
          ),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  let registryless = PrimitiveProgramDispatchShell(interp)
  let rejected_registryless = try {
    let _ = registryless.perform_effect(
      DispatchEnterActivation(
        DispatchCallActivation(
          DispatchCallRequest(
            callee=trap,
            this_value=capture.handler,
            args=[capture.target, capture.property_key, capture.receiver],
            loc=plan.recipe.root_member_loc,
          ),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(rejected_receiver, content="rejected")
  inspect(rejected_callee, content="rejected")
  inspect(rejected_args, content="rejected")
  inspect(rejected_registryless, content="rejected")
  inspect(shell.cleanup_stack.length(), content="0")
  inspect(registryless.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 52)
}

///|
test "Proxy get abrupt cleanup attributes the trap and restores its caller" {
  let (interp, shell, _, plan, capture, trap) = proxy_activation_test_fixture()
  dispatch_shell_test_install_realm_sentinel(interp, 55)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let thrown : Error = @errors.TypeError(message="Proxy trap failure")
  let observed : Result[Unit, SourceObservedFailure] = observe_source_failure(
    interp.realm_state,
    () => {
      let (cleanup, _) = proxy_activation_test_enter(shell, plan, capture, trap)
      proxy_activation_test_release(shell, cleanup, DispatchThrow(thrown))
      raise thrown
    },
  )
  match observed {
    Err(failure) => {
      inspect(physical_equal(failure.cause(), thrown), content="true")
      match failure.source_identity() {
        Some(source) => inspect(source, content="proxy.js")
        None => fail("expected the Proxy trap source identity")
      }
    }
    Ok(_) => fail("expected the Proxy trap source failure")
  }
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 55)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected the caller source identity to be restored")
  }
}

///|
test "Proxy property shell preserves captured work across trap continuations" {
  let (interp, shell, _, plan, capture, trap) = proxy_activation_test_fixture()
  dispatch_shell_test_install_realm_sentinel(interp, 53)
  let outer_work = DispatchPropertyGetResume(
    target=capture.proxy,
    property_key=capture.property_key,
    receiver=capture.receiver,
    loc=plan.recipe.root_member_loc,
  )
  let (outer_cleanup, scoped_outer, outer_consumer) = dispatch_shell_test_start_property(
    shell,
    outer_work,
    DispatchDeliverCallResult,
  )
  let (inner_cleanup, handler_work, resolver) = match
    shell.perform_effect(
      DispatchRunProduction(DispatchPropertyExecute(scoped_outer)),
    ) {
    DispatchWorkSuspended(DispatchSuspendProperty(cleanup, work, continuation)) =>
      (cleanup, work, continuation)
    _ => fail("expected nested handler get-trap lookup")
  }
  let lookup = match resolver {
    DispatchResolveProxyGetTrap(found) => found
    _ => fail("expected the Proxy trap resolver")
  }
  inspect(same_value(lookup.proxy, capture.proxy), content="true")
  inspect(same_value(lookup.handler, capture.handler), content="true")
  inspect(same_value(lookup.post_trap.target, capture.target), content="true")
  let candidate = match
    shell.perform_effect(
      DispatchRunProduction(DispatchPropertyExecute(handler_work)),
    ) {
    DispatchWorkCompleted(DispatchNormal(found)) => found
    _ => fail("expected the exact handler data property")
  }
  inspect(same_value(candidate, trap), content="true")
  dispatch_shell_test_restore_property(
    shell,
    inner_cleanup,
    DispatchNormal(candidate),
  )
  dispatch_shell_test_expect_realm_cleared(interp)

  let (request, result_consumer) = match
    shell.perform_effect(
      DispatchRunProduction(
        DispatchPropertyResolveProxyGetTrap(lookup, candidate),
      ),
    ) {
    DispatchWorkSuspended(DispatchSuspendCall(found, continuation)) =>
      (found, continuation)
    _ => fail("expected the resolved Proxy trap call")
  }
  inspect(same_value(request.callee, trap), content="true")
  inspect(same_value(request.this_value, capture.handler), content="true")
  inspect(request.args.length(), content="3")
  inspect(same_value(request.args[0], capture.target), content="true")
  inspect(same_value(request.args[1], capture.property_key), content="true")
  inspect(same_value(request.args[2], capture.receiver), content="true")
  let call_cleanup = match
    shell.perform_effect(
      DispatchEnterActivation(DispatchCallActivation(request)),
    ) {
    DispatchCallAccepted(cleanup, DispatchCallBody(_)) => cleanup
    _ => fail("expected the exact Proxy trap activation")
  }
  proxy_activation_test_release(
    shell,
    call_cleanup,
    DispatchReturn(Number(9.0)),
  )
  dispatch_shell_test_expect_realm_cleared(interp)
  let result_work = match result_consumer {
    DispatchCheckProxyGetResult(found) => found
    _ => fail("expected the Proxy result continuation")
  }
  match
    shell.perform_effect(
      DispatchRunProduction(
        DispatchPropertyCheckProxyGetResult(result_work, Number(9.0)),
      ),
    ) {
    DispatchWorkCompleted(DispatchNormal(Number(value))) =>
      inspect(value, content="9")
    _ => fail("expected the post-trap result")
  }
  match outer_consumer {
    DispatchDeliverCallResult => ()
    _ => fail("expected the outer property consumer to remain unchanged")
  }
  dispatch_shell_test_restore_property(
    shell,
    outer_cleanup,
    DispatchNormal(Number(9.0)),
  )
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 53)
}

///|
test "Proxy root owns and releases its registry and caller realm" {
  let interp = proxy_get_recursion_trust_test_interpreter()
  let (stmts, plan) = proxy_get_recursion_trust_test_plan()
  let preflight = match interp.preflight_proxy_get_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free Proxy get preflight")
  }
  dispatch_shell_test_install_realm_sentinel(interp, 54)
  let ctx : ExecContext = { strict: false, current_generator: None }
  let result = activation_dispatch_root_value(
    interp.run_activation_dispatch_proxy_program(stmts, ctx, preflight),
  )
  match result {
    Number(value) => inspect(value, content="256")
    _ => fail("expected the exact Proxy get result")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 54)
}
