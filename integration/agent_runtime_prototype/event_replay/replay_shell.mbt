///|
/// PROTOTYPE replay result. Adapter execution is intentionally absent.
priv struct ReplayOutcome {
  accepted_ : Bool
  error_ : String?
  projection_ : @replay.ReplayState
  engine_ : EngineShell?
  broker_ : BrokerShell?
  pending_observation_ : Json?
  pending_invocation_ : @broker.AdapterInvocation?
  replay_cursor_ : Int
  engine_started_ : Bool
}

///|
fn replay_rejected(
  projection : @replay.ReplayState,
  error : String,
  replay_cursor : Int,
  engine_started : Bool,
) -> ReplayOutcome {
  {
    accepted_: false,
    error_: Some(error),
    projection_: projection,
    engine_: None,
    broker_: None,
    pending_observation_: None,
    pending_invocation_: None,
    replay_cursor_: replay_cursor,
    engine_started_: engine_started,
  }
}

///|
fn ReplayOutcome::accepted(self : ReplayOutcome) -> Bool {
  self.accepted_
}

///|
fn ReplayOutcome::error(self : ReplayOutcome) -> String? {
  self.error_
}

///|
fn ReplayOutcome::projection(self : ReplayOutcome) -> @replay.ReplayState {
  self.projection_
}

///|
fn ReplayOutcome::engine(self : ReplayOutcome) -> EngineShell? {
  self.engine_
}

///|
fn ReplayOutcome::broker(self : ReplayOutcome) -> BrokerShell? {
  self.broker_
}

///|
fn ReplayOutcome::pending_observation(self : ReplayOutcome) -> Json? {
  self.pending_observation_
}

///|
fn ReplayOutcome::pending_invocation(
  self : ReplayOutcome,
) -> @broker.AdapterInvocation? {
  self.pending_invocation_
}

///|
fn ReplayOutcome::replay_cursor(self : ReplayOutcome) -> Int {
  self.replay_cursor_
}

///|
fn ReplayOutcome::engine_started(self : ReplayOutcome) -> Bool {
  self.engine_started_
}

///|
fn reply_payload(reply : Json, expected_kind : String) -> Json? {
  match reply {
    Json::Object(fields) =>
      match fields.get("kind") {
        Some(Json::String(kind)) if kind == expected_kind =>
          fields.get(
            if kind == "tool_request" {
              "request"
            } else {
              "completion"
            },
          )
        _ => None
      }
    _ => None
  }
}

///|
fn invocation_request(invocation : @broker.AdapterInvocation) -> Json {
  Json::object({
    "tool": Json::string(invocation.tool()),
    "arguments": invocation.arguments(),
  })
}

///|
fn fail_after_engine(
  projection : @replay.ReplayState,
  error : String,
  cursor : Int,
  engine : EngineShell,
) -> ReplayOutcome {
  engine.crash()
  replay_rejected(projection, error, cursor, true)
}

///|
fn replay_log(
  events : Array[@replay.ReplayEvent],
  expected_source_hash : String,
  expected_runtime_fingerprint : String,
  expected_host_config_hash : String,
  expected_input : Json,
  engine_epoch : Int,
) -> ReplayOutcome raise @js_engine.EngineError {
  let reduction = @replay.reduce_events(events)
  guard reduction.accepted() else {
    return replay_rejected(
      reduction.state(),
      match reduction.error() {
        Some(error) => error
        None => "invalid_event_log"
      },
      reduction.state().replay_cursor(),
      false,
    )
  }
  let projection = reduction.state()
  guard events.length() > 0 else {
    return replay_rejected(projection, "empty_event_log", 0, false)
  }
  guard projection.source_hash() == expected_source_hash else {
    return replay_rejected(projection, "source_hash_mismatch", 0, false)
  }
  guard projection.runtime_fingerprint() == expected_runtime_fingerprint else {
    return replay_rejected(projection, "runtime_fingerprint_mismatch", 0, false)
  }
  guard projection.host_config_hash() == expected_host_config_hash else {
    return replay_rejected(projection, "host_config_mismatch", 0, false)
  }
  guard projection.input().equal(expected_input) else {
    return replay_rejected(projection, "input_mismatch", 0, false)
  }
  let engine = EngineShell(engine_epoch)
  let broker = BrokerShell(SESSION_ID)
  let mut observation : Json? = None
  let mut pending_invocation : @broker.AdapterInvocation? = None
  let mut cursor = 0
  for event in events {
    match event.kind() {
      @replay.SessionStarted(session_id, _, _, _, input) => {
        guard session_id == SESSION_ID else {
          return fail_after_engine(
            projection, "session_id_mismatch", cursor, engine,
          )
        }
        observation = Some(engine.start(input))
      }
      @replay.ToolRequestObserved(call_id, idempotency_key, request) => {
        guard observation is Some(reply) else {
          return fail_after_engine(
            projection, "request_without_engine_observation", cursor, engine,
          )
        }
        guard reply_payload(reply, "tool_request") is Some(actual_request) else {
          return fail_after_engine(
            projection, "expected_tool_request", cursor, engine,
          )
        }
        guard actual_request.equal(request) else {
          return fail_after_engine(
            projection, "request_payload_mismatch", cursor, engine,
          )
        }
        let actual_call_id = broker.submit_and_validate(request)
        guard actual_call_id == call_id else {
          return fail_after_engine(
            projection, "broker_call_id_mismatch", cursor, engine,
          )
        }
        guard broker.expected_idempotency_key(call_id) == idempotency_key else {
          return fail_after_engine(
            projection, "broker_idempotency_key_mismatch", cursor, engine,
          )
        }
        observation = None
      }
      @replay.ApprovalGranted(call_id) => broker.approve(call_id)
      @replay.DispatchIntentRecorded(call_id, idempotency_key) => {
        let invocation = broker.dispatch(call_id)
        guard invocation.call_id() == call_id else {
          return fail_after_engine(
            projection, "dispatch_call_id_mismatch", cursor, engine,
          )
        }
        guard invocation.idempotency_key() == idempotency_key else {
          return fail_after_engine(
            projection, "dispatch_idempotency_key_mismatch", cursor, engine,
          )
        }
        guard invocation_request(invocation).equal(
          projection_for_prefix(events, event.sequence()).current_request(),
        ) else {
          return fail_after_engine(
            projection, "dispatch_request_mismatch", cursor, engine,
          )
        }
        pending_invocation = Some(invocation)
      }
      @replay.ToolResultRecorded(
        call_id,
        idempotency_key,
        result,
        write_committed
      ) => {
        guard pending_invocation is Some(invocation) else {
          return fail_after_engine(
            projection, "result_without_replayed_dispatch", cursor, engine,
          )
        }
        guard invocation.call_id() == call_id &&
          invocation.idempotency_key() == idempotency_key else {
          return fail_after_engine(
            projection, "result_identity_mismatch", cursor, engine,
          )
        }
        let delivered = broker.record_and_deliver(
          call_id, result, write_committed,
        )
        observation = Some(engine.supply_result(delivered))
        pending_invocation = None
      }
      @replay.SessionCompleted(completion) => {
        guard observation is Some(reply) else {
          return fail_after_engine(
            projection, "completion_without_engine_observation", cursor, engine,
          )
        }
        guard reply_payload(reply, "completion") is Some(actual_completion) else {
          return fail_after_engine(
            projection, "expected_completion", cursor, engine,
          )
        }
        guard actual_completion.equal(completion) else {
          return fail_after_engine(
            projection, "completion_mismatch", cursor, engine,
          )
        }
        observation = None
      }
      @replay.SessionCancelled(call_id, reason) =>
        broker.cancel(call_id, reason)
    }
    cursor = event.sequence()
  }
  {
    accepted_: true,
    error_: None,
    projection_: projection,
    engine_: Some(engine),
    broker_: Some(broker),
    pending_observation_: observation,
    pending_invocation_: pending_invocation,
    replay_cursor_: cursor,
    engine_started_: true,
  }
}

///|
/// Reduces only a verified prefix; used to compare Dispatch against that request.
fn projection_for_prefix(
  events : Array[@replay.ReplayEvent],
  inclusive_sequence : Int,
) -> @replay.ReplayState {
  let prefix : Array[@replay.ReplayEvent] = []
  for event in events {
    if event.sequence() <= inclusive_sequence {
      prefix.push(event)
    }
  }
  let reduced = @replay.reduce_events(prefix)
  guard reduced.accepted() else {
    abort("PROTOTYPE invariant: previously validated prefix became invalid")
  }
  reduced.state()
}
