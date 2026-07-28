///|
pub struct InactiveUserViewer {
  priv session_ : PrototypeSession
  priv mut step_ : Int
}

///|
pub fn InactiveUserViewer::InactiveUserViewer() -> InactiveUserViewer {
  let session = PrototypeSession(1) catch {
    _ => abort("PROTOTYPE viewer could not initialize Engine")
  }
  { session_: session, step_: 0 }
}

///|
pub fn InactiveUserViewer::state(self : InactiveUserViewer) -> Json {
  self.session_.state_.render()
}

///|
pub fn InactiveUserViewer::prompt(self : InactiveUserViewer) -> String {
  match self.step_ {
    0 => "start"
    1 => "read-inactive"
    2 => "write-ok"
    _ => "resume-again"
  }
}

///|
fn viewer_result(
  command : String,
  call : Json,
  error : Json,
  state : @protocol.SessionState,
) -> Json {
  Json::object({
    "viewer": Json::string("agent-runtime-p0/inactive-user"),
    "command": Json::string(command),
    "facade_call": call,
    "viewer_error": error,
    "state": state.render(),
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
pub fn InactiveUserViewer::apply(
  self : InactiveUserViewer,
  command : String,
) -> Json {
  let expected = self.prompt()
  guard command == expected else {
    return viewer_result(
      command,
      Json::null(),
      viewer_error(command, expected),
      self.session_.state_,
    )
  }
  let (args, reply, name) = match self.step_ {
    0 => {
      let input = user_input("user-inactive")
      let reply = self.session_.start(input) catch {
        _ => abort("PROTOTYPE viewer start facade call failed")
      }
      expect_reply(reply, get_user_reply("user-inactive"), "viewer:start")
      ([input], reply, "start_agent_session")
    }
    1 => {
      let result = get_user_result("user-inactive", "inactive")
      let reply = self.session_.supply_tool_result(result) catch {
        _ => abort("PROTOTYPE viewer read facade call failed")
      }
      expect_reply(reply, update_user_reply("user-inactive"), "viewer:read")
      ([result], reply, "resume_agent_session")
    }
    2 => {
      let result = update_user_result("user-inactive")
      let reply = self.session_.supply_tool_result(result) catch {
        _ => abort("PROTOTYPE viewer write facade call failed")
      }
      expect_reply(
        reply,
        successful_completion("user-inactive", true),
        "viewer:write",
      )
      ([result], reply, "resume_agent_session")
    }
    _ => {
      let result = update_user_result("user-inactive")
      let reply = self.session_.supply_tool_result(result) catch {
        _ => abort("PROTOTYPE viewer completed facade call failed")
      }
      expect_reply(
        reply,
        rejected_reply("resume_after_completion", "session is already complete"),
        "viewer:resume-again",
      )
      ([result], reply, "resume_agent_session")
    }
  }
  self.step_ += 1
  viewer_result(
    command,
    facade_call(name, args, reply),
    Json::null(),
    self.session_.state_,
  )
}
