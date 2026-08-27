///|
pub using @runtime {type ConsoleOutputKind}

///|
/// Realm-independent Console Output delivered to an application-owned Output
/// Sink. Runtime Values never cross this boundary.
pub struct ConsoleOutput {
  priv kind_ : ConsoleOutputKind
  priv text_ : String
}

///|
fn ConsoleOutput::ConsoleOutput(
  kind~ : ConsoleOutputKind,
  text~ : String,
) -> ConsoleOutput {
  { kind_: kind, text_: text }
}

///|
pub fn ConsoleOutput::kind(self : ConsoleOutput) -> ConsoleOutputKind {
  self.kind_
}

///|
pub fn ConsoleOutput::text(self : ConsoleOutput) -> String {
  self.text_
}

///|
/// Application-defined request for a Script Resource. The request and
/// referrer are opaque names; the engine does not apply path or URL rules.
pub struct ScriptResourceRequest {
  priv request_ : String
  priv referrer_ : String?
}

///|
fn ScriptResourceRequest::ScriptResourceRequest(
  request~ : String,
  referrer~ : String?,
) -> ScriptResourceRequest {
  { request_: request, referrer_: referrer }
}

///|
pub fn ScriptResourceRequest::request(self : ScriptResourceRequest) -> String {
  self.request_
}

///|
pub fn ScriptResourceRequest::referrer(self : ScriptResourceRequest) -> String? {
  self.referrer_
}

///|
/// JavaScript source resolved by an application under an opaque identity.
pub struct ScriptResource {
  priv identity_ : String
  priv source_ : String
}

///|
pub fn ScriptResource::ScriptResource(
  identity~ : String,
  source~ : String,
) -> ScriptResource {
  { identity_: identity, source_: source }
}

///|
pub fn ScriptResource::identity(self : ScriptResource) -> String {
  self.identity_
}

///|
pub fn ScriptResource::source(self : ScriptResource) -> String {
  self.source_
}

///|
/// Opaque permission to resume one Session-owned timer callback once.
pub struct ScheduledTurn {
  priv host_binding : SessionHostBinding
  priv id : Int
}

///|
fn ScheduledTurn::ScheduledTurn(
  host_binding~ : SessionHostBinding,
  id~ : Int,
) -> ScheduledTurn {
  { host_binding, id }
}

///|
/// A timer request delivered to an application-owned scheduler.
pub struct TimerSchedule {
  priv delay_milliseconds_ : Int
  priv turn_ : ScheduledTurn
}

///|
fn TimerSchedule::TimerSchedule(
  delay_milliseconds~ : Int,
  turn~ : ScheduledTurn,
) -> TimerSchedule {
  { delay_milliseconds_: delay_milliseconds, turn_: turn }
}

///|
pub fn TimerSchedule::delay_milliseconds(self : TimerSchedule) -> Int {
  self.delay_milliseconds_
}

///|
pub fn TimerSchedule::turn(self : TimerSchedule) -> ScheduledTurn {
  self.turn_
}

///|
const MAX_SCHEDULED_TURN_ID : Int = 0x7FFFFFFF

///|
/// Reusable application-owned configuration for creating independent
/// Execution Sessions.
pub struct HostEnvironment {
  priv annex_b : Bool
  priv console : Bool
  priv script_resources : Bool
  priv timers : Bool
}

///|
pub fn HostEnvironment::HostEnvironment(
  annex_b? : Bool = false,
  console? : Bool = false,
  script_resources? : Bool = false,
  timers? : Bool = false,
) -> HostEnvironment {
  { annex_b, console, script_resources, timers }
}

///|
/// Application services bound while creating one Execution Session.
pub struct SessionBindings {
  priv console_output_sink : ((ConsoleOutput) -> Unit raise Error)?
  priv script_resource_resolver : ((ScriptResourceRequest) -> ScriptResource? raise Error)?
  priv timer_scheduler : ((TimerSchedule) -> Unit raise Error)?
}

///|
pub fn SessionBindings::SessionBindings(
  console_output_sink? : ((ConsoleOutput) -> Unit raise Error)? = None,
  script_resource_resolver? : ((ScriptResourceRequest) -> ScriptResource? raise Error)? = None,
  timer_scheduler? : ((TimerSchedule) -> Unit raise Error)? = None,
) -> SessionBindings {
  { console_output_sink, script_resource_resolver, timer_scheduler }
}

///|
/// Invalid combinations of a fixed Host Capability Set and Session Bindings.
pub(all) suberror SessionCreationError {
  BindingForAbsentCapability(String)
  MissingBindingForCapability(String)
} derive(Debug)

///|
pub impl Show for SessionCreationError with fn output(self, logger) {
  match self {
    BindingForAbsentCapability(capability) => {
      logger.write_string("BindingForAbsentCapability: ")
      logger.write_string(capability)
    }
    MissingBindingForCapability(capability) => {
      logger.write_string("MissingBindingForCapability: ")
      logger.write_string(capability)
    }
  }
}

///|
/// Errors reported by an Execution Session at its application boundary.
pub(all) suberror ExecutionSessionError {
  ExecutionFailure(EngineDiagnostic)
  HostFailure(capability~ : String, detail~ : String)
  SessionBusy
  SessionClosed
  SessionFaulted
  ScheduledTurnUnavailable
}

///|
pub impl Show for ExecutionSessionError with fn output(self, logger) {
  match self {
    ExecutionFailure(diagnostic) => {
      logger.write_string(diagnostic.failure_kind_code())
      logger.write_string(": ")
      logger.write_string(diagnostic.message())
    }
    HostFailure(capability~, detail~) => {
      logger.write_string("HostFailure(")
      logger.write_string(capability)
      logger.write_string("): ")
      logger.write_string(detail)
    }
    SessionBusy => logger.write_string("SessionBusy")
    SessionClosed => logger.write_string("SessionClosed")
    SessionFaulted => logger.write_string("SessionFaulted")
    ScheduledTurnUnavailable => logger.write_string("ScheduledTurnUnavailable")
  }
}

///|
priv struct SessionHostFailure {
  capability : String
  detail : String
}

///|
priv struct ScheduledCallback {
  callback : @runtime.Value
  arguments : Array[@runtime.Value]
}

///|
priv suberror ScheduledTurnAllocationFailure {
  ScheduledTurnIdSpaceExhausted
}

///|
impl Show for ScheduledTurnAllocationFailure with fn output(self, logger) {
  match self {
    ScheduledTurnIdSpaceExhausted =>
      logger.write_string("Scheduled Turn ID space is exhausted")
  }
}

///|
priv struct SessionHostBinding {
  console_output_sink : ((ConsoleOutput) -> Unit raise Error)?
  script_resource_resolver : ((ScriptResourceRequest) -> ScriptResource? raise Error)?
  timer_scheduler : ((TimerSchedule) -> Unit raise Error)?
  load_stack : Array[String]
  scheduled_callbacks : Map[Int, ScheduledCallback]
  mut next_scheduled_turn_id : Int
  mut failure : SessionHostFailure?
}

///|
fn SessionHostBinding::SessionHostBinding(
  bindings : SessionBindings,
) -> SessionHostBinding {
  {
    console_output_sink: bindings.console_output_sink,
    script_resource_resolver: bindings.script_resource_resolver,
    timer_scheduler: bindings.timer_scheduler,
    load_stack: [],
    scheduled_callbacks: Map([]),
    next_scheduled_turn_id: 1,
    failure: None,
  }
}

///|
fn SessionHostBinding::record_failure(
  self : SessionHostBinding,
  capability : String,
  error : Error,
) -> Unit {
  self.failure = Some({ capability, detail: error.to_string() })
}

///|
/// Notify this Session's Console destination. A raised application error
/// poisons this binding so the enclosing Hosted Turn can fault its Session.
fn SessionHostBinding::emit_console_output(
  self : SessionHostBinding,
  output : ConsoleOutput,
) -> Unit raise Error {
  match self.console_output_sink {
    Some(sink) => {
      let result : Result[Unit, Error] = Ok(sink(output)) catch {
        error => Err(error)
      }
      match result {
        Ok(_) => ()
        Err(error) => {
          self.record_failure("Console Output Sink", error)
          raise error
        }
      }
    }
    None => ()
  }
}

///|
fn SessionHostBinding::take_failure(
  self : SessionHostBinding,
) -> SessionHostFailure? {
  let failure = self.failure
  self.failure = None
  failure
}

///|
fn SessionHostBinding::load_referrer(self : SessionHostBinding) -> String? {
  guard self.load_stack.length() > 0 else { return None }
  Some(self.load_stack[self.load_stack.length() - 1])
}

///|
fn SessionHostBinding::resolve_script_resource(
  self : SessionHostBinding,
  request : String,
) -> ScriptResource? raise Error {
  guard self.script_resource_resolver is Some(resolve) else {
    fail("selected Script Resources capability has no Session binding")
  }
  let result : Result[ScriptResource?, Error] = Ok(
    resolve(ScriptResourceRequest(request~, referrer=self.load_referrer())),
  ) catch {
    error => Err(error)
  }
  match result {
    Ok(resource) => resource
    Err(error) => {
      self.record_failure("Script Resource Resolver", error)
      raise error
    }
  }
}

///|
fn SessionHostBinding::schedule_timer(
  self : SessionHostBinding,
  callback : @runtime.Value,
  arguments : Array[@runtime.Value],
  delay_milliseconds : Int,
) -> Int raise Error {
  guard self.timer_scheduler is Some(schedule) else {
    fail("selected Timers capability has no Session binding")
  }
  guard self.next_scheduled_turn_id >= 1 &&
    self.next_scheduled_turn_id < MAX_SCHEDULED_TURN_ID else {
    let error : Error = ScheduledTurnIdSpaceExhausted
    self.record_failure("Timer Scheduler", error)
    raise error
  }
  let id = self.next_scheduled_turn_id
  self.next_scheduled_turn_id += 1
  self.scheduled_callbacks[id] = { callback, arguments }
  let result : Result[Unit, Error] = Ok(
    schedule(
      TimerSchedule(
        delay_milliseconds~,
        turn=ScheduledTurn(host_binding=self, id~),
      ),
    ),
  ) catch {
    error => Err(error)
  }
  match result {
    Ok(_) => id
    Err(error) => {
      ignore(self.scheduled_callbacks.remove(id))
      self.record_failure("Timer Scheduler", error)
      raise error
    }
  }
}

///|
fn SessionHostBinding::cancel_scheduled_turn(
  self : SessionHostBinding,
  id : Int,
) -> Unit {
  ignore(self.scheduled_callbacks.remove(id))
}

///|
fn SessionHostBinding::take_scheduled_callback(
  self : SessionHostBinding,
  turn : ScheduledTurn,
) -> ScheduledCallback? {
  guard physical_equal(self, turn.host_binding) else { return None }
  let callback = self.scheduled_callbacks.get(turn.id)
  ignore(self.scheduled_callbacks.remove(turn.id))
  callback
}

///|
fn SessionHostBinding::invalidate_scheduled_turns(
  self : SessionHostBinding,
) -> Unit {
  self.scheduled_callbacks.clear()
}

///|
priv suberror ScriptResourceUnavailable {
  ScriptResourceUnavailable(String)
}

///|
impl Show for ScriptResourceUnavailable with fn output(self, logger) {
  let ScriptResourceUnavailable(request) = self
  logger.write_string("Script resource is unavailable: ")
  logger.write_string(request)
}

///|
fn Engine::eval_host_loaded_script(
  self : Engine,
  source : String,
  identity : String,
) -> Unit raise Error {
  let program = @parser.parse(source) catch {
    error => raise @errors.SyntaxError(message=error.to_string())
  }
  ignore(
    @runtime.with_source_identity(self.interp.realm_state, Some(identity), fn() raise {
      if @engine_candidate_mode.candidate_mode_enabled() {
        @compiler.run_candidate_program(self.interp, program.stmts)
      } else {
        self.interp.run(program.stmts)
      }
    }),
  )
}

///|
fn Engine::install_host_global(
  self : Engine,
  name : String,
  value : @runtime.Value,
) -> Unit {
  match self.interp.global_this {
    @runtime.Object(data) => {
      data.bag.properties[name] = value
      data.bag.descriptors[name] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      }
    }
    _ => ()
  }
}

///|
fn Engine::install_script_resource_loader(
  self : Engine,
  host_binding : SessionHostBinding,
) -> Unit {
  let load = @runtime.make_native_func(
    name="load",
    length=1,
    realm_state=Some(self.interp.realm_state),
    fn(arguments) raise {
      guard arguments.length() > 0 else {
        raise @errors.TypeError(message="load() requires a resource request")
      }
      let request = self.interp.to_js_string(arguments[0])
      let resource = match host_binding.resolve_script_resource(request) {
        Some(resource) => resource
        None => {
          let error : Error = ScriptResourceUnavailable(request)
          @runtime.raise_js_exception(
            @runtime.js_error_to_value_with_env(error, Some(self.interp.global)),
          )
          return @runtime.Undefined
        }
      }
      host_binding.load_stack.push(resource.identity())
      let evaluated : Result[Unit, Error] = Ok(
        self.eval_host_loaded_script(resource.source(), resource.identity()),
      ) catch {
        error => Err(error)
      }
      ignore(host_binding.load_stack.pop())
      match evaluated {
        Ok(_) => @runtime.Undefined
        Err(error) => raise error
      }
    },
  )
  self.install_host_global("load", load)
}

///|
fn Engine::install_timer_scheduler(
  self : Engine,
  host_binding : SessionHostBinding,
) -> Unit {
  let set_timeout = @runtime.make_native_func(
    name="setTimeout",
    length=1,
    realm_state=Some(self.interp.realm_state),
    fn(arguments) raise {
      let callback = if arguments.length() > 0 {
        arguments[0]
      } else {
        @runtime.Undefined
      }
      guard @runtime.is_callable(callback) else {
        raise @errors.TypeError(
          message="setTimeout requires a function as first argument",
        )
      }
      let delay = if arguments.length() > 1 {
        match arguments[1] {
          @runtime.Number(value) => {
            let milliseconds = value.to_int()
            if milliseconds < 0 {
              0
            } else {
              milliseconds
            }
          }
          _ => 0
        }
      } else {
        0
      }
      let callback_arguments : Array[@runtime.Value] = []
      for i = 2; i < arguments.length(); i = i + 1 {
        callback_arguments.push(arguments[i])
      }
      let id = host_binding.schedule_timer(callback, callback_arguments, delay)
      @runtime.Number(id.to_double())
    },
  )
  let clear_timeout = @runtime.make_native_func(
    name="clearTimeout",
    length=1,
    realm_state=Some(self.interp.realm_state),
    fn(arguments) {
      if arguments.length() > 0 {
        match arguments[0] {
          @runtime.Number(value) =>
            host_binding.cancel_scheduled_turn(value.to_int())
          _ => ()
        }
      }
      @runtime.Undefined
    },
  )
  self.install_host_global("setTimeout", set_timeout)
  self.install_host_global("clearTimeout", clear_timeout)
}

///|
fn Engine::for_host_environment(
  annex_b : Bool,
  console_enabled : Bool,
  console_output_sink : ((ConsoleOutputKind, String) -> Unit raise Error)?,
) -> Engine {
  let engine : Engine = {
    interp: @interpreter.new_interpreter(
      annex_b~,
      console_enabled~,
      console_output_sink~,
      setup_test262_harness=false,
    ),
  }
  for name in ["setTimeout", "clearTimeout", "setInterval", "clearInterval"] {
    ignore(engine.interp.global.bindings.remove(name))
  }
  engine
}

///|
fn Engine::run_scheduled_callback_diagnostic(
  self : Engine,
  scheduled : ScheduledCallback,
) -> Result[Unit, EngineDiagnostic] {
  let observed = @runtime.observe_source_failure(self.interp.realm_state, fn() raise {
    ignore(
      self.interp.call_value(
        scheduled.callback,
        @runtime.Undefined,
        scheduled.arguments,
        @token.Loc::default(),
      ),
    )
  })
  match observed {
    Ok(_) => Ok(())
    Err(failure) =>
      Err(
        runtime_engine_diagnostic(
          failure.cause(),
          operation="scheduled-turn",
          phase="callback",
          source_identity=failure.source_identity(),
          javascript_integrity=EngineIntegrity::Reusable,
          javascript_effects=RetainedEffects::MayRemain,
          javascript_jobs=self.pending_jobs_snapshot(),
          internal_integrity=EngineIntegrity::Discard,
        ),
      )
  }
}

///|
/// Create a new Execution Session with an independent Hosted Realm.
pub fn HostEnvironment::create_session(
  self : HostEnvironment,
  bindings? : SessionBindings = SessionBindings(),
) -> ExecutionSession raise SessionCreationError {
  guard self.console || bindings.console_output_sink is None else {
    raise BindingForAbsentCapability("Console")
  }
  guard self.script_resources || bindings.script_resource_resolver is None else {
    raise BindingForAbsentCapability("Script Resources")
  }
  guard !self.script_resources || bindings.script_resource_resolver is Some(_) else {
    raise MissingBindingForCapability("Script Resources")
  }
  guard self.timers || bindings.timer_scheduler is None else {
    raise BindingForAbsentCapability("Timers")
  }
  guard !self.timers || bindings.timer_scheduler is Some(_) else {
    raise MissingBindingForCapability("Timers")
  }
  let host_binding = SessionHostBinding(bindings)
  let console_output_sink = if self.console {
    Some(fn(kind, text) raise {
      host_binding.emit_console_output(ConsoleOutput(kind~, text~))
    })
  } else {
    None
  }
  let engine = Engine::for_host_environment(
    self.annex_b,
    self.console,
    console_output_sink,
  )
  if self.script_resources {
    engine.install_script_resource_loader(host_binding)
  }
  if self.timers {
    engine.install_timer_scheduler(host_binding)
  }
  ExecutionSession(engine, host_binding)
}

///|
priv enum ExecutionSessionState {
  Available
  Running
  Closed
  Faulted
}

///|
fn execution_session_state_after_integrity(
  integrity : EngineIntegrity,
) -> ExecutionSessionState {
  match integrity {
    EngineIntegrity::Reusable => Available
    EngineIntegrity::Discard
    | EngineIntegrity::Unknown
    | EngineIntegrity::NotApplicable => Faulted
  }
}

///|
fn[T] execution_session_should_checkpoint(
  result : Result[T, EngineDiagnostic],
) -> Bool {
  match result {
    Ok(_) => true
    Err(diagnostic) =>
      diagnostic.engine_integrity() is EngineIntegrity::Reusable
  }
}

///|
/// One mutable JavaScript execution state created from a Host Environment.
pub struct ExecutionSession {
  priv engine : Engine
  priv host_binding : SessionHostBinding
  priv mut state : ExecutionSessionState
}

///|
fn ExecutionSession::ExecutionSession(
  engine : Engine,
  host_binding : SessionHostBinding,
) -> ExecutionSession {
  { engine, host_binding, state: Available }
}

///|
fn ExecutionSession::require_available(
  self : ExecutionSession,
) -> Unit raise ExecutionSessionError {
  match self.state {
    Available => self.state = Running
    Running => raise SessionBusy
    Closed => raise SessionClosed
    Faulted => raise SessionFaulted
  }
}

///|
/// Permanently make this Execution Session unavailable for new Hosted Turns.
/// Closing a running Session is rejected and does not interrupt execution.
pub fn ExecutionSession::close(
  self : ExecutionSession,
) -> Unit raise ExecutionSessionError {
  match self.state {
    Available | Faulted => {
      self.host_binding.invalidate_scheduled_turns()
      self.state = Closed
    }
    Running => raise SessionBusy
    Closed => raise SessionClosed
  }
}

///|
fn[T] ExecutionSession::finish_turn(
  self : ExecutionSession,
  result : Result[T, EngineDiagnostic],
) -> T raise ExecutionSessionError {
  match self.host_binding.take_failure() {
    Some(failure) => {
      self.state = Faulted
      self.host_binding.invalidate_scheduled_turns()
      raise HostFailure(capability=failure.capability, detail=failure.detail)
    }
    None =>
      match result {
        Ok(value) => {
          self.state = Available
          value
        }
        Err(diagnostic) => {
          self.state = execution_session_state_after_integrity(
            diagnostic.engine_integrity(),
          )
          if self.state is Faulted {
            self.host_binding.invalidate_scheduled_turns()
          }
          raise ExecutionFailure(diagnostic)
        }
      }
  }
}

///|
fn[T] ExecutionSession::complete_running_turn(
  self : ExecutionSession,
  result : Result[T, EngineDiagnostic],
) -> T raise ExecutionSessionError {
  match self.host_binding.take_failure() {
    Some(failure) => {
      self.state = Faulted
      self.host_binding.invalidate_scheduled_turns()
      raise HostFailure(capability=failure.capability, detail=failure.detail)
    }
    None => ()
  }
  let should_checkpoint = execution_session_should_checkpoint(result)
  guard should_checkpoint else { return self.finish_turn(result) }
  let completed = match self.engine.run_microtask_checkpoint_diagnostic() {
    Ok(_) => result
    Err(diagnostic) => Err(diagnostic)
  }
  self.finish_turn(completed)
}

///|
fn[T] ExecutionSession::run_hosted_turn(
  self : ExecutionSession,
  action : () -> Result[T, EngineDiagnostic],
) -> T raise ExecutionSessionError {
  self.require_available()
  self.complete_running_turn(action())
}

///|
/// Resume one application-scheduled callback as a new Hosted Turn.
pub fn ExecutionSession::resume_scheduled_turn(
  self : ExecutionSession,
  turn : ScheduledTurn,
) -> Unit raise ExecutionSessionError {
  self.require_available()
  guard self.host_binding.take_scheduled_callback(turn) is Some(scheduled) else {
    self.state = Available
    raise ScheduledTurnUnavailable
  }
  self.complete_running_turn(
    self.engine.run_scheduled_callback_diagnostic(scheduled),
  )
}

///|
/// Evaluate source in this Execution Session's persistent Realm.
pub fn ExecutionSession::evaluate(
  self : ExecutionSession,
  source : String,
) -> Unit raise ExecutionSessionError {
  self.run_hosted_turn(() => self.engine.eval_diagnostic(source))
}

///|
/// Call a global JavaScript function through the explicit JSON Data Copy
/// boundary.
pub fn ExecutionSession::call_json(
  self : ExecutionSession,
  name : String,
  arguments : Array[Json],
) -> Json raise ExecutionSessionError {
  self.run_hosted_turn(() => self.engine.call_json_diagnostic(name, arguments))
}
