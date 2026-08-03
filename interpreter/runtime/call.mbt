///|
/// Spread an iterable value into an array of values using the iterator protocol
pub fn Interpreter::spread_iterable(
  self : Interpreter,
  val : Value,
  loc : @token.Loc,
) -> Array[Value] raise Error {
  let result : Array[Value] = []

  // Try to get the iterator via Symbol.iterator protocol
  let iterator_sym = self.realm_state.well_known_symbols.iterator
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

  let next_method = self.get_iterator_next_method(iterator, loc)

  // Iterate using the iterator protocol
  while true {
    match self.iterator_step_value(iterator, next_method, loc) {
      None => break
      Some(value) => result.push(value)
    }
  }
  result
}

///|
/// Raise SyntaxError for Break/Continue signals escaping a function boundary.
/// Used as a shared invariant at all function-body and module execution sites.
fn raise_if_break_continue(sig : Signal) -> Unit raise Error {
  match sig {
    BreakSignal(_, _) =>
      raise @errors.SyntaxError(message="break statement outside of loop")
    ContinueSignal(_, _) =>
      raise @errors.SyntaxError(message="continue statement outside of loop")
    _ => ()
  }
}

///|
fn Interpreter::eval_args_with_spread(
  self : Interpreter,
  ctx : ExecContext,
  arg_exprs : Array[@ast.Expr],
  env : Environment,
) -> Array[Value] raise Error {
  let args : Array[Value] = []
  for a in arg_exprs {
    match a {
      SpreadExpr(inner, loc) => {
        let val = self.eval_expr(ctx, inner, env)
        // Use iterator protocol for spreading
        let spread_vals = self.spread_iterable(val, loc)
        for v in spread_vals {
          args.push(v)
        }
      }
      _ => args.push(self.eval_expr(ctx, a, env))
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
pub fn load_direct_eval_callee(env : Environment) -> Value raise Error {
  env.get("eval") catch {
    _ => raise @errors.ReferenceError(message="eval is not defined")
  }
}

///|
pub fn Interpreter::call_direct_eval_or_shadowed(
  self : Interpreter,
  callee : Value,
  args : Array[Value],
  env : Environment,
  loc : @token.Loc,
  caller_strict~ : Bool,
) -> Value raise Error {
  if is_eval_function(callee) {
    if args.length() == 0 {
      return Undefined
    }
    match args[0] {
      String_(code) => self.perform_eval(code, env, true, caller_strict~)
      other => other
    }
  } else {
    self.call_value(callee, Undefined, args, loc)
  }
}

///|
/// Strip consecutive Grouping nodes from an expression.
/// Per ES spec, grouping parentheses do not change the Reference type,
/// so ((eval))("code") is still a direct eval call.
pub fn unwrap_grouping(expr : @ast.Expr) -> @ast.Expr {
  let mut current = expr
  for ;; {
    match current {
      Grouping(inner, _) => current = inner
      _ => return current
    }
  }
}

///|
fn collect_param_default_eval_var_conflicts(
  params : Array[@ast.Param],
  rest_param : String?,
  implicit_arguments? : Bool = false,
) -> @set.Set[String] {
  let conflicts = @set.Set::default()
  if implicit_arguments {
    conflicts.add("arguments")
  }
  for param in params {
    match param.pattern {
      Some(pattern) =>
        for name in @static_semantics.bound_names(pattern) {
          conflicts.add(name)
        }
      None => if !param.is_rest_pattern { conflicts.add(param.name) }
    }
  }
  match rest_param {
    Some(name) => conflicts.add(name)
    None => ()
  }
  conflicts
}

///|
/// Shared core of UserFuncExt and ArrowFuncExt call paths: bind
/// parameters (with defaults, destructuring, rest), optionally split
/// the body env per §10.2.11, hoist body declarations, execute the
/// body, and reduce the completion to a plain Value.
///
/// Caller is responsible for everything that differs between named
/// FunctionExpression calls and arrow calls:
/// - `param_env`'s parent (the named-FE self-name wrapper, or
///   `data.closure` directly for arrows)
/// - Strict-mode duplicate / reserved-name validation
/// - `this` / `<new.target>` / `arguments` installs (arrows skip them
///   entirely — ThisMode=lexical per §10.2.11 step 18).
///
/// Per §10.2.11 step 26 the split is gated on
/// `has_parameter_expressions(data.params)` — plain-rest and
/// plain-destructure shapes stay single-env so a body-level
/// `var <name>` reuses the param binding.
fn Interpreter::bind_ext_params_and_exec_body_signal(
  self : Interpreter,
  data : FuncDataExt,
  args : Array[Value],
  param_env : Environment,
  func_ctx : ExecContext,
  is_arrow? : Bool = false,
) -> Signal raise Error {
  // §19.2.1.3 (#A.6): save on entry, reset to false so nested function
  // invocations in param defaults (IIFE, arrow, recursive call) do not
  // inherit this frame's state. Restored on both the normal and raise
  // paths below so any abnormal completion during default evaluation
  // or body execution leaves the flag clean for outer frames.
  let saved_in_default = self.in_nonarrow_param_default_eval
  let saved_param_default_conflicts = self.param_default_eval_var_conflicts
  self.in_nonarrow_param_default_eval = false
  self.param_default_eval_var_conflicts = None
  let param_default_conflicts = collect_param_default_eval_var_conflicts(
    data.params,
    data.rest_param,
    implicit_arguments=!is_arrow,
  )
  let result : Signal = try {
    // §10.2.11 step 21: pre-declare all param BoundNames as TDZ so that
    // self- and forward-referencing defaults throw ReferenceError.
    let mut has_rest_pattern_param = false
    for p in data.params {
      if p.is_rest_pattern {
        has_rest_pattern_param = true
        // Declare bound names from the rest destructuring pattern (...[a] → a),
        // but NOT the synthetic "$rest" name stored in rest_param.
        match p.pattern {
          Some(pat) =>
            for name in @static_semantics.bound_names(pat) {
              param_env.def_param_tdz(name)
            }
          None => ()
        }
        continue
      }
      match p.pattern {
        Some(pat) =>
          // Destructuring param: pre-declare all bound names (e.g. {y} → y).
          for name in @static_semantics.bound_names(pat) {
            param_env.def_param_tdz(name)
          }
        None => param_env.def_param_tdz(p.name)
      }
    }
    // Simple named rest (e.g. ...rest): pre-declare the user name.
    // Destructuring rest (...[a]): bound names declared above via BoundNames.
    if !has_rest_pattern_param {
      match data.rest_param {
        Some(rp) => param_env.def_param_tdz(rp)
        None => ()
      }
    }
    // Bind params with defaults
    let mut effective_param_count = 0
    for i = 0; i < data.params.length(); i = i + 1 {
      let param = data.params[i]
      // Skip destructuring-rest params; they are bound from the rest array below.
      if param.is_rest_pattern {
        continue
      }
      let val : Value = if effective_param_count < args.length() &&
        !(args[effective_param_count] is Undefined) {
        args[effective_param_count]
      } else {
        match param.default_val {
          Some(default_expr) => {
            // §19.2.1.3 gate: active only around default evaluation.
            self.in_nonarrow_param_default_eval = true
            self.param_default_eval_var_conflicts = Some(
              param_default_conflicts,
            )
            let v = match param.pattern {
              None =>
                self.eval_named_expr(
                  func_ctx,
                  default_expr,
                  param_env,
                  param.name,
                )
              Some(_) => self.eval_expr(func_ctx, default_expr, param_env)
            }
            self.in_nonarrow_param_default_eval = false
            self.param_default_eval_var_conflicts = None
            v
          }
          None =>
            if effective_param_count < args.length() {
              args[effective_param_count]
            } else {
              Undefined
            }
        }
      }
      // Destructure pattern params without exposing their synthetic names.
      match param.pattern {
        Some(pat) =>
          self.bind_pattern(pat, val, param_env, LetBinding, ctx=func_ctx)
        None => param_env.initialize(param.name, val)
      }
      effective_param_count = effective_param_count + 1
    }
    // Rest param
    match data.rest_param {
      Some(rest_name) => {
        let rest_elements : Array[Value] = []
        for i in effective_param_count..<args.length() {
          rest_elements.push(args[i])
        }
        let rest_val = make_array(rest_elements)
        let mut bound_rest_pattern = false
        for p in data.params {
          if p.is_rest_pattern {
            match p.pattern {
              Some(pat) =>
                self.bind_pattern(
                  pat,
                  rest_val,
                  param_env,
                  LetBinding,
                  ctx=func_ctx,
                )
              None => ()
            }
            bound_rest_pattern = true
            break
          }
        }
        if !bound_rest_pattern {
          param_env.initialize(rest_name, rest_val)
        }
      }
      None => ()
    }
    // Split the body env iff HasParameterExpressions; otherwise body
    // decls hoist directly onto param_env (same semantics as non-Ext).
    let split_scope = has_parameter_expressions(data.params)
    let body_env = if split_scope {
      let be = Environment::new(parent=Some(param_env))
      be.is_var_scope = true
      be
    } else {
      param_env
    }
    let param_source : Environment? = if split_scope {
      Some(param_env)
    } else {
      None
    }
    self.hoist_declarations(
      data.body,
      body_env,
      strict=data.strict,
      param_source~,
    )
    hoist_block_tdz(data.body, body_env)
    let sig = self.exec_stmts(func_ctx, data.body, body_env)
    raise_if_break_continue(sig)
    sig
  } catch {
    e => {
      self.in_nonarrow_param_default_eval = saved_in_default
      self.param_default_eval_var_conflicts = saved_param_default_conflicts
      raise e
    }
  }
  self.in_nonarrow_param_default_eval = saved_in_default
  self.param_default_eval_var_conflicts = saved_param_default_conflicts
  result
}

///|
/// Call-mode wrapper applying ES §10.2.1 [[Call]] return rule.
fn Interpreter::bind_ext_params_and_exec_body(
  self : Interpreter,
  data : FuncDataExt,
  args : Array[Value],
  param_env : Environment,
  func_ctx : ExecContext,
  is_arrow? : Bool = false,
) -> Value raise Error {
  match
    self.bind_ext_params_and_exec_body_signal(
      data,
      args,
      param_env,
      func_ctx,
      is_arrow~,
    ) {
    ReturnSignal(v) => v
    _ => Undefined
  }
}

///|
/// Resolve PerformEval's super permissions from the current this environment.
/// Ordinary functions install an explicit boundary; arrows do not, so only
/// arrows inherit the surrounding method or constructor's lexical super.
fn current_eval_super_context(env : Environment) -> (Bool, Bool) {
  match env.bindings.get("[[EvalMethodContext]]") {
    Some(binding) =>
      match binding.value {
        Bool(is_method) => (is_method, false)
        _ => (false, false)
      }
    None => {
      if env.bindings.contains("[[ActiveClassFunction]]") {
        return (true, true)
      }
      if env.bindings.contains("[[SuperPrototype]]") ||
        env.bindings.contains("[[InClassFieldInitializer]]") {
        return (true, false)
      }
      match env.parent {
        Some(parent) => current_eval_super_context(parent)
        None => (false, false)
      }
    }
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
pub fn Interpreter::perform_eval(
  self : Interpreter,
  code : String,
  caller_env : Environment,
  direct : Bool,
  caller_strict? : Bool = false,
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
    caller_strict || @static_semantics.has_use_strict(stmts)
  } else {
    @static_semantics.has_use_strict(stmts)
  }
  // Apply static block-scoped redeclaration checks before declaration instantiation.
  self.validate_block_early_errors(stmts, eval_strict)
  // ES262 §19.2.1.1 PerformEval steps 8–14: reject the eval source when it
  // references super/new.target/arguments outside the surrounding context's
  // permitted form. Indirect eval inherits no surrounding context, so all
  // four flags are false and any of the predicates triggers the error.
  // Direct eval looks at the caller's env chain via existing markers.
  let in_function = if direct { caller_env.has("<new.target>") } else { false }
  let (in_method, in_derived_constructor) = if direct {
    current_eval_super_context(caller_env)
  } else {
    (false, false)
  }
  let in_class_field_initializer = if direct {
    caller_env.has("[[InClassFieldInitializer]]")
  } else {
    false
  }
  let scan = scan_eval_contains(stmts)
  if scan.super_call && !in_derived_constructor {
    raise @errors.SyntaxError(
      message="'super' call is not allowed here — eval source contains super() outside a derived class constructor",
    )
  }
  if scan.super_property && !in_method {
    raise @errors.SyntaxError(
      message="'super' property access is not allowed here — eval source contains super.x outside a method",
    )
  }
  if scan.new_target && !in_function {
    raise @errors.SyntaxError(
      message="'new.target' is not allowed outside of a function — eval source contains new.target at the top level",
    )
  }
  if scan.arguments_ref && in_class_field_initializer {
    raise @errors.SyntaxError(
      message="'arguments' is not allowed in a class field initializer — eval source references arguments",
    )
  }
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
  let eval_ctx : ExecContext = { strict: eval_strict, current_generator: None }
  if eval_strict {
    // Strict eval: all declarations stay in the eval scope (isolated)
    self.hoist_declarations(stmts, exec_env, strict=eval_strict)
    hoist_block_tdz(stmts, exec_env)
  } else {
    // EvalDeclarationInstantiation steps 5.a and 5.d:
    // Check for var/lexical conflicts before hoisting.
    let var_names = collect_eval_var_names(stmts)
    // §19.2.1.3 gate (#A.6): a direct eval in a parameter default cannot
    // var-declare names that belong to that call's parameter scope. The
    // precomputed map includes later formals that are not bound yet, and the
    // implicit non-arrow `arguments` binding.
    if direct && self.in_nonarrow_param_default_eval {
      for name in var_names {
        let conflicts = match self.param_default_eval_var_conflicts {
          Some(conflict_names) => conflict_names.contains(name)
          None =>
            match var_env.bindings.get(name) {
              Some(binding) => binding.is_parameter || name == "arguments"
              None => false
            }
        }
        if conflicts {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        }
      }
    }
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
    // Step 5.d (ES §19.2.1.3): walk from the fresh eval lex env (NOT the
    // caller env) up to varEnv exclusive. For indirect eval this is trivially
    // the new eval env rooted at global — the walk runs at most once over
    // exec_env, which holds only the internal reconcile marker. For direct
    // eval the walk crosses caller-side block scopes, catching `let`/`const`
    // conflicts with the incoming var names.
    //
    // Per §B.3.4, catch environments are transparent for this check. Our env
    // model does not distinguish catch envs from other block envs, so that
    // edge case remains a known gap (see agent-todo).
    exec_env.set_marker(EVAL_FUNCTION_RECONCILE_MARKER)
    {
      let mut this_lex = exec_env
      while !this_lex.is_var_scope {
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
    for name in var_names {
      if !var_env.bindings.contains(name) {
        var_env.set_marker(eval_deletable_var_marker(name))
      }
    }
    // Non-strict eval: hoist var/function to the variable environment (leak),
    // then hoist let/const TDZ markers to the eval scope (isolated).
    // `suppress_annex_b_candidates` defers the Annex B walk so we can slot
    // it between var hoisting and TDZ setup, matching §19.2.1.3's ordering.
    self.hoist_declarations(stmts, var_env, suppress_annex_b_candidates=true)
    hoist_block_tdz(stmts, exec_env)
    // Annex B §B.3.2.3: promote eligible block-level FunctionDeclarations
    // to var bindings on `var_env`, skipping names that would clash with an
    // outer lex declaration. Same walker as §B.3.2.1 used for function
    // bodies in `hoist_declarations`.
    if self.annex_b {
      let top_lex = collect_stmts_lex_names(stmts)
      hoist_eval_annex_b_candidates(self, stmts, var_env, top_lex)
    }
  }
  // Execute statements and collect result
  let mut last : Value = Undefined
  for stmt in stmts {
    match self.exec_stmt(eval_ctx, stmt, exec_env) {
      Normal(v) =>
        // Per spec, declarations have empty completion values
        if !is_declaration_stmt(stmt) {
          last = v
        }
      ReturnSignal(_) =>
        raise @errors.SyntaxError(
          message="return statement outside of function",
        )
      sig => raise_if_break_continue(sig)
    }
  }
  last
}

///|
fn Interpreter::eval_call(
  self : Interpreter,
  ctx : ExecContext,
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
        let args = self.eval_args_with_spread(ctx, arg_exprs, env)
        if args.length() == 0 {
          return Undefined
        }
        match args[0] {
          String_(code) =>
            return self.perform_eval(code, env, true, caller_strict=ctx.strict)
          other => return other // non-string argument returns as-is
        }
      }
      // eval has been shadowed by a non-eval binding — call normally
      let args = self.eval_args_with_spread(ctx, arg_exprs, env)
      self.call_value(callee, Undefined, args, loc)
    }
    _ => {
      // Per ES spec (13.3.6.1), evaluate callee/receiver first, then arguments.
      // Grouping ends the optional-chain boundary: (a?.b)() is a plain call on
      // the chain result, not a?.b().  Detect it once so the Optional arms can
      // decide whether a short-circuit returns Undefined or reaches call_value.
      let was_grouped = callee_expr is Grouping(_)
      let unwrapped = unwrap_grouping(callee_expr)
      match unwrapped {
        OptionalCall(inner_callee, inner_args, inner_loc) => {
          // was_grouped=false: a?.b?.()()  — outer call short-circuits too.
          // was_grouped=true:  (a?.b?.())() — grouping ended chain; outer always
          //   runs; if inner short-circuited to Undefined, call_value TypeError.
          let (value, short_circuited) = self.eval_chain_expr(
            ctx,
            OptionalCall(inner_callee, inner_args, inner_loc),
            env,
          )
          if short_circuited && !was_grouped {
            Undefined
          } else {
            let args = self.eval_args_with_spread(ctx, arg_exprs, env)
            self.call_value(value, Undefined, args, loc)
          }
        }
        OptionalMember(obj_expr, prop, mloc) => {
          // was_grouped=false: a?.b() — short-circuit returns Undefined.
          // was_grouped=true:  (a?.b)() — pass Undefined to call_value (TypeError).
          let obj = self.eval_expr(ctx, obj_expr, env)
          match obj {
            Null | Undefined =>
              if was_grouped {
                let args = self.eval_args_with_spread(ctx, arg_exprs, env)
                self.call_value(Undefined, obj, args, loc)
              } else {
                Undefined
              }
            _ => {
              let func_val = self.get_property(obj, prop, mloc)
              let args = self.eval_args_with_spread(ctx, arg_exprs, env)
              self.call_value(func_val, obj, args, loc)
            }
          }
        }
        OptionalComputedMember(obj_expr, key_expr, mloc) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          match obj {
            Null | Undefined =>
              if was_grouped {
                let args = self.eval_args_with_spread(ctx, arg_exprs, env)
                self.call_value(Undefined, obj, args, loc)
              } else {
                Undefined
              }
            _ => {
              let key = self.eval_expr(ctx, key_expr, env)
              let func_val = self.get_computed_property(obj, key, mloc)
              let args = self.eval_args_with_spread(ctx, arg_exprs, env)
              self.call_value(func_val, obj, args, loc)
            }
          }
        }
        // Parser emits OptionalCall, not plain Call, inside optional chains;
        // keep these arms for hand-built ASTs and future parser changes.
        ChainMember(obj_expr, prop, mloc) => {
          let (obj, short_circuited) = self.eval_chain_expr(ctx, obj_expr, env)
          if short_circuited {
            Undefined
          } else {
            let func_val = self.get_property(obj, prop, mloc)
            let args = self.eval_args_with_spread(ctx, arg_exprs, env)
            self.call_value(func_val, obj, args, loc)
          }
        }
        ChainComputedMember(obj_expr, key_expr, mloc) => {
          let (obj, short_circuited) = self.eval_chain_expr(ctx, obj_expr, env)
          if short_circuited {
            Undefined
          } else {
            let key = self.eval_expr(ctx, key_expr, env)
            let func_val = self.get_computed_property(obj, key, mloc)
            let args = self.eval_args_with_spread(ctx, arg_exprs, env)
            self.call_value(func_val, obj, args, loc)
          }
        }
        // For member and super references, grouping preserves the Reference,
        // so ((a.b))() correctly calls with this=a.
        Member(obj_expr, prop, mloc) =>
          match obj_expr {
            Ident("console", _) => {
              let callee = self.eval_member(ctx, obj_expr, prop, env, mloc)
              let args = self.eval_args_with_spread(ctx, arg_exprs, env)
              self.call_value(callee, Undefined, args, loc)
            }
            _ => {
              let obj = self.eval_expr(ctx, obj_expr, env)
              let func_val = self.get_property(obj, prop, mloc)
              let args = self.eval_args_with_spread(ctx, arg_exprs, env)
              self.call_value(func_val, obj, args, loc)
            }
          }
        ComputedMember(obj_expr, key_expr, mloc) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          let key = self.eval_expr(ctx, key_expr, env)
          let func_val = self.get_computed_property(obj, key, mloc)
          let args = self.eval_args_with_spread(ctx, arg_exprs, env)
          self.call_value(func_val, obj, args, loc)
        }
        PrivateMember(obj_expr, name, _) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          let func_val = get_private_member(obj, name, env)
          let args = self.eval_args_with_spread(ctx, arg_exprs, env)
          self.call_value(func_val, obj, args, loc)
        }
        SuperMember(prop, sloc) => {
          let (this_val, func_val) = self.eval_super_property_call_reference(
            env, prop, sloc,
          )
          let args = self.eval_args_with_spread(ctx, arg_exprs, env)
          self.call_value(func_val, this_val, args, loc)
        }
        SuperComputedMember(key_expr, sloc) => {
          let _ = eval_this_value(env)
          let key = self.eval_expr(ctx, key_expr, env)
          let (this_val, func_val) = self.eval_super_computed_call_reference(
            env, key, sloc,
          )
          let args = self.eval_args_with_spread(ctx, arg_exprs, env)
          self.call_value(func_val, this_val, args, loc)
        }
        _ => {
          let callee = self.eval_expr(ctx, callee_expr, env)
          let args = self.eval_args_with_spread(ctx, arg_exprs, env)
          self.call_value(callee, Undefined, args, loc)
        }
      }
    }
  }
}

///|
priv enum CallForwardingDecision {
  Forward(Value, Value, Array[Value])
  PrepareApply(Value, Value, Value)
  NotForwarded
}

///|
// Engine-private provenance for exact runtime-created Arguments objects.
let runtime_arguments_host_slot : HostSlotKey = HostSlotKey::reserve()

///|
fn call_forwarding_args(args : Array[Value]) -> Array[Value] {
  let call_args : Array[Value] = []
  for i = 1; i < args.length(); i = i + 1 {
    call_args.push(args[i])
  }
  call_args
}

///|
fn call_forwarding_decision(
  callee : Value,
  this_val : Value,
  args : Array[Value],
) -> CallForwardingDecision {
  match callee {
    Object(data) =>
      match data.callable {
        // `FuncCallMethod(Undefined)` is the runtime-owned identity for the
        // exact Function.prototype.call intrinsic. Fallback `.call` wrappers
        // capture callable Objects, so their target can never be Undefined.
        Some(FuncCallMethod(Undefined)) => {
          let call_this = if args.length() > 0 { args[0] } else { Undefined }
          Forward(this_val, call_this, call_forwarding_args(args))
        }
        Some(FuncCallMethod(target)) => {
          let call_this = if args.length() > 0 { args[0] } else { Undefined }
          Forward(target, call_this, call_forwarding_args(args))
        }
        // `FuncApplyMethod(Undefined)` is the runtime-owned identity for the
        // exact Function.prototype.apply intrinsic. Its target is the
        // current receiver, just as the exact Function.prototype.call
        // intrinsic above forwards its current receiver.
        Some(FuncApplyMethod(Undefined)) => {
          let call_this = if args.length() > 0 { args[0] } else { Undefined }
          let arg_array = if args.length() > 1 { args[1] } else { Undefined }
          PrepareApply(this_val, call_this, arg_array)
        }
        Some(FuncApplyMethod(target)) => {
          let call_this = if args.length() > 0 { args[0] } else { Undefined }
          let arg_array = if args.length() > 1 { args[1] } else { Undefined }
          PrepareApply(target, call_this, arg_array)
        }
        _ => NotForwarded
      }
    _ => NotForwarded
  }
}

///|
priv enum ApplyArgument {
  Direct(Value)
  Mapped(PropDescriptor)
}

///|
fn dense_array_apply_shape(data : ArrayData) -> Array[ApplyArgument]? {
  let len = array_logical_length(data)
  // A sealed dense list has no length override and therefore cannot expose
  // sparse slots or an arbitrarily large logical length through this path.
  guard len == data.elements.length().to_int64() else { return None }
  let mut i = 0L
  while i < len {
    guard array_index_lookup_result64(data, i) is Present(_) else {
      return None
    }
    i += 1L
  }
  let result : Array[ApplyArgument] = []
  i = 0L
  while i < len {
    match array_index_lookup_result64(data, i) {
      Present(value) => result.push(Direct(value))
      _ => return None
    }
    i += 1L
  }
  Some(result)
}

///|
fn mapped_arguments_accessor(desc : PropDescriptor) -> Bool {
  guard desc.is_accessor else { return false }
  match (desc.getter, desc.setter) {
    (
      Some(
        Object({ callable: Some(NativeCallable("[[MappedArgGetter]]", _)), .. })
      ),
      Some(
        Object({ callable: Some(NativeCallable("[[MappedArgSetter]]", _)), .. })
      ),
    ) => true
    _ => false
  }
}

///|
fn mapped_arguments_value(desc : PropDescriptor) -> Value raise Error {
  match desc.getter {
    Some(
      Object(
        { callable: Some(NativeCallable("[[MappedArgGetter]]", getter)), .. }
      )
    ) => getter([])
    _ => Undefined
  }
}

///|
fn exact_arguments_apply_shape(data : ObjectData) -> Array[ApplyArgument]? {
  // A host slot is the non-forgeable provenance marker installed only by
  // make_arguments_object. The class name is retained as a defensive shape
  // check, but is never used as provenance on its own.
  guard data.class_name == "Arguments" &&
    has_host_slot(data, runtime_arguments_host_slot) else {
    return None
  }
  let length_value = data.bag.properties.get("length")
  let length_desc = data.bag.descriptors.get("length")
  let n = match length_value {
    Some(Number(n)) => n
    _ => return None
  }
  let desc = match length_desc {
    Some(desc) => desc
    _ => return None
  }
  guard !desc.is_accessor &&
    n >= 0.0 &&
    n == n.floor() &&
    n <= JS_MAX_SAFE_INTEGER_DOUBLE else {
    return None
  }
  let length = n.to_int64()
  guard length <= data.bag.properties.length().to_int64() else { return None }
  let mut i = 0L
  while i < length {
    let key = i.to_string()
    match (data.bag.descriptors.get(key), data.bag.properties.get(key)) {
      (Some(desc), Some(_)) if !desc.is_accessor => ()
      (Some(desc), Some(_)) if mapped_arguments_accessor(desc) => ()
      _ => return None
    }
    i += 1L
  }
  let result : Array[ApplyArgument] = []
  i = 0L
  while i < length {
    let key = i.to_string()
    match (data.bag.descriptors.get(key), data.bag.properties.get(key)) {
      (Some(desc), Some(value)) if !desc.is_accessor =>
        result.push(Direct(value))
      (Some(desc), Some(_)) if mapped_arguments_accessor(desc) =>
        result.push(Mapped(desc))
      _ => return None
    }
    i += 1L
  }
  Some(result)
}

///|
fn Interpreter::materialize_apply_shape(
  self : Interpreter,
  shape : Array[ApplyArgument],
) -> Array[Value] raise Error {
  let _ = self
  let result : Array[Value] = []
  for item in shape {
    match item {
      Direct(value) => result.push(value)
      Mapped(desc) => result.push(mapped_arguments_value(desc))
    }
  }
  result
}

///|
fn prepare_apply_shape(
  target : Value,
  arg_array : Value,
) -> Array[ApplyArgument]? raise Error {
  // §20.2.3.1 checks IsCallable before touching argArray. This check also
  // applies when the exact intrinsic is reached through Function#call.
  guard is_callable(target) else {
    raise @errors.TypeError(message="is not a function")
  }
  match arg_array {
    Undefined | Null => Some([])
    Array(data) => dense_array_apply_shape(data)
    Object(data) => exact_arguments_apply_shape(data)
    _ => None
  }
}

///|
fn Interpreter::resolve_call_forwarding(
  self : Interpreter,
  callee : Value,
  this_val : Value,
  args : Array[Value],
) -> (Value, Value, Array[Value]) raise Error {
  let mut current_callee = callee
  let mut current_this_val = this_val
  let mut current_args = args
  for ;; {
    match
      call_forwarding_decision(current_callee, current_this_val, current_args) {
      Forward(next_callee, next_this_val, next_args) => {
        current_callee = next_callee
        current_this_val = next_this_val
        current_args = next_args
      }
      PrepareApply(target, call_this, arg_array) =>
        match prepare_apply_shape(target, arg_array) {
          Some(shape) => {
            let next_args = self.materialize_apply_shape(shape)
            current_callee = target
            current_this_val = call_this
            current_args = next_args
          }
          // Shapes that are observable or unsupported by the sealed-list
          // classifier retain the legacy FuncApplyMethod call below.
          None => break
        }
      NotForwarded => break
    }
  }
  (current_callee, current_this_val, current_args)
}

///|
pub fn Interpreter::call_value(
  self : Interpreter,
  callee : Value,
  this_val : Value,
  args : Array[Value],
  loc : @token.Loc,
) -> Value raise Error {
  let (current_callee, current_this_val, current_args) = self.resolve_call_forwarding(
    callee, this_val, args,
  )
  match
    self.preflight_direct_numeric_recursion_call(
      current_callee, current_this_val, current_args, loc,
    ) {
    Some(preflight) => {
      let registry = self.seal_direct_numeric_recursion_registry(
        preflight, current_callee, current_this_val, current_args, loc,
      )
      let completion = self.run_activation_dispatch_numeric_call(
        DispatchCallRequest(
          callee=current_callee,
          this_value=current_this_val,
          args=current_args,
          loc~,
        ),
        registry,
      )
      return activation_dispatch_root_value(completion) catch {
        ExecutionControlError(StackDepthLimit) as depth_error => {
          let translated = JsException(
            js_error_to_value_with_env(depth_error, Some(self.global)),
          )
          remap_observed_source_failure(
            self.realm_state,
            depth_error,
            translated,
          )
          raise translated
        }
        error => raise error
      }
    }
    None => ()
  }
  // Fast path: skip both realm-proto wrapper layers when every active-override
  // slot is None and every callee stamped proto matches the main realm's (or is
  // absent). Checks every packed realm slot so it is safe even when
  // stamp_function_realm_with sets slots independently or when a non-function
  // override is active.
  if realm_fast_path_allowed(current_callee, self.realm_state) {
    self.call_value_impl(current_callee, current_this_val, current_args, loc)
  } else {
    self.with_active_value(fn() raise {
      with_active_callee_realm_value(self.realm_state, current_callee, fn() raise {
        self.call_value_impl(
          current_callee, current_this_val, current_args, loc,
        )
      })
    })
  }
}

///|
fn box_primitive_call_this(value : Value, realm_state : RealmState) -> Value {
  match value {
    String_(s) => {
      let utf16_units = string_to_utf16(s)
      let properties : Map[String, Value] = {
        "length": Number(utf16_units.length().to_double()),
      }
      let descriptors : Map[String, PropDescriptor] = {
        "length": {
          writable: false,
          enumerable: false,
          configurable: false,
          getter: None,
          setter: None,
          is_accessor: false,
        },
      }
      for i = 0; i < utf16_units.length(); i = i + 1 {
        let key = i.to_string()
        properties[key] = String_(
          String::make(1, utf16_units[i].unsafe_to_char()),
        )
        descriptors[key] = {
          writable: false,
          enumerable: true,
          configurable: false,
          getter: None,
          setter: None,
          is_accessor: false,
        }
      }
      Object({
        bag: {
          properties,
          symbol_properties: Map([]),
          descriptors,
          symbol_descriptors: Map([]),
          internal_slots: Map::from_array([(StringData, String_(s))]),
          host_slots: Map([]),
        },
        prototype: get_string_proto(realm_state=Some(realm_state)),
        callable: None,
        class_name: "String",
        extensible: true,
        arraybuffer_state: None,
      })
    }
    Number(n) =>
      Object({
        bag: {
          properties: Map([]),
          symbol_properties: Map([]),
          descriptors: Map([]),
          symbol_descriptors: Map([]),
          internal_slots: Map::from_array([(NumberData, Number(n))]),
          host_slots: Map([]),
        },
        prototype: get_number_proto(realm_state=Some(realm_state)),
        callable: None,
        class_name: "Number",
        extensible: true,
        arraybuffer_state: None,
      })
    Bool(b) =>
      Object({
        bag: {
          properties: Map([]),
          symbol_properties: Map([]),
          descriptors: Map([]),
          symbol_descriptors: Map([]),
          internal_slots: Map::from_array([(BooleanData, Bool(b))]),
          host_slots: Map([]),
        },
        prototype: get_boolean_proto(realm_state=Some(realm_state)),
        callable: None,
        class_name: "Boolean",
        extensible: true,
        arraybuffer_state: None,
      })
    Symbol(sym) =>
      Object({
        bag: {
          properties: Map([]),
          symbol_properties: Map([]),
          descriptors: Map([]),
          symbol_descriptors: Map([]),
          internal_slots: Map::from_array([(SymbolData, Symbol(sym))]),
          host_slots: Map([]),
        },
        prototype: get_symbol_proto(realm_state=Some(realm_state)),
        callable: None,
        class_name: "Symbol",
        extensible: true,
        arraybuffer_state: None,
      })
    _ => value
  }
}

///|
// Low-level parameter-default gate snapshot, not an exactly-once cleanup
// capability. Call adapters and the dispatch shell must own LIFO restoration.
priv struct SimpleUserFuncParameterGateScope {
  previous_in_nonarrow_param_default_eval : Bool
  previous_param_default_eval_var_conflicts : @set.Set[String]?
}

///|
fn SimpleUserFuncParameterGateScope::SimpleUserFuncParameterGateScope(
  previous_in_nonarrow_param_default_eval~ : Bool,
  previous_param_default_eval_var_conflicts~ : @set.Set[String]?,
) -> SimpleUserFuncParameterGateScope {
  {
    previous_in_nonarrow_param_default_eval,
    previous_param_default_eval_var_conflicts,
  }
}

///|
fn Interpreter::begin_simple_user_func_parameter_gate(
  self : Interpreter,
) -> SimpleUserFuncParameterGateScope {
  let previous_in_nonarrow_param_default_eval = self.in_nonarrow_param_default_eval
  let previous_param_default_eval_var_conflicts = self.param_default_eval_var_conflicts
  self.in_nonarrow_param_default_eval = false
  self.param_default_eval_var_conflicts = None
  SimpleUserFuncParameterGateScope(
    previous_in_nonarrow_param_default_eval~,
    previous_param_default_eval_var_conflicts~,
  )
}

///|
fn Interpreter::finish_simple_user_func_parameter_gate(
  self : Interpreter,
  scope : SimpleUserFuncParameterGateScope,
) -> Unit {
  self.in_nonarrow_param_default_eval = scope.previous_in_nonarrow_param_default_eval
  self.param_default_eval_var_conflicts = scope.previous_param_default_eval_var_conflicts
}

///|
#warnings("-unused_constructor")
priv enum UserFuncThrowTypeErrorSource {
  ResolveInheritedThrowTypeError
  UsePreResolvedThrowTypeError(Value?)
}

///|
// Prepared lexical state only. Body scheduling and execution remain owned by
// the caller so the legacy path does not copy the function's statement array.
priv struct PreparedUserFuncActivation {
  ctx : ExecContext
  env : Environment
}

///|
fn PreparedUserFuncActivation::PreparedUserFuncActivation(
  ctx~ : ExecContext,
  env~ : Environment,
) -> PreparedUserFuncActivation {
  { ctx, env }
}

///|
fn Interpreter::normalize_sloppy_this(
  self : Interpreter,
  this_val : Value,
) -> Value {
  match this_val {
    Undefined | Null => self.global_this
    _ => box_primitive_call_this(this_val, self.realm_state)
  }
}

///|
// Prepare the lexical activation shared by legacy and resumable simple
// UserFunc adapters. The default source may invoke guest code while resolving
// the inherited [[ThrowTypeError]] binding; routing-neutral callers must pass a
// value resolved before admission.
fn Interpreter::prepare_user_func_activation(
  self : Interpreter,
  callee : Value,
  this_val : Value,
  args : Array[Value],
  data : FuncData,
  throw_type_error_source? : UserFuncThrowTypeErrorSource = ResolveInheritedThrowTypeError,
) -> PreparedUserFuncActivation raise Error {
  let func_env = Environment::new(parent=Some(data.closure))
  func_env.is_var_scope = true
  func_env.def_builtin("[[EvalMethodContext]]", Bool(data.is_method))
  let func_strict = data.strict
  let func_ctx : ExecContext = { strict: func_strict, current_generator: None }
  if func_strict {
    // Strict mode: check for duplicate parameters
    check_duplicate_params(data.params)
    // Strict mode: validate parameter names
    for p in data.params {
      @static_semantics.validate_strict_binding_name(p)
    }
  }
  let effective_this = if func_strict {
    this_val
  } else {
    self.normalize_sloppy_this(this_val)
  }
  func_env.def("this", effective_this, LetBinding)
  func_env.def("<new.target>", Undefined, LetBinding)
  for i, param in data.params {
    let val : Value = if i < args.length() { args[i] } else { Undefined }
    // In sloppy mode, duplicate params are allowed; last value wins
    if func_env.bindings.contains(param) {
      func_env.assign(param, val)
    } else {
      func_env.def_parameter(param, val)
    }
  }
  if !params_include_arguments(data.params, None) {
    // Create arguments object unless a formal parameter is named `arguments`.
    let tte_val : Value? = match throw_type_error_source {
      // Preserve the legacy lookup order exactly for ordinary callers.
      ResolveInheritedThrowTypeError =>
        if func_env.has("[[ThrowTypeError]]") {
          Some(func_env.get("[[ThrowTypeError]]"))
        } else {
          None
        }
      // Trusted callers resolve this before entering the routing-neutral path.
      UsePreResolvedThrowTypeError(value) => value
    }
    func_env.def(
      "arguments",
      make_arguments_object(
        self.realm_state,
        self.realm_state.well_known_symbols,
        args,
        callee,
        func_strict,
        throw_type_error=tte_val,
        mapped_names=data.params,
        mapped_env=Some(func_env),
      ),
      VarBinding,
    )
  }
  // Hoist declarations and top-level lexical TDZ markers within the function body.
  self.hoist_declarations(data.body, func_env, strict=func_strict)
  hoist_block_tdz(data.body, func_env)
  if data.has_name_binding {
    match data.name {
      Some(name) =>
        if !func_env.bindings.contains(name) {
          func_env.def(name, callee, FunctionNameBinding)
        }
      None => ()
    }
  }
  PreparedUserFuncActivation(ctx=func_ctx, env=func_env)
}

///|
fn Interpreter::call_value_impl(
  self : Interpreter,
  callee : Value,
  this_val : Value,
  args : Array[Value],
  loc : @token.Loc,
) -> Value raise Error {
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
      if !check_callable(target) {
        raise @errors.TypeError(message="proxy target is not a function")
      }
      let trap = get_proxy_trap(proxy_data, "apply", self)
      match trap {
        Some(trap_fn) => {
          let handler = get_proxy_handler(proxy_data)
          let args_array : Value = make_array(args.copy())
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
          // §19.2.1.3 gate reset (#A.6): any function call entry clears
          // the signal so a nested invocation (e.g. an IIFE in an outer
          // function's param default) does not inherit the outer state.
          let gate_scope = self.begin_simple_user_func_parameter_gate()
          let result : Value = try {
            let prepared = self.prepare_user_func_activation(
              callee, this_val, args, data,
            )
            let exec_result = self.exec_stmts(
              prepared.ctx,
              data.body,
              prepared.env,
            )
            raise_if_break_continue(exec_result)
            match exec_result {
              Normal(_) => Undefined
              ReturnSignal(v) => v
              _ => Undefined
            }
          } catch {
            e => {
              self.finish_simple_user_func_parameter_gate(gate_scope)
              raise e
            }
          }
          self.finish_simple_user_func_parameter_gate(gate_scope)
          result
        }
        Some(ArrowFunc(data)) => {
          // §19.2.1.3 gate reset (#A.6), same rationale as UserFunc above.
          let saved_in_default = self.in_nonarrow_param_default_eval
          let saved_param_default_conflicts = self.param_default_eval_var_conflicts
          self.in_nonarrow_param_default_eval = false
          self.param_default_eval_var_conflicts = None
          let result : Value = try {
            let func_env = Environment::new(parent=Some(data.closure))
            func_env.is_var_scope = true
            let func_ctx : ExecContext = {
              strict: data.strict,
              current_generator: None,
            }
            // Arrow functions do NOT rebind this — use closure's this
            for i, param in data.params {
              let val : Value = if i < args.length() {
                args[i]
              } else {
                Undefined
              }
              func_env.def_parameter(param, val)
            }
            self.hoist_declarations(data.body, func_env, strict=data.strict)
            hoist_block_tdz(data.body, func_env)
            let exec_result = self.exec_stmts(func_ctx, data.body, func_env)
            raise_if_break_continue(exec_result)
            match exec_result {
              Normal(_) => Undefined
              ReturnSignal(v) => v
              _ => Undefined
            }
          } catch {
            e => {
              self.in_nonarrow_param_default_eval = saved_in_default
              self.param_default_eval_var_conflicts = saved_param_default_conflicts
              raise e
            }
          }
          self.in_nonarrow_param_default_eval = saved_in_default
          self.param_default_eval_var_conflicts = saved_param_default_conflicts
          result
        }
        Some(UserFuncExt(data)) => {
          // §15.2.5: for named function expressions, install the self-name
          // on a dedicated func_env sitting between data.closure and
          // param_env, so default expressions that close over param_env
          // can still resolve the name (e.g.
          // `var g = function f(a = () => f) { return a(); }`).
          // Gated on has_name_binding so methods / class methods /
          // function declarations (which also carry a `name`) do NOT get
          // the self-binding — per spec those names live in enclosing
          // envs, not on a per-call funcEnv.
          let self_name_env : Environment = if data.has_name_binding {
            match data.name {
              Some(name) => {
                let ne = Environment::new(parent=Some(data.closure))
                ne.def(name, callee, FunctionNameBinding)
                ne
              }
              None => data.closure
            }
          } else {
            data.closure
          }
          let param_env = Environment::new(parent=Some(self_name_env))
          param_env.is_var_scope = true
          param_env.def_builtin("[[EvalMethodContext]]", Bool(data.is_method))
          let func_strict = data.strict
          let func_ctx : ExecContext = {
            strict: func_strict,
            current_generator: None,
          }
          if func_strict {
            // Strict mode: check for duplicate parameters and reserved names
            check_duplicate_params_ext(data.params, data.rest_param)
            validate_strict_param_binding_names_ext(
              data.params,
              data.rest_param,
            )
          }
          let effective_this = if func_strict {
            this_val
          } else {
            self.normalize_sloppy_this(this_val)
          }
          param_env.def("this", effective_this, LetBinding)
          param_env.def("<new.target>", Undefined, LetBinding)
          if !ext_params_include_arguments(data.params, data.rest_param) {
            // Create arguments object before binding params so defaults can reference it,
            // unless a formal parameter is named `arguments`.
            let tte_val2 : Value? = if param_env.has("[[ThrowTypeError]]") {
              Some(param_env.get("[[ThrowTypeError]]"))
            } else {
              None
            }
            param_env.def(
              "arguments",
              make_arguments_object(
                self.realm_state,
                self.realm_state.well_known_symbols,
                args,
                callee,
                func_strict,
                throw_type_error=tte_val2,
              ),
              VarBinding,
            )
          }
          // Self-name lives on self_name_env; body-local `var/let/const`
          // of the same name naturally shadows via lexical lookup, and a
          // param of the same name sits on param_env which shadows too.
          self.bind_ext_params_and_exec_body(
            data,
            args,
            param_env,
            func_ctx,
            is_arrow=false,
          )
        }
        Some(ArrowFuncExt(data)) => {
          // Arrows skip `arguments`/this/<new.target> install
          // (ThisMode=lexical per §10.2.11 step 18) and have no self-name
          // wrapper — param_env's parent is just `data.closure`.
          let param_env = Environment::new(parent=Some(data.closure))
          param_env.is_var_scope = true
          let func_ctx : ExecContext = {
            strict: data.strict,
            current_generator: None,
          }
          self.bind_ext_params_and_exec_body(
            data,
            args,
            param_env,
            func_ctx,
            is_arrow=true,
          )
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
        Some(FuncCallMethod(_)) =>
          raise @errors.TypeError(message="is not a function")
        Some(FuncApplyMethod(target)) => {
          let effective_target = if target is Undefined {
            this_val
          } else {
            target
          }
          guard is_callable(effective_target) else {
            raise @errors.TypeError(message="is not a function")
          }
          let call_this = if args.length() > 0 { args[0] } else { Undefined }
          let call_args : Array[Value] = []
          if args.length() > 1 {
            let arg_array = args[1]
            match arg_array {
              Undefined | Null => ()
              _ => {
                // Unsupported shapes retain full CreateListFromArrayLike
                // semantics: reject primitives, then observe length/index
                // through the interpreter so Proxy, accessors, and inherited
                // properties stay visible.
                guard is_object_value(arg_array) else {
                  raise @errors.TypeError(
                    message="CreateListFromArrayLike called on non-object",
                  )
                }
                let arg_len = to_array_like_length_interp(arg_array, self)
                for i = 0L; i < arg_len; i = i + 1L {
                  let element = get_array_like_element_interp(
                    self, arg_array, i,
                  )
                  call_args.push(element)
                }
              }
            }
          }
          self.call_value(effective_target, call_this, call_args, loc)
        }
        Some(MethodCallable(_, func)) => func(this_val, args)
        Some(NativeCallable(_, func)) => func(args)
        Some(NativeCallableWithContext(_, func)) => func(Call, args)
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
        Some(InterpreterCallableWithContext(_, func)) =>
          func(self, Call, this_val, args)
        Some(ExecutorCallable(executable)) =>
          self.run_executor_function(executable, callee, Call, this_val, args)
        Some(NonConstructableInterpreterCallable(_, func)) => func(self, args)
        Some(ConstructorOnlyCallable(name, _)) =>
          raise @errors.TypeError(
            message=name + " constructor cannot be invoked without 'new'",
          )
        Some(ClassConstructor({ name, .. })) =>
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
