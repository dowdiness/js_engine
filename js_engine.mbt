///|
/// Opaque policy and interruption controls for the staged bounded-evaluation
/// facade. Runtime owns their invariants; the root package is the consumer API.
pub using @runtime {
  type ExecutionPolicy,
  type ExecutionPolicyError,
  type InterruptionHandle,
}

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
fn Engine::with_console_output_sink(
  annex_b : Bool,
  console_output_sink : (@runtime.ConsoleOutputKind, String) -> Unit raise Error,
) -> Engine {
  {
    interp: @interpreter.new_interpreter(
      annex_b~,
      console_output_sink=Some(console_output_sink),
    ),
  }
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
  let candidate_mode = @engine_candidate_mode.candidate_mode_enabled()
  let program = @parser.parse(source) catch {
    err => raise ParseError(err.to_string())
  }
  if candidate_mode {
    ignore(@compiler.run_candidate_program(self.interp, program.stmts)) catch {
      @runtime.JsException(value) =>
        raise JavaScriptException(value.to_string())
      err => raise classify_engine_runtime_error(err)
    }
  } else {
    ignore(self.interp.run(program.stmts)) catch {
      @runtime.JsException(value) =>
        raise JavaScriptException(value.to_string())
      err => raise classify_engine_runtime_error(err)
    }
  }
}

///|
/// Evaluate a script loaded by a host function while preserving JavaScript
/// exceptions for the currently-active execution. Parse failures become
/// JavaScript SyntaxErrors at this boundary.
fn Engine::eval_shell_loaded(self : Engine, source : String) -> Unit raise {
  let program = @parser.parse(source) catch {
    err => raise @errors.SyntaxError(message=err.to_string())
  }
  if @engine_candidate_mode.candidate_mode_enabled() {
    ignore(@compiler.run_candidate_program(self.interp, program.stmts))
  } else {
    ignore(self.interp.run(program.stmts))
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
/// Source returned by a shell host after resolving a requested script name.
/// `identity` is used as the referrer for nested `load()` calls.
pub struct LoadedScript {
  identity : String
  source : String
}

///|
pub fn LoadedScript::LoadedScript(
  identity~ : String,
  source~ : String,
) -> LoadedScript {
  { identity, source }
}

///|
fn Engine::install_shell_global(
  self : Engine,
  name : String,
  value : @runtime.Value,
) -> Unit {
  self.interp.global.def_builtin(name, value)
  self.install_host_global(name, value)
}

///|
fn Engine::make_shell_reader(
  self : Engine,
  load_source : (String, String?) -> LoadedScript raise,
  read_bytes : ((String, String?) -> Bytes raise)?,
  current_referrer : () -> String?,
) -> @runtime.Value {
  @runtime.make_native_func(
    name="read",
    length=1,
    realm_state=Some(self.interp.realm_state),
    fn(args) raise {
      guard args.length() > 0 else {
        raise @errors.TypeError(message="read() requires a file name")
      }
      let request = self.interp.to_js_string(args[0])
      let binary = args.length() > 1 &&
        self.interp.to_js_string(args[1]) == "binary"
      if binary {
        let reader = match read_bytes {
          Some(reader) => reader
          None =>
            raise @errors.InternalError(
              message="binary file reads are not available in this host",
            )
        }
        let bytes = reader(request, current_referrer()) catch {
          err =>
            raise @errors.InternalError(
              message="cannot read '\{request}': \{err}",
            )
        }
        let prototype = self.interp.global.get("[[ArrayBufferPrototype]]")
        let buffer = @stdlib.make_arraybuffer_object(
          self.interp.realm_state,
          bytes.length(),
          prototype,
        )
        let buffer_id = match @stdlib.get_buffer_id(buffer) {
          Some(buffer_id) => buffer_id
          None =>
            raise @errors.InternalError(
              message="failed to allocate ArrayBuffer",
            )
        }
        let destination = match
          @stdlib.get_arraybuffer_bytes(self.interp.realm_state, buffer_id) {
          Some(destination) => destination
          None =>
            raise @errors.InternalError(message="failed to access ArrayBuffer")
        }
        for i in 0..<bytes.length() {
          destination[i] = bytes[i].to_int()
        }
        return buffer
      }
      let loaded = load_source(request, current_referrer()) catch {
        err =>
          raise @errors.InternalError(
            message="cannot read '\{request}': \{err}",
          )
      }
      @runtime.String_(loaded.source)
    },
  )
}

///|
/// A persistent JavaScript shell realm. The host owns filesystem policy and
/// supplies script loading as a capability; the shell owns evaluation order,
/// the load stack, and JavaScript-visible host functions.
pub struct Shell {
  priv engine : Engine
  priv load_source : (String, String?) -> LoadedScript raise
  priv read_bytes : ((String, String?) -> Bytes raise)?
  priv load_stack : Array[String]
}

///|
pub fn Shell::Shell(
  load_source~ : (String, String?) -> LoadedScript raise,
  read_bytes? : ((String, String?) -> Bytes raise)? = None,
  now_millis? : (() -> Double)? = None,
  annex_b? : Bool = false,
) -> Shell {
  let shell = {
    engine: Engine(annex_b~),
    load_source,
    read_bytes,
    load_stack: [],
  }
  let load = @runtime.make_native_func(
    name="load",
    length=1,
    realm_state=Some(shell.engine.interp.realm_state),
    fn(args) raise {
      guard args.length() > 0 else {
        raise @errors.TypeError(message="load() requires a script name")
      }
      let request = shell.engine.interp.to_js_string(args[0])
      shell.load_runtime(request)
      @runtime.Undefined
    },
  )
  shell.engine.install_shell_global("load", load)
  let read = shell.engine.make_shell_reader(
    shell.load_source,
    shell.read_bytes,
    () => shell.load_referrer(),
  )
  shell.engine.install_shell_global("read", read)
  shell.engine.install_shell_global("readFile", read)
  let run_string = @runtime.make_native_func(
    name="runString",
    length=1,
    realm_state=Some(shell.engine.interp.realm_state),
    fn(args) raise {
      let source = if args.length() == 0 {
        ""
      } else {
        shell.engine.interp.to_js_string(args[0])
      }
      let child = Engine::with_console_output_sink(annex_b, fn(
        kind,
        text,
      ) raise {
        shell.engine.interp.host.emit_console_output(kind, text)
      })
      let child_load_stack : Array[String] = []
      let child_referrer = () => {
        if child_load_stack.length() == 0 {
          shell.load_referrer()
        } else {
          Some(child_load_stack[child_load_stack.length() - 1])
        }
      }
      let child_read = child.make_shell_reader(
        shell.load_source,
        shell.read_bytes,
        child_referrer,
      )
      let load_string = @runtime.make_native_func(
        name="loadString",
        length=1,
        realm_state=Some(child.interp.realm_state),
        fn(load_args) raise {
          guard load_args.length() > 0 else {
            raise @errors.TypeError(message="loadString() requires source text")
          }
          let loaded_source = child.interp.to_js_string(load_args[0])
          child.eval_shell_loaded(loaded_source)
          @runtime.Undefined
        },
      )
      let child_load = @runtime.make_native_func(
        name="load",
        length=1,
        realm_state=Some(child.interp.realm_state),
        fn(load_args) raise {
          guard load_args.length() > 0 else {
            raise @errors.TypeError(message="load() requires a script name")
          }
          let request = child.interp.to_js_string(load_args[0])
          let referrer = child_referrer()
          let loaded = (shell.load_source)(request, referrer) catch {
            err =>
              raise @errors.InternalError(
                message="cannot load '\{request}': \{err}",
              )
          }
          child_load_stack.push(loaded.identity)
          let evaluated : Result[Unit, Error] = Ok(
            child.eval_shell_loaded(loaded.source),
          ) catch {
            err => Err(err)
          }
          ignore(child_load_stack.pop())
          match evaluated {
            Ok(_) => @runtime.Undefined
            Err(err) => raise err
          }
        },
      )
      child.install_shell_global("loadString", load_string)
      child.install_shell_global("load", child_load)
      child.install_shell_global("read", child_read)
      child.install_shell_global("readFile", child_read)
      child.eval_shell_loaded(source)
      child.interp.global_this
    },
  )
  shell.engine.install_shell_global("runString", run_string)
  match now_millis {
    Some(clock) => {
      let now = @runtime.make_native_func(
        name="now",
        realm_state=Some(shell.engine.interp.realm_state),
        fn(_args) { @runtime.Number(clock()) },
      )
      let mark = @runtime.make_native_func(
        name="mark",
        length=1,
        realm_state=Some(shell.engine.interp.realm_state),
        fn(_args) { @runtime.Undefined },
      )
      let measure = @runtime.make_native_func(
        name="measure",
        length=1,
        realm_state=Some(shell.engine.interp.realm_state),
        fn(_args) { @runtime.Undefined },
      )
      let performance = @runtime.make_host_object(
        name="Performance",
        proto=@runtime.get_obj_proto(
          realm_state=Some(shell.engine.interp.realm_state),
        ),
        methods=Map::from_array([
          ("now", now),
          ("mark", mark),
          ("measure", measure),
        ]),
      )
      shell.engine.install_shell_global("performance", performance)
    }
    None => ()
  }
  shell
}

///|
fn Shell::load_referrer(self : Shell) -> String? {
  if self.load_stack.length() == 0 {
    None
  } else {
    Some(self.load_stack[self.load_stack.length() - 1])
  }
}

///|
fn Shell::load(self : Shell, request : String) -> Unit raise EngineError {
  let referrer = self.load_referrer()
  let loaded = (self.load_source)(request, referrer) catch {
    err => raise InternalError("cannot load '\{request}': \{err}")
  }
  self.load_stack.push(loaded.identity)
  let evaluated : Result[Unit, EngineError] = Ok(
    self.engine.eval(loaded.source),
  ) catch {
    err => Err(err)
  }
  ignore(self.load_stack.pop())
  match evaluated {
    Ok(_) => ()
    Err(err) => raise err
  }
}

///|
/// `load()` runs inside an active JavaScript call. Keep runtime exceptions in
/// their native form so the outer evaluation reports the original JS error.
fn Shell::load_runtime(self : Shell, request : String) -> Unit raise {
  let referrer = self.load_referrer()
  let loaded = (self.load_source)(request, referrer) catch {
    err =>
      raise @errors.InternalError(message="cannot load '\{request}': \{err}")
  }
  self.load_stack.push(loaded.identity)
  let evaluated : Result[Unit, Error] = Ok(
    self.engine.eval_shell_loaded(loaded.source),
  ) catch {
    err => Err(err)
  }
  ignore(self.load_stack.pop())
  match evaluated {
    Ok(_) => ()
    Err(err) => raise err
  }
}

///|
/// Resolve and execute a script as the shell entry point.
pub fn Shell::run_file(self : Shell, path : String) -> Unit raise EngineError {
  self.load(path)
}

///|
/// Evaluate source in the shell's persistent realm without changing the load
/// referrer. This is the implementation of the command-line `-e` mode.
pub fn Shell::eval(self : Shell, source : String) -> Unit raise EngineError {
  self.engine.eval(source)
}

///|
/// Install command-line arguments without parsing an extra JavaScript setup
/// program. `arguments` follows d8/JSC and excludes the script name;
/// `scriptArgs` follows QuickJS and includes it as element zero.
pub fn Shell::set_arguments(
  self : Shell,
  script_name : String,
  args : Array[String],
) -> Unit raise EngineError {
  let arguments_json = Json::array(args.map(arg => Json::string(arg)))
  let script_args : Array[String] = [script_name]
  for arg in args {
    script_args.push(arg)
  }
  let script_args_json = Json::array(script_args.map(arg => Json::string(arg)))
  let arguments = @runtime.json_to_realm_value(
    self.engine.interp.realm_state,
    arguments_json,
  ) catch {
    @runtime.JsonBridgeFailure(message) => raise JsonConversionError(message)
  }
  let script_arguments = @runtime.json_to_realm_value(
    self.engine.interp.realm_state,
    script_args_json,
  ) catch {
    @runtime.JsonBridgeFailure(message) => raise JsonConversionError(message)
  }
  self.engine.interp.global.def_builtin("arguments", arguments)
  self.engine.interp.global.def_builtin("scriptArgs", script_arguments)
  ignore(
    self.engine.interp.set_property(
      self.engine.interp.global_this,
      "arguments",
      arguments,
      @token.Loc::default(),
    ),
  ) catch {
    err => raise classify_engine_runtime_error(err)
  }
  ignore(
    self.engine.interp.set_property(
      self.engine.interp.global_this,
      "scriptArgs",
      script_arguments,
      @token.Loc::default(),
    ),
  ) catch {
    err => raise classify_engine_runtime_error(err)
  }
}

///|
pub fn Shell::take_output(self : Shell) -> Array[String] {
  self.engine.take_output()
}

///|
pub fn Shell::drain_jobs(self : Shell) -> Unit raise EngineError {
  while self.engine.has_pending_microtasks() {
    ignore(self.engine.run_microtask_checkpoint())
  }
  self.engine.run_timer_checkpoint()
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
