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
#warnings("-unused_constructor")
priv enum ProgramCleanupOwner {
  AcceptedProgram
  RejectedProgram
  AcceptedDirectReturnCall
  RejectedDirectReturnCall
  AcceptedNumericCall
  RejectedNumericCall
  AcceptedGetterCall
  RejectedGetterCall
  AcceptedProxyCall
  RejectedProxyCall
  AcceptedReceiverCall
  RejectedReceiverCall
  AcceptedConstructorCall
  RejectedConstructorCall
  AcceptedArrayMapCall
  RejectedArrayMapCall
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
  retained_parameter : DispatchNumericParameterCapability?
  mut recursive_callee : DispatchNumericCalleeCaptureState
  mut catch_binding : DispatchNumericCatchBindingState
}

///|
fn DispatchNumericActivationCapabilities::DispatchNumericActivationCapabilities(
  parameter~ : DispatchNumericParameterCapability?,
  retained_parameter? : DispatchNumericParameterCapability? = None,
  recursive_callee~ : DispatchNumericCalleeCaptureState,
  catch_binding~ : DispatchNumericCatchBindingState,
) -> DispatchNumericActivationCapabilities {
  { parameter, retained_parameter, recursive_callee, catch_binding }
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
// Shared imperative resources for sealed ordinary UserFunc activations. The
// direct-return family is the first producer; later ordinary-call families can
// reuse this boundary without changing the dispatch core.
priv struct DispatchOrdinaryCallRealmCleanup {
  cleared_realm : ClearedActiveCalleeRealmScope
  active_realm : ActiveCalleeRealmValueScope
  parameter_gate : SimpleUserFuncParameterGateScope
  actual_arguments : Array[Value]
}

///|
fn DispatchOrdinaryCallRealmCleanup::DispatchOrdinaryCallRealmCleanup(
  cleared_realm~ : ClearedActiveCalleeRealmScope,
  active_realm~ : ActiveCalleeRealmValueScope,
  parameter_gate~ : SimpleUserFuncParameterGateScope,
  actual_arguments~ : Array[Value],
) -> DispatchOrdinaryCallRealmCleanup {
  {
    cleared_realm,
    active_realm,
    parameter_gate,
    actual_arguments: actual_arguments.copy(),
  }
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
priv struct DispatchReceiverCallRealmCleanup {
  cleared_realm : ClearedActiveCalleeRealmScope
  active_realm : ActiveCalleeRealmValueScope
  parameter_gate : SimpleUserFuncParameterGateScope
}

///|
priv struct DispatchConstructorCallRealmCleanup {
  cleared_realm : ClearedActiveCalleeRealmScope
  active_realm : ActiveCalleeRealmValueScope
  parameter_gate : SimpleUserFuncParameterGateScope
}

///|
fn DispatchConstructorCallRealmCleanup::DispatchConstructorCallRealmCleanup(
  cleared_realm~ : ClearedActiveCalleeRealmScope,
  active_realm~ : ActiveCalleeRealmValueScope,
  parameter_gate~ : SimpleUserFuncParameterGateScope,
) -> DispatchConstructorCallRealmCleanup {
  { cleared_realm, active_realm, parameter_gate }
}

///|
fn DispatchReceiverCallRealmCleanup::DispatchReceiverCallRealmCleanup(
  cleared_realm~ : ClearedActiveCalleeRealmScope,
  active_realm~ : ActiveCalleeRealmValueScope,
  parameter_gate~ : SimpleUserFuncParameterGateScope,
) -> DispatchReceiverCallRealmCleanup {
  { cleared_realm, active_realm, parameter_gate }
}

///|
priv enum DispatchActivationObservation {
  AcceptedActivationObservation(ActivationObservationToken)
  RejectedActivationObservation(ActivationEntryAttempt)
}

///|
#warnings("-unused_constructor")
priv enum DispatchShellCleanupResources {
  DispatchProgramRealmCleanup(FunctionRealmProtos)
  DispatchDirectReturnRootRealmCleanup(FunctionRealmProtos)
  DispatchControlRootRealmCleanup(FunctionRealmProtos)
  DispatchNumericRootRealmCleanup(FunctionRealmProtos)
  DispatchGetterRootRealmCleanup(FunctionRealmProtos)
  DispatchProxyRootRealmCleanup(FunctionRealmProtos)
  DispatchReceiverRootRealmCleanup(FunctionRealmProtos)
  DispatchConstructorRootRealmCleanup(FunctionRealmProtos)
  DispatchArrayMapRootRealmCleanup(FunctionRealmProtos)
  DispatchNumericMapCompositionRootRealmCleanup(FunctionRealmProtos)
  DispatchDeniedActivationCleanup
  DispatchNumericRealmCleanup(DispatchNumericCallRealmCleanup)
  DispatchOrdinaryRealmCleanup(DispatchOrdinaryCallRealmCleanup)
  DispatchGetterRealmCleanup(DispatchGetterCallRealmCleanup)
  DispatchProxyRealmCleanup(DispatchProxyCallRealmCleanup)
  DispatchReceiverRealmCleanup(DispatchReceiverCallRealmCleanup)
  DispatchConstructorRealmCleanup(DispatchConstructorCallRealmCleanup)
  DispatchArrayMapRealmCleanup(DispatchReceiverCallRealmCleanup)
  DispatchPropertyRealmCleanup(ClearedActiveCalleeRealmScope)
}

///|
priv struct ProgramRealmCleanup {
  id : Int
  owner : ProgramCleanupOwner
  resources : DispatchShellCleanupResources
  capabilities : DispatchNumericActivationCapabilities?
  observation : DispatchActivationObservation?
}

///|
#warnings("-unused_field")
priv struct PrimitiveProgramDispatchShell {
  interp : Interpreter
  cleanup_stack : Array[ProgramRealmCleanup]
  mut control_root_preflight : ControlLifecyclePreflight?
  mut control_registry : TrustedControlLifecycleProgram?
  mut control_phase : ControlLifecyclePhase
  mut control_try_env : Environment?
  mut control_finalizer_env : Environment?
  direct_return_root_preflight : DirectReturnRecursionPreflight?
  direct_return_root_stmts : Array[@ast.Stmt]?
  mut direct_return_registry : TrustedDirectReturnRecursionRegistry?
  numeric_root_preflight : NumericRecursionPreflight?
  mut numeric_registry : TrustedNumericRecursionRegistry?
  getter_root_preflight : GetterRecursionPreflight?
  getter_root_stmts : Array[@ast.Stmt]?
  mut getter_registry : TrustedGetterRecursionRegistry?
  proxy_root_preflight : ProxyGetRecursionPreflight?
  proxy_root_stmts : Array[@ast.Stmt]?
  mut proxy_registry : TrustedProxyGetRecursionRegistry?
  receiver_root_preflight : ReceiverRecursionPreflight?
  receiver_root_stmts : Array[@ast.Stmt]?
  mut receiver_registry : TrustedReceiverRecursionRegistry?
  mutual_receiver_root_preflight : MutualReceiverRecursionPreflight?
  mutual_receiver_root_stmts : Array[@ast.Stmt]?
  mut mutual_receiver_registry : TrustedMutualReceiverRecursionRegistry?
  constructor_root_preflight : ConstructorRecursionPreflight?
  constructor_root_stmts : Array[@ast.Stmt]?
  mut constructor_registry : TrustedConstructorRecursionRegistry?
  array_map_root_preflight : ArrayMapRecursionPreflight?
  array_map_root_stmts : Array[@ast.Stmt]?
  mut array_map_registry : TrustedArrayMapRecursionRegistry?
  expression_root_preflight : NumericMapExpressionPreflight?
  expression_root_stmts : Array[@ast.Stmt]?
  mut expression_plan : DispatchExpressionPlan?
  mut expression_root_call_locs : Array[@token.Loc]
  composition_root_preflight : NumericMapCompositionPreflight?
  composition_root_stmts : Array[@ast.Stmt]?
  mut managed_user_func_catalog : DispatchManagedUserFuncCatalog?
  array_map_states : Array[MapState]
  array_map_activation_envs : Array[Environment]
  activation_observation_port : ActivationObservationPort
  mut next_cleanup_id : Int
}

///|
fn PrimitiveProgramDispatchShell::PrimitiveProgramDispatchShell(
  interp : Interpreter,
  control_root_preflight? : ControlLifecyclePreflight? = None,
  direct_return_root_preflight? : DirectReturnRecursionPreflight? = None,
  direct_return_root_stmts? : Array[@ast.Stmt]? = None,
  direct_return_registry? : TrustedDirectReturnRecursionRegistry? = None,
  numeric_root_preflight? : NumericRecursionPreflight? = None,
  numeric_registry? : TrustedNumericRecursionRegistry? = None,
  getter_root_preflight? : GetterRecursionPreflight? = None,
  getter_root_stmts? : Array[@ast.Stmt]? = None,
  getter_registry? : TrustedGetterRecursionRegistry? = None,
  proxy_root_preflight? : ProxyGetRecursionPreflight? = None,
  proxy_root_stmts? : Array[@ast.Stmt]? = None,
  proxy_registry? : TrustedProxyGetRecursionRegistry? = None,
  receiver_root_preflight? : ReceiverRecursionPreflight? = None,
  receiver_root_stmts? : Array[@ast.Stmt]? = None,
  receiver_registry? : TrustedReceiverRecursionRegistry? = None,
  mutual_receiver_root_preflight? : MutualReceiverRecursionPreflight? = None,
  mutual_receiver_root_stmts? : Array[@ast.Stmt]? = None,
  mutual_receiver_registry? : TrustedMutualReceiverRecursionRegistry? = None,
  constructor_root_preflight? : ConstructorRecursionPreflight? = None,
  constructor_root_stmts? : Array[@ast.Stmt]? = None,
  constructor_registry? : TrustedConstructorRecursionRegistry? = None,
  array_map_root_preflight? : ArrayMapRecursionPreflight? = None,
  array_map_root_stmts? : Array[@ast.Stmt]? = None,
  array_map_registry? : TrustedArrayMapRecursionRegistry? = None,
  expression_root_preflight? : NumericMapExpressionPreflight? = None,
  expression_root_stmts? : Array[@ast.Stmt]? = None,
  expression_plan? : DispatchExpressionPlan? = None,
  composition_root_preflight? : NumericMapCompositionPreflight? = None,
  composition_root_stmts? : Array[@ast.Stmt]? = None,
  managed_user_func_catalog? : DispatchManagedUserFuncCatalog? = None,
  // The shell lifecycle is policy-free; admitted production roots inject the
  // execution-control port explicitly below.
  activation_observation_port? : ActivationObservationPort = allow_all_activation_observation_port(),
) -> PrimitiveProgramDispatchShell {
  {
    interp,
    cleanup_stack: [],
    control_root_preflight,
    control_registry: None,
    control_phase: ControlAwaitRoot,
    control_try_env: None,
    control_finalizer_env: None,
    direct_return_root_preflight,
    direct_return_root_stmts: direct_return_root_stmts.map(stmts => stmts.copy()),
    direct_return_registry,
    numeric_root_preflight,
    numeric_registry,
    getter_root_preflight,
    getter_root_stmts: getter_root_stmts.map(stmts => stmts.copy()),
    getter_registry,
    proxy_root_preflight,
    proxy_root_stmts: proxy_root_stmts.map(stmts => stmts.copy()),
    proxy_registry,
    receiver_root_preflight,
    receiver_root_stmts: receiver_root_stmts.map(stmts => stmts.copy()),
    receiver_registry,
    mutual_receiver_root_preflight,
    mutual_receiver_root_stmts: mutual_receiver_root_stmts.map(stmts => {
      stmts.copy()
    }),
    mutual_receiver_registry,
    constructor_root_preflight,
    constructor_root_stmts: constructor_root_stmts.map(stmts => stmts.copy()),
    constructor_registry,
    array_map_root_preflight,
    array_map_root_stmts: array_map_root_stmts.map(stmts => stmts.copy()),
    array_map_registry,
    expression_root_preflight,
    expression_root_stmts: expression_root_stmts.map(stmts => stmts.copy()),
    expression_plan,
    expression_root_call_locs: [],
    composition_root_preflight,
    composition_root_stmts: composition_root_stmts.map(stmts => stmts.copy()),
    managed_user_func_catalog,
    array_map_states: [],
    array_map_activation_envs: [],
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
    // Keep the private engine-origin error intact until JS translation. The
    // translation layer attaches a non-observable marker so the host boundary
    // can distinguish it from a guest-created lookalike without message tests.
    ExecutionControlError(StackDepthLimit) => DispatchEntryGuestThrow(error)
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
    AcceptedProgram | AcceptedDirectReturnCall | AcceptedNumericCall => true
    RejectedProgram
    | RejectedDirectReturnCall
    | RejectedNumericCall
    | AcceptedGetterCall
    | RejectedGetterCall
    | AcceptedProxyCall
    | RejectedProxyCall
    | AcceptedReceiverCall
    | RejectedReceiverCall
    | AcceptedConstructorCall
    | RejectedConstructorCall
    | AcceptedArrayMapCall
    | RejectedArrayMapCall
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
    | (AcceptedDirectReturnCall, true)
    | (AcceptedNumericCall, true)
    | (AcceptedGetterCall, true)
    | (AcceptedProxyCall, true)
    | (AcceptedReceiverCall, true)
    | (AcceptedConstructorCall, true)
    | (AcceptedArrayMapCall, true) => true
    (RejectedProgram, false)
    | (RejectedDirectReturnCall, false)
    | (RejectedNumericCall, false)
    | (RejectedGetterCall, false)
    | (RejectedProxyCall, false)
    | (RejectedReceiverCall, false)
    | (RejectedConstructorCall, false)
    | (RejectedArrayMapCall, false) => true
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
    RejectedDirectReturnCall
    | RejectedNumericCall
    | RejectedGetterCall
    | RejectedProxyCall
    | RejectedReceiverCall
    | RejectedConstructorCall
    | RejectedArrayMapCall => ()
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
fn PrimitiveProgramDispatchShell::push_direct_return_root_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  previous_realm_protos : FunctionRealmProtos,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner: AcceptedProgram,
    resources: DispatchDirectReturnRootRealmCleanup(previous_realm_protos),
    capabilities: None,
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
  observation : DispatchActivationObservation?,
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
fn PrimitiveProgramDispatchShell::push_ordinary_call_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  owner : ProgramCleanupOwner,
  resources : DispatchOrdinaryCallRealmCleanup,
  observation : DispatchActivationObservation?,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner,
    resources: DispatchOrdinaryRealmCleanup(resources),
    capabilities: None,
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
  observation : DispatchActivationObservation?,
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
  observation : DispatchActivationObservation?,
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
fn PrimitiveProgramDispatchShell::push_receiver_root_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  previous_realm_protos : FunctionRealmProtos,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner: AcceptedProgram,
    resources: DispatchReceiverRootRealmCleanup(previous_realm_protos),
    capabilities: None,
    observation: None,
  })
}

///|
fn PrimitiveProgramDispatchShell::push_receiver_call_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  owner : ProgramCleanupOwner,
  resources : DispatchReceiverCallRealmCleanup,
  observation : DispatchActivationObservation?,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner,
    resources: DispatchReceiverRealmCleanup(resources),
    capabilities: None,
    observation,
  })
}

///|
fn PrimitiveProgramDispatchShell::push_constructor_root_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  previous_realm_protos : FunctionRealmProtos,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner: AcceptedProgram,
    resources: DispatchConstructorRootRealmCleanup(previous_realm_protos),
    capabilities: None,
    observation: None,
  })
}

///|
#warnings("-unused_value")
fn PrimitiveProgramDispatchShell::push_array_map_root_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  previous_realm_protos : FunctionRealmProtos,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner: AcceptedProgram,
    resources: DispatchArrayMapRootRealmCleanup(previous_realm_protos),
    capabilities: None,
    observation: None,
  })
}

///|
fn PrimitiveProgramDispatchShell::push_numeric_map_composition_root_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  previous_realm_protos : FunctionRealmProtos,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner: AcceptedProgram,
    resources: DispatchNumericMapCompositionRootRealmCleanup(
      previous_realm_protos,
    ),
    capabilities: None,
    observation: None,
  })
}

///|
fn PrimitiveProgramDispatchShell::push_constructor_call_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  owner : ProgramCleanupOwner,
  resources : DispatchConstructorCallRealmCleanup,
  observation : DispatchActivationObservation?,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner,
    resources: DispatchConstructorRealmCleanup(resources),
    capabilities: None,
    observation,
  })
}

///|
#warnings("-unused_value")
fn PrimitiveProgramDispatchShell::push_array_map_call_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  owner : ProgramCleanupOwner,
  resources : DispatchReceiverCallRealmCleanup,
  observation : DispatchActivationObservation?,
) -> Unit {
  self.cleanup_stack.push({
    id,
    owner,
    resources: DispatchArrayMapRealmCleanup(resources),
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
fn PrimitiveProgramDispatchShell::start_receiver_call(
  self : PrimitiveProgramDispatchShell,
  request : DispatchCallRequest,
  continuation : DispatchContinuation,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  match (self.receiver_registry, self.mutual_receiver_registry) {
    (Some(registry), None) => {
      let _ = registry.require_call(
        self.interp,
        request.callee,
        request.this_value,
        request.args,
      )
    }
    (None, Some(registry)) => {
      let _ = registry.require_call(
        self.interp,
        request.callee,
        request.this_value,
        request.args,
        request.loc,
      )
    }
    _ =>
      invalid_activation_dispatch_shell(
        "receiver call requires exactly one sealed receiver registry",
      )
  }
  DispatchWorkSuspended(DispatchSuspendCall(request, continuation))
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
    DispatchDirectReturnRootRealmCleanup(previous_realm_protos) => {
      self.direct_return_registry = None
      apply_active_realm_protos(self.interp.realm_state, previous_realm_protos)
    }
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
    DispatchReceiverRootRealmCleanup(previous_realm_protos) => {
      self.receiver_registry = None
      self.mutual_receiver_registry = None
      apply_active_realm_protos(self.interp.realm_state, previous_realm_protos)
    }
    DispatchConstructorRootRealmCleanup(previous_realm_protos) => {
      self.constructor_registry = None
      apply_active_realm_protos(self.interp.realm_state, previous_realm_protos)
    }
    DispatchArrayMapRootRealmCleanup(previous_realm_protos) => {
      self.array_map_registry = None
      self.array_map_states.clear()
      self.array_map_activation_envs.clear()
      apply_active_realm_protos(self.interp.realm_state, previous_realm_protos)
    }
    DispatchNumericMapCompositionRootRealmCleanup(previous_realm_protos) => {
      self.numeric_registry = None
      self.array_map_registry = None
      self.managed_user_func_catalog = None
      self.expression_plan = None
      self.expression_root_call_locs.clear()
      self.array_map_states.clear()
      self.array_map_activation_envs.clear()
      apply_active_realm_protos(self.interp.realm_state, previous_realm_protos)
    }
    DispatchDeniedActivationCleanup => ()
    DispatchOrdinaryRealmCleanup(resources) => {
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
    DispatchReceiverRealmCleanup(resources) => {
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
    DispatchConstructorRealmCleanup(resources) => {
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
    DispatchArrayMapRealmCleanup(resources) => {
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
    Some(AcceptedActivationObservation(token)) =>
      release_managed_activation_observation(token)
    Some(RejectedActivationObservation(attempt)) =>
      attempt.release_after_rejection() catch {
        InvalidActivationObservationTransition(message) =>
          invalid_activation_dispatch_shell(
            "managed rejected activation release is invalid: " + message,
          )
      }
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
fn PrimitiveProgramDispatchShell::require_direct_return_registry(
  self : PrimitiveProgramDispatchShell,
) -> TrustedDirectReturnRecursionRegistry raise InvalidActivationDispatchShell {
  match self.direct_return_registry {
    Some(registry) => registry
    None =>
      invalid_activation_dispatch_shell(
        "direct-return activation requires a sealed trust registry",
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
fn PrimitiveProgramDispatchShell::composition_root_stmts_or_fail(
  self : PrimitiveProgramDispatchShell,
) -> Array[@ast.Stmt] raise InvalidActivationDispatchShell {
  match self.composition_root_stmts {
    Some(stmts) => stmts
    None =>
      invalid_activation_dispatch_shell(
        "numeric/map composition root statements were not retained by admission",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::expression_root_stmts_or_fail(
  self : PrimitiveProgramDispatchShell,
) -> Array[@ast.Stmt] raise InvalidActivationDispatchShell {
  match self.expression_root_stmts {
    Some(stmts) => stmts
    None =>
      invalid_activation_dispatch_shell(
        "numeric/map expression root statements were not retained by admission",
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
fn PrimitiveProgramDispatchShell::require_receiver_registry(
  self : PrimitiveProgramDispatchShell,
) -> TrustedReceiverRecursionRegistry raise InvalidActivationDispatchShell {
  match self.receiver_registry {
    Some(registry) => registry
    None =>
      invalid_activation_dispatch_shell(
        "receiver activation requires a sealed runtime registry",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::receiver_root_stmts_or_fail(
  self : PrimitiveProgramDispatchShell,
) -> Array[@ast.Stmt] raise InvalidActivationDispatchShell {
  match self.receiver_root_stmts {
    Some(stmts) => stmts
    None =>
      invalid_activation_dispatch_shell(
        "receiver root statements were not retained by admission",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::require_mutual_receiver_registry(
  self : PrimitiveProgramDispatchShell,
) -> TrustedMutualReceiverRecursionRegistry raise InvalidActivationDispatchShell {
  match self.mutual_receiver_registry {
    Some(registry) => registry
    None =>
      invalid_activation_dispatch_shell(
        "mutual receiver activation requires a sealed runtime registry",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::mutual_receiver_root_stmts_or_fail(
  self : PrimitiveProgramDispatchShell,
) -> Array[@ast.Stmt] raise InvalidActivationDispatchShell {
  match self.mutual_receiver_root_stmts {
    Some(stmts) => stmts
    None =>
      invalid_activation_dispatch_shell(
        "mutual receiver root statements were not retained by admission",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::require_constructor_registry(
  self : PrimitiveProgramDispatchShell,
) -> TrustedConstructorRecursionRegistry raise InvalidActivationDispatchShell {
  match self.constructor_registry {
    Some(registry) => registry
    None =>
      invalid_activation_dispatch_shell(
        "constructor activation requires a sealed runtime registry",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::constructor_root_stmts_or_fail(
  self : PrimitiveProgramDispatchShell,
) -> Array[@ast.Stmt] raise InvalidActivationDispatchShell {
  match self.constructor_root_stmts {
    Some(stmts) => stmts
    None =>
      invalid_activation_dispatch_shell(
        "constructor root statements were not retained by admission",
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
    retained_parameter=None,
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
fn PrimitiveProgramDispatchShell::complete_direct_return_root_preparation(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  cursor : DispatchStatementCursor,
  previous_realm_protos : FunctionRealmProtos,
  preflight : DirectReturnRecursionPreflight,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  self.push_direct_return_root_cleanup(id, previous_realm_protos)
  self.direct_return_registry = Some(
    self.interp.seal_direct_return_recursion_registry(preflight, cursor.stmts),
  )
  DispatchProgramAccepted(DispatchActivationCleanup(id))
}

///|
fn PrimitiveProgramDispatchShell::complete_constructor_root_preparation(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  cursor : DispatchStatementCursor,
  previous_realm_protos : FunctionRealmProtos,
  preflight : ConstructorRecursionPreflight,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  self.push_constructor_root_cleanup(id, previous_realm_protos)
  let registry = self.interp.seal_constructor_recursion_registry(
    preflight,
    cursor.stmts,
  )
  self.constructor_registry = Some(registry)
  DispatchProgramAccepted(DispatchActivationCleanup(id))
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
    Ok(_) => {
      match self.constructor_root_preflight {
        Some(preflight) =>
          return self.complete_constructor_root_preparation(
            id, cursor, previous_realm_protos, preflight,
          )
        None => ()
      }
      match self.direct_return_root_preflight {
        Some(preflight) =>
          return self.complete_direct_return_root_preparation(
            id, cursor, previous_realm_protos, preflight,
          )
        None => ()
      }
      match self.expression_root_preflight {
        Some(_) => {
          self.push_numeric_map_composition_root_cleanup(
            id, previous_realm_protos,
          )
          return DispatchProgramAccepted(DispatchActivationCleanup(id))
        }
        None => ()
      }
      match self.composition_root_preflight {
        Some(_) => {
          self.push_numeric_map_composition_root_cleanup(
            id, previous_realm_protos,
          )
          return DispatchProgramAccepted(DispatchActivationCleanup(id))
        }
        None => ()
      }
      match self.array_map_root_preflight {
        Some(_) => {
          self.push_array_map_root_cleanup(id, previous_realm_protos)
          return DispatchProgramAccepted(DispatchActivationCleanup(id))
        }
        None => ()
      }
      match
        (
          self.control_root_preflight,
          self.numeric_root_preflight,
          self.getter_root_preflight,
          self.proxy_root_preflight,
          self.receiver_root_preflight,
          self.mutual_receiver_root_preflight,
        ) {
        (Some(preflight), None, None, None, None, None) =>
          self.complete_control_root_preparation(
            id, cursor, previous_realm_protos, preflight,
          )
        (None, Some(preflight), None, None, None, None) =>
          self.complete_numeric_root_preparation(
            id, cursor, previous_realm_protos, preflight,
          )
        (None, None, Some(_), None, None, None) => {
          self.push_getter_root_cleanup(id, previous_realm_protos)
          DispatchProgramAccepted(DispatchActivationCleanup(id))
        }
        (None, None, None, Some(_), None, None) => {
          self.push_proxy_root_cleanup(id, previous_realm_protos)
          DispatchProgramAccepted(DispatchActivationCleanup(id))
        }
        (None, None, None, None, Some(_), None) => {
          self.push_receiver_root_cleanup(id, previous_realm_protos)
          DispatchProgramAccepted(DispatchActivationCleanup(id))
        }
        (None, None, None, None, None, Some(_)) => {
          self.push_receiver_root_cleanup(id, previous_realm_protos)
          DispatchProgramAccepted(DispatchActivationCleanup(id))
        }
        (None, None, None, None, None, None) => {
          self.push_program_cleanup(id, AcceptedProgram, previous_realm_protos)
          DispatchProgramAccepted(DispatchActivationCleanup(id))
        }
        _ =>
          invalid_activation_dispatch_shell(
            "program cannot own multiple activation admissions",
          )
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
  let syntax = registry.require_callee(self.interp, request.callee)
  let expected_argument_count = match syntax.retained_parameter {
    None => 1
    Some(_) => 2
  }
  guard request.args.length() == expected_argument_count else {
    invalid_activation_dispatch_shell(
      "numeric activation received an unexpected argument count",
    )
  }
  let _ = match request.args[0] {
    Number(_) => ()
    _ =>
      invalid_activation_dispatch_shell(
        "numeric activation requires a number argument",
      )
  }
  if expected_argument_count == 2 {
    let _ = match request.args[1] {
      Number(_) => ()
      _ =>
        invalid_activation_dispatch_shell(
          "numeric activation requires a number retained argument",
        )
    }
  }
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
      request.args,
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
// Shared ordinary-UserFunc activation boundary for the first sealed direct
// return family. Preparation, realm ownership, observation, and cleanup stay
// here; family-specific statement execution remains below.
fn PrimitiveProgramDispatchShell::enter_direct_return_call(
  self : PrimitiveProgramDispatchShell,
  request : DispatchCallRequest,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_direct_return_registry()
  registry.require_call(
    self.interp,
    request.callee,
    request.this_value,
    request.args,
    request.loc,
  )
  guard request.callee is Object(callee_object) &&
    callee_object.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "direct-return activation lost its exact UserFunc provenance",
    )
  }
  let id = self.reserve_program_cleanup_id()
  let observation = match self.begin_managed_activation_observation() {
    Ok(attempt) => attempt
    Err(error) =>
      return self.reject_denied_managed_activation(
        id,
        RejectedDirectReturnCall,
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
      request.args,
      data,
      throw_type_error_source=UsePreResolvedThrowTypeError(
        registry.throw_type_error,
      ),
    ),
  ) catch {
    error => Err(error)
  }
  let resources = DispatchOrdinaryCallRealmCleanup(
    cleared_realm~,
    active_realm~,
    parameter_gate~,
    actual_arguments=request.args,
  )
  match setup {
    Ok(prepared) => {
      let token = accept_managed_activation_observation(observation)
      self.push_ordinary_call_cleanup(
        id,
        AcceptedDirectReturnCall,
        resources,
        Some(AcceptedActivationObservation(token)),
      )
      DispatchCallAccepted(
        DispatchActivationCleanup(id),
        DispatchCallBody(
          DispatchStatementCursor(
            ctx=prepared.ctx,
            stmts=data.body,
            env=prepared.env,
            production=true,
          ),
        ),
      )
    }
    Err(error) => {
      reject_managed_activation_observation(observation)
      self.push_ordinary_call_cleanup(
        id,
        RejectedDirectReturnCall,
        resources,
        Some(RejectedActivationObservation(observation)),
      )
      DispatchActivationRejected(
        DispatchRejectedEntryCleanup(id),
        dispatch_entry_rejection(error),
      )
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::direct_return_call_arguments(
  self : PrimitiveProgramDispatchShell,
) -> Array[Value] raise InvalidActivationDispatchShell {
  guard !self.cleanup_stack.is_empty() else {
    invalid_activation_dispatch_shell(
      "direct-return leaf execution has no active ordinary cleanup",
    )
  }
  let cleanup = self.cleanup_stack[self.cleanup_stack.length() - 1]
  guard cleanup.owner is AcceptedDirectReturnCall else {
    invalid_activation_dispatch_shell(
      "direct-return leaf execution lost its ordinary cleanup owner",
    )
  }
  match cleanup.resources {
    DispatchOrdinaryRealmCleanup(resources) => resources.actual_arguments.copy()
    _ =>
      invalid_activation_dispatch_shell(
        "direct-return leaf execution lost its ordinary argument snapshot",
      )
  }
}

///|
fn direct_return_leaf_parameter_value(
  step : DispatchStatementStep,
  registry : TrustedDirectReturnRecursionRegistry,
  syntax : DirectReturnLeafSyntax,
  parameter : DirectReturnBoundParameter,
  actual_arguments : Array[Value],
) -> Value raise InvalidActivationDispatchShell {
  let leaf_call = match direct_return_leaf_call_plan(registry.entry.syntax) {
    Some(plan) => plan
    None =>
      invalid_activation_dispatch_shell(
        "direct-return leaf registry lost its leaf completion plan",
      )
  }
  guard syntax.parameters.length() == actual_arguments.length() &&
    parameter.index >= 0 &&
    parameter.index < syntax.parameters.length() &&
    syntax.parameters[parameter.index] == parameter.name else {
    invalid_activation_dispatch_shell(
      "direct-return leaf parameter escaped its sealed argument index",
    )
  }
  for index, name in syntax.parameters {
    let binding = match step.env.bindings.get(name) {
      Some(binding) => binding
      None =>
        invalid_activation_dispatch_shell(
          "direct-return leaf lost a sealed parameter binding",
        )
    }
    guard binding.initialized &&
      binding.kind == LetBinding &&
      binding.is_parameter &&
      same_value(actual_arguments[index], binding.value) else {
      invalid_activation_dispatch_shell(
        "direct-return leaf parameter lost its sealed binding provenance",
      )
    }
  }
  guard direct_return_leaf_argument_sources_match_values(
    leaf_call.argument_sources,
    actual_arguments,
  ) else {
    invalid_activation_dispatch_shell(
      "direct-return leaf arguments lost their sealed source plan",
    )
  }
  match step.env.bindings.get(parameter.name) {
    Some(binding) => binding.value
    None =>
      invalid_activation_dispatch_shell(
        "direct-return leaf result binding disappeared after validation",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_direct_return_leaf_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  registry : TrustedDirectReturnRecursionRegistry,
  leaf : TrustedDirectReturnLeafFunction,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let syntax = registry.require_leaf(self.interp, leaf.callee)
  guard step.ctx.current_generator is None &&
    !step.ctx.strict &&
    step.env.parent is Some(parent) &&
    physical_equal(parent, self.interp.global) &&
    step.env.with_object is None &&
    step.env.is_var_scope &&
    step.index == 0 &&
    leaf.body.length() == 1 &&
    physical_equal(step.stmt, leaf.body[0]) else {
    invalid_activation_dispatch_shell(
      "direct-return leaf statement lost its sealed body provenance",
    )
  }
  match self.observe_managed_execution_steps(1) {
    Some(completion) => return DispatchWorkCompleted(completion)
    None => ()
  }
  match syntax.leaf_completion {
    DirectReturnLeafClosedValue(literal) =>
      DispatchWorkCompleted(
        DispatchReturn(direct_return_closed_literal_value(literal)),
      )
    DirectReturnLeafClosedThrow(literal) =>
      DispatchWorkCompleted(
        DispatchThrow(JsException(direct_return_closed_literal_value(literal))),
      )
    DirectReturnLeafParameterValue(parameter) =>
      DispatchWorkCompleted(
        DispatchReturn(
          direct_return_leaf_parameter_value(
            step,
            registry,
            syntax,
            parameter,
            self.direct_return_call_arguments(),
          ),
        ),
      )
    DirectReturnLeafParameterThrow(parameter) =>
      DispatchWorkCompleted(
        DispatchThrow(
          JsException(
            direct_return_leaf_parameter_value(
              step,
              registry,
              syntax,
              parameter,
              self.direct_return_call_arguments(),
            ),
          ),
        ),
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_direct_return_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_direct_return_registry()
  match registry.leaf {
    Some(leaf) if step.index == 0 &&
      leaf.body.length() == 1 &&
      physical_equal(step.stmt, leaf.body[0]) =>
      return self.execute_direct_return_leaf_statement(step, registry, leaf)
    _ => ()
  }
  let syntax = registry.require_callee(self.interp, registry.entry.callee)
  guard step.ctx.current_generator is None &&
    !step.ctx.strict &&
    step.env.parent is Some(parent) &&
    physical_equal(parent, self.interp.global) &&
    step.env.with_object is None &&
    step.env.is_var_scope &&
    step.index >= 0 &&
    step.index < registry.entry.body.length() &&
    physical_equal(step.stmt, registry.entry.body[step.index]) else {
    invalid_activation_dispatch_shell(
      "direct-return statement lost its sealed body provenance",
    )
  }
  let parameter_value = match step.env.bindings.get(syntax.parameter) {
    Some(binding) if binding.initialized &&
      binding.kind == LetBinding &&
      binding.is_parameter => binding.value
    _ =>
      invalid_activation_dispatch_shell(
        "direct-return parameter binding lost its trusted provenance",
      )
  }
  let n = match parameter_value {
    Number(value) if !value.is_nan() && !value.is_inf() => value
    _ =>
      invalid_activation_dispatch_shell(
        "direct-return parameter value is not a finite Number",
      )
  }
  match self.observe_managed_execution_steps(1) {
    Some(completion) => return DispatchWorkCompleted(completion)
    None => ()
  }
  match step.index {
    0 => {
      guard step.stmt
        is (@ast.IfStmt(_, @ast.ReturnStmt(_, _), None, _)
        | @ast.IfStmt(_, @ast.ThrowStmt(_, _), None, _)) else {
        invalid_activation_dispatch_shell(
          "direct-return base statement changed after sealing",
        )
      }
      if n == DIRECT_RETURN_RECURSION_BASE_ARGUMENT {
        match syntax.base_completion {
          DirectReturnBaseValue(literal) =>
            DispatchWorkCompleted(
              DispatchReturn(direct_return_closed_literal_value(literal)),
            )
          DirectReturnBaseThrow(literal) =>
            DispatchWorkCompleted(
              DispatchThrow(
                JsException(direct_return_closed_literal_value(literal)),
              ),
            )
          DirectReturnBaseLeafCall(leaf_call) => {
            let leaf = match registry.leaf {
              Some(leaf) => leaf
              None =>
                invalid_activation_dispatch_shell(
                  "direct-return base call lost its sealed leaf",
                )
            }
            let request = DispatchCallRequest(
              callee=leaf.callee,
              this_value=Undefined,
              args=leaf_call.argument_sources.map(source => {
                match source {
                  DirectReturnLeafClosedArgument(argument) =>
                    direct_return_closed_literal_value(argument.literal)
                  DirectReturnLeafRecursiveResult(_) =>
                    invalid_activation_dispatch_shell(
                      "direct-return base call unexpectedly consumes a recursive result",
                    )
                }
              }),
              loc=leaf_call.call_loc,
            )
            let _ = registry.require_call(
              self.interp,
              request.callee,
              request.this_value,
              request.args,
              request.loc,
            )
            DispatchWorkSuspended(
              DispatchSuspendCall(request, DispatchCompleteReturn),
            )
          }
        }
      } else {
        guard n > DIRECT_RETURN_RECURSION_BASE_ARGUMENT && n.floor() == n else {
          invalid_activation_dispatch_shell(
            "direct-return parameter escaped the admitted decrement domain",
          )
        }
        DispatchWorkCompleted(DispatchNormal(Undefined))
      }
    }
    1 => {
      guard step.stmt is @ast.ReturnStmt(Some(@ast.Call(_, _, _)), _) else {
        invalid_activation_dispatch_shell(
          "direct-return recursive statement changed after sealing",
        )
      }
      guard n > DIRECT_RETURN_RECURSION_BASE_ARGUMENT && n.floor() == n else {
        invalid_activation_dispatch_shell(
          "direct-return recursive argument escaped the admitted domain",
        )
      }
      let request = DispatchCallRequest(
        callee=registry.entry.callee,
        this_value=Undefined,
        args=[Number(n - DIRECT_RETURN_RECURSION_STEP)],
        loc=syntax.recursive_call_loc,
      )
      let continuation = match syntax.recursive_completion {
        DirectReturnRecursiveSelfCall => DispatchCompleteReturn
        DirectReturnRecursiveResultFedLeafCall(leaf_call) => {
          let leaf = match registry.leaf {
            Some(leaf) => leaf
            None =>
              invalid_activation_dispatch_shell(
                "direct-return result-fed call lost its sealed leaf",
              )
          }
          guard leaf_call.callee_name == leaf.syntax.name else {
            invalid_activation_dispatch_shell(
              "direct-return result-fed call selected the wrong leaf binding",
            )
          }
          let mut result_argument_index : Int? = None
          let template_args : Array[Value] = []
          for index, source in leaf_call.argument_sources {
            match source {
              DirectReturnLeafClosedArgument(argument) =>
                template_args.push(
                  direct_return_closed_literal_value(argument.literal),
                )
              DirectReturnLeafRecursiveResult(source_loc) => {
                guard source_loc == syntax.recursive_call_loc &&
                  result_argument_index is None else {
                  invalid_activation_dispatch_shell(
                    "direct-return result-fed argument source drifted",
                  )
                }
                result_argument_index = Some(index)
                template_args.push(Undefined)
              }
            }
          }
          let result_argument_index = match result_argument_index {
            Some(index) => index
            None =>
              invalid_activation_dispatch_shell(
                "direct-return result-fed call has no recursive-result argument",
              )
          }
          DispatchFeedDirectReturnLeafResult(
            DispatchResultFedLeafCallResume(
              call_template=DispatchCallRequest(
                callee=leaf.callee,
                this_value=Undefined,
                args=template_args,
                loc=leaf_call.call_loc,
              ),
              result_argument_index~,
            ),
          )
        }
      }
      let _ = registry.require_call(
        self.interp,
        request.callee,
        request.this_value,
        request.args,
        request.loc,
      )
      DispatchWorkSuspended(DispatchSuspendCall(request, continuation))
    }
    _ =>
      invalid_activation_dispatch_shell(
        "direct-return body index is outside exact admission",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_direct_return_root_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_direct_return_registry()
  let root_stmts = match self.direct_return_root_stmts {
    Some(stmts) => stmts
    None =>
      invalid_activation_dispatch_shell(
        "direct-return root statements are unavailable",
      )
  }
  let root_index = match registry.plan.leaf {
    Some(_) => 2
    None => 1
  }
  guard root_stmts.length() == root_index + 1 else {
    invalid_activation_dispatch_shell(
      "direct-return root statements changed after sealing",
    )
  }
  guard physical_equal(step.env, self.interp.global) &&
    step.index >= 0 &&
    step.index <= root_index else {
    invalid_activation_dispatch_shell(
      "direct-return root statement lost its global provenance",
    )
  }
  if step.index < root_index {
    guard physical_equal(step.stmt, root_stmts[step.index]) else {
      invalid_activation_dispatch_shell(
        "direct-return root declaration changed after sealing",
      )
    }
    self.execute_statement_with_legacy_adapter(step)
  } else {
    guard physical_equal(step.stmt, root_stmts[root_index]) else {
      invalid_activation_dispatch_shell(
        "direct-return root call changed after sealing",
      )
    }
    guard step.stmt is @ast.ExprStmt(@ast.Call(_, _, _), _) else {
      invalid_activation_dispatch_shell(
        "direct-return root call changed after sealing",
      )
    }
    match self.observe_managed_execution_steps(1) {
      Some(completion) => return DispatchWorkCompleted(completion)
      None => ()
    }
    let request = DispatchCallRequest(
      callee=registry.entry.callee,
      this_value=Undefined,
      args=[Number(DIRECT_RETURN_RECURSION_INITIAL_ARGUMENT)],
      loc=registry.plan.root_call_loc,
    )
    let _ = registry.require_call(
      self.interp,
      request.callee,
      request.this_value,
      request.args,
      request.loc,
    )
    DispatchWorkSuspended(
      DispatchSuspendCall(request, DispatchDeliverCallResult),
    )
  }
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
        Some(AcceptedActivationObservation(token)),
      )
      DispatchCallAccepted(
        DispatchActivationCleanup(id),
        DispatchCallBody(
          DispatchStatementCursor(
            ctx=prepared.ctx,
            stmts=data.body,
            env=prepared.env,
            production=true,
          ),
        ),
      )
    }
    Err(error) => {
      reject_managed_activation_observation(observation)
      self.push_getter_call_cleanup(
        id,
        RejectedGetterCall,
        resources,
        Some(RejectedActivationObservation(observation)),
      )
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
        Some(AcceptedActivationObservation(token)),
      )
      DispatchCallAccepted(
        DispatchActivationCleanup(id),
        DispatchCallBody(
          DispatchStatementCursor(
            ctx=prepared.ctx,
            stmts=data.body,
            env=prepared.env,
            production=true,
          ),
        ),
      )
    }
    Err(error) => {
      reject_managed_activation_observation(observation)
      self.push_proxy_call_cleanup(
        id,
        RejectedProxyCall,
        resources,
        Some(RejectedActivationObservation(observation)),
      )
      DispatchActivationRejected(
        DispatchRejectedEntryCleanup(id),
        dispatch_entry_rejection(error),
      )
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::enter_receiver_call(
  self : PrimitiveProgramDispatchShell,
  request : DispatchCallRequest,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_receiver_registry()
  guard request.loc == registry.plan.recipe.root_member_loc ||
    request.loc == registry.plan.recipe.recursive_call_loc else {
    invalid_activation_dispatch_shell(
      "receiver activation call location escaped the sealed syntax recipe",
    )
  }
  let _ = registry.require_call(
    self.interp,
    request.callee,
    request.this_value,
    request.args,
  )
  guard request.args.length() == 1 else {
    invalid_activation_dispatch_shell(
      "receiver activation requires exactly one argument",
    )
  }
  guard request.callee is Object(callee_object) &&
    callee_object.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "receiver activation lost its exact UserFunc provenance",
    )
  }
  let id = self.reserve_program_cleanup_id()
  let observation = match self.begin_managed_activation_observation() {
    Ok(attempt) => attempt
    Err(error) =>
      return self.reject_denied_managed_activation(
        id,
        RejectedReceiverCall,
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
      request.args,
      data,
      throw_type_error_source=UsePreResolvedThrowTypeError(
        registry.throw_type_error,
      ),
    ),
  ) catch {
    error => Err(error)
  }
  let resources = DispatchReceiverCallRealmCleanup(
    cleared_realm~,
    active_realm~,
    parameter_gate~,
  )
  match setup {
    Ok(prepared) => {
      let token = accept_managed_activation_observation(observation)
      self.push_receiver_call_cleanup(
        id,
        AcceptedReceiverCall,
        resources,
        Some(AcceptedActivationObservation(token)),
      )
      DispatchCallAccepted(
        DispatchActivationCleanup(id),
        DispatchCallBody(
          DispatchStatementCursor(
            ctx=prepared.ctx,
            stmts=data.body,
            env=prepared.env,
            production=true,
          ),
        ),
      )
    }
    Err(error) => {
      reject_managed_activation_observation(observation)
      self.push_receiver_call_cleanup(
        id,
        RejectedReceiverCall,
        resources,
        Some(RejectedActivationObservation(observation)),
      )
      DispatchActivationRejected(
        DispatchRejectedEntryCleanup(id),
        dispatch_entry_rejection(error),
      )
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::enter_mutual_receiver_call(
  self : PrimitiveProgramDispatchShell,
  request : DispatchCallRequest,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_mutual_receiver_registry()
  let _ = registry.require_call(
    self.interp,
    request.callee,
    request.this_value,
    request.args,
    request.loc,
  )
  guard request.args.length() == 1 else {
    invalid_activation_dispatch_shell(
      "mutual receiver activation requires exactly one argument",
    )
  }
  guard request.callee is Object(callee_object) &&
    callee_object.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "mutual receiver activation lost its exact UserFunc provenance",
    )
  }
  let id = self.reserve_program_cleanup_id()
  let observation = match self.begin_managed_activation_observation() {
    Ok(attempt) => attempt
    Err(error) =>
      return self.reject_denied_managed_activation(
        id,
        RejectedReceiverCall,
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
      request.args,
      data,
      throw_type_error_source=UsePreResolvedThrowTypeError(
        registry.throw_type_error,
      ),
    ),
  ) catch {
    error => Err(error)
  }
  let resources = DispatchReceiverCallRealmCleanup(
    cleared_realm~,
    active_realm~,
    parameter_gate~,
  )
  match setup {
    Ok(prepared) => {
      let token = accept_managed_activation_observation(observation)
      self.push_receiver_call_cleanup(
        id,
        AcceptedReceiverCall,
        resources,
        Some(AcceptedActivationObservation(token)),
      )
      DispatchCallAccepted(
        DispatchActivationCleanup(id),
        DispatchCallBody(
          DispatchStatementCursor(
            ctx=prepared.ctx,
            stmts=data.body,
            env=prepared.env,
            production=true,
          ),
        ),
      )
    }
    Err(error) => {
      reject_managed_activation_observation(observation)
      self.push_receiver_call_cleanup(
        id,
        RejectedReceiverCall,
        resources,
        Some(RejectedActivationObservation(observation)),
      )
      DispatchActivationRejected(
        DispatchRejectedEntryCleanup(id),
        dispatch_entry_rejection(error),
      )
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::enter_constructor_activation(
  self : PrimitiveProgramDispatchShell,
  request : DispatchConstructRequest,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_constructor_registry()
  let trusted = match request.ctor {
    Object(_) => registry.require_function(self.interp, registry.plan.root_name)
    _ =>
      invalid_activation_dispatch_shell(
        "constructor activation lost its direct UserFunc value",
      )
  }
  let mut selected = trusted
  for candidate in registry.functions {
    if constructor_recursion_value_identity(candidate.callee, request.ctor) {
      selected = candidate
    }
  }
  guard constructor_recursion_value_identity(selected.callee, request.ctor) else {
    invalid_activation_dispatch_shell(
      "constructor activation requested an unsealed callable",
    )
  }
  guard request.args.length() == 1 && request.args[0] is Number(_) else {
    invalid_activation_dispatch_shell(
      "constructor activation requires one fixed numeric argument",
    )
  }
  let mut location_matches = request.loc == registry.plan.root_member_loc
  for function in registry.functions {
    if request.loc == function.plan.construct_loc {
      location_matches = true
    }
  }
  guard location_matches else {
    invalid_activation_dispatch_shell(
      "constructor activation escaped the sealed source recipe",
    )
  }
  let id = self.reserve_program_cleanup_id()
  let observation = match self.begin_managed_activation_observation() {
    Ok(attempt) => attempt
    Err(error) =>
      return self.reject_denied_managed_activation(
        id,
        RejectedConstructorCall,
        error,
      )
  }
  let cleared_realm = begin_cleared_active_callee_realm(self.interp.realm_state)
  let active_realm = begin_active_callee_realm_value(
    self.interp.realm_state,
    request.ctor,
  )
  let parameter_gate = self.interp.begin_simple_user_func_parameter_gate()
  let receiver = make_constructor_instance(selected.prototype, "Object")
  let setup : Result[PreparedUserFuncActivation, Error] = Ok(
    {
      let prepared = self.interp.prepare_user_func_activation(
        request.ctor,
        receiver,
        request.args,
        match request.ctor {
          Object({ callable: Some(UserFunc(data)), .. }) => data
          _ =>
            raise @errors.TypeError(
              message="constructor activation lost its UserFunc payload",
            )
        },
        throw_type_error_source=UsePreResolvedThrowTypeError(
          registry.throw_type_error,
        ),
      )
      prepared.env.assign("<new.target>", request.ctor)
      prepared
    },
  ) catch {
    error => Err(error)
  }
  let resources = DispatchConstructorCallRealmCleanup(
    cleared_realm~,
    active_realm~,
    parameter_gate~,
  )
  match setup {
    Ok(prepared) => {
      let token = accept_managed_activation_observation(observation)
      self.push_constructor_call_cleanup(
        id,
        AcceptedConstructorCall,
        resources,
        Some(AcceptedActivationObservation(token)),
      )
      DispatchCallAccepted(
        DispatchActivationCleanup(id),
        DispatchConstructorCall(
          DispatchStatementCursor(
            ctx=prepared.ctx,
            stmts=selected.body,
            env=prepared.env,
            production=true,
          ),
          receiver,
        ),
      )
    }
    Err(error) => {
      reject_managed_activation_observation(observation)
      self.push_constructor_call_cleanup(
        id,
        RejectedConstructorCall,
        resources,
        Some(RejectedActivationObservation(observation)),
      )
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
  match self.direct_return_registry {
    Some(_) => return self.enter_direct_return_call(request)
    None => ()
  }
  match self.managed_user_func_catalog {
    Some(catalog) => {
      let map_state : MapState? = if self.array_map_states.is_empty() {
        None
      } else {
        Some(self.array_map_states[self.array_map_states.length() - 1])
      }
      match catalog.select(request.callee, map_state, request.this_value) {
        Some(DispatchNumericUserFuncAdapterToken(_)) =>
          return self.enter_numeric_call(request)
        Some(DispatchArrayMapUserFuncAdapterToken(_)) =>
          return self.enter_array_map_call(request)
        None =>
          invalid_activation_dispatch_shell(
            "managed call is outside the sealed UserFunc adapter catalog",
          )
      }
    }
    None => ()
  }
  match
    (
      self.numeric_registry,
      self.getter_registry,
      self.proxy_registry,
      self.receiver_registry,
      self.mutual_receiver_registry,
      self.array_map_registry,
    ) {
    (Some(_), None, None, None, None, None) => self.enter_numeric_call(request)
    (None, Some(_), None, None, None, None) => self.enter_getter_call(request)
    (None, None, Some(_), None, None, None) => self.enter_proxy_call(request)
    (None, None, None, Some(_), None, None) => self.enter_receiver_call(request)
    (None, None, None, None, Some(_), None) =>
      self.enter_mutual_receiver_call(request)
    (None, None, None, None, None, Some(_)) =>
      self.enter_array_map_call(request)
    (None, None, None, None, None, None) =>
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
      let retained_capability = match syntax.retained_parameter {
        None => None
        Some(name) =>
          Some(DispatchNumericParameterCapability(env=prepared.env, name~))
      }
      let retained_token = match syntax.retained_parameter {
        None => None
        Some(_) => Some(DispatchRetainedParameterBindingToken(id~))
      }
      let capabilities = DispatchNumericActivationCapabilities(
        parameter=Some(
          DispatchNumericParameterCapability(
            env=prepared.env,
            name=syntax.parameter,
          ),
        ),
        retained_parameter=retained_capability,
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
        Some(AcceptedActivationObservation(token)),
      )
      DispatchCallAccepted(
        DispatchActivationCleanup(id),
        DispatchNumericCall(
          DispatchNumericCallStart(
            parameter=DispatchParameterBindingToken(id~),
            retained_parameter=retained_token,
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
        Some(RejectedActivationObservation(observation)),
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
fn PrimitiveProgramDispatchShell::read_numeric_retained_parameter(
  self : PrimitiveProgramDispatchShell,
  token : DispatchRetainedParameterBindingToken,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let capabilities = self.require_numeric_capabilities(token.id)
  let retained_parameter = match capabilities.retained_parameter {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "numeric activation does not own a retained parameter capability",
      )
  }
  guard retained_parameter.env.bindings.get(retained_parameter.name)
    is Some(binding) &&
    binding.initialized &&
    binding.kind == LetBinding &&
    binding.is_parameter else {
    invalid_activation_dispatch_shell(
      "numeric retained parameter binding lost its trusted provenance",
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
fn PrimitiveProgramDispatchShell::start_captured_two_argument_numeric_call(
  self : PrimitiveProgramDispatchShell,
  token : DispatchCalleeCaptureToken,
  first : Double,
  second : Double,
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
        args=[Number(first), Number(second)],
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
fn PrimitiveProgramDispatchShell::execute_numeric_map_composition_root_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  preflight : NumericMapCompositionPreflight,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  guard physical_equal(step.env, self.interp.global) &&
    classify_numeric_map_composition_source(
      self.composition_root_stmts_or_fail(),
    )
    is Some(_) else {
    invalid_activation_dispatch_shell(
      "numeric/map composition root statement lost its exact admission",
    )
  }
  match step.index {
    0 | 1 => self.execute_statement_with_legacy_adapter(step)
    2 => {
      let result = self.execute_statement_with_legacy_adapter(step)
      match result {
        DispatchWorkCompleted(DispatchNormal(_)) => {
          let catalog = self.interp.seal_numeric_map_composition_catalog(
            preflight,
            self.composition_root_stmts_or_fail(),
          )
          self.numeric_registry = Some(catalog.numeric)
          self.array_map_registry = Some(catalog.array_map)
          self.managed_user_func_catalog = Some(catalog)
        }
        _ => ()
      }
      result
    }
    3 => {
      match self.observe_managed_execution_steps(3) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      let catalog = match self.managed_user_func_catalog {
        Some(catalog) => catalog
        None =>
          invalid_activation_dispatch_shell(
            "numeric/map composition call started before catalog sealing",
          )
      }
      let call_resume = match
        numeric_map_composition_call_plan(preflight, catalog) {
        Some(plan) => plan
        None =>
          invalid_activation_dispatch_shell(
            "numeric/map composition call plan was not selected",
          )
      }
      DispatchWorkSuspended(
        DispatchSuspendCall(
          call_resume.left_request,
          DispatchComposeBinaryRight(call_resume),
        ),
      )
    }
    _ =>
      invalid_activation_dispatch_shell(
        "numeric/map composition root statement index is outside exact admission",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_numeric_map_expression_root_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  preflight : NumericMapExpressionPreflight,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  guard physical_equal(step.env, self.interp.global) &&
    numeric_map_expression_source(self.expression_root_stmts_or_fail())
    is Some(_) else {
    invalid_activation_dispatch_shell(
      "numeric/map expression root statement lost its exact admission",
    )
  }
  match step.index {
    0 | 1 => self.execute_statement_with_legacy_adapter(step)
    2 => {
      let result = self.execute_statement_with_legacy_adapter(step)
      match result {
        DispatchWorkCompleted(DispatchNormal(_)) => {
          let (catalog, plan) = self.interp.seal_numeric_map_expression_catalog(
            preflight,
            self.expression_root_stmts_or_fail(),
          )
          self.numeric_registry = Some(catalog.numeric)
          self.array_map_registry = Some(catalog.array_map)
          self.managed_user_func_catalog = Some(catalog)
          self.expression_plan = Some(plan)
          self.expression_root_call_locs = dispatch_expression_plan_root_call_locs(
            plan,
          )
        }
        _ => ()
      }
      result
    }
    3 => {
      let plan = match self.expression_plan {
        Some(plan) => plan
        None =>
          invalid_activation_dispatch_shell(
            "numeric/map expression call started before plan sealing",
          )
      }
      guard plan.steps.length() > 0 else {
        invalid_activation_dispatch_shell(
          "numeric/map expression plan was empty",
        )
      }
      let observation_count = preflight.source.steps.length()
      guard plan.steps.length() == observation_count else {
        invalid_activation_dispatch_shell(
          "numeric/map expression plan observation count drifted",
        )
      }
      match self.observe_managed_execution_steps(observation_count) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      match plan.steps[0] {
        DispatchExpressionCall(call) => {
          guard dispatch_managed_user_func_adapter_token_matches(
              call.adapter,
              call.request.callee,
            ) &&
            dispatch_expression_adapter_matches_name(call.adapter, call.name) else {
            invalid_activation_dispatch_shell(
              "numeric/map expression initial adapter drifted",
            )
          }
          DispatchWorkSuspended(
            DispatchSuspendCall(
              call.request,
              DispatchContinueExpressionPlan(
                DispatchExpressionPlanResume(plan~, next_index=1, values=[]),
              ),
            ),
          )
        }
        DispatchExpressionNumericAdd(_) =>
          invalid_activation_dispatch_shell(
            "numeric/map expression plan did not start with a call",
          )
      }
    }
    _ =>
      invalid_activation_dispatch_shell(
        "numeric/map expression root statement index is outside exact admission",
      )
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
fn PrimitiveProgramDispatchShell::execute_receiver_root_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  preflight : ReceiverRecursionPreflight,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  guard physical_equal(step.env, self.interp.global) &&
    receiver_recursion_root_statement_matches(
      preflight.plan,
      step.index,
      step.stmt,
    ) else {
    invalid_activation_dispatch_shell(
      "receiver root statement no longer matches exact admission",
    )
  }
  match step.index {
    0 => self.execute_statement_with_legacy_adapter(step)
    1 => {
      let result = self.execute_statement_with_legacy_adapter(step)
      match result {
        DispatchWorkCompleted(DispatchNormal(_)) => {
          let registry = self.interp.seal_receiver_recursion_registry(
            preflight,
            self.receiver_root_stmts_or_fail(),
          )
          self.receiver_registry = Some(registry)
        }
        _ => ()
      }
      result
    }
    2 => {
      match self.observe_managed_execution_steps(3) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      let registry = self.require_receiver_registry()
      let receiver = registry.require_receiver(self.interp)
      let request = DispatchCallRequest(
        callee=registry.trusted.callee,
        this_value=receiver,
        args=[Number(preflight.plan.initial_argument)],
        loc=preflight.plan.recipe.root_member_loc,
      )
      DispatchWorkSuspended(
        DispatchSuspendContinueProduction(
          DispatchDeliverCallResult,
          DispatchReceiverStartCall(request, DispatchDeliverCallResult),
        ),
      )
    }
    _ =>
      invalid_activation_dispatch_shell(
        "receiver root statement index is outside exact admission",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_mutual_receiver_root_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  preflight : MutualReceiverRecursionPreflight,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  guard physical_equal(step.env, self.interp.global) &&
    mutual_receiver_root_statement_matches(
      preflight.plan,
      step.index,
      step.stmt,
    ) else {
    invalid_activation_dispatch_shell(
      "mutual receiver root statement no longer matches exact admission",
    )
  }
  match step.index {
    0 | 1 => self.execute_statement_with_legacy_adapter(step)
    2 => {
      let result = self.execute_statement_with_legacy_adapter(step)
      match result {
        DispatchWorkCompleted(DispatchNormal(_)) => {
          let registry = self.interp.seal_mutual_receiver_recursion_registry(
            preflight,
            self.mutual_receiver_root_stmts_or_fail(),
          )
          self.mutual_receiver_registry = Some(registry)
        }
        _ => ()
      }
      result
    }
    3 => {
      match self.observe_managed_execution_steps(3) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      let registry = self.require_mutual_receiver_registry()
      let receiver = registry.require_receiver(self.interp)
      let callee = registry.require_function(
        self.interp,
        preflight.plan.root_node,
      )
      let request = DispatchCallRequest(
        callee~,
        this_value=receiver,
        args=[Number(preflight.plan.initial_argument)],
        loc=preflight.plan.root_member_loc,
      )
      DispatchWorkSuspended(
        DispatchSuspendContinueProduction(
          DispatchDeliverCallResult,
          DispatchReceiverStartCall(request, DispatchDeliverCallResult),
        ),
      )
    }
    _ =>
      invalid_activation_dispatch_shell(
        "mutual receiver root statement index is outside exact admission",
      )
  }
}

///|
fn receiver_recursion_parameter_value(
  env : Environment,
  name : String,
) -> Double raise InvalidActivationDispatchShell {
  match env.bindings.get(name) {
    Some(binding) if binding.initialized &&
      binding.kind == LetBinding &&
      binding.is_parameter =>
      match binding.value {
        Number(value) => value
        _ =>
          invalid_activation_dispatch_shell(
            "receiver recursion parameter is not a number",
          )
      }
    _ =>
      invalid_activation_dispatch_shell(
        "receiver recursion parameter lost its activation provenance",
      )
  }
}

///|
fn mutual_receiver_parameter_value(
  env : Environment,
  name : String,
) -> Double raise InvalidActivationDispatchShell {
  match env.bindings.get(name) {
    Some(binding) if binding.initialized &&
      binding.kind == LetBinding &&
      binding.is_parameter =>
      match binding.value {
        Number(value) => value
        _ =>
          invalid_activation_dispatch_shell(
            "mutual receiver recursion parameter is not a number",
          )
      }
    _ =>
      invalid_activation_dispatch_shell(
        "mutual receiver recursion parameter lost its activation provenance",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_receiver_body_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  registry : TrustedReceiverRecursionRegistry,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let trusted = registry.trusted
  let plan = registry.plan
  guard receiver_recursion_body_statement_matches(plan, step.index, step.stmt) &&
    step.env.parent is Some(parent) &&
    physical_equal(parent, trusted.closure) &&
    step.env.with_object is None &&
    step.env.is_var_scope &&
    step.env.bindings.get("this") is Some(this_binding) &&
    this_binding.initialized &&
    receiver_recursion_value_identity(trusted.receiver, this_binding.value) else {
    invalid_activation_dispatch_shell(
      "receiver body statement lost its activation provenance",
    )
  }
  match step.index {
    0 => self.execute_statement_with_legacy_adapter(step)
    1 => {
      match self.observe_managed_execution_steps(5) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      let argument = Number(
        receiver_recursion_parameter_value(step.env, plan.parameter) -
        NUMERIC_RECURSION_STEP,
      )
      let request = DispatchCallRequest(
        callee=trusted.callee,
        this_value=trusted.receiver,
        args=[argument],
        loc=plan.recipe.recursive_call_loc,
      )
      let binary = DispatchBinaryResume(
        op=@ast.Add,
        left=Number(NUMERIC_RECURSION_STEP),
        loc=plan.recipe.recursive_add_loc,
      )
      DispatchWorkSuspended(
        DispatchSuspendContinueProduction(
          DispatchCompleteReturn,
          DispatchReceiverStartCall(
            request,
            DispatchApplyPropertyBinaryRight(binary),
          ),
        ),
      )
    }
    _ =>
      invalid_activation_dispatch_shell(
        "receiver body statement index is outside exact admission",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_mutual_receiver_body_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_mutual_receiver_registry()
  let node = registry.require_body_statement(self.interp, step.index, step.stmt)
  let trusted = match node {
    MutualReceiverLeft => registry.left
    MutualReceiverRight => registry.right
  }
  guard step.env.parent is Some(parent) &&
    physical_equal(parent, trusted.closure) &&
    step.env.with_object is None &&
    step.env.is_var_scope &&
    step.env.bindings.get("this") is Some(this_binding) &&
    this_binding.initialized &&
    mutual_receiver_value_identity(trusted.receiver, this_binding.value) else {
    invalid_activation_dispatch_shell(
      "mutual receiver body statement lost its activation provenance",
    )
  }
  match step.index {
    0 => self.execute_statement_with_legacy_adapter(step)
    1 => {
      match self.observe_managed_execution_steps(5) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      let argument = Number(
        mutual_receiver_parameter_value(step.env, trusted.plan.parameter) -
        NUMERIC_RECURSION_STEP,
      )
      let opposite = match node {
        MutualReceiverLeft => MutualReceiverRight
        MutualReceiverRight => MutualReceiverLeft
      }
      let callee = registry.require_function(self.interp, opposite)
      let binary = DispatchBinaryResume(
        op=@ast.Add,
        left=Number(NUMERIC_RECURSION_STEP),
        loc=trusted.plan.recipe.recursive_add_loc,
      )
      let request = DispatchCallRequest(
        callee~,
        this_value=trusted.receiver,
        args=[argument],
        loc=trusted.plan.recipe.recursive_call_loc,
      )
      DispatchWorkSuspended(
        DispatchSuspendContinueProduction(
          DispatchCompleteReturn,
          DispatchReceiverStartCall(
            request,
            DispatchApplyPropertyBinaryRight(binary),
          ),
        ),
      )
    }
    _ =>
      invalid_activation_dispatch_shell(
        "mutual receiver body statement index is outside exact admission",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_constructor_root_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  preflight : ConstructorRecursionPreflight,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  guard physical_equal(step.env, self.interp.global) else {
    invalid_activation_dispatch_shell(
      "constructor root statement lost its global environment",
    )
  }
  let declaration_count = preflight.plan.functions.length()
  if step.index < declaration_count {
    guard constructor_recursion_root_statement_matches(
      preflight.plan,
      step.index,
      step.stmt,
    ) else {
      invalid_activation_dispatch_shell(
        "constructor declaration no longer matches exact admission",
      )
    }
    let result = self.execute_statement_with_legacy_adapter(step)
    if step.index + 1 == declaration_count {
      match result {
        DispatchWorkCompleted(DispatchNormal(_)) => {
          let registry = self.interp.seal_constructor_recursion_registry(
            preflight,
            self.constructor_root_stmts_or_fail(),
          )
          self.constructor_registry = Some(registry)
        }
        _ => ()
      }
    }
    return result
  }
  guard step.index == declaration_count &&
    constructor_recursion_root_expression_matches(preflight.plan, step.stmt) else {
    invalid_activation_dispatch_shell(
      "constructor root expression no longer matches exact admission",
    )
  }
  // The closed root replaces the ExprStmt/New/member expression tree. Preserve
  // the source-backed five observation points before entering the constructor,
  // matching legacy order: statement, member, new, callee, and argument.
  match self.observe_managed_execution_steps(5) {
    Some(completion) => return DispatchWorkCompleted(completion)
    None => ()
  }
  let registry = self.require_constructor_registry()
  let root = registry.require_root_function(self.interp)
  let request = DispatchConstructRequest(
    ctor=root.callee,
    args=[Number(preflight.plan.initial_argument)],
    loc=preflight.plan.root_member_loc,
  )
  let property = DispatchPropertyGetResume(
    target=Undefined,
    property_key=String_(preflight.plan.value_property),
    receiver=Undefined,
    loc=preflight.plan.root_member_loc,
  )
  DispatchWorkSuspended(
    DispatchSuspendContinueProduction(
      DispatchDeliverCallResult,
      DispatchConstructStart(request, DispatchApplyConstructProperty(property)),
    ),
  )
}

///|
fn PrimitiveProgramDispatchShell::execute_constructor_body_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_constructor_registry()
  let mut selected : TrustedConstructorRecursionFunction? = None
  for function_index, function in registry.functions {
    if constructor_recursion_body_statement_matches(
        registry.plan,
        function_index,
        step.index,
        step.stmt,
      ) {
      selected = Some(function)
    }
  }
  let function = match selected {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "constructor body statement no longer matches exact admission",
      )
  }
  guard step.env.parent is Some(parent) &&
    physical_equal(parent, function.closure) &&
    step.env.with_object is None &&
    step.env.is_var_scope &&
    step.env.bindings.get("this") is Some(this_binding) &&
    this_binding.initialized else {
    invalid_activation_dispatch_shell(
      "constructor body lost its activation environment",
    )
  }
  match step.index {
    0 => self.execute_statement_with_legacy_adapter(step)
    1 => {
      let argument_value = match
        step.env.bindings.get(function.plan.parameter) {
        Some(binding) if binding.initialized => binding.value
        _ =>
          return invalid_activation_dispatch_shell(
            "constructor parameter binding was lost",
          )
      }
      let parameter = match argument_value {
        Number(value) => value
        _ =>
          return invalid_activation_dispatch_shell(
            "constructor parameter is no longer numeric",
          )
      }
      if parameter <= 0.0 {
        DispatchWorkCompleted(DispatchNormal(Undefined))
      } else {
        // The closed edge replaces the If/New expression tree. Preserve the
        // source-backed five expression observation points before entering
        // the child constructor, as the analogous receiver paths do.
        match self.observe_managed_execution_steps(5) {
          Some(completion) => return DispatchWorkCompleted(completion)
          None => ()
        }
        let callee = registry.require_function(
          self.interp,
          function.plan.recursive_callee,
        )
        let this_value = this_binding.value
        let request = DispatchConstructRequest(
          ctor=callee.callee,
          args=[Number(parameter - 1.0)],
          loc=function.plan.construct_loc,
        )
        let assign = DispatchConstructAssignResume(
          target=this_value,
          property=function.plan.child_property,
          loc=function.plan.construct_loc,
          strict=step.ctx.strict,
        )
        DispatchWorkSuspended(
          DispatchSuspendContinueProduction(
            DispatchDeliverCallResult,
            DispatchConstructStart(
              request,
              DispatchAssignConstructResult(assign),
            ),
          ),
        )
      }
    }
    2 => self.execute_statement_with_legacy_adapter(step)
    _ =>
      invalid_activation_dispatch_shell(
        "constructor body statement index is outside exact admission",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::start_constructor(
  self : PrimitiveProgramDispatchShell,
  request : DispatchConstructRequest,
  continuation : DispatchContinuation,
) -> DispatchEffectResult {
  ignore(self)
  DispatchWorkSuspended(DispatchSuspendConstruct(request, continuation))
}

///|
fn PrimitiveProgramDispatchShell::assign_constructor_result(
  self : PrimitiveProgramDispatchShell,
  assign : DispatchConstructAssignResume,
  value : Value,
) -> DispatchEffectResult {
  let result : Result[Value, Error] = Ok(
    self.interp.set_property(
      assign.target,
      assign.property,
      value,
      assign.loc,
      strict=assign.strict,
    ),
  ) catch {
    error => Err(error)
  }
  match result {
    Ok(_) => DispatchWorkCompleted(DispatchNormal(Undefined))
    Err(error) => DispatchWorkCompleted(dispatch_work_error_completion(error))
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
        DispatchSuspendContinueProduction(
          DispatchCompleteReturn,
          DispatchPropertyStart(
            DispatchPropertyGetResume(
              target~,
              property_key=String_(plan.property_name),
              receiver=target,
              loc=plan.recipe.recursive_member_loc,
            ),
            DispatchApplyPropertyBinaryRight(
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
        DispatchSuspendContinueProduction(
          DispatchCompleteReturn,
          DispatchPropertyStart(
            DispatchPropertyGetResume(
              target=proxy,
              property_key=String_(plan.property_name),
              receiver=proxy,
              loc=plan.recipe.recursive_member_loc,
            ),
            DispatchApplyPropertyBinaryRight(
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
              DispatchStatementCursor(
                ctx=step.ctx,
                stmts=[body],
                env=step.env,
                production=true,
              ),
            ),
          )
        }
        (ControlBoundedContinue, @ast.DoWhileStmt(body, condition, _)) => {
          let loop_state = DispatchLoopResume(
            kind=DispatchDoWhileLoop(body, condition, step.env),
            ctx=step.ctx,
            label=None,
            completion=Undefined,
            production=true,
          )
          DispatchWorkSuspended(
            DispatchSuspendLoopIteration(
              loop_state,
              DispatchStatementCursor(
                ctx=step.ctx,
                stmts=[body],
                env=step.env,
                production=true,
              ),
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
          DispatchStatementCursor(
            ctx=step.ctx,
            stmts=try_body,
            env=try_env,
            production=true,
          ),
          None,
          Some(
            DispatchStatementCursor(
              ctx=step.ctx,
              stmts=finalizer_body,
              env=finalizer_env,
              production=true,
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
  match self.direct_return_root_preflight {
    Some(_) =>
      if physical_equal(step.env, self.interp.global) {
        return self.execute_direct_return_root_statement(step)
      } else {
        return self.execute_direct_return_statement(step)
      }
    None => ()
  }
  match self.expression_root_preflight {
    Some(preflight) =>
      if physical_equal(step.env, self.interp.global) {
        return self.execute_numeric_map_expression_root_statement(
          step, preflight,
        )
      } else {
        return self.execute_array_map_body_statement(
          step,
          self.require_array_map_registry(),
        )
      }
    None => ()
  }
  match self.composition_root_preflight {
    Some(preflight) =>
      if physical_equal(step.env, self.interp.global) {
        return self.execute_numeric_map_composition_root_statement(
          step, preflight,
        )
      } else {
        return self.execute_array_map_body_statement(
          step,
          self.require_array_map_registry(),
        )
      }
    None => ()
  }
  if activation_dispatch_leaf_statement_is_admissible(step.stmt) {
    return self.execute_statement_with_legacy_adapter(step)
  }
  match
    (
      self.array_map_root_preflight,
      self.constructor_root_preflight,
      self.getter_root_preflight,
      self.proxy_root_preflight,
      self.receiver_root_preflight,
      self.mutual_receiver_root_preflight,
    ) {
    (Some(preflight), None, None, None, None, None) =>
      if physical_equal(step.env, self.interp.global) {
        self.execute_array_map_root_statement(step, preflight)
      } else {
        self.execute_array_map_body_statement(
          step,
          self.require_array_map_registry(),
        )
      }
    (None, Some(preflight), None, None, None, None) =>
      if physical_equal(step.env, self.interp.global) {
        self.execute_constructor_root_statement(step, preflight)
      } else {
        self.execute_constructor_body_statement(step)
      }
    (None, None, Some(preflight), None, None, None) =>
      if physical_equal(step.env, self.interp.global) {
        self.execute_getter_root_statement(step, preflight)
      } else {
        self.execute_getter_body_statement(step, self.require_getter_registry())
      }
    (None, None, None, Some(preflight), None, None) =>
      if physical_equal(step.env, self.interp.global) {
        self.execute_proxy_root_statement(step, preflight)
      } else {
        self.execute_proxy_body_statement(step, self.require_proxy_registry())
      }
    (None, None, None, None, Some(preflight), None) =>
      if physical_equal(step.env, self.interp.global) {
        self.execute_receiver_root_statement(step, preflight)
      } else {
        self.execute_receiver_body_statement(
          step,
          self.require_receiver_registry(),
        )
      }
    (None, None, None, None, None, Some(preflight)) =>
      if physical_equal(step.env, self.interp.global) {
        self.execute_mutual_receiver_root_statement(step, preflight)
      } else {
        self.execute_mutual_receiver_body_statement(step)
      }
    (None, None, None, None, None, None) =>
      invalid_activation_dispatch_shell(
        "managed statement is outside admitted execution",
      )
    _ =>
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
fn PrimitiveProgramDispatchShell::perform_production_work(
  self : PrimitiveProgramDispatchShell,
  work : DispatchProductionWork,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  match work {
    DispatchExecuteStatement(step) => self.execute_managed_statement(step)
    DispatchAdvanceLoop(loop_state) => self.advance_control_loop(loop_state)
    DispatchPropertyApplyBinaryRight(binary, right) =>
      self.apply_numeric_binary(binary, right)
    DispatchNumericObserveExpressionStep(observation) => {
      ignore(observation)
      self.observe_numeric_execution_step()
    }
    DispatchNumericObserveStatementStep(observation) => {
      ignore(observation)
      self.observe_numeric_execution_step()
    }
    DispatchNumericReadParameter(token) => self.read_numeric_parameter(token)
    DispatchNumericReadRetainedParameter(token) =>
      self.read_numeric_retained_parameter(token)
    DispatchNumericEnterCatch(catch_state, error) =>
      self.enter_numeric_catch(catch_state, error)
    DispatchNumericReadCatchBinding(token) =>
      self.read_numeric_catch_binding(token)
    DispatchNumericCaptureTrustedCallee(token) =>
      self.capture_numeric_callee(token)
    DispatchNumericStartCapturedCall(token, argument, loc) =>
      self.start_captured_numeric_call(token, argument, loc)
    DispatchNumericStartCapturedTwoArgumentCall(token, first, second, loc) =>
      self.start_captured_two_argument_numeric_call(token, first, second, loc)
    DispatchReceiverStartCall(request, continuation) =>
      self.start_receiver_call(request, continuation)
    DispatchConstructStart(request, continuation) =>
      self.start_constructor(request, continuation)
    DispatchConstructAssignResult(assign, value) =>
      self.assign_constructor_result(assign, value)
    DispatchNumericApplyBinaryRight(binary, right) =>
      self.apply_numeric_binary(binary, right)
    DispatchPropertyStart(work, consumer) => self.start_property(work, consumer)
    DispatchPropertyExecute(work) => self.execute_dispatch_property(work)
    DispatchPropertyDeliverAccessorResult(accessor, value) => {
      ignore(accessor)
      DispatchWorkCompleted(DispatchNormal(value))
    }
    DispatchPropertyResolveProxyGetTrap(lookup, value) =>
      self.resume_proxy_get_trap(lookup, value)
    DispatchPropertyCheckProxyGetResult(work, value) =>
      self.resume_proxy_get_result(work, value)
    DispatchMapStart(state) => {
      guard state.phase is MapReady else {
        invalid_activation_dispatch_shell(
          "array map start received a non-ready state",
        )
      }
      self.array_map_states.push(state)
      self.perform_array_map_event(state, MapStart)
    }
    DispatchMapResume(state, value) =>
      self.perform_array_map_event(
        state,
        self.array_map_resume_event(state, value),
      )
    DispatchMapStartMemberCall(member_resume, value) => {
      let registry = self.require_array_map_registry()
      guard member_resume.loc == registry.plan.member_call_loc else {
        invalid_activation_dispatch_shell(
          "array map member call escaped its sealed source location",
        )
      }
      guard member_resume.receiver is Object(_) else {
        invalid_activation_dispatch_shell(
          "array map member call receiver is not the admitted object",
        )
      }
      DispatchWorkSuspended(
        DispatchSuspendCall(
          DispatchCallRequest(
            callee=value,
            this_value=member_resume.receiver,
            args=[],
            loc=member_resume.loc,
          ),
          DispatchCompleteReturn,
        ),
      )
    }
    DispatchMapAbort(state, error) =>
      self.perform_array_map_event(state, MapAbrupt(error))
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
    DispatchEnterActivation(DispatchConstructActivation(request)) =>
      self.enter_constructor_activation(request)
    DispatchRunProduction(work) => self.perform_production_work(work)
    DispatchRun(DispatchExecuteStatement(_))
    | DispatchRun(DispatchAdvanceLoop(_))
    | DispatchRun(DispatchAdvanceParameters(_))
    | DispatchRun(DispatchExecuteCatch(_, _))
    | DispatchRun(DispatchNormalizeFunctionControl(_))
    | DispatchRun(DispatchResumeContinuation(DispatchCompleteReturn, _))
    | DispatchRun(DispatchResumeContinuation(DispatchCompleteThrow, _))
    | DispatchRun(DispatchResumeContinuation(DispatchDeliverCallResult, _))
    | DispatchRun(
      DispatchResumeContinuation(DispatchFeedDirectReturnLeafResult(_), _)
    )
    | DispatchRun(
      DispatchResumeContinuation(DispatchApplyConstructProperty(_), _)
    )
    | DispatchRun(
      DispatchResumeContinuation(DispatchAssignConstructResult(_), _)
    )
    | DispatchRun(DispatchResumeContinuation(DispatchApplyBinaryRight(_), _))
    | DispatchRun(
      DispatchResumeContinuation(DispatchApplyPropertyBinaryRight(_), _)
    )
    | DispatchRun(
      DispatchResumeContinuation(DispatchApplyNumericBinaryRight(_), _)
    )
    | DispatchRun(DispatchResumeContinuation(DispatchComposeBinaryRight(_), _))
    | DispatchRun(
      DispatchResumeContinuation(DispatchDeliverAccessorResult(_), _)
    )
    | DispatchRun(DispatchResumeContinuation(DispatchResolveProxyGetTrap(_), _))
    | DispatchRun(DispatchResumeContinuation(DispatchCheckProxyGetResult(_), _))
    | DispatchRun(
      DispatchResumeContinuation(DispatchContinueExpressionPlan(_), _)
    )
    | DispatchRun(DispatchResumeContinuation(DispatchContinueMap(_), _))
    | DispatchRun(DispatchResumeContinuation(DispatchMapStartMemberCall(_), _))
    | DispatchRun(
      DispatchResumeContinuation(DispatchBindParameterDefault(_), _)
    )
    | DispatchRun(
      DispatchResumeContinuation(DispatchContinueNumericExpression(_), _)
    )
    | DispatchRun(
      DispatchResumeContinuation(DispatchContinueNumericStatement(_), _)
    ) =>
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
  let production = self.control_root_preflight is Some(_) ||
    self.constructor_root_preflight is Some(_) ||
    self.direct_return_root_preflight is Some(_) ||
    self.composition_root_preflight is Some(_) ||
    self.expression_root_preflight is Some(_) ||
    self.array_map_root_preflight is Some(_) ||
    self.numeric_root_preflight is Some(_) ||
    self.getter_root_preflight is Some(_) ||
    self.proxy_root_preflight is Some(_) ||
    self.receiver_root_preflight is Some(_) ||
    self.mutual_receiver_root_preflight is Some(_) ||
    activation_dispatch_leaf_program_is_admissible(stmts)
  try {
    let completion = self.drive(
      DispatchProgramActivation(
        DispatchStatementCursor(
          ctx~,
          stmts~,
          env=self.interp.global,
          production~,
        ),
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
fn Interpreter::run_activation_dispatch_array_map_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
  preflight : ArrayMapRecursionPreflight,
) -> DispatchCompletion raise Error {
  let shell = PrimitiveProgramDispatchShell(
    self,
    array_map_root_preflight=Some(preflight),
    array_map_root_stmts=Some(stmts),
    activation_observation_port=self.execution_control_activation_observation_port(),
  )
  let completion = shell.drive_root_program(stmts, ctx)
  guard shell.array_map_registry is None &&
    shell.array_map_states.is_empty() &&
    shell.array_map_activation_envs.is_empty() else {
    invalid_activation_dispatch_shell(
      "array map registry, map state, or activation environment outlived its root activation",
    )
  }
  completion
}

///|
fn Interpreter::run_activation_dispatch_numeric_map_composition_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
  preflight : NumericMapCompositionPreflight,
) -> DispatchCompletion raise Error {
  let shell = PrimitiveProgramDispatchShell(
    self,
    composition_root_preflight=Some(preflight),
    composition_root_stmts=Some(stmts),
    activation_observation_port=self.execution_control_activation_observation_port(),
  )
  let completion = shell.drive_root_program(stmts, ctx)
  guard shell.numeric_registry is None &&
    shell.array_map_registry is None &&
    shell.managed_user_func_catalog is None &&
    shell.array_map_states.is_empty() &&
    shell.array_map_activation_envs.is_empty() else {
    invalid_activation_dispatch_shell(
      "numeric/map composition ownership outlived its root activation",
    )
  }
  completion
}

///|
fn Interpreter::run_activation_dispatch_numeric_map_expression_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
  preflight : NumericMapExpressionPreflight,
) -> DispatchCompletion raise Error {
  let shell = PrimitiveProgramDispatchShell(
    self,
    expression_root_preflight=Some(preflight),
    expression_root_stmts=Some(stmts),
    activation_observation_port=self.execution_control_activation_observation_port(),
  )
  let completion = shell.drive_root_program(stmts, ctx)
  guard shell.numeric_registry is None &&
    shell.array_map_registry is None &&
    shell.managed_user_func_catalog is None &&
    shell.expression_plan is None &&
    shell.array_map_states.is_empty() &&
    shell.array_map_activation_envs.is_empty() else {
    invalid_activation_dispatch_shell(
      "numeric/map expression ownership outlived its root activation",
    )
  }
  completion
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
fn Interpreter::run_activation_dispatch_direct_return_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
  preflight : DirectReturnRecursionPreflight,
) -> DispatchCompletion raise Error {
  let shell = PrimitiveProgramDispatchShell(
    self,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    activation_observation_port=self.execution_control_activation_observation_port(),
  )
  let completion = shell.drive_root_program(stmts, ctx)
  guard shell.direct_return_registry is None else {
    invalid_activation_dispatch_shell(
      "direct-return registry outlived its root activation",
    )
  }
  completion
}

///|
fn Interpreter::run_activation_dispatch_constructor_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
  preflight : ConstructorRecursionPreflight,
) -> DispatchCompletion raise Error {
  let shell = PrimitiveProgramDispatchShell(
    self,
    constructor_root_preflight=Some(preflight),
    constructor_root_stmts=Some(stmts),
    activation_observation_port=self.execution_control_activation_observation_port(),
  )
  let completion = shell.drive_root_program(stmts, ctx)
  guard shell.constructor_registry is None else {
    invalid_activation_dispatch_shell(
      "constructor registry outlived its root activation",
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
    activation_observation_port=self.execution_control_activation_observation_port(),
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
    activation_observation_port=self.execution_control_activation_observation_port(),
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
fn Interpreter::run_activation_dispatch_receiver_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
  preflight : ReceiverRecursionPreflight,
) -> DispatchCompletion raise Error {
  let shell = PrimitiveProgramDispatchShell(
    self,
    receiver_root_preflight=Some(preflight),
    receiver_root_stmts=Some(stmts),
    activation_observation_port=self.execution_control_activation_observation_port(),
  )
  let completion = shell.drive_root_program(stmts, ctx)
  guard shell.receiver_registry is None else {
    invalid_activation_dispatch_shell(
      "receiver registry outlived its root activation",
    )
  }
  completion
}

///|
fn Interpreter::run_activation_dispatch_mutual_receiver_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
  preflight : MutualReceiverRecursionPreflight,
) -> DispatchCompletion raise Error {
  let shell = PrimitiveProgramDispatchShell(
    self,
    mutual_receiver_root_preflight=Some(preflight),
    mutual_receiver_root_stmts=Some(stmts),
    activation_observation_port=self.execution_control_activation_observation_port(),
  )
  let completion = shell.drive_root_program(stmts, ctx)
  guard shell.mutual_receiver_registry is None else {
    invalid_activation_dispatch_shell(
      "mutual receiver registry outlived its root activation",
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
    ActivationDispatchConstructorRoot(preflight) =>
      self.run_activation_dispatch_constructor_program(stmts, ctx, preflight)
    ActivationDispatchDirectReturnRoot(preflight) =>
      self.run_activation_dispatch_direct_return_program(stmts, ctx, preflight)
    ActivationDispatchNumericMapExpressionRoot(preflight) =>
      self.run_activation_dispatch_numeric_map_expression_program(
        stmts, ctx, preflight,
      )
    ActivationDispatchNumericMapCompositionRoot(preflight) =>
      self.run_activation_dispatch_numeric_map_composition_program(
        stmts, ctx, preflight,
      )
    ActivationDispatchArrayMapRoot(preflight) =>
      self.run_activation_dispatch_array_map_program(stmts, ctx, preflight)
    ActivationDispatchNumericRoot(preflight) =>
      self.run_activation_dispatch_numeric_program(stmts, ctx, preflight)
    ActivationDispatchGetterRoot(preflight) =>
      self.run_activation_dispatch_getter_program(stmts, ctx, preflight)
    ActivationDispatchProxyRoot(preflight) =>
      self.run_activation_dispatch_proxy_program(stmts, ctx, preflight)
    ActivationDispatchReceiverRoot(preflight) =>
      self.run_activation_dispatch_receiver_program(stmts, ctx, preflight)
    ActivationDispatchMutualReceiverRoot(preflight) =>
      self.run_activation_dispatch_mutual_receiver_program(
        stmts, ctx, preflight,
      )
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
