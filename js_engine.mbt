///|
pub fn run(
  source : String,
  annex_b? : Bool = false,
) -> (Array[String], String) raise Error {
  let interp = @interpreter.new_interpreter(annex_b~)
  let prog = @parser.parse(source)
  let result = interp.run(prog.stmts)
  // Drain microtask queue after script execution
  // This implements the event loop checkpoint per WHATWG spec
  interp.run_microtasks()
  // Process timer task queue with microtask checkpoints between each
  interp.run_timers()
  (interp.host.output, result.to_string())
}

///|
/// Run JavaScript source through the opt-in closure-conversion prototype.
///
/// The normal `run` facade remains the default interpreter path. This entry
/// point parses once, compiles the supported script subset to executable
/// closures, then runs it with the same event-loop drain behavior as `run`.
pub fn run_compiled(
  source : String,
  annex_b? : Bool = false,
) -> (Array[String], String) raise Error {
  let interp = @interpreter.new_interpreter(annex_b~)
  let prog = @parser.parse(source)
  let compiled = @compiler.compile_script_to_closure(prog.stmts)
  let result = compiled(interp)
  interp.run_microtasks()
  interp.run_timers()
  (interp.host.output, result.to_string())
}

///|
/// Run JavaScript source with event loop support
/// This version allows the host to control microtask and timer execution timing
pub fn run_with_event_loop(
  source : String,
  annex_b? : Bool = false,
) -> (@interpreter.Interpreter, @interpreter.Value) raise Error {
  let interp = @interpreter.new_interpreter(annex_b~)
  let prog = @parser.parse(source)
  let result = interp.run(prog.stmts)
  // Return interpreter to allow host to manage event loop
  (interp, result)
}

///|
/// Check if there are pending microtasks in the queue
pub fn has_pending_microtasks(interp : @interpreter.Interpreter) -> Bool {
  interp.host.microtask_queue.length() > 0
}

///|
/// Check if there are pending timers in the queue
pub fn has_pending_timers(interp : @interpreter.Interpreter) -> Bool {
  interp.host.timer_queue.length() > 0
}

///|
/// Run a single microtask checkpoint
/// Returns true if there are more microtasks to process
pub fn run_microtask_checkpoint(
  interp : @interpreter.Interpreter,
) -> Bool raise Error {
  interp.run_microtasks()
  interp.host.microtask_queue.length() > 0
}

///|
/// Run all pending timers with microtask draining between each
pub fn run_timer_checkpoint(
  interp : @interpreter.Interpreter,
) -> Unit raise Error {
  interp.run_timers()
}

///|
/// Stable errors raised by the stateful Engine facade.
pub(all) suberror EngineError {
  ParseError(String)
  JavaScriptException(String)
  MissingGlobal(String)
  NotCallable(String)
  JsonConversionError(String)
  InternalError(String)
} derive(Debug)

///|
pub impl Show for EngineError with fn output(self, logger) {
  let (name, message) = match self {
    ParseError(message) => ("ParseError", message)
    JavaScriptException(message) => ("JavaScriptException", message)
    MissingGlobal(message) => ("MissingGlobal", message)
    NotCallable(message) => ("NotCallable", message)
    JsonConversionError(message) => ("JsonConversionError", message)
    InternalError(message) => ("InternalError", message)
  }
  logger.write_string(name)
  logger.write_string(": ")
  logger.write_string(message)
}

///|
/// A persistent JavaScript realm for repeated evaluation and JSON calls.
pub struct Engine {
  interp : @interpreter.Interpreter
}

///|
pub fn Engine::Engine(annex_b? : Bool = false) -> Engine {
  { interp: @interpreter.new_interpreter(annex_b~) }
}

///|
fn classify_engine_runtime_error(err : Error) -> EngineError {
  match @errors.name_message_if_js_error(err) {
    Some(("InternalError", message)) => InternalError(message)
    Some((name, message)) => JavaScriptException(name + ": " + message)
    None => InternalError(err.to_string())
  }
}

///|
pub fn Engine::eval(self : Engine, source : String) -> Unit raise EngineError {
  let program = @parser.parse(source) catch {
    err => raise ParseError(err.to_string())
  }
  ignore(self.interp.run(program.stmts)) catch {
    @runtime.JsException(value) => raise JavaScriptException(value.to_string())
    err => raise classify_engine_runtime_error(err)
  }
}

///|
fn Engine::get_global_export(
  self : Engine,
  name : String,
) -> @runtime.Value raise EngineError {
  let has_binding = self.interp.global.has(name) catch {
    err => raise classify_engine_runtime_error(err)
  }
  if has_binding {
    return self.interp.global.get(name) catch {
      err => raise classify_engine_runtime_error(err)
    }
  }
  let own_property = self.interp.get_own_property(
    self.interp.global_this,
    @runtime.String_(name),
  ) catch {
    @runtime.JsException(value) => raise JavaScriptException(value.to_string())
    err => raise classify_engine_runtime_error(err)
  }
  guard own_property is Some(_) else { raise MissingGlobal(name) }
  self.interp.get_property(self.interp.global_this, name, @token.Loc::default()) catch {
    @runtime.JsException(value) => raise JavaScriptException(value.to_string())
    err => raise classify_engine_runtime_error(err)
  }
}

///|
pub fn Engine::call_json(
  self : Engine,
  name : String,
  args : Array[Json],
) -> Json raise EngineError {
  let callee = self.get_global_export(name)
  guard @runtime.is_callable(callee) else { raise NotCallable(name) }
  let runtime_args : Array[@runtime.Value] = []
  for arg in args {
    let converted = @runtime.json_to_realm_value(self.interp.realm_state, arg) catch {
      @runtime.JsonBridgeFailure(message) => raise JsonConversionError(message)
    }
    runtime_args.push(converted)
  }
  let result = self.interp.call_value(
    callee,
    @runtime.Undefined,
    runtime_args,
    @token.Loc::default(),
  ) catch {
    @runtime.JsException(value) => raise JavaScriptException(value.to_string())
    err => raise classify_engine_runtime_error(err)
  }
  @runtime.realm_value_to_json(self.interp.realm_state, result) catch {
    @runtime.JsonBridgeFailure(message) => raise JsonConversionError(message)
  }
}

///|
pub fn Engine::take_output(self : Engine) -> Array[String] {
  let output = self.interp.host.output.copy()
  self.interp.host.output.clear()
  output
}

///|
pub fn Engine::has_pending_microtasks(self : Engine) -> Bool {
  self.interp.host.microtask_queue.length() > 0
}

///|
pub fn Engine::has_pending_timers(self : Engine) -> Bool {
  self.interp.host.timer_queue.length() > 0
}

///|
pub fn Engine::run_microtask_checkpoint(
  self : Engine,
) -> Bool raise EngineError {
  self.interp.run_microtasks() catch {
    @runtime.JsException(value) => raise JavaScriptException(value.to_string())
    err => raise classify_engine_runtime_error(err)
  }
  self.has_pending_microtasks()
}

///|
pub fn Engine::run_timer_checkpoint(self : Engine) -> Unit raise EngineError {
  self.interp.run_timers() catch {
    @runtime.JsException(value) => raise JavaScriptException(value.to_string())
    err => raise classify_engine_runtime_error(err)
  }
}

///|
/// Run a JavaScript module source and return its exports
/// The module is executed in strict mode and its exports are collected
pub fn run_module(
  source : String,
  annex_b? : Bool = false,
) -> (Array[String], Map[String, @interpreter.Value]) raise Error {
  let interp = @interpreter.new_interpreter(annex_b~)
  let prog = @parser.parse(source)
  let exports = interp.run_module(prog.stmts)
  interp.run_microtasks()
  interp.run_timers()
  (interp.host.output, exports)
}

///|
/// Run multiple modules with dependency resolution.
/// The runtime graph runner pre-registers every module specifier before
/// instantiation/evaluation, so callers do not need to order modules by
/// dependency. Returns the exports of the last module.
pub fn run_modules(
  modules : Array[(String, String)],
  annex_b? : Bool = false,
) -> (Array[String], Map[String, @interpreter.Value]) raise Error {
  let interp = @interpreter.new_interpreter(annex_b~)
  let last_exports = interp.run_modules(modules)
  interp.run_microtasks()
  interp.run_timers()
  (interp.host.output, last_exports)
}
