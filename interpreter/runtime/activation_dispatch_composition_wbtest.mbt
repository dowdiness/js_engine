///|
const NUMERIC_MAP_COMPOSITION_OBSERVATION_SOURCE =
  #|function step(n){if(n===0)return 0;return 1+step(n-1);}
  #|function f(t){if(t===0)return 0;return u(t);}
  #|function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}
  #|step(256)+u(256);

///|
fn numeric_map_composition_observation_fixture() -> (
  Interpreter,
  Array[@ast.Stmt],
  NumericMapCompositionPreflight,
) raise Error {
  // Reuse the map observation fixture's canonical Array/map realm setup; the
  // composition preflight adds the sealed numeric half to that same realm.
  let (interp, _, _) = map_observation_test_fixture_for_source(
    MAP_FORWARDING_OBSERVATION_SOURCE,
  )
  let stmts = @parser.parse(NUMERIC_MAP_COMPOSITION_OBSERVATION_SOURCE).stmts
  let preflight = match
    interp.preflight_dispatchable_numeric_map_composition_program(stmts) {
    Some(found) => found
    None => fail("expected the numeric/map composition fixture to preflight")
  }
  (interp, stmts, preflight)
}

///|
test "composition call plan seals source calls and adapter tokens" {
  let (interp, stmts, preflight) = numeric_map_composition_observation_fixture()
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let ctx : ExecContext = { strict: false, current_generator: None }
  for index in 0..<3 {
    let _ = interp.exec_stmt(ctx, stmts[index], interp.global)
  }
  let catalog = interp.seal_numeric_map_composition_catalog(preflight, stmts)
  let call_resume = match
    numeric_map_composition_call_plan(preflight, catalog) {
    Some(plan) => plan
    None => fail("sealed composition catalog must produce one call plan")
  }
  inspect(
    array_map_value_identity_matches(
      catalog.numeric.entry.callee,
      call_resume.left_request.callee,
    ),
    content="true",
  )
  inspect(
    array_map_value_identity_matches(
      catalog.array_map.step_function,
      call_resume.right_request.callee,
    ),
    content="true",
  )
  inspect(call_resume.left_request.this_value, content="undefined")
  inspect(call_resume.right_request.this_value, content="undefined")
  inspect(call_resume.left_request.args.length(), content="1")
  inspect(call_resume.right_request.args.length(), content="1")
  inspect(call_resume.left_request.args[0], content="256")
  inspect(call_resume.right_request.args[0], content="256")
  inspect(
    call_resume.left_request.loc == preflight.left_call_loc,
    content="true",
  )
  inspect(
    call_resume.right_request.loc == preflight.right_call_loc,
    content="true",
  )
  inspect(call_resume.loc == preflight.binary_loc, content="true")
  match call_resume.op {
    @ast.Add => ()
    _ => fail("composition call plan must preserve the source Add operator")
  }
  match call_resume.left_adapter {
    DispatchNumericUserFuncAdapterToken(callee) =>
      inspect(
        array_map_value_identity_matches(
          callee,
          call_resume.left_request.callee,
        ),
        content="true",
      )
    _ => fail("left request must carry the numeric adapter token")
  }
  match call_resume.right_adapter {
    DispatchArrayMapUserFuncAdapterToken(callee) =>
      inspect(
        array_map_value_identity_matches(
          callee,
          call_resume.right_request.callee,
        ),
        content="true",
      )
    _ => fail("right request must carry the Array.map adapter token")
  }
}

///|
test "composition observations release numeric and map ownership in LIFO order" {
  let (interp, stmts, preflight) = numeric_map_composition_observation_fixture()
  dispatch_shell_test_install_realm_sentinel(interp, 801)
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let shell = PrimitiveProgramDispatchShell(
    interp,
    composition_root_preflight=Some(preflight),
    composition_root_stmts=Some(stmts),
    activation_observation_port=probe.port(),
  )
  let completion = shell.drive_root_program(stmts, {
    strict: false,
    current_generator: None,
  }) catch {
    InvalidActivationDispatchShell(message) =>
      fail("composition observation run rejected: " + message)
    error => fail("composition observation run failed: " + error.to_string())
  }
  match completion {
    DispatchNormal(Number(value)) => inspect(value, content="512")
    _ => fail("expected the exact composition fixture to complete normally")
  }
  // The root cleanup is intentionally unobserved; the 1537 accepted calls are
  // 257 numeric calls (256..0) plus 1280 forwarding-map calls.
  inspect(probe.accepted, content="1537")
  inspect(probe.released, content="1537")
  inspect(probe.rejected, content="0")
  inspect(probe.denied, content="0")
  inspect(probe.active, content="0")
  inspect(probe.lifo_violations, content="0")
  inspect(probe.release_ordinals.length(), content="1537")
  for restored in probe.release_state_restored {
    inspect(restored, content="true")
  }
  inspect(shell.cleanup_stack.length(), content="0")
  inspect(shell.numeric_registry is None, content="true")
  inspect(shell.array_map_registry is None, content="true")
  inspect(shell.managed_user_func_catalog is None, content="true")
  inspect(shell.array_map_states.is_empty(), content="true")
  inspect(shell.array_map_activation_envs.is_empty(), content="true")
  dispatch_shell_test_expect_realm_sentinel(interp, 801)
}

///|
test "composition catalog rejects post-seal numeric body drift before observation" {
  let (interp, stmts, preflight) = numeric_map_composition_observation_fixture()
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let ctx : ExecContext = { strict: false, current_generator: None }
  for index in 0..<3 {
    let _ = interp.exec_stmt(ctx, stmts[index], interp.global)
  }
  let catalog = interp.seal_numeric_map_composition_catalog(preflight, stmts)
  let probe = DispatchObservationProbe()
  let shell = PrimitiveProgramDispatchShell(
    interp,
    composition_root_preflight=Some(preflight),
    composition_root_stmts=Some(stmts),
    numeric_registry=Some(catalog.numeric),
    array_map_registry=Some(catalog.array_map),
    managed_user_func_catalog=Some(catalog),
    activation_observation_port=probe.port(),
  )
  guard catalog.numeric.entry.callee
    is Object({ callable: Some(UserFunc(data)), .. }) else {
    fail(
      "expected the sealed composition numeric entry to retain UserFunc data",
    )
  }
  let original_body = data.body[1]
  data.body[1] = @parser.parse("return 99;").stmts[0]
  let request = DispatchCallRequest(
    callee=catalog.numeric.entry.callee,
    this_value=Undefined,
    args=[Number(256.0)],
    loc=preflight.left_call_loc,
  )
  let result = try {
    let _ = shell.enter_managed_call(request)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  data.body[1] = original_body
  inspect(
    result,
    content="numeric recursion candidate no longer has exact UserFunc provenance",
  )
  inspect(probe.attempts, content="0")
  inspect(shell.cleanup_stack.length(), content="0")
  inspect(shell.array_map_states.is_empty(), content="true")
  inspect(shell.array_map_activation_envs.is_empty(), content="true")
  inspect(shell.numeric_registry is Some(_), content="true")
  inspect(shell.array_map_registry is Some(_), content="true")
  inspect(shell.managed_user_func_catalog is Some(_), content="true")
}

///|
fn composition_test_resume(
  left_callee : Value,
  right_callee : Value,
  left_value : Value?,
) -> DispatchBinaryRightCallResume {
  let loc = @token.Loc::default()
  let left_request = DispatchCallRequest(
    callee=left_callee,
    this_value=String_("left-this"),
    args=[Number(256.0)],
    loc~,
  )
  let right_request = DispatchCallRequest(
    callee=right_callee,
    this_value=String_("right-this"),
    args=[Number(256.0)],
    loc~,
  )
  DispatchBinaryRightCallResume(
    left_request~,
    right_request~,
    left_value~,
    op=@ast.Add,
    loc~,
    left_adapter=DispatchNumericUserFuncAdapterToken(left_callee),
    right_adapter=DispatchArrayMapUserFuncAdapterToken(right_callee),
  )
}

///|
fn composition_test_state(
  binary_call : DispatchBinaryRightCallResume,
) -> ActivationDispatchState {
  dispatch_test_ready_state(
    DispatchFrameStackNode(
      DispatchContinuationFrame(DispatchComposeBinaryRight(binary_call)),
      DispatchFrameStackEmpty,
    ),
  )
}

///|
test "composition reducer schedules one right call then applies binary once" {
  let left_callee = make_array([])
  let right_callee = make_array([])
  let initial = composition_test_state(
    composition_test_resume(left_callee, right_callee, None),
  )
  let (waiting_right, right_decision) = route_dispatch_completion(
    initial,
    DispatchNormal(Number(3.0)),
  )
  let right_ticket = match right_decision {
    DispatchPerform(
      ticket,
      DispatchEnterActivation(DispatchCallActivation(request))
    ) => {
      inspect(
        array_map_value_identity_matches(request.callee, right_callee),
        content="true",
      )
      inspect(request.this_value, content="right-this")
      inspect(request.args.length(), content="1")
      inspect(request.args[0], content="256")
      ticket
    }
    _ => fail("left normal completion must schedule exactly one right call")
  }
  let (waiting_binary, binary_decision) = route_dispatch_completion(
    composition_test_state(
      composition_test_resume(left_callee, right_callee, Some(Number(3.0))),
    ),
    DispatchNormal(Number(2.0)),
  )
  let binary_ticket = match binary_decision {
    DispatchPerform(
      ticket,
      DispatchRunProduction(DispatchNumericApplyBinaryRight(binary, right))
    ) => {
      inspect(binary.left, content="3")
      inspect(right, content="2")
      ticket
    }
    _ => fail("right normal completion must apply the binary once")
  }
  ignore(waiting_right)
  let (finished, finish_decision) = reduce_activation_dispatch(
    waiting_binary,
    DispatchEffectCompleted(
      binary_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(5.0))),
    ),
  )
  match finish_decision {
    DispatchFinish(DispatchNormal(Number(value))) => inspect(value, content="5")
    _ => fail("binary production completion must finish the composition")
  }
  ignore(finished)
  ignore(right_ticket)
}

///|
test "composition reducer skips right and binary on guest throw or runtime abrupt" {
  let left_callee = make_array([])
  let right_callee = make_array([])
  let guest_marker = make_array([])
  let guest_throw = DispatchThrow(JsException(guest_marker))
  let runtime_error : Error = ExecutionControlError(ExecutionLimit)
  let runtime_abrupt = DispatchRuntimeAbrupt(runtime_error)
  let left_throw = composition_test_state(
    composition_test_resume(left_callee, right_callee, None),
  )
  let (_, left_throw_decision) = route_dispatch_completion(
    left_throw, guest_throw,
  )
  match left_throw_decision {
    DispatchFinish(DispatchThrow(JsException(found))) =>
      inspect(
        array_map_value_identity_matches(found, guest_marker),
        content="true",
      )
    _ => fail("left guest throw must skip the right call")
  }
  let right_throw = composition_test_state(
    composition_test_resume(left_callee, right_callee, Some(Number(1.0))),
  )
  let (_, right_throw_decision) = route_dispatch_completion(
    right_throw, guest_throw,
  )
  match right_throw_decision {
    DispatchFinish(DispatchThrow(JsException(found))) =>
      inspect(
        array_map_value_identity_matches(found, guest_marker),
        content="true",
      )
    _ => fail("right guest throw must skip binary application")
  }
  let left_runtime = composition_test_state(
    composition_test_resume(left_callee, right_callee, None),
  )
  let (_, left_runtime_decision) = route_dispatch_completion(
    left_runtime, runtime_abrupt,
  )
  match left_runtime_decision {
    DispatchFinish(DispatchRuntimeAbrupt(found)) =>
      inspect(physical_equal(found, runtime_error), content="true")
    _ => fail("left runtime abrupt must skip the right call")
  }
  let right_runtime = composition_test_state(
    composition_test_resume(left_callee, right_callee, Some(Number(1.0))),
  )
  let (_, right_runtime_decision) = route_dispatch_completion(
    right_runtime, runtime_abrupt,
  )
  match right_runtime_decision {
    DispatchFinish(DispatchRuntimeAbrupt(found)) =>
      inspect(physical_equal(found, runtime_error), content="true")
    _ => fail("right runtime abrupt must skip binary application")
  }
}

///|
test "composition reducer releases left and right children before binary" {
  let left_callee = make_array([])
  let right_callee = make_array([])
  let left_request = DispatchCallRequest(
    callee=left_callee,
    this_value=Undefined,
    args=[Number(256.0)],
    loc=@token.Loc::default(),
  )
  let continuation = DispatchComposeBinaryRight(
    composition_test_resume(left_callee, right_callee, None),
  )
  let (running_root, root_ticket) = start_accepted_dispatch_root(2200)
  let (waiting_left, left_entry_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(DispatchSuspendCall(left_request, continuation)),
    ),
  )
  let left_entry_ticket = match left_entry_decision {
    DispatchPerform(ticket, DispatchEnterActivation(DispatchCallActivation(_))) =>
      ticket
    _ => fail("expected left child activation entry")
  }
  let left_cleanup = DispatchActivationCleanup(2211)
  let (running_left, left_run_decision) = reduce_activation_dispatch(
    waiting_left,
    DispatchEffectCompleted(
      left_entry_ticket,
      DispatchCallAccepted(
        left_cleanup,
        DispatchCallBody(dispatch_test_statement_work(2212)),
      ),
    ),
  )
  let left_run_ticket = match left_run_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected left child work")
  }
  let (releasing_left, left_release_decision) = reduce_activation_dispatch(
    running_left,
    DispatchEffectCompleted(
      left_run_ticket,
      DispatchWorkCompleted(DispatchReturn(Number(3.0))),
    ),
  )
  let left_release_ticket = match left_release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(found, DispatchNormal(Number(value)))
    ) => {
      inspect(found.id, content="2211")
      inspect(value, content="3")
      ticket
    }
    _ => fail("expected left child release")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      releasing_left,
      DispatchEffectCompleted(left_run_ticket, DispatchCleanupCompleted),
    )
  })
  let (waiting_right, right_entry_decision) = reduce_activation_dispatch(
    releasing_left,
    DispatchEffectCompleted(left_release_ticket, DispatchCleanupCompleted),
  )
  let right_entry_ticket = match right_entry_decision {
    DispatchPerform(
      ticket,
      DispatchEnterActivation(DispatchCallActivation(request))
    ) => {
      inspect(
        array_map_value_identity_matches(request.callee, right_callee),
        content="true",
      )
      ticket
    }
    _ => fail("expected right child entry after left release")
  }
  let right_cleanup = DispatchActivationCleanup(2221)
  let (running_right, right_run_decision) = reduce_activation_dispatch(
    waiting_right,
    DispatchEffectCompleted(
      right_entry_ticket,
      DispatchCallAccepted(
        right_cleanup,
        DispatchCallBody(dispatch_test_statement_work(2222)),
      ),
    ),
  )
  let right_run_ticket = match right_run_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected right child work")
  }
  let (releasing_right, right_release_decision) = reduce_activation_dispatch(
    running_right,
    DispatchEffectCompleted(
      right_run_ticket,
      DispatchWorkCompleted(DispatchReturn(Number(2.0))),
    ),
  )
  let right_release_ticket = match right_release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(found, DispatchNormal(Number(value)))
    ) => {
      inspect(found.id, content="2221")
      inspect(value, content="2")
      ticket
    }
    _ => fail("expected right child release")
  }
  let (running_binary, binary_decision) = reduce_activation_dispatch(
    releasing_right,
    DispatchEffectCompleted(right_release_ticket, DispatchCleanupCompleted),
  )
  let binary_ticket = match binary_decision {
    DispatchPerform(
      ticket,
      DispatchRunProduction(
        DispatchNumericApplyBinaryRight(binary, Number(right))
      )
    ) => {
      inspect(binary.left, content="3")
      inspect(right, content="2")
      ticket
    }
    _ => fail("expected binary only after right release")
  }
  let (releasing_root, root_release_decision) = reduce_activation_dispatch(
    running_binary,
    DispatchEffectCompleted(
      binary_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(5.0))),
    ),
  )
  let root_release_ticket = match root_release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(found, DispatchNormal(Number(value)))
    ) => {
      inspect(found.id, content="2201")
      inspect(value, content="5")
      ticket
    }
    _ => fail("expected root release after binary")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing_root,
    DispatchEffectCompleted(root_release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(DispatchNormal(Number(value))) => inspect(value, content="5")
    _ => fail("expected one final composition result")
  }
}

///|
test "managed UserFunc catalog selects exact, zero, and ambiguous identities" {
  let (_, _, numeric_registry, _) = numeric_activation_test_fixture(
    "function step(n){if(n===0)return 0;return 1+step(n-1);}step(256);",
  )
  let (map_interp, map_stmts, map_preflight) = map_observation_test_fixture_for_source(
    MAP_FORWARDING_OBSERVATION_SOURCE,
  )
  map_interp.prepare_root_program_execution(map_stmts, map_interp.global, false)
  let map_registry = map_interp.seal_array_map_recursion_registry(
    map_preflight, map_stmts,
  )
  let catalog = DispatchManagedUserFuncCatalog(
    numeric=numeric_registry,
    array_map=map_registry,
  )
  let numeric_callee = numeric_registry.entry.callee
  let map_callee = map_registry.step_function
  match catalog.select(numeric_callee, None, Undefined) {
    Some(DispatchNumericUserFuncAdapterToken(found)) =>
      inspect(
        array_map_value_identity_matches(found, numeric_callee),
        content="true",
      )
    _ => fail("catalog must select the sealed numeric adapter")
  }
  match catalog.select(map_callee, None, Undefined) {
    Some(DispatchArrayMapUserFuncAdapterToken(found)) =>
      inspect(
        array_map_value_identity_matches(found, map_callee),
        content="true",
      )
    _ => fail("catalog must select the sealed Array.map adapter")
  }
  inspect(
    catalog.select(make_array([]), None, Undefined) is None,
    content="true",
  )
  let ambiguous_map = { ..map_registry, step_function: numeric_callee }
  let ambiguous_catalog = DispatchManagedUserFuncCatalog(
    numeric=numeric_registry,
    array_map=ambiguous_map,
  )
  inspect(
    ambiguous_catalog.select(numeric_callee, None, Undefined) is None,
    content="true",
  )
}
