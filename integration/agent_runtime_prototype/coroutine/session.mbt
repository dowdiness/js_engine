///|
priv struct PrototypeSession {
  mut engine_ : @js_engine.Engine?
  mut state_ : @protocol.SessionState
}

///|
fn PrototypeSession::PrototypeSession(
  engine_epoch : Int,
) -> PrototypeSession raise @js_engine.EngineError {
  let engine = @js_engine.Engine()
  engine.eval(AGENT_SOURCE)
  { engine_: Some(engine), state_: @protocol.SessionState(engine_epoch) }
}

///|
fn PrototypeSession::call(
  self : PrototypeSession,
  name : String,
  args : Array[Json],
) -> Json raise @js_engine.EngineError {
  match self.engine_ {
    Some(engine) => engine.call_json(name, args)
    None => abort("PROTOTYPE invariant: discarded Engine cannot be called")
  }
}

///|
fn PrototypeSession::start(
  self : PrototypeSession,
  input : Json,
) -> Json raise @js_engine.EngineError {
  let reply = self.call("start_agent_session", [input])
  self.state_ = self.state_.record_start(reply)
  reply
}

///|
fn PrototypeSession::supply_tool_result(
  self : PrototypeSession,
  result : Json,
) -> Json raise @js_engine.EngineError {
  let reply = self.call("resume_agent_session", [result])
  self.state_ = self.state_.record_resume(result, reply)
  reply
}

///|
fn PrototypeSession::discard(self : PrototypeSession) -> Unit {
  self.engine_ = None
  self.state_ = self.state_.record_discard("operator_discard")
}

///|
fn PrototypeSession::restart(
  self : PrototypeSession,
) -> Unit raise @js_engine.EngineError {
  let next_epoch = self.state_.engine_epoch() + 1
  let engine = @js_engine.Engine()
  engine.eval(AGENT_SOURCE)
  self.engine_ = Some(engine)
  self.state_ = @protocol.SessionState(next_epoch)
}

///|
fn user_input(user_id : String) -> Json {
  Json::object({ "user_id": Json::string(user_id) })
}

///|
fn get_user_result(user_id : String, status : String) -> Json {
  Json::object({
    "tag": Json::string("ok"),
    "value": Json::object({
      "user_id": Json::string(user_id),
      "status": Json::string(status),
    }),
  })
}

///|
fn update_user_result(user_id : String) -> Json {
  get_user_result(user_id, "active")
}

///|
fn tool_error_result(code : String, message : String) -> Json {
  Json::object({
    "tag": Json::string("error"),
    "error": Json::object({
      "code": Json::string(code),
      "message": Json::string(message),
    }),
  })
}

///|
fn malformed_get_user_result(user_id : String) -> Json {
  Json::object({
    "tag": Json::string("ok"),
    "value": Json::object({ "user_id": Json::string(user_id) }),
  })
}

///|
fn request_reply(tool : String, arguments : Json) -> Json {
  Json::object({
    "kind": Json::string("tool_request"),
    "request": Json::object({
      "tool": Json::string(tool),
      "arguments": arguments,
    }),
  })
}

///|
fn get_user_reply(user_id : String) -> Json {
  request_reply("get_user", Json::object({ "user_id": Json::string(user_id) }))
}

///|
fn update_user_reply(user_id : String) -> Json {
  request_reply(
    "update_user_status",
    Json::object({
      "user_id": Json::string(user_id),
      "status": Json::string("active"),
    }),
  )
}

///|
fn successful_completion(user_id : String, updated : Bool) -> Json {
  Json::object({
    "kind": Json::string("completion"),
    "completion": Json::object({
      "status": Json::string("ok"),
      "output": Json::object({
        "user_id": Json::string(user_id),
        "status": Json::string("active"),
        "updated": Json::boolean(updated),
      }),
    }),
  })
}

///|
fn failed_completion(tool : String, code : String, message : String) -> Json {
  Json::object({
    "kind": Json::string("completion"),
    "completion": Json::object({
      "status": Json::string("error"),
      "error": Json::object({
        "code": Json::string(code),
        "tool": Json::string(tool),
        "message": Json::string(message),
      }),
    }),
  })
}

///|
fn rejected_reply(code : String, message : String) -> Json {
  Json::object({
    "kind": Json::string("rejected"),
    "error": Json::object({
      "code": Json::string(code),
      "message": Json::string(message),
    }),
  })
}

///|
fn expect_reply(actual : Json, expected : Json, label : String) -> Unit {
  guard actual.equal(expected) else {
    abort(
      "PROTOTYPE scenario mismatch at " +
      label +
      ": expected " +
      expected.stringify() +
      ", got " +
      actual.stringify(),
    )
  }
}

///|
fn start_action(input : Json) -> Json {
  Json::object({ "kind": Json::string("start"), "input": input })
}

///|
fn resume_action(result : Json) -> Json {
  Json::object({ "kind": Json::string("resume"), "tool_result": result })
}

///|
fn discard_action() -> Json {
  Json::object({
    "kind": Json::string("discard"),
    "reason": Json::string("operator_discard"),
  })
}

///|
fn restart_action(from_epoch : Int, to_epoch : Int) -> Json {
  Json::object({
    "kind": Json::string("restart"),
    "from_engine_epoch": Json::number(
      from_epoch.to_double(),
      repr=from_epoch.to_string(),
    ),
    "to_engine_epoch": Json::number(
      to_epoch.to_double(),
      repr=to_epoch.to_string(),
    ),
  })
}

///|
fn facade_call(name : String, args : Array[Json], reply : Json) -> Json {
  Json::object({
    "name": Json::string(name),
    "args": Json::array(args),
    "reply": reply,
  })
}

///|
fn append_record(
  lines : Array[String],
  scenario : String,
  sequence : Int,
  action : Json,
  call : Json,
  session : PrototypeSession,
) -> Unit {
  lines.push(
    @protocol.transcript_record(
      scenario,
      sequence,
      action,
      call,
      session.state_,
    ),
  )
}

///|
fn run_inactive_user_success(
  lines : Array[String],
) -> Unit raise @js_engine.EngineError {
  let scenario = "inactive_user_success"
  let user_id = "user-inactive"
  let session = PrototypeSession(1)
  let input = user_input(user_id)
  let start_reply = session.start(input)
  expect_reply(start_reply, get_user_reply(user_id), scenario + ":start")
  append_record(
    lines,
    scenario,
    0,
    start_action(input),
    facade_call("start_agent_session", [input], start_reply),
    session,
  )
  let read = get_user_result(user_id, "inactive")
  let read_reply = session.supply_tool_result(read)
  expect_reply(read_reply, update_user_reply(user_id), scenario + ":read")
  append_record(
    lines,
    scenario,
    1,
    resume_action(read),
    facade_call("resume_agent_session", [read], read_reply),
    session,
  )
  let write = update_user_result(user_id)
  let write_reply = session.supply_tool_result(write)
  expect_reply(
    write_reply,
    successful_completion(user_id, true),
    scenario + ":write",
  )
  append_record(
    lines,
    scenario,
    2,
    resume_action(write),
    facade_call("resume_agent_session", [write], write_reply),
    session,
  )
}

///|
fn run_active_user_success(
  lines : Array[String],
) -> Unit raise @js_engine.EngineError {
  let scenario = "active_user_success"
  let user_id = "user-active"
  let session = PrototypeSession(1)
  let input = user_input(user_id)
  let start_reply = session.start(input)
  expect_reply(start_reply, get_user_reply(user_id), scenario + ":start")
  append_record(
    lines,
    scenario,
    0,
    start_action(input),
    facade_call("start_agent_session", [input], start_reply),
    session,
  )
  let read = get_user_result(user_id, "active")
  let read_reply = session.supply_tool_result(read)
  expect_reply(
    read_reply,
    successful_completion(user_id, false),
    scenario + ":read",
  )
  append_record(
    lines,
    scenario,
    1,
    resume_action(read),
    facade_call("resume_agent_session", [read], read_reply),
    session,
  )
}

///|
fn run_read_failure(lines : Array[String]) -> Unit raise @js_engine.EngineError {
  let scenario = "read_failure"
  let user_id = "user-read-failure"
  let session = PrototypeSession(1)
  let input = user_input(user_id)
  let start_reply = session.start(input)
  expect_reply(start_reply, get_user_reply(user_id), scenario + ":start")
  append_record(
    lines,
    scenario,
    0,
    start_action(input),
    facade_call("start_agent_session", [input], start_reply),
    session,
  )
  let result = tool_error_result(
    "fixture_read_failed", "fixture get_user failure",
  )
  let reply = session.supply_tool_result(result)
  expect_reply(
    reply,
    failed_completion(
      "get_user", "fixture_read_failed", "fixture get_user failure",
    ),
    scenario + ":read",
  )
  append_record(
    lines,
    scenario,
    1,
    resume_action(result),
    facade_call("resume_agent_session", [result], reply),
    session,
  )
}

///|
fn run_write_failure(
  lines : Array[String],
) -> Unit raise @js_engine.EngineError {
  let scenario = "write_failure"
  let user_id = "user-write-failure"
  let session = PrototypeSession(1)
  let input = user_input(user_id)
  let start_reply = session.start(input)
  expect_reply(start_reply, get_user_reply(user_id), scenario + ":start")
  append_record(
    lines,
    scenario,
    0,
    start_action(input),
    facade_call("start_agent_session", [input], start_reply),
    session,
  )
  let read = get_user_result(user_id, "inactive")
  let read_reply = session.supply_tool_result(read)
  expect_reply(read_reply, update_user_reply(user_id), scenario + ":read")
  append_record(
    lines,
    scenario,
    1,
    resume_action(read),
    facade_call("resume_agent_session", [read], read_reply),
    session,
  )
  let result = tool_error_result(
    "fixture_write_failed", "fixture update_user_status failure",
  )
  let reply = session.supply_tool_result(result)
  expect_reply(
    reply,
    failed_completion(
      "update_user_status", "fixture_write_failed", "fixture update_user_status failure",
    ),
    scenario + ":write",
  )
  append_record(
    lines,
    scenario,
    2,
    resume_action(result),
    facade_call("resume_agent_session", [result], reply),
    session,
  )
}

///|
fn run_malformed_tool_result(
  lines : Array[String],
) -> Unit raise @js_engine.EngineError {
  let scenario = "malformed_tool_result"
  let user_id = "user-malformed"
  let session = PrototypeSession(1)
  let input = user_input(user_id)
  let start_reply = session.start(input)
  expect_reply(start_reply, get_user_reply(user_id), scenario + ":start")
  append_record(
    lines,
    scenario,
    0,
    start_action(input),
    facade_call("start_agent_session", [input], start_reply),
    session,
  )
  let malformed = malformed_get_user_result(user_id)
  let malformed_reply = session.supply_tool_result(malformed)
  expect_reply(
    malformed_reply,
    rejected_reply(
      "malformed_tool_result", "expected tagged ToolResult with a valid value or error",
    ),
    scenario + ":malformed",
  )
  append_record(
    lines,
    scenario,
    1,
    resume_action(malformed),
    facade_call("resume_agent_session", [malformed], malformed_reply),
    session,
  )
  let corrected = get_user_result(user_id, "active")
  let corrected_reply = session.supply_tool_result(corrected)
  expect_reply(
    corrected_reply,
    successful_completion(user_id, false),
    scenario + ":corrected",
  )
  append_record(
    lines,
    scenario,
    2,
    resume_action(corrected),
    facade_call("resume_agent_session", [corrected], corrected_reply),
    session,
  )
}

///|
fn run_resume_after_completion(
  lines : Array[String],
) -> Unit raise @js_engine.EngineError {
  let scenario = "resume_after_completion"
  let user_id = "user-completed"
  let session = PrototypeSession(1)
  let input = user_input(user_id)
  let start_reply = session.start(input)
  expect_reply(start_reply, get_user_reply(user_id), scenario + ":start")
  append_record(
    lines,
    scenario,
    0,
    start_action(input),
    facade_call("start_agent_session", [input], start_reply),
    session,
  )
  let first_result = get_user_result(user_id, "active")
  let completion = session.supply_tool_result(first_result)
  expect_reply(
    completion,
    successful_completion(user_id, false),
    scenario + ":complete",
  )
  append_record(
    lines,
    scenario,
    1,
    resume_action(first_result),
    facade_call("resume_agent_session", [first_result], completion),
    session,
  )
  let extra_result = get_user_result(user_id, "active")
  let rejected = session.supply_tool_result(extra_result)
  expect_reply(
    rejected,
    rejected_reply("resume_after_completion", "session is already complete"),
    scenario + ":resume-again",
  )
  append_record(
    lines,
    scenario,
    2,
    resume_action(extra_result),
    facade_call("resume_agent_session", [extra_result], rejected),
    session,
  )
}

///|
fn run_discard_while_waiting(
  lines : Array[String],
) -> Unit raise @js_engine.EngineError {
  let scenario = "discard_while_waiting"
  let user_id = "user-discarded"
  let session = PrototypeSession(1)
  let input = user_input(user_id)
  let start_reply = session.start(input)
  expect_reply(start_reply, get_user_reply(user_id), scenario + ":start")
  append_record(
    lines,
    scenario,
    0,
    start_action(input),
    facade_call("start_agent_session", [input], start_reply),
    session,
  )
  session.discard()
  append_record(lines, scenario, 1, discard_action(), Json::null(), session)
}

///|
fn run_restart_with_fresh_engine(
  lines : Array[String],
) -> Unit raise @js_engine.EngineError {
  let scenario = "restart_with_fresh_engine"
  let user_id = "user-restart"
  let session = PrototypeSession(1)
  let input = user_input(user_id)
  let start_reply = session.start(input)
  expect_reply(start_reply, get_user_reply(user_id), scenario + ":start")
  append_record(
    lines,
    scenario,
    0,
    start_action(input),
    facade_call("start_agent_session", [input], start_reply),
    session,
  )
  session.discard()
  append_record(lines, scenario, 1, discard_action(), Json::null(), session)
  session.restart()
  append_record(lines, scenario, 2, restart_action(1, 2), Json::null(), session)
  let stale_result = get_user_result(user_id, "inactive")
  let stale_reply = session.supply_tool_result(stale_result)
  expect_reply(
    stale_reply,
    rejected_reply("not_started", "session has not started"),
    scenario + ":stale-resume",
  )
  append_record(
    lines,
    scenario,
    3,
    resume_action(stale_result),
    facade_call("resume_agent_session", [stale_result], stale_reply),
    session,
  )
  let fresh_reply = session.start(input)
  expect_reply(fresh_reply, get_user_reply(user_id), scenario + ":fresh-start")
  append_record(
    lines,
    scenario,
    4,
    start_action(input),
    facade_call("start_agent_session", [input], fresh_reply),
    session,
  )
}

///|
fn run_required_scenarios() -> Array[String] raise @js_engine.EngineError {
  let lines : Array[String] = []
  run_inactive_user_success(lines)
  run_active_user_success(lines)
  run_read_failure(lines)
  run_write_failure(lines)
  run_malformed_tool_result(lines)
  run_resume_after_completion(lines)
  run_discard_while_waiting(lines)
  run_restart_with_fresh_engine(lines)
  lines
}

///|
pub fn required_transcript() -> Array[String] {
  run_required_scenarios() catch {
    _ => abort("PROTOTYPE Engine facade call failed")
  }
}
