///|
fn numeric_routing_test_plan() -> NumericRecursionPlan raise {
  let stmts = @parser.parse(
      "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
    ).stmts
  match classify_numeric_recursion_program(stmts) {
    Some(plan) => plan
    None => fail("expected the exact numeric-recursion plan")
  }
}

///|
fn numeric_routing_test_mutual_plan() -> NumericRecursionPlan raise {
  let stmts = @parser.parse(
      "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
      "function g(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
    ).stmts
  match classify_numeric_recursion_program(stmts) {
    Some(plan) => plan
    None => fail("expected the exact mutual numeric-recursion plan")
  }
}

///|
#warnings("-unused_value")
fn numeric_routing_test_protected_plan() -> NumericRecursionPlan raise {
  let stmts = @parser.parse(
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{throw f(256);}catch(e){throw e;}finally{throw 7;}",
    ).stmts
  match classify_numeric_recursion_program(stmts) {
    Some(plan) => plan
    None => fail("expected the exact protected numeric-recursion plan")
  }
}

///|
fn numeric_routing_test_call_start(
  plan : NumericRecursionPlan,
  id : Int,
) -> DispatchNumericCallStart {
  DispatchNumericCallStart(
    parameter=DispatchParameterBindingToken(id~),
    recursive_callee=DispatchCalleeCaptureToken(id~),
    recipe=plan.entry.expression_recipe,
  )
}

///|
fn numeric_routing_test_base_condition_state(
  start : DispatchNumericCallStart,
  cleanup : DispatchActivationCleanup,
) -> ActivationDispatchState {
  dispatch_test_ready_state(
    DispatchFrameStackNode(
      DispatchContinuationFrame(
        DispatchContinueNumericExpression(
          DispatchAfterNumericBaseCondition(start),
        ),
      ),
      DispatchFrameStackNode(
        DispatchActivationFrame(cleanup, DispatchFunctionExit),
        DispatchFrameStackEmpty,
      ),
    ),
  )
}

///|
test "numeric routing root observes statements before the admitted call" {
  let plan = numeric_routing_test_plan()
  let initial = ActivationDispatchState::ActivationDispatchState()
  let (waiting, enter_decision) = reduce_activation_dispatch(
    initial,
    DispatchStart(dispatch_test_program_request(2700)),
  )
  let entry_ticket = match enter_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected numeric root entry")
  }
  let start = numeric_recursion_program_dispatch_start(
    plan,
    DispatchCalleeCaptureToken(id=2701),
  )
  let (after_declaration, declaration_decision) = reduce_activation_dispatch(
    waiting,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchNumericProgramAccepted(DispatchActivationCleanup(2701), start),
    ),
  )
  let declaration_ticket = match declaration_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveStatementStep(
          DispatchNumericObserveRootDeclaration(index)
        )
      )
    ) => {
      inspect(index, content="0")
      ticket
    }
    _ => fail("expected the root declaration observation")
  }
  let (after_root_statement, root_statement_decision) = reduce_activation_dispatch(
    after_declaration,
    DispatchEffectCompleted(
      declaration_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let root_statement_ticket = match root_statement_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveStatementStep(
          DispatchNumericObserveRootExpressionStatement
        )
      )
    ) => ticket
    _ => fail("expected the root expression-statement observation")
  }
  let (_, call_decision) = reduce_activation_dispatch(
    after_root_statement,
    DispatchEffectCompleted(
      root_statement_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  match call_decision {
    DispatchPerform(
      _,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveCall(loc))
      )
    ) => inspect(loc == plan.root_call_loc, content="true")
    _ => fail("expected the admitted root call observation")
  }
}

///|
test "numeric routing installs protected frames only after the root try observation" {
  let plan = numeric_routing_test_protected_plan()
  let initial = ActivationDispatchState::ActivationDispatchState()
  let (waiting, enter_decision) = reduce_activation_dispatch(
    initial,
    DispatchStart(dispatch_test_program_request(2720)),
  )
  let entry_ticket = match enter_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected protected numeric root entry")
  }
  let start = numeric_recursion_program_dispatch_start(
    plan,
    DispatchCalleeCaptureToken(id=2721),
  )
  let (observing_declaration, declaration_decision) = reduce_activation_dispatch(
    waiting,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchNumericProgramAccepted(DispatchActivationCleanup(2721), start),
    ),
  )
  let declaration_ticket = match declaration_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveStatementStep(DispatchNumericObserveRootDeclaration(0))
      )
    ) => ticket
    _ => fail("expected protected root declaration observation")
  }
  let (observing_try, try_decision) = reduce_activation_dispatch(
    observing_declaration,
    DispatchEffectCompleted(
      declaration_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let try_ticket = match try_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveStatementStep(DispatchNumericObserveRootTryStatement)
      )
    ) => ticket
    _ => fail("expected the outer TryCatchStmt observation")
  }
  match observing_try.frames {
    DispatchFrameStackNode(
      DispatchContinuationFrame(
        DispatchContinueNumericStatement(
          DispatchAfterNumericRootTryStatement(_)
        )
      ),
      DispatchFrameStackNode(
        DispatchActivationFrame(_, DispatchRootExit),
        DispatchFrameStackEmpty
      )
    ) => ()
    _ => fail("catch/finally frames must not precede the root try observation")
  }
  let (observing_inner, inner_decision) = reduce_activation_dispatch(
    observing_try,
    DispatchEffectCompleted(
      try_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  match inner_decision {
    DispatchPerform(
      _,
      DispatchRun(
        DispatchObserveStatementStep(
          DispatchNumericObserveProtectedStatement(
            DispatchNumericTryBody,
            DispatchNumericThrowStatement
          )
        )
      )
    ) => ()
    _ => fail("expected the protected ThrowStmt observation")
  }
  match observing_inner.frames {
    DispatchFrameStackNode(
      DispatchContinuationFrame(
        DispatchContinueNumericStatement(
          DispatchAfterNumericProtectedStatement(_)
        )
      ),
      DispatchFrameStackNode(
        DispatchNumericCatchFrame(_),
        DispatchFrameStackNode(
          DispatchNumericFinallyFrame(_),
          DispatchFrameStackNode(
            DispatchActivationFrame(_, DispatchRootExit),
            DispatchFrameStackEmpty
          )
        )
      )
    ) => ()
    _ => fail("protected frames must be installed before the inner statement")
  }
}

///|
test "numeric routing catch rethrow is replaced by an abrupt finalizer" {
  let plan = numeric_routing_test_protected_plan()
  let recipe = match plan.root_control {
    NumericRecursionProtectedRoot(found) => found
    _ => fail("expected a protected root recipe")
  }
  let token = DispatchNumericCatchBindingToken(id=2730)
  let catch_state = match recipe.catch_recipe {
    NumericRecursionCatch(parameter, body) =>
      DispatchNumericCatchResume(token~, parameter~, body~)
    _ => fail("expected a catch recipe")
  }
  let finalizer_body = match recipe.finalizer_recipe {
    NumericRecursionFinalizer(body) => body
    _ => fail("expected a finalizer recipe")
  }
  let initial = dispatch_test_ready_state(
    DispatchFrameStackNode(
      DispatchNumericCatchFrame(catch_state),
      DispatchFrameStackNode(
        DispatchNumericFinallyFrame(finalizer_body),
        DispatchFrameStackNode(
          DispatchActivationFrame(
            DispatchActivationCleanup(2730),
            DispatchRootExit,
          ),
          DispatchFrameStackEmpty,
        ),
      ),
    ),
  )
  let (entering_catch, catch_decision) = route_dispatch_completion(
    initial,
    DispatchThrow(JsException(Number(256.0))),
  )
  let catch_ticket = match catch_decision {
    DispatchPerform(
      ticket,
      DispatchRun(DispatchEnterNumericCatch(found, JsException(Number(value))))
    ) => {
      inspect(found.token.id, content="2730")
      inspect(value, content="256")
      ticket
    }
    _ => fail("expected numeric catch entry")
  }
  let (observing_catch, catch_statement_decision) = reduce_activation_dispatch(
    entering_catch,
    DispatchEffectCompleted(
      catch_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let catch_statement_ticket = match catch_statement_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveStatementStep(
          DispatchNumericObserveProtectedStatement(
            DispatchNumericCatchBody,
            DispatchNumericThrowStatement
          )
        )
      )
    ) => ticket
    _ => fail("expected catch ThrowStmt observation")
  }
  let (observing_binding, binding_observation_decision) = reduce_activation_dispatch(
    observing_catch,
    DispatchEffectCompleted(
      catch_statement_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let binding_observation_ticket = match binding_observation_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveCatchBinding(found))
      )
    ) => {
      inspect(found.id, content="2730")
      ticket
    }
    _ => fail("expected catch binding observation")
  }
  let (reading_binding, binding_read_decision) = reduce_activation_dispatch(
    observing_binding,
    DispatchEffectCompleted(
      binding_observation_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let binding_read_ticket = match binding_read_decision {
    DispatchPerform(ticket, DispatchRun(DispatchReadNumericCatchBinding(found))) => {
      inspect(found.id, content="2730")
      ticket
    }
    _ => fail("expected catch binding read")
  }
  let (observing_finalizer, finalizer_statement_decision) = reduce_activation_dispatch(
    reading_binding,
    DispatchEffectCompleted(
      binding_read_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(256.0))),
    ),
  )
  let finalizer_statement_ticket = match finalizer_statement_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveStatementStep(
          DispatchNumericObserveProtectedStatement(
            DispatchNumericFinalizerBody,
            DispatchNumericThrowStatement
          )
        )
      )
    ) => ticket
    _ => fail("expected finalizer ThrowStmt observation")
  }
  let (observing_finalizer_value, finalizer_value_decision) = reduce_activation_dispatch(
    observing_finalizer,
    DispatchEffectCompleted(
      finalizer_statement_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let finalizer_value_ticket = match finalizer_value_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveNumber(value))
      )
    ) => {
      inspect(value, content="7")
      ticket
    }
    _ => fail("expected finalizer number observation")
  }
  let (releasing, release_decision) = reduce_activation_dispatch(
    observing_finalizer_value,
    DispatchEffectCompleted(
      finalizer_value_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let release_ticket = match release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(
        cleanup,
        DispatchThrow(JsException(Number(value)))
      )
    ) => {
      inspect(cleanup.id, content="2730")
      inspect(value, content="7")
      ticket
    }
    _ => fail("abrupt finalizer must replace the catch rethrow")
  }
  let (_, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(DispatchThrow(JsException(Number(value)))) =>
      inspect(value, content="7")
    _ => fail("expected the replacement throw to finish")
  }
}

///|
test "numeric routing runtime abrupt skips catch and crosses a normal finalizer" {
  let token = DispatchNumericCatchBindingToken(id=2740)
  let catch_state = DispatchNumericCatchResume(
    token~,
    parameter=Some("e"),
    body=NumericRecursionClosedBindingValue,
  )
  let initial = dispatch_test_ready_state(
    DispatchFrameStackNode(
      DispatchNumericCatchFrame(catch_state),
      DispatchFrameStackNode(
        DispatchNumericFinallyFrame(NumericRecursionClosedNumberValue(0.0)),
        DispatchFrameStackNode(
          DispatchActivationFrame(
            DispatchActivationCleanup(2740),
            DispatchRootExit,
          ),
          DispatchFrameStackEmpty,
        ),
      ),
    ),
  )
  let failure = ExecutionControlError(ExecutionLimit)
  let (observing_finalizer, statement_decision) = route_dispatch_completion(
    initial,
    DispatchRuntimeAbrupt(failure),
  )
  let statement_ticket = match statement_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveStatementStep(
          DispatchNumericObserveProtectedStatement(
            DispatchNumericFinalizerBody,
            DispatchNumericExpressionStatement
          )
        )
      )
    ) => ticket
    _ => fail("runtime abrupt must skip catch and enter the finalizer")
  }
  let (observing_value, value_decision) = reduce_activation_dispatch(
    observing_finalizer,
    DispatchEffectCompleted(
      statement_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let value_ticket = match value_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveNumber(value))
      )
    ) => {
      inspect(value, content="0")
      ticket
    }
    _ => fail("expected the normal finalizer value observation")
  }
  let (_, release_decision) = reduce_activation_dispatch(
    observing_value,
    DispatchEffectCompleted(
      value_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  match release_decision {
    DispatchPerform(
      _,
      DispatchReleaseActivation(
        cleanup,
        DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit))
      )
    ) => inspect(cleanup.id, content="2740")
    _ => fail("normal finalizer must resume the original runtime abrupt")
  }
}

///|
test "numeric routing mutual root observes both declarations in source order" {
  let plan = numeric_routing_test_mutual_plan()
  let initial = ActivationDispatchState::ActivationDispatchState()
  let (waiting, enter_decision) = reduce_activation_dispatch(
    initial,
    DispatchStart(dispatch_test_program_request(2750)),
  )
  let entry_ticket = match enter_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected numeric root entry")
  }
  let (after_first, first_decision) = reduce_activation_dispatch(
    waiting,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchNumericProgramAccepted(
        DispatchActivationCleanup(2751),
        numeric_recursion_program_dispatch_start(
          plan,
          DispatchCalleeCaptureToken(id=2751),
        ),
      ),
    ),
  )
  let first_ticket = match first_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveStatementStep(
          DispatchNumericObserveRootDeclaration(index)
        )
      )
    ) => {
      inspect(index, content="0")
      ticket
    }
    _ => fail("expected the first declaration observation")
  }
  let (_, second_decision) = reduce_activation_dispatch(
    after_first,
    DispatchEffectCompleted(
      first_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  match second_decision {
    DispatchPerform(
      _,
      DispatchRun(
        DispatchObserveStatementStep(
          DispatchNumericObserveRootDeclaration(index)
        )
      )
    ) => inspect(index, content="1")
    _ => fail("expected the second declaration observation")
  }
}

///|
test "numeric routing call observes IfStmt before its base condition" {
  let plan = numeric_routing_test_plan()
  let start = numeric_routing_test_call_start(plan, 2801)
  let initial = ActivationDispatchState::ActivationDispatchState()
  let (waiting, enter_decision) = reduce_activation_dispatch(
    initial,
    DispatchStart(dispatch_test_call_request(2800)),
  )
  let entry_ticket = match enter_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected numeric call entry")
  }
  let (after_if, if_decision) = reduce_activation_dispatch(
    waiting,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchCallAccepted(
        DispatchActivationCleanup(2801),
        DispatchNumericCall(start),
      ),
    ),
  )
  let if_ticket = match if_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveStatementStep(DispatchNumericObserveIfStatement)
      )
    ) => ticket
    _ => fail("expected the numeric IfStmt observation")
  }
  let (_, condition_decision) = reduce_activation_dispatch(
    after_if,
    DispatchEffectCompleted(
      if_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  match condition_decision {
    DispatchPerform(
      _,
      DispatchRun(
        DispatchObserveExpressionStep(
          DispatchNumericObserveBinary(DispatchNumericStrictEqual, loc)
        )
      )
    ) => inspect(loc == start.recipe.base_condition_loc, content="true")
    _ => fail("expected the numeric base-condition observation")
  }
}

///|
test "numeric routing base condition observes ReturnStmt before its expression" {
  let plan = numeric_routing_test_plan()
  let start = numeric_routing_test_call_start(plan, 2901)
  let cleanup = DispatchActivationCleanup(2901)
  let (base_waiting, base_statement_decision) = route_dispatch_completion(
    numeric_routing_test_base_condition_state(start, cleanup),
    DispatchNormal(Bool(true)),
  )
  let base_statement_ticket = match base_statement_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveStatementStep(DispatchNumericObserveReturnStatement)
      )
    ) => ticket
    _ => fail("expected the base ReturnStmt observation")
  }
  let (_, base_expression_decision) = reduce_activation_dispatch(
    base_waiting,
    DispatchEffectCompleted(
      base_statement_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  match base_expression_decision {
    DispatchPerform(
      _,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveNumber(value))
      )
    ) => inspect(value, content="0")
    _ => fail("expected the numeric base result")
  }
  let (recursive_waiting, recursive_statement_decision) = route_dispatch_completion(
    numeric_routing_test_base_condition_state(start, cleanup),
    DispatchNormal(Bool(false)),
  )
  let recursive_statement_ticket = match recursive_statement_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveStatementStep(DispatchNumericObserveReturnStatement)
      )
    ) => ticket
    _ => fail("expected the recursive ReturnStmt observation")
  }
  let (_, recursive_expression_decision) = reduce_activation_dispatch(
    recursive_waiting,
    DispatchEffectCompleted(
      recursive_statement_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  match recursive_expression_decision {
    DispatchPerform(
      _,
      DispatchRun(
        DispatchObserveExpressionStep(
          DispatchNumericObserveBinary(DispatchNumericAdd, loc)
        )
      )
    ) => inspect(loc == start.recipe.recursive_add_loc, content="true")
    _ => fail("expected the numeric recursive result")
  }
}

///|
test "numeric routing base condition rejects non-boolean completion" {
  let plan = numeric_routing_test_plan()
  let start = numeric_routing_test_call_start(plan, 3001)
  expect_invalid_dispatch(() => {
    let _ = route_dispatch_completion(
      numeric_routing_test_base_condition_state(
        start,
        DispatchActivationCleanup(3001),
      ),
      DispatchNormal(Number(1.0)),
    )
  })
}

///|
test "numeric routing abrupt base condition releases exactly once" {
  let plan = numeric_routing_test_plan()
  let cleanup = DispatchActivationCleanup(3101)
  let start = numeric_routing_test_call_start(plan, cleanup.id)
  let failure = ExecutionControlError(ExecutionLimit)
  let (releasing, release_decision) = route_dispatch_completion(
    numeric_routing_test_base_condition_state(start, cleanup),
    DispatchRuntimeAbrupt(failure),
  )
  let release_ticket = match release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(
        found,
        DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit))
      )
    ) => {
      inspect(found.id, content="3101")
      ticket
    }
    _ => fail("expected one numeric activation release")
  }
  let (finished, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit))) =>
      ()
    _ => fail("expected abrupt completion after the single release")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      finished,
      DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
    )
  })
}

///|
test "numeric routing abrupt statement observation releases exactly once" {
  let plan = numeric_routing_test_plan()
  let cleanup = DispatchActivationCleanup(3201)
  let start = numeric_routing_test_call_start(plan, cleanup.id)
  let initial = ActivationDispatchState::ActivationDispatchState()
  let (waiting_entry, entry_decision) = reduce_activation_dispatch(
    initial,
    DispatchStart(dispatch_test_call_request(3200)),
  )
  let entry_ticket = match entry_decision {
    DispatchPerform(ticket, DispatchEnterActivation(_)) => ticket
    _ => fail("expected numeric call entry")
  }
  let (waiting_statement, statement_decision) = reduce_activation_dispatch(
    waiting_entry,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchCallAccepted(cleanup, DispatchNumericCall(start)),
    ),
  )
  let statement_ticket = match statement_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveStatementStep(DispatchNumericObserveIfStatement)
      )
    ) => ticket
    _ => fail("expected the numeric IfStmt observation")
  }
  let failure = ExecutionControlError(ExecutionLimit)
  let (releasing, release_decision) = reduce_activation_dispatch(
    waiting_statement,
    DispatchEffectCompleted(
      statement_ticket,
      DispatchWorkCompleted(DispatchRuntimeAbrupt(failure)),
    ),
  )
  let release_ticket = match release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(
        found,
        DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit))
      )
    ) => {
      inspect(found.id, content="3201")
      ticket
    }
    _ => fail("expected one numeric activation release")
  }
  let (finished, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  match finish_decision {
    DispatchFinish(DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit))) =>
      ()
    _ => fail("expected abrupt completion after the single release")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      finished,
      DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
    )
  })
}
