///|
const AGENT_SOURCE =
  #|let __agent = null;
  #|let __agent_state = "idle";
  #|let __pending_request = null;
  #|
  #|function is_object(value) {
  #|  return value !== null && typeof value === "object" && !Array.isArray(value);
  #|}
  #|
  #|function rejected(code, message) {
  #|  return {
  #|    kind: "rejected",
  #|    error: { code: code, message: message }
  #|  };
  #|}
  #|
  #|function tool_request(tool, args) {
  #|  return { tool: tool, arguments: args };
  #|}
  #|
  #|function tool_failure(tool, result) {
  #|  return {
  #|    status: "error",
  #|    error: {
  #|      code: result.error.code,
  #|      tool: tool,
  #|      message: result.error.message
  #|    }
  #|  };
  #|}
  #|
  #|function* agent_program(input) {
  #|  const read = yield tool_request("get_user", { user_id: input.user_id });
  #|  if (read.tag === "error") {
  #|    return tool_failure("get_user", read);
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
  #|  const write = yield tool_request("update_user_status", {
  #|    user_id: read.value.user_id,
  #|    status: "active"
  #|  });
  #|  if (write.tag === "error") {
  #|    return tool_failure("update_user_status", write);
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
  #|function valid_error(result) {
  #|  return is_object(result.error) &&
  #|    typeof result.error.code === "string" &&
  #|    typeof result.error.message === "string";
  #|}
  #|
  #|function valid_success(result) {
  #|  if (!is_object(result.value) || __pending_request === null) {
  #|    return false;
  #|  }
  #|  const expected_user_id = __pending_request.arguments.user_id;
  #|  if (result.value.user_id !== expected_user_id) {
  #|    return false;
  #|  }
  #|  if (__pending_request.tool === "get_user") {
  #|    return result.value.status === "active" ||
  #|      result.value.status === "inactive";
  #|  }
  #|  if (__pending_request.tool === "update_user_status") {
  #|    return result.value.status === "active";
  #|  }
  #|  return false;
  #|}
  #|
  #|function valid_tool_result(result) {
  #|  if (!is_object(result) || typeof result.tag !== "string") {
  #|    return false;
  #|  }
  #|  if (result.tag === "error") {
  #|    return valid_error(result);
  #|  }
  #|  if (result.tag === "ok") {
  #|    return valid_success(result);
  #|  }
  #|  return false;
  #|}
  #|
  #|function encode_step(step) {
  #|  if (step.done) {
  #|    __agent = null;
  #|    __pending_request = null;
  #|    __agent_state = "completed";
  #|    return {
  #|      kind: "completion",
  #|      completion: step.value === undefined ? null : step.value
  #|    };
  #|  }
  #|  if (!is_object(step.value) ||
  #|      typeof step.value.tool !== "string" ||
  #|      !is_object(step.value.arguments)) {
  #|    __agent = null;
  #|    __pending_request = null;
  #|    __agent_state = "completed";
  #|    return {
  #|      kind: "completion",
  #|      completion: {
  #|        status: "error",
  #|        error: {
  #|          code: "malformed_tool_request",
  #|          tool: "agent_program",
  #|          message: "generator yielded an invalid request"
  #|        }
  #|      }
  #|    };
  #|  }
  #|  __pending_request = step.value;
  #|  __agent_state = "waiting";
  #|  return { kind: "tool_request", request: step.value };
  #|}
  #|
  #|function start_agent_session(input) {
  #|  if (__agent_state !== "idle") {
  #|    return rejected("already_started", "session has already started");
  #|  }
  #|  if (!is_object(input) || typeof input.user_id !== "string") {
  #|    return rejected("malformed_input", "input must contain user_id");
  #|  }
  #|  try {
  #|    __agent = agent_program(input);
  #|    __agent_state = "running";
  #|    return encode_step(__agent.next());
  #|  } catch (_) {
  #|    __agent = null;
  #|    __pending_request = null;
  #|    __agent_state = "completed";
  #|    return {
  #|      kind: "completion",
  #|      completion: {
  #|        status: "error",
  #|        error: {
  #|          code: "generator_exception",
  #|          tool: "agent_program",
  #|          message: "generator start failed"
  #|        }
  #|      }
  #|    };
  #|  }
  #|}
  #|
  #|function resume_agent_session(result) {
  #|  if (__agent_state === "completed") {
  #|    return rejected("resume_after_completion", "session is already complete");
  #|  }
  #|  if (__agent_state === "idle") {
  #|    return rejected("not_started", "session has not started");
  #|  }
  #|  if (__agent_state !== "waiting") {
  #|    return rejected("not_waiting", "session is not waiting for a tool result");
  #|  }
  #|  if (!valid_tool_result(result)) {
  #|    return rejected(
  #|      "malformed_tool_result",
  #|      "expected tagged ToolResult with a valid value or error"
  #|    );
  #|  }
  #|  try {
  #|    __agent_state = "running";
  #|    return encode_step(__agent.next(result));
  #|  } catch (_) {
  #|    __agent = null;
  #|    __pending_request = null;
  #|    __agent_state = "completed";
  #|    return {
  #|      kind: "completion",
  #|      completion: {
  #|        status: "error",
  #|        error: {
  #|          code: "generator_exception",
  #|          tool: "agent_program",
  #|          message: "generator resume failed"
  #|        }
  #|      }
  #|    };
  #|  }
  #|}
