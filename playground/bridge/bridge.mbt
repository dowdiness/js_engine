///|
const PROTOCOL_VERSION = 1

///|
#export_name("playground_run")
pub fn playground_run(source : String, source_id : String) -> String {
  match @js_engine.run_diagnostic(source, source_id~) {
    Ok((output, result)) => completed_response(output, result).stringify()
    Err(diagnostic) => failed_response(diagnostic).stringify()
  }
}

///|
fn completed_response(output : Array[String], result : String) -> Json {
  Json::object({
    "protocolVersion": Json::number(
      PROTOCOL_VERSION.to_double(),
      repr=PROTOCOL_VERSION.to_string(),
    ),
    "kind": Json::string("completed"),
    "output": Json::array(output.map(value => Json::string(value))),
    "result": Json::string(result),
  })
}

///|
fn failed_response(diagnostic : @js_engine.EngineDiagnostic) -> Json {
  Json::object({
    "protocolVersion": Json::number(
      PROTOCOL_VERSION.to_double(),
      repr=PROTOCOL_VERSION.to_string(),
    ),
    "kind": Json::string("failed"),
    "output": Json::array([]),
    "partialOutputAvailable": Json::boolean(false),
    "diagnostic": diagnostic_json(diagnostic),
  })
}

///|
fn diagnostic_json(diagnostic : @js_engine.EngineDiagnostic) -> Json {
  Json::object({
    "failureKind": Json::string(diagnostic.failure_kind_code()),
    "message": Json::string(diagnostic.message()),
    "operation": Json::string(diagnostic.operation_code()),
    "phase": Json::string(diagnostic.phase_code()),
    "sourceId": optional_string_json(diagnostic.source_identity()),
    "location": optional_location_json(diagnostic.source_location()),
    "engineIntegrity": Json::string(
      engine_integrity_code(diagnostic.engine_integrity()),
    ),
    "retainedEffects": Json::string(
      retained_effects_code(diagnostic.retained_effects()),
    ),
    "pendingJobs": Json::string(pending_jobs_code(diagnostic.pending_jobs())),
  })
}

///|
fn optional_string_json(value : String?) -> Json {
  match value {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

///|
fn optional_location_json(value : @js_engine.SourceLocation?) -> Json {
  match value {
    Some(location) => {
      let end = match location.end() {
        Some(position) => position_json(position)
        None => Json::null()
      }
      Json::object({ "start": position_json(location.start()), "end": end })
    }
    None => Json::null()
  }
}

///|
fn position_json(position : @js_engine.SourcePosition) -> Json {
  Json::object({
    "line": Json::number(
      position.line().to_double(),
      repr=position.line().to_string(),
    ),
    "column": Json::number(
      position.column().to_double(),
      repr=position.column().to_string(),
    ),
    "offset": Json::number(
      position.offset().to_double(),
      repr=position.offset().to_string(),
    ),
  })
}

///|
fn engine_integrity_code(value : @js_engine.EngineIntegrity) -> String {
  match value {
    @js_engine.EngineIntegrity::Reusable => "reusable"
    @js_engine.EngineIntegrity::Discard => "discard"
    @js_engine.EngineIntegrity::Unknown => "unknown"
    @js_engine.EngineIntegrity::NotApplicable => "not-applicable"
  }
}

///|
fn retained_effects_code(value : @js_engine.RetainedEffects) -> String {
  match value {
    @js_engine.RetainedEffects::None => "none"
    @js_engine.RetainedEffects::MayRemain => "may-remain"
    @js_engine.RetainedEffects::Unknown => "unknown"
  }
}

///|
fn pending_jobs_code(value : @js_engine.PendingJobs) -> String {
  match value {
    @js_engine.PendingJobs::None => "none"
    @js_engine.PendingJobs::Present => "present"
    @js_engine.PendingJobs::Unknown => "unknown"
  }
}
