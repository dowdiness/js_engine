///|
priv enum RequestValidation {
  ValidRequest(KnownTool, Json, Int)
  InvalidRequest(String)
}

///|
fn exact_object(
  value : Json,
  keys : Array[String],
) -> Map[String, Json]? {
  match value {
    Json::Object(fields) => {
      if fields.length() != keys.length() {
        return None
      }
      for key in keys {
        if !fields.contains(key) {
          return None
        }
      }
      Some(fields)
    }
    _ => None
  }
}

///|
fn string_field(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(Json::String(value)) => Some(value)
    _ => None
  }
}

///|
fn well_formed_utf16(text : String) -> Bool {
  let units = text.code_units()
  let mut index = 0
  while index < units.length() {
    let unit = units[index]
    if unit.is_leading_surrogate() {
      if index + 1 >= units.length() ||
        !units[index + 1].is_trailing_surrogate() {
        return false
      }
      index += 2
    } else if unit.is_trailing_surrogate() {
      return false
    } else {
      index += 1
    }
  }
  true
}

///|
fn utf8_length(text : String) -> Int {
  let mut length = 0
  for character in text.iter() {
    let code_point = character.to_int()
    if code_point <= 0x7f {
      length += 1
    } else if code_point <= 0x7ff {
      length += 2
    } else if code_point <= 0xffff {
      length += 3
    } else {
      length += 4
    }
  }
  length
}

///|
fn canonical_get_user(user_id : String) -> (Json, String) {
  let normalized = Json::object({
    "tool": Json::string("get_user"),
    "arguments": Json::object({ "user_id": Json::string(user_id) }),
  })
  let encoded_user_id = Json::string(user_id).stringify()
  let canonical =
    "{\"tool\":\"get_user\",\"arguments\":{\"user_id\":" +
    encoded_user_id +
    "}}"
  (normalized, canonical)
}

///|
fn canonical_update_user_status(
  user_id : String,
  status : String,
) -> (Json, String) {
  let normalized = Json::object({
    "tool": Json::string("update_user_status"),
    "arguments": Json::object({
      "user_id": Json::string(user_id),
      "status": Json::string(status),
    }),
  })
  let encoded_user_id = Json::string(user_id).stringify()
  let encoded_status = Json::string(status).stringify()
  let canonical =
    "{\"tool\":\"update_user_status\",\"arguments\":{\"user_id\":" +
    encoded_user_id +
    ",\"status\":" +
    encoded_status +
    "}}"
  (normalized, canonical)
}

///|
fn validate_request(raw_request : Json) -> RequestValidation {
  guard exact_object(
    raw_request,
    ["tool", "arguments"],
  ) is Some(envelope) else {
    return InvalidRequest("malformed_envelope")
  }
  guard string_field(envelope, "tool") is Some(tool_name) else {
    return InvalidRequest("malformed_envelope")
  }
  guard well_formed_utf16(tool_name) else {
    return InvalidRequest("ill_formed_string")
  }
  guard envelope.get("arguments") is Some(arguments) else {
    return InvalidRequest("malformed_envelope")
  }
  match tool_name {
    "get_user" => {
      guard exact_object(arguments, ["user_id"]) is Some(fields) else {
        return InvalidRequest("invalid_arguments")
      }
      guard string_field(fields, "user_id") is Some(user_id) else {
        return InvalidRequest("invalid_arguments")
      }
      guard user_id.length() > 0 && well_formed_utf16(user_id) else {
        return InvalidRequest("invalid_arguments")
      }
      let (normalized, canonical) = canonical_get_user(user_id)
      ValidRequest(GetUser, normalized, utf8_length(canonical))
    }
    "update_user_status" => {
      guard exact_object(
        arguments,
        ["user_id", "status"],
      ) is Some(fields) else {
        return InvalidRequest("invalid_arguments")
      }
      guard string_field(fields, "user_id") is Some(user_id) else {
        return InvalidRequest("invalid_arguments")
      }
      guard string_field(fields, "status") is Some(status) else {
        return InvalidRequest("invalid_arguments")
      }
      guard
        user_id.length() > 0 &&
        status == "active" &&
        well_formed_utf16(user_id) &&
        well_formed_utf16(status)
      else {
        return InvalidRequest("invalid_arguments")
      }
      let (normalized, canonical) = canonical_update_user_status(
        user_id,
        status,
      )
      ValidRequest(UpdateUserStatus, normalized, utf8_length(canonical))
    }
    _ => InvalidRequest("unknown_tool")
  }
}

///|
pub fn measured_request_bytes(raw_request : Json) -> Int? {
  match validate_request(raw_request) {
    ValidRequest(_, _, request_bytes) => Some(request_bytes)
    InvalidRequest(_) => None
  }
}

///|
fn error_result(code : String, message : String) -> Json {
  Json::object({
    "tag": Json::string("error"),
    "error": Json::object({
      "code": Json::string(code),
      "message": Json::string(message),
    }),
  })
}

///|
fn success_result(value : Json) -> Json {
  Json::object({ "tag": Json::string("ok"), "value": value })
}

///|
fn invalid_transition(state : BrokerState, code : String) -> Transition {
  Transition(
    { ..state, last_transition_error_: Some(code) },
    [],
  )
}

///|
pub fn submit_worker_request(
  state : BrokerState,
  raw_request : Json,
) -> Transition {
  guard !state.cancelled_ else {
    return invalid_transition(state, "session_cancelled")
  }
  match state.phase_ {
    Ready | Completed => {
      let call_id = "call-" + state.next_call_number_.to_string()
      let idempotency_key = state.session_id_ + ":" + call_id
      let call = CallState(call_id, idempotency_key, raw_request)
      Transition(
        {
          ..state,
          phase_: ValidatingRequest,
          next_call_number_: state.next_call_number_ + 1,
          call_: Some(call),
          cancelled_: false,
          cancelled_at_: None,
          cancellation_reason_: None,
          last_transition_error_: None,
        },
        [],
      )
    }
    _ => invalid_transition(state, "worker_submit_requires_ready_or_completed")
  }
}

///|
fn reject_validation(
  state : BrokerState,
  call : CallState,
  code : String,
  message : String,
) -> Transition {
  let rejected_call = {
    ..call,
    validation_status_: "rejected",
    validation_code_: Some(code),
    authority_decision_: if code == "capability_denied" {
      "denied"
    } else {
      call.authority_decision_
    },
    approval_status_: "not_applicable",
    result_: error_result(code, message),
  }
  Transition(
    {
      ..state,
      phase_: Rejected,
      call_: Some(rejected_call),
      calls_reserved_: 0,
      request_bytes_reserved_: 0,
      last_transition_error_: None,
    },
    [],
  )
}

///|
fn validate_pending(state : BrokerState) -> Transition {
  guard state.phase_ == ValidatingRequest else {
    return invalid_transition(state, "validation_requires_pending_request")
  }
  guard state.call_ is Some(call) else {
    return invalid_transition(state, "validation_missing_call")
  }
  match validate_request(call.raw_request_) {
    InvalidRequest(code) =>
      reject_validation(
        state,
        call,
        code,
        match code {
          "unknown_tool" => "tool is not present in the host catalog"
          "invalid_arguments" => "arguments do not match the host schema"
          "ill_formed_string" => "request contains an ill-formed string"
          _ => "request envelope must contain only tool and arguments"
        },
      )
    ValidRequest(tool, normalized, request_bytes) => {
      let authorized = match tool {
        GetUser => state.allow_user_read_
        UpdateUserStatus => state.allow_user_write_
      }
      let checked_call = {
        ..call,
        normalized_request_: normalized,
        tool_: Some(tool),
        request_bytes_: request_bytes,
        authority_decision_: if authorized { "allowed" } else { "denied" },
        approval_required_: tool.requires_approval(),
      }
      guard authorized else {
        return reject_validation(
          state,
          checked_call,
          "capability_denied",
          "host capability does not authorize this tool",
        )
      }
      let remaining_calls =
        state.call_limit_ - state.calls_used_ - state.calls_reserved_
      guard remaining_calls >= 1 else {
        return reject_validation(
          state,
          checked_call,
          "tool_count_exhausted",
          "adapter dispatch count budget is exhausted",
        )
      }
      let remaining_bytes =
        state.request_byte_limit_ -
        state.request_bytes_used_ -
        state.request_bytes_reserved_
      guard request_bytes <= remaining_bytes else {
        return reject_validation(
          state,
          checked_call,
          "request_bytes_exhausted",
          "canonical request byte budget is exhausted",
        )
      }
      let accepted_call = {
        ..checked_call,
        validation_status_: "accepted",
        validation_code_: None,
        approval_status_: if tool.requires_approval() {
          "pending"
        } else {
          "not_required"
        },
      }
      Transition(
        {
          ..state,
          phase_: if tool.requires_approval() {
            WaitingApproval
          } else {
            Executing
          },
          call_: Some(accepted_call),
          calls_reserved_: 1,
          request_bytes_reserved_: request_bytes,
          last_transition_error_: None,
        },
        [],
      )
    }
  }
}

///|
fn approve_pending(state : BrokerState, call_id : String) -> Transition {
  guard state.phase_ == WaitingApproval else {
    return invalid_transition(state, "approval_requires_waiting")
  }
  guard state.call_ is Some(call) else {
    return invalid_transition(state, "approval_missing_call")
  }
  guard call.call_id_ == call_id else {
    return invalid_transition(state, "stale_call_id")
  }
  guard call.approval_required_ && call.approval_status_ == "pending" else {
    return invalid_transition(state, "approval_not_pending")
  }
  Transition(
    {
      ..state,
      phase_: Executing,
      call_: Some({ ..call, approval_status_: "approved" }),
      last_transition_error_: None,
    },
    [],
  )
}

///|
fn reject_pending(
  state : BrokerState,
  call_id : String,
  _reason : String,
) -> Transition {
  guard state.phase_ == WaitingApproval else {
    return invalid_transition(state, "rejection_requires_waiting")
  }
  guard state.call_ is Some(call) else {
    return invalid_transition(state, "rejection_missing_call")
  }
  guard call.call_id_ == call_id else {
    return invalid_transition(state, "stale_call_id")
  }
  let rejected_call = {
    ..call,
    approval_status_: "rejected",
    result_: error_result("operator_rejected", "operator rejected the write"),
  }
  Transition(
    {
      ..state,
      phase_: Rejected,
      call_: Some(rejected_call),
      calls_reserved_: 0,
      request_bytes_reserved_: 0,
      last_transition_error_: None,
    },
    [],
  )
}

///|
fn normalized_arguments(call : CallState) -> Json {
  match call.normalized_request_ {
    Json::Object(fields) =>
      match fields.get("arguments") {
        Some(arguments) => arguments
        None => abort("PROTOTYPE invariant: normalized arguments missing")
      }
    _ => abort("PROTOTYPE invariant: normalized request missing")
  }
}

///|
fn adapter_value_is_valid(
  call : CallState,
  tool : KnownTool,
  value : Json,
) -> Bool {
  guard exact_object(value, ["user_id", "status"]) is Some(fields) else {
    return false
  }
  guard string_field(fields, "user_id") is Some(user_id) else {
    return false
  }
  guard string_field(fields, "status") is Some(status) else {
    return false
  }
  guard
    user_id.length() > 0 &&
    status.length() > 0 &&
    well_formed_utf16(user_id) &&
    well_formed_utf16(status)
  else {
    return false
  }
  guard exact_object(normalized_arguments(call), ["user_id"]) is Some(_) ||
    exact_object(normalized_arguments(call), ["user_id", "status"]) is Some(_)
  else {
    return false
  }
  guard normalized_arguments(call) is Json::Object(arguments) else {
    return false
  }
  guard string_field(arguments, "user_id") is Some(expected_user_id) else {
    return false
  }
  guard user_id == expected_user_id else {
    return false
  }
  match tool {
    GetUser => status == "active" || status == "inactive"
    UpdateUserStatus =>
      match string_field(arguments, "status") {
        Some(expected_status) => status == expected_status
        None => false
      }
  }
}

///|
fn dispatch_pending(state : BrokerState, call_id : String) -> Transition {
  guard state.phase_ == Executing else {
    return invalid_transition(state, "dispatch_requires_executing")
  }
  guard state.call_ is Some(call) else {
    return invalid_transition(state, "dispatch_missing_call")
  }
  guard call.call_id_ == call_id else {
    return invalid_transition(state, "stale_call_id")
  }
  guard !call.dispatch_emitted_ else {
    return invalid_transition(state, "already_dispatched")
  }
  guard !state.cancelled_ else {
    return invalid_transition(state, "cancelled_before_dispatch")
  }
  guard call.validation_status_ == "accepted" else {
    return invalid_transition(state, "dispatch_requires_valid_request")
  }
  guard call.tool_ is Some(tool) else {
    return invalid_transition(state, "dispatch_missing_catalog_tool")
  }
  let still_authorized = match tool {
    GetUser => state.allow_user_read_
    UpdateUserStatus => state.allow_user_write_
  }
  guard still_authorized else {
    return invalid_transition(state, "capability_denied_at_dispatch")
  }
  let approval_allows_dispatch =
    call.approval_status_ == "not_required" ||
    call.approval_status_ == "approved"
  guard approval_allows_dispatch else {
    return invalid_transition(state, "approval_required_at_dispatch")
  }
  guard
    state.calls_reserved_ == 1 &&
    state.request_bytes_reserved_ == call.request_bytes_
  else {
    return invalid_transition(state, "budget_reservation_mismatch")
  }
  let invocation = AdapterInvocation(
    call.call_id_,
    call.idempotency_key_,
    tool.name(),
    tool.effect_class(),
    normalized_arguments(call),
  )
  Transition(
    {
      ..state,
      call_: Some({ ..call, dispatch_emitted_: true }),
      calls_used_: state.calls_used_ + 1,
      calls_reserved_: 0,
      request_bytes_used_: state.request_bytes_used_ + call.request_bytes_,
      request_bytes_reserved_: 0,
      directives_emitted_: state.directives_emitted_ + 1,
      last_transition_error_: None,
    },
    [InvokeAdapter(invocation)],
  )
}

///|
fn cancel_before_dispatch(
  state : BrokerState,
  call_id : String,
  reason : String,
) -> Transition {
  guard
    state.phase_ == ValidatingRequest ||
    state.phase_ == WaitingApproval ||
    state.phase_ == Executing
  else {
    return invalid_transition(state, "cancellation_requires_pending_call")
  }
  guard state.call_ is Some(call) else {
    return invalid_transition(state, "cancellation_missing_call")
  }
  guard call.call_id_ == call_id else {
    return invalid_transition(state, "stale_call_id")
  }
  guard !call.dispatch_emitted_ else {
    return invalid_transition(state, "cancellation_too_late")
  }
  let cancelled_call = {
    ..call,
    result_: error_result(
      "cancelled_before_dispatch",
      "operator cancelled before adapter dispatch",
    ),
  }
  Transition(
    {
      ..state,
      phase_: Cancelled,
      call_: Some(cancelled_call),
      calls_reserved_: 0,
      request_bytes_reserved_: 0,
      cancelled_: true,
      cancelled_at_: Some(state.phase_.label()),
      cancellation_reason_: Some(reason),
      last_transition_error_: None,
    },
    [],
  )
}

///|
fn adapter_succeeded(
  state : BrokerState,
  call_id : String,
  value : Json,
  write_committed : Bool,
) -> Transition {
  guard state.phase_ == Executing else {
    return invalid_transition(state, "adapter_result_requires_executing")
  }
  guard state.call_ is Some(call) else {
    return invalid_transition(state, "adapter_result_missing_call")
  }
  guard call.call_id_ == call_id else {
    return invalid_transition(state, "stale_call_id")
  }
  guard call.dispatch_emitted_ else {
    return invalid_transition(state, "adapter_result_before_dispatch")
  }
  guard call.tool_ is Some(tool) else {
    return invalid_transition(state, "adapter_result_missing_catalog_tool")
  }
  guard !write_committed || tool == UpdateUserStatus else {
    return invalid_transition(state, "read_cannot_commit_write")
  }
  let result = if adapter_value_is_valid(call, tool, value) {
    success_result(value)
  } else {
    error_result(
      "invalid_adapter_result",
      "adapter result did not match the catalog schema and request identity",
    )
  }
  Transition(
    {
      ..state,
      phase_: ReturningResult,
      call_: Some({ ..call, result_: result }),
      adapter_invocations_: state.adapter_invocations_ + 1,
      committed_writes_: state.committed_writes_ +
      (if write_committed { 1 } else { 0 }),
      last_transition_error_: None,
    },
    [],
  )
}

///|
fn adapter_failed(
  state : BrokerState,
  call_id : String,
) -> Transition {
  guard state.phase_ == Executing else {
    return invalid_transition(state, "adapter_result_requires_executing")
  }
  guard state.call_ is Some(call) else {
    return invalid_transition(state, "adapter_result_missing_call")
  }
  guard call.call_id_ == call_id else {
    return invalid_transition(state, "stale_call_id")
  }
  guard call.dispatch_emitted_ else {
    return invalid_transition(state, "adapter_result_before_dispatch")
  }
  Transition(
    {
      ..state,
      phase_: ReturningResult,
      call_: Some({
        ..call,
        result_: error_result(
          "adapter_failed",
          "fake adapter returned a sanitized failure",
        ),
      }),
      adapter_invocations_: state.adapter_invocations_ + 1,
      last_transition_error_: None,
    },
    [],
  )
}

///|
fn prepare_result(state : BrokerState) -> Transition {
  guard state.phase_ == Rejected else {
    return invalid_transition(state, "prepare_requires_rejected")
  }
  guard state.call_ is Some(call) else {
    return invalid_transition(state, "prepare_missing_call")
  }
  guard call.result_ != Json::null() else {
    return invalid_transition(state, "prepare_missing_result")
  }
  Transition(
    { ..state, phase_: ReturningResult, last_transition_error_: None },
    [],
  )
}

///|
fn deliver_result(state : BrokerState) -> Transition {
  guard state.phase_ == ReturningResult else {
    return invalid_transition(state, "delivery_requires_returning_result")
  }
  guard state.call_ is Some(call) else {
    return invalid_transition(state, "delivery_missing_call")
  }
  guard call.result_ != Json::null() else {
    return invalid_transition(state, "delivery_missing_result")
  }
  Transition(
    { ..state, phase_: Completed, last_transition_error_: None },
    [DeliverToolResult(call.result_)],
  )
}

///|
pub fn apply_host_action(
  state : BrokerState,
  action : HostAction,
) -> Transition {
  match action {
    ValidatePending => validate_pending(state)
    Approve(call_id) => approve_pending(state, call_id)
    Reject(call_id, reason) => reject_pending(state, call_id, reason)
    Dispatch(call_id) => dispatch_pending(state, call_id)
    Cancel(call_id, reason) => cancel_before_dispatch(state, call_id, reason)
    AdapterSucceeded(call_id, value, write_committed) =>
      adapter_succeeded(state, call_id, value, write_committed)
    AdapterFailed(call_id) => adapter_failed(state, call_id)
    PrepareResult => prepare_result(state)
    DeliverResult => deliver_result(state)
  }
}
