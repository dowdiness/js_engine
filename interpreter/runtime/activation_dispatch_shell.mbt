// Imperative adapter for admitted production activation-dispatch slices.
// Admission and callback-free preflight finish before any managed effect. Once
// managed execution starts, it stays inside this loop; unsupported effects are
// invariant failures, never legacy fallbacks.

///|
priv suberror InvalidActivationDispatchShell {
  InvalidActivationDispatchShell(String)
}

///|
fn[T] invalid_activation_dispatch_shell(
  message : String,
) -> T raise InvalidActivationDispatchShell {
  raise InvalidActivationDispatchShell(message)
}

///|
priv enum ProgramCleanupOwner {
  AcceptedProgram
  RejectedProgram
  AcceptedNumericCall
  RejectedNumericCall
}

///|
const MAX_DISPATCH_CLEANUP_ID = 2147483647

///|
priv enum DispatchNumericCalleeCaptureState {
  DispatchNumericCalleeUnresolved(String)
  DispatchNumericCalleeCaptured(Value)
  DispatchNumericCalleeConsumed
}

///|
priv struct DispatchNumericParameterCapability {
  env : Environment
  name : String
}

///|
fn DispatchNumericParameterCapability::DispatchNumericParameterCapability(
  env~ : Environment,
  name~ : String,
) -> DispatchNumericParameterCapability {
  { env, name }
}

///|
priv struct DispatchNumericActivationCapabilities {
  parameter : DispatchNumericParameterCapability?
  mut recursive_callee : DispatchNumericCalleeCaptureState
}

///|
fn DispatchNumericActivationCapabilities::DispatchNumericActivationCapabilities(
  parameter~ : DispatchNumericParameterCapability?,
  recursive_callee~ : DispatchNumericCalleeCaptureState,
) -> DispatchNumericActivationCapabilities {
  { parameter, recursive_callee }
}

///|
priv struct DispatchNumericCallRealmCleanup {
  cleared_realm : ClearedActiveCalleeRealmScope
  active_realm : ActiveCalleeRealmValueScope
  parameter_gate : SimpleUserFuncParameterGateScope
}

///|
fn DispatchNumericCallRealmCleanup::DispatchNumericCallRealmCleanup(
  cleared_realm~ : ClearedActiveCalleeRealmScope,
  active_realm~ : ActiveCalleeRealmValueScope,
  parameter_gate~ : SimpleUserFuncParameterGateScope,
) -> DispatchNumericCallRealmCleanup {
  { cleared_realm, active_realm, parameter_gate }
}

///|
priv enum DispatchShellCleanupResources {
  DispatchProgramRealmCleanup(FunctionRealmProtos)
  DispatchNumericRootRealmCleanup(FunctionRealmProtos)
  DispatchNumericRealmCleanup(DispatchNumericCallRealmCleanup)
}

///|
priv struct ProgramRealmCleanup {
  id : Int
  owner : ProgramCleanupOwner
  resources : DispatchShellCleanupResources
  capabilities : DispatchNumericActivationCapabilities?
}

///|
priv struct PrimitiveProgramDispatchShell {
  interp : Interpreter
  cleanup_stack : Array[ProgramRealmCleanup]
  numeric_root_preflight : NumericRecursionPreflight?
  mut numeric_registry : TrustedNumericRecursionRegistry?
  mut next_cleanup_id : Int
}

///|
fn PrimitiveProgramDispatchShell::PrimitiveProgramDispatchShell(
  interp : Interpreter,
  numeric_root_preflight? : NumericRecursionPreflight? = None,
  numeric_registry? : TrustedNumericRecursionRegistry? = None,
) -> PrimitiveProgramDispatchShell {
  {
    interp,
    cleanup_stack: [],
    numeric_root_preflight,
    numeric_registry,
    next_cleanup_id: 0,
  }
}

///|
fn activation_dispatch_leaf_expression_is_admissible(expr : @ast.Expr) -> Bool {
  match expr {
    @ast.NumberLit(_, _, _)
    | @ast.StringLit(_, _, _, _)
    | @ast.BoolLit(_, _)
    | @ast.NullLit(_)
    | @ast.UndefinedLit(_) => true
    _ => false
  }
}

///|
fn activation_dispatch_leaf_statement_is_admissible(stmt : @ast.Stmt) -> Bool {
  match stmt {
    @ast.ExprStmt(expr, _) | @ast.ThrowStmt(expr, _) =>
      activation_dispatch_leaf_expression_is_admissible(expr)
    _ => false
  }
}

///|
fn activation_dispatch_leaf_program_is_admissible(
  stmts : Array[@ast.Stmt],
) -> Bool {
  for stmt in stmts {
    guard activation_dispatch_leaf_statement_is_admissible(stmt) else {
      return false
    }
  }
  true
}

///|
fn Interpreter::prepare_root_program_execution(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  env : Environment,
  strict : Bool,
) -> Unit raise Error {
  self.validate_block_early_errors(stmts, strict)
  self.hoist_declarations(stmts, env, strict~)
  hoist_block_tdz(stmts, env)
}

///|
fn dispatch_entry_rejection(error : Error) -> DispatchEntryRejection {
  if is_js_catchable_error(error) {
    DispatchEntryGuestThrow(error)
  } else {
    DispatchEntryRuntimeAbrupt(error)
  }
}

///|
fn dispatch_work_error_completion(error : Error) -> DispatchCompletion {
  if is_js_catchable_error(error) {
    DispatchThrow(error)
  } else {
    DispatchRuntimeAbrupt(error)
  }
}

///|
fn dispatch_signal_completion(signal : Signal) -> DispatchCompletion {
  match signal {
    Normal(value) => DispatchNormal(value)
    ReturnSignal(value) => DispatchReturn(value)
    BreakSignal(value, label) => DispatchBreak(value, label)
    ContinueSignal(value, label) => DispatchContinue(value, label)
  }
}

///|
fn program_cleanup_owner_is_accepted(owner : ProgramCleanupOwner) -> Bool {
  match owner {
    AcceptedProgram | AcceptedNumericCall => true
    RejectedProgram | RejectedNumericCall => false
  }
}

///|
fn PrimitiveProgramDispatchShell::reserve_program_cleanup_id(
  self : PrimitiveProgramDispatchShell,
) -> Int raise InvalidActivationDispatchShell {
  guard self.next_cleanup_id >= 0 &&
    self.next_cleanup_id < MAX_DISPATCH_CLEANUP_ID else {
    invalid_activation_dispatch_shell("cleanup generation is exhausted")
  }
  let id = self.next_cleanup_id
  self.next_cleanup_id += 1
  id
}

///|
fn PrimitiveProgramDispatchShell::push_program_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  owner : ProgramCleanupOwner,
  previous_realm_protos : FunctionRealmProtos,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner,
    resources: DispatchProgramRealmCleanup(previous_realm_protos),
    capabilities: None,
  })
}

///|
fn PrimitiveProgramDispatchShell::push_numeric_root_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  previous_realm_protos : FunctionRealmProtos,
  capabilities : DispatchNumericActivationCapabilities,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner: AcceptedProgram,
    resources: DispatchNumericRootRealmCleanup(previous_realm_protos),
    capabilities: Some(capabilities),
  })
}

///|
fn PrimitiveProgramDispatchShell::push_numeric_call_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  owner : ProgramCleanupOwner,
  resources : DispatchNumericCallRealmCleanup,
  capabilities : DispatchNumericActivationCapabilities?,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner,
    resources: DispatchNumericRealmCleanup(resources),
    capabilities,
  })
}

///|
fn dispatch_cleanup_failure(completion : DispatchCompletion) -> Error? {
  match completion {
    DispatchThrow(error) | DispatchRuntimeAbrupt(error) => Some(error)
    _ => None
  }
}

///|
fn PrimitiveProgramDispatchShell::restore_cleanup_record(
  self : PrimitiveProgramDispatchShell,
  cleanup : ProgramRealmCleanup,
  failure : Error?,
) -> Unit {
  match cleanup.resources {
    DispatchProgramRealmCleanup(previous_realm_protos) =>
      apply_active_realm_protos(self.interp.realm_state, previous_realm_protos)
    DispatchNumericRootRealmCleanup(previous_realm_protos) => {
      self.numeric_registry = None
      apply_active_realm_protos(self.interp.realm_state, previous_realm_protos)
    }
    DispatchNumericRealmCleanup(resources) => {
      self.interp.finish_simple_user_func_parameter_gate(
        resources.parameter_gate,
      )
      finish_active_callee_realm_value(
        self.interp.realm_state,
        resources.active_realm,
        failure~,
      )
      finish_cleared_active_callee_realm(
        self.interp.realm_state,
        resources.cleared_realm,
      )
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::consume_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  accepted : Bool,
  completion : DispatchCompletion,
) -> Unit raise InvalidActivationDispatchShell {
  guard !self.cleanup_stack.is_empty() else {
    invalid_activation_dispatch_shell(
      "cleanup is stale, duplicated, or outside LIFO order",
    )
  }
  let cleanup = self.cleanup_stack[self.cleanup_stack.length() - 1]
  guard id == cleanup.id else {
    invalid_activation_dispatch_shell(
      "cleanup is stale, duplicated, or outside LIFO order",
    )
  }
  guard program_cleanup_owner_is_accepted(cleanup.owner) == accepted else {
    invalid_activation_dispatch_shell("cleanup owner does not match its exit")
  }
  self.restore_cleanup_record(cleanup, dispatch_cleanup_failure(completion))
  let _ = self.cleanup_stack.pop()
}

///|
fn PrimitiveProgramDispatchShell::restore_all_cleanup(
  self : PrimitiveProgramDispatchShell,
  failure? : Error? = None,
) -> Unit {
  while !self.cleanup_stack.is_empty() {
    match self.cleanup_stack.pop() {
      Some(cleanup) => self.restore_cleanup_record(cleanup, failure)
      None => ()
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::require_numeric_registry(
  self : PrimitiveProgramDispatchShell,
) -> TrustedNumericRecursionRegistry raise InvalidActivationDispatchShell {
  match self.numeric_registry {
    Some(registry) => registry
    None =>
      invalid_activation_dispatch_shell(
        "numeric activation requires a sealed trust registry",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::require_numeric_capabilities(
  self : PrimitiveProgramDispatchShell,
  id : Int,
) -> DispatchNumericActivationCapabilities raise InvalidActivationDispatchShell {
  guard !self.cleanup_stack.is_empty() else {
    invalid_activation_dispatch_shell(
      "numeric capability is stale or outside LIFO activation ownership",
    )
  }
  let cleanup = self.cleanup_stack[self.cleanup_stack.length() - 1]
  guard cleanup.id == id && program_cleanup_owner_is_accepted(cleanup.owner) else {
    invalid_activation_dispatch_shell(
      "numeric capability is stale or outside LIFO activation ownership",
    )
  }
  match cleanup.capabilities {
    Some(capabilities) => capabilities
    None =>
      invalid_activation_dispatch_shell(
        "activation does not own numeric capabilities",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::complete_numeric_root_preparation(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  cursor : DispatchStatementCursor,
  previous_realm_protos : FunctionRealmProtos,
  preflight : NumericRecursionPreflight,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let capabilities = DispatchNumericActivationCapabilities(
    parameter=None,
    recursive_callee=DispatchNumericCalleeUnresolved(preflight.plan.entry.name),
  )
  self.push_numeric_root_cleanup(id, previous_realm_protos, capabilities)
  let registry = self.interp.seal_numeric_recursion_registry(
    preflight,
    cursor.stmts,
  )
  self.numeric_registry = Some(registry)
  let capture = DispatchCalleeCaptureToken(id~)
  DispatchNumericProgramAccepted(
    DispatchActivationCleanup(id),
    numeric_recursion_program_dispatch_start(registry.plan, capture),
  )
}

///|
fn PrimitiveProgramDispatchShell::enter_program(
  self : PrimitiveProgramDispatchShell,
  cursor : DispatchStatementCursor,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let id = self.reserve_program_cleanup_id()
  let previous_realm_protos = active_realm_protos(self.interp.realm_state)
  apply_active_realm_protos(
    self.interp.realm_state,
    empty_function_realm_protos(),
  )
  let setup : Result[Unit, Error] = Ok(
    self.interp.prepare_root_program_execution(
      cursor.stmts,
      cursor.env,
      cursor.ctx.strict,
    ),
  ) catch {
    error => Err(error)
  }
  match setup {
    Ok(_) =>
      match self.numeric_root_preflight {
        Some(preflight) =>
          self.complete_numeric_root_preparation(
            id, cursor, previous_realm_protos, preflight,
          )
        None => {
          self.push_program_cleanup(id, AcceptedProgram, previous_realm_protos)
          DispatchProgramAccepted(DispatchActivationCleanup(id))
        }
      }
    Err(error) => {
      self.push_program_cleanup(id, RejectedProgram, previous_realm_protos)
      DispatchActivationRejected(
        DispatchRejectedEntryCleanup(id),
        dispatch_entry_rejection(error),
      )
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::enter_numeric_call(
  self : PrimitiveProgramDispatchShell,
  request : DispatchCallRequest,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_numeric_registry()
  guard request.this_value is Undefined else {
    invalid_activation_dispatch_shell(
      "numeric activation requires an undefined receiver",
    )
  }
  guard request.args.length() == 1 else {
    invalid_activation_dispatch_shell(
      "numeric activation requires exactly one argument",
    )
  }
  let argument = match request.args[0] {
    Number(value) => value
    _ =>
      invalid_activation_dispatch_shell(
        "numeric activation requires a number argument",
      )
  }
  let syntax = registry.require_callee(self.interp, request.callee)
  guard request.callee is Object(callee_object) else {
    invalid_activation_dispatch_shell(
      "trusted numeric callee lost its function object",
    )
  }
  guard callee_object.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "trusted numeric callee lost its UserFunc provenance",
    )
  }
  let id = self.reserve_program_cleanup_id()
  let cleared_realm = begin_cleared_active_callee_realm(self.interp.realm_state)
  let active_realm = begin_active_callee_realm_value(
    self.interp.realm_state,
    request.callee,
  )
  let parameter_gate = self.interp.begin_simple_user_func_parameter_gate()
  let setup : Result[PreparedUserFuncActivation, Error] = Ok(
    self.interp.prepare_user_func_activation(
      request.callee,
      request.this_value,
      [Number(argument)],
      data,
      throw_type_error_source=UsePreResolvedThrowTypeError(
        registry.throw_type_error,
      ),
    ),
  ) catch {
    error => Err(error)
  }
  let resources = DispatchNumericCallRealmCleanup(
    cleared_realm~,
    active_realm~,
    parameter_gate~,
  )
  self.complete_numeric_call_preparation(id, syntax, resources, setup)
}

///|
// Converts the caught preparation result into exactly one accepted or rejected
// cleanup owner. The current sealed numeric syntax is expected to prepare
// without error; keeping this boundary explicit preserves balanced cleanup if
// preparation gains another fallible step.
fn PrimitiveProgramDispatchShell::complete_numeric_call_preparation(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  syntax : NumericRecursionFunctionPlan,
  resources : DispatchNumericCallRealmCleanup,
  setup : Result[PreparedUserFuncActivation, Error],
) -> DispatchEffectResult {
  match setup {
    Ok(prepared) => {
      let capabilities = DispatchNumericActivationCapabilities(
        parameter=Some(
          DispatchNumericParameterCapability(
            env=prepared.env,
            name=syntax.parameter,
          ),
        ),
        recursive_callee=DispatchNumericCalleeUnresolved(
          syntax.recursive_callee,
        ),
      )
      self.push_numeric_call_cleanup(
        id,
        AcceptedNumericCall,
        resources,
        Some(capabilities),
      )
      DispatchCallAccepted(
        DispatchActivationCleanup(id),
        DispatchNumericCall(
          DispatchNumericCallStart(
            parameter=DispatchParameterBindingToken(id~),
            recursive_callee=DispatchCalleeCaptureToken(id~),
            recipe=syntax.expression_recipe,
          ),
        ),
      )
    }
    Err(error) => {
      self.push_numeric_call_cleanup(id, RejectedNumericCall, resources, None)
      DispatchActivationRejected(
        DispatchRejectedEntryCleanup(id),
        dispatch_entry_rejection(error),
      )
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::observe_numeric_execution_step(
  self : PrimitiveProgramDispatchShell,
) -> DispatchEffectResult {
  let observed : Result[Unit, Error] = Ok(self.interp.observe_execution_step()) catch {
    error => Err(error)
  }
  match observed {
    Ok(_) => DispatchWorkCompleted(DispatchNormal(Undefined))
    Err(error) => DispatchWorkCompleted(dispatch_work_error_completion(error))
  }
}

///|
fn PrimitiveProgramDispatchShell::read_numeric_parameter(
  self : PrimitiveProgramDispatchShell,
  token : DispatchParameterBindingToken,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let capabilities = self.require_numeric_capabilities(token.id)
  let parameter = match capabilities.parameter {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "numeric activation does not own a parameter capability",
      )
  }
  guard parameter.env.bindings.get(parameter.name) is Some(binding) &&
    binding.initialized &&
    binding.kind == LetBinding &&
    binding.is_parameter else {
    invalid_activation_dispatch_shell(
      "numeric parameter binding lost its trusted provenance",
    )
  }
  DispatchWorkCompleted(DispatchNormal(binding.value))
}

///|
fn PrimitiveProgramDispatchShell::capture_numeric_callee(
  self : PrimitiveProgramDispatchShell,
  token : DispatchCalleeCaptureToken,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_numeric_registry()
  let capabilities = self.require_numeric_capabilities(token.id)
  match capabilities.recursive_callee {
    DispatchNumericCalleeUnresolved(name) => {
      let callee = registry.require_named(self.interp, name)
      capabilities.recursive_callee = DispatchNumericCalleeCaptured(callee)
      DispatchWorkCompleted(DispatchNormal(Undefined))
    }
    DispatchNumericCalleeCaptured(_) | DispatchNumericCalleeConsumed =>
      invalid_activation_dispatch_shell(
        "numeric callee capture capability was already consumed",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::start_captured_numeric_call(
  self : PrimitiveProgramDispatchShell,
  token : DispatchCalleeCaptureToken,
  argument : Double,
  loc : @token.Loc,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_numeric_registry()
  let capabilities = self.require_numeric_capabilities(token.id)
  let callee = match capabilities.recursive_callee {
    DispatchNumericCalleeCaptured(found) => found
    DispatchNumericCalleeUnresolved(_) =>
      invalid_activation_dispatch_shell(
        "numeric callee must be captured before call start",
      )
    DispatchNumericCalleeConsumed =>
      invalid_activation_dispatch_shell(
        "numeric callee call-start capability was already consumed",
      )
  }
  let _ = registry.require_callee(self.interp, callee)
  capabilities.recursive_callee = DispatchNumericCalleeConsumed
  DispatchWorkSuspended(
    DispatchSuspendCall(
      DispatchCallRequest(
        callee~,
        this_value=Undefined,
        args=[Number(argument)],
        loc~,
      ),
      DispatchDeliverCallResult,
    ),
  )
}

///|
fn PrimitiveProgramDispatchShell::apply_numeric_binary(
  self : PrimitiveProgramDispatchShell,
  binary : DispatchBinaryResume,
  right : Value,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  ignore(self)
  let left_number = match binary.left {
    Number(value) => value
    _ =>
      invalid_activation_dispatch_shell(
        "numeric binary left operand is not a number",
      )
  }
  let right_number = match right {
    Number(value) => value
    _ =>
      invalid_activation_dispatch_shell(
        "numeric binary right operand is not a number",
      )
  }
  let result : Value = match binary.op {
    @ast.Add => Number(left_number + right_number)
    @ast.Sub => Number(left_number - right_number)
    @ast.EqEqEq => Bool(left_number == right_number)
    _ =>
      invalid_activation_dispatch_shell(
        "numeric binary operator is outside the closed dispatch set",
      )
  }
  DispatchWorkCompleted(DispatchNormal(result))
}

///|
fn PrimitiveProgramDispatchShell::execute_leaf_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  guard activation_dispatch_leaf_statement_is_admissible(step.stmt) else {
    invalid_activation_dispatch_shell(
      "managed leaf execution received an unsupported statement",
    )
  }
  let result : Result[Signal, Error] = Ok(
    self.interp.exec_stmt(step.ctx, step.stmt, step.env),
  ) catch {
    error => Err(error)
  }
  match result {
    Ok(signal) => DispatchWorkCompleted(dispatch_signal_completion(signal))
    Err(error) => DispatchWorkCompleted(dispatch_work_error_completion(error))
  }
}

///|
fn PrimitiveProgramDispatchShell::perform_effect(
  self : PrimitiveProgramDispatchShell,
  effect : DispatchEffect,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  match effect {
    DispatchEnterActivation(DispatchProgramActivation(cursor)) =>
      self.enter_program(cursor)
    DispatchEnterActivation(DispatchCallActivation(request)) =>
      self.enter_numeric_call(request)
    DispatchRun(DispatchExecuteStatement(step)) =>
      self.execute_leaf_statement(step)
    DispatchRun(DispatchObserveExpressionStep(observation)) => {
      ignore(observation)
      self.observe_numeric_execution_step()
    }
    DispatchRun(DispatchObserveStatementStep(observation)) => {
      ignore(observation)
      self.observe_numeric_execution_step()
    }
    DispatchRun(DispatchReadNumericParameter(token)) =>
      self.read_numeric_parameter(token)
    DispatchRun(DispatchCaptureTrustedCallee(token)) =>
      self.capture_numeric_callee(token)
    DispatchRun(DispatchStartCapturedNumericCall(token, argument, loc)) =>
      self.start_captured_numeric_call(token, argument, loc)
    DispatchRun(
      DispatchResumeContinuation(DispatchApplyBinaryRight(binary), right)
    ) => self.apply_numeric_binary(binary, right)
    DispatchRun(_) =>
      invalid_activation_dispatch_shell(
        "program shell received unsupported managed work",
      )
    DispatchReleaseActivation(cleanup, completion) => {
      self.consume_cleanup(cleanup.id, true, completion)
      DispatchCleanupCompleted
    }
    DispatchRollbackRejectedEntry(cleanup, completion) => {
      self.consume_cleanup(cleanup.id, false, completion)
      DispatchCleanupCompleted
    }
    DispatchRestorePropertyScope(_, _) =>
      invalid_activation_dispatch_shell(
        "program shell cannot restore a property scope",
      )
    DispatchNormalizeEscapedControl(_) =>
      invalid_activation_dispatch_shell(
        "program shell cannot normalize function control",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::drive(
  self : PrimitiveProgramDispatchShell,
  request : DispatchActivationRequest,
) -> DispatchCompletion raise Error {
  let mut state = ActivationDispatchState::ActivationDispatchState()
  let mut event = DispatchStart(request)
  for ;; {
    let (next_state, decision) = reduce_activation_dispatch(state, event)
    state = next_state
    match decision {
      DispatchFinish(completion) => return completion
      DispatchPerform(ticket, effect) => {
        let result = self.perform_effect(effect)
        event = DispatchEffectCompleted(ticket, result)
      }
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::drive_root_program(
  self : PrimitiveProgramDispatchShell,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
) -> DispatchCompletion raise Error {
  try {
    let completion = self.drive(
      DispatchProgramActivation(
        DispatchStatementCursor(ctx~, stmts~, env=self.interp.global),
      ),
    )
    guard self.cleanup_stack.is_empty() else {
      invalid_activation_dispatch_shell(
        "dispatch finished while cleanup ownership remained",
      )
    }
    completion
  } catch {
    error => {
      self.restore_all_cleanup(failure=Some(error))
      raise error
    }
  }
}

///|
fn Interpreter::run_activation_dispatch_leaf_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
) -> DispatchCompletion raise Error {
  guard activation_dispatch_leaf_program_is_admissible(stmts) else {
    invalid_activation_dispatch_shell(
      "program admission must succeed before managed execution starts",
    )
  }
  PrimitiveProgramDispatchShell(self).drive_root_program(stmts, ctx)
}

///|
fn Interpreter::run_activation_dispatch_numeric_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
  preflight : NumericRecursionPreflight,
) -> DispatchCompletion raise Error {
  let shell = PrimitiveProgramDispatchShell(
    self,
    numeric_root_preflight=Some(preflight),
  )
  let completion = shell.drive_root_program(stmts, ctx)
  guard shell.numeric_registry is None else {
    invalid_activation_dispatch_shell(
      "numeric registry outlived its root activation",
    )
  }
  completion
}

///|
fn activation_dispatch_root_value(
  completion : DispatchCompletion,
) -> Value raise Error {
  match completion {
    DispatchNormal(value) => value
    DispatchReturn(_) =>
      raise @errors.SyntaxError(message="return statement outside of function")
    DispatchBreak(value, label) => {
      raise_if_break_continue(BreakSignal(value, label))
      Undefined
    }
    DispatchContinue(value, label) => {
      raise_if_break_continue(ContinueSignal(value, label))
      Undefined
    }
    DispatchThrow(error) | DispatchRuntimeAbrupt(error) => raise error
  }
}
