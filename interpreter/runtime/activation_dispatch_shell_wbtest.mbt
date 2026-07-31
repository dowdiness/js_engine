///|
fn dispatch_shell_test_program(source : String) -> Array[@ast.Stmt] raise {
  @parser.parse(source).stmts
}

///|
fn dispatch_shell_test_completion(
  interp : Interpreter,
  source : String,
) -> DispatchCompletion raise Error {
  let stmts = dispatch_shell_test_program(source)
  guard activation_dispatch_leaf_program_is_admissible(stmts) else {
    fail("expected an admissible leaf program")
  }
  let ctx : ExecContext = {
    strict: @static_semantics.has_use_strict(stmts),
    current_generator: None,
  }
  interp.run_activation_dispatch_leaf_program(stmts, ctx)
}

///|
fn dispatch_shell_test_structural_completion(
  interp : Interpreter,
  source : String,
) -> DispatchCompletion raise Error {
  let stmts = dispatch_shell_test_program(source)
  let ctx : ExecContext = {
    strict: @static_semantics.has_use_strict(stmts),
    current_generator: None,
  }
  PrimitiveProgramDispatchShell(interp).drive_root_program(stmts, ctx)
}

///|
fn dispatch_shell_test_install_realm_sentinel(
  interp : Interpreter,
  id : Int,
) -> Unit {
  apply_active_realm_protos(
    interp.realm_state,
    FunctionRealmProtos(
      object_proto=Some(String_("sentinel:" + id.to_string())),
    ),
  )
}

///|
fn dispatch_shell_test_expect_realm_sentinel(
  interp : Interpreter,
  id : Int,
) -> Unit raise {
  match active_realm_protos(interp.realm_state).object_proto {
    Some(String_(value)) => inspect(value, content="sentinel:" + id.to_string())
    _ => fail("expected the caller realm override to be restored")
  }
}

///|
fn dispatch_shell_test_expect_realm_cleared(interp : Interpreter) -> Unit raise {
  match active_realm_protos(interp.realm_state).object_proto {
    None => ()
    Some(_) => fail("expected the program realm override to remain cleared")
  }
}

///|
test "leaf program shell returns its last value and restores realm state" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 1)
  match dispatch_shell_test_completion(interp, "1; 2; 3") {
    DispatchNormal(Number(value)) => inspect(value, content="3")
    _ => fail("expected the final literal value")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 1)
  match dispatch_shell_test_completion(interp, "") {
    DispatchNormal(Undefined) => ()
    _ => fail("expected an empty program to complete with undefined")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 1)
}

///|
test "structural shell routes labelled break through its closed finalizer" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 15)
  match
    dispatch_shell_test_structural_completion(
      interp, "outer: try { break outer; } finally { 1; } 9;",
    ) {
    DispatchNormal(Number(value)) => inspect(value, content="9")
    _ => fail("expected the label to consume break after its finalizer")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 15)
}

///|
test "structural shell advances bounded continue after its closed finalizer" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 16)
  match
    dispatch_shell_test_structural_completion(
      interp, "do try { continue; } finally { 2; } while(false); 8;",
    ) {
    DispatchNormal(Number(value)) => inspect(value, content="8")
    _ => fail("expected the loop to consume continue after its finalizer")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 16)
}

///|
fn control_lifecycle_trace_effect(
  shell : PrimitiveProgramDispatchShell,
  effect : DispatchEffect,
) -> String raise {
  match effect {
    DispatchEnterActivation(DispatchProgramActivation(_)) => "enter"
    DispatchRunProduction(DispatchExecuteStatement(_)) =>
      match shell.control_phase {
        ControlAwaitRoot => "root"
        ControlAwaitProtected => "protected"
        ControlAwaitAbrupt => "abrupt"
        ControlAwaitFinalizer => "finalizer"
        ControlAwaitTerminal => "terminal"
        ControlAwaitLoopAdvance | ControlFinished =>
          fail("statement arrived outside an admitted control phase")
      }
    DispatchRunProduction(DispatchAdvanceLoop(_)) => "advance-loop"
    DispatchReleaseActivation(_, _) => "release"
    _ => fail("unexpected effect in exact control lifecycle trace")
  }
}

///|
fn trace_control_lifecycle_program(
  source : String,
) -> (DispatchCompletion, Array[String]) raise Error {
  let interp = Interpreter::new()
  let stmts = dispatch_shell_test_program(source)
  let preflight = match preflight_control_lifecycle_program(stmts) {
    Some(found) => found
    None => fail("expected an exact control lifecycle preflight")
  }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    control_root_preflight=Some(preflight),
  )
  let ctx : ExecContext = { strict: false, current_generator: None }
  let mut state = ActivationDispatchState::ActivationDispatchState()
  let mut event = DispatchStart(
    DispatchProgramActivation(
      DispatchStatementCursor(ctx~, stmts~, env=interp.global, production=true),
    ),
  )
  let trace : Array[String] = []
  for ;; {
    let (next_state, decision) = reduce_activation_dispatch(state, event)
    state = next_state
    match decision {
      DispatchFinish(completion) => return (completion, trace)
      DispatchPerform(ticket, effect) => {
        let tag = control_lifecycle_trace_effect(shell, effect)
        trace.push(tag)
        let result = shell.perform_effect(effect)
        if tag == "protected" {
          guard shell.control_try_env is Some(try_env) &&
            shell.control_finalizer_env is Some(finalizer_env) &&
            !physical_equal(try_env, finalizer_env) else {
            fail("try and finally must own distinct child environments")
          }
        }
        event = DispatchEffectCompleted(ticket, result)
      }
    }
  }
  fail("control lifecycle trace did not terminate")
}

///|
test "production control trace completes finalizer before label consumption" {
  let (completion, trace) = trace_control_lifecycle_program(
    "outer: try { break outer; } finally { 1; } 9;",
  )
  match completion {
    DispatchNormal(Number(value)) => inspect(value, content="9")
    _ => fail("expected normal labelled-break completion")
  }
  json_inspect(trace, content=[
    "enter", "root", "protected", "abrupt", "finalizer", "terminal", "release",
  ])
}

///|
test "production control trace completes finalizer before loop advance" {
  let (completion, trace) = trace_control_lifecycle_program(
    "do try { continue; } finally { 2; } while(false); 8;",
  )
  match completion {
    DispatchNormal(Number(value)) => inspect(value, content="8")
    _ => fail("expected normal bounded-continue completion")
  }
  json_inspect(trace, content=[
    "enter", "root", "protected", "abrupt", "finalizer", "advance-loop", "terminal",
    "release",
  ])
}

///|
fn expect_control_lifecycle_step_parity(
  source : String,
  steps : Int64,
  expected : Double,
) -> Unit raise {
  let exact_interp = Interpreter::new()
  let exact = ExecutionControl(
    remaining_steps=steps,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let exact_completion = exact_interp.with_execution_control(exact, () => {
    dispatch_shell_test_structural_completion(exact_interp, source)
  })
  match exact_completion {
    DispatchNormal(Number(value)) =>
      inspect(value, content=expected.to_string())
    _ => fail("exact control step budget must complete normally")
  }
  inspect(exact.remaining_steps(), content="0")
  let short_interp = Interpreter::new()
  let short = ExecutionControl(
    remaining_steps=steps - 1L,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let short_completion = short_interp.with_execution_control(short, () => {
    dispatch_shell_test_structural_completion(short_interp, source)
  })
  guard short_completion
    is DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)) else {
    fail("one-short control step budget must stop before completion")
  }
  inspect(short.remaining_steps(), content="0")
}

///|
test "structural shell preserves exact statement and condition step counts" {
  expect_control_lifecycle_step_parity(
    "outer: try { break outer; } finally { 1; } 9;", 7, 9.0,
  )
  expect_control_lifecycle_step_parity(
    "do try { continue; } finally { 2; } while(false); 8;", 8, 8.0,
  )
}

///|
fn install_one_shot_control_step_failure(
  interp : Interpreter,
  failure_ordinal : Int,
  runtime_failure : Error,
) -> Ref[Int] {
  let calls : Ref[Int] = { val: 0 }
  let observer = make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("[[one-shot-control-observer]]", fn(_) raise {
        calls.val = calls.val + 1
        if calls.val == failure_ordinal {
          raise runtime_failure
        }
        Undefined
      }),
    ),
    "Function",
    Map([]),
    true,
  )
  interp.global.bindings[EXECUTION_CONTROL_BINDING] = {
    value: observer,
    kind: VarBinding,
    initialized: true,
    annex_b_hoisted: false,
    is_parameter: false,
  }
  calls
}

///|
test "runtime abrupt at control statement observation still runs finally" {
  for
    source in [
      "outer: try { break outer; } finally { 1; } 9;", "do try { continue; } finally { 2; } while(false); 8;",
    ] {
    let interp = Interpreter::new()
    dispatch_shell_test_install_realm_sentinel(interp, 19)
    let runtime_failure : Error = ExecutionControlError(Interrupted)
    let calls = install_one_shot_control_step_failure(
      interp, 3, runtime_failure,
    )
    match dispatch_shell_test_structural_completion(interp, source) {
      DispatchRuntimeAbrupt(found) =>
        inspect(physical_equal(found, runtime_failure), content="true")
      _ => fail("expected the original one-shot runtime abrupt completion")
    }
    inspect(calls.val, content="5")
    dispatch_shell_test_expect_realm_sentinel(interp, 19)
  }
}

///|
test "control preflight rejects cross-plan and source drift before execution" {
  let admitted = dispatch_shell_test_program(
    "outer: try { break outer; } finally { 1; } 9;",
  )
  let preflight = match preflight_control_lifecycle_program(admitted) {
    Some(found) => found
    None => fail("expected labelled-break preflight")
  }
  for
    source in [
      "outer: try { break outer; } finally { 2; } 9;", "do try { continue; } finally { 2; } while(false); 8;",
    ] {
    let interp = Interpreter::new()
    dispatch_shell_test_install_realm_sentinel(interp, 17)
    let control = ExecutionControl(
      remaining_steps=1,
      maximum_active_depth=1,
      interruption=ExecutionInterruptionRequest(),
    )
    let outcome = interp.with_execution_control(control, () => {
      let stmts = dispatch_shell_test_program(source)
      let shell = PrimitiveProgramDispatchShell(
        interp,
        control_root_preflight=Some(preflight),
      )
      let ctx : ExecContext = { strict: false, current_generator: None }
      try {
        ignore(shell.drive_root_program(stmts, ctx))
        "accepted"
      } catch {
        InvalidActivationDispatchShell(_) => "rejected"
        _ => "wrong error"
      }
    })
    inspect(outcome, content="rejected")
    inspect(control.remaining_steps(), content="1")
    dispatch_shell_test_expect_realm_sentinel(interp, 17)
  }
}

///|
test "control shell rejects a direct invalid loop advance without evaluation" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 18)
  let stmts = dispatch_shell_test_program(
    "do try { continue; } finally { 2; } while(false); 8;",
  )
  let preflight = match preflight_control_lifecycle_program(stmts) {
    Some(found) => found
    None => fail("expected bounded-continue preflight")
  }
  guard stmts[0] is @ast.DoWhileStmt(body, _, _) else {
    fail("expected a do-while root")
  }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    control_root_preflight=Some(preflight),
  )
  let ctx : ExecContext = { strict: false, current_generator: None }
  let cleanup = match
    shell.perform_effect(
      DispatchEnterActivation(
        DispatchProgramActivation(
          DispatchStatementCursor(ctx~, stmts~, env=interp.global),
        ),
      ),
    ) {
    DispatchProgramAccepted(found) => found
    _ => fail("expected accepted control root ownership")
  }
  shell.control_phase = ControlAwaitLoopAdvance
  let control = ExecutionControl(
    remaining_steps=1,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let outcome = interp.with_execution_control(control, () => {
    try {
      ignore(
        shell.perform_effect(
          DispatchRunProduction(
            DispatchAdvanceLoop(
              DispatchLoopResume(
                kind=DispatchDoWhileLoop(
                  body,
                  @ast.BoolLit(true, @token.Loc::default()),
                  interp.global,
                ),
                ctx~,
                label=None,
                completion=Undefined,
              ),
            ),
          ),
        ),
      )
      "accepted"
    } catch {
      InvalidActivationDispatchShell(_) => "rejected"
    }
  })
  inspect(outcome, content="rejected")
  inspect(control.remaining_steps(), content="1")
  match
    shell.perform_effect(
      DispatchReleaseActivation(cleanup, DispatchNormal(Undefined)),
    ) {
    DispatchCleanupCompleted => ()
    _ => fail("expected control cleanup release")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 18)
}

///|
test "production shell rejects generic managed work" {
  let interp = Interpreter::new()
  let shell = PrimitiveProgramDispatchShell(interp)
  let binary = DispatchBinaryResume(
    op=@ast.Add,
    left=Number(1.0),
    loc=@token.Loc::default(),
  )
  let outcome = try {
    ignore(
      shell.perform_effect(
        DispatchRun(
          DispatchResumeContinuation(
            DispatchApplyBinaryRight(binary),
            Number(2.0),
          ),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(outcome, content="rejected")
}

///|
test "leaf program shell preserves a raw guest throw until root translation" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 2)
  match dispatch_shell_test_completion(interp, "throw 7") {
    DispatchThrow(JsException(Number(value))) => inspect(value, content="7")
    _ => fail("expected the original JsException completion")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 2)
  let public_value = try {
    let _ = interp.run(dispatch_shell_test_program("throw 7"))
    "no throw"
  } catch {
    JsException(Number(value)) => "throw:" + value.to_string()
    _ => "wrong error"
  }
  inspect(public_value, content="throw:7")
  dispatch_shell_test_expect_realm_sentinel(interp, 2)
}

///|
test "leaf program runtime abrupt completion releases realm cleanup" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 3)
  let control = ExecutionControl(
    remaining_steps=1,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let completion = interp.with_execution_control(control, () => {
    dispatch_shell_test_completion(interp, "7")
  })
  match completion {
    DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)) => ()
    _ => fail("expected a non-catchable execution-limit completion")
  }
  inspect(control.remaining_steps(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 3)
}

///|
test "leaf program entry rejection rolls back realm cleanup" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 4)
  match
    dispatch_shell_test_completion(interp, "\"use strict\"; 0777; throw 7") {
    DispatchThrow(@errors.SyntaxError(message~)) =>
      inspect(message.contains("Octal literals"), content="true")
    _ => fail("expected a catchable strict-mode entry rejection")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 4)
}

///|
test "leaf program admission rejects unsupported shapes before execution" {
  inspect(
    activation_dispatch_leaf_program_is_admissible(
      dispatch_shell_test_program(""),
    ),
    content="true",
  )
  inspect(
    activation_dispatch_leaf_program_is_admissible(
      dispatch_shell_test_program("1; throw null"),
    ),
    content="true",
  )
  for source in ["1 + 2", "(1)", "value", "var value = 1", "f()"] {
    inspect(
      activation_dispatch_leaf_program_is_admissible(
        dispatch_shell_test_program(source),
      ),
      content="false",
    )
  }
  let interp = Interpreter::new()
  match interp.run(dispatch_shell_test_program("1 + 2")) {
    Number(value) => inspect(value, content="3")
    _ => fail("legacy execution must remain available before admission")
  }
}

///|
test "leaf program cleanup capability is consumed exactly once" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 5)
  let stmts = dispatch_shell_test_program("1")
  let shell = PrimitiveProgramDispatchShell(interp)
  let entry = shell.perform_effect(
    DispatchEnterActivation(
      DispatchProgramActivation(
        DispatchStatementCursor(
          ctx={ strict: false, current_generator: None },
          stmts~,
          env=interp.global,
        ),
      ),
    ),
  )
  let cleanup = match entry {
    DispatchProgramAccepted(found) => found
    _ => fail("expected accepted program cleanup ownership")
  }
  dispatch_shell_test_expect_realm_cleared(interp)
  let wrong_owner = try {
    let _ = shell.perform_effect(
      DispatchRollbackRejectedEntry(
        DispatchRejectedEntryCleanup(cleanup.id),
        DispatchNormal(Number(1.0)),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(wrong_owner, content="rejected")
  dispatch_shell_test_expect_realm_cleared(interp)
  let release = DispatchReleaseActivation(cleanup, DispatchNormal(Number(1.0)))
  match shell.perform_effect(release) {
    DispatchCleanupCompleted => ()
    _ => fail("expected cleanup completion")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 5)
  let duplicate = try {
    let _ = shell.perform_effect(release)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(duplicate, content="rejected")
  dispatch_shell_test_expect_realm_sentinel(interp, 5)

  let second_entry = shell.perform_effect(
    DispatchEnterActivation(
      DispatchProgramActivation(
        DispatchStatementCursor(
          ctx={ strict: false, current_generator: None },
          stmts~,
          env=interp.global,
        ),
      ),
    ),
  )
  let second_cleanup = match second_entry {
    DispatchProgramAccepted(found) => found
    _ => fail("expected a second accepted program cleanup")
  }
  dispatch_shell_test_expect_realm_cleared(interp)
  let stale = try {
    let _ = shell.perform_effect(release)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(stale, content="rejected")
  dispatch_shell_test_expect_realm_cleared(interp)
  match
    shell.perform_effect(
      DispatchReleaseActivation(second_cleanup, DispatchNormal(Number(2.0))),
    ) {
    DispatchCleanupCompleted => ()
    _ => fail("expected the current cleanup capability to remain owned")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 5)
}

///|
test "rejected entry rollback capability cannot consume a later rejection" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 6)
  let stmts = dispatch_shell_test_program("0777")
  let shell = PrimitiveProgramDispatchShell(interp)
  let entry_effect = DispatchEnterActivation(
    DispatchProgramActivation(
      DispatchStatementCursor(
        ctx={ strict: true, current_generator: None },
        stmts~,
        env=interp.global,
      ),
    ),
  )
  let first_rejected = match shell.perform_effect(entry_effect) {
    DispatchActivationRejected(found, DispatchEntryGuestThrow(_)) => found
    _ => fail("expected a catchable rejected entry")
  }
  dispatch_shell_test_expect_realm_cleared(interp)
  let wrong_owner = try {
    let _ = shell.perform_effect(
      DispatchReleaseActivation(
        DispatchActivationCleanup(first_rejected.id),
        DispatchThrow(JsException(Undefined)),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(wrong_owner, content="rejected")
  dispatch_shell_test_expect_realm_cleared(interp)
  let rollback = DispatchRollbackRejectedEntry(
    first_rejected,
    DispatchThrow(JsException(Undefined)),
  )
  match shell.perform_effect(rollback) {
    DispatchCleanupCompleted => ()
    _ => fail("expected the first rejected entry to roll back")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 6)

  let second_rejected = match shell.perform_effect(entry_effect) {
    DispatchActivationRejected(found, DispatchEntryGuestThrow(_)) => found
    _ => fail("expected a second catchable rejected entry")
  }
  dispatch_shell_test_expect_realm_cleared(interp)
  let stale = try {
    let _ = shell.perform_effect(rollback)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(stale, content="rejected")
  dispatch_shell_test_expect_realm_cleared(interp)
  match
    shell.perform_effect(
      DispatchRollbackRejectedEntry(
        second_rejected,
        DispatchThrow(JsException(Undefined)),
      ),
    ) {
    DispatchCleanupCompleted => ()
    _ => fail("expected the current rollback capability to remain owned")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 6)
}

///|
fn dispatch_shell_test_expect_exhausted_entry_preserves_realm(
  source : String,
  strict : Bool,
  sentinel : Int,
) -> Unit raise {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, sentinel)
  let stmts = dispatch_shell_test_program(source)
  let shell = PrimitiveProgramDispatchShell(interp)
  shell.next_cleanup_id = MAX_DISPATCH_CLEANUP_ID
  let outcome = try {
    let _ = shell.perform_effect(
      DispatchEnterActivation(
        DispatchProgramActivation(
          DispatchStatementCursor(
            ctx={ strict, current_generator: None },
            stmts~,
            env=interp.global,
          ),
        ),
      ),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "exhausted"
  }
  inspect(outcome, content="exhausted")
  dispatch_shell_test_expect_realm_sentinel(interp, sentinel)
}

///|
test "cleanup generation exhaustion never installs program realm state" {
  dispatch_shell_test_expect_exhausted_entry_preserves_realm("1", false, 7)
  dispatch_shell_test_expect_exhausted_entry_preserves_realm("0777", true, 8)
}

///|
test "program cleanup capabilities enforce nested LIFO ownership" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 9)
  let stmts = dispatch_shell_test_program("1")
  let shell = PrimitiveProgramDispatchShell(interp)
  let entry_effect = DispatchEnterActivation(
    DispatchProgramActivation(
      DispatchStatementCursor(
        ctx={ strict: false, current_generator: None },
        stmts~,
        env=interp.global,
      ),
    ),
  )
  let outer = match shell.perform_effect(entry_effect) {
    DispatchProgramAccepted(found) => found
    _ => fail("expected outer cleanup ownership")
  }
  let inner = match shell.perform_effect(entry_effect) {
    DispatchProgramAccepted(found) => found
    _ => fail("expected inner cleanup ownership")
  }
  let out_of_order = try {
    let _ = shell.perform_effect(
      DispatchReleaseActivation(outer, DispatchNormal(Undefined)),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(out_of_order, content="rejected")
  dispatch_shell_test_expect_realm_cleared(interp)
  match
    shell.perform_effect(
      DispatchReleaseActivation(inner, DispatchNormal(Undefined)),
    ) {
    DispatchCleanupCompleted => ()
    _ => fail("expected inner cleanup to release first")
  }
  dispatch_shell_test_expect_realm_cleared(interp)
  match
    shell.perform_effect(
      DispatchReleaseActivation(outer, DispatchNormal(Undefined)),
    ) {
    DispatchCleanupCompleted => ()
    _ => fail("expected outer cleanup to release last")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 9)
}

///|
fn dispatch_shell_test_route_property_completion(
  completion : DispatchCompletion,
  sentinel : Int,
) -> DispatchCompletion raise {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, sentinel)
  let shell = PrimitiveProgramDispatchShell(interp)
  let cleanup = shell.begin_property_scope()
  dispatch_shell_test_expect_realm_cleared(interp)
  let (restoring, decision) = route_dispatch_completion(
    dispatch_test_ready_state(
      DispatchFrameStackNode(
        DispatchPropertyScopeFrame(cleanup),
        DispatchFrameStackEmpty,
      ),
    ),
    completion,
  )
  let (ticket, effect) = match decision {
    DispatchPerform(ticket, effect) =>
      match effect {
        DispatchRestorePropertyScope(found, routed) => {
          inspect(found.id, content=cleanup.id.to_string())
          inspect(
            dispatch_completion_tag(routed),
            content=dispatch_completion_tag(completion),
          )
          (ticket, effect)
        }
        _ => fail("expected property scope restoration before completion")
      }
    _ => fail("expected property scope restoration before completion")
  }
  let result = shell.perform_effect(effect)
  dispatch_shell_test_expect_realm_sentinel(interp, sentinel)
  let duplicate = try {
    let _ = shell.perform_effect(effect)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(duplicate, content="rejected")
  dispatch_shell_test_expect_realm_sentinel(interp, sentinel)
  let (_, finish_decision) = reduce_activation_dispatch(
    restoring,
    DispatchEffectCompleted(ticket, result),
  )
  match finish_decision {
    DispatchFinish(found) => found
    _ => fail("expected the exact completion after property restoration")
  }
}

///|
test "property scope shell restores every completion category once" {
  match
    dispatch_shell_test_route_property_completion(
      DispatchNormal(Number(7.0)),
      10,
    ) {
    DispatchNormal(Number(value)) => inspect(value, content="7")
    _ => fail("expected exact normal property completion")
  }
  let guest : Error = @errors.TypeError(message="property guest throw")
  match
    dispatch_shell_test_route_property_completion(DispatchThrow(guest), 11) {
    DispatchThrow(found) =>
      inspect(physical_equal(found, guest), content="true")
    _ => fail("expected exact guest property completion")
  }
  let abrupt : Error = @errors.InternalError(message="property runtime abrupt")
  match
    dispatch_shell_test_route_property_completion(
      DispatchRuntimeAbrupt(abrupt),
      12,
    ) {
    DispatchRuntimeAbrupt(found) =>
      inspect(physical_equal(found, abrupt), content="true")
    _ => fail("expected exact runtime property completion")
  }
}

///|
test "property scope shell shares activation LIFO ownership" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 13)
  let shell = PrimitiveProgramDispatchShell(interp)
  let stmts = dispatch_shell_test_program("1")
  let activation = match
    shell.perform_effect(
      DispatchEnterActivation(
        DispatchProgramActivation(
          DispatchStatementCursor(
            ctx={ strict: false, current_generator: None },
            stmts~,
            env=interp.global,
          ),
        ),
      ),
    ) {
    DispatchProgramAccepted(found) => found
    _ => fail("expected activation cleanup ownership")
  }
  dispatch_shell_test_install_realm_sentinel(interp, 14)
  let property = shell.begin_property_scope()
  dispatch_shell_test_expect_realm_cleared(interp)
  let out_of_order = try {
    let _ = shell.perform_effect(
      DispatchReleaseActivation(activation, DispatchNormal(Undefined)),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(out_of_order, content="rejected")
  dispatch_shell_test_expect_realm_cleared(interp)
  match
    shell.perform_effect(
      DispatchRestorePropertyScope(property, DispatchNormal(Undefined)),
    ) {
    DispatchCleanupCompleted => ()
    _ => fail("expected inner property scope to restore first")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 14)
  match
    shell.perform_effect(
      DispatchReleaseActivation(activation, DispatchNormal(Undefined)),
    ) {
    DispatchCleanupCompleted => ()
    _ => fail("expected outer activation to release last")
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 13)
}

///|
test "property cleanup generation exhaustion preserves realm state" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 15)
  let shell = PrimitiveProgramDispatchShell(interp)
  shell.next_cleanup_id = MAX_DISPATCH_CLEANUP_ID
  let outcome = try {
    let _ = shell.begin_property_scope()
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "exhausted"
  }
  inspect(outcome, content="exhausted")
  dispatch_shell_test_expect_realm_sentinel(interp, 15)
}

///|
fn dispatch_shell_test_ordinary_object(
  prototype : Value,
  descriptor : PropDescriptor?,
  property_value : Value?,
) -> Value {
  let bag = PropertyBag()
  match descriptor {
    Some(found) => bag.descriptors["x"] = found
    None => ()
  }
  match property_value {
    Some(found) => bag.properties["x"] = found
    None => ()
  }
  Object({
    bag,
    prototype,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
fn dispatch_shell_test_accessor_descriptor(getter : Value) -> PropDescriptor {
  {
    writable: false,
    enumerable: true,
    configurable: true,
    getter: Some(getter),
    setter: None,
    is_accessor: true,
  }
}

///|
fn dispatch_shell_test_data_descriptor() -> PropDescriptor {
  {
    writable: true,
    enumerable: true,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
fn dispatch_shell_test_start_property(
  shell : PrimitiveProgramDispatchShell,
  work : DispatchPropertyGetResume,
  consumer : DispatchContinuation,
) -> (DispatchPropertyCleanup, DispatchPropertyGetResume, DispatchContinuation) raise {
  match
    shell.perform_effect(
      DispatchRunProduction(DispatchPropertyStart(work, consumer)),
    ) {
    DispatchWorkSuspended(
      DispatchSuspendProperty(cleanup, found_work, found_consumer)
    ) => (cleanup, found_work, found_consumer)
    _ => fail("expected property work to acquire a cleanup scope")
  }
}

///|
fn dispatch_shell_test_restore_property(
  shell : PrimitiveProgramDispatchShell,
  cleanup : DispatchPropertyCleanup,
  completion : DispatchCompletion,
) -> Unit raise {
  match
    shell.perform_effect(DispatchRestorePropertyScope(cleanup, completion)) {
    DispatchCleanupCompleted => ()
    _ => fail("expected property cleanup to restore its realm scope")
  }
}

///|
test "ordinary own accessor work suspends without invoking its getter" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 16)
  let calls : Ref[Int] = { val: 0 }
  let getter = make_native_func(name="x getter", _args => {
    calls.val += 1
    Number(99.0)
  })
  let receiver = dispatch_shell_test_ordinary_object(
    Null,
    Some(dispatch_shell_test_accessor_descriptor(getter)),
    Some(Number(88.0)),
  )
  let work = DispatchPropertyGetResume(
    target=receiver,
    property_key=String_("x"),
    receiver~,
    loc=@token.Loc::default(),
  )
  let shell = PrimitiveProgramDispatchShell(interp)
  let (cleanup, scoped_work, consumer) = dispatch_shell_test_start_property(
    shell,
    work,
    DispatchDeliverCallResult,
  )
  dispatch_shell_test_expect_realm_cleared(interp)
  let accessor_consumer = match
    shell.perform_effect(
      DispatchRunProduction(DispatchPropertyExecute(scoped_work)),
    ) {
    DispatchWorkSuspended(DispatchSuspendCall(request, continuation)) => {
      inspect(physical_equal(request.callee, getter), content="true")
      inspect(physical_equal(request.this_value, receiver), content="true")
      inspect(request.args.length(), content="0")
      continuation
    }
    _ => fail("expected own accessor work to suspend at its getter call")
  }
  inspect(calls.val, content="0")
  let accessor_work = match accessor_consumer {
    DispatchDeliverAccessorResult(found) => found
    _ => fail("expected the accessor result continuation")
  }
  match
    shell.perform_effect(
      DispatchRunProduction(
        DispatchPropertyDeliverAccessorResult(accessor_work, Number(21.0)),
      ),
    ) {
    DispatchWorkCompleted(DispatchNormal(Number(value))) =>
      inspect(value, content="21")
    _ => fail("expected the accessor result to resume exactly once")
  }
  inspect(calls.val, content="0")
  match consumer {
    DispatchDeliverCallResult => ()
    _ => fail("expected the outer property consumer to remain unchanged")
  }
  dispatch_shell_test_restore_property(
    shell,
    cleanup,
    DispatchNormal(Number(21.0)),
  )
  dispatch_shell_test_expect_realm_sentinel(interp, 16)
}

///|
test "ordinary prototype accessor work preserves the original receiver" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 17)
  let getter = make_native_func(name="prototype x getter", _args => Undefined)
  let prototype = dispatch_shell_test_ordinary_object(
    Null,
    Some(dispatch_shell_test_accessor_descriptor(getter)),
    None,
  )
  let target = dispatch_shell_test_ordinary_object(prototype, None, None)
  let receiver = dispatch_shell_test_ordinary_object(Null, None, None)
  let work = DispatchPropertyGetResume(
    target~,
    property_key=String_("x"),
    receiver~,
    loc=@token.Loc::default(),
  )
  let shell = PrimitiveProgramDispatchShell(interp)
  let (cleanup, scoped_work, _) = dispatch_shell_test_start_property(
    shell,
    work,
    DispatchDeliverCallResult,
  )
  match
    shell.perform_effect(
      DispatchRunProduction(DispatchPropertyExecute(scoped_work)),
    ) {
    DispatchWorkSuspended(DispatchSuspendCall(request, _)) => {
      inspect(physical_equal(request.callee, getter), content="true")
      inspect(physical_equal(request.this_value, receiver), content="true")
    }
    _ => fail("expected prototype accessor work to suspend at its getter call")
  }
  dispatch_shell_test_restore_property(
    shell,
    cleanup,
    DispatchNormal(Undefined),
  )
  dispatch_shell_test_expect_realm_sentinel(interp, 17)
}

///|
test "ordinary getterless accessor shadows a conflicting data slot" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 18)
  let setter = make_native_func(name="x setter", _args => Undefined)
  let descriptor : PropDescriptor = {
    writable: false,
    enumerable: true,
    configurable: true,
    getter: None,
    setter: Some(setter),
    is_accessor: true,
  }
  let receiver = dispatch_shell_test_ordinary_object(
    Null,
    Some(descriptor),
    Some(Number(55.0)),
  )
  let work = DispatchPropertyGetResume(
    target=receiver,
    property_key=String_("x"),
    receiver~,
    loc=@token.Loc::default(),
  )
  let shell = PrimitiveProgramDispatchShell(interp)
  let (cleanup, scoped_work, _) = dispatch_shell_test_start_property(
    shell,
    work,
    DispatchDeliverCallResult,
  )
  match
    shell.perform_effect(
      DispatchRunProduction(DispatchPropertyExecute(scoped_work)),
    ) {
    DispatchWorkCompleted(DispatchNormal(Undefined)) => ()
    _ => fail("expected a getterless accessor to produce undefined")
  }
  dispatch_shell_test_restore_property(
    shell,
    cleanup,
    DispatchNormal(Undefined),
  )
  dispatch_shell_test_expect_realm_sentinel(interp, 18)
}

///|
test "ordinary data property work completes once through the reducer" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 19)
  let receiver = dispatch_shell_test_ordinary_object(
    Null,
    Some(dispatch_shell_test_data_descriptor()),
    Some(Number(34.0)),
  )
  let work = DispatchPropertyGetResume(
    target=receiver,
    property_key=String_("x"),
    receiver~,
    loc=@token.Loc::default(),
  )
  let shell = PrimitiveProgramDispatchShell(interp)
  let (starting, start_decision) = schedule_dispatch_effect(
    dispatch_test_ready_state(DispatchFrameStackEmpty),
    DispatchRunProduction(
      DispatchPropertyStart(work, DispatchDeliverCallResult),
    ),
  )
  let (start_ticket, start_effect) = match start_decision {
    DispatchPerform(ticket, effect) => (ticket, effect)
    _ => fail("expected the property start effect")
  }
  let start_result = shell.perform_effect(start_effect)
  dispatch_shell_test_expect_realm_cleared(interp)
  let (running, property_decision) = reduce_activation_dispatch(
    starting,
    DispatchEffectCompleted(start_ticket, start_result),
  )
  let (property_ticket, property_effect) = match property_decision {
    DispatchPerform(ticket, effect) =>
      match effect {
        DispatchRunProduction(DispatchPropertyExecute(_)) => (ticket, effect)
        _ => fail("expected scoped property execution")
      }
    _ => fail("expected scoped property execution")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      running,
      DispatchEffectCompleted(
        start_ticket,
        DispatchWorkCompleted(DispatchNormal(Undefined)),
      ),
    )
  })
  let property_result = shell.perform_effect(property_effect)
  let (restoring, restore_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(property_ticket, property_result),
  )
  let (restore_ticket, restore_effect) = match restore_decision {
    DispatchPerform(ticket, effect) =>
      match effect {
        DispatchRestorePropertyScope(_, DispatchNormal(Number(value))) => {
          inspect(value, content="34")
          (ticket, effect)
        }
        _ => fail("expected property cleanup after its exact value")
      }
    _ => fail("expected property cleanup after its exact value")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      restoring,
      DispatchEffectCompleted(
        property_ticket,
        DispatchWorkCompleted(DispatchNormal(Number(99.0))),
      ),
    )
  })
  let restore_result = shell.perform_effect(restore_effect)
  let (finished, finish_decision) = reduce_activation_dispatch(
    restoring,
    DispatchEffectCompleted(restore_ticket, restore_result),
  )
  match finish_decision {
    DispatchFinish(DispatchNormal(Number(value))) =>
      inspect(value, content="34")
    _ => fail("expected the exact data property result")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      finished,
      DispatchEffectCompleted(restore_ticket, DispatchCleanupCompleted),
    )
  })
  dispatch_shell_test_expect_realm_sentinel(interp, 19)
}
