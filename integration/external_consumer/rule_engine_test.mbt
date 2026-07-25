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
fn diagnostic_integrity_code(value : @js_engine.EngineIntegrity) -> String {
  match value {
    @js_engine.EngineIntegrity::Reusable => "reusable"
    @js_engine.EngineIntegrity::Discard => "discard"
    @js_engine.EngineIntegrity::Unknown => "unknown"
    @js_engine.EngineIntegrity::NotApplicable => "not-applicable"
  }
}

///|
fn diagnostic_effects_code(value : @js_engine.RetainedEffects) -> String {
  match value {
    @js_engine.RetainedEffects::None => "none"
    @js_engine.RetainedEffects::MayRemain => "may-remain"
    @js_engine.RetainedEffects::Unknown => "unknown"
  }
}

///|
fn diagnostic_jobs_code(value : @js_engine.PendingJobs) -> String {
  match value {
    @js_engine.PendingJobs::None => "none"
    @js_engine.PendingJobs::Present => "present"
    @js_engine.PendingJobs::Unknown => "unknown"
  }
}

///|
fn portable_code_or_fallback(code : String) -> String {
  match code {
    "parse-error" | "eval" | "parse" => code
    _ => "other"
  }
}

///|
fn source_position_fields(position : @js_engine.SourcePosition) -> (Int, Int, Int) {
  (position.line(), position.column(), position.offset())
}

///|
fn source_location_fields(
  location : @js_engine.SourceLocation,
) -> ((Int, Int, Int), (Int, Int, Int)?) {
  (
    source_position_fields(location.start()),
    location.end().map(source_position_fields),
  )
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

///|
test "external consumer can inspect opaque structured diagnostics" {
  let engine = @js_engine.Engine()
  match engine.eval_diagnostic("let =", source_id="consumer-input.js") {
    Ok(_) => fail("expected parse failure")
    Err(diagnostic) => {
      inspect(portable_code_or_fallback(diagnostic.failure_kind_code()), content="parse-error")
      inspect(portable_code_or_fallback(diagnostic.operation_code()), content="eval")
      inspect(portable_code_or_fallback(diagnostic.phase_code()), content="parse")
      inspect(portable_code_or_fallback("future-code"), content="other")
      assert_true(
        diagnostic.source_identity() == Some("consumer-input.js"),
      )
      match diagnostic.source_location() {
        None => ()
        Some(location) => ignore(source_location_fields(location))
      }
      inspect(diagnostic_integrity_code(diagnostic.engine_integrity()), content="reusable")
      inspect(diagnostic_effects_code(diagnostic.retained_effects()), content="none")
      inspect(diagnostic_jobs_code(diagnostic.pending_jobs()), content="none")
      assert_true(diagnostic.message().length() > 0)
    }
  }
}
