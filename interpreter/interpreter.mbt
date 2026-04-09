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
}

///|
pub fn Interpreter::new(annex_b? : Bool = false) -> Interpreter {
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

///|
fn Interpreter::exec_stmt(
  self : Interpreter,
  stmt : @ast.Stmt,
  env : Environment,
  label? : String? = None,
) -> Signal raise Error {
  match stmt {
    ExprStmt(expr, _) => Normal(self.eval_expr(expr, env))
    VarDecl(kind, name, init, _) => {
      // Strict mode: cannot use eval/arguments as variable name
      if self.strict {
        validate_strict_binding_name(name)
      }
      let bk : BindingKind = match kind {
        LetKind => LetBinding
        ConstKind => ConstBinding
        VarKind => VarBinding
      }
      let value : Value = match init {
        Some(expr) => {
          let v = self.eval_expr(expr, env)
          // SetFunctionName for variable declarations
          // Per spec, only set name for IsAnonymousFunctionDefinition
          // Comma expressions, parenthesized expressions are NOT anonymous function definitions
          if is_anonymous_function_definition(expr) {
            set_function_name(v, name)
          }
          v
        }
        None => Undefined
      }
      // For var declarations that were hoisted, use assign instead of def.
      // Check parent scope too — var may have been hoisted to a parent env
      // (e.g., eval hoists var to caller scope, block-scoped var goes to function scope).
      // Use has_var to only match VarBinding, not let/const in parent scopes.
      if bk == VarBinding && (env.bindings.contains(name) || env.has_var(name)) {
        if init is Some(_) {
          // Use assign_var to skip any intervening let/const that shadow the name.
          // This ensures eval("var x = 1") targets the function scope's var x,
          // not a block-scoped let x in between.
          env.assign_var(name, value)
          // Mirror var assignment to global object when in global scope
          if physical_equal(env.find_var_env(), self.global) {
            self.mirror_to_global(name, value)
          }
        }
      } else if (bk == LetBinding || bk == ConstBinding) &&
        env.bindings.contains(name) {
        // let/const hoisted with TDZ - initialize it
        env.initialize(name, value)
      } else {
        env.def(name, value, bk)
        // Mirror new var declaration to global object when in global scope
        if bk == VarBinding && physical_equal(env.find_var_env(), self.global) {
          self.mirror_to_global(name, value)
        }
      }
      Normal(Undefined)
    }
    Block(stmts, _) => {
      let block_env = Environment::new(parent=Some(env))
      // Hoist let/const with TDZ markers
      hoist_block_tdz(stmts, block_env)
      self.exec_stmts(stmts, block_env)
    }
    StmtList(stmts, _) =>
      // Execute statements in same scope (no new environment)
      // Used for comma-separated declarations like: var a, b, c;
      self.exec_stmts(stmts, env)
    IfStmt(cond, then_branch, else_branch, _) => {
      let cond_val = self.eval_expr(cond, env)
      if is_truthy(cond_val) {
        self.exec_stmt(then_branch, env)
      } else {
        match else_branch {
          Some(eb) => self.exec_stmt(eb, env)
          None => Normal(Undefined)
        }
      }
    }
    WhileStmt(cond, body, _) => {
      let gen_opt = current_generator.val
      let resuming_loop = match gen_opt {
        Some(g) => g.loop_env_stack.length() > 0
        _ => false
      }
      let mut first_iteration = resuming_loop
      // If resuming, pop the env marker (we push env as a marker for while loops)
      if resuming_loop {
        match gen_opt {
          Some(g) => {
            let _ = g.loop_env_stack.pop()
          }
          _ => ()
        }
      }
      // Track last completion value for eval completion semantics
      let mut completion : Value = Undefined
      while true {
        if first_iteration {
          first_iteration = false
        } else if !is_truthy(self.eval_expr(cond, env)) {
          break
        }
        let body_signal = self.exec_stmt(body, env) catch {
          e => {
            if e is YieldSignal(_) {
              match gen_opt {
                Some(g) => g.loop_env_stack.push(env)
                _ => ()
              }
            }
            raise e
          }
        }
        match body_signal {
          Normal(v) => completion = v
          ReturnSignal(v) => return ReturnSignal(v)
          BreakSignal(v, None) => {
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              completion = bv.unwrap_or(completion)
              break
            } else {
              return BreakSignal(bv, Some(l))
            }
          ContinueSignal(v, None) => {
            completion = v.unwrap_or(completion)
            continue
          }
          ContinueSignal(cv, Some(l)) =>
            if label == Some(l) {
              completion = cv.unwrap_or(completion)
              continue
            } else {
              return ContinueSignal(cv, Some(l))
            }
        }
      }
      Normal(completion)
    }
    ForStmt(init, cond, update, body, _) => {
      // Check if we're resuming inside a generator loop
      let gen_opt = current_generator.val
      let resuming_loop = match gen_opt {
        Some(g) => g.loop_env_stack.length() > 0
        _ => false
      }
      // Collect let/const variable names from init for per-iteration scoping
      let loop_vars : Array[String] = []
      fn collect_loop_vars(stmt : @ast.Stmt) {
        match stmt {
          VarDecl(kind, name, _, _) =>
            if kind == LetKind || kind == ConstKind {
              loop_vars.push(name)
            }
          StmtList(stmts, _) =>
            for s in stmts {
              collect_loop_vars(s)
            }
          _ => ()
        }
      }
      match init {
        Some(init_stmt) => collect_loop_vars(init_stmt)
        None => ()
      }
      let has_lexical_vars = loop_vars.length() > 0
      let for_env = if resuming_loop {
        // Use saved loop env from stack (pop from end = outermost first)
        match gen_opt {
          Some(g) => g.loop_env_stack.pop().unwrap()
          _ => Environment::new(parent=Some(env))
        }
      } else {
        let e = Environment::new(parent=Some(env))
        match init {
          Some(init_stmt) => {
            let _ = self.exec_stmt(init_stmt, e)
          }
          None => ()
        }
        e
      }
      let mut first_iteration = resuming_loop // skip condition on first resumed iteration
      let mut completion : Value = Undefined
      while true {
        if first_iteration {
          first_iteration = false
        } else {
          match cond {
            Some(c) => if !is_truthy(self.eval_expr(c, for_env)) { break }
            None => ()
          }
        }
        // Per-iteration scoping: create a new scope with copies of loop vars
        let iter_env = if has_lexical_vars {
          let ie = Environment::new(parent=Some(env))
          for v in loop_vars {
            ie.def(v, for_env.get(v), LetBinding)
          }
          ie
        } else {
          for_env
        }
        let mut do_continue = false
        let body_signal = self.exec_stmt(body, iter_env) catch {
          e => {
            if e is YieldSignal(_) {
              // Yield inside for loop body — save for_env for resume
              match gen_opt {
                Some(g) => g.loop_env_stack.push(for_env)
                _ => ()
              }
            }
            raise e
          }
        }
        match body_signal {
          Normal(v) => completion = v
          ReturnSignal(v) => return ReturnSignal(v)
          BreakSignal(v, None) => {
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              completion = bv.unwrap_or(completion)
              break
            } else {
              return BreakSignal(bv, Some(l))
            }
          ContinueSignal(v, None) => {
            completion = v.unwrap_or(completion)
            do_continue = true
          }
          ContinueSignal(cv, Some(l)) =>
            if label == Some(l) {
              completion = cv.unwrap_or(completion)
              do_continue = true
            } else {
              return ContinueSignal(cv, Some(l))
            }
        }
        // Copy iteration values back to for_env for update expression
        if has_lexical_vars {
          for v in loop_vars {
            for_env.assign(v, iter_env.get(v))
          }
        }
        if do_continue {
          match update {
            Some(u) => {
              let _ = self.eval_expr(u, for_env)
            }
            None => ()
          }
          continue
        }
        match update {
          Some(u) => {
            let _ = self.eval_expr(u, for_env)
          }
          None => ()
        }
      }
      Normal(completion)
    }
    FuncDecl(name, params, body, _) => {
      validate_function_signature(self.strict, Some(name), params, body)
      // Check if this was already hoisted - if so, don't re-create the function.
      // Function declarations at the top level (var scope) are fully handled
      // during hoisting and should be no-ops during execution.
      let already_hoisted = match env.bindings.get(name) {
        Some(binding) => binding.kind == VarBinding
        None => false
      }
      if already_hoisted && env.is_var_scope {
        // Function was hoisted; no-op during execution
        Normal(Undefined)
      } else {
        let func_data : FuncData = {
          name: Some(name),
          params,
          body,
          closure: env,
          strict: is_function_strict(self.strict, body),
        }
        let func_val = make_func(func_data)
        // For non-strict eval execution, function declarations are hoisted into
        // var_env but executed in exec_env. Reconcile assignment back to var_env.
        if env.bindings.contains(name) {
          env.assign(name, func_val)
        } else if should_reconcile_eval_function_decl(env, name) {
          env.assign_var(name, func_val)
        } else {
          env.def(name, func_val, VarBinding)
        }
        // Annex B.3.3: propagate block-level function to function scope's var binding
        if self.annex_b && !self.strict && !env.is_var_scope {
          let var_env = env.find_var_env()
          match var_env.bindings.get(name) {
            Some(binding) =>
              if binding.kind == VarBinding {
                binding.value = func_val
              }
            None => ()
          }
        }
        Normal(Undefined)
      }
    }
    ReturnStmt(expr, _) => {
      let value : Value = match expr {
        Some(e) => self.eval_expr(e, env)
        None => Undefined
      }
      ReturnSignal(value)
    }
    BreakStmt(label, _) => BreakSignal(None, label)
    ContinueStmt(label, _) => ContinueSignal(None, label)
    ThrowStmt(expr, _) => {
      let value = self.eval_expr(expr, env)
      raise JsException(value)
    }
    TryCatchStmt(try_body, catch_param, catch_body, finally_body, _) =>
      self.exec_try_catch(try_body, catch_param, catch_body, finally_body, env)
    SwitchStmt(discriminant, cases, _) => {
      let disc_val = self.eval_expr(discriminant, env)
      let mut match_idx = -1
      let mut default_idx = -1
      for i = 0; i < cases.length(); i = i + 1 {
        match cases[i].condition {
          Some(test_expr) =>
            if match_idx < 0 {
              let test_val = self.eval_expr(test_expr, env)
              if strict_equal(disc_val, test_val) {
                match_idx = i
              }
            }
          None => default_idx = i
        }
      }
      let start = if match_idx >= 0 {
        match_idx
      } else if default_idx >= 0 {
        default_idx
      } else {
        cases.length()
      }
      // Create a new lexical environment for the switch block
      // so that let/const declarations are scoped to the switch
      let switch_env = Environment::new(parent=Some(env))
      let mut completion : Value = Undefined
      for i = start; i < cases.length(); i = i + 1 {
        for stmt in cases[i].body {
          match self.exec_stmt(stmt, switch_env) {
            Normal(v) => completion = v
            BreakSignal(v, None) => {
              // UpdateEmpty: use break's carried value if non-empty, otherwise accumulated
              let cv = match v {
                None => completion
                Some(val) => val
              }
              return Normal(cv)
            }
            BreakSignal(v, Some(l)) => {
              let cv = match v {
                None => Some(completion)
                some => some
              }
              return BreakSignal(cv, Some(l))
            }
            ContinueSignal(v, label) => {
              let cv = match v {
                None => Some(completion)
                some => some
              }
              return ContinueSignal(cv, label)
            }
            other => return other
          }
        }
      }
      Normal(completion)
    }
    DoWhileStmt(body, cond, _) => {
      let gen_opt = current_generator.val
      let resuming_loop = match gen_opt {
        Some(g) => g.loop_env_stack.length() > 0
        _ => false
      }
      if resuming_loop {
        match gen_opt {
          Some(g) => {
            let _ = g.loop_env_stack.pop()
          }
          _ => ()
        }
      }
      let mut completion : Value = Undefined
      while true {
        let body_signal = self.exec_stmt(body, env) catch {
          e => {
            if e is YieldSignal(_) {
              match gen_opt {
                Some(g) => g.loop_env_stack.push(env)
                _ => ()
              }
            }
            raise e
          }
        }
        match body_signal {
          Normal(v) => completion = v
          ReturnSignal(v) => return ReturnSignal(v)
          BreakSignal(v, None) => {
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              completion = bv.unwrap_or(completion)
              break
            } else {
              return BreakSignal(bv, Some(l))
            }
          ContinueSignal(v, None) => completion = v.unwrap_or(completion)
          ContinueSignal(cv, Some(l)) =>
            if label == Some(l) {
              completion = cv.unwrap_or(completion)
            } else {
              return ContinueSignal(cv, Some(l))
            }
        }
        if !is_truthy(self.eval_expr(cond, env)) {
          break
        }
      }
      Normal(completion)
    }
    ForInStmt(var_kind, name, obj_expr, body, _) => {
      let obj = self.eval_expr(obj_expr, env)
      let keys = collect_for_in_keys(obj)
      let mut completion : Value = Undefined
      for key in keys {
        let body_env = Environment::new(parent=Some(env))
        match var_kind {
          Some(kind) => {
            let bk : BindingKind = match kind {
              LetKind => LetBinding
              ConstKind => ConstBinding
              VarKind => VarBinding
            }
            body_env.def(name, String_(key), bk)
          }
          None =>
            env.assign(name, String_(key)) catch {
              @errors.ReferenceError(_) =>
                if !self.strict {
                  self.global.def(name, String_(key), VarBinding)
                  self.mirror_to_global(name, String_(key), configurable=true)
                } else {
                  raise @errors.ReferenceError(message="\{name} is not defined")
                }
              e => raise e
            }
        }
        match self.exec_stmt(body, body_env) {
          Normal(v) => completion = v
          ReturnSignal(v) => return ReturnSignal(v)
          BreakSignal(v, None) => {
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              completion = bv.unwrap_or(completion)
              break
            } else {
              return BreakSignal(bv, Some(l))
            }
          ContinueSignal(v, None) => {
            completion = v.unwrap_or(completion)
            continue
          }
          ContinueSignal(cv, Some(l)) =>
            if label == Some(l) {
              completion = cv.unwrap_or(completion)
              continue
            } else {
              return ContinueSignal(cv, Some(l))
            }
        }
      }
      Normal(completion)
    }
    ForOfStmt(var_kind, name, iterable_expr, body, loc) => {
      // Check if we're resuming inside a generator for-of
      let gen_opt = current_generator.val
      let resuming_for_of = match gen_opt {
        Some(g) => g.for_of_resume
        _ => false
      }
      let (iterator, next_method) = if resuming_for_of {
        // Restore saved iterator state
        match gen_opt {
          Some(g) => {
            g.for_of_resume = false
            let it = g.for_of_iterator
            let nm = g.for_of_next
            g.for_of_iterator = Undefined
            g.for_of_next = Undefined
            (it, nm)
          }
          _ => abort("unreachable: for-of resume without generator")
        }
      } else {
        let iterable = self.eval_expr(iterable_expr, env)

        // Try to get the iterator via Symbol.iterator protocol
        let iterator_sym = get_iterator_symbol()
        let iterator_method = self.get_computed_property(
          iterable,
          Symbol(iterator_sym),
          loc,
        )

        // Get the iterator object by calling the iterator method
        let it = match iterator_method {
          Object(data) =>
            match data.callable {
              Some(_) => self.call_value(iterator_method, iterable, [], loc)
              None =>
                raise @errors.TypeError(
                  message="Result of the Symbol.iterator method is not an object",
                )
            }
          Undefined =>
            // Fall back to built-in iteration for arrays and strings
            match iterable {
              Array(arr) => make_array_iterator_value(arr)
              String_(s) => make_string_iterator_value(s)
              _ =>
                raise @errors.TypeError(
                  message="\{type_of(iterable)} is not iterable (cannot read property Symbol(Symbol.iterator))",
                )
            }
          _ =>
            raise @errors.TypeError(
              message="Result of the Symbol.iterator method is not an object",
            )
        }

        // Get the next method from the iterator (walk prototype chain)
        let nm = match it {
          Object(iter_data) =>
            match iter_data.properties.get("next") {
              Some(next_fn) => next_fn
              None => {
                let mut found : Value = Undefined
                let mut current = iter_data.prototype
                while true {
                  match current {
                    Object(proto_data) =>
                      match proto_data.properties.get("next") {
                        Some(next_fn) => {
                          found = next_fn
                          break
                        }
                        None => current = proto_data.prototype
                      }
                    _ => break
                  }
                }
                match found {
                  Undefined =>
                    raise @errors.TypeError(
                      message="iterator.next is not a function",
                    )
                  _ => found
                }
              }
            }
          _ => raise @errors.TypeError(message="Iterator is not an object")
        }
        (it, nm)
      }
      // If resuming, first resume the body without calling next()
      let mut first_resume = resuming_for_of
      let mut completion : Value = Undefined
      // Iterate using the iterator protocol
      while true {
        if first_resume {
          // On resume, the body was interrupted by yield — replay it
          // The loop variable is already bound from before the yield
          first_resume = false
          let body_env = Environment::new(parent=Some(env))
          // We need the loop variable bound. Since we're replaying the body,
          // gen.resuming will handle the yield. But we need the loop variable.
          // It's in the saved loop env stack.
          let resuming_loop = match gen_opt {
            Some(g) => g.loop_env_stack.length() > 0
            _ => false
          }
          let actual_body_env = if resuming_loop {
            match gen_opt {
              Some(g) => g.loop_env_stack.pop().unwrap()
              _ => body_env
            }
          } else {
            body_env
          }
          let body_signal = self.exec_stmt(body, actual_body_env) catch {
            e => {
              if e is YieldSignal(_) {
                match gen_opt {
                  Some(g) => {
                    g.for_of_iterator = iterator
                    g.for_of_next = next_method
                    g.for_of_resume = true
                    g.loop_env_stack.push(actual_body_env)
                  }
                  _ => ()
                }
              }
              raise e
            }
          }
          match body_signal {
            Normal(v) => completion = v
            ReturnSignal(v) => return ReturnSignal(v)
            BreakSignal(v, None) => {
              completion = v.unwrap_or(completion)
              break
            }
            BreakSignal(bv, Some(l)) =>
              if label == Some(l) {
                completion = bv.unwrap_or(completion)
                break
              } else {
                return BreakSignal(bv, Some(l))
              }
            ContinueSignal(v, None) => {
              completion = v.unwrap_or(completion)
              continue
            }
            ContinueSignal(cv, Some(l)) =>
              if label == Some(l) {
                completion = cv.unwrap_or(completion)
                continue
              } else {
                return ContinueSignal(cv, Some(l))
              }
          }
          // After resume body completes, continue the loop normally below
          continue
        }
        // Call iterator.next()
        let result = self.call_value(next_method, iterator, [], loc)

        // Get 'done' and 'value' from the result
        let (done, value) = match result {
          Object(result_data) => {
            let done_val = match result_data.properties.get("done") {
              Some(v) => is_truthy(v)
              None => false
            }
            let value_val = match result_data.properties.get("value") {
              Some(v) => v
              None => Undefined
            }
            (done_val, value_val)
          }
          _ =>
            raise @errors.TypeError(message="Iterator result is not an object")
        }

        // If done, exit the loop
        if done {
          break
        }

        // Bind the value to the loop variable
        let body_env = Environment::new(parent=Some(env))
        match var_kind {
          Some(VarKind) =>
            if env.bindings.contains(name) {
              env.assign(name, value)
            } else {
              env.def(name, value, VarBinding)
            }
          Some(kind) => {
            let bk : BindingKind = match kind {
              LetKind => LetBinding
              ConstKind => ConstBinding
              _ => fail("unreachable")
            }
            body_env.def(name, value, bk)
          }
          None => env.assign(name, value)
        }

        // Execute the loop body
        let body_signal = self.exec_stmt(body, body_env) catch {
          e => {
            if e is YieldSignal(_) {
              // Save for-of state for resume
              match gen_opt {
                Some(g) => {
                  g.for_of_iterator = iterator
                  g.for_of_next = next_method
                  g.for_of_resume = true
                  g.loop_env_stack.push(body_env)
                }
                _ => ()
              }
            } else {
              // Close iterator on exception (IteratorClose)
              close_iterator(self, iterator, loc) catch {
                _ => ()
              }
            }
            raise e
          }
        }
        match body_signal {
          Normal(v) => completion = v
          ReturnSignal(v) => {
            close_iterator(self, iterator, loc) catch {
              _ => ()
            }
            return ReturnSignal(v)
          }
          BreakSignal(v, None) => {
            close_iterator(self, iterator, loc) catch {
              _ => ()
            }
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              close_iterator(self, iterator, loc) catch {
                _ => ()
              }
              completion = bv.unwrap_or(completion)
              break
            } else {
              close_iterator(self, iterator, loc) catch {
                _ => ()
              }
              return BreakSignal(bv, Some(l))
            }
          ContinueSignal(v, None) => {
            completion = v.unwrap_or(completion)
            continue
          }
          ContinueSignal(cv, Some(l)) =>
            if label == Some(l) {
              completion = cv.unwrap_or(completion)
              continue
            } else {
              close_iterator(self, iterator, loc) catch {
                _ => ()
              }
              return ContinueSignal(cv, Some(l))
            }
        }
      }
      Normal(completion)
    }
    ForInStmtPat(var_kind, pattern, obj_expr, body, _) => {
      let obj = self.eval_expr(obj_expr, env)
      let keys = collect_for_in_keys(obj)
      let mut completion : Value = Undefined
      for key in keys {
        let body_env = Environment::new(parent=Some(env))
        match var_kind {
          Some(kind) => {
            let bk : BindingKind = match kind {
              LetKind => LetBinding
              ConstKind => ConstBinding
              VarKind => VarBinding
            }
            let bind_env = match kind {
              VarKind => env
              _ => body_env
            }
            self.bind_pattern(pattern, String_(key), bind_env, bk)
          }
          None => self.assign_pattern(pattern, String_(key), env)
        }
        match self.exec_stmt(body, body_env) {
          Normal(v) => completion = v
          ReturnSignal(v) => return ReturnSignal(v)
          BreakSignal(v, None) => {
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              completion = bv.unwrap_or(completion)
              break
            } else {
              return BreakSignal(bv, Some(l))
            }
          ContinueSignal(v, None) => {
            completion = v.unwrap_or(completion)
            continue
          }
          ContinueSignal(cv, Some(l)) =>
            if label == Some(l) {
              completion = cv.unwrap_or(completion)
              continue
            } else {
              return ContinueSignal(cv, Some(l))
            }
        }
      }
      Normal(completion)
    }
    ForOfStmtPat(var_kind, pattern, iterable_expr, body, loc) => {
      let iterable = self.eval_expr(iterable_expr, env)

      // Try to get the iterator via Symbol.iterator protocol
      let iterator_sym = get_iterator_symbol()
      let iterator_method = self.get_computed_property(
        iterable,
        Symbol(iterator_sym),
        loc,
      )

      // Get the iterator object
      let iterator = match iterator_method {
        Object(data) =>
          match data.callable {
            Some(_) => self.call_value(iterator_method, iterable, [], loc)
            None =>
              raise @errors.TypeError(
                message="Result of the Symbol.iterator method is not an object",
              )
          }
        Undefined =>
          match iterable {
            Array(arr) => make_array_iterator_value(arr)
            String_(s) => make_string_iterator_value(s)
            _ =>
              raise @errors.TypeError(
                message="\{type_of(iterable)} is not iterable",
              )
          }
        _ =>
          raise @errors.TypeError(
            message="Result of the Symbol.iterator method is not an object",
          )
      }

      // Get the next method
      let next_method = match iterator {
        Object(iter_data) =>
          match iter_data.properties.get("next") {
            Some(next_fn) => next_fn
            None => {
              let mut found : Value = Undefined
              let mut current = iter_data.prototype
              while true {
                match current {
                  Object(proto_data) =>
                    match proto_data.properties.get("next") {
                      Some(next_fn) => {
                        found = next_fn
                        break
                      }
                      None => current = proto_data.prototype
                    }
                  _ => break
                }
              }
              match found {
                Undefined =>
                  raise @errors.TypeError(
                    message="iterator.next is not a function",
                  )
                _ => found
              }
            }
          }
        _ => raise @errors.TypeError(message="Iterator is not an object")
      }

      // Iterate using the iterator protocol
      let mut completion : Value = Undefined
      while true {
        let result = self.call_value(next_method, iterator, [], loc)
        let (done, value) = match result {
          Object(result_data) => {
            let done_val = match result_data.properties.get("done") {
              Some(v) => is_truthy(v)
              None => false
            }
            let value_val = match result_data.properties.get("value") {
              Some(v) => v
              None => Undefined
            }
            (done_val, value_val)
          }
          _ =>
            raise @errors.TypeError(message="Iterator result is not an object")
        }
        if done {
          break
        }
        let body_env = Environment::new(parent=Some(env))
        match var_kind {
          Some(kind) => {
            let bk : BindingKind = match kind {
              LetKind => LetBinding
              ConstKind => ConstBinding
              VarKind => VarBinding
            }
            let bind_env = match kind {
              VarKind => env
              _ => body_env
            }
            self.bind_pattern(pattern, value, bind_env, bk)
          }
          None => self.assign_pattern(pattern, value, env)
        }
        let body_signal = self.exec_stmt(body, body_env) catch {
          e => {
            close_iterator(self, iterator, loc) catch {
              _ => ()
            }
            raise e
          }
        }
        match body_signal {
          Normal(v) => completion = v
          ReturnSignal(v) => {
            close_iterator(self, iterator, loc) catch {
              _ => ()
            }
            return ReturnSignal(v)
          }
          BreakSignal(v, None) => {
            close_iterator(self, iterator, loc) catch {
              _ => ()
            }
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              close_iterator(self, iterator, loc) catch {
                _ => ()
              }
              completion = bv.unwrap_or(completion)
              break
            } else {
              close_iterator(self, iterator, loc) catch {
                _ => ()
              }
              return BreakSignal(bv, Some(l))
            }
          ContinueSignal(v, None) => {
            completion = v.unwrap_or(completion)
            continue
          }
          ContinueSignal(cv, Some(l)) =>
            if label == Some(l) {
              completion = cv.unwrap_or(completion)
              continue
            } else {
              close_iterator(self, iterator, loc) catch {
                _ => ()
              }
              return ContinueSignal(cv, Some(l))
            }
        }
      }
      Normal(completion)
    }
    ForInExpr(lhs_expr, obj_expr, body, _) => {
      let obj = self.eval_expr(obj_expr, env)
      let keys = collect_for_in_keys(obj)
      let mut completion : Value = Undefined
      for key in keys {
        let body_env = Environment::new(parent=Some(env))
        self.assign_to_expr(lhs_expr, String_(key), env)
        match self.exec_stmt(body, body_env) {
          Normal(v) => completion = v
          ReturnSignal(v) => return ReturnSignal(v)
          BreakSignal(v, None) => {
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              completion = bv.unwrap_or(completion)
              break
            } else {
              return BreakSignal(bv, Some(l))
            }
          ContinueSignal(v, None) => {
            completion = v.unwrap_or(completion)
            continue
          }
          ContinueSignal(cv, Some(l)) =>
            if label == Some(l) {
              completion = cv.unwrap_or(completion)
              continue
            } else {
              return ContinueSignal(cv, Some(l))
            }
        }
      }
      Normal(completion)
    }
    ForOfExpr(lhs_expr, iterable_expr, body, loc) => {
      let iterable = self.eval_expr(iterable_expr, env)
      let iterator_sym = get_iterator_symbol()
      let iterator_method = self.get_computed_property(
        iterable,
        Symbol(iterator_sym),
        loc,
      )
      let iterator = match iterator_method {
        Object(data) =>
          match data.callable {
            Some(_) => self.call_value(iterator_method, iterable, [], loc)
            None =>
              raise @errors.TypeError(
                message="Result of the Symbol.iterator method is not an object",
              )
          }
        Undefined =>
          match iterable {
            Array(arr) => make_array_iterator_value(arr)
            String_(s) => make_string_iterator_value(s)
            _ =>
              raise @errors.TypeError(
                message="\{type_of(iterable)} is not iterable",
              )
          }
        _ =>
          raise @errors.TypeError(
            message="Result of the Symbol.iterator method is not an object",
          )
      }
      let next_method = match iterator {
        Object(iter_data) =>
          match iter_data.properties.get("next") {
            Some(next_fn) => next_fn
            None => {
              let mut found : Value = Undefined
              let mut current = iter_data.prototype
              while true {
                match current {
                  Object(proto_data) =>
                    match proto_data.properties.get("next") {
                      Some(next_fn) => {
                        found = next_fn
                        break
                      }
                      None => current = proto_data.prototype
                    }
                  _ => break
                }
              }
              match found {
                Undefined =>
                  raise @errors.TypeError(
                    message="iterator.next is not a function",
                  )
                _ => found
              }
            }
          }
        _ => raise @errors.TypeError(message="Iterator is not an object")
      }
      let mut completion : Value = Undefined
      while true {
        let result = self.call_value(next_method, iterator, [], loc)
        let (done, value) = match result {
          Object(result_data) => {
            let done_val = match result_data.properties.get("done") {
              Some(v) => is_truthy(v)
              None => false
            }
            let value_val = match result_data.properties.get("value") {
              Some(v) => v
              None => Undefined
            }
            (done_val, value_val)
          }
          _ =>
            raise @errors.TypeError(message="Iterator result is not an object")
        }
        if done {
          break
        }
        let body_env = Environment::new(parent=Some(env))
        self.assign_to_expr(lhs_expr, value, env)
        match self.exec_stmt(body, body_env) {
          Normal(v) => completion = v
          ReturnSignal(v) => return ReturnSignal(v)
          BreakSignal(v, None) => {
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              completion = bv.unwrap_or(completion)
              break
            } else {
              return BreakSignal(bv, Some(l))
            }
          ContinueSignal(v, None) => {
            completion = v.unwrap_or(completion)
            continue
          }
          ContinueSignal(cv, Some(l)) =>
            if label == Some(l) {
              completion = cv.unwrap_or(completion)
              continue
            } else {
              return ContinueSignal(cv, Some(l))
            }
        }
      }
      Normal(completion)
    }
    DestructureDecl(kind, pattern, init_expr, _) => {
      let bk : BindingKind = match kind {
        LetKind => LetBinding
        ConstKind => ConstBinding
        VarKind => VarBinding
      }
      let value = self.eval_expr(init_expr, env)
      self.bind_pattern(pattern, value, env, bk)
      Normal(Undefined)
    }
    FuncDeclExt(name, params, rest_param, body, _) => {
      validate_function_signature_ext(
        self.strict,
        Some(name),
        params,
        rest_param,
        body,
      )
      // Same hoisting optimization as FuncDecl
      let already_hoisted = match env.bindings.get(name) {
        Some(binding) => binding.kind == VarBinding
        None => false
      }
      if already_hoisted && env.is_var_scope {
        Normal(Undefined)
      } else {
        let func_data : FuncDataExt = {
          name: Some(name),
          params,
          rest_param,
          body,
          closure: env,
          strict: is_function_strict(self.strict, body),
        }
        let func_val = make_func_ext(func_data)
        if env.bindings.contains(name) {
          env.assign(name, func_val)
        } else if should_reconcile_eval_function_decl(env, name) {
          env.assign_var(name, func_val)
        } else {
          env.def(name, func_val, VarBinding)
        }
        // Annex B.3.3: propagate block-level function to function scope's var binding
        if self.annex_b && !self.strict && !env.is_var_scope {
          let var_env = env.find_var_env()
          match var_env.bindings.get(name) {
            Some(binding) =>
              if binding.kind == VarBinding {
                binding.value = func_val
              }
            None => ()
          }
        }
        Normal(Undefined)
      }
    }
    GeneratorDecl(name, params, body, _) => {
      validate_function_signature(self.strict, Some(name), params, body)
      let gen_func = self.make_generator_function(
        Some(name),
        params,
        None,
        body,
        env,
      )
      if env.bindings.contains(name) {
        env.assign(name, gen_func)
      } else if should_reconcile_eval_function_decl(env, name) {
        env.assign_var(name, gen_func)
      } else {
        env.def(name, gen_func, VarBinding)
      }
      Normal(Undefined)
    }
    GeneratorDeclExt(name, params, rest_param, body, _) => {
      validate_function_signature_ext(
        self.strict,
        Some(name),
        params,
        rest_param,
        body,
      )
      let gen_func = self.make_generator_function_ext(
        Some(name),
        params,
        rest_param,
        body,
        env,
      )
      if env.bindings.contains(name) {
        env.assign(name, gen_func)
      } else if should_reconcile_eval_function_decl(env, name) {
        env.assign_var(name, gen_func)
      } else {
        env.def(name, gen_func, VarBinding)
      }
      Normal(Undefined)
    }
    AsyncFuncDecl(name, params, body, _) => {
      validate_function_signature(self.strict, Some(name), params, body)
      let async_func = self.make_async_function(
        Some(name),
        params,
        None,
        body,
        env,
      )
      if env.bindings.contains(name) {
        env.assign(name, async_func)
      } else if should_reconcile_eval_function_decl(env, name) {
        env.assign_var(name, async_func)
      } else {
        env.def(name, async_func, VarBinding)
      }
      Normal(Undefined)
    }
    AsyncFuncDeclExt(name, params, rest_param, body, _) => {
      validate_function_signature_ext(
        self.strict,
        Some(name),
        params,
        rest_param,
        body,
      )
      let async_func = self.make_async_function_ext(
        Some(name),
        params,
        rest_param,
        body,
        env,
      )
      if env.bindings.contains(name) {
        env.assign(name, async_func)
      } else if should_reconcile_eval_function_decl(env, name) {
        env.assign_var(name, async_func)
      } else {
        env.def(name, async_func, VarBinding)
      }
      Normal(Undefined)
    }
    AsyncGeneratorDecl(name, params, body, _) => {
      validate_function_signature(self.strict, Some(name), params, body)
      let gen_func = self.make_async_generator_function(
        Some(name),
        params,
        None,
        body,
        env,
      )
      if env.bindings.contains(name) {
        env.assign(name, gen_func)
      } else if should_reconcile_eval_function_decl(env, name) {
        env.assign_var(name, gen_func)
      } else {
        env.def(name, gen_func, VarBinding)
      }
      Normal(Undefined)
    }
    AsyncGeneratorDeclExt(name, params, rest_param, body, _) => {
      validate_function_signature_ext(
        self.strict,
        Some(name),
        params,
        rest_param,
        body,
      )
      let gen_func = self.make_async_generator_function_ext(
        Some(name),
        params,
        rest_param,
        body,
        env,
      )
      if env.bindings.contains(name) {
        env.assign(name, gen_func)
      } else if should_reconcile_eval_function_decl(env, name) {
        env.assign_var(name, gen_func)
      } else {
        env.def(name, gen_func, VarBinding)
      }
      Normal(Undefined)
    }
    LabeledStmt(lbl, body, _) =>
      match self.exec_stmt(body, env, label=Some(lbl)) {
        BreakSignal(v, Some(l)) =>
          if l == lbl {
            Normal(v.unwrap_or(Undefined))
          } else {
            BreakSignal(v, Some(l))
          }
        other => other
      }
    ClassDecl(name, superclass, methods, _) => {
      let class_val = self.create_class(name, superclass, methods, env)
      // Class was hoisted with TDZ, initialize it now
      if env.bindings.contains(name) {
        env.initialize(name, class_val)
      } else {
        env.def(name, class_val, LetBinding)
      }
      Normal(Undefined)
    }
    // ES Module declarations
    ImportDecl(default_import, specifiers, namespace_import, source, loc) =>
      self.exec_import(
        default_import, specifiers, namespace_import, source, env, loc,
      )
    ExportNamedDecl(decl, specifiers, source, loc) =>
      self.exec_export_named(decl, specifiers, source, env, loc)
    ExportDefaultDecl(expr, _) => {
      let value = self.eval_expr(expr, env)
      self.module_exports["default"] = value
      // Named default exports also bind the name locally
      match expr {
        FuncExpr(Some(name), _, _, _) | FuncExprExt(Some(name), _, _, _, _) =>
          if !env.bindings.contains(name) {
            env.def(name, value, LetBinding)
          }
        GeneratorExpr(Some(name), _, _, _)
        | GeneratorExprExt(Some(name), _, _, _, _) =>
          if !env.bindings.contains(name) {
            env.def(name, value, LetBinding)
          }
        ClassExpr(Some(name), _, _, _) =>
          if !env.bindings.contains(name) {
            env.def(name, value, LetBinding)
          }
        _ => ()
      }
      Normal(Undefined)
    }
    ExportAllDecl(ns_alias, source, loc) =>
      self.exec_export_all(ns_alias, source, loc)
    WithStmt(expr, body, _) => {
      // In strict mode, 'with' is always a SyntaxError
      if self.strict {
        raise @errors.SyntaxError(
          message="Strict mode code may not include a with statement",
        )
      }
      let raw_obj = self.eval_expr(expr, env)
      // Per spec: ToObject() the expression result. Throw TypeError for null/undefined.
      let obj = match raw_obj {
        Null => raise @errors.TypeError(message="Cannot convert null to object")
        Undefined =>
          raise @errors.TypeError(message="Cannot convert undefined to object")
        String_(s) => {
          // Box string primitive to String wrapper object
          let str_proto = env.get("[[StringPrototype]]") catch { _ => Null }
          let props : Map[String, Value] = {}
          let utf16_units = string_to_utf16(s)
          props["length"] = Number(utf16_units.length().to_double())
          props["[[PrimitiveValue]]"] = String_(s)
          // Add character indices as properties (UTF-16 code units)
          for i = 0; i < utf16_units.length(); i = i + 1 {
            let unit = utf16_units[i]
            let ch_str = if unit <= 0xFFFF {
              String::make(1, unit.unsafe_to_char())
            } else {
              String::make(1, unit.unsafe_to_char())
            }
            props[i.to_string()] = String_(ch_str)
          }
          Object({
            properties: props,
            symbol_properties: {},
            prototype: str_proto,
            callable: None,
            class_name: "String",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
        }
        Number(n) => {
          // Box number primitive to Number wrapper object
          let num_proto = env.get("[[NumberPrototype]]") catch { _ => Null }
          let props : Map[String, Value] = {}
          props["[[PrimitiveValue]]"] = Number(n)
          Object({
            properties: props,
            symbol_properties: {},
            prototype: num_proto,
            callable: None,
            class_name: "Number",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
        }
        Bool(b) => {
          // Box boolean primitive to Boolean wrapper object
          let bool_proto = env.get("[[BooleanPrototype]]") catch { _ => Null }
          let props : Map[String, Value] = {}
          props["[[PrimitiveValue]]"] = Bool(b)
          Object({
            properties: props,
            symbol_properties: {},
            prototype: bool_proto,
            callable: None,
            class_name: "Boolean",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
        }
        Object(_) => raw_obj
        _ => raw_obj
      }
      // Create an object environment record with live object reference
      // Property lookups/assignments go directly through the object
      let with_env = Environment::new(parent=Some(env))
      with_env.with_object = Some(obj)
      self.exec_stmt(body, with_env)
    }
  }
}

///|
fn collect_for_in_keys(obj : Value) -> Array[String] raise Error {
  let keys : Array[String] = []
  let seen : Map[String, Bool] = {}
  let mut current = obj
  while true {
    match current {
      Proxy(proxy_data) => {
        // For Proxy, enumerate the target's enumerable properties
        let target = match proxy_data.target {
          Some(t) => t
          None =>
            raise @errors.TypeError(
              message="Cannot perform 'ownKeys' on a proxy that has been revoked",
            )
        }
        // Delegate to target for key enumeration
        current = target
        continue
      }
      Object(data) => {
        // TypedArray: enumerate numeric indices as keys
        if is_typedarray_class(data.class_name) {
          let ta_len = match data.properties.get("[[ArrayLength]]") {
            Some(Number(n)) => n.to_int()
            _ => 0
          }
          for i = 0; i < ta_len; i = i + 1 {
            let k = i.to_string()
            if !seen.contains(k) {
              seen[k] = true
              keys.push(k)
            }
          }
        }
        let sorted = sort_property_keys(data.properties)
        for k in sorted {
          if !seen.contains(k) {
            // Skip internal slots (e.g., [[BooleanData]], [[NumberData]], [[StringData]])
            if k.has_prefix("[[") {
              continue
            }
            seen[k] = true
            let enumerable = match data.descriptors.get(k) {
              Some(d) => d.enumerable
              None => true
            }
            if enumerable {
              keys.push(k)
            }
          }
        }
        current = data.prototype
      }
      Array(data) => {
        for i = 0; i < data.elements.length(); i = i + 1 {
          let k = i.to_string()
          if !seen.contains(k) {
            seen[k] = true
            keys.push(k)
          }
        }
        break
      }
      _ => break
    }
  }
  keys
}

///|
fn is_declaration_stmt(stmt : @ast.Stmt) -> Bool {
  match stmt {
    VarDecl(_, _, _, _)
    | DestructureDecl(_, _, _, _)
    | FuncDecl(_, _, _, _)
    | FuncDeclExt(_, _, _, _, _)
    | GeneratorDecl(_, _, _, _)
    | GeneratorDeclExt(_, _, _, _, _)
    | AsyncFuncDecl(_, _, _, _)
    | AsyncFuncDeclExt(_, _, _, _, _)
    | AsyncGeneratorDecl(_, _, _, _)
    | AsyncGeneratorDeclExt(_, _, _, _, _)
    | ClassDecl(_, _, _, _)
    | ImportDecl(_, _, _, _, _)
    | ExportNamedDecl(_, _, _, _)
    | ExportDefaultDecl(_, _)
    | ExportAllDecl(_, _, _) => true
    _ => false
  }
}

///|
fn Interpreter::exec_stmts(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  env : Environment,
) -> Signal raise Error {
  let mut last : Value = Undefined
  for stmt in stmts {
    match self.exec_stmt(stmt, env) {
      Normal(v) =>
        // Per spec, declarations have empty completion values that don't update
        // the statement list's value. Only non-declaration statements update it.
        if !is_declaration_stmt(stmt) {
          last = v
        }
      BreakSignal(v, label) => {
        // UpdateEmpty: if break's value is None (empty), use accumulated value
        let cv = match v {
          None => Some(last)
          some => some
        }
        return BreakSignal(cv, label)
      }
      ContinueSignal(v, label) => {
        let cv = match v {
          None => Some(last)
          some => some
        }
        return ContinueSignal(cv, label)
      }
      other => return other
    }
  }
  Normal(last)
}

///|
/// Collect names from a destructuring pattern (for eval var name collection).
fn collect_pattern_var_names(
  pattern : @ast.Pattern,
  names : Array[String],
) -> Unit {
  match pattern {
    IdentPat(name) => names.push(name)
    DefaultPat(inner_pat, _) => collect_pattern_var_names(inner_pat, names)
    AssignTarget(_) => ()
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => collect_pattern_var_names(p, names)
          None => ()
        }
      }
      match rest {
        Some(p) => collect_pattern_var_names(p, names)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        collect_pattern_var_names(prop.value, names)
      }
      match rest {
        Some(p) => collect_pattern_var_names(p, names)
        None => ()
      }
    }
  }
}

///|
fn add_lexical_decl_name(
  lexical_names : Map[String, Bool],
  name : String,
) -> Unit raise Error {
  if lexical_names.contains(name) {
    raise @errors.SyntaxError(
      message="Identifier '\{name}' has already been declared",
    )
  }
  lexical_names[name] = true
}

///|
fn collect_pattern_decl_names(
  pattern : @ast.Pattern,
  names : Map[String, Bool],
  lexical? : Bool = false,
) -> Unit raise Error {
  match pattern {
    IdentPat(name) =>
      if lexical {
        add_lexical_decl_name(names, name)
      } else {
        names[name] = true
      }
    DefaultPat(inner_pat, _) =>
      collect_pattern_decl_names(inner_pat, names, lexical~)
    AssignTarget(_) => ()
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => collect_pattern_decl_names(p, names, lexical~)
          None => ()
        }
      }
      match rest {
        Some(p) => collect_pattern_decl_names(p, names, lexical~)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        collect_pattern_decl_names(prop.value, names, lexical~)
      }
      match rest {
        Some(p) => collect_pattern_decl_names(p, names, lexical~)
        None => ()
      }
    }
  }
}

///|
fn collect_block_lexical_decl_names_from_stmt(
  stmt : @ast.Stmt,
  lexical_names : Map[String, Bool],
  block_function_kinds : Map[String, Int],
  include_block_functions? : Bool = false,
  allow_duplicate_block_functions? : Bool = false,
) -> Unit raise Error {
  match stmt {
    VarDecl(LetKind, name, _, _) => add_lexical_decl_name(lexical_names, name)
    VarDecl(ConstKind, name, _, _) => add_lexical_decl_name(lexical_names, name)
    DestructureDecl(LetKind, pattern, _, _) =>
      collect_pattern_decl_names(pattern, lexical_names, lexical=true)
    DestructureDecl(ConstKind, pattern, _, _) =>
      collect_pattern_decl_names(pattern, lexical_names, lexical=true)
    ClassDecl(name, _, _, _) => add_lexical_decl_name(lexical_names, name)
    // Function declarations are lexical only in block statement lists.
    FuncDecl(name, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          if !(allow_duplicate_block_functions &&
            block_function_kinds.get(name) == Some(1)) {
            raise @errors.SyntaxError(
              message="Identifier '\{name}' has already been declared",
            )
          }
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 1
      }
    FuncDeclExt(name, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          if !(allow_duplicate_block_functions &&
            block_function_kinds.get(name) == Some(1)) {
            raise @errors.SyntaxError(
              message="Identifier '\{name}' has already been declared",
            )
          }
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 1
      }
    GeneratorDecl(name, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 2
      }
    GeneratorDeclExt(name, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 2
      }
    AsyncFuncDecl(name, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 2
      }
    AsyncFuncDeclExt(name, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 2
      }
    AsyncGeneratorDecl(name, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 2
      }
    AsyncGeneratorDeclExt(name, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 2
      }
    StmtList(inner_stmts, _) =>
      for inner in inner_stmts {
        collect_block_lexical_decl_names_from_stmt(
          inner,
          lexical_names,
          block_function_kinds,
          include_block_functions~,
          allow_duplicate_block_functions~,
        )
      }
    ExportNamedDecl(Some(decl), _, _, _) =>
      collect_block_lexical_decl_names_from_stmt(
        decl,
        lexical_names,
        block_function_kinds,
        include_block_functions~,
        allow_duplicate_block_functions~,
      )
    _ => ()
  }
}

///|
fn collect_block_var_decl_names_from_stmt(
  stmt : @ast.Stmt,
  var_names : Map[String, Bool],
  include_function_decls? : Bool = false,
) -> Unit raise Error {
  match stmt {
    VarDecl(VarKind, name, _, _) => var_names[name] = true
    FuncDecl(name, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    FuncDeclExt(name, _, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    GeneratorDecl(name, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    GeneratorDeclExt(name, _, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    AsyncFuncDecl(name, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    AsyncFuncDeclExt(name, _, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    AsyncGeneratorDecl(name, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    AsyncGeneratorDeclExt(name, _, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    DestructureDecl(VarKind, pattern, _, _) =>
      collect_pattern_decl_names(pattern, var_names)
    Block(inner_stmts, _) =>
      for inner in inner_stmts {
        collect_block_var_decl_names_from_stmt(
          inner,
          var_names,
          include_function_decls~,
        )
      }
    StmtList(inner_stmts, _) =>
      for inner in inner_stmts {
        collect_block_var_decl_names_from_stmt(
          inner,
          var_names,
          include_function_decls~,
        )
      }
    IfStmt(_, then_branch, else_branch, _) => {
      collect_block_var_decl_names_from_stmt(
        then_branch,
        var_names,
        include_function_decls~,
      )
      match else_branch {
        Some(eb) =>
          collect_block_var_decl_names_from_stmt(
            eb,
            var_names,
            include_function_decls~,
          )
        None => ()
      }
    }
    WhileStmt(_, body, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    DoWhileStmt(body, _, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    ForStmt(init, _, _, body, _) => {
      match init {
        Some(init_stmt) =>
          collect_block_var_decl_names_from_stmt(
            init_stmt,
            var_names,
            include_function_decls~,
          )
        None => ()
      }
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    }
    ForInStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) {
        var_names[name] = true
      }
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    }
    ForOfStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) {
        var_names[name] = true
      }
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    }
    ForInStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        collect_pattern_decl_names(pattern, var_names)
      }
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    }
    ForOfStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        collect_pattern_decl_names(pattern, var_names)
      }
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    }
    ForInExpr(_, _, body, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    ForOfExpr(_, _, body, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    LabeledStmt(_, inner, _) =>
      collect_block_var_decl_names_from_stmt(
        inner,
        var_names,
        include_function_decls~,
      )
    SwitchStmt(_, cases, _) =>
      for case_ in cases {
        for inner in case_.body {
          collect_block_var_decl_names_from_stmt(
            inner,
            var_names,
            include_function_decls~,
          )
        }
      }
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      for inner in try_body {
        collect_block_var_decl_names_from_stmt(
          inner,
          var_names,
          include_function_decls~,
        )
      }
      match catch_body {
        Some(cb) =>
          for inner in cb {
            collect_block_var_decl_names_from_stmt(
              inner,
              var_names,
              include_function_decls~,
            )
          }
        None => ()
      }
      match finally_body {
        Some(fb) =>
          for inner in fb {
            collect_block_var_decl_names_from_stmt(
              inner,
              var_names,
              include_function_decls~,
            )
          }
        None => ()
      }
    }
    WithStmt(_, body, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    ExportNamedDecl(Some(decl), _, _, _) =>
      collect_block_var_decl_names_from_stmt(
        decl,
        var_names,
        include_function_decls~,
      )
    // Do not recurse into function/class bodies when collecting VarDeclaredNames
    // for the surrounding block.
    _ => ()
  }
}

///|
fn validate_block_statement_list_early_errors(
  stmts : Array[@ast.Stmt],
  include_block_functions? : Bool = false,
  allow_duplicate_block_functions? : Bool = false,
  include_function_decls_in_var_names? : Bool = false,
) -> Unit raise Error {
  let lexical_names : Map[String, Bool] = {}
  let block_function_kinds : Map[String, Int] = {}
  for stmt in stmts {
    collect_block_lexical_decl_names_from_stmt(
      stmt,
      lexical_names,
      block_function_kinds,
      include_block_functions~,
      allow_duplicate_block_functions~,
    )
  }
  let var_names : Map[String, Bool] = {}
  for stmt in stmts {
    collect_block_var_decl_names_from_stmt(
      stmt,
      var_names,
      include_function_decls=include_function_decls_in_var_names,
    )
  }
  for name, _ in lexical_names {
    if var_names.contains(name) {
      raise @errors.SyntaxError(
        message="Identifier '\{name}' has already been declared",
      )
    }
  }
}

///|
fn validate_block_early_errors_expr(
  expr : @ast.Expr,
  strict_context : Bool,
) -> Unit raise Error {
  match expr {
    FuncExpr(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    FuncExprExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    ArrowFunc(_, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    ArrowFuncExt(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    GeneratorExpr(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    GeneratorExprExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    AsyncFuncExpr(_, _, body, _)
    | AsyncFuncExprExt(_, _, _, body, _)
    | AsyncArrowFunc(_, body, _)
    | AsyncArrowFuncExt(_, _, body, _)
    | AsyncGeneratorExpr(_, _, body, _)
    | AsyncGeneratorExprExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    AwaitExpr(inner, _) =>
      validate_block_early_errors_expr(inner, strict_context)
    ClassExpr(_, _, methods, _) =>
      for m in methods {
        // Class bodies are always strict.
        validate_block_early_errors_expr(m.value, true)
      }
    Binary(_, l, r, _) => {
      validate_block_early_errors_expr(l, strict_context)
      validate_block_early_errors_expr(r, strict_context)
    }
    Unary(_, e, _) => validate_block_early_errors_expr(e, strict_context)
    Assign(_, e, _) => validate_block_early_errors_expr(e, strict_context)
    Call(callee, args, _) => {
      validate_block_early_errors_expr(callee, strict_context)
      for a in args {
        validate_block_early_errors_expr(a, strict_context)
      }
    }
    Member(obj, _, _) => validate_block_early_errors_expr(obj, strict_context)
    Ternary(c, t, f, _) => {
      validate_block_early_errors_expr(c, strict_context)
      validate_block_early_errors_expr(t, strict_context)
      validate_block_early_errors_expr(f, strict_context)
    }
    Grouping(inner, _) =>
      validate_block_early_errors_expr(inner, strict_context)
    ObjectLit(props, _) =>
      for prop in props {
        validate_block_early_errors_expr(prop.key, strict_context)
        validate_block_early_errors_expr(prop.value, strict_context)
      }
    ArrayLit(elements, _) =>
      for e in elements {
        validate_block_early_errors_expr(e, strict_context)
      }
    ComputedMember(obj, key, _) => {
      validate_block_early_errors_expr(obj, strict_context)
      validate_block_early_errors_expr(key, strict_context)
    }
    MemberAssign(obj, _, rhs, _) => {
      validate_block_early_errors_expr(obj, strict_context)
      validate_block_early_errors_expr(rhs, strict_context)
    }
    ComputedAssign(obj, key, rhs, _) => {
      validate_block_early_errors_expr(obj, strict_context)
      validate_block_early_errors_expr(key, strict_context)
      validate_block_early_errors_expr(rhs, strict_context)
    }
    NewExpr(callee, args, _) => {
      validate_block_early_errors_expr(callee, strict_context)
      for a in args {
        validate_block_early_errors_expr(a, strict_context)
      }
    }
    UpdateExpr(_, target, _, _) =>
      validate_block_early_errors_expr(target, strict_context)
    CompoundAssign(_, lhs, rhs, _) => {
      validate_block_early_errors_expr(lhs, strict_context)
      validate_block_early_errors_expr(rhs, strict_context)
    }
    Comma(l, r, _) => {
      validate_block_early_errors_expr(l, strict_context)
      validate_block_early_errors_expr(r, strict_context)
    }
    TemplateLit(_, exprs, _) =>
      for e in exprs {
        validate_block_early_errors_expr(e, strict_context)
      }
    SpreadExpr(e, _) => validate_block_early_errors_expr(e, strict_context)
    DestructureAssign(_, rhs, _) =>
      validate_block_early_errors_expr(rhs, strict_context)
    OptionalMember(obj, _, _) =>
      validate_block_early_errors_expr(obj, strict_context)
    OptionalComputedMember(obj, key, _) => {
      validate_block_early_errors_expr(obj, strict_context)
      validate_block_early_errors_expr(key, strict_context)
    }
    OptionalCall(callee, args, _) => {
      validate_block_early_errors_expr(callee, strict_context)
      for a in args {
        validate_block_early_errors_expr(a, strict_context)
      }
    }
    SuperComputedMember(e, _) =>
      validate_block_early_errors_expr(e, strict_context)
    TaggedTemplate(tag, _, exprs, _) => {
      validate_block_early_errors_expr(tag, strict_context)
      for e in exprs {
        validate_block_early_errors_expr(e, strict_context)
      }
    }
    _ => ()
  }
}

///|
fn validate_block_early_errors_stmt(
  stmt : @ast.Stmt,
  strict_context : Bool,
) -> Unit raise Error {
  match stmt {
    Block(stmts, _) => {
      validate_block_statement_list_early_errors(
        stmts,
        include_block_functions=true,
        allow_duplicate_block_functions=!strict_context,
      )
      for inner in stmts {
        validate_block_early_errors_stmt(inner, strict_context)
      }
    }
    StmtList(stmts, _) =>
      for inner in stmts {
        validate_block_early_errors_stmt(inner, strict_context)
      }
    ExprStmt(expr, _) => validate_block_early_errors_expr(expr, strict_context)
    IfStmt(_, then_branch, else_branch, _) => {
      validate_block_early_errors_stmt(then_branch, strict_context)
      match else_branch {
        Some(eb) => validate_block_early_errors_stmt(eb, strict_context)
        None => ()
      }
    }
    WhileStmt(_, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    DoWhileStmt(body, _, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    ForStmt(init, _, _, body, _) => {
      match init {
        Some(init_stmt) =>
          validate_block_early_errors_stmt(init_stmt, strict_context)
        None => ()
      }
      validate_block_early_errors_stmt(body, strict_context)
    }
    ForInStmt(_, _, _, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    ForOfStmt(_, _, _, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    ForInStmtPat(_, _, _, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    ForOfStmtPat(_, _, _, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    ForInExpr(_, _, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    ForOfExpr(_, _, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    LabeledStmt(_, inner, _) =>
      validate_block_early_errors_stmt(inner, strict_context)
    SwitchStmt(_, cases, _) =>
      for case_ in cases {
        for inner in case_.body {
          validate_block_early_errors_stmt(inner, strict_context)
        }
      }
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      for inner in try_body {
        validate_block_early_errors_stmt(inner, strict_context)
      }
      match catch_body {
        Some(cb) =>
          for inner in cb {
            validate_block_early_errors_stmt(inner, strict_context)
          }
        None => ()
      }
      match finally_body {
        Some(fb) =>
          for inner in fb {
            validate_block_early_errors_stmt(inner, strict_context)
          }
        None => ()
      }
    }
    FuncDecl(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    FuncDeclExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    GeneratorDecl(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    GeneratorDeclExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    AsyncFuncDecl(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    AsyncFuncDeclExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    AsyncGeneratorDecl(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    AsyncGeneratorDeclExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    ClassDecl(_, _, methods, _) =>
      for m in methods {
        // Class bodies are always strict.
        validate_block_early_errors_expr(m.value, true)
      }
    WithStmt(_, body, _) => {
      if strict_context {
        raise @errors.SyntaxError(
          message="Strict mode code may not include a with statement",
        )
      }
      validate_block_early_errors_stmt(body, strict_context)
    }
    ExportNamedDecl(Some(decl), _, _, _) =>
      validate_block_early_errors_stmt(decl, strict_context)
    ExportDefaultDecl(expr, _) =>
      validate_block_early_errors_expr(expr, strict_context)
    _ => ()
  }
}

///|
fn Interpreter::validate_block_early_errors(
  _self : Interpreter,
  stmts : Array[@ast.Stmt],
  strict_context : Bool,
) -> Unit raise Error {
  // Validate lexical-vs-var conflicts for the current statement list itself.
  // This is required for script/function/eval bodies, not just nested Block nodes.
  validate_block_statement_list_early_errors(
    stmts,
    include_function_decls_in_var_names=true,
  )
  for stmt in stmts {
    validate_block_early_errors_stmt(stmt, strict_context)
  }
}

///|
/// Collect all var-scoped declaration names from eval code.
/// Used by EvalDeclarationInstantiation to check for var/lex conflicts.
fn collect_eval_var_names_from_stmt(
  stmt : @ast.Stmt,
  names : Array[String],
  in_block? : Bool = false,
) -> Unit {
  match stmt {
    VarDecl(VarKind, name, _, _) => names.push(name)
    FuncDecl(name, _, _, _) => if !in_block { names.push(name) }
    FuncDeclExt(name, _, _, _, _) => if !in_block { names.push(name) }
    GeneratorDecl(name, _, _, _) => if !in_block { names.push(name) }
    GeneratorDeclExt(name, _, _, _, _) => if !in_block { names.push(name) }
    AsyncFuncDecl(name, _, _, _) => if !in_block { names.push(name) }
    AsyncFuncDeclExt(name, _, _, _, _) => if !in_block { names.push(name) }
    AsyncGeneratorDecl(name, _, _, _) => if !in_block { names.push(name) }
    AsyncGeneratorDeclExt(name, _, _, _, _) => if !in_block { names.push(name) }
    DestructureDecl(VarKind, pattern, _, _) =>
      collect_pattern_var_names(pattern, names)
    StmtList(inner_stmts, _) =>
      for inner in inner_stmts {
        collect_eval_var_names_from_stmt(inner, names, in_block~)
      }
    Block(inner_stmts, _) =>
      for inner in inner_stmts {
        collect_eval_var_names_from_stmt(inner, names, in_block=true)
      }
    IfStmt(_, then_branch, else_branch, _) => {
      // Statement-position function declarations in if branches should not be
      // treated as leaked var names for eval conflict checks.
      collect_eval_var_names_from_stmt(then_branch, names, in_block=true)
      match else_branch {
        Some(eb) => collect_eval_var_names_from_stmt(eb, names, in_block=true)
        None => ()
      }
    }
    WhileStmt(_, body, _) =>
      collect_eval_var_names_from_stmt(body, names, in_block~)
    DoWhileStmt(body, _, _) =>
      collect_eval_var_names_from_stmt(body, names, in_block~)
    ForStmt(init, _, _, body, _) => {
      match init {
        Some(init_stmt) =>
          collect_eval_var_names_from_stmt(init_stmt, names, in_block~)
        None => ()
      }
      collect_eval_var_names_from_stmt(body, names, in_block~)
    }
    ForInStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) {
        names.push(name)
      }
      collect_eval_var_names_from_stmt(body, names, in_block~)
    }
    ForOfStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) {
        names.push(name)
      }
      collect_eval_var_names_from_stmt(body, names, in_block~)
    }
    ForInStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        collect_pattern_var_names(pattern, names)
      }
      collect_eval_var_names_from_stmt(body, names, in_block~)
    }
    ForOfStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        collect_pattern_var_names(pattern, names)
      }
      collect_eval_var_names_from_stmt(body, names, in_block~)
    }
    ForInExpr(_, _, body, _) =>
      collect_eval_var_names_from_stmt(body, names, in_block~)
    ForOfExpr(_, _, body, _) =>
      collect_eval_var_names_from_stmt(body, names, in_block~)
    LabeledStmt(_, inner, _) =>
      collect_eval_var_names_from_stmt(inner, names, in_block=true)
    SwitchStmt(_, cases, _) =>
      for case_ in cases {
        for inner in case_.body {
          collect_eval_var_names_from_stmt(inner, names, in_block~)
        }
      }
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      for inner in try_body {
        collect_eval_var_names_from_stmt(inner, names, in_block~)
      }
      match catch_body {
        Some(cb) =>
          for inner in cb {
            collect_eval_var_names_from_stmt(inner, names, in_block~)
          }
        None => ()
      }
      match finally_body {
        Some(fb) =>
          for inner in fb {
            collect_eval_var_names_from_stmt(inner, names, in_block~)
          }
        None => ()
      }
    }
    WithStmt(_, body, _) =>
      collect_eval_var_names_from_stmt(body, names, in_block~)
    ExportNamedDecl(Some(decl), _, _, _) =>
      collect_eval_var_names_from_stmt(decl, names, in_block~)
    _ => ()
  }
}

///|
fn collect_eval_var_names(stmts : Array[@ast.Stmt]) -> Array[String] {
  let names : Array[String] = []
  for stmt in stmts {
    collect_eval_var_names_from_stmt(stmt, names)
  }
  names
}

///|
fn hoist_pattern(pattern : @ast.Pattern, env : Environment) -> Unit raise Error {
  match pattern {
    IdentPat(name) =>
      if !env.bindings.contains(name) {
        env.def(name, Undefined, VarBinding)
      }
    DefaultPat(inner_pat, _) => hoist_pattern(inner_pat, env)
    AssignTarget(_) => () // member expressions don't need hoisting
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => hoist_pattern(p, env)
          None => ()
        }
      }
      match rest {
        Some(p) => hoist_pattern(p, env)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        hoist_pattern(prop.value, env)
      }
      match rest {
        Some(p) => hoist_pattern(p, env)
        None => ()
      }
    }
  }
}

///|
fn hoist_var_declarations_from_stmt(
  stmt : @ast.Stmt,
  env : Environment,
) -> Unit raise Error {
  match stmt {
    VarDecl(VarKind, name, _, _) =>
      if !env.bindings.contains(name) {
        env.def(name, Undefined, VarBinding)
      }
    DestructureDecl(VarKind, pattern, _, _) => hoist_pattern(pattern, env)
    StmtList(inner_stmts, _) =>
      for inner in inner_stmts {
        hoist_var_declarations_from_stmt(inner, env)
      }
    Block(inner_stmts, _) =>
      for inner in inner_stmts {
        hoist_var_declarations_from_stmt(inner, env)
      }
    IfStmt(_, then_branch, else_branch, _) => {
      hoist_var_declarations_from_stmt(then_branch, env)
      match else_branch {
        Some(eb) => hoist_var_declarations_from_stmt(eb, env)
        None => ()
      }
    }
    WhileStmt(_, body, _) => hoist_var_declarations_from_stmt(body, env)
    DoWhileStmt(body, _, _) => hoist_var_declarations_from_stmt(body, env)
    ForStmt(init, _, _, body, _) => {
      match init {
        Some(init_stmt) => hoist_var_declarations_from_stmt(init_stmt, env)
        None => ()
      }
      hoist_var_declarations_from_stmt(body, env)
    }
    ForInStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) && !env.bindings.contains(name) {
        env.def(name, Undefined, VarBinding)
      }
      hoist_var_declarations_from_stmt(body, env)
    }
    ForOfStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) && !env.bindings.contains(name) {
        env.def(name, Undefined, VarBinding)
      }
      hoist_var_declarations_from_stmt(body, env)
    }
    ForInStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        hoist_pattern(pattern, env)
      }
      hoist_var_declarations_from_stmt(body, env)
    }
    ForOfStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        hoist_pattern(pattern, env)
      }
      hoist_var_declarations_from_stmt(body, env)
    }
    ForInExpr(_, _, body, _) => hoist_var_declarations_from_stmt(body, env)
    ForOfExpr(_, _, body, _) => hoist_var_declarations_from_stmt(body, env)
    LabeledStmt(_, inner, _) => hoist_var_declarations_from_stmt(inner, env)
    SwitchStmt(_, cases, _) =>
      for case_ in cases {
        for inner in case_.body {
          hoist_var_declarations_from_stmt(inner, env)
        }
      }
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      for inner in try_body {
        hoist_var_declarations_from_stmt(inner, env)
      }
      match catch_body {
        Some(cb) =>
          for inner in cb {
            hoist_var_declarations_from_stmt(inner, env)
          }
        None => ()
      }
      match finally_body {
        Some(fb) =>
          for inner in fb {
            hoist_var_declarations_from_stmt(inner, env)
          }
        None => ()
      }
    }
    WithStmt(_, body, _) => hoist_var_declarations_from_stmt(body, env)
    // Export with declaration: hoist declarations from the inner declaration.
    ExportNamedDecl(Some(decl), _, _, _) =>
      hoist_var_declarations_from_stmt(decl, env)
    // Do not recurse into function/class declarations: their bodies create
    // separate var scopes.
    _ => ()
  }
}

///|
/// Annex B.3.3: Scan nested blocks for function declarations and create
/// var bindings in the function scope (initialized to undefined).
/// Only used in sloppy mode with --annex-b.
fn hoist_block_func_declarations(
  stmt : @ast.Stmt,
  var_env : Environment,
) -> Unit raise Error {
  match stmt {
    Block(inner_stmts, _) =>
      for inner in inner_stmts {
        match inner {
          FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
            if !var_env.bindings.contains(name) {
              var_env.def(name, Undefined, VarBinding)
            }
          _ => ()
        }
        hoist_block_func_declarations(inner, var_env)
      }
    IfStmt(_, then_branch, else_branch, _) => {
      // Also handle bare function declarations in if/else branches
      match then_branch {
        FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
          if !var_env.bindings.contains(name) {
            var_env.def(name, Undefined, VarBinding)
          }
        _ => ()
      }
      hoist_block_func_declarations(then_branch, var_env)
      match else_branch {
        Some(eb) => {
          match eb {
            FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
              if !var_env.bindings.contains(name) {
                var_env.def(name, Undefined, VarBinding)
              }
            _ => ()
          }
          hoist_block_func_declarations(eb, var_env)
        }
        None => ()
      }
    }
    WhileStmt(_, body, _) => hoist_block_func_declarations(body, var_env)
    DoWhileStmt(body, _, _) => hoist_block_func_declarations(body, var_env)
    ForStmt(_, _, _, body, _) => hoist_block_func_declarations(body, var_env)
    ForInStmt(_, _, _, body, _) => hoist_block_func_declarations(body, var_env)
    ForOfStmt(_, _, _, body, _) => hoist_block_func_declarations(body, var_env)
    ForInStmtPat(_, _, _, body, _) =>
      hoist_block_func_declarations(body, var_env)
    ForOfStmtPat(_, _, _, body, _) =>
      hoist_block_func_declarations(body, var_env)
    ForInExpr(_, _, body, _) => hoist_block_func_declarations(body, var_env)
    ForOfExpr(_, _, body, _) => hoist_block_func_declarations(body, var_env)
    LabeledStmt(_, inner, _) => hoist_block_func_declarations(inner, var_env)
    WithStmt(_, body, _) => {
      // Handle bare function declarations directly in with body (Annex B.3.3)
      match body {
        FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
          if !var_env.bindings.contains(name) {
            var_env.def(name, Undefined, VarBinding)
          }
        _ => ()
      }
      hoist_block_func_declarations(body, var_env)
    }
    SwitchStmt(_, cases, _) =>
      for case_ in cases {
        for inner in case_.body {
          match inner {
            FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
              if !var_env.bindings.contains(name) {
                var_env.def(name, Undefined, VarBinding)
              }
            _ => ()
          }
          hoist_block_func_declarations(inner, var_env)
        }
      }
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      for inner in try_body {
        match inner {
          FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
            if !var_env.bindings.contains(name) {
              var_env.def(name, Undefined, VarBinding)
            }
          _ => ()
        }
        hoist_block_func_declarations(inner, var_env)
      }
      match catch_body {
        Some(cb) =>
          for inner in cb {
            match inner {
              FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
                if !var_env.bindings.contains(name) {
                  var_env.def(name, Undefined, VarBinding)
                }
              _ => ()
            }
            hoist_block_func_declarations(inner, var_env)
          }
        None => ()
      }
      match finally_body {
        Some(fb) =>
          for inner in fb {
            match inner {
              FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
                if !var_env.bindings.contains(name) {
                  var_env.def(name, Undefined, VarBinding)
                }
              _ => ()
            }
            hoist_block_func_declarations(inner, var_env)
          }
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn Interpreter::hoist_declarations(
  _self : Interpreter,
  stmts : Array[@ast.Stmt],
  env : Environment,
) -> Unit raise Error {
  let is_global = physical_equal(env, _self.global)
  for stmt in stmts {
    match stmt {
      VarDecl(VarKind, name, _, _) =>
        if !env.bindings.contains(name) {
          env.def(name, Undefined, VarBinding)
          // Mirror var declaration to global object per ES spec
          if is_global {
            _self.mirror_to_global(name, Undefined)
          }
        }
      FuncDecl(name, params, body, _) => {
        validate_function_signature(_self.strict, Some(name), params, body)
        let func_data : FuncData = {
          name: Some(name),
          params,
          body,
          closure: env,
          strict: is_function_strict(_self.strict, body),
        }
        let func_val = make_func(func_data)
        if env.bindings.contains(name) {
          env.assign(name, func_val)
        } else {
          env.def(name, func_val, VarBinding)
        }
        // Mirror function declaration to global object per ES spec
        if is_global {
          _self.mirror_to_global(name, func_val)
        }
      }
      FuncDeclExt(name, params, rest_param, body, _) => {
        validate_function_signature_ext(
          _self.strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let func_data : FuncDataExt = {
          name: Some(name),
          params,
          rest_param,
          body,
          closure: env,
          strict: is_function_strict(_self.strict, body),
        }
        let func_val = make_func_ext(func_data)
        if env.bindings.contains(name) {
          env.assign(name, func_val)
        } else {
          env.def(name, func_val, VarBinding)
        }
        // Mirror function declaration to global object per ES spec
        if is_global {
          _self.mirror_to_global(name, func_val)
        }
      }
      GeneratorDecl(name, params, body, _) => {
        validate_function_signature(_self.strict, Some(name), params, body)
        let gen_func = _self.make_generator_function(
          Some(name),
          params,
          None,
          body,
          env,
        )
        if env.bindings.contains(name) {
          env.assign(name, gen_func)
        } else {
          env.def(name, gen_func, VarBinding)
        }
        // Mirror generator declaration to global object per ES spec
        if is_global {
          _self.mirror_to_global(name, gen_func)
        }
      }
      GeneratorDeclExt(name, params, rest_param, body, _) => {
        validate_function_signature_ext(
          _self.strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let gen_func = _self.make_generator_function_ext(
          Some(name),
          params,
          rest_param,
          body,
          env,
        )
        if env.bindings.contains(name) {
          env.assign(name, gen_func)
        } else {
          env.def(name, gen_func, VarBinding)
        }
        // Mirror generator declaration to global object per ES spec
        if is_global {
          _self.mirror_to_global(name, gen_func)
        }
      }
      AsyncFuncDecl(name, params, body, _) => {
        validate_function_signature(_self.strict, Some(name), params, body)
        let async_func = _self.make_async_function(
          Some(name),
          params,
          None,
          body,
          env,
        )
        if env.bindings.contains(name) {
          env.assign(name, async_func)
        } else {
          env.def(name, async_func, VarBinding)
        }
      }
      AsyncFuncDeclExt(name, params, rest_param, body, _) => {
        validate_function_signature_ext(
          _self.strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let async_func = _self.make_async_function_ext(
          Some(name),
          params,
          rest_param,
          body,
          env,
        )
        if env.bindings.contains(name) {
          env.assign(name, async_func)
        } else {
          env.def(name, async_func, VarBinding)
        }
      }
      AsyncGeneratorDecl(name, params, body, _) => {
        validate_function_signature(_self.strict, Some(name), params, body)
        let gen_func = _self.make_async_generator_function(
          Some(name),
          params,
          None,
          body,
          env,
        )
        if env.bindings.contains(name) {
          env.assign(name, gen_func)
        } else {
          env.def(name, gen_func, VarBinding)
        }
      }
      AsyncGeneratorDeclExt(name, params, rest_param, body, _) => {
        validate_function_signature_ext(
          _self.strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let gen_func = _self.make_async_generator_function_ext(
          Some(name),
          params,
          rest_param,
          body,
          env,
        )
        if env.bindings.contains(name) {
          env.assign(name, gen_func)
        } else {
          env.def(name, gen_func, VarBinding)
        }
      }
      DestructureDecl(VarKind, pattern, _, _) => hoist_pattern(pattern, env)
      StmtList(inner_stmts, _) =>
        // Recursively hoist declarations from StmtList (comma-separated decls)
        for inner in inner_stmts {
          match inner {
            VarDecl(VarKind, name, _, _) =>
              if !env.bindings.contains(name) {
                env.def(name, Undefined, VarBinding)
              }
            DestructureDecl(VarKind, pattern, _, _) =>
              hoist_pattern(pattern, env)
            _ => ()
          }
        }
      // Export with declaration: hoist the inner declaration
      ExportNamedDecl(Some(decl), _, _, _) => {
        let inner_stmts : Array[@ast.Stmt] = [decl]
        _self.hoist_declarations(inner_stmts, env)
      }
      // export default function name() {} - hoist the named function
      ExportDefaultDecl(FuncExpr(Some(name), params, body, _), _) => {
        validate_function_signature(_self.strict, Some(name), params, body)
        let func_data : FuncData = {
          name: Some(name),
          params,
          body,
          closure: env,
          strict: is_function_strict(_self.strict, body),
        }
        if env.bindings.contains(name) {
          env.assign(name, make_func(func_data))
        } else {
          env.def(name, make_func(func_data), VarBinding)
        }
      }
      ExportDefaultDecl(FuncExprExt(Some(name), params, rest_param, body, _), _) => {
        validate_function_signature_ext(
          _self.strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let func_data : FuncDataExt = {
          name: Some(name),
          params,
          rest_param,
          body,
          closure: env,
          strict: is_function_strict(_self.strict, body),
        }
        if env.bindings.contains(name) {
          env.assign(name, make_func_ext(func_data))
        } else {
          env.def(name, make_func_ext(func_data), VarBinding)
        }
      }
      _ => ()
    }
    // Hoist var declarations recursively through nested statements
    // (e.g. var inside blocks still hoists to function/global var scope).
    hoist_var_declarations_from_stmt(stmt, env)
    // Annex B.3.3: Hoist block-level function declarations as var bindings
    if _self.annex_b && !_self.strict {
      hoist_block_func_declarations(stmt, env)
    }
  }
}

///|
/// Hoist let/const declarations with TDZ markers at block scope
fn hoist_block_tdz(
  stmts : Array[@ast.Stmt],
  env : Environment,
) -> Unit raise Error {
  for stmt in stmts {
    match stmt {
      VarDecl(LetKind, name, _, _) =>
        if !env.bindings.contains(name) {
          env.def_tdz(name, LetBinding)
        }
      VarDecl(ConstKind, name, _, _) =>
        if !env.bindings.contains(name) {
          env.def_tdz(name, ConstBinding)
        }
      // DestructureDecl with let/const also needs TDZ
      DestructureDecl(LetKind, pattern, _, _) =>
        hoist_pattern_tdz(pattern, env, LetBinding)
      DestructureDecl(ConstKind, pattern, _, _) =>
        hoist_pattern_tdz(pattern, env, ConstBinding)
      // Class declarations have TDZ (similar to let)
      ClassDecl(name, _, _, _) =>
        if !env.bindings.contains(name) {
          env.def_tdz(name, LetBinding)
        }
      // Export with declaration: hoist let/const inner declarations with TDZ
      ExportNamedDecl(Some(decl), _, _, _) => {
        let inner_stmts : Array[@ast.Stmt] = [decl]
        hoist_block_tdz(inner_stmts, env)
      }
      _ => ()
    }
  }
}

///|
/// Hoist pattern bindings with TDZ markers
fn hoist_pattern_tdz(
  pattern : @ast.Pattern,
  env : Environment,
  kind : BindingKind,
) -> Unit raise Error {
  match pattern {
    IdentPat(name) =>
      if !env.bindings.contains(name) {
        env.def_tdz(name, kind)
      }
    DefaultPat(inner_pat, _) => hoist_pattern_tdz(inner_pat, env, kind)
    AssignTarget(_) => () // member expressions don't need TDZ hoisting
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => hoist_pattern_tdz(p, env, kind)
          None => ()
        }
      }
      match rest {
        Some(p) => hoist_pattern_tdz(p, env, kind)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        hoist_pattern_tdz(prop.value, env, kind)
      }
      match rest {
        Some(p) => hoist_pattern_tdz(p, env, kind)
        None => ()
      }
    }
  }
}
