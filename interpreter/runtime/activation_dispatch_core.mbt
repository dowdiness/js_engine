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
}

///|
#warnings("-unused_value")
fn DispatchStatementCursor::DispatchStatementCursor(
  ctx~ : ExecContext,
  stmts~ : Array[@ast.Stmt],
  env~ : Environment,
  index? : Int = 0,
  last_value? : Value = Undefined,
) -> DispatchStatementCursor {
  { ctx, stmts: stmts.copy(), env, index, last_value }
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
#warnings("-unused_constructor-unused_field")
priv enum DispatchCallStart {
  DispatchCallBody(DispatchStatementCursor)
  DispatchCallParameters(DispatchParameterDefaultResume)
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
}

///|
#warnings("-unused_value")
fn DispatchLoopResume::DispatchLoopResume(
  kind~ : DispatchLoopKind,
  ctx~ : ExecContext,
  label~ : String?,
  completion~ : Value,
) -> DispatchLoopResume {
  { kind, ctx, label, completion }
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
  )
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
    DispatchDeliverAccessorResult(accessor) =>
      DispatchDeliverAccessorResult(accessor)
    DispatchCheckProxyGetResult(proxy) => DispatchCheckProxyGetResult(proxy)
    DispatchBindParameterDefault(progress) =>
      DispatchBindParameterDefault(
        snapshot_dispatch_parameter_progress(progress),
      )
    DispatchContinueNumericExpression(numeric) =>
      DispatchContinueNumericExpression(
        snapshot_dispatch_numeric_continuation(numeric),
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
  DispatchDeliverAccessorResult(DispatchPropertyGetResume)
  DispatchCheckProxyGetResult(DispatchProxyGetResume)
  DispatchBindParameterDefault(DispatchParameterDefaultResume)
  DispatchContinueNumericExpression(DispatchNumericExpressionContinuation)
}

///|
#warnings("-unused_constructor")
priv enum DispatchWork {
  DispatchExecuteStatement(DispatchStatementStep)
  DispatchAdvanceParameters(DispatchParameterDefaultResume)
  DispatchAdvanceLoop(DispatchLoopResume)
  DispatchExecuteProperty(DispatchPropertyGetResume)
  DispatchExecuteCatch(DispatchCatchResume, Error)
  DispatchNormalizeFunctionControl(DispatchCompletion)
  DispatchResumeContinuation(DispatchContinuation, Value)
  DispatchObserveExpressionStep(DispatchNumericExpressionObservation)
  DispatchReadNumericParameter(DispatchParameterBindingToken)
  DispatchCaptureTrustedCallee(DispatchCalleeCaptureToken)
  DispatchStartCapturedNumericCall(
    DispatchCalleeCaptureToken,
    Double,
    @token.Loc
  )
}

///|
#warnings("-unused_constructor")
priv enum DispatchSuspension {
  DispatchSuspendStatements(DispatchStatementCursor)
  DispatchSuspendParameters(DispatchParameterDefaultResume)
  DispatchSuspendContinue(DispatchContinuation, DispatchWork)
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
    DispatchRun(_) => DispatchPendingWork(ticket)
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
  schedule_dispatch_effect(
    push_dispatch_frame(state, DispatchStatementFrame(statement_resume)),
    DispatchRun(DispatchExecuteStatement(step)),
  )
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
                return resume_dispatch_numeric_expression(
                  popped, numeric, value,
                )
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
                return begin_dispatch_statements(popped, cursor)
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
                return schedule_dispatch_effect(
                  popped,
                  DispatchRun(DispatchAdvanceLoop(next_loop)),
                )
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
                  return schedule_dispatch_effect(
                    popped,
                    DispatchRun(DispatchAdvanceLoop(next_loop)),
                  )
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
          DispatchFinallyFrame(finalizer_work) => {
            let waiting_finalizer = push_dispatch_frame(
              popped,
              DispatchSavedCompletionFrame(routed),
            )
            return begin_dispatch_statements(waiting_finalizer, finalizer_work)
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
      begin_dispatch_numeric_expression(
        with_outer_consumer,
        snapshot_dispatch_numeric_expression(expression),
      )
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
        DispatchRun(DispatchExecuteProperty(work)),
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
