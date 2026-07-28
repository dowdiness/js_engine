///|
pub struct SessionState {
  engine_epoch_ : Int
  phase_ : String
  pending_request_ : Json
  last_result_ : Json
  completion_ : Json
  discarded_ : Bool
  discard_reason_ : Json
  last_protocol_error_ : Json
}

///|
pub fn SessionState::SessionState(engine_epoch : Int) -> SessionState {
  {
    engine_epoch_: engine_epoch,
    phase_: "idle",
    pending_request_: Json::null(),
    last_result_: Json::null(),
    completion_: Json::null(),
    discarded_: false,
    discard_reason_: Json::null(),
    last_protocol_error_: Json::null(),
  }
}

///|
fn SessionState::with_reply(
  self : SessionState,
  reply : Json,
  last_result : Json,
) -> SessionState {
  let fields = match reply {
    Object(fields) => fields
    _ => abort("PROTOTYPE invariant: generator reply must be an object")
  }
  let kind = match fields.get("kind") {
    Some(String(kind)) => kind
    _ => abort("PROTOTYPE invariant: generator reply must have a string kind")
  }
  match kind {
    "tool_request" => {
      let request = match fields.get("request") {
        Some(Object(_) as request) => request
        _ => abort("PROTOTYPE invariant: tool_request must contain request")
      }
      {
        engine_epoch_: self.engine_epoch_,
        phase_: "waiting",
        pending_request_: request,
        last_result_: last_result,
        completion_: Json::null(),
        discarded_: false,
        discard_reason_: Json::null(),
        last_protocol_error_: Json::null(),
      }
    }
    "completion" => {
      let completion = match fields.get("completion") {
        Some(Object(_) as completion) => completion
        _ =>
          abort("PROTOTYPE invariant: completion reply must contain completion")
      }
      {
        engine_epoch_: self.engine_epoch_,
        phase_: "completed",
        pending_request_: Json::null(),
        last_result_: last_result,
        completion_: completion,
        discarded_: false,
        discard_reason_: Json::null(),
        last_protocol_error_: Json::null(),
      }
    }
    "rejected" => {
      let error = match fields.get("error") {
        Some(Object(_) as error) => error
        _ => abort("PROTOTYPE invariant: rejected reply must contain error")
      }
      {
        engine_epoch_: self.engine_epoch_,
        phase_: self.phase_,
        pending_request_: self.pending_request_,
        last_result_: last_result,
        completion_: self.completion_,
        discarded_: self.discarded_,
        discard_reason_: self.discard_reason_,
        last_protocol_error_: error,
      }
    }
    _ => abort("PROTOTYPE invariant: unknown generator reply kind")
  }
}

///|
pub fn SessionState::record_start(
  self : SessionState,
  reply : Json,
) -> SessionState {
  self.with_reply(reply, Json::null())
}

///|
pub fn SessionState::record_resume(
  self : SessionState,
  result : Json,
  reply : Json,
) -> SessionState {
  self.with_reply(reply, result)
}

///|
pub fn SessionState::record_discard(
  self : SessionState,
  reason : String,
) -> SessionState {
  {
    engine_epoch_: self.engine_epoch_,
    phase_: "discarded",
    pending_request_: Json::null(),
    last_result_: self.last_result_,
    completion_: self.completion_,
    discarded_: true,
    discard_reason_: Json::string(reason),
    last_protocol_error_: Json::null(),
  }
}

///|
pub fn SessionState::engine_epoch(self : SessionState) -> Int {
  self.engine_epoch_
}

///|
pub fn SessionState::render(self : SessionState) -> Json {
  Json::object({
    "engine_epoch": Json::number(
      self.engine_epoch_.to_double(),
      repr=self.engine_epoch_.to_string(),
    ),
    "phase": Json::string(self.phase_),
    "pending_request": self.pending_request_,
    "last_result": self.last_result_,
    "completion": self.completion_,
    "discard_status": Json::object({
      "discarded": Json::boolean(self.discarded_),
      "reason": self.discard_reason_,
    }),
    "last_protocol_error": self.last_protocol_error_,
  })
}

///|
pub fn transcript_record(
  scenario : String,
  sequence : Int,
  action : Json,
  facade_call : Json,
  state : SessionState,
) -> String {
  Json::object({
    "schema": Json::string("agent-runtime-p0-transcript/v1"),
    "scenario": Json::string(scenario),
    "sequence": Json::number(sequence.to_double(), repr=sequence.to_string()),
    "action": action,
    "facade_call": facade_call,
    "state": state.render(),
  }).stringify()
}
