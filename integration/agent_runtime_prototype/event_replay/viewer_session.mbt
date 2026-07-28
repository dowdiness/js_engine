///|
pub struct EventReplayViewer {
  priv mut session_ : ScenarioSession
}

///|
pub fn EventReplayViewer::EventReplayViewer() -> EventReplayViewer {
  { session_: ScenarioSession("interactive_viewer") }
}

///|
fn viewer_snapshot(
  session : ScenarioSession,
  command : String,
  outcome : String,
) -> Json {
  Json::object({
    "command": Json::string(command),
    "outcome": Json::string(outcome),
    "event_count": int_json(session.events_.length()),
    "event_log": session.event_log_json(),
    "replay_state": session.projection_.render(),
    "broker_state": session.broker_render(),
    "adapter_state": session.adapter_.render(),
    "engine": session.engine_render(),
    "replay_cursor": int_json(session.replay_cursor_),
    "last_replay_error": optional_string_json(session.last_replay_error_),
    "last_replay_engine_started": Json::boolean(
      session.last_replay_engine_started_,
    ),
  })
}

///|
pub fn EventReplayViewer::state(self : EventReplayViewer) -> Json {
  viewer_snapshot(self.session_, "state", "unchanged")
}

///|
pub fn EventReplayViewer::prompt(self : EventReplayViewer) -> String {
  match self.session_.projection_.phase() {
    "Empty" => "start | reset | quit"
    "ReadyToDispatch" =>
      "dispatch | dispatch-without-result | cancel | crash | replay | reset | quit"
    "AwaitingAgentResume" => "return-result | crash | replay | reset | quit"
    "WaitingApproval" => "approve | cancel | crash | replay | reset | quit"
    "AwaitingToolResult" => "reconcile | crash | replay | reset | quit"
    "Completed" | "Cancelled" => "crash | replay | reset | quit"
    _ => "state | reset | quit"
  }
}

///|
fn viewer_error(
  session : ScenarioSession,
  command : String,
  expected : String,
) -> Json {
  viewer_snapshot(session, command, "invalid_command; expected " + expected)
}

///|
pub fn EventReplayViewer::apply(
  self : EventReplayViewer,
  command : String,
) -> Json {
  let phase = self.session_.projection_.phase()
  let attempted : Result[Json, @js_engine.EngineError] = Ok(
    match command {
      "state" => self.state()
      "reset" => {
        self.session_ = ScenarioSession("interactive_viewer")
        viewer_snapshot(self.session_, command, "reset")
      }
      "start" if phase == "Empty" => {
        self.session_.start(required_input())
        viewer_snapshot(self.session_, command, "request_recorded")
      }
      "dispatch" if phase == "ReadyToDispatch" => {
        self.session_.dispatch("viewer_dispatch", true)
        viewer_snapshot(self.session_, command, "tool_result_recorded")
      }
      "dispatch-without-result" if phase == "ReadyToDispatch" => {
        self.session_.dispatch("viewer_dispatch_without_result", false)
        viewer_snapshot(self.session_, command, "outcome_unknown")
      }
      "return-result" if phase == "AwaitingAgentResume" => {
        self.session_.return_result("viewer_return_result")
        viewer_snapshot(self.session_, command, "agent_observation_recorded")
      }
      "approve" if phase == "WaitingApproval" => {
        self.session_.approve()
        viewer_snapshot(self.session_, command, "approval_recorded")
      }
      "cancel" if phase == "WaitingApproval" || phase == "ReadyToDispatch" => {
        self.session_.cancel("interactive operator cancellation")
        viewer_snapshot(self.session_, command, "cancelled")
      }
      "crash" if self.session_.engine_ is Some(engine) &&
        engine.status() == "live" => {
        self.session_.crash("viewer_crash")
        viewer_snapshot(self.session_, command, "engine_discarded_log_retained")
      }
      "replay" if self.session_.events_.length() > 0 => {
        self.session_.replay("viewer_replay", true)
        viewer_snapshot(
          self.session_,
          command,
          if self.session_.last_replay_error_ is None {
            "replayed_without_adapter_execution"
          } else {
            "replay_rejected"
          },
        )
      }
      "reconcile" if phase == "AwaitingToolResult" &&
        self.session_.pending_invocation_ is Some(_) => {
        self.session_.reconcile_unknown_outcome()
        viewer_snapshot(self.session_, command, "same_key_cache_hit")
      }
      _ => viewer_error(self.session_, command, self.prompt())
    },
  ) catch {
    error => Err(error)
  }
  match attempted {
    Ok(result) => result
    Err(_) =>
      viewer_error(
        self.session_,
        command,
        "stable Engine facade call to succeed",
      )
  }
}
