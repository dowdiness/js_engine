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
