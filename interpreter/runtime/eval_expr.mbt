///|
/// Resolve the target of a `super.x` / `super[k]` access (ES2022 §13.3.7.1
/// MakeSuperPropertyReference).
///
/// Per spec, super resolves via the method's [[HomeObject]] at *call* time:
/// `Object.getPrototypeOf(homeObject)`. Object-literal methods bind
/// [[HomeObject]] to the live object, so `Object.setPrototypeOf` after
/// creation is honored.
///
/// Class methods still bind [[SuperPrototype]] (a compile-time snapshot of
/// the super-class's prototype) for backwards compatibility — a class's
/// super target rarely shifts after creation, and migrating class machinery
/// to [[HomeObject]] is left for a separate change.
fn resolve_super_target(env : Environment) -> Value {
  let home = env.get("[[HomeObject]]") catch { _ => Undefined }
  match home {
    Object(data) => return data.prototype
    _ => ()
  }
  env.get("[[SuperPrototype]]") catch {
    _ => Undefined
  }
}

///|
fn pattern_may_contain_yield(pattern : @ast.Pattern) -> Bool {
  match pattern {
    IdentPat(_) => false
    ArrayPat(elements, rest) => {
      let elements_have_yield = elements
        .iter()
        .any(fn(pat) {
          match pat {
            Some(pat) => pattern_may_contain_yield(pat)
            None => false
          }
        })
      let rest_has_yield = match rest {
        Some(pat) => pattern_may_contain_yield(pat)
        None => false
      }
      elements_have_yield || rest_has_yield
    }
    ObjectPat(props, rest) => {
      let props_have_yield = props
        .iter()
        .any(fn(prop) {
          let key_has_yield = match prop.computed_key {
            Some(expr) => expr_may_contain_yield(expr)
            None => false
          }
          let default_has_yield = match prop.default_val {
            Some(expr) => expr_may_contain_yield(expr)
            None => false
          }
          key_has_yield ||
          default_has_yield ||
          pattern_may_contain_yield(prop.value)
        })
      let rest_has_yield = match rest {
        Some(pat) => pattern_may_contain_yield(pat)
        None => false
      }
      props_have_yield || rest_has_yield
    }
    DefaultPat(inner, default_expr) =>
      pattern_may_contain_yield(inner) || expr_may_contain_yield(default_expr)
    AssignTarget(expr) => expr_may_contain_yield(expr)
  }
}

///|
fn expr_may_contain_yield(expr : @ast.Expr) -> Bool {
  match expr {
    YieldExpr(_, _, _) => true
    Grouping(inner, _)
    | Unary(_, inner, _)
    | SpreadExpr(inner, _)
    | AwaitExpr(inner, _) => expr_may_contain_yield(inner)
    Binary(_, left, right, _)
    | Comma(left, right, _)
    | ComputedMember(left, right, _)
    | MemberAssign(left, _, right, _)
    | CompoundAssign(_, left, right, _) =>
      expr_may_contain_yield(left) || expr_may_contain_yield(right)
    Ternary(cond, then_expr, else_expr, _) =>
      expr_may_contain_yield(cond) ||
      expr_may_contain_yield(then_expr) ||
      expr_may_contain_yield(else_expr)
    Assign(_, value, _)
    | Member(value, _, _)
    | UpdateExpr(_, value, _, _)
    | SuperComputedMember(value, _) => expr_may_contain_yield(value)
    DestructureAssign(pattern, value, _) =>
      pattern_may_contain_yield(pattern) || expr_may_contain_yield(value)
    ComputedAssign(obj, key, value, _) =>
      expr_may_contain_yield(obj) ||
      expr_may_contain_yield(key) ||
      expr_may_contain_yield(value)
    Call(callee, args, _)
    | NewExpr(callee, args, _)
    | OptionalCall(callee, args, _) =>
      expr_may_contain_yield(callee) || args.iter().any(expr_may_contain_yield)
    ArrayLit(elements, _) => elements.iter().any(expr_may_contain_yield)
    ObjectLit(props, _) =>
      props
      .iter()
      .any(fn(prop) {
        expr_may_contain_yield(prop.key) || expr_may_contain_yield(prop.value)
      })
    OptionalMember(obj, _, _) => expr_may_contain_yield(obj)
    OptionalComputedMember(obj, key, _) =>
      expr_may_contain_yield(obj) || expr_may_contain_yield(key)
    TemplateLit(_, exprs, _) => exprs.iter().any(expr_may_contain_yield)
    TaggedTemplate(tag, _, exprs, _) =>
      expr_may_contain_yield(tag) || exprs.iter().any(expr_may_contain_yield)
    ClassExpr(_, superclass, members, _) => {
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
          }
        })
      super_has_yield || members_have_yield
    }
    _ => false
  }
}

///|
// In subclass construction, align a super constructor return value with the
// calling class instance's prototype for built-in super constructors
// (Array/Map/Set/Promise).
fn apply_super_return_prototype(super_result : Value, this_val : Value) -> Unit {
  let target_proto : Value? = match this_val {
    Object(data) => Some(data.prototype)
    _ => None
  }
  match target_proto {
    Some(proto) =>
      match super_result {
        Object(data) => data.prototype = proto
        Array(data) => set_array_prototype_override(data, proto)
        Map(data) => data.prototype = proto
        Set(data) => data.prototype = proto
        Promise(data) => data.prototype = proto
        _ => ()
      }
    None => ()
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
  let key = Value::Symbol(sym)
  let mut current = proto
  while true {
    match current {
      Object(data) => {
        match data.bag.symbol_descriptors.get(sym.id) {
          Some(desc) =>
            match desc.getter {
              Some(getter) => return self.call_value(getter, receiver, [], loc)
              None => if desc.setter is Some(_) { return Undefined }
            }
          None => ()
        }
        match data.bag.symbol_properties.get(sym.id) {
          Some(value) => return value
          None => current = data.prototype
        }
      }
      Array(data) => {
        match data.bag.symbol_descriptors.get(sym.id) {
          Some(desc) =>
            match desc.getter {
              Some(getter) => return self.call_value(getter, receiver, [], loc)
              None => if desc.setter is Some(_) { return Undefined }
            }
          None => ()
        }
        match get_array_symbol_prop(data, sym.id) {
          Some(value) => return value
          None => current = get_array_prototype(self.realm_state, data)
        }
      }
      Proxy(proxy_data) =>
        match get_proxy_trap(proxy_data, "get", self) {
          Some(trap_fn) => {
            let target = get_proxy_target(proxy_data)
            let handler = get_proxy_handler(proxy_data)
            return self.call_value(
              trap_fn,
              handler,
              [target, key, receiver],
              loc,
            )
          }
          None => current = get_proxy_target(proxy_data)
        }
      Null => return Undefined
      _ => return self.get_computed_property(current, key, loc)
    }
  }
  Undefined
}

///|
fn Interpreter::get_computed_property_from_prototype(
  self : Interpreter,
  receiver : Value,
  proto : Value,
  key : Value,
  loc : @token.Loc,
) -> Value raise Error {
  match key {
    Symbol(sym) =>
      self.get_symbol_property_from_prototype(receiver, proto, sym, loc)
    _ =>
      self.get_property_from_prototype(
        receiver,
        proto,
        to_js_string(key, interp=Some(self)),
        loc,
      )
  }
}

///|
pub fn Interpreter::eval_super_property(
  self : Interpreter,
  env : Environment,
  prop : String,
  loc : @token.Loc,
) -> Value raise Error {
  let super_proto = resolve_super_target(env)
  match super_proto {
    Null | Undefined =>
      raise @errors.ReferenceError(
        message="super.prop used but no [[SuperPrototype]] in scope at line \{loc.line}",
      )
    _ => {
      let this_val = eval_this_value(env)
      self.get_property_from_prototype(this_val, super_proto, prop, loc)
    }
  }
}

///|
pub fn Interpreter::eval_super_computed_property(
  self : Interpreter,
  env : Environment,
  key : Value,
  loc : @token.Loc,
) -> Value raise Error {
  let super_proto = resolve_super_target(env)
  match super_proto {
    Null | Undefined =>
      raise @errors.ReferenceError(
        message="super[expr] used but no [[SuperPrototype]] in scope at line \{loc.line}",
      )
    _ => {
      let this_val = eval_this_value(env)
      self.get_computed_property_from_prototype(this_val, super_proto, key, loc)
    }
  }
}

///|
pub fn Interpreter::eval_super_property_call_reference(
  self : Interpreter,
  env : Environment,
  prop : String,
  loc : @token.Loc,
) -> (Value, Value) raise Error {
  let super_proto = resolve_super_target(env)
  match super_proto {
    Null | Undefined =>
      raise @errors.ReferenceError(
        message="super.prop used but no [[SuperPrototype]] in scope at line \{loc.line}",
      )
    _ => {
      let this_val = eval_this_value(env)
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
  let super_proto = resolve_super_target(env)
  match super_proto {
    Null | Undefined =>
      raise @errors.ReferenceError(
        message="super[expr] used but no [[SuperPrototype]] in scope at line \{loc.line}",
      )
    _ => {
      let this_val = eval_this_value(env)
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
      FuncExpr(name, params, body, _) => {
        validate_function_signature(ctx.strict, None, params, body)
        let func_data : FuncData = {
          name,
          params,
          body,
          closure: method_env,
          strict: is_function_strict(ctx.strict, body),
          has_name_binding: false,
          is_method: true,
        }
        return make_func(func_data)
      }
      FuncExprExt(name, params, rest_param, body, _) => {
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
        }
        return make_func_ext(func_data)
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
pub fn make_tagged_template_object(strings : Array[String]) -> Value {
  let raw_vals : Array[Value] = []
  for s in strings {
    raw_vals.push(String_(s))
  }
  let raw_arr = make_array(raw_vals)
  freeze_template_array(raw_arr)
  let template_obj = make_array(raw_vals.copy())
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
  strings : Array[String],
) -> String {
  let buf = StringBuilder::new()
  buf.write_string(loc.line.to_string())
  buf.write_string(":")
  buf.write_string(loc.col.to_string())
  buf.write_string(":")
  buf.write_string(loc.offset.to_string())
  for s in strings {
    buf.write_string(":")
    buf.write_string(s.length().to_string())
    buf.write_string(":")
    buf.write_string(s)
  }
  buf.to_string()
}

///|
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
  strings : Array[String],
) -> Value {
  let cache = self.get_template_object_cache()
  match cache.bag.properties.get(key) {
    Some(value) => value
    None => {
      let value = make_tagged_template_object(strings)
      cache.bag.properties[key] = value
      value
    }
  }
}

///|
fn Interpreter::get_tagged_template_object(
  self : Interpreter,
  loc : @token.Loc,
  strings : Array[String],
) -> Value {
  self.get_cached_tagged_template_object(
    tagged_template_cache_key(loc, strings),
    strings,
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
  let (properties, symbol_properties) = match target {
    Object(data) => (data.bag.properties, data.bag.symbol_properties)
    _ =>
      raise @errors.InternalError(
        message="object spread target was not an object",
      )
  }
  match source {
    Object(data) => {
      // Copy all enumerable own properties. Per ES spec, spread invokes [[Get]]
      // (which triggers getters) and creates data properties (not accessor
      // descriptors).
      for key, raw_value in data.bag.properties {
        match data.bag.descriptors.get(key) {
          Some(desc) =>
            if desc.enumerable {
              let val : Value = match desc.getter {
                Some(getter) => self.call_value(getter, source, [], loc)
                None => raw_value
              }
              properties[key] = val
            }
          None => properties[key] = raw_value
        }
      }
      // Copy symbol properties too, matching the existing object-literal spread
      // path's descriptor handling.
      for sym_id, value in data.bag.symbol_properties {
        match data.bag.symbol_descriptors.get(sym_id) {
          Some(desc) => if desc.enumerable { symbol_properties[sym_id] = value }
          None => symbol_properties[sym_id] = value
        }
      }
    }
    Array(arr_data) =>
      // Spread array into object: only enumerable own properties. The current
      // interpreter representation treats dense element slots as enumerable.
      for i, value in arr_data.elements {
        properties[i.to_string()] = value
      }
    String_(s) => {
      // Spread string into object: { ..."abc" } -> { "0": "a", "1": "b" }.
      let mut idx = 0
      for ch in s {
        properties[idx.to_string()] = String_(ch.to_string())
        idx = idx + 1
      }
    }
    Null | Undefined => () // Skip null/undefined per spec.
    Number(_) | Bool(_) => () // Primitives have no enumerable own properties.
    _ => ()
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
      validate_strict_identifier_reference(ctx.strict, name)
      env.get(name) catch {
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
      validate_strict_assignment_target_name(ctx.strict, name)
      let value = self.eval_expr(ctx, value_expr, env)
      // SetFunctionName for assignments: x = function() {} gives name "x"
      if is_anonymous_function_definition(value_expr) {
        set_function_name(value, name)
      }
      // Check if the target is a non-writable property on the global object
      // (e.g. undefined, NaN, Infinity). In strict mode this is a TypeError;
      // in non-strict mode the assignment is silently ignored.
      if self.is_immutable_global(name) {
        if ctx.strict {
          raise @errors.TypeError(
            message="Cannot assign to read only property '\{name}' of object '[object global]'",
          )
        }
        return value
      }
      env.assign(name, value) catch {
        @errors.ReferenceError(message~) =>
          // In non-strict mode, assigning to an undeclared variable creates
          // a global property (sloppy mode implicit global). TDZ errors
          // ("Cannot access before initialization") must propagate as-is.
          if !ctx.strict && message == "\{name} is not defined" {
            self.global.def(name, value, VarBinding)
            // Also mirror onto globalThis as a configurable, enumerable property
            self.mirror_to_global(name, value, configurable=true)
          } else {
            raise @errors.ReferenceError(message~)
          }
        e => raise e
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
    FuncExpr(name, params, body, _) => {
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
      }
      make_func(func_data)
    }
    GeneratorExpr(name, params, body, _) => {
      validate_function_signature(ctx.strict, name, params, body)
      let strict = is_function_strict(ctx.strict, body)
      self.make_generator_function(name, params, None, body, strict, env)
    }
    GeneratorExprExt(name, params, rest_param, body, _) => {
      validate_function_signature_ext(
        ctx.strict,
        name,
        params,
        rest_param,
        body,
      )
      let strict = is_function_strict(ctx.strict, body)
      self.make_generator_function_ext(
        name, params, rest_param, body, strict, env,
      )
    }
    AsyncFuncExpr(name, params, body, _) => {
      validate_function_signature(ctx.strict, name, params, body)
      let strict = is_function_strict(ctx.strict, body)
      self.make_async_function(name, params, None, body, strict, env)
    }
    AsyncFuncExprExt(name, params, rest_param, body, _) => {
      validate_function_signature_ext(
        ctx.strict,
        name,
        params,
        rest_param,
        body,
      )
      let strict = is_function_strict(ctx.strict, body)
      self.make_async_function_ext(name, params, rest_param, body, strict, env)
    }
    AsyncArrowFunc(params, body, _) => {
      validate_function_signature(ctx.strict, None, params, body)
      let strict = is_function_strict(ctx.strict, body)
      self.make_async_function(None, params, None, body, strict, env)
    }
    AsyncArrowFuncExt(params, rest_param, body, _) => {
      validate_function_signature_ext(
        ctx.strict,
        None,
        params,
        rest_param,
        body,
      )
      let strict = is_function_strict(ctx.strict, body)
      self.make_async_function_ext(None, params, rest_param, body, strict, env)
    }
    AsyncGeneratorExpr(name, params, body, _) => {
      validate_function_signature(ctx.strict, name, params, body)
      let strict = is_function_strict(ctx.strict, body)
      self.make_async_generator_function(name, params, None, body, strict, env)
    }
    AsyncGeneratorExprExt(name, params, rest_param, body, _) => {
      validate_function_signature_ext(
        ctx.strict,
        name,
        params,
        rest_param,
        body,
      )
      let strict = is_function_strict(ctx.strict, body)
      self.make_async_generator_function_ext(
        name, params, rest_param, body, strict, env,
      )
    }
    AwaitExpr(argument, _) =>
      // await acts like yield inside the generator that backs the async function
      self.eval_yield(ctx, Some(argument), false, env)
    YieldExpr(argument, delegate, _) =>
      self.eval_yield(ctx, argument, delegate, env)
    ObjectLit(props, obj_loc) => {
      let properties : Map[String, Value] = {}
      let symbol_properties : Map[Int, Value] = {}
      let descriptors : Map[String, PropDescriptor] = {}
      let symbol_descriptors : Map[Int, PropDescriptor] = {}
      // Build the object eagerly so methods captured during the prop loop can
      // reference it as [[HomeObject]] (ES2022 §13.2.5.5). The bag's Maps are
      // shared by reference, so later inserts populate the live object; the
      // mutable `prototype` field is updated when a __proto__ override is seen.
      // This is what makes `super.x` resolve dynamically against
      // `Object.getPrototypeOf(homeObject)` even after Object.setPrototypeOf is
      // called on the literal.
      let default_obj_proto = env.get("[[ObjectPrototype]]") catch { _ => Null }
      let object_data : ObjectData = {
        bag: { properties, symbol_properties, descriptors, symbol_descriptors },
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
                  let val = self.eval_prop_value(ctx, prop, method_env)
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
                  let val = self.eval_prop_value(ctx, prop, method_env)
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
                let val = self.eval_prop_value(ctx, prop, method_env)
                // SetFunctionName: infer name for anonymous functions
                set_function_name(val, key_str)
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
    ComputedAssign(obj_expr, key_expr, value_expr, loc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let key = self.eval_expr(ctx, key_expr, env)
      let value = self.eval_expr(ctx, value_expr, env)
      self.set_computed_property(obj, key, value, loc, strict=ctx.strict)
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
    TemplateLit(strings, exprs, _) => {
      let buf = StringBuilder::new()
      for i = 0; i < strings.length(); i = i + 1 {
        buf.write_string(strings[i])
        if i < exprs.length() {
          let val = self.eval_expr(ctx, exprs[i], env)
          buf.write_string(to_js_string(val, interp=Some(self)))
        }
      }
      String_(buf.to_string())
    }
    TaggedTemplate(tag_expr, strings, exprs, loc) => {
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
      let args : Array[Value] = [self.get_tagged_template_object(loc, strings)]
      for e in exprs {
        args.push(self.eval_expr(ctx, e, env))
      }
      self.call_value(tag, this_val, args, loc)
    }
    ArrowFunc(params, body, _) => {
      validate_function_signature(ctx.strict, None, params, body)
      let func_data : FuncData = {
        name: None,
        params,
        body,
        closure: env,
        strict: is_function_strict(ctx.strict, body),
        has_name_binding: false,
        is_method: false,
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
            symbol_properties: {},
            descriptors: { "name": nf_desc, "length": nf_desc },
            symbol_descriptors: {},
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
    ArrowFuncExt(params, rest_param, body, _) => {
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
            symbol_properties: {},
            descriptors: { "name": nf_desc, "length": nf_desc },
            symbol_descriptors: {},
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
    FuncExprExt(name, params, rest_param, body, _) => {
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
    OptionalCall(callee_expr, arg_exprs, loc) =>
      // func?.(args) - return undefined if func is null/undefined
      // Per ES spec, arguments are NOT evaluated if function is nullish
      // Need to preserve receiver for method calls
      match callee_expr {
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
    ClassExpr(name, superclass, methods, _) => {
      // For named class expressions, the name is visible inside the class body
      // but not in the outer scope. Create a new scope for this.
      let class_name = name.unwrap_or("")
      let class_env = if class_name != "" {
        let inner = Environment::new(parent=Some(env))
        // Pre-define the name (will be set after class creation)
        inner.def(class_name, Undefined, LetBinding)
        inner
      } else {
        env
      }
      let class_val = self.create_class(
        ctx, class_name, superclass, methods, class_env,
      )
      // Set the class name binding in the inner scope
      if class_name != "" {
        class_env.assign(class_name, class_val) catch {
          _ => ()
        }
      }
      class_val
    }
    SuperCall(arg_exprs, loc) => {
      // super(args) - call the parent constructor
      // Get the [[HomeObject]] from the current environment
      let super_ctor = env.get("[[SuperConstructor]]")
      // Use [[PendingThis]] if 'this' is in TDZ (derived class before super())
      let this_val = if env.has("[[PendingThis]]") {
        env.get("[[PendingThis]]")
      } else {
        env.get("this")
      }
      let super_new_target = env.get("<new.target>") catch { _ => Undefined }
      let args = self.eval_args_with_spread(ctx, arg_exprs, env)
      // Call the super constructor
      match super_ctor {
        Object(data) =>
          match data.callable {
            Some(
              ClassConstructor(
                {
                  super_ctor: _super_ctor,
                  instance_fields: super_instance_fields,
                  ctor_fn,
                  closure: ctor_closure,
                  super_proto,
                  ..,
                }
              )
            ) => {
              // Create new environment for the super constructor body
              let call_env = Environment::new(parent=Some(ctor_closure))
              call_env.def_builtin("this", this_val)
              // §10.2.2 step 4: new.target in super constructor = derived class's new.target
              call_env.def(
                "<new.target>",
                env.get("<new.target>") catch {
                  _ => Undefined
                },
                LetBinding,
              )
              // Set up super chain and handle super's own instance fields
              match _super_ctor {
                Some(grand_super) => {
                  call_env.def_builtin("[[SuperConstructor]]", grand_super)
                  call_env.def_builtin("[[SuperPrototype]]", super_proto)
                  // Super is also derived: defer its fields until its own super() returns
                  if super_instance_fields.length() > 0 {
                    call_env.def_builtin(
                      "[[InitInstanceFields]]",
                      make_instance_fields_init(
                        super_instance_fields,
                        self.realm_state,
                      ),
                    )
                  }
                }
                None =>
                  // Super is a base class: initialize its fields before its body
                  self.install_instance_fields(this_val, super_instance_fields)
              }
              // Bind parameters and execute constructor body
              match ctor_fn {
                Some((ctor_params, _rest_param, ctor_body)) => {
                  for i = 0; i < ctor_params.length(); i = i + 1 {
                    let val : Value = if i < args.length() {
                      args[i]
                    } else {
                      Undefined
                    }
                    call_env.def_parameter(ctor_params[i].name, val)
                  }
                  let tte : Value? = if call_env.has("[[ThrowTypeError]]") {
                    Some(call_env.get("[[ThrowTypeError]]"))
                  } else {
                    None
                  }
                  call_env.def(
                    "arguments",
                    make_arguments_object(
                      self.realm_state,
                      self.realm_state.well_known_symbols,
                      args,
                      super_ctor,
                      true,
                      throw_type_error=tte,
                    ),
                    VarBinding,
                  )
                  self.hoist_declarations(ctor_body, call_env, strict=true)
                  hoist_block_tdz(ctor_body, call_env)
                  let super_ctor_ctx : ExecContext = {
                    strict: true,
                    current_generator: None,
                  }
                  let exec_result = self.exec_stmts(
                    super_ctor_ctx, ctor_body, call_env,
                  )
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
                          // Initialize 'this' (may be in TDZ for derived classes).
                          // Walk the chain: with the §10.2.11 param/body env
                          // split, 'this' lives on the caller's param env,
                          // not its body env.
                          env.initialize_in_chain("this", v)
                          // Apply calling class's instance fields to the override object
                          if env.has("[[InitInstanceFields]]") {
                            let init_fn = env.get("[[InitInstanceFields]]")
                            let _ = self.call_value(init_fn, v, [], loc)
                          }
                          return v
                        }
                        _ => ()
                      }
                    _ => ()
                  }
                }
                None => ()
              }
              // Initialize 'this' in the calling env (may be TDZ for derived classes)
              env.initialize_in_chain("this", this_val)
              // Apply calling class's instance fields after super() establishes this
              if env.has("[[InitInstanceFields]]") {
                let init_fn = env.get("[[InitInstanceFields]]")
                let actual_this = env.get("this")
                let _ = self.call_value(init_fn, actual_this, [], loc)
              }
              env.get("this")
            }
            Some(callable) => {
              // Support non-class constructible supers (e.g. built-in constructors like Error).
              // Use constructor semantics (`new`) instead of plain call.
              let align_builtin_super_result = match callable {
                NativeCallable(_, _)
                | NativeCallableWithContext(_, _)
                | InterpreterCallable(_, _)
                | InterpreterCallableWithContext(_, _)
                | ConstructorOnlyCallable(_, _) => true
                _ => false
              }
              let super_result = self.construct_value(
                super_ctor,
                args,
                loc,
                new_target=Some(super_new_target),
              )
              match super_result {
                Object(_)
                | Array(_)
                | Map(_)
                | Set(_)
                | Promise(_)
                | Proxy(_) => {
                  if align_builtin_super_result {
                    apply_super_return_prototype(super_result, this_val)
                  }
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
            _ =>
              raise @errors.ReferenceError(
                message=format_loc_context(
                  "super() called but [[SuperConstructor]] is not a constructor",
                  loc,
                ),
              )
          }
        Null =>
          // `extends null`: super() attempts Construct(null, ...) → TypeError
          raise @errors.TypeError(
            message=format_loc_context("null is not a constructor", loc),
          )
        _ =>
          raise @errors.ReferenceError(
            message=format_loc_context(
              "super() called but no [[SuperConstructor]] in scope", loc,
            ),
          )
      }
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
    In => {
      let left = self.eval_expr(ctx, left_expr, env)
      let right = self.eval_expr(ctx, right_expr, env)
      if is_object_value(right) {
        Bool(
          self.has_property_key(right, to_property_key(left, interp=Some(self))),
        )
      } else {
        raise @errors.TypeError(
          message="Cannot use 'in' operator to search for '\{left.to_string()}' in \{type_of(right)}",
        )
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
    (EqEq, l, r) => Bool(loose_equal(l, r))
    (NotEq, l, r) => Bool(!loose_equal(l, r))
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
      match data.prototype {
        Null => interp.realm_state.get_map_proto()
        proto => proto
      }
    Set(data) =>
      match data.prototype {
        Null => interp.realm_state.get_set_proto()
        proto => proto
      }
    Promise(data) =>
      match data.prototype {
        Null => interp.realm_state.get_promise_proto()
        proto => proto
      }
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
      let prim = to_primitive_number(a, data) catch {
        _ => String_(a.to_string())
      }
      loose_equal(prim, b)
    }
    (Number(_), Object(data)) | (String_(_), Object(data)) => {
      let prim = to_primitive_number(b, data) catch {
        _ => String_(b.to_string())
      }
      loose_equal(a, prim)
    }
    (Array(_), Number(_)) | (Array(_), String_(_)) => {
      let prim = String_(to_js_string(a)) catch { _ => String_(a.to_string()) }
      loose_equal(prim, b)
    }
    (Number(_), Array(_)) | (String_(_), Array(_)) => {
      let prim = String_(to_js_string(b)) catch { _ => String_(b.to_string()) }
      loose_equal(a, prim)
    }
    // Symbols don't coerce - any comparison with Symbol and different type is false
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
fn env_has_binding_ignoring_with(env : Environment, name : String) -> Bool {
  match env.bindings.get(name) {
    Some(_) => true
    None =>
      match env.parent {
        Some(parent) => env_has_binding_ignoring_with(parent, name)
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
  // Check if this identifier is in a with-object first
  match env.find_with_object(name) {
    Some(Object(with_data)) => {
      match with_data.bag.descriptors.get(name) {
        Some(desc) => if !desc.configurable { return Bool(false) }
        None => ()
      }
      let _ = with_data.bag.properties.remove(name)
      let _ = with_data.bag.descriptors.remove(name)
      Bool(true)
    }
    _ =>
      if env_has_binding_ignoring_with(env, name) {
        Bool(false)
      } else {
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
          validate_strict_identifier_reference(ctx.strict, name)
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
        Ident(name, _) => eval_delete_identifier(self, ctx, env, name)
        _ => Bool(true)
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
