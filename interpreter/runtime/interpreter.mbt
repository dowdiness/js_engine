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
/// Immutable per-call execution context passed through the evaluation pipeline.
/// Replaces the mutable `strict` and `current_generator` fields that were
/// previously on the Interpreter struct, eliminating fragile save/restore patterns.
pub(all) struct ExecContext {
  strict : Bool
  current_generator : GeneratorObject?
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
/// Host environment state — concerns that belong to the runtime container
/// rather than the JavaScript execution model itself.
///
/// Separating these fields makes the engine/host boundary explicit and
/// enables future host-environment variations (different I/O, timer
/// semantics, or module resolution) without touching execution internals.
pub(all) struct HostEnv {
  output : Array[String] // console.log / print accumulator
  microtask_queue : Array[Microtask] // Promise microtask queue (WHATWG spec)
  timer_queue : Array[TimerTask] // setTimeout / setInterval task queue
  timer_id_counter : Ref[Int] // Next timer ID (monotonically increasing)
  timer_insertion_counter : Ref[Int] // Stable-sort tiebreaker for equal delays
  cancelled_timer_ids : Map[Int, Bool] // IDs cancelled during an active callback
  module_loader : ModuleLoader? // Optional host-provided module resolver
}

///|
pub(all) struct Interpreter {
  host : HostEnv // Host environment (I/O, event loop, module loading)
  global : Environment
  global_this : Value
  annex_b : Bool // Enable Annex B legacy features (--annex-b flag)
  realm_state : RealmState // Per-realm mutable engine state owner
  // ES Modules support
  module_registry : Map[String, Map[String, Value]] // module specifier -> exports namespace
  mut module_exports : Map[String, Value] // current module's exports being built
  mut module_export_bindings : Array[(String, String)] // deferred: (export_name, local_binding_name)
  // Generator runtime state
  generator_objects : Map[Int, GeneratorObject] // live generator instances keyed by ID
  gen_id_counter : Ref[Int] // monotonically increasing ID for new generator instances
  // Compatibility access to realm_state.symbols for existing runtime/stdlib code.
  symbols : SymbolState
  // Stdlib dispatch hooks — populated by the wiring layer in the root package
  mut stdlib_hooks : StdlibHooks
  // §19.2.1.3 (#A.6): true while the current function frame is evaluating
  // one of its own parameter defaults. Direct eval in that window raises
  // SyntaxError if its var names conflict with this frame's parameter-scope
  // names (and non-arrow `arguments`). Reset to false on every function entry
  // so nested IIFEs / arrows / recursive calls don't inherit the outer frame's
  // default-eval state.
  mut in_nonarrow_param_default_eval : Bool
  mut param_default_eval_var_conflicts : @set.Set[String]?
}

///|
pub fn Interpreter::new(
  annex_b? : Bool = false,
  module_loader? : ModuleLoader? = None,
  setup_builtins? : (Environment, Array[String], RealmState, Bool) -> Unit = fn(
    _,
    _,
    _,
    _,
  ) {

  },
  setup_harness? : (Environment, Array[String], Value) -> Unit = fn(_, _, _) {

  },
  stdlib_hooks? : StdlibHooks = default_stdlib_hooks(),
) -> Interpreter {
  let global = Environment::new()
  global.is_var_scope = true
  let output : Array[String] = []
  // Create global object for 'this' in global context
  let global_this : Value = Object({
    bag: PropertyBag(),
    prototype: Null,
    callable: None,
    class_name: "global",
    extensible: true,
    arraybuffer_state: None,
  })
  let realm_state = RealmState()
  global.realm_state = Some(realm_state)
  let symbols = realm_state.symbols
  let host : HostEnv = {
    output,
    microtask_queue: [],
    timer_queue: [],
    timer_id_counter: { val: 1 },
    timer_insertion_counter: { val: 0 },
    cancelled_timer_ids: {},
    module_loader,
  }
  let interp : Interpreter = {
    host,
    global,
    global_this,
    annex_b,
    realm_state,
    module_registry: {},
    module_exports: {},
    module_export_bindings: [],
    generator_objects: {},
    gen_id_counter: { val: 0 },
    symbols,
    stdlib_hooks,
    in_nonarrow_param_default_eval: false,
    param_default_eval_var_conflicts: None,
  }
  global.interpreter_context = Some(interp)
  with_cleared_active_callee_realm_unit(realm_state, fn() {
    setup_builtins(global, output, realm_state, annex_b)
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
      is_accessor: false,
    }
    match global_this {
      Object(data) =>
        for name in global_func_names {
          match global.bindings.get(name) {
            Some(binding) => {
              data.bag.properties[name] = binding.value
              data.bag.descriptors[name] = { ..builtin_desc }
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
        data.bag.properties["undefined"] = Undefined
        data.bag.properties["NaN"] = Number(0.0 / 0.0)
        data.bag.properties["Infinity"] = Number(1.0 / 0.0)
        // All three are { writable: false, enumerable: false, configurable: false }
        let frozen_desc : PropDescriptor = {
          writable: false,
          enumerable: false,
          configurable: false,
          getter: None,
          setter: None,
          is_accessor: false,
        }
        data.bag.descriptors["undefined"] = { ..frozen_desc }
        data.bag.descriptors["NaN"] = { ..frozen_desc }
        data.bag.descriptors["Infinity"] = { ..frozen_desc }
      }
      _ => ()
    }
    // Set up GeneratorFunction constructor
    setup_generator_function_constructor(
      global,
      global_this,
      well_known_symbols=realm_state.well_known_symbols,
    )
    // Set up AsyncFunction constructor
    setup_async_function_constructor(
      global,
      well_known_symbols=realm_state.well_known_symbols,
    )
    // Set up test262 harness host functions (print, $262)
    setup_harness(global, output, global_this)
  })
  interp
}

///|
/// Check for duplicate parameter names. Raises SyntaxError in strict mode.
fn check_duplicate_params(params : Array[String]) -> Unit raise Error {
  let seen = @set.Set::default()
  for p in params {
    if seen.contains(p) {
      raise @errors.SyntaxError(
        message="Duplicate parameter name not allowed in this context",
      )
    }
    seen.add(p)
  }
}

///|
/// Check for duplicate parameter names from Param array (extended params).
fn params_have_rest_pattern(params : Array[@ast.Param]) -> Bool {
  for p in params {
    if p.is_rest_pattern {
      return true
    }
  }
  false
}

///|
fn check_duplicate_binding_name(
  seen : @set.Set[String],
  name : String,
) -> Unit raise Error {
  if seen.contains(name) {
    raise @errors.SyntaxError(
      message="Duplicate parameter name not allowed in this context",
    )
  }
  seen.add(name)
}

///|
fn check_duplicate_pattern_binding_names(
  pattern : @ast.Pattern,
  seen : @set.Set[String],
) -> Unit raise Error {
  match pattern {
    IdentPat(name) => check_duplicate_binding_name(seen, name)
    DefaultPat(inner, _) => check_duplicate_pattern_binding_names(inner, seen)
    AssignTarget(_) => ()
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(pat) => check_duplicate_pattern_binding_names(pat, seen)
          None => ()
        }
      }
      match rest {
        Some(pat) => check_duplicate_pattern_binding_names(pat, seen)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        check_duplicate_pattern_binding_names(prop.value, seen)
      }
      match rest {
        Some(pat) => check_duplicate_pattern_binding_names(pat, seen)
        None => ()
      }
    }
  }
}

///|
fn check_duplicate_params_ext(
  params : Array[@ast.Param],
  rest_param : String?,
) -> Unit raise Error {
  let seen = @set.Set::default()
  let has_rest_pattern = params_have_rest_pattern(params)
  for p in params {
    match p.pattern {
      Some(pat) => check_duplicate_pattern_binding_names(pat, seen)
      None => check_duplicate_binding_name(seen, p.name)
    }
  }
  match rest_param {
    Some(rn) => if !has_rest_pattern { check_duplicate_binding_name(seen, rn) }
    None => ()
  }
}

///|
fn params_include_arguments(
  params : Array[String],
  rest_param : String?,
) -> Bool {
  for p in params {
    if p == "arguments" {
      return true
    }
  }
  rest_param is Some("arguments")
}

///|
fn pattern_includes_arguments(pattern : @ast.Pattern) -> Bool {
  match pattern {
    IdentPat(name) => name == "arguments"
    DefaultPat(inner, _) => pattern_includes_arguments(inner)
    AssignTarget(_) => false
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(pat) => if pattern_includes_arguments(pat) { return true }
          None => ()
        }
      }
      match rest {
        Some(pat) => pattern_includes_arguments(pat)
        None => false
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        if pattern_includes_arguments(prop.value) {
          return true
        }
      }
      match rest {
        Some(pat) => pattern_includes_arguments(pat)
        None => false
      }
    }
  }
}

///|
fn ext_params_include_arguments(
  params : Array[@ast.Param],
  rest_param : String?,
) -> Bool {
  for p in params {
    if p.name == "arguments" {
      return true
    }
    match p.pattern {
      Some(pat) => if pattern_includes_arguments(pat) { return true }
      None => ()
    }
  }
  rest_param is Some("arguments")
}

///|
fn validate_strict_pattern_binding_names(
  pattern : @ast.Pattern,
) -> Unit raise Error {
  match pattern {
    IdentPat(name) => @static_semantics.validate_strict_binding_name(name)
    DefaultPat(inner, _) => validate_strict_pattern_binding_names(inner)
    AssignTarget(_) => ()
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(pat) => validate_strict_pattern_binding_names(pat)
          None => ()
        }
      }
      match rest {
        Some(pat) => validate_strict_pattern_binding_names(pat)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        validate_strict_pattern_binding_names(prop.value)
      }
      match rest {
        Some(pat) => validate_strict_pattern_binding_names(pat)
        None => ()
      }
    }
  }
}

///|
fn validate_strict_param_binding_names_ext(
  params : Array[@ast.Param],
  rest_param : String?,
) -> Unit raise Error {
  let has_rest_pattern = params_have_rest_pattern(params)
  for p in params {
    match p.pattern {
      Some(pat) => validate_strict_pattern_binding_names(pat)
      None => @static_semantics.validate_strict_binding_name(p.name)
    }
  }
  match rest_param {
    Some(rn) =>
      if !has_rest_pattern {
        @static_semantics.validate_strict_binding_name(rn)
      }
    None => ()
  }
}

///|
/// Apply parameter-list early errors for functions built via the
/// Function / GeneratorFunction / AsyncFunction / AsyncGeneratorFunction
/// constructors. Per spec these fire at construction time, not at call.
///
/// Three checks:
///   1. Non-simple parameter list with `"use strict"` directive in body
///      is a SyntaxError (§15.1.1 / §14.1.2).
///   2. Strict-mode (or non-simple) parameter list must not contain
///      duplicate names.
///   3. Strict-mode parameter names must not be `eval`, `arguments`,
///      or a strict-reserved word (§15.1.5).
pub fn validate_function_constructor_params(
  is_simple : Bool,
  param_names : Array[String],
  rest_name : String?,
  body : Array[@ast.Stmt],
) -> Unit raise Error {
  let body_has_use_strict = @static_semantics.has_use_strict(body)
  if !is_simple && body_has_use_strict {
    raise @errors.SyntaxError(
      message="Illegal 'use strict' directive in function with non-simple parameter list",
    )
  }
  let body_strict = body_has_use_strict
  if !is_simple || body_strict {
    let seen = @set.Set::default()
    for p in param_names {
      if seen.contains(p) {
        raise @errors.SyntaxError(
          message="Duplicate parameter name not allowed in this context",
        )
      }
      seen.add(p)
    }
    match rest_name {
      Some(n) =>
        if seen.contains(n) {
          raise @errors.SyntaxError(
            message="Duplicate parameter name not allowed in this context",
          )
        }
      None => ()
    }
  }
  if body_strict {
    for p in param_names {
      @static_semantics.validate_strict_binding_name(p)
    }
    match rest_name {
      Some(n) => @static_semantics.validate_strict_binding_name(n)
      None => ()
    }
  }
}

///|
pub fn validate_function_constructor_params_ext(
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
) -> Unit raise Error {
  if @static_semantics.has_use_strict(body) {
    raise @errors.SyntaxError(
      message="Illegal 'use strict' directive in function with non-simple parameter list",
    )
  }
  check_duplicate_params_ext(params, rest_param)
}

///|
const EVAL_FUNCTION_RECONCILE_MARKER = "[[EvalFunctionReconcile]]"

///|
fn is_function_strict(enclosing_strict : Bool, body : Array[@ast.Stmt]) -> Bool {
  @static_semantics.body_is_strict(body, enclosing_strict)
}

///|
/// §10.2.11 `ContainsExpression` / `HasParameterExpressions` for Ext
/// function parameter lists. True iff any param carries a default
/// initializer or a pattern that itself contains an expression
/// (nested default, computed key, or assignment target). A plain
/// destructuring pattern like `{a}` or `[a, b]` with no nested
/// initializers has NO expression per spec and must not trigger the
/// split; otherwise `function f({a}) { var a; return a }` would hoist
/// `var a` into body_env and shadow the destructured parameter.
/// Plain rest without a pattern is also not a parameter expression.
pub fn has_parameter_expressions(params : Array[@ast.Param]) -> Bool {
  for p in params {
    if p.default_val is Some(_) {
      return true
    }
    match p.pattern {
      Some(pat) => if pattern_contains_expression(pat) { return true }
      None => ()
    }
  }
  false
}

///|
/// Returns true iff a BindingPattern contains any Initializer,
/// computed property key, or assignment target — i.e. the AST
/// subtrees the spec classifies as expressions inside
/// `ContainsExpression`.
fn pattern_contains_expression(pattern : @ast.Pattern) -> Bool {
  match pattern {
    IdentPat(_) => false
    DefaultPat(_, _) => true
    // AssignTarget shows up only for destructuring-assignment forms, not
    // BindingPattern parameters, but treat it as an expression defensively.
    AssignTarget(_) => true
    ArrayPat(elements, rest) => {
      for e in elements {
        match e {
          Some(p) => if pattern_contains_expression(p) { return true }
          None => ()
        }
      }
      match rest {
        Some(p) => pattern_contains_expression(p)
        None => false
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        if prop.default_val is Some(_) {
          return true
        }
        if prop.computed_key is Some(_) {
          return true
        }
        if pattern_contains_expression(prop.value) {
          return true
        }
      }
      match rest {
        Some(p) => pattern_contains_expression(p)
        None => false
      }
    }
  }
}

///|
pub fn validate_function_signature(
  enclosing_strict : Bool,
  name : String?,
  params : Array[String],
  body : Array[@ast.Stmt],
) -> Unit raise Error {
  if is_function_strict(enclosing_strict, body) {
    match name {
      Some(n) => @static_semantics.validate_strict_binding_name(n)
      None => ()
    }
    check_duplicate_params(params)
    for p in params {
      @static_semantics.validate_strict_binding_name(p)
    }
  }
}

///|
pub fn validate_function_signature_ext(
  enclosing_strict : Bool,
  name : String?,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
) -> Unit raise Error {
  if is_function_strict(enclosing_strict, body) {
    match name {
      Some(n) => @static_semantics.validate_strict_binding_name(n)
      None => ()
    }
    check_duplicate_params_ext(params, rest_param)
    validate_strict_param_binding_names_ext(params, rest_param)
  }
}

///|
fn should_reconcile_eval_function_decl(
  env : Environment,
  name : String,
) -> Bool {
  env.bindings.contains(EVAL_FUNCTION_RECONCILE_MARKER) && env.has_var(name)
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
      data.bag.properties[name] = value
      // Only set descriptor if not already set (preserve existing non-configurable)
      match data.bag.descriptors.get(name) {
        Some(existing) =>
          if existing.configurable {
            // Update value via property, descriptor stays
            ()
          }
        None =>
          data.bag.descriptors[name] = {
            writable: true,
            enumerable: true,
            configurable,
            getter: None,
            setter: None,
            is_accessor: false,
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
  let strict = @static_semantics.has_use_strict(stmts)
  let ctx : ExecContext = { strict, current_generator: None }
  try {
    let result = with_cleared_active_callee_realm(self.realm_state, fn() raise {
      // Static block-scoped redeclaration checks (block lexical-vs-var conflicts).
      self.validate_block_early_errors(stmts, strict)
      // Hoist var/function declarations and top-level lexical TDZ markers.
      self.hoist_declarations(stmts, self.global, strict~)
      hoist_block_tdz(stmts, self.global)
      let mut last : Value = Undefined
      for stmt in stmts {
        match self.exec_stmt(ctx, stmt, self.global) {
          Normal(v) => last = v
          ReturnSignal(_) =>
            raise @errors.SyntaxError(
              message="return statement outside of function",
            )
          sig => raise_if_break_continue(sig)
        }
      }
      last
    })
    result
  } catch {
    e =>
      if is_js_catchable_error(e) {
        raise JsException(js_error_to_value_with_env(e, Some(self.global)))
      } else {
        raise e
      }
  }
}
