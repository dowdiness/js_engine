///|
const RULE_SOURCE =
  #|let evaluationCount = 0;
  #|function allow(request) {
  #|  evaluationCount += 1;
  #|  const allowed = request.role === "admin" || request.action === "read";
  #|  return { allowed, evaluationCount };
  #|}

///|
fn request(role : String, action : String) -> Json {
  Json::object({ "role": Json::string(role), "action": Json::string(action) })
}

///|
fn load_rule_engine() -> @js_engine.Engine raise @js_engine.EngineError {
  let engine = @js_engine.Engine()
  engine.eval(RULE_SOURCE)
  engine
}

///|
test "stable facade supports a persistent portable rule engine" {
  let engine = load_rule_engine()
  let isolated = load_rule_engine()
  json_inspect(
    [
      engine.call_json("allow", [request("member", "read")]),
      engine.call_json("allow", [request("member", "delete")]),
      engine.call_json("allow", [request("admin", "delete")]),
      isolated.call_json("allow", [request("member", "read")]),
    ],
    content=[
      { "allowed": true, "evaluationCount": 1 },
      { "allowed": false, "evaluationCount": 2 },
      { "allowed": true, "evaluationCount": 3 },
      { "allowed": true, "evaluationCount": 1 },
    ],
  )
}
