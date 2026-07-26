///|
/// Resolve the target of a `super.x` / `super[k]` access (ES2022 §13.3.7.1
/// MakeSuperPropertyReference).
///
/// Per spec, super resolves via the method's [[HomeObject]] at *call* time by
/// invoking its [[GetPrototypeOf]] internal method. The Proxy arm preserves a
/// possible getPrototypeOf trap before the later property [[Get]]/[[Set]].
/// [[SuperPrototype]] remains only as a fallback for legacy constructor-call
/// environments that do not yet carry a [[HomeObject]].
fn Interpreter::resolve_super_target(
  self : Interpreter,
  env : Environment,
) -> Value raise Error {
  let home = env.get("[[HomeObject]]") catch { _ => Undefined }
  match home {
    Object(_) | Array(_) | Proxy(_) =>
      return object_get_prototype_of(self, home)
    _ => ()
  }
  env.get("[[SuperPrototype]]") catch {
    _ => Undefined
  }
}

///|
fn Interpreter::require_super_target(
  self : Interpreter,
  env : Environment,
  access : String,
  loc : @token.Loc,
) -> Value raise Error {
  match self.resolve_super_target(env) {
    Undefined =>
      raise @errors.ReferenceError(
        message=access +
          " used but no [[SuperPrototype]] in scope at line \{loc.line}",
      )
    Null =>
      raise @errors.TypeError(
        message=format_loc_context("Cannot convert null to object", loc),
      )
    target => target
  }
}

///|
fn pattern_may_contain_yield(pattern : @ast.Pattern) -> Bool {
  @ast.pattern_immediate_children_any(
    pattern, pattern_may_contain_yield, expr_may_contain_yield,
  )
}

///|
fn expr_may_contain_yield(expr : @ast.Expr) -> Bool {
  match expr {
    YieldExpr(_, _, _) => true
    ClassExpr(_, superclass, members, _, _) => {
      let super_has_yield = match superclass {
        Some(expr) => expr_may_contain_yield(expr)
        None => false
      }
      let members_have_yield = members
        .iter()
        .any(fn(mbr) {
          match mbr {
            @ast.ClassMember::Method(m) =>
              expr_may_contain_yield(m.key) || expr_may_contain_yield(m.value)
            @ast.ClassMember::Field(f) => {
              let init_has_yield = match f.initializer {
                Some(init) => expr_may_contain_yield(init)
                None => false
              }
              expr_may_contain_yield(f.key) || init_has_yield
            }
            @ast.ClassMember::StaticBlock(_) => false
          }
        })
      super_has_yield || members_have_yield
    }
    DestructureAssign(pattern, _, _) =>
      pattern_may_contain_yield(pattern) ||
      @ast.expr_immediate_children_any(expr, expr_may_contain_yield)
    _ => @ast.expr_immediate_children_any(expr, expr_may_contain_yield)
  }
}

///|
fn Interpreter::get_symbol_property_from_prototype(
  self : Interpreter,
  receiver : Value,
  proto : Value,
  sym : SymbolData,
  loc : @token.Loc,
) -> Value raise Error {
  self.get_property_key_with_receiver(proto, Symbol(sym), receiver, loc)
}

///|
fn Interpreter::get_computed_property_from_prototype(
  self : Interpreter,
  receiver : Value,
  proto : Value,
  key : Value,
  loc : @token.Loc,
) -> Value raise Error {
  self.get_property_key_with_receiver(proto, key, receiver, loc)
}

///|
pub fn Interpreter::eval_super_property(
  self : Interpreter,
  env : Environment,
  prop : String,
  loc : @token.Loc,
) -> Value raise Error {
  let this_val = eval_this_value(env)
  let super_proto = self.resolve_super_target(env)
  match super_proto {
    Undefined =>
      raise @errors.ReferenceError(
        message="super.prop used but no [[SuperPrototype]] in scope at line \{loc.line}",
      )
    Null =>
      raise @errors.TypeError(
        message="Cannot read property from null super base at line \{loc.line}",
      )
    _ => self.get_property_from_prototype(this_val, super_proto, prop, loc)
  }
}

///|
pub fn Interpreter::eval_super_computed_property(
  self : Interpreter,
  env : Environment,
  key : Value,
  loc : @token.Loc,
) -> Value raise Error {
  let this_val = eval_this_value(env)
  let super_proto = self.resolve_super_target(env)
  match super_proto {
    Undefined =>
      raise @errors.ReferenceError(
        message="super[expr] used but no [[SuperPrototype]] in scope at line \{loc.line}",
      )
    Null =>
      raise @errors.TypeError(
        message="Cannot read property from null super base at line \{loc.line}",
      )
    _ =>
      self.get_computed_property_from_prototype(this_val, super_proto, key, loc)
  }
}

///|
pub fn Interpreter::eval_super_property_call_reference(
  self : Interpreter,
  env : Environment,
  prop : String,
  loc : @token.Loc,
) -> (Value, Value) raise Error {
  let this_val = eval_this_value(env)
  let super_proto = self.resolve_super_target(env)
  match super_proto {
    Undefined =>
      raise @errors.ReferenceError(
        message="super.prop used but no [[SuperPrototype]] in scope at line \{loc.line}",
      )
    Null =>
      raise @errors.TypeError(
        message="Cannot read property from null super base at line \{loc.line}",
      )
    _ => {
      let func_val = self.get_property_from_prototype(
        this_val, super_proto, prop, loc,
      )
      (this_val, func_val)
    }
  }
}

///|
pub fn Interpreter::eval_super_computed_call_reference(
  self : Interpreter,
  env : Environment,
  key : Value,
  loc : @token.Loc,
) -> (Value, Value) raise Error {
  let this_val = eval_this_value(env)
  let super_proto = self.resolve_super_target(env)
  match super_proto {
    Undefined =>
      raise @errors.ReferenceError(
        message="super[expr] used but no [[SuperPrototype]] in scope at line \{loc.line}",
      )
    Null =>
      raise @errors.TypeError(
        message="Cannot read property from null super base at line \{loc.line}",
      )
    _ => {
      let func_val = self.get_computed_property_from_prototype(
        this_val, super_proto, key, loc,
      )
      (this_val, func_val)
    }
  }
}

///|
/// Resolve `this` with the same TDZ-to-derived-constructor error mapping used
/// by expression evaluation. Compiled execution uses this helper instead of
/// treating `this` as an ordinary identifier.
pub fn eval_this_value(env : Environment) -> Value raise Error {
  env.get("this") catch {
    @errors.ReferenceError(message~) => {
      if message.contains("before initialization") {
        raise @errors.ReferenceError(
          message="Must call super constructor in derived class before accessing 'this' or returning from derived constructor",
        )
      }
      Value::Undefined
    }
    other => raise other
  }
}

///|
/// Resolve `new.target` from the current function environment. Scripts and
/// ordinary calls without a constructor binding match the tree-walker fallback
/// to `undefined`.
pub fn eval_new_target_value(env : Environment) -> Value {
  env.get("<new.target>") catch {
    _ => Undefined
  }
}

///|
/// Evaluate an object-literal property's value. For method-shorthand
/// props the returned function must not carry the §15.2.5 self-name
/// binding (methods have no FunctionExpressionName), so we strip it
/// off the resulting FuncData. For `key: value` props the value passes
/// through — a named FunctionExpression there still gets its self-name.
fn Interpreter::eval_prop_value(
  self : Interpreter,
  ctx : ExecContext,
  prop : @ast.Property,
  method_env : Environment,
) -> Value raise Error {
  if prop.is_method {
    match prop.value {
      FuncExpr(name, params, body, _, source_text) => {
        validate_function_signature(ctx.strict, None, params, body)
        let func_data : FuncData = {
          name,
          params,
          body,
          closure: method_env,
          strict: is_function_strict(ctx.strict, body),
          has_name_binding: false,
          is_method: true,
          source_text,
        }
        return make_func(func_data)
      }
      FuncExprExt(name, params, rest_param, body, _, source_text) => {
        validate_function_signature_ext(
          ctx.strict,
          None,
          params,
          rest_param,
          body,
        )
        let func_data : FuncDataExt = {
          name,
          params,
          rest_param,
          body,
          closure: method_env,
          strict: is_function_strict(ctx.strict, body),
          has_name_binding: false,
          is_method: true,
          source_text,
        }
        return make_func_ext(func_data)
      }
      // Generator/async methods: fast path with has_name_binding=false.
      // strip_self_name_binding is a no-op for InterpreterCallable, so we
      // must suppress the binding at creation time (§15.2.5 does not apply
      // to MethodDefinitionEvaluation).
      GeneratorExpr(name, params, body, _, source_text) => {
        validate_function_signature(ctx.strict, None, params, body)
        let strict = is_function_strict(ctx.strict, body)
        return self.make_generator_function(
          name,
          params,
          None,
          body,
          strict,
          method_env,
          has_name_binding=false,
          is_method=true,
          source_text~,
        )
      }
      GeneratorExprExt(name, params, rest_param, body, _, source_text) => {
        validate_function_signature_ext(
          ctx.strict,
          None,
          params,
          rest_param,
          body,
        )
        let strict = is_function_strict(ctx.strict, body)
        return self.make_generator_function_ext(
          name,
          params,
          rest_param,
          body,
          strict,
          method_env,
          has_name_binding=false,
          is_method=true,
          source_text~,
        )
      }
      AsyncFuncExpr(name, params, body, _, source_text) => {
        validate_function_signature(ctx.strict, None, params, body)
        let strict = is_function_strict(ctx.strict, body)
        return self.make_async_function(
          name,
          params,
          None,
          body,
          strict,
          method_env,
          has_name_binding=false,
          is_method=true,
          source_text~,
        )
      }
      AsyncFuncExprExt(name, params, rest_param, body, _, source_text) => {
        validate_function_signature_ext(
          ctx.strict,
          None,
          params,
          rest_param,
          body,
        )
        let strict = is_function_strict(ctx.strict, body)
        return self.make_async_function_ext(
          name,
          params,
          rest_param,
          body,
          strict,
          method_env,
          has_name_binding=false,
          is_method=true,
          source_text~,
        )
      }
      AsyncGeneratorExpr(name, params, body, _, source_text) => {
        validate_function_signature(ctx.strict, None, params, body)
        let strict = is_function_strict(ctx.strict, body)
        return self.make_async_generator_function(
          name,
          params,
          None,
          body,
          strict,
          method_env,
          has_name_binding=false,
          is_method=true,
          source_text~,
        )
      }
      AsyncGeneratorExprExt(name, params, rest_param, body, _, source_text) => {
        validate_function_signature_ext(
          ctx.strict,
          None,
          params,
          rest_param,
          body,
        )
        let strict = is_function_strict(ctx.strict, body)
        return self.make_async_generator_function_ext(
          name,
          params,
          rest_param,
          body,
          strict,
          method_env,
          has_name_binding=false,
          is_method=true,
          source_text~,
        )
      }
      _ => ()
    }
  }
  let v = self.eval_expr(ctx, prop.value, method_env)
  if prop.is_method {
    // Strip §15.2.5 self-name binding (methods have no FunctionExpressionName),
    // then mark as method-shorthand so `new obj.m()` throws TypeError per
    // ES §15.4.5 MethodDefinitionEvaluation + §13.3.5.1 step 5.
    mark_as_method(strip_self_name_binding(v))
  } else {
    v
  }
}

///|
fn object_literal_inferred_name(key : Value) -> String raise Error {
  match key {
    Symbol(sym) =>
      match sym.description {
        Some(description) => "[\{description}]"
        None => ""
      }
    _ => to_js_string(key)
  }
}

///|
fn Interpreter::eval_named_prop_value(
  self : Interpreter,
  ctx : ExecContext,
  prop : @ast.Property,
  method_env : Environment,
  key : Value,
) -> Value raise Error {
  if prop.is_method {
    self.eval_prop_value(ctx, prop, method_env)
  } else {
    self.eval_named_expr(
      ctx,
      prop.value,
      method_env,
      object_literal_inferred_name(key),
    )
  }
}

///|
pub fn apply_object_literal_proto_property(
  target : Value,
  value : Value,
) -> Unit raise Error {
  match target {
    Object(data) =>
      match value {
        Object(_) | Array(_) | Map(_) | Set(_) => data.prototype = value
        Null => data.prototype = Null
        _ => data.bag.properties["__proto__"] = value
      }
    _ =>
      raise @errors.InternalError(
        message="object literal __proto__ target was not an object",
      )
  }
}

///|
pub fn Interpreter::to_object_literal_property_key(
  self : Interpreter,
  key : Value,
) -> Value raise Error {
  to_property_key(key, interp=Some(self))
}

///|
fn frozen_template_data_descriptor(enumerable : Bool) -> PropDescriptor {
  {
    writable: false,
    enumerable,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
fn freeze_template_array(value : Value) -> Unit {
  match value {
    Array(data) => {
      data.extensible = false
      data.length_writable = false
      for i = 0; i < data.elements.length(); i = i + 1 {
        data.bag.descriptors[i.to_string()] = frozen_template_data_descriptor(
          true,
        )
      }
    }
    _ => ()
  }
}

///|
pub fn make_tagged_template_object(quasis : Array[(String, String?)]) -> Value {
  let raw_vals : Array[Value] = []
  let cooked_vals : Array[Value] = []
  for q in quasis {
    raw_vals.push(String_(q.0))
    cooked_vals.push(
      match q.1 {
        Some(s) => String_(s)
        None => Undefined
      },
    )
  }
  let raw_arr = make_array(raw_vals)
  freeze_template_array(raw_arr)
  let template_obj = make_array(cooked_vals)
  match template_obj {
    Array(data) => {
      set_array_named_prop(data, "raw", raw_arr)
      data.bag.descriptors["raw"] = frozen_template_data_descriptor(false)
    }
    _ => ()
  }
  freeze_template_array(template_obj)
  template_obj
}

///|
fn tagged_template_cache_key(
  loc : @token.Loc,
  quasis : Array[(String, String?)],
) -> String {
  let buf = StringBuilder::new()
  buf.write_string(loc.line.to_string())
  buf.write_string(":")
  buf.write_string(loc.col.to_string())
  buf.write_string(":")
  buf.write_string(loc.offset.to_string())
  for q in quasis {
    buf.write_string(":")
    buf.write_string(q.0.length().to_string())
    buf.write_string(":")
    buf.write_string(q.0)
  }
  buf.to_string()
}

///|
// Per-interpreter template-object cache. It is stored as an internal global
// binding so it follows the Interpreter/global lifetime, and all access stays
// behind Interpreter methods rather than a module-level mutable table.
const TEMPLATE_OBJECT_CACHE_BINDING = "[[TemplateObjectCache]]"

///|
fn Interpreter::get_template_object_cache(self : Interpreter) -> ObjectData {
  match self.global.bindings.get(TEMPLATE_OBJECT_CACHE_BINDING) {
    Some(binding) =>
      match binding.value {
        Object(data) => return data
        _ => ()
      }
    None => ()
  }
  let cache_data : ObjectData = {
    bag: PropertyBag(),
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  }
  self.global.bindings[TEMPLATE_OBJECT_CACHE_BINDING] = {
    value: Object(cache_data),
    kind: VarBinding,
    initialized: true,
    annex_b_hoisted: false,
    is_parameter: false,
  }
  cache_data
}

///|
pub fn Interpreter::get_cached_tagged_template_object(
  self : Interpreter,
  key : String,
  quasis : Array[(String, String?)],
) -> Value {
  let cache = self.get_template_object_cache()
  match cache.bag.properties.get(key) {
    Some(value) => value
    None => {
      let value = make_tagged_template_object(quasis)
      cache.bag.properties[key] = value
      value
    }
  }
}

///|
fn Interpreter::get_tagged_template_object(
  self : Interpreter,
  loc : @token.Loc,
  quasis : Array[(String, String?)],
) -> Value {
  self.get_cached_tagged_template_object(
    tagged_template_cache_key(loc, quasis),
    quasis,
  )
}

///|
pub fn apply_object_literal_data_property(
  target : Value,
  key : Value,
  value : Value,
) -> Unit raise Error {
  match target {
    Object(data) =>
      match key {
        Symbol(sym) => {
          let sym_name = match sym.description {
            Some(d) => "[\{d}]"
            None => ""
          }
          set_function_name(value, sym_name)
          data.bag.symbol_properties[sym.id] = value
        }
        _ => {
          let key_str = to_js_string(key)
          set_function_name(value, key_str)
          data.bag.properties[key_str] = value
        }
      }
    _ =>
      raise @errors.InternalError(
        message="object literal data property target was not an object",
      )
  }
}

///|
/// Set a static (compile-time string keyed) data property on an object literal
/// accumulator. Unlike `apply_object_literal_data_property`, this performs no
/// function-name inference: the bytecode lowering emits a separate
/// `SetFunctionName` instruction for static keys, so naming is already handled
/// upstream and must not be re-applied here.
pub fn apply_object_literal_static_data_property(
  target : Value,
  key : String,
  value : Value,
) -> Unit raise Error {
  match target {
    Object(data) => data.bag.properties[key] = value
    _ =>
      raise @errors.InternalError(
        message="object literal static data property target was not an object",
      )
  }
}

///|
/// Append one evaluated element to an array literal accumulator.
pub fn apply_array_literal_element(
  target : Value,
  value : Value,
) -> Unit raise Error {
  match target {
    Array(data) => data.elements.push(value)
    _ =>
      raise @errors.InternalError(
        message="array literal element target was not an array",
      )
  }
}

///|
/// Append already-spread iterable values to an array literal accumulator. The
/// caller is responsible for running the iterator protocol (interpreter
/// semantics); this operation only lands the resulting values into storage.
pub fn apply_array_literal_spread(
  target : Value,
  values : Array[Value],
) -> Unit raise Error {
  match target {
    Array(data) =>
      for value in values {
        data.elements.push(value)
      }
    _ =>
      raise @errors.InternalError(
        message="array literal spread target was not an array",
      )
  }
}

///|
/// Append a single elision (hole) to an array literal accumulator: the index is
/// recorded as a hole and the slot is filled with `undefined` so that `length`
/// advances while `in`/iteration treat the index as absent.
pub fn apply_array_literal_hole(target : Value) -> Unit raise Error {
  match target {
    Array(data) => {
      data.holes[data.elements.length()] = ()
      data.elements.push(Value::Undefined)
    }
    _ =>
      raise @errors.InternalError(
        message="array literal hole target was not an array",
      )
  }
}

///|
fn force_object_literal_accessor_name(accessor : Value, name : String) -> Unit {
  match accessor {
    Object(data) if data.callable is Some(_) =>
      data.bag.properties["name"] = String_(name)
    _ => ()
  }
}

///|
pub fn apply_object_literal_accessor_property(
  target : Value,
  key : Value,
  accessor : Value,
  is_getter : Bool,
) -> Unit raise Error {
  match target {
    Object(data) =>
      match key {
        Symbol(sym) => {
          let accessor_name = match (is_getter, sym.description) {
            (true, Some(d)) => "get [\{d}]"
            (true, None) => "get "
            (false, Some(d)) => "set [\{d}]"
            (false, None) => "set "
          }
          force_object_literal_accessor_name(accessor, accessor_name)
          if !data.bag.symbol_properties.contains(sym.id) {
            data.bag.symbol_properties[sym.id] = Undefined
          }
          let existing = data.bag.symbol_descriptors.get(sym.id)
          data.bag.symbol_descriptors[sym.id] = {
            writable: false,
            enumerable: true,
            configurable: true,
            getter: if is_getter {
              Some(accessor)
            } else {
              match existing {
                Some(desc) => desc.getter
                None => None
              }
            },
            setter: if is_getter {
              match existing {
                Some(desc) => desc.setter
                None => None
              }
            } else {
              Some(accessor)
            },
            is_accessor: true,
          }
        }
        _ => {
          let key_str = to_js_string(key)
          let accessor_name = if is_getter {
            "get " + key_str
          } else {
            "set " + key_str
          }
          force_object_literal_accessor_name(accessor, accessor_name)
          if !data.bag.properties.contains(key_str) {
            data.bag.properties[key_str] = Undefined
          }
          let existing = data.bag.descriptors.get(key_str)
          data.bag.descriptors[key_str] = {
            writable: false,
            enumerable: true,
            configurable: true,
            getter: if is_getter {
              Some(accessor)
            } else {
              match existing {
                Some(desc) => desc.getter
                None => None
              }
            },
            setter: if is_getter {
              match existing {
                Some(desc) => desc.setter
                None => None
              }
            } else {
              Some(accessor)
            },
            is_accessor: true,
          }
        }
      }
    _ =>
      raise @errors.InternalError(
        message="object literal accessor property target was not an object",
      )
  }
}

///|
pub fn Interpreter::copy_object_spread_properties(
  self : Interpreter,
  target : Value,
  source : Value,
  loc : @token.Loc,
) -> Unit raise Error {
  match target {
    Object(_) => ()
    _ =>
      raise @errors.InternalError(
        message="object spread target was not an object",
      )
  }
  // CopyDataProperties: [[OwnPropertyKeys]] → [[GetOwnProperty]] → [[Get]].
  // The target is a fresh ordinary object, so building its owned maps locally
  // is the unobservable CreateDataProperty shell around those dispatchers.
  if source is (Null | Undefined) {
    return
  }
  for key in self.own_property_keys(source) {
    match self.get_own_property(source, key) {
      Some((desc, _)) if desc.enumerable => {
        let value = self.get_computed_property(source, key, loc)
        let succeeded = self.define_own_property(
          target,
          key,
          PartialDescriptor::data_default(value),
          loc,
        )
        if !succeeded {
          raise @errors.TypeError(
            message=format_loc_context("Cannot create data property", loc),
          )
        }
      }
      _ => ()
    }
  }
}

///|
/// If func_val is null/undefined, short-circuit to (Undefined, true).
/// Otherwise evaluate arguments and call with the given receiver.
/// Shared tail for all OptionalCall arms.
fn Interpreter::eval_optional_call_tail(
  self : Interpreter,
  ctx : ExecContext,
  func_val : Value,
  receiver : Value,
  arg_exprs : Array[@ast.Expr],
  env : Environment,
  loc : @token.Loc,
) -> (Value, Bool) raise Error {
  match func_val {
    Null | Undefined => (Undefined, true)
    _ => {
      let args = self.eval_args_with_spread(ctx, arg_exprs, env)
      (self.call_value(func_val, receiver, args, loc), false)
    }
  }
}

///|
fn Interpreter::eval_chain_expr(
  self : Interpreter,
  ctx : ExecContext,
  expr : @ast.Expr,
  env : Environment,
) -> (Value, Bool) raise Error {
  match expr {
    OptionalMember(obj_expr, prop, loc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      match obj {
        Null | Undefined => (Undefined, true)
        _ => (self.get_property(obj, prop, loc), false)
      }
    }
    OptionalComputedMember(obj_expr, key_expr, loc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      match obj {
        Null | Undefined => (Undefined, true)
        _ => {
          let key = self.eval_expr(ctx, key_expr, env)
          (self.get_computed_property(obj, key, loc), false)
        }
      }
    }
    ChainMember(obj_expr, prop, loc) => {
      let (obj, short_circuited) = self.eval_chain_expr(ctx, obj_expr, env)
      if short_circuited {
        (Undefined, true)
      } else {
        (self.get_property(obj, prop, loc), false)
      }
    }
    ChainComputedMember(obj_expr, key_expr, loc) => {
      let (obj, short_circuited) = self.eval_chain_expr(ctx, obj_expr, env)
      if short_circuited {
        (Undefined, true)
      } else {
        let key = self.eval_expr(ctx, key_expr, env)
        (self.get_computed_property(obj, key, loc), false)
      }
    }
    OptionalCall(callee_expr, arg_exprs, loc) => {
      // Peel grouping parentheses to recover the reference/receiver (§13.2.9).
      // Grouping preserves the Reference, so (a.b)?.() should call with this=a.
      let unwrapped = unwrap_grouping(callee_expr)
      match unwrapped {
        OptionalMember(obj_expr, prop, mloc) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          match obj {
            Null | Undefined => (Undefined, true)
            _ => {
              let func_val = self.get_property(obj, prop, mloc)
              self.eval_optional_call_tail(
                ctx, func_val, obj, arg_exprs, env, loc,
              )
            }
          }
        }
        ChainMember(obj_expr, prop, mloc) => {
          let (obj, short_circuited) = self.eval_chain_expr(ctx, obj_expr, env)
          if short_circuited {
            (Undefined, true)
          } else {
            let func_val = self.get_property(obj, prop, mloc)
            self.eval_optional_call_tail(
              ctx, func_val, obj, arg_exprs, env, loc,
            )
          }
        }
        OptionalComputedMember(obj_expr, key_expr, mloc) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          match obj {
            Null | Undefined => (Undefined, true)
            _ => {
              let key = self.eval_expr(ctx, key_expr, env)
              let func_val = self.get_computed_property(obj, key, mloc)
              self.eval_optional_call_tail(
                ctx, func_val, obj, arg_exprs, env, loc,
              )
            }
          }
        }
        ChainComputedMember(obj_expr, key_expr, mloc) => {
          let (obj, short_circuited) = self.eval_chain_expr(ctx, obj_expr, env)
          if short_circuited {
            (Undefined, true)
          } else {
            let key = self.eval_expr(ctx, key_expr, env)
            let func_val = self.get_computed_property(obj, key, mloc)
            self.eval_optional_call_tail(
              ctx, func_val, obj, arg_exprs, env, loc,
            )
          }
        }
        Member(obj_expr, prop, mloc) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          let func_val = self.get_property(obj, prop, mloc)
          self.eval_optional_call_tail(ctx, func_val, obj, arg_exprs, env, loc)
        }
        ComputedMember(obj_expr, key_expr, mloc) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          let key = self.eval_expr(ctx, key_expr, env)
          let func_val = self.get_computed_property(obj, key, mloc)
          self.eval_optional_call_tail(ctx, func_val, obj, arg_exprs, env, loc)
        }
        PrivateMember(obj_expr, name, _) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          let func_val = get_private_member(obj, name, env)
          self.eval_optional_call_tail(ctx, func_val, obj, arg_exprs, env, loc)
        }
        SuperMember(prop, sloc) => {
          let (this_val, func_val) = self.eval_super_property_call_reference(
            env, prop, sloc,
          )
          self.eval_optional_call_tail(
            ctx, func_val, this_val, arg_exprs, env, loc,
          )
        }
        SuperComputedMember(key_expr, sloc) => {
          let _ = eval_this_value(env)
          let key = self.eval_expr(ctx, key_expr, env)
          let (this_val, func_val) = self.eval_super_computed_call_reference(
            env, key, sloc,
          )
          self.eval_optional_call_tail(
            ctx, func_val, this_val, arg_exprs, env, loc,
          )
        }
        _ => {
          let callee = self.eval_expr(ctx, callee_expr, env)
          match callee {
            Null | Undefined => (Undefined, true)
            _ => {
              let args = self.eval_args_with_spread(ctx, arg_exprs, env)
              (self.call_value(callee, Undefined, args, loc), false)
            }
          }
        }
      }
    }
    // Call(OptionalCall(...), ...): continuation call after an optional call.
    // If the inner OptionalCall short-circuits, propagate short-circuit.
    // Otherwise the inner call produced a value; call it with no receiver.
    // Must recurse on the inner OptionalCall, not on `expr` (which is the
    // outer Call), to avoid infinite recursion.
    Call(
      OptionalCall(inner_callee, inner_args, inner_loc),
      continuation_args,
      loc
    ) => {
      let (value, short_circuited) = self.eval_chain_expr(
        ctx,
        OptionalCall(inner_callee, inner_args, inner_loc),
        env,
      )
      if short_circuited {
        (Undefined, true)
      } else {
        let args = self.eval_args_with_spread(ctx, continuation_args, env)
        (self.call_value(value, Undefined, args, loc), false)
      }
    }
    Call(OptionalMember(obj_expr, prop, mloc), arg_exprs, loc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      match obj {
        Null | Undefined => (Undefined, true)
        _ => {
          let func_val = self.get_property(obj, prop, mloc)
          let args = self.eval_args_with_spread(ctx, arg_exprs, env)
          (self.call_value(func_val, obj, args, loc), false)
        }
      }
    }
    Call(ChainMember(obj_expr, prop, mloc), arg_exprs, loc) => {
      let (obj, short_circuited) = self.eval_chain_expr(ctx, obj_expr, env)
      if short_circuited {
        (Undefined, true)
      } else {
        let func_val = self.get_property(obj, prop, mloc)
        let args = self.eval_args_with_spread(ctx, arg_exprs, env)
        (self.call_value(func_val, obj, args, loc), false)
      }
    }
    Call(OptionalComputedMember(obj_expr, key_expr, mloc), arg_exprs, loc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      match obj {
        Null | Undefined => (Undefined, true)
        _ => {
          let key = self.eval_expr(ctx, key_expr, env)
          let func_val = self.get_computed_property(obj, key, mloc)
          let args = self.eval_args_with_spread(ctx, arg_exprs, env)
          (self.call_value(func_val, obj, args, loc), false)
        }
      }
    }
    Call(ChainComputedMember(obj_expr, key_expr, mloc), arg_exprs, loc) => {
      let (obj, short_circuited) = self.eval_chain_expr(ctx, obj_expr, env)
      if short_circuited {
        (Undefined, true)
      } else {
        let key = self.eval_expr(ctx, key_expr, env)
        let func_val = self.get_computed_property(obj, key, mloc)
        let args = self.eval_args_with_spread(ctx, arg_exprs, env)
        (self.call_value(func_val, obj, args, loc), false)
      }
    }
    _ => (self.eval_expr(ctx, expr, env), false)
  }
}

///|

///|
/// Resolve the [[PrivateBrand]] from an environment.
/// Raises ReferenceError if the brand is not found (expression outside a class context).
fn resolve_private_brand(env : Environment, name : String) -> Value raise Error {
  env.get("[[PrivateBrand]]") catch {
    _ =>
      raise @errors.ReferenceError(
        message="Private field '#\{name}' must be declared in an enclosing class",
      )
  }
}

///|
fn get_private_member(
  obj : Value,
  name : String,
  env : Environment,
) -> Value raise Error {
  let brand = resolve_private_brand(env, name)
  // Check private methods first (shared per-class, not instance-specific)
  let methods_obj = env.get("[[PrivateMethods]]") catch { _ => Undefined }
  match methods_obj {
    Object(mobj_data) =>
      match mobj_data.bag.properties.get(name) {
        Some(method_val) => {
          if !has_brand(obj, brand) {
            raise @errors.TypeError(
              message="Cannot read private member #\{name} from object of different class",
            )
          }
          return method_val
        }
        None => ()
      }
    _ => ()
  }
  // Fall back to private field lookup
  get_private_field(obj, brand, name)
}

///|
/// Runtime Semantics: NamedEvaluation. Anonymous class expressions need the
/// inferred name during ClassDefinitionEvaluation (before static elements run),
/// while the other anonymous function forms can retain their existing
/// SetFunctionName path after ordinary evaluation.
fn Interpreter::eval_named_expr(
  self : Interpreter,
  ctx : ExecContext,
  expr : @ast.Expr,
  env : Environment,
  inferred_name : String,
) -> Value raise Error {
  match expr {
    Grouping(inner, _) => self.eval_named_expr(ctx, inner, env, inferred_name)
    ClassExpr(None, superclass, members, _, source_text) =>
      self.create_class(
        ctx, inferred_name, superclass, members, env, source_text,
      )
    _ => {
      let value = self.eval_expr(ctx, expr, env)
      if is_anonymous_function_definition(expr) {
        set_function_name(value, inferred_name)
      }
      value
    }
  }
}

///|
fn Interpreter::eval_expr(
  self : Interpreter,
  ctx : ExecContext,
  expr : @ast.Expr,
  env : Environment,
) -> Value raise Error {
  match expr {
    NumberLit(n, _, _) => Number(n)
    StringLit(s, _, _, _) => String_(s)
    BoolLit(b, _) => Bool(b)
    NullLit(_) => Null
    UndefinedLit(_) => Undefined
    ArrayHole(_) => Undefined
    Ident(name, _) => {
      @static_semantics.validate_strict_identifier_reference(ctx.strict, name)
      env.get_with_strict(name, ctx.strict) catch {
        @errors.ReferenceError(message~) =>
          if message == "\{name} is not defined" {
            // Fallback: check global object (globalThis) for properties set via this.x = y
            match self.global_this {
              Object(data) =>
                match data.bag.properties.get(name) {
                  Some(v) => v
                  None =>
                    raise @errors.ReferenceError(
                      message="\{name} is not defined",
                    )
                }
              _ =>
                raise @errors.ReferenceError(message="\{name} is not defined")
            }
          } else {
            raise @errors.ReferenceError(message~)
          }
        other => raise other
      }
    }
    Grouping(e, _) => self.eval_expr(ctx, e, env)
    Binary(op, left, right, loc) =>
      self.eval_binary(ctx, op, left, right, env, loc)
    Unary(op, operand, loc) => self.eval_unary(ctx, op, operand, env, loc)
    Assign(name, value_expr, _) => {
      @static_semantics.validate_strict_assignment_target_name(ctx.strict, name)
      let resolved_env = env.resolve_binding_env(name)
      let value = self.eval_named_expr(ctx, value_expr, env, name)
      // Check if the target is a non-writable property on the global object
      // (e.g. undefined, NaN, Infinity). In strict mode this is a TypeError;
      // in non-strict mode the assignment is silently ignored.
      // Check both unresolvable references AND global-env bindings, since
      // undefined/NaN/Infinity are installed as global env bindings.
      let is_global_or_missing = match resolved_env {
        None => true
        Some(e) => e.parent is None
      }
      if is_global_or_missing && self.is_immutable_global(name) {
        if ctx.strict {
          raise @errors.TypeError(
            message="Cannot assign to read only property '\{name}' of object '[object global]'",
          )
        }
        return value
      }
      match resolved_env {
        Some(target_env) =>
          target_env.assign_resolved(name, value, ctx.strict) catch {
            @errors.ReferenceError(message~) => {
              // The pre-RHS resolved binding was deleted by RHS evaluation.
              // In non-strict mode, fall back to implicit global; in strict
              // mode, propagate the ReferenceError.
              if ctx.strict {
                raise @errors.ReferenceError(message~)
              }
              self.global.def(name, value, VarBinding)
              self.mirror_to_global(name, value, configurable=true)
            }
            e => raise e
          }
        None => {
          if ctx.strict {
            raise @errors.ReferenceError(message="\{name} is not defined")
          }
          // In non-strict mode, assigning to an undeclared variable creates
          // a global property (sloppy mode implicit global) using the
          // reference resolution result captured before RHS evaluation.
          self.global.def(name, value, VarBinding)
          self.mirror_to_global(name, value, configurable=true)
        }
      }
      value
    }
    Ternary(cond, then_expr, else_expr, _) =>
      if is_truthy(self.eval_expr(ctx, cond, env)) {
        self.eval_expr(ctx, then_expr, env)
      } else {
        self.eval_expr(ctx, else_expr, env)
      }
    Call(callee, args, loc) => self.eval_call(ctx, callee, args, env, loc)
    Member(obj_expr, prop, loc) =>
      self.eval_member(ctx, obj_expr, prop, env, loc)
    FuncExpr(name, params, body, _, source_text) => {
      validate_function_signature(ctx.strict, name, params, body)
      let func_data : FuncData = {
        name,
        params,
        body,
        closure: env,
        strict: is_function_strict(ctx.strict, body),
        // Named FunctionExpression: §15.2.5 installs a self-name binding
        // in a dedicated funcEnv. Anonymous FEs have no such binding.
        has_name_binding: name is Some(_),
        is_method: false,
        source_text,
      }
      make_func(func_data)
    }
    GeneratorExpr(name, params, body, _, source_text) => {
      validate_function_signature(ctx.strict, name, params, body)
      let strict = is_function_strict(ctx.strict, body)
      self.make_generator_function(
        name,
        params,
        None,
        body,
        strict,
        env,
        has_name_binding=name is Some(_),
        source_text~,
      )
    }
    GeneratorExprExt(name, params, rest_param, body, _, source_text) => {
      validate_function_signature_ext(
        ctx.strict,
        name,
        params,
        rest_param,
        body,
      )
      let strict = is_function_strict(ctx.strict, body)
      self.make_generator_function_ext(
        name,
        params,
        rest_param,
        body,
        strict,
        env,
        has_name_binding=name is Some(_),
        source_text~,
      )
    }
    AsyncFuncExpr(name, params, body, _, source_text) => {
      validate_function_signature(ctx.strict, name, params, body)
      let strict = is_function_strict(ctx.strict, body)
      self.make_async_function(
        name,
        params,
        None,
        body,
        strict,
        env,
        has_name_binding=name is Some(_),
        source_text~,
      )
    }
    AsyncFuncExprExt(name, params, rest_param, body, _, source_text) => {
      validate_function_signature_ext(
        ctx.strict,
        name,
        params,
        rest_param,
        body,
      )
      let strict = is_function_strict(ctx.strict, body)
      self.make_async_function_ext(
        name,
        params,
        rest_param,
        body,
        strict,
        env,
        has_name_binding=name is Some(_),
        source_text~,
      )
    }
    AsyncArrowFunc(params, body, _, source_text) => {
      validate_function_signature(ctx.strict, None, params, body)
      let strict = is_function_strict(ctx.strict, body)
      self.make_async_function(
        None,
        params,
        None,
        body,
        strict,
        env,
        source_text~,
        is_arrow=true,
      )
    }
    AsyncArrowFuncExt(params, rest_param, body, _, source_text) => {
      validate_function_signature_ext(
        ctx.strict,
        None,
        params,
        rest_param,
        body,
      )
      let strict = is_function_strict(ctx.strict, body)
      self.make_async_function_ext(
        None,
        params,
        rest_param,
        body,
        strict,
        env,
        source_text~,
        is_arrow=true,
      )
    }
    AsyncGeneratorExpr(name, params, body, _, source_text) => {
      validate_function_signature(ctx.strict, name, params, body)
      let strict = is_function_strict(ctx.strict, body)
      self.make_async_generator_function(
        name,
        params,
        None,
        body,
        strict,
        env,
        has_name_binding=name is Some(_),
        source_text~,
      )
    }
    AsyncGeneratorExprExt(name, params, rest_param, body, _, source_text) => {
      validate_function_signature_ext(
        ctx.strict,
        name,
        params,
        rest_param,
        body,
      )
      let strict = is_function_strict(ctx.strict, body)
      self.make_async_generator_function_ext(
        name,
        params,
        rest_param,
        body,
        strict,
        env,
        has_name_binding=name is Some(_),
        source_text~,
      )
    }
    AwaitExpr(argument, _) =>
      // await acts like yield inside the generator that backs the async function
      self.eval_yield(ctx, Some(argument), false, env)
    YieldExpr(argument, delegate, _) =>
      self.eval_yield(ctx, argument, delegate, env)
    ObjectLit(props, obj_loc) => {
      let properties : Map[String, Value] = Map([])
      let symbol_properties : Map[Int, Value] = Map([])
      let descriptors : Map[String, PropDescriptor] = Map([])
      let symbol_descriptors : Map[Int, PropDescriptor] = Map([])
      // Build the object eagerly so methods captured during the prop loop can
      // reference it as [[HomeObject]] (ES2022 §13.2.5.5). The bag's Maps are
      // shared by reference, so later inserts populate the live object; the
      // mutable `prototype` field is updated when a __proto__ override is seen.
      // This is what makes `super.x` resolve dynamically against
      // `Object.getPrototypeOf(homeObject)` even after Object.setPrototypeOf is
      // called on the literal.
      let default_obj_proto = env.get("[[ObjectPrototype]]") catch { _ => Null }
      let object_data : ObjectData = {
        bag: {
          properties,
          symbol_properties,
          descriptors,
          symbol_descriptors,
          internal_slots: Map([]),
          host_slots: Map([]),
        },
        prototype: default_obj_proto,
        callable: None,
        class_name: "Object",
        extensible: true,
        arraybuffer_state: None,
      }
      let home_object : Value = Object(object_data)
      let method_env = Environment::new(parent=Some(env))
      method_env.def_builtin("[[HomeObject]]", home_object)
      for prop in props {
        // Handle spread property: { ...expr }
        if prop.kind == @ast.Spread {
          let spread_val = self.eval_expr(ctx, prop.key, env)
          self.copy_object_spread_properties(home_object, spread_val, obj_loc)
          continue
        }
        if prop.computed {
          // Evaluate and canonicalize the computed key before the value.
          let key_val = self.eval_expr(ctx, prop.key, env)
          let prop_key = self.to_object_literal_property_key(key_val)
          match prop_key {
            Symbol(_) =>
              // Symbol key - store in symbol_properties
              match prop.kind {
                Init => {
                  let val = self.eval_named_prop_value(
                    ctx, prop, method_env, prop_key,
                  )
                  apply_object_literal_data_property(home_object, prop_key, val)
                }
                Get => {
                  let getter = self.eval_prop_value(ctx, prop, method_env)
                  apply_object_literal_accessor_property(
                    home_object, prop_key, getter, true,
                  )
                }
                Set => {
                  let setter = self.eval_prop_value(ctx, prop, method_env)
                  apply_object_literal_accessor_property(
                    home_object, prop_key, setter, false,
                  )
                }
                Spread => () // handled above
              }
            _ =>
              match prop.kind {
                Init => {
                  let val = self.eval_named_prop_value(
                    ctx, prop, method_env, prop_key,
                  )
                  apply_object_literal_data_property(home_object, prop_key, val)
                }
                Get => {
                  let getter = self.eval_prop_value(ctx, prop, method_env)
                  apply_object_literal_accessor_property(
                    home_object, prop_key, getter, true,
                  )
                }
                Set => {
                  let setter = self.eval_prop_value(ctx, prop, method_env)
                  apply_object_literal_accessor_property(
                    home_object, prop_key, setter, false,
                  )
                }
                Spread => () // handled above
              }
          }
        } else {
          // Static key - extract from StringLit
          let key_str = match prop.key {
            StringLit(s, _, _, _) => s
            Ident(name, _) => name
            NumberLit(n, _, _) => {
              let i = n.to_int()
              if i.to_double() == n {
                i.to_string()
              } else {
                n.to_string()
              }
            }
            _ => "" // fallback
          }
          match prop.kind {
            Init =>
              // Handle __proto__ as special syntax per B.3.1
              if key_str == "__proto__" {
                let val = self.eval_prop_value(ctx, prop, method_env)
                apply_object_literal_proto_property(home_object, val)
              } else {
                let val = self.eval_named_prop_value(
                  ctx,
                  prop,
                  method_env,
                  String_(key_str),
                )
                properties[key_str] = val
              }
            Get => {
              let getter = self.eval_prop_value(ctx, prop, method_env)
              apply_object_literal_accessor_property(
                home_object,
                String_(key_str),
                getter,
                true,
              )
            }
            Set => {
              let setter = self.eval_prop_value(ctx, prop, method_env)
              apply_object_literal_accessor_property(
                home_object,
                String_(key_str),
                setter,
                false,
              )
            }
            Spread => () // handled above
          }
        }
      }
      home_object
    }
    ArrayLit(elements, _) => {
      let vals : Array[Value] = []
      let hole_idxs : Array[Int] = []
      for e in elements {
        match e {
          SpreadExpr(inner, spread_loc) => {
            let val = self.eval_expr(ctx, inner, env)
            // Use iterator protocol for spreading
            let spread_vals = self.spread_iterable(val, spread_loc)
            for v in spread_vals {
              vals.push(v)
            }
          }
          ArrayHole(_) => {
            hole_idxs.push(vals.length())
            vals.push(Undefined)
          }
          _ => vals.push(self.eval_expr(ctx, e, env))
        }
      }
      make_array_with_holes(vals, hole_idxs)
    }
    ComputedMember(obj_expr, key_expr, loc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let key = self.eval_expr(ctx, key_expr, env)
      self.get_computed_property(obj, key, loc)
    }
    MemberAssign(obj_expr, prop, value_expr, loc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let value = self.eval_expr(ctx, value_expr, env)
      self.set_property(obj, prop, value, loc, strict=ctx.strict)
    }
    PrivateMemberAssign(obj_expr, name, value_expr, _) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let value = self.eval_expr(ctx, value_expr, env)
      let brand = resolve_private_brand(env, name)
      let _ = set_private_field(obj, brand, name, value)
      value
    }
    ComputedAssign(obj_expr, key_expr, value_expr, loc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let key = self.eval_expr(ctx, key_expr, env)
      let value = self.eval_expr(ctx, value_expr, env)
      self.set_computed_property(obj, key, value, loc, strict=ctx.strict)
    }
    SuperMemberAssign(prop, value_expr, loc) => {
      let this_val = eval_this_value(env)
      let super_proto = self.resolve_super_target(env)
      match super_proto {
        Undefined =>
          raise @errors.ReferenceError(
            message="super.prop used but no [[SuperPrototype]] in scope at line \{loc.line}",
          )
        _ => {
          let value = self.eval_expr(ctx, value_expr, env)
          if super_proto is Null {
            raise @errors.TypeError(
              message="Cannot set property on null super base at line \{loc.line}",
            )
          }
          self.set_property(
            super_proto,
            prop,
            value,
            loc,
            strict=ctx.strict,
            receiver=this_val,
          )
        }
      }
    }
    SuperComputedAssign(key_expr, value_expr, loc) => {
      let this_val = eval_this_value(env)
      let key = self.eval_expr(ctx, key_expr, env)
      let super_proto = self.resolve_super_target(env)
      match super_proto {
        Undefined =>
          raise @errors.ReferenceError(
            message="super[expr] used but no [[SuperPrototype]] in scope at line \{loc.line}",
          )
        _ => {
          let value = self.eval_expr(ctx, value_expr, env)
          if super_proto is Null {
            raise @errors.TypeError(
              message="Cannot set property on null super base at line \{loc.line}",
            )
          }
          let prop_key = to_property_key(key, interp=Some(self))
          self.set_computed_property(
            super_proto,
            prop_key,
            value,
            loc,
            strict=ctx.strict,
            receiver=this_val,
          )
        }
      }
    }
    NewExpr(callee_expr, arg_exprs, loc) =>
      self.eval_new(ctx, callee_expr, arg_exprs, env, loc)
    ThisExpr(_) => eval_this_value(env)
    UpdateExpr(op, operand, prefix, loc) =>
      self.eval_update(ctx, op, operand, prefix, env, loc)
    CompoundAssign(op, target, value_expr, loc) =>
      self.eval_compound_assign(ctx, op, target, value_expr, env, loc)
    Comma(left, right, _) => {
      let skip_left = match ctx.current_generator {
        Some(gen) => gen.resuming && !expr_may_contain_yield(left)
        None => false
      }
      if !skip_left {
        let _ = self.eval_expr(ctx, left, env)
      }
      self.eval_expr(ctx, right, env)
    }
    TemplateLit(quasis, exprs, _) => {
      let buf = StringBuilder::new()
      for i = 0; i < quasis.length(); i = i + 1 {
        // Validator ensures cooked is always Some for untagged templates
        buf.write_string(
          match quasis[i].1 {
            Some(s) => s
            None =>
              fail(
                "unreachable: untagged TemplateLit with invalid escape reached evaluator; early-error validator should have rejected it",
              )
          },
        )
        if i < exprs.length() {
          let val = self.eval_expr(ctx, exprs[i], env)
          buf.write_string(to_js_string(val, interp=Some(self)))
        }
      }
      String_(buf.to_string())
    }
    TaggedTemplate(tag_expr, quasis, exprs, loc) => {
      let (tag, this_val) = match tag_expr {
        Member(obj_expr, prop, member_loc) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          (self.get_property(obj, prop, member_loc), obj)
        }
        ComputedMember(obj_expr, key_expr, member_loc) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          let key = self.eval_expr(ctx, key_expr, env)
          (self.get_computed_property(obj, key, member_loc), obj)
        }
        _ => (self.eval_expr(ctx, tag_expr, env), Undefined)
      }
      // Build args: [templateObj, ...substitutions]
      let args : Array[Value] = [self.get_tagged_template_object(loc, quasis)]
      for e in exprs {
        args.push(self.eval_expr(ctx, e, env))
      }
      self.call_value(tag, this_val, args, loc)
    }
    ArrowFunc(params, body, _, source_text) => {
      validate_function_signature(ctx.strict, None, params, body)
      let func_data : FuncData = {
        name: None,
        params,
        body,
        closure: env,
        strict: is_function_strict(ctx.strict, body),
        has_name_binding: false,
        is_method: false,
        source_text,
      }
      let nf_desc : PropDescriptor = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      }
      stamp_function_realm(
        Object({
          bag: {
            properties: {
              "name": String_(""),
              "length": Number(params.length().to_double()),
            },
            symbol_properties: Map([]),
            descriptors: { "name": nf_desc, "length": nf_desc },
            symbol_descriptors: Map([]),
            internal_slots: Map([]),
            host_slots: Map([]),
          },
          prototype: get_func_proto(realm_state=Some(self.realm_state)),
          callable: Some(ArrowFunc(func_data)),
          class_name: "Function",
          extensible: true,
          arraybuffer_state: None,
        }),
        realm_state=Some(self.realm_state),
      )
    }
    ArrowFuncExt(params, rest_param, body, _, source_text) => {
      validate_function_signature_ext(
        ctx.strict,
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
        strict: is_function_strict(ctx.strict, body),
        has_name_binding: false,
        is_method: false,
        source_text,
      }
      let nf_desc : PropDescriptor = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      }
      let arrow_len = expected_argument_count_ext(params)
      stamp_function_realm(
        Object({
          bag: {
            properties: {
              "name": String_(""),
              "length": Number(arrow_len.to_double()),
            },
            symbol_properties: Map([]),
            descriptors: { "name": nf_desc, "length": nf_desc },
            symbol_descriptors: Map([]),
            internal_slots: Map([]),
            host_slots: Map([]),
          },
          prototype: get_func_proto(realm_state=Some(self.realm_state)),
          callable: Some(ArrowFuncExt(func_data)),
          class_name: "Function",
          extensible: true,
          arraybuffer_state: None,
        }),
        realm_state=Some(self.realm_state),
      )
    }
    FuncExprExt(name, params, rest_param, body, _, source_text) => {
      validate_function_signature_ext(
        ctx.strict,
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
        strict: is_function_strict(ctx.strict, body),
        has_name_binding: name is Some(_),
        is_method: false,
        source_text,
      }
      make_func_ext(func_data)
    }
    RegexLit(pattern, flags, _) =>
      (self.stdlib_hooks.make_regexp_object)(self.realm_state, pattern, flags)
    SpreadExpr(_, _) =>
      raise @errors.SyntaxError(
        message="Spread expression used outside of call or array literal",
      )
    DestructureAssign(pattern, value_expr, _) => {
      let value = self.eval_expr(ctx, value_expr, env)
      self.eval_destructure_assign(ctx, pattern, value, env)
    }
    WebCompatCallAssign(call_expr, _, loc) => {
      if ctx.strict {
        raise @errors.SyntaxError(
          message="Invalid assignment target at line \{loc.line}, col \{loc.col}",
        )
      }
      let _ = self.eval_expr(ctx, call_expr, env)
      raise @errors.ReferenceError(
        message="Invalid left-hand side in assignment",
      )
    }
    OptionalMember(obj_expr, prop, loc) => {
      // obj?.prop - return undefined if obj is null/undefined
      let obj = self.eval_expr(ctx, obj_expr, env)
      match obj {
        Null | Undefined => Undefined
        _ => self.get_property(obj, prop, loc)
      }
    }
    OptionalComputedMember(obj_expr, key_expr, loc) => {
      // obj?.[key] - return undefined if obj is null/undefined
      let obj = self.eval_expr(ctx, obj_expr, env)
      match obj {
        Null | Undefined => Undefined
        _ => {
          let key = self.eval_expr(ctx, key_expr, env)
          self.get_computed_property(obj, key, loc)
        }
      }
    }
    ChainMember(_, _, _) | ChainComputedMember(_, _, _) => {
      let (value, _) = self.eval_chain_expr(ctx, expr, env)
      value
    }
    OptionalCall(callee_expr, arg_exprs, loc) => {
      // func?.(args) - return undefined if func is null/undefined
      // Per ES spec, arguments are NOT evaluated if function is nullish
      // Need to preserve receiver for method calls
      // Peel grouping parentheses to recover the reference/receiver (§13.2.9).
      // Grouping preserves the Reference, so (a.b)?.() should call with this=a.
      let unwrapped = unwrap_grouping(callee_expr)
      match unwrapped {
        OptionalMember(obj_expr, prop, mloc) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          match obj {
            Null | Undefined => Undefined
            _ => {
              let func_val = self.get_property(obj, prop, mloc)
              match func_val {
                Null | Undefined => Undefined
                _ => {
                  let args = self.eval_args_with_spread(ctx, arg_exprs, env)
                  self.call_value(func_val, obj, args, loc)
                }
              }
            }
          }
        }
        OptionalComputedMember(obj_expr, key_expr, mloc) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          match obj {
            Null | Undefined => Undefined
            _ => {
              let key = self.eval_expr(ctx, key_expr, env)
              let func_val = self.get_computed_property(obj, key, mloc)
              match func_val {
                Null | Undefined => Undefined
                _ => {
                  let args = self.eval_args_with_spread(ctx, arg_exprs, env)
                  self.call_value(func_val, obj, args, loc)
                }
              }
            }
          }
        }
        ChainMember(obj_expr, prop, mloc) => {
          let (obj, short_circuited) = self.eval_chain_expr(ctx, obj_expr, env)
          if short_circuited {
            Undefined
          } else {
            let func_val = self.get_property(obj, prop, mloc)
            match func_val {
              Null | Undefined => Undefined
              _ => {
                let args = self.eval_args_with_spread(ctx, arg_exprs, env)
                self.call_value(func_val, obj, args, loc)
              }
            }
          }
        }
        ChainComputedMember(obj_expr, key_expr, mloc) => {
          let (obj, short_circuited) = self.eval_chain_expr(ctx, obj_expr, env)
          if short_circuited {
            Undefined
          } else {
            let key = self.eval_expr(ctx, key_expr, env)
            let func_val = self.get_computed_property(obj, key, mloc)
            match func_val {
              Null | Undefined => Undefined
              _ => {
                let args = self.eval_args_with_spread(ctx, arg_exprs, env)
                self.call_value(func_val, obj, args, loc)
              }
            }
          }
        }
        Member(obj_expr, prop, mloc) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          let func_val = self.get_property(obj, prop, mloc)
          match func_val {
            Null | Undefined => Undefined
            _ => {
              let args = self.eval_args_with_spread(ctx, arg_exprs, env)
              self.call_value(func_val, obj, args, loc)
            }
          }
        }
        ComputedMember(obj_expr, key_expr, mloc) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          let key = self.eval_expr(ctx, key_expr, env)
          let func_val = self.get_computed_property(obj, key, mloc)
          match func_val {
            Null | Undefined => Undefined
            _ => {
              let args = self.eval_args_with_spread(ctx, arg_exprs, env)
              self.call_value(func_val, obj, args, loc)
            }
          }
        }
        PrivateMember(obj_expr, name, _) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          let func_val = get_private_member(obj, name, env)
          match func_val {
            Null | Undefined => Undefined
            _ => {
              let args = self.eval_args_with_spread(ctx, arg_exprs, env)
              self.call_value(func_val, obj, args, loc)
            }
          }
        }
        SuperMember(prop, sloc) => {
          let (this_val, func_val) = self.eval_super_property_call_reference(
            env, prop, sloc,
          )
          match func_val {
            Null | Undefined => Undefined
            _ => {
              let args = self.eval_args_with_spread(ctx, arg_exprs, env)
              self.call_value(func_val, this_val, args, loc)
            }
          }
        }
        SuperComputedMember(key_expr, sloc) => {
          let _ = eval_this_value(env)
          let key = self.eval_expr(ctx, key_expr, env)
          let (this_val, func_val) = self.eval_super_computed_call_reference(
            env, key, sloc,
          )
          match func_val {
            Null | Undefined => Undefined
            _ => {
              let args = self.eval_args_with_spread(ctx, arg_exprs, env)
              self.call_value(func_val, this_val, args, loc)
            }
          }
        }
        _ => {
          let callee = self.eval_expr(ctx, callee_expr, env)
          match callee {
            Null | Undefined => Undefined
            _ => {
              let args = self.eval_args_with_spread(ctx, arg_exprs, env)
              self.call_value(callee, Undefined, args, loc)
            }
          }
        }
      }
    }
    ClassExpr(name, superclass, methods, _, source_text) => {
      let class_name = name.unwrap_or("")
      self.create_class(
        ctx,
        class_name,
        superclass,
        methods,
        env,
        source_text,
        class_binding=name,
      )
    }
    SuperCall(arg_exprs, loc) => {
      // SuperCall steps 3-5: read the active class function's current
      // [[Prototype]] before evaluating Arguments, but defer IsConstructor
      // validation until after argument evaluation.
      let super_ctor = get_active_super_constructor(env, loc)
      let args = self.eval_args_with_spread(ctx, arg_exprs, env)
      self.eval_super_dispatch(super_ctor, args, env, loc)
    }
    SuperMember(prop, loc) => self.eval_super_property(env, prop, loc)
    SuperComputedMember(key_expr, loc) => {
      // Evaluate super binding first to ensure `this` TDZ/derived checks
      // happen before computed-key side effects.
      let _ = eval_this_value(env)
      let key = self.eval_expr(ctx, key_expr, env)
      self.eval_super_computed_property(env, key, loc)
    }
    NewTargetExpr(_) => eval_new_target_value(env)
    PrivateIdent(name, _) => fail("TODO: bare private name reference: #\{name}")
    PrivateMember(obj, name, _) => {
      let obj_val = self.eval_expr(ctx, obj, env)
      get_private_member(obj_val, name, env)
    }
  }
}

///|
// GetSuperConstructor reads the active class function's live [[Prototype]].
// The caller performs this before ArgumentListEvaluation, matching SuperCall's
// required observable ordering.
fn get_active_super_constructor(
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  let active_function = env.get("[[ActiveClassFunction]]") catch {
    _ =>
      raise @errors.ReferenceError(
        message=format_loc_context(
          "super() called but no active class function is in scope", loc,
        ),
      )
  }
  match active_function {
    Object(data) => data.prototype
    _ =>
      raise @errors.ReferenceError(
        message=format_loc_context(
          "super() called but active class function is invalid", loc,
        ),
      )
  }
}

///|
fn Interpreter::construct_and_bind_super(
  self : Interpreter,
  super_ctor : Value,
  args : Array[Value],
  super_new_target : Value,
  this_val : Value,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  let super_result = self.construct_value(
    super_ctor,
    args,
    loc,
    new_target=Some(super_new_target),
  )
  match super_result {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => {
      env.initialize_in_chain("this", super_result)
      if env.has("[[InitInstanceFields]]") {
        let init_fn = env.get("[[InitInstanceFields]]")
        let _ = self.call_value(init_fn, super_result, [], loc)
      }
      super_result
    }
    _ => {
      env.initialize_in_chain("this", this_val)
      if env.has("[[InitInstanceFields]]") {
        let init_fn = env.get("[[InitInstanceFields]]")
        let _ = self.call_value(init_fn, this_val, [], loc)
      }
      env.get("this")
    }
  }
}

///|
// Dispatch a super() call. The selected super constructor was captured before
// argument evaluation. This function validates it afterward, reads
// [[PendingThis]]/this and <new.target> from `env`, runs the constructor,
// updates env.this, applies env.[[InitInstanceFields]], and returns the resolved
// this value. It calls itself recursively for implicit derived constructors.
fn Interpreter::eval_super_dispatch(
  self : Interpreter,
  super_ctor : Value,
  args : Array[Value],
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  if !is_constructor_value(super_ctor) {
    raise @errors.TypeError(
      message=format_loc_context("super constructor is not a constructor", loc),
    )
  }
  let this_val = if env.has("[[PendingThis]]") {
    env.get("[[PendingThis]]")
  } else {
    env.get("this")
  }
  let super_new_target = env.get("<new.target>") catch { _ => Undefined }
  match super_ctor {
    Object(data) =>
      match data.callable {
        Some(_) =>
          // All super constructors, including classes and built-ins, use the
          // canonical [[Construct]] path. This keeps newTarget forwarding,
          // allocation timing, return-value replacement, and field setup in a
          // single implementation.
          self.construct_and_bind_super(
            super_ctor, args, super_new_target, this_val, env, loc,
          )
        _ =>
          raise @errors.ReferenceError(
            message=format_loc_context(
              "super() called but the selected super value is not a constructor",
              loc,
            ),
          )
      }
    Proxy(_) =>
      self.construct_and_bind_super(
        super_ctor, args, super_new_target, this_val, env, loc,
      )
    Null =>
      // `extends null`: super() attempts Construct(null, ...) → TypeError
      raise @errors.TypeError(
        message=format_loc_context("null is not a constructor", loc),
      )
    _ =>
      raise @errors.ReferenceError(
        message=format_loc_context(
          "super() called but no super constructor is in scope", loc,
        ),
      )
  }
}

///|
fn Interpreter::eval_instanceof_values(
  self : Interpreter,
  l : Value,
  r : Value,
  loc : @token.Loc,
) -> Value raise Error {
  match r {
    Object(r_data) => {
      // Step 1: GetMethod(C, @@hasInstance) — must invoke accessor getters per spec.
      let has_instance_sym = self.realm_state.well_known_symbols.has_instance
      match
        lookup_symbol_property_chain(
          r,
          r_data,
          has_instance_sym.id,
          interp=Some(self),
        ) {
        Some(Undefined) | Some(Null) | None =>
          // No @@hasInstance — fall back to OrdinaryHasInstance.
          // Step 2: Check if RHS is callable (required for OrdinaryHasInstance)
          match r_data.callable {
            None =>
              raise @errors.TypeError(
                message="Right-hand side of 'instanceof' is not callable",
              )
            Some(_) =>
              // Step 3 of OrdinaryHasInstance: If O is not an Object, return
              // false. MUST precede steps 4-5 so primitive LHS never triggers
              // step 5's TypeError even when C.prototype is a non-object.
              if !is_object_value(l) {
                Bool(false)
              } else {
                // Steps 4-5: Get(C, "prototype"); if not Object, TypeError.
                // Bound functions without own prototype property fall through
                // to the None arm.
                match r_data.bag.properties.get("prototype") {
                  Some(proto) =>
                    if is_object_value(proto) {
                      instanceof_prototype_chain(l, proto, self)
                    } else {
                      raise @errors.TypeError(
                        message="Function has non-object prototype in instanceof check",
                      )
                    }
                  None => Bool(false)
                }
              }
          }
        Some(has_instance_fn) => {
          if !is_callable(has_instance_fn) {
            raise @errors.TypeError(
              message="Symbol.hasInstance is not a function",
            )
          }
          let result = self.call_value(has_instance_fn, r, [l], loc)
          Bool(is_truthy(result))
        }
      }
    }
    Proxy(proxy_data) => {
      // Step 1: Check for Symbol.hasInstance on the proxy (via get trap)
      let has_instance_sym = self.realm_state.well_known_symbols.has_instance
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
            Object(_) => instanceof_prototype_chain(l, proto, self)
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

///|
fn Interpreter::eval_binary(
  self : Interpreter,
  ctx : ExecContext,
  op : @ast.BinOp,
  left_expr : @ast.Expr,
  right_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // Short-circuit for &&, ||, and ??
  match op {
    And => {
      let left = self.eval_expr(ctx, left_expr, env)
      if !is_truthy(left) {
        return left
      }
      self.eval_expr(ctx, right_expr, env)
    }
    Or => {
      let left = self.eval_expr(ctx, left_expr, env)
      if is_truthy(left) {
        return left
      }
      self.eval_expr(ctx, right_expr, env)
    }
    NullishCoalesce => {
      // ?? returns left if it's not null/undefined, otherwise right
      let left = self.eval_expr(ctx, left_expr, env)
      match left {
        Null | Undefined => self.eval_expr(ctx, right_expr, env)
        _ => left
      }
    }
    Instanceof => {
      let l = self.eval_expr(ctx, left_expr, env)
      let r = self.eval_expr(ctx, right_expr, env)
      self.eval_instanceof_values(l, r, loc)
    }
    In =>
      // Handle #x in obj — check private brand rather than property lookup
      match left_expr {
        PrivateIdent(_, _) => {
          let right = self.eval_expr(ctx, right_expr, env)
          if !is_object_value(right) {
            raise @errors.TypeError(
              message="Cannot use 'in' operator to search for '\{right.to_string()}' in \{type_of(right)}",
            )
          }
          let brand = env.get("[[PrivateBrand]]") catch {
            _ => return Bool(false)
          }
          Bool(has_brand(right, brand))
        }
        _ => {
          let left = self.eval_expr(ctx, left_expr, env)
          let right = self.eval_expr(ctx, right_expr, env)
          if is_object_value(right) {
            Bool(
              self.has_property_key(
                right,
                to_property_key(left, interp=Some(self)),
              ),
            )
          } else {
            raise @errors.TypeError(
              message="Cannot use 'in' operator to search for '\{left.to_string()}' in \{type_of(right)}",
            )
          }
        }
      }
    _ => {
      let left = self.eval_expr(ctx, left_expr, env)
      let right = self.eval_expr(ctx, right_expr, env)
      eval_binary_op(op, left, right, loc, interp=Some(self))
    }
  }
}

///|
pub fn eval_unary_value_op(
  op : @ast.UnaryOp,
  value : Value,
  loc : @token.Loc,
  interp? : Interpreter? = None,
) -> Value raise Error {
  match op {
    Neg => Number(-to_number(value, interp~))
    Pos => Number(to_number(value, interp~))
    Not => Bool(!is_truthy(value))
    BitNot => Number(to_int32(to_number(value, interp~)).lnot().to_double())
    Typeof => String_(type_of(value))
    Void | Delete =>
      raise @errors.InternalError(
        message="Unexpected unary operator at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
pub fn eval_binary_op(
  op : @ast.BinOp,
  left : Value,
  right : Value,
  _loc : @token.Loc,
  interp? : Interpreter? = None,
) -> Value raise Error {
  fn n(v : Value) -> Double raise Error {
    to_number(v, interp~)
  }
  fn s(v : Value) -> String raise Error {
    to_js_string(v, interp~)
  }
  fn p_default(v : Value, data : ObjectData) -> Value raise Error {
    to_primitive_default(v, data, interp~)
  }
  match (op, left, right) {
    // Symbol cannot be converted to string implicitly
    (Add, Symbol(_), _) | (Add, _, Symbol(_)) =>
      raise @errors.TypeError(
        message="Cannot convert a Symbol value to a string",
      )
    // String concatenation (only for primitive operands)
    (Add, String_(a), String_(b)) => String_(a + b)
    (Add, String_(a), Number(b)) => String_(a + Number(b).to_string())
    (Add, String_(a), Bool(b)) => String_(a + b.to_string())
    (Add, String_(a), Null) => String_(a + "null")
    (Add, String_(a), Undefined) => String_(a + "undefined")
    (Add, Number(a), String_(b)) => String_(Number(a).to_string() + b)
    (Add, Bool(a), String_(b)) => String_(a.to_string() + b)
    (Add, Null, String_(b)) => String_("null" + b)
    (Add, Undefined, String_(b)) => String_("undefined" + b)
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
    (NotEqEq, l, r) => Bool(!strict_equal(l, r))
    (EqEq, l, r) => Bool(loose_equal(l, r, interp~))
    (NotEq, l, r) => Bool(!loose_equal(l, r, interp~))
    // Exponentiation
    (Exp, Number(a), Number(b)) => Number(@math.pow(a, b))
    (Exp, l, r) => Number(@math.pow(n(l), n(r)))
    // Add fallback: ToPrimitive, then check for strings
    (Add, l, r) => {
      // ToPrimitive with hint "default" per spec (+ operator uses no preferred type)
      let lp = match l {
        Object(data) => p_default(l, data)
        Array(arr_data) => {
          let s = arr_data.elements.map(fn(v) { v.to_string() }).join(",")
          String_(s)
        }
        _ => l
      }
      let rp = match r {
        Object(data) => p_default(r, data)
        Array(arr_data) => {
          let s = arr_data.elements.map(fn(v) { v.to_string() }).join(",")
          String_(s)
        }
        _ => r
      }
      // If either is a string after ToPrimitive, do string concatenation
      match (lp, rp) {
        (String_(a), String_(b)) => String_(a + b)
        (String_(a), b) => String_(a + s(b))
        (a, String_(b)) => String_(s(a) + b)
        (a, b) => Number(n(a) + n(b))
      }
    }
    (Sub, l, r) => Number(n(l) - n(r))
    (Mul, l, r) => Number(n(l) * n(r))
    (Div, l, r) => Number(n(l) / n(r))
    (Mod, l, r) => Number(n(l) % n(r))
    // Comparison fallbacks (type coercion)
    (Lt, l, r) => Bool(n(l) < n(r))
    (Gt, l, r) => Bool(n(l) > n(r))
    (LtEq, l, r) => Bool(n(l) <= n(r))
    (GtEq, l, r) => Bool(n(l) >= n(r))
    // Bitwise operations
    (BitAnd, l, r) => Number((to_int32(n(l)) & to_int32(n(r))).to_double())
    (BitOr, l, r) => Number((to_int32(n(l)) | to_int32(n(r))).to_double())
    (BitXor, l, r) => Number((to_int32(n(l)) ^ to_int32(n(r))).to_double())
    // Shift operations
    (LShift, l, r) => {
      let a = to_int32(n(l))
      let shift = to_int32(n(r)) & 0x1f
      Number((a << shift).to_double())
    }
    (RShift, l, r) => {
      let a = to_int32(n(l))
      let shift = to_int32(n(r)) & 0x1f
      Number((a >> shift).to_double())
    }
    (URShift, l, r) => {
      let a = to_int32(n(l))
      let shift = to_int32(n(r)) & 0x1f
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
    // instanceof - ES2015+ with Symbol.hasInstance support (spec: 7.3.21 OrdinaryHasInstance)
    (Instanceof, l, r) =>
      match interp {
        Some(ip) => ip.eval_instanceof_values(l, r, _loc)
        None =>
          raise @errors.InternalError(
            message="Internal error: instanceof requires interpreter context",
          )
      }
    // in operator - ES §7.3.11 HasProperty
    (In, l, r) =>
      if is_object_value(r) {
        match interp {
          Some(ip) =>
            Bool(ip.has_property_key(r, to_property_key(l, interp=Some(ip))))
          None => Bool(has_property(r, s(l)))
        }
      } else {
        raise @errors.TypeError(
          message="Cannot use 'in' operator to search for '\{l.to_string()}' in \{type_of(r)}",
        )
      }
    // And/Or/?? already handled in eval_binary
    (And, _, _) | (Or, _, _) | (NullishCoalesce, _, _) =>
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
        match data.bag.symbol_properties.get(symbol_id) {
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
pub fn instanceof_prototype_chain(
  l : Value,
  target_proto : Value,
  interp : Interpreter,
) -> Value raise Error {
  let mut current = match l {
    Object(l_data) => l_data.prototype
    Array(data) =>
      match get_array_prototype_override(data) {
        Some(proto) => proto
        None => interp.realm_state.get_array_proto()
      }
    Map(data) =>
      data.prototype.unwrap_or_else(fn() { interp.realm_state.get_map_proto() })
    Set(data) =>
      data.prototype.unwrap_or_else(fn() { interp.realm_state.get_set_proto() })
    Promise(data) =>
      data.prototype.unwrap_or_else(fn() {
        interp.realm_state.get_promise_proto()
      })
    // Invoke the [[GetPrototypeOf]] trap so Proxy handler can intercept
    Proxy(proxy_data) => proxy_get_prototype_of(interp, proxy_data)
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
            // Invoke [[GetPrototypeOf]] trap when proxy appears in the chain
            Proxy(proxy_data) =>
              current = proxy_get_prototype_of(interp, proxy_data)
            _ => break
          }
        }
    }
  }
  Bool(found)
}

///|
pub fn get_array_prototype(realm_state : RealmState, arr : ArrayData) -> Value {
  match get_array_prototype_override(arr) {
    Some(proto) => proto
    None => realm_state.get_array_proto()
  }
}

///|
pub fn strict_equal(a : Value, b : Value) -> Bool {
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
fn loose_equal(
  a : Value,
  b : Value,
  interp? : Interpreter? = None,
) -> Bool raise Error {
  // Abstract Equality Comparison Algorithm (ES spec §7.2.14)
  match (a, b) {
    // Same type: use strict equality
    (Number(x), Number(y)) => x == y
    (String_(x), String_(y)) => x == y
    (Bool(x), Bool(y)) => x == y
    (Null, Null) => true
    (Undefined, Undefined) => true
    (Object(x), Object(y)) => physical_equal(x, y)
    (Array(x), Array(y)) => physical_equal(x, y)
    (Symbol(x), Symbol(y)) => x.id == y.id
    (Promise(x), Promise(y)) => physical_equal(x, y)
    (Proxy(x), Proxy(y)) => physical_equal(x, y)
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
    // Boolean == anything: convert boolean to number first (§7.2.14 step 9/10)
    (Bool(bval), _) =>
      loose_equal(Number(if bval { 1.0 } else { 0.0 }), b, interp~)
    (_, Bool(bval)) =>
      loose_equal(a, Number(if bval { 1.0 } else { 0.0 }), interp~)
    // Object == primitive: ToPrimitive with hint "default" (§7.2.14 steps 10-11)
    (Object(data), Number(_))
    | (Object(data), String_(_))
    | (Object(data), Symbol(_)) => {
      let prim = to_primitive_default(a, data, interp~)
      loose_equal(prim, b, interp~)
    }
    (Number(_), Object(data))
    | (String_(_), Object(data))
    | (Symbol(_), Object(data)) => {
      let prim = to_primitive_default(b, data, interp~)
      loose_equal(a, prim, interp~)
    }
    // Array == primitive: ToPrimitive with hint "default" (§7.2.14 steps 10-11)
    (Array(_), Number(_)) | (Array(_), String_(_)) | (Array(_), Symbol(_)) => {
      let prim = to_primitive_default_array(a, interp~)
      loose_equal(prim, b, interp~)
    }
    (Number(_), Array(_)) | (String_(_), Array(_)) | (Symbol(_), Array(_)) => {
      let prim = to_primitive_default_array(b, interp~)
      loose_equal(a, prim, interp~)
    }
    // Symbols don't coerce to other primitive types
    (Symbol(_), _) | (_, Symbol(_)) => false
    // Everything else is false
    _ => false
  }
}

///|
fn delete_string_property_from_bag(
  bag : PropertyBag,
  prop : String,
  strict : Bool,
) -> Bool raise Error {
  match bag.descriptors.get(prop) {
    Some(desc) =>
      if !desc.configurable {
        if strict {
          raise @errors.TypeError(message="Cannot delete property '\{prop}'")
        }
        return false
      }
    None => ()
  }
  let _ = bag.properties.remove(prop)
  let _ = bag.descriptors.remove(prop)
  true
}

///|
fn delete_symbol_property_from_bag(
  bag : PropertyBag,
  sym_id : Int,
  strict : Bool,
) -> Bool raise Error {
  match bag.symbol_descriptors.get(sym_id) {
    Some(desc) =>
      if !desc.configurable {
        if strict {
          raise @errors.TypeError(message="Cannot delete property")
        }
        return false
      }
    None => ()
  }
  let _ = bag.symbol_properties.remove(sym_id)
  let _ = bag.symbol_descriptors.remove(sym_id)
  true
}

///|
fn mark_array_hole_if_index(data : ArrayData, prop : String) -> Unit {
  let idx = @string.parse_int(prop) catch { _ => -1 }
  if idx >= 0 && idx.to_string() == prop && idx < data.elements.length() {
    data.holes.set(idx, ())
    data.elements[idx] = Undefined
  }
}

///|
fn delete_typedarray_string_property(
  interp : Interpreter,
  data : ObjectData,
  prop : String,
  strict : Bool,
) -> Bool raise Error {
  match classify_typedarray_string_key(prop) {
    Some(idx) =>
      if idx >= 0 &&
        (interp.stdlib_hooks.typedarray_is_valid_index)(
          data,
          idx,
          interp.realm_state,
        ) {
        if strict {
          raise @errors.TypeError(message="Cannot delete property '\{prop}'")
        }
        false
      } else {
        true
      }
    None => delete_string_property_from_bag(data.bag, prop, strict)
  }
}

///|
pub fn Interpreter::delete_property_key(
  self : Interpreter,
  obj : Value,
  key : Value,
  strict? : Bool = false,
) -> Bool raise Error {
  let prop_key = to_property_key(key, interp=Some(self))
  match obj {
    Proxy(proxy_data) => {
      let result = proxy_delete_property_key(self, proxy_data, prop_key)
      if !result && strict {
        raise @errors.TypeError(message="Cannot delete property")
      }
      result
    }
    Object(data) =>
      match prop_key {
        Symbol(sym) => delete_symbol_property_from_bag(data.bag, sym.id, strict)
        String_(prop) if is_typedarray_class(data.class_name) =>
          delete_typedarray_string_property(self, data, prop, strict)
        String_(prop) => delete_string_property_from_bag(data.bag, prop, strict)
        _ => true
      }
    Array(data) =>
      match prop_key {
        Symbol(sym) => delete_symbol_property_from_bag(data.bag, sym.id, strict)
        String_("length") => {
          if strict {
            raise @errors.TypeError(message="Cannot delete property 'length'")
          }
          false
        }
        String_(prop) => {
          let result = delete_string_property_from_bag(data.bag, prop, strict)
          if result {
            mark_array_hole_if_index(data, prop)
          }
          result
        }
        _ => true
      }
    Map(data) =>
      match prop_key {
        Symbol(sym) => delete_symbol_property_from_bag(data.bag, sym.id, strict)
        String_(prop) => delete_string_property_from_bag(data.bag, prop, strict)
        _ => true
      }
    Set(data) =>
      match prop_key {
        Symbol(sym) => delete_symbol_property_from_bag(data.bag, sym.id, strict)
        String_(prop) => delete_string_property_from_bag(data.bag, prop, strict)
        _ => true
      }
    Promise(data) =>
      match prop_key {
        Symbol(sym) => delete_symbol_property_from_bag(data.bag, sym.id, strict)
        String_(prop) => delete_string_property_from_bag(data.bag, prop, strict)
        _ => true
      }
    Undefined | Null =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    _ => true
  }
}

///|
pub fn eval_delete_property(
  interp : Interpreter,
  obj : Value,
  prop : String,
  strict : Bool,
) -> Value raise Error {
  Bool(interp.delete_property_key(obj, String_(prop), strict~))
}

///|
pub fn eval_delete_computed_property(
  interp : Interpreter,
  obj : Value,
  key : Value,
  strict : Bool,
) -> Value raise Error {
  Bool(interp.delete_property_key(obj, key, strict~))
}

///|
fn env_delete_binding_ignoring_with(env : Environment, name : String) -> Bool {
  if env.bindings.contains(name) {
    let _ = env.bindings.remove(name)
    true
  } else {
    match env.parent {
      Some(parent) => env_delete_binding_ignoring_with(parent, name)
      None => false
    }
  }
}

///|
pub fn eval_delete_identifier(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  name : String,
) -> Value raise Error {
  // delete of an unqualified identifier is a SyntaxError in strict mode
  if ctx.strict {
    raise @errors.SyntaxError(
      message="Delete of an unqualified identifier in strict mode.",
    )
  }
  // Check if this identifier is in a with-object first.
  match env.find_with_object(name) {
    Some(with_obj) => Bool(interp.delete_property_key(with_obj, String_(name)))
    None =>
      match env.resolve_binding_env(name) {
        Some(target_env) =>
          if target_env.has_marker_in_chain(eval_deletable_var_marker(name)) {
            // Only delete if target_env actually has the eval-created var
            // binding. resolve_binding_env may have returned a shadowing
            // let/const from an inner scope — we must not delete that.
            match target_env.bindings.get(name) {
              Some(binding) if binding.kind == VarBinding => {
                let _ = env_delete_binding_ignoring_with(target_env, name)
                // Also remove the globalThis mirror if the target is the
                // global environment. eval-created vars are mirrored to
                // globalThis, and the deleted env binding alone would
                // still be reachable via the global property fallback.
                if target_env.parent is None {
                  match interp.global_this {
                    Object(data) => {
                      let _ = data.bag.properties.remove(name)
                      let _ = data.bag.descriptors.remove(name)
                    }
                    _ => ()
                  }
                }
                Bool(true)
              }
              _ => Bool(false)
            }
          } else if target_env.parent is None {
            // Only delete if the binding is a VarBinding, not let/const.
            // A global let/const is non-configurable and must not be
            // deleted even when globalThis has a configurable property
            // with the same name (e.g. after defineProperty).
            match target_env.bindings.get(name) {
              Some(binding) if binding.kind == VarBinding =>
                match interp.global_this {
                  Object(data) =>
                    match data.bag.descriptors.get(name) {
                      Some(desc) if desc.configurable => {
                        let _ = env_delete_binding_ignoring_with(
                          target_env, name,
                        )
                        let _ = data.bag.properties.remove(name)
                        let _ = data.bag.descriptors.remove(name)
                        Bool(true)
                      }
                      _ => Bool(false)
                    }
                  _ => Bool(false)
                }
              _ => Bool(false)
            }
          } else {
            Bool(false)
          }
        None =>
          // In non-strict mode, check if the identifier is a non-configurable
          // property on the global object (e.g. undefined, NaN, Infinity).
          match interp.global_this {
            Object(data) =>
              match data.bag.descriptors.get(name) {
                Some(desc) =>
                  if !desc.configurable {
                    Bool(false)
                  } else {
                    let _ = data.bag.properties.remove(name)
                    let _ = data.bag.descriptors.remove(name)
                    Bool(true)
                  }
                None => {
                  let _ = data.bag.properties.remove(name)
                  Bool(true)
                }
              }
            _ => Bool(true)
          }
      }
  }
}

///|
/// Check whether `name` is a non-writable property on the global object
/// (undefined, NaN, Infinity). These are { writable:false } per ES spec §19.1.
fn Interpreter::is_immutable_global(self : Interpreter, name : String) -> Bool {
  match self.global_this {
    Object(data) =>
      match data.bag.descriptors.get(name) {
        Some(desc) => !desc.writable
        None => false
      }
    _ => false
  }
}

///|
fn Interpreter::eval_unary(
  self : Interpreter,
  ctx : ExecContext,
  op : @ast.UnaryOp,
  operand : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  match op {
    Typeof =>
      match operand {
        Ident(name, _) => {
          @static_semantics.validate_strict_identifier_reference(
            ctx.strict,
            name,
          )
          if env.has(name) {
            String_(type_of(env.get(name)))
          } else {
            // Also check global object for properties
            match self.global_this {
              Object(data) =>
                match data.bag.properties.get(name) {
                  Some(v) => String_(type_of(v))
                  None => String_("undefined")
                }
              _ => String_("undefined")
            }
          }
        }
        _ => String_(type_of(self.eval_expr(ctx, operand, env)))
      }
    Void => {
      let _ = self.eval_expr(ctx, operand, env)
      Undefined
    }
    Delete =>
      match operand {
        Member(obj_expr, prop, _) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          eval_delete_property(self, obj, prop, ctx.strict)
        }
        ComputedMember(obj_expr, key_expr, _) => {
          let obj = self.eval_expr(ctx, obj_expr, env)
          let key = self.eval_expr(ctx, key_expr, env)
          eval_delete_computed_property(self, obj, key, ctx.strict)
        }
        OptionalMember(obj_expr, prop, _) => {
          // delete o?.x: evaluate obj_expr directly, check nullish, delete
          let obj = self.eval_expr(ctx, obj_expr, env)
          match obj {
            Null | Undefined => Bool(true)
            _ => eval_delete_property(self, obj, prop, ctx.strict)
          }
        }
        OptionalComputedMember(obj_expr, key_expr, _) => {
          // delete o?.[x]: evaluate obj_expr directly, check nullish, delete
          let obj = self.eval_expr(ctx, obj_expr, env)
          match obj {
            Null | Undefined => Bool(true)
            _ => {
              let key = self.eval_expr(ctx, key_expr, env)
              eval_delete_computed_property(self, obj, key, ctx.strict)
            }
          }
        }
        ChainMember(obj_expr, prop, _) => {
          // delete chain-member: evaluate chain up to base object, delete prop
          let (obj, short_circuited) = self.eval_chain_expr(ctx, obj_expr, env)
          if short_circuited {
            Bool(true)
          } else {
            eval_delete_property(self, obj, prop, ctx.strict)
          }
        }
        ChainComputedMember(obj_expr, key_expr, _) => {
          let (obj, short_circuited) = self.eval_chain_expr(ctx, obj_expr, env)
          if short_circuited {
            Bool(true)
          } else {
            let key = self.eval_expr(ctx, key_expr, env)
            eval_delete_computed_property(self, obj, key, ctx.strict)
          }
        }
        Ident(name, _) => eval_delete_identifier(self, ctx, env, name)
        Grouping(inner, _) =>
          // Preserve delete semantics: `delete (expr)` evaluates `expr`
          // with delete semantics, not as a plain value read.
          self.eval_unary(ctx, Delete, inner, env, loc)
        SuperMember(_, _) => {
          // Must evaluate the this-value before throwing, so TDZ and
          // null/undefined checks for the super-base are performed.
          let _ = eval_this_value(env)
          raise @errors.ReferenceError(
            message="Cannot delete a super property reference",
          )
        }
        SuperComputedMember(key_expr, _) => {
          let _ = eval_this_value(env)
          let _ = self.eval_expr(ctx, key_expr, env)
          raise @errors.ReferenceError(
            message="Cannot delete a super property reference",
          )
        }
        _ => {
          let _ = self.eval_expr(ctx, operand, env)
          Bool(true)
        }
      }
    _ => {
      let val = self.eval_expr(ctx, operand, env)
      eval_unary_value_op(op, val, loc, interp=Some(self))
    }
  }
}

///|
fn format_loc_context(message : String, loc : @token.Loc) -> String {
  message + " at line \{loc.line}, col \{loc.col}"
}
