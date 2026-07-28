///|
pub struct ToolBrokerViewer {
  priv mut state_ : @core.BrokerState
  priv mut step_ : Int
}

///|
pub fn ToolBrokerViewer::ToolBrokerViewer() -> ToolBrokerViewer {
  {
    state_: @core.BrokerState("viewer-read-only", true, false, 2, 4096),
    step_: 0,
  }
}

///|
pub fn ToolBrokerViewer::state(self : ToolBrokerViewer) -> Json {
  self.state_.render()
}

///|
pub fn ToolBrokerViewer::prompt(self : ToolBrokerViewer) -> String {
  match self.step_ {
    0 => "inject-authority"
    1 => "validate-injection"
    2 => "prepare-rejection"
    3 => "deliver-rejection"
    4 => "start-cancel-scenario"
    5 => "submit-write"
    6 => "validate-write"
    7 => "approve-write"
    8 => "cancel-before-dispatch"
    9 => "late-dispatch"
    10 => "resubmit-after-cancel"
    _ => "done"
  }
}

///|
fn viewer_escalation_request() -> Json {
  Json::object({
    "tool": Json::string("update_user_status"),
    "arguments": Json::object({
      "user_id": Json::string("user-1"),
      "status": Json::string("active"),
    }),
    "authority": Json::string("user.write"),
    "approved": Json::boolean(true),
    "requires_approval": Json::boolean(false),
  })
}

///|
fn viewer_error(command : String, expected : String) -> Json {
  Json::object({
    "code": Json::string("unexpected_command"),
    "message": Json::string(
      "expected '" + expected + "' but received '" + command + "'",
    ),
  })
}

///|
fn viewer_transition(
  walkthrough : String,
  command : String,
  action : Json,
  before : @core.BrokerState,
  transition : @core.Transition,
) -> Json {
  Json::object({
    "viewer": Json::string("agent-runtime-p1/tool-broker"),
    "walkthrough": Json::string(walkthrough),
    "command": Json::string(command),
    "action": action,
    "before": before.render(),
    "after": transition.after().render(),
    "effects": transition.render_effects(),
    "observable_adapter_effects": Json::array([]),
    "viewer_error": Json::null(),
  })
}

///|
fn ToolBrokerViewer::apply_transition(
  self : ToolBrokerViewer,
  walkthrough : String,
  command : String,
  action : Json,
  transition : @core.Transition,
) -> Json {
  let before = self.state_
  let reply = viewer_transition(
    walkthrough, command, action, before, transition,
  )
  self.state_ = transition.after()
  self.step_ += 1
  reply
}

///|
pub fn ToolBrokerViewer::apply(
  self : ToolBrokerViewer,
  command : String,
) -> Json {
  let expected = self.prompt()
  guard command == expected else {
    return Json::object({
      "viewer": Json::string("agent-runtime-p1/tool-broker"),
      "command": Json::string(command),
      "state": self.state_.render(),
      "viewer_error": viewer_error(command, expected),
    })
  }
  match self.step_ {
    0 => {
      let request = viewer_escalation_request()
      let transition = @core.submit_worker_request(self.state_, request)
      self.apply_transition(
        "authority-escalation-attempt",
        command,
        Json::object({
          "kind": Json::string("SubmitRequest"),
          "request": request,
        }),
        transition,
      )
    }
    1 => {
      let action = @core.host_validate()
      let transition = @core.apply_host_action(self.state_, action)
      self.apply_transition(
        "authority-escalation-attempt",
        command,
        action.render(),
        transition,
      )
    }
    2 => {
      let action = @core.host_prepare_result()
      let transition = @core.apply_host_action(self.state_, action)
      self.apply_transition(
        "authority-escalation-attempt",
        command,
        action.render(),
        transition,
      )
    }
    3 => {
      let action = @core.host_deliver_result()
      let transition = @core.apply_host_action(self.state_, action)
      self.apply_transition(
        "authority-escalation-attempt",
        command,
        action.render(),
        transition,
      )
    }
    4 => {
      let before = self.state_
      let after = @core.BrokerState(
        "viewer-cancel-before-dispatch", true, true, 2, 4096,
      )
      self.state_ = after
      self.step_ += 1
      Json::object({
        "viewer": Json::string("agent-runtime-p1/tool-broker"),
        "walkthrough": Json::string("approve-then-cancel-before-dispatch"),
        "command": Json::string(command),
        "action": Json::object({
          "kind": Json::string("HostStartsFreshBrokerSession"),
          "reason": Json::string("independent human walkthrough"),
        }),
        "before": before.render(),
        "after": after.render(),
        "effects": Json::array([]),
        "observable_adapter_effects": Json::array([]),
        "viewer_error": Json::null(),
      })
    }
    5 => {
      let request = update_user_request("user-1", "active")
      let transition = @core.submit_worker_request(self.state_, request)
      self.apply_transition(
        "approve-then-cancel-before-dispatch",
        command,
        Json::object({
          "kind": Json::string("SubmitRequest"),
          "request": request,
        }),
        transition,
      )
    }
    6 => {
      let action = @core.host_validate()
      let transition = @core.apply_host_action(self.state_, action)
      self.apply_transition(
        "approve-then-cancel-before-dispatch",
        command,
        action.render(),
        transition,
      )
    }
    7 => {
      let call_id = current_call_id(self.state_, "viewer approve")
      let action = @core.operator_approve(call_id)
      let transition = @core.apply_host_action(self.state_, action)
      self.apply_transition(
        "approve-then-cancel-before-dispatch",
        command,
        action.render(),
        transition,
      )
    }
    8 => {
      let call_id = current_call_id(self.state_, "viewer cancel")
      let action = @core.operator_cancel(
        call_id, "human cancelled before dispatch",
      )
      let transition = @core.apply_host_action(self.state_, action)
      self.apply_transition(
        "approve-then-cancel-before-dispatch",
        command,
        action.render(),
        transition,
      )
    }
    9 => {
      let call_id = current_call_id(self.state_, "viewer late dispatch")
      let action = @core.host_dispatch(call_id)
      let transition = @core.apply_host_action(self.state_, action)
      self.apply_transition(
        "approve-then-cancel-before-dispatch",
        command,
        action.render(),
        transition,
      )
    }
    10 => {
      let request = get_user_request("user-2")
      let transition = @core.submit_worker_request(self.state_, request)
      self.apply_transition(
        "approve-then-cancel-before-dispatch",
        command,
        Json::object({
          "kind": Json::string("SubmitRequest"),
          "request": request,
        }),
        transition,
      )
    }
    _ =>
      Json::object({
        "viewer": Json::string("agent-runtime-p1/tool-broker"),
        "command": Json::string(command),
        "state": self.state_.render(),
        "viewer_error": Json::null(),
      })
  }
}
