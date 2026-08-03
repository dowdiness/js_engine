// Array-free numeric-expression work for the exact recursion slice. The
// reducer retains only immutable syntax recipes and opaque activation-owned
// capabilities. Observation, binding reads, callee capture, calls, and binary
// application remain effects owned by the imperative shell.

///|
#warnings("-unused_field")
priv struct DispatchParameterBindingToken {
  id : Int
}

///|
#warnings("-unused_value")
fn DispatchParameterBindingToken::DispatchParameterBindingToken(
  id~ : Int,
) -> DispatchParameterBindingToken {
  { id, }
}

///|
#warnings("-unused_field")
priv struct DispatchRetainedParameterBindingToken {
  id : Int
}

///|
#warnings("-unused_value")
fn DispatchRetainedParameterBindingToken::DispatchRetainedParameterBindingToken(
  id~ : Int,
) -> DispatchRetainedParameterBindingToken {
  { id, }
}

///|
#warnings("-unused_field")
priv struct DispatchNumericCatchBindingToken {
  id : Int
}

///|
#warnings("-unused_value")
fn DispatchNumericCatchBindingToken::DispatchNumericCatchBindingToken(
  id~ : Int,
) -> DispatchNumericCatchBindingToken {
  { id, }
}

///|
#warnings("-unused_field")
priv struct DispatchCalleeCaptureToken {
  id : Int
}

///|
#warnings("-unused_value")
fn DispatchCalleeCaptureToken::DispatchCalleeCaptureToken(
  id~ : Int,
) -> DispatchCalleeCaptureToken {
  { id, }
}

///|
#warnings("-unused_constructor")
priv enum DispatchNumericBinaryOperator {
  DispatchNumericAdd
  DispatchNumericSubtract
  DispatchNumericStrictEqual
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchNumericExpression {
  DispatchNumericNumber(Double)
  DispatchNumericParameter(DispatchParameterBindingToken)
  DispatchNumericRetainedParameter(DispatchRetainedParameterBindingToken)
  DispatchNumericCatchBinding(DispatchNumericCatchBindingToken)
  DispatchNumericTrustedCallee(DispatchCalleeCaptureToken)
  DispatchNumericClosedArgument(NumericRecursionClosedArgumentRecipe)
  DispatchNumericBinary(
    DispatchNumericBinaryOperator,
    DispatchNumericExpression,
    DispatchNumericExpression,
    @token.Loc
  )
  DispatchNumericSingleArgumentCall(
    DispatchCalleeCaptureToken,
    DispatchNumericExpression,
    @token.Loc
  )
  DispatchNumericTwoArgumentCall(
    DispatchCalleeCaptureToken,
    DispatchNumericExpression,
    DispatchNumericExpression,
    @token.Loc
  )
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchNumericExpressionObservation {
  DispatchNumericObserveNumber(Double)
  DispatchNumericObserveParameter(DispatchParameterBindingToken)
  DispatchNumericObserveRetainedParameter(DispatchRetainedParameterBindingToken)
  DispatchNumericObserveCatchBinding(DispatchNumericCatchBindingToken)
  DispatchNumericObserveTrustedCallee(DispatchCalleeCaptureToken)
  DispatchNumericObserveClosedArgument
  DispatchNumericObserveBinary(DispatchNumericBinaryOperator, @token.Loc)
  DispatchNumericObserveCall(@token.Loc)
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchNumericExpressionContinuation {
  DispatchAfterNumericExpressionObservation(DispatchNumericExpression)
  DispatchAfterNumericParameterRead(DispatchParameterBindingToken)
  DispatchAfterNumericRetainedParameterRead(
    DispatchRetainedParameterBindingToken
  )
  DispatchAfterNumericCatchBindingRead(DispatchNumericCatchBindingToken)
  DispatchAfterNumericClosedArgumentObservation(Double, Int)
  DispatchAfterNumericBaseCondition(DispatchNumericCallStart)
  DispatchNumericBinaryLeft(
    DispatchNumericBinaryOperator,
    DispatchNumericExpression,
    @token.Loc
  )
  DispatchNumericCallCallee(
    DispatchCalleeCaptureToken,
    DispatchNumericExpression,
    @token.Loc
  )
  DispatchNumericCallCalleeTwoArgument(
    DispatchCalleeCaptureToken,
    DispatchNumericExpression,
    DispatchNumericExpression,
    @token.Loc
  )
  DispatchNumericCallArgument(DispatchCalleeCaptureToken, @token.Loc)
  DispatchNumericCallFirstArgument(
    DispatchCalleeCaptureToken,
    DispatchNumericExpression,
    @token.Loc
  )
  DispatchNumericCallSecondArgument(
    DispatchCalleeCaptureToken,
    Double,
    @token.Loc
  )
}

///|
#warnings("-unused_value")
fn numeric_recursion_root_dispatch_expression(
  plan : NumericRecursionPlan,
  capture : DispatchCalleeCaptureToken,
) -> DispatchNumericExpression {
  match plan.retained_argument {
    None =>
      DispatchNumericSingleArgumentCall(
        capture,
        DispatchNumericNumber(plan.initial_argument),
        plan.root_call_loc,
      )
    Some(recipe) =>
      DispatchNumericTwoArgumentCall(
        capture,
        DispatchNumericNumber(plan.initial_argument),
        DispatchNumericClosedArgument(recipe),
        plan.root_call_loc,
      )
  }
}

///|
#warnings("-unused_value")
fn numeric_recursion_base_condition_dispatch_expression(
  recipe : NumericRecursionExpressionRecipe,
  parameter : DispatchParameterBindingToken,
) -> DispatchNumericExpression {
  DispatchNumericBinary(
    DispatchNumericStrictEqual,
    DispatchNumericParameter(parameter),
    DispatchNumericNumber(NUMERIC_RECURSION_BASE),
    recipe.base_condition_loc,
  )
}

///|
#warnings("-unused_value")
fn numeric_recursion_base_result_dispatch_expression(
  retained_parameter? : DispatchRetainedParameterBindingToken? = None,
) -> DispatchNumericExpression {
  match retained_parameter {
    None => DispatchNumericNumber(NUMERIC_RECURSION_BASE)
    Some(token) => DispatchNumericRetainedParameter(token)
  }
}

///|
#warnings("-unused_value")
fn numeric_recursion_recursive_result_dispatch_expression(
  recipe : NumericRecursionExpressionRecipe,
  parameter : DispatchParameterBindingToken,
  capture : DispatchCalleeCaptureToken,
  retained_parameter? : DispatchRetainedParameterBindingToken? = None,
) -> DispatchNumericExpression {
  let recursive_argument = DispatchNumericBinary(
    DispatchNumericSubtract,
    DispatchNumericParameter(parameter),
    DispatchNumericNumber(NUMERIC_RECURSION_STEP),
    recipe.recursive_subtract_loc,
  )
  let recursive_call = match retained_parameter {
    None =>
      DispatchNumericSingleArgumentCall(
        capture,
        recursive_argument,
        recipe.recursive_call_loc,
      )
    Some(token) =>
      DispatchNumericTwoArgumentCall(
        capture,
        recursive_argument,
        DispatchNumericRetainedParameter(token),
        recipe.recursive_call_loc,
      )
  }
  DispatchNumericBinary(
    DispatchNumericAdd,
    DispatchNumericNumber(NUMERIC_RECURSION_STEP),
    recursive_call,
    recipe.recursive_add_loc,
  )
}

///|
fn snapshot_dispatch_numeric_expression(
  expression : DispatchNumericExpression,
) -> DispatchNumericExpression {
  match expression {
    DispatchNumericNumber(value) => DispatchNumericNumber(value)
    DispatchNumericParameter(token) => DispatchNumericParameter(token)
    DispatchNumericRetainedParameter(token) =>
      DispatchNumericRetainedParameter(token)
    DispatchNumericCatchBinding(token) => DispatchNumericCatchBinding(token)
    DispatchNumericTrustedCallee(token) => DispatchNumericTrustedCallee(token)
    DispatchNumericClosedArgument(recipe) =>
      DispatchNumericClosedArgument(recipe)
    DispatchNumericBinary(operator, left, right, loc) =>
      DispatchNumericBinary(
        operator,
        snapshot_dispatch_numeric_expression(left),
        snapshot_dispatch_numeric_expression(right),
        loc,
      )
    DispatchNumericSingleArgumentCall(token, argument, loc) =>
      DispatchNumericSingleArgumentCall(
        token,
        snapshot_dispatch_numeric_expression(argument),
        loc,
      )
    DispatchNumericTwoArgumentCall(token, first, second, loc) =>
      DispatchNumericTwoArgumentCall(
        token,
        snapshot_dispatch_numeric_expression(first),
        snapshot_dispatch_numeric_expression(second),
        loc,
      )
  }
}

///|
fn snapshot_dispatch_numeric_continuation(
  continuation : DispatchNumericExpressionContinuation,
) -> DispatchNumericExpressionContinuation {
  match continuation {
    DispatchAfterNumericExpressionObservation(expression) =>
      DispatchAfterNumericExpressionObservation(
        snapshot_dispatch_numeric_expression(expression),
      )
    DispatchAfterNumericParameterRead(token) =>
      DispatchAfterNumericParameterRead(token)
    DispatchAfterNumericRetainedParameterRead(token) =>
      DispatchAfterNumericRetainedParameterRead(token)
    DispatchAfterNumericCatchBindingRead(token) =>
      DispatchAfterNumericCatchBindingRead(token)
    DispatchAfterNumericClosedArgumentObservation(value, remaining) =>
      DispatchAfterNumericClosedArgumentObservation(value, remaining)
    DispatchAfterNumericBaseCondition(start) =>
      DispatchAfterNumericBaseCondition(
        DispatchNumericCallStart(
          parameter=start.parameter,
          retained_parameter=start.retained_parameter,
          recursive_callee=start.recursive_callee,
          recipe=start.recipe,
          return_recipe=start.return_recipe,
        ),
      )
    DispatchNumericBinaryLeft(operator, right, loc) =>
      DispatchNumericBinaryLeft(
        operator,
        snapshot_dispatch_numeric_expression(right),
        loc,
      )
    DispatchNumericCallCallee(token, argument, loc) =>
      DispatchNumericCallCallee(
        token,
        snapshot_dispatch_numeric_expression(argument),
        loc,
      )
    DispatchNumericCallCalleeTwoArgument(token, first, second, loc) =>
      DispatchNumericCallCalleeTwoArgument(
        token,
        snapshot_dispatch_numeric_expression(first),
        snapshot_dispatch_numeric_expression(second),
        loc,
      )
    DispatchNumericCallArgument(token, loc) =>
      DispatchNumericCallArgument(token, loc)
    DispatchNumericCallFirstArgument(token, second, loc) =>
      DispatchNumericCallFirstArgument(
        token,
        snapshot_dispatch_numeric_expression(second),
        loc,
      )
    DispatchNumericCallSecondArgument(token, first, loc) =>
      DispatchNumericCallSecondArgument(token, first, loc)
  }
}

///|
fn dispatch_numeric_expression_observation(
  expression : DispatchNumericExpression,
) -> DispatchNumericExpressionObservation {
  match expression {
    DispatchNumericNumber(value) => DispatchNumericObserveNumber(value)
    DispatchNumericParameter(token) => DispatchNumericObserveParameter(token)
    DispatchNumericRetainedParameter(token) =>
      DispatchNumericObserveRetainedParameter(token)
    DispatchNumericCatchBinding(token) =>
      DispatchNumericObserveCatchBinding(token)
    DispatchNumericTrustedCallee(token) =>
      DispatchNumericObserveTrustedCallee(token)
    DispatchNumericClosedArgument(_) => DispatchNumericObserveClosedArgument
    DispatchNumericBinary(operator, _, _, loc) =>
      DispatchNumericObserveBinary(operator, loc)
    DispatchNumericSingleArgumentCall(_, _, loc) =>
      DispatchNumericObserveCall(loc)
    DispatchNumericTwoArgumentCall(_, _, _, loc) =>
      DispatchNumericObserveCall(loc)
  }
}

///|
fn dispatch_numeric_binary_operator_to_ast(
  operator : DispatchNumericBinaryOperator,
) -> @ast.BinOp {
  match operator {
    DispatchNumericAdd => @ast.Add
    DispatchNumericSubtract => @ast.Sub
    DispatchNumericStrictEqual => @ast.EqEqEq
  }
}

///|
fn begin_dispatch_numeric_expression(
  state : ActivationDispatchState,
  expression : DispatchNumericExpression,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  guard state.phase is DispatchReady else {
    invalid_dispatch_transition("numeric expression dispatch requires Ready")
  }
  let retained = snapshot_dispatch_numeric_expression(expression)
  schedule_dispatch_production_work(
    push_dispatch_frame(
      state,
      DispatchContinuationFrame(
        DispatchContinueNumericExpression(
          DispatchAfterNumericExpressionObservation(retained),
        ),
      ),
    ),
    DispatchNumericObserveExpressionStep(
      dispatch_numeric_expression_observation(retained),
    ),
  )
}

///|
fn resume_dispatch_numeric_expression_outcome(
  state : ActivationDispatchState,
  continuation : DispatchNumericExpressionContinuation,
  value : Value,
) -> DispatchCompletionResume raise InvalidDispatchTransition {
  guard state.phase is DispatchReady else {
    invalid_dispatch_transition("numeric expression resume requires Ready")
  }
  match continuation {
    DispatchAfterNumericExpressionObservation(DispatchNumericNumber(number)) => {
      guard value is Undefined else {
        invalid_dispatch_transition(
          "numeric expression observation returned a non-sentinel value",
        )
      }
      DispatchResumeCompletion(DispatchNormal(Number(number)))
    }
    DispatchAfterNumericExpressionObservation(
      DispatchNumericClosedArgument(recipe)
    ) => {
      guard value is Undefined else {
        invalid_dispatch_transition(
          "closed numeric argument observation returned a non-sentinel value",
        )
      }
      if recipe.observation_count <= 1 {
        DispatchResumeCompletion(DispatchNormal(Number(recipe.value)))
      } else {
        dispatch_resume_decision(
          schedule_dispatch_production_work(
            push_dispatch_frame(
              state,
              DispatchContinuationFrame(
                DispatchContinueNumericExpression(
                  DispatchAfterNumericClosedArgumentObservation(
                    recipe.value,
                    recipe.observation_count - 1,
                  ),
                ),
              ),
            ),
            DispatchNumericObserveExpressionStep(
              DispatchNumericObserveClosedArgument,
            ),
          ),
        )
      }
    }
    DispatchAfterNumericParameterRead(_) => {
      guard value is Number(_) else {
        invalid_dispatch_transition(
          "numeric parameter capability returned a non-number",
        )
      }
      DispatchResumeCompletion(DispatchNormal(value))
    }
    DispatchAfterNumericRetainedParameterRead(_) => {
      guard value is Number(_) else {
        invalid_dispatch_transition(
          "numeric retained parameter capability returned a non-number",
        )
      }
      DispatchResumeCompletion(DispatchNormal(value))
    }
    DispatchAfterNumericCatchBindingRead(_) =>
      DispatchResumeCompletion(DispatchNormal(value))
    DispatchAfterNumericClosedArgumentObservation(final_value, remaining) => {
      guard value is Undefined else {
        invalid_dispatch_transition(
          "closed numeric argument observation returned a non-sentinel value",
        )
      }
      if remaining <= 1 {
        DispatchResumeCompletion(DispatchNormal(Number(final_value)))
      } else {
        dispatch_resume_decision(
          schedule_dispatch_production_work(
            push_dispatch_frame(
              state,
              DispatchContinuationFrame(
                DispatchContinueNumericExpression(
                  DispatchAfterNumericClosedArgumentObservation(
                    final_value,
                    remaining - 1,
                  ),
                ),
              ),
            ),
            DispatchNumericObserveExpressionStep(
              DispatchNumericObserveClosedArgument,
            ),
          ),
        )
      }
    }
    _ =>
      dispatch_resume_decision(
        resume_dispatch_numeric_expression_effect(state, continuation, value),
      )
  }
}

///|
fn resume_dispatch_numeric_expression_effect(
  state : ActivationDispatchState,
  continuation : DispatchNumericExpressionContinuation,
  value : Value,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  guard state.phase is DispatchReady else {
    invalid_dispatch_transition("numeric expression resume requires Ready")
  }
  match continuation {
    DispatchAfterNumericExpressionObservation(expression) => {
      guard value is Undefined else {
        invalid_dispatch_transition(
          "numeric expression observation returned a non-sentinel value",
        )
      }
      match expression {
        DispatchNumericNumber(_) =>
          invalid_dispatch_transition(
            "numeric literal completion must remain in the routing loop",
          )
        DispatchNumericParameter(token) =>
          schedule_dispatch_production_work(
            push_dispatch_frame(
              state,
              DispatchContinuationFrame(
                DispatchContinueNumericExpression(
                  DispatchAfterNumericParameterRead(token),
                ),
              ),
            ),
            DispatchNumericReadParameter(token),
          )
        DispatchNumericRetainedParameter(token) =>
          schedule_dispatch_production_work(
            push_dispatch_frame(
              state,
              DispatchContinuationFrame(
                DispatchContinueNumericExpression(
                  DispatchAfterNumericRetainedParameterRead(token),
                ),
              ),
            ),
            DispatchNumericReadRetainedParameter(token),
          )
        DispatchNumericCatchBinding(token) =>
          schedule_dispatch_production_work(
            push_dispatch_frame(
              state,
              DispatchContinuationFrame(
                DispatchContinueNumericExpression(
                  DispatchAfterNumericCatchBindingRead(token),
                ),
              ),
            ),
            DispatchNumericReadCatchBinding(token),
          )
        // SingleArgumentCall is the only producer of this internal node. It
        // pushes the matching NumericCallCallee frame before capture starts,
        // so the sentinel completion deliberately resumes that paired frame.
        DispatchNumericTrustedCallee(token) =>
          schedule_dispatch_production_work(
            state,
            DispatchNumericCaptureTrustedCallee(token),
          )
        DispatchNumericClosedArgument(_) =>
          invalid_dispatch_transition(
            "closed numeric argument must remain in its observation loop",
          )
        DispatchNumericBinary(operator, left, right, loc) =>
          begin_dispatch_numeric_expression(
            push_dispatch_frame(
              state,
              DispatchContinuationFrame(
                DispatchContinueNumericExpression(
                  DispatchNumericBinaryLeft(operator, right, loc),
                ),
              ),
            ),
            left,
          )
        DispatchNumericSingleArgumentCall(token, argument, loc) =>
          begin_dispatch_numeric_expression(
            push_dispatch_frame(
              state,
              DispatchContinuationFrame(
                DispatchContinueNumericExpression(
                  DispatchNumericCallCallee(token, argument, loc),
                ),
              ),
            ),
            DispatchNumericTrustedCallee(token),
          )
        DispatchNumericTwoArgumentCall(token, first, second, loc) =>
          begin_dispatch_numeric_expression(
            push_dispatch_frame(
              state,
              DispatchContinuationFrame(
                DispatchContinueNumericExpression(
                  DispatchNumericCallCalleeTwoArgument(
                    token, first, second, loc,
                  ),
                ),
              ),
            ),
            DispatchNumericTrustedCallee(token),
          )
      }
    }
    DispatchAfterNumericParameterRead(_) => {
      guard value is Number(_) else {
        invalid_dispatch_transition(
          "numeric parameter capability returned a non-number",
        )
      }
      invalid_dispatch_transition(
        "numeric parameter completion must remain in the routing loop",
      )
    }
    DispatchAfterNumericRetainedParameterRead(_) =>
      invalid_dispatch_transition(
        "numeric retained parameter completion must remain in the routing loop",
      )
    DispatchAfterNumericCatchBindingRead(_) =>
      invalid_dispatch_transition(
        "numeric catch completion must remain in the routing loop",
      )
    DispatchAfterNumericClosedArgumentObservation(_, _) =>
      invalid_dispatch_transition(
        "closed numeric argument completion must remain in the routing loop",
      )
    DispatchAfterNumericBaseCondition(start) =>
      match value {
        Bool(true) =>
          begin_dispatch_numeric_statement_observation(
            state,
            DispatchNumericObserveReturnStatement,
            DispatchAfterNumericReturnStatement(
              numeric_recursion_base_result_dispatch_expression(
                retained_parameter=start.retained_parameter,
              ),
            ),
          )
        Bool(false) => {
          let expression = numeric_recursion_recursive_result_dispatch_expression(
            start.recipe,
            start.parameter,
            start.recursive_callee,
            retained_parameter=start.retained_parameter,
          )
          match start.return_recipe {
            NumericRecursionDirectReturn =>
              begin_dispatch_numeric_statement_observation(
                state,
                DispatchNumericObserveReturnStatement,
                DispatchAfterNumericReturnStatement(expression),
              )
            NumericRecursionProtectedReturn(finalizer) =>
              begin_dispatch_numeric_statement_observation(
                state,
                DispatchNumericObserveFunctionTryStatement,
                DispatchAfterNumericFunctionTryStatement(
                  DispatchNumericProtectedReturnStart(expression~, finalizer~),
                ),
              )
          }
        }
        _ =>
          invalid_dispatch_transition(
            "numeric base condition completed with a non-boolean",
          )
      }
    DispatchNumericBinaryLeft(operator, right, loc) => {
      guard value is Number(_) else {
        invalid_dispatch_transition(
          "numeric binary left operand completed with a non-number",
        )
      }
      begin_dispatch_numeric_expression(
        push_dispatch_frame(
          state,
          DispatchContinuationFrame(
            DispatchApplyNumericBinaryRight(
              DispatchBinaryResume(
                op=dispatch_numeric_binary_operator_to_ast(operator),
                left=value,
                loc~,
              ),
            ),
          ),
        ),
        right,
      )
    }
    DispatchNumericCallCallee(token, argument, loc) => {
      guard value is Undefined else {
        invalid_dispatch_transition(
          "numeric callee capture returned a non-sentinel value",
        )
      }
      begin_dispatch_numeric_expression(
        push_dispatch_frame(
          state,
          DispatchContinuationFrame(
            DispatchContinueNumericExpression(
              DispatchNumericCallArgument(token, loc),
            ),
          ),
        ),
        argument,
      )
    }
    DispatchNumericCallCalleeTwoArgument(token, first, second, loc) => {
      guard value is Undefined else {
        invalid_dispatch_transition(
          "numeric callee capture returned a non-sentinel value",
        )
      }
      begin_dispatch_numeric_expression(
        push_dispatch_frame(
          state,
          DispatchContinuationFrame(
            DispatchContinueNumericExpression(
              DispatchNumericCallFirstArgument(token, second, loc),
            ),
          ),
        ),
        first,
      )
    }
    DispatchNumericCallArgument(token, loc) => {
      guard value is Number(argument) else {
        invalid_dispatch_transition(
          "numeric call argument completed with a non-number",
        )
      }
      schedule_dispatch_production_work(
        state,
        DispatchNumericStartCapturedCall(token, argument, loc),
      )
    }
    DispatchNumericCallFirstArgument(token, second, loc) => {
      guard value is Number(first) else {
        invalid_dispatch_transition(
          "numeric first call argument completed with a non-number",
        )
      }
      begin_dispatch_numeric_expression(
        push_dispatch_frame(
          state,
          DispatchContinuationFrame(
            DispatchContinueNumericExpression(
              DispatchNumericCallSecondArgument(token, first, loc),
            ),
          ),
        ),
        second,
      )
    }
    DispatchNumericCallSecondArgument(token, first, loc) => {
      guard value is Number(second) else {
        invalid_dispatch_transition(
          "numeric second call argument completed with a non-number",
        )
      }
      schedule_dispatch_production_work(
        state,
        DispatchNumericStartCapturedTwoArgumentCall(token, first, second, loc),
      )
    }
  }
}
