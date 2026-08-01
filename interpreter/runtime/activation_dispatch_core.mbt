// Deterministic activation/continuation transition core. The imperative
// dispatcher shell performs every effect described here and returns the
// ticketed result as a DispatchEvent. This module stores semantic data only:
// no host callback, evaluator frame, or Ref-backed result slot crosses a guest
// activation boundary.

///|
priv suberror InvalidDispatchTransition {
  InvalidDispatchTransition(String)
}

///|
priv struct DispatchTicket {
  value : String
}

///|
fn DispatchTicket::DispatchTicket(value~ : String) -> DispatchTicket {
  { value, }
}

///|
#warnings("-unused_field")
priv struct DispatchStatementCursor {
  ctx : ExecContext
  stmts : Array[@ast.Stmt]
  env : Environment
  index : Int
  last_value : Value
  production : Bool
}

///|
#warnings("-unused_value")
fn DispatchStatementCursor::DispatchStatementCursor(
  ctx~ : ExecContext,
  stmts~ : Array[@ast.Stmt],
  env~ : Environment,
  index? : Int = 0,
  last_value? : Value = Undefined,
  production? : Bool = false,
) -> DispatchStatementCursor {
  { ctx, stmts: stmts.copy(), env, index, last_value, production }
}

///|
#warnings("-unused_field")
priv struct DispatchStatementStep {
  ctx : ExecContext
  stmt : @ast.Stmt
  env : Environment
  index : Int
}

///|
#warnings("-unused_field")
priv struct DispatchStatementResume {
  cursor : DispatchStatementCursor
  updates_last_value : Bool
}

///|
#warnings("-unused_value")
fn DispatchStatementResume::DispatchStatementResume(
  cursor~ : DispatchStatementCursor,
  updates_last_value~ : Bool,
) -> DispatchStatementResume {
  { cursor, updates_last_value }
}

///|
#warnings("-unused_field")
priv struct DispatchCatchResume {
  parameter : @ast.Pattern?
  body : DispatchStatementCursor
}

///|
#warnings("-unused_value")
fn DispatchCatchResume::DispatchCatchResume(
  parameter~ : @ast.Pattern?,
  body~ : DispatchStatementCursor,
) -> DispatchCatchResume {
  { parameter, body }
}

///|
#warnings("-unused_field")
priv struct DispatchCallRequest {
  callee : Value
  this_value : Value
  args : Array[Value]
  loc : @token.Loc
}

///|
#warnings("-unused_value")
fn DispatchCallRequest::DispatchCallRequest(
  callee~ : Value,
  this_value~ : Value,
  args~ : Array[Value],
  loc~ : @token.Loc,
) -> DispatchCallRequest {
  { callee, this_value, args: args.copy(), loc }
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchActivationRequest {
  DispatchProgramActivation(DispatchStatementCursor)
  DispatchCallActivation(DispatchCallRequest)
}

///|
#warnings("-unused_field")
priv struct DispatchBinaryResume {
  op : @ast.BinOp
  left : Value
  loc : @token.Loc
}

///|
#warnings("-unused_value")
fn DispatchBinaryResume::DispatchBinaryResume(
  op~ : @ast.BinOp,
  left~ : Value,
  loc~ : @token.Loc,
) -> DispatchBinaryResume {
  { op, left, loc }
}

///|
#warnings("-unused_field")
priv struct DispatchPropertyGetResume {
  target : Value
  property_key : Value
  receiver : Value
  loc : @token.Loc
}

///|
#warnings("-unused_value")
fn DispatchPropertyGetResume::DispatchPropertyGetResume(
  target~ : Value,
  property_key~ : Value,
  receiver~ : Value,
  loc~ : @token.Loc,
) -> DispatchPropertyGetResume {
  { target, property_key, receiver, loc }
}

///|
#warnings("-unused_field")
priv struct DispatchProxyGetResume {
  target : Value
  property_key : Value
  receiver : Value
  loc : @token.Loc
}

///|
#warnings("-unused_value")
fn DispatchProxyGetResume::DispatchProxyGetResume(
  target~ : Value,
  property_key~ : Value,
  receiver~ : Value,
  loc~ : @token.Loc,
) -> DispatchProxyGetResume {
  { target, property_key, receiver, loc }
}

///|
// `post_trap.target` and `handler` are captured before handler.[[Get]]. The
// mutable Proxy slots must not be read again when this continuation resumes;
// `proxy` is retained only for runtime provenance identity.
#warnings("-unused_field")
priv struct DispatchProxyGetTrapLookupResume {
  proxy : Value
  handler : Value
  post_trap : DispatchProxyGetResume
}

///|
#warnings("-unused_value")
fn DispatchProxyGetTrapLookupResume::DispatchProxyGetTrapLookupResume(
  proxy~ : Value,
  handler~ : Value,
  post_trap~ : DispatchProxyGetResume,
) -> DispatchProxyGetTrapLookupResume {
  { proxy, handler, post_trap }
}

///|
#warnings("-unused_field")
priv struct DispatchParameterDefaultResume {
  params : Array[@ast.Param]
  next_index : Int
  effective_param_count : Int
  args : Array[Value]
  rest_param : String?
  is_arrow : Bool
  env : Environment
  ctx : ExecContext
  body : Array[@ast.Stmt]
}

///|
#warnings("-unused_value")
fn DispatchParameterDefaultResume::DispatchParameterDefaultResume(
  params~ : Array[@ast.Param],
  next_index~ : Int,
  effective_param_count~ : Int,
  args~ : Array[Value],
  rest_param~ : String?,
  is_arrow~ : Bool,
  env~ : Environment,
  ctx~ : ExecContext,
  body~ : Array[@ast.Stmt],
) -> DispatchParameterDefaultResume {
  {
    params: params.copy(),
    next_index,
    effective_param_count,
    args: args.copy(),
    rest_param,
    is_arrow,
    env,
    ctx,
    body: body.copy(),
  }
}

///|
#warnings("-unused_field")
priv struct DispatchNumericCallStart {
  parameter : DispatchParameterBindingToken
  recursive_callee : DispatchCalleeCaptureToken
  recipe : NumericRecursionExpressionRecipe
  return_recipe : NumericRecursionFunctionReturnRecipe
}

///|
#warnings("-unused_value")
fn DispatchNumericCallStart::DispatchNumericCallStart(
  parameter~ : DispatchParameterBindingToken,
  recursive_callee~ : DispatchCalleeCaptureToken,
  recipe~ : NumericRecursionExpressionRecipe,
  return_recipe? : NumericRecursionFunctionReturnRecipe = NumericRecursionDirectReturn,
) -> DispatchNumericCallStart {
  { parameter, recursive_callee, recipe, return_recipe }
}

///|
#warnings("-unused_constructor")
priv enum DispatchNumericProtectedRegion {
  DispatchNumericTryBody
  DispatchNumericCatchBody
  DispatchNumericFinalizerBody
}

///|
#warnings("-unused_constructor")
priv enum DispatchNumericClosedStatementKind {
  DispatchNumericExpressionStatement
  DispatchNumericReturnStatement
  DispatchNumericThrowStatement
}

///|
#warnings("-unused_field")
priv struct DispatchNumericProtectedStatementStart {
  expression : DispatchNumericExpression
  completion : NumericRecursionRootCallCompletion
}

///|
#warnings("-unused_value")
fn DispatchNumericProtectedStatementStart::DispatchNumericProtectedStatementStart(
  expression~ : DispatchNumericExpression,
  completion~ : NumericRecursionRootCallCompletion,
) -> DispatchNumericProtectedStatementStart {
  { expression, completion }
}

///|
#warnings("-unused_field")
priv struct DispatchNumericProtectedStart {
  expression : DispatchNumericExpression
  recipe : NumericRecursionProtectedRootRecipe
  catch_binding : DispatchNumericCatchBindingToken
}

///|
#warnings("-unused_value")
fn DispatchNumericProtectedStart::DispatchNumericProtectedStart(
  expression~ : DispatchNumericExpression,
  recipe~ : NumericRecursionProtectedRootRecipe,
  catch_binding~ : DispatchNumericCatchBindingToken,
) -> DispatchNumericProtectedStart {
  { expression, recipe, catch_binding }
}

///|
#warnings("-unused_field")
priv struct DispatchNumericProtectedReturnStart {
  expression : DispatchNumericExpression
  finalizer : NumericRecursionClosedBodyRecipe
}

///|
#warnings("-unused_value")
fn DispatchNumericProtectedReturnStart::DispatchNumericProtectedReturnStart(
  expression~ : DispatchNumericExpression,
  finalizer~ : NumericRecursionClosedBodyRecipe,
) -> DispatchNumericProtectedReturnStart {
  { expression, finalizer }
}

///|
#warnings("-unused_field")
priv struct DispatchNumericCatchResume {
  token : DispatchNumericCatchBindingToken
  parameter : String?
  body : NumericRecursionClosedBodyRecipe
}

///|
#warnings("-unused_value")
fn DispatchNumericCatchResume::DispatchNumericCatchResume(
  token~ : DispatchNumericCatchBindingToken,
  parameter~ : String?,
  body~ : NumericRecursionClosedBodyRecipe,
) -> DispatchNumericCatchResume {
  { token, parameter, body }
}

///|
#warnings("-unused_field")
priv struct DispatchNumericProgramStart {
  declaration_count : Int
  expression : DispatchNumericExpression
  root_control : NumericRecursionRootControlRecipe
  catch_binding : DispatchNumericCatchBindingToken
}

///|
#warnings("-unused_value")
fn DispatchNumericProgramStart::DispatchNumericProgramStart(
  declaration_count~ : Int,
  expression~ : DispatchNumericExpression,
  root_control~ : NumericRecursionRootControlRecipe,
  catch_binding~ : DispatchNumericCatchBindingToken,
) -> DispatchNumericProgramStart {
  { declaration_count, expression, root_control, catch_binding }
}

///|
#warnings("-unused_value")
fn numeric_recursion_program_dispatch_start(
  plan : NumericRecursionPlan,
  capture : DispatchCalleeCaptureToken,
) -> DispatchNumericProgramStart {
  let declaration_count = match plan.peer {
    Some(_) => 2
    None => 1
  }
  DispatchNumericProgramStart(
    declaration_count~,
    expression=numeric_recursion_root_dispatch_expression(plan, capture),
    root_control=plan.root_control,
    catch_binding=DispatchNumericCatchBindingToken(id=capture.id),
  )
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchNumericStatementObservation {
  DispatchNumericObserveRootDeclaration(Int)
  DispatchNumericObserveRootExpressionStatement
  DispatchNumericObserveRootTryStatement
  DispatchNumericObserveFunctionTryStatement
  DispatchNumericObserveProtectedStatement(
    DispatchNumericProtectedRegion,
    DispatchNumericClosedStatementKind
  )
  DispatchNumericObserveIfStatement
  DispatchNumericObserveReturnStatement
}

///|
#warnings("-unused_field")
priv struct DispatchNumericRootDeclarationResume {
  next_index : Int
  remaining : Int
  expression : DispatchNumericExpression
  root_control : NumericRecursionRootControlRecipe
  catch_binding : DispatchNumericCatchBindingToken
}

///|
#warnings("-unused_value")
fn DispatchNumericRootDeclarationResume::DispatchNumericRootDeclarationResume(
  next_index~ : Int,
  remaining~ : Int,
  expression~ : DispatchNumericExpression,
  root_control~ : NumericRecursionRootControlRecipe,
  catch_binding~ : DispatchNumericCatchBindingToken,
) -> DispatchNumericRootDeclarationResume {
  { next_index, remaining, expression, root_control, catch_binding }
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchNumericStatementContinuation {
  DispatchAfterNumericRootDeclaration(DispatchNumericRootDeclarationResume)
  DispatchAfterNumericRootExpressionStatement(DispatchNumericExpression)
  DispatchAfterNumericRootTryStatement(DispatchNumericProtectedStart)
  DispatchAfterNumericFunctionTryStatement(DispatchNumericProtectedReturnStart)
  DispatchAfterNumericProtectedStatement(DispatchNumericProtectedStatementStart)
  DispatchAfterNumericCatchEntry(DispatchNumericCatchResume)
  DispatchAfterNumericIfStatement(DispatchNumericCallStart)
  DispatchAfterNumericReturnStatement(DispatchNumericExpression)
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchCallStart {
  DispatchCallBody(DispatchStatementCursor)
  DispatchCallParameters(DispatchParameterDefaultResume)
  DispatchNumericCall(DispatchNumericCallStart)
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchEntryRejection {
  DispatchEntryGuestThrow(Error)
  DispatchEntryRuntimeAbrupt(Error)
}

///|
#warnings("-unused_field")
priv struct DispatchForLoopState {
  condition : @ast.Expr?
  update : @ast.Expr?
  body : @ast.Stmt
  outer_env : Environment
  for_env : Environment
  loop_vars : Array[String]
}

///|
#warnings("-unused_value")
fn DispatchForLoopState::DispatchForLoopState(
  condition~ : @ast.Expr?,
  update~ : @ast.Expr?,
  body~ : @ast.Stmt,
  outer_env~ : Environment,
  for_env~ : Environment,
  loop_vars~ : Array[String],
) -> DispatchForLoopState {
  { condition, update, body, outer_env, for_env, loop_vars: loop_vars.copy() }
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchLoopKind {
  DispatchWhileLoop(@ast.Expr, @ast.Stmt, Environment)
  DispatchDoWhileLoop(@ast.Stmt, @ast.Expr, Environment)
  DispatchForLoop(DispatchForLoopState)
}

///|
#warnings("-unused_field")
priv struct DispatchLoopResume {
  kind : DispatchLoopKind
  ctx : ExecContext
  label : String?
  completion : Value
  production : Bool
}

///|
#warnings("-unused_value")
fn DispatchLoopResume::DispatchLoopResume(
  kind~ : DispatchLoopKind,
  ctx~ : ExecContext,
  label~ : String?,
  completion~ : Value,
  production? : Bool = false,
) -> DispatchLoopResume {
  { kind, ctx, label, completion, production }
}

///|
fn snapshot_dispatch_statement_cursor(
  cursor : DispatchStatementCursor,
) -> DispatchStatementCursor {
  DispatchStatementCursor(
    ctx=cursor.ctx,
    stmts=cursor.stmts,
    env=cursor.env,
    index=cursor.index,
    last_value=cursor.last_value,
    production=cursor.production,
  )
}

///|
fn snapshot_dispatch_parameter_progress(
  progress : DispatchParameterDefaultResume,
) -> DispatchParameterDefaultResume {
  DispatchParameterDefaultResume(
    params=progress.params,
    next_index=progress.next_index,
    effective_param_count=progress.effective_param_count,
    args=progress.args,
    rest_param=progress.rest_param,
    is_arrow=progress.is_arrow,
    env=progress.env,
    ctx=progress.ctx,
    body=progress.body,
  )
}

///|
fn snapshot_dispatch_catch_resume(
  catch_state : DispatchCatchResume,
) -> DispatchCatchResume {
  DispatchCatchResume(
    parameter=catch_state.parameter,
    body=snapshot_dispatch_statement_cursor(catch_state.body),
  )
}

///|
fn snapshot_dispatch_loop_kind(kind : DispatchLoopKind) -> DispatchLoopKind {
  match kind {
    DispatchWhileLoop(condition, body, env) =>
      DispatchWhileLoop(condition, body, env)
    DispatchDoWhileLoop(body, condition, env) =>
      DispatchDoWhileLoop(body, condition, env)
    DispatchForLoop(for_state) =>
      DispatchForLoop(
        DispatchForLoopState(
          condition=for_state.condition,
          update=for_state.update,
          body=for_state.body,
          outer_env=for_state.outer_env,
          for_env=for_state.for_env,
          loop_vars=for_state.loop_vars,
        ),
      )
  }
}

///|
fn snapshot_dispatch_loop_resume(
  loop_state : DispatchLoopResume,
) -> DispatchLoopResume {
  DispatchLoopResume(
    kind=snapshot_dispatch_loop_kind(loop_state.kind),
    ctx=loop_state.ctx,
    label=loop_state.label,
    completion=loop_state.completion,
    production=loop_state.production,
  )
}

///|
fn snapshot_dispatch_numeric_call_start(
  start : DispatchNumericCallStart,
) -> DispatchNumericCallStart {
  DispatchNumericCallStart(
    parameter=start.parameter,
    recursive_callee=start.recursive_callee,
    recipe=start.recipe,
    return_recipe=start.return_recipe,
  )
}

///|
fn snapshot_dispatch_numeric_statement_continuation(
  continuation : DispatchNumericStatementContinuation,
) -> DispatchNumericStatementContinuation {
  match continuation {
    DispatchAfterNumericRootDeclaration(progress) =>
      DispatchAfterNumericRootDeclaration(
        DispatchNumericRootDeclarationResume(
          next_index=progress.next_index,
          remaining=progress.remaining,
          expression=snapshot_dispatch_numeric_expression(progress.expression),
          root_control=progress.root_control,
          catch_binding=progress.catch_binding,
        ),
      )
    DispatchAfterNumericRootExpressionStatement(expression) =>
      DispatchAfterNumericRootExpressionStatement(
        snapshot_dispatch_numeric_expression(expression),
      )
    DispatchAfterNumericRootTryStatement(start) =>
      DispatchAfterNumericRootTryStatement(
        DispatchNumericProtectedStart(
          expression=snapshot_dispatch_numeric_expression(start.expression),
          recipe=start.recipe,
          catch_binding=start.catch_binding,
        ),
      )
    DispatchAfterNumericFunctionTryStatement(start) =>
      DispatchAfterNumericFunctionTryStatement(
        DispatchNumericProtectedReturnStart(
          expression=snapshot_dispatch_numeric_expression(start.expression),
          finalizer=start.finalizer,
        ),
      )
    DispatchAfterNumericProtectedStatement(start) =>
      DispatchAfterNumericProtectedStatement(
        DispatchNumericProtectedStatementStart(
          expression=snapshot_dispatch_numeric_expression(start.expression),
          completion=start.completion,
        ),
      )
    DispatchAfterNumericCatchEntry(catch_state) =>
      DispatchAfterNumericCatchEntry(
        DispatchNumericCatchResume(
          token=catch_state.token,
          parameter=catch_state.parameter,
          body=catch_state.body,
        ),
      )
    DispatchAfterNumericIfStatement(start) =>
      DispatchAfterNumericIfStatement(
        snapshot_dispatch_numeric_call_start(start),
      )
    DispatchAfterNumericReturnStatement(expression) =>
      DispatchAfterNumericReturnStatement(
        snapshot_dispatch_numeric_expression(expression),
      )
  }
}

///|
fn snapshot_dispatch_continuation(
  continuation : DispatchContinuation,
) -> DispatchContinuation {
  match continuation {
    DispatchCompleteReturn => DispatchCompleteReturn
    DispatchCompleteThrow => DispatchCompleteThrow
    DispatchDeliverCallResult => DispatchDeliverCallResult
    DispatchApplyBinaryRight(binary) => DispatchApplyBinaryRight(binary)
    DispatchApplyPropertyBinaryRight(binary) =>
      DispatchApplyPropertyBinaryRight(binary)
    DispatchApplyNumericBinaryRight(binary) =>
      DispatchApplyNumericBinaryRight(binary)
    DispatchDeliverAccessorResult(accessor) =>
      DispatchDeliverAccessorResult(accessor)
    DispatchResolveProxyGetTrap(lookup) => DispatchResolveProxyGetTrap(lookup)
    DispatchCheckProxyGetResult(proxy) => DispatchCheckProxyGetResult(proxy)
    DispatchBindParameterDefault(progress) =>
      DispatchBindParameterDefault(
        snapshot_dispatch_parameter_progress(progress),
      )
    DispatchContinueNumericExpression(numeric) =>
      DispatchContinueNumericExpression(
        snapshot_dispatch_numeric_continuation(numeric),
      )
    DispatchContinueNumericStatement(numeric) =>
      DispatchContinueNumericStatement(
        snapshot_dispatch_numeric_statement_continuation(numeric),
      )
  }
}

///|
#warnings("-unused_field")
priv struct DispatchActivationCleanup {
  id : Int
}

///|
#warnings("-unused_value")
fn DispatchActivationCleanup::DispatchActivationCleanup(
  id : Int,
) -> DispatchActivationCleanup {
  { id, }
}

///|
#warnings("-unused_field")
priv struct DispatchPropertyCleanup {
  id : Int
}

///|
#warnings("-unused_value")
fn DispatchPropertyCleanup::DispatchPropertyCleanup(
  id : Int,
) -> DispatchPropertyCleanup {
  { id, }
}

///|
#warnings("-unused_field")
priv struct DispatchRejectedEntryCleanup {
  id : Int
}

///|
#warnings("-unused_value")
fn DispatchRejectedEntryCleanup::DispatchRejectedEntryCleanup(
  id : Int,
) -> DispatchRejectedEntryCleanup {
  { id, }
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchCompletion {
  DispatchNormal(Value)
  DispatchReturn(Value)
  DispatchBreak(Value?, String?)
  DispatchContinue(Value?, String?)
  DispatchThrow(Error)
  DispatchRuntimeAbrupt(Error)
}

///|
#warnings("-unused_constructor")
priv enum DispatchActivationExitRule {
  DispatchRootExit
  DispatchFunctionExit
}

///|
#warnings("-unused_constructor")
priv enum DispatchContinuation {
  DispatchCompleteReturn
  DispatchCompleteThrow
  DispatchDeliverCallResult
  DispatchApplyBinaryRight(DispatchBinaryResume)
  DispatchApplyPropertyBinaryRight(DispatchBinaryResume)
  DispatchApplyNumericBinaryRight(DispatchBinaryResume)
  DispatchDeliverAccessorResult(DispatchPropertyGetResume)
  DispatchResolveProxyGetTrap(DispatchProxyGetTrapLookupResume)
  DispatchCheckProxyGetResult(DispatchProxyGetResume)
  DispatchBindParameterDefault(DispatchParameterDefaultResume)
  DispatchContinueNumericExpression(DispatchNumericExpressionContinuation)
  DispatchContinueNumericStatement(DispatchNumericStatementContinuation)
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchWork {
  DispatchExecuteStatement(DispatchStatementStep)
  DispatchAdvanceParameters(DispatchParameterDefaultResume)
  DispatchAdvanceLoop(DispatchLoopResume)
  DispatchExecuteCatch(DispatchCatchResume, Error)
  DispatchNormalizeFunctionControl(DispatchCompletion)
  DispatchResumeContinuation(DispatchContinuation, Value)
}

///|
#warnings("-unused_constructor")
priv enum DispatchProductionWork {
  DispatchExecuteStatement(DispatchStatementStep)
  DispatchAdvanceLoop(DispatchLoopResume)
  DispatchPropertyApplyBinaryRight(DispatchBinaryResume, Value)
  DispatchNumericObserveExpressionStep(DispatchNumericExpressionObservation)
  DispatchNumericObserveStatementStep(DispatchNumericStatementObservation)
  DispatchNumericReadParameter(DispatchParameterBindingToken)
  DispatchNumericEnterCatch(DispatchNumericCatchResume, Error)
  DispatchNumericReadCatchBinding(DispatchNumericCatchBindingToken)
  DispatchNumericCaptureTrustedCallee(DispatchCalleeCaptureToken)
  DispatchNumericStartCapturedCall(
    DispatchCalleeCaptureToken,
    Double,
    @token.Loc
  )
  DispatchReceiverStartCall(DispatchCallRequest, DispatchContinuation)
  DispatchNumericApplyBinaryRight(DispatchBinaryResume, Value)
  DispatchPropertyStart(DispatchPropertyGetResume, DispatchContinuation)
  DispatchPropertyExecute(DispatchPropertyGetResume)
  DispatchPropertyDeliverAccessorResult(DispatchPropertyGetResume, Value)
  DispatchPropertyResolveProxyGetTrap(DispatchProxyGetTrapLookupResume, Value)
  DispatchPropertyCheckProxyGetResult(DispatchProxyGetResume, Value)
}

///|
#warnings("-unused_constructor")
priv enum DispatchSuspension {
  DispatchSuspendStatements(DispatchStatementCursor)
  DispatchSuspendParameters(DispatchParameterDefaultResume)
  DispatchSuspendContinue(DispatchContinuation, DispatchWork)
  DispatchSuspendContinueProduction(
    DispatchContinuation,
    DispatchProductionWork
  )
  DispatchSuspendCall(DispatchCallRequest, DispatchContinuation)
  DispatchSuspendNumericExpression(
    DispatchNumericExpression,
    DispatchContinuation?
  )
  DispatchSuspendProtected(
    DispatchStatementCursor,
    DispatchCatchResume?,
    DispatchStatementCursor?
  )
  DispatchSuspendLoopIteration(DispatchLoopResume, DispatchStatementCursor)
  DispatchSuspendSwitch(Value, DispatchStatementCursor)
  DispatchSuspendLabel(String, DispatchStatementCursor)
  DispatchSuspendProperty(
    DispatchPropertyCleanup,
    DispatchPropertyGetResume,
    DispatchContinuation
  )
}

///|
#warnings("-unused_field")
priv enum DispatchEffect {
  DispatchEnterActivation(DispatchActivationRequest)
  DispatchRun(DispatchWork)
  DispatchRunProduction(DispatchProductionWork)
  DispatchReleaseActivation(DispatchActivationCleanup, DispatchCompletion)
  DispatchRestorePropertyScope(DispatchPropertyCleanup, DispatchCompletion)
  DispatchRollbackRejectedEntry(
    DispatchRejectedEntryCleanup,
    DispatchCompletion
  )
  DispatchNormalizeEscapedControl(DispatchCompletion)
}

///|
#warnings("-unused_constructor")
priv enum DispatchEffectResult {
  DispatchProgramAccepted(DispatchActivationCleanup)
  DispatchNumericProgramAccepted(
    DispatchActivationCleanup,
    DispatchNumericProgramStart
  )
  DispatchCallAccepted(DispatchActivationCleanup, DispatchCallStart)
  DispatchActivationRejected(
    DispatchRejectedEntryCleanup,
    DispatchEntryRejection
  )
  DispatchEscapedControlNormalized(Error)
  DispatchWorkCompleted(DispatchCompletion)
  DispatchWorkSuspended(DispatchSuspension)
  DispatchCleanupCompleted
}

///|
#warnings("-unused_constructor")
priv enum ActivationDispatchEvent {
  DispatchStart(DispatchActivationRequest)
  DispatchEffectCompleted(DispatchTicket, DispatchEffectResult)
}

///|
#warnings("-unused_constructor")
priv enum ActivationDispatchDecision {
  DispatchPerform(DispatchTicket, DispatchEffect)
  DispatchFinish(DispatchCompletion)
}

///|
priv enum DispatchFrame {
  DispatchContinuationFrame(DispatchContinuation)
  DispatchStatementFrame(DispatchStatementResume)
  DispatchLoopFrame(DispatchLoopResume)
  DispatchSwitchFrame(Value)
  DispatchLabelFrame(String)
  DispatchCatchFrame(DispatchCatchResume)
  DispatchFinallyFrame(DispatchStatementCursor)
  DispatchNumericCatchFrame(DispatchNumericCatchResume)
  DispatchNumericFinallyFrame(NumericRecursionClosedBodyRecipe)
  DispatchSavedCompletionFrame(DispatchCompletion)
  DispatchPropertyScopeFrame(DispatchPropertyCleanup)
  DispatchActivationFrame(DispatchActivationCleanup, DispatchActivationExitRule)
}

///|
priv enum DispatchFrameStack {
  DispatchFrameStackEmpty
  DispatchFrameStackNode(DispatchFrame, DispatchFrameStack)
}

///|
priv enum DispatchPendingActivation {
  DispatchPendingProgram(DispatchStatementCursor)
  DispatchPendingCall
}

///|
priv enum DispatchPendingEffect {
  DispatchPendingActivationEntry(DispatchTicket, DispatchPendingActivation)
  DispatchPendingWork(DispatchTicket)
  DispatchPendingActivationRelease(DispatchTicket, DispatchCompletion)
  DispatchPendingPropertyRestore(DispatchTicket, DispatchCompletion)
  DispatchPendingRejectedRollback(DispatchTicket, DispatchCompletion)
  DispatchPendingControlNormalization(DispatchTicket, DispatchActivationCleanup)
}

///|
#warnings("-unused_field")
priv enum ActivationDispatchPhase {
  DispatchReady
  DispatchAwaiting(DispatchPendingEffect)
  DispatchFinishedPhase(DispatchCompletion)
}

///|
priv struct ActivationDispatchState {
  frames : DispatchFrameStack
  phase : ActivationDispatchPhase
  ticket_cursor : DispatchTicket
}

///|
priv enum DispatchCompletionResume {
  DispatchResumeCompletion(DispatchCompletion)
  DispatchResumeDecision(ActivationDispatchState, ActivationDispatchDecision)
}

///|
fn dispatch_resume_decision(
  result : (ActivationDispatchState, ActivationDispatchDecision),
) -> DispatchCompletionResume {
  let (state, decision) = result
  DispatchResumeDecision(state, decision)
}

///|
#warnings("-unused_value")
fn ActivationDispatchState::ActivationDispatchState() -> ActivationDispatchState {
  {
    frames: DispatchFrameStackEmpty,
    phase: DispatchReady,
    ticket_cursor: DispatchTicket(value="0"),
  }
}

///|
fn[T] invalid_dispatch_transition(
  message : String,
) -> T raise InvalidDispatchTransition {
  raise InvalidDispatchTransition(message)
}

///|
fn require_dispatch_ticket(
  expected : DispatchTicket,
  actual : DispatchTicket,
) -> Unit raise InvalidDispatchTransition {
  guard expected.value == actual.value else {
    invalid_dispatch_transition(
      "stale dispatch ticket: expected " +
      expected.value +
      ", received " +
      actual.value,
    )
  }
}

///|
fn push_dispatch_frame(
  state : ActivationDispatchState,
  frame : DispatchFrame,
) -> ActivationDispatchState {
  {
    frames: DispatchFrameStackNode(frame, state.frames),
    phase: state.phase,
    ticket_cursor: state.ticket_cursor,
  }
}

///|
fn with_dispatch_frames(
  state : ActivationDispatchState,
  frames : DispatchFrameStack,
) -> ActivationDispatchState {
  { frames, phase: state.phase, ticket_cursor: state.ticket_cursor }
}

///|
fn ready_dispatch_state(
  state : ActivationDispatchState,
) -> ActivationDispatchState {
  {
    frames: state.frames,
    phase: DispatchReady,
    ticket_cursor: state.ticket_cursor,
  }
}

///|
fn increment_dispatch_ticket_value(
  value : String,
) -> String raise InvalidDispatchTransition {
  let digits = value.to_array()
  guard !digits.is_empty() else {
    invalid_dispatch_transition("dispatch ticket must not be empty")
  }
  let mut index = digits.length() - 1
  while index >= 0 {
    match digits[index] {
      '0' => {
        digits[index] = '1'
        return String::from_array(digits)
      }
      '1' => {
        digits[index] = '2'
        return String::from_array(digits)
      }
      '2' => {
        digits[index] = '3'
        return String::from_array(digits)
      }
      '3' => {
        digits[index] = '4'
        return String::from_array(digits)
      }
      '4' => {
        digits[index] = '5'
        return String::from_array(digits)
      }
      '5' => {
        digits[index] = '6'
        return String::from_array(digits)
      }
      '6' => {
        digits[index] = '7'
        return String::from_array(digits)
      }
      '7' => {
        digits[index] = '8'
        return String::from_array(digits)
      }
      '8' => {
        digits[index] = '9'
        return String::from_array(digits)
      }
      '9' => digits[index] = '0'
      _ => invalid_dispatch_transition("dispatch ticket must be decimal")
    }
    index = index - 1
  }
  "1" + String::from_array(digits)
}

///|
fn issue_dispatch_ticket(
  cursor : DispatchTicket,
) -> (DispatchTicket, DispatchTicket) raise InvalidDispatchTransition {
  let next = DispatchTicket(value=increment_dispatch_ticket_value(cursor.value))
  (cursor, next)
}

///|
fn pending_dispatch_ticket(pending : DispatchPendingEffect) -> DispatchTicket {
  match pending {
    DispatchPendingActivationEntry(ticket, _) => ticket
    DispatchPendingWork(ticket) => ticket
    DispatchPendingActivationRelease(ticket, _) => ticket
    DispatchPendingPropertyRestore(ticket, _) => ticket
    DispatchPendingRejectedRollback(ticket, _) => ticket
    DispatchPendingControlNormalization(ticket, _) => ticket
  }
}

///|
fn schedule_dispatch_effect(
  state : ActivationDispatchState,
  effect : DispatchEffect,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  guard state.phase is DispatchReady else {
    invalid_dispatch_transition("cannot schedule an effect outside Ready")
  }
  let (ticket, next_cursor) = issue_dispatch_ticket(state.ticket_cursor)
  let pending = match effect {
    DispatchEnterActivation(request) => {
      let activation = match request {
        DispatchProgramActivation(cursor) =>
          DispatchPendingProgram(snapshot_dispatch_statement_cursor(cursor))
        DispatchCallActivation(_) => DispatchPendingCall
      }
      DispatchPendingActivationEntry(ticket, activation)
    }
    DispatchRun(_) | DispatchRunProduction(_) => DispatchPendingWork(ticket)
    DispatchReleaseActivation(_, completion) =>
      DispatchPendingActivationRelease(ticket, completion)
    DispatchRestorePropertyScope(_, completion) =>
      DispatchPendingPropertyRestore(ticket, completion)
    DispatchRollbackRejectedEntry(_, completion) =>
      DispatchPendingRejectedRollback(ticket, completion)
    DispatchNormalizeEscapedControl(_) =>
      invalid_dispatch_transition(
        "escaped control requires its ownership-preserving scheduler",
      )
  }
  let next : ActivationDispatchState = {
    frames: state.frames,
    phase: DispatchAwaiting(pending),
    ticket_cursor: next_cursor,
  }
  (next, DispatchPerform(ticket, effect))
}

///|
fn schedule_dispatch_production_work(
  state : ActivationDispatchState,
  work : DispatchProductionWork,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  schedule_dispatch_effect(state, DispatchRunProduction(work))
}

///|
fn schedule_dispatch_control_normalization(
  state : ActivationDispatchState,
  cleanup : DispatchActivationCleanup,
  completion : DispatchCompletion,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  guard state.phase is DispatchReady else {
    invalid_dispatch_transition(
      "cannot schedule control normalization outside Ready",
    )
  }
  let (ticket, next_cursor) = issue_dispatch_ticket(state.ticket_cursor)
  let next : ActivationDispatchState = {
    frames: state.frames,
    phase: DispatchAwaiting(
      DispatchPendingControlNormalization(ticket, cleanup),
    ),
    ticket_cursor: next_cursor,
  }
  (next, DispatchPerform(ticket, DispatchNormalizeEscapedControl(completion)))
}

///|
fn normalize_activation_completion(
  rule : DispatchActivationExitRule,
  completion : DispatchCompletion,
) -> DispatchCompletion {
  match (rule, completion) {
    (DispatchFunctionExit, DispatchNormal(_)) => DispatchNormal(Undefined)
    (DispatchFunctionExit, DispatchReturn(value)) => DispatchNormal(value)
    (_, other) => other
  }
}

///|
fn dispatch_completion_value(value : Value?, fallback : Value) -> Value {
  match value {
    Some(found) => found
    None => fallback
  }
}

///|
fn dispatch_loop_label_matches(
  control_label : String?,
  loop_label : String?,
) -> Bool {
  match control_label {
    None => true
    Some(target) =>
      match loop_label {
        Some(found) => found == target
        None => false
      }
  }
}

///|
fn begin_dispatch_statements(
  state : ActivationDispatchState,
  cursor : DispatchStatementCursor,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  guard state.phase is DispatchReady else {
    invalid_dispatch_transition("statement dispatch requires Ready")
  }
  guard cursor.index >= 0 && cursor.index <= cursor.stmts.length() else {
    invalid_dispatch_transition(
      "statement cursor is outside its statement list",
    )
  }
  if cursor.index == cursor.stmts.length() {
    return route_dispatch_completion(state, DispatchNormal(cursor.last_value))
  }
  let statement = cursor.stmts[cursor.index]
  let next_cursor : DispatchStatementCursor = {
    ..cursor,
    index: cursor.index + 1,
  }
  let statement_resume = DispatchStatementResume(
    cursor=next_cursor,
    updates_last_value=!is_declaration_stmt(statement),
  )
  let step : DispatchStatementStep = {
    ctx: cursor.ctx,
    stmt: statement,
    env: cursor.env,
    index: cursor.index,
  }
  let with_frame = push_dispatch_frame(
    state,
    DispatchStatementFrame(statement_resume),
  )
  if cursor.production {
    schedule_dispatch_production_work(
      with_frame,
      DispatchExecuteStatement(step),
    )
  } else {
    schedule_dispatch_effect(
      with_frame,
      DispatchRun(DispatchExecuteStatement(step)),
    )
  }
}

///|
fn begin_dispatch_numeric_statement_observation(
  state : ActivationDispatchState,
  observation : DispatchNumericStatementObservation,
  continuation : DispatchNumericStatementContinuation,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  guard state.phase is DispatchReady else {
    invalid_dispatch_transition("numeric statement observation requires Ready")
  }
  schedule_dispatch_production_work(
    push_dispatch_frame(
      state,
      DispatchContinuationFrame(
        DispatchContinueNumericStatement(
          snapshot_dispatch_numeric_statement_continuation(continuation),
        ),
      ),
    ),
    DispatchNumericObserveStatementStep(observation),
  )
}

///|
fn begin_dispatch_numeric_protected_statement(
  state : ActivationDispatchState,
  region : DispatchNumericProtectedRegion,
  expression : DispatchNumericExpression,
  completion : NumericRecursionRootCallCompletion,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  let kind = match completion {
    NumericRecursionRootCallValue => DispatchNumericExpressionStatement
    NumericRecursionRootCallThrow => DispatchNumericThrowStatement
  }
  begin_dispatch_numeric_statement_observation(
    state,
    DispatchNumericObserveProtectedStatement(region, kind),
    DispatchAfterNumericProtectedStatement(
      DispatchNumericProtectedStatementStart(expression~, completion~),
    ),
  )
}

///|
fn begin_dispatch_numeric_closed_body(
  state : ActivationDispatchState,
  region : DispatchNumericProtectedRegion,
  body : NumericRecursionClosedBodyRecipe,
  catch_binding : DispatchNumericCatchBindingToken?,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  match body {
    NumericRecursionClosedBodyEmpty =>
      route_dispatch_completion(state, DispatchNormal(Undefined))
    NumericRecursionClosedNumberValue(value) =>
      begin_dispatch_numeric_protected_statement(
        state,
        region,
        DispatchNumericNumber(value),
        NumericRecursionRootCallValue,
      )
    NumericRecursionClosedNumberThrow(value) =>
      begin_dispatch_numeric_protected_statement(
        state,
        region,
        DispatchNumericNumber(value),
        NumericRecursionRootCallThrow,
      )
    NumericRecursionClosedBindingValue => {
      guard catch_binding is Some(token) else {
        return invalid_dispatch_transition(
          "numeric binding body requires a catch capability",
        )
      }
      begin_dispatch_numeric_protected_statement(
        state,
        region,
        DispatchNumericCatchBinding(token),
        NumericRecursionRootCallValue,
      )
    }
    NumericRecursionClosedBindingThrow => {
      guard catch_binding is Some(token) else {
        return invalid_dispatch_transition(
          "numeric binding body requires a catch capability",
        )
      }
      begin_dispatch_numeric_protected_statement(
        state,
        region,
        DispatchNumericCatchBinding(token),
        NumericRecursionRootCallThrow,
      )
    }
  }
}

///|
fn begin_dispatch_numeric_protected_root(
  state : ActivationDispatchState,
  start : DispatchNumericProtectedStart,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  let with_finalizer = match start.recipe.finalizer_recipe {
    NumericRecursionNoFinalizer => state
    NumericRecursionFinalizer(body) =>
      push_dispatch_frame(state, DispatchNumericFinallyFrame(body))
  }
  let with_handler = match start.recipe.catch_recipe {
    NumericRecursionNoCatch => with_finalizer
    NumericRecursionCatch(parameter, body) =>
      push_dispatch_frame(
        with_finalizer,
        DispatchNumericCatchFrame(
          DispatchNumericCatchResume(
            token=start.catch_binding,
            parameter~,
            body~,
          ),
        ),
      )
  }
  begin_dispatch_numeric_protected_statement(
    with_handler,
    DispatchNumericTryBody,
    start.expression,
    start.recipe.try_completion,
  )
}

///|
fn begin_dispatch_numeric_program(
  state : ActivationDispatchState,
  start : DispatchNumericProgramStart,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  guard start.declaration_count > 0 else {
    invalid_dispatch_transition(
      "numeric root requires at least one declaration observation",
    )
  }
  begin_dispatch_numeric_statement_observation(
    state,
    DispatchNumericObserveRootDeclaration(0),
    DispatchAfterNumericRootDeclaration(
      DispatchNumericRootDeclarationResume(
        next_index=1,
        remaining=start.declaration_count - 1,
        expression=snapshot_dispatch_numeric_expression(start.expression),
        root_control=start.root_control,
        catch_binding=start.catch_binding,
      ),
    ),
  )
}

///|
fn resume_dispatch_numeric_statement(
  state : ActivationDispatchState,
  continuation : DispatchNumericStatementContinuation,
  value : Value,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  guard state.phase is DispatchReady else {
    invalid_dispatch_transition("numeric statement resume requires Ready")
  }
  guard value is Undefined else {
    invalid_dispatch_transition(
      "numeric statement observation returned a non-sentinel value",
    )
  }
  match continuation {
    DispatchAfterNumericRootDeclaration(progress) => {
      guard progress.next_index > 0 && progress.remaining >= 0 else {
        invalid_dispatch_transition(
          "numeric root declaration progress is invalid",
        )
      }
      if progress.remaining > 0 {
        begin_dispatch_numeric_statement_observation(
          state,
          DispatchNumericObserveRootDeclaration(progress.next_index),
          DispatchAfterNumericRootDeclaration(
            DispatchNumericRootDeclarationResume(
              next_index=progress.next_index + 1,
              remaining=progress.remaining - 1,
              expression=progress.expression,
              root_control=progress.root_control,
              catch_binding=progress.catch_binding,
            ),
          ),
        )
      } else {
        match progress.root_control {
          NumericRecursionDirectRoot =>
            begin_dispatch_numeric_statement_observation(
              state,
              DispatchNumericObserveRootExpressionStatement,
              DispatchAfterNumericRootExpressionStatement(progress.expression),
            )
          NumericRecursionProtectedRoot(recipe) =>
            begin_dispatch_numeric_statement_observation(
              state,
              DispatchNumericObserveRootTryStatement,
              DispatchAfterNumericRootTryStatement(
                DispatchNumericProtectedStart(
                  expression=progress.expression,
                  recipe~,
                  catch_binding=progress.catch_binding,
                ),
              ),
            )
        }
      }
    }
    DispatchAfterNumericRootExpressionStatement(expression) =>
      begin_dispatch_numeric_expression(state, expression)
    DispatchAfterNumericRootTryStatement(start) =>
      begin_dispatch_numeric_protected_root(state, start)
    DispatchAfterNumericFunctionTryStatement(start) =>
      begin_dispatch_numeric_statement_observation(
        push_dispatch_frame(state, DispatchNumericFinallyFrame(start.finalizer)),
        DispatchNumericObserveProtectedStatement(
          DispatchNumericTryBody,
          DispatchNumericReturnStatement,
        ),
        DispatchAfterNumericReturnStatement(start.expression),
      )
    DispatchAfterNumericProtectedStatement(start) => {
      let waiting = match start.completion {
        NumericRecursionRootCallValue => state
        NumericRecursionRootCallThrow =>
          push_dispatch_frame(
            state,
            DispatchContinuationFrame(DispatchCompleteThrow),
          )
      }
      begin_dispatch_numeric_expression(waiting, start.expression)
    }
    DispatchAfterNumericCatchEntry(catch_state) => {
      let binding = match catch_state.parameter {
        Some(_) => Some(catch_state.token)
        None => None
      }
      begin_dispatch_numeric_closed_body(
        state,
        DispatchNumericCatchBody,
        catch_state.body,
        binding,
      )
    }
    DispatchAfterNumericIfStatement(start) => {
      let waiting_condition = push_dispatch_frame(
        state,
        DispatchContinuationFrame(
          DispatchContinueNumericExpression(
            DispatchAfterNumericBaseCondition(start),
          ),
        ),
      )
      begin_dispatch_numeric_expression(
        waiting_condition,
        numeric_recursion_base_condition_dispatch_expression(
          start.recipe,
          start.parameter,
        ),
      )
    }
    DispatchAfterNumericReturnStatement(expression) =>
      begin_dispatch_numeric_expression(
        push_dispatch_frame(
          state,
          DispatchContinuationFrame(DispatchCompleteReturn),
        ),
        expression,
      )
  }
}

///|
fn route_dispatch_completion(
  state : ActivationDispatchState,
  completion : DispatchCompletion,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  guard state.phase is DispatchReady else {
    invalid_dispatch_transition("completion routing requires Ready")
  }
  let mut frames = state.frames
  let mut routed = completion
  // The routing loop decreases a weighted explicit-work measure. Ordinary
  // frames weigh one; finally frames weigh two because entering an empty
  // finalizer replaces that frame with one saved-completion frame. Every
  // internal iteration strictly decreases that weight. Branches that add
  // further semantic work return a decision to the outer dispatcher.
  while true {
    match frames {
      DispatchFrameStackEmpty => {
        let finished : ActivationDispatchState = {
          frames,
          phase: DispatchFinishedPhase(routed),
          ticket_cursor: state.ticket_cursor,
        }
        return (finished, DispatchFinish(routed))
      }
      DispatchFrameStackNode(frame, rest) => {
        frames = rest
        let popped = with_dispatch_frames(state, frames)
        match frame {
          DispatchContinuationFrame(continuation) =>
            match (continuation, routed) {
              (DispatchCompleteReturn, DispatchNormal(value)) =>
                routed = DispatchReturn(value)
              (DispatchCompleteThrow, DispatchNormal(value)) =>
                routed = DispatchThrow(JsException(value))
              (DispatchDeliverCallResult, DispatchNormal(_)) => ()
              (DispatchContinueNumericExpression(numeric), DispatchNormal(value)
              ) =>
                match
                  resume_dispatch_numeric_expression_outcome(
                    popped, numeric, value,
                  ) {
                  DispatchResumeCompletion(next) => routed = next
                  DispatchResumeDecision(next_state, decision) =>
                    return (next_state, decision)
                }
              (DispatchApplyNumericBinaryRight(binary), DispatchNormal(value)) =>
                return schedule_dispatch_production_work(
                  popped,
                  DispatchNumericApplyBinaryRight(binary, value),
                )
              (DispatchApplyPropertyBinaryRight(binary), DispatchNormal(value)) =>
                return schedule_dispatch_production_work(
                  popped,
                  DispatchPropertyApplyBinaryRight(binary, value),
                )
              (DispatchDeliverAccessorResult(accessor), DispatchNormal(value)) =>
                return schedule_dispatch_production_work(
                  popped,
                  DispatchPropertyDeliverAccessorResult(accessor, value),
                )
              (DispatchResolveProxyGetTrap(lookup), DispatchNormal(value)) =>
                return schedule_dispatch_production_work(
                  popped,
                  DispatchPropertyResolveProxyGetTrap(lookup, value),
                )
              (DispatchCheckProxyGetResult(work), DispatchNormal(value)) =>
                return schedule_dispatch_production_work(
                  popped,
                  DispatchPropertyCheckProxyGetResult(work, value),
                )
              (DispatchContinueNumericStatement(numeric), DispatchNormal(value)) =>
                match numeric {
                  DispatchAfterNumericCatchEntry(catch_state) =>
                    match (value, catch_state.body) {
                      (Undefined, NumericRecursionClosedBodyEmpty) =>
                        routed = DispatchNormal(Undefined)
                      _ =>
                        return resume_dispatch_numeric_statement(
                          popped, numeric, value,
                        )
                    }
                  _ =>
                    return resume_dispatch_numeric_statement(
                      popped, numeric, value,
                    )
                }
              (consumer, DispatchNormal(value)) =>
                return schedule_dispatch_effect(
                  popped,
                  DispatchRun(DispatchResumeContinuation(consumer, value)),
                )
              (_, abrupt) => routed = abrupt
            }
          DispatchStatementFrame(statement_resume) =>
            match routed {
              DispatchNormal(value) => {
                let cursor = if statement_resume.updates_last_value {
                  { ..statement_resume.cursor, last_value: value }
                } else {
                  statement_resume.cursor
                }
                if cursor.index == cursor.stmts.length() {
                  routed = DispatchNormal(cursor.last_value)
                } else {
                  return begin_dispatch_statements(popped, cursor)
                }
              }
              DispatchBreak(value, label) =>
                routed = DispatchBreak(
                  Some(
                    dispatch_completion_value(
                      value,
                      statement_resume.cursor.last_value,
                    ),
                  ),
                  label,
                )
              DispatchContinue(value, label) =>
                routed = DispatchContinue(
                  Some(
                    dispatch_completion_value(
                      value,
                      statement_resume.cursor.last_value,
                    ),
                  ),
                  label,
                )
              other => routed = other
            }
          DispatchLoopFrame(loop_state) =>
            match routed {
              DispatchNormal(value) => {
                let next_loop : DispatchLoopResume = {
                  ..loop_state,
                  completion: value,
                }
                if loop_state.production {
                  return schedule_dispatch_production_work(
                    popped,
                    DispatchAdvanceLoop(next_loop),
                  )
                } else {
                  return schedule_dispatch_effect(
                    popped,
                    DispatchRun(DispatchAdvanceLoop(next_loop)),
                  )
                }
              }
              DispatchContinue(value, label) =>
                if dispatch_loop_label_matches(label, loop_state.label) {
                  let next_loop : DispatchLoopResume = {
                    ..loop_state,
                    completion: dispatch_completion_value(
                      value,
                      loop_state.completion,
                    ),
                  }
                  if loop_state.production {
                    return schedule_dispatch_production_work(
                      popped,
                      DispatchAdvanceLoop(next_loop),
                    )
                  } else {
                    return schedule_dispatch_effect(
                      popped,
                      DispatchRun(DispatchAdvanceLoop(next_loop)),
                    )
                  }
                } else {
                  routed = DispatchContinue(value, label)
                }
              DispatchBreak(value, label) =>
                if dispatch_loop_label_matches(label, loop_state.label) {
                  routed = DispatchNormal(
                    dispatch_completion_value(value, loop_state.completion),
                  )
                } else {
                  routed = DispatchBreak(value, label)
                }
              other => routed = other
            }
          DispatchSwitchFrame(completion) =>
            match routed {
              DispatchBreak(value, None) =>
                routed = DispatchNormal(
                  dispatch_completion_value(value, completion),
                )
              other => routed = other
            }
          DispatchLabelFrame(expected) =>
            match routed {
              DispatchBreak(value, Some(actual)) if actual == expected =>
                routed = DispatchNormal(
                  dispatch_completion_value(value, Undefined),
                )
              other => routed = other
            }
          DispatchCatchFrame(catch_work) =>
            match routed {
              DispatchThrow(value) =>
                return schedule_dispatch_effect(
                  popped,
                  DispatchRun(DispatchExecuteCatch(catch_work, value)),
                )
              other => routed = other
            }
          DispatchNumericCatchFrame(catch_work) =>
            match routed {
              DispatchThrow(value) =>
                return schedule_dispatch_production_work(
                  push_dispatch_frame(
                    popped,
                    DispatchContinuationFrame(
                      DispatchContinueNumericStatement(
                        DispatchAfterNumericCatchEntry(catch_work),
                      ),
                    ),
                  ),
                  DispatchNumericEnterCatch(catch_work, value),
                )
              other => routed = other
            }
          DispatchFinallyFrame(finalizer_work) => {
            let waiting_finalizer = push_dispatch_frame(
              popped,
              DispatchSavedCompletionFrame(routed),
            )
            if finalizer_work.index == finalizer_work.stmts.length() {
              frames = waiting_finalizer.frames
              routed = DispatchNormal(finalizer_work.last_value)
            } else {
              return begin_dispatch_statements(
                waiting_finalizer, finalizer_work,
              )
            }
          }
          DispatchNumericFinallyFrame(finalizer_body) => {
            let waiting_finalizer = push_dispatch_frame(
              popped,
              DispatchSavedCompletionFrame(routed),
            )
            match finalizer_body {
              NumericRecursionClosedBodyEmpty => {
                frames = waiting_finalizer.frames
                routed = DispatchNormal(Undefined)
              }
              _ =>
                return begin_dispatch_numeric_closed_body(
                  waiting_finalizer,
                  DispatchNumericFinalizerBody,
                  finalizer_body,
                  None,
                )
            }
          }
          DispatchSavedCompletionFrame(saved) =>
            match routed {
              DispatchNormal(_) => routed = saved
              abrupt => routed = abrupt
            }
          DispatchPropertyScopeFrame(cleanup) =>
            return schedule_dispatch_effect(
              popped,
              DispatchRestorePropertyScope(cleanup, routed),
            )
          DispatchActivationFrame(cleanup, exit_rule) => {
            if exit_rule is DispatchFunctionExit {
              match routed {
                DispatchBreak(_, _) | DispatchContinue(_, _) =>
                  return schedule_dispatch_control_normalization(
                    popped, cleanup, routed,
                  )
                _ => ()
              }
            }
            let leaving = normalize_activation_completion(exit_rule, routed)
            return schedule_dispatch_effect(
              popped,
              DispatchReleaseActivation(cleanup, leaving),
            )
          }
        }
      }
    }
  }
  invalid_dispatch_transition("completion routing did not terminate")
}

///|
fn suspend_dispatch_work(
  state : ActivationDispatchState,
  suspension : DispatchSuspension,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  match suspension {
    DispatchSuspendStatements(cursor) =>
      begin_dispatch_statements(
        state,
        snapshot_dispatch_statement_cursor(cursor),
      )
    DispatchSuspendParameters(progress) =>
      schedule_dispatch_effect(
        state,
        DispatchRun(
          DispatchAdvanceParameters(
            snapshot_dispatch_parameter_progress(progress),
          ),
        ),
      )
    DispatchSuspendContinue(continuation, work) =>
      schedule_dispatch_effect(
        push_dispatch_frame(
          state,
          DispatchContinuationFrame(
            snapshot_dispatch_continuation(continuation),
          ),
        ),
        DispatchRun(work),
      )
    DispatchSuspendContinueProduction(continuation, work) =>
      schedule_dispatch_production_work(
        push_dispatch_frame(
          state,
          DispatchContinuationFrame(
            snapshot_dispatch_continuation(continuation),
          ),
        ),
        work,
      )
    DispatchSuspendCall(request, continuation) =>
      schedule_dispatch_effect(
        push_dispatch_frame(
          state,
          DispatchContinuationFrame(
            snapshot_dispatch_continuation(continuation),
          ),
        ),
        DispatchEnterActivation(DispatchCallActivation(request)),
      )
    DispatchSuspendNumericExpression(expression, outer_consumer) => {
      let with_outer_consumer = match outer_consumer {
        Some(continuation) =>
          push_dispatch_frame(
            state,
            DispatchContinuationFrame(
              snapshot_dispatch_continuation(continuation),
            ),
          )
        None => state
      }
      begin_dispatch_numeric_expression(with_outer_consumer, expression)
    }
    DispatchSuspendProtected(work, catch_work, finalizer_work) => {
      let with_finalizer = match finalizer_work {
        Some(cursor) =>
          push_dispatch_frame(
            state,
            DispatchFinallyFrame(snapshot_dispatch_statement_cursor(cursor)),
          )
        None => state
      }
      let with_handler = match catch_work {
        Some(catch_state) =>
          push_dispatch_frame(
            with_finalizer,
            DispatchCatchFrame(snapshot_dispatch_catch_resume(catch_state)),
          )
        None => with_finalizer
      }
      begin_dispatch_statements(
        with_handler,
        snapshot_dispatch_statement_cursor(work),
      )
    }
    DispatchSuspendLoopIteration(loop_state, body) =>
      begin_dispatch_statements(
        push_dispatch_frame(
          state,
          DispatchLoopFrame(snapshot_dispatch_loop_resume(loop_state)),
        ),
        snapshot_dispatch_statement_cursor(body),
      )
    DispatchSuspendSwitch(completion, body) =>
      begin_dispatch_statements(
        push_dispatch_frame(state, DispatchSwitchFrame(completion)),
        snapshot_dispatch_statement_cursor(body),
      )
    DispatchSuspendLabel(label, body) =>
      begin_dispatch_statements(
        push_dispatch_frame(state, DispatchLabelFrame(label)),
        snapshot_dispatch_statement_cursor(body),
      )
    DispatchSuspendProperty(cleanup, work, continuation) => {
      let with_consumer = push_dispatch_frame(
        state,
        DispatchContinuationFrame(snapshot_dispatch_continuation(continuation)),
      )
      let with_scope = push_dispatch_frame(
        with_consumer,
        DispatchPropertyScopeFrame(cleanup),
      )
      schedule_dispatch_effect(
        with_scope,
        DispatchRunProduction(DispatchPropertyExecute(work)),
      )
    }
  }
}

///|
fn complete_dispatch_effect(
  state : ActivationDispatchState,
  pending : DispatchPendingEffect,
  result : DispatchEffectResult,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  let ready = ready_dispatch_state(state)
  match (pending, result) {
    (
      DispatchPendingActivationEntry(_, DispatchPendingProgram(work)),
      DispatchProgramAccepted(cleanup),
    ) => {
      let entered = push_dispatch_frame(
        ready,
        DispatchActivationFrame(cleanup, DispatchRootExit),
      )
      begin_dispatch_statements(entered, work)
    }
    (
      DispatchPendingActivationEntry(_, DispatchPendingProgram(_)),
      DispatchNumericProgramAccepted(cleanup, start),
    ) => {
      let entered = push_dispatch_frame(
        ready,
        DispatchActivationFrame(cleanup, DispatchRootExit),
      )
      begin_dispatch_numeric_program(entered, start)
    }
    (
      DispatchPendingActivationEntry(_, DispatchPendingCall),
      DispatchCallAccepted(cleanup, DispatchCallBody(work)),
    ) => {
      let entered = push_dispatch_frame(
        ready,
        DispatchActivationFrame(cleanup, DispatchFunctionExit),
      )
      begin_dispatch_statements(
        entered,
        snapshot_dispatch_statement_cursor(work),
      )
    }
    (
      DispatchPendingActivationEntry(_, DispatchPendingCall),
      DispatchCallAccepted(cleanup, DispatchCallParameters(progress)),
    ) => {
      let entered = push_dispatch_frame(
        ready,
        DispatchActivationFrame(cleanup, DispatchFunctionExit),
      )
      schedule_dispatch_effect(
        entered,
        DispatchRun(
          DispatchAdvanceParameters(
            snapshot_dispatch_parameter_progress(progress),
          ),
        ),
      )
    }
    (
      DispatchPendingActivationEntry(_, DispatchPendingCall),
      DispatchCallAccepted(cleanup, DispatchNumericCall(start)),
    ) => {
      let entered = push_dispatch_frame(
        ready,
        DispatchActivationFrame(cleanup, DispatchFunctionExit),
      )
      begin_dispatch_numeric_statement_observation(
        entered,
        DispatchNumericObserveIfStatement,
        DispatchAfterNumericIfStatement(start),
      )
    }
    (
      DispatchPendingActivationEntry(_, _),
      DispatchActivationRejected(cleanup, rejection),
    ) => {
      let rejected = match rejection {
        DispatchEntryGuestThrow(error) => DispatchThrow(error)
        DispatchEntryRuntimeAbrupt(error) => DispatchRuntimeAbrupt(error)
      }
      schedule_dispatch_effect(
        ready,
        DispatchRollbackRejectedEntry(cleanup, rejected),
      )
    }
    (DispatchPendingWork(_), DispatchWorkCompleted(completion)) =>
      route_dispatch_completion(ready, completion)
    (DispatchPendingWork(_), DispatchWorkSuspended(suspension)) =>
      suspend_dispatch_work(ready, suspension)
    (
      DispatchPendingControlNormalization(_, cleanup),
      DispatchEscapedControlNormalized(error),
    ) =>
      schedule_dispatch_effect(
        ready,
        DispatchReleaseActivation(cleanup, DispatchThrow(error)),
      )
    (DispatchPendingActivationRelease(_, completion), DispatchCleanupCompleted)
    | (DispatchPendingPropertyRestore(_, completion), DispatchCleanupCompleted)
    | (DispatchPendingRejectedRollback(_, completion), DispatchCleanupCompleted) =>
      route_dispatch_completion(ready, completion)
    _ =>
      invalid_dispatch_transition("effect result does not match pending effect")
  }
}

///|
#warnings("-unused_value")
fn reduce_activation_dispatch(
  state : ActivationDispatchState,
  event : ActivationDispatchEvent,
) -> (ActivationDispatchState, ActivationDispatchDecision) raise InvalidDispatchTransition {
  match (state.phase, event) {
    (DispatchReady, DispatchStart(request)) => {
      guard state.frames is DispatchFrameStackEmpty else {
        invalid_dispatch_transition("root start requires an empty frame stack")
      }
      schedule_dispatch_effect(state, DispatchEnterActivation(request))
    }
    (DispatchAwaiting(pending), DispatchEffectCompleted(ticket, result)) => {
      require_dispatch_ticket(pending_dispatch_ticket(pending), ticket)
      complete_dispatch_effect(state, pending, result)
    }
    (DispatchReady, DispatchEffectCompleted(_, _)) =>
      invalid_dispatch_transition("no dispatch effect is awaiting a result")
    (DispatchAwaiting(_), DispatchStart(_)) =>
      invalid_dispatch_transition("dispatch has already started")
    (DispatchFinishedPhase(_), _) =>
      invalid_dispatch_transition("dispatch is already finished")
  }
}
