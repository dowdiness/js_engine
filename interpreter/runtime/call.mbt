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
      match iter_data.bag.properties.get("next") {
        Some(next_fn) => next_fn
        None => {
          // Walk prototype chain
          let mut found : Value = Undefined
          let mut current = iter_data.prototype
          while true {
            match current {
              Object(proto_data) =>
                match proto_data.bag.properties.get("next") {
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
        let done_val = match result_data.bag.properties.get("done") {
          Some(v) => is_truthy(v)
          None => false
        }
        let value_val = match result_data.bag.properties.get("value") {
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
fn Interpreter::bind_ext_params_and_exec_body(
  self : Interpreter,
  data : FuncDataExt,
  args : Array[Value],
  param_env : Environment,
  func_ctx : ExecContext,
) -> Value raise Error {
  // Bind params with defaults
  let mut effective_param_count = 0
  for i = 0; i < data.params.length(); i = i + 1 {
    let param = data.params[i]
    // Skip rest destructuring params - they're bound via rest_param
    if data.rest_param is Some(rn) && param.name == rn {
      continue
    }
    let val : Value = if effective_param_count < args.length() &&
      !(args[effective_param_count] is Undefined) {
      args[effective_param_count]
    } else {
      match param.default_val {
        Some(default_expr) => {
          let v = self.eval_expr(func_ctx, default_expr, param_env)
          // Set function name for anonymous function defaults
          if param.pattern is None &&
            is_anonymous_function_definition(default_expr) {
            set_function_name(v, param.name)
          }
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
    param_env.def_parameter(param.name, val)
    // Destructure if pattern param
    match param.pattern {
      Some(pat) =>
        self.bind_pattern(pat, val, param_env, LetBinding, ctx=func_ctx)
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
      let rest_val = make_array(rest_elements)
      param_env.def_parameter(rest_name, rest_val)
      // Apply destructuring pattern if present
      for p in data.params {
        if p.name == rest_name {
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
          break
        }
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
  match self.exec_stmts(func_ctx, data.body, body_env) {
    Normal(_) => Undefined
    ReturnSignal(v) => v
    BreakSignal(_, _) =>
      raise @errors.SyntaxError(message="break statement outside of loop")
    ContinueSignal(_, _) =>
      raise @errors.SyntaxError(message="continue statement outside of loop")
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
    caller_strict || has_use_strict(stmts)
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
  let eval_ctx : ExecContext = { strict: eval_strict, current_generator: None }
  if eval_strict {
    // Strict eval: all declarations stay in the eval scope (isolated)
    self.hoist_declarations(stmts, exec_env, strict=eval_strict)
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
    exec_env.def(eval_function_reconcile_marker, Bool(true), LetBinding)
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
      BreakSignal(_, _) =>
        raise @errors.SyntaxError(message="break statement outside of loop")
      ContinueSignal(_, _) =>
        raise @errors.SyntaxError(message="continue statement outside of loop")
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
    _ =>
      // Per ES spec (13.3.6.1), evaluate callee/receiver first, then arguments.
      match callee_expr {
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
        SuperMember(prop, sloc) => {
          // super.method() - look up on super prototype, call with current this
          let super_proto = env.get("[[SuperPrototype]]")
          let func_val = self.get_property(super_proto, prop, sloc)
          let this_val = env.get("this") catch { _ => Undefined }
          let args = self.eval_args_with_spread(ctx, arg_exprs, env)
          self.call_value(func_val, this_val, args, loc)
        }
        SuperComputedMember(key_expr, sloc) => {
          // super[expr]() - look up on super prototype, call with current this
          let super_proto = env.get("[[SuperPrototype]]")
          let key = self.eval_expr(ctx, key_expr, env)
          let func_val = self.get_computed_property(super_proto, key, sloc)
          let this_val = env.get("this") catch { _ => Undefined }
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

///|
pub fn Interpreter::call_value(
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
          let func_env = Environment::new(parent=Some(data.closure))
          func_env.is_var_scope = true
          let func_strict = data.strict
          let func_ctx : ExecContext = {
            strict: func_strict,
            current_generator: None,
          }
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
              func_env.def_parameter(data.params[i], val)
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
          self.hoist_declarations(data.body, func_env, strict=func_strict)
          match data.name {
            Some(name) =>
              if !func_env.bindings.contains(name) {
                func_env.def(name, callee, LetBinding)
              }
            None => ()
          }
          match self.exec_stmts(func_ctx, data.body, func_env) {
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
        }
        Some(ArrowFunc(data)) => {
          let func_env = Environment::new(parent=Some(data.closure))
          func_env.is_var_scope = true
          let func_ctx : ExecContext = {
            strict: data.strict,
            current_generator: None,
          }
          // Arrow functions do NOT rebind this — use closure's this
          for i = 0; i < data.params.length(); i = i + 1 {
            let val : Value = if i < args.length() {
              args[i]
            } else {
              Undefined
            }
            func_env.def_parameter(data.params[i], val)
          }
          self.hoist_declarations(data.body, func_env, strict=data.strict)
          match self.exec_stmts(func_ctx, data.body, func_env) {
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
                ne.def(name, callee, LetBinding)
                ne
              }
              None => data.closure
            }
          } else {
            data.closure
          }
          let param_env = Environment::new(parent=Some(self_name_env))
          param_env.is_var_scope = true
          let func_strict = data.strict
          let func_ctx : ExecContext = {
            strict: func_strict,
            current_generator: None,
          }
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
          param_env.def("this", effective_this, LetBinding)
          param_env.def("<new.target>", Undefined, LetBinding)
          // Create arguments object BEFORE binding params so defaults can reference it
          let tte_val2 : Value? = if param_env.has("[[ThrowTypeError]]") {
            Some(param_env.get("[[ThrowTypeError]]"))
          } else {
            None
          }
          param_env.def(
            "arguments",
            make_arguments_object(
              args,
              callee,
              func_strict,
              throw_type_error=tte_val2,
            ),
            VarBinding,
          )
          // Self-name lives on self_name_env; body-local `var/let/const`
          // of the same name naturally shadows via lexical lookup, and a
          // param of the same name sits on param_env which shadows too.
          self.bind_ext_params_and_exec_body(data, args, param_env, func_ctx)
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
          self.bind_ext_params_and_exec_body(data, args, param_env, func_ctx)
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
