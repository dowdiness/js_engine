///|
pub enum BrokerPhase {
  Ready
  ValidatingRequest
  Rejected
  WaitingApproval
  Executing
  ReturningResult
  Completed
  Cancelled
} derive(Debug, Eq)

///|
fn BrokerPhase::label(self : BrokerPhase) -> String {
  match self {
    Ready => "Ready"
    ValidatingRequest => "ValidatingRequest"
    Rejected => "Rejected"
    WaitingApproval => "WaitingApproval"
    Executing => "Executing"
    ReturningResult => "ReturningResult"
    Completed => "Completed"
    Cancelled => "Cancelled"
  }
}

///|
enum KnownTool {
  GetUser
  UpdateUserStatus
} derive(Debug, Eq)

///|
fn KnownTool::name(self : KnownTool) -> String {
  match self {
    GetUser => "get_user"
    UpdateUserStatus => "update_user_status"
  }
}

///|
fn KnownTool::required_capability(self : KnownTool) -> String {
  match self {
    GetUser => "user.read"
    UpdateUserStatus => "user.write"
  }
}

///|
fn KnownTool::effect_class(self : KnownTool) -> String {
  match self {
    GetUser => "Read"
    UpdateUserStatus => "Write"
  }
}

///|
fn KnownTool::requires_approval(self : KnownTool) -> Bool {
  match self {
    GetUser => false
    UpdateUserStatus => true
  }
}

///|
struct CallState {
  call_id_ : String
  idempotency_key_ : String
  raw_request_ : Json
  normalized_request_ : Json
  tool_ : KnownTool?
  request_bytes_ : Int
  validation_status_ : String
  validation_code_ : String?
  authority_decision_ : String
  approval_required_ : Bool
  approval_status_ : String
  dispatch_emitted_ : Bool
  result_ : Json
}

///|
fn CallState::CallState(
  call_id : String,
  idempotency_key : String,
  raw_request : Json,
) -> CallState {
  {
    call_id_: call_id,
    idempotency_key_: idempotency_key,
    raw_request_: raw_request,
    normalized_request_: Json::null(),
    tool_: None,
    request_bytes_: 0,
    validation_status_: "not_run",
    validation_code_: None,
    authority_decision_: "unchecked",
    approval_required_: false,
    approval_status_: "unchecked",
    dispatch_emitted_: false,
    result_: Json::null(),
  }
}

///|
pub struct AdapterInvocation {
  call_id_ : String
  idempotency_key_ : String
  tool_ : String
  effect_class_ : String
  arguments_ : Json
}

///|
fn AdapterInvocation::AdapterInvocation(
  call_id : String,
  idempotency_key : String,
  tool : String,
  effect_class : String,
  arguments : Json,
) -> AdapterInvocation {
  {
    call_id_: call_id,
    idempotency_key_: idempotency_key,
    tool_: tool,
    effect_class_: effect_class,
    arguments_: arguments,
  }
}

///|
pub fn AdapterInvocation::call_id(self : AdapterInvocation) -> String {
  self.call_id_
}

///|
pub fn AdapterInvocation::idempotency_key(
  self : AdapterInvocation,
) -> String {
  self.idempotency_key_
}

///|
pub fn AdapterInvocation::tool(self : AdapterInvocation) -> String {
  self.tool_
}

///|
pub fn AdapterInvocation::effect_class(
  self : AdapterInvocation,
) -> String {
  self.effect_class_
}

///|
pub fn AdapterInvocation::arguments(self : AdapterInvocation) -> Json {
  self.arguments_
}

///|
pub fn AdapterInvocation::render(self : AdapterInvocation) -> Json {
  Json::object({
    "kind": Json::string("InvokeAdapter"),
    "call_id": Json::string(self.call_id_),
    "idempotency_key": Json::string(self.idempotency_key_),
    "adapter_route": Json::string("fake.users"),
    "tool": Json::string(self.tool_),
    "effect_class": Json::string(self.effect_class_),
    "arguments": self.arguments_,
  })
}

///|
pub enum BrokerEffect {
  InvokeAdapter(AdapterInvocation)
  DeliverToolResult(Json)
}

///|
pub fn BrokerEffect::render(self : BrokerEffect) -> Json {
  match self {
    InvokeAdapter(invocation) => invocation.render()
    DeliverToolResult(result) =>
      Json::object({
        "kind": Json::string("DeliverToolResult"),
        "result": result,
      })
  }
}

///|
pub fn BrokerEffect::adapter_invocation(
  self : BrokerEffect,
) -> AdapterInvocation? {
  match self {
    InvokeAdapter(invocation) => Some(invocation)
    DeliverToolResult(_) => None
  }
}

///|
pub fn BrokerEffect::delivered_result(self : BrokerEffect) -> Json? {
  match self {
    InvokeAdapter(_) => None
    DeliverToolResult(result) => Some(result)
  }
}

///|
pub enum HostAction {
  ValidatePending
  Approve(String)
  Reject(String, String)
  Dispatch(String)
  Cancel(String, String)
  AdapterSucceeded(String, Json, Bool)
  AdapterFailed(String)
  PrepareResult
  DeliverResult
}

///| Trusted-host constructor. Worker JSON has no path to this value.
pub fn host_validate() -> HostAction {
  ValidatePending
}

///| Trusted-operator constructor. Approval grants no capability.
pub fn operator_approve(call_id : String) -> HostAction {
  Approve(call_id)
}

///| Trusted-operator constructor.
pub fn operator_reject(call_id : String, reason : String) -> HostAction {
  Reject(call_id, reason)
}

///| Trusted-host constructor. This is the only action that may emit an adapter directive.
pub fn host_dispatch(call_id : String) -> HostAction {
  Dispatch(call_id)
}

///| Trusted-operator constructor.
pub fn operator_cancel(call_id : String, reason : String) -> HostAction {
  Cancel(call_id, reason)
}

///| Thin-adapter-shell constructor.
pub fn adapter_succeeded_action(
  call_id : String,
  value : Json,
  write_committed : Bool,
) -> HostAction {
  AdapterSucceeded(call_id, value, write_committed)
}

///| Thin-adapter-shell constructor. Raw adapter failure details stay outside this type.
pub fn adapter_failed_action(call_id : String) -> HostAction {
  AdapterFailed(call_id)
}

///| Trusted-host constructor.
pub fn host_prepare_result() -> HostAction {
  PrepareResult
}

///| Trusted-host constructor.
pub fn host_deliver_result() -> HostAction {
  DeliverResult
}

///|
pub fn HostAction::render(self : HostAction) -> Json {
  match self {
    ValidatePending => Json::object({ "kind": Json::string("Validate") })
    Approve(call_id) =>
      Json::object({
        "kind": Json::string("Approve"),
        "call_id": Json::string(call_id),
        "source": Json::string("operator"),
      })
    Reject(call_id, reason) =>
      Json::object({
        "kind": Json::string("Reject"),
        "call_id": Json::string(call_id),
        "source": Json::string("operator"),
        "reason": Json::string(reason),
      })
    Dispatch(call_id) =>
      Json::object({
        "kind": Json::string("Dispatch"),
        "call_id": Json::string(call_id),
        "source": Json::string("host"),
      })
    Cancel(call_id, reason) =>
      Json::object({
        "kind": Json::string("Cancel"),
        "call_id": Json::string(call_id),
        "source": Json::string("operator"),
        "reason": Json::string(reason),
      })
    AdapterSucceeded(call_id, _, write_committed) =>
      Json::object({
        "kind": Json::string("AdapterSucceeded"),
        "call_id": Json::string(call_id),
        "result_visibility": Json::string("validated_before_publication"),
        "write_committed": Json::boolean(write_committed),
      })
    AdapterFailed(call_id) =>
      Json::object({
        "kind": Json::string("AdapterFailed"),
        "call_id": Json::string(call_id),
        "code": Json::string("adapter_failed"),
      })
    PrepareResult => Json::object({ "kind": Json::string("PrepareResult") })
    DeliverResult => Json::object({ "kind": Json::string("DeliverResult") })
  }
}

///|
pub struct BrokerState {
  session_id_ : String
  phase_ : BrokerPhase
  allow_user_read_ : Bool
  allow_user_write_ : Bool
  call_limit_ : Int
  calls_used_ : Int
  calls_reserved_ : Int
  request_byte_limit_ : Int
  request_bytes_used_ : Int
  request_bytes_reserved_ : Int
  next_call_number_ : Int
  call_ : CallState?
  directives_emitted_ : Int
  adapter_invocations_ : Int
  committed_writes_ : Int
  cancelled_ : Bool
  cancelled_at_ : String?
  cancellation_reason_ : String?
  last_transition_error_ : String?
}

///|
pub fn BrokerState::BrokerState(
  session_id : String,
  allow_user_read : Bool,
  allow_user_write : Bool,
  call_limit : Int,
  request_byte_limit : Int,
) -> BrokerState {
  guard call_limit >= 0 && request_byte_limit >= 0 else {
    abort("PROTOTYPE invariant: budgets must be nonnegative")
  }
  {
    session_id_: session_id,
    phase_: Ready,
    allow_user_read_: allow_user_read,
    allow_user_write_: allow_user_write,
    call_limit_: call_limit,
    calls_used_: 0,
    calls_reserved_: 0,
    request_byte_limit_: request_byte_limit,
    request_bytes_used_: 0,
    request_bytes_reserved_: 0,
    next_call_number_: 1,
    call_: None,
    directives_emitted_: 0,
    adapter_invocations_: 0,
    committed_writes_: 0,
    cancelled_: false,
    cancelled_at_: None,
    cancellation_reason_: None,
    last_transition_error_: None,
  }
}

///|
pub fn BrokerState::phase_name(self : BrokerState) -> String {
  self.phase_.label()
}

///|
pub fn BrokerState::current_call_id(self : BrokerState) -> String? {
  match self.call_ {
    Some(call) => Some(call.call_id_)
    None => None
  }
}

///|
pub fn BrokerState::current_request_bytes(self : BrokerState) -> Int {
  match self.call_ {
    Some(call) => call.request_bytes_
    None => 0
  }
}

///|
pub fn BrokerState::current_validation_code(self : BrokerState) -> String? {
  match self.call_ {
    Some(call) => call.validation_code_
    None => None
  }
}

///|
pub fn BrokerState::current_approval_status(self : BrokerState) -> String {
  match self.call_ {
    Some(call) => call.approval_status_
    None => "unchecked"
  }
}

///|
pub fn BrokerState::current_dispatch_emitted(self : BrokerState) -> Bool {
  match self.call_ {
    Some(call) => call.dispatch_emitted_
    None => false
  }
}

///|
pub fn BrokerState::cancelled(self : BrokerState) -> Bool {
  self.cancelled_
}

///|
pub fn BrokerState::directives_emitted(self : BrokerState) -> Int {
  self.directives_emitted_
}

///|
pub fn BrokerState::adapter_invocations(self : BrokerState) -> Int {
  self.adapter_invocations_
}

///|
pub fn BrokerState::committed_writes(self : BrokerState) -> Int {
  self.committed_writes_
}

///|
pub fn BrokerState::calls_used(self : BrokerState) -> Int {
  self.calls_used_
}

///|
pub fn BrokerState::calls_reserved(self : BrokerState) -> Int {
  self.calls_reserved_
}

///|
pub fn BrokerState::request_bytes_used(self : BrokerState) -> Int {
  self.request_bytes_used_
}

///|
pub fn BrokerState::request_bytes_reserved(self : BrokerState) -> Int {
  self.request_bytes_reserved_
}

///|
pub fn BrokerState::last_transition_error(self : BrokerState) -> String? {
  self.last_transition_error_
}

///|
fn optional_string_json(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn int_json(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn BrokerState::authority_render(self : BrokerState) -> Json {
  let granted : Array[Json] = []
  if self.allow_user_read_ {
    granted.push(Json::string("user.read"))
  }
  if self.allow_user_write_ {
    granted.push(Json::string("user.write"))
  }
  let (required, decision) = match self.call_ {
    Some(call) =>
      (
        match call.tool_ {
          Some(tool) => Json::string(tool.required_capability())
          None => Json::null()
        },
        Json::string(call.authority_decision_),
      )
    None => (Json::null(), Json::string("unchecked"))
  }
  Json::object({
    "source": Json::string("host_session_config"),
    "granted_capabilities": Json::array(granted),
    "required_capability": required,
    "decision": decision,
  })
}

///|
fn CallState::render(self : CallState) -> Json {
  let (catalog_tool, effect_class) = match self.tool_ {
    Some(tool) =>
      (Json::string(tool.name()), Json::string(tool.effect_class()))
    None => (Json::null(), Json::null())
  }
  Json::object({
    "call_id": Json::string(self.call_id_),
    "idempotency_key": Json::string(self.idempotency_key_),
    "raw_request": self.raw_request_,
    "normalized_request": self.normalized_request_,
    "catalog_tool": catalog_tool,
    "effect_class": effect_class,
    "validation": Json::object({
      "status": Json::string(self.validation_status_),
      "code": optional_string_json(self.validation_code_),
    }),
    "approval": Json::object({
      "required": Json::boolean(self.approval_required_),
      "status": Json::string(self.approval_status_),
      "source": if self.approval_required_ {
        Json::string("operator")
      } else {
        Json::null()
      },
    }),
    "request_bytes": int_json(self.request_bytes_),
    "dispatch_status": Json::string(
      if self.dispatch_emitted_ { "dispatched" } else { "pending" },
    ),
    "result": self.result_,
  })
}

///|
pub fn BrokerState::render(self : BrokerState) -> Json {
  let current_call = match self.call_ {
    Some(call) => call.render()
    None => Json::null()
  }
  let current_result = match self.call_ {
    Some(call) => call.result_
    None => Json::null()
  }
  Json::object({
    "phase": Json::string(self.phase_.label()),
    "session_id": Json::string(self.session_id_),
    "next_call_number": int_json(self.next_call_number_),
    "current_call": current_call,
    "authority": self.authority_render(),
    "budgets": Json::object({
      "tool_count": Json::object({
        "limit": int_json(self.call_limit_),
        "used": int_json(self.calls_used_),
        "reserved": int_json(self.calls_reserved_),
        "remaining": int_json(
          self.call_limit_ - self.calls_used_ - self.calls_reserved_,
        ),
      }),
      "request_bytes": Json::object({
        "limit": int_json(self.request_byte_limit_),
        "used": int_json(self.request_bytes_used_),
        "reserved": int_json(self.request_bytes_reserved_),
        "remaining": int_json(
          self.request_byte_limit_ -
          self.request_bytes_used_ -
          self.request_bytes_reserved_,
        ),
        "current_request": int_json(self.current_request_bytes()),
        "definition": Json::string(
          "cumulative canonical UTF-8 request bytes before adapter dispatch",
        ),
      }),
    }),
    "adapter_effects": Json::object({
      "directives_emitted": int_json(self.directives_emitted_),
      "adapter_results_observed": int_json(self.adapter_invocations_),
      "adapter_reported_committed_writes": int_json(self.committed_writes_),
    }),
    "cancellation": Json::object({
      "cancelled": Json::boolean(self.cancelled_),
      "at_phase": optional_string_json(self.cancelled_at_),
      "reason": optional_string_json(self.cancellation_reason_),
    }),
    "result": current_result,
    "last_transition_error": optional_string_json(
      self.last_transition_error_,
    ),
  })
}

///|
pub struct Transition {
  after_ : BrokerState
  effects_ : Array[BrokerEffect]
}

///|
fn Transition::Transition(
  after : BrokerState,
  effects : Array[BrokerEffect],
) -> Transition {
  { after_: after, effects_: effects }
}

///|
pub fn Transition::after(self : Transition) -> BrokerState {
  self.after_
}

///|
pub fn Transition::effects(self : Transition) -> Array[BrokerEffect] {
  self.effects_
}

///|
pub fn Transition::render_effects(self : Transition) -> Json {
  Json::array(self.effects_.map(effect => effect.render()))
}
