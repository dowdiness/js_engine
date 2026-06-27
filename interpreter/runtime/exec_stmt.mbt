///|
/// Returns true when a FunctionDeclaration's name is already present as a
/// `VarBinding` in the current environment — meaning the instantiation/hoisting
/// pass already bound the function value, so the FunctionDeclaration's
/// *execution* step is a no-op. Module environments are also var scopes for
/// module-scoped `var` bindings, and module declaration instantiation
/// pre-initializes top-level function declarations this way.
fn function_decl_is_hoisted_noop(env : Environment, name : String) -> Bool {
  env.is_var_scope &&
  (match env.bindings.get(name) {
    Some(binding) => binding.kind == VarBinding
    None => false
  })
}

///|
/// Bind a FunctionDeclaration's value into `env` per §B.3.3.3 step 2.b.i and
/// the runtime side of §10.2 FunctionDeclarationInstantiation, then propagate
/// the value to the outer var scope when Annex B hoisting tagged it.
///
/// The kind-gated match enforces the §B.3.3.3 conflict-skip invariant: a
/// block-level FunctionDeclaration whose name already binds a `let`, `const`,
/// or `class` in the surrounding scope must NOT overwrite that binding. The
/// hoist pass suppresses the Annex B var-promotion in that case; the runtime
/// must remain a no-op so `let f = 1; if (true) function f(){}` keeps
/// `f === 1`. Shared by FuncDecl and FuncDeclExt — keep it that way so the
/// next bug fix lands once, not twice (see PR #119 Codex review).
fn Interpreter::bind_function_decl_value(
  self : Interpreter,
  ctx : ExecContext,
  env : Environment,
  name : String,
  func_val : Value,
) -> Unit raise Error {
  let existing_kind = match env.bindings.get(name) {
    Some(b) => Some(b.kind)
    None => None
  }
  match existing_kind {
    Some(VarBinding) => env.assign(name, func_val)
    Some(_) => () // §B.3.3.3 conflict: leave outer lex binding intact
    None =>
      if env.has_marker_in_chain(eval_deletable_var_marker(name)) &&
        !env.has_var(name) &&
        env.parent is Some(p) &&
        physical_equal(p, env.find_var_env()) {
        // Top-level eval function whose binding was deleted — skip to
        // avoid recreating it. Block-level functions have a different
        // env.parent (block_env) and proceed normally to create a new
        // block-scoped binding.
        ()
      } else if should_reconcile_eval_function_decl(env, name) {
        env.assign_var(name, func_val)
      } else {
        env.def(name, func_val, VarBinding)
      }
  }
  // Annex B §B.3.3.3: propagate block-level function to outer var scope when
  // the hoist pass tagged the binding `annex_b_hoisted`. The tag is only set
  // on reusable slots (param/var bindings), so genuine lex bindings in the
  // outer scope are never touched here.
  if self.annex_b && !ctx.strict && !env.is_var_scope {
    let var_env = env.find_var_env()
    match var_env.bindings.get(name) {
      Some(binding) => if binding.annex_b_hoisted { binding.value = func_val }
      None => ()
    }
  }
}

///|
const FOR_OF_RESUME_VALUE_BINDING = "[[ForOfResumeValue]]"

///|
/// Collect all binding names from a pattern (IdentPat leaves only).
/// Used to build the TDZ environment for let/const for-of ForDeclaration
/// per spec §14.7.5.12 step 2 (ForIn/OfHeadEvaluation TDZnames).
fn collect_pattern_tdz_names(
  pattern : @ast.Pattern,
  names : Array[String],
) -> Unit {
  match pattern {
    IdentPat(name) => names.push(name)
    DefaultPat(inner, _) => collect_pattern_tdz_names(inner, names)
    AssignTarget(_) => ()
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(pat) => collect_pattern_tdz_names(pat, names)
          None => ()
        }
      }
      match rest {
        Some(pat) => collect_pattern_tdz_names(pat, names)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        collect_pattern_tdz_names(prop.value, names)
      }
      match rest {
        Some(pat) => collect_pattern_tdz_names(pat, names)
        None => ()
      }
    }
  }
}

///|
fn save_for_of_resume_state(
  gen_opt : GeneratorObject?,
  iterator : Value,
  next_method : Value,
  loop_env : Environment,
  yield_base : Int,
) -> Unit {
  match gen_opt {
    Some(g) => {
      g.for_of_iterator = iterator
      g.for_of_next = next_method
      g.for_of_iterator_stack.push(iterator)
      g.for_of_next_stack.push(next_method)
      g.for_of_resume = true
      g.loop_env_stack.push(loop_env)
      g.loop_yield_base_stack.push(yield_base)
    }
    None => ()
  }
}

///|
fn restore_for_of_resume_state(gen_opt : GeneratorObject?) -> (Value, Value) {
  match gen_opt {
    Some(g) => {
      let iterator = g.for_of_iterator_stack.pop().unwrap()
      let next_method = g.for_of_next_stack.pop().unwrap()
      if g.for_of_iterator_stack.length() > 0 {
        let idx = g.for_of_iterator_stack.length() - 1
        g.for_of_iterator = g.for_of_iterator_stack[idx]
        g.for_of_next = g.for_of_next_stack[idx]
        g.for_of_resume = true
      } else {
        g.for_of_iterator = Undefined
        g.for_of_next = Undefined
        g.for_of_resume = false
      }
      (iterator, next_method)
    }
    None => abort("unreachable: for-of resume without generator")
  }
}

///|
fn save_for_of_resume_value(loop_env : Environment, value : Value) -> Unit {
  loop_env.bindings[FOR_OF_RESUME_VALUE_BINDING] = {
    value,
    kind: VarBinding,
    initialized: true,
    annex_b_hoisted: false,
    is_parameter: false,
  }
}

///|
fn take_for_of_resume_value(loop_env : Environment) -> Value? {
  match loop_env.bindings.get(FOR_OF_RESUME_VALUE_BINDING) {
    Some(binding) => {
      let value = binding.value
      let _ = loop_env.bindings.remove(FOR_OF_RESUME_VALUE_BINDING)
      Some(value)
    }
    None => None
  }
}

///|
fn restore_for_of_loop_env(
  gen_opt : GeneratorObject?,
  fallback : Environment,
) -> Environment {
  match gen_opt {
    Some(g) =>
      if g.loop_env_stack.length() > 0 {
        let saved_env = g.loop_env_stack.pop().unwrap()
        match g.loop_yield_base_stack.pop() {
          Some(base) => g.yield_index = base
          None => ()
        }
        saved_env
      } else {
        fallback
      }
    None => fallback
  }
}

///|
fn Interpreter::exec_stmt(
  self : Interpreter,
  ctx : ExecContext,
  stmt : @ast.Stmt,
  env : Environment,
  label? : String? = None,
) -> Signal raise Error {
  match stmt {
    ExprStmt(expr, _) => Normal(self.eval_expr(ctx, expr, env))
    VarDecl(kind, name, init, _) => {
      // Strict mode: cannot use eval/arguments as variable name
      if ctx.strict {
        @static_semantics.validate_strict_binding_name(name)
      }
      let bk : BindingKind = match kind {
        LetKind => LetBinding
        ConstKind => ConstBinding
        VarKind => VarBinding
      }
      let value : Value = match init {
        Some(expr) => {
          let v = self.eval_expr(ctx, expr, env)
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
      } else if bk == VarBinding &&
        env.has_marker_in_chain(eval_deletable_var_marker(name)) {
        // Marker exists — check if the binding was deleted by a prior
        // `delete` in the same eval.
        if env.has_var(name) {
          // Binding still exists: marker is still valid. The hoisted
          // value takes precedence — skip the initializer.
          ()
        } else if init is Some(_) {
          // Binding was deleted but there's an initializer (e.g.
          // `eval("var x; delete x; var x = 1;")`). The initializer was
          // already evaluated. Since the env binding is gone, PutValue
          // creates an implicit global in sloppy mode.
          // In strict mode, throw ReferenceError per §13.3.2.2.
          match env.resolve_binding_env(name) {
            Some(target_env) =>
              target_env.assign_resolved(name, value, ctx.strict) catch {
                e => raise e
              }
            None => {
              if ctx.strict {
                raise @errors.ReferenceError(message="\{name} is not defined")
              }
              self.global.def(name, value, VarBinding)
              self.mirror_to_global(name, value, configurable=true)
            }
          }
        }
        // No init and binding was deleted: bare `var x` after `delete x`
        // does nothing — the declaration was already hoisted and deleted.
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
      self.exec_stmts(ctx, stmts, block_env)
    }
    StmtList(stmts, _) =>
      // Execute statements in same scope (no new environment)
      // Used for comma-separated declarations like: var a, b, c;
      self.exec_stmts(ctx, stmts, env)
    IfStmt(cond, then_branch, else_branch, _) => {
      let cond_val = self.eval_expr(ctx, cond, env)
      if is_truthy(cond_val) {
        self.exec_stmt(ctx, then_branch, env)
      } else {
        match else_branch {
          Some(eb) => self.exec_stmt(ctx, eb, env)
          None => Normal(Undefined)
        }
      }
    }
    WhileStmt(cond, body, _) => {
      let gen_opt = ctx.current_generator
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
            match g.loop_yield_base_stack.pop() {
              Some(base) => g.yield_index = base
              None => ()
            }
          }
          _ => ()
        }
      }
      // Track last completion value for eval completion semantics
      let mut completion : Value = Undefined
      while true {
        if first_iteration {
          first_iteration = false
        } else if !is_truthy(self.eval_expr(ctx, cond, env)) {
          break
        }
        let body_yield_base = match gen_opt {
          Some(g) => g.yield_index
          _ => 0
        }
        let body_signal = self.exec_stmt(ctx, body, env) catch {
          e => {
            if e is YieldSignal(_) {
              match gen_opt {
                Some(g) => {
                  g.loop_env_stack.push(env)
                  g.loop_yield_base_stack.push(body_yield_base)
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
      }
      Normal(completion)
    }
    ForStmt(init, cond, update, body, _) => {
      // Check if we're resuming inside a generator loop
      let gen_opt = ctx.current_generator
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
          Some(g) => {
            let saved_env = g.loop_env_stack.pop().unwrap()
            match g.loop_yield_base_stack.pop() {
              Some(base) => g.yield_index = base
              None => ()
            }
            saved_env
          }
          _ => Environment::new(parent=Some(env))
        }
      } else {
        let e = Environment::new(parent=Some(env))
        match init {
          Some(init_stmt) => {
            let _ = self.exec_stmt(ctx, init_stmt, e)
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
            Some(c) => if !is_truthy(self.eval_expr(ctx, c, for_env)) { break }
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
        let body_yield_base = match gen_opt {
          Some(g) => g.yield_index
          _ => 0
        }
        let body_signal = self.exec_stmt(ctx, body, iter_env) catch {
          e => {
            if e is YieldSignal(_) {
              // Yield inside for loop body — save for_env for resume
              match gen_opt {
                Some(g) => {
                  g.loop_env_stack.push(for_env)
                  g.loop_yield_base_stack.push(body_yield_base)
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
              let _ = self.eval_expr(ctx, u, for_env)
            }
            None => ()
          }
          continue
        }
        match update {
          Some(u) => {
            let _ = self.eval_expr(ctx, u, for_env)
          }
          None => ()
        }
      }
      Normal(completion)
    }
    FuncDecl(name, params, body, _, source_text) => {
      validate_function_signature(ctx.strict, Some(name), params, body)
      // FunctionDeclaration at the top of a var scope is fully handled during
      // hoisting (the func value was already bound there); execution is a
      // no-op. See `function_decl_is_hoisted_noop` + `bind_function_decl_value`.
      if function_decl_is_hoisted_noop(env, name) {
        Normal(Undefined)
      } else {
        let func_data : FuncData = {
          name: Some(name),
          params,
          body,
          closure: env,
          strict: is_function_strict(ctx.strict, body),
          // FunctionDeclaration execution path — name binds in enclosing
          // VarEnvironment, no dedicated funcEnv.
          has_name_binding: false,
          is_method: false,
          source_text,
        }
        let func_val = make_func(func_data)
        self.bind_function_decl_value(ctx, env, name, func_val)
        Normal(Undefined)
      }
    }
    ReturnStmt(expr, _) => {
      let value : Value = match expr {
        Some(e) => self.eval_expr(ctx, e, env)
        None => Undefined
      }
      ReturnSignal(value)
    }
    BreakStmt(label, _) => BreakSignal(None, label)
    ContinueStmt(label, _) => ContinueSignal(None, label)
    ThrowStmt(expr, _) => {
      let value = self.eval_expr(ctx, expr, env)
      raise JsException(value)
    }
    TryCatchStmt(try_body, catch_param, catch_body, finally_body, _) =>
      self.exec_try_catch(
        ctx, try_body, catch_param, catch_body, finally_body, env,
      )
    SwitchStmt(discriminant, cases, _) => {
      let disc_val = self.eval_expr(ctx, discriminant, env)
      let mut match_idx = -1
      let mut default_idx = -1
      for i = 0; i < cases.length(); i = i + 1 {
        match cases[i].condition {
          Some(test_expr) =>
            if match_idx < 0 {
              let test_val = self.eval_expr(ctx, test_expr, env)
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
          match self.exec_stmt(ctx, stmt, switch_env) {
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
      let gen_opt = ctx.current_generator
      let resuming_loop = match gen_opt {
        Some(g) => g.loop_env_stack.length() > 0
        _ => false
      }
      if resuming_loop {
        match gen_opt {
          Some(g) => {
            let _ = g.loop_env_stack.pop()
            match g.loop_yield_base_stack.pop() {
              Some(base) => g.yield_index = base
              None => ()
            }
          }
          _ => ()
        }
      }
      let mut completion : Value = Undefined
      while true {
        let body_yield_base = match gen_opt {
          Some(g) => g.yield_index
          _ => 0
        }
        let body_signal = self.exec_stmt(ctx, body, env) catch {
          e => {
            if e is YieldSignal(_) {
              match gen_opt {
                Some(g) => {
                  g.loop_env_stack.push(env)
                  g.loop_yield_base_stack.push(body_yield_base)
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
          ContinueSignal(v, None) => completion = v.unwrap_or(completion)
          ContinueSignal(cv, Some(l)) =>
            if label == Some(l) {
              completion = cv.unwrap_or(completion)
            } else {
              return ContinueSignal(cv, Some(l))
            }
        }
        if !is_truthy(self.eval_expr(ctx, cond, env)) {
          break
        }
      }
      Normal(completion)
    }
    ForInStmt(var_kind, name, obj_expr, body, _) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let keys = collect_for_in_keys(obj, self)
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
            env.assign_with_strict(name, String_(key), ctx.strict) catch {
              @errors.ReferenceError(_) =>
                if !ctx.strict {
                  self.global.def(name, String_(key), VarBinding)
                  self.mirror_to_global(name, String_(key), configurable=true)
                } else {
                  raise @errors.ReferenceError(message="\{name} is not defined")
                }
              e => raise e
            }
        }
        match self.exec_stmt(ctx, body, body_env) {
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
      let mut loop_binding_env : Environment? = None
      // Check if we're resuming inside a generator for-of
      let gen_opt = ctx.current_generator
      let resuming_for_of = match gen_opt {
        Some(g) => g.for_of_resume
        _ => false
      }
      let (iterator, next_method) = if resuming_for_of {
        // Restore saved iterator state
        restore_for_of_resume_state(gen_opt)
      } else {
        if var_kind is Some(LetKind) || var_kind is Some(ConstKind) {
          let loop_env = Environment::new(parent=Some(env))
          let loop_binding_kind : BindingKind = match var_kind {
            Some(LetKind) => LetBinding
            _ => ConstBinding
          }
          loop_env.def_tdz(name, loop_binding_kind)
          loop_binding_env = Some(loop_env)
        }
        let iterable_env = match loop_binding_env {
          Some(e) => e
          None => env
        }
        let iterable = self.eval_expr(ctx, iterable_expr, iterable_env)

        // Try to get the iterator via Symbol.iterator protocol
        let iterator_sym = self.realm_state.well_known_symbols.iterator
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
              Array(arr) => self.realm_state.make_array_iterator_value(arr)
              String_(s) => self.realm_state.make_string_iterator_value(s)
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

        let nm = self.get_iterator_next_method(it, loc)
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
          let body_env_parent = match loop_binding_env {
            Some(e) => e
            None => env
          }
          let body_env = Environment::new(parent=Some(body_env_parent))
          // We need the loop variable bound. Since we're replaying the body,
          // gen.resuming will handle the yield. But we need the loop variable.
          // It's in the saved loop env stack.
          let resuming_loop = match gen_opt {
            Some(g) => g.loop_env_stack.length() > 0
            _ => false
          }
          let actual_body_env = if resuming_loop {
            match gen_opt {
              Some(g) => {
                let saved_env = g.loop_env_stack.pop().unwrap()
                match g.loop_yield_base_stack.pop() {
                  Some(base) => g.yield_index = base
                  None => ()
                }
                saved_env
              }
              _ => body_env
            }
          } else {
            body_env
          }
          let body_yield_base = match gen_opt {
            Some(g) => g.yield_index
            _ => 0
          }
          let body_signal = self.exec_stmt(ctx, body, actual_body_env) catch {
            e => {
              if e is YieldSignal(_) {
                save_for_of_resume_state(
                  gen_opt, iterator, next_method, actual_body_env, body_yield_base,
                )
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
        let value = match self.iterator_step_value(iterator, next_method, loc) {
          None => break
          Some(value) => value
        }

        // Bind the value to the loop variable
        let body_env_parent = match loop_binding_env {
          Some(e) => e
          None => env
        }
        let body_env = Environment::new(parent=Some(body_env_parent))
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
          None =>
            env.assign_with_strict(name, value, ctx.strict) catch {
              e => {
                close_iterator(self, iterator, loc) catch {
                  _ => ()
                }
                raise e
              }
            }
        }

        // Execute the loop body
        let body_yield_base = match gen_opt {
          Some(g) => g.yield_index
          _ => 0
        }
        let body_signal = self.exec_stmt(ctx, body, body_env) catch {
          e => {
            if e is YieldSignal(_) {
              // Save for-of state for resume
              save_for_of_resume_state(
                gen_opt, iterator, next_method, body_env, body_yield_base,
              )
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
            close_iterator(self, iterator, loc)
            return ReturnSignal(v)
          }
          BreakSignal(v, None) => {
            close_iterator(self, iterator, loc)
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              close_iterator(self, iterator, loc)
              completion = bv.unwrap_or(completion)
              break
            } else {
              close_iterator(self, iterator, loc)
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
              close_iterator(self, iterator, loc)
              return ContinueSignal(cv, Some(l))
            }
        }
      }
      Normal(completion)
    }
    ForInStmtPat(var_kind, pattern, obj_expr, body, _) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let keys = collect_for_in_keys(obj, self)
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
            self.bind_pattern(pattern, String_(key), bind_env, bk, ctx~)
          }
          None => self.assign_pattern(ctx, pattern, String_(key), env)
        }
        match self.exec_stmt(ctx, body, body_env) {
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
      let gen_opt = ctx.current_generator
      let resuming_for_of = match gen_opt {
        Some(g) => g.for_of_resume
        None => false
      }
      let (iterator, next_method) : (Value, Value) = if resuming_for_of {
        restore_for_of_resume_state(gen_opt)
      } else {
        // Per spec §14.7.5.12 ForIn/OfHeadEvaluation step 2: for let/const
        // ForDeclaration, create a TDZ env with the binding names before
        // evaluating the iterable expression. Functions created in the iterable
        // expression that reference these names will see them as uninitialized
        // (ReferenceError on access) rather than seeing the outer binding.
        let iterable_eval_env = match var_kind {
          Some(LetKind | ConstKind) => {
            let tdz_env = Environment::new(parent=Some(env))
            let bk : BindingKind = match var_kind {
              Some(LetKind) => LetBinding
              _ => ConstBinding
            }
            let tdz_names : Array[String] = []
            collect_pattern_tdz_names(pattern, tdz_names)
            for tdz_name in tdz_names {
              tdz_env.def_tdz(tdz_name, bk)
            }
            tdz_env
          }
          _ => env
        }
        let iterable = self.eval_expr(ctx, iterable_expr, iterable_eval_env)

        // Try to get the iterator via Symbol.iterator protocol
        let iterator_sym = self.realm_state.well_known_symbols.iterator
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
              Array(arr) => self.realm_state.make_array_iterator_value(arr)
              String_(s) => self.realm_state.make_string_iterator_value(s)
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

        (iterator, self.get_iterator_next_method(iterator, loc))
      }

      // Iterate using the iterator protocol
      let mut completion : Value = Undefined
      let mut first_resume = resuming_for_of
      while true {
        let (value, body_env, should_bind) : (Value, Environment, Bool) = if first_resume {
          first_resume = false
          let saved_env = restore_for_of_loop_env(
            gen_opt,
            Environment::new(parent=Some(env)),
          )
          match take_for_of_resume_value(saved_env) {
            Some(value) => (value, saved_env, true)
            None => (Undefined, saved_env, false)
          }
        } else {
          let value = match
            self.iterator_step_value(iterator, next_method, loc) {
            None => break
            Some(value) => value
          }
          (value, Environment::new(parent=Some(env)), true)
        }
        if should_bind {
          let binding_yield_base = match gen_opt {
            Some(g) => g.yield_index
            None => 0
          }
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
              self.bind_pattern(pattern, value, bind_env, bk, ctx~) catch {
                e => {
                  if e is YieldSignal(_) {
                    save_for_of_resume_value(body_env, value)
                    save_for_of_resume_state(
                      gen_opt, iterator, next_method, body_env, binding_yield_base,
                    )
                  } else if e is GeneratorReturnSignal(_) {
                    // §7.4.9: return completion — outer loop close error replaces it
                    close_iterator(self, iterator, loc) catch {
                      close_err => raise close_err
                    }
                  } else {
                    // Throw completion — outer close error discarded (§7.4.9 step 4)
                    close_iterator(self, iterator, loc) catch {
                      _ => ()
                    }
                  }
                  raise e
                }
              }
            }
            None =>
              // No exec_stmt-level guard here: the guard lives inside
              // assign_pattern's ArrayPat branch (destructuring.mbt).  On abrupt
              // resume with a stacked dstr iterator, assign_pattern raises from
              // within, which propagates here and triggers the catch block below —
              // closing the outer for-of iterator in the right order (inner first,
              // then outer), mirroring how the Some(kind) → bind_pattern arm works.
              self.assign_pattern(ctx, pattern, value, env) catch {
                e => {
                  if e is YieldSignal(_) {
                    save_for_of_resume_value(body_env, value)
                    save_for_of_resume_state(
                      gen_opt, iterator, next_method, body_env, binding_yield_base,
                    )
                  } else if e is GeneratorReturnSignal(_) {
                    // §7.4.9: return completion — outer loop close error replaces it
                    close_iterator(self, iterator, loc) catch {
                      close_err => raise close_err
                    }
                  } else {
                    // Throw completion — outer close error discarded (§7.4.9 step 4)
                    close_iterator(self, iterator, loc) catch {
                      _ => ()
                    }
                  }
                  raise e
                }
              }
          }
        }
        let body_yield_base = match gen_opt {
          Some(g) => g.yield_index
          None => 0
        }
        let body_signal = self.exec_stmt(ctx, body, body_env) catch {
          e => {
            if e is YieldSignal(_) {
              save_for_of_resume_state(
                gen_opt, iterator, next_method, body_env, body_yield_base,
              )
            } else {
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
            close_iterator(self, iterator, loc)
            return ReturnSignal(v)
          }
          BreakSignal(v, None) => {
            close_iterator(self, iterator, loc)
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              close_iterator(self, iterator, loc)
              completion = bv.unwrap_or(completion)
              break
            } else {
              close_iterator(self, iterator, loc)
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
              close_iterator(self, iterator, loc)
              return ContinueSignal(cv, Some(l))
            }
        }
      }
      Normal(completion)
    }
    ForInExpr(lhs_expr, obj_expr, body, _) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let keys = collect_for_in_keys(obj, self)
      let mut completion : Value = Undefined
      for key in keys {
        let body_env = Environment::new(parent=Some(env))
        self.assign_to_expr(ctx, lhs_expr, String_(key), env)
        match self.exec_stmt(ctx, body, body_env) {
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
      let gen_opt = ctx.current_generator
      let resuming_for_of = match gen_opt {
        Some(g) => g.for_of_resume
        None => false
      }
      let (iterator, next_method) : (Value, Value) = if resuming_for_of {
        restore_for_of_resume_state(gen_opt)
      } else {
        let iterable = self.eval_expr(ctx, iterable_expr, env)
        let iterator_sym = self.realm_state.well_known_symbols.iterator
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
              Array(arr) => self.realm_state.make_array_iterator_value(arr)
              String_(s) => self.realm_state.make_string_iterator_value(s)
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
        (iterator, self.get_iterator_next_method(iterator, loc))
      }
      let mut completion : Value = Undefined
      let mut first_resume = resuming_for_of
      while true {
        let (value, body_env, should_assign) : (Value, Environment, Bool) = if first_resume {
          first_resume = false
          let saved_env = restore_for_of_loop_env(
            gen_opt,
            Environment::new(parent=Some(env)),
          )
          match take_for_of_resume_value(saved_env) {
            Some(value) => (value, saved_env, true)
            None => (Undefined, saved_env, false)
          }
        } else {
          let value = match
            self.iterator_step_value(iterator, next_method, loc) {
            None => break
            Some(value) => value
          }
          (value, Environment::new(parent=Some(env)), true)
        }
        if should_assign {
          let assignment_yield_base = match gen_opt {
            Some(g) => g.yield_index
            None => 0
          }
          self.assign_to_expr(ctx, lhs_expr, value, env) catch {
            e => {
              if e is YieldSignal(_) {
                save_for_of_resume_value(body_env, value)
                save_for_of_resume_state(
                  gen_opt, iterator, next_method, body_env, assignment_yield_base,
                )
              } else {
                close_iterator(self, iterator, loc) catch {
                  _ => ()
                }
              }
              raise e
            }
          }
        }
        let body_yield_base = match gen_opt {
          Some(g) => g.yield_index
          None => 0
        }
        let body_signal = self.exec_stmt(ctx, body, body_env) catch {
          e => {
            if e is YieldSignal(_) {
              save_for_of_resume_state(
                gen_opt, iterator, next_method, body_env, body_yield_base,
              )
            } else {
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
            close_iterator(self, iterator, loc)
            return ReturnSignal(v)
          }
          BreakSignal(v, None) => {
            close_iterator(self, iterator, loc)
            completion = v.unwrap_or(completion)
            break
          }
          BreakSignal(bv, Some(l)) =>
            if label == Some(l) {
              close_iterator(self, iterator, loc)
              completion = bv.unwrap_or(completion)
              break
            } else {
              close_iterator(self, iterator, loc)
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
              close_iterator(self, iterator, loc)
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
      let value = self.eval_expr(ctx, init_expr, env)
      self.bind_pattern(pattern, value, env, bk, ctx~)
      Normal(Undefined)
    }
    FuncDeclExt(name, params, rest_param, body, _, source_text) => {
      validate_function_signature_ext(
        ctx.strict,
        Some(name),
        params,
        rest_param,
        body,
      )
      if function_decl_is_hoisted_noop(env, name) {
        Normal(Undefined)
      } else {
        let func_data : FuncDataExt = {
          name: Some(name),
          params,
          rest_param,
          body,
          closure: env,
          strict: is_function_strict(ctx.strict, body),
          has_name_binding: false,
          is_method: false,
          source_text,
        }
        let func_val = make_func_ext(func_data)
        self.bind_function_decl_value(ctx, env, name, func_val)
        Normal(Undefined)
      }
    }
    GeneratorDecl(name, params, body, _, source_text) => {
      validate_function_signature(ctx.strict, Some(name), params, body)
      if function_decl_is_hoisted_noop(env, name) {
        Normal(Undefined)
      } else {
        let gen_func = self.make_generator_function(
          Some(name),
          params,
          None,
          body,
          is_function_strict(ctx.strict, body),
          env,
          source_text~,
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
    }
    GeneratorDeclExt(name, params, rest_param, body, _, source_text) => {
      validate_function_signature_ext(
        ctx.strict,
        Some(name),
        params,
        rest_param,
        body,
      )
      if function_decl_is_hoisted_noop(env, name) {
        Normal(Undefined)
      } else {
        let gen_func = self.make_generator_function_ext(
          Some(name),
          params,
          rest_param,
          body,
          is_function_strict(ctx.strict, body),
          env,
          source_text~,
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
    }
    AsyncFuncDecl(name, params, body, _, source_text) => {
      validate_function_signature(ctx.strict, Some(name), params, body)
      let async_func = self.make_async_function(
        Some(name),
        params,
        None,
        body,
        is_function_strict(ctx.strict, body),
        env,
        source_text~,
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
    AsyncFuncDeclExt(name, params, rest_param, body, _, source_text) => {
      validate_function_signature_ext(
        ctx.strict,
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
        is_function_strict(ctx.strict, body),
        env,
        source_text~,
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
    AsyncGeneratorDecl(name, params, body, _, source_text) => {
      validate_function_signature(ctx.strict, Some(name), params, body)
      let gen_func = self.make_async_generator_function(
        Some(name),
        params,
        None,
        body,
        is_function_strict(ctx.strict, body),
        env,
        source_text~,
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
    AsyncGeneratorDeclExt(name, params, rest_param, body, _, source_text) => {
      validate_function_signature_ext(
        ctx.strict,
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
        is_function_strict(ctx.strict, body),
        env,
        source_text~,
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
      match self.exec_stmt(ctx, body, env, label=Some(lbl)) {
        BreakSignal(v, Some(l)) =>
          if l == lbl {
            Normal(v.unwrap_or(Undefined))
          } else {
            BreakSignal(v, Some(l))
          }
        other => other
      }
    ClassDecl(name, superclass, methods, _, source_text) => {
      let class_val = self.create_class(
        ctx, name, superclass, methods, env, source_text,
      )
      // Class was hoisted with TDZ, initialize it now
      if env.bindings.contains(name) {
        env.initialize(name, class_val)
      } else {
        env.def(name, class_val, LetBinding)
      }
      Normal(Undefined)
    }
    // ES Module declarations
    ImportDecl(default_import, specifiers, namespace_import, source, _, loc) =>
      self.exec_import(
        default_import, specifiers, namespace_import, source, env, loc,
      )
    ExportNamedDecl(decl, specifiers, source, _, loc) =>
      self.exec_export_named(ctx, decl, specifiers, source, env, loc)
    ExportDefaultDecl(expr, _) => {
      if is_hoisted_default_export_expr(expr) &&
        self.module_exports.contains("default") {
        return Normal(Undefined)
      }
      let value = self.eval_expr(ctx, expr, env)
      if is_anonymous_function_definition(expr) {
        set_function_name(value, "default")
      }
      self.module_exports["default"] = value
      // Named default exports also bind the name locally
      match expr {
        FuncExpr(Some(name), _, _, _, _)
        | FuncExprExt(Some(name), _, _, _, _, _) =>
          if !env.bindings.contains(name) {
            env.def(name, value, LetBinding)
          }
        GeneratorExpr(Some(name), _, _, _, _)
        | GeneratorExprExt(Some(name), _, _, _, _, _) =>
          if !env.bindings.contains(name) {
            env.def(name, value, LetBinding)
          }
        AsyncFuncExpr(Some(name), _, _, _, _)
        | AsyncFuncExprExt(Some(name), _, _, _, _, _) =>
          if !env.bindings.contains(name) {
            env.def(name, value, LetBinding)
          }
        AsyncGeneratorExpr(Some(name), _, _, _, _)
        | AsyncGeneratorExprExt(Some(name), _, _, _, _, _) =>
          if !env.bindings.contains(name) {
            env.def(name, value, LetBinding)
          }
        ClassExpr(Some(name), _, _, _, _) =>
          if !env.bindings.contains(name) {
            env.def(name, value, LetBinding)
          }
        _ => ()
      }
      Normal(Undefined)
    }
    ExportAllDecl(ns_alias, source, _, loc) =>
      self.exec_export_all(ns_alias, source, loc)
    WithStmt(expr, body, _) => {
      // In strict mode, 'with' is always a SyntaxError
      if ctx.strict {
        raise @errors.SyntaxError(
          message="Strict mode code may not include a with statement",
        )
      }
      let raw_obj = self.eval_expr(ctx, expr, env)
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
            bag: {
              properties: props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
              internal_slots: Map::from_array([(PrimitiveValue, String_(s))]),
            },
            prototype: str_proto,
            callable: None,
            class_name: "String",
            extensible: true,
            arraybuffer_state: None,
          })
        }
        Number(n) => {
          // Box number primitive to Number wrapper object
          let num_proto = env.get("[[NumberPrototype]]") catch { _ => Null }
          Object({
            bag: {
              properties: {},
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
              internal_slots: Map::from_array([(PrimitiveValue, Number(n))]),
            },
            prototype: num_proto,
            callable: None,
            class_name: "Number",
            extensible: true,
            arraybuffer_state: None,
          })
        }
        Bool(b) => {
          // Box boolean primitive to Boolean wrapper object
          let bool_proto = env.get("[[BooleanPrototype]]") catch { _ => Null }
          Object({
            bag: {
              properties: {},
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
              internal_slots: Map::from_array([(PrimitiveValue, Bool(b))]),
            },
            prototype: bool_proto,
            callable: None,
            class_name: "Boolean",
            extensible: true,
            arraybuffer_state: None,
          })
        }
        Object(_) => raw_obj
        _ => raw_obj
      }
      // Create an object environment record with live object reference
      // Property lookups/assignments go directly through the object
      let with_env = Environment::new(parent=Some(env))
      with_env.with_object = Some(obj)
      self.exec_stmt(ctx, body, with_env)
    }
  }
}

///|
pub fn collect_for_in_keys(
  obj : Value,
  interp : Interpreter,
) -> Array[String] raise Error {
  let keys : Array[String] = []
  let seen = @set.Set::default()
  let mut current = obj
  while true {
    match current {
      Proxy(proxy_data) => {
        // Invoke [[OwnPropertyKeys]] trap, then filter for enumerable string keys
        let own_keys_val = proxy_own_property_keys(interp, proxy_data)
        let own_keys = match own_keys_val {
          Array(data) => data.elements
          _ => []
        }
        for k in own_keys {
          match k {
            String_(s) =>
              if !seen.contains(s) {
                // Use [[GetOwnPropertyDescriptor]] trap to check enumerability.
                // If the trap returns None the key is not an own property —
                // don't mark it seen so the prototype chain can still surface it.
                let desc_opt = proxy_get_own_property(
                  interp,
                  proxy_data,
                  String_(s),
                )
                match desc_opt {
                  Some((d, _)) => {
                    seen.add(s)
                    if d.enumerable {
                      keys.push(s)
                    }
                  }
                  None => ()
                }
              }
            // Symbol keys are never enumerated in for-in
            _ => ()
          }
        }
        // Walk prototype chain via [[GetPrototypeOf]] trap
        current = proxy_get_prototype_of(interp, proxy_data)
        continue
      }
      Object(data) => {
        // TypedArray: enumerate numeric indices as keys, but only while
        // IntegerIndexedElementGet would report them present. A detached
        // buffer makes every index invalid for [[GetOwnProperty]], so for-in
        // must skip them instead of yielding stale 0..length-1 keys.
        if is_typedarray_class(data.class_name) {
          let ta_len = match data.bag.internal_slots.get(ArrayLength) {
            Some(Number(n)) => n.to_int()
            _ => 0
          }
          for i = 0; i < ta_len; i = i + 1 {
            let k = i.to_string()
            if !seen.contains(k) &&
              (interp.stdlib_hooks.typedarray_is_valid_index)(
                data,
                i,
                interp.realm_state,
              ) {
              seen.add(k)
              keys.push(k)
            }
          }
        }
        let sorted = if data.class_name == "Module" {
          module_namespace_own_string_keys(data)
        } else {
          sort_property_keys(data.bag.properties)
        }
        for k in sorted {
          if !seen.contains(k) {
            seen.add(k)
            let enumerable = if data.class_name == "Module" {
              match interp.get_own_property(Object(data), String_(k)) {
                Some((d, _)) => d.enumerable
                None => false
              }
            } else {
              match data.bag.descriptors.get(k) {
                Some(d) => d.enumerable
                None => true
              }
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
          if data.holes.contains(i) {
            continue
          }
          let k = i.to_string()
          if !seen.contains(k) {
            let enumerable = match data.bag.descriptors.get(k) {
              Some(d) => d.enumerable
              None => true
            }
            seen.add(k)
            if enumerable {
              keys.push(k)
            }
          }
        }
        let sorted = sort_property_keys(data.bag.properties)
        for k in sorted {
          if !seen.contains(k) {
            let enumerable = match data.bag.descriptors.get(k) {
              Some(d) => d.enumerable
              None => true
            }
            seen.add(k)
            if enumerable {
              keys.push(k)
            }
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
    | FuncDecl(_, _, _, _, _)
    | FuncDeclExt(_, _, _, _, _, _)
    | GeneratorDecl(_, _, _, _, _)
    | GeneratorDeclExt(_, _, _, _, _, _)
    | AsyncFuncDecl(_, _, _, _, _)
    | AsyncFuncDeclExt(_, _, _, _, _, _)
    | AsyncGeneratorDecl(_, _, _, _, _)
    | AsyncGeneratorDeclExt(_, _, _, _, _, _)
    | ClassDecl(_, _, _, _, _)
    | ImportDecl(_, _, _, _, _, _)
    | ExportNamedDecl(_, _, _, _, _)
    | ExportDefaultDecl(_, _)
    | ExportAllDecl(_, _, _, _) => true
    _ => false
  }
}

///|
fn Interpreter::exec_stmts(
  self : Interpreter,
  ctx : ExecContext,
  stmts : Array[@ast.Stmt],
  env : Environment,
) -> Signal raise Error {
  let mut last : Value = Undefined
  for stmt in stmts {
    match self.exec_stmt(ctx, stmt, env) {
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
/// §7.4.10 IteratorClose: call iterator.return() if it exists.
///
/// Resolves "return" via the [[Get]] dispatcher (`Interpreter::get_property`)
/// rather than walking `bag.properties` directly, so:
/// - Proxy `get` traps fire on Proxy-wrapped iterators
/// - Accessor `return` properties invoke their getter
/// - Map/Set iterator prototypes (and any non-ObjectData iterator) resolve
///   "return" through the same dispatcher path used by ordinary property access
///
/// Per §7.3.10 GetMethod: undefined/null → skip; non-callable → TypeError.
/// Per §7.4.10 step 6: a non-Object result from `return()` → TypeError.
///
/// This helper does NOT distinguish throw vs non-throw completions — that
/// responsibility lives at the call sites, which wrap the call in
/// `try { … } catch { _ => () }` when the surrounding completion is a throw
/// (so the original error wins per §7.4.10 step 4).
fn close_iterator(
  interp : Interpreter,
  iterator : Value,
  loc : @token.Loc,
) -> Unit raise Error {
  interp.iterator_close(iterator, loc)
}

///|
fn Interpreter::exec_try_catch(
  self : Interpreter,
  ctx : ExecContext,
  try_body : Array[@ast.Stmt],
  catch_param : @ast.Pattern?,
  catch_body : Array[@ast.Stmt]?,
  finally_body : Array[@ast.Stmt]?,
  env : Environment,
) -> Signal raise Error {
  // Check if we're resuming inside a generator at a specific phase
  let gen_opt = ctx.current_generator
  let start_phase = match gen_opt {
    Some(g) =>
      if g.try_resume_phase >= 0 {
        let p = g.try_resume_phase
        g.try_resume_phase = -1 // consume it
        g.yield_index = g.try_resume_yield_base
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
    let try_yield_base = match gen_opt {
      Some(g) => g.yield_index
      _ => 0
    }
    result = self.exec_stmts(ctx, try_body, try_env) catch {
      e =>
        if e is YieldSignal(_) {
          // Yield inside try body — save phase for resume
          match gen_opt {
            Some(g) => {
              g.try_resume_phase = 0
              g.try_resume_yield_base = try_yield_base
            }
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
              // Bind the catch parameter - supports simple identifier and destructuring
              self.bind_pattern(param, error_value, catch_env, LetBinding, ctx~)
              let catch_yield_base = match gen_opt {
                Some(g) => g.yield_index
                _ => 0
              }
              self.exec_stmts(ctx, body, catch_env) catch {
                ce =>
                  if ce is YieldSignal(_) {
                    // Yield inside catch body — save phase and error for resume
                    match gen_opt {
                      Some(g) => {
                        g.try_resume_phase = 1
                        g.try_resume_yield_base = catch_yield_base
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
        // Bind the catch parameter - supports simple identifier and destructuring
        self.bind_pattern(param, error_value, catch_env, LetBinding, ctx~)
        let catch_yield_base = match gen_opt {
          Some(g) => g.yield_index
          _ => 0
        }
        result = self.exec_stmts(ctx, body, catch_env) catch {
          ce =>
            if ce is YieldSignal(_) {
              // Yield inside catch body again — save phase
              match gen_opt {
                Some(g) => {
                  g.try_resume_phase = 1
                  g.try_resume_yield_base = catch_yield_base
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
      let finally_yield_base = match gen_opt {
        Some(g) => g.yield_index
        _ => 0
      }
      let finally_result = self.exec_stmts(
        ctx,
        body,
        Environment::new(parent=Some(env)),
      ) catch {
        fe =>
          if fe is YieldSignal(_) {
            // Yield inside finally body — save phase and pending state for resume
            match gen_opt {
              Some(g) => {
                g.try_resume_phase = 2
                g.try_resume_yield_base = finally_yield_base
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
