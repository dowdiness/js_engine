///|
fn int_json(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn optional_string_json(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn require_invariant(condition : Bool, message : String) -> Unit {
  guard condition else { abort("PROTOTYPE invariant failed: " + message) }
}

///|
priv struct ScenarioSession {
  scenario_ : String
  events_ : Array[@replay.ReplayEvent]
  transcript_ : Array[String]
  adapter_ : FakeAdapter
  mut projection_ : @replay.ReplayState
  mut engine_ : EngineShell?
  mut broker_ : BrokerShell?
  mut engine_epoch_ : Int
  mut observation_ : Json?
  mut pending_result_ : Json?
  mut pending_invocation_ : @broker.AdapterInvocation?
  mut replay_cursor_ : Int
  mut last_replay_error_ : String?
  mut last_replay_engine_started_ : Bool
  mut action_sequence_ : Int
}

///|
fn ScenarioSession::ScenarioSession(scenario : String) -> ScenarioSession {
  {
    scenario_: scenario,
    events_: [],
    transcript_: [],
    adapter_: FakeAdapter(),
    projection_: @replay.ReplayState(),
    engine_: None,
    broker_: None,
    engine_epoch_: 0,
    observation_: None,
    pending_result_: None,
    pending_invocation_: None,
    replay_cursor_: 0,
    last_replay_error_: None,
    last_replay_engine_started_: false,
    action_sequence_: 0,
  }
}

///|
fn ScenarioSession::engine(self : ScenarioSession) -> EngineShell {
  match self.engine_ {
    Some(engine) => engine
    None => abort("PROTOTYPE invariant: scenario has no Engine")
  }
}

///|
fn ScenarioSession::broker(self : ScenarioSession) -> BrokerShell {
  match self.broker_ {
    Some(broker) => broker
    None => abort("PROTOTYPE invariant: scenario has no ToolBroker")
  }
}

///|
fn ScenarioSession::append_event(
  self : ScenarioSession,
  event : @replay.ReplayEvent,
) -> Unit {
  let result = @replay.apply_event(self.projection_, event)
  guard result.accepted() else {
    abort(
      "PROTOTYPE event append rejected: " +
      (match result.error() {
        Some(error) => error
        None => "unknown"
      }),
    )
  }
  self.events_.push(event)
  self.projection_ = result.state()
}

///|
fn ScenarioSession::event_log_json(self : ScenarioSession) -> Json {
  Json::array(self.events_.map(event => event.render()))
}

///|
fn ScenarioSession::engine_render(self : ScenarioSession) -> Json {
  match self.engine_ {
    Some(engine) =>
      Json::object({
        "epoch": int_json(engine.epoch()),
        "status": Json::string(engine.status()),
      })
    None =>
      Json::object({
        "epoch": int_json(self.engine_epoch_),
        "status": Json::string("absent"),
      })
  }
}

///|
fn ScenarioSession::broker_render(self : ScenarioSession) -> Json {
  match self.broker_ {
    Some(broker) => broker.render()
    None => Json::null()
  }
}

///|
fn ScenarioSession::record(
  self : ScenarioSession,
  action : String,
  outcome : String,
) -> Unit {
  self.action_sequence_ += 1
  self.transcript_.push(
    Json::object({
      "schema": Json::string("agent-runtime-p3-action/v1"),
      "scenario": Json::string(self.scenario_),
      "action_sequence": int_json(self.action_sequence_),
      "action": Json::string(action),
      "outcome": Json::string(outcome),
      "event_count": int_json(self.events_.length()),
      "event_log": self.event_log_json(),
      "replay_state": self.projection_.render(),
      "broker_state": self.broker_render(),
      "adapter_state": self.adapter_.render(),
      "engine": self.engine_render(),
      "replay_cursor": int_json(self.replay_cursor_),
      "last_replay_error": optional_string_json(self.last_replay_error_),
      "last_replay_engine_started": Json::boolean(
        self.last_replay_engine_started_,
      ),
    }).stringify(),
  )
}

///|
fn ScenarioSession::observe_tool_request(self : ScenarioSession) -> Unit {
  guard self.observation_ is Some(reply) else {
    abort("PROTOTYPE invariant: no Engine observation to record")
  }
  guard reply_payload(reply, "tool_request") is Some(request) else {
    abort("PROTOTYPE invariant: expected ToolRequest observation")
  }
  let call_id = self.broker().submit_and_validate(request)
  let idempotency_key = self.broker().expected_idempotency_key(call_id)
  self.append_event(
    @replay.request_observed_event(
      self.projection_.next_sequence(),
      call_id,
      idempotency_key,
      request,
    ),
  )
  self.observation_ = None
}

///|
fn ScenarioSession::observe_completion(self : ScenarioSession) -> Unit {
  guard self.observation_ is Some(reply) else {
    abort("PROTOTYPE invariant: no Engine completion to record")
  }
  guard reply_payload(reply, "completion") is Some(completion) else {
    abort("PROTOTYPE invariant: expected completion observation")
  }
  self.append_event(
    @replay.session_completed_event(
      self.projection_.next_sequence(),
      completion,
    ),
  )
  self.observation_ = None
}

///|
fn ScenarioSession::observe_next(self : ScenarioSession) -> Unit {
  guard self.observation_ is Some(reply) else {
    abort("PROTOTYPE invariant: replay produced no observation")
  }
  if reply_payload(reply, "tool_request") is Some(_) {
    self.observe_tool_request()
  } else if reply_payload(reply, "completion") is Some(_) {
    self.observe_completion()
  } else {
    abort("PROTOTYPE invariant: Engine produced an unknown observation")
  }
}

///|
fn ScenarioSession::start(
  self : ScenarioSession,
  input : Json,
) -> Unit raise @js_engine.EngineError {
  require_invariant(self.engine_epoch_ == 0, "session may start only once")
  self.engine_epoch_ = 1
  self.engine_ = Some(EngineShell(self.engine_epoch_))
  self.broker_ = Some(BrokerShell(SESSION_ID))
  self.append_event(
    @replay.session_started_event(
      self.projection_.next_sequence(),
      SESSION_ID,
      source_hash(),
      RUNTIME_FINGERPRINT,
      host_config_hash(),
      input,
    ),
  )
  self.observation_ = Some(self.engine().start(input))
  self.observe_tool_request()
  self.record("start", "request_recorded")
}

///|
fn ScenarioSession::approve(self : ScenarioSession) -> Unit {
  let call_id = self.projection_.current_call_id()
  self.broker().approve(call_id)
  self.append_event(
    @replay.approval_granted_event(self.projection_.next_sequence(), call_id),
  )
  self.record("approve", "approval_recorded")
}

///|
fn ScenarioSession::dispatch(
  self : ScenarioSession,
  action : String,
  record_result : Bool,
) -> Unit {
  let call_id = self.projection_.current_call_id()
  let idempotency_key = self.projection_.current_idempotency_key()
  let invocation = self.broker().dispatch(call_id)
  require_invariant(
    invocation.idempotency_key() == idempotency_key,
    "P1 dispatch identity must match event projection",
  )
  require_invariant(
    invocation_request(invocation).equal(self.projection_.current_request()),
    "P1 dispatch request must match recorded request",
  )
  self.append_event(
    @replay.dispatch_intent_event(
      self.projection_.next_sequence(),
      call_id,
      idempotency_key,
    ),
  )
  let adapter_outcome = self.adapter_.execute(invocation, "live")
  self.pending_invocation_ = Some(invocation)
  if record_result {
    let result = adapter_outcome.tagged_result()
    self.append_event(
      @replay.tool_result_event(
        self.projection_.next_sequence(),
        call_id,
        idempotency_key,
        result,
        adapter_outcome.write_committed(),
      ),
    )
    self.pending_result_ = Some(
      self
      .broker()
      .record_and_deliver(call_id, result, adapter_outcome.write_committed()),
    )
    self.pending_invocation_ = None
    self.record(action, "tool_result_recorded_before_resume")
  } else {
    self.record(action, "outcome_unknown_after_external_effect")
  }
}

///|
fn ScenarioSession::return_result(
  self : ScenarioSession,
  action : String,
) -> Unit raise @js_engine.EngineError {
  guard self.pending_result_ is Some(result) else {
    abort("PROTOTYPE invariant: no recorded result to return")
  }
  self.observation_ = Some(self.engine().supply_result(result))
  self.pending_result_ = None
  self.observe_next()
  self.record(action, "agent_observation_recorded")
}

///|
fn ScenarioSession::crash(self : ScenarioSession, action : String) -> Unit {
  self.engine().crash()
  self.record(action, "engine_discarded_log_retained")
}

///|
fn ScenarioSession::replay_with_identity(
  self : ScenarioSession,
  action : String,
  expected_source_hash : String,
  expected_runtime_fingerprint : String,
  expected_host_config_hash : String,
  expected_input : Json,
  record_pending_observation : Bool,
) -> Unit raise @js_engine.EngineError {
  let next_epoch = self.engine_epoch_ + 1
  let outcome = replay_log(
    self.events_,
    expected_source_hash,
    expected_runtime_fingerprint,
    expected_host_config_hash,
    expected_input,
    next_epoch,
  )
  self.replay_cursor_ = outcome.replay_cursor()
  self.last_replay_error_ = outcome.error()
  self.last_replay_engine_started_ = outcome.engine_started()
  if outcome.accepted() {
    self.projection_ = outcome.projection()
    self.engine_epoch_ = next_epoch
    self.engine_ = outcome.engine()
    self.broker_ = outcome.broker()
    self.pending_result_ = None
    self.pending_invocation_ = outcome.pending_invocation()
    self.observation_ = outcome.pending_observation()
    if record_pending_observation && self.observation_ is Some(_) {
      self.observe_next()
    }
    self.record(action, "replay_accepted_without_adapter_execution")
  } else {
    self.record(
      action,
      match outcome.error() {
        Some(error) => "replay_rejected:" + error
        None => "replay_rejected"
      },
    )
  }
}

///|
fn ScenarioSession::replay(
  self : ScenarioSession,
  action : String,
  record_pending_observation : Bool,
) -> Unit raise @js_engine.EngineError {
  self.replay_with_identity(
    action,
    source_hash(),
    RUNTIME_FINGERPRINT,
    host_config_hash(),
    self.projection_.input(),
    record_pending_observation,
  )
}

///|
fn ScenarioSession::cancel(self : ScenarioSession, reason : String) -> Unit {
  let call_id = self.projection_.current_call_id()
  self.broker().cancel(call_id, reason)
  self.append_event(
    @replay.session_cancelled_event(
      self.projection_.next_sequence(),
      call_id,
      reason,
    ),
  )
  self.record("cancel", "cancelled_before_dispatch")
}

///|
fn ScenarioSession::reconcile_unknown_outcome(self : ScenarioSession) -> Unit {
  guard self.pending_invocation_ is Some(invocation) else {
    abort("PROTOTYPE invariant: no unknown adapter outcome to reconcile")
  }
  let outcome = self.adapter_.execute(invocation, "reconcile")
  require_invariant(
    outcome.cache_hit(),
    "reconciliation must hit stable fake key",
  )
  let call_id = invocation.call_id()
  let idempotency_key = invocation.idempotency_key()
  let result = outcome.tagged_result()
  self.append_event(
    @replay.tool_result_event(
      self.projection_.next_sequence(),
      call_id,
      idempotency_key,
      result,
      outcome.write_committed(),
    ),
  )
  self.pending_result_ = Some(
    self.broker().record_and_deliver(call_id, result, outcome.write_committed()),
  )
  self.pending_invocation_ = None
  self.record(
    "reconcile_unknown_outcome", "same_key_cache_hit_no_second_write_commit",
  )
}

///|
fn ScenarioSession::lines(self : ScenarioSession) -> Array[String] {
  self.transcript_
}

///|
fn ScenarioSession::events(
  self : ScenarioSession,
) -> Array[@replay.ReplayEvent] {
  self.events_
}

///|
fn append_lines(target : Array[String], source : Array[String]) -> Unit {
  target.push_iter(source.iter())
}

///|
fn require_event_logs_equal(
  actual : Array[@replay.ReplayEvent],
  expected : Array[@replay.ReplayEvent],
) -> Unit {
  require_invariant(
    actual.length() == expected.length(),
    "event count mismatch",
  )
  for index, event in actual {
    require_invariant(
      event.render().equal(expected[index].render()),
      "canonical event mismatch at index " + index.to_string(),
    )
  }
}

///|
fn canonical_completed_events() -> Array[@replay.ReplayEvent] {
  let read_request = get_user_request("user-1")
  let write_request = update_user_request("user-1")
  let read_result = get_user_result("user-1", "inactive")
  let write_result = update_user_result("user-1")
  [
    @replay.session_started_event(
      1,
      SESSION_ID,
      source_hash(),
      RUNTIME_FINGERPRINT,
      host_config_hash(),
      required_input(),
    ),
    @replay.request_observed_event(
      2,
      "call-1",
      SESSION_ID + ":call-1",
      read_request,
    ),
    @replay.dispatch_intent_event(3, "call-1", SESSION_ID + ":call-1"),
    @replay.tool_result_event(
      4,
      "call-1",
      SESSION_ID + ":call-1",
      read_result,
      false,
    ),
    @replay.request_observed_event(
      5,
      "call-2",
      SESSION_ID + ":call-2",
      write_request,
    ),
    @replay.approval_granted_event(6, "call-2"),
    @replay.dispatch_intent_event(7, "call-2", SESSION_ID + ":call-2"),
    @replay.tool_result_event(
      8,
      "call-2",
      SESSION_ID + ":call-2",
      write_result,
      true,
    ),
    @replay.session_completed_event(9, expected_completion("user-1", true)),
  ]
}

///|
fn run_uninterrupted_oracle(
  lines : Array[String],
) -> Json raise @js_engine.EngineError {
  let session = ScenarioSession("uninterrupted_oracle")
  session.start(required_input())
  session.dispatch("dispatch_read", true)
  session.return_result("return_read_result")
  session.approve()
  session.dispatch("dispatch_write", true)
  session.return_result("return_write_result")
  require_invariant(
    session.projection_.completion().equal(expected_completion("user-1", true)),
    "uninterrupted oracle completion mismatch",
  )
  require_invariant(
    session.adapter_.external_write_commits() == 1,
    "uninterrupted oracle must commit one fake write",
  )
  append_lines(lines, session.lines())
  session.projection_.completion()
}

///|
fn run_required_post_result_crash(
  lines : Array[String],
  oracle : Json,
) -> Unit raise @js_engine.EngineError {
  let session = ScenarioSession("post_write_result_crash")
  session.start(required_input())
  session.dispatch("dispatch_read", true)
  session.return_result("return_read_result")
  session.crash("crash_waiting_approval")
  session.replay("replay_approval_wait", false)
  require_invariant(
    session.projection_.phase() == "WaitingApproval",
    "approval wait must recover",
  )
  require_invariant(
    session.broker().approval_status() == "pending",
    "approval must remain pending after replay",
  )
  require_invariant(
    session.adapter_.external_write_commits() == 0,
    "approval replay must not execute write",
  )
  session.approve()
  session.dispatch("dispatch_write", true)
  session.crash("crash_after_tool_result")
  session.replay("replay", true)
  require_invariant(
    session.projection_.phase() == "Completed" &&
    session.projection_.completion().equal(oracle) &&
    session.pending_result_ is None,
    "post-result replay must reach oracle completion",
  )
  require_invariant(
    session.adapter_.external_write_commits() == 1,
    "post-result replay must retain exactly one fake write",
  )
  require_invariant(
    session.adapter_.replay_invocations() == 0,
    "replay must never call the adapter",
  )
  session.crash("crash_completed_session")
  session.replay("replay_completed", false)
  session.replay("replay_completed_again", false)
  require_invariant(
    session.projection_.completion().equal(oracle) &&
    session.events_.length() == 9 &&
    session.replay_cursor_ == 9,
    "completion replay must be stable and append nothing",
  )
  require_event_logs_equal(session.events(), canonical_completed_events())
  append_lines(lines, session.lines())
}

///|
fn run_read_only_completion_recovery(
  lines : Array[String],
) -> Unit raise @js_engine.EngineError {
  let session = ScenarioSession("completed_read_only_recovery")
  session.start(active_input())
  session.dispatch("dispatch_read", true)
  session.return_result("return_read_result")
  let completion = session.projection_.completion()
  session.crash("crash_after_completion")
  session.replay("replay_completed", false)
  require_invariant(
    session.projection_.completion().equal(completion),
    "read-only completion must recover exactly",
  )
  require_invariant(
    session.adapter_.external_write_commits() == 0,
    "read-only recovery must not write",
  )
  append_lines(lines, session.lines())
}

///|
fn run_cancel_recovery(
  lines : Array[String],
) -> Unit raise @js_engine.EngineError {
  let session = ScenarioSession("cancelled_session_recovery")
  session.start(required_input())
  session.dispatch("dispatch_read", true)
  session.return_result("return_read_result")
  session.cancel("operator cancelled prototype write")
  session.crash("crash_after_cancel")
  session.replay("replay_cancelled", false)
  require_invariant(
    session.projection_.phase() == "Cancelled" &&
    session.broker().phase() == "Cancelled",
    "cancelled session must recover terminal state",
  )
  require_invariant(
    session.adapter_.external_write_commits() == 0,
    "cancel recovery must not execute write",
  )
  append_lines(lines, session.lines())
}

///|
fn run_unknown_outcome_reconciliation(
  lines : Array[String],
) -> Unit raise @js_engine.EngineError {
  let session = ScenarioSession("commit_before_result_boundary")
  session.start(required_input())
  session.dispatch("dispatch_read", true)
  session.return_result("return_read_result")
  session.approve()
  session.dispatch("dispatch_write_without_result_record", false)
  require_invariant(
    session.adapter_.external_write_commits() == 1,
    "fake write must commit before injected crash",
  )
  session.crash("crash_before_tool_result_record")
  session.replay("replay_outcome_unknown", false)
  require_invariant(
    session.projection_.phase() == "AwaitingToolResult" &&
    session.adapter_.replay_invocations() == 0,
    "unknown outcome replay must stop without adapter execution",
  )
  session.reconcile_unknown_outcome()
  require_invariant(
    session.adapter_.external_write_commits() == 1,
    "same-key reconciliation must not commit twice",
  )
  session.crash("crash_after_reconciled_result")
  session.replay("replay_reconciled_result", true)
  require_invariant(
    session.projection_.phase() == "Completed",
    "reconciled result must replay to completion",
  )
  append_lines(lines, session.lines())
}

///|
fn zero_adapter_state() -> Json {
  FakeAdapter().render()
}

///|
fn append_replay_diagnostic(
  lines : Array[String],
  scenario : String,
  action : String,
  events : Array[@replay.ReplayEvent],
  outcome : ReplayOutcome,
) -> Unit {
  lines.push(
    Json::object({
      "schema": Json::string("agent-runtime-p3-action/v1"),
      "scenario": Json::string(scenario),
      "action_sequence": int_json(1),
      "action": Json::string(action),
      "outcome": Json::string(
        if outcome.accepted() {
          "unexpected_acceptance"
        } else {
          "replay_rejected:" +
          (match outcome.error() {
            Some(error) => error
            None => "unknown"
          })
        },
      ),
      "event_count": int_json(events.length()),
      "event_log": Json::array(events.map(event => event.render())),
      "replay_state": outcome.projection().render(),
      "broker_state": Json::null(),
      "adapter_state": zero_adapter_state(),
      "engine": Json::object({
        "epoch": int_json(0),
        "status": Json::string(
          if outcome.engine_started() {
            "discarded_after_rejection"
          } else {
            "not_started"
          },
        ),
      }),
      "replay_cursor": int_json(outcome.replay_cursor()),
      "last_replay_error": optional_string_json(outcome.error()),
      "last_replay_engine_started": Json::boolean(outcome.engine_started()),
    }).stringify(),
  )
}

///|
fn divergent_request_events() -> Array[@replay.ReplayEvent] {
  let events = canonical_completed_events()
  let divergent : Array[@replay.ReplayEvent] = []
  for event in events {
    if event.sequence() == 5 {
      divergent.push(
        @replay.request_observed_event(
          5,
          "call-2",
          SESSION_ID + ":call-2",
          update_user_request("user-diverged"),
        ),
      )
    } else {
      divergent.push(event)
    }
  }
  divergent
}

///|
fn gapped_events() -> Array[@replay.ReplayEvent] {
  [
    @replay.session_started_event(
      1,
      SESSION_ID,
      source_hash(),
      RUNTIME_FINGERPRINT,
      host_config_hash(),
      required_input(),
    ),
    @replay.request_observed_event(
      3,
      "call-1",
      SESSION_ID + ":call-1",
      get_user_request("user-1"),
    ),
  ]
}

///|
fn stale_result_events() -> Array[@replay.ReplayEvent] {
  [
    @replay.session_started_event(
      1,
      SESSION_ID,
      source_hash(),
      RUNTIME_FINGERPRINT,
      host_config_hash(),
      required_input(),
    ),
    @replay.request_observed_event(
      2,
      "call-1",
      SESSION_ID + ":call-1",
      get_user_request("user-1"),
    ),
    @replay.dispatch_intent_event(3, "call-1", SESSION_ID + ":call-1"),
    @replay.tool_result_event(
      4,
      "call-9",
      SESSION_ID + ":call-9",
      get_user_result("user-1", "inactive"),
      false,
    ),
  ]
}

///|
fn run_negative_replay_cases(
  lines : Array[String],
) -> Unit raise @js_engine.EngineError {
  let canonical = canonical_completed_events()
  let source_mismatch = replay_log(
    canonical,
    source_hash() + "00",
    RUNTIME_FINGERPRINT,
    host_config_hash(),
    required_input(),
    2,
  )
  require_invariant(
    source_mismatch.error() == Some("source_hash_mismatch") &&
    !source_mismatch.engine_started() &&
    source_mismatch.replay_cursor() == 0,
    "source mismatch must fail before Engine start",
  )
  append_replay_diagnostic(
    lines, "source_hash_mismatch", "replay", canonical, source_mismatch,
  )
  let runtime_mismatch = replay_log(
    canonical,
    source_hash(),
    RUNTIME_FINGERPRINT + ";drift",
    host_config_hash(),
    required_input(),
    2,
  )
  require_invariant(
    runtime_mismatch.error() == Some("runtime_fingerprint_mismatch") &&
    !runtime_mismatch.engine_started(),
    "runtime mismatch must fail before Engine start",
  )
  append_replay_diagnostic(
    lines, "runtime_fingerprint_mismatch", "replay", canonical, runtime_mismatch,
  )
  let config_mismatch = replay_log(
    canonical,
    source_hash(),
    RUNTIME_FINGERPRINT,
    host_config_hash() + "00",
    required_input(),
    2,
  )
  require_invariant(
    config_mismatch.error() == Some("host_config_mismatch") &&
    !config_mismatch.engine_started(),
    "host config mismatch must fail before Engine start",
  )
  append_replay_diagnostic(
    lines, "host_config_mismatch", "replay", canonical, config_mismatch,
  )
  let input_mismatch = replay_log(
    canonical,
    source_hash(),
    RUNTIME_FINGERPRINT,
    host_config_hash(),
    Json::object({ "user_id": Json::string("other-user") }),
    2,
  )
  require_invariant(
    input_mismatch.error() == Some("input_mismatch") &&
    !input_mismatch.engine_started(),
    "input mismatch must fail before Engine start",
  )
  append_replay_diagnostic(
    lines, "input_mismatch", "replay", canonical, input_mismatch,
  )
  let divergent = divergent_request_events()
  let divergence = replay_log(
    divergent,
    source_hash(),
    RUNTIME_FINGERPRINT,
    host_config_hash(),
    required_input(),
    2,
  )
  require_invariant(
    divergence.error() == Some("request_payload_mismatch") &&
    divergence.replay_cursor() == 4,
    "request divergence must fail before recorded write result delivery",
  )
  append_replay_diagnostic(
    lines, "request_sequence_divergence", "replay", divergent, divergence,
  )
  let gap = gapped_events()
  let gap_outcome = replay_log(
    gap,
    source_hash(),
    RUNTIME_FINGERPRINT,
    host_config_hash(),
    required_input(),
    2,
  )
  require_invariant(
    gap_outcome.error() == Some("non_contiguous_event_sequence") &&
    !gap_outcome.engine_started(),
    "sequence gap must fail in pure reducer",
  )
  append_replay_diagnostic(
    lines, "gapped_event_sequence", "replay", gap, gap_outcome,
  )
  let stale = stale_result_events()
  let stale_outcome = replay_log(
    stale,
    source_hash(),
    RUNTIME_FINGERPRINT,
    host_config_hash(),
    required_input(),
    2,
  )
  require_invariant(
    stale_outcome.error() == Some("tool_result_call_id_mismatch") &&
    !stale_outcome.engine_started(),
    "stale ToolResult identity must fail in pure reducer",
  )
  append_replay_diagnostic(
    lines, "stale_tool_result_identity", "replay", stale, stale_outcome,
  )
}

///|
fn summary_line(lines : Array[String]) -> String {
  Json::object({
    "schema": Json::string("agent-runtime-p3-summary/v1"),
    "scenario": Json::string("summary"),
    "action": Json::string("verdict"),
    "verdict": Json::string("GO"),
    "question": Json::string(
      "Can a fresh Engine recover fixed pending/completed state from source, input, and an append-only event log without replaying a recorded write?",
    ),
    "action_rows": int_json(lines.length()),
    "jsonl_rows_including_summary": int_json(lines.length() + 1),
    "required_event_count": int_json(9),
    "required_request_sequence": int_json(2),
    "required_fake_external_write_commits": int_json(1),
    "required_replay_adapter_invocations": int_json(0),
    "scope": Json::string(
      "native fixed fixture; Engine crash only; host in-memory log and fake idempotency registry survive",
    ),
  }).stringify()
}

///|
fn run_required_scenarios() -> Array[String] raise @js_engine.EngineError {
  let lines : Array[String] = []
  let oracle = run_uninterrupted_oracle(lines)
  run_required_post_result_crash(lines, oracle)
  run_read_only_completion_recovery(lines)
  run_cancel_recovery(lines)
  run_unknown_outcome_reconciliation(lines)
  run_negative_replay_cases(lines)
  lines.push(summary_line(lines))
  lines
}

///|
pub fn required_event_log() -> Array[String] {
  canonical_completed_events().map(event => event.render().stringify())
}

///|
pub fn required_transcript() -> Array[String] {
  run_required_scenarios() catch {
    _ => abort("PROTOTYPE stable Engine facade call failed")
  }
}
