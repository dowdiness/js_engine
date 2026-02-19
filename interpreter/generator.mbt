///|
/// Generator state machine
pub(all) enum GenState {
  SuspendedStart // Created but body not yet started
  Executing // Currently running (re-entrancy guard)
  SuspendedYield // Suspended at a yield point
  Completed // Body finished or abruptly completed
}

///|
/// How the generator was resumed
pub(all) enum ResumeKind {
  Next(Value) // .next(v)
  Throw(Value) // .throw(e)
  Return(Value) // .return(v)
}

///|
/// Resume action for eval_yield to inspect when replaying
pub(all) enum ResumeAction {
  NextAction // deliver yield_value normally
  ThrowAction(Value) // inject throw at yield point
  ReturnAction(Value) // inject return at yield point
}

///|
/// Generator object stored as internal data on an ObjectData
pub(all) struct GeneratorObject {
  id : Int // generator object ID for cleanup
  mut state : GenState
  // The interpreter, body, params, closure, etc. needed to execute
  body : Array[@ast.Stmt]
  params : Array[String] // simple params
  params_ext : Array[@ast.Param]? // extended params (with defaults)
  rest_param : String?
  closure : Environment
  name : String?
  interpreter : Interpreter
  args : Array[Value] // arguments passed when generator function was called
  this_val : Value // this value at call time
  // Step engine state
  mut env : Environment? // execution environment (created on first .next())
  mut pc : Int // program counter: index into body
  mut yield_value : Value // value to be returned by yield expression on resume
  // Resume replay state
  mut resuming : Bool // true when replaying a statement to deliver resume value
  mut resume_action : ResumeAction // what to do when eval_yield is hit during replay
  // Try/catch/finally resume tracking
  // -1 = no saved phase, 0 = try body, 1 = catch body, 2 = finally body
  mut try_resume_phase : Int
  mut try_resume_error : Value // saved error value when resuming in catch
  mut try_resume_result : Signal // saved try/catch result when resuming in finally
  mut try_resume_pending_error : Error? // saved non-catchable error for finally
  // Loop resume tracking — stack of saved loop envs (innermost first, outermost last)
  loop_env_stack : Array[Environment]
  // For-of resume state
  mut for_of_iterator : Value // saved iterator object
  mut for_of_next : Value // saved next method
  mut for_of_resume : Bool // true if resuming inside for-of
  // yield* delegation state
  mut delegate_iterator : Value // the delegate iterator (or Undefined if not delegating)
  mut delegate_next : Value // the delegate's next method
  mut delegating : Bool // true if currently in yield* delegation
}

///|
/// Create iterator result { value, done }
fn make_iterator_result(value : Value, done : Bool) -> Value {
  let props : Map[String, Value] = {}
  props["value"] = value
  props["done"] = Bool(done)
  Object({
    properties: props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Object",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Get or create %GeneratorPrototype% for the given interpreter.
/// We create a new prototype each time to avoid stale symbol IDs
/// across interpreter instances (each test creates a new interpreter).
fn get_generator_prototype(_interp : Interpreter) -> Value {
  init_generator_prototype()
}

///|
/// Global map: generator object ID -> GeneratorObject
let generator_objects : Map[Int, GeneratorObject] = {}

///|
/// Counter for generator object IDs
let gen_id_counter : Ref[Int] = { val: 0 }

///|
/// Allocate a new generator object ID
fn next_gen_id() -> Int {
  let id = gen_id_counter.val
  gen_id_counter.val = id + 1
  id
}

///|
/// Mark generator as completed and remove from global map to free resources
fn complete_generator(gen : GeneratorObject) -> Unit {
  gen.state = Completed
  // Clear references to reduce memory pressure while keeping
  // the object in the map so subsequent .next/.throw/.return calls
  // correctly return {done: true} instead of "incompatible receiver".
  gen.env = None
  gen.delegate_iterator = Undefined
  gen.delegate_next = Undefined
  gen.for_of_iterator = Undefined
  gen.for_of_next = Undefined
  gen.loop_env_stack.clear()
  // Clear mutable fields to allow GC
  // Note: body/args/closure/this_val are immutable and may be shared
  // across generator instances from the same function, so leave them.
  gen.yield_value = Undefined
  gen.try_resume_error = Undefined
  gen.try_resume_result = Normal(Undefined)
  gen.try_resume_pending_error = None
}

///|
/// Global reference to currently executing generator (for eval_yield to access)
let current_generator : Ref[GeneratorObject?] = { val: None }

///|
/// Initialize %GeneratorPrototype% with next, throw, return methods
fn init_generator_prototype() -> Value {
  let iterator_sym = get_iterator_symbol()
  let props : Map[String, Value] = {}
  let sym_props : Map[Int, Value] = {}
  let descs : Map[String, PropDescriptor] = {}

  // .next(value)
  props["next"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("next", fn(ip, this_val, args) raise {
        let arg = if args.length() > 0 { args[0] } else { Undefined }
        generator_resume(ip, this_val, Next(arg))
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  descs["next"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }

  // .throw(exception)
  props["throw"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("throw", fn(ip, this_val, args) raise {
        let arg = if args.length() > 0 { args[0] } else { Undefined }
        generator_resume(ip, this_val, Throw(arg))
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  descs["throw"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }

  // .return(value)
  props["return"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("return", fn(ip, this_val, args) raise {
        let arg = if args.length() > 0 { args[0] } else { Undefined }
        generator_resume(ip, this_val, Return(arg))
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  descs["return"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }

  // [Symbol.iterator]() { return this; }
  sym_props[iterator_sym.id] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("[Symbol.iterator]", fn(this_val, _args) { this_val }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  Object({
    properties: props,
    symbol_properties: sym_props,
    prototype: Null,
    callable: None,
    class_name: "Generator",
    descriptors: descs,
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Set up the GeneratorFunction constructor on the given interpreter.
/// GeneratorFunction("a", "yield a") creates a generator function,
/// analogous to Function("a", "return a") for regular functions.
pub fn setup_generator_function_constructor(
  env : Environment,
  global_this : Value,
) -> Unit {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  // %GeneratorFunction.prototype% inherits from Function.prototype
  let func_proto : Value = match env.bindings.get("[[FunctionPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
  let gen_func_proto : Value = Object({
    properties: {},
    symbol_properties: {},
    prototype: func_proto,
    callable: None,
    class_name: "GeneratorFunction",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  // GeneratorFunction constructor: GeneratorFunction(p1, p2, ..., body)
  let gen_func_ctor : Value = Object({
    properties: { "length": Number(1.0), "prototype": gen_func_proto, "name": String_("GeneratorFunction") },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("GeneratorFunction", fn(interp, _this, args) raise {
        if args.length() == 0 {
          // No arguments: return empty generator function
          return interp.make_generator_function(
            Some("anonymous"),
            [],
            None,
            [],
            interp.global,
          )
        }
        // Last arg is body, previous args are parameter names
        let body_str = match args[args.length() - 1] {
          String_(s) => s
          _ => args[args.length() - 1].to_string()
        }
        let param_parts : Array[String] = []
        for i = 0; i < args.length() - 1; i = i + 1 {
          match args[i] {
            String_(s) => param_parts.push(s)
            _ => param_parts.push(args[i].to_string())
          }
        }
        let params_str = param_parts.join(",")
        let source = "function* anonymous(" +
          params_str +
          ") {\n" +
          body_str +
          "\n}"
        let prog = @parser.parse(source)
        if prog.stmts.length() > 0 {
          match prog.stmts[0] {
            GeneratorDecl(_, params, body, _) =>
              return interp.make_generator_function(
                Some("anonymous"),
                params,
                None,
                body,
                interp.global,
              )
            GeneratorDeclExt(_, params, rest_param, body, _) =>
              return interp.make_generator_function_ext(
                Some("anonymous"),
                params,
                rest_param,
                body,
                interp.global,
              )
            _ => ()
          }
        }
        // Fallback: empty generator function
        interp.make_generator_function(
          Some("anonymous"),
          [],
          None,
          [],
          interp.global,
        )
      }),
    ),
    class_name: "Function",
    descriptors: { "name": nf_desc, "length": nf_desc },
    symbol_descriptors: {},
    extensible: true,
  })
  // Set up prototype chain: GeneratorFunction.prototype.constructor = GeneratorFunction
  match gen_func_proto {
    Object(data) => data.properties["constructor"] = gen_func_ctor
    _ => ()
  }
  // Mirror onto globalThis
  match global_this {
    Object(data) => data.properties["GeneratorFunction"] = gen_func_ctor
    _ => ()
  }
  env.def_builtin("GeneratorFunction", gen_func_ctor)
  env.def_builtin("[[GeneratorFunctionPrototype]]", gen_func_proto)
}

///|
/// Yield signal — used to suspend generator execution
pub suberror YieldSignal {
  YieldSignal(Value) // the yielded value
}

///|
/// Generator return signal — used to inject return at yield point
/// This is NOT JS-catchable, but must trigger finally blocks.
pub suberror GeneratorReturnSignal {
  GeneratorReturnSignal(Value)
}

///|
/// Create a generator function value (simple params)
fn Interpreter::make_generator_function(
  self : Interpreter,
  name : String?,
  params : Array[String],
  rest_param : String?,
  body : Array[@ast.Stmt],
  closure : Environment,
) -> Value {
  let interp = self
  let gen_proto = get_generator_prototype(interp)
  // Create the generator function's own .prototype (instances inherit from it)
  let func_prototype = Object({
    properties: {},
    symbol_properties: {},
    prototype: gen_proto,
    callable: None,
    class_name: "Generator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  // Generator functions inherit from %GeneratorFunction.prototype%
  let gen_func_proto : Value = match
    interp.global.bindings.get("[[GeneratorFunctionPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
  let fn_props : Map[String, Value] = {}
  fn_props["prototype"] = func_prototype
  Object({
    properties: fn_props,
    symbol_properties: {},
    prototype: gen_func_proto,
    callable: Some(
      InterpreterCallable(
        match name {
          Some(n) => n
          None => "anonymous"
        },
        fn(ip, this_val, args) {
          create_generator_instance(
            ip,
            this_val,
            args,
            name,
            params,
            None,
            rest_param,
            body,
            closure,
            func_prototype,
          )
        },
      ),
    ),
    class_name: "GeneratorFunction",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Create a generator function value (extended params)
fn Interpreter::make_generator_function_ext(
  self : Interpreter,
  name : String?,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
  closure : Environment,
) -> Value {
  let interp = self
  let gen_proto = get_generator_prototype(interp)
  let func_prototype = Object({
    properties: {},
    symbol_properties: {},
    prototype: gen_proto,
    callable: None,
    class_name: "Generator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  // Generator functions inherit from %GeneratorFunction.prototype%
  let gen_func_proto : Value = match
    interp.global.bindings.get("[[GeneratorFunctionPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
  let fn_props : Map[String, Value] = {}
  fn_props["prototype"] = func_prototype
  Object({
    properties: fn_props,
    symbol_properties: {},
    prototype: gen_func_proto,
    callable: Some(
      InterpreterCallable(
        match name {
          Some(n) => n
          None => "anonymous"
        },
        fn(ip, this_val, args) {
          create_generator_instance(
            ip,
            this_val,
            args,
            name,
            [],
            Some(params),
            rest_param,
            body,
            closure,
            func_prototype,
          )
        },
      ),
    ),
    class_name: "GeneratorFunction",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Create a generator instance when a generator function is called
fn create_generator_instance(
  interp : Interpreter,
  this_val : Value,
  args : Array[Value],
  name : String?,
  params : Array[String],
  params_ext : Array[@ast.Param]?,
  rest_param : String?,
  body : Array[@ast.Stmt],
  closure : Environment,
  func_prototype : Value,
) -> Value {
  let gen_id = next_gen_id()
  let gen_obj : GeneratorObject = {
    id: gen_id,
    state: SuspendedStart,
    body,
    params,
    params_ext,
    rest_param,
    closure,
    name,
    interpreter: interp,
    args,
    this_val,
    env: None,
    pc: 0,
    yield_value: Undefined,
    resuming: false,
    resume_action: NextAction,
    try_resume_phase: -1,
    try_resume_error: Undefined,
    try_resume_result: Normal(Undefined),
    try_resume_pending_error: None,
    loop_env_stack: [],
    for_of_iterator: Undefined,
    for_of_next: Undefined,
    for_of_resume: false,
    delegate_iterator: Undefined,
    delegate_next: Undefined,
    delegating: false,
  }
  generator_objects[gen_id] = gen_obj
  // Create the generator instance object with gen_id stored in a property
  let props : Map[String, Value] = {}
  props["<gen_id>"] = Number(gen_id.to_double())
  Object({
    properties: props,
    symbol_properties: {},
    prototype: func_prototype,
    callable: None,
    class_name: "Generator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Get GeneratorObject from a generator instance Value
fn get_generator_object(this_val : Value) -> GeneratorObject? {
  match this_val {
    Object(data) =>
      match data.properties.get("<gen_id>") {
        Some(Number(id)) => generator_objects.get(id.to_int())
        _ => None
      }
    _ => None
  }
}

///|
/// Resume generator execution
fn generator_resume(
  interp : Interpreter,
  this_val : Value,
  resume_kind : ResumeKind,
) -> Value raise Error {
  let gen = match get_generator_object(this_val) {
    Some(g) => g
    None =>
      raise @errors.TypeError(
        message="Method next/throw/return called on incompatible receiver",
      )
  }
  match gen.state {
    Executing => raise @errors.TypeError(message="Generator is already running")
    Completed =>
      match resume_kind {
        Next(_) => make_iterator_result(Undefined, true)
        Return(v) => make_iterator_result(v, true)
        Throw(e) => raise JsException(e)
      }
    SuspendedStart =>
      match resume_kind {
        Next(_) => {
          // Start execution of generator body
          gen.state = Executing
          generator_start(interp, gen)
        }
        Throw(e) => {
          // .throw(e) on SuspendedStart: complete generator and throw
          complete_generator(gen)
          raise JsException(e)
        }
        Return(v) => {
          // .return(v) on SuspendedStart: complete generator and return done
          complete_generator(gen)
          make_iterator_result(v, true)
        }
      }
    SuspendedYield =>
      if gen.delegating {
        // Forward to delegate iterator
        gen.state = Executing
        delegate_resume(interp, gen, resume_kind)
      } else {
        match resume_kind {
          Next(v) => {
            gen.state = Executing
            gen.yield_value = v
            gen.resume_action = NextAction
            generator_continue(interp, gen)
          }
          Throw(e) => {
            gen.state = Executing
            gen.yield_value = Undefined
            gen.resume_action = ThrowAction(e)
            generator_continue(interp, gen)
          }
          Return(v) => {
            gen.state = Executing
            gen.yield_value = v
            gen.resume_action = ReturnAction(v)
            generator_continue(interp, gen)
          }
        }
      }
  }
}

///|
/// Start generator body execution (first .next() call)
fn generator_start(
  interp : Interpreter,
  gen : GeneratorObject,
) -> Value raise Error {
  // Create execution environment
  let func_env = Environment::new(parent=Some(gen.closure))
  func_env.is_var_scope = true
  func_env.def("this", gen.this_val, LetBinding)
  func_env.def("<new.target>", Undefined, LetBinding)
  // Bind parameters
  match gen.params_ext {
    Some(params_ext) => {
      // Extended params with defaults (aligned with UserFuncExt semantics)
      let mut effective_count = 0
      for i = 0; i < params_ext.length(); i = i + 1 {
        let param = params_ext[i]
        // Skip rest destructuring params - they're bound via rest_param
        if gen.rest_param is Some(rn) && param.name == rn {
          continue
        }
        let val : Value = if effective_count < gen.args.length() &&
          not(gen.args[effective_count] is Undefined) {
          gen.args[effective_count]
        } else {
          match param.default_val {
            Some(d) => interp.eval_expr(d, func_env)
            None =>
              if effective_count < gen.args.length() {
                gen.args[effective_count]
              } else {
                Undefined
              }
          }
        }
        func_env.def(param.name, val, LetBinding)
        // Destructure if pattern param
        match param.pattern {
          Some(pat) => interp.bind_pattern(pat, val, func_env, LetBinding)
          None => ()
        }
        effective_count = effective_count + 1
      }
      // Rest param
      match gen.rest_param {
        Some(rp) => {
          let rest_elems : Array[Value] = []
          for i = effective_count; i < gen.args.length(); i = i + 1 {
            rest_elems.push(gen.args[i])
          }
          let rest_val = Array({ elements: rest_elems })
          func_env.def(rp, rest_val, LetBinding)
          // Apply destructuring pattern if present
          for p in params_ext {
            if p.name == rp {
              match p.pattern {
                Some(pat) =>
                  interp.bind_pattern(pat, rest_val, func_env, LetBinding)
                None => ()
              }
              break
            }
          }
        }
        None => ()
      }
    }
    None => {
      // Simple params
      for i = 0; i < gen.params.length(); i = i + 1 {
        let val = if i < gen.args.length() { gen.args[i] } else { Undefined }
        func_env.def(gen.params[i], val, LetBinding)
      }
      // Bind rest param if present
      match gen.rest_param {
        Some(rp) => {
          let rest_elems : Array[Value] = []
          for i = gen.params.length(); i < gen.args.length(); i = i + 1 {
            rest_elems.push(gen.args[i])
          }
          func_env.def(rp, Array({ elements: rest_elems }), LetBinding)
        }
        None => ()
      }
    }
  }
  // Create arguments object
  let args_props : Map[String, Value] = {}
  for i = 0; i < gen.args.length(); i = i + 1 {
    args_props[i.to_string()] = gen.args[i]
  }
  args_props["length"] = Number(gen.args.length().to_double())
  func_env.def(
    "arguments",
    Object({
      properties: args_props,
      symbol_properties: {},
      prototype: Null,
      callable: None,
      class_name: "Arguments",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    }),
    VarBinding,
  )
  // Hoist declarations
  interp.hoist_declarations(gen.body, func_env)
  // Store env for later resumption
  gen.env = Some(func_env)
  // Execute generator body, catching yields
  run_generator_body(interp, gen, func_env)
}

///|
/// Run generator body, handling yields.
/// On initial execution, statements run from gen.pc forward.
/// When a YieldSignal is caught, the generator suspends.
/// On resume, the SAME statement is re-executed with gen.resuming=true,
/// so that eval_yield returns the resume value instead of yielding again.
fn run_generator_body(
  interp : Interpreter,
  gen : GeneratorObject,
  env : Environment,
) -> Value raise Error {
  // Save and set the current generator context
  let prev_gen = current_generator.val
  current_generator.val = Some(gen)
  let result = try {
    let mut last_val : Value = Undefined
    while gen.pc < gen.body.length() {
      let i = gen.pc
      let stmt = gen.body[i]
      let signal = interp.exec_stmt(stmt, env) catch {
        YieldSignal(yielded_value) => {
          // Statement yielded. DON'T advance pc — on resume we'll replay this stmt.
          gen.state = SuspendedYield
          current_generator.val = prev_gen
          return make_iterator_result(yielded_value, false)
        }
        GeneratorReturnSignal(v) => {
          // .return(v) was injected at yield point and propagated up
          // (possibly through finally blocks). Complete the generator.
          complete_generator(gen)
          current_generator.val = prev_gen
          return make_iterator_result(v, true)
        }
        e => raise e
      }
      // Statement completed normally — advance to next
      gen.pc = i + 1
      match signal {
        Normal(v) => last_val = v
        ReturnSignal(v) => {
          complete_generator(gen)
          current_generator.val = prev_gen
          return make_iterator_result(v, true)
        }
        BreakSignal(_) | ContinueSignal(_) => last_val = Undefined
      }
    }
    // Body completed normally
    complete_generator(gen)
    make_iterator_result(last_val, true)
  } catch {
    e => {
      complete_generator(gen)
      current_generator.val = prev_gen
      raise e
    }
  }
  current_generator.val = prev_gen
  result
}

///|
/// Continue generator after yield (resume with next value)
fn generator_continue(
  interp : Interpreter,
  gen : GeneratorObject,
) -> Value raise Error {
  match gen.env {
    Some(env) => {
      // Set resuming flag — the statement will be replayed, and eval_yield
      // will return the resume value instead of throwing YieldSignal
      gen.resuming = true
      run_generator_body(interp, gen, env)
    }
    None => {
      complete_generator(gen)
      make_iterator_result(Undefined, true)
    }
  }
}

// generator_continue_throw and generator_continue_return are now handled
// by the unified generator_continue path via resume_action field.

///|
/// Evaluate a yield expression during generator body execution.
/// When resuming (gen.resuming == true), inspects resume_action:
/// - NextAction: returns the resume value
/// - ThrowAction(e): raises JsException(e) at the yield point
/// - ReturnAction(v): raises GeneratorReturnSignal(v) at the yield point
/// When delegate is true (yield*), iterates the delegate and yields each value.
fn Interpreter::eval_yield(
  self : Interpreter,
  argument : @ast.Expr?,
  delegate : Bool,
  env : Environment,
) -> Value raise Error {
  match current_generator.val {
    Some(gen) =>
      if gen.resuming {
        // We're replaying this statement after resume.
        gen.resuming = false
        match gen.resume_action {
          NextAction => gen.yield_value
          ThrowAction(e) => {
            gen.resume_action = NextAction
            raise JsException(e)
          }
          ReturnAction(v) => {
            gen.resume_action = NextAction
            raise GeneratorReturnSignal(v)
          }
        }
      } else if delegate {
        // yield* expr — delegate to another iterable
        let iterable = match argument {
          Some(expr) => self.eval_expr(expr, env)
          None => Undefined
        }
        // Get iterator from iterable
        let loc = @token.Loc::default()
        let iterator_sym = get_iterator_symbol()
        let iterator_method = self.get_computed_property(
          iterable,
          Symbol(iterator_sym),
          loc,
        )
        let iterator = match iterator_method {
          Object(data) =>
            match data.callable {
              Some(_) => {
                let result = self.call_value(iterator_method, iterable, [], loc)
                match result {
                  Object(_) => result
                  _ =>
                    raise @errors.TypeError(
                      message="Result of the Symbol.iterator method is not an object",
                    )
                }
              }
              None =>
                raise @errors.TypeError(
                  message="Symbol.iterator is not a function",
                )
            }
          _ =>
            raise @errors.TypeError(message="yield* delegate is not iterable")
        }
        // Get next method
        let next_method = get_iterator_next(iterator)
        // Start delegation: call next() and yield first value
        let first_result = self.call_value(next_method, iterator, [], loc)
        let (done, value) = extract_iter_result(first_result)
        if done {
          // Delegate is immediately done — yield* evaluates to the return value
          value
        } else {
          // Save delegation state on generator and yield the value
          gen.delegate_iterator = iterator
          gen.delegate_next = next_method
          gen.delegating = true
          raise YieldSignal(value)
        }
      } else {
        // Normal yield: evaluate argument and suspend
        let yielded_value = match argument {
          Some(expr) => self.eval_expr(expr, env)
          None => Undefined
        }
        raise YieldSignal(yielded_value)
      }
    None =>
      // Parser prevents YieldExpr outside generator context, so this is unreachable
      raise @errors.TypeError(
        message="Internal error: yield outside generator context",
      )
  }
}

///|
/// Get iterator's next method (walk prototype chain)
fn get_iterator_next(iterator : Value) -> Value raise Error {
  match get_optional_method(iterator, "next") {
    Some(next_fn) => next_fn
    None => raise @errors.TypeError(message="iterator.next is not a function")
  }
}

///|
/// Extract done and value from an iterator result
fn extract_iter_result(result : Value) -> (Bool, Value) raise Error {
  match result {
    Object(data) => {
      let done = match data.properties.get("done") {
        Some(v) => is_truthy(v)
        None => false
      }
      let value = match data.properties.get("value") {
        Some(v) => v
        None => Undefined
      }
      (done, value)
    }
    _ => raise @errors.TypeError(message="Iterator result is not an object")
  }
}

///|
/// Resume a delegated yield* — forward the resume to the delegate iterator
fn delegate_resume(
  interp : Interpreter,
  gen : GeneratorObject,
  resume_kind : ResumeKind,
) -> Value raise Error {
  let loc = @token.Loc::default()
  let iterator = gen.delegate_iterator
  let next_method = gen.delegate_next
  // Forward the resume to the delegate
  match resume_kind {
    Next(v) => {
      let result = interp.call_value(next_method, iterator, [v], loc)
      let (done, value) = extract_iter_result(result)
      if done {
        // Delegate completed — yield* expression evaluates to the return value
        // Resume the outer generator body (state is already Executing from caller)
        gen.delegating = false
        gen.delegate_iterator = Undefined
        gen.delegate_next = Undefined
        gen.yield_value = value
        gen.resume_action = NextAction
        generator_continue(interp, gen)
      } else {
        // Delegate yielded — suspend the outer generator
        gen.state = SuspendedYield
        make_iterator_result(value, false)
      }
    }
    Throw(e) => {
      // Check if delegate has .throw method
      let throw_method = get_optional_method(iterator, "throw")
      match throw_method {
        Some(tm) => {
          let result = interp.call_value(tm, iterator, [e], loc)
          let (done, value) = extract_iter_result(result)
          if done {
            // Delegate completed after throw — resume outer with return value
            gen.delegating = false
            gen.delegate_iterator = Undefined
            gen.delegate_next = Undefined
            gen.yield_value = value
            gen.resume_action = NextAction
            generator_continue(interp, gen)
          } else {
            // Delegate yielded after throw (e.g. from catch block)
            gen.state = SuspendedYield
            make_iterator_result(value, false)
          }
        }
        None => {
          // No .throw — per ES spec, close delegate via .return() then throw TypeError
          let return_method = get_optional_method(iterator, "return")
          match return_method {
            Some(rm) => {
              // Close the delegate so finally blocks execute
              let close_result = interp.call_value(rm, iterator, [], loc)
              match close_result {
                Object(_) => ()
                _ =>
                  raise @errors.TypeError(
                    message="Iterator close result is not an object",
                  )
              }
            }
            None => ()
          }
          gen.delegating = false
          gen.delegate_iterator = Undefined
          gen.delegate_next = Undefined
          // Per spec: raise TypeError, not the original error
          raise @errors.TypeError(
            message="Iterator does not have a 'throw' method",
          )
        }
      }
    }
    Return(v) => {
      // Check if delegate has .return method
      let return_method = get_optional_method(iterator, "return")
      match return_method {
        Some(rm) => {
          let result = interp.call_value(rm, iterator, [v], loc)
          let (done, value) = extract_iter_result(result)
          if done {
            // Delegate completed after .return() — propagate through outer
            // body so finally blocks execute
            gen.delegating = false
            gen.delegate_iterator = Undefined
            gen.delegate_next = Undefined
            gen.yield_value = value
            gen.resume_action = ReturnAction(value)
            generator_continue(interp, gen)
          } else {
            // Delegate yielded from finally — outer stays suspended delegating
            gen.state = SuspendedYield
            make_iterator_result(value, false)
          }
        }
        None => {
          // No .return — propagate return through outer body for finally blocks
          gen.delegating = false
          gen.delegate_iterator = Undefined
          gen.delegate_next = Undefined
          gen.yield_value = v
          gen.resume_action = ReturnAction(v)
          generator_continue(interp, gen)
        }
      }
    }
  }
}

///|
/// Get an optional method from an object per ES spec GetMethod.
/// Returns None if property is undefined/null/missing.
/// Throws TypeError if property exists but is not callable.
fn get_optional_method(obj : Value, name : String) -> Value? raise Error {
  match obj {
    Object(data) =>
      // Check direct properties first
      match data.properties.get(name) {
        Some(v) =>
          match v {
            Undefined | Null => None
            Object(fd) =>
              match fd.callable {
                Some(_) => Some(v)
                None =>
                  raise @errors.TypeError(message="\{name} is not a function")
              }
            _ => raise @errors.TypeError(message="\{name} is not a function")
          }
        None => {
          // Walk prototype chain
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) =>
                match proto_data.properties.get(name) {
                  Some(v) =>
                    match v {
                      Undefined | Null => return None
                      Object(fd) =>
                        match fd.callable {
                          Some(_) => return Some(v)
                          None =>
                            raise @errors.TypeError(
                              message="\{name} is not a function",
                            )
                        }
                      _ =>
                        raise @errors.TypeError(
                          message="\{name} is not a function",
                        )
                    }
                  None => current = proto_data.prototype
                }
              _ => break
            }
          }
          None
        }
      }
    _ => None
  }
}
