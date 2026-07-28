///|
/// PROTOTYPE fixture derived from P0's generator contract; deliberately deterministic.
const AGENT_SOURCE =
  #|let __agent = null;
  #|let __state = "idle";
  #|
  #|function* agent_program(input) {
  #|  const read = yield {
  #|    tool: "get_user",
  #|    arguments: { user_id: input.user_id }
  #|  };
  #|  if (read.tag === "error") {
  #|    return { status: "error", error: read.error };
  #|  }
  #|  if (read.value.status === "active") {
  #|    return {
  #|      status: "ok",
  #|      output: {
  #|        user_id: read.value.user_id,
  #|        status: "active",
  #|        updated: false
  #|      }
  #|    };
  #|  }
  #|  const write = yield {
  #|    tool: "update_user_status",
  #|    arguments: {
  #|      user_id: read.value.user_id,
  #|      status: "active"
  #|    }
  #|  };
  #|  if (write.tag === "error") {
  #|    return { status: "error", error: write.error };
  #|  }
  #|  return {
  #|    status: "ok",
  #|    output: {
  #|      user_id: write.value.user_id,
  #|      status: write.value.status,
  #|      updated: true
  #|    }
  #|  };
  #|}
  #|
  #|function encode(step) {
  #|  if (step.done) {
  #|    __agent = null;
  #|    __state = "completed";
  #|    return { kind: "completion", completion: step.value };
  #|  }
  #|  __state = "waiting";
  #|  return { kind: "tool_request", request: step.value };
  #|}
  #|
  #|function start_agent_session(input) {
  #|  if (__state !== "idle") {
  #|    return { kind: "rejected", error: { code: "already_started" } };
  #|  }
  #|  __agent = agent_program(input);
  #|  __state = "running";
  #|  return encode(__agent.next());
  #|}
  #|
  #|function resume_agent_session(result) {
  #|  if (__state !== "waiting") {
  #|    return { kind: "rejected", error: { code: "not_waiting" } };
  #|  }
  #|  __state = "running";
  #|  return encode(__agent.next(result));
  #|}

///|
/// Host-owned build identity; js_engine exposes no runtime-version getter.
const RUNTIME_FINGERPRINT = "js_engine@0.7.0;event_replay_schema=v1;base=c249fbab15db305f345391bc72f1c4431138c207"

///|
const HOST_CONFIG = "catalog=get_user:update_user_status;capabilities=user.read,user.write;call_limit=4;request_byte_limit=4096"

///|
const SESSION_ID = "p3-required-crash"

///|
fn sha256_hex(text : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(text)))
}

///|
fn source_hash() -> String {
  sha256_hex(AGENT_SOURCE)
}

///|
fn host_config_hash() -> String {
  sha256_hex(HOST_CONFIG)
}

///|
fn required_input() -> Json {
  Json::object({ "user_id": Json::string("user-1") })
}

///|
fn active_input() -> Json {
  Json::object({ "user_id": Json::string("user-active") })
}

///|
fn get_user_request(user_id : String) -> Json {
  Json::object({
    "tool": Json::string("get_user"),
    "arguments": Json::object({ "user_id": Json::string(user_id) }),
  })
}

///|
fn update_user_request(user_id : String) -> Json {
  Json::object({
    "tool": Json::string("update_user_status"),
    "arguments": Json::object({
      "user_id": Json::string(user_id),
      "status": Json::string("active"),
    }),
  })
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
fn expected_completion(user_id : String, updated : Bool) -> Json {
  Json::object({
    "status": Json::string("ok"),
    "output": Json::object({
      "user_id": Json::string(user_id),
      "status": Json::string("active"),
      "updated": Json::boolean(updated),
    }),
  })
}
