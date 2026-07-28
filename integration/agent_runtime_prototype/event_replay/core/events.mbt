///|
pub enum ReplayEventKind {
  SessionStarted(String, String, String, String, Json)
  ToolRequestObserved(String, String, Json)
  ApprovalGranted(String)
  DispatchIntentRecorded(String, String)
  ToolResultRecorded(String, String, Json, Bool)
  SessionCompleted(Json)
  SessionCancelled(String, String)
}

///|
pub struct ReplayEvent {
  sequence_ : Int
  kind_ : ReplayEventKind
}

///|
fn ReplayEvent::ReplayEvent(
  sequence : Int,
  kind : ReplayEventKind,
) -> ReplayEvent {
  { sequence_: sequence, kind_: kind }
}

///|
pub fn session_started_event(
  sequence : Int,
  session_id : String,
  source_hash : String,
  runtime_fingerprint : String,
  host_config_hash : String,
  input : Json,
) -> ReplayEvent {
  ReplayEvent(
    sequence,
    SessionStarted(
      session_id, source_hash, runtime_fingerprint, host_config_hash, input,
    ),
  )
}

///|
pub fn request_observed_event(
  sequence : Int,
  call_id : String,
  idempotency_key : String,
  request : Json,
) -> ReplayEvent {
  ReplayEvent(sequence, ToolRequestObserved(call_id, idempotency_key, request))
}

///|
pub fn approval_granted_event(sequence : Int, call_id : String) -> ReplayEvent {
  ReplayEvent(sequence, ApprovalGranted(call_id))
}

///|
pub fn dispatch_intent_event(
  sequence : Int,
  call_id : String,
  idempotency_key : String,
) -> ReplayEvent {
  ReplayEvent(sequence, DispatchIntentRecorded(call_id, idempotency_key))
}

///|
pub fn tool_result_event(
  sequence : Int,
  call_id : String,
  idempotency_key : String,
  result : Json,
  write_committed : Bool,
) -> ReplayEvent {
  ReplayEvent(
    sequence,
    ToolResultRecorded(call_id, idempotency_key, result, write_committed),
  )
}

///|
pub fn session_completed_event(
  sequence : Int,
  completion : Json,
) -> ReplayEvent {
  ReplayEvent(sequence, SessionCompleted(completion))
}

///|
pub fn session_cancelled_event(
  sequence : Int,
  call_id : String,
  reason : String,
) -> ReplayEvent {
  ReplayEvent(sequence, SessionCancelled(call_id, reason))
}

///|
pub fn ReplayEvent::sequence(self : ReplayEvent) -> Int {
  self.sequence_
}

///|
pub fn ReplayEvent::kind(self : ReplayEvent) -> ReplayEventKind {
  self.kind_
}

///|
fn int_json(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn event_kind_name(kind : ReplayEventKind) -> String {
  match kind {
    SessionStarted(_, _, _, _, _) => "SessionStarted"
    ToolRequestObserved(_, _, _) => "ToolRequestObserved"
    ApprovalGranted(_) => "ApprovalGranted"
    DispatchIntentRecorded(_, _) => "DispatchIntentRecorded"
    ToolResultRecorded(_, _, _, _) => "ToolResultRecorded"
    SessionCompleted(_) => "SessionCompleted"
    SessionCancelled(_, _) => "SessionCancelled"
  }
}

///|
pub fn ReplayEvent::render(self : ReplayEvent) -> Json {
  let details = match self.kind_ {
    SessionStarted(
      session_id,
      source_hash,
      runtime_fingerprint,
      host_config_hash,
      input
    ) =>
      Json::object({
        "session_id": Json::string(session_id),
        "source_sha256": Json::string(source_hash),
        "runtime_fingerprint": Json::string(runtime_fingerprint),
        "host_config_sha256": Json::string(host_config_hash),
        "input": input,
      })
    ToolRequestObserved(call_id, idempotency_key, request) =>
      Json::object({
        "call_id": Json::string(call_id),
        "idempotency_key": Json::string(idempotency_key),
        "request": request,
      })
    ApprovalGranted(call_id) =>
      Json::object({ "call_id": Json::string(call_id) })
    DispatchIntentRecorded(call_id, idempotency_key) =>
      Json::object({
        "call_id": Json::string(call_id),
        "idempotency_key": Json::string(idempotency_key),
      })
    ToolResultRecorded(call_id, idempotency_key, result, write_committed) =>
      Json::object({
        "call_id": Json::string(call_id),
        "idempotency_key": Json::string(idempotency_key),
        "result": result,
        "adapter_reported_write_committed": Json::boolean(write_committed),
      })
    SessionCompleted(completion) => Json::object({ "completion": completion })
    SessionCancelled(call_id, reason) =>
      Json::object({
        "call_id": Json::string(call_id),
        "reason": Json::string(reason),
      })
  }
  Json::object({
    "sequence": int_json(self.sequence_),
    "kind": Json::string(event_kind_name(self.kind_)),
    "details": details,
  })
}

///|
pub struct ReplayState {
  phase_ : String
  session_id_ : String
  source_hash_ : String
  runtime_fingerprint_ : String
  host_config_hash_ : String
  input_ : Json
  next_sequence_ : Int
  request_sequence_ : Int
  current_call_id_ : String
  current_idempotency_key_ : String
  current_request_ : Json
  approval_status_ : String
  dispatch_recorded_ : Bool
  recorded_results_ : Int
  recorded_write_commits_ : Int
  replay_cursor_ : Int
  completion_ : Json
  cancellation_reason_ : String?
  last_error_ : String?
}

///|
pub fn ReplayState::ReplayState() -> ReplayState {
  {
    phase_: "Empty",
    session_id_: "",
    source_hash_: "",
    runtime_fingerprint_: "",
    host_config_hash_: "",
    input_: Json::null(),
    next_sequence_: 1,
    request_sequence_: 0,
    current_call_id_: "",
    current_idempotency_key_: "",
    current_request_: Json::null(),
    approval_status_: "not_applicable",
    dispatch_recorded_: false,
    recorded_results_: 0,
    recorded_write_commits_: 0,
    replay_cursor_: 0,
    completion_: Json::null(),
    cancellation_reason_: None,
    last_error_: None,
  }
}

///|
pub fn ReplayState::phase(self : ReplayState) -> String {
  self.phase_
}

///|
pub fn ReplayState::next_sequence(self : ReplayState) -> Int {
  self.next_sequence_
}

///|
pub fn ReplayState::request_sequence(self : ReplayState) -> Int {
  self.request_sequence_
}

///|
pub fn ReplayState::current_call_id(self : ReplayState) -> String {
  self.current_call_id_
}

///|
pub fn ReplayState::current_idempotency_key(self : ReplayState) -> String {
  self.current_idempotency_key_
}

///|
pub fn ReplayState::current_request(self : ReplayState) -> Json {
  self.current_request_
}

///|
pub fn ReplayState::source_hash(self : ReplayState) -> String {
  self.source_hash_
}

///|
pub fn ReplayState::runtime_fingerprint(self : ReplayState) -> String {
  self.runtime_fingerprint_
}

///|
pub fn ReplayState::host_config_hash(self : ReplayState) -> String {
  self.host_config_hash_
}

///|
pub fn ReplayState::input(self : ReplayState) -> Json {
  self.input_
}

///|
pub fn ReplayState::completion(self : ReplayState) -> Json {
  self.completion_
}

///|
pub fn ReplayState::replay_cursor(self : ReplayState) -> Int {
  self.replay_cursor_
}

///|
pub fn ReplayState::recorded_results(self : ReplayState) -> Int {
  self.recorded_results_
}

///|
fn optional_string_json(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
pub fn ReplayState::render(self : ReplayState) -> Json {
  Json::object({
    "phase": Json::string(self.phase_),
    "session_id": Json::string(self.session_id_),
    "source_sha256": Json::string(self.source_hash_),
    "runtime_fingerprint": Json::string(self.runtime_fingerprint_),
    "host_config_sha256": Json::string(self.host_config_hash_),
    "input": self.input_,
    "next_event_sequence": int_json(self.next_sequence_),
    "request_sequence": int_json(self.request_sequence_),
    "current_call_id": if self.current_call_id_ == "" {
      Json::null()
    } else {
      Json::string(self.current_call_id_)
    },
    "current_idempotency_key": if self.current_idempotency_key_ == "" {
      Json::null()
    } else {
      Json::string(self.current_idempotency_key_)
    },
    "current_request": self.current_request_,
    "approval_status": Json::string(self.approval_status_),
    "dispatch_recorded": Json::boolean(self.dispatch_recorded_),
    "recorded_results": int_json(self.recorded_results_),
    "recorded_adapter_reported_write_commits": int_json(
      self.recorded_write_commits_,
    ),
    "replay_cursor": int_json(self.replay_cursor_),
    "completion": self.completion_,
    "cancellation_reason": optional_string_json(self.cancellation_reason_),
    "last_error": optional_string_json(self.last_error_),
  })
}

///|
pub struct ApplyResult {
  state_ : ReplayState
  accepted_ : Bool
  error_ : String?
}

///|
fn accepted(state : ReplayState) -> ApplyResult {
  { state_: state, accepted_: true, error_: None }
}

///|
fn rejected(state : ReplayState, error : String) -> ApplyResult {
  {
    state_: { ..state, last_error_: Some(error) },
    accepted_: false,
    error_: Some(error),
  }
}

///|
pub fn ApplyResult::state(self : ApplyResult) -> ReplayState {
  self.state_
}

///|
pub fn ApplyResult::accepted(self : ApplyResult) -> Bool {
  self.accepted_
}

///|
pub fn ApplyResult::error(self : ApplyResult) -> String? {
  self.error_
}

///|
fn request_tool(request : Json) -> String? {
  match request {
    Json::Object(envelope) =>
      match (envelope.get("tool"), envelope.get("arguments")) {
        (Some(Json::String(tool)), Some(Json::Object(_))) => Some(tool)
        _ => None
      }
    _ => None
  }
}

///|
fn valid_tool_result(result : Json) -> Bool {
  match result {
    Json::Object(fields) =>
      match fields.get("tag") {
        Some(Json::String("ok" | "error")) => true
        _ => false
      }
    _ => false
  }
}

///|
fn advance(state : ReplayState, event : ReplayEvent) -> ReplayState {
  {
    ..state,
    next_sequence_: state.next_sequence_ + 1,
    replay_cursor_: event.sequence_,
    last_error_: None,
  }
}

///|
pub fn apply_event(state : ReplayState, event : ReplayEvent) -> ApplyResult {
  guard event.sequence_ == state.next_sequence_ else {
    return rejected(state, "non_contiguous_event_sequence")
  }
  match event.kind_ {
    SessionStarted(
      session_id,
      source_hash,
      runtime_fingerprint,
      host_config_hash,
      input
    ) => {
      guard state.phase_ == "Empty" else {
        return rejected(state, "session_start_requires_empty_log")
      }
      guard session_id.length() > 0 &&
        source_hash.length() > 0 &&
        runtime_fingerprint.length() > 0 &&
        host_config_hash.length() > 0 else {
        return rejected(state, "incomplete_identity_envelope")
      }
      accepted(
        advance(
          {
            ..state,
            phase_: "AwaitingRequest",
            session_id_: session_id,
            source_hash_: source_hash,
            runtime_fingerprint_: runtime_fingerprint,
            host_config_hash_: host_config_hash,
            input_: input,
          },
          event,
        ),
      )
    }
    ToolRequestObserved(call_id, idempotency_key, request) => {
      guard state.phase_ == "AwaitingRequest" ||
        state.phase_ == "AwaitingAgentResume" else {
        return rejected(state, "request_observed_in_wrong_phase")
      }
      let ordinal = state.request_sequence_ + 1
      let expected_call_id = "call-" + ordinal.to_string()
      let expected_key = state.session_id_ + ":" + expected_call_id
      guard call_id == expected_call_id else {
        return rejected(state, "request_call_id_mismatch")
      }
      guard idempotency_key == expected_key else {
        return rejected(state, "request_idempotency_key_mismatch")
      }
      guard request_tool(request) is Some(tool) else {
        return rejected(state, "malformed_tool_request")
      }
      guard tool == "get_user" || tool == "update_user_status" else {
        return rejected(state, "unknown_tool_request")
      }
      let approval_required = tool == "update_user_status"
      accepted(
        advance(
          {
            ..state,
            phase_: if approval_required {
              "WaitingApproval"
            } else {
              "ReadyToDispatch"
            },
            request_sequence_: ordinal,
            current_call_id_: call_id,
            current_idempotency_key_: idempotency_key,
            current_request_: request,
            approval_status_: if approval_required {
              "pending"
            } else {
              "not_required"
            },
            dispatch_recorded_: false,
          },
          event,
        ),
      )
    }
    ApprovalGranted(call_id) => {
      guard state.phase_ == "WaitingApproval" else {
        return rejected(state, "approval_requires_waiting")
      }
      guard call_id == state.current_call_id_ else {
        return rejected(state, "approval_call_id_mismatch")
      }
      accepted(
        advance(
          { ..state, phase_: "ReadyToDispatch", approval_status_: "approved" },
          event,
        ),
      )
    }
    DispatchIntentRecorded(call_id, idempotency_key) => {
      guard state.phase_ == "ReadyToDispatch" else {
        return rejected(state, "dispatch_requires_ready")
      }
      guard call_id == state.current_call_id_ else {
        return rejected(state, "dispatch_call_id_mismatch")
      }
      guard idempotency_key == state.current_idempotency_key_ else {
        return rejected(state, "dispatch_idempotency_key_mismatch")
      }
      accepted(
        advance(
          { ..state, phase_: "AwaitingToolResult", dispatch_recorded_: true },
          event,
        ),
      )
    }
    ToolResultRecorded(call_id, idempotency_key, result, write_committed) => {
      guard state.phase_ == "AwaitingToolResult" else {
        return rejected(state, "tool_result_requires_dispatch_intent")
      }
      guard call_id == state.current_call_id_ else {
        return rejected(state, "tool_result_call_id_mismatch")
      }
      guard idempotency_key == state.current_idempotency_key_ else {
        return rejected(state, "tool_result_idempotency_key_mismatch")
      }
      guard valid_tool_result(result) else {
        return rejected(state, "malformed_tool_result")
      }
      accepted(
        advance(
          {
            ..state,
            phase_: "AwaitingAgentResume",
            recorded_results_: state.recorded_results_ + 1,
            recorded_write_commits_: state.recorded_write_commits_ +
            (if write_committed { 1 } else { 0 }),
          },
          event,
        ),
      )
    }
    SessionCompleted(completion) => {
      guard state.phase_ == "AwaitingAgentResume" else {
        return rejected(state, "completion_requires_recorded_tool_result")
      }
      accepted(
        advance(
          { ..state, phase_: "Completed", completion_: completion },
          event,
        ),
      )
    }
    SessionCancelled(call_id, reason) => {
      guard state.phase_ == "WaitingApproval" ||
        state.phase_ == "ReadyToDispatch" else {
        return rejected(state, "cancellation_requires_pending_request")
      }
      guard call_id == state.current_call_id_ else {
        return rejected(state, "cancellation_call_id_mismatch")
      }
      accepted(
        advance(
          { ..state, phase_: "Cancelled", cancellation_reason_: Some(reason) },
          event,
        ),
      )
    }
  }
}

///|
pub fn reduce_events(events : Array[ReplayEvent]) -> ApplyResult {
  let mut state = ReplayState()
  for event in events {
    let result = apply_event(state, event)
    guard result.accepted() else { return result }
    state = result.state()
  }
  accepted(state)
}
