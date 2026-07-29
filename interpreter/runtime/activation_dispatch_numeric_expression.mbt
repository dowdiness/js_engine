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
  DispatchNumericTrustedCallee(DispatchCalleeCaptureToken)
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
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchNumericExpressionObservation {
  DispatchNumericObserveNumber(Double)
  DispatchNumericObserveParameter(DispatchParameterBindingToken)
  DispatchNumericObserveTrustedCallee(DispatchCalleeCaptureToken)
  DispatchNumericObserveBinary(DispatchNumericBinaryOperator, @token.Loc)
  DispatchNumericObserveCall(@token.Loc)
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchNumericExpressionContinuation {
  DispatchAfterNumericExpressionObservation(DispatchNumericExpression)
  DispatchAfterNumericParameterRead(DispatchParameterBindingToken)
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
  DispatchNumericCallArgument(DispatchCalleeCaptureToken, @token.Loc)
}

///|
#warnings("-unused_value")
fn numeric_recursion_root_dispatch_expression(
  plan : NumericRecursionPlan,
  capture : DispatchCalleeCaptureToken,
) -> DispatchNumericExpression {
  DispatchNumericSingleArgumentCall(
    capture,
    DispatchNumericNumber(plan.initial_argument),
    plan.root_call_loc,
  )
}

///|
#warnings("-unused_value")
fn numeric_recursion_base_condition_dispatch_expression(
  syntax : NumericRecursionFunctionPlan,
  parameter : DispatchParameterBindingToken,
) -> DispatchNumericExpression {
  DispatchNumericBinary(
    DispatchNumericStrictEqual,
    DispatchNumericParameter(parameter),
    DispatchNumericNumber(NUMERIC_RECURSION_BASE),
    syntax.expression_recipe.base_condition_loc,
  )
}

///|
#warnings("-unused_value")
fn numeric_recursion_base_result_dispatch_expression() -> DispatchNumericExpression {
  DispatchNumericNumber(NUMERIC_RECURSION_BASE)
}

///|
#warnings("-unused_value")
fn numeric_recursion_recursive_result_dispatch_expression(
  syntax : NumericRecursionFunctionPlan,
  parameter : DispatchParameterBindingToken,
  capture : DispatchCalleeCaptureToken,
) -> DispatchNumericExpression {
  let recipe = syntax.expression_recipe
  DispatchNumericBinary(
    DispatchNumericAdd,
    DispatchNumericNumber(NUMERIC_RECURSION_STEP),
    DispatchNumericSingleArgumentCall(
      capture,
      DispatchNumericBinary(
        DispatchNumericSubtract,
        DispatchNumericParameter(parameter),
        DispatchNumericNumber(NUMERIC_RECURSION_STEP),
        recipe.recursive_subtract_loc,
      ),
      recipe.recursive_call_loc,
    ),
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
    DispatchNumericTrustedCallee(token) => DispatchNumericTrustedCallee(token)
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
    DispatchNumericCallArgument(token, loc) =>
      DispatchNumericCallArgument(token, loc)
  }
}

///|
fn dispatch_numeric_expression_observation(
  expression : DispatchNumericExpression,
) -> DispatchNumericExpressionObservation {
  match expression {
    DispatchNumericNumber(value) => DispatchNumericObserveNumber(value)
    DispatchNumericParameter(token) => DispatchNumericObserveParameter(token)
    DispatchNumericTrustedCallee(token) =>
      DispatchNumericObserveTrustedCallee(token)
    DispatchNumericBinary(operator, _, _, loc) =>
      DispatchNumericObserveBinary(operator, loc)
    DispatchNumericSingleArgumentCall(_, _, loc) =>
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
  schedule_dispatch_effect(
    push_dispatch_frame(
      state,
      DispatchContinuationFrame(
        DispatchContinueNumericExpression(
          DispatchAfterNumericExpressionObservation(retained),
        ),
      ),
    ),
    DispatchRun(
      DispatchObserveExpressionStep(
        dispatch_numeric_expression_observation(retained),
      ),
    ),
  )
}

///|
fn resume_dispatch_numeric_expression(
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
        DispatchNumericNumber(number) =>
          route_dispatch_completion(state, DispatchNormal(Number(number)))
        DispatchNumericParameter(token) =>
          schedule_dispatch_effect(
            push_dispatch_frame(
              state,
              DispatchContinuationFrame(
                DispatchContinueNumericExpression(
                  DispatchAfterNumericParameterRead(token),
                ),
              ),
            ),
            DispatchRun(DispatchReadNumericParameter(token)),
          )
        DispatchNumericTrustedCallee(token) =>
          schedule_dispatch_effect(
            state,
            DispatchRun(DispatchCaptureTrustedCallee(token)),
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
      }
    }
    DispatchAfterNumericParameterRead(_) => {
      guard value is Number(_) else {
        invalid_dispatch_transition(
          "numeric parameter capability returned a non-number",
        )
      }
      route_dispatch_completion(state, DispatchNormal(value))
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
            DispatchApplyBinaryRight(
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
    DispatchNumericCallArgument(token, loc) => {
      guard value is Number(argument) else {
        invalid_dispatch_transition(
          "numeric call argument completed with a non-number",
        )
      }
      schedule_dispatch_effect(
        state,
        DispatchRun(DispatchStartCapturedNumericCall(token, argument, loc)),
      )
    }
  }
}
