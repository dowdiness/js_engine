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
test "numeric routing root acceptance starts the admitted root call" {
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
  let expression = numeric_recursion_root_dispatch_expression(
    plan,
    DispatchCalleeCaptureToken(id=2701),
  )
  let (_, decision) = reduce_activation_dispatch(
    waiting,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchNumericProgramAccepted(
        DispatchActivationCleanup(2701),
        expression,
      ),
    ),
  )
  match decision {
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
test "numeric routing call acceptance starts its base condition" {
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
  let (_, decision) = reduce_activation_dispatch(
    waiting,
    DispatchEffectCompleted(
      entry_ticket,
      DispatchCallAccepted(
        DispatchActivationCleanup(2801),
        DispatchNumericCall(start),
      ),
    ),
  )
  match decision {
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
test "numeric routing base condition selects base or recursive return" {
  let plan = numeric_routing_test_plan()
  let start = numeric_routing_test_call_start(plan, 2901)
  let cleanup = DispatchActivationCleanup(2901)
  let (_, base_decision) = route_dispatch_completion(
    numeric_routing_test_base_condition_state(start, cleanup),
    DispatchNormal(Bool(true)),
  )
  match base_decision {
    DispatchPerform(
      _,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveNumber(value))
      )
    ) => inspect(value, content="0")
    _ => fail("expected the numeric base result")
  }
  let (_, recursive_decision) = route_dispatch_completion(
    numeric_routing_test_base_condition_state(start, cleanup),
    DispatchNormal(Bool(false)),
  )
  match recursive_decision {
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
