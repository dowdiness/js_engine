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
        validate_strict_binding_name(name)
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
        let body_signal = self.exec_stmt(ctx, body, env) catch {
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
          Some(g) => g.loop_env_stack.pop().unwrap()
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
        let body_signal = self.exec_stmt(ctx, body, iter_env) catch {
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
    FuncDecl(name, params, body, _) => {
      validate_function_signature(ctx.strict, Some(name), params, body)
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
          strict: is_function_strict(ctx.strict, body),
          // FunctionDeclaration execution path — name binds in enclosing
          // VarEnvironment, no dedicated funcEnv.
          has_name_binding: false,
          is_method: false,
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
        // Annex B §B.3.3.3: propagate block-level function to outer var scope.
        // The binding is updated only when the hoist pass tagged it — which
        // permits updating reused param/var bindings while leaving genuine
        // lex bindings untouched.
        if self.annex_b && !ctx.strict && !env.is_var_scope {
          let var_env = env.find_var_env()
          match var_env.bindings.get(name) {
            Some(binding) =>
              if binding.annex_b_hoisted {
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
          }
          _ => ()
        }
      }
      let mut completion : Value = Undefined
      while true {
        let body_signal = self.exec_stmt(ctx, body, env) catch {
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
        if !is_truthy(self.eval_expr(ctx, cond, env)) {
          break
        }
      }
      Normal(completion)
    }
    ForInStmt(var_kind, name, obj_expr, body, _) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
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
      // Check if we're resuming inside a generator for-of
      let gen_opt = ctx.current_generator
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
        let iterable = self.eval_expr(ctx, iterable_expr, env)

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
            match iter_data.bag.properties.get("next") {
              Some(next_fn) => next_fn
              None => {
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
          let body_signal = self.exec_stmt(ctx, body, actual_body_env) catch {
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
          None =>
            env.assign(name, value) catch {
              e => {
                close_iterator(self, iterator, loc) catch {
                  _ => ()
                }
                raise e
              }
            }
        }

        // Execute the loop body
        let body_signal = self.exec_stmt(ctx, body, body_env) catch {
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
      let iterable = self.eval_expr(ctx, iterable_expr, env)

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
          match iter_data.bag.properties.get("next") {
            Some(next_fn) => next_fn
            None => {
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
            self.bind_pattern(pattern, value, bind_env, bk, ctx~) catch {
              e => {
                close_iterator(self, iterator, loc) catch {
                  _ => ()
                }
                raise e
              }
            }
          }
          None =>
            self.assign_pattern(ctx, pattern, value, env) catch {
              e => {
                close_iterator(self, iterator, loc) catch {
                  _ => ()
                }
                raise e
              }
            }
        }
        let body_signal = self.exec_stmt(ctx, body, body_env) catch {
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
      let keys = collect_for_in_keys(obj)
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
      let iterable = self.eval_expr(ctx, iterable_expr, env)
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
          match iter_data.bag.properties.get("next") {
            Some(next_fn) => next_fn
            None => {
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
          _ =>
            raise @errors.TypeError(message="Iterator result is not an object")
        }
        if done {
          break
        }
        let body_env = Environment::new(parent=Some(env))
        self.assign_to_expr(ctx, lhs_expr, value, env) catch {
          e => {
            close_iterator(self, iterator, loc) catch {
              _ => ()
            }
            raise e
          }
        }
        let body_signal = self.exec_stmt(ctx, body, body_env) catch {
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
    FuncDeclExt(name, params, rest_param, body, _) => {
      validate_function_signature_ext(
        ctx.strict,
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
          strict: is_function_strict(ctx.strict, body),
          has_name_binding: false,
          is_method: false,
        }
        let func_val = make_func_ext(func_data)
        if env.bindings.contains(name) {
          env.assign(name, func_val)
        } else if should_reconcile_eval_function_decl(env, name) {
          env.assign_var(name, func_val)
        } else {
          env.def(name, func_val, VarBinding)
        }
        // Annex B §B.3.3.3: see matching comment on the FuncDecl arm.
        if self.annex_b && !ctx.strict && !env.is_var_scope {
          let var_env = env.find_var_env()
          match var_env.bindings.get(name) {
            Some(binding) =>
              if binding.annex_b_hoisted {
                binding.value = func_val
              }
            None => ()
          }
        }
        Normal(Undefined)
      }
    }
    GeneratorDecl(name, params, body, _) => {
      validate_function_signature(ctx.strict, Some(name), params, body)
      let gen_func = self.make_generator_function(
        Some(name),
        params,
        None,
        body,
        is_function_strict(ctx.strict, body),
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
        ctx.strict,
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
        is_function_strict(ctx.strict, body),
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
      validate_function_signature(ctx.strict, Some(name), params, body)
      let async_func = self.make_async_function(
        Some(name),
        params,
        None,
        body,
        is_function_strict(ctx.strict, body),
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
      validate_function_signature(ctx.strict, Some(name), params, body)
      let gen_func = self.make_async_generator_function(
        Some(name),
        params,
        None,
        body,
        is_function_strict(ctx.strict, body),
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
    ClassDecl(name, superclass, methods, _) => {
      let class_val = self.create_class(ctx, name, superclass, methods, env)
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
      self.exec_export_named(ctx, decl, specifiers, source, env, loc)
    ExportDefaultDecl(expr, _) => {
      let value = self.eval_expr(ctx, expr, env)
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
            bag: {
              properties: props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: str_proto,
            callable: None,
            class_name: "String",
            extensible: true,
          })
        }
        Number(n) => {
          // Box number primitive to Number wrapper object
          let num_proto = env.get("[[NumberPrototype]]") catch { _ => Null }
          let props : Map[String, Value] = {}
          props["[[PrimitiveValue]]"] = Number(n)
          Object({
            bag: {
              properties: props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: num_proto,
            callable: None,
            class_name: "Number",
            extensible: true,
          })
        }
        Bool(b) => {
          // Box boolean primitive to Boolean wrapper object
          let bool_proto = env.get("[[BooleanPrototype]]") catch { _ => Null }
          let props : Map[String, Value] = {}
          props["[[PrimitiveValue]]"] = Bool(b)
          Object({
            bag: {
              properties: props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: bool_proto,
            callable: None,
            class_name: "Boolean",
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
      self.exec_stmt(ctx, body, with_env)
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
          let ta_len = match data.bag.properties.get("[[ArrayLength]]") {
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
        let sorted = sort_property_keys(data.bag.properties)
        for k in sorted {
          if !seen.contains(k) {
            // Skip internal slots (e.g., [[BooleanData]], [[NumberData]], [[StringData]])
            if k.has_prefix("[[") {
              continue
            }
            seen[k] = true
            let enumerable = match data.bag.descriptors.get(k) {
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
            let enumerable = match data.bag.descriptors.get(k) {
              Some(d) => d.enumerable
              None => true
            }
            seen[k] = true
            if enumerable {
              keys.push(k)
            }
          }
        }
        let sorted = sort_property_keys(data.bag.properties)
        for k in sorted {
          if k.has_prefix("[[") {
            continue
          }
          if !seen.contains(k) {
            let enumerable = match data.bag.descriptors.get(k) {
              Some(d) => d.enumerable
              None => true
            }
            seen[k] = true
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
/// IteratorClose: call iterator.return() if it exists
fn close_iterator(
  interp : Interpreter,
  iterator : Value,
  loc : @token.Loc,
) -> Unit raise Error {
  match iterator {
    Object(data) => {
      // Look for 'return' method on iterator
      let return_fn = match data.bag.properties.get("return") {
        Some(f) => f
        None => {
          // Walk prototype chain
          let mut found : Value = Undefined
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) =>
                match proto_data.bag.properties.get("return") {
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
      // §7.4.10 step 2: GetMethod(iterator, "return") — if absent/undefined/null skip.
      // If present but non-callable, GetMethod throws TypeError (§7.3.9 step 3).
      match return_fn {
        Undefined | Null => ()
        _ =>
          if !is_callable(return_fn) {
            raise @errors.TypeError(message="iterator.return is not a function")
          } else {
            // §7.4.10 step 3c/7: call return(); non-Object result is TypeError.
            let result = interp.call_value(return_fn, iterator, [], loc)
            if !is_object_value(result) {
              raise @errors.TypeError(
                message="Iterator return() must return an object",
              )
            }
          }
      }
    }
    _ => ()
  }
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
    result = self.exec_stmts(ctx, try_body, try_env) catch {
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
              // Bind the catch parameter - supports simple identifier and destructuring
              self.bind_pattern(param, error_value, catch_env, LetBinding, ctx~)
              self.exec_stmts(ctx, body, catch_env) catch {
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
        // Bind the catch parameter - supports simple identifier and destructuring
        self.bind_pattern(param, error_value, catch_env, LetBinding, ctx~)
        result = self.exec_stmts(ctx, body, catch_env) catch {
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
