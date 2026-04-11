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
    Ident(name, _) =>
      env.get(name) catch {
        @errors.ReferenceError(_) =>
          // Fallback: check global object (globalThis) for properties set via this.x = y
          match self.global_this {
            Object(data) =>
              match data.properties.get(name) {
                Some(v) => v
                None =>
                  raise @errors.ReferenceError(message="\{name} is not defined")
              }
            _ => raise @errors.ReferenceError(message="\{name} is not defined")
          }
        other => raise other
      }
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
      if is_anonymous_function_definition(value_expr) {
        set_function_name(value, name)
      }
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
      env.assign(name, value) catch {
        @errors.ReferenceError(_) =>
          // In non-strict mode, assigning to an undeclared variable creates
          // a global property (sloppy mode implicit global).
          if !self.strict {
            self.global.def(name, value, VarBinding)
            // Also mirror onto globalThis as a configurable, enumerable property
            self.mirror_to_global(name, value, configurable=true)
          } else {
            raise @errors.ReferenceError(message="\{name} is not defined")
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
      validate_function_signature_ext(
        self.strict,
        name,
        params,
        rest_param,
        body,
      )
      self.make_async_function_ext(name, params, rest_param, body, env)
    }
    AsyncArrowFunc(params, body, _) => {
      validate_function_signature(self.strict, None, params, body)
      self.make_async_function(None, params, None, body, env)
    }
    AsyncArrowFuncExt(params, rest_param, body, _) => {
      validate_function_signature_ext(
        self.strict,
        None,
        params,
        rest_param,
        body,
      )
      self.make_async_function_ext(None, params, rest_param, body, env)
    }
    AsyncGeneratorExpr(name, params, body, _) => {
      validate_function_signature(self.strict, name, params, body)
      self.make_async_generator_function(name, params, None, body, env)
    }
    AsyncGeneratorExprExt(name, params, rest_param, body, _) => {
      validate_function_signature_ext(
        self.strict,
        name,
        params,
        rest_param,
        body,
      )
      self.make_async_generator_function_ext(
        name, params, rest_param, body, env,
      )
    }
    AwaitExpr(argument, _) =>
      // await acts like yield inside the generator that backs the async function
      self.eval_yield(Some(argument), false, env)
    YieldExpr(argument, delegate, _) => self.eval_yield(argument, delegate, env)
    ObjectLit(props, obj_loc) => {
      let properties : Map[String, Value] = {}
      let symbol_properties : Map[Int, Value] = {}
      let descriptors : Map[String, PropDescriptor] = {}
      let symbol_descriptors : Map[Int, PropDescriptor] = {}
      let mut proto_override : Value? = None
      // Create a placeholder for the object being built so methods can reference it as [[HomeObject]]
      // The actual object will be stored after creation via the mutable ref
      // Create method environment for super.x support in object literal methods
      // Set [[SuperPrototype]] to Object.prototype as default
      let method_env = Environment::new(parent=Some(env))
      let default_obj_proto = env.get("[[ObjectPrototype]]") catch { _ => Null }
      method_env.def_builtin("[[SuperPrototype]]", default_obj_proto)
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
                  let val = self.eval_expr(prop.value, method_env)
                  // SetFunctionName with symbol description
                  let sym_name = match sym.description {
                    Some(d) => "[\{d}]"
                    None => ""
                  }
                  set_function_name(val, sym_name)
                  symbol_properties[sym.id] = val
                }
                Get => {
                  let getter = self.eval_expr(prop.value, method_env)
                  let sym_name = match sym.description {
                    Some(d) => "get [\{d}]"
                    None => "get "
                  }
                  set_function_name(getter, sym_name)
                  // Store accessor in descriptor, use Undefined as placeholder in properties
                  if !symbol_properties.contains(sym.id) {
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
                  let setter = self.eval_expr(prop.value, method_env)
                  let sym_name = match sym.description {
                    Some(d) => "set [\{d}]"
                    None => "set "
                  }
                  set_function_name(setter, sym_name)
                  if !symbol_properties.contains(sym.id) {
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
                  let val = self.eval_expr(prop.value, method_env)
                  set_function_name(val, key_str)
                  properties[key_str] = val
                }
                Get => {
                  let getter = self.eval_expr(prop.value, method_env)
                  set_function_name(getter, "get " + key_str)
                  if !properties.contains(key_str) {
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
                  let setter = self.eval_expr(prop.value, method_env)
                  set_function_name(setter, "set " + key_str)
                  if !properties.contains(key_str) {
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
            Ident(name, _) => name
            NumberLit(n, _) => {
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
                let val = self.eval_expr(prop.value, method_env)
                match val {
                  Object(_) | Array(_) | Map(_) | Set(_) =>
                    proto_override = Some(val)
                  Null => proto_override = Some(Null)
                  _ => properties[key_str] = val // primitives don't set proto
                }
              } else {
                let val = self.eval_expr(prop.value, method_env)
                // SetFunctionName: infer name for anonymous functions
                set_function_name(val, key_str)
                properties[key_str] = val
              }
            Get => {
              let getter = self.eval_expr(prop.value, method_env)
              // Force set name with "get " prefix per spec
              match getter {
                Object(d) => d.properties["name"] = String_("get " + key_str)
                _ => ()
              }
              if !properties.contains(key_str) {
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
              let setter = self.eval_expr(prop.value, method_env)
              // Force set name with "set " prefix per spec
              match setter {
                Object(d) => d.properties["name"] = String_("set " + key_str)
                _ => ()
              }
              if !properties.contains(key_str) {
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
      let result_obj = Object({
        properties,
        symbol_properties,
        prototype: obj_prototype,
        callable: None,
        class_name: "Object",
        descriptors,
        symbol_descriptors,
        extensible: true,
      })
      result_obj
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
    ThisExpr(_) =>
      env.get("this") catch {
        @errors.ReferenceError(message~) => {
          // In derived class constructors, 'this' is in TDZ until super() is called
          if message.contains("before initialization") {
            raise @errors.ReferenceError(
              message="Must call super constructor in derived class before accessing 'this' or returning from derived constructor",
            )
          }
          // Otherwise, 'this' is just not defined (global arrow function, etc.)
          Undefined
        }
        other => raise other
      }
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
        prototype: get_func_proto(),
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
        prototype: get_func_proto(),
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
        class_name, superclass, methods, class_env,
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
      let args = self.eval_args_with_spread(arg_exprs, env)
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
              // Set up super chain and handle super's own instance fields
              match _super_ctor {
                Some(grand_super) => {
                  call_env.def_builtin("[[SuperConstructor]]", grand_super)
                  call_env.def_builtin("[[SuperPrototype]]", super_proto)
                  // Super is also derived: defer its fields until its own super() returns
                  if super_instance_fields.length() > 0 {
                    call_env.def_builtin(
                      "[[InitInstanceFields]]",
                      make_instance_fields_init(super_instance_fields),
                    )
                  }
                }
                None =>
                  // Super is a base class: initialize its fields before its body
                  self.install_instance_fields(this_val, super_instance_fields)
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
                          // Initialize 'this' (may be in TDZ for derived classes)
                          env.initialize("this", v) catch {
                            _ => env.assign("this", v)
                          }
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
              env.initialize("this", this_val) catch {
                _ => env.assign("this", this_val) catch { _ => () }
              }
              // Apply calling class's instance fields after super() establishes this
              if env.has("[[InitInstanceFields]]") {
                let init_fn = env.get("[[InitInstanceFields]]")
                let actual_this = env.get("this")
                let _ = self.call_value(init_fn, actual_this, [], loc)
              }
              env.get("this")
            }
            Some(_) => {
              // Support non-class constructible supers (e.g. built-in constructors like Error).
              // Use constructor semantics (`new`) instead of plain call.
              let super_result = self.construct_value(super_ctor, args, loc)
              match super_result {
                Object(result_data) => {
                  // Per spec, OrdinaryCreateFromConstructor uses newTarget's prototype.
                  // Set the prototype from the subclass's pending this object.
                  match this_val {
                    Object(this_data) =>
                      result_data.prototype = this_data.prototype
                    _ => ()
                  }
                  env.initialize("this", super_result) catch {
                    _ => env.assign("this", super_result)
                  }
                  if env.has("[[InitInstanceFields]]") {
                    let init_fn = env.get("[[InitInstanceFields]]")
                    let _ = self.call_value(init_fn, super_result, [], loc)
                  }
                  super_result
                }
                Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => {
                  env.initialize("this", super_result) catch {
                    _ => env.assign("this", super_result)
                  }
                  if env.has("[[InitInstanceFields]]") {
                    let init_fn = env.get("[[InitInstanceFields]]")
                    let _ = self.call_value(init_fn, super_result, [], loc)
                  }
                  super_result
                }
                _ => {
                  env.initialize("this", this_val) catch {
                    _ => env.assign("this", this_val) catch { _ => () }
                  }
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
      if !is_truthy(left) {
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
    (Exp, l, r) => Number(@math.pow(to_number(l), to_number(r)))
    // Add fallback: ToPrimitive, then check for strings
    (Add, l, r) => {
      // ToPrimitive with hint "default" per spec (+ operator uses no preferred type)
      let lp = match l {
        Object(data) => to_primitive_default(l, data)
        Array(arr_data) => {
          let s = arr_data.elements.map(fn(v) { v.to_string() }).join(",")
          String_(s)
        }
        _ => l
      }
      let rp = match r {
        Object(data) => to_primitive_default(r, data)
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
              let key = to_js_string(l)
              // Check own property first
              if data.properties.contains(key) {
                return Bool(true)
              }
              // Walk prototype chain
              let mut current = data.prototype
              let mut func_fallback_used = false
              while true {
                match current {
                  Object(proto_data) =>
                    if proto_data.properties.contains(key) {
                      return Bool(true)
                    } else {
                      current = proto_data.prototype
                    }
                  Null =>
                    // For function objects, fall back to Function.prototype once
                    if !func_fallback_used {
                      match data.callable {
                        Some(_) =>
                          match current_interpreter.val {
                            Some(interp) => {
                              let fp = interp.global.get(
                                "[[FunctionPrototype]]",
                              ) catch {
                                _ => break
                              }
                              func_fallback_used = true
                              current = fp
                            }
                            None => break
                          }
                        None => break
                      }
                    } else {
                      break
                    }
                  _ => break
                }
              }
              Bool(false)
            }
          }
        Array(data) =>
          match l {
            Symbol(sym) => Bool(get_array_symbol_prop(data, sym.id) is Some(_))
            _ => {
              let key = to_js_string(l)
              if key == "length" {
                return Bool(true)
              }
              // Check numeric index
              try {
                let n = @string.parse_double(key)
                let idx = n.to_int()
                if idx.to_double() == n &&
                  idx >= 0 &&
                  idx < data.elements.length() {
                  return Bool(true)
                }
              } catch {
                _ => ()
              }
              // Check named properties side-table
              if get_array_named_prop(data, key) is Some(_) {
                return Bool(true)
              }
              // Check Array.prototype chain
              Bool(has_property(Array(data), key))
            }
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
/// Check whether `name` is a non-writable property on the global object
/// (undefined, NaN, Infinity). These are { writable:false } per ES spec §19.1.
fn Interpreter::is_immutable_global(self : Interpreter, name : String) -> Bool {
  match self.global_this {
    Object(data) =>
      match data.descriptors.get(name) {
        Some(desc) => !desc.writable
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
            // Also check global object for properties
            match self.global_this {
              Object(data) =>
                match data.properties.get(name) {
                  Some(v) => String_(type_of(v))
                  None => String_("undefined")
                }
              _ => String_("undefined")
            }
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
                  if !is_truthy(result) && self.strict {
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
                          if !desc.configurable {
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
                  if !desc.configurable {
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
                  if !is_truthy(result) && self.strict {
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
                          if !desc.configurable {
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
                      if !desc.configurable {
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
                      if !desc.configurable {
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
            // Check if this identifier is in a with-object first
            match env.find_with_object(name) {
              Some(Object(with_data)) => {
                match with_data.descriptors.get(name) {
                  Some(desc) => if !desc.configurable { return Bool(false) }
                  None => ()
                }
                let _ = with_data.properties.remove(name)
                let _ = with_data.descriptors.remove(name)
                Bool(true)
              }
              _ =>
                // In non-strict mode, check if the identifier is a non-configurable
                // property on the global object (e.g. undefined, NaN, Infinity).
                match self.global_this {
                  Object(data) =>
                    match data.descriptors.get(name) {
                      Some(desc) =>
                        if !desc.configurable {
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
          }
        _ => Bool(true)
      }
    _ => {
      let val = self.eval_expr(operand, env)
      match op {
        Neg => Number(-to_number(val))
        Pos => Number(to_number(val))
        Not => Bool(!is_truthy(val))
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
fn format_loc_context(message : String, loc : @token.Loc) -> String {
  message + " at line \{loc.line}, col \{loc.col}"
}
