///|
fn Interpreter::destructuring_property_key(
  self : Interpreter,
  ctx : ExecContext,
  prop : @ast.PropPat,
  env : Environment,
) -> Value raise Error {
  match prop.computed_key {
    Some(key_expr) => {
      let key_val = self.eval_expr(ctx, key_expr, env)
      to_property_key(key_val, interp=Some(self))
    }
    None => String_(prop.key)
  }
}

///|
fn destructuring_mark_used_key(
  key : Value,
  string_keys : @set.Set[String],
  symbol_keys : Map[Int, Bool],
) -> Unit {
  match key {
    String_(s) => string_keys.add(s)
    Symbol(sym) => symbol_keys[sym.id] = true
    _ => ()
  }
}

///|
fn Interpreter::bind_pattern(
  self : Interpreter,
  pattern : @ast.Pattern,
  value : Value,
  env : Environment,
  bk : BindingKind,
  ctx~ : ExecContext,
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
        let v = self.eval_expr(ctx, default_expr, env)
        // Per spec, if default is anonymous function and target is identifier, set name
        if is_anonymous_function_definition(default_expr) {
          match inner_pat {
            IdentPat(name) => set_function_name(v, name)
            _ => ()
          }
        }
        v
      } else {
        value
      }
      self.bind_pattern(inner_pat, final_val, env, bk, ctx~)
    }
    AssignTarget(expr) =>
      // Member expression targets are only valid in assignment destructuring,
      // not in binding declarations (let/const/var). Delegate to assign_to_expr.
      self.assign_to_expr(ctx, expr, value, env)
    ArrayPat(elements, rest) => {
      // Per spec, destructuring null/undefined must throw TypeError
      if value is (Null | Undefined) {
        raise @errors.TypeError(
          message=value.to_string() + " is not iterable (cannot destructure)",
        )
      }
      // Always use iterator protocol per spec (ArrayBindingPattern uses GetIterator)
      let loc_dstr = @token.Loc::default()
      // On generator resume with a stacked dstr iterator: abrupt resumes close
      // and signal; normal (NextAction) resumes drain stale entries without
      // calling return() — the replay creates fresh iterators.
      match ctx.current_generator {
        Some(g) if g.dstr_iterator_stack.length() > 0 =>
          match g.resume_action {
            ReturnAction(_) | ThrowAction(_) =>
              self.close_dstr_stack_on_abrupt_resume(g, loc_dstr)
            NextAction =>
              while g.dstr_iterator_stack.length() > 0 {
                let _ = g.dstr_iterator_stack.pop()
              }
          }
        _ => ()
      }
      let iterator_sym_dstr = self.realm_state.well_known_symbols.iterator
      let iterator_method_dstr = self.get_computed_property(
        value,
        Symbol(iterator_sym_dstr),
        loc_dstr,
      )
      let iterator : Value = match iterator_method_dstr {
        Object(data) =>
          match data.callable {
            Some(_) =>
              self.call_value(iterator_method_dstr, value, [], loc_dstr)
            None =>
              raise @errors.TypeError(
                message=value.to_string() +
                  " is not iterable (cannot destructure)",
              )
          }
        _ =>
          raise @errors.TypeError(
            message=value.to_string() + " is not iterable (cannot destructure)",
          )
      }
      // Per spec §7.4.1 GetIterator: next method lookup is part of iterator record
      // construction; its getter is observable even for empty patterns.
      let next_method = self.get_iterator_next_method(iterator, loc_dstr)
      // Per spec: ArrayBindingPattern : [ ] still requires GetIterator + IteratorClose
      if elements.length() == 0 && rest is None {
        self.iterator_close(iterator, loc_dstr)
        return
      }
      // Lazily consume iterator values per spec — one next() call per element
      let mut iter_done = false
      for i = 0; i < elements.length(); i = i + 1 {
        // Advance iterator one step for this element position. Elisions only
        // perform IteratorStep; they must not perform IteratorValue.
        match elements[i] {
          Some(pat) => {
            let val : Value = if iter_done {
              Undefined
            } else {
              match self.iterator_step_result(iterator, next_method, loc_dstr) {
                None => {
                  iter_done = true
                  Undefined
                }
                Some(result) => self.iterator_result_value(result, loc_dstr)
              }
            }
            self.bind_pattern(pat, val, env, bk, ctx~) catch {
              e => {
                if e is YieldSignal(_) {
                  if !iter_done {
                    match ctx.current_generator {
                      Some(g) => g.dstr_iterator_stack.push(iterator)
                      None => ()
                    }
                  }
                } else if !iter_done {
                  self.iterator_close_throw(iterator, loc_dstr)
                }
                raise e
              }
            }
          }
          None =>
            if !iter_done {
              match self.iterator_step_result(iterator, next_method, loc_dstr) {
                None => iter_done = true
                Some(_) => ()
              }
            }
        }
      }
      // Handle rest pattern: collect remaining iterator values
      match rest {
        Some(rest_pat) => {
          let rest_elements : Array[Value] = []
          if iter_done {
            // iterator already exhausted, rest is empty
          } else {
            while true {
              match self.iterator_step_value(iterator, next_method, loc_dstr) {
                None => break
                Some(value) => rest_elements.push(value)
              }
            }
          }
          self.bind_pattern(rest_pat, make_array(rest_elements), env, bk, ctx~)
        }
        None =>
          // Per spec: IteratorClose — call iterator.return() if not exhausted
          if iter_done == false {
            self.iterator_close(iterator, loc_dstr)
          }
      }
    }
    ObjectPat(props, rest) => {
      // Per spec, destructuring null/undefined must throw TypeError
      if value is (Null | Undefined) {
        raise @errors.TypeError(
          message="Cannot destructure " + value.to_string() + " value",
        )
      }
      let used_string_keys = @set.Set::default()
      let used_symbol_keys : Map[Int, Bool] = {}
      for prop in props {
        let property_key = self.destructuring_property_key(ctx, prop, env)
        destructuring_mark_used_key(
          property_key, used_string_keys, used_symbol_keys,
        )
        match prop.value {
          IdentPat(name) =>
            if bk == VarBinding {
              // SingleNameBinding resolves the binding before GetV(value, P),
              // so object-environment HasBinding traps are observable before
              // the source getter or default initializer runs.
              let _ = env.has(name)
            }
          _ => ()
        }
        let val : Value = self.get_computed_property(
          value,
          property_key,
          @token.Loc::default(),
        )
        let final_val : Value = if val is Undefined {
          match prop.default_val {
            Some(default_expr) => {
              let v = self.eval_expr(ctx, default_expr, env)
              // Per spec, SingleNameBinding: if IsAnonymousFunctionDefinition(Initializer), SetFunctionName
              if is_anonymous_function_definition(default_expr) {
                match prop.value {
                  IdentPat(name) => set_function_name(v, name)
                  _ => ()
                }
              }
              v
            }
            None => Undefined
          }
        } else {
          val
        }
        self.bind_pattern(prop.value, final_val, env, bk, ctx~)
      }
      match rest {
        Some(rest_pat) => {
          let rest_props : Map[String, Value] = {}
          let rest_symbol_props : Map[Int, Value] = {}
          let loc_rest = @token.Loc::default()
          match value {
            Object(data) => {
              // CopyDataProperties: copy own enumerable properties, invoking getters
              // First collect all own enumerable string keys (from properties and descriptors)
              let all_keys = @set.Set::default()
              data.bag.properties.each(fn(k, _v) { all_keys.add(k) })
              data.bag.descriptors.each(fn(k, _v) { all_keys.add(k) })
              all_keys.each(fn(k) raise {
                if !used_string_keys.contains(k) {
                  let is_enumerable = match data.bag.descriptors.get(k) {
                    Some(desc) => desc.enumerable
                    None => true
                  }
                  if is_enumerable {
                    // Use get_property to invoke getters
                    rest_props[k] = self.get_property(value, k, loc_rest)
                  }
                }
              })
              // Also copy enumerable symbol properties
              data.bag.symbol_properties.each(fn(k, v) {
                let is_enumerable = match data.bag.symbol_descriptors.get(k) {
                  Some(desc) => desc.enumerable
                  None => true
                }
                if is_enumerable && !used_symbol_keys.contains(k) {
                  rest_symbol_props[k] = v
                }
              })
            }
            _ => ()
          }
          self.bind_pattern(
            rest_pat,
            Object({
              bag: {
                properties: rest_props,
                symbol_properties: rest_symbol_props,
                descriptors: {},
                symbol_descriptors: {},
                internal_slots: {},
              },
              prototype: get_obj_proto(realm_state=Some(self.realm_state)),
              callable: None,
              class_name: "Object",
              extensible: true,
              arraybuffer_state: None,
            }),
            env,
            bk,
            ctx~,
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
  ctx : ExecContext,
  pattern : @ast.Pattern,
  value : Value,
  env : Environment,
) -> Unit raise Error {
  match pattern {
    IdentPat(name) =>
      env.assign_with_strict(name, value, ctx.strict) catch {
        @errors.ReferenceError(message~) =>
          if !ctx.strict && message == "\{name} is not defined" {
            // Sloppy mode: implicit global creation for unbound names only.
            // TDZ errors ("Cannot access before initialization") must propagate.
            self.global.def(name, value, VarBinding)
            self.mirror_to_global(name, value, configurable=true)
          } else {
            raise @errors.ReferenceError(message~)
          }
        other => raise other
      }
    DefaultPat(inner_pat, default_expr) => {
      let final_val : Value = if value is Undefined {
        let v = self.eval_expr(ctx, default_expr, env)
        // Per spec, if default is anonymous function and target is identifier, set name
        if is_anonymous_function_definition(default_expr) {
          match inner_pat {
            IdentPat(name) => set_function_name(v, name)
            _ => ()
          }
        }
        v
      } else {
        value
      }
      self.assign_pattern(ctx, inner_pat, final_val, env)
    }
    AssignTarget(expr) =>
      // Member expression assignment target: [obj.x] = [1]
      self.assign_to_expr(ctx, expr, value, env)
    ArrayPat(elements, rest) => {
      // Per spec, destructuring null/undefined must throw TypeError
      if value is (Null | Undefined) {
        raise @errors.TypeError(
          message=value.to_string() + " is not iterable (cannot destructure)",
        )
      }
      // Always use iterator protocol per spec (ArrayAssignmentPattern uses GetIterator)
      let loc_dstr = @token.Loc::default()
      // On generator resume with a stacked dstr iterator: abrupt resumes close
      // and signal; normal (NextAction) resumes drain stale entries without
      // calling return() — the replay creates fresh iterators.
      match ctx.current_generator {
        Some(g) if g.dstr_iterator_stack.length() > 0 =>
          match g.resume_action {
            ReturnAction(_) | ThrowAction(_) =>
              self.close_dstr_stack_on_abrupt_resume(g, loc_dstr)
            NextAction =>
              while g.dstr_iterator_stack.length() > 0 {
                let _ = g.dstr_iterator_stack.pop()
              }
          }
        _ => ()
      }
      let iterator_sym_dstr = self.realm_state.well_known_symbols.iterator
      let iterator_method_dstr = self.get_computed_property(
        value,
        Symbol(iterator_sym_dstr),
        loc_dstr,
      )
      let iterator_a : Value = match iterator_method_dstr {
        Object(data) =>
          match data.callable {
            Some(_) =>
              self.call_value(iterator_method_dstr, value, [], loc_dstr)
            None =>
              raise @errors.TypeError(
                message=value.to_string() +
                  " is not iterable (cannot destructure)",
              )
          }
        _ =>
          raise @errors.TypeError(
            message=value.to_string() + " is not iterable (cannot destructure)",
          )
      }
      // Per spec §7.4.1 GetIterator: next method lookup is part of iterator record
      // construction; its getter is observable even for empty patterns.
      let next_method_a = self.get_iterator_next_method(iterator_a, loc_dstr)
      // Per spec: ArrayAssignmentPattern : [ ] still requires GetIterator + IteratorClose
      if elements.length() == 0 && rest is None {
        self.iterator_close(iterator_a, loc_dstr)
        return
      }
      // Lazily consume iterator values per spec — one next() call per element.
      // For AssignTarget elements, lref is evaluated BEFORE the iterator step
      // per spec §13.1 (lref-before-IteratorStepValue ordering).
      let mut iter_done_a = false
      for i = 0; i < elements.length(); i = i + 1 {
        // Advance iterator one step for this element position. Elisions only
        // perform IteratorStep; they must not perform IteratorValue.
        match elements[i] {
          Some(pat) => {
            // For AssignTarget patterns, pre-evaluate the lref before consuming
            // from the iterator so that lref errors fire before next() is called.
            let assign_expr : @ast.Expr? = match pat {
              AssignTarget(expr) => Some(expr)
              DefaultPat(AssignTarget(expr), _) => Some(expr)
              _ => None
            }
            match assign_expr {
              Some(expr) => {
                // Phase 1: evaluate lref (may throw before any iterator call)
                let lref = self.eval_lref_of_expr(ctx, expr, env) catch {
                  e => {
                    if e is YieldSignal(_) {
                      if !iter_done_a {
                        match ctx.current_generator {
                          Some(g) => g.dstr_iterator_stack.push(iterator_a)
                          None => ()
                        }
                      }
                    } else if !iter_done_a {
                      self.iterator_close_throw(iterator_a, loc_dstr)
                    }
                    raise e
                  }
                }
                // Phase 2: consume one value from iterator
                let val : Value = if iter_done_a {
                  Undefined
                } else {
                  let step = self.iterator_step_result(
                    iterator_a, next_method_a, loc_dstr,
                  ) catch {
                    e => {
                      self.iterator_close_throw(iterator_a, loc_dstr)
                      raise e
                    }
                  }
                  match step {
                    None => {
                      iter_done_a = true
                      Undefined
                    }
                    Some(result) => self.iterator_result_value(result, loc_dstr)
                  }
                }
                // Phase 3: apply default initializer if element is undefined
                let final_val : Value = match pat {
                  DefaultPat(_, default_expr) =>
                    if val is Undefined {
                      self.eval_expr(ctx, default_expr, env) catch {
                        e => {
                          if e is YieldSignal(_) {
                            if !iter_done_a {
                              match ctx.current_generator {
                                Some(g) =>
                                  g.dstr_iterator_stack.push(iterator_a)
                                None => ()
                              }
                            }
                          } else if !iter_done_a {
                            self.iterator_close_throw(iterator_a, loc_dstr)
                          }
                          raise e
                        }
                      }
                    } else {
                      val
                    }
                  _ => val
                }
                // Phase 4: assign via the pre-evaluated lref
                self.put_lref(ctx, lref, final_val, env) catch {
                  e => {
                    if !iter_done_a && !(e is YieldSignal(_)) {
                      self.iterator_close_throw(iterator_a, loc_dstr)
                    }
                    raise e
                  }
                }
              }
              None => {
                // Non-AssignTarget: consume from iterator, then bind pattern
                let val : Value = if iter_done_a {
                  Undefined
                } else {
                  match
                    self.iterator_step_result(
                      iterator_a, next_method_a, loc_dstr,
                    ) {
                    None => {
                      iter_done_a = true
                      Undefined
                    }
                    Some(result) => self.iterator_result_value(result, loc_dstr)
                  }
                }
                self.assign_pattern(ctx, pat, val, env) catch {
                  e => {
                    if e is YieldSignal(_) {
                      if !iter_done_a {
                        match ctx.current_generator {
                          Some(g) => g.dstr_iterator_stack.push(iterator_a)
                          None => ()
                        }
                      }
                    } else if !iter_done_a {
                      self.iterator_close_throw(iterator_a, loc_dstr)
                    }
                    raise e
                  }
                }
              }
            }
          }
          None =>
            if !iter_done_a {
              match
                self.iterator_step_result(iterator_a, next_method_a, loc_dstr) {
                None => iter_done_a = true
                Some(_) => ()
              }
            }
        }
      }
      // Handle rest pattern: collect remaining iterator values.
      // For AssignTarget rest, lref is evaluated BEFORE consuming rest values.
      match rest {
        Some(AssignTarget(expr)) => {
          // Pre-evaluate lref before consuming rest values from iterator
          let lref = self.eval_lref_of_expr(ctx, expr, env) catch {
            e => {
              if e is YieldSignal(_) {
                if !iter_done_a {
                  match ctx.current_generator {
                    Some(g) => g.dstr_iterator_stack.push(iterator_a)
                    None => ()
                  }
                }
              } else if !iter_done_a {
                self.iterator_close_throw(iterator_a, loc_dstr)
              }
              raise e
            }
          }
          let rest_elements : Array[Value] = []
          if !iter_done_a {
            while true {
              let step = self.iterator_step_value(
                iterator_a, next_method_a, loc_dstr,
              ) catch {
                e => {
                  self.iterator_close_throw(iterator_a, loc_dstr)
                  raise e
                }
              }
              match step {
                None => {
                  iter_done_a = true
                  break
                }
                Some(v) => rest_elements.push(v)
              }
            }
          }
          self.put_lref(ctx, lref, make_array(rest_elements), env) catch {
            e => {
              if !iter_done_a && !(e is YieldSignal(_)) {
                self.iterator_close_throw(iterator_a, loc_dstr)
              }
              raise e
            }
          }
        }
        Some(rest_pat) => {
          let rest_elements : Array[Value] = []
          if iter_done_a {
            // iterator already exhausted, rest is empty
          } else {
            while true {
              match
                self.iterator_step_value(iterator_a, next_method_a, loc_dstr) {
                None => break
                Some(value) => rest_elements.push(value)
              }
            }
          }
          self.assign_pattern(ctx, rest_pat, make_array(rest_elements), env)
        }
        None =>
          // Per spec: IteratorClose — call iterator.return() if not exhausted
          if iter_done_a == false {
            self.iterator_close(iterator_a, loc_dstr)
          }
      }
    }
    ObjectPat(props, rest) => {
      // Per spec, destructuring null/undefined must throw TypeError
      if value is (Null | Undefined) {
        raise @errors.TypeError(
          message="Cannot destructure " + value.to_string() + " value",
        )
      }
      let used_string_keys = @set.Set::default()
      let used_symbol_keys : Map[Int, Bool] = {}
      for prop in props {
        let property_key = self.destructuring_property_key(ctx, prop, env)
        destructuring_mark_used_key(
          property_key, used_string_keys, used_symbol_keys,
        )
        let val : Value = self.get_computed_property(
          value,
          property_key,
          @token.Loc::default(),
        )
        let final_val : Value = if val is Undefined {
          match prop.default_val {
            Some(default_expr) => {
              let v = self.eval_expr(ctx, default_expr, env)
              // Per spec, SingleNameBinding: if IsAnonymousFunctionDefinition(Initializer), SetFunctionName
              if is_anonymous_function_definition(default_expr) {
                match prop.value {
                  IdentPat(name) => set_function_name(v, name)
                  _ => ()
                }
              }
              v
            }
            None => Undefined
          }
        } else {
          val
        }
        self.assign_pattern(ctx, prop.value, final_val, env)
      }
      match rest {
        Some(rest_pat) => {
          let rest_props : Map[String, Value] = {}
          let rest_symbol_props : Map[Int, Value] = {}
          let loc_rest_a = @token.Loc::default()
          match value {
            Object(data) => {
              // CopyDataProperties: copy own enumerable properties, invoking getters
              let all_keys_a = @set.Set::default()
              data.bag.properties.each(fn(k, _v) { all_keys_a.add(k) })
              data.bag.descriptors.each(fn(k, _v) { all_keys_a.add(k) })
              all_keys_a.each(fn(k) raise {
                if !used_string_keys.contains(k) {
                  let is_enumerable = match data.bag.descriptors.get(k) {
                    Some(desc) => desc.enumerable
                    None => true
                  }
                  if is_enumerable {
                    rest_props[k] = self.get_property(value, k, loc_rest_a)
                  }
                }
              })
              // Also copy enumerable symbol properties
              data.bag.symbol_properties.each(fn(k, v) {
                let is_enumerable = match data.bag.symbol_descriptors.get(k) {
                  Some(desc) => desc.enumerable
                  None => true
                }
                if is_enumerable && !used_symbol_keys.contains(k) {
                  rest_symbol_props[k] = v
                }
              })
            }
            _ => ()
          }
          self.assign_pattern(
            ctx,
            rest_pat,
            Object({
              bag: {
                properties: rest_props,
                symbol_properties: rest_symbol_props,
                descriptors: {},
                symbol_descriptors: {},
                internal_slots: {},
              },
              prototype: get_obj_proto(realm_state=Some(self.realm_state)),
              callable: None,
              class_name: "Object",
              extensible: true,
              arraybuffer_state: None,
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
pub fn Interpreter::eval_destructure_assign(
  self : Interpreter,
  ctx : ExecContext,
  pattern : @ast.Pattern,
  value : Value,
  env : Environment,
) -> Value raise Error {
  self.assign_pattern(ctx, pattern, value, env)
  value
}

///|
fn Interpreter::assign_to_expr(
  self : Interpreter,
  ctx : ExecContext,
  expr : @ast.Expr,
  value : Value,
  env : Environment,
) -> Unit raise Error {
  match expr {
    Ident(name, _) =>
      env.assign_with_strict(name, value, ctx.strict) catch {
        @errors.ReferenceError(message~) =>
          if !ctx.strict && message == "\{name} is not defined" {
            // Sloppy mode: implicit global creation for unbound names only.
            // TDZ errors must propagate as ReferenceError.
            self.global.def(name, value, VarBinding)
            self.mirror_to_global(name, value, configurable=true)
          } else {
            raise @errors.ReferenceError(message~)
          }
        e => raise e
      }
    Member(obj_expr, prop, loc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let _ = self.set_property(obj, prop, value, loc, strict=ctx.strict)
    }
    ComputedMember(obj_expr, key_expr, loc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let key = self.eval_expr(ctx, key_expr, env)
      let _ = self.set_computed_property(
        obj,
        key,
        value,
        loc,
        strict=ctx.strict,
      )
    }
    Call(_, _, _) => {
      if ctx.strict {
        raise @errors.SyntaxError(
          message="Invalid left-hand side in for-in/for-of",
        )
      }
      let _ = self.eval_expr(ctx, expr, env)
      raise @errors.ReferenceError(
        message="Invalid left-hand side in for-in/for-of",
      )
    }
    Grouping(_, _) => {
      let inner = unwrap_groupings(expr)
      match inner {
        Call(_, _, _) => {
          if ctx.strict {
            raise @errors.SyntaxError(
              message="Invalid left-hand side in for-in/for-of",
            )
          }
          let _ = self.eval_expr(ctx, inner, env)
          raise @errors.ReferenceError(
            message="Invalid left-hand side in for-in/for-of",
          )
        }
        _ =>
          raise @errors.ReferenceError(
            message="Invalid left-hand side in for-in/for-of",
          )
      }
    }
    _ =>
      raise @errors.ReferenceError(
        message="Invalid left-hand side in for-in/for-of",
      )
  }
}

// A pre-evaluated assignment reference: the LHS components are resolved eagerly
// before consuming from the iterator, so that lref errors fire before any next() call.

///|
priv enum EvalLRef {
  IdentLRef(String)
  MemberLRef(Value, String, @token.Loc)
  ComputedLRef(Value, Value, @token.Loc)
}

///|
// Evaluate the left-hand side of an assignment target expression without assigning.
// Used to implement spec §13.1 lref-before-IteratorStep ordering in destructuring.
fn Interpreter::eval_lref_of_expr(
  self : Interpreter,
  ctx : ExecContext,
  expr : @ast.Expr,
  env : Environment,
) -> EvalLRef raise Error {
  match expr {
    Ident(name, _) => IdentLRef(name)
    Member(obj_expr, prop, loc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      MemberLRef(obj, prop, loc)
    }
    ComputedMember(obj_expr, key_expr, loc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let key = self.eval_expr(ctx, key_expr, env)
      ComputedLRef(obj, key, loc)
    }
    _ =>
      raise @errors.ReferenceError(
        message="Invalid left-hand side in destructuring assignment",
      )
  }
}

///|
// Assign a value to a pre-evaluated assignment reference.
fn Interpreter::put_lref(
  self : Interpreter,
  ctx : ExecContext,
  lref : EvalLRef,
  value : Value,
  env : Environment,
) -> Unit raise Error {
  match lref {
    IdentLRef(name) =>
      env.assign_with_strict(name, value, ctx.strict) catch {
        @errors.ReferenceError(_) =>
          if !ctx.strict {
            self.global.def(name, value, VarBinding)
            self.mirror_to_global(name, value, configurable=true)
          } else {
            raise @errors.ReferenceError(message="\{name} is not defined")
          }
        e => raise e
      }
    MemberLRef(obj, prop, loc) => {
      let _ = self.set_property(obj, prop, value, loc, strict=ctx.strict)
    }
    ComputedLRef(obj, key, loc) => {
      let _ = self.set_computed_property(
        obj,
        key,
        value,
        loc,
        strict=ctx.strict,
      )
    }
  }
}
