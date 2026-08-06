///|
fn expect_dispatch_number(
  completion : DispatchCompletion,
  expected : Double,
) -> Unit raise {
  match completion {
    DispatchNormal(Number(actual)) if actual == expected => ()
    _ => fail("expected normal numeric dispatch completion")
  }
}

///|
fn dispatch_test_statement_work(id : Int) -> DispatchStatementCursor {
  let loc = @token.Loc::default()
  let ctx : ExecContext = { strict: false, current_generator: None }
  DispatchStatementCursor(
    ctx~,
    stmts=[@ast.BreakStmt(Some(id.to_string()), loc)],
    env=Environment::new(),
  )
}

///|
fn dispatch_test_work_label(work : DispatchStatementCursor) -> String raise {
  match work.stmts {
    [@ast.BreakStmt(Some(label), _)] => label
    _ => fail("expected labelled test statement work")
  }
}

///|
fn dispatch_test_step_label(step : DispatchStatementStep) -> String raise {
  match step.stmt {
    @ast.BreakStmt(Some(label), _) => label
    _ => fail("expected labelled test statement step")
  }
}

///|
fn dispatch_test_statement_step(id : Int) -> DispatchStatementStep {
  let cursor = dispatch_test_statement_work(id)
  { ctx: cursor.ctx, stmt: cursor.stmts[0], env: cursor.env, index: 0 }
}

///|
fn dispatch_test_statement_resume(
  id : Int,
  last_value? : Value = Undefined,
  updates_last_value? : Bool = true,
) -> DispatchStatementResume {
  DispatchStatementResume(
    cursor=DispatchStatementCursor(
      ctx={ strict: false, current_generator: None },
      stmts=[@ast.BreakStmt(Some(id.to_string()), @token.Loc::default())],
      env=Environment::new(),
      index=1,
      last_value~,
    ),
    updates_last_value~,
  )
}

///|
fn dispatch_test_program_request(id : Int) -> DispatchActivationRequest {
  DispatchProgramActivation(dispatch_test_statement_work(id))
}

///|
fn dispatch_test_call_work(id : Int) -> DispatchCallRequest {
  DispatchCallRequest(
    callee=String_("callee:" + id.to_string()),
    this_value=Undefined,
    args=[],
    loc=@token.Loc::default(),
  )
}

///|
fn dispatch_test_call_request(id : Int) -> DispatchActivationRequest {
  DispatchCallActivation(dispatch_test_call_work(id))
}

///|
fn dispatch_test_request_tag(
  request : DispatchActivationRequest,
) -> String raise {
  match request {
    DispatchProgramActivation(work) =>
      "program:" + dispatch_test_work_label(work)
    DispatchCallActivation({ callee: String_(tag), .. }) => "call:" + tag
    _ => fail("expected test activation request")
  }
}

///|
fn dispatch_test_property_resume(id : Int) -> DispatchPropertyGetResume {
  DispatchPropertyGetResume(
    target=String_("target:" + id.to_string()),
    property_key=String_("key:" + id.to_string()),
    receiver=String_("receiver:" + id.to_string()),
    loc=@token.Loc::default(),
  )
}

///|
fn dispatch_test_proxy_resume(id : Int) -> DispatchProxyGetResume {
  DispatchProxyGetResume(
    target=String_("target:" + id.to_string()),
    property_key=String_("key:" + id.to_string()),
    receiver=String_("receiver:" + id.to_string()),
    loc=@token.Loc::default(),
  )
}

///|
fn dispatch_test_proxy_trap_lookup_resume(
  id : Int,
) -> DispatchProxyGetTrapLookupResume {
  DispatchProxyGetTrapLookupResume(
    proxy=String_("proxy:" + id.to_string()),
    handler=String_("handler:" + id.to_string()),
    post_trap=dispatch_test_proxy_resume(id),
  )
}

///|
fn dispatch_test_property_key(value : Value) -> String raise {
  match value {
    String_(key) => key
    _ => fail("expected string test property key")
  }
}

///|
fn dispatch_test_catch_resume(id : Int) -> DispatchCatchResume {
  DispatchCatchResume(
    parameter=Some(@ast.Pattern::IdentPat("caught:" + id.to_string())),
    body=dispatch_test_statement_work(id),
  )
}

///|
fn dispatch_test_parameter_progress(
  id : Int,
  next_index : Int,
) -> DispatchParameterDefaultResume {
  let loc = @token.Loc::default()
  DispatchParameterDefaultResume(
    params=[
      {
        name: "value",
        default_val: Some(@ast.Expr::UndefinedLit(loc)),
        pattern: None,
        is_rest_pattern: false,
      },
      { name: "next", default_val: None, pattern: None, is_rest_pattern: false },
    ],
    next_index~,
    effective_param_count=1,
    args=[Undefined, Number(9.0)],
    rest_param=Some("rest"),
    is_arrow=false,
    env=Environment::new(),
    ctx={ strict: true, current_generator: None },
    body=dispatch_test_statement_work(id).stmts,
  )
}

///|
fn dispatch_test_loop_resume(id : Int, label : String?) -> DispatchLoopResume {
  let loc = @token.Loc::default()
  let env = Environment::new()
  DispatchLoopResume(
    kind=DispatchWhileLoop(
      @ast.Expr::BoolLit(true, loc),
      @ast.BreakStmt(None, loc),
      env,
    ),
    ctx={ strict: false, current_generator: None },
    label~,
    completion=Number(id.to_double()),
  )
}

///|
fn dispatch_test_ready_state(
  frames : DispatchFrameStack,
) -> ActivationDispatchState {
  { frames, phase: DispatchReady, ticket_cursor: DispatchTicket(value="0") }
}

///|
test "activation dispatch enters and releases one accepted root" {
  let initial = ActivationDispatchState::ActivationDispatchState()
  let request = dispatch_test_program_request(1)
  let (waiting_entry, enter_decision) = reduce_activation_dispatch(
    initial,
    DispatchStart(request),
  )
  let entry_ticket = match enter_decision {
    DispatchPerform(ticket, DispatchEnterActivation(found)) => {
      inspect(dispatch_test_request_tag(found), content="program:1")
      match found {
        DispatchProgramActivation(cursor) => cursor.stmts.clear()
        _ => fail("expected retained program request")
      }
      ticket
    }
    _ => fail("expected activation-entry effect")
  }
  let cleanup = DispatchActivationCleanup(2)
  let (running, run_decision) = reduce_activation_dispatch(
    waiting_entry,
    DispatchEffectCompleted(entry_ticket, DispatchProgramAccepted(cleanup)),
  )
  let run_ticket = match run_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(step))) => {
      inspect(dispatch_test_step_label(step), content="1")
      ticket
    }
    _ => fail("expected activation work")
  }
  let (releasing, release_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      run_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(7.0))),
    ),
  )
  let release_ticket = match release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(found, completion)) => {
      inspect(found.id, content="2")
      expect_dispatch_number(completion, 7.0)
      ticket
    }
    _ => fail("expected activation release")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(completion) => expect_dispatch_number(completion, 7.0)
    _ => fail("expected final completion")
  }
}

///|
test "production root statement enters the closed production seam" {
  let initial = ActivationDispatchState::ActivationDispatchState()
  let request = DispatchProgramActivation(
    DispatchStatementCursor(
      ctx={ strict: false, current_generator: None },
      stmts=[@ast.BreakStmt(Some("901"), @token.Loc::default())],
      env=Environment::new(),
      production=true,
    ),
  )
  let (waiting_entry, enter_decision) = reduce_activation_dispatch(
    initial,
    DispatchStart(request),
  )
  let entry_ticket = match enter_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected activation-entry effect")
  }
  let (_, run_decision) = reduce_activation_dispatch(
    waiting_entry,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchProgramAccepted(DispatchActivationCleanup(902)),
    ),
  )
  match run_decision {
    DispatchPerform(_, DispatchRunProduction(_)) => ()
    _ => fail("expected admitted root work in production seam")
  }
}

///|
test "accepted call starts parameter progress and resumes its body once" {
  let id = 20
  let initial = ActivationDispatchState::ActivationDispatchState()
  let (waiting_entry, entry_decision) = reduce_activation_dispatch(
    initial,
    DispatchStart(dispatch_test_call_request(id)),
  )
  let entry_ticket = match entry_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected call activation entry")
  }
  let initial_progress = dispatch_test_parameter_progress(id + 1, 0)
  let (preparing, prepare_decision) = reduce_activation_dispatch(
    waiting_entry,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchCallAccepted(
        DispatchActivationCleanup(id + 2),
        DispatchCallParameters(initial_progress),
      ),
    ),
  )
  let prepare_ticket = match prepare_decision {
    DispatchPerform(ticket, DispatchRun(DispatchAdvanceParameters(progress))) => {
      inspect(progress.next_index, content="0")
      inspect(progress.args.length(), content="2")
      ticket
    }
    _ => fail("parameter progress must precede the function body")
  }
  let resumed_progress = dispatch_test_parameter_progress(id + 1, 1)
  let (waiting_default_child, child_entry_decision) = reduce_activation_dispatch(
    preparing,
    DispatchEffectCompleted(
      prepare_ticket,
      DispatchWorkSuspended(
        DispatchSuspendCall(
          dispatch_test_call_work(id + 3),
          DispatchBindParameterDefault(resumed_progress),
        ),
      ),
    ),
  )
  let child_entry_ticket = match child_entry_decision {
    DispatchPerform(ticket, DispatchEnterActivation(found)) => {
      inspect(
        dispatch_test_request_tag(found),
        content="call:callee:" + (id + 3).to_string(),
      )
      ticket
    }
    _ => fail("expected guest call from parameter default")
  }
  let (running_child, child_decision) = reduce_activation_dispatch(
    waiting_default_child,
    DispatchEffectCompleted(
      child_entry_ticket,
      DispatchCallAccepted(
        DispatchActivationCleanup(id + 4),
        DispatchCallBody(dispatch_test_statement_work(id + 5)),
      ),
    ),
  )
  let child_ticket = match child_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected parameter-default child body")
  }
  let (releasing_child, child_release_decision) = reduce_activation_dispatch(
    running_child,
    DispatchEffectCompleted(
      child_ticket,
      DispatchWorkCompleted(DispatchReturn(Number(41.0))),
    ),
  )
  let child_release_ticket = match child_release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => {
      inspect(value, content="41")
      ticket
    }
    _ => fail("expected child release before default binding")
  }
  let (binding_default, bind_decision) = reduce_activation_dispatch(
    releasing_child,
    DispatchEffectCompleted(child_release_ticket, DispatchCleanupCompleted),
  )
  let bind_ticket = match bind_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchResumeContinuation(
          DispatchBindParameterDefault(progress),
          Number(value)
        )
      )
    ) => {
      inspect(progress.next_index, content="1")
      inspect(value, content="41")
      ticket
    }
    _ => fail("expected one parameter-default binding resume")
  }
  let (continuing_parameters, continue_decision) = reduce_activation_dispatch(
    binding_default,
    DispatchEffectCompleted(
      bind_ticket,
      DispatchWorkSuspended(DispatchSuspendParameters(resumed_progress)),
    ),
  )
  let continue_ticket = match continue_decision {
    DispatchPerform(ticket, DispatchRun(DispatchAdvanceParameters(progress))) => {
      inspect(progress.next_index, content="1")
      inspect(progress.args.length(), content="2")
      match progress.rest_param {
        Some(name) => inspect(name, content="rest")
        None => fail("expected retained rest parameter")
      }
      ticket
    }
    _ => fail("default binding must continue remaining parameter progress")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      continuing_parameters,
      DispatchEffectCompleted(
        bind_ticket,
        DispatchWorkSuspended(DispatchSuspendParameters(resumed_progress)),
      ),
    )
  })
  let body = DispatchStatementCursor(
    ctx=resumed_progress.ctx,
    stmts=resumed_progress.body,
    env=resumed_progress.env,
  )
  let (running_body, body_decision) = reduce_activation_dispatch(
    continuing_parameters,
    DispatchEffectCompleted(
      continue_ticket,
      DispatchWorkSuspended(DispatchSuspendStatements(body)),
    ),
  )
  let body_ticket = match body_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(step))) => {
      inspect(dispatch_test_step_label(step), content=(id + 1).to_string())
      ticket
    }
    _ => fail("expected body statement after parameter completion")
  }
  let (releasing, release_decision) = reduce_activation_dispatch(
    running_body,
    DispatchEffectCompleted(
      body_ticket,
      DispatchWorkCompleted(DispatchReturn(Number(42.0))),
    ),
  )
  let release_ticket = match release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => {
      inspect(value, content="42")
      ticket
    }
    _ => fail("expected call release after its body")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(completion) => expect_dispatch_number(completion, 42.0)
    _ => fail("expected completed parameter-default call")
  }
}

///|
test "accepted call discards a normal body value" {
  let id = 60
  let initial = ActivationDispatchState::ActivationDispatchState()
  let (waiting_entry, entry_decision) = reduce_activation_dispatch(
    initial,
    DispatchStart(dispatch_test_call_request(id)),
  )
  let entry_ticket = match entry_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected call activation entry")
  }
  let (running, run_decision) = reduce_activation_dispatch(
    waiting_entry,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchCallAccepted(
        DispatchActivationCleanup(id + 1),
        DispatchCallBody(dispatch_test_statement_work(id + 2)),
      ),
    ),
  )
  let run_ticket = match run_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected call body")
  }
  let (releasing, release_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      run_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(99.0))),
    ),
  )
  let release_ticket = match release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(_, DispatchNormal(Undefined))
    ) => ticket
    _ => fail("ordinary function completion must return undefined")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  guard finish_decision is DispatchFinish(DispatchNormal(Undefined)) else {
    fail("expected implicit undefined function result")
  }
}

///|
fn expect_invalid_dispatch(
  action : () -> Unit raise InvalidDispatchTransition,
) -> Unit raise {
  let invalid = try {
    action()
    false
  } catch {
    InvalidDispatchTransition(_) => true
  }
  inspect(invalid, content="true")
}

///|
test "rejected activation rolls back without acquired release" {
  let initial = ActivationDispatchState::ActivationDispatchState()
  let (waiting_entry, enter_decision) = reduce_activation_dispatch(
    initial,
    DispatchStart(dispatch_test_program_request(10)),
  )
  let entry_ticket = match enter_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected activation-entry effect")
  }
  let rejection : Error = @errors.InternalError(message="entry rejected")
  let rollback = DispatchRejectedEntryCleanup(11)
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      waiting_entry,
      DispatchEffectCompleted(
        entry_ticket,
        DispatchWorkCompleted(DispatchNormal(Undefined)),
      ),
    )
  })
  let (rolling_back, rollback_decision) = reduce_activation_dispatch(
    waiting_entry,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchActivationRejected(
        rollback,
        DispatchEntryRuntimeAbrupt(rejection),
      ),
    ),
  )
  let rollback_ticket = match rollback_decision {
    DispatchPerform(
      ticket,
      DispatchRollbackRejectedEntry(found, DispatchRuntimeAbrupt(error))
    ) => {
      inspect(found.id, content="11")
      inspect(physical_equal(error, rejection), content="true")
      ticket
    }
    _ => fail("expected rejected-entry rollback, not activation release")
  }
  expect_invalid_dispatch(() => {
    let stale = DispatchTicket(value=rollback_ticket.value + "0")
    let _ = reduce_activation_dispatch(
      rolling_back,
      DispatchEffectCompleted(stale, DispatchCleanupCompleted),
    )
  })
  let (finished, finish_decision) = reduce_activation_dispatch(
    rolling_back,
    DispatchEffectCompleted(rollback_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(DispatchRuntimeAbrupt(error)) =>
      inspect(physical_equal(error, rejection), content="true")
    _ => fail("expected rejected runtime completion")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      finished,
      DispatchEffectCompleted(rollback_ticket, DispatchCleanupCompleted),
    )
  })
}

///|
test "guest entry rejection rolls back then enters the parent catch" {
  let id = 40
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let (running_try, try_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendProtected(
          dispatch_test_statement_work(id + 3),
          Some(dispatch_test_catch_resume(id + 4)),
          None,
        ),
      ),
    ),
  )
  let try_ticket = match try_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected protected work before rejected child entry")
  }
  let (waiting_child, entry_decision) = reduce_activation_dispatch(
    running_try,
    DispatchEffectCompleted(
      try_ticket,
      DispatchWorkSuspended(
        DispatchSuspendCall(
          dispatch_test_call_work(id + 6),
          DispatchDeliverCallResult,
        ),
      ),
    ),
  )
  let entry_ticket = match entry_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected child activation entry")
  }
  let rollback = DispatchRejectedEntryCleanup(id + 7)
  let rejected_error : Error = @errors.RangeError(message="activation limit")
  let (rolling_back, rollback_decision) = reduce_activation_dispatch(
    waiting_child,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchActivationRejected(
        rollback,
        DispatchEntryGuestThrow(rejected_error),
      ),
    ),
  )
  let rollback_ticket = match rollback_decision {
    DispatchPerform(
      ticket,
      DispatchRollbackRejectedEntry(found, DispatchThrow(error))
    ) => {
      inspect(found.id, content=(id + 7).to_string())
      inspect(physical_equal(error, rejected_error), content="true")
      ticket
    }
    _ => fail("guest rejection must roll back without activation release")
  }
  let (running_catch, catch_decision) = reduce_activation_dispatch(
    rolling_back,
    DispatchEffectCompleted(rollback_ticket, DispatchCleanupCompleted),
  )
  let catch_ticket = match catch_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteCatch(_, caught))) => {
      inspect(physical_equal(caught, rejected_error), content="true")
      ticket
    }
    _ => fail("guest entry rejection must reach the parent catch")
  }
  let (releasing_root, release_decision) = reduce_activation_dispatch(
    running_catch,
    DispatchEffectCompleted(
      catch_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(6.0))),
    ),
  )
  let release_ticket = match release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => {
      inspect(value, content="6")
      ticket
    }
    _ => fail("only the acquired parent activation may be released")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing_root,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(completion) => expect_dispatch_number(completion, 6.0)
    _ => fail("expected caught rejection to finish normally")
  }
}

///|
fn dispatch_test_value_tag(value : Value) -> String {
  match value {
    Undefined => "undefined"
    Number(number) => number.to_string()
    String_(text) => text
    _ => "other"
  }
}

///|
fn dispatch_test_optional_value_tag(value : Value?) -> String {
  match value {
    Some(found) => dispatch_test_value_tag(found)
    None => "none"
  }
}

///|
fn dispatch_test_optional_label_tag(label : String?) -> String {
  match label {
    Some(found) => found
    None => "none"
  }
}

///|
fn dispatch_test_guest_error_tag(error : Error) -> String {
  match error {
    JsException(value) => dispatch_test_value_tag(value)
    _ => "engine-error"
  }
}

///|
fn dispatch_test_js_exception_value(error : Error) -> Value raise {
  match error {
    JsException(value) => value
    _ => fail("expected JsException dispatch completion")
  }
}

///|
fn dispatch_completion_tag(completion : DispatchCompletion) -> String {
  match completion {
    DispatchNormal(value) => "normal:" + dispatch_test_value_tag(value)
    DispatchReturn(value) => "return:" + dispatch_test_value_tag(value)
    DispatchBreak(value, label) =>
      "break:" +
      dispatch_test_optional_value_tag(value) +
      ":" +
      dispatch_test_optional_label_tag(label)
    DispatchContinue(value, label) =>
      "continue:" +
      dispatch_test_optional_value_tag(value) +
      ":" +
      dispatch_test_optional_label_tag(label)
    DispatchThrow(error) => "throw:" + dispatch_test_guest_error_tag(error)
    DispatchRuntimeAbrupt(_) => "runtime-abrupt"
  }
}

///|
fn start_accepted_dispatch_root(
  id : Int,
) -> (ActivationDispatchState, DispatchTicket) raise {
  let initial = ActivationDispatchState::ActivationDispatchState()
  let (waiting_entry, enter_decision) = reduce_activation_dispatch(
    initial,
    DispatchStart(dispatch_test_program_request(id)),
  )
  let entry_ticket = match enter_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected activation-entry effect")
  }
  let (running, run_decision) = reduce_activation_dispatch(
    waiting_entry,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchProgramAccepted(DispatchActivationCleanup(id + 1)),
    ),
  )
  let run_ticket = match run_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(step))) => {
      inspect(dispatch_test_step_label(step), content=id.to_string())
      ticket
    }
    _ => fail("expected root activation work")
  }
  (running, run_ticket)
}

///|
fn run_dispatch_completion_through_finally(
  id : Int,
  saved : DispatchCompletion,
  finalizer_result : DispatchCompletion,
) -> String raise {
  let (running, root_ticket) = start_accepted_dispatch_root(id)
  let (running_try, try_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendProtected(
          dispatch_test_statement_work(id + 3),
          None,
          Some(dispatch_test_statement_work(id + 4)),
        ),
      ),
    ),
  )
  let try_ticket = match try_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(step))) => {
      inspect(dispatch_test_step_label(step), content=(id + 3).to_string())
      ticket
    }
    _ => fail("expected protected work")
  }
  let (running_finally, finalizer_decision) = reduce_activation_dispatch(
    running_try,
    DispatchEffectCompleted(try_ticket, DispatchWorkCompleted(saved)),
  )
  let finalizer_ticket = match finalizer_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(step))) => {
      inspect(dispatch_test_step_label(step), content=(id + 4).to_string())
      ticket
    }
    _ => fail("expected finalizer before activation release")
  }
  let (releasing, release_decision) = reduce_activation_dispatch(
    running_finally,
    DispatchEffectCompleted(
      finalizer_ticket,
      DispatchWorkCompleted(finalizer_result),
    ),
  )
  let (release_ticket, released_completion) = match release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(cleanup, completion)) => {
      inspect(cleanup.id, content=(id + 1).to_string())
      match (saved, finalizer_result, completion) {
        (DispatchThrow(expected), DispatchNormal(_), DispatchThrow(found)) =>
          inspect(physical_equal(found, expected), content="true")
        (_, DispatchThrow(expected), DispatchThrow(found)) =>
          inspect(physical_equal(found, expected), content="true")
        _ => ()
      }
      (ticket, completion)
    }
    _ => fail("expected release only after finalizer completion")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(completion) => {
      match (released_completion, completion) {
        (DispatchThrow(expected), DispatchThrow(found)) =>
          inspect(physical_equal(found, expected), content="true")
        (DispatchRuntimeAbrupt(expected), DispatchRuntimeAbrupt(found)) =>
          inspect(physical_equal(found, expected), content="true")
        _ => ()
      }
      let released_tag = dispatch_completion_tag(released_completion)
      let finished_tag = dispatch_completion_tag(completion)
      inspect(finished_tag == released_tag, content="true")
      finished_tag
    }
    _ => fail("expected final completion after release")
  }
}

///|
test "normal finalizer resumes every saved completion category" {
  let catchable_error : Error = @errors.TypeError(message="guest engine error")
  let runtime_error : Error = @errors.InternalError(message="runtime")
  let tags = [
    run_dispatch_completion_through_finally(
      100,
      DispatchNormal(Number(1.0)),
      DispatchNormal(Undefined),
    ),
    run_dispatch_completion_through_finally(
      200,
      DispatchReturn(Number(2.0)),
      DispatchNormal(Undefined),
    ),
    run_dispatch_completion_through_finally(
      300,
      DispatchBreak(Some(Number(3.0)), Some("L")),
      DispatchNormal(Undefined),
    ),
    run_dispatch_completion_through_finally(
      400,
      DispatchContinue(None, None),
      DispatchNormal(Undefined),
    ),
    run_dispatch_completion_through_finally(
      500,
      DispatchThrow(JsException(String_("guest"))),
      DispatchNormal(Undefined),
    ),
    run_dispatch_completion_through_finally(
      600,
      DispatchThrow(catchable_error),
      DispatchNormal(Undefined),
    ),
    run_dispatch_completion_through_finally(
      700,
      DispatchRuntimeAbrupt(runtime_error),
      DispatchNormal(Undefined),
    ),
  ]
  json_inspect(tags, content=[
    "normal:1", "return:2", "break:3:L", "continue:undefined:none", "throw:guest",
    "throw:engine-error", "runtime-abrupt",
  ])
}

///|
test "abrupt finalizer replaces the saved completion" {
  let tag = run_dispatch_completion_through_finally(
    700,
    DispatchReturn(Number(7.0)),
    DispatchThrow(JsException(String_("replacement"))),
  )
  inspect(tag, content="throw:replacement")
}

///|
test "catch consumes guest throw and returns its completion" {
  let id = 800
  let (running, root_ticket) = start_accepted_dispatch_root(id)
  let (running_try, try_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendProtected(
          dispatch_test_statement_work(id + 3),
          Some(dispatch_test_catch_resume(id + 4)),
          None,
        ),
      ),
    ),
  )
  let try_ticket = match try_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected protected work")
  }
  let thrown : Error = @errors.TypeError(message="caught")
  let (running_catch, catch_decision) = reduce_activation_dispatch(
    running_try,
    DispatchEffectCompleted(
      try_ticket,
      DispatchWorkCompleted(DispatchThrow(thrown)),
    ),
  )
  let catch_ticket = match catch_decision {
    DispatchPerform(
      ticket,
      DispatchRun(DispatchExecuteCatch(catch_state, value))
    ) => {
      inspect(
        dispatch_test_work_label(catch_state.body),
        content=(id + 4).to_string(),
      )
      match catch_state.parameter {
        Some(@ast.Pattern::IdentPat(name)) =>
          inspect(name, content="caught:" + (id + 4).to_string())
        _ => fail("expected retained catch binding pattern")
      }
      inspect(physical_equal(value, thrown), content="true")
      ticket
    }
    _ => fail("expected catch work for guest throw")
  }
  let (releasing, release_decision) = reduce_activation_dispatch(
    running_catch,
    DispatchEffectCompleted(
      catch_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(5.0))),
    ),
  )
  let release_ticket = match release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(_, completion)) => {
      inspect(dispatch_completion_tag(completion), content="normal:5")
      ticket
    }
    _ => fail("expected activation release after catch")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(completion) =>
      inspect(dispatch_completion_tag(completion), content="normal:5")
    _ => fail("expected caught completion")
  }
}

///|
test "bindingless catch runs before its pending finalizer" {
  let id = 850
  let (running, root_ticket) = start_accepted_dispatch_root(id)
  let catch_state = DispatchCatchResume(
    parameter=None,
    body=dispatch_test_statement_work(id + 4),
  )
  let (running_try, try_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendProtected(
          dispatch_test_statement_work(id + 3),
          Some(catch_state),
          Some(dispatch_test_statement_work(id + 5)),
        ),
      ),
    ),
  )
  let try_ticket = match try_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(step))) => {
      inspect(dispatch_test_step_label(step), content=(id + 3).to_string())
      ticket
    }
    _ => fail("expected protected statement")
  }
  let (binding_catch, catch_decision) = reduce_activation_dispatch(
    running_try,
    DispatchEffectCompleted(
      try_ticket,
      DispatchWorkCompleted(
        DispatchThrow(JsException(String_("caught without binding"))),
      ),
    ),
  )
  let (catch_ticket, catch_body) = match catch_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteCatch(found, error))) => {
      guard found.parameter is None else {
        fail("bindingless catch must remain an applicable handler")
      }
      inspect(
        dispatch_test_value_tag(dispatch_test_js_exception_value(error)),
        content="caught without binding",
      )
      (ticket, found.body)
    }
    _ => fail("expected bindingless catch before finally")
  }
  let (running_catch, catch_body_decision) = reduce_activation_dispatch(
    binding_catch,
    DispatchEffectCompleted(
      catch_ticket,
      DispatchWorkSuspended(DispatchSuspendStatements(catch_body)),
    ),
  )
  let catch_body_ticket = match catch_body_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(step))) => {
      inspect(dispatch_test_step_label(step), content=(id + 4).to_string())
      ticket
    }
    _ => fail("expected catch body statement")
  }
  let (running_finally, finally_decision) = reduce_activation_dispatch(
    running_catch,
    DispatchEffectCompleted(
      catch_body_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(5.0))),
    ),
  )
  let finally_ticket = match finally_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(step))) => {
      inspect(dispatch_test_step_label(step), content=(id + 5).to_string())
      ticket
    }
    _ => fail("pending finalizer must run after the catch body")
  }
  let (releasing, release_decision) = reduce_activation_dispatch(
    running_finally,
    DispatchEffectCompleted(
      finally_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let release_ticket = match release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => {
      inspect(value, content="5")
      ticket
    }
    _ => fail("normal finalizer must resume the catch completion")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(completion) => expect_dispatch_number(completion, 5.0)
    _ => fail("expected bindingless catch completion")
  }
}

///|
test "catch bypasses runtime abrupt completion" {
  let id = 900
  let (running, root_ticket) = start_accepted_dispatch_root(id)
  let (running_try, try_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendProtected(
          dispatch_test_statement_work(id + 3),
          Some(dispatch_test_catch_resume(id + 4)),
          None,
        ),
      ),
    ),
  )
  let try_ticket = match try_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected protected work")
  }
  let runtime_error : Error = @errors.InternalError(message="not catchable")
  let (releasing, release_decision) = reduce_activation_dispatch(
    running_try,
    DispatchEffectCompleted(
      try_ticket,
      DispatchWorkCompleted(DispatchRuntimeAbrupt(runtime_error)),
    ),
  )
  let release_ticket = match release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(_, DispatchRuntimeAbrupt(found))
    ) => {
      inspect(physical_equal(found, runtime_error), content="true")
      ticket
    }
    _ => fail("runtime abrupt must bypass catch and release")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(DispatchRuntimeAbrupt(found)) =>
      inspect(physical_equal(found, runtime_error), content="true")
    _ => fail("expected uncaught runtime completion")
  }
}

///|
test "child result resumes binary then return once after child release" {
  let id = 1000
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let binary = DispatchBinaryResume(
    op=@ast.Add,
    left=Number(1.0),
    loc=@token.Loc::default(),
  )
  let (running_return_value, return_value_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendContinue(
          DispatchCompleteReturn,
          DispatchExecuteStatement(dispatch_test_statement_step(id + 9)),
        ),
      ),
    ),
  )
  let return_value_ticket = match return_value_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected pending return expression work")
  }
  let child_request = dispatch_test_call_work(id + 10)
  let (waiting_child, child_entry_decision) = reduce_activation_dispatch(
    running_return_value,
    DispatchEffectCompleted(
      return_value_ticket,
      DispatchWorkSuspended(
        DispatchSuspendCall(child_request, DispatchApplyBinaryRight(binary)),
      ),
    ),
  )
  let child_entry_ticket = match child_entry_decision {
    DispatchPerform(ticket, DispatchEnterActivation(found)) => {
      inspect(
        dispatch_test_request_tag(found),
        content="call:callee:" + (id + 10).to_string(),
      )
      ticket
    }
    _ => fail("expected child activation entry")
  }
  let child_cleanup = DispatchActivationCleanup(id + 11)
  let (running_child, child_run_decision) = reduce_activation_dispatch(
    waiting_child,
    DispatchEffectCompleted(
      child_entry_ticket,
      DispatchCallAccepted(
        child_cleanup,
        DispatchCallBody(dispatch_test_statement_work(id + 12)),
      ),
    ),
  )
  let child_run_ticket = match child_run_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(step))) => {
      inspect(dispatch_test_step_label(step), content=(id + 12).to_string())
      ticket
    }
    _ => fail("expected child activation work")
  }
  let (releasing_child, child_release_decision) = reduce_activation_dispatch(
    running_child,
    DispatchEffectCompleted(
      child_run_ticket,
      DispatchWorkCompleted(DispatchReturn(Number(7.0))),
    ),
  )
  let child_release_ticket = match child_release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(found, completion)) => {
      inspect(found.id, content=(id + 11).to_string())
      inspect(dispatch_completion_tag(completion), content="normal:7")
      ticket
    }
    _ => fail("expected child release before caller continuation")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      releasing_child,
      DispatchEffectCompleted(
        child_run_ticket,
        DispatchWorkCompleted(DispatchReturn(Number(8.0))),
      ),
    )
  })
  let (running_binary, binary_decision) = reduce_activation_dispatch(
    releasing_child,
    DispatchEffectCompleted(child_release_ticket, DispatchCleanupCompleted),
  )
  let binary_ticket = match binary_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchResumeContinuation(
          DispatchApplyBinaryRight(found),
          Number(right)
        )
      )
    ) => {
      inspect(found.op == @ast.Add, content="true")
      inspect(dispatch_test_value_tag(found.left), content="1")
      inspect(right, content="7")
      ticket
    }
    _ => fail("expected binary continuation after child release")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      running_binary,
      DispatchEffectCompleted(child_release_ticket, DispatchCleanupCompleted),
    )
  })
  let (releasing_root, root_release_decision) = reduce_activation_dispatch(
    running_binary,
    DispatchEffectCompleted(
      binary_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(8.0))),
    ),
  )
  let root_release_ticket = match root_release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(found, completion)) => {
      inspect(found.id, content=(id + 1).to_string())
      inspect(dispatch_completion_tag(completion), content="return:8")
      ticket
    }
    _ => fail("expected caller return after child release")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      releasing_root,
      DispatchEffectCompleted(child_release_ticket, DispatchCleanupCompleted),
    )
  })
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing_root,
    DispatchEffectCompleted(root_release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(completion) =>
      inspect(dispatch_completion_tag(completion), content="return:8")
    _ => fail("expected returned root completion")
  }
}

///|
test "normal call result resumes its caller once after child release" {
  let id = 1050
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let (waiting_child, entry_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendCall(
          dispatch_test_call_work(id + 2),
          DispatchDeliverCallResult,
        ),
      ),
    ),
  )
  let entry_ticket = match entry_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected child activation entry")
  }
  let (running_child, child_decision) = reduce_activation_dispatch(
    waiting_child,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchCallAccepted(
        DispatchActivationCleanup(id + 3),
        DispatchCallBody(dispatch_test_statement_work(id + 4)),
      ),
    ),
  )
  let child_ticket = match child_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected child body")
  }
  let (releasing_child, child_release_decision) = reduce_activation_dispatch(
    running_child,
    DispatchEffectCompleted(
      child_ticket,
      DispatchWorkCompleted(DispatchReturn(Number(8.0))),
    ),
  )
  let child_release_ticket = match child_release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => {
      inspect(value, content="8")
      ticket
    }
    _ => fail("expected child release before value delivery")
  }
  let (releasing_root, root_release_decision) = reduce_activation_dispatch(
    releasing_child,
    DispatchEffectCompleted(child_release_ticket, DispatchCleanupCompleted),
  )
  let root_release_ticket = match root_release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => {
      inspect(value, content="8")
      ticket
    }
    _ => fail("normal child value must resume the caller statement")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      releasing_root,
      DispatchEffectCompleted(child_release_ticket, DispatchCleanupCompleted),
    )
  })
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing_root,
    DispatchEffectCompleted(root_release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(completion) => expect_dispatch_number(completion, 8.0)
    _ => fail("expected delivered call result")
  }
}

///|
test "expression plan defensively inserts and consumes the recursive result" {
  let id = 1150
  let template_args = [Undefined]
  let plan = DispatchExpressionPlan(steps=[
    DispatchExpressionCall(
      DispatchExpressionCallStep(
        request=DispatchCallRequest(
          callee=String_("id"),
          this_value=Undefined,
          args=template_args,
          loc=@token.Loc::default(),
        ),
        adapter=DispatchDirectReturnUserFuncAdapterToken(String_("id"), "id"),
        name="id",
        result_argument_index=Some(0),
      ),
    ),
  ])
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let (running_value, value_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendContinue(
          DispatchContinueExpressionPlan(
            DispatchExpressionPlanResume(plan~, next_index=0, values=[]),
          ),
          DispatchExecuteStatement(dispatch_test_statement_step(id + 3)),
        ),
      ),
    ),
  )
  let value_ticket = match value_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected expression-plan continuation input work")
  }
  let (_, resume_decision) = reduce_activation_dispatch(
    running_value,
    DispatchEffectCompleted(
      value_ticket,
      DispatchWorkCompleted(DispatchNormal(String_("done"))),
    ),
  )
  match resume_decision {
    DispatchPerform(_, DispatchEnterActivation(DispatchCallActivation(request))) => {
      guard request.args is [String_("done")] else {
        fail("expected the recursive result in the helper argument slot")
      }
      inspect(dispatch_test_value_tag(template_args[0]), content="undefined")
    }
    _ => fail("expected the result-fed helper call activation")
  }
}

///|
test "expression plan preserves abrupt result without entering helper" {
  let id = 1160
  let plan = DispatchExpressionPlan(steps=[
    DispatchExpressionCall(
      DispatchExpressionCallStep(
        request=DispatchCallRequest(
          callee=String_("id"),
          this_value=Undefined,
          args=[Undefined],
          loc=@token.Loc::default(),
        ),
        adapter=DispatchDirectReturnUserFuncAdapterToken(String_("id"), "id"),
        name="id",
        result_argument_index=Some(0),
      ),
    ),
  ])
  let thrown : Error = JsException(String_("boom"))
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let (running_value, decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendContinue(
          DispatchContinueExpressionPlan(
            DispatchExpressionPlanResume(plan~, next_index=0, values=[]),
          ),
          DispatchExecuteStatement(dispatch_test_statement_step(id + 3)),
        ),
      ),
    ),
  )
  let value_ticket = match decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected expression-plan continuation input work")
  }
  let (_, release_decision) = reduce_activation_dispatch(
    running_value,
    DispatchEffectCompleted(
      value_ticket,
      DispatchWorkCompleted(DispatchThrow(thrown)),
    ),
  )
  match release_decision {
    DispatchPerform(_, DispatchReleaseActivation(_, DispatchThrow(found))) =>
      inspect(physical_equal(found, thrown), content="true")
    DispatchPerform(_, DispatchEnterActivation(DispatchCallActivation(_))) =>
      fail("abrupt result must bypass helper activation")
    _ => fail("expected activation release for abrupt result")
  }
}

///|
test "expression plan preserves runtime abrupt result without entering helper" {
  let id = 1170
  let plan = DispatchExpressionPlan(steps=[
    DispatchExpressionCall(
      DispatchExpressionCallStep(
        request=DispatchCallRequest(
          callee=String_("id"),
          this_value=Undefined,
          args=[Undefined],
          loc=@token.Loc::default(),
        ),
        adapter=DispatchDirectReturnUserFuncAdapterToken(String_("id"), "id"),
        name="id",
        result_argument_index=Some(0),
      ),
    ),
  ])
  let runtime_error : Error = ExecutionControlError(Interrupted)
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let (running_value, decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendContinue(
          DispatchContinueExpressionPlan(
            DispatchExpressionPlanResume(plan~, next_index=0, values=[]),
          ),
          DispatchExecuteStatement(dispatch_test_statement_step(id + 3)),
        ),
      ),
    ),
  )
  let value_ticket = match decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected expression-plan continuation input work")
  }
  let (releasing, release_decision) = reduce_activation_dispatch(
    running_value,
    DispatchEffectCompleted(
      value_ticket,
      DispatchWorkCompleted(DispatchRuntimeAbrupt(runtime_error)),
    ),
  )
  let release_ticket = match release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(_, DispatchRuntimeAbrupt(found))
    ) => {
      inspect(physical_equal(found, runtime_error), content="true")
      ticket
    }
    DispatchPerform(_, DispatchEnterActivation(DispatchCallActivation(_))) =>
      fail("runtime abrupt must bypass helper activation")
    _ => fail("expected activation release for runtime abrupt")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(DispatchRuntimeAbrupt(found)) =>
      inspect(physical_equal(found, runtime_error), content="true")
    DispatchPerform(_, DispatchEnterActivation(DispatchCallActivation(_))) =>
      fail("cleanup must not enter the runtime-abrupt helper activation")
    _ => fail("expected runtime abrupt completion after cleanup")
  }
}

///|
fn direct_return_two_stage_expression_test_plan() -> DispatchExpressionPlan {
  DispatchExpressionPlan(steps=[
    DispatchExpressionCall(
      DispatchExpressionCallStep(
        request=DispatchCallRequest(
          callee=String_("inner"),
          this_value=Undefined,
          args=[Undefined],
          loc=@token.Loc::default(),
        ),
        adapter=DispatchDirectReturnUserFuncAdapterToken(
          String_("inner"),
          "inner",
        ),
        name="inner",
        result_argument_index=Some(0),
      ),
    ),
    DispatchExpressionCall(
      DispatchExpressionCallStep(
        request=DispatchCallRequest(
          callee=String_("outer"),
          this_value=Undefined,
          args=[Undefined, Undefined],
          loc=@token.Loc::default(),
        ),
        adapter=DispatchDirectReturnUserFuncAdapterToken(
          String_("outer"),
          "outer",
        ),
        name="outer",
        result_argument_index=Some(1),
      ),
    ),
  ])
}

///|
fn direct_return_two_stage_failure_error(
  failure_after_inner : Bool,
  runtime_abrupt : Bool,
) -> Error {
  let stage = if failure_after_inner { "inner" } else { "outer" }
  if runtime_abrupt {
    @errors.InternalError(message="two-stage runtime " + stage)
  } else {
    JsException(
      Object({
        bag: PropertyBag(),
        prototype: Null,
        callable: None,
        class_name: "Error",
        extensible: true,
        arraybuffer_state: None,
      }),
    )
  }
}

///|
fn expect_direct_return_two_stage_failure_completion(
  actual : DispatchCompletion,
  expected : DispatchCompletion,
) -> Unit raise {
  match (actual, expected) {
    (DispatchThrow(actual), DispatchThrow(expected)) =>
      inspect(physical_equal(actual, expected), content="true")
    (DispatchRuntimeAbrupt(actual), DispatchRuntimeAbrupt(expected)) =>
      inspect(physical_equal(actual, expected), content="true")
    _ => fail("two-stage expression plan changed its failure completion")
  }
}

///|
fn finish_direct_return_two_stage_failure(
  running : ActivationDispatchState,
  body_ticket : DispatchTicket,
  expected_completion : DispatchCompletion,
  stage : String,
) -> Unit raise {
  let (releasing, release_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      body_ticket,
      DispatchWorkCompleted(expected_completion),
    ),
  )
  let release_ticket = match release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(_, actual_completion)) => {
      expect_direct_return_two_stage_failure_completion(
        actual_completion, expected_completion,
      )
      ticket
    }
    DispatchPerform(_, DispatchEnterActivation(_)) =>
      fail(stage + " failure must not enter a later helper activation")
    _ => fail(stage + " failure must release its activation")
  }
  let (releasing_root, root_release_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  let root_release_ticket = match root_release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(_, actual_completion)) => {
      expect_direct_return_two_stage_failure_completion(
        actual_completion, expected_completion,
      )
      ticket
    }
    DispatchPerform(_, DispatchEnterActivation(_)) =>
      fail(stage + " failure cleanup must not enter a later helper activation")
    _ => fail(stage + " failure cleanup must release the root activation")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing_root,
    DispatchEffectCompleted(root_release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(actual_completion) =>
      expect_direct_return_two_stage_failure_completion(
        actual_completion, expected_completion,
      )
    DispatchPerform(_, DispatchEnterActivation(_)) =>
      fail(stage + " failure cleanup must not enter a later helper activation")
    _ => fail(stage + " failure must finish after cleanup")
  }
}

///|
fn expect_direct_return_two_stage_failure(
  failure_after_inner : Bool,
  runtime_abrupt : Bool,
) -> Unit raise {
  let id = if failure_after_inner { 1180 } else { 1190 }
  let id = if runtime_abrupt { id + 1 } else { id }
  let expected_error = direct_return_two_stage_failure_error(
    failure_after_inner, runtime_abrupt,
  )
  let expected_completion = if runtime_abrupt {
    DispatchRuntimeAbrupt(expected_error)
  } else {
    DispatchThrow(expected_error)
  }
  let plan = direct_return_two_stage_expression_test_plan()
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let (waiting_for_expression, root_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendContinue(
          DispatchContinueExpressionPlan(
            DispatchExpressionPlanResume(plan~, next_index=0, values=[]),
          ),
          DispatchExecuteStatement(dispatch_test_statement_step(id + 1)),
        ),
      ),
    ),
  )
  let expression_ticket = match root_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("two-stage plan did not schedule its recursive result")
  }
  let (waiting_inner, inner_decision) = reduce_activation_dispatch(
    waiting_for_expression,
    DispatchEffectCompleted(
      expression_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(41.0))),
    ),
  )
  let inner_entry_ticket = match inner_decision {
    DispatchPerform(
      ticket,
      DispatchEnterActivation(DispatchCallActivation(request))
    ) => {
      guard request.callee is String_("inner") else {
        fail("two-stage plan did not enter inner first")
      }
      ticket
    }
    _ => fail("two-stage plan did not schedule inner activation")
  }
  let (running_inner, inner_decision) = reduce_activation_dispatch(
    waiting_inner,
    DispatchEffectCompleted(
      inner_entry_ticket,
      DispatchCallAccepted(
        DispatchActivationCleanup(id + 2),
        DispatchCallBody(dispatch_test_statement_work(id + 3)),
      ),
    ),
  )
  let inner_body_ticket = match inner_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("two-stage plan did not run inner body")
  }
  if failure_after_inner {
    finish_direct_return_two_stage_failure(
      running_inner, inner_body_ticket, expected_completion, "inner",
    )
  } else {
    let (releasing_inner, inner_release_decision) = reduce_activation_dispatch(
      running_inner,
      DispatchEffectCompleted(
        inner_body_ticket,
        DispatchWorkCompleted(DispatchReturn(Number(42.0))),
      ),
    )
    let inner_release_ticket = match inner_release_decision {
      DispatchPerform(
        ticket,
        DispatchReleaseActivation(_, DispatchNormal(Number(value)))
      ) => {
        inspect(value, content="42")
        ticket
      }
      _ => fail("inner normal result must release inner activation")
    }
    let (waiting_outer, outer_decision) = reduce_activation_dispatch(
      releasing_inner,
      DispatchEffectCompleted(inner_release_ticket, DispatchCleanupCompleted),
    )
    let outer_entry_ticket = match outer_decision {
      DispatchPerform(
        ticket,
        DispatchEnterActivation(DispatchCallActivation(request))
      ) => {
        guard request.callee is String_("outer") else {
          fail("two-stage plan did not enter outer second")
        }
        ticket
      }
      _ => fail("inner success did not schedule outer activation")
    }
    let (running_outer, outer_decision) = reduce_activation_dispatch(
      waiting_outer,
      DispatchEffectCompleted(
        outer_entry_ticket,
        DispatchCallAccepted(
          DispatchActivationCleanup(id + 4),
          DispatchCallBody(dispatch_test_statement_work(id + 5)),
        ),
      ),
    )
    let outer_body_ticket = match outer_decision {
      DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) =>
        ticket
      _ => fail("two-stage plan did not run outer body")
    }
    finish_direct_return_two_stage_failure(
      running_outer, outer_body_ticket, expected_completion, "outer",
    )
  }
}

///|
test "expression plan preserves inner guest Error identity" {
  expect_direct_return_two_stage_failure(true, false)
}

///|
test "expression plan preserves outer guest Error identity" {
  expect_direct_return_two_stage_failure(false, false)
}

///|
test "expression plan preserves inner runtime-abrupt Error identity" {
  expect_direct_return_two_stage_failure(true, true)
}

///|
test "expression plan preserves outer runtime-abrupt Error identity" {
  expect_direct_return_two_stage_failure(false, true)
}

///|
test "throw-value continuation consumes one normal value" {
  let id = 1100
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let (running_value, value_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendContinue(
          DispatchCompleteThrow,
          DispatchExecuteStatement(dispatch_test_statement_step(id + 3)),
        ),
      ),
    ),
  )
  let value_ticket = match value_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected value-producing work")
  }
  let (releasing, release_decision) = reduce_activation_dispatch(
    running_value,
    DispatchEffectCompleted(
      value_ticket,
      DispatchWorkCompleted(DispatchNormal(String_("boom"))),
    ),
  )
  let (release_ticket, released_error) = match release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(_, DispatchThrow(error))) => {
      inspect(
        dispatch_test_value_tag(dispatch_test_js_exception_value(error)),
        content="boom",
      )
      (ticket, error)
    }
    _ => fail("expected throw completion at activation boundary")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      releasing,
      DispatchEffectCompleted(
        value_ticket,
        DispatchWorkCompleted(DispatchNormal(String_("again"))),
      ),
    )
  })
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(DispatchThrow(error)) => {
      inspect(physical_equal(error, released_error), content="true")
      inspect(
        dispatch_test_value_tag(dispatch_test_js_exception_value(error)),
        content="boom",
      )
    }
    _ => fail("expected thrown root completion")
  }
}

///|
fn start_proxy_invariant_dispatch(
  id : Int,
  post_trap : DispatchProxyGetResume,
  trap_result : Value,
) -> (
  ActivationDispatchState,
  DispatchTicket,
  DispatchEffect,
  DispatchPropertyCleanup,
) raise {
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let property_cleanup = DispatchPropertyCleanup(id + 3)
  let (running_property, property_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendProperty(
          property_cleanup,
          dispatch_test_property_resume(id + 4),
          DispatchCompleteReturn,
        ),
      ),
    ),
  )
  let property_ticket = match property_decision {
    DispatchPerform(
      ticket,
      DispatchRunProduction(DispatchPropertyExecute(work))
    ) => {
      inspect(
        dispatch_test_property_key(work.property_key),
        content="key:" + (id + 4).to_string(),
      )
      ticket
    }
    _ => fail("expected property work")
  }
  let (waiting_trap, trap_entry_decision) = reduce_activation_dispatch(
    running_property,
    DispatchEffectCompleted(
      property_ticket,
      DispatchWorkSuspended(
        DispatchSuspendCall(
          dispatch_test_call_work(id + 5),
          DispatchCheckProxyGetResult(post_trap),
        ),
      ),
    ),
  )
  let trap_entry_ticket = match trap_entry_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected Proxy trap activation entry")
  }
  let (running_trap, trap_decision) = reduce_activation_dispatch(
    waiting_trap,
    DispatchEffectCompleted(
      trap_entry_ticket,
      DispatchCallAccepted(
        DispatchActivationCleanup(id + 7),
        DispatchCallBody(dispatch_test_statement_work(id + 8)),
      ),
    ),
  )
  let trap_ticket = match trap_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected Proxy trap work")
  }
  let (releasing_trap, trap_release_decision) = reduce_activation_dispatch(
    running_trap,
    DispatchEffectCompleted(
      trap_ticket,
      DispatchWorkCompleted(DispatchReturn(trap_result)),
    ),
  )
  let trap_release_ticket = match trap_release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(_, DispatchNormal(value))) => {
      inspect(same_value(value, trap_result), content="true")
      ticket
    }
    _ => fail("expected trap release before invariant work")
  }
  let (running_invariant, invariant_decision) = reduce_activation_dispatch(
    releasing_trap,
    DispatchEffectCompleted(trap_release_ticket, DispatchCleanupCompleted),
  )
  let (invariant_ticket, invariant_effect) = match invariant_decision {
    DispatchPerform(
      ticket,
      DispatchRunProduction(DispatchPropertyCheckProxyGetResult(work, value))
    ) => {
      inspect(
        dispatch_test_property_key(work.property_key),
        content=dispatch_test_property_key(post_trap.property_key),
      )
      inspect(same_value(work.target, post_trap.target), content="true")
      inspect(same_value(work.receiver, post_trap.receiver), content="true")
      inspect(same_value(value, trap_result), content="true")
      (
        ticket,
        DispatchRunProduction(DispatchPropertyCheckProxyGetResult(work, value)),
      )
    }
    _ => fail("expected Proxy invariant before property restore")
  }
  (running_invariant, invariant_ticket, invariant_effect, property_cleanup)
}

///|
fn expect_proxy_invariant_error_route(
  id : Int,
  target : Value,
  trap_result : Value,
  expected_message : String,
) -> Unit raise {
  let post_trap = DispatchProxyGetResume(
    target~,
    property_key=String_("x"),
    receiver=String_("receiver:" + id.to_string()),
    loc=@token.Loc::default(),
  )
  let (running_invariant, invariant_ticket, invariant_effect, property_cleanup) = start_proxy_invariant_dispatch(
    id, post_trap, trap_result,
  )
  let shell = PrimitiveProgramDispatchShell(Interpreter::new())
  let invariant_result = shell.perform_effect(invariant_effect)
  let invariant_error = match invariant_result {
    DispatchWorkCompleted(DispatchThrow(error)) => {
      match @errors.name_message_if_js_error(error) {
        Some((name, message)) => {
          inspect(name, content="TypeError")
          inspect(message, content=expected_message)
        }
        None => fail("expected a JavaScript TypeError from Proxy validation")
      }
      error
    }
    _ => fail("expected Proxy validation to complete with a guest throw")
  }
  let (restoring_property, restore_decision) = reduce_activation_dispatch(
    running_invariant,
    DispatchEffectCompleted(
      invariant_ticket,
      DispatchWorkCompleted(DispatchThrow(invariant_error)),
    ),
  )
  let restore_ticket = match restore_decision {
    DispatchPerform(
      ticket,
      DispatchRestorePropertyScope(found, DispatchThrow(error))
    ) => {
      inspect(found.id, content=property_cleanup.id.to_string())
      inspect(physical_equal(error, invariant_error), content="true")
      ticket
    }
    _ => fail("expected property restore after invariant error")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      restoring_property,
      DispatchEffectCompleted(
        invariant_ticket,
        DispatchWorkCompleted(DispatchThrow(invariant_error)),
      ),
    )
  })
  let (releasing_root, root_release_decision) = reduce_activation_dispatch(
    restoring_property,
    DispatchEffectCompleted(restore_ticket, DispatchCleanupCompleted),
  )
  let root_release_ticket = match root_release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(_, DispatchThrow(error))) => {
      inspect(physical_equal(error, invariant_error), content="true")
      ticket
    }
    _ => fail("expected parent release after property restore")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing_root,
    DispatchEffectCompleted(root_release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(DispatchThrow(error)) =>
      inspect(physical_equal(error, invariant_error), content="true")
    _ => fail("expected the Proxy invariant error to reach the root")
  }
}

///|
test "Proxy invariant precedes property restore and parent release" {
  let id = 1200
  let trap_result = Number(9.0)
  let post_trap = dispatch_test_proxy_resume(id + 6)
  let (running_invariant, invariant_ticket, _, property_cleanup) = start_proxy_invariant_dispatch(
    id, post_trap, trap_result,
  )
  let (restoring_property, restore_decision) = reduce_activation_dispatch(
    running_invariant,
    DispatchEffectCompleted(
      invariant_ticket,
      DispatchWorkCompleted(DispatchNormal(trap_result)),
    ),
  )
  let restore_ticket = match restore_decision {
    DispatchPerform(ticket, DispatchRestorePropertyScope(found, completion)) => {
      inspect(found.id, content=property_cleanup.id.to_string())
      inspect(dispatch_completion_tag(completion), content="normal:9")
      ticket
    }
    _ => fail("expected property restore after invariant")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      restoring_property,
      DispatchEffectCompleted(invariant_ticket, DispatchCleanupCompleted),
    )
  })
  let (releasing_root, root_release_decision) = reduce_activation_dispatch(
    restoring_property,
    DispatchEffectCompleted(restore_ticket, DispatchCleanupCompleted),
  )
  let root_release_ticket = match root_release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(_, completion)) => {
      inspect(dispatch_completion_tag(completion), content="return:9")
      ticket
    }
    _ => fail("expected parent release after property restore")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing_root,
    DispatchEffectCompleted(root_release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(completion) =>
      inspect(dispatch_completion_tag(completion), content="return:9")
    _ => fail("expected Proxy result completion")
  }
}

///|
test "Proxy frozen data invariant preserves post-trap error ordering" {
  let descriptor : PropDescriptor = {
    writable: false,
    enumerable: true,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let target = dispatch_shell_test_ordinary_object(
    Null,
    Some(descriptor),
    Some(Number(1.0)),
  )
  expect_proxy_invariant_error_route(
    1210,
    target,
    Number(2.0),
    "'get' on proxy: trap did not return the actual value of a read-only non-configurable target property",
  )
}

///|
test "Proxy getterless accessor invariant preserves post-trap error ordering" {
  let descriptor : PropDescriptor = {
    writable: false,
    enumerable: true,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: true,
  }
  let target = dispatch_shell_test_ordinary_object(Null, Some(descriptor), None)
  expect_proxy_invariant_error_route(
    1220,
    target,
    Number(2.0),
    "'get' on proxy: trap returned a value for a non-configurable target accessor without a getter",
  )
}

///|
test "Proxy handler lookup restores its nested property scope before trap resolution" {
  let id = 1230
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let outer_cleanup = DispatchPropertyCleanup(id + 10)
  let outer_work = dispatch_test_property_resume(id + 11)
  let (running_outer, outer_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendProperty(
          outer_cleanup,
          outer_work,
          DispatchCompleteReturn,
        ),
      ),
    ),
  )
  let outer_ticket = match outer_decision {
    DispatchPerform(ticket, DispatchRunProduction(DispatchPropertyExecute(_))) =>
      ticket
    _ => fail("expected outer Proxy property work")
  }
  let inner_cleanup = DispatchPropertyCleanup(id + 12)
  let handler_work = dispatch_test_property_resume(id + 13)
  let lookup = dispatch_test_proxy_trap_lookup_resume(id + 14)
  let (running_handler_lookup, handler_decision) = reduce_activation_dispatch(
    running_outer,
    DispatchEffectCompleted(
      outer_ticket,
      DispatchWorkSuspended(
        DispatchSuspendProperty(
          inner_cleanup,
          handler_work,
          DispatchResolveProxyGetTrap(lookup),
        ),
      ),
    ),
  )
  let handler_ticket = match handler_decision {
    DispatchPerform(
      ticket,
      DispatchRunProduction(DispatchPropertyExecute(work))
    ) => {
      inspect(
        dispatch_test_property_key(work.property_key),
        content="key:" + (id + 13).to_string(),
      )
      ticket
    }
    _ => fail("expected handler get-trap lookup work")
  }
  let trap = String_("trap")
  let (restoring_handler, handler_restore_decision) = reduce_activation_dispatch(
    running_handler_lookup,
    DispatchEffectCompleted(
      handler_ticket,
      DispatchWorkCompleted(DispatchNormal(trap)),
    ),
  )
  let handler_restore_ticket = match handler_restore_decision {
    DispatchPerform(
      ticket,
      DispatchRestorePropertyScope(found, DispatchNormal(value))
    ) => {
      inspect(found.id, content=(id + 12).to_string())
      inspect(dispatch_test_value_tag(value), content="trap")
      ticket
    }
    _ => fail("expected handler property restoration before trap resolution")
  }
  let (resolving_trap, trap_resolution_decision) = reduce_activation_dispatch(
    restoring_handler,
    DispatchEffectCompleted(handler_restore_ticket, DispatchCleanupCompleted),
  )
  let trap_resolution_ticket = match trap_resolution_decision {
    DispatchPerform(
      ticket,
      DispatchRunProduction(DispatchPropertyResolveProxyGetTrap(found, value))
    ) => {
      inspect(
        dispatch_test_value_tag(found.proxy),
        content="proxy:" + (id + 14).to_string(),
      )
      inspect(
        dispatch_test_value_tag(found.handler),
        content="handler:" + (id + 14).to_string(),
      )
      inspect(
        same_value(found.post_trap.target, lookup.post_trap.target),
        content="true",
      )
      inspect(
        dispatch_test_property_key(found.post_trap.property_key),
        content="key:" + (id + 14).to_string(),
      )
      inspect(
        same_value(found.post_trap.receiver, lookup.post_trap.receiver),
        content="true",
      )
      inspect(dispatch_test_value_tag(value), content="trap")
      ticket
    }
    _ => fail("expected trap resolution after handler property restoration")
  }
  let (restoring_outer, outer_restore_decision) = reduce_activation_dispatch(
    resolving_trap,
    DispatchEffectCompleted(
      trap_resolution_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(9.0))),
    ),
  )
  let outer_restore_ticket = match outer_restore_decision {
    DispatchPerform(
      ticket,
      DispatchRestorePropertyScope(found, DispatchNormal(value))
    ) => {
      inspect(found.id, content=(id + 10).to_string())
      inspect(dispatch_test_value_tag(value), content="9")
      ticket
    }
    _ => fail("expected outer property restoration after trap resolution")
  }
  let (releasing_root, root_release_decision) = reduce_activation_dispatch(
    restoring_outer,
    DispatchEffectCompleted(outer_restore_ticket, DispatchCleanupCompleted),
  )
  let root_release_ticket = match root_release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(_, completion)) => {
      inspect(dispatch_completion_tag(completion), content="return:9")
      ticket
    }
    _ => fail("expected root release after both property scopes")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing_root,
    DispatchEffectCompleted(root_release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(completion) =>
      inspect(dispatch_completion_tag(completion), content="return:9")
    _ => fail("expected nested Proxy lookup completion")
  }
}

///|
test "abrupt Proxy handler lookup restores inner and outer property scopes" {
  let id = 1240
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let outer_cleanup = DispatchPropertyCleanup(id + 10)
  let (running_outer, outer_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendProperty(
          outer_cleanup,
          dispatch_test_property_resume(id + 11),
          DispatchCompleteReturn,
        ),
      ),
    ),
  )
  let outer_ticket = match outer_decision {
    DispatchPerform(ticket, DispatchRunProduction(DispatchPropertyExecute(_))) =>
      ticket
    _ => fail("expected outer Proxy property work")
  }
  let inner_cleanup = DispatchPropertyCleanup(id + 12)
  let (running_handler_lookup, handler_decision) = reduce_activation_dispatch(
    running_outer,
    DispatchEffectCompleted(
      outer_ticket,
      DispatchWorkSuspended(
        DispatchSuspendProperty(
          inner_cleanup,
          dispatch_test_property_resume(id + 13),
          DispatchResolveProxyGetTrap(
            dispatch_test_proxy_trap_lookup_resume(id + 14),
          ),
        ),
      ),
    ),
  )
  let handler_ticket = match handler_decision {
    DispatchPerform(ticket, DispatchRunProduction(DispatchPropertyExecute(_))) =>
      ticket
    _ => fail("expected handler get-trap lookup work")
  }
  let lookup_error : Error = JsException(String_("handler lookup failed"))
  let (restoring_handler, handler_restore_decision) = reduce_activation_dispatch(
    running_handler_lookup,
    DispatchEffectCompleted(
      handler_ticket,
      DispatchWorkCompleted(DispatchThrow(lookup_error)),
    ),
  )
  let handler_restore_ticket = match handler_restore_decision {
    DispatchPerform(
      ticket,
      DispatchRestorePropertyScope(found, DispatchThrow(completion_error))
    ) => {
      inspect(found.id, content=(id + 12).to_string())
      inspect(physical_equal(completion_error, lookup_error), content="true")
      ticket
    }
    _ => fail("expected inner property restoration first")
  }
  let (restoring_outer, outer_restore_decision) = reduce_activation_dispatch(
    restoring_handler,
    DispatchEffectCompleted(handler_restore_ticket, DispatchCleanupCompleted),
  )
  let outer_restore_ticket = match outer_restore_decision {
    DispatchPerform(
      ticket,
      DispatchRestorePropertyScope(found, DispatchThrow(completion_error))
    ) => {
      inspect(found.id, content=(id + 10).to_string())
      inspect(physical_equal(completion_error, lookup_error), content="true")
      ticket
    }
    _ => fail("expected outer property restoration without trap resolution")
  }
  let (releasing_root, root_release_decision) = reduce_activation_dispatch(
    restoring_outer,
    DispatchEffectCompleted(outer_restore_ticket, DispatchCleanupCompleted),
  )
  let root_release_ticket = match root_release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(_, DispatchThrow(found))) => {
      inspect(physical_equal(found, lookup_error), content="true")
      ticket
    }
    _ => fail("expected root release after both property restorations")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing_root,
    DispatchEffectCompleted(root_release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(DispatchThrow(found)) =>
      inspect(physical_equal(found, lookup_error), content="true")
    _ => fail("expected abrupt nested Proxy lookup completion")
  }
}

///|
test "abrupt property work restores its scope before activation release" {
  let id = 1250
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let property_cleanup = DispatchPropertyCleanup(id + 2)
  let property_resume = dispatch_test_property_resume(id + 3)
  let (running_property, property_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendProperty(
          property_cleanup,
          property_resume,
          DispatchDeliverAccessorResult(property_resume),
        ),
      ),
    ),
  )
  let property_ticket = match property_decision {
    DispatchPerform(ticket, DispatchRunProduction(DispatchPropertyExecute(_))) =>
      ticket
    _ => fail("expected property work")
  }
  let runtime_error : Error = @errors.InternalError(message="property failed")
  let (restoring, restore_decision) = reduce_activation_dispatch(
    running_property,
    DispatchEffectCompleted(
      property_ticket,
      DispatchWorkCompleted(DispatchRuntimeAbrupt(runtime_error)),
    ),
  )
  let restore_ticket = match restore_decision {
    DispatchPerform(
      ticket,
      DispatchRestorePropertyScope(
        found,
        DispatchRuntimeAbrupt(completion_error)
      )
    ) => {
      inspect(found.id, content=(id + 2).to_string())
      inspect(physical_equal(completion_error, runtime_error), content="true")
      ticket
    }
    _ => fail("abrupt property completion must restore scope first")
  }
  let (releasing, release_decision) = reduce_activation_dispatch(
    restoring,
    DispatchEffectCompleted(restore_ticket, DispatchCleanupCompleted),
  )
  let release_ticket = match release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(_, DispatchRuntimeAbrupt(found))
    ) => {
      inspect(physical_equal(found, runtime_error), content="true")
      ticket
    }
    _ => fail("activation release must follow property restoration")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(DispatchRuntimeAbrupt(found)) =>
      inspect(physical_equal(found, runtime_error), content="true")
    _ => fail("expected abrupt property completion")
  }
}

///|
fn run_escaped_function_control(
  id : Int,
  escaped : DispatchCompletion,
  normalized_error : Error,
) -> (String, String) raise {
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let (running_try, try_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendProtected(
          dispatch_test_statement_work(id + 3),
          Some(dispatch_test_catch_resume(id + 4)),
          None,
        ),
      ),
    ),
  )
  let try_ticket = match try_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected parent protected work")
  }
  let (waiting_child, entry_decision) = reduce_activation_dispatch(
    running_try,
    DispatchEffectCompleted(
      try_ticket,
      DispatchWorkSuspended(
        DispatchSuspendCall(
          dispatch_test_call_work(id + 5),
          DispatchDeliverCallResult,
        ),
      ),
    ),
  )
  let entry_ticket = match entry_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected child activation entry")
  }
  let child_cleanup = DispatchActivationCleanup(id + 6)
  let (running_child, child_decision) = reduce_activation_dispatch(
    waiting_child,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchCallAccepted(
        child_cleanup,
        DispatchCallBody(dispatch_test_statement_work(id + 7)),
      ),
    ),
  )
  let child_ticket = match child_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected child activation work")
  }
  let (normalizing, normalize_decision) = reduce_activation_dispatch(
    running_child,
    DispatchEffectCompleted(child_ticket, DispatchWorkCompleted(escaped)),
  )
  let (normalize_ticket, escaped_tag) = match normalize_decision {
    DispatchPerform(ticket, DispatchNormalizeEscapedControl(completion)) =>
      (ticket, dispatch_completion_tag(completion))
    _ => fail("expected escaped-control normalization before release")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      normalizing,
      DispatchEffectCompleted(normalize_ticket, DispatchCleanupCompleted),
    )
  })
  let (releasing_child, child_release_decision) = reduce_activation_dispatch(
    normalizing,
    DispatchEffectCompleted(
      normalize_ticket,
      DispatchEscapedControlNormalized(normalized_error),
    ),
  )
  let child_release_ticket = match child_release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(found, DispatchThrow(error))
    ) => {
      inspect(found.id, content=(id + 6).to_string())
      inspect(physical_equal(error, normalized_error), content="true")
      ticket
    }
    _ => fail("expected child release after normalization")
  }
  let (running_catch, catch_decision) = reduce_activation_dispatch(
    releasing_child,
    DispatchEffectCompleted(child_release_ticket, DispatchCleanupCompleted),
  )
  let catch_ticket = match catch_decision {
    DispatchPerform(
      ticket,
      DispatchRun(DispatchExecuteCatch(catch_state, caught))
    ) => {
      inspect(
        dispatch_test_work_label(catch_state.body),
        content=(id + 4).to_string(),
      )
      inspect(physical_equal(caught, normalized_error), content="true")
      ticket
    }
    _ => fail("expected parent catch after normalized child control")
  }
  let (releasing_root, root_release_decision) = reduce_activation_dispatch(
    running_catch,
    DispatchEffectCompleted(
      catch_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(8.0))),
    ),
  )
  let root_release_ticket = match root_release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(_, completion)) => {
      inspect(dispatch_completion_tag(completion), content="normal:8")
      ticket
    }
    _ => fail("expected parent release after catch")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing_root,
    DispatchEffectCompleted(root_release_ticket, DispatchCleanupCompleted),
  )
  let final_tag = match finish_decision {
    DispatchFinish(completion) => dispatch_completion_tag(completion)
    _ => fail("expected normalized final completion")
  }
  (escaped_tag, final_tag)
}

///|
test "function break and continue normalize before cleanup release" {
  let break_trace = run_escaped_function_control(
    1300,
    DispatchBreak(Some(Number(1.0)), Some("L")),
    @errors.SyntaxError(message="break SyntaxError"),
  )
  let continue_trace = run_escaped_function_control(
    1400,
    DispatchContinue(Some(Number(2.0)), None),
    @errors.SyntaxError(message="continue SyntaxError"),
  )
  json_inspect(
    [break_trace.0, break_trace.1, continue_trace.0, continue_trace.1],
    content=["break:1:L", "normal:8", "continue:2:none", "normal:8"],
  )
}

///|
fn run_growing_dispatch_ticket(cursor : String) -> Array[String] raise {
  let initial : ActivationDispatchState = {
    frames: DispatchFrameStackEmpty,
    phase: DispatchReady,
    ticket_cursor: DispatchTicket(value=cursor),
  }
  let (waiting_entry, entry_decision) = reduce_activation_dispatch(
    initial,
    DispatchStart(dispatch_test_program_request(1500)),
  )
  let entry_ticket = match entry_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected activation entry at large ticket")
  }
  let (running, run_decision) = reduce_activation_dispatch(
    waiting_entry,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchProgramAccepted(DispatchActivationCleanup(1501)),
    ),
  )
  let run_ticket = match run_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected activation work after ticket growth")
  }
  let (releasing, release_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      run_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let release_ticket = match release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(_, _)) => ticket
    _ => fail("expected release after ticket growth")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  guard finish_decision is DispatchFinish(_) else {
    fail("expected completion after ticket growth")
  }
  [entry_ticket.value, run_ticket.value, release_ticket.value]
}

///|
test "dispatch tickets grow without reuse or stranded cleanup" {
  let portable_int_boundary = run_growing_dispatch_ticket("2147483647")
  let arbitrary_precision_boundary = run_growing_dispatch_ticket(
    "99999999999999999999",
  )
  json_inspect([portable_int_boundary, arbitrary_precision_boundary], content=[
    ["2147483647", "2147483648", "2147483649"],
    ["99999999999999999999", "100000000000000000000", "100000000000000000001"],
  ])
}

///|
test "statement cursor advances once and declarations preserve the last value" {
  let loc = @token.Loc::default()
  let ctx : ExecContext = { strict: false, current_generator: None }
  let sequential = DispatchStatementCursor(
    ctx~,
    stmts=[
      @ast.BreakStmt(Some("first"), loc),
      @ast.BreakStmt(Some("second"), loc),
    ],
    env=Environment::new(),
    index=0,
    last_value=Number(1.0),
  )
  let initial_frames = DispatchFrameStackNode(
    DispatchActivationFrame(DispatchActivationCleanup(1901), DispatchRootExit),
    DispatchFrameStackEmpty,
  )
  let (running_first, first_decision) = begin_dispatch_statements(
    dispatch_test_ready_state(initial_frames),
    sequential,
  )
  let first_ticket = match first_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(step))) => {
      inspect(step.index, content="0")
      inspect(dispatch_test_step_label(step), content="first")
      ticket
    }
    _ => fail("expected first statement step")
  }
  let (running_second, second_decision) = reduce_activation_dispatch(
    running_first,
    DispatchEffectCompleted(
      first_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(5.0))),
    ),
  )
  let second_ticket = match second_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(step))) => {
      inspect(step.index, content="1")
      inspect(dispatch_test_step_label(step), content="second")
      ticket
    }
    _ => fail("expected second statement exactly once")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      running_second,
      DispatchEffectCompleted(
        first_ticket,
        DispatchWorkCompleted(DispatchNormal(Number(99.0))),
      ),
    )
  })
  let (_, sequential_release) = reduce_activation_dispatch(
    running_second,
    DispatchEffectCompleted(
      second_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(6.0))),
    ),
  )
  match sequential_release {
    DispatchPerform(
      _,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => inspect(value, content="6")
    _ => fail("expected statement cursor completion")
  }
  let declaration = DispatchStatementCursor(
    ctx~,
    stmts=[@ast.VarDecl(@ast.VarKind::LetKind, "x", None, loc)],
    env=Environment::new(),
    index=0,
    last_value=Number(4.0),
  )
  let (running_declaration, declaration_decision) = begin_dispatch_statements(
    dispatch_test_ready_state(initial_frames),
    declaration,
  )
  let declaration_ticket = match declaration_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected declaration statement")
  }
  let (_, declaration_release) = reduce_activation_dispatch(
    running_declaration,
    DispatchEffectCompleted(
      declaration_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(9.0))),
    ),
  )
  match declaration_release {
    DispatchPerform(
      _,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => inspect(value, content="4")
    _ => fail("declaration completion must preserve the previous value")
  }
}

///|
test "finally routes break and continue through structural control frames" {
  let activation = DispatchActivationFrame(
    DispatchActivationCleanup(2001),
    DispatchRootExit,
  )
  let outer_resume = dispatch_test_statement_resume(
    2002,
    last_value=Number(1.0),
  )
  let body_resume = dispatch_test_statement_resume(2003, last_value=Number(3.0))
  let loop_state = dispatch_test_loop_resume(2004, Some("loop"))
  let continue_frames = DispatchFrameStackNode(
    DispatchSavedCompletionFrame(DispatchContinue(None, Some("loop"))),
    DispatchFrameStackNode(
      DispatchStatementFrame(body_resume),
      DispatchFrameStackNode(
        DispatchLoopFrame(loop_state),
        DispatchFrameStackNode(
          DispatchStatementFrame(outer_resume),
          DispatchFrameStackNode(activation, DispatchFrameStackEmpty),
        ),
      ),
    ),
  )
  let (advancing_loop, continue_decision) = route_dispatch_completion(
    dispatch_test_ready_state(continue_frames),
    DispatchNormal(Undefined),
  )
  let advance_ticket = match continue_decision {
    DispatchPerform(ticket, DispatchRun(DispatchAdvanceLoop(found))) => {
      inspect(dispatch_test_value_tag(found.completion), content="3")
      ticket
    }
    _ => fail("matching continue must advance the loop after finally")
  }
  let (_, continue_release) = reduce_activation_dispatch(
    advancing_loop,
    DispatchEffectCompleted(
      advance_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(4.0))),
    ),
  )
  match continue_release {
    DispatchPerform(
      _,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => inspect(value, content="4")
    _ => fail("activation release must wait for loop advancement")
  }
  let break_frames = DispatchFrameStackNode(
    DispatchSavedCompletionFrame(DispatchBreak(None, Some("loop"))),
    DispatchFrameStackNode(
      DispatchStatementFrame(body_resume),
      DispatchFrameStackNode(
        DispatchLoopFrame(loop_state),
        DispatchFrameStackNode(
          DispatchStatementFrame(outer_resume),
          DispatchFrameStackNode(activation, DispatchFrameStackEmpty),
        ),
      ),
    ),
  )
  let (_, break_decision) = route_dispatch_completion(
    dispatch_test_ready_state(break_frames),
    DispatchNormal(Undefined),
  )
  match break_decision {
    DispatchPerform(
      _,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => inspect(value, content="3")
    _ => fail("matching break must exit the loop after finally")
  }
  let abrupt_frames = DispatchFrameStackNode(
    DispatchSavedCompletionFrame(DispatchContinue(None, Some("loop"))),
    DispatchFrameStackNode(
      DispatchStatementFrame(body_resume),
      DispatchFrameStackNode(
        DispatchLoopFrame(loop_state),
        DispatchFrameStackNode(activation, DispatchFrameStackEmpty),
      ),
    ),
  )
  let (_, abrupt_decision) = route_dispatch_completion(
    dispatch_test_ready_state(abrupt_frames),
    DispatchThrow(JsException(String_("finally failed"))),
  )
  match abrupt_decision {
    DispatchPerform(_, DispatchReleaseActivation(_, DispatchThrow(error))) =>
      inspect(
        dispatch_test_value_tag(dispatch_test_js_exception_value(error)),
        content="finally failed",
      )
    _ => fail("abrupt finally must bypass loop control consumption")
  }
  let mismatched_frames = DispatchFrameStackNode(
    DispatchStatementFrame(body_resume),
    DispatchFrameStackNode(
      DispatchLoopFrame(loop_state),
      DispatchFrameStackNode(activation, DispatchFrameStackEmpty),
    ),
  )
  let (_, mismatched_break_decision) = route_dispatch_completion(
    dispatch_test_ready_state(mismatched_frames),
    DispatchBreak(None, Some("other")),
  )
  match mismatched_break_decision {
    DispatchPerform(
      _,
      DispatchReleaseActivation(
        _,
        DispatchBreak(Some(Number(value)), Some(label))
      )
    ) => {
      inspect(value, content="3")
      inspect(label, content="other")
    }
    _ => fail("loop must propagate a non-matching labelled break")
  }
  let (_, mismatched_continue_decision) = route_dispatch_completion(
    dispatch_test_ready_state(mismatched_frames),
    DispatchContinue(None, Some("other")),
  )
  match mismatched_continue_decision {
    DispatchPerform(
      _,
      DispatchReleaseActivation(
        _,
        DispatchContinue(Some(Number(value)), Some(label))
      )
    ) => {
      inspect(value, content="3")
      inspect(label, content="other")
    }
    _ => fail("loop must propagate a non-matching labelled continue")
  }
}

///|
fn run_structural_statement_suspension(
  id : Int,
  suspension : DispatchSuspension,
  body_completion : DispatchCompletion,
) -> DispatchCompletion raise {
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let (running_body, body_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(root_ticket, DispatchWorkSuspended(suspension)),
  )
  let body_ticket = match body_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected structural body statement")
  }
  let (releasing, release_decision) = reduce_activation_dispatch(
    running_body,
    DispatchEffectCompleted(body_ticket, DispatchWorkCompleted(body_completion)),
  )
  let (release_ticket, released) = match release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(_, completion)) =>
      (ticket, completion)
    _ => fail("expected structural statement release")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(_) => released
    _ => fail("expected structural statement completion")
  }
}

///|
test "structural suspensions install loop switch and label frames" {
  let loc = @token.Loc::default()
  let ctx : ExecContext = { strict: false, current_generator: None }
  let switch_body = DispatchStatementCursor(
    ctx~,
    stmts=[@ast.BreakStmt(None, loc)],
    env=Environment::new(),
    last_value=Number(7.0),
  )
  let switch_result = run_structural_statement_suspension(
    2050,
    DispatchSuspendSwitch(Number(7.0), switch_body),
    DispatchBreak(None, None),
  )
  expect_dispatch_number(switch_result, 7.0)
  let label_body = DispatchStatementCursor(
    ctx~,
    stmts=[@ast.BreakStmt(Some("outer"), loc)],
    env=Environment::new(),
    last_value=Number(8.0),
  )
  let label_result = run_structural_statement_suspension(
    2060,
    DispatchSuspendLabel("outer", label_body),
    DispatchBreak(None, Some("outer")),
  )
  expect_dispatch_number(label_result, 8.0)
  let loop_vars = ["item"]
  let for_loop = DispatchForLoopState(
    condition=None,
    update=None,
    body=@ast.ContinueStmt(None, loc),
    outer_env=Environment::new(),
    for_env=Environment::new(),
    loop_vars~,
  )
  let loop_state = DispatchLoopResume(
    kind=DispatchForLoop(for_loop),
    ctx~,
    label=None,
    completion=Number(1.0),
  )
  let loop_body = DispatchStatementCursor(
    ctx~,
    stmts=[@ast.ContinueStmt(None, loc)],
    env=Environment::new(),
    last_value=Number(2.0),
  )
  let (running_root, root_ticket) = start_accepted_dispatch_root(2070)
  let (running_loop, loop_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(DispatchSuspendLoopIteration(loop_state, loop_body)),
    ),
  )
  let loop_ticket = match loop_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected loop body statement")
  }
  for_loop.loop_vars.clear()
  let (advancing_loop, advance_decision) = reduce_activation_dispatch(
    running_loop,
    DispatchEffectCompleted(
      loop_ticket,
      DispatchWorkCompleted(DispatchContinue(None, None)),
    ),
  )
  let advance_ticket = match advance_decision {
    DispatchPerform(ticket, DispatchRun(DispatchAdvanceLoop(found))) => {
      inspect(dispatch_test_value_tag(found.completion), content="2")
      match found.kind {
        DispatchForLoop(owned) => {
          inspect(owned.loop_vars.length(), content="1")
          inspect(owned.loop_vars[0], content="item")
        }
        _ => fail("expected retained for-loop state")
      }
      ticket
    }
    _ => fail("matching continue must advance the installed loop")
  }
  let (releasing, release_decision) = reduce_activation_dispatch(
    advancing_loop,
    DispatchEffectCompleted(
      advance_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(4.0))),
    ),
  )
  let release_ticket = match release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => {
      inspect(value, content="4")
      ticket
    }
    _ => fail("expected release after loop advancement")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  guard finish_decision is DispatchFinish(DispatchNormal(Number(4.0))) else {
    fail("expected completed loop suspension")
  }
}

///|
test "switch and label frames consume only their matching break" {
  let activation = DispatchActivationFrame(
    DispatchActivationCleanup(2101),
    DispatchRootExit,
  )
  let switch_frames = DispatchFrameStackNode(
    DispatchSwitchFrame(Number(7.0)),
    DispatchFrameStackNode(activation, DispatchFrameStackEmpty),
  )
  let (_, switch_decision) = route_dispatch_completion(
    dispatch_test_ready_state(switch_frames),
    DispatchBreak(None, None),
  )
  match switch_decision {
    DispatchPerform(
      _,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => inspect(value, content="7")
    _ => fail("switch must consume only unlabelled break")
  }
  let switch_body_frames = DispatchFrameStackNode(
    DispatchStatementFrame(
      dispatch_test_statement_resume(2102, last_value=Number(7.0)),
    ),
    DispatchFrameStackNode(
      DispatchSwitchFrame(Number(7.0)),
      DispatchFrameStackNode(activation, DispatchFrameStackEmpty),
    ),
  )
  let (_, labelled_switch_break) = route_dispatch_completion(
    dispatch_test_ready_state(switch_body_frames),
    DispatchBreak(None, Some("outer")),
  )
  match labelled_switch_break {
    DispatchPerform(
      _,
      DispatchReleaseActivation(
        _,
        DispatchBreak(Some(Number(value)), Some(label))
      )
    ) => {
      inspect(value, content="7")
      inspect(label, content="outer")
    }
    _ => fail("switch must propagate labelled break after UpdateEmpty")
  }
  let (_, labelled_switch_continue) = route_dispatch_completion(
    dispatch_test_ready_state(switch_body_frames),
    DispatchContinue(None, Some("outer")),
  )
  match labelled_switch_continue {
    DispatchPerform(
      _,
      DispatchReleaseActivation(
        _,
        DispatchContinue(Some(Number(value)), Some(label))
      )
    ) => {
      inspect(value, content="7")
      inspect(label, content="outer")
    }
    _ => fail("switch must propagate labelled continue after UpdateEmpty")
  }
  let label_frames = DispatchFrameStackNode(
    DispatchLabelFrame("outer"),
    DispatchFrameStackNode(activation, DispatchFrameStackEmpty),
  )
  let (_, label_decision) = route_dispatch_completion(
    dispatch_test_ready_state(label_frames),
    DispatchBreak(Some(Number(8.0)), Some("outer")),
  )
  match label_decision {
    DispatchPerform(
      _,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => inspect(value, content="8")
    _ => fail("label must consume its matching break")
  }
  let (_, mismatch_decision) = route_dispatch_completion(
    dispatch_test_ready_state(label_frames),
    DispatchBreak(Some(Number(9.0)), Some("other")),
  )
  match mismatch_decision {
    DispatchPerform(
      _,
      DispatchReleaseActivation(
        _,
        DispatchBreak(Some(Number(value)), Some(label))
      )
    ) => {
      inspect(value, content="9")
      inspect(label, content="other")
    }
    _ => fail("label must propagate a non-matching break")
  }
}

///|
test "semantic payload constructors defensively copy mutable arrays" {
  let ctx : ExecContext = { strict: false, current_generator: None }
  let stmts = [@ast.BreakStmt(Some("original"), @token.Loc::default())]
  let statement_work = DispatchStatementCursor(
    ctx~,
    stmts~,
    env=Environment::new(),
  )
  stmts.clear()
  inspect(dispatch_test_work_label(statement_work), content="original")
  let args = [Number(1.0)]
  let call = DispatchCallRequest(
    callee=Undefined,
    this_value=Undefined,
    args~,
    loc=@token.Loc::default(),
  )
  args.clear()
  inspect(call.args.length(), content="1")
  let params : Array[@ast.Param] = []
  let parameter_args = [Number(2.0)]
  let body : Array[@ast.Stmt] = []
  let parameter_resume = DispatchParameterDefaultResume(
    params~,
    next_index=0,
    effective_param_count=0,
    args=parameter_args,
    rest_param=Some("rest"),
    is_arrow=false,
    env=Environment::new(),
    ctx~,
    body~,
  )
  params.push({
    name: "later",
    default_val: None,
    pattern: None,
    is_rest_pattern: false,
  })
  parameter_args.clear()
  body.push(@ast.BreakStmt(None, @token.Loc::default()))
  inspect(parameter_resume.params.length(), content="0")
  inspect(parameter_resume.args.length(), content="1")
  inspect(parameter_resume.body.length(), content="0")
  let loop_vars = ["item"]
  let for_loop = DispatchForLoopState(
    condition=None,
    update=None,
    body=@ast.BreakStmt(None, @token.Loc::default()),
    outer_env=Environment::new(),
    for_env=Environment::new(),
    loop_vars~,
  )
  loop_vars.clear()
  let loop_state = DispatchLoopResume(
    kind=DispatchForLoop(for_loop),
    ctx~,
    label=None,
    completion=Undefined,
  )
  match loop_state.kind {
    DispatchForLoop(found) => {
      inspect(found.loop_vars.length(), content="1")
      inspect(found.loop_vars[0], content="item")
    }
    _ => fail("expected copied for-loop state")
  }
}

///|
fn request_test_continuation_resume(
  id : Int,
  continuation : DispatchContinuation,
  value : Value,
) -> DispatchEffect raise {
  let (running, root_ticket) = start_accepted_dispatch_root(id)
  let (running_value, value_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendContinue(
          continuation,
          DispatchExecuteStatement(dispatch_test_statement_step(id + 3)),
        ),
      ),
    ),
  )
  let value_ticket = match value_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(_))) => ticket
    _ => fail("expected continuation input work")
  }
  let (_, resume_decision) = reduce_activation_dispatch(
    running_value,
    DispatchEffectCompleted(
      value_ticket,
      DispatchWorkCompleted(DispatchNormal(value)),
    ),
  )
  match resume_decision {
    DispatchPerform(_, effect) => effect
    _ => fail("expected semantic continuation resume work")
  }
}

///|
fn request_test_production_continuation_resume(
  id : Int,
  continuation : DispatchContinuation,
  work : DispatchProductionWork,
  value : Value,
) -> DispatchEffect raise {
  let (running, root_ticket) = start_accepted_dispatch_root(id)
  let (running_value, value_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendContinueProduction(continuation, work),
      ),
    ),
  )
  let value_ticket = match value_decision {
    DispatchPerform(ticket, DispatchRunProduction(_)) => ticket
    _ => fail("expected production continuation input work")
  }
  let (_, resume_decision) = reduce_activation_dispatch(
    running_value,
    DispatchEffectCompleted(
      value_ticket,
      DispatchWorkCompleted(DispatchNormal(value)),
    ),
  )
  match resume_decision {
    DispatchPerform(_, effect) => effect
    _ => fail("expected production continuation resume work")
  }
}

///|
test "binary accessor and parameter continuations retain semantic payloads" {
  let binary = DispatchBinaryResume(
    op=@ast.Add,
    left=Number(1.0),
    loc=@token.Loc::default(),
  )
  match
    request_test_continuation_resume(
      1600,
      DispatchApplyBinaryRight(binary),
      Number(2.0),
    ) {
    DispatchRun(
      DispatchResumeContinuation(DispatchApplyBinaryRight(found), Number(right))
    ) => {
      inspect(found.op == @ast.Add, content="true")
      inspect(dispatch_test_value_tag(found.left), content="1")
      inspect(right, content="2")
    }
    _ => fail("expected binary semantic resume")
  }
  let property_binary = DispatchBinaryResume(
    op=@ast.Add,
    left=Number(3.0),
    loc=@token.Loc::default(),
  )
  match
    request_test_production_continuation_resume(
      1750,
      DispatchApplyPropertyBinaryRight(property_binary),
      DispatchPropertyDeliverAccessorResult(
        dispatch_test_property_resume(1751),
        Number(4.0),
      ),
      Number(4.0),
    ) {
    DispatchRunProduction(
      DispatchPropertyApplyBinaryRight(found, Number(right))
    ) => {
      inspect(found.op == @ast.Add, content="true")
      inspect(dispatch_test_value_tag(found.left), content="3")
      inspect(right, content="4")
    }
    _ => fail("expected property continuation in production seam")
  }
  let accessor = dispatch_test_property_resume(1700)
  match
    request_test_continuation_resume(
      1700,
      DispatchDeliverAccessorResult(accessor),
      Number(3.0),
    ) {
    DispatchRunProduction(
      DispatchPropertyDeliverAccessorResult(found, Number(value))
    ) => {
      inspect(
        dispatch_test_property_key(found.property_key),
        content="key:1700",
      )
      inspect(value, content="3")
    }
    _ => fail("expected accessor semantic resume")
  }
  let parameter = DispatchParameterDefaultResume(
    params=[],
    next_index=4,
    effective_param_count=3,
    args=[Number(1.0), Number(2.0), Number(3.0)],
    rest_param=Some("remaining"),
    is_arrow=true,
    env=Environment::new(),
    ctx={ strict: true, current_generator: None },
    body=[],
  )
  match
    request_test_continuation_resume(
      1800,
      DispatchBindParameterDefault(parameter),
      Number(4.0),
    ) {
    DispatchRun(
      DispatchResumeContinuation(
        DispatchBindParameterDefault(found),
        Number(value)
      )
    ) => {
      inspect(found.next_index, content="4")
      inspect(found.effective_param_count, content="3")
      inspect(found.args.length(), content="3")
      match found.rest_param {
        Some(name) => inspect(name, content="remaining")
        None => fail("expected retained rest parameter")
      }
      inspect(found.is_arrow, content="true")
      inspect(found.ctx.strict, content="true")
      inspect(value, content="4")
    }
    _ => fail("expected parameter-default semantic resume")
  }
}

///|
test "property work enters the production seam" {
  let id = 1900
  let (running_root, root_ticket) = start_accepted_dispatch_root(id)
  let property_cleanup = DispatchPropertyCleanup(id + 1)
  let property_work = dispatch_test_property_resume(id + 2)
  let (_, property_decision) = reduce_activation_dispatch(
    running_root,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendProperty(
          property_cleanup,
          property_work,
          DispatchDeliverAccessorResult(property_work),
        ),
      ),
    ),
  )
  let production = match property_decision {
    DispatchPerform(_, DispatchRunProduction(_)) => true
    DispatchPerform(_, DispatchRun(_)) => false
    _ => false
  }
  inspect(production, content="true")
}
