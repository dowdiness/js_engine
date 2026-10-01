///|
/// Experimental stateful embedding facade used by the exception/reentry probes.
/// This is intentionally small and is not a production API.
pub struct HostedProbe {
  priv session : ExecutionSession
  priv policy : @runtime.ExecutionPolicy
  priv mut next_frame : Int
  priv mut current_frame : Int?
  priv mut effects : Int
  priv mut terminal_cause : Error?
  // Failure-only retention for the admitted turn, not execution-control state.
  priv mut operation : String
  priv mut failure_phase : String
  priv mut last_guest_failure : (Error, EngineDiagnostic)?
  priv mut terminal_diagnostic : EngineDiagnostic?
  priv mut completion_failure : HostedProbeError?
  priv mut secondary_diagnostics : Array[EngineDiagnostic]?
}

///|
pub struct HostedValue {
  priv owner : HostedProbe
  priv value : @runtime.Value
}

///|
priv struct HostedFrame {
  owner : HostedProbe
  id : Int
  mut active : Bool
}

///|
pub struct HostedCall {
  priv frame : HostedFrame
}

///|
fn HostedValue::HostedValue(
  owner : HostedProbe,
  value : @runtime.Value,
) -> HostedValue {
  { owner, value, }
}

///|
fn HostedCall::HostedCall(frame : HostedFrame) -> HostedCall {
  { frame, }
}

///|
// Kept inside the runtime's opaque terminal carrier until the public boundary.
// Retaining the error here avoids formatting host diagnostics during guest unwind.
priv suberror HostedCallbackFailure {
  HostedCallbackFailure(Error)
}

///|
pub(all) suberror HostedProbeError {
  HostedParse(EngineDiagnostic)
  HostedGuestThrow(HostedValue, EngineDiagnostic)
  HostedGuestThrowWithSecondary(
    primary~ : HostedValue,
    secondary~ : HostedValue,
    primary_diagnostic~ : EngineDiagnostic,
    secondary_diagnostic~ : EngineDiagnostic
  )
  HostedTerminal(Error, EngineDiagnostic, Array[EngineDiagnostic]?)
  HostedHostFailure(Error, EngineDiagnostic, Array[EngineDiagnostic]?)
  HostedForeignValue
  HostedExpiredHostCall
  HostedSessionBusy
  HostedSessionClosed
  HostedSessionFaulted
  HostedExpectedNumber
  HostedExpectedBool
  HostedExpectedString
}

///|
pub fn HostedProbe::HostedProbe(
  policy : @runtime.ExecutionPolicy,
) -> HostedProbe raise HostedProbeError {
  let session = HostEnvironment().create_session() catch {
    error =>
      raise HostedHostFailure(
        error,
        make_engine_diagnostic(
          failure_kind_code="host-failure",
          message="Hosted session creation failed",
          operation_code="create",
          phase_code="admission",
          source_identity=None,
          engine_integrity=EngineIntegrity::NotApplicable,
          retained_effects=RetainedEffects::None,
          pending_jobs=PendingJobs::Unknown,
        ),
        None,
      )
  }
  {
    session,
    policy,
    next_frame: 1,
    current_frame: None,
    effects: 0,
    terminal_cause: None,
    operation: "",
    failure_phase: "admission",
    last_guest_failure: None,
    terminal_diagnostic: None,
    completion_failure: None,
    secondary_diagnostics: None,
  }
}

///|
pub fn HostedProbe::register(
  self : HostedProbe,
  name : String,
  callback : (HostedCall, Array[HostedValue]) -> HostedValue raise,
) -> Unit raise HostedProbeError {
  self.require_available()
  let native = @runtime.make_native_func(
    name~,
    realm_state=Some(self.session.engine.interp.realm_state),
    args => self.dispatch_callback(callback, args),
  )
  self.session.engine.install_host_global(name, native)
}

///|
fn HostedProbe::dispatch_callback(
  self : HostedProbe,
  callback : (HostedCall, Array[HostedValue]) -> HostedValue raise,
  args : Array[@runtime.Value],
) -> @runtime.Value raise {
  self.session.engine.interp.check_hosted_execution()
  let id = self.next_frame
  self.next_frame += 1
  let frame = { owner: self, id, active: true, }
  let previous = self.current_frame
  self.current_frame = Some(id)
  let result : Result[HostedValue, Error] = Ok(
    {
      let value = callback(
        HostedCall::HostedCall(frame),
        args.map(value => HostedValue::HostedValue(self, value)),
      )
      self.require_owner(value)
      value
    },
  ) catch {
    error => Err(error)
  }
  frame.active = false
  self.current_frame = previous
  let gate : Result[Unit, Error] = Ok(
    self.session.engine.interp.check_hosted_execution(),
  ) catch {
    error => Err(error)
  }
  match gate {
    Err(terminal) => {
      match result {
        Err(error) =>
          if !same_hosted_terminal_report(error, terminal) {
            self.remember_secondary_error(error, None, host_failure=true)
          }
        Ok(_) => ()
      }
      raise terminal
    }
    Ok(_) => ()
  }
  match result {
    Ok(value) => value.value
    Err(error) => {
      match error {
        HostedGuestThrow(value, diagnostic) =>
          self.rethrow_guest_value(value, diagnostic)
        HostedGuestThrowWithSecondary(
          primary~,
          secondary~,
          primary_diagnostic~,
          secondary_diagnostic=_
        ) => {
          let ownership : Result[Unit, HostedProbeError] = Ok(
            self.require_owner(secondary),
          ) catch {
            error => Err(error)
          }
          match ownership {
            Err(error) =>
              self.session.engine.interp.terminate_hosted_execution(
                HostedCallbackFailure(error),
              )
            Ok(_) => ()
          }
          self.rethrow_guest_value(primary, primary_diagnostic)
        }
        HostedTerminal(cause, diagnostic, secondary) => {
          self.seed_terminal_diagnostic(diagnostic, secondary)
          self.session.engine.interp.terminate_hosted_execution(cause)
        }
        HostedHostFailure(cause, diagnostic, secondary) => {
          self.seed_terminal_diagnostic(diagnostic, secondary)
          self.session.engine.interp.terminate_hosted_execution(
            HostedCallbackFailure(cause),
          )
        }
        @runtime.JsException(_) => ()
        _ =>
          match @runtime.hosted_execution_failure_cause(error) {
            Some(cause) =>
              self.session.engine.interp.terminate_hosted_execution(cause)
            None =>
              self.session.engine.interp.terminate_hosted_execution(
                HostedCallbackFailure(error),
              )
          }
      }
      raise error
    }
  }
}

///|
fn HostedProbe::require_available(
  self : HostedProbe,
) -> Unit raise HostedProbeError {
  match self.session.state {
    Available => ()
    Running => raise HostedSessionBusy
    Closed => raise HostedSessionClosed
    Faulted => raise HostedSessionFaulted
  }
}

///|
fn HostedProbe::require_live(self : HostedProbe) -> Unit raise HostedProbeError {
  match self.session.state {
    Available | Running => ()
    Closed => raise HostedSessionClosed
    Faulted => raise HostedSessionFaulted
  }
}

///|
fn HostedProbe::require_owner(
  self : HostedProbe,
  value : HostedValue,
) -> Unit raise HostedProbeError {
  guard physical_equal(self, value.owner) else { raise HostedForeignValue }
  self.require_live()
}

///|
fn HostedProbe::begin_nested(
  self : HostedProbe,
  frame : HostedFrame,
  nested? : Bool = false,
) -> Unit raise HostedProbeError {
  let current_matches = match self.current_frame {
    Some(id) => id == frame.id
    None => false
  }
  guard frame.active && current_matches else { raise HostedExpiredHostCall }
  self.require_live()
  self.check_control(
    phase=if nested { self.nested_failure_phase() } else { self.failure_phase },
  )
}

///|
fn HostedProbe::inner_call(
  self : HostedProbe,
  frame : HostedFrame,
  callee : HostedValue,
  receiver : HostedValue,
  args : Array[HostedValue],
) -> HostedValue raise HostedProbeError {
  self.begin_nested(frame, nested=true)
  self.require_owner(callee)
  self.require_owner(receiver)
  for arg in args {
    self.require_owner(arg)
  }
  let saved = self.current_frame
  self.current_frame = None
  let result : Result[@runtime.Value, HostedProbeError] = Ok(
    self.observed_guest_action(self.nested_failure_phase(), () => {
      self.session.engine.interp.call_value(
        callee.value,
        receiver.value,
        args.map(arg => arg.value),
        @token.Loc::default(),
      )
    }),
  ) catch {
    error => Err(error)
  }
  self.current_frame = saved
  match result {
    Ok(value) => HostedValue::HostedValue(self, value)
    Err(error) => raise error
  }
}

///|
fn HostedProbe::inner_get(
  self : HostedProbe,
  frame : HostedFrame,
  target : HostedValue,
  name : String,
) -> HostedValue raise HostedProbeError {
  self.begin_nested(frame, nested=true)
  self.require_owner(target)
  let saved = self.current_frame
  self.current_frame = None
  let result : Result[@runtime.Value, HostedProbeError] = Ok(
    self.observed_guest_action(self.nested_failure_phase(), () => {
      self.session.engine.interp.get_property(
        target.value,
        name,
        @token.Loc::default(),
      )
    }),
  ) catch {
    error => Err(error)
  }
  self.current_frame = saved
  match result {
    Ok(value) => HostedValue::HostedValue(self, value)
    Err(error) => raise error
  }
}

///|
fn[T] HostedProbe::public_turn(
  self : HostedProbe,
  action : () -> T raise Error,
  operation~ : String,
  checkpoint? : Bool = false,
) -> T raise HostedProbeError {
  self.require_available()
  self.operation = operation
  self.failure_phase = "admission"
  self.session.state = Running
  let result : Result[T, Error] = Ok(
    self.session.engine.interp.with_hosted_execution_policy(self.policy, () => {
      self.failure_phase = if checkpoint { "body" } else { "inspection" }
      errdefer {
        self.failure_phase = "commit"
      }
      let value = if checkpoint {
        self.complete_public_body(action)
      } else {
        action() catch {
          error => {
            let failure = self.classify_failure(error, None, snapshot=false)
            self.completion_failure = Some(failure)
            raise failure
          }
        }
      }
      self.failure_phase = "commit"
      value
    }),
  ) catch {
    error => Err(error)
  }
  let outcome : Result[T, HostedProbeError] = match result {
    Ok(value) => {
      self.session.state = Available
      Ok(value)
    }
    Err(error) => {
      let failure = self.classify_failure(
        error,
        None,
        snapshot=false,
        settled=true,
      )
      match failure {
        HostedTerminal(cause, _, _) => {
          self.session.state = Faulted
          self.terminal_cause = Some(cause)
          self.session.host_binding.invalidate_scheduled_turns()
        }
        HostedHostFailure(cause, _, _) => {
          self.session.state = Faulted
          self.terminal_cause = Some(
            match @runtime.hosted_execution_failure_cause(error) {
              Some(first) => first
              None => HostedCallbackFailure(cause)
            },
          )
          self.session.host_binding.invalidate_scheduled_turns()
        }
        _ => self.session.state = Available
      }
      Err(failure)
    }
  }
  self.operation = ""
  self.failure_phase = "admission"
  self.last_guest_failure = None
  self.terminal_diagnostic = None
  self.completion_failure = None
  self.secondary_diagnostics = None
  match outcome {
    Ok(value) => value
    Err(error) => raise error
  }
}

///|
fn same_hosted_terminal_report(error : Error, terminal : Error) -> Bool {
  guard @runtime.hosted_execution_failure_cause(terminal) is Some(first) else {
    return false
  }
  match error {
    HostedTerminal(cause, _, _) => physical_equal(cause, first)
    HostedHostFailure(cause, _, _) =>
      match first {
        HostedCallbackFailure(original) => physical_equal(cause, original)
        _ => false
      }
    _ =>
      match @runtime.hosted_execution_failure_cause(error) {
        Some(cause) => physical_equal(cause, first)
        None => false
      }
  }
}

///|
fn HostedProbe::nested_failure_phase(self : HostedProbe) -> String {
  match self.failure_phase {
    "checkpoint" | "checkpoint-nested" => "checkpoint-nested"
    _ => "nested"
  }
}

///|
fn HostedProbe::runtime_diagnostic(
  self : HostedProbe,
  kind : String,
  message : String,
  source_identity : String?,
  integrity : EngineIntegrity,
  phase? : String = self.failure_phase,
) -> EngineDiagnostic {
  make_engine_diagnostic(
    failure_kind_code=kind,
    message~,
    operation_code=self.operation,
    phase_code=phase,
    source_identity~,
    engine_integrity=integrity,
    retained_effects=if phase == "admission" || phase == "inspection" {
      RetainedEffects::None
    } else {
      RetainedEffects::MayRemain
    },
    pending_jobs=self.session.engine.pending_jobs_snapshot(),
  )
}

///|
fn HostedProbe::guest_diagnostic(
  self : HostedProbe,
  error : Error,
  source_identity : String?,
  phase? : String = self.failure_phase,
) -> EngineDiagnostic {
  match self.last_guest_failure {
    Some((original, diagnostic)) if physical_equal(original, error) =>
      enrich_hosted_failure_source(diagnostic, source_identity)
    _ => {
      let message = match error {
        @runtime.JsException(@runtime.String_(text)) => text
        @runtime.JsException(_) => "JavaScript exception"
        _ =>
          match @errors.name_message_if_js_error(error) {
            Some((_, message)) => message
            None => "JavaScript exception"
          }
      }
      self.runtime_diagnostic(
        "javascript-exception",
        message,
        source_identity,
        EngineIntegrity::Reusable,
        phase~,
      )
    }
  }
}

///|
// A later trusted unwind can identify the source of the same failure.
// Never overwrite a known origin or mutate a diagnostic retained by a Host.
fn enrich_hosted_failure_source(
  diagnostic : EngineDiagnostic,
  source_identity : String?,
) -> EngineDiagnostic {
  guard diagnostic.source_identity() is None && source_identity is Some(_) else {
    return diagnostic
  }
  make_engine_diagnostic(
    failure_kind_code=diagnostic.failure_kind_code(),
    message=diagnostic.message(),
    operation_code=diagnostic.operation_code(),
    phase_code=diagnostic.phase_code(),
    source_identity~,
    source_location=diagnostic.source_location(),
    engine_integrity=diagnostic.engine_integrity(),
    retained_effects=diagnostic.retained_effects(),
    pending_jobs=diagnostic.pending_jobs(),
  )
}

///|
fn HostedProbe::push_secondary(
  self : HostedProbe,
  diagnostic : EngineDiagnostic,
) -> Unit {
  match self.secondary_diagnostics {
    Some(diagnostics) => diagnostics.push(diagnostic)
    None => self.secondary_diagnostics = Some([diagnostic])
  }
}

///|
fn HostedProbe::remember_secondary_error(
  self : HostedProbe,
  error : Error,
  source_identity : String?,
  host_failure? : Bool = false,
) -> Unit {
  match error {
    HostedGuestThrow(_, diagnostic)
    | HostedTerminal(_, diagnostic, _)
    | HostedHostFailure(_, diagnostic, _) => self.push_secondary(diagnostic)
    HostedGuestThrowWithSecondary(
      primary=_,
      secondary=_,
      primary_diagnostic~,
      secondary_diagnostic~
    ) => {
      self.push_secondary(primary_diagnostic)
      self.push_secondary(secondary_diagnostic)
    }
    @runtime.JsException(_) =>
      self.push_secondary(self.guest_diagnostic(error, source_identity))
    _ =>
      if !host_failure && @runtime.is_js_catchable_error(error) {
        self.push_secondary(self.guest_diagnostic(error, source_identity))
      } else {
        self.push_secondary(
          self.runtime_diagnostic(
            "host-failure",
            "Host callback failed",
            source_identity,
            EngineIntegrity::Discard,
          ),
        )
      }
  }
}

///|
fn HostedProbe::seed_terminal_diagnostic(
  self : HostedProbe,
  diagnostic : EngineDiagnostic,
  secondary : Array[EngineDiagnostic]?,
) -> Unit {
  if self.terminal_diagnostic is None {
    self.terminal_diagnostic = Some(diagnostic)
    self.secondary_diagnostics = secondary.map(diagnostics => diagnostics.copy())
  }
}

///|
fn HostedProbe::take_terminal_secondaries(
  self : HostedProbe,
) -> Array[EngineDiagnostic]? {
  match self.completion_failure {
    Some(HostedGuestThrow(_, diagnostic)) =>
      match self.secondary_diagnostics {
        Some(diagnostics) => {
          diagnostics.insert(0, diagnostic)
          Some(diagnostics)
        }
        None => Some([diagnostic])
      }
    Some(
      HostedGuestThrowWithSecondary(
        primary=_,
        secondary=_,
        primary_diagnostic~,
        secondary_diagnostic~
      )
    ) =>
      match self.secondary_diagnostics {
        Some(diagnostics) => {
          diagnostics.insert(0, secondary_diagnostic)
          diagnostics.insert(0, primary_diagnostic)
          Some(diagnostics)
        }
        None => Some([primary_diagnostic, secondary_diagnostic])
      }
    _ => self.secondary_diagnostics
  }
}

///|
fn HostedProbe::terminal_failure(
  self : HostedProbe,
  cause : Error,
  source_identity : String?,
  snapshot~ : Bool,
  settled~ : Bool,
) -> HostedProbeError {
  let diagnostic = match self.terminal_diagnostic {
    Some(diagnostic) =>
      if diagnostic.source_identity() is None && source_identity is Some(_) {
        let enriched = enrich_hosted_failure_source(diagnostic, source_identity)
        self.terminal_diagnostic = Some(enriched)
        enriched
      } else {
        diagnostic
      }
    None => {
      let diagnostic = match cause {
        HostedCallbackFailure(_) =>
          self.runtime_diagnostic(
            "host-failure",
            "Host callback failed",
            source_identity,
            EngineIntegrity::Discard,
          )
        _ =>
          self.runtime_diagnostic(
            @runtime.execution_control_failure_code(cause).unwrap_or(
              "execution-termination",
            ),
            "Hosted execution terminated",
            source_identity,
            EngineIntegrity::Discard,
          )
      }
      self.terminal_diagnostic = Some(diagnostic)
      diagnostic
    }
  }
  let secondary = if settled {
    self.take_terminal_secondaries()
  } else if snapshot {
    // A Host may retain this error while later cleanup adds diagnostics.
    self.secondary_diagnostics.map(diagnostics => diagnostics.copy())
  } else {
    self.secondary_diagnostics
  }
  match cause {
    HostedCallbackFailure(original) =>
      HostedHostFailure(original, diagnostic, secondary)
    _ => HostedTerminal(cause, diagnostic, secondary)
  }
}

///|
fn HostedProbe::latch_terminal_failure(
  self : HostedProbe,
  cause : Error,
  source_identity : String?,
  snapshot~ : Bool,
  settled~ : Bool,
) -> HostedProbeError {
  let mut first = cause
  self.session.engine.interp.terminate_hosted_execution(cause) catch {
    carrier =>
      match @runtime.hosted_execution_failure_cause(carrier) {
        Some(primary) => first = primary
        None => first = HostedCallbackFailure(carrier)
      }
  }
  self.terminal_failure(first, source_identity, snapshot~, settled~)
}

///|
fn HostedProbe::classify_failure(
  self : HostedProbe,
  error : Error,
  source_identity : String?,
  snapshot? : Bool = true,
  settled? : Bool = false,
) -> HostedProbeError {
  match @runtime.hosted_execution_failure_cause(error) {
    Some(cause) =>
      return self.terminal_failure(cause, source_identity, snapshot~, settled~)
    None => ()
  }
  // Sticky termination/interruption wins before constructing any JS Error.
  let gate : Result[Unit, Error] = Ok(
    self.session.engine.interp.check_hosted_execution(),
  ) catch {
    error => Err(error)
  }
  match gate {
    Err(terminal) => {
      if !same_hosted_terminal_report(error, terminal) {
        self.remember_secondary_error(error, source_identity)
      }
      match @runtime.hosted_execution_failure_cause(terminal) {
        Some(cause) =>
          return self.terminal_failure(cause, None, snapshot~, settled~)
        None =>
          return self.latch_terminal_failure(
            HostedCallbackFailure(terminal),
            None,
            snapshot~,
            settled~,
          )
      }
    }
    Ok(_) => ()
  }
  match error {
    HostedTerminal(cause, diagnostic, secondary) => {
      self.seed_terminal_diagnostic(diagnostic, secondary)
      self.latch_terminal_failure(cause, source_identity, snapshot~, settled~)
    }
    HostedHostFailure(cause, diagnostic, secondary) => {
      self.seed_terminal_diagnostic(diagnostic, secondary)
      self.latch_terminal_failure(
        HostedCallbackFailure(cause),
        source_identity,
        snapshot~,
        settled~,
      )
    }
    HostedProbeError::_ as typed => typed
    _ =>
      if @runtime.is_js_catchable_error(error) {
        let diagnostic = self.guest_diagnostic(error, source_identity)
        let value = @runtime.js_error_to_value_with_env(
          error,
          Some(self.session.engine.interp.global),
        )
        HostedGuestThrow(HostedValue::HostedValue(self, value), diagnostic)
      } else {
        self.latch_terminal_failure(
          HostedCallbackFailure(error),
          source_identity,
          snapshot~,
          settled~,
        )
      }
  }
}

///|
fn HostedProbe::check_control(
  self : HostedProbe,
  phase? : String = self.failure_phase,
) -> Unit raise HostedProbeError {
  self.session.engine.interp.check_hosted_execution() catch {
    error => {
      let previous = self.failure_phase
      self.failure_phase = phase
      let failure = self.classify_failure(error, None)
      self.failure_phase = previous
      raise failure
    }
  }
}

///|
fn[T] HostedProbe::observed_guest_action(
  self : HostedProbe,
  phase : String,
  action : () -> T raise Error,
  snapshot? : Bool = true,
) -> T raise HostedProbeError {
  let previous = self.failure_phase
  self.failure_phase = phase
  let observed = @runtime.observe_source_failure(
    self.session.engine.interp.realm_state,
    () => {
      let value = action()
      self.session.engine.interp.check_hosted_execution()
      value
    },
  )
  let outcome : Result[T, HostedProbeError] = match observed {
    Ok(value) => Ok(value)
    Err(failure) =>
      Err(
        self.classify_failure(
          failure.cause(),
          failure.source_identity(),
          snapshot~,
        ),
      )
  }
  self.failure_phase = previous
  match outcome {
    Ok(value) => value
    Err(error) => raise error
  }
}

///|
fn HostedProbe::rethrow_guest_value(
  self : HostedProbe,
  value : HostedValue,
  diagnostic : EngineDiagnostic,
) -> Unit raise Error {
  let ownership : Result[Unit, HostedProbeError] = Ok(self.require_owner(value)) catch {
    error => Err(error)
  }
  match ownership {
    Err(error) =>
      self.session.engine.interp.terminate_hosted_execution(
        HostedCallbackFailure(error),
      )
    Ok(_) => ()
  }
  let result : Result[Unit, Error] = Ok(
    @runtime.raise_js_exception(value.value),
  ) catch {
    exception => Err(exception)
  }
  match result {
    Err(exception) => {
      self.last_guest_failure = Some((exception, diagnostic))
      raise exception
    }
    Ok(_) => ()
  }
}

///|
fn[T] HostedProbe::complete_public_body(
  self : HostedProbe,
  action : () -> T raise Error,
) -> T raise HostedProbeError {
  let primary : Result[T, HostedProbeError] = Ok(
    self.observed_guest_action("body", action, snapshot=false),
  ) catch {
    HostedGuestThrow(_, _) as failure => {
      self.completion_failure = Some(failure)
      Err(failure)
    }
    error => raise error
  }
  self.check_control()
  self.failure_phase = "checkpoint"
  let checkpoint : Result[Unit, HostedProbeError] = try {
    match self.session.engine.interp.run_microtasks_observed() {
      Ok(_) => Ok(())
      Err(failure) =>
        Err(
          self.classify_failure(
            failure.cause(),
            failure.source_identity(),
            snapshot=false,
          ),
        )
    }
  } catch {
    error => Err(self.classify_failure(error, None, snapshot=false))
  }
  self.failure_phase = "body"
  match (primary, checkpoint) {
    (Ok(value), Ok(_)) => value
    (Err(failure), Ok(_)) => raise failure
    (Ok(_), Err(HostedGuestThrow(_, _) as failure)) => {
      self.completion_failure = Some(failure)
      raise failure
    }
    (
      Err(HostedGuestThrow(first, primary_diagnostic)),
      Err(HostedGuestThrow(second, secondary_diagnostic)),
    ) => {
      let failure = HostedGuestThrowWithSecondary(
        primary=first,
        secondary=second,
        primary_diagnostic~,
        secondary_diagnostic~,
      )
      self.completion_failure = Some(failure)
      raise failure
    }
    (_, Err(failure)) => raise failure
  }
}

///|
pub fn HostedProbe::global(
  self : HostedProbe,
  name : String,
) -> HostedValue raise HostedProbeError {
  self.public_turn(
    () => {
      let value = self.session.engine.get_global_export_for_diagnostic(name)
      HostedValue::HostedValue(self, value)
    },
    operation="global",
  )
}

///|
pub fn HostedProbe::evaluate(
  self : HostedProbe,
  source : String,
) -> HostedValue raise HostedProbeError {
  self.require_available()
  let program = match @parser.parse_diagnostic(source) {
    Ok(program) => program
    Err(failure) =>
      raise HostedParse(
        make_engine_diagnostic(
          failure_kind_code="parse-error",
          message=failure.message(),
          operation_code="evaluate",
          phase_code="parse",
          source_identity=None,
          source_location=parse_failure_location(failure),
          engine_integrity=EngineIntegrity::Reusable,
          retained_effects=RetainedEffects::None,
          pending_jobs=self.session.engine.pending_jobs_snapshot(),
        ),
      )
  }
  self.public_turn(
    () => {
      let value = if @engine_candidate_mode.candidate_mode_enabled() {
        @compiler.run_candidate_program(
          self.session.engine.interp,
          program.stmts,
        )
      } else {
        self.session.engine.interp.run(program.stmts)
      }
      HostedValue::HostedValue(self, value)
    },
    operation="evaluate",
    checkpoint=true,
  )
}

///|
pub fn HostedProbe::number(
  self : HostedProbe,
  value : Double,
) -> HostedValue raise HostedProbeError {
  self.require_available()
  { owner: self, value: @runtime.Number(value), }
}

///|
pub fn HostedProbe::effect_count(self : HostedProbe) -> Int {
  self.effects
}

///|
pub fn HostedProbe::state(self : HostedProbe) -> String {
  match self.session.state {
    Available => "available"
    Running => "running"
    Closed => "closed"
    Faulted => "faulted"
  }
}

///|
pub fn HostedProbe::close(self : HostedProbe) -> Unit raise HostedProbeError {
  self.session.close() catch {
    SessionBusy => raise HostedSessionBusy
    SessionClosed => raise HostedSessionClosed
    SessionFaulted => raise HostedSessionFaulted
    error => {
      self.session.state = Faulted
      self.terminal_cause = Some(error)
      self.session.host_binding.invalidate_scheduled_turns()
      raise HostedHostFailure(
        error,
        make_engine_diagnostic(
          failure_kind_code="host-failure",
          message="Unexpected Session close failure",
          operation_code="close",
          phase_code="admission",
          source_identity=None,
          engine_integrity=EngineIntegrity::Discard,
          retained_effects=RetainedEffects::None,
          pending_jobs=self.session.engine.pending_jobs_snapshot(),
        ),
        None,
      )
    }
  }
}

///|
pub fn HostedValue::expect_number(
  self : HostedValue,
) -> Double raise HostedProbeError {
  self.owner.require_live()
  match self.value {
    Number(value) => value
    _ => raise HostedExpectedNumber
  }
}

///|
pub fn HostedProbe::terminal_cause(self : HostedProbe) -> Error? {
  self.terminal_cause
}

///|
pub fn HostedValue::expect_bool(
  self : HostedValue,
) -> Bool raise HostedProbeError {
  self.owner.require_live()
  match self.value {
    Bool(value) => value
    _ => raise HostedExpectedBool
  }
}

///|
pub fn HostedValue::expect_string(
  self : HostedValue,
) -> String raise HostedProbeError {
  self.owner.require_live()
  match self.value {
    String_(value) => value
    _ => raise HostedExpectedString
  }
}

///|
pub fn HostedValue::get(
  self : HostedValue,
  name : String,
) -> HostedValue raise HostedProbeError {
  self.owner.public_turn(
    () => {
      let value = self.owner.session.engine.interp.get_property(
        self.value,
        name,
        @token.Loc::default(),
      )
      HostedValue::HostedValue(self.owner, value)
    },
    operation="get",
    checkpoint=true,
  )
}

///|
pub fn HostedValue::call(
  self : HostedValue,
  args : Array[HostedValue],
) -> HostedValue raise HostedProbeError {
  self.owner.public_turn(
    () => {
      for arg in args {
        self.owner.require_owner(arg)
      }
      let value = self.owner.session.engine.interp.call_value(
        self.value,
        @runtime.Undefined,
        args.map(arg => arg.value),
        @token.Loc::default(),
      )
      HostedValue::HostedValue(self.owner, value)
    },
    operation="call",
    checkpoint=true,
  )
}

///|
pub fn HostedValue::call_property(
  self : HostedValue,
  name : String,
  args : Array[HostedValue],
) -> HostedValue raise HostedProbeError {
  self.owner.public_turn(
    () => {
      for arg in args {
        self.owner.require_owner(arg)
      }
      let callee = self.owner.session.engine.interp.get_property(
        self.value,
        name,
        @token.Loc::default(),
      )
      // A getter can reenter Host code and replace elements of the argument array.
      for arg in args {
        self.owner.require_owner(arg)
      }
      let value = self.owner.session.engine.interp.call_value(
        callee,
        self.value,
        args.map(arg => arg.value),
        @token.Loc::default(),
      )
      HostedValue::HostedValue(self.owner, value)
    },
    operation="call-property",
    checkpoint=true,
  )
}

///|
pub fn HostedCall::get(
  self : HostedCall,
  value : HostedValue,
  name : String,
) -> HostedValue raise HostedProbeError {
  self.frame.owner.inner_get(self.frame, value, name)
}

///|
pub fn HostedCall::call(
  self : HostedCall,
  function : HostedValue,
  args : Array[HostedValue],
) -> HostedValue raise HostedProbeError {
  self.frame.owner.inner_call(
    self.frame,
    function,
    HostedValue::HostedValue(self.frame.owner, @runtime.Undefined),
    args,
  )
}

///|
pub fn HostedCall::call_property(
  self : HostedCall,
  value : HostedValue,
  name : String,
  args : Array[HostedValue],
) -> HostedValue raise HostedProbeError {
  self.frame.owner.begin_nested(self.frame, nested=true)
  // Host arrays are mutable: check arguments before the getter and again in
  // inner_call after it returns.
  for arg in args {
    self.frame.owner.require_owner(arg)
  }
  let function = self.get(value, name)
  self.frame.owner.inner_call(self.frame, function, value, args)
}

///|
pub fn HostedCall::record_effect(
  self : HostedCall,
) -> Unit raise HostedProbeError {
  self.frame.owner.begin_nested(self.frame)
  self.frame.owner.effects += 1
}

///|
pub fn HostedProbe::bool(
  self : HostedProbe,
  value : Bool,
) -> HostedValue raise HostedProbeError {
  self.require_available()
  { owner: self, value: @runtime.Bool(value), }
}

///|
pub fn HostedProbe::string(
  self : HostedProbe,
  value : String,
) -> HostedValue raise HostedProbeError {
  self.require_available()
  { owner: self, value: @runtime.String_(value), }
}

///|
pub fn HostedCall::throw_value(
  self : HostedCall,
  value : HostedValue,
) -> Unit raise HostedProbeError {
  self.frame.owner.begin_nested(self.frame)
  self.frame.owner.require_owner(value)
  let owner = self.frame.owner
  let message = match value.value {
    @runtime.String_(text) => text
    _ => "JavaScript exception"
  }
  raise HostedGuestThrow(
    value,
    owner.runtime_diagnostic(
      "javascript-exception",
      message,
      None,
      EngineIntegrity::Reusable,
      phase=owner.nested_failure_phase(),
    ),
  )
}

///|
pub fn HostedCall::terminate(
  self : HostedCall,
  cause : Error,
) -> Unit raise HostedProbeError {
  self.frame.owner.begin_nested(self.frame)
  raise self.frame.owner.latch_terminal_failure(
    cause,
    None,
    snapshot=true,
    settled=false,
  )
}
