///|
/// Check if an expression is an anonymous function/class/arrow definition
/// per ECMAScript IsAnonymousFunctionDefinition (§15.2)
fn is_anonymous_function_definition(expr : @ast.Expr) -> Bool {
  match expr {
    FuncExpr(None, _, _, _) => true
    FuncExprExt(None, _, _, _, _) => true
    ArrowFunc(_, _, _) => true
    ArrowFuncExt(_, _, _, _) => true
    ClassExpr(None, _, _, _) => true
    GeneratorExpr(None, _, _, _) => true
    GeneratorExprExt(None, _, _, _, _) => true
    AsyncFuncExpr(None, _, _, _) => true
    AsyncFuncExprExt(None, _, _, _, _) => true
    AsyncArrowFunc(_, _, _) => true
    AsyncArrowFuncExt(_, _, _, _) => true
    AsyncGeneratorExpr(None, _, _, _) => true
    AsyncGeneratorExprExt(None, _, _, _, _) => true
    Grouping(inner, _) => is_anonymous_function_definition(inner)
    _ => false
  }
}

///|
pub(all) enum Signal {
  Normal(Value)
  ReturnSignal(Value)
  BreakSignal(Value?, String?) // (completion_value (None=empty), label?)
  ContinueSignal(Value?, String?) // (completion_value (None=empty), label?)
}

///|
/// Microtask record for the event loop microtask queue
/// Stores a callback function and argument list to pass to it
pub(all) struct Microtask {
  callback : Value // The function to call
  args : Array[Value] // Arguments to pass (Promise jobs pass one, queueMicrotask passes none)
}

///|
/// Timer task for setTimeout/setInterval (task queue per WHATWG spec)
/// Timers are processed one at a time with microtask checkpoints between each
pub(all) struct TimerTask {
  id : Int // Unique timer ID for clearTimeout/clearInterval
  callback : Value // The function to call
  args : Array[Value] // Additional arguments to pass to the callback
  delay : Int // Absolute fire-at time in virtual ms (used for ordering)
  period : Int // Interval repeat period (0 for setTimeout)
  mut cancelled : Bool // Whether clearTimeout was called
  is_interval : Bool // Whether this is a setInterval (repeats)
  insertion_order : Int // Stable sort tiebreaker for equal delays
}

///|
/// Host-provided callback that resolves a module specifier to its exports.
/// Called by exec_import when a specifier is not already in module_registry.
/// Return a Map[String, Value] of exported names → values, or raise an error.
pub(all) struct ModuleLoader((String) -> Map[String, Value] raise Error)

///|
pub(all) struct Interpreter {
  output : Array[String]
  global : Environment
  global_this : Value
  mut strict : Bool
  annex_b : Bool // Enable Annex B legacy features (--annex-b flag)
  microtask_queue : Array[Microtask] // Event loop microtask queue
  timer_queue : Array[TimerTask] // Timer task queue (WHATWG task queue)
  timer_id_counter : Ref[Int] // Next timer ID
  timer_insertion_counter : Ref[Int] // Insertion order counter
  cancelled_timer_ids : Map[Int, Bool] // IDs cancelled during callback execution
  // ES Modules support
  module_registry : Map[String, Map[String, Value]] // module specifier -> exports namespace
  mut module_exports : Map[String, Value] // current module's exports being built
  mut module_export_bindings : Array[(String, String)] // deferred: (export_name, local_binding_name)
  module_loader : ModuleLoader? // optional host-provided dynamic module resolver
  // Generator runtime state (previously module-level globals)
  generator_objects : Map[Int, GeneratorObject] // live generator instances keyed by ID
  gen_id_counter : Ref[Int] // monotonically increasing ID for new generator instances
  mut current_generator : GeneratorObject? // generator currently executing (None outside generator body)
}

///|
pub fn Interpreter::new(
  annex_b? : Bool = false,
  module_loader? : ModuleLoader? = None,
) -> Interpreter {
  let global = Environment::new()
  global.is_var_scope = true
  let output : Array[String] = []
  // Create global object for 'this' in global context
  let global_this : Value = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "global",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  setup_builtins(global, output, annex_b~)
  // Bind 'this' and 'globalThis' in global scope
  global.def_builtin("this", global_this)
  global.def_builtin("globalThis", global_this)
  // Mirror global built-in functions onto the global object (globalThis.X)
  // so that this.isFinite, this.isNaN, etc. work correctly per the ES spec
  let global_func_names = [
    "eval", "isFinite", "isNaN", "parseInt", "parseFloat", "encodeURIComponent",
    "decodeURIComponent", "encodeURI", "decodeURI", "escape", "unescape", "String",
    "Number", "Boolean", "Object", "Array", "Function", "RegExp", "Error", "TypeError",
    "RangeError", "ReferenceError", "SyntaxError", "URIError", "EvalError", "Date",
    "Math", "JSON", "Symbol", "Map", "Set", "WeakMap", "WeakSet", "Promise", "Proxy",
    "Reflect", "ArrayBuffer", "DataView", "Int8Array", "Uint8Array", "Uint8ClampedArray",
    "Int16Array", "Uint16Array", "Int32Array", "Uint32Array", "Float32Array", "Float64Array",
  ]
  let builtin_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  match global_this {
    Object(data) =>
      for name in global_func_names {
        match global.bindings.get(name) {
          Some(binding) => {
            data.properties[name] = binding.value
            data.descriptors[name] = { ..builtin_desc }
          }
          None => ()
        }
      }
    _ => ()
  }
  // Mirror global constants (undefined, NaN, Infinity) onto the global object
  // with correct property descriptors per ES spec §19.1
  match global_this {
    Object(data) => {
      data.properties["undefined"] = Undefined
      data.properties["NaN"] = Number(0.0 / 0.0)
      data.properties["Infinity"] = Number(1.0 / 0.0)
      // All three are { writable: false, enumerable: false, configurable: false }
      let frozen_desc : PropDescriptor = {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
      }
      data.descriptors["undefined"] = { ..frozen_desc }
      data.descriptors["NaN"] = { ..frozen_desc }
      data.descriptors["Infinity"] = { ..frozen_desc }
    }
    _ => ()
  }
  // Set up GeneratorFunction constructor
  setup_generator_function_constructor(global, global_this)
  // Set up test262 harness host functions (print, $262)
  setup_harness_builtins(global, output, global_this)
  let microtask_queue : Array[Microtask] = []
  let timer_queue : Array[TimerTask] = []
  let timer_id_counter : Ref[Int] = { val: 1 }
  let timer_insertion_counter : Ref[Int] = { val: 0 }
  let cancelled_timer_ids : Map[Int, Bool] = {}
  {
    output,
    global,
    global_this,
    strict: false,
    annex_b,
    microtask_queue,
    timer_queue,
    timer_id_counter,
    timer_insertion_counter,
    cancelled_timer_ids,
    module_registry: {},
    module_exports: {},
    module_export_bindings: [],
    module_loader,
    generator_objects: {},
    gen_id_counter: { val: 0 },
    current_generator: None,
  }
}

///|
fn has_use_strict(stmts : Array[@ast.Stmt]) -> Bool {
  // Scan the directive prologue: the longest sequence of ExpressionStatements
  // consisting entirely of StringLiterals at the beginning of the body.
  // Only the literal string "use strict" WITHOUT escape sequences activates strict mode.
  for i = 0; i < stmts.length(); i = i + 1 {
    match stmts[i] {
      ExprStmt(StringLit(s, has_escape, _), _) =>
        if s == "use strict" && !has_escape {
          return true
        }
      // Continue scanning — other string directives are part of the prologue
      _ => break // Non-string ExprStmt or other statement ends the prologue
    }
  }
  false
}

///|
/// Check if a name is a strict-mode reserved word (ES5 §7.6.1.2).
/// These identifiers cannot be used as variable names, function names,
/// or parameter names in strict mode code.
fn is_strict_reserved_word(name : String) -> Bool {
  match name {
    "implements"
    | "interface"
    | "let"
    | "package"
    | "private"
    | "protected"
    | "public"
    | "static"
    | "yield" => true
    _ => false
  }
}

///|
/// Validate that a binding name is legal in strict mode.
/// Raises SyntaxError if name is "eval", "arguments", or a strict reserved word.
fn validate_strict_binding_name(name : String) -> Unit raise Error {
  if name == "eval" || name == "arguments" {
    raise @errors.SyntaxError(
      message="Unexpected eval or arguments in strict mode",
    )
  }
  if is_strict_reserved_word(name) {
    raise @errors.SyntaxError(message="Unexpected strict mode reserved word")
  }
}

///|
/// Check for duplicate parameter names. Raises SyntaxError in strict mode.
fn check_duplicate_params(params : Array[String]) -> Unit raise Error {
  let seen : Map[String, Bool] = {}
  for p in params {
    if seen.contains(p) {
      raise @errors.SyntaxError(
        message="Duplicate parameter name not allowed in this context",
      )
    }
    seen[p] = true
  }
}

///|
/// Check for duplicate parameter names from Param array (extended params).
fn check_duplicate_params_ext(
  params : Array[@ast.Param],
  rest_param : String?,
) -> Unit raise Error {
  let seen : Map[String, Bool] = {}
  for p in params {
    if seen.contains(p.name) {
      raise @errors.SyntaxError(
        message="Duplicate parameter name not allowed in this context",
      )
    }
    seen[p.name] = true
  }
  match rest_param {
    Some(rn) =>
      if seen.contains(rn) {
        raise @errors.SyntaxError(
          message="Duplicate parameter name not allowed in this context",
        )
      }
    None => ()
  }
}

///|
let eval_function_reconcile_marker = "[[EvalFunctionReconcile]]"

///|
fn is_function_strict(enclosing_strict : Bool, body : Array[@ast.Stmt]) -> Bool {
  enclosing_strict || has_use_strict(body)
}

///|
fn validate_function_signature(
  enclosing_strict : Bool,
  name : String?,
  params : Array[String],
  body : Array[@ast.Stmt],
) -> Unit raise Error {
  if is_function_strict(enclosing_strict, body) {
    match name {
      Some(n) => validate_strict_binding_name(n)
      None => ()
    }
    check_duplicate_params(params)
    for p in params {
      validate_strict_binding_name(p)
    }
  }
}

///|
fn validate_function_signature_ext(
  enclosing_strict : Bool,
  name : String?,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
) -> Unit raise Error {
  if is_function_strict(enclosing_strict, body) {
    match name {
      Some(n) => validate_strict_binding_name(n)
      None => ()
    }
    check_duplicate_params_ext(params, rest_param)
    for p in params {
      validate_strict_binding_name(p.name)
    }
    match rest_param {
      Some(rn) => validate_strict_binding_name(rn)
      None => ()
    }
  }
}

///|
fn should_reconcile_eval_function_decl(
  env : Environment,
  name : String,
) -> Bool {
  env.bindings.contains(eval_function_reconcile_marker) && env.has_var(name)
}

///|
/// Mirror a binding to the global object (globalThis) as an own property.
/// This implements CreateGlobalVarBinding / CreateGlobalFunctionBinding per the
/// ES spec, where global `var` and function declarations become properties of
/// the global object.  `configurable` controls the property descriptor.
fn Interpreter::mirror_to_global(
  self : Interpreter,
  name : String,
  value : Value,
  configurable? : Bool = false,
) -> Unit {
  match self.global_this {
    Object(data) => {
      data.properties[name] = value
      // Only set descriptor if not already set (preserve existing non-configurable)
      match data.descriptors.get(name) {
        Some(existing) =>
          if existing.configurable {
            // Update value via property, descriptor stays
            ()
          }
        None =>
          data.descriptors[name] = {
            writable: true,
            enumerable: true,
            configurable,
            getter: None,
            setter: None,
          }
      }
    }
    _ => ()
  }
}

///|
pub fn Interpreter::run(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> Value raise Error {
  // Store interpreter ref for ToPrimitive to use when calling user functions
  current_interpreter.val = Some(self)
  try {
    // Check for "use strict" directive
    if has_use_strict(stmts) {
      self.strict = true
    }
    // Static block-scoped redeclaration checks (block lexical-vs-var conflicts).
    self.validate_block_early_errors(stmts, self.strict)
    // Hoist var declarations and function declarations at global level
    self.hoist_declarations(stmts, self.global)
    let mut last : Value = Undefined
    for stmt in stmts {
      match self.exec_stmt(stmt, self.global) {
        Normal(v) => last = v
        ReturnSignal(_) =>
          raise @errors.SyntaxError(
            message="return statement outside of function",
          )
        BreakSignal(_, _) =>
          raise @errors.SyntaxError(message="break statement outside of loop")
        ContinueSignal(_, _) =>
          raise @errors.SyntaxError(
            message="continue statement outside of loop",
          )
      }
    }
    last
  } catch {
    e =>
      if is_js_catchable_error(e) {
        raise JsException(js_error_to_value_with_env(e, Some(self.global)))
      } else {
        raise e
      }
  }
}
