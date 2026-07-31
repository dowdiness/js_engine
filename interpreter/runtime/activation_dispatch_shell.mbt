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
  AcceptedGetterCall
  RejectedGetterCall
  AcceptedProxyCall
  RejectedProxyCall
  PropertyAccessCleanup
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
#warnings("-unused_field")
priv struct DispatchNumericCatchBindingCapability {
  env : Environment
  name : String
}

///|
#warnings("-unused_value")
fn DispatchNumericCatchBindingCapability::DispatchNumericCatchBindingCapability(
  env~ : Environment,
  name~ : String,
) -> DispatchNumericCatchBindingCapability {
  { env, name }
}

///|
#warnings("-unused_constructor-unused_field")
priv enum DispatchNumericCatchBindingState {
  DispatchNumericCatchBindingDisabled
  DispatchNumericCatchBindingArmed
  DispatchNumericCatchBindingAvailable(DispatchNumericCatchBindingCapability)
  DispatchNumericCatchBindingConsumed
}

///|
priv struct DispatchNumericActivationCapabilities {
  parameter : DispatchNumericParameterCapability?
  mut recursive_callee : DispatchNumericCalleeCaptureState
  mut catch_binding : DispatchNumericCatchBindingState
}

///|
fn DispatchNumericActivationCapabilities::DispatchNumericActivationCapabilities(
  parameter~ : DispatchNumericParameterCapability?,
  recursive_callee~ : DispatchNumericCalleeCaptureState,
  catch_binding~ : DispatchNumericCatchBindingState,
) -> DispatchNumericActivationCapabilities {
  { parameter, recursive_callee, catch_binding }
}

///|
fn numeric_recursion_root_catch_binding_state(
  root_control : NumericRecursionRootControlRecipe,
) -> DispatchNumericCatchBindingState {
  match root_control {
    NumericRecursionProtectedRoot(
      { catch_recipe: NumericRecursionCatch(_, _), .. }
    ) => DispatchNumericCatchBindingArmed
    NumericRecursionDirectRoot
    | NumericRecursionProtectedRoot(
      { catch_recipe: NumericRecursionNoCatch, .. }
    ) => DispatchNumericCatchBindingDisabled
  }
}

///|
fn retire_numeric_catch_binding(
  capabilities : DispatchNumericActivationCapabilities,
) -> Unit {
  match capabilities.catch_binding {
    DispatchNumericCatchBindingArmed
    | DispatchNumericCatchBindingAvailable(_) =>
      capabilities.catch_binding = DispatchNumericCatchBindingConsumed
    DispatchNumericCatchBindingDisabled | DispatchNumericCatchBindingConsumed =>
      ()
  }
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
priv struct DispatchGetterCallRealmCleanup {
  cleared_realm : ClearedActiveCalleeRealmScope
  active_realm : ActiveCalleeRealmValueScope
  parameter_gate : SimpleUserFuncParameterGateScope
}

///|
fn DispatchGetterCallRealmCleanup::DispatchGetterCallRealmCleanup(
  cleared_realm~ : ClearedActiveCalleeRealmScope,
  active_realm~ : ActiveCalleeRealmValueScope,
  parameter_gate~ : SimpleUserFuncParameterGateScope,
) -> DispatchGetterCallRealmCleanup {
  { cleared_realm, active_realm, parameter_gate }
}

///|
priv struct DispatchProxyCallRealmCleanup {
  cleared_realm : ClearedActiveCalleeRealmScope
  active_realm : ActiveCalleeRealmValueScope
  parameter_gate : SimpleUserFuncParameterGateScope
}

///|
fn DispatchProxyCallRealmCleanup::DispatchProxyCallRealmCleanup(
  cleared_realm~ : ClearedActiveCalleeRealmScope,
  active_realm~ : ActiveCalleeRealmValueScope,
  parameter_gate~ : SimpleUserFuncParameterGateScope,
) -> DispatchProxyCallRealmCleanup {
  { cleared_realm, active_realm, parameter_gate }
}

///|
priv enum DispatchShellCleanupResources {
  DispatchProgramRealmCleanup(FunctionRealmProtos)
  DispatchControlRootRealmCleanup(FunctionRealmProtos)
  DispatchNumericRootRealmCleanup(FunctionRealmProtos)
  DispatchGetterRootRealmCleanup(FunctionRealmProtos)
  DispatchProxyRootRealmCleanup(FunctionRealmProtos)
  DispatchDeniedActivationCleanup
  DispatchNumericRealmCleanup(DispatchNumericCallRealmCleanup)
  DispatchGetterRealmCleanup(DispatchGetterCallRealmCleanup)
  DispatchProxyRealmCleanup(DispatchProxyCallRealmCleanup)
  DispatchPropertyRealmCleanup(ClearedActiveCalleeRealmScope)
}

///|
priv struct ProgramRealmCleanup {
  id : Int
  owner : ProgramCleanupOwner
  resources : DispatchShellCleanupResources
  capabilities : DispatchNumericActivationCapabilities?
  observation : ActivationObservationToken?
}

///|
priv struct PrimitiveProgramDispatchShell {
  interp : Interpreter
  cleanup_stack : Array[ProgramRealmCleanup]
  mut control_root_preflight : ControlLifecyclePreflight?
  mut control_registry : TrustedControlLifecycleProgram?
  mut control_phase : ControlLifecyclePhase
  mut control_try_env : Environment?
  mut control_finalizer_env : Environment?
  numeric_root_preflight : NumericRecursionPreflight?
  mut numeric_registry : TrustedNumericRecursionRegistry?
  getter_root_preflight : GetterRecursionPreflight?
  getter_root_stmts : Array[@ast.Stmt]?
  mut getter_registry : TrustedGetterRecursionRegistry?
  proxy_root_preflight : ProxyGetRecursionPreflight?
  proxy_root_stmts : Array[@ast.Stmt]?
  mut proxy_registry : TrustedProxyGetRecursionRegistry?
  activation_observation_port : ActivationObservationPort
  mut next_cleanup_id : Int
}

///|
fn PrimitiveProgramDispatchShell::PrimitiveProgramDispatchShell(
  interp : Interpreter,
  control_root_preflight? : ControlLifecyclePreflight? = None,
  numeric_root_preflight? : NumericRecursionPreflight? = None,
  numeric_registry? : TrustedNumericRecursionRegistry? = None,
  getter_root_preflight? : GetterRecursionPreflight? = None,
  getter_root_stmts? : Array[@ast.Stmt]? = None,
  getter_registry? : TrustedGetterRecursionRegistry? = None,
  proxy_root_preflight? : ProxyGetRecursionPreflight? = None,
  proxy_root_stmts? : Array[@ast.Stmt]? = None,
  proxy_registry? : TrustedProxyGetRecursionRegistry? = None,
  activation_observation_port? : ActivationObservationPort = interp.execution_control_activation_observation_port(),
) -> PrimitiveProgramDispatchShell {
  {
    interp,
    cleanup_stack: [],
    control_root_preflight,
    control_registry: None,
    control_phase: ControlAwaitRoot,
    control_try_env: None,
    control_finalizer_env: None,
    numeric_root_preflight,
    numeric_registry,
    getter_root_preflight,
    getter_root_stmts: getter_root_stmts.map(stmts => stmts.copy()),
    getter_registry,
    proxy_root_preflight,
    proxy_root_stmts: proxy_root_stmts.map(stmts => stmts.copy()),
    proxy_registry,
    activation_observation_port,
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
  match error {
    ExecutionControlError(StackDepthLimit) =>
      DispatchEntryRuntimeAbrupt(
        @errors.RangeError(message=STACK_DEPTH_LIMIT_MESSAGE),
      )
    _ =>
      if is_js_catchable_error(error) {
        DispatchEntryGuestThrow(error)
      } else {
        DispatchEntryRuntimeAbrupt(error)
      }
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
fn activation_cleanup_owner_is_accepted(owner : ProgramCleanupOwner) -> Bool {
  match owner {
    AcceptedProgram | AcceptedNumericCall => true
    RejectedProgram
    | RejectedNumericCall
    | AcceptedGetterCall
    | RejectedGetterCall
    | AcceptedProxyCall
    | RejectedProxyCall
    | PropertyAccessCleanup => false
  }
}

///|
fn activation_cleanup_owner_matches(
  owner : ProgramCleanupOwner,
  accepted : Bool,
) -> Bool {
  match (owner, accepted) {
    (AcceptedProgram, true)
    | (AcceptedNumericCall, true)
    | (AcceptedGetterCall, true)
    | (AcceptedProxyCall, true) => true
    (RejectedProgram, false)
    | (RejectedNumericCall, false)
    | (RejectedGetterCall, false)
    | (RejectedProxyCall, false) => true
    _ => false
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
fn PrimitiveProgramDispatchShell::begin_managed_activation_observation(
  self : PrimitiveProgramDispatchShell,
) -> Result[ActivationEntryAttempt, Error] {
  Ok(observe_activation_entry(self.activation_observation_port)) catch {
    error => Err(error)
  }
}

///|
fn accept_managed_activation_observation(
  attempt : ActivationEntryAttempt,
) -> ActivationObservationToken raise InvalidActivationDispatchShell {
  attempt.accept() catch {
    InvalidActivationObservationTransition(message) =>
      invalid_activation_dispatch_shell(
        "managed activation acceptance is invalid: " + message,
      )
  }
}

///|
fn reject_managed_activation_observation(
  attempt : ActivationEntryAttempt,
) -> Unit raise InvalidActivationDispatchShell {
  attempt.reject() catch {
    InvalidActivationObservationTransition(message) =>
      invalid_activation_dispatch_shell(
        "managed activation rejection is invalid: " + message,
      )
  }
}

///|
fn release_managed_activation_observation(
  token : ActivationObservationToken,
) -> Unit raise InvalidActivationDispatchShell {
  token.release() catch {
    InvalidActivationObservationTransition(message) =>
      invalid_activation_dispatch_shell(
        "managed activation release is invalid: " + message,
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::reject_denied_managed_activation(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  owner : ProgramCleanupOwner,
  error : Error,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  match owner {
    RejectedNumericCall | RejectedGetterCall | RejectedProxyCall => ()
    _ =>
      invalid_activation_dispatch_shell(
        "denied activation requires a rejected call owner",
      )
  }
  self.cleanup_stack.push({
    id,
    owner,
    resources: DispatchDeniedActivationCleanup,
    capabilities: None,
    observation: None,
  })
  DispatchActivationRejected(
    DispatchRejectedEntryCleanup(id),
    dispatch_entry_rejection(error),
  )
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
    observation: None,
  })
}

///|
fn PrimitiveProgramDispatchShell::push_control_root_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  previous_realm_protos : FunctionRealmProtos,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner: AcceptedProgram,
    resources: DispatchControlRootRealmCleanup(previous_realm_protos),
    capabilities: None,
    observation: None,
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
    observation: None,
  })
}

///|
fn PrimitiveProgramDispatchShell::push_numeric_call_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  owner : ProgramCleanupOwner,
  resources : DispatchNumericCallRealmCleanup,
  capabilities : DispatchNumericActivationCapabilities?,
  observation : ActivationObservationToken?,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner,
    resources: DispatchNumericRealmCleanup(resources),
    capabilities,
    observation,
  })
}

///|
fn PrimitiveProgramDispatchShell::push_getter_root_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  previous_realm_protos : FunctionRealmProtos,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner: AcceptedProgram,
    resources: DispatchGetterRootRealmCleanup(previous_realm_protos),
    capabilities: None,
    observation: None,
  })
}

///|
fn PrimitiveProgramDispatchShell::push_getter_call_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  owner : ProgramCleanupOwner,
  resources : DispatchGetterCallRealmCleanup,
  observation : ActivationObservationToken?,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner,
    resources: DispatchGetterRealmCleanup(resources),
    capabilities: None,
    observation,
  })
}

///|
fn PrimitiveProgramDispatchShell::push_proxy_root_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  previous_realm_protos : FunctionRealmProtos,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner: AcceptedProgram,
    resources: DispatchProxyRootRealmCleanup(previous_realm_protos),
    capabilities: None,
    observation: None,
  })
}

///|
fn PrimitiveProgramDispatchShell::push_proxy_call_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  owner : ProgramCleanupOwner,
  resources : DispatchProxyCallRealmCleanup,
  observation : ActivationObservationToken?,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner,
    resources: DispatchProxyRealmCleanup(resources),
    capabilities: None,
    observation,
  })
}

///|
fn PrimitiveProgramDispatchShell::push_property_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  scope : ClearedActiveCalleeRealmScope,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner: PropertyAccessCleanup,
    resources: DispatchPropertyRealmCleanup(scope),
    capabilities: None,
    observation: None,
  })
}

///|
fn PrimitiveProgramDispatchShell::begin_property_scope(
  self : PrimitiveProgramDispatchShell,
) -> DispatchPropertyCleanup raise InvalidActivationDispatchShell {
  let id = self.reserve_program_cleanup_id()
  let scope = begin_cleared_active_callee_realm(self.interp.realm_state)
  self.push_property_cleanup(id, scope)
  DispatchPropertyCleanup(id)
}

///|
fn PrimitiveProgramDispatchShell::start_property(
  self : PrimitiveProgramDispatchShell,
  work : DispatchPropertyGetResume,
  consumer : DispatchContinuation,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let cleanup = self.begin_property_scope()
  DispatchWorkSuspended(DispatchSuspendProperty(cleanup, work, consumer))
}

///|
fn execute_dispatch_ordinary_property(
  work : DispatchPropertyGetResume,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  match dispatch_ordinary_property_lookup(work) {
    DispatchOrdinaryPropertyValue(value) =>
      DispatchWorkCompleted(DispatchNormal(value))
    DispatchOrdinaryPropertyGetter(getter) =>
      DispatchWorkSuspended(
        DispatchSuspendCall(
          DispatchCallRequest(
            callee=getter,
            this_value=work.receiver,
            args=[],
            loc=work.loc,
          ),
          DispatchDeliverAccessorResult(work),
        ),
      )
    DispatchOrdinaryPropertyUnsupported =>
      invalid_activation_dispatch_shell(
        "property work requires an ordinary object and canonical string key",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_dispatch_proxy_property(
  self : PrimitiveProgramDispatchShell,
  work : DispatchPropertyGetResume,
  registry : TrustedProxyGetRecursionRegistry,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let capture = registry.capture_get(
    self.interp,
    work.target,
    work.property_key,
    work.receiver,
  )
  let post_trap = DispatchProxyGetResume(
    target=capture.target,
    property_key=capture.property_key,
    receiver=capture.receiver,
    loc=work.loc,
  )
  self.start_property(
    DispatchPropertyGetResume(
      target=capture.handler,
      property_key=String_(PROXY_GET_RECURSION_TRAP_NAME),
      receiver=capture.handler,
      loc=work.loc,
    ),
    DispatchResolveProxyGetTrap(
      DispatchProxyGetTrapLookupResume(
        proxy=capture.proxy,
        handler=capture.handler,
        post_trap~,
      ),
    ),
  )
}

///|
fn PrimitiveProgramDispatchShell::execute_dispatch_property(
  self : PrimitiveProgramDispatchShell,
  work : DispatchPropertyGetResume,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  match (work.target, self.proxy_registry) {
    (Proxy(_), Some(registry)) =>
      self.execute_dispatch_proxy_property(work, registry)
    _ => execute_dispatch_ordinary_property(work)
  }
}

///|
fn PrimitiveProgramDispatchShell::resume_proxy_get_trap(
  self : PrimitiveProgramDispatchShell,
  lookup : DispatchProxyGetTrapLookupResume,
  candidate : Value,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_proxy_registry()
  let capture = TrustedProxyGetCapture(
    proxy=lookup.proxy,
    target=lookup.post_trap.target,
    handler=lookup.handler,
    property_key=lookup.post_trap.property_key,
    receiver=lookup.post_trap.receiver,
  )
  let _ = registry.require_resolved_trap(self.interp, capture, candidate)
  DispatchWorkSuspended(
    DispatchSuspendCall(
      DispatchCallRequest(
        callee=candidate,
        this_value=lookup.handler,
        args=[
          lookup.post_trap.target,
          lookup.post_trap.property_key,
          lookup.post_trap.receiver,
        ],
        loc=lookup.post_trap.loc,
      ),
      DispatchCheckProxyGetResult(lookup.post_trap),
    ),
  )
}

///|
fn PrimitiveProgramDispatchShell::resume_proxy_get_result(
  self : PrimitiveProgramDispatchShell,
  work : DispatchProxyGetResume,
  result : Value,
) -> DispatchEffectResult {
  let validated : Result[Unit, Error] = Ok(
    validate_proxy_get_trap_result(
      self.interp,
      work.target,
      work.property_key,
      result,
    ),
  ) catch {
    error => Err(error)
  }
  match validated {
    Ok(_) => DispatchWorkCompleted(DispatchNormal(result))
    Err(error) => DispatchWorkCompleted(dispatch_work_error_completion(error))
  }
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
) -> Unit raise InvalidActivationDispatchShell {
  match cleanup.capabilities {
    Some(capabilities) => retire_numeric_catch_binding(capabilities)
    None => ()
  }
  match cleanup.resources {
    DispatchProgramRealmCleanup(previous_realm_protos) =>
      apply_active_realm_protos(self.interp.realm_state, previous_realm_protos)
    DispatchControlRootRealmCleanup(previous_realm_protos) => {
      self.control_registry = None
      self.control_try_env = None
      self.control_finalizer_env = None
      apply_active_realm_protos(self.interp.realm_state, previous_realm_protos)
    }
    DispatchNumericRootRealmCleanup(previous_realm_protos) => {
      self.numeric_registry = None
      apply_active_realm_protos(self.interp.realm_state, previous_realm_protos)
    }
    DispatchGetterRootRealmCleanup(previous_realm_protos) => {
      self.getter_registry = None
      apply_active_realm_protos(self.interp.realm_state, previous_realm_protos)
    }
    DispatchProxyRootRealmCleanup(previous_realm_protos) => {
      self.proxy_registry = None
      apply_active_realm_protos(self.interp.realm_state, previous_realm_protos)
    }
    DispatchDeniedActivationCleanup => ()
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
    DispatchGetterRealmCleanup(resources) => {
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
    DispatchProxyRealmCleanup(resources) => {
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
    DispatchPropertyRealmCleanup(scope) =>
      finish_cleared_active_callee_realm(self.interp.realm_state, scope)
  }
  match cleanup.observation {
    Some(token) => release_managed_activation_observation(token)
    None => ()
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
  guard activation_cleanup_owner_matches(cleanup.owner, accepted) else {
    invalid_activation_dispatch_shell("cleanup owner does not match its exit")
  }
  self.restore_cleanup_record(cleanup, dispatch_cleanup_failure(completion))
  let _ = self.cleanup_stack.pop()
}

///|
fn PrimitiveProgramDispatchShell::consume_property_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
) -> Unit raise InvalidActivationDispatchShell {
  guard !self.cleanup_stack.is_empty() else {
    invalid_activation_dispatch_shell(
      "property cleanup is stale, duplicated, or outside LIFO order",
    )
  }
  let cleanup = self.cleanup_stack[self.cleanup_stack.length() - 1]
  guard id == cleanup.id else {
    invalid_activation_dispatch_shell(
      "property cleanup is stale, duplicated, or outside LIFO order",
    )
  }
  guard cleanup.owner is PropertyAccessCleanup else {
    invalid_activation_dispatch_shell(
      "property cleanup does not own the current scope",
    )
  }
  self.restore_cleanup_record(cleanup, None)
  let _ = self.cleanup_stack.pop()
}

///|
fn PrimitiveProgramDispatchShell::restore_all_cleanup(
  self : PrimitiveProgramDispatchShell,
  failure? : Error? = None,
) -> Unit raise InvalidActivationDispatchShell {
  while !self.cleanup_stack.is_empty() {
    match self.cleanup_stack.pop() {
      Some(cleanup) => self.restore_cleanup_record(cleanup, failure)
      None => ()
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::require_control_registry(
  self : PrimitiveProgramDispatchShell,
) -> TrustedControlLifecycleProgram raise InvalidActivationDispatchShell {
  match self.control_registry {
    Some(registry) => registry
    None =>
      invalid_activation_dispatch_shell(
        "control lifecycle registry is unavailable",
      )
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
fn PrimitiveProgramDispatchShell::require_getter_registry(
  self : PrimitiveProgramDispatchShell,
) -> TrustedGetterRecursionRegistry raise InvalidActivationDispatchShell {
  match self.getter_registry {
    Some(registry) => registry
    None =>
      invalid_activation_dispatch_shell(
        "getter activation requires a sealed runtime registry",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::require_proxy_registry(
  self : PrimitiveProgramDispatchShell,
) -> TrustedProxyGetRecursionRegistry raise InvalidActivationDispatchShell {
  match self.proxy_registry {
    Some(registry) => registry
    None =>
      invalid_activation_dispatch_shell(
        "Proxy get activation requires a sealed runtime registry",
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
  guard cleanup.id == id && activation_cleanup_owner_is_accepted(cleanup.owner) else {
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
fn PrimitiveProgramDispatchShell::complete_control_root_preparation(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  cursor : DispatchStatementCursor,
  previous_realm_protos : FunctionRealmProtos,
  preflight : ControlLifecyclePreflight,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  self.push_control_root_cleanup(id, previous_realm_protos)
  self.control_registry = Some(
    seal_control_lifecycle_program(preflight, cursor.stmts, cursor.env),
  )
  self.control_phase = ControlAwaitRoot
  DispatchProgramAccepted(DispatchActivationCleanup(id))
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
    recursive_callee=DispatchNumericCalleeUnresolved(
      preflight.plan.entry.syntax.name,
    ),
    catch_binding=numeric_recursion_root_catch_binding_state(
      preflight.plan.root_control,
    ),
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
    numeric_recursion_program_dispatch_start(
      registry.require_program_plan(),
      capture,
    ),
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
      match
        (
          self.control_root_preflight,
          self.numeric_root_preflight,
          self.getter_root_preflight,
          self.proxy_root_preflight,
        ) {
        (Some(preflight), None, None, None) =>
          self.complete_control_root_preparation(
            id, cursor, previous_realm_protos, preflight,
          )
        (None, Some(preflight), None, None) =>
          self.complete_numeric_root_preparation(
            id, cursor, previous_realm_protos, preflight,
          )
        (None, None, Some(_), None) => {
          self.push_getter_root_cleanup(id, previous_realm_protos)
          DispatchProgramAccepted(DispatchActivationCleanup(id))
        }
        (None, None, None, Some(_)) => {
          self.push_proxy_root_cleanup(id, previous_realm_protos)
          DispatchProgramAccepted(DispatchActivationCleanup(id))
        }
        (None, None, None, None) => {
          self.push_program_cleanup(id, AcceptedProgram, previous_realm_protos)
          DispatchProgramAccepted(DispatchActivationCleanup(id))
        }
        _ =>
          invalid_activation_dispatch_shell(
            "program cannot own multiple activation admissions",
          )
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
  let observation = match self.begin_managed_activation_observation() {
    Ok(attempt) => attempt
    Err(error) =>
      return self.reject_denied_managed_activation(
        id,
        RejectedNumericCall,
        error,
      )
  }
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
  self.complete_numeric_call_preparation(
    id, syntax, resources, observation, setup,
  )
}

///|
fn PrimitiveProgramDispatchShell::enter_getter_call(
  self : PrimitiveProgramDispatchShell,
  request : DispatchCallRequest,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_getter_registry()
  guard request.args.is_empty() else {
    invalid_activation_dispatch_shell(
      "getter activation requires exactly zero arguments",
    )
  }
  let _ = registry.require_getter(
    self.interp,
    request.callee,
    request.this_value,
  )
  guard request.callee is Object(callee_object) &&
    callee_object.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "getter activation lost its exact UserFunc provenance",
    )
  }
  let id = self.reserve_program_cleanup_id()
  let observation = match self.begin_managed_activation_observation() {
    Ok(attempt) => attempt
    Err(error) =>
      return self.reject_denied_managed_activation(
        id,
        RejectedGetterCall,
        error,
      )
  }
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
      [],
      data,
      throw_type_error_source=UsePreResolvedThrowTypeError(
        registry.throw_type_error,
      ),
    ),
  ) catch {
    error => Err(error)
  }
  let resources = DispatchGetterCallRealmCleanup(
    cleared_realm~,
    active_realm~,
    parameter_gate~,
  )
  match setup {
    Ok(prepared) => {
      let token = accept_managed_activation_observation(observation)
      self.push_getter_call_cleanup(
        id,
        AcceptedGetterCall,
        resources,
        Some(token),
      )
      DispatchCallAccepted(
        DispatchActivationCleanup(id),
        DispatchCallBody(
          DispatchStatementCursor(
            ctx=prepared.ctx,
            stmts=data.body,
            env=prepared.env,
          ),
        ),
      )
    }
    Err(error) => {
      reject_managed_activation_observation(observation)
      self.push_getter_call_cleanup(id, RejectedGetterCall, resources, None)
      DispatchActivationRejected(
        DispatchRejectedEntryCleanup(id),
        dispatch_entry_rejection(error),
      )
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::enter_proxy_call(
  self : PrimitiveProgramDispatchShell,
  request : DispatchCallRequest,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_proxy_registry()
  let _ = registry.require_trap_call(
    self.interp,
    request.callee,
    request.this_value,
    request.args,
  )
  guard request.callee is Object(callee_object) &&
    callee_object.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "Proxy get activation lost its exact UserFunc provenance",
    )
  }
  let id = self.reserve_program_cleanup_id()
  let observation = match self.begin_managed_activation_observation() {
    Ok(attempt) => attempt
    Err(error) =>
      return self.reject_denied_managed_activation(id, RejectedProxyCall, error)
  }
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
      request.args,
      data,
      throw_type_error_source=UsePreResolvedThrowTypeError(
        registry.throw_type_error,
      ),
    ),
  ) catch {
    error => Err(error)
  }
  let resources = DispatchProxyCallRealmCleanup(
    cleared_realm~,
    active_realm~,
    parameter_gate~,
  )
  match setup {
    Ok(prepared) => {
      let token = accept_managed_activation_observation(observation)
      self.push_proxy_call_cleanup(
        id,
        AcceptedProxyCall,
        resources,
        Some(token),
      )
      DispatchCallAccepted(
        DispatchActivationCleanup(id),
        DispatchCallBody(
          DispatchStatementCursor(
            ctx=prepared.ctx,
            stmts=data.body,
            env=prepared.env,
          ),
        ),
      )
    }
    Err(error) => {
      reject_managed_activation_observation(observation)
      self.push_proxy_call_cleanup(id, RejectedProxyCall, resources, None)
      DispatchActivationRejected(
        DispatchRejectedEntryCleanup(id),
        dispatch_entry_rejection(error),
      )
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::enter_managed_call(
  self : PrimitiveProgramDispatchShell,
  request : DispatchCallRequest,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  match (self.numeric_registry, self.getter_registry, self.proxy_registry) {
    (Some(_), None, None) => self.enter_numeric_call(request)
    (None, Some(_), None) => self.enter_getter_call(request)
    (None, None, Some(_)) => self.enter_proxy_call(request)
    (None, None, None) =>
      invalid_activation_dispatch_shell(
        "managed call requires one sealed runtime registry",
      )
    _ =>
      invalid_activation_dispatch_shell(
        "managed call cannot select multiple runtime registries",
      )
  }
}

///|
// Converts the caught preparation result into exactly one accepted or rejected
// cleanup owner. The current sealed numeric syntax is expected to prepare
// without error; keeping this boundary explicit preserves balanced cleanup if
// preparation gains another fallible step.
fn PrimitiveProgramDispatchShell::complete_numeric_call_preparation(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  syntax : NumericRecursionFunctionSyntax,
  resources : DispatchNumericCallRealmCleanup,
  observation : ActivationEntryAttempt,
  setup : Result[PreparedUserFuncActivation, Error],
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
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
        catch_binding=DispatchNumericCatchBindingDisabled,
      )
      let token = accept_managed_activation_observation(observation)
      self.push_numeric_call_cleanup(
        id,
        AcceptedNumericCall,
        resources,
        Some(capabilities),
        Some(token),
      )
      DispatchCallAccepted(
        DispatchActivationCleanup(id),
        DispatchNumericCall(
          DispatchNumericCallStart(
            parameter=DispatchParameterBindingToken(id~),
            recursive_callee=DispatchCalleeCaptureToken(id~),
            recipe=syntax.expression_recipe,
            return_recipe=syntax.return_recipe,
          ),
        ),
      )
    }
    Err(error) => {
      reject_managed_activation_observation(observation)
      self.push_numeric_call_cleanup(
        id,
        RejectedNumericCall,
        resources,
        None,
        None,
      )
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
fn PrimitiveProgramDispatchShell::enter_numeric_catch(
  self : PrimitiveProgramDispatchShell,
  catch_state : DispatchNumericCatchResume,
  error : Error,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let capabilities = self.require_numeric_capabilities(catch_state.token.id)
  guard capabilities.catch_binding is DispatchNumericCatchBindingArmed else {
    invalid_activation_dispatch_shell(
      "numeric catch binding was entered more than once",
    )
  }
  match catch_state.parameter {
    None => capabilities.catch_binding = DispatchNumericCatchBindingConsumed
    Some(name) => {
      guard numeric_recursion_identifier_is_safe(name) else {
        return invalid_activation_dispatch_shell(
          "numeric catch binding lost its trusted identifier",
        )
      }
      let catch_env = Environment::new(parent=Some(self.interp.global))
      let caught = js_error_to_value_with_env(error, Some(self.interp.global))
      let setup : Result[Unit, Error] = Ok(
        catch_env.def(name, caught, LetBinding),
      ) catch {
        binding_error => Err(binding_error)
      }
      match setup {
        Ok(_) =>
          capabilities.catch_binding = DispatchNumericCatchBindingAvailable(
            DispatchNumericCatchBindingCapability(env=catch_env, name~),
          )
        Err(_) =>
          invalid_activation_dispatch_shell(
            "numeric catch binding could not be initialized",
          )
      }
    }
  }
  DispatchWorkCompleted(DispatchNormal(Undefined))
}

///|
fn PrimitiveProgramDispatchShell::read_numeric_catch_binding(
  self : PrimitiveProgramDispatchShell,
  token : DispatchNumericCatchBindingToken,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let capabilities = self.require_numeric_capabilities(token.id)
  let binding_capability = match capabilities.catch_binding {
    DispatchNumericCatchBindingAvailable(found) => found
    DispatchNumericCatchBindingDisabled
    | DispatchNumericCatchBindingArmed
    | DispatchNumericCatchBindingConsumed =>
      invalid_activation_dispatch_shell(
        "numeric catch binding is unavailable or already consumed",
      )
  }
  guard binding_capability.env.parent is Some(parent) &&
    physical_equal(parent, self.interp.global) &&
    binding_capability.env.with_object is None &&
    !binding_capability.env.is_var_scope &&
    binding_capability.env.bindings.get(binding_capability.name)
    is Some(binding) &&
    binding.initialized &&
    binding.kind == LetBinding &&
    !binding.is_parameter else {
    invalid_activation_dispatch_shell(
      "numeric catch binding lost its trusted provenance",
    )
  }
  let value = binding.value
  capabilities.catch_binding = DispatchNumericCatchBindingConsumed
  DispatchWorkCompleted(DispatchNormal(value))
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
fn PrimitiveProgramDispatchShell::execute_statement_with_legacy_adapter(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
) -> DispatchEffectResult {
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
fn PrimitiveProgramDispatchShell::observe_managed_execution_steps(
  self : PrimitiveProgramDispatchShell,
  count : Int,
) -> DispatchCompletion? {
  for _ in 0..<count {
    let observed : Result[Unit, Error] = Ok(
      self.interp.observe_execution_step(),
    ) catch {
      error => Err(error)
    }
    match observed {
      Ok(_) => ()
      Err(error) => return Some(dispatch_work_error_completion(error))
    }
  }
  None
}

///|
fn PrimitiveProgramDispatchShell::getter_root_stmts_or_fail(
  self : PrimitiveProgramDispatchShell,
) -> Array[@ast.Stmt] raise InvalidActivationDispatchShell {
  match self.getter_root_stmts {
    Some(stmts) => stmts
    None =>
      invalid_activation_dispatch_shell(
        "getter root statements were not retained by admission",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::proxy_root_stmts_or_fail(
  self : PrimitiveProgramDispatchShell,
) -> Array[@ast.Stmt] raise InvalidActivationDispatchShell {
  match self.proxy_root_stmts {
    Some(stmts) => stmts
    None =>
      invalid_activation_dispatch_shell(
        "Proxy get root statements were not retained by admission",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_getter_root_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  preflight : GetterRecursionPreflight,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  guard physical_equal(step.env, self.interp.global) &&
    getter_recursion_root_statement_matches(
      preflight.plan,
      step.index,
      step.stmt,
    ) else {
    invalid_activation_dispatch_shell(
      "getter root statement no longer matches exact admission",
    )
  }
  let seal_index = getter_recursion_seal_statement_index(preflight.plan)
  let root_index = getter_recursion_root_statement_index(preflight.plan)
  if step.index < seal_index {
    return self.execute_statement_with_legacy_adapter(step)
  }
  if step.index == seal_index {
    let result = self.execute_statement_with_legacy_adapter(step)
    match result {
      DispatchWorkCompleted(DispatchNormal(_)) => {
        let registry = self.interp.seal_getter_recursion_registry(
          preflight,
          self.getter_root_stmts_or_fail(),
        )
        self.getter_registry = Some(registry)
      }
      _ => ()
    }
    return result
  }
  if step.index == root_index {
    match self.observe_managed_execution_steps(3) {
      Some(completion) => return DispatchWorkCompleted(completion)
      None => ()
    }
    let registry = self.require_getter_registry()
    let target = registry.require_target(self.interp)
    return self.start_property(
      DispatchPropertyGetResume(
        target~,
        property_key=String_(preflight.plan.property_name),
        receiver=target,
        loc=preflight.plan.recipe.root_member_loc,
      ),
      DispatchDeliverCallResult,
    )
  }
  invalid_activation_dispatch_shell(
    "getter root statement index is outside exact admission",
  )
}

///|
fn PrimitiveProgramDispatchShell::execute_getter_body_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  registry : TrustedGetterRecursionRegistry,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let plan = registry.plan
  guard getter_recursion_body_statement_matches(plan, step.index, step.stmt) &&
    step.env.parent is Some(parent) &&
    physical_equal(parent, registry.trusted.closure) &&
    step.env.with_object is None &&
    step.env.is_var_scope &&
    step.env.bindings.get("this") is Some(this_binding) &&
    this_binding.initialized &&
    getter_recursion_target_identity_matches(
      registry.trusted.target,
      this_binding.value,
    ) else {
    invalid_activation_dispatch_shell(
      "getter body statement lost its activation provenance",
    )
  }
  match step.index {
    0 | 1 => self.execute_statement_with_legacy_adapter(step)
    2 => {
      match self.observe_managed_execution_steps(5) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      let target = registry.require_target(self.interp)
      DispatchWorkSuspended(
        DispatchSuspendContinue(
          DispatchCompleteReturn,
          DispatchStartProperty(
            DispatchPropertyGetResume(
              target~,
              property_key=String_(plan.property_name),
              receiver=target,
              loc=plan.recipe.recursive_member_loc,
            ),
            DispatchApplyBinaryRight(
              DispatchBinaryResume(
                op=@ast.Add,
                left=Number(NUMERIC_RECURSION_STEP),
                loc=plan.recipe.recursive_add_loc,
              ),
            ),
          ),
        ),
      )
    }
    _ =>
      invalid_activation_dispatch_shell(
        "getter body statement index is outside exact admission",
      )
  }
}

///|
fn proxy_activation_parameter_matches(
  env : Environment,
  name : String,
  expected : Value,
) -> Bool {
  match env.bindings.get(name) {
    Some(binding) =>
      binding.initialized &&
      binding.kind == LetBinding &&
      binding.is_parameter &&
      same_value(binding.value, expected)
    None => false
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_proxy_root_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  preflight : ProxyGetRecursionPreflight,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  guard physical_equal(step.env, self.interp.global) &&
    proxy_get_recursion_root_statement_matches(
      preflight.plan,
      step.index,
      step.stmt,
    ) else {
    invalid_activation_dispatch_shell(
      "Proxy get root statement no longer matches exact admission",
    )
  }
  match step.index {
    0 | 1 => self.execute_statement_with_legacy_adapter(step)
    seal_index if seal_index ==
      proxy_get_recursion_seal_statement_index(preflight.plan) => {
      let result = self.execute_statement_with_legacy_adapter(step)
      match result {
        DispatchWorkCompleted(DispatchNormal(_)) => {
          let registry = self.interp.seal_proxy_get_recursion_registry(
            preflight,
            self.proxy_root_stmts_or_fail(),
          )
          self.proxy_registry = Some(registry)
        }
        _ => ()
      }
      result
    }
    root_index if root_index ==
      proxy_get_recursion_root_statement_index(preflight.plan) => {
      match self.observe_managed_execution_steps(3) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      let registry = self.require_proxy_registry()
      let proxy = registry.require_proxy(self.interp)
      self.start_property(
        DispatchPropertyGetResume(
          target=proxy,
          property_key=String_(preflight.plan.property_name),
          receiver=proxy,
          loc=preflight.plan.recipe.root_member_loc,
        ),
        DispatchDeliverCallResult,
      )
    }
    _ =>
      invalid_activation_dispatch_shell(
        "Proxy get root statement index is outside exact admission",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_proxy_body_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  registry : TrustedProxyGetRecursionRegistry,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let plan = registry.plan
  let trusted = registry.trusted
  guard proxy_get_recursion_body_statement_matches(plan, step.index, step.stmt) &&
    step.env.parent is Some(parent) &&
    physical_equal(parent, trusted.closure) &&
    step.env.with_object is None &&
    step.env.is_var_scope &&
    step.env.bindings.get("this") is Some(this_binding) &&
    this_binding.initialized &&
    proxy_get_recursion_object_identity_matches(
      trusted.handler,
      this_binding.value,
    ) &&
    proxy_activation_parameter_matches(
      step.env,
      plan.target_parameter,
      trusted.target,
    ) &&
    proxy_activation_parameter_matches(
      step.env,
      plan.key_parameter,
      String_(plan.property_name),
    ) &&
    proxy_activation_parameter_matches(
      step.env,
      plan.receiver_parameter,
      trusted.proxy,
    ) else {
    invalid_activation_dispatch_shell(
      "Proxy get body statement lost its activation provenance",
    )
  }
  match step.index {
    0 | 1 => self.execute_statement_with_legacy_adapter(step)
    2 => {
      match self.observe_managed_execution_steps(5) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      let proxy = registry.require_proxy(self.interp)
      DispatchWorkSuspended(
        DispatchSuspendContinue(
          DispatchCompleteReturn,
          DispatchStartProperty(
            DispatchPropertyGetResume(
              target=proxy,
              property_key=String_(plan.property_name),
              receiver=proxy,
              loc=plan.recipe.recursive_member_loc,
            ),
            DispatchApplyBinaryRight(
              DispatchBinaryResume(
                op=@ast.Add,
                left=Number(NUMERIC_RECURSION_STEP),
                loc=plan.recipe.recursive_add_loc,
              ),
            ),
          ),
        ),
      )
    }
    _ =>
      invalid_activation_dispatch_shell(
        "Proxy get body statement index is outside exact admission",
      )
  }
}

///|
fn control_lifecycle_child_env_matches(
  actual : Environment,
  expected : Environment?,
  root : Environment,
) -> Bool {
  match (expected, actual.parent) {
    (Some(owned), Some(parent)) =>
      physical_equal(actual, owned) &&
      physical_equal(parent, root) &&
      !actual.is_var_scope &&
      actual.with_object is None
    _ => false
  }
}

///|
fn PrimitiveProgramDispatchShell::advance_control_phase(
  self : PrimitiveProgramDispatchShell,
  plan : ControlLifecyclePlan,
  role : ControlLifecycleRole,
) -> Unit raise InvalidActivationDispatchShell {
  match advance_control_lifecycle_phase(plan, self.control_phase, role) {
    Some(next) => self.control_phase = next
    None =>
      invalid_activation_dispatch_shell(
        "control lifecycle effect arrived outside its admitted order",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_control_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  registry : TrustedControlLifecycleProgram,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let plan = registry.plan
  guard step.ctx.current_generator is None && !step.ctx.strict else {
    invalid_activation_dispatch_shell(
      "control lifecycle statement lost its root execution context",
    )
  }
  match self.control_phase {
    ControlAwaitRoot => {
      guard step.index == 0 &&
        physical_equal(step.env, registry.root_env) &&
        control_lifecycle_root_matches(plan, step.stmt) else {
        invalid_activation_dispatch_shell(
          "control lifecycle root no longer matches exact admission",
        )
      }
      match self.observe_managed_execution_steps(1) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      self.advance_control_phase(plan, ControlRootRole)
      match (plan, step.stmt) {
        (ControlLabelledBreak(expected), @ast.LabeledStmt(actual, body, _)) => {
          guard actual == expected else {
            invalid_activation_dispatch_shell(
              "control lifecycle label changed after admission",
            )
          }
          DispatchWorkSuspended(
            DispatchSuspendLabel(
              actual,
              DispatchStatementCursor(ctx=step.ctx, stmts=[body], env=step.env),
            ),
          )
        }
        (ControlBoundedContinue, @ast.DoWhileStmt(body, condition, _)) => {
          let loop_state = DispatchLoopResume(
            kind=DispatchDoWhileLoop(body, condition, step.env),
            ctx=step.ctx,
            label=None,
            completion=Undefined,
          )
          DispatchWorkSuspended(
            DispatchSuspendLoopIteration(
              loop_state,
              DispatchStatementCursor(ctx=step.ctx, stmts=[body], env=step.env),
            ),
          )
        }
        _ =>
          invalid_activation_dispatch_shell(
            "control lifecycle root lost its admitted representation",
          )
      }
    }
    ControlAwaitProtected => {
      guard step.index == 0 &&
        physical_equal(step.env, registry.root_env) &&
        control_lifecycle_try_matches(plan, step.stmt) else {
        invalid_activation_dispatch_shell(
          "control lifecycle protected statement lost its provenance",
        )
      }
      match self.observe_managed_execution_steps(1) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      guard step.stmt
        is @ast.TryCatchStmt(try_body, None, None, Some(finalizer_body), _) else {
        invalid_activation_dispatch_shell(
          "control lifecycle protected statement lost its exact shape",
        )
      }
      let try_env = Environment::new(parent=Some(step.env))
      let finalizer_env = Environment::new(parent=Some(step.env))
      self.control_try_env = Some(try_env)
      self.control_finalizer_env = Some(finalizer_env)
      self.advance_control_phase(plan, ControlProtectedRole)
      DispatchWorkSuspended(
        DispatchSuspendProtected(
          DispatchStatementCursor(ctx=step.ctx, stmts=try_body, env=try_env),
          None,
          Some(
            DispatchStatementCursor(
              ctx=step.ctx,
              stmts=finalizer_body,
              env=finalizer_env,
            ),
          ),
        ),
      )
    }
    ControlAwaitAbrupt => {
      guard step.index == 0 &&
        control_lifecycle_child_env_matches(
          step.env,
          self.control_try_env,
          registry.root_env,
        ) &&
        control_lifecycle_abrupt_matches(plan, step.stmt) else {
        invalid_activation_dispatch_shell(
          "control lifecycle abrupt statement lost its try ownership",
        )
      }
      // The core already owns the pending finally frame. Even when statement
      // observation itself becomes runtime-abrupt, the next managed statement
      // is therefore the finalizer rather than a retry of this control node.
      self.control_try_env = None
      self.advance_control_phase(plan, ControlAbruptRole)
      match self.observe_managed_execution_steps(1) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      match (plan, step.stmt) {
        (ControlLabelledBreak(expected), @ast.BreakStmt(Some(actual), _)) if actual ==
          expected => DispatchWorkCompleted(DispatchBreak(None, Some(actual)))
        (ControlBoundedContinue, @ast.ContinueStmt(None, _)) =>
          DispatchWorkCompleted(DispatchContinue(None, None))
        _ =>
          invalid_activation_dispatch_shell(
            "control lifecycle abrupt statement changed after validation",
          )
      }
    }
    ControlAwaitFinalizer => {
      guard step.index == 0 &&
        control_lifecycle_child_env_matches(
          step.env,
          self.control_finalizer_env,
          registry.root_env,
        ) &&
        control_lifecycle_finalizer_matches(plan, step.stmt) else {
        invalid_activation_dispatch_shell(
          "control lifecycle finalizer lost its owned child environment",
        )
      }
      let result = self.execute_statement_with_legacy_adapter(step)
      match result {
        DispatchWorkCompleted(DispatchNormal(_)) => {
          self.control_finalizer_env = None
          self.advance_control_phase(plan, ControlFinalizerRole)
        }
        _ => ()
      }
      result
    }
    ControlAwaitTerminal => {
      guard step.index == 1 &&
        physical_equal(step.env, registry.root_env) &&
        control_lifecycle_terminal_matches(plan, step.stmt) else {
        invalid_activation_dispatch_shell(
          "control lifecycle terminal statement lost its root provenance",
        )
      }
      let result = self.execute_statement_with_legacy_adapter(step)
      match result {
        DispatchWorkCompleted(DispatchNormal(_)) =>
          self.advance_control_phase(plan, ControlTerminalRole)
        _ => ()
      }
      result
    }
    ControlAwaitLoopAdvance | ControlFinished =>
      invalid_activation_dispatch_shell(
        "control lifecycle received a statement outside its admitted phase",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_managed_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  match self.control_registry {
    Some(registry) => return self.execute_control_statement(step, registry)
    None => ()
  }
  if activation_dispatch_leaf_statement_is_admissible(step.stmt) {
    return self.execute_statement_with_legacy_adapter(step)
  }
  match (self.getter_root_preflight, self.proxy_root_preflight) {
    (Some(preflight), None) =>
      if physical_equal(step.env, self.interp.global) {
        self.execute_getter_root_statement(step, preflight)
      } else {
        self.execute_getter_body_statement(step, self.require_getter_registry())
      }
    (None, Some(preflight)) =>
      if physical_equal(step.env, self.interp.global) {
        self.execute_proxy_root_statement(step, preflight)
      } else {
        self.execute_proxy_body_statement(step, self.require_proxy_registry())
      }
    (None, None) =>
      invalid_activation_dispatch_shell(
        "managed statement is outside admitted execution",
      )
    (Some(_), Some(_)) =>
      invalid_activation_dispatch_shell(
        "managed statement cannot select multiple admissions",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::advance_control_loop(
  self : PrimitiveProgramDispatchShell,
  loop_state : DispatchLoopResume,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_control_registry()
  guard registry.plan is ControlBoundedContinue &&
    self.control_phase is ControlAwaitLoopAdvance &&
    loop_state.label is None &&
    loop_state.ctx.current_generator is None &&
    !loop_state.ctx.strict &&
    loop_state.kind is DispatchDoWhileLoop(body, condition, env) &&
    physical_equal(env, registry.root_env) &&
    control_lifecycle_try_matches(registry.plan, body) &&
    condition is @ast.BoolLit(false, _) else {
    invalid_activation_dispatch_shell(
      "control lifecycle loop advance no longer matches exact admission",
    )
  }
  let condition_result : Result[Value, Error] = Ok(
    self.interp.eval_expr(loop_state.ctx, condition, env),
  ) catch {
    error => Err(error)
  }
  match condition_result {
    Ok(Bool(false)) => {
      self.advance_control_phase(registry.plan, ControlLoopAdvanceRole)
      DispatchWorkCompleted(DispatchNormal(loop_state.completion))
    }
    Ok(_) =>
      invalid_activation_dispatch_shell(
        "control lifecycle false condition changed during evaluation",
      )
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
      self.enter_managed_call(request)
    DispatchRun(DispatchExecuteStatement(step)) =>
      self.execute_managed_statement(step)
    DispatchRun(DispatchAdvanceLoop(loop_state)) =>
      self.advance_control_loop(loop_state)
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
    DispatchRun(DispatchEnterNumericCatch(catch_state, error)) =>
      self.enter_numeric_catch(catch_state, error)
    DispatchRun(DispatchReadNumericCatchBinding(token)) =>
      self.read_numeric_catch_binding(token)
    DispatchRun(DispatchStartProperty(work, consumer)) =>
      self.start_property(work, consumer)
    DispatchRun(DispatchExecuteProperty(work)) =>
      self.execute_dispatch_property(work)
    DispatchRun(
      DispatchResumeContinuation(DispatchDeliverAccessorResult(_), value)
    ) => DispatchWorkCompleted(DispatchNormal(value))
    DispatchRun(
      DispatchResumeContinuation(DispatchResolveProxyGetTrap(lookup), value)
    ) => self.resume_proxy_get_trap(lookup, value)
    DispatchRun(
      DispatchResumeContinuation(DispatchCheckProxyGetResult(work), value)
    ) => self.resume_proxy_get_result(work, value)
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
    DispatchRestorePropertyScope(cleanup, _) => {
      self.consume_property_cleanup(cleanup.id)
      DispatchCleanupCompleted
    }
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
  match self.control_root_preflight {
    Some(_) => ()
    None =>
      match preflight_control_lifecycle_program(stmts) {
        Some(preflight) => self.control_root_preflight = Some(preflight)
        None => ()
      }
  }
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
fn PrimitiveProgramDispatchShell::drive_root_call(
  self : PrimitiveProgramDispatchShell,
  request : DispatchCallRequest,
) -> DispatchCompletion raise Error {
  try {
    let completion = self.drive(DispatchCallActivation(request))
    guard self.cleanup_stack.is_empty() else {
      invalid_activation_dispatch_shell(
        "direct call dispatch finished while cleanup ownership remained",
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
fn Interpreter::run_activation_dispatch_control_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
  preflight : ControlLifecyclePreflight,
) -> DispatchCompletion raise Error {
  let shell = PrimitiveProgramDispatchShell(
    self,
    control_root_preflight=Some(preflight),
  )
  let completion = shell.drive_root_program(stmts, ctx)
  guard shell.control_registry is None &&
    shell.control_try_env is None &&
    shell.control_finalizer_env is None else {
    invalid_activation_dispatch_shell(
      "control lifecycle ownership outlived its root activation",
    )
  }
  match completion {
    DispatchNormal(_) =>
      if !(shell.control_phase is ControlFinished) {
        invalid_activation_dispatch_shell(
          "normal control lifecycle completion skipped an admitted phase",
        )
      }
    _ => ()
  }
  completion
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
    activation_observation_port=self.execution_control_activation_observation_port(),
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
#warnings("-unused_value")
fn Interpreter::run_activation_dispatch_numeric_call(
  self : Interpreter,
  request : DispatchCallRequest,
  registry : TrustedNumericRecursionRegistry,
) -> DispatchCompletion raise Error {
  let shell = PrimitiveProgramDispatchShell(
    self,
    numeric_registry=Some(registry),
    activation_observation_port=self.execution_control_activation_observation_port(),
  )
  let completion = shell.drive_root_call(request)
  guard shell.numeric_registry is Some(_) else {
    invalid_activation_dispatch_shell(
      "direct call registry was released by a non-root activation",
    )
  }
  shell.numeric_registry = None
  completion
}

///|
fn Interpreter::run_activation_dispatch_getter_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
  preflight : GetterRecursionPreflight,
) -> DispatchCompletion raise Error {
  let shell = PrimitiveProgramDispatchShell(
    self,
    getter_root_preflight=Some(preflight),
    getter_root_stmts=Some(stmts),
  )
  let completion = shell.drive_root_program(stmts, ctx)
  guard shell.getter_registry is None else {
    invalid_activation_dispatch_shell(
      "getter registry outlived its root activation",
    )
  }
  completion
}

///|
fn Interpreter::run_activation_dispatch_proxy_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
  preflight : ProxyGetRecursionPreflight,
) -> DispatchCompletion raise Error {
  let shell = PrimitiveProgramDispatchShell(
    self,
    proxy_root_preflight=Some(preflight),
    proxy_root_stmts=Some(stmts),
  )
  let completion = shell.drive_root_program(stmts, ctx)
  guard shell.proxy_registry is None else {
    invalid_activation_dispatch_shell(
      "Proxy get registry outlived its root activation",
    )
  }
  completion
}

///|
fn Interpreter::run_activation_dispatch_root_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
  root : ActivationDispatchManagedRoot,
) -> DispatchCompletion raise Error {
  match root {
    ActivationDispatchLeafRoot =>
      self.run_activation_dispatch_leaf_program(stmts, ctx)
    ActivationDispatchControlRoot(preflight) =>
      self.run_activation_dispatch_control_program(stmts, ctx, preflight)
    ActivationDispatchNumericRoot(preflight) =>
      self.run_activation_dispatch_numeric_program(stmts, ctx, preflight)
    ActivationDispatchGetterRoot(preflight) =>
      self.run_activation_dispatch_getter_program(stmts, ctx, preflight)
    ActivationDispatchProxyRoot(preflight) =>
      self.run_activation_dispatch_proxy_program(stmts, ctx, preflight)
  }
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
