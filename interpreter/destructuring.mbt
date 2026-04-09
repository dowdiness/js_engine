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
        let v = self.eval_expr(default_expr, env)
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
      self.bind_pattern(inner_pat, final_val, env, bk)
    }
    AssignTarget(expr) =>
      // Member expression targets are only valid in assignment destructuring,
      // not in binding declarations (let/const/var). Delegate to assign_to_expr.
      self.assign_to_expr(expr, value, env)
    ArrayPat(elements, rest) => {
      // Per spec, destructuring null/undefined must throw TypeError
      if value is (Null | Undefined) {
        raise @errors.TypeError(
          message=value.to_string() + " is not iterable (cannot destructure)",
        )
      }
      // Per spec: ArrayBindingPattern : [ ] → no iteration occurs
      if elements.length() == 0 && rest is None {
        return
      }
      // Always use iterator protocol per spec (ArrayBindingPattern uses GetIterator)
      let loc_dstr = @token.Loc::default()
      let iterator_sym_dstr = get_iterator_symbol()
      let iterator_method_dstr = self.get_computed_property(
        value,
        Symbol(iterator_sym_dstr),
        loc_dstr,
      )
      // Get iterator and next method
      let (iterator, next_method) : (Value, Value) = match
        iterator_method_dstr {
        Object(data) =>
          match data.callable {
            Some(_) => {
              let iter = self.call_value(
                iterator_method_dstr,
                value,
                [],
                loc_dstr,
              )
              // Get next method from iterator (walk prototype chain)
              let next_fn : Value = match iter {
                Object(iter_data) =>
                  match iter_data.properties.get("next") {
                    Some(f) => f
                    None => {
                      let mut found : Value = Undefined
                      let mut current = iter_data.prototype
                      while true {
                        match current {
                          Object(proto_data) =>
                            match proto_data.properties.get("next") {
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
                _ => Undefined
              }
              (iter, next_fn)
            }
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
      // Lazily consume iterator values per spec — one next() call per element
      let mut iter_done = match next_method {
        Undefined => true
        _ => false
      }
      for i = 0; i < elements.length(); i = i + 1 {
        // Advance iterator one step for this element position
        let val : Value = if iter_done {
          Undefined
        } else {
          let iter_result = self.call_value(next_method, iterator, [], loc_dstr)
          match iter_result {
            Object(result_data) => {
              let done_val = match result_data.properties.get("done") {
                Some(v) => is_truthy(v)
                None => false
              }
              if done_val {
                iter_done = true
                Undefined
              } else {
                match result_data.properties.get("value") {
                  Some(v) => v
                  None => Undefined
                }
              }
            }
            _ => {
              iter_done = true
              Undefined
            }
          }
        }
        match elements[i] {
          Some(pat) => self.bind_pattern(pat, val, env, bk)
          None => () // elision — value consumed above, just discard
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
              let iter_result = self.call_value(
                next_method,
                iterator,
                [],
                loc_dstr,
              )
              let (done, val) = match iter_result {
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
                _ => (true, Undefined)
              }
              if done {
                break
              }
              rest_elements.push(val)
            }
          }
          self.bind_pattern(
            rest_pat,
            Array({ elements: rest_elements }),
            env,
            bk,
          )
        }
        None =>
          // Per spec: IteratorClose — call iterator.return() if not exhausted
          if iter_done == false {
            match iterator {
              Object(iter_data) =>
                match iter_data.properties.get("return") {
                  Some(return_fn) =>
                    if is_callable(return_fn) {
                      let _ = self.call_value(return_fn, iterator, [], loc_dstr)
                    }
                  None => ()
                }
              _ => ()
            }
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
      let used_keys : Map[String, Bool] = {}
      for prop in props {
        // Evaluate computed key if present, otherwise use static key
        let key_str : String = match prop.computed_key {
          Some(key_expr) => {
            let key_val = self.eval_expr(key_expr, env)
            to_js_string(key_val)
          }
          None => prop.key
        }
        used_keys[key_str] = true
        let val : Value = self.get_property(
          value,
          key_str,
          @token.Loc::default(),
        )
        let final_val : Value = if val is Undefined {
          match prop.default_val {
            Some(default_expr) => {
              let v = self.eval_expr(default_expr, env)
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
        self.bind_pattern(prop.value, final_val, env, bk)
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
              let all_keys : Map[String, Bool] = {}
              data.properties.each(fn(k, _v) { all_keys[k] = true })
              data.descriptors.each(fn(k, _v) { all_keys[k] = true })
              all_keys.each(fn(k, _) raise {
                if !used_keys.contains(k) {
                  let is_enumerable = match data.descriptors.get(k) {
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
              prototype: get_obj_proto(),
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
    IdentPat(name) =>
      env.assign(name, value) catch {
        @errors.ReferenceError(_) =>
          if !self.strict {
            // Sloppy mode: implicit global creation
            self.global.def(name, value, VarBinding)
            self.mirror_to_global(name, value, configurable=true)
          } else {
            raise @errors.ReferenceError(message="\{name} is not defined")
          }
        other => raise other
      }
    DefaultPat(inner_pat, default_expr) => {
      let final_val : Value = if value is Undefined {
        let v = self.eval_expr(default_expr, env)
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
      self.assign_pattern(inner_pat, final_val, env)
    }
    AssignTarget(expr) =>
      // Member expression assignment target: [obj.x] = [1]
      self.assign_to_expr(expr, value, env)
    ArrayPat(elements, rest) => {
      // Per spec, destructuring null/undefined must throw TypeError
      if value is (Null | Undefined) {
        raise @errors.TypeError(
          message=value.to_string() + " is not iterable (cannot destructure)",
        )
      }
      // Per spec: ArrayBindingPattern : [ ] → no iteration occurs
      if elements.length() == 0 && rest is None {
        return
      }
      // Always use iterator protocol per spec (ArrayBindingPattern uses GetIterator)
      let loc_dstr = @token.Loc::default()
      let iterator_sym_dstr = get_iterator_symbol()
      let iterator_method_dstr = self.get_computed_property(
        value,
        Symbol(iterator_sym_dstr),
        loc_dstr,
      )
      // Get iterator and next method
      let (iterator_a, next_method_a) : (Value, Value) = match
        iterator_method_dstr {
        Object(data) =>
          match data.callable {
            Some(_) => {
              let iter = self.call_value(
                iterator_method_dstr,
                value,
                [],
                loc_dstr,
              )
              // Get next method from iterator (walk prototype chain)
              let next_fn : Value = match iter {
                Object(iter_data) =>
                  match iter_data.properties.get("next") {
                    Some(f) => f
                    None => {
                      let mut found : Value = Undefined
                      let mut current = iter_data.prototype
                      while true {
                        match current {
                          Object(proto_data) =>
                            match proto_data.properties.get("next") {
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
                _ => Undefined
              }
              (iter, next_fn)
            }
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
      // Lazily consume iterator values per spec — one next() call per element
      let mut iter_done_a = match next_method_a {
        Undefined => true
        _ => false
      }
      for i = 0; i < elements.length(); i = i + 1 {
        // Advance iterator one step for this element position
        let val : Value = if iter_done_a {
          Undefined
        } else {
          let iter_result = self.call_value(
            next_method_a,
            iterator_a,
            [],
            loc_dstr,
          )
          match iter_result {
            Object(result_data) => {
              let done_val = match result_data.properties.get("done") {
                Some(v) => is_truthy(v)
                None => false
              }
              if done_val {
                iter_done_a = true
                Undefined
              } else {
                match result_data.properties.get("value") {
                  Some(v) => v
                  None => Undefined
                }
              }
            }
            _ => {
              iter_done_a = true
              Undefined
            }
          }
        }
        match elements[i] {
          Some(pat) => self.assign_pattern(pat, val, env)
          None => () // elision — value consumed above, just discard
        }
      }
      // Handle rest pattern: collect remaining iterator values
      match rest {
        Some(rest_pat) => {
          let rest_elements : Array[Value] = []
          if iter_done_a {
            // iterator already exhausted, rest is empty
          } else {
            while true {
              let iter_result = self.call_value(
                next_method_a,
                iterator_a,
                [],
                loc_dstr,
              )
              let (done, val) = match iter_result {
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
                _ => (true, Undefined)
              }
              if done {
                break
              }
              rest_elements.push(val)
            }
          }
          self.assign_pattern(rest_pat, Array({ elements: rest_elements }), env)
        }
        None =>
          // Per spec: IteratorClose — call iterator.return() if not exhausted
          if iter_done_a == false {
            match iterator_a {
              Object(iter_data) =>
                match iter_data.properties.get("return") {
                  Some(return_fn) =>
                    if is_callable(return_fn) {
                      let _ = self.call_value(
                        return_fn,
                        iterator_a,
                        [],
                        loc_dstr,
                      )
                    }
                  None => ()
                }
              _ => ()
            }
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
      let used_keys : Map[String, Bool] = {}
      for prop in props {
        // Evaluate computed key if present, otherwise use static key
        let key_str : String = match prop.computed_key {
          Some(key_expr) => {
            let key_val = self.eval_expr(key_expr, env)
            to_js_string(key_val)
          }
          None => prop.key
        }
        used_keys[key_str] = true
        let val : Value = self.get_property(
          value,
          key_str,
          @token.Loc::default(),
        )
        let final_val : Value = if val is Undefined {
          match prop.default_val {
            Some(default_expr) => {
              let v = self.eval_expr(default_expr, env)
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
        self.assign_pattern(prop.value, final_val, env)
      }
      match rest {
        Some(rest_pat) => {
          let rest_props : Map[String, Value] = {}
          let rest_symbol_props : Map[Int, Value] = {}
          let loc_rest_a = @token.Loc::default()
          match value {
            Object(data) => {
              // CopyDataProperties: copy own enumerable properties, invoking getters
              let all_keys_a : Map[String, Bool] = {}
              data.properties.each(fn(k, _v) { all_keys_a[k] = true })
              data.descriptors.each(fn(k, _v) { all_keys_a[k] = true })
              all_keys_a.each(fn(k, _) raise {
                if !used_keys.contains(k) {
                  let is_enumerable = match data.descriptors.get(k) {
                    Some(desc) => desc.enumerable
                    None => true
                  }
                  if is_enumerable {
                    rest_props[k] = self.get_property(value, k, loc_rest_a)
                  }
                }
              })
              // Also copy enumerable symbol properties
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
              prototype: get_obj_proto(),
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
      env.assign(name, value) catch {
        @errors.ReferenceError(_) =>
          if !self.strict {
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
  catch_param : @ast.Pattern?,
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
              // Bind the catch parameter - supports simple identifier and destructuring
              self.bind_pattern(param, error_value, catch_env, LetBinding)
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
        // Bind the catch parameter - supports simple identifier and destructuring
        self.bind_pattern(param, error_value, catch_env, LetBinding)
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
