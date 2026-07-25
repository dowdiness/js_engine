///|
/// Whether a persistent Engine remains supported for later operations.
pub(all) enum EngineIntegrity {
  Reusable
  Discard
  Unknown
  NotApplicable
}

///|
/// Whether observable work from the failed operation may remain committed.
pub(all) enum RetainedEffects {
  None
  MayRemain
  Unknown
}

///|
/// Whether either Engine job queue contains pending work at the failure boundary.
pub(all) enum PendingJobs {
  None
  Present
  Unknown
}

///|
/// A position within a source identified by an Engine diagnostic.
pub struct SourcePosition {
  line_ : Int
  column_ : Int
  offset_ : Int
}

///|
#warnings("-unused_value")
fn SourcePosition::SourcePosition(
  line : Int,
  column : Int,
  offset : Int,
) -> SourcePosition {
  { line_: line, column_: column, offset_: offset }
}

///|
/// A half-open source range. The end position is absent when unavailable.
pub struct SourceLocation {
  start_ : SourcePosition
  end_ : SourcePosition?
}

///|
#warnings("-unused_value")
fn SourceLocation::SourceLocation(
  start : SourcePosition,
  end : SourcePosition?,
) -> SourceLocation {
  { start_: start, end_: end }
}

///|
/// Portable, operation-aware details for a failed stable-facade operation.
pub struct EngineDiagnostic {
  failure_kind_code_ : String
  message_ : String
  operation_code_ : String
  phase_code_ : String
  source_identity_ : String?
  source_location_ : SourceLocation?
  engine_integrity_ : EngineIntegrity
  retained_effects_ : RetainedEffects
  pending_jobs_ : PendingJobs
}

///|
fn EngineDiagnostic::EngineDiagnostic(
  failure_kind_code~ : String,
  message~ : String,
  operation_code~ : String,
  phase_code~ : String,
  source_identity~ : String?,
  engine_integrity~ : EngineIntegrity,
  retained_effects~ : RetainedEffects,
  pending_jobs~ : PendingJobs,
) -> EngineDiagnostic {
  {
    failure_kind_code_: failure_kind_code,
    message_: message,
    operation_code_: operation_code,
    phase_code_: phase_code,
    source_identity_: source_identity,
    source_location_: None,
    engine_integrity_: engine_integrity,
    retained_effects_: retained_effects,
    pending_jobs_: pending_jobs,
  }
}

///|
pub fn EngineDiagnostic::failure_kind_code(self : EngineDiagnostic) -> String {
  self.failure_kind_code_
}

///|
pub fn EngineDiagnostic::message(self : EngineDiagnostic) -> String {
  self.message_
}

///|
pub fn EngineDiagnostic::operation_code(self : EngineDiagnostic) -> String {
  self.operation_code_
}

///|
pub fn EngineDiagnostic::phase_code(self : EngineDiagnostic) -> String {
  self.phase_code_
}

///|
pub fn EngineDiagnostic::source_identity(self : EngineDiagnostic) -> String? {
  self.source_identity_
}

///|
pub fn EngineDiagnostic::source_location(
  self : EngineDiagnostic,
) -> SourceLocation? {
  self.source_location_
}

///|
pub fn EngineDiagnostic::engine_integrity(
  self : EngineDiagnostic,
) -> EngineIntegrity {
  self.engine_integrity_
}

///|
pub fn EngineDiagnostic::retained_effects(
  self : EngineDiagnostic,
) -> RetainedEffects {
  self.retained_effects_
}

///|
pub fn EngineDiagnostic::pending_jobs(self : EngineDiagnostic) -> PendingJobs {
  self.pending_jobs_
}

///|
pub fn SourceLocation::start(self : SourceLocation) -> SourcePosition {
  self.start_
}

///|
pub fn SourceLocation::end(self : SourceLocation) -> SourcePosition? {
  self.end_
}

///|
pub fn SourcePosition::line(self : SourcePosition) -> Int {
  self.line_
}

///|
pub fn SourcePosition::column(self : SourcePosition) -> Int {
  self.column_
}

///|
pub fn SourcePosition::offset(self : SourcePosition) -> Int {
  self.offset_
}

///|
fn Engine::pending_jobs_snapshot(self : Engine) -> PendingJobs {
  if self.has_pending_microtasks() || self.has_pending_timers() {
    PendingJobs::Present
  } else {
    PendingJobs::None
  }
}

///|
fn Engine::eval_failure(
  self : Engine,
  kind : String,
  message : String,
  phase : String,
  source_id : String?,
  effects : RetainedEffects,
) -> EngineDiagnostic {
  EngineDiagnostic(
    failure_kind_code=kind,
    message~,
    operation_code="eval",
    phase_code=phase,
    source_identity=source_id,
    engine_integrity=EngineIntegrity::Reusable,
    retained_effects=effects,
    pending_jobs=self.pending_jobs_snapshot(),
  )
}

///|
fn Engine::eval_runtime_failure(
  self : Engine,
  err : Error,
  source_id : String?,
) -> EngineDiagnostic {
  match @errors.name_message_if_js_error(err) {
    Some(("InternalError", message)) =>
      EngineDiagnostic(
        failure_kind_code="internal-error",
        message~,
        operation_code="eval",
        phase_code="execute",
        source_identity=source_id,
        engine_integrity=EngineIntegrity::Discard,
        retained_effects=RetainedEffects::Unknown,
        pending_jobs=PendingJobs::Unknown,
      )
    Some((name, message)) =>
      self.eval_failure(
        "javascript-exception",
        name + ": " + message,
        "execute",
        source_id,
        RetainedEffects::MayRemain,
      )
    None =>
      EngineDiagnostic(
        failure_kind_code="internal-error",
        message=err.to_string(),
        operation_code="eval",
        phase_code="execute",
        source_identity=source_id,
        engine_integrity=EngineIntegrity::Discard,
        retained_effects=RetainedEffects::Unknown,
        pending_jobs=PendingJobs::Unknown,
      )
  }
}

///|
/// Evaluate source while returning operation-aware failure details atomically.
pub fn Engine::eval_diagnostic(
  self : Engine,
  source : String,
  source_id? : String,
) -> Result[Unit, EngineDiagnostic] {
  let program = @parser.parse(source) catch {
    err =>
      return Err(
        self.eval_failure(
          "parse-error",
          err.to_string(),
          "parse",
          source_id,
          RetainedEffects::None,
        ),
      )
  }
  ignore(
    @runtime.with_source_identity(self.interp.realm_state, source_id, fn() raise {
      self.interp.run(program.stmts)
    }),
  ) catch {
    @runtime.JsException(value) =>
      return Err(
        self.eval_failure(
          "javascript-exception",
          value.to_string(),
          "execute",
          source_id,
          RetainedEffects::MayRemain,
        ),
      )
    err => return Err(self.eval_runtime_failure(err, source_id))
  }
  Ok(())
}

///|
fn make_engine_diagnostic(
  failure_kind_code : String,
  message : String,
  operation_code : String,
  phase_code : String,
  source_identity : String?,
  engine_integrity : EngineIntegrity,
  retained_effects : RetainedEffects,
  pending_jobs : PendingJobs,
) -> EngineDiagnostic {
  EngineDiagnostic(
    failure_kind_code~,
    message~,
    operation_code~,
    phase_code~,
    source_identity~,
    engine_integrity~,
    retained_effects~,
    pending_jobs~,
  )
}

///|
fn runtime_engine_diagnostic(
  err : Error,
  operation : String,
  phase : String,
  source_identity : String?,
  javascript_integrity : EngineIntegrity,
  javascript_effects : RetainedEffects,
  javascript_jobs : PendingJobs,
  internal_integrity : EngineIntegrity,
) -> EngineDiagnostic {
  match err {
    @runtime.JsException(value) =>
      make_engine_diagnostic(
        "javascript-exception",
        value.to_string(),
        operation,
        phase,
        source_identity,
        javascript_integrity,
        javascript_effects,
        javascript_jobs,
      )
    other =>
      match @errors.name_message_if_js_error(other) {
        Some(("InternalError", message)) =>
          make_engine_diagnostic(
            "internal-error",
            message,
            operation,
            phase,
            source_identity,
            internal_integrity,
            RetainedEffects::Unknown,
            PendingJobs::Unknown,
          )
        Some((name, message)) =>
          make_engine_diagnostic(
            "javascript-exception",
            name + ": " + message,
            operation,
            phase,
            source_identity,
            javascript_integrity,
            javascript_effects,
            javascript_jobs,
          )
        None =>
          make_engine_diagnostic(
            "internal-error",
            other.to_string(),
            operation,
            phase,
            source_identity,
            internal_integrity,
            RetainedEffects::Unknown,
            PendingJobs::Unknown,
          )
      }
  }
}

///|
/// Resolve a global export without translating runtime errors first, so the
/// detailed observer can pair the original failure with its deepest source.
fn Engine::get_global_export_for_diagnostic(
  self : Engine,
  name : String,
) -> @runtime.Value raise Error {
  if self.interp.global.has(name) {
    return self.interp.global.get(name)
  }
  let own_property = self.interp.get_own_property(
    self.interp.global_this,
    @runtime.String_(name),
  )
  guard own_property is Some(_) else { raise MissingGlobal(name) }
  self.interp.get_property(self.interp.global_this, name, @token.Loc::default())
}

///|
fn Engine::call_json_lookup_diagnostic(
  self : Engine,
  name : String,
) -> Result[@runtime.Value, EngineDiagnostic] {
  let lookup_result = @runtime.observe_source_failure(self.interp.realm_state, fn() raise {
    self.get_global_export_for_diagnostic(name)
  })
  match lookup_result {
    Ok(callee) => Ok(callee)
    Err(failure) =>
      match failure.cause() {
        MissingGlobal(message) =>
          Err(
            make_engine_diagnostic(
              "missing-global",
              message,
              "call-json",
              "lookup",
              None,
              EngineIntegrity::Reusable,
              RetainedEffects::None,
              PendingJobs::Unknown,
            ),
          )
        other =>
          Err(
            runtime_engine_diagnostic(
              other,
              "call-json",
              "lookup",
              failure.source_identity(),
              EngineIntegrity::Reusable,
              RetainedEffects::MayRemain,
              self.pending_jobs_snapshot(),
              EngineIntegrity::Discard,
            ),
          )
      }
  }
}

///|
/// Call a JSON-boundary function while returning operation-aware failure details.
pub fn Engine::call_json_diagnostic(
  self : Engine,
  name : String,
  args : Array[Json],
) -> Result[Json, EngineDiagnostic] {
  let callee = match self.call_json_lookup_diagnostic(name) {
    Ok(value) => value
    Err(diagnostic) => return Err(diagnostic)
  }
  guard @runtime.is_callable(callee) else {
    return Err(
      make_engine_diagnostic(
        "not-callable",
        name,
        "call-json",
        "lookup",
        None,
        EngineIntegrity::Reusable,
        RetainedEffects::MayRemain,
        PendingJobs::Unknown,
      ),
    )
  }
  let runtime_args : Array[@runtime.Value] = []
  for arg in args {
    let converted = @runtime.json_to_realm_value(self.interp.realm_state, arg) catch {
      @runtime.JsonBridgeFailure(message) =>
        return Err(
          make_engine_diagnostic(
            "json-conversion-error",
            message,
            "call-json",
            "argument-conversion",
            None,
            EngineIntegrity::Reusable,
            RetainedEffects::MayRemain,
            self.pending_jobs_snapshot(),
          ),
        )
    }
    runtime_args.push(converted)
  }
  let call_result = @runtime.observe_source_failure(self.interp.realm_state, fn() raise {
    self.interp.call_value(
      callee,
      @runtime.Undefined,
      runtime_args,
      @token.Loc::default(),
    )
  })
  let result = match call_result {
    Ok(value) => value
    Err(failure) =>
      return Err(
        runtime_engine_diagnostic(
          failure.cause(),
          "call-json",
          "execute",
          failure.source_identity(),
          EngineIntegrity::Reusable,
          RetainedEffects::MayRemain,
          self.pending_jobs_snapshot(),
          EngineIntegrity::Discard,
        ),
      )
  }
  let json = @runtime.realm_value_to_json(self.interp.realm_state, result) catch {
    @runtime.JsonBridgeFailure(message) =>
      return Err(
        make_engine_diagnostic(
          "json-conversion-error",
          message,
          "call-json",
          "result-conversion",
          None,
          EngineIntegrity::Reusable,
          RetainedEffects::MayRemain,
          self.pending_jobs_snapshot(),
        ),
      )
  }
  Ok(json)
}

///|
/// Run a microtask checkpoint while returning operation-aware failure details.
pub fn Engine::run_microtask_checkpoint_diagnostic(
  self : Engine,
) -> Result[Bool, EngineDiagnostic] {
  let observed = self.interp.run_microtasks_observed() catch {
    err =>
      return Err(
        runtime_engine_diagnostic(
          err,
          "microtask-checkpoint",
          "microtask-dispatch",
          None,
          EngineIntegrity::Discard,
          RetainedEffects::MayRemain,
          self.pending_jobs_snapshot(),
          EngineIntegrity::Discard,
        ),
      )
  }
  match observed {
    Ok(_) => ()
    Err(failure) =>
      return Err(
        runtime_engine_diagnostic(
          failure.cause(),
          "microtask-checkpoint",
          "microtask-dispatch",
          failure.source_identity(),
          EngineIntegrity::Discard,
          RetainedEffects::MayRemain,
          self.pending_jobs_snapshot(),
          EngineIntegrity::Discard,
        ),
      )
  }
  Ok(self.has_pending_microtasks())
}

///|
fn timer_failure_phase_code(phase : @runtime.TimerRunFailurePhase) -> String {
  match phase {
    @runtime.TimerRunFailurePhase::TimerCallback => "timer-callback"
    @runtime.TimerRunFailurePhase::IntervalCallback => "interval-callback"
    @runtime.TimerRunFailurePhase::MicrotaskCheckpoint =>
      "timer-microtask-checkpoint"
  }
}

///|
fn timer_dispatch_diagnostic(err : Error) -> EngineDiagnostic {
  runtime_engine_diagnostic(
    err,
    "timer-checkpoint",
    "timer-dispatch",
    None,
    EngineIntegrity::Discard,
    RetainedEffects::Unknown,
    PendingJobs::Unknown,
    EngineIntegrity::Discard,
  )
}

///|
/// Run a timer checkpoint while returning operation-aware failure details.
pub fn Engine::run_timer_checkpoint_diagnostic(
  self : Engine,
) -> Result[Unit, EngineDiagnostic] {
  let observed = self.interp.run_timers_observed() catch {
    err => return Err(timer_dispatch_diagnostic(err))
  }
  match observed {
    Ok(_) => Ok(())
    Err(failure) => {
      let phase = timer_failure_phase_code(failure.phase())
      Err(
        runtime_engine_diagnostic(
          failure.cause(),
          "timer-checkpoint",
          phase,
          failure.source_identity(),
          EngineIntegrity::Discard,
          RetainedEffects::MayRemain,
          self.pending_jobs_snapshot(),
          EngineIntegrity::Discard,
        ),
      )
    }
  }
}

///|
fn run_operation_diagnostic(
  err : Error,
  phase : String,
  source_identity : String?,
  effects : RetainedEffects,
) -> EngineDiagnostic {
  runtime_engine_diagnostic(
    err,
    "run",
    phase,
    source_identity,
    EngineIntegrity::NotApplicable,
    effects,
    PendingJobs::Unknown,
    EngineIntegrity::NotApplicable,
  )
}

///|
/// Run a one-shot script while returning operation-aware failure details.
pub fn run_diagnostic(
  source : String,
  source_id? : String,
  annex_b? : Bool = false,
) -> Result[(Array[String], String), EngineDiagnostic] {
  let interp = @interpreter.new_interpreter(annex_b~)
  let program = @parser.parse(source) catch {
    err =>
      return Err(
        make_engine_diagnostic(
          "parse-error",
          err.to_string(),
          "run",
          "parse",
          source_id,
          EngineIntegrity::NotApplicable,
          RetainedEffects::None,
          PendingJobs::Unknown,
        ),
      )
  }
  let result = @runtime.with_source_identity(interp.realm_state, source_id, fn() raise {
    interp.run(program.stmts)
  }) catch {
    err =>
      return Err(
        run_operation_diagnostic(
          err,
          "execute",
          source_id,
          RetainedEffects::MayRemain,
        ),
      )
  }
  let microtask_result = interp.run_microtasks_observed() catch {
    err =>
      return Err(
        run_operation_diagnostic(
          err,
          "microtask-dispatch",
          None,
          RetainedEffects::Unknown,
        ),
      )
  }
  match microtask_result {
    Ok(_) => ()
    Err(failure) =>
      return Err(
        run_operation_diagnostic(
          failure.cause(),
          "microtask-dispatch",
          failure.source_identity(),
          RetainedEffects::Unknown,
        ),
      )
  }
  let timer_result = interp.run_timers_observed() catch {
    err =>
      return Err(
        run_operation_diagnostic(
          err,
          "timer-dispatch",
          None,
          RetainedEffects::Unknown,
        ),
      )
  }
  match timer_result {
    Ok(_) => ()
    Err(failure) => {
      let phase = timer_failure_phase_code(failure.phase())
      return Err(
        run_operation_diagnostic(
          failure.cause(),
          phase,
          failure.source_identity(),
          RetainedEffects::Unknown,
        ),
      )
    }
  }
  Ok((interp.host.output, result.to_string()))
}
