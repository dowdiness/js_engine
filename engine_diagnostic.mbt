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
fn Engine::inject_json_expected_failure(
  self : Engine,
  kind : String,
  message : String,
  phase : String,
) -> EngineDiagnostic {
  make_engine_diagnostic(
    failure_kind_code=kind,
    message~,
    operation_code="inject-json",
    phase_code=phase,
    source_identity=None,
    engine_integrity=EngineIntegrity::Reusable,
    retained_effects=RetainedEffects::None,
    pending_jobs=self.pending_jobs_snapshot(),
  )
}

///|
fn inject_json_internal_failure(
  err : Error,
  phase : String,
) -> EngineDiagnostic {
  runtime_engine_diagnostic(
    err,
    operation="inject-json",
    phase~,
    source_identity=None,
    javascript_integrity=EngineIntegrity::Discard,
    javascript_effects=RetainedEffects::Unknown,
    javascript_jobs=PendingJobs::Unknown,
    internal_integrity=EngineIntegrity::Discard,
  )
}

///|
/// Copy host-owned JSON into this Engine as an immutable global binding and
/// matching immutable own property of `globalThis`.
pub fn Engine::inject_json(
  self : Engine,
  name : String,
  value : Json,
) -> Result[Unit, EngineDiagnostic] {
  let has_binding = self.interp.global.has(name) catch {
    err => return Err(inject_json_internal_failure(err, "define"))
  }
  if has_binding {
    return Err(
      self.inject_json_expected_failure(
        "injection-conflict",
        "global name already has a binding: " + name,
        "define",
      ),
    )
  }
  let global_data = match self.interp.global_this {
    @runtime.Object(data) => data
    _ =>
      return Err(
        self.inject_json_expected_failure(
          "injection-conflict", "global object cannot accept host-owned data", "define",
        ),
      )
  }
  if global_data.bag.properties.contains(name) ||
    global_data.bag.descriptors.contains(name) {
    return Err(
      self.inject_json_expected_failure(
        "injection-conflict",
        "global name already has an own property: " + name,
        "define",
      ),
    )
  }
  if !global_data.extensible {
    return Err(
      self.inject_json_expected_failure(
        "injection-conflict", "global object is not extensible", "define",
      ),
    )
  }
  let runtime_value = @runtime.json_to_realm_value(
    self.interp.realm_state,
    value,
  ) catch {
    @runtime.JsonBridgeFailure(message) =>
      return Err(
        self.inject_json_expected_failure(
          "json-conversion-error", message, "conversion",
        ),
      )
  }
  self.interp.global.def(name, runtime_value, @runtime.ConstBinding) catch {
    err => return Err(inject_json_internal_failure(err, "define"))
  }
  global_data.bag.properties[name] = runtime_value
  global_data.bag.descriptors[name] = {
    writable: false,
    enumerable: true,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  Ok(())
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
  runtime_engine_diagnostic(
    err,
    operation="eval",
    phase="execute",
    source_identity=source_id,
    javascript_integrity=EngineIntegrity::Reusable,
    javascript_effects=RetainedEffects::MayRemain,
    javascript_jobs=self.pending_jobs_snapshot(),
    internal_integrity=EngineIntegrity::Discard,
  )
}

///|
fn Engine::bounded_eval_guardrail_failure(
  self : Engine,
  kind : String,
  message : String,
  source_id : String?,
) -> EngineDiagnostic {
  make_engine_diagnostic(
    failure_kind_code=kind,
    message~,
    operation_code="eval",
    phase_code="execute",
    source_identity=source_id,
    engine_integrity=EngineIntegrity::Unknown,
    retained_effects=RetainedEffects::MayRemain,
    pending_jobs=self.pending_jobs_snapshot(),
  )
}

///|
fn execution_guardrail_message(kind : String) -> String {
  match kind {
    "interrupted" => "Execution interrupted"
    "execution-limit" => "Execution limit exceeded"
    "stack-depth-limit" => @runtime.stack_depth_limit_message()
    _ => "Execution guardrail rejected the operation"
  }
}

///|
/// Evaluate source under one explicitly supplied, operation-scoped policy.
/// Parsing remains outside the control carrier; all existing unbounded Engine
/// entry points retain their current behavior and signatures.
pub fn Engine::eval_bounded(
  self : Engine,
  source : String,
  policy : @runtime.ExecutionPolicy,
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
  let observed = @runtime.observe_source_failure(self.interp.realm_state, fn() raise {
    ignore(
      @runtime.with_source_identity(self.interp.realm_state, source_id, fn() raise {
        self.interp.run_bounded(program.stmts, policy)
      }),
    )
  })
  match observed {
    Ok(_) => Ok(())
    Err(failure) => {
      let failure_source = match failure.source_identity() {
        Some(identity) => Some(identity)
        None => source_id
      }
      let cause = failure.cause()
      match @runtime.execution_control_failure_code(cause) {
        Some(kind) =>
          Err(
            self.bounded_eval_guardrail_failure(
              kind,
              execution_guardrail_message(kind),
              failure_source,
            ),
          )
        None =>
          match cause {
            @runtime.JsException(value) =>
              if @runtime.is_engine_stack_depth_error(value) {
                Err(
                  self.bounded_eval_guardrail_failure(
                    "stack-depth-limit",
                    @runtime.stack_depth_limit_message(),
                    failure_source,
                  ),
                )
              } else {
                Err(
                  self.eval_failure(
                    "javascript-exception",
                    value.to_string(),
                    "execute",
                    failure_source,
                    RetainedEffects::MayRemain,
                  ),
                )
              }
            err => Err(self.eval_runtime_failure(err, failure_source))
          }
      }
    }
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
  let observed = @runtime.observe_source_failure(self.interp.realm_state, fn() raise {
    ignore(
      @runtime.with_source_identity(self.interp.realm_state, source_id, fn() raise {
        self.interp.run(program.stmts)
      }),
    )
  })
  match observed {
    Ok(_) => ()
    Err(failure) => {
      let failure_source = match failure.source_identity() {
        Some(identity) => Some(identity)
        None => source_id
      }
      match failure.cause() {
        @runtime.JsException(value) =>
          return Err(
            self.eval_failure(
              "javascript-exception",
              value.to_string(),
              "execute",
              failure_source,
              RetainedEffects::MayRemain,
            ),
          )
        err => return Err(self.eval_runtime_failure(err, failure_source))
      }
    }
  }
  Ok(())
}

///|
fn make_engine_diagnostic(
  failure_kind_code~ : String,
  message~ : String,
  operation_code~ : String,
  phase_code~ : String,
  source_identity~ : String?,
  engine_integrity~ : EngineIntegrity,
  retained_effects~ : RetainedEffects,
  pending_jobs~ : PendingJobs,
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
  operation~ : String,
  phase~ : String,
  source_identity~ : String?,
  javascript_integrity~ : EngineIntegrity,
  javascript_effects~ : RetainedEffects,
  javascript_jobs~ : PendingJobs,
  internal_integrity~ : EngineIntegrity,
) -> EngineDiagnostic {
  match err {
    @runtime.JsException(value) =>
      make_engine_diagnostic(
        failure_kind_code="javascript-exception",
        message=value.to_string(),
        operation_code=operation,
        phase_code=phase,
        source_identity~,
        engine_integrity=javascript_integrity,
        retained_effects=javascript_effects,
        pending_jobs=javascript_jobs,
      )
    other =>
      match @errors.name_message_if_js_error(other) {
        Some(("InternalError", message)) =>
          make_engine_diagnostic(
            failure_kind_code="internal-error",
            message~,
            operation_code=operation,
            phase_code=phase,
            source_identity~,
            engine_integrity=internal_integrity,
            retained_effects=RetainedEffects::Unknown,
            pending_jobs=PendingJobs::Unknown,
          )
        Some((name, message)) =>
          make_engine_diagnostic(
            failure_kind_code="javascript-exception",
            message=name + ": " + message,
            operation_code=operation,
            phase_code=phase,
            source_identity~,
            engine_integrity=javascript_integrity,
            retained_effects=javascript_effects,
            pending_jobs=javascript_jobs,
          )
        None =>
          make_engine_diagnostic(
            failure_kind_code="internal-error",
            message=other.to_string(),
            operation_code=operation,
            phase_code=phase,
            source_identity~,
            engine_integrity=internal_integrity,
            retained_effects=RetainedEffects::Unknown,
            pending_jobs=PendingJobs::Unknown,
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
              failure_kind_code="missing-global",
              message~,
              operation_code="call-json",
              phase_code="lookup",
              source_identity=None,
              engine_integrity=EngineIntegrity::Reusable,
              retained_effects=RetainedEffects::None,
              pending_jobs=self.pending_jobs_snapshot(),
            ),
          )
        other =>
          Err(
            runtime_engine_diagnostic(
              other,
              operation="call-json",
              phase="lookup",
              source_identity=failure.source_identity(),
              javascript_integrity=EngineIntegrity::Reusable,
              javascript_effects=RetainedEffects::MayRemain,
              javascript_jobs=self.pending_jobs_snapshot(),
              internal_integrity=EngineIntegrity::Discard,
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
        failure_kind_code="not-callable",
        message=name,
        operation_code="call-json",
        phase_code="lookup",
        source_identity=None,
        engine_integrity=EngineIntegrity::Reusable,
        retained_effects=RetainedEffects::MayRemain,
        pending_jobs=self.pending_jobs_snapshot(),
      ),
    )
  }
  let runtime_args : Array[@runtime.Value] = []
  for arg in args {
    let converted = @runtime.json_to_realm_value(self.interp.realm_state, arg) catch {
      @runtime.JsonBridgeFailure(message) =>
        return Err(
          make_engine_diagnostic(
            failure_kind_code="json-conversion-error",
            message~,
            operation_code="call-json",
            phase_code="argument-conversion",
            source_identity=None,
            engine_integrity=EngineIntegrity::Reusable,
            retained_effects=RetainedEffects::MayRemain,
            pending_jobs=self.pending_jobs_snapshot(),
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
          operation="call-json",
          phase="execute",
          source_identity=failure.source_identity(),
          javascript_integrity=EngineIntegrity::Reusable,
          javascript_effects=RetainedEffects::MayRemain,
          javascript_jobs=self.pending_jobs_snapshot(),
          internal_integrity=EngineIntegrity::Discard,
        ),
      )
  }
  let json = @runtime.realm_value_to_json(self.interp.realm_state, result) catch {
    @runtime.JsonBridgeFailure(message) =>
      return Err(
        make_engine_diagnostic(
          failure_kind_code="json-conversion-error",
          message~,
          operation_code="call-json",
          phase_code="result-conversion",
          source_identity=None,
          engine_integrity=EngineIntegrity::Reusable,
          retained_effects=RetainedEffects::MayRemain,
          pending_jobs=self.pending_jobs_snapshot(),
        ),
      )
  }
  Ok(json)
}

///|
/// Call a JSON-boundary function under one explicitly supplied,
/// operation-scoped execution policy. The same fresh control carrier spans
/// global lookup and target execution; direct JSON copying does not execute
/// JavaScript and therefore does not consume steps.
priv enum BoundedCallFailure {
  Expected(String, String, String)
  JsonConversion(String, String)
  Observed(String, @runtime.SourceObservedFailure)
  Unexpected(String, Error)
}

///|
priv enum BoundedCallOutcome {
  Success(Json)
  Failure(BoundedCallFailure)
}

///|
/// Perform the bounded call while returning only private outcome descriptors.
/// The caller deliberately materializes diagnostics after the execution-control
/// carrier has been restored.
fn Engine::bounded_call_outcome(
  self : Engine,
  name : String,
  args : Array[Json],
) -> BoundedCallOutcome {
  let lookup_result = @runtime.observe_source_failure(self.interp.realm_state, () => {
    self.get_global_export_for_diagnostic(name)
  })
  let callee = match lookup_result {
    Ok(callee) => callee
    Err(failure) =>
      return match failure.cause() {
        MissingGlobal(message) =>
          Failure(
            BoundedCallFailure::Expected("missing-global", message, "lookup"),
          )
        _ => Failure(BoundedCallFailure::Observed("lookup", failure))
      }
  }
  guard @runtime.is_callable(callee) else {
    return Failure(BoundedCallFailure::Expected("not-callable", name, "lookup"))
  }
  let runtime_args : Array[@runtime.Value] = []
  for arg in args {
    let converted = @runtime.json_to_realm_value(self.interp.realm_state, arg) catch {
      @runtime.JsonBridgeFailure(message) =>
        return Failure(
          BoundedCallFailure::JsonConversion("argument-conversion", message),
        )
    }
    runtime_args.push(converted)
  }
  let call_result = @runtime.observe_source_failure(self.interp.realm_state, () => {
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
      return Failure(BoundedCallFailure::Observed("execute", failure))
  }
  let json = @runtime.realm_value_to_json(self.interp.realm_state, result) catch {
    @runtime.JsonBridgeFailure(message) =>
      return Failure(
        BoundedCallFailure::JsonConversion("result-conversion", message),
      )
  }
  Success(json)
}

///|
fn bounded_call_guardrail_message(kind : String) -> String {
  match kind {
    "interrupted" => "Execution interrupted"
    "execution-limit" => "Execution limit exceeded"
    "stack-depth-limit" => @runtime.stack_depth_limit_message()
    _ => "Execution guardrail rejected the operation"
  }
}

///|
fn Engine::bounded_call_observed_diagnostic(
  self : Engine,
  phase : String,
  failure : @runtime.SourceObservedFailure,
) -> EngineDiagnostic {
  let cause = failure.cause()
  let source_identity = failure.source_identity()
  match @runtime.execution_control_failure_code(cause) {
    Some(kind) =>
      make_engine_diagnostic(
        failure_kind_code=kind,
        message=bounded_call_guardrail_message(kind),
        operation_code="call-json",
        phase_code=phase,
        source_identity~,
        engine_integrity=EngineIntegrity::Unknown,
        retained_effects=RetainedEffects::MayRemain,
        pending_jobs=self.pending_jobs_snapshot(),
      )
    None =>
      match cause {
        @runtime.JsException(value) if @runtime.is_engine_stack_depth_error(
            value,
          ) =>
          make_engine_diagnostic(
            failure_kind_code="stack-depth-limit",
            message=@runtime.stack_depth_limit_message(),
            operation_code="call-json",
            phase_code=phase,
            source_identity~,
            engine_integrity=EngineIntegrity::Unknown,
            retained_effects=RetainedEffects::MayRemain,
            pending_jobs=self.pending_jobs_snapshot(),
          )
        _ =>
          runtime_engine_diagnostic(
            cause,
            operation="call-json",
            phase~,
            source_identity~,
            javascript_integrity=EngineIntegrity::Reusable,
            javascript_effects=RetainedEffects::MayRemain,
            javascript_jobs=self.pending_jobs_snapshot(),
            internal_integrity=EngineIntegrity::Discard,
          )
      }
  }
}

///|
fn Engine::bounded_call_diagnostic(
  self : Engine,
  failure : BoundedCallFailure,
) -> EngineDiagnostic {
  match failure {
    Expected(kind, message, phase) =>
      make_engine_diagnostic(
        failure_kind_code=kind,
        message~,
        operation_code="call-json",
        phase_code=phase,
        source_identity=None,
        engine_integrity=EngineIntegrity::Reusable,
        retained_effects=if kind == "missing-global" {
          RetainedEffects::None
        } else {
          RetainedEffects::MayRemain
        },
        pending_jobs=self.pending_jobs_snapshot(),
      )
    JsonConversion(phase, message) =>
      make_engine_diagnostic(
        failure_kind_code="json-conversion-error",
        message~,
        operation_code="call-json",
        phase_code=phase,
        source_identity=None,
        engine_integrity=EngineIntegrity::Reusable,
        retained_effects=RetainedEffects::MayRemain,
        pending_jobs=self.pending_jobs_snapshot(),
      )
    Observed(phase, failure) =>
      self.bounded_call_observed_diagnostic(phase, failure)
    Unexpected(phase, error) =>
      runtime_engine_diagnostic(
        error,
        operation="call-json",
        phase~,
        source_identity=None,
        javascript_integrity=EngineIntegrity::Discard,
        javascript_effects=RetainedEffects::Unknown,
        javascript_jobs=PendingJobs::Unknown,
        internal_integrity=EngineIntegrity::Discard,
      )
  }
}

///|
/// Call a JSON-boundary function under one explicitly supplied,
/// operation-scoped execution policy. The same fresh control carrier spans
/// global lookup, direct JSON conversion, target execution, and direct result
/// conversion. The direct bridge itself does not execute JavaScript.
pub fn Engine::call_json_bounded(
  self : Engine,
  name : String,
  args : Array[Json],
  policy : @runtime.ExecutionPolicy,
) -> Result[Json, EngineDiagnostic] {
  let outcome = self.interp.with_execution_policy(policy, () => {
    self.bounded_call_outcome(name, args)
  }) catch {
    error =>
      BoundedCallOutcome::Failure(
        BoundedCallFailure::Unexpected("lookup", error),
      )
  }
  match outcome {
    Success(json) => Ok(json)
    Failure(failure) => Err(self.bounded_call_diagnostic(failure))
  }
}

///|
fn Engine::microtask_checkpoint_failure_diagnostic(
  self : Engine,
  error : Error,
  source_identity : String?,
) -> EngineDiagnostic {
  let guardrail_kind = match @runtime.execution_control_failure_code(error) {
    Some(kind) => Some(kind)
    None =>
      match error {
        @runtime.JsException(value) if @runtime.is_engine_stack_depth_error(
            value,
          ) => Some("stack-depth-limit")
        _ => None
      }
  }
  match guardrail_kind {
    Some(kind) =>
      make_engine_diagnostic(
        failure_kind_code=kind,
        message=execution_guardrail_message(kind),
        operation_code="microtask-checkpoint",
        phase_code="microtask-dispatch",
        source_identity~,
        engine_integrity=EngineIntegrity::Discard,
        retained_effects=RetainedEffects::MayRemain,
        pending_jobs=self.pending_jobs_snapshot(),
      )
    None =>
      runtime_engine_diagnostic(
        error,
        operation="microtask-checkpoint",
        phase="microtask-dispatch",
        source_identity~,
        javascript_integrity=EngineIntegrity::Discard,
        javascript_effects=RetainedEffects::MayRemain,
        javascript_jobs=self.pending_jobs_snapshot(),
        internal_integrity=EngineIntegrity::Discard,
      )
  }
}

///|
/// Run a microtask checkpoint while returning operation-aware failure details.
pub fn Engine::run_microtask_checkpoint_diagnostic(
  self : Engine,
) -> Result[Bool, EngineDiagnostic] {
  let observed = self.interp.run_microtasks_observed() catch {
    error =>
      return Err(self.microtask_checkpoint_failure_diagnostic(error, None))
  }
  match observed {
    Ok(_) => Ok(self.has_pending_microtasks())
    Err(failure) =>
      Err(
        self.microtask_checkpoint_failure_diagnostic(
          failure.cause(),
          failure.source_identity(),
        ),
      )
  }
}

///|
/// Run one microtask checkpoint under a fresh operation-scoped execution
/// policy. Empty-queue detection is outside the execution-step budget.
pub fn Engine::run_microtask_checkpoint_bounded(
  self : Engine,
  policy : @runtime.ExecutionPolicy,
) -> Result[Bool, EngineDiagnostic] {
  let observed = self.interp.with_execution_policy(policy, () => {
    self.interp.run_microtasks_observed()
  }) catch {
    error =>
      return Err(self.microtask_checkpoint_failure_diagnostic(error, None))
  }
  match observed {
    Ok(_) => Ok(self.has_pending_microtasks())
    Err(failure) =>
      Err(
        self.microtask_checkpoint_failure_diagnostic(
          failure.cause(),
          failure.source_identity(),
        ),
      )
  }
}

///|
fn timer_failure_phase_code(phase : @runtime.TimerRunFailurePhase) -> String {
  match phase {
    @runtime.TimerRunFailurePhase::TimerQueueDispatch => "timer-queue-dispatch"
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
    operation="timer-checkpoint",
    phase="timer-dispatch",
    source_identity=None,
    javascript_integrity=EngineIntegrity::Discard,
    javascript_effects=RetainedEffects::Unknown,
    javascript_jobs=PendingJobs::Unknown,
    internal_integrity=EngineIntegrity::Discard,
  )
}

///|
fn Engine::timer_checkpoint_failure_diagnostic(
  self : Engine,
  failure : @runtime.TimerRunFailure,
) -> EngineDiagnostic {
  let error = failure.cause()
  let guardrail_kind = match @runtime.execution_control_failure_code(error) {
    Some(kind) => Some(kind)
    None =>
      match error {
        @runtime.JsException(value) if @runtime.is_engine_stack_depth_error(
            value,
          ) => Some("stack-depth-limit")
        _ => None
      }
  }
  let phase = timer_failure_phase_code(failure.phase())
  match guardrail_kind {
    Some(kind) =>
      make_engine_diagnostic(
        failure_kind_code=kind,
        message=execution_guardrail_message(kind),
        operation_code="timer-checkpoint",
        phase_code=phase,
        source_identity=failure.source_identity(),
        engine_integrity=EngineIntegrity::Discard,
        retained_effects=RetainedEffects::MayRemain,
        pending_jobs=self.pending_jobs_snapshot(),
      )
    None =>
      runtime_engine_diagnostic(
        error,
        operation="timer-checkpoint",
        phase~,
        source_identity=failure.source_identity(),
        javascript_integrity=EngineIntegrity::Discard,
        javascript_effects=RetainedEffects::MayRemain,
        javascript_jobs=self.pending_jobs_snapshot(),
        internal_integrity=EngineIntegrity::Discard,
      )
  }
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
    Err(failure) => Err(self.timer_checkpoint_failure_diagnostic(failure))
  }
}

///|
/// Run one timer checkpoint under a fresh operation-scoped execution policy.
/// Queue dispatch, callbacks, and timer-following microtasks share this scope.
pub fn Engine::run_timer_checkpoint_bounded(
  self : Engine,
  policy : @runtime.ExecutionPolicy,
) -> Result[Unit, EngineDiagnostic] {
  let observed = self.interp.with_execution_policy(policy, () => {
    self.interp.run_timers_observed()
  }) catch {
    err => return Err(timer_dispatch_diagnostic(err))
  }
  match observed {
    Ok(_) => Ok(())
    Err(failure) => Err(self.timer_checkpoint_failure_diagnostic(failure))
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
    operation="run",
    phase~,
    source_identity~,
    javascript_integrity=EngineIntegrity::NotApplicable,
    javascript_effects=effects,
    javascript_jobs=PendingJobs::Unknown,
    internal_integrity=EngineIntegrity::NotApplicable,
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
          failure_kind_code="parse-error",
          message=err.to_string(),
          operation_code="run",
          phase_code="parse",
          source_identity=source_id,
          engine_integrity=EngineIntegrity::NotApplicable,
          retained_effects=RetainedEffects::None,
          pending_jobs=PendingJobs::Unknown,
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
