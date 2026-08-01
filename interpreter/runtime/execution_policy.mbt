///|
/// Public, immutable policy inputs for an explicitly bounded evaluation.
/// The fields remain private so callers can only obtain validated values.
pub(all) struct ExecutionPolicy {
  priv step_budget_ : Int64
  priv stack_depth_limit_ : Int64
  priv interruption_ : InterruptionHandle
}

///|
/// Opaque validation details for an invalid bounded-evaluation policy.
pub(all) struct ExecutionPolicyError {
  priv parameter_code_ : String
  priv message_ : String
}

///|
/// A monotonic, shared host interruption request.
pub(all) struct InterruptionHandle {
  priv request_ : ExecutionInterruptionRequest
}

///|
/// Private marker carried by an engine-created depth RangeError value. Host
/// slots are invisible to JavaScript property access and survive translation
/// into a catchable object without relying on user-controlled message text.
let engine_stack_depth_error_slot : HostSlotKey = HostSlotKey::reserve()

///|
pub fn InterruptionHandle::InterruptionHandle() -> InterruptionHandle {
  { request_: ExecutionInterruptionRequest() }
}

///|
pub fn InterruptionHandle::request(self : InterruptionHandle) -> Unit {
  self.request_.request()
}

///|
pub fn InterruptionHandle::is_requested(self : InterruptionHandle) -> Bool {
  self.request_.is_requested()
}

///|
fn execution_policy_error(
  parameter_code : String,
  message : String,
) -> ExecutionPolicyError {
  { parameter_code_: parameter_code, message_: message }
}

///|
pub fn ExecutionPolicy::new(
  step_budget : Int64,
  stack_depth_limit : Int64,
  interruption : InterruptionHandle,
) -> Result[ExecutionPolicy, ExecutionPolicyError] {
  guard step_budget >= 0L && step_budget <= MAX_PORTABLE_EXECUTION_COUNT else {
    return Err(
      execution_policy_error(
        "step-budget", "step budget must be between 0 and 2147483647",
      ),
    )
  }
  guard stack_depth_limit >= 0L &&
    stack_depth_limit <= MAX_PORTABLE_EXECUTION_COUNT else {
    return Err(
      execution_policy_error(
        "stack-depth", "stack depth limit must be between 0 and 2147483647",
      ),
    )
  }
  Ok({
    step_budget_: step_budget,
    stack_depth_limit_: stack_depth_limit,
    interruption_: interruption,
  })
}

///|
pub fn ExecutionPolicyError::parameter_code(
  self : ExecutionPolicyError,
) -> String {
  self.parameter_code_
}

///|
pub fn ExecutionPolicyError::message(self : ExecutionPolicyError) -> String {
  self.message_
}

///|
fn mark_engine_stack_depth_error(value : Value) -> Value {
  match value {
    Object(data) => {
      data.bag.set_host_slot(engine_stack_depth_error_slot, Bool(true))
      Object(data)
    }
    _ => value
  }
}

///|
pub fn is_engine_stack_depth_error(value : Value) -> Bool {
  match value {
    Object(data) => data.bag.has_host_slot(engine_stack_depth_error_slot)
    _ => false
  }
}

///|
/// Translate private guardrail failures at the stable Engine boundary without
/// exposing the runtime error constructors through the root facade.
pub fn execution_control_failure_code(error : Error) -> String? {
  match error {
    ExecutionControlError(Interrupted) => Some("interrupted")
    ExecutionControlError(StackDepthLimit) => Some("stack-depth-limit")
    ExecutionControlError(ExecutionLimit) => Some("execution-limit")
    _ => None
  }
}

///|
pub fn stack_depth_limit_message() -> String {
  STACK_DEPTH_LIMIT_MESSAGE
}

///|
fn ExecutionPolicy::to_execution_control(
  self : ExecutionPolicy,
) -> ExecutionControl raise Error {
  ExecutionControl(
    remaining_steps=self.step_budget_,
    maximum_active_depth=self.stack_depth_limit_,
    interruption=self.interruption_.request_,
  )
}

///|
/// Run parsed source under one operation-scoped control carrier. The carrier
/// is installed and restored by the imperative shell around the existing run
/// path, so unbounded compatibility entry points remain unchanged.
pub fn Interpreter::run_bounded(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  policy : ExecutionPolicy,
) -> Value raise Error {
  let control = policy.to_execution_control()
  self.with_execution_control(control, () => self.run(stmts))
}
