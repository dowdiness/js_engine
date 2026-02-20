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
    "eval", "isFinite", "isNaN", "parseInt", "parseFloat",
    "encodeURIComponent", "decodeURIComponent", "encodeURI", "decodeURI",
    "escape", "unescape",
    "String", "Number", "Boolean", "Object", "Array", "Function",
    "RegExp", "Error", "TypeError", "RangeError", "ReferenceError",
    "SyntaxError", "URIError", "EvalError", "Date", "Math", "JSON",
    "Symbol", "Map", "Set", "WeakMap", "WeakSet", "Promise", "Proxy",
    "Reflect", "ArrayBuffer", "DataView",
    "Int8Array", "Uint8Array", "Uint8ClampedArray",
    "Int16Array", "Uint16Array", "Int32Array", "Uint32Array",
    "Float32Array", "Float64Array",
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
        if s == "use strict" && not(has_escape) {
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
  configurable~ : Bool = false,
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
          set_function_name(v, name)
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
        } else if not(is_truthy(self.eval_expr(cond, env))) {
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
            Some(c) => if not(is_truthy(self.eval_expr(c, for_env))) { break }
            None => ()
          }
        }
        let mut do_continue = false
        let body_signal = self.exec_stmt(body, for_env) catch {
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
        if self.annex_b && not(self.strict) && not(env.is_var_scope) {
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
          ContinueSignal(v, None) => {
            completion = v.unwrap_or(completion)
          }
          ContinueSignal(cv, Some(l)) =>
            if label == Some(l) {
              completion = cv.unwrap_or(completion)
            } else {
              return ContinueSignal(cv, Some(l))
            }
        }
        if not(is_truthy(self.eval_expr(cond, env))) {
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
            try {
              env.assign(name, String_(key))
            } catch {
              @errors.ReferenceError(_) =>
                if not(self.strict) {
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
              try { close_iterator(self, iterator, loc) } catch { _ => () }
            }
            raise e
          }
        }
        match body_signal {
          Normal(v) => completion = v
          ReturnSignal(v) => {
            try { close_iterator(self, iterator, loc) } catch { _ => () }
            return ReturnSignal(v)
          }
          BreakSignal(v, None) => {
            try { close_iterator(self, iterator, loc) } catch { _ => () }
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              try { close_iterator(self, iterator, loc) } catch { _ => () }
              completion = bv.unwrap_or(completion)
              break
            } else {
              try { close_iterator(self, iterator, loc) } catch { _ => () }
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
              try { close_iterator(self, iterator, loc) } catch { _ => () }
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
            try { close_iterator(self, iterator, loc) } catch { _ => () }
            raise e
          }
        }
        match body_signal {
          Normal(v) => completion = v
          ReturnSignal(v) => {
            try { close_iterator(self, iterator, loc) } catch { _ => () }
            return ReturnSignal(v)
          }
          BreakSignal(v, None) => {
            try { close_iterator(self, iterator, loc) } catch { _ => () }
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              try { close_iterator(self, iterator, loc) } catch { _ => () }
              completion = bv.unwrap_or(completion)
              break
            } else {
              try { close_iterator(self, iterator, loc) } catch { _ => () }
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
              try { close_iterator(self, iterator, loc) } catch { _ => () }
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
        if self.annex_b && not(self.strict) && not(env.is_var_scope) {
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
          if not(env.bindings.contains(name)) {
            env.def(name, value, LetBinding)
          }
        GeneratorExpr(Some(name), _, _, _)
        | GeneratorExprExt(Some(name), _, _, _, _) =>
          if not(env.bindings.contains(name)) {
            env.def(name, value, LetBinding)
          }
        ClassExpr(Some(name), _, _, _) =>
          if not(env.bindings.contains(name)) {
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
      // Create an object environment record: lookups check the object first
      let with_env = Environment::new(parent=Some(env))
      let data = match obj {
        Object(d) => d
        _ =>
          // Fallback: just execute with parent env
          return self.exec_stmt(body, env)
      }
      // Add all properties (walking prototype chain for lookup)
      let mut current : Value = obj
      while true {
        match current {
          Object(cur_data) => {
            cur_data.properties.each(fn(key, value) {
              if not(with_env.bindings.contains(key)) {
                with_env.bindings[key] = {
                  value,
                  kind: VarBinding,
                  initialized: true,
                }
              }
            })
            current = cur_data.prototype
          }
          _ => break
        }
      }
      // Execute the body; after execution, write back modified bindings
      let result = self.exec_stmt(body, with_env)
      // Write back changes: use [[Set]] semantics (own properties + prototype chain)
      with_env.bindings.each(fn(key, binding) {
        // Check if this binding existed before in the object or its prototype
        let mut found = false
        let mut cur : Value = obj
        while true {
          match cur {
            Object(cur_data) => {
              if cur_data.properties.contains(key) {
                found = true
                break
              }
              cur = cur_data.prototype
            }
            _ => break
          }
        }
        if found {
          // Write to the object itself (per [[Set]] semantics, own property creation)
          data.properties[key] = binding.value
        }
      })
      result
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
            if not(seen.contains(k)) {
              seen[k] = true
              keys.push(k)
            }
          }
        }
        data.properties.each(fn(k, _v) {
          if not(seen.contains(k)) {
            // Skip internal slots for TypedArray/ArrayBuffer/DataView only
            if k.has_prefix("[[") &&
              k.has_suffix("]]") &&
              (
                is_typedarray_class(data.class_name) ||
                data.class_name == "ArrayBuffer" ||
                data.class_name == "DataView"
              ) {
              return
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
        })
        current = data.prototype
      }
      Array(data) => {
        for i = 0; i < data.elements.length(); i = i + 1 {
          let k = i.to_string()
          if not(seen.contains(k)) {
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
fn Interpreter::exec_stmts(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  env : Environment,
) -> Signal raise Error {
  let mut last : Value = Undefined
  for stmt in stmts {
    match self.exec_stmt(stmt, env) {
      Normal(v) => last = v
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
          if not(
              allow_duplicate_block_functions &&
              block_function_kinds.get(name) == Some(1),
            ) {
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
          if not(
              allow_duplicate_block_functions &&
              block_function_kinds.get(name) == Some(1),
            ) {
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
        allow_duplicate_block_functions=not(strict_context),
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
    FuncDecl(name, _, _, _) => if not(in_block) { names.push(name) }
    FuncDeclExt(name, _, _, _, _) => if not(in_block) { names.push(name) }
    GeneratorDecl(name, _, _, _) => if not(in_block) { names.push(name) }
    GeneratorDeclExt(name, _, _, _, _) => if not(in_block) { names.push(name) }
    AsyncFuncDecl(name, _, _, _) => if not(in_block) { names.push(name) }
    AsyncFuncDeclExt(name, _, _, _, _) => if not(in_block) { names.push(name) }
    AsyncGeneratorDecl(name, _, _, _) => if not(in_block) { names.push(name) }
    AsyncGeneratorDeclExt(name, _, _, _, _) =>
      if not(in_block) { names.push(name) }
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
      if not(env.bindings.contains(name)) {
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
      if not(env.bindings.contains(name)) {
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
      if kind == Some(VarKind) && not(env.bindings.contains(name)) {
        env.def(name, Undefined, VarBinding)
      }
      hoist_var_declarations_from_stmt(body, env)
    }
    ForOfStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) && not(env.bindings.contains(name)) {
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
            if not(var_env.bindings.contains(name)) {
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
          if not(var_env.bindings.contains(name)) {
            var_env.def(name, Undefined, VarBinding)
          }
        _ => ()
      }
      hoist_block_func_declarations(then_branch, var_env)
      match else_branch {
        Some(eb) => {
          match eb {
            FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
              if not(var_env.bindings.contains(name)) {
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
          if not(var_env.bindings.contains(name)) {
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
              if not(var_env.bindings.contains(name)) {
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
            if not(var_env.bindings.contains(name)) {
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
                if not(var_env.bindings.contains(name)) {
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
                if not(var_env.bindings.contains(name)) {
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
        if not(env.bindings.contains(name)) {
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
              if not(env.bindings.contains(name)) {
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
    if _self.annex_b && not(_self.strict) {
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
        if not(env.bindings.contains(name)) {
          env.def_tdz(name, LetBinding)
        }
      VarDecl(ConstKind, name, _, _) =>
        if not(env.bindings.contains(name)) {
          env.def_tdz(name, ConstBinding)
        }
      // DestructureDecl with let/const also needs TDZ
      DestructureDecl(LetKind, pattern, _, _) =>
        hoist_pattern_tdz(pattern, env, LetBinding)
      DestructureDecl(ConstKind, pattern, _, _) =>
        hoist_pattern_tdz(pattern, env, ConstBinding)
      // Class declarations have TDZ (similar to let)
      ClassDecl(name, _, _, _) =>
        if not(env.bindings.contains(name)) {
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
      if not(env.bindings.contains(name)) {
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

///|
fn Interpreter::bind_pattern(
  self : Interpreter,
  pattern : @ast.Pattern,
  value : Value,
  env : Environment,
  bk : BindingKind,
) -> Unit raise Error {
  match pattern {
    IdentPat(name) =>
      if bk == VarBinding && env.bindings.contains(name) {
        env.assign(name, value)
      } else if (bk == LetBinding || bk == ConstBinding) &&
        env.bindings.contains(name) {
        // let/const hoisted with TDZ - initialize it
        env.initialize(name, value)
      } else {
        env.def(name, value, bk)
      }
    DefaultPat(inner_pat, default_expr) => {
      let final_val : Value = if value is Undefined {
        self.eval_expr(default_expr, env)
      } else {
        value
      }
      self.bind_pattern(inner_pat, final_val, env, bk)
    }
    AssignTarget(expr) =>
      // Member expression targets are only valid in assignment destructuring,
      // not in binding declarations (let/const/var). Delegate to assign_to_expr.
      self.assign_to_expr(expr, value, env)
    ArrayPat(elements, rest) => {
      let arr_elements : Array[Value] = match value {
        Array(data) => data.elements
        _ => {
          // Try iterator protocol for non-array iterables (e.g. generators)
          let loc = @token.Loc::default()
          let iterator_sym = get_iterator_symbol()
          let iterator_method = self.get_computed_property(
            value,
            Symbol(iterator_sym),
            loc,
          )
          match iterator_method {
            Object(data) =>
              match data.callable {
                Some(_) => {
                  let iterator = self.call_value(
                    iterator_method,
                    value,
                    [],
                    loc,
                  )
                  // Get next method from iterator (walk prototype chain)
                  let next_method : Value = match iterator {
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
                          found
                        }
                      }
                    _ => Undefined
                  }
                  match next_method {
                    Undefined => []
                    _ => {
                      let collected : Array[Value] = []
                      while true {
                        let iter_result = self.call_value(
                          next_method,
                          iterator,
                          [],
                          loc,
                        )
                        let (done, val) = match iter_result {
                          Object(result_data) => {
                            let done_val = match
                              result_data.properties.get("done") {
                              Some(v) => is_truthy(v)
                              None => false
                            }
                            let value_val = match
                              result_data.properties.get("value") {
                              Some(v) => v
                              None => Undefined
                            }
                            (done_val, value_val)
                          }
                          _ => (true, Undefined)
                        }
                        if done {
                          break
                        }
                        collected.push(val)
                      }
                      collected
                    }
                  }
                }
                None => []
              }
            _ => []
          }
        }
      }
      for i = 0; i < elements.length(); i = i + 1 {
        match elements[i] {
          Some(pat) => {
            let val : Value = if i < arr_elements.length() {
              arr_elements[i]
            } else {
              Undefined
            }
            self.bind_pattern(pat, val, env, bk)
          }
          None => () // hole — skip
        }
      }
      match rest {
        Some(rest_pat) => {
          let rest_elements : Array[Value] = []
          for i = elements.length(); i < arr_elements.length(); i = i + 1 {
            rest_elements.push(arr_elements[i])
          }
          self.bind_pattern(
            rest_pat,
            Array({ elements: rest_elements }),
            env,
            bk,
          )
        }
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      let used_keys : Map[String, Bool] = {}
      for prop in props {
        used_keys[prop.key] = true
        let val : Value = match value {
          Object(data) =>
            match data.properties.get(prop.key) {
              Some(v) => v
              None => Undefined
            }
          _ => Undefined
        }
        let final_val : Value = if val is Undefined {
          match prop.default_val {
            Some(default_expr) => self.eval_expr(default_expr, env)
            None => Undefined
          }
        } else {
          val
        }
        self.bind_pattern(prop.value, final_val, env, bk)
      }
      match rest {
        Some(rest_pat) => {
          let rest_props : Map[String, Value] = {}
          let rest_symbol_props : Map[Int, Value] = {}
          match value {
            Object(data) => {
              // Only copy own enumerable properties per ES CopyDataProperties
              data.properties.each(fn(k, v) {
                if not(used_keys.contains(k)) {
                  // Check if property is enumerable (default true if no descriptor)
                  let is_enumerable = match data.descriptors.get(k) {
                    Some(desc) => desc.enumerable
                    None => true
                  }
                  if is_enumerable {
                    rest_props[k] = v
                  }
                }
              })
              // Also copy enumerable symbol properties (they are never in used_keys)
              data.symbol_properties.each(fn(k, v) {
                let is_enumerable = match data.symbol_descriptors.get(k) {
                  Some(desc) => desc.enumerable
                  None => true
                }
                if is_enumerable {
                  rest_symbol_props[k] = v
                }
              })
            }
            _ => ()
          }
          self.bind_pattern(
            rest_pat,
            Object({
              properties: rest_props,
              symbol_properties: rest_symbol_props,
              prototype: Null,
              callable: None,
              class_name: "Object",
              descriptors: {},
              symbol_descriptors: {},
              extensible: true,
            }),
            env,
            bk,
          )
        }
        None => ()
      }
    }
  }
}

///|
fn Interpreter::assign_pattern(
  self : Interpreter,
  pattern : @ast.Pattern,
  value : Value,
  env : Environment,
) -> Unit raise Error {
  match pattern {
    IdentPat(name) => env.assign(name, value)
    DefaultPat(inner_pat, default_expr) => {
      let final_val : Value = if value is Undefined {
        self.eval_expr(default_expr, env)
      } else {
        value
      }
      self.assign_pattern(inner_pat, final_val, env)
    }
    AssignTarget(expr) =>
      // Member expression assignment target: [obj.x] = [1]
      self.assign_to_expr(expr, value, env)
    ArrayPat(elements, rest) => {
      let arr_elements : Array[Value] = match value {
        Array(data) => data.elements
        _ => {
          // Try iterator protocol for non-array iterables (e.g. generators)
          let loc = @token.Loc::default()
          let iterator_sym = get_iterator_symbol()
          let iterator_method = self.get_computed_property(
            value,
            Symbol(iterator_sym),
            loc,
          )
          match iterator_method {
            Object(data) =>
              match data.callable {
                Some(_) => {
                  let iterator = self.call_value(
                    iterator_method,
                    value,
                    [],
                    loc,
                  )
                  // Get next method from iterator (walk prototype chain)
                  let next_method : Value = match iterator {
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
                          found
                        }
                      }
                    _ => Undefined
                  }
                  match next_method {
                    Undefined => []
                    _ => {
                      let collected : Array[Value] = []
                      while true {
                        let iter_result = self.call_value(
                          next_method,
                          iterator,
                          [],
                          loc,
                        )
                        let (done, val) = match iter_result {
                          Object(result_data) => {
                            let done_val = match
                              result_data.properties.get("done") {
                              Some(v) => is_truthy(v)
                              None => false
                            }
                            let value_val = match
                              result_data.properties.get("value") {
                              Some(v) => v
                              None => Undefined
                            }
                            (done_val, value_val)
                          }
                          _ => (true, Undefined)
                        }
                        if done {
                          break
                        }
                        collected.push(val)
                      }
                      collected
                    }
                  }
                }
                None => []
              }
            _ => []
          }
        }
      }
      for i = 0; i < elements.length(); i = i + 1 {
        match elements[i] {
          Some(pat) => {
            let val : Value = if i < arr_elements.length() {
              arr_elements[i]
            } else {
              Undefined
            }
            self.assign_pattern(pat, val, env)
          }
          None => ()
        }
      }
      match rest {
        Some(rest_pat) => {
          let rest_elements : Array[Value] = []
          for i = elements.length(); i < arr_elements.length(); i = i + 1 {
            rest_elements.push(arr_elements[i])
          }
          self.assign_pattern(rest_pat, Array({ elements: rest_elements }), env)
        }
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      let used_keys : Map[String, Bool] = {}
      for prop in props {
        used_keys[prop.key] = true
        let val : Value = match value {
          Object(data) =>
            match data.properties.get(prop.key) {
              Some(v) => v
              None => Undefined
            }
          _ => Undefined
        }
        let final_val : Value = if val is Undefined {
          match prop.default_val {
            Some(default_expr) => self.eval_expr(default_expr, env)
            None => Undefined
          }
        } else {
          val
        }
        self.assign_pattern(prop.value, final_val, env)
      }
      match rest {
        Some(rest_pat) => {
          let rest_props : Map[String, Value] = {}
          let rest_symbol_props : Map[Int, Value] = {}
          match value {
            Object(data) => {
              // Only copy own enumerable properties per ES CopyDataProperties
              data.properties.each(fn(k, v) {
                if not(used_keys.contains(k)) {
                  // Check if property is enumerable (default true if no descriptor)
                  let is_enumerable = match data.descriptors.get(k) {
                    Some(desc) => desc.enumerable
                    None => true
                  }
                  if is_enumerable {
                    rest_props[k] = v
                  }
                }
              })
              // Also copy enumerable symbol properties (they are never in used_keys)
              data.symbol_properties.each(fn(k, v) {
                let is_enumerable = match data.symbol_descriptors.get(k) {
                  Some(desc) => desc.enumerable
                  None => true
                }
                if is_enumerable {
                  rest_symbol_props[k] = v
                }
              })
            }
            _ => ()
          }
          self.assign_pattern(
            rest_pat,
            Object({
              properties: rest_props,
              symbol_properties: rest_symbol_props,
              prototype: Null,
              callable: None,
              class_name: "Object",
              descriptors: {},
              symbol_descriptors: {},
              extensible: true,
            }),
            env,
          )
        }
        None => ()
      }
    }
  }
}

///|
fn Interpreter::assign_to_expr(
  self : Interpreter,
  expr : @ast.Expr,
  value : Value,
  env : Environment,
) -> Unit raise Error {
  match expr {
    Ident(name, _) =>
      try {
        env.assign(name, value)
      } catch {
        @errors.ReferenceError(_) =>
          if not(self.strict) {
            // Implicit global creation in sloppy mode
            self.global.def(name, value, VarBinding)
            self.mirror_to_global(name, value, configurable=true)
          } else {
            raise @errors.ReferenceError(message="\{name} is not defined")
          }
        e => raise e
      }
    Member(obj_expr, prop, loc) => {
      let obj = self.eval_expr(obj_expr, env)
      let _ = self.set_property(obj, prop, value, loc)
    }
    ComputedMember(obj_expr, key_expr, loc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let _ = self.set_computed_property(obj, key, value, loc)
    }
    _ =>
      raise @errors.ReferenceError(
        message="Invalid left-hand side in for-in/for-of",
      )
  }
}

///|
/// IteratorClose: call iterator.return() if it exists
fn close_iterator(
  interp : Interpreter,
  iterator : Value,
  loc : @token.Loc,
) -> Unit raise Error {
  match iterator {
    Object(data) => {
      // Look for 'return' method on iterator
      let return_fn = match data.properties.get("return") {
        Some(f) => f
        None => {
          // Walk prototype chain
          let mut found : Value = Undefined
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) =>
                match proto_data.properties.get("return") {
                  Some(f) => {
                    found = f
                    break
                  }
                  None => current = proto_data.prototype
                }
              _ => break
            }
          }
          found
        }
      }
      if is_callable(return_fn) {
        let _ = interp.call_value(return_fn, iterator, [], loc)

      }
    }
    _ => ()
  }
}

///|
fn Interpreter::exec_try_catch(
  self : Interpreter,
  try_body : Array[@ast.Stmt],
  catch_param : String?,
  catch_body : Array[@ast.Stmt]?,
  finally_body : Array[@ast.Stmt]?,
  env : Environment,
) -> Signal raise Error {
  // Check if we're resuming inside a generator at a specific phase
  let gen_opt = current_generator.val
  let start_phase = match gen_opt {
    Some(g) =>
      if g.try_resume_phase >= 0 {
        let p = g.try_resume_phase
        g.try_resume_phase = -1 // consume it
        p
      } else {
        0
      }
    _ => 0
  }
  let mut result : Signal = Normal(Undefined)
  let mut pending_error : Error? = match gen_opt {
    Some(g) =>
      if start_phase == 2 {
        // Resuming in finally — restore pending error and result
        result = g.try_resume_result
        g.try_resume_result = Normal(Undefined)
        let pe = g.try_resume_pending_error
        g.try_resume_pending_error = None
        pe
      } else {
        None
      }
    _ => None
  }
  // Phase 0: Try body (skip if resuming at catch or finally)
  if start_phase == 0 {
    let try_env = Environment::new(parent=Some(env))
    result = self.exec_stmts(try_body, try_env) catch {
      e =>
        if e is YieldSignal(_) {
          // Yield inside try body — save phase for resume
          match gen_opt {
            Some(g) => g.try_resume_phase = 0
            _ => ()
          }
          raise e
        } else if e is GeneratorReturnSignal(_) {
          // .return(v) injected at yield — save for finally
          pending_error = Some(e)
          Normal(Undefined)
        } else if is_js_catchable_error(e) {
          // JS exception caught — run catch body (phase 1)
          match (catch_param, catch_body) {
            (Some(param), Some(body)) => {
              let catch_env = Environment::new(parent=Some(env))
              let error_value = js_error_to_value_with_env(e, Some(env))
              catch_env.def(param, error_value, LetBinding)
              self.exec_stmts(body, catch_env) catch {
                ce =>
                  if ce is YieldSignal(_) {
                    // Yield inside catch body — save phase and error for resume
                    match gen_opt {
                      Some(g) => {
                        g.try_resume_phase = 1
                        g.try_resume_error = error_value
                      }
                      _ => ()
                    }
                    raise ce
                  } else {
                    raise ce
                  }
              }
            }
            _ => Normal(Undefined)
          }
        } else {
          raise e
        }
    }
  } else if start_phase == 1 {
    // Resuming in catch body — skip try, go directly to catch
    match (catch_param, catch_body) {
      (Some(param), Some(body)) => {
        let catch_env = Environment::new(parent=Some(env))
        // Restore saved error value
        let error_value = match gen_opt {
          Some(g) => {
            let ev = g.try_resume_error
            g.try_resume_error = Undefined
            ev
          }
          _ => Undefined
        }
        catch_env.def(param, error_value, LetBinding)
        result = self.exec_stmts(body, catch_env) catch {
          ce =>
            if ce is YieldSignal(_) {
              // Yield inside catch body again — save phase
              match gen_opt {
                Some(g) => {
                  g.try_resume_phase = 1
                  g.try_resume_error = error_value
                }
                _ => ()
              }
              raise ce
            } else {
              raise ce
            }
        }
      }
      _ => result = Normal(Undefined)
    }
  }
  // else start_phase == 2: skip try and catch, go to finally
  // Phase 2: Finally body (always runs if present)
  match finally_body {
    Some(body) => {
      let finally_result = self.exec_stmts(
        body,
        Environment::new(parent=Some(env)),
      ) catch {
        fe =>
          if fe is YieldSignal(_) {
            // Yield inside finally body — save phase and pending state for resume
            match gen_opt {
              Some(g) => {
                g.try_resume_phase = 2
                g.try_resume_result = result
                g.try_resume_pending_error = pending_error
              }
              _ => ()
            }
            raise fe
          } else {
            raise fe
          }
      }
      match pending_error {
        Some(e) =>
          match finally_result {
            Normal(_) => raise e
            ReturnSignal(_) => finally_result
            _ => raise e
          }
        None =>
          match finally_result {
            Normal(_) => result
            other => other
          }
      }
    }
    None =>
      match pending_error {
        Some(e) => raise e
        None => result
      }
  }
}

///|
fn Interpreter::eval_expr(
  self : Interpreter,
  expr : @ast.Expr,
  env : Environment,
) -> Value raise Error {
  match expr {
    NumberLit(n, _) => Number(n)
    StringLit(s, _, _) => String_(s)
    BoolLit(b, _) => Bool(b)
    NullLit(_) => Null
    UndefinedLit(_) => Undefined
    Ident(name, _) => env.get(name)
    Grouping(e, _) => self.eval_expr(e, env)
    Binary(op, left, right, loc) => self.eval_binary(op, left, right, env, loc)
    Unary(op, operand, loc) => self.eval_unary(op, operand, env, loc)
    Assign(name, value_expr, _) => {
      // Strict mode: assignment to eval/arguments is a SyntaxError
      if self.strict && (name == "eval" || name == "arguments") {
        raise @errors.SyntaxError(
          message="Unexpected eval or arguments in strict mode",
        )
      }
      let value = self.eval_expr(value_expr, env)
      // SetFunctionName for assignments: x = function() {} gives name "x"
      set_function_name(value, name)
      // Check if the target is a non-writable property on the global object
      // (e.g. undefined, NaN, Infinity). In strict mode this is a TypeError;
      // in non-strict mode the assignment is silently ignored.
      if self.is_immutable_global(name) {
        if self.strict {
          raise @errors.TypeError(
            message="Cannot assign to read only property '\{name}' of object '[object global]'",
          )
        }
        return value
      }
      try {
        env.assign(name, value)
      } catch {
        @errors.ReferenceError(_) => {
          // In non-strict mode, assigning to an undeclared variable creates
          // a global property (sloppy mode implicit global).
          if not(self.strict) {
            self.global.def(name, value, VarBinding)
            // Also mirror onto globalThis as a configurable, enumerable property
            self.mirror_to_global(name, value, configurable=true)
          } else {
            raise @errors.ReferenceError(
              message="\{name} is not defined",
            )
          }
        }
        e => raise e
      }
      value
    }
    Ternary(cond, then_expr, else_expr, _) =>
      if is_truthy(self.eval_expr(cond, env)) {
        self.eval_expr(then_expr, env)
      } else {
        self.eval_expr(else_expr, env)
      }
    Call(callee, args, loc) => self.eval_call(callee, args, env, loc)
    Member(obj_expr, prop, loc) => self.eval_member(obj_expr, prop, env, loc)
    FuncExpr(name, params, body, _) => {
      validate_function_signature(self.strict, name, params, body)
      let func_data : FuncData = {
        name,
        params,
        body,
        closure: env,
        strict: is_function_strict(self.strict, body),
      }
      make_func(func_data)
    }
    GeneratorExpr(name, params, body, _) => {
      validate_function_signature(self.strict, name, params, body)
      self.make_generator_function(name, params, None, body, env)
    }
    GeneratorExprExt(name, params, rest_param, body, _) => {
      validate_function_signature_ext(
        self.strict,
        name,
        params,
        rest_param,
        body,
      )
      self.make_generator_function_ext(name, params, rest_param, body, env)
    }
    AsyncFuncExpr(name, params, body, _) => {
      validate_function_signature(self.strict, name, params, body)
      self.make_async_function(name, params, None, body, env)
    }
    AsyncFuncExprExt(name, params, rest_param, body, _) => {
      validate_function_signature_ext(self.strict, name, params, rest_param, body)
      self.make_async_function_ext(name, params, rest_param, body, env)
    }
    AsyncArrowFunc(params, body, _) => {
      validate_function_signature(self.strict, None, params, body)
      self.make_async_function(None, params, None, body, env)
    }
    AsyncArrowFuncExt(params, rest_param, body, _) => {
      validate_function_signature_ext(self.strict, None, params, rest_param, body)
      self.make_async_function_ext(None, params, rest_param, body, env)
    }
    AsyncGeneratorExpr(name, params, body, _) => {
      validate_function_signature(self.strict, name, params, body)
      self.make_async_generator_function(name, params, None, body, env)
    }
    AsyncGeneratorExprExt(name, params, rest_param, body, _) => {
      validate_function_signature_ext(self.strict, name, params, rest_param, body)
      self.make_async_generator_function_ext(name, params, rest_param, body, env)
    }
    AwaitExpr(argument, _) => {
      // await acts like yield inside the generator that backs the async function
      self.eval_yield(Some(argument), false, env)
    }
    YieldExpr(argument, delegate, _) => self.eval_yield(argument, delegate, env)
    ObjectLit(props, obj_loc) => {
      let properties : Map[String, Value] = {}
      let symbol_properties : Map[Int, Value] = {}
      let descriptors : Map[String, PropDescriptor] = {}
      let symbol_descriptors : Map[Int, PropDescriptor] = {}
      let mut proto_override : Value? = None
      for prop in props {
        // Handle spread property: { ...expr }
        if prop.kind == @ast.Spread {
          let spread_val = self.eval_expr(prop.key, env)
          match spread_val {
            Object(data) => {
              // Copy all enumerable own properties
              // Per ES spec, spread invokes [[Get]] (which triggers getters)
              // and creates data properties (not accessor descriptors)
              for key, _value in data.properties {
                match data.descriptors.get(key) {
                  Some(desc) =>
                    if desc.enumerable {
                      // Invoke getter if present, otherwise use raw value
                      let val : Value = match desc.getter {
                        Some(getter) =>
                          self.call_value(getter, spread_val, [], obj_loc)
                        None => _value
                      }
                      properties[key] = val
                    }
                  None => properties[key] = _value
                }
              }
              // Copy symbol properties too
              for sym_id, value in data.symbol_properties {
                match data.symbol_descriptors.get(sym_id) {
                  Some(desc) =>
                    if desc.enumerable {
                      symbol_properties[sym_id] = value
                    }
                  None => symbol_properties[sym_id] = value
                }
              }
            }
            Array(arr_data) =>
              // Spread array into object: only enumerable own properties
              // length is non-enumerable per spec, so only copy indexed elements
              for i, value in arr_data.elements {
                properties[i.to_string()] = value
              }
            String_(s) => {
              // Spread string into object: { ..."abc" } -> { "0": "a", "1": "b", "2": "c" }
              let mut idx = 0
              for ch in s {
                properties[idx.to_string()] = String_(ch.to_string())
                idx = idx + 1
              }
            }
            Null | Undefined => () // Skip null/undefined per spec
            Number(_) | Bool(_) => () // Primitives have no enumerable own properties
            _ => ()
          }
          continue
        }
        if prop.computed {
          // Evaluate the computed key
          let key_val = self.eval_expr(prop.key, env)
          match key_val {
            Symbol(sym) =>
              // Symbol key - store in symbol_properties
              match prop.kind {
                Init => {
                  let val = self.eval_expr(prop.value, env)
                  // SetFunctionName with symbol description
                  let sym_name = match sym.description {
                    Some(d) => "[\{d}]"
                    None => ""
                  }
                  set_function_name(val, sym_name)
                  symbol_properties[sym.id] = val
                }
                Get => {
                  let getter = self.eval_expr(prop.value, env)
                  // Store accessor in descriptor, use Undefined as placeholder in properties
                  if not(symbol_properties.contains(sym.id)) {
                    symbol_properties[sym.id] = Undefined
                  }
                  let existing = symbol_descriptors.get(sym.id)
                  symbol_descriptors[sym.id] = {
                    writable: false,
                    enumerable: true,
                    configurable: true,
                    getter: Some(getter),
                    setter: match existing {
                      Some(d) => d.setter
                      None => None
                    },
                  }
                }
                Set => {
                  let setter = self.eval_expr(prop.value, env)
                  if not(symbol_properties.contains(sym.id)) {
                    symbol_properties[sym.id] = Undefined
                  }
                  let existing = symbol_descriptors.get(sym.id)
                  symbol_descriptors[sym.id] = {
                    writable: false,
                    enumerable: true,
                    configurable: true,
                    getter: match existing {
                      Some(d) => d.getter
                      None => None
                    },
                    setter: Some(setter),
                  }
                }
                Spread => () // handled above
              }
            _ => {
              // Convert to string key using ECMAScript ToString
              let key_str = to_js_string(key_val)
              match prop.kind {
                Init => {
                  let val = self.eval_expr(prop.value, env)
                  set_function_name(val, key_str)
                  properties[key_str] = val
                }
                Get => {
                  let getter = self.eval_expr(prop.value, env)
                  if not(properties.contains(key_str)) {
                    properties[key_str] = Undefined
                  }
                  let existing = descriptors.get(key_str)
                  descriptors[key_str] = {
                    writable: false,
                    enumerable: true,
                    configurable: true,
                    getter: Some(getter),
                    setter: match existing {
                      Some(d) => d.setter
                      None => None
                    },
                  }
                }
                Set => {
                  let setter = self.eval_expr(prop.value, env)
                  if not(properties.contains(key_str)) {
                    properties[key_str] = Undefined
                  }
                  let existing = descriptors.get(key_str)
                  descriptors[key_str] = {
                    writable: false,
                    enumerable: true,
                    configurable: true,
                    getter: match existing {
                      Some(d) => d.getter
                      None => None
                    },
                    setter: Some(setter),
                  }
                }
                Spread => () // handled above
              }
            }
          }
        } else {
          // Static key - extract from StringLit
          let key_str = match prop.key {
            StringLit(s, _, _) => s
            _ => prop.key.to_string() // fallback
          }
          match prop.kind {
            Init => {
              // Handle __proto__ as special syntax per B.3.1
              if key_str == "__proto__" {
                let val = self.eval_expr(prop.value, env)
                match val {
                  Object(_) | Array(_) | Map(_) | Set(_) => {
                    proto_override = Some(val)
                  }
                  Null => proto_override = Some(Null)
                  _ => properties[key_str] = val // primitives don't set proto
                }
              } else {
                let val = self.eval_expr(prop.value, env)
                // SetFunctionName: infer name for anonymous functions
                set_function_name(val, key_str)
                properties[key_str] = val
              }
            }
            Get => {
              let getter = self.eval_expr(prop.value, env)
              set_function_name(getter, "get " + key_str)
              if not(properties.contains(key_str)) {
                properties[key_str] = Undefined
              }
              let existing = descriptors.get(key_str)
              descriptors[key_str] = {
                writable: false,
                enumerable: true,
                configurable: true,
                getter: Some(getter),
                setter: match existing {
                  Some(d) => d.setter
                  None => None
                },
              }
            }
            Set => {
              let setter = self.eval_expr(prop.value, env)
              set_function_name(setter, "set " + key_str)
              if not(properties.contains(key_str)) {
                properties[key_str] = Undefined
              }
              let existing = descriptors.get(key_str)
              descriptors[key_str] = {
                writable: false,
                enumerable: true,
                configurable: true,
                getter: match existing {
                  Some(d) => d.getter
                  None => None
                },
                setter: Some(setter),
              }
            }
            Spread => () // handled above
          }
        }
      }
      let obj_prototype : Value = match proto_override {
        Some(p) => p
        None => env.get("[[ObjectPrototype]]") catch { _ => Null }
      }
      Object({
        properties,
        symbol_properties,
        prototype: obj_prototype,
        callable: None,
        class_name: "Object",
        descriptors,
        symbol_descriptors,
        extensible: true,
      })
    }
    ArrayLit(elements, _) => {
      let vals : Array[Value] = []
      for e in elements {
        match e {
          SpreadExpr(inner, spread_loc) => {
            let val = self.eval_expr(inner, env)
            // Use iterator protocol for spreading
            let spread_vals = self.spread_iterable(val, spread_loc)
            for v in spread_vals {
              vals.push(v)
            }
          }
          _ => vals.push(self.eval_expr(e, env))
        }
      }
      Array({ elements: vals })
    }
    ComputedMember(obj_expr, key_expr, loc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      self.get_computed_property(obj, key, loc)
    }
    MemberAssign(obj_expr, prop, value_expr, loc) => {
      let obj = self.eval_expr(obj_expr, env)
      let value = self.eval_expr(value_expr, env)
      self.set_property(obj, prop, value, loc)
    }
    ComputedAssign(obj_expr, key_expr, value_expr, loc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let value = self.eval_expr(value_expr, env)
      self.set_computed_property(obj, key, value, loc)
    }
    NewExpr(callee_expr, arg_exprs, loc) =>
      self.eval_new(callee_expr, arg_exprs, env, loc)
    ThisExpr(_) => env.get("this") catch { _ => Undefined }
    UpdateExpr(op, operand, prefix, loc) =>
      self.eval_update(op, operand, prefix, env, loc)
    CompoundAssign(op, target, value_expr, loc) =>
      self.eval_compound_assign(op, target, value_expr, env, loc)
    Comma(left, right, _) => {
      let _ = self.eval_expr(left, env)
      self.eval_expr(right, env)
    }
    TemplateLit(strings, exprs, _) => {
      let buf = StringBuilder::new()
      for i = 0; i < strings.length(); i = i + 1 {
        buf.write_string(strings[i])
        if i < exprs.length() {
          let val = self.eval_expr(exprs[i], env)
          buf.write_string(to_js_string(val))
        }
      }
      String_(buf.to_string())
    }
    TaggedTemplate(tag_expr, strings, exprs, loc) => {
      let tag = self.eval_expr(tag_expr, env)
      // Build the raw array (same as cooked for now - raw doesn't process escapes)
      let raw_vals : Array[Value] = []
      for s in strings {
        raw_vals.push(String_(s))
      }
      let raw_arr = Array({ elements: raw_vals })
      // Create the template strings object as an array-like object with raw property
      let props : Map[String, Value] = {}
      props["length"] = Number(strings.length().to_double())
      props["raw"] = raw_arr
      for i, s in strings {
        props[i.to_string()] = String_(s)
      }
      let template_obj = Object({
        properties: props,
        symbol_properties: {},
        prototype: self.global.get("[[ObjectPrototype]]") catch {
          _ => Null
        },
        callable: None,
        class_name: "Array",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
      // Build args: [templateObj, ...substitutions]
      let args : Array[Value] = [template_obj]
      for e in exprs {
        args.push(self.eval_expr(e, env))
      }
      // Resolve this binding for member expression tags (e.g., String.raw`...`)
      let this_val : Value = match tag_expr {
        Member(obj_expr, _, _) | ComputedMember(obj_expr, _, _) =>
          self.eval_expr(obj_expr, env)
        _ => Undefined
      }
      self.call_value(tag, this_val, args, loc)
    }
    ArrowFunc(params, body, _) => {
      validate_function_signature(self.strict, None, params, body)
      let func_data : FuncData = {
        name: None,
        params,
        body,
        closure: env,
        strict: is_function_strict(self.strict, body),
      }
      let nf_desc : PropDescriptor = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      Object({
        properties: {
          "name": String_(""),
          "length": Number(params.length().to_double()),
        },
        symbol_properties: {},
        prototype: Null,
        callable: Some(ArrowFunc(func_data)),
        class_name: "Function",
        descriptors: { "name": nf_desc, "length": nf_desc },
        symbol_descriptors: {},
        extensible: true,
      })
    }
    ArrowFuncExt(params, rest_param, body, _) => {
      validate_function_signature_ext(
        self.strict,
        None,
        params,
        rest_param,
        body,
      )
      let func_data : FuncDataExt = {
        name: None,
        params,
        rest_param,
        body,
        closure: env,
        strict: is_function_strict(self.strict, body),
      }
      let nf_desc : PropDescriptor = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      // Length = number of params before first default
      let mut arrow_len = 0
      for p in params {
        if p.default_val is Some(_) {
          break
        }
        arrow_len += 1
      }
      Object({
        properties: {
          "name": String_(""),
          "length": Number(arrow_len.to_double()),
        },
        symbol_properties: {},
        prototype: Null,
        callable: Some(ArrowFuncExt(func_data)),
        class_name: "Function",
        descriptors: { "name": nf_desc, "length": nf_desc },
        symbol_descriptors: {},
        extensible: true,
      })
    }
    FuncExprExt(name, params, rest_param, body, _) => {
      validate_function_signature_ext(
        self.strict,
        name,
        params,
        rest_param,
        body,
      )
      let func_data : FuncDataExt = {
        name,
        params,
        rest_param,
        body,
        closure: env,
        strict: is_function_strict(self.strict, body),
      }
      make_func_ext(func_data)
    }
    RegexLit(pattern, flags, _) => make_regexp_object(pattern, flags)
    SpreadExpr(_, _) =>
      raise @errors.SyntaxError(
        message="Spread expression used outside of call or array literal",
      )
    DestructureAssign(pattern, value_expr, _) => {
      let value = self.eval_expr(value_expr, env)
      self.assign_pattern(pattern, value, env)
      value
    }
    OptionalMember(obj_expr, prop, loc) => {
      // obj?.prop - return undefined if obj is null/undefined
      let obj = self.eval_expr(obj_expr, env)
      match obj {
        Null | Undefined => Undefined
        _ => self.get_property(obj, prop, loc)
      }
    }
    OptionalComputedMember(obj_expr, key_expr, loc) => {
      // obj?.[key] - return undefined if obj is null/undefined
      let obj = self.eval_expr(obj_expr, env)
      match obj {
        Null | Undefined => Undefined
        _ => {
          let key = self.eval_expr(key_expr, env)
          self.get_computed_property(obj, key, loc)
        }
      }
    }
    OptionalCall(callee_expr, arg_exprs, loc) =>
      // func?.(args) - return undefined if func is null/undefined
      // Per ES spec, arguments are NOT evaluated if function is nullish
      // Need to preserve receiver for method calls
      match callee_expr {
        OptionalMember(obj_expr, prop, mloc) => {
          let obj = self.eval_expr(obj_expr, env)
          match obj {
            Null | Undefined => Undefined
            _ => {
              let func_val = self.get_property(obj, prop, mloc)
              match func_val {
                Null | Undefined => Undefined
                _ => {
                  let args = self.eval_args_with_spread(arg_exprs, env)
                  self.call_value(func_val, obj, args, loc)
                }
              }
            }
          }
        }
        OptionalComputedMember(obj_expr, key_expr, mloc) => {
          let obj = self.eval_expr(obj_expr, env)
          match obj {
            Null | Undefined => Undefined
            _ => {
              let key = self.eval_expr(key_expr, env)
              let func_val = self.get_computed_property(obj, key, mloc)
              match func_val {
                Null | Undefined => Undefined
                _ => {
                  let args = self.eval_args_with_spread(arg_exprs, env)
                  self.call_value(func_val, obj, args, loc)
                }
              }
            }
          }
        }
        Member(obj_expr, prop, mloc) => {
          let obj = self.eval_expr(obj_expr, env)
          let func_val = self.get_property(obj, prop, mloc)
          match func_val {
            Null | Undefined => Undefined
            _ => {
              let args = self.eval_args_with_spread(arg_exprs, env)
              self.call_value(func_val, obj, args, loc)
            }
          }
        }
        ComputedMember(obj_expr, key_expr, mloc) => {
          let obj = self.eval_expr(obj_expr, env)
          let key = self.eval_expr(key_expr, env)
          let func_val = self.get_computed_property(obj, key, mloc)
          match func_val {
            Null | Undefined => Undefined
            _ => {
              let args = self.eval_args_with_spread(arg_exprs, env)
              self.call_value(func_val, obj, args, loc)
            }
          }
        }
        _ => {
          let callee = self.eval_expr(callee_expr, env)
          match callee {
            Null | Undefined => Undefined
            _ => {
              let args = self.eval_args_with_spread(arg_exprs, env)
              self.call_value(callee, Undefined, args, loc)
            }
          }
        }
      }
    ClassExpr(name, superclass, methods, _) =>
      self.create_class(name.unwrap_or(""), superclass, methods, env)
    SuperCall(arg_exprs, loc) => {
      // super(args) - call the parent constructor
      // Get the [[HomeObject]] from the current environment
      let super_ctor = env.get("[[SuperConstructor]]")
      let this_val = env.get("this")
      let args = self.eval_args_with_spread(arg_exprs, env)
      // Call the super constructor
      match super_ctor {
        Object(data) =>
          match data.callable {
            Some(
              ClassConstructor(
                _,
                _,
                _super_ctor,
                ctor_fn,
                ctor_env,
                super_proto
              )
            ) => {
              // Create new environment for the constructor call
              let call_env = Environment::new(parent=Some(ctor_env))
              call_env.def_builtin("this", this_val)
              // Set up super constructor chain if there's a grandparent
              match _super_ctor {
                Some(grand_super) => {
                  call_env.def_builtin("[[SuperConstructor]]", grand_super)
                  call_env.def_builtin("[[SuperPrototype]]", super_proto)
                }
                None => ()
              }
              // Bind parameters and execute constructor body
              match ctor_fn {
                Some((ctor_params, ctor_body)) => {
                  for i = 0; i < ctor_params.length(); i = i + 1 {
                    let val : Value = if i < args.length() {
                      args[i]
                    } else {
                      Undefined
                    }
                    call_env.def(ctor_params[i], val, LetBinding)
                  }
                  let tte : Value? = if call_env.has("[[ThrowTypeError]]") {
                    Some(call_env.get("[[ThrowTypeError]]"))
                  } else {
                    None
                  }
                  call_env.def(
                    "arguments",
                    make_arguments_object(
                      args,
                      super_ctor,
                      true,
                      throw_type_error=tte,
                    ),
                    VarBinding,
                  )
                  self.hoist_declarations(ctor_body, call_env)
                  let exec_result = self.exec_stmts(ctor_body, call_env)
                  // If super constructor returns an object, use it as the new 'this'
                  match exec_result {
                    ReturnSignal(v) =>
                      match v {
                        Object(_)
                        | Array(_)
                        | Map(_)
                        | Set(_)
                        | Promise(_)
                        | Proxy(_) => {
                          // Update 'this' in the current environment
                          env.assign("this", v)
                          return v
                        }
                        _ => ()
                      }
                    _ => ()
                  }
                }
                None => ()
              }
              env.get("this")
            }
            Some(_) => {
              // Support non-class constructible supers (e.g. Promise constructor).
              // Use constructor semantics (`new`) instead of plain call.
              let super_result = self.construct_value(super_ctor, args, loc)
              match super_result {
                Object(_)
                | Array(_)
                | Map(_)
                | Set(_)
                | Promise(_)
                | Proxy(_) => {
                  env.assign("this", super_result)
                  super_result
                }
                _ => env.get("this")
              }
            }
            _ =>
              raise @errors.ReferenceError(
                message=format_loc_context(
                  "super() called but [[SuperConstructor]] is not a constructor",
                  loc,
                ),
              )
          }
        _ =>
          raise @errors.ReferenceError(
            message=format_loc_context(
              "super() called but no [[SuperConstructor]] in scope", loc,
            ),
          )
      }
    }
    SuperMember(prop, loc) => {
      // super.prop - access parent prototype property
      let super_proto = env.get("[[SuperPrototype]]")
      match super_proto {
        Null | Undefined =>
          raise @errors.ReferenceError(
            message="super.prop used but no [[SuperPrototype]] in scope at line \{loc.line}",
          )
        _ => self.get_property(super_proto, prop, loc)
      }
    }
    SuperComputedMember(key_expr, loc) => {
      // super[expr] - access parent prototype property with computed key
      let super_proto = env.get("[[SuperPrototype]]")
      let key = self.eval_expr(key_expr, env)
      match super_proto {
        Null | Undefined =>
          raise @errors.ReferenceError(
            message="super[expr] used but no [[SuperPrototype]] in scope at line \{loc.line}",
          )
        _ => self.get_computed_property(super_proto, key, loc)
      }
    }
    NewTargetExpr(_) =>
      // new.target - returns the constructor called with new, or undefined
      env.get("<new.target>") catch {
        _ => Undefined
      }
  }
}

///|
fn Interpreter::eval_binary(
  self : Interpreter,
  op : @ast.BinOp,
  left_expr : @ast.Expr,
  right_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // Short-circuit for &&, ||, and ??
  match op {
    And => {
      let left = self.eval_expr(left_expr, env)
      if not(is_truthy(left)) {
        return left
      }
      self.eval_expr(right_expr, env)
    }
    Or => {
      let left = self.eval_expr(left_expr, env)
      if is_truthy(left) {
        return left
      }
      self.eval_expr(right_expr, env)
    }
    NullishCoalesce => {
      // ?? returns left if it's not null/undefined, otherwise right
      let left = self.eval_expr(left_expr, env)
      match left {
        Null | Undefined => self.eval_expr(right_expr, env)
        _ => left
      }
    }
    Instanceof => {
      // instanceof - ES2015+ with Symbol.hasInstance support (spec: 7.3.21 OrdinaryHasInstance)
      let l = self.eval_expr(left_expr, env)
      let r = self.eval_expr(right_expr, env)
      match r {
        Object(r_data) => {
          // Step 1: Check for Symbol.hasInstance method via GetMethod (walks prototype chain)
          let has_instance_sym = get_hasinstance_symbol()
          let has_instance_method = get_symbol_method(r, has_instance_sym.id)
          match has_instance_method {
            Some(has_instance_fn) =>
              // Call [Symbol.hasInstance](l) and convert result to boolean
              match has_instance_fn {
                Object(fn_data) =>
                  match fn_data.callable {
                    Some(_) => {
                      let result = self.call_value(has_instance_fn, r, [l], loc)
                      Bool(is_truthy(result))
                    }
                    None =>
                      // Symbol.hasInstance exists but is not callable - TypeError per spec
                      raise @errors.TypeError(
                        message="Symbol.hasInstance is not a function",
                      )
                  }
                _ =>
                  // Symbol.hasInstance is not an object - TypeError per spec
                  raise @errors.TypeError(
                    message="Symbol.hasInstance is not a function",
                  )
              }
            None =>
              // No Symbol.hasInstance found, use OrdinaryHasInstance
              // Step 2: Check if RHS is callable (required for OrdinaryHasInstance)
              match r_data.callable {
                None =>
                  raise @errors.TypeError(
                    message="Right-hand side of 'instanceof' is not callable",
                  )
                Some(_) =>
                  // Step 3: Get prototype property and walk LHS prototype chain
                  // Per OrdinaryHasInstance spec: if prototype is not an object, return false
                  // This handles bound functions which don't have own prototype property
                  match r_data.properties.get("prototype") {
                    Some(proto) =>
                      match proto {
                        Object(_) =>
                          instanceof_prototype_chain(l, proto, self.global)
                        // Non-object prototype: return false per spec
                        _ => Bool(false)
                      }
                    // No prototype property (e.g., bound functions): return false per spec
                    None => Bool(false)
                  }
              }
          }
        }
        Proxy(proxy_data) => {
          // Step 1: Check for Symbol.hasInstance on the proxy (via get trap)
          let has_instance_sym = get_hasinstance_symbol()
          let has_instance_method = get_symbol_method(r, has_instance_sym.id)
          match has_instance_method {
            Some(has_instance_fn) =>
              match has_instance_fn {
                Object(fn_data) =>
                  match fn_data.callable {
                    Some(_) => {
                      let result = self.call_value(has_instance_fn, r, [l], loc)
                      Bool(is_truthy(result))
                    }
                    None =>
                      raise @errors.TypeError(
                        message="Symbol.hasInstance is not a function",
                      )
                  }
                _ =>
                  raise @errors.TypeError(
                    message="Symbol.hasInstance is not a function",
                  )
              }
            None => {
              // Step 2: Fall back to prototype chain check
              let target = get_proxy_target(proxy_data)
              let proto = self.get_property(r, "prototype", loc)
              match proto {
                Object(_) => instanceof_prototype_chain(l, proto, self.global)
                _ =>
                  // Check if target is callable
                  match target {
                    Object(t_data) =>
                      match t_data.callable {
                        Some(_) => Bool(false)
                        None =>
                          raise @errors.TypeError(
                            message="Right-hand side of 'instanceof' is not callable",
                          )
                      }
                    _ => Bool(false)
                  }
              }
            }
          }
        }
        _ =>
          raise @errors.TypeError(
            message="Right-hand side of 'instanceof' is not an object",
          )
      }
    }
    In => {
      let left = self.eval_expr(left_expr, env)
      let right = self.eval_expr(right_expr, env)
      match right {
        Proxy(proxy_data) => {
          let trap = get_proxy_trap(proxy_data, "has")
          match trap {
            Some(trap_fn) => {
              let target = get_proxy_target(proxy_data)
              let handler = get_proxy_handler(proxy_data)
              let prop_key = match left {
                Symbol(_) => left
                _ => String_(left.to_string())
              }
              let result = self.call_value(
                trap_fn,
                handler,
                [target, prop_key],
                loc,
              )
              Bool(is_truthy(result))
            }
            None => {
              let target = get_proxy_target(proxy_data)
              eval_binary_op(In, left, target, loc)
            }
          }
        }
        _ => eval_binary_op(In, left, right, loc)
      }
    }
    _ => {
      let left = self.eval_expr(left_expr, env)
      let right = self.eval_expr(right_expr, env)
      eval_binary_op(op, left, right, loc)
    }
  }
}

///|
fn eval_binary_op(
  op : @ast.BinOp,
  left : Value,
  right : Value,
  _loc : @token.Loc,
) -> Value raise Error {
  match (op, left, right) {
    // Symbol cannot be converted to string implicitly
    (Add, Symbol(_), _) | (Add, _, Symbol(_)) =>
      raise @errors.TypeError(
        message="Cannot convert a Symbol value to a string",
      )
    // String concatenation
    (Add, String_(a), String_(b)) => String_(a + b)
    (Add, String_(a), b) => String_(a + to_js_string(b))
    (Add, a, String_(b)) => String_(to_js_string(a) + b)
    // Numeric operations
    (Add, Number(a), Number(b)) => Number(a + b)
    (Sub, Number(a), Number(b)) => Number(a - b)
    (Mul, Number(a), Number(b)) => Number(a * b)
    (Div, Number(a), Number(b)) => Number(a / b)
    (Mod, Number(a), Number(b)) => Number(a % b)
    // Comparison (numeric)
    (Lt, Number(a), Number(b)) => Bool(a < b)
    (Gt, Number(a), Number(b)) => Bool(a > b)
    (LtEq, Number(a), Number(b)) => Bool(a <= b)
    (GtEq, Number(a), Number(b)) => Bool(a >= b)
    // Comparison (string — lexicographic)
    (Lt, String_(a), String_(b)) => Bool(a < b)
    (Gt, String_(a), String_(b)) => Bool(a > b)
    (LtEq, String_(a), String_(b)) => Bool(a <= b)
    (GtEq, String_(a), String_(b)) => Bool(a >= b)
    // Equality
    (EqEqEq, l, r) => Bool(strict_equal(l, r))
    (NotEqEq, l, r) => Bool(not(strict_equal(l, r)))
    (EqEq, l, r) => Bool(loose_equal(l, r))
    (NotEq, l, r) => Bool(not(loose_equal(l, r)))
    // Exponentiation
    (Exp, Number(a), Number(b)) => Number(@math.pow(a, b))
    (Exp, l, r) => Number(@math.pow(to_number(l), to_number(r)))
    // Add fallback: ToPrimitive, then check for strings
    (Add, l, r) => {
      // ToPrimitive with hint "default" (acts like "number")
      let lp = match l {
        Object(data) => to_primitive_number(l, data)
        Array(arr_data) => {
          let s = arr_data.elements.map(fn(v) { v.to_string() }).join(",")
          String_(s)
        }
        _ => l
      }
      let rp = match r {
        Object(data) => to_primitive_number(r, data)
        Array(arr_data) => {
          let s = arr_data.elements.map(fn(v) { v.to_string() }).join(",")
          String_(s)
        }
        _ => r
      }
      // If either is a string after ToPrimitive, do string concatenation
      match (lp, rp) {
        (String_(a), String_(b)) => String_(a + b)
        (String_(a), b) => String_(a + to_js_string(b))
        (a, String_(b)) => String_(to_js_string(a) + b)
        (a, b) => Number(to_number(a) + to_number(b))
      }
    }
    (Sub, l, r) => Number(to_number(l) - to_number(r))
    (Mul, l, r) => Number(to_number(l) * to_number(r))
    (Div, l, r) => Number(to_number(l) / to_number(r))
    (Mod, l, r) => Number(to_number(l) % to_number(r))
    // Comparison fallbacks (type coercion)
    (Lt, l, r) => Bool(to_number(l) < to_number(r))
    (Gt, l, r) => Bool(to_number(l) > to_number(r))
    (LtEq, l, r) => Bool(to_number(l) <= to_number(r))
    (GtEq, l, r) => Bool(to_number(l) >= to_number(r))
    // Bitwise operations
    (BitAnd, l, r) =>
      Number((to_int32(to_number(l)) & to_int32(to_number(r))).to_double())
    (BitOr, l, r) =>
      Number((to_int32(to_number(l)) | to_int32(to_number(r))).to_double())
    (BitXor, l, r) =>
      Number((to_int32(to_number(l)) ^ to_int32(to_number(r))).to_double())
    // Shift operations
    (LShift, l, r) => {
      let a = to_int32(to_number(l))
      let shift = to_int32(to_number(r)) & 0x1f
      Number((a << shift).to_double())
    }
    (RShift, l, r) => {
      let a = to_int32(to_number(l))
      let shift = to_int32(to_number(r)) & 0x1f
      Number((a >> shift).to_double())
    }
    (URShift, l, r) => {
      let a = to_int32(to_number(l))
      let shift = to_int32(to_number(r)) & 0x1f
      if shift == 0 {
        if a < 0 {
          Number(a.to_double() + 4294967296.0)
        } else {
          Number(a.to_double())
        }
      } else {
        let shifted = a >> shift
        let all_bits : Int = 0x7FFFFFFF
        let mask = all_bits >> (shift - 1)
        Number((shifted & mask).to_double())
      }
    }
    // in operator - walks prototype chain
    (In, l, r) =>
      match r {
        Object(data) =>
          // Handle Symbol keys
          match l {
            Symbol(sym) => {
              // Check own symbol property first
              if data.symbol_properties.contains(sym.id) {
                return Bool(true)
              }
              // Walk prototype chain for symbol properties
              let mut current = data.prototype
              while true {
                match current {
                  Object(proto_data) =>
                    if proto_data.symbol_properties.contains(sym.id) {
                      return Bool(true)
                    } else {
                      current = proto_data.prototype
                    }
                  _ => break
                }
              }
              Bool(false)
            }
            _ => {
              let key = l.to_string()
              // Check own property first
              if data.properties.contains(key) {
                return Bool(true)
              }
              // Walk prototype chain
              let mut current = data.prototype
              while true {
                match current {
                  Object(proto_data) =>
                    if proto_data.properties.contains(key) {
                      return Bool(true)
                    } else {
                      current = proto_data.prototype
                    }
                  _ => break
                }
              }
              Bool(false)
            }
          }
        Array(data) => {
          let idx = to_number(l).to_int() catch { _ => -1 }
          Bool(idx >= 0 && idx < data.elements.length())
        }
        _ =>
          raise @errors.TypeError(
            message="Cannot use 'in' operator to search for '\{l.to_string()}' in \{type_of(r)}",
          )
      }
    // And/Or/??/Instanceof already handled in eval_binary
    (And, _, _) | (Or, _, _) | (NullishCoalesce, _, _) | (Instanceof, _, _) =>
      raise @errors.InternalError(
        message="Internal error: logical operators should be short-circuited",
      )
  }
}

///|
/// GetMethod for symbol keys - walks prototype chain to find a symbol-keyed method (spec 7.3.9)
fn get_symbol_method(obj : Value, symbol_id : Int) -> Value? {
  let mut current = obj
  while true {
    match current {
      Object(data) =>
        match data.symbol_properties.get(symbol_id) {
          Some(val) =>
            match val {
              Null | Undefined => return None
              _ => return Some(val)
            }
          None => current = data.prototype
        }
      _ => return None
    }
  }
  None
}

///|
/// Helper for instanceof: walk prototype chain to check if l's prototype chain includes target_proto
fn instanceof_prototype_chain(
  l : Value,
  target_proto : Value,
  env : Environment,
) -> Value {
  let mut current = match l {
    Object(l_data) => l_data.prototype
    Array(_) => get_constructor_prototype(env, "Array")
    Map(_) => get_constructor_prototype(env, "Map")
    Set(_) => get_constructor_prototype(env, "Set")
    Promise(_) => get_constructor_prototype(env, "Promise")
    Proxy(proxy_data) =>
      match proxy_data.target {
        Some(target) =>
          match target {
            Object(data) => data.prototype
            _ => Null
          }
        None => return Bool(false)
      }
    // Primitive values are never instances
    _ => return Bool(false)
  }
  let mut found = false
  while true {
    match current {
      Null | Undefined => break
      _ =>
        if strict_equal(current, target_proto) {
          found = true
          break
        } else {
          match current {
            Object(data) => current = data.prototype
            _ => break
          }
        }
    }
  }
  Bool(found)
}

///|
fn get_constructor_prototype(env : Environment, ctor_name : String) -> Value {
  let ctor = env.get(ctor_name) catch { _ => return Null }
  match ctor {
    Object(data) =>
      match data.properties.get("prototype") {
        Some(proto) => proto
        None => Null
      }
    _ => Null
  }
}

///|
fn strict_equal(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Number(a), Number(b)) => a == b
    (String_(a), String_(b)) => a == b
    (Bool(a), Bool(b)) => a == b
    (Null, Null) => true
    (Undefined, Undefined) => true
    (Object(a), Object(b)) => physical_equal(a, b)
    (Array(a), Array(b)) => physical_equal(a, b)
    (Symbol(a), Symbol(b)) => a.id == b.id // Symbols compare by identity
    (Map(a), Map(b)) => physical_equal(a, b) // Maps compare by reference
    (Set(a), Set(b)) => physical_equal(a, b) // Sets compare by reference
    (Promise(a), Promise(b)) => physical_equal(a, b) // Promises compare by reference
    (Proxy(a), Proxy(b)) => physical_equal(a, b) // Proxies compare by reference
    _ => false
  }
}

///|
fn loose_equal(a : Value, b : Value) -> Bool {
  // Abstract Equality Comparison Algorithm (ES spec 7.2.14)
  match (a, b) {
    // Same type: use strict equality
    (Number(x), Number(y)) => x == y
    (String_(x), String_(y)) => x == y
    (Bool(x), Bool(y)) => x == y
    (Null, Null) => true
    (Undefined, Undefined) => true
    (Object(x), Object(y)) => physical_equal(x, y)
    (Array(x), Array(y)) => physical_equal(x, y)
    (Symbol(x), Symbol(y)) => x.id == y.id // Symbols compare by identity only
    (Promise(x), Promise(y)) => physical_equal(x, y) // Promises compare by reference
    (Proxy(x), Proxy(y)) => physical_equal(x, y) // Proxies compare by reference
    // null == undefined
    (Null, Undefined) | (Undefined, Null) => true
    // Number == String: convert string to number
    (Number(n), String_(s)) => {
      let num = to_number(String_(s)) catch { _ => return false }
      n == num
    }
    (String_(s), Number(n)) => {
      let num = to_number(String_(s)) catch { _ => return false }
      num == n
    }
    // Boolean == anything: convert boolean to number first
    (Bool(bval), _) => loose_equal(Number(if bval { 1.0 } else { 0.0 }), b)
    (_, Bool(bval)) => loose_equal(a, Number(if bval { 1.0 } else { 0.0 }))
    // Object/Array == Number/String: try ToPrimitive
    (Object(data), Number(_)) | (Object(data), String_(_)) => {
      // Use ToPrimitive with "number" hint (default for ordinary objects)
      let prim = try { to_primitive_number(a, data) } catch { _ => String_(a.to_string()) }
      loose_equal(prim, b)
    }
    (Number(_), Object(data)) | (String_(_), Object(data)) => {
      let prim = try { to_primitive_number(b, data) } catch { _ => String_(b.to_string()) }
      loose_equal(a, prim)
    }
    (Array(_), Number(_)) | (Array(_), String_(_)) => {
      let prim = try { String_(to_js_string(a)) } catch { _ => String_(a.to_string()) }
      loose_equal(prim, b)
    }
    (Number(_), Array(_)) | (String_(_), Array(_)) => {
      let prim = try { String_(to_js_string(b)) } catch { _ => String_(b.to_string()) }
      loose_equal(a, prim)
    }
    // Symbols don't coerce - any comparison with Symbol and different type is false
    (Symbol(_), _) | (_, Symbol(_)) => false
    // Everything else is false
    _ => false
  }
}

///|
/// Check whether `name` is a non-writable property on the global object
/// (undefined, NaN, Infinity). These are { writable:false } per ES spec §19.1.
fn Interpreter::is_immutable_global(self : Interpreter, name : String) -> Bool {
  match self.global_this {
    Object(data) =>
      match data.descriptors.get(name) {
        Some(desc) => not(desc.writable)
        None => false
      }
    _ => false
  }
}

///|
fn Interpreter::eval_unary(
  self : Interpreter,
  op : @ast.UnaryOp,
  operand : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  match op {
    Typeof =>
      match operand {
        Ident(name, _) =>
          if env.has(name) {
            String_(type_of(env.get(name)))
          } else {
            String_("undefined")
          }
        _ => String_(type_of(self.eval_expr(operand, env)))
      }
    Void => {
      let _ = self.eval_expr(operand, env)
      Undefined
    }
    Delete =>
      match operand {
        Member(obj_expr, prop, _) => {
          let obj = self.eval_expr(obj_expr, env)
          match obj {
            Proxy(proxy_data) => {
              let trap = get_proxy_trap(proxy_data, "deleteProperty")
              match trap {
                Some(trap_fn) => {
                  let target = get_proxy_target(proxy_data)
                  let handler = get_proxy_handler(proxy_data)
                  let result = self.call_value(
                    trap_fn,
                    handler,
                    [target, String_(prop)],
                    loc,
                  )
                  if not(is_truthy(result)) && self.strict {
                    raise @errors.TypeError(
                      message="'deleteProperty' on proxy: trap returned falsish for property '\{prop}'",
                    )
                  }
                  Bool(is_truthy(result))
                }
                None => {
                  let target = get_proxy_target(proxy_data)
                  match target {
                    Object(data) => {
                      match data.descriptors.get(prop) {
                        Some(desc) =>
                          if not(desc.configurable) {
                            if self.strict {
                              raise @errors.TypeError(
                                message="Cannot delete property '\{prop}'",
                              )
                            }
                            return Bool(false)
                          }
                        None => ()
                      }
                      let _ = data.properties.remove(prop)
                      let _ = data.descriptors.remove(prop)
                      Bool(true)
                    }
                    _ => Bool(true)
                  }
                }
              }
            }
            Object(data) => {
              match data.descriptors.get(prop) {
                Some(desc) =>
                  if not(desc.configurable) {
                    if self.strict {
                      raise @errors.TypeError(
                        message="Cannot delete property '\{prop}'",
                      )
                    }
                    return Bool(false)
                  }
                None => ()
              }
              let _ = data.properties.remove(prop)
              let _ = data.descriptors.remove(prop)
              Bool(true)
            }
            _ => Bool(true)
          }
        }
        ComputedMember(obj_expr, key_expr, _) => {
          let obj = self.eval_expr(obj_expr, env)
          let key = self.eval_expr(key_expr, env)
          match obj {
            Proxy(proxy_data) => {
              let trap = get_proxy_trap(proxy_data, "deleteProperty")
              match trap {
                Some(trap_fn) => {
                  let target = get_proxy_target(proxy_data)
                  let handler = get_proxy_handler(proxy_data)
                  let prop_key = match key {
                    Symbol(_) => key
                    _ => String_(to_js_string(key))
                  }
                  let result = self.call_value(
                    trap_fn,
                    handler,
                    [target, prop_key],
                    loc,
                  )
                  if not(is_truthy(result)) && self.strict {
                    raise @errors.TypeError(
                      message="'deleteProperty' on proxy: trap returned falsish",
                    )
                  }
                  Bool(is_truthy(result))
                }
                None => {
                  let target = get_proxy_target(proxy_data)
                  match target {
                    Object(data) => {
                      let k = to_js_string(key)
                      match data.descriptors.get(k) {
                        Some(desc) =>
                          if not(desc.configurable) {
                            if self.strict {
                              raise @errors.TypeError(
                                message="Cannot delete property '\{k}'",
                              )
                            }
                            return Bool(false)
                          }
                        None => ()
                      }
                      let _ = data.properties.remove(k)
                      let _ = data.descriptors.remove(k)
                      Bool(true)
                    }
                    _ => Bool(true)
                  }
                }
              }
            }
            Object(data) =>
              match key {
                Symbol(sym) => {
                  // Delete a symbol-keyed property
                  match data.symbol_descriptors.get(sym.id) {
                    Some(desc) =>
                      if not(desc.configurable) {
                        if self.strict {
                          raise @errors.TypeError(
                            message="Cannot delete property",
                          )
                        }
                        return Bool(false)
                      }
                    None => ()
                  }
                  let _ = data.symbol_properties.remove(sym.id)
                  let _ = data.symbol_descriptors.remove(sym.id)
                  Bool(true)
                }
                _ => {
                  let k = to_js_string(key)
                  match data.descriptors.get(k) {
                    Some(desc) =>
                      if not(desc.configurable) {
                        if self.strict {
                          raise @errors.TypeError(
                            message="Cannot delete property '\{k}'",
                          )
                        }
                        return Bool(false)
                      }
                    None => ()
                  }
                  let _ = data.properties.remove(k)
                  let _ = data.descriptors.remove(k)
                  Bool(true)
                }
              }
            _ => Bool(true)
          }
        }
        Ident(name, _) =>
          // delete of an unqualified identifier is a SyntaxError in strict mode
          if self.strict {
            raise @errors.SyntaxError(
              message="Delete of an unqualified identifier in strict mode.",
            )
          } else {
            // In non-strict mode, check if the identifier is a non-configurable
            // property on the global object (e.g. undefined, NaN, Infinity).
            match self.global_this {
              Object(data) =>
                match data.descriptors.get(name) {
                  Some(desc) =>
                    if not(desc.configurable) {
                      Bool(false)
                    } else {
                      let _ = data.properties.remove(name)
                      let _ = data.descriptors.remove(name)
                      Bool(true)
                    }
                  None => Bool(true)
                }
              _ => Bool(true)
            }
          }
        _ => Bool(true)
      }
    _ => {
      let val = self.eval_expr(operand, env)
      match op {
        Neg => Number(-to_number(val))
        Pos => Number(to_number(val))
        Not => Bool(not(is_truthy(val)))
        BitNot => Number(to_int32(to_number(val)).lnot().to_double())
        _ =>
          raise @errors.InternalError(
            message="Unexpected unary operator at line \{loc.line}, col \{loc.col}",
          )
      }
    }
  }
}

///|
/// Spread an iterable value into an array of values using the iterator protocol
fn Interpreter::spread_iterable(
  self : Interpreter,
  val : Value,
  loc : @token.Loc,
) -> Array[Value] raise Error {
  let result : Array[Value] = []

  // Try to get the iterator via Symbol.iterator protocol
  let iterator_sym = get_iterator_symbol()
  let iterator_method = self.get_computed_property(
    val,
    Symbol(iterator_sym),
    loc,
  )

  // Get the iterator object
  let iterator = match iterator_method {
    Object(data) =>
      match data.callable {
        Some(_) => self.call_value(iterator_method, val, [], loc)
        None =>
          raise @errors.TypeError(
            message=type_of(val) +
              " is not iterable (Symbol.iterator is not a function)",
          )
      }
    Undefined =>
      // No iterator method — fall back for arrays/strings which are built-in iterables
      match val {
        Array(arr) => {
          for el in arr.elements {
            result.push(el)
          }
          return result
        }
        String_(s) => {
          let chars = s.to_array()
          for c in chars {
            let buf = StringBuilder::new()
            buf.write_char(c)
            result.push(String_(buf.to_string()))
          }
          return result
        }
        _ => raise @errors.TypeError(message=type_of(val) + " is not iterable")
      }
    _ => raise @errors.TypeError(message=type_of(val) + " is not iterable")
  }

  // Get the next method from the iterator (walk prototype chain)
  let next_method = match iterator {
    Object(iter_data) =>
      // First check direct properties
      match iter_data.properties.get("next") {
        Some(next_fn) => next_fn
        None => {
          // Walk prototype chain
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
              raise @errors.TypeError(message="iterator.next is not a function")
            _ => found
          }
        }
      }
    _ => raise @errors.TypeError(message="Iterator result is not an object")
  }

  // Iterate using the iterator protocol
  while true {
    let iter_result = self.call_value(next_method, iterator, [], loc)
    let (done, value) = match iter_result {
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
      _ => raise @errors.TypeError(message="Iterator result is not an object")
    }
    if done {
      break
    }
    result.push(value)
  }
  result
}

///|
fn Interpreter::eval_args_with_spread(
  self : Interpreter,
  arg_exprs : Array[@ast.Expr],
  env : Environment,
) -> Array[Value] raise Error {
  let args : Array[Value] = []
  for a in arg_exprs {
    match a {
      SpreadExpr(inner, loc) => {
        let val = self.eval_expr(inner, env)
        // Use iterator protocol for spreading
        let spread_vals = self.spread_iterable(val, loc)
        for v in spread_vals {
          args.push(v)
        }
      }
      _ => args.push(self.eval_expr(a, env))
    }
  }
  args
}

///|
/// Check if a value is the global eval function
fn is_eval_function(val : Value) -> Bool {
  match val {
    Object(obj_data) =>
      match obj_data.callable {
        Some(NonConstructableCallable("eval", _)) => true
        _ => false
      }
    _ => false
  }
}

///|
/// Recursively strip Grouping nodes from an expression.
/// Per ES spec, grouping parentheses do not change the Reference type,
/// so ((eval))("code") is still a direct eval call.
fn unwrap_grouping(expr : @ast.Expr) -> @ast.Expr {
  match expr {
    Grouping(inner, _) => unwrap_grouping(inner)
    _ => expr
  }
}

///|
/// Execute eval code in a given environment.
/// If `direct` is true, executes in the caller's environment (direct eval).
/// If `direct` is false, executes in the global environment (indirect eval).
/// Handles strict mode isolation and var leaking per ES spec.
///
/// Per ES spec (18.2.1.1 PerformEval):
/// - Strict eval: all declarations (var, let, const, function) are isolated in a new scope
/// - Non-strict direct eval: var/function declarations leak to caller's variable environment,
///   but let/const are isolated in a new eval lexical scope
/// - Non-strict indirect eval: var/function declarations leak to global scope,
///   but let/const are isolated in a new eval lexical scope
fn Interpreter::perform_eval(
  self : Interpreter,
  code : String,
  caller_env : Environment,
  direct : Bool,
) -> Value raise Error {
  // Parse the code — syntax errors propagate as SyntaxError
  let prog = @parser.parse(code)
  let stmts = prog.stmts
  if stmts.length() == 0 {
    return Undefined
  }
  // Determine if eval code is strict.
  // Direct eval inherits strictness from the caller OR its own "use strict" directive.
  // Indirect eval is strict ONLY if the eval code itself has "use strict" — it does
  // NOT inherit the caller's strict mode (it runs as a fresh global script).
  let eval_strict = if direct {
    self.strict || has_use_strict(stmts)
  } else {
    has_use_strict(stmts)
  }
  // Apply static block-scoped redeclaration checks before declaration instantiation.
  self.validate_block_early_errors(stmts, eval_strict)
  // Determine the variable environment (where var/function declarations leak to).
  // For direct eval, walk up from the caller's env to find the function/global scope
  // (the nearest is_var_scope environment). This ensures that eval("var x = 1")
  // inside a block correctly hoists to the enclosing function scope, not the block.
  let var_env : Environment = if direct {
    caller_env.find_var_env()
  } else {
    self.global
  }
  // Always create a new scope for eval execution.
  // This isolates let/const declarations from the caller.
  // For strict eval, it also isolates var/function declarations.
  // For direct eval, parent to caller_env so block-scoped bindings are visible:
  //   { let x = 1; eval("x") } must see x.
  // For indirect eval, parent to global scope since it runs as a fresh script.
  let exec_parent = if direct { caller_env } else { self.global }
  let exec_env = Environment::new(parent=Some(exec_parent))
  // Save and set strict mode
  let saved_strict = self.strict
  if eval_strict {
    self.strict = true
  }
  let result = try {
    if eval_strict {
      // Strict eval: all declarations stay in the eval scope (isolated)
      self.hoist_declarations(stmts, exec_env)
      hoist_block_tdz(stmts, exec_env)
    } else {
      // EvalDeclarationInstantiation steps 5.a and 5.d:
      // Check for var/lexical conflicts before hoisting.
      let var_names = collect_eval_var_names(stmts)
      // Step 5.a: If var_env is the global Environment Record, check that
      // var names don't conflict with global lexical (let/const) declarations.
      if var_env.parent is None {
        for name in var_names {
          match var_env.bindings.get(name) {
            Some(b) =>
              if b.kind == LetBinding || b.kind == ConstBinding {
                raise @errors.SyntaxError(
                  message="Identifier '\{name}' has already been declared",
                )
              }
            _ => ()
          }
        }
      }
      // Step 5.d: Walk from caller_env up to var_env (exclusive), checking
      // that no intermediate scope has a binding that conflicts with a var name.
      // This prevents eval("var x") from hoisting past a block-scoped let/const x.
      {
        let mut this_lex = caller_env
        while not(this_lex.is_var_scope) {
          for name in var_names {
            if this_lex.bindings.contains(name) {
              raise @errors.SyntaxError(
                message="Identifier '\{name}' has already been declared",
              )
            }
          }
          match this_lex.parent {
            Some(parent) => this_lex = parent
            None => break
          }
        }
      }
      // Non-strict eval: hoist var/function to the variable environment (leak),
      // then hoist let/const TDZ markers to the eval scope (isolated)
      exec_env.def(eval_function_reconcile_marker, Bool(true), LetBinding)
      self.hoist_declarations(stmts, var_env)
      hoist_block_tdz(stmts, exec_env)
    }
    // Execute statements and collect result
    let mut last : Value = Undefined
    for stmt in stmts {
      match self.exec_stmt(stmt, exec_env) {
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
    e => {
      self.strict = saved_strict
      raise e
    }
  }
  self.strict = saved_strict
  result
}

///|
fn Interpreter::eval_call(
  self : Interpreter,
  callee_expr : @ast.Expr,
  arg_exprs : Array[@ast.Expr],
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // Detect direct eval: eval(...), (eval)(...), ((eval))(...) etc.
  // Per ES spec, grouping parentheses do not change the Reference type,
  // so any nesting of parens around eval is still a direct eval call.
  match unwrap_grouping(callee_expr) {
    Ident("eval", _) => {
      // Check if this identifier actually resolves to the global eval function
      let callee = env.get("eval") catch {
        _ =>
          // eval is not defined - throw ReferenceError
          raise @errors.ReferenceError(message="eval is not defined")
      }
      if is_eval_function(callee) {
        // Direct eval: parse and execute in caller's environment
        let args = self.eval_args_with_spread(arg_exprs, env)
        if args.length() == 0 {
          return Undefined
        }
        match args[0] {
          String_(code) => return self.perform_eval(code, env, true)
          other => return other // non-string argument returns as-is
        }
      }
      // eval has been shadowed by a non-eval binding — call normally
      let args = self.eval_args_with_spread(arg_exprs, env)
      self.call_value(callee, Undefined, args, loc)
    }
    _ =>
      // Per ES spec (13.3.6.1), evaluate callee/receiver first, then arguments.
      match callee_expr {
        Member(obj_expr, prop, mloc) =>
          match obj_expr {
            Ident("console", _) => {
              let callee = self.eval_member(obj_expr, prop, env, mloc)
              let args = self.eval_args_with_spread(arg_exprs, env)
              self.call_value(callee, Undefined, args, loc)
            }
            _ => {
              let obj = self.eval_expr(obj_expr, env)
              let func_val = self.get_property(obj, prop, mloc)
              let args = self.eval_args_with_spread(arg_exprs, env)
              self.call_value(func_val, obj, args, loc)
            }
          }
        ComputedMember(obj_expr, key_expr, mloc) => {
          let obj = self.eval_expr(obj_expr, env)
          let key = self.eval_expr(key_expr, env)
          let func_val = self.get_computed_property(obj, key, mloc)
          let args = self.eval_args_with_spread(arg_exprs, env)
          self.call_value(func_val, obj, args, loc)
        }
        SuperMember(prop, sloc) => {
          // super.method() - look up on super prototype, call with current this
          let super_proto = env.get("[[SuperPrototype]]")
          let func_val = self.get_property(super_proto, prop, sloc)
          let this_val = env.get("this") catch { _ => Undefined }
          let args = self.eval_args_with_spread(arg_exprs, env)
          self.call_value(func_val, this_val, args, loc)
        }
        SuperComputedMember(key_expr, sloc) => {
          // super[expr]() - look up on super prototype, call with current this
          let super_proto = env.get("[[SuperPrototype]]")
          let key = self.eval_expr(key_expr, env)
          let func_val = self.get_computed_property(super_proto, key, sloc)
          let this_val = env.get("this") catch { _ => Undefined }
          let args = self.eval_args_with_spread(arg_exprs, env)
          self.call_value(func_val, this_val, args, loc)
        }
        _ => {
          let callee = self.eval_expr(callee_expr, env)
          let args = self.eval_args_with_spread(arg_exprs, env)
          self.call_value(callee, Undefined, args, loc)
        }
      }
  }
}

///|
fn Interpreter::call_value(
  self : Interpreter,
  callee : Value,
  this_val : Value,
  args : Array[Value],
  loc : @token.Loc,
) -> Value raise Error {
  let normalize_sloppy_this = fn(tv : Value) {
    match tv {
      Undefined | Null => self.global_this
      _ => tv
    }
  }
  match callee {
    Proxy(proxy_data) => {
      // Verify target chain is callable (recursively unwrap nested proxies)
      let target = get_proxy_target(proxy_data)
      fn check_callable(v : Value) -> Bool {
        match v {
          Object(t_data) => t_data.callable is Some(_)
          Proxy(pd) =>
            match pd.target {
              Some(inner) => check_callable(inner)
              None => false
            }
          _ => false
        }
      }
      if not(check_callable(target)) {
        raise @errors.TypeError(message="proxy target is not a function")
      }
      let trap = get_proxy_trap(proxy_data, "apply")
      match trap {
        Some(trap_fn) => {
          let handler = get_proxy_handler(proxy_data)
          let args_array : Value = Array({ elements: args.copy() })
          return self.call_value(
            trap_fn,
            handler,
            [target, this_val, args_array],
            loc,
          )
        }
        None => return self.call_value(target, this_val, args, loc)
      }
    }
    Object(obj_data) =>
      match obj_data.callable {
        Some(UserFunc(data)) => {
          let saved_strict = self.strict
          let result = try {
            let func_env = Environment::new(parent=Some(data.closure))
            func_env.is_var_scope = true
            let func_strict = data.strict
            self.strict = func_strict
            if func_strict {
              // Strict mode: check for duplicate parameters
              check_duplicate_params(data.params)
              // Strict mode: validate parameter names
              for p in data.params {
                validate_strict_binding_name(p)
              }
            }
            let effective_this = if func_strict {
              this_val
            } else {
              normalize_sloppy_this(this_val)
            }
            func_env.def("this", effective_this, LetBinding)
            func_env.def("<new.target>", Undefined, LetBinding)
            for i = 0; i < data.params.length(); i = i + 1 {
              let val : Value = if i < args.length() {
                args[i]
              } else {
                Undefined
              }
              // In sloppy mode, duplicate params are allowed; last value wins
              if func_env.bindings.contains(data.params[i]) {
                func_env.assign(data.params[i], val)
              } else {
                func_env.def(data.params[i], val, LetBinding)
              }
            }
            // Create arguments object
            let tte_val : Value? = if func_env.has("[[ThrowTypeError]]") {
              Some(func_env.get("[[ThrowTypeError]]"))
            } else {
              None
            }
            func_env.def(
              "arguments",
              make_arguments_object(
                args,
                callee,
                func_strict,
                throw_type_error=tte_val,
              ),
              VarBinding,
            )
            // Hoist var declarations and function declarations within function body
            self.hoist_declarations(data.body, func_env)
            match data.name {
              Some(name) =>
                if not(func_env.bindings.contains(name)) {
                  func_env.def(name, callee, LetBinding)
                }
              None => ()
            }
            match self.exec_stmts(data.body, func_env) {
              Normal(_) => Undefined
              ReturnSignal(v) => v
              BreakSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="break statement outside of loop",
                )
              ContinueSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="continue statement outside of loop",
                )
            }
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
          result
        }
        Some(ArrowFunc(data)) => {
          let saved_strict = self.strict
          let result = try {
            self.strict = data.strict
            let func_env = Environment::new(parent=Some(data.closure))
            func_env.is_var_scope = true
            // Arrow functions do NOT rebind this — use closure's this
            for i = 0; i < data.params.length(); i = i + 1 {
              let val : Value = if i < args.length() {
                args[i]
              } else {
                Undefined
              }
              func_env.def(data.params[i], val, LetBinding)
            }
            self.hoist_declarations(data.body, func_env)
            match self.exec_stmts(data.body, func_env) {
              Normal(_) => Undefined
              ReturnSignal(v) => v
              BreakSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="break statement outside of loop",
                )
              ContinueSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="continue statement outside of loop",
                )
            }
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
          result
        }
        Some(UserFuncExt(data)) => {
          let saved_strict = self.strict
          let result = try {
            let func_env = Environment::new(parent=Some(data.closure))
            func_env.is_var_scope = true
            let func_strict = data.strict
            self.strict = func_strict
            if func_strict {
              // Strict mode: check for duplicate parameters and reserved names
              check_duplicate_params_ext(data.params, data.rest_param)
              for p in data.params {
                validate_strict_binding_name(p.name)
              }
              match data.rest_param {
                Some(rn) => validate_strict_binding_name(rn)
                None => ()
              }
            }
            let effective_this = if func_strict {
              this_val
            } else {
              normalize_sloppy_this(this_val)
            }
            func_env.def("this", effective_this, LetBinding)
            func_env.def("<new.target>", Undefined, LetBinding)
            // Bind params with defaults
            let mut effective_param_count = 0
            for i = 0; i < data.params.length(); i = i + 1 {
              let param = data.params[i]
              // Skip rest destructuring params - they're bound via rest_param
              if data.rest_param is Some(rn) && param.name == rn {
                continue
              }
              let val : Value = if effective_param_count < args.length() &&
                not(args[effective_param_count] is Undefined) {
                args[effective_param_count]
              } else {
                match param.default_val {
                  Some(default_expr) => self.eval_expr(default_expr, func_env)
                  None =>
                    if effective_param_count < args.length() {
                      args[effective_param_count]
                    } else {
                      Undefined
                    }
                }
              }
              func_env.def(param.name, val, LetBinding)
              // Destructure if pattern param
              match param.pattern {
                Some(pat) => self.bind_pattern(pat, val, func_env, LetBinding)
                None => ()
              }
              effective_param_count = effective_param_count + 1
            }
            // Rest param
            match data.rest_param {
              Some(rest_name) => {
                let rest_elements : Array[Value] = []
                for i = effective_param_count; i < args.length(); i = i + 1 {
                  rest_elements.push(args[i])
                }
                let rest_val = Array({ elements: rest_elements })
                func_env.def(rest_name, rest_val, LetBinding)
                // Apply destructuring pattern if present
                for p in data.params {
                  if p.name == rest_name {
                    match p.pattern {
                      Some(pat) =>
                        self.bind_pattern(pat, rest_val, func_env, LetBinding)
                      None => ()
                    }
                    break
                  }
                }
              }
              None => ()
            }
            // Create arguments object
            let tte_val2 : Value? = if func_env.has("[[ThrowTypeError]]") {
              Some(func_env.get("[[ThrowTypeError]]"))
            } else {
              None
            }
            func_env.def(
              "arguments",
              make_arguments_object(
                args,
                callee,
                func_strict,
                throw_type_error=tte_val2,
              ),
              VarBinding,
            )
            self.hoist_declarations(data.body, func_env)
            match data.name {
              Some(name) =>
                if not(func_env.bindings.contains(name)) {
                  func_env.def(name, callee, LetBinding)
                }
              None => ()
            }
            match self.exec_stmts(data.body, func_env) {
              Normal(_) => Undefined
              ReturnSignal(v) => v
              BreakSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="break statement outside of loop",
                )
              ContinueSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="continue statement outside of loop",
                )
            }
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
          result
        }
        Some(ArrowFuncExt(data)) => {
          let saved_strict = self.strict
          let result = try {
            self.strict = data.strict
            let func_env = Environment::new(parent=Some(data.closure))
            func_env.is_var_scope = true
            // Arrow functions do NOT rebind this
            let mut effective_param_count = 0
            for i = 0; i < data.params.length(); i = i + 1 {
              let param = data.params[i]
              // Skip rest destructuring params
              if data.rest_param is Some(rn) && param.name == rn {
                continue
              }
              let val : Value = if effective_param_count < args.length() &&
                not(args[effective_param_count] is Undefined) {
                args[effective_param_count]
              } else {
                match param.default_val {
                  Some(default_expr) => self.eval_expr(default_expr, func_env)
                  None =>
                    if effective_param_count < args.length() {
                      args[effective_param_count]
                    } else {
                      Undefined
                    }
                }
              }
              func_env.def(param.name, val, LetBinding)
              // Destructure if pattern param
              match param.pattern {
                Some(pat) => self.bind_pattern(pat, val, func_env, LetBinding)
                None => ()
              }
              effective_param_count = effective_param_count + 1
            }
            // Rest param
            match data.rest_param {
              Some(rest_name) => {
                let rest_elements : Array[Value] = []
                for i = effective_param_count; i < args.length(); i = i + 1 {
                  rest_elements.push(args[i])
                }
                let rest_val = Array({ elements: rest_elements })
                func_env.def(rest_name, rest_val, LetBinding)
                // Apply destructuring pattern if present
                for p in data.params {
                  if p.name == rest_name {
                    match p.pattern {
                      Some(pat) =>
                        self.bind_pattern(pat, rest_val, func_env, LetBinding)
                      None => ()
                    }
                    break
                  }
                }
              }
              None => ()
            }
            self.hoist_declarations(data.body, func_env)
            match self.exec_stmts(data.body, func_env) {
              Normal(_) => Undefined
              ReturnSignal(v) => v
              BreakSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="break statement outside of loop",
                )
              ContinueSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="continue statement outside of loop",
                )
            }
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
          result
        }
        Some(BoundFunc(target, bound_this, bound_args)) => {
          let all_args : Array[Value] = []
          for a in bound_args {
            all_args.push(a)
          }
          for a in args {
            all_args.push(a)
          }
          self.call_value(target, bound_this, all_args, loc)
        }
        Some(FuncCallMethod(target)) => {
          let call_this = if args.length() > 0 { args[0] } else { Undefined }
          let call_args : Array[Value] = []
          for i = 1; i < args.length(); i = i + 1 {
            call_args.push(args[i])
          }
          self.call_value(target, call_this, call_args, loc)
        }
        Some(FuncApplyMethod(target)) => {
          let call_this = if args.length() > 0 { args[0] } else { Undefined }
          let call_args : Array[Value] = []
          if args.length() > 1 {
            let arg_array = args[1]
            match arg_array {
              Undefined | Null => ()
              _ => {
                // apply accepts any array-like object (including `arguments`).
                let arg_len = to_array_like_length(arg_array)
                for i = 0; i < arg_len; i = i + 1 {
                  let element = self.get_computed_property(
                    arg_array,
                    Number(i.to_double()),
                    loc,
                  )
                  call_args.push(element)
                }
              }
            }
          }
          self.call_value(target, call_this, call_args, loc)
        }
        Some(MethodCallable(_, func)) => func(this_val, args)
        Some(NativeCallable(_, func)) => func(args)
        Some(NonConstructableCallable(name, func)) =>
          if name == "eval" {
            // Indirect eval: route through perform_eval for interpreter access
            if args.length() == 0 {
              Undefined
            } else {
              match args[0] {
                String_(code) => self.perform_eval(code, self.global, false)
                other => other
              }
            }
          } else {
            func(args)
          }
        Some(InterpreterCallable(_, func)) => func(self, this_val, args)
        Some(ConstructorOnlyCallable(name, _)) =>
          raise @errors.TypeError(
            message=name + " constructor cannot be invoked without 'new'",
          )
        Some(ClassConstructor(name, _, _, _, _, _)) =>
          raise @errors.TypeError(
            message="Class constructor " +
              name +
              " cannot be invoked without 'new'",
          )
        None => raise @errors.TypeError(message="is not a function")
      }
    _ => raise @errors.TypeError(message="is not a function")
  }
}

///|
fn Interpreter::eval_member(
  self : Interpreter,
  obj_expr : @ast.Expr,
  prop : String,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // Special case: console.log
  match obj_expr {
    Ident("console", _) =>
      if prop == "log" {
        let output = self.output
        make_native_func("log", fn(args) {
          let parts : Array[String] = args.map(fn(a) { a.to_string() })
          output.push(parts.join(" "))
          Undefined
        })
      } else {
        raise @errors.TypeError(message="console.\{prop} is not supported")
      }
    _ => {
      let obj = self.eval_expr(obj_expr, env)
      self.get_property(obj, prop, loc)
    }
  }
}

///|
fn get_bound_func_name(target : Value) -> String {
  match target {
    Object(td) => {
      // First check properties["name"] (set by Object.defineProperty or bind)
      let prop_name = match td.properties.get("name") {
        Some(String_(s)) => s
        _ => ""
      }
      if prop_name != "" {
        return "bound " + prop_name
      }
      match td.callable {
        Some(UserFunc(fd)) => "bound " + fd.name.unwrap_or("")
        Some(UserFuncExt(fd)) => "bound " + fd.name.unwrap_or("")
        Some(NativeCallable(n, _)) => "bound " + n
        Some(NonConstructableCallable(n, _)) => "bound " + n
        Some(BoundFunc(inner, _, _)) => "bound " + get_bound_func_name(inner)
        Some(ArrowFunc(fd)) => "bound " + fd.name.unwrap_or("")
        Some(ArrowFuncExt(fd)) => "bound " + fd.name.unwrap_or("")
        Some(ClassConstructor(n, _, _, _, _, _)) => "bound " + n
        Some(MethodCallable(n, _)) => "bound " + n
        Some(InterpreterCallable(n, _)) => "bound " + n
        Some(_) => "bound "
        None => "bound "
      }
    }
    _ => "bound "
  }
}

///|
fn get_func_length(callable : Callable) -> Int {
  match callable {
    UserFunc(func_data) => func_data.params.length()
    UserFuncExt(func_data) => func_data.params.length()
    ArrowFunc(func_data) => func_data.params.length()
    ArrowFuncExt(func_data) => func_data.params.length()
    BoundFunc(target, _, bound_args) =>
      match target {
        Object(td) =>
          match td.callable {
            Some(inner) => {
              let target_len = get_func_length(inner)
              let diff = target_len - bound_args.length()
              if diff < 0 { 0 } else { diff }
            }
            None => 0
          }
        _ => 0
      }
    NativeCallable(_, _) => 0
    NonConstructableCallable(_, _) => 0
    FuncCallMethod(_) => 1
    FuncApplyMethod(_) => 2
    MethodCallable(_, _) => 0
    InterpreterCallable(_, _) => 0
    ConstructorOnlyCallable(_, _) => 0
    ClassConstructor(_, _, _, ctor, _, _) =>
      match ctor {
        Some((params, _)) => params.length()
        None => 0
      }
  }
}

///|
fn Interpreter::get_property(
  self : Interpreter,
  obj : Value,
  prop : String,
  loc : @token.Loc,
) -> Value raise Error {
  match obj {
    Proxy(proxy_data) => {
      let trap = get_proxy_trap(proxy_data, "get")
      match trap {
        Some(trap_fn) => {
          let target = get_proxy_target(proxy_data)
          let handler = get_proxy_handler(proxy_data)
          self.call_value(trap_fn, handler, [target, String_(prop), obj], loc)
        }
        None => {
          let target = get_proxy_target(proxy_data)
          self.get_property(target, prop, loc)
        }
      }
    }
    Object(data) => {
      // Check for accessor descriptor (getter) on own property
      match data.descriptors.get(prop) {
        Some(desc) =>
          match desc.getter {
            Some(getter) => return self.call_value(getter, obj, [], loc)
            None => ()
          }
        None => ()
      }
      match data.properties.get(prop) {
        Some(v) => v
        None => {
          // Walk prototype chain
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) => {
                // Check for accessor descriptor (getter) on prototype property
                match proto_data.descriptors.get(prop) {
                  Some(desc) =>
                    match desc.getter {
                      Some(getter) =>
                        return self.call_value(getter, obj, [], loc)
                      None => ()
                    }
                  None => ()
                }
                match proto_data.properties.get(prop) {
                  Some(v) => return v
                  None => current = proto_data.prototype
                }
              }
              Array(arr_data) => {
                // Handle Array values in the prototype chain
                if prop == "length" {
                  return Number(arr_data.elements.length().to_double())
                }
                match get_array_named_prop(arr_data, prop) {
                  Some(v) => return v
                  None => {
                    let result = get_array_method_with_interp(arr_data, prop)
                    match result {
                      Undefined => {
                        // Continue to Array.prototype
                        let ctor = self.global.get("Array") catch { _ => break }
                        match ctor {
                          Object(ctor_data) =>
                            match ctor_data.properties.get("prototype") {
                              Some(proto) => current = proto
                              None => break
                            }
                          _ => break
                        }
                      }
                      _ => return result
                    }
                  }
                }
              }
              Map(map_data) => {
                // Handle Map values in the prototype chain
                if prop == "size" {
                  return Number(map_data.entries.length().to_double())
                }
                let result = get_map_method(map_data, prop)
                match result {
                  Undefined => {
                    let ctor = self.global.get("Map") catch { _ => break }
                    match ctor {
                      Object(ctor_data) =>
                        match ctor_data.properties.get("prototype") {
                          Some(proto) => current = proto
                          None => break
                        }
                      _ => break
                    }
                  }
                  _ => return result
                }
              }
              Set(set_data) => {
                // Handle Set values in the prototype chain
                if prop == "size" {
                  return Number(set_data.values.length().to_double())
                }
                let result = get_set_method(set_data, prop)
                match result {
                  Undefined => {
                    let ctor = self.global.get("Set") catch { _ => break }
                    match ctor {
                      Object(ctor_data) =>
                        match ctor_data.properties.get("prototype") {
                          Some(proto) => current = proto
                          None => break
                        }
                      _ => break
                    }
                  }
                  _ => return result
                }
              }
              _ => break
            }
          }
          // Built-in Function methods (for callable objects)
          match data.callable {
            Some(callable) =>
              if prop == "call" {
                return Object({
                  properties: {},
                  symbol_properties: {},
                  prototype: Null,
                  callable: Some(FuncCallMethod(obj)),
                  class_name: "Function",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
              } else if prop == "apply" {
                return Object({
                  properties: {},
                  symbol_properties: {},
                  prototype: Null,
                  callable: Some(FuncApplyMethod(obj)),
                  class_name: "Function",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
              } else if prop == "bind" {
                let target = obj
                let target_length = get_func_length(callable)
                return make_native_func("bind", fn(args) {
                  let bind_this = if args.length() > 0 {
                    args[0]
                  } else {
                    Undefined
                  }
                  let bound_args : Array[Value] = []
                  for i = 1; i < args.length(); i = i + 1 {
                    bound_args.push(args[i])
                  }
                  let bound_name = get_bound_func_name(target)
                  let bound_length = {
                    let diff = target_length - bound_args.length()
                    if diff < 0 { 0 } else { diff }
                  }
                  let nf_desc : PropDescriptor = {
                    writable: false,
                    enumerable: false,
                    configurable: true,
                    getter: None,
                    setter: None,
                  }
                  let bprops : Map[String, Value] = {}
                  bprops["name"] = String_(bound_name)
                  bprops["length"] = Number(bound_length.to_double())
                  Object({
                    properties: bprops,
                    symbol_properties: {},
                    prototype: Null,
                    callable: Some(BoundFunc(target, bind_this, bound_args)),
                    class_name: "Function",
                    descriptors: { "name": nf_desc, "length": nf_desc },
                    symbol_descriptors: {},
                    extensible: true,
                  })
                })
              } else if prop == "length" {
                // Return the number of formal parameters
                let param_count = get_func_length(callable)
                return Number(param_count.to_double())
              } else if prop == "name" {
                // Return the function name
                let func_name : String = match callable {
                  UserFunc(func_data) => func_data.name.unwrap_or("")
                  UserFuncExt(func_data) => func_data.name.unwrap_or("")
                  ArrowFunc(_) => ""
                  ArrowFuncExt(_) => ""
                  BoundFunc(target, _, _) => get_bound_func_name(target)
                  NativeCallable(n, _) => n
                  NonConstructableCallable(n, _) => n
                  FuncCallMethod(_) => "call"
                  FuncApplyMethod(_) => "apply"
                  MethodCallable(n, _) => n
                  InterpreterCallable(n, _) => n
                  ConstructorOnlyCallable(n, _) => n
                  ClassConstructor(n, _, _, _, _, _) => n
                }
                return String_(func_name)
              } else if prop == "toString" {
                // Return function string representation
                let func_str : String = match callable {
                  UserFunc(func_data) => {
                    let name = func_data.name.unwrap_or("")
                    "function " + name + "() { [native code] }"
                  }
                  UserFuncExt(func_data) => {
                    let name = func_data.name.unwrap_or("")
                    "function " + name + "() { [native code] }"
                  }
                  ArrowFunc(_) => "() => { [native code] }"
                  ArrowFuncExt(_) => "() => { [native code] }"
                  BoundFunc(_, _, _) => "function () { [native code] }"
                  NativeCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  NonConstructableCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  FuncCallMethod(_) => "function call() { [native code] }"
                  FuncApplyMethod(_) => "function apply() { [native code] }"
                  MethodCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  InterpreterCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  ConstructorOnlyCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  ClassConstructor(n, _, _, _, _, _) =>
                    "class " + n + " { [native code] }"
                }
                return make_native_func("toString", fn(_args) {
                  String_(func_str)
                })
              } else if prop == "prototype" {
                // Only constructable functions have a prototype property
                // Non-constructable (arrow functions, bound functions, etc.) return undefined
                let is_constructable = match callable {
                  UserFunc(_)
                  | UserFuncExt(_)
                  | NativeCallable(_, _)
                  | ConstructorOnlyCallable(_, _)
                  | ClassConstructor(_, _, _, _, _, _) => true
                  ArrowFunc(_)
                  | ArrowFuncExt(_)
                  | BoundFunc(_, _, _)
                  | NonConstructableCallable(_, _)
                  | FuncCallMethod(_)
                  | FuncApplyMethod(_)
                  | MethodCallable(_, _)
                  | InterpreterCallable(_, _) => false
                }
                if not(is_constructable) {
                  return Undefined
                }
                // For constructable functions, check if prototype exists
                match data.properties.get("prototype") {
                  Some(p) => return p
                  None => {
                    // Create and memoize default prototype
                    let proto : Value = Object({
                      properties: {},
                      symbol_properties: {},
                      prototype: Null,
                      callable: None,
                      class_name: "Object",
                      descriptors: {},
                      symbol_descriptors: {},
                      extensible: true,
                    })
                    data.properties["prototype"] = proto
                    return proto
                  }
                }
              }
            None => ()
          }
          // Built-in Object methods
          if prop == "hasOwnProperty" {
            return make_method_func("hasOwnProperty", 1, fn(this_val, args) {
                  let key_val = if args.length() > 0 {
                    args[0]
                  } else {
                    Undefined
                  }
                  match this_val {
                    Object(d) =>
                      // Handle Symbol keys
                      match key_val {
                        Symbol(sym) =>
                          Bool(d.symbol_properties.contains(sym.id))
                        _ => Bool(d.properties.contains(key_val.to_string()))
                      }
                    _ => Bool(false)
                  }
                })
          }
          if prop == "toString" {
            return make_native_func("toString", fn(_args) {
              String_("[object Object]")
            })
          }
          Undefined
        }
      }
    }
    Array(data) =>
      if prop == "length" {
        Number(data.elements.length().to_double())
      } else {
        // Check named properties side table first (e.g., index, input on exec results)
        match get_array_named_prop(data, prop) {
          Some(v) => v
          None => {
            let result = get_array_method_with_interp(data, prop)
            match result {
              Undefined => lookup_builtin_proto(self, obj, "Array", prop, loc)
              _ => result
            }
          }
        }
      }
    String_(s) =>
      if prop == "length" {
        Number(utf16_length(s).to_double())
      } else {
        let result = get_string_method(s, prop, annex_b=self.annex_b)
        match result {
          Undefined => lookup_builtin_proto(self, obj, "String", prop, loc)
          _ => result
        }
      }
    Number(_) => {
      let result = get_number_method(obj, prop)
      match result {
        Undefined => lookup_builtin_proto(self, obj, "Number", prop, loc)
        _ => result
      }
    }
    Bool(_) => lookup_builtin_proto(self, obj, "Boolean", prop, loc)
    Symbol(sym) =>
      // Symbol properties: description, toString
      if prop == "description" {
        match sym.description {
          Some(desc) => String_(desc)
          None => Undefined
        }
      } else if prop == "toString" {
        make_native_func("toString", fn(_args) {
          match sym.description {
            Some(desc) => String_("Symbol(\{desc})")
            None => String_("Symbol()")
          }
        })
      } else {
        lookup_builtin_proto(self, obj, "Symbol", prop, loc)
      }
    Map(data) =>
      if prop == "size" {
        Number(data.entries.length().to_double())
      } else {
        get_map_method(data, prop)
      }
    Set(data) =>
      if prop == "size" {
        Number(data.values.length().to_double())
      } else {
        get_set_method(data, prop)
      }
    Promise(data) =>
      // Check user-defined properties first, then prototype methods
      match data.descriptors.get(prop) {
        Some(desc) =>
          match desc.getter {
            Some(getter) => self.call_value(getter, obj, [], loc)
            None =>
              match data.properties.get(prop) {
                Some(v) => v
                None => get_promise_method(data, prop)
              }
          }
        None =>
          match data.properties.get(prop) {
            Some(v) => v
            None => get_promise_method(data, prop)
          }
      }
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot read property '\{prop}' of \{type_of(obj)}",
      )
  }
}

///|
/// Look up a property on a built-in constructor's prototype (e.g. Array.prototype.constructor)
fn lookup_builtin_proto(
  interp : Interpreter,
  receiver : Value,
  ctor_name : String,
  prop : String,
  loc : @token.Loc,
) -> Value raise Error {
  let ctor = interp.global.get(ctor_name) catch { _ => return Undefined }
  match ctor {
    Object(ctor_data) =>
      match ctor_data.properties.get("prototype") {
        Some(Object(proto_data)) => {
          // Walk up prototype chain and honor accessor getters with `receiver`.
          let mut current : Value = Object(proto_data)
          while true {
            match current {
              Object(pdata) => {
                match pdata.descriptors.get(prop) {
                  Some(desc) =>
                    match desc.getter {
                      Some(getter) =>
                        return interp.call_value(getter, receiver, [], loc)
                      None =>
                        match pdata.properties.get(prop) {
                          Some(v) => return v
                          None => ()
                        }
                    }
                  None =>
                    match pdata.properties.get(prop) {
                      Some(v) => return v
                      None => ()
                    }
                }
                current = pdata.prototype
              }
              _ => break
            }
          }
          Undefined
        }
        _ => Undefined
      }
    _ => Undefined
  }
}

///|
fn Interpreter::get_computed_property(
  self : Interpreter,
  obj : Value,
  key : Value,
  loc : @token.Loc,
) -> Value raise Error {
  // Handle Proxy objects first
  match obj {
    Proxy(proxy_data) => {
      let trap = get_proxy_trap(proxy_data, "get")
      match trap {
        Some(trap_fn) => {
          let target = get_proxy_target(proxy_data)
          let handler = get_proxy_handler(proxy_data)
          let prop_key = match key {
            Symbol(_) => key
            _ => String_(to_js_string(key))
          }
          return self.call_value(trap_fn, handler, [target, prop_key, obj], loc)
        }
        None => {
          let target = get_proxy_target(proxy_data)
          return self.get_computed_property(target, key, loc)
        }
      }
    }
    _ => ()
  }
  // Handle Symbol keys specially
  match key {
    Symbol(sym) =>
      match obj {
        Object(data) => {
          // Check for symbol accessor descriptor (getter)
          match data.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              match desc.getter {
                Some(getter) => return self.call_value(getter, obj, [], loc)
                None => ()
              }
            None => ()
          }
          // Look up symbol property
          match data.symbol_properties.get(sym.id) {
            Some(v) => return v
            None => {
              // Walk prototype chain for symbol properties
              let mut current = data.prototype
              while true {
                match current {
                  Object(proto_data) => {
                    // Check for accessor on prototype
                    match proto_data.symbol_descriptors.get(sym.id) {
                      Some(desc) =>
                        match desc.getter {
                          Some(getter) =>
                            return self.call_value(getter, obj, [], loc)
                          None => ()
                        }
                      None => ()
                    }
                    match proto_data.symbol_properties.get(sym.id) {
                      Some(v) => return v
                      None => current = proto_data.prototype
                    }
                  }
                  _ => break
                }
              }
              // Boxed primitive objects: delegate Symbol.iterator to primitive
              let iterator_sym = get_iterator_symbol()
              if sym.id == iterator_sym.id {
                if data.class_name == "String" {
                  match data.properties.get("[[StringData]]") {
                    Some(String_(_)) =>
                      return make_method_func("[Symbol.iterator]", 0, fn(
                            this_val,
                            _args,
                          ) raise {
                            let str = match this_val {
                              String_(sv) => sv
                              Object(d) =>
                                if d.class_name == "String" {
                                  match d.properties.get("[[StringData]]") {
                                    Some(String_(sv)) => sv
                                    _ => this_val.to_string()
                                  }
                                } else {
                                  this_val.to_string()
                                }
                              Null | Undefined =>
                                raise @errors.TypeError(
                                  message="Cannot convert undefined or null to object",
                                )
                              _ => this_val.to_string()
                            }
                            make_string_iterator_value(str)
                          })
                    _ => ()
                  }
                } else if data.class_name == "Array" {
                  // Shouldn't reach here for arrays normally, but fallback
                  ()
                }
              }
              return Undefined
            }
          }
        }
        String_(s) => {
          // Handle Symbol.iterator for strings
          let iterator_sym = get_iterator_symbol()
          if sym.id == iterator_sym.id {
            // Return a function that creates a string iterator
            return make_method_func("[Symbol.iterator]", 0, fn(_this_val, _args) {
                  make_string_iterator_value(s)
                })
          }
          return Undefined
        }
        Array(arr) => {
          // Handle Symbol.iterator for arrays
          let iterator_sym = get_iterator_symbol()
          if sym.id == iterator_sym.id {
            let (override_getter, override_value) = get_array_iterator_override(
              arr,
            )
            match override_getter {
              Some(getter) => return self.call_value(getter, obj, [], loc)
              None => ()
            }
            match override_value {
              Some(v) => return v
              None => ()
            }
            // Return a function that creates an array iterator
            return make_method_func("[Symbol.iterator]", 0, fn(_this_val, _args) {
                  make_array_iterator_value(arr)
                })
          }
          return Undefined
        }
        Map(_) => {
          // Handle Symbol.iterator for Maps (delegates to entries)
          let iterator_sym = get_iterator_symbol()
          if sym.id == iterator_sym.id {
            return get_map_method(
              match obj {
                Map(data) => data
                _ => abort("unreachable")
              },
              "entries",
            )
          }
          let tostringtag_sym = get_tostringtag_symbol()
          if sym.id == tostringtag_sym.id {
            return String_("Map")
          }
          return Undefined
        }
        Set(_) => {
          // Handle Symbol.iterator for Sets (delegates to values)
          let iterator_sym = get_iterator_symbol()
          if sym.id == iterator_sym.id {
            return get_set_method(
              match obj {
                Set(data) => data
                _ => abort("unreachable")
              },
              "values",
            )
          }
          let tostringtag_sym = get_tostringtag_symbol()
          if sym.id == tostringtag_sym.id {
            return String_("Set")
          }
          return Undefined
        }
        Promise(data) =>
          match data.symbol_properties.get(sym.id) {
            Some(v) => return v
            None => return Undefined
          }
        Symbol(_) => {
          // Delegate to Symbol.prototype for symbol-keyed property access
          let proto = self.global.get("[[SymbolPrototype]]") catch { _ => Null }
          match proto {
            Object(proto_data) => {
              match proto_data.symbol_descriptors.get(sym.id) {
                Some(desc) =>
                  match desc.getter {
                    Some(getter) => return self.call_value(getter, obj, [], loc)
                    None => ()
                  }
                None => ()
              }
              match proto_data.symbol_properties.get(sym.id) {
                Some(v) => return v
                None => return Undefined
              }
            }
            _ => return Undefined
          }
        }
        _ => return Undefined
      }
    _ => ()
  }
  match obj {
    Object(data) => {
      // TypedArray indexed access: intercept numeric keys before regular property lookup
      if is_typedarray_class(data.class_name) {
        match key {
          Number(n) => {
            let idx = n.to_int()
            if idx.to_double() == n && idx >= 0 {
              return typedarray_get_index(data, idx)
            }
            // Non-integer or negative Number key: return undefined per spec
            return Undefined
          }
          String_(s) =>
            // Canonical numeric index string check per spec
            // Note: "-0" is NOT canonical (ToString(ToNumber("-0")) === "0"), so it falls through
            try {
              let n = @strconv.parse_double(s)
              // If string converts to a number and back to same string, it's a canonical numeric index
              if n.to_string() == s {
                let idx = n.to_int()
                if idx.to_double() == n && idx >= 0 {
                  return typedarray_get_index(data, idx)
                }
                // Canonical numeric index but not a valid integer index
                return Undefined
              }
            } catch {
              _ => () // Not a numeric string, fall through to normal property lookup
            }
          _ => ()
        }
      }
      let prop = to_js_string(key)
      // Check for accessor descriptor (getter) on own property
      match data.descriptors.get(prop) {
        Some(desc) =>
          match desc.getter {
            Some(getter) => return self.call_value(getter, obj, [], loc)
            None => ()
          }
        None => ()
      }
      match data.properties.get(prop) {
        Some(v) => v
        None => {
          // Walk prototype chain
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) => {
                // Check for accessor descriptor on prototype
                match proto_data.descriptors.get(prop) {
                  Some(desc) =>
                    match desc.getter {
                      Some(getter) =>
                        return self.call_value(getter, obj, [], loc)
                      None => ()
                    }
                  None => ()
                }
                match proto_data.properties.get(prop) {
                  Some(v) => return v
                  None => current = proto_data.prototype
                }
              }
              Array(arr_data) => {
                if prop == "length" {
                  return Number(arr_data.elements.length().to_double())
                }
                match get_array_named_prop(arr_data, prop) {
                  Some(v) => return v
                  None => {
                    let result = get_array_method_with_interp(arr_data, prop)
                    match result {
                      Undefined => {
                        let ctor = self.global.get("Array") catch { _ => break }
                        match ctor {
                          Object(ctor_data) =>
                            match ctor_data.properties.get("prototype") {
                              Some(proto) => current = proto
                              None => break
                            }
                          _ => break
                        }
                      }
                      _ => return result
                    }
                  }
                }
              }
              Map(map_data) => {
                if prop == "size" {
                  return Number(map_data.entries.length().to_double())
                }
                let result = get_map_method(map_data, prop)
                match result {
                  Undefined => {
                    let ctor = self.global.get("Map") catch { _ => break }
                    match ctor {
                      Object(ctor_data) =>
                        match ctor_data.properties.get("prototype") {
                          Some(proto) => current = proto
                          None => break
                        }
                      _ => break
                    }
                  }
                  _ => return result
                }
              }
              Set(set_data) => {
                if prop == "size" {
                  return Number(set_data.values.length().to_double())
                }
                let result = get_set_method(set_data, prop)
                match result {
                  Undefined => {
                    let ctor = self.global.get("Set") catch { _ => break }
                    match ctor {
                      Object(ctor_data) =>
                        match ctor_data.properties.get("prototype") {
                          Some(proto) => current = proto
                          None => break
                        }
                      _ => break
                    }
                  }
                  _ => return result
                }
              }
              _ => break
            }
          }
          // Built-in Function methods (for callable objects)
          match data.callable {
            Some(callable) =>
              if prop == "call" {
                return Object({
                  properties: {},
                  symbol_properties: {},
                  prototype: Null,
                  callable: Some(FuncCallMethod(obj)),
                  class_name: "Function",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
              } else if prop == "apply" {
                return Object({
                  properties: {},
                  symbol_properties: {},
                  prototype: Null,
                  callable: Some(FuncApplyMethod(obj)),
                  class_name: "Function",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
              } else if prop == "bind" {
                let target = obj
                let target_length = get_func_length(callable)
                return make_native_func("bind", fn(args) {
                  let bind_this = if args.length() > 0 {
                    args[0]
                  } else {
                    Undefined
                  }
                  let bound_args : Array[Value] = []
                  for i = 1; i < args.length(); i = i + 1 {
                    bound_args.push(args[i])
                  }
                  let bound_name = get_bound_func_name(target)
                  let bound_length = {
                    let diff = target_length - bound_args.length()
                    if diff < 0 { 0 } else { diff }
                  }
                  let nf_desc : PropDescriptor = {
                    writable: false,
                    enumerable: false,
                    configurable: true,
                    getter: None,
                    setter: None,
                  }
                  let bprops : Map[String, Value] = {}
                  bprops["name"] = String_(bound_name)
                  bprops["length"] = Number(bound_length.to_double())
                  Object({
                    properties: bprops,
                    symbol_properties: {},
                    prototype: Null,
                    callable: Some(BoundFunc(target, bind_this, bound_args)),
                    class_name: "Function",
                    descriptors: { "name": nf_desc, "length": nf_desc },
                    symbol_descriptors: {},
                    extensible: true,
                  })
                })
              } else if prop == "length" {
                // Return the number of formal parameters
                let param_count = get_func_length(callable)
                return Number(param_count.to_double())
              } else if prop == "name" {
                // Return the function name
                let func_name : String = match callable {
                  UserFunc(func_data) => func_data.name.unwrap_or("")
                  UserFuncExt(func_data) => func_data.name.unwrap_or("")
                  ArrowFunc(_) => ""
                  ArrowFuncExt(_) => ""
                  BoundFunc(target, _, _) => get_bound_func_name(target)
                  NativeCallable(n, _) => n
                  NonConstructableCallable(n, _) => n
                  FuncCallMethod(_) => "call"
                  FuncApplyMethod(_) => "apply"
                  MethodCallable(n, _) => n
                  InterpreterCallable(n, _) => n
                  ConstructorOnlyCallable(n, _) => n
                  ClassConstructor(n, _, _, _, _, _) => n
                }
                return String_(func_name)
              } else if prop == "toString" {
                // Return function string representation
                let func_str : String = match callable {
                  UserFunc(func_data) => {
                    let name = func_data.name.unwrap_or("")
                    "function " + name + "() { [native code] }"
                  }
                  UserFuncExt(func_data) => {
                    let name = func_data.name.unwrap_or("")
                    "function " + name + "() { [native code] }"
                  }
                  ArrowFunc(_) => "() => { [native code] }"
                  ArrowFuncExt(_) => "() => { [native code] }"
                  BoundFunc(_, _, _) => "function () { [native code] }"
                  NativeCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  NonConstructableCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  FuncCallMethod(_) => "function call() { [native code] }"
                  FuncApplyMethod(_) => "function apply() { [native code] }"
                  MethodCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  InterpreterCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  ConstructorOnlyCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  ClassConstructor(n, _, _, _, _, _) =>
                    "class " + n + " { [native code] }"
                }
                return make_native_func("toString", fn(_args) {
                  String_(func_str)
                })
              } else if prop == "prototype" {
                // Only constructable functions have a prototype property
                // Non-constructable (arrow functions, bound functions, etc.) return undefined
                let is_constructable = match callable {
                  UserFunc(_)
                  | UserFuncExt(_)
                  | NativeCallable(_, _)
                  | ConstructorOnlyCallable(_, _)
                  | ClassConstructor(_, _, _, _, _, _) => true
                  ArrowFunc(_)
                  | ArrowFuncExt(_)
                  | BoundFunc(_, _, _)
                  | NonConstructableCallable(_, _)
                  | FuncCallMethod(_)
                  | FuncApplyMethod(_)
                  | MethodCallable(_, _)
                  | InterpreterCallable(_, _) => false
                }
                if not(is_constructable) {
                  return Undefined
                }
                // For constructable functions, check if prototype exists
                match data.properties.get("prototype") {
                  Some(p) => return p
                  None => {
                    // Create and memoize default prototype
                    let proto : Value = Object({
                      properties: {},
                      symbol_properties: {},
                      prototype: Null,
                      callable: None,
                      class_name: "Object",
                      descriptors: {},
                      symbol_descriptors: {},
                      extensible: true,
                    })
                    data.properties["prototype"] = proto
                    return proto
                  }
                }
              }
            None => ()
          }
          // Built-in Object methods
          if prop == "hasOwnProperty" {
            return make_method_func("hasOwnProperty", 1, fn(this_val, args) {
                  let key_val = if args.length() > 0 {
                    args[0]
                  } else {
                    Undefined
                  }
                  match this_val {
                    Object(d) =>
                      // Handle Symbol keys
                      match key_val {
                        Symbol(sym) =>
                          Bool(d.symbol_properties.contains(sym.id))
                        _ => Bool(d.properties.contains(key_val.to_string()))
                      }
                    _ => Bool(false)
                  }
                })
          }
          if prop == "toString" {
            return make_native_func("toString", fn(_args) {
              String_("[object Object]")
            })
          }
          Undefined
        }
      }
    }
    Array(data) =>
      match key {
        Number(n) => {
          let i = n.to_int()
          if i >= 0 && i < data.elements.length() {
            data.elements[i]
          } else {
            Undefined
          }
        }
        String_("length") => Number(data.elements.length().to_double())
        String_(s) => {
          // Canonical numeric index string check: parseDouble(s).toString() === s
          let mut numeric_result : Value? = None
          try {
            let n = @strconv.parse_double(s)
            if n.to_string() == s {
              let idx = n.to_int()
              if idx.to_double() == n &&
                idx >= 0 &&
                idx < data.elements.length() {
                numeric_result = Some(data.elements[idx])
              }
            }
          } catch {
            _ => () // Not a numeric string
          }
          match numeric_result {
            Some(v) => v
            None =>
              // Check side table for named properties, then methods
              match get_array_named_prop(data, s) {
                Some(v) => v
                None => get_array_method_with_interp(data, s)
              }
          }
        }
        _ => Undefined
      }
    String_(s) =>
      match key {
        Number(n) => {
          let i = n.to_int()
          if i >= 0 && i < s.length() {
            let buf = StringBuilder::new()
            buf.write_char(s.to_array()[i])
            String_(buf.to_string())
          } else {
            Undefined
          }
        }
        String_("length") => Number(utf16_length(s).to_double())
        String_(method_name) =>
          get_string_method(s, method_name, annex_b=self.annex_b)
        _ => Undefined
      }
    Number(_) =>
      match key {
        String_(method_name) => get_number_method(obj, method_name)
        _ => Undefined
      }
    Promise(data) => {
      // Coerce key to string via ToPropertyKey (Symbol handled above)
      let prop = to_js_string(key)
      match data.properties.get(prop) {
        Some(v) => v
        None => get_promise_method(data, prop)
      }
    }
    Null | Undefined =>
      raise @errors.TypeError(message="Cannot read property of \{type_of(obj)}")
    _ => Undefined
  }
}

///|
fn Interpreter::set_property(
  self : Interpreter,
  obj : Value,
  prop : String,
  value : Value,
  loc : @token.Loc,
) -> Value raise Error {
  match obj {
    Proxy(proxy_data) => {
      let trap = get_proxy_trap(proxy_data, "set")
      match trap {
        Some(trap_fn) => {
          let target = get_proxy_target(proxy_data)
          let handler = get_proxy_handler(proxy_data)
          let result = self.call_value(
            trap_fn,
            handler,
            [target, String_(prop), value, obj],
            loc,
          )
          if not(is_truthy(result)) {
            if self.strict {
              raise @errors.TypeError(
                message="'set' on proxy: trap returned falsish for property '\{prop}'",
              )
            }
          }
          value
        }
        None => {
          let target = get_proxy_target(proxy_data)
          self.set_property(target, prop, value, loc)
        }
      }
    }
    Object(data) => {
      // TypedArray indexed write via dot notation (numeric string prop)
      if is_typedarray_class(data.class_name) {
        // Canonical numeric index string check per spec
        // Note: "-0" is NOT canonical (ToString(ToNumber("-0")) === "0"), so it falls through
        try {
          let n = @strconv.parse_double(prop)
          if n.to_string() == prop {
            let idx = n.to_int()
            if idx.to_double() == n && idx >= 0 {
              let num = to_number(value)
              typedarray_set_index(data, idx, num)
            }
            // Canonical numeric index: don't fall through to regular property set
            return value
          }
        } catch {
          _ => () // Not a numeric string, fall through to normal property set
        }
      }
      // Check for accessor descriptor (setter)
      match data.descriptors.get(prop) {
        Some(desc) =>
          match desc.setter {
            Some(setter) => {
              let _ = self.call_value(setter, obj, [value], loc)
              return value
            }
            None =>
              if desc.getter is Some(_) {
                if self.strict {
                  raise @errors.TypeError(
                    message="Cannot set property \{prop} which has only a getter",
                  )
                }
                return value
              } else if not(desc.writable) {
                if self.strict {
                  raise @errors.TypeError(
                    message="Cannot assign to read only property '\{prop}'",
                  )
                }
                return value
              }
          }
        None => {
          // Walk prototype chain for inherited setters
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) => {
                match proto_data.descriptors.get(prop) {
                  Some(desc) =>
                    match desc.setter {
                      Some(setter) => {
                        let _ = self.call_value(setter, obj, [value], loc)
                        return value
                      }
                      None =>
                        if desc.getter is Some(_) {
                          if self.strict {
                            raise @errors.TypeError(
                              message="Cannot set property \{prop} which has only a getter",
                            )
                          }
                          return value
                        } else if not(desc.writable) {
                          // Inherited non-writable data property blocks assignment
                          if self.strict {
                            raise @errors.TypeError(
                              message="Cannot assign to read only property '\{prop}'",
                            )
                          }
                          return value
                        }
                    }
                  None => ()
                }
                current = proto_data.prototype
              }
              _ => break
            }
          }
        }
      }
      // Check extensible for new properties
      if not(data.properties.contains(prop)) && not(data.extensible) {
        if self.strict {
          raise @errors.TypeError(
            message="Cannot add property \{prop}, object is not extensible",
          )
        }
        return value
      }
      data.properties[prop] = value
      value
    }
    Array(data) => {
      if prop == "length" {
        let n = to_number(value).to_int()
        while data.elements.length() > n {
          let _ = data.elements.pop()
        }
      } else {
        // try numeric index
        let mut handled = false
        try {
          let i = @strconv.parse_int(prop)
          if i >= 0 {
            while data.elements.length() <= i {
              data.elements.push(Undefined)
            }
            data.elements[i] = value
            handled = true
          }
        } catch {
          _ => ()
        }
        if not(handled) {
          // Store named properties in side table
          set_array_named_prop(data, prop, value)
        }
      }
      value
    }
    Promise(data) => {
      match data.descriptors.get(prop) {
        Some(desc) =>
          match desc.setter {
            Some(setter) => {
              let _ = self.call_value(setter, obj, [value], loc)
              return value
            }
            None =>
              if desc.getter is Some(_) {
                if self.strict {
                  raise @errors.TypeError(
                    message="Cannot set property \{prop} which has only a getter",
                  )
                }
                return value
              } else if not(desc.writable) {
                if self.strict {
                  raise @errors.TypeError(
                    message="Cannot assign to read only property '\{prop}'",
                  )
                }
                return value
              }
          }
        None => ()
      }
      data.properties[prop] = value
      value
    }
    _ =>
      // In non-strict mode, setting a property on a primitive is silently ignored
      // (the temporary wrapper object is discarded). In strict mode, throw TypeError.
      if self.strict {
        raise @errors.TypeError(
          message="Cannot set property '\{prop}' of \{type_of(obj)}",
        )
      } else {
        value
      }
  }
}

///|
fn Interpreter::set_computed_property(
  self : Interpreter,
  obj : Value,
  key : Value,
  value : Value,
  loc : @token.Loc,
) -> Value raise Error {
  match obj {
    Proxy(proxy_data) => {
      let trap = get_proxy_trap(proxy_data, "set")
      match trap {
        Some(trap_fn) => {
          let target = get_proxy_target(proxy_data)
          let handler = get_proxy_handler(proxy_data)
          let prop_key = match key {
            Symbol(_) => key
            _ => String_(to_js_string(key))
          }
          let result = self.call_value(
            trap_fn,
            handler,
            [target, prop_key, value, obj],
            loc,
          )
          if not(is_truthy(result)) {
            if self.strict {
              raise @errors.TypeError(
                message="'set' on proxy: trap returned falsish",
              )
            }
          }
          return value
        }
        None => {
          let target = get_proxy_target(proxy_data)
          return self.set_computed_property(target, key, value, loc)
        }
      }
    }
    Object(data) =>
      match key {
        Symbol(sym) => {
          // Check symbol property accessor descriptor (setter)
          match data.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              match desc.setter {
                Some(setter) => {
                  let _ = self.call_value(setter, obj, [value], loc)
                  return value
                }
                None =>
                  if desc.getter is Some(_) {
                    if self.strict {
                      raise @errors.TypeError(
                        message="Cannot set property which has only a getter",
                      )
                    }
                    return value
                  } else if not(desc.writable) {
                    if self.strict {
                      raise @errors.TypeError(
                        message="Cannot assign to read only property",
                      )
                    }
                    return value
                  }
              }
            None => {
              // Walk prototype chain for inherited symbol setters
              let mut current = data.prototype
              while true {
                match current {
                  Object(proto_data) => {
                    match proto_data.symbol_descriptors.get(sym.id) {
                      Some(desc) =>
                        match desc.setter {
                          Some(setter) => {
                            let _ = self.call_value(setter, obj, [value], loc)
                            return value
                          }
                          None =>
                            if desc.getter is Some(_) {
                              if self.strict {
                                raise @errors.TypeError(
                                  message="Cannot set property which has only a getter",
                                )
                              }
                              return value
                            } else if not(desc.writable) {
                              if self.strict {
                                raise @errors.TypeError(
                                  message="Cannot assign to read only property",
                                )
                              }
                              return value
                            }
                        }
                      None => ()
                    }
                    current = proto_data.prototype
                  }
                  _ => break
                }
              }
            }
          }
          if not(data.symbol_properties.contains(sym.id)) &&
            not(data.extensible) {
            if self.strict {
              raise @errors.TypeError(
                message="Cannot add property, object is not extensible",
              )
            }
            return value
          }
          data.symbol_properties[sym.id] = value
          value
        }
        _ => {
          // TypedArray indexed write: intercept numeric keys
          if is_typedarray_class(data.class_name) {
            match key {
              Number(n) => {
                let idx = n.to_int()
                if idx.to_double() == n && idx >= 0 {
                  let num = to_number(value)
                  typedarray_set_index(data, idx, num)
                }
                // Numeric key always intercepted for TypedArrays
                return value
              }
              String_(s) =>
                // Canonical numeric index string check per spec
                // Note: "-0" is NOT canonical (ToString(ToNumber("-0")) === "0"), so it falls through
                try {
                  let n = @strconv.parse_double(s)
                  if n.to_string() == s {
                    let idx = n.to_int()
                    if idx.to_double() == n && idx >= 0 {
                      let num = to_number(value)
                      typedarray_set_index(data, idx, num)
                    }
                    return value
                  }
                } catch {
                  _ => () // Not numeric, fall through
                }
              _ => ()
            }
          }
          let prop = to_js_string(key)
          // Check for accessor descriptor (setter) on string key
          match data.descriptors.get(prop) {
            Some(desc) =>
              match desc.setter {
                Some(setter) => {
                  let _ = self.call_value(setter, obj, [value], loc)
                  return value
                }
                None =>
                  if desc.getter is Some(_) {
                    if self.strict {
                      raise @errors.TypeError(
                        message="Cannot set property \{prop} which has only a getter",
                      )
                    }
                    return value
                  } else if not(desc.writable) {
                    if self.strict {
                      raise @errors.TypeError(
                        message="Cannot assign to read only property '\{prop}'",
                      )
                    }
                    return value
                  }
              }
            None => {
              // Walk prototype chain for inherited setters
              let mut current = data.prototype
              while true {
                match current {
                  Object(proto_data) => {
                    match proto_data.descriptors.get(prop) {
                      Some(desc) =>
                        match desc.setter {
                          Some(setter) => {
                            let _ = self.call_value(setter, obj, [value], loc)
                            return value
                          }
                          None =>
                            if desc.getter is Some(_) {
                              if self.strict {
                                raise @errors.TypeError(
                                  message="Cannot set property \{prop} which has only a getter",
                                )
                              }
                              return value
                            } else if not(desc.writable) {
                              if self.strict {
                                raise @errors.TypeError(
                                  message="Cannot assign to read only property '\{prop}'",
                                )
                              }
                              return value
                            }
                        }
                      None => ()
                    }
                    current = proto_data.prototype
                  }
                  _ => break
                }
              }
            }
          }
          if not(data.properties.contains(prop)) && not(data.extensible) {
            if self.strict {
              raise @errors.TypeError(
                message="Cannot add property \{prop}, object is not extensible",
              )
            }
            return value
          }
          data.properties[prop] = value
          value
        }
      }
    Array(data) =>
      match key {
        Number(n) => {
          let i = n.to_int()
          if i >= 0 {
            while data.elements.length() <= i {
              data.elements.push(Undefined)
            }
            data.elements[i] = value
          }
          value
        }
        _ => {
          let prop = to_js_string(key)
          if prop == "length" {
            let n = to_number(value).to_int()
            while data.elements.length() > n {
              let _ = data.elements.pop()
            }
          } else {
            // Canonical numeric index string check: parseDouble(s).toString() === s
            let mut handled = false
            try {
              let n = @strconv.parse_double(prop)
              if n.to_string() == prop {
                let idx = n.to_int()
                if idx.to_double() == n && idx >= 0 {
                  while data.elements.length() <= idx {
                    data.elements.push(Undefined)
                  }
                  data.elements[idx] = value
                  handled = true
                }
              }
            } catch {
              _ => ()
            }
            if not(handled) {
              // Store named properties in side table
              set_array_named_prop(data, prop, value)
            }
          }
          value
        }
      }
    Promise(data) =>
      match key {
        Symbol(sym) => {
          data.symbol_properties[sym.id] = value
          value
        }
        _ => {
          data.properties[to_js_string(key)] = value
          value
        }
      }
    _ =>
      if self.strict {
        raise @errors.TypeError(message="Cannot set property of \{type_of(obj)}")
      } else {
        value
      }
  }
}

///|
fn Interpreter::eval_new(
  self : Interpreter,
  callee_expr : @ast.Expr,
  arg_exprs : Array[@ast.Expr],
  env : Environment,
  _loc : @token.Loc,
) -> Value raise Error {
  let ctor = self.eval_expr(callee_expr, env)
  let args : Array[Value] = self.eval_args_with_spread(arg_exprs, env)
  self.construct_value(ctor, args, _loc)
}

///|
fn is_object_like_for_constructor_return(value : Value) -> Bool {
  match value {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => true
    _ => false
  }
}

///|
fn make_constructor_instance(proto : Value, class_name : String) -> Value {
  Object({
    properties: {},
    symbol_properties: {},
    prototype: proto,
    callable: None,
    class_name,
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
fn make_arguments_object(
  args : Array[Value],
  ctor : Value,
  strict : Bool,
  throw_type_error? : Value? = None,
) -> Value {
  let new_args_props : Map[String, Value] = {}
  for i = 0; i < args.length(); i = i + 1 {
    new_args_props[i.to_string()] = args[i]
  }
  new_args_props["length"] = Number(args.length().to_double())
  let new_args_descs : Map[String, PropDescriptor] = {}
  new_args_descs["length"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  if not(strict) {
    new_args_props["callee"] = ctor
    new_args_descs["callee"] = {
      writable: true,
      enumerable: false,
      configurable: true,
      getter: None,
      setter: None,
    }
  } else {
    // Strict mode: install %ThrowTypeError% accessors for callee and caller
    match throw_type_error {
      Some(tte) => {
        new_args_descs["callee"] = {
          writable: false,
          enumerable: false,
          configurable: false,
          getter: Some(tte),
          setter: Some(tte),
        }
        new_args_descs["caller"] = {
          writable: false,
          enumerable: false,
          configurable: false,
          getter: Some(tte),
          setter: Some(tte),
        }
      }
      None => ()
    }
  }
  // Add Symbol.iterator - creates an iterator over the arguments
  let iter_sym = get_iterator_symbol()
  let args_copy = args
  let new_args_sym_props : Map[Int, Value] = {}
  new_args_sym_props[iter_sym.id] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("values", fn(_this_val, _args2) {
        let index_ref : Ref[Int] = { val: 0 }
        let len = args_copy.length()
        let next_fn = Object({
          properties: {},
          symbol_properties: {},
          prototype: Null,
          callable: Some(
            NativeCallable("next", fn(_a) {
              let idx = index_ref.val
              if idx < len {
                let value = args_copy[idx]
                index_ref.val = idx + 1
                Object({
                  properties: { "value": value, "done": Bool(false) },
                  symbol_properties: {},
                  prototype: Null,
                  callable: None,
                  class_name: "Object",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
              } else {
                Object({
                  properties: { "value": Undefined, "done": Bool(true) },
                  symbol_properties: {},
                  prototype: Null,
                  callable: None,
                  class_name: "Object",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
              }
            }),
          ),
          class_name: "Function",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
        Object({
          properties: { "next": next_fn },
          symbol_properties: {},
          prototype: Null,
          callable: None,
          class_name: "Array Iterator",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  Object({
    properties: new_args_props,
    symbol_properties: new_args_sym_props,
    prototype: Null,
    callable: None,
    class_name: "Arguments",
    descriptors: new_args_descs,
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
fn format_loc_context(message : String, loc : @token.Loc) -> String {
  message + " at line \{loc.line}, col \{loc.col}"
}

///|
fn maybe_set_promise_constructor(value : Value, ctor : Value) -> Value {
  match value {
    Promise(data) => {
      data.properties["constructor"] = ctor
      data.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      value
    }
    _ => value
  }
}

///|
fn Interpreter::construct_value(
  self : Interpreter,
  ctor : Value,
  args : Array[Value],
  loc : @token.Loc,
  proto_override? : Value? = None,
) -> Value raise Error {
  match ctor {
    Proxy(proxy_data) => {
      // Verify target is constructible before checking trap
      let target = get_proxy_target(proxy_data)
      fn is_constructible(v : Value) -> Bool {
        match v {
          Object(t_data) => t_data.callable is Some(_)
          Proxy(pd) =>
            match pd.target {
              Some(inner) => is_constructible(inner)
              None => false
            }
          _ => false
        }
      }
      if not(is_constructible(target)) {
        raise @errors.TypeError(message="target is not a constructor")
      }
      let trap = get_proxy_trap(proxy_data, "construct")
      match trap {
        Some(trap_fn) => {
          let handler = get_proxy_handler(proxy_data)
          let args_array : Value = Array({ elements: args.copy() })
          let result = self.call_value(
            trap_fn,
            handler,
            [target, args_array, ctor],
            loc,
          )
          match result {
            Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
              result
            _ =>
              raise @errors.TypeError(
                message="'construct' on proxy: trap returned non-Object",
              )
          }
        }
        None => self.construct_value(target, args, loc)
      }
    }
    Object(obj_data) =>
      match obj_data.callable {
        Some(UserFunc(data)) => {
          let saved_strict = self.strict
          let result = try {
            let func_strict = data.strict
            self.strict = func_strict
            if func_strict {
              // Strict mode: check for duplicate parameters and reserved names
              check_duplicate_params(data.params)
              for p in data.params {
                validate_strict_binding_name(p)
              }
            }
            let proto = match proto_override {
              Some(p) => p
              None =>
                match obj_data.properties.get("prototype") {
                  Some(v) => v
                  None => Null
                }
            }
            let new_obj = make_constructor_instance(proto, "Object")
            let func_env = Environment::new(parent=Some(data.closure))
            func_env.is_var_scope = true
            func_env.def("this", new_obj, LetBinding)
            func_env.def("<new.target>", ctor, LetBinding)
            for i = 0; i < data.params.length(); i = i + 1 {
              let val : Value = if i < args.length() {
                args[i]
              } else {
                Undefined
              }
              // In sloppy mode, duplicate params are allowed; last value wins
              if func_env.bindings.contains(data.params[i]) {
                func_env.assign(data.params[i], val)
              } else {
                func_env.def(data.params[i], val, LetBinding)
              }
            }
            let tte : Value? = if func_env.has("[[ThrowTypeError]]") {
              Some(func_env.get("[[ThrowTypeError]]"))
            } else {
              None
            }
            func_env.def(
              "arguments",
              make_arguments_object(
                args,
                ctor,
                func_strict,
                throw_type_error=tte,
              ),
              VarBinding,
            )
            // Hoist var declarations and function declarations
            self.hoist_declarations(data.body, func_env)
            match data.name {
              Some(name) =>
                if not(func_env.bindings.contains(name)) {
                  func_env.def(name, ctor, LetBinding)
                }
              None => ()
            }
            let exec_result = self.exec_stmts(data.body, func_env)
            match exec_result {
              Normal(_) => new_obj
              ReturnSignal(v) =>
                if is_object_like_for_constructor_return(v) {
                  v
                } else {
                  new_obj
                }
              BreakSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="break statement outside of loop",
                )
              ContinueSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="continue statement outside of loop",
                )
            }
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
          result
        }
        Some(UserFuncExt(data)) => {
          let saved_strict = self.strict
          let result = try {
            let func_strict = data.strict
            self.strict = func_strict
            if func_strict {
              // Strict mode: check for duplicate parameters and reserved names
              check_duplicate_params_ext(data.params, data.rest_param)
              for p in data.params {
                validate_strict_binding_name(p.name)
              }
              match data.rest_param {
                Some(rn) => validate_strict_binding_name(rn)
                None => ()
              }
            }
            let proto = match proto_override {
              Some(p) => p
              None =>
                match obj_data.properties.get("prototype") {
                  Some(v) => v
                  None => Null
                }
            }
            let new_obj = make_constructor_instance(proto, "Object")
            let func_env = Environment::new(parent=Some(data.closure))
            func_env.is_var_scope = true
            func_env.def("this", new_obj, LetBinding)
            func_env.def("<new.target>", ctor, LetBinding)
            let mut effective_param_count = 0
            for i = 0; i < data.params.length(); i = i + 1 {
              let param = data.params[i]
              // Skip rest destructuring params
              if data.rest_param is Some(rn) && param.name == rn {
                continue
              }
              let val : Value = if effective_param_count < args.length() &&
                not(args[effective_param_count] is Undefined) {
                args[effective_param_count]
              } else {
                match param.default_val {
                  Some(default_expr) => self.eval_expr(default_expr, func_env)
                  None =>
                    if effective_param_count < args.length() {
                      args[effective_param_count]
                    } else {
                      Undefined
                    }
                }
              }
              func_env.def(param.name, val, LetBinding)
              match param.pattern {
                Some(pat) => self.bind_pattern(pat, val, func_env, LetBinding)
                None => ()
              }
              effective_param_count = effective_param_count + 1
            }
            match data.rest_param {
              Some(rest_name) => {
                let rest_elements : Array[Value] = []
                for i = effective_param_count; i < args.length(); i = i + 1 {
                  rest_elements.push(args[i])
                }
                let rest_val = Array({ elements: rest_elements })
                func_env.def(rest_name, rest_val, LetBinding)
                // Apply destructuring pattern if present
                for p in data.params {
                  if p.name == rest_name {
                    match p.pattern {
                      Some(pat) =>
                        self.bind_pattern(pat, rest_val, func_env, LetBinding)
                      None => ()
                    }
                    break
                  }
                }
              }
              None => ()
            }
            let tte2 : Value? = if func_env.has("[[ThrowTypeError]]") {
              Some(func_env.get("[[ThrowTypeError]]"))
            } else {
              None
            }
            func_env.def(
              "arguments",
              make_arguments_object(
                args,
                ctor,
                func_strict,
                throw_type_error=tte2,
              ),
              VarBinding,
            )
            self.hoist_declarations(data.body, func_env)
            match data.name {
              Some(name) =>
                if not(func_env.bindings.contains(name)) {
                  func_env.def(name, ctor, LetBinding)
                }
              None => ()
            }
            let exec_result = self.exec_stmts(data.body, func_env)
            match exec_result {
              Normal(_) => new_obj
              ReturnSignal(v) =>
                if is_object_like_for_constructor_return(v) {
                  v
                } else {
                  new_obj
                }
              BreakSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="break statement outside of loop",
                )
              ContinueSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="continue statement outside of loop",
                )
            }
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
          result
        }
        Some(BoundFunc(target, _, bound_args)) => {
          // new BoundFunc(...args) delegates to new Target(...boundArgs, ...args)
          let all_args : Array[Value] = []
          for a in bound_args {
            all_args.push(a)
          }
          for a in args {
            all_args.push(a)
          }
          self.construct_value(target, all_args, loc)
        }
        Some(NativeCallable(_, func)) => {
          is_constructing.val = true
          let result = func(args) catch {
            e => {
              is_constructing.val = false
              raise e
            }
          }
          is_constructing.val = false
          result
        }
        Some(NonConstructableCallable(name, _)) =>
          raise @errors.TypeError(
            message=format_loc_context(name + " is not a constructor", loc),
          )
        Some(InterpreterCallable(_name, func)) => {
          // InterpreterCallable can be constructable (e.g., Map, Set constructors)
          is_constructing.val = true
          let result = func(self, Undefined, args) catch {
            e => {
              is_constructing.val = false
              raise e
            }
          }
          is_constructing.val = false
          result
        }
        Some(MethodCallable(name, _)) =>
          raise @errors.TypeError(
            message=format_loc_context(name + " is not a constructor", loc),
          )
        Some(ConstructorOnlyCallable(_, func)) => func(self, args)
        Some(ArrowFunc(_)) | Some(ArrowFuncExt(_)) =>
          raise @errors.TypeError(
            message=format_loc_context(
              "arrow functions cannot be used as constructors", loc,
            ),
          )
        Some(
          ClassConstructor(
            class_name,
            proto,
            super_ctor,
            ctor_fn,
            closure,
            super_proto
          )
        ) => {
          // Class bodies are always strict mode
          let saved_strict = self.strict
          self.strict = true
          let result = try {
            // Create the new instance with the class prototype
            let new_obj = make_constructor_instance(proto, class_name)
            // Set up the constructor environment
            let ctor_env = Environment::new(parent=Some(closure))
            ctor_env.is_var_scope = true
            ctor_env.def_builtin("this", new_obj)
            ctor_env.def("<new.target>", ctor, LetBinding)
            // Set up [[SuperConstructor]] and [[SuperPrototype]] for super() calls
            match super_ctor {
              Some(sc) => {
                ctor_env.def_builtin("[[SuperConstructor]]", sc)
                ctor_env.def_builtin("[[SuperPrototype]]", super_proto)
              }
              None => ()
            }
            // Execute the constructor if one was defined
            match ctor_fn {
              Some((params, body)) => {
                // Class constructors are always strict — validate params
                check_duplicate_params(params)
                for p in params {
                  validate_strict_binding_name(p)
                }
                // Bind parameters
                for i = 0; i < params.length(); i = i + 1 {
                  let val : Value = if i < args.length() {
                    args[i]
                  } else {
                    Undefined
                  }
                  ctor_env.def(params[i], val, LetBinding)
                }
                let ctor_tte : Value? = if ctor_env.has("[[ThrowTypeError]]") {
                  Some(ctor_env.get("[[ThrowTypeError]]"))
                } else {
                  None
                }
                ctor_env.def(
                  "arguments",
                  make_arguments_object(
                    args,
                    ctor,
                    true,
                    throw_type_error=ctor_tte,
                  ),
                  VarBinding,
                )
                // Hoist declarations and execute body
                self.hoist_declarations(body, ctor_env)
                let exec_result = self.exec_stmts(body, ctor_env)
                let current_this = ctor_env.get("this")
                match exec_result {
                  Normal(_) => current_this
                  ReturnSignal(v) =>
                    if is_object_like_for_constructor_return(v) {
                      v
                    } else {
                      current_this
                    }
                  BreakSignal(_, _) =>
                    raise @errors.SyntaxError(
                      message="break statement outside of loop",
                    )
                  ContinueSignal(_, _) =>
                    raise @errors.SyntaxError(
                      message="continue statement outside of loop",
                    )
                }
              }
              None => {
                // No explicit constructor - if there's a super class, call super()
                // Save the derived class constructor for new.target propagation
                let derived_ctor = ctor
                match super_ctor {
                  Some(sc) =>
                    match sc {
                      Object(super_data) =>
                        match super_data.callable {
                          Some(
                            ClassConstructor(
                              _,
                              _,
                              grand_super,
                              ctor,
                              senv,
                              sproto
                            )
                          ) => {
                            let super_env = Environment::new(parent=Some(senv))
                            super_env.def_builtin("this", new_obj)
                            super_env.def(
                              "<new.target>",
                              derived_ctor,
                              LetBinding,
                            )
                            match grand_super {
                              Some(gs) => {
                                super_env.def_builtin(
                                  "[[SuperConstructor]]", gs,
                                )
                                super_env.def_builtin(
                                  "[[SuperPrototype]]", sproto,
                                )
                              }
                              None => ()
                            }
                            match ctor {
                              Some((params, body)) => {
                                for i = 0; i < params.length(); i = i + 1 {
                                  let val : Value = if i < args.length() {
                                    args[i]
                                  } else {
                                    Undefined
                                  }
                                  super_env.def(params[i], val, LetBinding)
                                }
                                let super_tte : Value? = if super_env.has(
                                    "[[ThrowTypeError]]",
                                  ) {
                                  Some(super_env.get("[[ThrowTypeError]]"))
                                } else {
                                  None
                                }
                                super_env.def(
                                  "arguments",
                                  make_arguments_object(
                                    args,
                                    sc,
                                    true,
                                    throw_type_error=super_tte,
                                  ),
                                  VarBinding,
                                )
                                self.hoist_declarations(body, super_env)
                                let exec_result = self.exec_stmts(
                                  body, super_env,
                                )
                                // If super constructor returns an object, use it
                                match exec_result {
                                  ReturnSignal(v) =>
                                    if is_object_like_for_constructor_return(v) {
                                      // Must restore strict before early return —
                                      // `return` exits eval_new entirely, bypassing
                                      // the normal restore at the end of the try block.
                                      self.strict = saved_strict
                                      return maybe_set_promise_constructor(
                                        v, derived_ctor,
                                      )
                                    }
                                  _ => ()
                                }
                              }
                              None => ()
                            }
                          }
                          Some(ConstructorOnlyCallable(_, super_func)) => {
                            let super_result = super_func(self, args)
                            if is_object_like_for_constructor_return(
                                super_result,
                              ) {
                              self.strict = saved_strict
                              return maybe_set_promise_constructor(
                                super_result, derived_ctor,
                              )
                            }
                          }
                          _ => ()
                        }
                      _ => ()
                    }
                  None => ()
                }
                new_obj
              }
            }
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
          maybe_set_promise_constructor(result, ctor)
        }
        _ =>
          raise @errors.TypeError(
            message=format_loc_context("is not a constructor", loc),
          )
      }
    _ =>
      raise @errors.TypeError(
        message=format_loc_context("is not a constructor", loc),
      )
  }
}

///|
/// Ensure a function body starts with "use strict" directive.
/// Returns the body unchanged if it already has one, or prepends the directive.
fn ensure_strict_body(body : Array[@ast.Stmt]) -> Array[@ast.Stmt] {
  if has_use_strict(body) {
    body
  } else {
    let strict_body : Array[@ast.Stmt] = [
      ExprStmt(
        StringLit("use strict", false, @token.Loc::default()),
        @token.Loc::default(),
      ),
    ]
    for s in body {
      strict_body.push(s)
    }
    strict_body
  }
}

///|
fn Interpreter::create_class(
  self : Interpreter,
  name : String,
  superclass_expr : @ast.Expr?,
  methods : Array[@ast.ClassMethod],
  env : Environment,
) -> Value raise Error {
  // Evaluate superclass if present
  let (super_ctor, super_proto) : (Value?, Value) = match superclass_expr {
    Some(expr) => {
      let super_val = self.eval_expr(expr, env)
      match super_val {
        Object(super_data) =>
          match super_data.properties.get("prototype") {
            Some(sp) => (Some(super_val), sp)
            None => (Some(super_val), Null)
          }
        _ =>
          raise @errors.TypeError(
            message="Class extends value is not a constructor",
          )
      }
    }
    None => (None, Null)
  }
  // Create the prototype object
  let proto_props : Map[String, Value] = {}
  let proto_descriptors : Map[String, PropDescriptor] = {}
  let proto_symbol_props : Map[Int, Value] = {}
  let proto_symbol_descriptors : Map[Int, PropDescriptor] = {}
  // Create static properties map
  let static_props : Map[String, Value] = {}
  let static_descriptors : Map[String, PropDescriptor] = {}
  let static_symbol_props : Map[Int, Value] = {}
  let static_symbol_descriptors : Map[Int, PropDescriptor] = {}
  // Track constructor method
  let mut ctor_fn : (Array[String], Array[@ast.Stmt])? = None
  // Create method environments with [[SuperPrototype]] for super.method() support
  let instance_method_env : Environment = match super_ctor {
    Some(_) => {
      let menv = Environment::new(parent=Some(env))
      menv.def_builtin("[[SuperPrototype]]", super_proto)
      menv
    }
    None => env
  }
  let static_method_env : Environment = match super_ctor {
    Some(sc) => {
      let menv = Environment::new(parent=Some(env))
      menv.def_builtin("[[SuperPrototype]]", sc)
      menv
    }
    None => env
  }
  // Process all methods
  for m in methods {
    // Get the method key - could be string or symbol
    let key_val : Value = match m.key {
      StringLit(s, _, _) => String_(s)
      _ => self.eval_expr(m.key, env)
    }
    let method_key_str : String = match key_val {
      Symbol(_) => key_val.to_string()
      _ => to_js_string(key_val)
    }
    // Check if this is the constructor
    if method_key_str == "constructor" && not(m.is_static) {
      // Extract constructor params and body
      // Class bodies are always strict, so ensure constructor body has "use strict"
      match m.value {
        FuncExpr(_, params, body, _) => {
          let strict_body = ensure_strict_body(body)
          validate_function_signature(true, None, params, strict_body)
          ctor_fn = Some((params, strict_body))
        }
        FuncExprExt(_, params, rest, body, _) => {
          let strict_body = ensure_strict_body(body)
          validate_function_signature_ext(true, None, params, rest, strict_body)
          // Convert Param array to String array (ignoring defaults for now)
          let param_names = params.map(fn(p) { p.name })
          ctor_fn = Some((param_names, strict_body))
        }
        _ => ()
      }
      continue
    }
    // Create the method function value
    // Class methods are always strict — ensure body has "use strict"
    // Use the appropriate method environment for super.method() support
    let method_closure = if m.is_static {
      static_method_env
    } else {
      instance_method_env
    }
    let method_val : Value = match m.value {
      FuncExpr(fn_name, params, body, _) => {
        let strict_body = ensure_strict_body(body)
        validate_function_signature(true, fn_name, params, strict_body)
        let func_data : FuncData = {
          name: fn_name,
          params,
          body: strict_body,
          closure: method_closure,
          strict: true,
        }
        make_func(func_data)
      }
      FuncExprExt(fn_name, params, rest, body, _) => {
        let strict_body = ensure_strict_body(body)
        validate_function_signature_ext(
          true, fn_name, params, rest, strict_body,
        )
        let func_data : FuncDataExt = {
          name: fn_name,
          params,
          rest_param: rest,
          body: strict_body,
          closure: method_closure,
          strict: true,
        }
        make_func_ext(func_data)
      }
      _ => self.eval_expr(m.value, method_closure)
    }
    // Handle getter/setter vs regular method
    // Class methods are non-enumerable per spec
    match m.kind {
      Get =>
        // Getter method - store as accessor descriptor
        match key_val {
          Symbol(sym) => {
            let (props, descs) = if m.is_static {
              (static_symbol_props, static_symbol_descriptors)
            } else {
              (proto_symbol_props, proto_symbol_descriptors)
            }
            if not(props.contains(sym.id)) {
              props[sym.id] = Undefined
            }
            let existing = descs.get(sym.id)
            descs[sym.id] = {
              writable: false,
              enumerable: false,
              configurable: true,
              getter: Some(method_val),
              setter: match existing {
                Some(d) => d.setter
                None => None
              },
            }
          }
          _ => {
            let (props, descs) = if m.is_static {
              (static_props, static_descriptors)
            } else {
              (proto_props, proto_descriptors)
            }
            if not(props.contains(method_key_str)) {
              props[method_key_str] = Undefined
            }
            let existing = descs.get(method_key_str)
            descs[method_key_str] = {
              writable: false,
              enumerable: false,
              configurable: true,
              getter: Some(method_val),
              setter: match existing {
                Some(d) => d.setter
                None => None
              },
            }
          }
        }
      Set =>
        // Setter method - store as accessor descriptor
        match key_val {
          Symbol(sym) => {
            let (props, descs) = if m.is_static {
              (static_symbol_props, static_symbol_descriptors)
            } else {
              (proto_symbol_props, proto_symbol_descriptors)
            }
            if not(props.contains(sym.id)) {
              props[sym.id] = Undefined
            }
            let existing = descs.get(sym.id)
            descs[sym.id] = {
              writable: false,
              enumerable: false,
              configurable: true,
              getter: match existing {
                Some(d) => d.getter
                None => None
              },
              setter: Some(method_val),
            }
          }
          _ => {
            let (props, descs) = if m.is_static {
              (static_props, static_descriptors)
            } else {
              (proto_props, proto_descriptors)
            }
            if not(props.contains(method_key_str)) {
              props[method_key_str] = Undefined
            }
            let existing = descs.get(method_key_str)
            descs[method_key_str] = {
              writable: false,
              enumerable: false,
              configurable: true,
              getter: match existing {
                Some(d) => d.getter
                None => None
              },
              setter: Some(method_val),
            }
          }
        }
      _ => {
        // Regular method or Init
        let method_descriptor : PropDescriptor = {
          writable: true,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        }
        // Store method in appropriate map based on key type (string vs symbol)
        match key_val {
          Symbol(sym) =>
            // Symbol key - store in symbol_properties
            if m.is_static {
              static_symbol_props[sym.id] = method_val
              static_symbol_descriptors[sym.id] = method_descriptor
            } else {
              proto_symbol_props[sym.id] = method_val
              proto_symbol_descriptors[sym.id] = method_descriptor
            }
          _ => {
            // String key - store in regular properties
            if m.is_static {
              static_props[method_key_str] = method_val
              static_descriptors[method_key_str] = method_descriptor
            } else {
              proto_props[method_key_str] = method_val
              proto_descriptors[method_key_str] = method_descriptor
            }
          }
        }
      }
    }
  }
  // Create prototype object
  let proto = Object({
    properties: proto_props,
    symbol_properties: proto_symbol_props,
    prototype: super_proto,
    callable: None,
    class_name: name,
    descriptors: proto_descriptors,
    symbol_descriptors: proto_symbol_descriptors,
    extensible: true,
  })
  // Add constructor back-reference to prototype
  // (will be set after class object is created)
  let class_proto = match super_ctor {
    Some(super_class) => super_class
    None => self.global.get("[[FunctionPrototype]]") catch { _ => Null }
  }
  // Create the class constructor function
  let class_obj = Object({
    properties: static_props,
    symbol_properties: static_symbol_props,
    prototype: class_proto,
    callable: Some(
      ClassConstructor(name, proto, super_ctor, ctor_fn, env, super_proto),
    ),
    class_name: "Function",
    descriptors: static_descriptors,
    symbol_descriptors: static_symbol_descriptors,
    extensible: true,
  })
  // Set prototype.constructor to point to the class (non-enumerable per spec)
  match proto {
    Object(proto_data) => {
      proto_data.properties["constructor"] = class_obj
      proto_data.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }
  // Add prototype property to the class
  match class_obj {
    Object(class_data) => class_data.properties["prototype"] = proto
    _ => ()
  }
  class_obj
}

///|
fn Interpreter::eval_update(
  self : Interpreter,
  op : @ast.UpdateOp,
  operand : @ast.Expr,
  prefix : Bool,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  match operand {
    Ident(name, _) => {
      // Strict mode: update of eval/arguments is a SyntaxError
      if self.strict && (name == "eval" || name == "arguments") {
        raise @errors.SyntaxError(
          message="Unexpected eval or arguments in strict mode",
        )
      }
      let current = env.get(name)
      let num = to_number(current)
      let new_val : Value = match op {
        Increment => Number(num + 1.0)
        Decrement => Number(num - 1.0)
      }
      if self.is_immutable_global(name) {
        if self.strict {
          raise @errors.TypeError(
            message="Cannot assign to read only property '\{name}' of object '[object global]'",
          )
        }
      } else {
        env.assign(name, new_val)
      }
      if prefix {
        new_val
      } else {
        Number(num)
      }
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      let num = to_number(current)
      let new_val : Value = match op {
        Increment => Number(num + 1.0)
        Decrement => Number(num - 1.0)
      }
      let _ = self.set_property(obj, prop, new_val, loc)
      if prefix {
        new_val
      } else {
        Number(num)
      }
    }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let current = self.get_computed_property(obj, key, mloc)
      let num = to_number(current)
      let new_val : Value = match op {
        Increment => Number(num + 1.0)
        Decrement => Number(num - 1.0)
      }
      let _ = self.set_computed_property(obj, key, new_val, loc)
      if prefix {
        new_val
      } else {
        Number(num)
      }
    }
    _ =>
      raise @errors.SyntaxError(
        message="Invalid update target at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
fn Interpreter::eval_compound_assign(
  self : Interpreter,
  op : @ast.CompoundOp,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // Handle logical assignment operators with short-circuit semantics
  match op {
    LogicalAndAssign =>
      return self.eval_logical_assign_and(target, value_expr, env, loc)
    LogicalOrAssign =>
      return self.eval_logical_assign_or(target, value_expr, env, loc)
    NullishAssign =>
      return self.eval_nullish_assign(target, value_expr, env, loc)
    _ => ()
  }
  let bin_op : @ast.BinOp = match op {
    AddAssign => Add
    SubAssign => Sub
    MulAssign => Mul
    ExpAssign => Exp
    DivAssign => Div
    ModAssign => Mod
    BitAndAssign => BitAnd
    BitOrAssign => BitOr
    BitXorAssign => BitXor
    LShiftAssign => LShift
    RShiftAssign => RShift
    URShiftAssign => URShift
    LogicalAndAssign | LogicalOrAssign | NullishAssign => Add // unreachable
  }
  match target {
    Ident(name, _) => {
      // Strict mode: compound assignment to eval/arguments is a SyntaxError
      if self.strict && (name == "eval" || name == "arguments") {
        raise @errors.SyntaxError(
          message="Unexpected eval or arguments in strict mode",
        )
      }
      let current = env.get(name)
      let rhs = self.eval_expr(value_expr, env)
      let result = eval_binary_op(bin_op, current, rhs, loc)
      // Check if the target is a non-writable property on the global object
      if self.is_immutable_global(name) {
        if self.strict {
          raise @errors.TypeError(
            message="Cannot assign to read only property '\{name}' of object '[object global]'",
          )
        }
        return result
      }
      env.assign(name, result)
      result
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      let rhs = self.eval_expr(value_expr, env)
      let result = eval_binary_op(bin_op, current, rhs, loc)
      let _ = self.set_property(obj, prop, result, loc)
      result
    }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let current = self.get_computed_property(obj, key, mloc)
      let rhs = self.eval_expr(value_expr, env)
      let result = eval_binary_op(bin_op, current, rhs, loc)
      let _ = self.set_computed_property(obj, key, result, loc)
      result
    }
    _ =>
      raise @errors.SyntaxError(
        message="Invalid compound assignment target at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
fn Interpreter::eval_logical_assign_and(
  self : Interpreter,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // x &&= y: if x is truthy, assign y to x; return final value
  match target {
    Ident(name, _) => {
      if self.strict && (name == "eval" || name == "arguments") {
        raise @errors.SyntaxError(
          message="Unexpected eval or arguments in strict mode",
        )
      }
      let current = env.get(name)
      if is_truthy(current) {
        let rhs = self.eval_expr(value_expr, env)
        if self.is_immutable_global(name) {
          if self.strict {
            raise @errors.TypeError(
              message="Cannot assign to read only property '\{name}' of object '[object global]'",
            )
          }
          return rhs
        }
        env.assign(name, rhs)
        rhs
      } else {
        current
      }
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      if is_truthy(current) {
        let rhs = self.eval_expr(value_expr, env)
        self.set_property(obj, prop, rhs, loc)
      } else {
        current
      }
    }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let current = self.get_computed_property(obj, key, mloc)
      if is_truthy(current) {
        let rhs = self.eval_expr(value_expr, env)
        self.set_computed_property(obj, key, rhs, loc)
      } else {
        current
      }
    }
    _ =>
      raise @errors.SyntaxError(
        message="Invalid assignment target at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
fn Interpreter::eval_logical_assign_or(
  self : Interpreter,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // x ||= y: if x is falsy, assign y to x; return final value
  match target {
    Ident(name, _) => {
      if self.strict && (name == "eval" || name == "arguments") {
        raise @errors.SyntaxError(
          message="Unexpected eval or arguments in strict mode",
        )
      }
      let current = env.get(name)
      if not(is_truthy(current)) {
        let rhs = self.eval_expr(value_expr, env)
        if self.is_immutable_global(name) {
          if self.strict {
            raise @errors.TypeError(
              message="Cannot assign to read only property '\{name}' of object '[object global]'",
            )
          }
          return rhs
        }
        env.assign(name, rhs)
        rhs
      } else {
        current
      }
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      if not(is_truthy(current)) {
        let rhs = self.eval_expr(value_expr, env)
        self.set_property(obj, prop, rhs, loc)
      } else {
        current
      }
    }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let current = self.get_computed_property(obj, key, mloc)
      if not(is_truthy(current)) {
        let rhs = self.eval_expr(value_expr, env)
        self.set_computed_property(obj, key, rhs, loc)
      } else {
        current
      }
    }
    _ =>
      raise @errors.SyntaxError(
        message="Invalid assignment target at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
fn Interpreter::eval_nullish_assign(
  self : Interpreter,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // x ??= y: if x is null or undefined, assign y to x; return final value
  match target {
    Ident(name, _) => {
      if self.strict && (name == "eval" || name == "arguments") {
        raise @errors.SyntaxError(
          message="Unexpected eval or arguments in strict mode",
        )
      }
      let current = env.get(name)
      match current {
        Null | Undefined => {
          let rhs = self.eval_expr(value_expr, env)
          if self.is_immutable_global(name) {
            if self.strict {
              raise @errors.TypeError(
                message="Cannot assign to read only property '\{name}' of object '[object global]'",
              )
            }
            return rhs
          }
          env.assign(name, rhs)
          rhs
        }
        _ => current
      }
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      match current {
        Null | Undefined => {
          let rhs = self.eval_expr(value_expr, env)
          self.set_property(obj, prop, rhs, loc)
        }
        _ => current
      }
    }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let current = self.get_computed_property(obj, key, mloc)
      match current {
        Null | Undefined => {
          let rhs = self.eval_expr(value_expr, env)
          self.set_computed_property(obj, key, rhs, loc)
        }
        _ => current
      }
    }
    _ =>
      raise @errors.SyntaxError(
        message="Invalid assignment target at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
/// Execute an import declaration
fn Interpreter::exec_import(
  self : Interpreter,
  default_import : String?,
  specifiers : Array[@ast.ImportSpecifier],
  namespace_import : String?,
  source : String,
  env : Environment,
  loc : @token.Loc,
) -> Signal raise Error {
  // Look up module in registry
  let module_exports = match self.module_registry.get(source) {
    Some(exports) => exports
    None =>
      raise @errors.SyntaxError(
        message="Cannot find module '\{source}' at line \{loc.line}, col \{loc.col}",
      )
  }
  // import defaultExport from 'source'
  match default_import {
    Some(name) => {
      let value = match module_exports.get("default") {
        Some(v) => v
        None =>
          raise @errors.SyntaxError(
            message="Module '\{source}' does not have a default export at line \{loc.line}, col \{loc.col}",
          )
      }
      env.def(name, value, ConstBinding)
    }
    None => ()
  }
  // import { name1, name2 as alias } from 'source'
  for spec in specifiers {
    let value = match module_exports.get(spec.imported) {
      Some(v) => v
      None =>
        raise @errors.SyntaxError(
          message="Module '\{source}' does not export '\{spec.imported}' at line \{loc.line}, col \{loc.col}",
        )
    }
    env.def(spec.local_name, value, ConstBinding)
  }
  // import * as namespace from 'source'
  match namespace_import {
    Some(name) => {
      // Create a namespace object with all exports as properties
      let ns_props : Map[String, Value] = {}
      let ns_descs : Map[String, PropDescriptor] = {}
      module_exports.each(fn(k, v) {
        ns_props[k] = v
        ns_descs[k] = {
          writable: false,
          enumerable: true,
          configurable: false,
          getter: None,
          setter: None,
        }
      })
      let ns_obj : Value = Object({
        properties: ns_props,
        symbol_properties: {},
        prototype: Null,
        callable: None,
        class_name: "Module",
        descriptors: ns_descs,
        symbol_descriptors: {},
        extensible: false,
      })
      env.def(name, ns_obj, ConstBinding)
    }
    None => ()
  }
  Normal(Undefined)
}

///|
/// Execute a named export declaration
fn Interpreter::exec_export_named(
  self : Interpreter,
  decl : @ast.Stmt?,
  specifiers : Array[@ast.ExportSpecifier],
  source : String?,
  env : Environment,
  loc : @token.Loc,
) -> Signal raise Error {
  // export let/const/var/function/class ...
  match decl {
    Some(inner_decl) => {
      let signal = self.exec_stmt(inner_decl, env)
      // Record declared names for deferred resolution (live bindings)
      self.extract_export_names(inner_decl)
      return signal
    }
    None => ()
  }
  // export { name1, name2 as alias } [from 'source']
  match source {
    Some(src) => {
      // Re-export from another module - resolve immediately (source already finalized)
      let src_exports = match self.module_registry.get(src) {
        Some(exports) => exports
        None =>
          raise @errors.SyntaxError(
            message="Cannot find module '\{src}' at line \{loc.line}, col \{loc.col}",
          )
      }
      for spec in specifiers {
        let value = match src_exports.get(spec.local_name) {
          Some(v) => v
          None =>
            raise @errors.SyntaxError(
              message="Module '\{src}' does not export '\{spec.local_name}' at line \{loc.line}, col \{loc.col}",
            )
        }
        self.module_exports[spec.exported] = value
      }
    }
    None =>
      // Local export: defer resolution for live bindings
      for spec in specifiers {
        self.module_export_bindings.push((spec.exported, spec.local_name))
      }
  }
  Normal(Undefined)
}

///|
/// Execute export * from 'source' or export * as name from 'source'
fn Interpreter::exec_export_all(
  self : Interpreter,
  ns_alias : String?,
  source : String,
  loc : @token.Loc,
) -> Signal raise Error {
  let src_exports = match self.module_registry.get(source) {
    Some(exports) => exports
    None =>
      raise @errors.SyntaxError(
        message="Cannot find module '\{source}' at line \{loc.line}, col \{loc.col}",
      )
  }
  match ns_alias {
    Some(name) => {
      // export * as name from 'source' - create namespace object
      let ns_props : Map[String, Value] = {}
      let ns_descs : Map[String, PropDescriptor] = {}
      src_exports.each(fn(k, v) {
        ns_props[k] = v
        ns_descs[k] = {
          writable: false,
          enumerable: true,
          configurable: false,
          getter: None,
          setter: None,
        }
      })
      let ns_obj : Value = Object({
        properties: ns_props,
        symbol_properties: {},
        prototype: Null,
        callable: None,
        class_name: "Module",
        descriptors: ns_descs,
        symbol_descriptors: {},
        extensible: false,
      })
      self.module_exports[name] = ns_obj
    }
    None =>
      // export * from 'source' - re-export all (except default)
      src_exports.each(fn(k, v) {
        if k != "default" {
          self.module_exports[k] = v
        }
      })
  }
  Normal(Undefined)
}

///|
/// Record exported names from a declaration for deferred resolution (live bindings)
fn Interpreter::extract_export_names(
  self : Interpreter,
  decl : @ast.Stmt,
) -> Unit {
  match decl {
    VarDecl(_, name, _, _) => self.module_export_bindings.push((name, name))
    FuncDecl(name, _, _, _) => self.module_export_bindings.push((name, name))
    FuncDeclExt(name, _, _, _, _) =>
      self.module_export_bindings.push((name, name))
    GeneratorDecl(name, _, _, _) =>
      self.module_export_bindings.push((name, name))
    GeneratorDeclExt(name, _, _, _, _) =>
      self.module_export_bindings.push((name, name))
    AsyncFuncDecl(name, _, _, _) =>
      self.module_export_bindings.push((name, name))
    AsyncFuncDeclExt(name, _, _, _, _) =>
      self.module_export_bindings.push((name, name))
    AsyncGeneratorDecl(name, _, _, _) =>
      self.module_export_bindings.push((name, name))
    AsyncGeneratorDeclExt(name, _, _, _, _) =>
      self.module_export_bindings.push((name, name))
    ClassDecl(name, _, _, _) => self.module_export_bindings.push((name, name))
    DestructureDecl(_, pattern, _, _) =>
      self.extract_pattern_export_names(pattern)
    StmtList(stmts, _) =>
      for stmt in stmts {
        self.extract_export_names(stmt)
      }
    _ => ()
  }
}

///|
/// Record names from a destructuring pattern for deferred export resolution
fn Interpreter::extract_pattern_export_names(
  self : Interpreter,
  pattern : @ast.Pattern,
) -> Unit {
  match pattern {
    IdentPat(name) => self.module_export_bindings.push((name, name))
    DefaultPat(inner_pat, _) => self.extract_pattern_export_names(inner_pat)
    AssignTarget(_) => () // member expressions don't export names
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => self.extract_pattern_export_names(p)
          None => ()
        }
      }
      match rest {
        Some(p) => self.extract_pattern_export_names(p)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        self.extract_pattern_export_names(prop.value)
      }
      match rest {
        Some(p) => self.extract_pattern_export_names(p)
        None => ()
      }
    }
  }
}

///|
/// Register a module's exports in the module registry
pub fn Interpreter::register_module(
  self : Interpreter,
  specifier : String,
  exports : Map[String, Value],
) -> Unit {
  self.module_registry[specifier] = exports
}

///|
/// Run a module source and return its exports
pub fn Interpreter::run_module(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> Map[String, Value] raise Error {
  // Save and reset module exports for this module
  let saved_exports = self.module_exports
  let saved_bindings = self.module_export_bindings
  let saved_strict = self.strict
  self.module_exports = {}
  self.module_export_bindings = []
  // Create a module-scoped environment that inherits from global
  let module_env = Environment::new(parent=Some(self.global))
  try {
    // Modules are always strict mode
    self.strict = true
    // Static block-scoped redeclaration checks (applies to module code too).
    self.validate_block_early_errors(stmts, true)
    // Hoist var declarations and function declarations
    self.hoist_declarations(stmts, module_env)
    // Also hoist block-scoped (let/const/class) with TDZ
    hoist_block_tdz(stmts, module_env)
    for stmt in stmts {
      match self.exec_stmt(stmt, module_env) {
        Normal(_) => ()
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
    self.strict = saved_strict
    // Resolve deferred export bindings from module environment (live bindings)
    for pair in self.module_export_bindings {
      let (export_name, local_name) = pair
      self.module_exports[export_name] = module_env.get(local_name)
    }
    let exports = self.module_exports
    self.module_exports = saved_exports
    self.module_export_bindings = saved_bindings
    exports
  } catch {
    e => {
      self.strict = saved_strict
      self.module_exports = saved_exports
      self.module_export_bindings = saved_bindings
      raise e
    }
  }
}
