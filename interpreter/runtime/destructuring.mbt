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
      // Per spec: ArrayBindingPattern : [ ] → no iteration occurs
      if elements.length() == 0 && rest is None {
        return
      }
      // Always use iterator protocol per spec (ArrayBindingPattern uses GetIterator)
      let loc_dstr = @token.Loc::default()
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
      let next_method = self.get_iterator_next_method(iterator, loc_dstr)
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
            self.bind_pattern(pat, val, env, bk, ctx~)
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
      let used_keys : Map[String, Bool] = {}
      for prop in props {
        // Evaluate computed key if present, otherwise use static key
        let key_str : String = match prop.computed_key {
          Some(key_expr) => {
            let key_val = self.eval_expr(ctx, key_expr, env)
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
              let all_keys : Map[String, Bool] = {}
              data.bag.properties.each(fn(k, _v) { all_keys[k] = true })
              data.bag.descriptors.each(fn(k, _v) { all_keys[k] = true })
              all_keys.each(fn(k, _) raise {
                if !used_keys.contains(k) {
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
              bag: {
                properties: rest_props,
                symbol_properties: rest_symbol_props,
                descriptors: {},
                symbol_descriptors: {},
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
      env.assign(name, value) catch {
        @errors.ReferenceError(_) =>
          if !ctx.strict {
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
      // Per spec: ArrayBindingPattern : [ ] → no iteration occurs
      if elements.length() == 0 && rest is None {
        return
      }
      // Always use iterator protocol per spec (ArrayBindingPattern uses GetIterator)
      let loc_dstr = @token.Loc::default()
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
      let next_method_a = self.get_iterator_next_method(iterator_a, loc_dstr)
      // Lazily consume iterator values per spec — one next() call per element
      let mut iter_done_a = false
      for i = 0; i < elements.length(); i = i + 1 {
        // Advance iterator one step for this element position. Elisions only
        // perform IteratorStep; they must not perform IteratorValue.
        match elements[i] {
          Some(pat) => {
            let val : Value = if iter_done_a {
              Undefined
            } else {
              match
                self.iterator_step_result(iterator_a, next_method_a, loc_dstr) {
                None => {
                  iter_done_a = true
                  Undefined
                }
                Some(result) => self.iterator_result_value(result, loc_dstr)
              }
            }
            self.assign_pattern(ctx, pat, val, env)
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
      // Handle rest pattern: collect remaining iterator values
      match rest {
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
      let used_keys : Map[String, Bool] = {}
      for prop in props {
        // Evaluate computed key if present, otherwise use static key
        let key_str : String = match prop.computed_key {
          Some(key_expr) => {
            let key_val = self.eval_expr(ctx, key_expr, env)
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
              let all_keys_a : Map[String, Bool] = {}
              data.bag.properties.each(fn(k, _v) { all_keys_a[k] = true })
              data.bag.descriptors.each(fn(k, _v) { all_keys_a[k] = true })
              all_keys_a.each(fn(k, _) raise {
                if !used_keys.contains(k) {
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
                if is_enumerable {
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
      env.assign(name, value) catch {
        @errors.ReferenceError(_) =>
          if !ctx.strict {
            // Implicit global creation in sloppy mode
            self.global.def(name, value, VarBinding)
            self.mirror_to_global(name, value, configurable=true)
          } else {
            raise @errors.ReferenceError(message="\{name} is not defined")
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
    _ =>
      raise @errors.ReferenceError(
        message="Invalid left-hand side in for-in/for-of",
      )
  }
}
