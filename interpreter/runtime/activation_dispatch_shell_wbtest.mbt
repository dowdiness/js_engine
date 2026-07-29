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
