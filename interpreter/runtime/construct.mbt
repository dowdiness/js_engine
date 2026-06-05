///|
fn Interpreter::eval_new(
  self : Interpreter,
  ctx : ExecContext,
  callee_expr : @ast.Expr,
  arg_exprs : Array[@ast.Expr],
  env : Environment,
  _loc : @token.Loc,
) -> Value raise Error {
  let ctor = self.eval_expr(ctx, callee_expr, env)
  let args : Array[Value] = self.eval_args_with_spread(ctx, arg_exprs, env)
  self.construct_value(ctor, args, _loc)
}

///|
fn is_object_like_for_constructor_return(value : Value) -> Bool {
  match value {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => true
    _ => false
  }
}

// Convert a constructor return value according to ES262 §9.2.2 step 13
// for class constructors. Derived constructors may only return object or
// undefined, while both base and derived constructors return `this` for the
// remaining case.

///|
fn apply_class_constructor_return(
  ctor_env : Environment,
  super_ctor : Value?,
  value : Value,
) -> Value raise Error {
  if is_object_like_for_constructor_return(value) {
    return value
  }
  match super_ctor {
    Some(_) =>
      match value {
        Undefined => ctor_env.get("this")
        _ =>
          raise @errors.TypeError(
            message="Derived constructors may only return object or undefined",
          )
      }
    None => ctor_env.get("this")
  }
}

///|
/// For subclass construction, align a built-in/special constructor return value
/// with the derived class instance prototype when `new.target` points to a
/// subclass constructor (Array/Map/Set/Promise).
fn set_derived_instance_prototype(
  super_result : Value,
  pending_this : Value,
) -> Unit {
  let target_proto : Value? = match pending_this {
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
/// Install instance field initializers onto `this_arg`.
/// Used for base-class construction (before constructor body) and for
/// derived-class implicit constructors (after super() returns).
fn Interpreter::install_instance_fields(
  self : Interpreter,
  this_arg : Value,
  fields : Array[ClassFieldInit],
) -> Unit raise Error {
  // Class field initializers are always evaluated as strict code per spec
  let field_ctx : ExecContext = { strict: true, current_generator: None }
  let field_desc : PropDescriptor = {
    writable: true,
    enumerable: true,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  for field in fields {
    let field_value : Value = match field.initializer {
      Some(expr) => {
        let init_env = Environment::new(parent=Some(field.closure))
        init_env.def_builtin("this", this_arg)
        // Per ES262 §15.7 ClassFieldDefinitionEvaluation: a class field
        // initializer is its own function-like execution context. Bind
        // `<new.target>` (always Undefined here — fields are invoked
        // implicitly during construction, never via `new`) so that direct
        // eval inside the field correctly classifies as "in function" and
        // permits `eval('new.target')` (matches V8). The
        // `[[InClassFieldInitializer]]` marker is consumed by perform_eval
        // (§19.2.1.1) to forbid `Contains arguments` in the eval source.
        init_env.def_builtin("<new.target>", Undefined)
        init_env.def_builtin("[[InClassFieldInitializer]]", Bool(true))
        self.eval_expr(field_ctx, expr, init_env)
      }
      None => Undefined
    }
    match this_arg {
      Object(data) =>
        // CreateDataPropertyOrThrow semantics: check [[DefineOwnProperty]]
        // invariants before writing (non-extensible objects, non-configurable
        // existing properties must throw TypeError per spec).
        match field.key {
          Symbol(sym) => {
            if !data.bag.symbol_properties.contains(sym.id) && !data.extensible {
              raise @errors.TypeError(
                message="Cannot define class field on non-extensible object",
              )
            }
            match data.bag.symbol_descriptors.get(sym.id) {
              Some(d) =>
                if !d.configurable {
                  raise @errors.TypeError(
                    message="Cannot redefine non-configurable class field",
                  )
                }
              None => ()
            }
            data.bag.symbol_properties[sym.id] = field_value
            data.bag.symbol_descriptors[sym.id] = field_desc
          }
          String_(key_str) => {
            if !data.bag.properties.contains(key_str) && !data.extensible {
              raise @errors.TypeError(
                message="Cannot define class field on non-extensible object",
              )
            }
            match data.bag.descriptors.get(key_str) {
              Some(d) =>
                if !d.configurable {
                  raise @errors.TypeError(
                    message="Cannot redefine non-configurable class field",
                  )
                }
              None => ()
            }
            data.bag.properties[key_str] = field_value
            data.bag.descriptors[key_str] = field_desc
          }
          _ => {
            let key_str = to_js_string(field.key)
            if !data.bag.properties.contains(key_str) && !data.extensible {
              raise @errors.TypeError(
                message="Cannot define class field on non-extensible object",
              )
            }
            match data.bag.descriptors.get(key_str) {
              Some(d) =>
                if !d.configurable {
                  raise @errors.TypeError(
                    message="Cannot redefine non-configurable class field",
                  )
                }
              None => ()
            }
            data.bag.properties[key_str] = field_value
            data.bag.descriptors[key_str] = field_desc
          }
        }
      Proxy(proxy_data) => {
        // Use [[DefineOwnProperty]] semantics for Proxy: invoke the
        // "defineProperty" trap so the proxy observes definition rather than
        // [[Set]] (which would invoke the "set" trap instead).
        let trap = get_proxy_trap(proxy_data, "defineProperty", self)
        let target = get_proxy_target(proxy_data)
        let handler = get_proxy_handler(proxy_data)
        match trap {
          Some(trap_fn) => {
            let desc_obj = Object({
              bag: {
                properties: {
                  "value": field_value,
                  "writable": Bool(true),
                  "enumerable": Bool(true),
                  "configurable": Bool(true),
                },
                symbol_properties: {},
                descriptors: {},
                symbol_descriptors: {},
              },
              prototype: Null,
              callable: None,
              class_name: "Object",
              extensible: true,
              arraybuffer_state: None,
            })
            let trap_result = self.call_value(
              trap_fn,
              handler,
              [target, field.key, desc_obj],
              @token.Loc::default(),
            )
            // Per spec, if the trap returns a falsy value, throw TypeError
            if !is_truthy(trap_result) {
              raise @errors.TypeError(
                message="'defineProperty' on proxy: trap returned falsish for class field",
              )
            }
          }
          None => {
            // No defineProperty trap: define directly on the target
            let _ = self.set_computed_property(
              target,
              field.key,
              field_value,
              @token.Loc::default(),
              strict=true,
            )
          }
        }
      }
      Map(data) =>
        // CreateDataPropertyOrThrow on Map expando properties
        match field.key {
          Symbol(sym) => {
            data.bag.symbol_properties[sym.id] = field_value
            data.bag.symbol_descriptors[sym.id] = field_desc
          }
          String_(key_str) => {
            data.bag.properties[key_str] = field_value
            data.bag.descriptors[key_str] = field_desc
          }
          _ => {
            let key_str = to_js_string(field.key)
            data.bag.properties[key_str] = field_value
            data.bag.descriptors[key_str] = field_desc
          }
        }
      Set(data) =>
        // CreateDataPropertyOrThrow on Set expando properties
        match field.key {
          Symbol(sym) => {
            data.bag.symbol_properties[sym.id] = field_value
            data.bag.symbol_descriptors[sym.id] = field_desc
          }
          String_(key_str) => {
            data.bag.properties[key_str] = field_value
            data.bag.descriptors[key_str] = field_desc
          }
          _ => {
            let key_str = to_js_string(field.key)
            data.bag.properties[key_str] = field_value
            data.bag.descriptors[key_str] = field_desc
          }
        }
      _ => {
        // Array, Promise — set_computed_property has define-own semantics
        // for these (no prototype-chain setter lookup).
        let _ = self.set_computed_property(
          this_arg,
          field.key,
          field_value,
          @token.Loc::default(),
          strict=true,
        )
      }
    }
  }
}

///|
/// Create a deferred instance-field initializer Value.
/// Stored as [[InitInstanceFields]] in the constructor env so the super()
/// call site can apply the fields to the actual `this` after super() returns.
fn make_instance_fields_init(
  fields : Array[ClassFieldInit],
  realm_state : RealmState,
) -> Value {
  stamp_function_realm(
    Object({
      bag: PropertyBag(),
      prototype: Null,
      callable: Some(
        InterpreterCallable("[[InitInstanceFields]]", fn(
          interp,
          this_arg,
          _,
        ) raise {
          interp.install_instance_fields(this_arg, fields)
          Undefined
        }),
      ),
      class_name: "Function",
      extensible: true,
      arraybuffer_state: None,
    }),
    realm_state=Some(realm_state),
  )
}

///|
fn make_constructor_instance(proto : Value, class_name : String) -> Value {
  Object({
    bag: PropertyBag(),
    prototype: proto,
    callable: None,
    class_name,
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
pub fn Interpreter::get_prototype_from_constructor(
  self : Interpreter,
  ctor : Value,
  loc : @token.Loc,
) -> Value raise Error {
  let prototype = self.get_property(ctor, "prototype", loc)
  match prototype {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => prototype
    _ =>
      with_active_callee_realm_value(self.realm_state, ctor, fn() {
        get_obj_proto(realm_state=Some(self.realm_state))
      })
  }
}

///|
pub fn Interpreter::define_simple_arguments_object(
  self : Interpreter,
  env : Environment,
  args : Array[Value],
  callee : Value,
  strict : Bool,
  params : Array[String],
) -> Unit raise Error {
  if params_include_arguments(params, None) {
    return
  }
  let tte : Value? = if env.has("[[ThrowTypeError]]") {
    Some(env.get("[[ThrowTypeError]]"))
  } else {
    None
  }
  env.def(
    "arguments",
    make_arguments_object(
      self.realm_state,
      self.realm_state.well_known_symbols,
      args,
      callee,
      strict,
      throw_type_error=tte,
      mapped_names=params,
      mapped_env=Some(env),
    ),
    VarBinding,
  )
}

///|
pub fn Interpreter::define_unmapped_arguments_object(
  self : Interpreter,
  env : Environment,
  args : Array[Value],
  callee : Value,
  strict : Bool,
) -> Unit raise Error {
  let tte : Value? = if env.has("[[ThrowTypeError]]") {
    Some(env.get("[[ThrowTypeError]]"))
  } else {
    None
  }
  env.def(
    "arguments",
    make_arguments_object(
      self.realm_state,
      self.realm_state.well_known_symbols,
      args,
      callee,
      strict,
      throw_type_error=tte,
    ),
    VarBinding,
  )
}

///|
fn make_arguments_object(
  realm_state : RealmState,
  well_known_symbols : WellKnownSymbols,
  args : Array[Value],
  ctor : Value,
  strict : Bool,
  throw_type_error? : Value? = None,
  mapped_names? : Array[String] = [],
  mapped_env? : Environment? = None,
) -> Value {
  let new_args_props : Map[String, Value] = {}
  let new_args_descs : Map[String, PropDescriptor] = {}
  // §10.4.4.1: sloppy simple-param lists get live-mapped accessor slots so
  // mutations to arguments[i] reflect in the named param binding and vice versa.
  let map_count = if strict {
    0
  } else {
    match mapped_env {
      Some(_) => {
        let a = mapped_names.length()
        let b = args.length()
        if a < b {
          a
        } else {
          b
        }
      }
      None => 0
    }
  }
  // §10.4.4.7: walk backwards so only the last occurrence of each param name
  // gets an accessor; earlier occurrences of duplicates stay as data properties.
  let mapped_indices : Map[Int, Bool] = {}
  match mapped_env {
    Some(_) => {
      let mapped_set : Map[String, Bool] = {}
      let mut idx = map_count - 1
      while idx >= 0 {
        let pname = mapped_names[idx]
        if !mapped_set.contains(pname) {
          mapped_set[pname] = true
          mapped_indices[idx] = true
        }
        idx = idx - 1
      }
    }
    None => ()
  }
  for i = 0; i < map_count; i = i + 1 {
    let key = i.to_string()
    let pname = mapped_names[i]
    match (mapped_env, mapped_indices.get(i)) {
      (Some(env), Some(true)) => {
        let getter_fn = stamp_function_realm(
          Object({
            bag: PropertyBag(),
            prototype: Null,
            callable: Some(
              NativeCallable("[[MappedArgGetter]]", _a => env.get(pname)),
            ),
            class_name: "Function",
            extensible: true,
            arraybuffer_state: None,
          }),
          realm_state=Some(realm_state),
        )
        let setter_fn = stamp_function_realm(
          Object({
            bag: PropertyBag(),
            prototype: Null,
            callable: Some(
              NativeCallable("[[MappedArgSetter]]", a => {
                env.assign(pname, if a.length() > 0 { a[0] } else { Undefined })
                Undefined
              }),
            ),
            class_name: "Function",
            extensible: true,
            arraybuffer_state: None,
          }),
          realm_state=Some(realm_state),
        )
        new_args_props[key] = Undefined // accessor sentinel
        new_args_descs[key] = {
          writable: false,
          enumerable: true,
          configurable: true,
          getter: Some(getter_fn),
          setter: Some(setter_fn),
          is_accessor: true,
        }
      }
      // Duplicate earlier occurrence: plain data property, not live-mapped
      _ => {
        new_args_props[key] = args[i]
        new_args_descs[key] = {
          writable: true,
          enumerable: true,
          configurable: true,
          getter: None,
          setter: None,
          is_accessor: false,
        }
      }
    }
  }
  for i = map_count; i < args.length(); i = i + 1 {
    let key = i.to_string()
    new_args_props[key] = args[i]
    new_args_descs[key] = {
      writable: true,
      enumerable: true,
      configurable: true,
      getter: None,
      setter: None,
      is_accessor: false,
    }
  }
  new_args_props["length"] = Number(args.length().to_double())
  new_args_descs["length"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  if !strict {
    new_args_props["callee"] = ctor
    new_args_descs["callee"] = {
      writable: true,
      enumerable: false,
      configurable: true,
      getter: None,
      setter: None,
      is_accessor: false,
    }
  } else {
    // Strict mode: install %ThrowTypeError% accessors for callee and caller
    match throw_type_error {
      Some(tte) => {
        new_args_descs["callee"] = {
          writable: false,
          enumerable: false,
          configurable: false,
          getter: Some(tte),
          setter: Some(tte),
          is_accessor: true,
        }
        new_args_descs["caller"] = {
          writable: false,
          enumerable: false,
          configurable: false,
          getter: Some(tte),
          setter: Some(tte),
          is_accessor: true,
        }
      }
      None => ()
    }
  }
  // Add Symbol.iterator using the generic Array.prototype.values semantics:
  // each next() observes the live arguments object length and indexed props.
  let iter_sym = well_known_symbols.iterator
  let new_args_sym_props : Map[Int, Value] = {}
  let new_args_sym_descs : Map[Int, PropDescriptor] = {}
  new_args_sym_props[iter_sym.id] = stamp_function_realm(
    Object({
      bag: PropertyBag(),
      prototype: Null,
      callable: Some(
        MethodCallable("values", fn(this_val, _args2) raise {
          realm_state.make_array_like_iterator_value(this_val)
        }),
      ),
      class_name: "Function",
      extensible: true,
      arraybuffer_state: None,
    }),
    realm_state=Some(realm_state),
  )
  new_args_sym_descs[iter_sym.id] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  Object({
    bag: {
      properties: new_args_props,
      symbol_properties: new_args_sym_props,
      descriptors: new_args_descs,
      symbol_descriptors: new_args_sym_descs,
    },
    prototype: get_obj_proto(realm_state=Some(realm_state)),
    callable: None,
    class_name: "Arguments",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
/// Shared class-constructor parameter binding and body execution.
/// Installs `arguments`, binds params with defaults/patterns, handles rest,
/// applies §10.2.11 param-env/body-env split, hoists, and executes `body`.
/// Caller handles: param validation, this/super/<new.target> setup on param_env,
/// and applying the ctor-specific return rule to the returned Signal.
fn Interpreter::bind_class_ctor_params_and_exec_body_signal(
  self : Interpreter,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
  ctor_val : Value,
  args : Array[Value],
  param_env : Environment,
  ctx : ExecContext,
) -> Signal raise Error {
  let tte : Value? = if param_env.has("[[ThrowTypeError]]") {
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
      ctor_val,
      true,
      throw_type_error=tte,
    ),
    VarBinding,
  )
  let mut effective_param_count = 0
  for i = 0; i < params.length(); i = i + 1 {
    let param = params[i]
    if param.is_rest_pattern {
      continue
    }
    let val : Value = if effective_param_count < args.length() &&
      !(args[effective_param_count] is Undefined) {
      args[effective_param_count]
    } else {
      match param.default_val {
        Some(default_expr) => self.eval_expr(ctx, default_expr, param_env)
        None =>
          if effective_param_count < args.length() {
            args[effective_param_count]
          } else {
            Undefined
          }
      }
    }
    match param.pattern {
      Some(pat) => self.bind_pattern(pat, val, param_env, LetBinding, ctx~)
      None => param_env.def_parameter(param.name, val)
    }
    effective_param_count += 1
  }
  match rest_param {
    Some(rest_name) => {
      let rest_elements : Array[Value] = []
      for i = effective_param_count; i < args.length(); i = i + 1 {
        rest_elements.push(args[i])
      }
      let rest_val = make_array(rest_elements)
      let mut bound_rest_pattern = false
      for p in params {
        if p.is_rest_pattern {
          match p.pattern {
            Some(pat) =>
              self.bind_pattern(pat, rest_val, param_env, LetBinding, ctx~)
            None => ()
          }
          bound_rest_pattern = true
          break
        }
      }
      if !bound_rest_pattern {
        param_env.def_parameter(rest_name, rest_val)
      }
    }
    None => ()
  }
  let split_scope = has_parameter_expressions(params)
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
  self.hoist_declarations(body, body_env, strict=true, param_source~)
  hoist_block_tdz(body, body_env)
  self.exec_stmts(ctx, body, body_env)
}

///|
fn maybe_set_promise_constructor(value : Value, ctor : Value) -> Value {
  match value {
    Promise(data) => {
      data.bag.properties["constructor"] = ctor
      data.bag.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      }
      value
    }
    _ => value
  }
}

///|
pub fn Interpreter::construct_value(
  self : Interpreter,
  ctor : Value,
  args : Array[Value],
  loc : @token.Loc,
  proto_override? : Value? = None,
  new_target? : Value? = None,
) -> Value raise Error {
  self.with_active_value(fn() raise {
    with_active_callee_realm_value(self.realm_state, ctor, fn() raise {
      self.construct_value_impl(ctor, args, loc, proto_override~, new_target~)
    })
  })
}

///|
fn Interpreter::construct_value_impl(
  self : Interpreter,
  ctor : Value,
  args : Array[Value],
  loc : @token.Loc,
  proto_override? : Value? = None,
  new_target? : Value? = None,
) -> Value raise Error {
  // Effective newTarget: explicit override (e.g. from Reflect.construct) or the
  // constructor itself (the normal `new Foo()` case, per §10.2.2 step 4).
  let new_target = new_target.unwrap_or(ctor)
  match ctor {
    Proxy(proxy_data) => {
      // §10.5.13 [[Construct]]: target must be a constructor per IsConstructor,
      // not merely callable — this rejects Proxy wrapping method-shorthand
      // (is_method: true), arrow functions, and other non-constructable callables.
      let target = get_proxy_target(proxy_data)
      if !is_constructor_value(target) {
        raise @errors.TypeError(message="target is not a constructor")
      }
      let trap = get_proxy_trap(proxy_data, "construct", self)
      match trap {
        Some(trap_fn) => {
          let handler = get_proxy_handler(proxy_data)
          let args_array : Value = make_array(args.copy())
          let result = self.call_value(
            trap_fn,
            handler,
            [target, args_array, new_target],
            loc,
          )
          match result {
            Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
              result
            _ =>
              raise @errors.TypeError(
                message="'construct' on proxy: trap returned non-Object",
              )
          }
        }
        None =>
          self.construct_value(
            target,
            args,
            loc,
            proto_override~,
            new_target=Some(new_target),
          )
      }
    }
    Object(obj_data) =>
      match obj_data.callable {
        Some(UserFunc(data)) => {
          // §13.3.5.1 step 5: method-shorthand functions have no [[Construct]]
          if data.is_method {
            raise @errors.TypeError(
              message=format_loc_context("is not a constructor", loc),
            )
          }
          let func_strict = data.strict
          let func_ctx : ExecContext = {
            strict: func_strict,
            current_generator: None,
          }
          if func_strict {
            // Strict mode: check for duplicate parameters and reserved names
            check_duplicate_params(data.params)
            for p in data.params {
              validate_strict_binding_name(p)
            }
          }
          let proto = match proto_override {
            Some(p) => p
            None => self.get_prototype_from_constructor(new_target, loc)
          }
          let new_obj = make_constructor_instance(proto, "Object")
          let func_env = Environment::new(parent=Some(data.closure))
          func_env.is_var_scope = true
          func_env.def("this", new_obj, LetBinding)
          func_env.def("<new.target>", new_target, LetBinding)
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
          if !params_include_arguments(data.params, None) {
            let tte : Value? = if func_env.has("[[ThrowTypeError]]") {
              Some(func_env.get("[[ThrowTypeError]]"))
            } else {
              None
            }
            func_env.def(
              "arguments",
              make_arguments_object(
                self.realm_state,
                self.realm_state.well_known_symbols,
                args,
                ctor,
                func_strict,
                throw_type_error=tte,
                mapped_names=data.params,
                mapped_env=Some(func_env),
              ),
              VarBinding,
            )
          }
          // Hoist declarations and top-level lexical TDZ markers.
          self.hoist_declarations(data.body, func_env, strict=func_strict)
          hoist_block_tdz(data.body, func_env)
          if data.has_name_binding {
            match data.name {
              Some(name) =>
                if !func_env.bindings.contains(name) {
                  func_env.def(name, ctor, LetBinding)
                }
              None => ()
            }
          }
          let exec_result = self.exec_stmts(func_ctx, data.body, func_env)
          raise_if_break_continue(exec_result)
          match exec_result {
            Normal(_) => new_obj
            ReturnSignal(v) =>
              if is_object_like_for_constructor_return(v) {
                v
              } else {
                new_obj
              }
            _ => new_obj
          }
        }
        Some(UserFuncExt(data)) => {
          // §13.3.5.1 step 5: method-shorthand functions have no [[Construct]]
          if data.is_method {
            raise @errors.TypeError(
              message=format_loc_context("is not a constructor", loc),
            )
          }
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
          let proto = match proto_override {
            Some(p) => p
            None => self.get_prototype_from_constructor(new_target, loc)
          }
          let new_obj = make_constructor_instance(proto, "Object")
          // §15.2.5: install the self-name on a dedicated env between
          // data.closure and param_env so default expressions can see it
          // (`function f(a = () => f) {}`). Params on param_env shadow
          // naturally; body-local decls of the same name shadow via
          // lexical lookup. Gated on has_name_binding — methods and
          // function declarations don't get this binding.
          let self_name_env : Environment = if data.has_name_binding {
            match data.name {
              Some(name) => {
                let ne = Environment::new(parent=Some(data.closure))
                ne.def(name, ctor, LetBinding)
                ne
              }
              None => data.closure
            }
          } else {
            data.closure
          }
          let param_env = Environment::new(parent=Some(self_name_env))
          param_env.is_var_scope = true
          param_env.def("this", new_obj, LetBinding)
          param_env.def("<new.target>", new_target, LetBinding)
          if !ext_params_include_arguments(data.params, data.rest_param) {
            // Create arguments object before binding params so defaults can reference it,
            // unless a formal parameter is named `arguments`.
            let tte2 : Value? = if param_env.has("[[ThrowTypeError]]") {
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
                ctor,
                func_strict,
                throw_type_error=tte2,
              ),
              VarBinding,
            )
          }
          // ES §10.2.2 [[Construct]] steps 13-14: object-like return
          // replaces the instance; anything else yields `new_obj`.
          match
            self.bind_ext_params_and_exec_body_signal(
              data,
              args,
              param_env,
              func_ctx,
              is_arrow=false,
            ) {
            ReturnSignal(v) =>
              if is_object_like_for_constructor_return(v) {
                v
              } else {
                new_obj
              }
            _ => new_obj
          }
        }
        Some(BoundFunc(target, _, bound_args)) => {
          // new BoundFunc(...args) delegates to new Target(...boundArgs, ...args)
          // §10.4.1.2 [[Construct]] step 6-7: if newTarget === bound function,
          // replace with target; otherwise forward the explicit newTarget.
          // When newTarget is rewritten to target (nt_for_target=None), drop
          // proto_override too — it was derived from the bound function's
          // .prototype (absent on bound fns → Null), and the effective newTarget
          // is now target, so the instance prototype must come from target.
          let nt_for_target = if physical_equal(new_target, ctor) {
            None // let recursive call default to target
          } else {
            Some(new_target)
          }
          let effective_proto_override : Value? = if nt_for_target is None {
            None
          } else {
            proto_override
          }
          let all_args : Array[Value] = []
          for a in bound_args {
            all_args.push(a)
          }
          for a in args {
            all_args.push(a)
          }
          self.construct_value(
            target,
            all_args,
            loc,
            proto_override=effective_proto_override,
            new_target=nt_for_target,
          )
        }
        Some(NativeCallable(_, func)) => func(args)
        Some(NativeCallableWithContext(_, func)) =>
          func(ConstructWithTarget(new_target), args)
        Some(NonConstructableCallable(name, _)) =>
          raise @errors.TypeError(
            message=format_loc_context(name + " is not a constructor", loc),
          )
        Some(NonConstructableInterpreterCallable(name, _)) =>
          raise @errors.TypeError(
            message=format_loc_context(name + " is not a constructor", loc),
          )
        Some(InterpreterCallable(_name, func)) => {
          if !interpreter_callable_is_constructor(obj_data) {
            raise @errors.TypeError(
              message=format_loc_context(_name + " is not a constructor", loc),
            )
          }
          func(self, Undefined, args)
        }
        Some(InterpreterCallableWithContext(_name, func)) => {
          if !interpreter_callable_is_constructor(obj_data) {
            raise @errors.TypeError(
              message=format_loc_context(_name + " is not a constructor", loc),
            )
          }
          if _name == "Symbol" {
            raise @errors.TypeError(message="Symbol is not a constructor")
          }
          func(self, ConstructWithTarget(new_target), Undefined, args)
        }
        Some(MethodCallable(name, _)) =>
          raise @errors.TypeError(
            message=format_loc_context(name + " is not a constructor", loc),
          )
        Some(ConstructorOnlyCallable(_, func)) => func(self, args)
        Some(ArrowFunc(_)) | Some(ArrowFuncExt(_)) =>
          raise @errors.TypeError(
            message=format_loc_context(
              "arrow functions cannot be used as constructors", loc,
            ),
          )
        Some(
          ClassConstructor(
            {
              name: class_name,
              proto,
              super_ctor,
              ctor_fn,
              closure,
              super_proto,
              instance_fields,
            }
          )
        ) => {
          // Class bodies are always strict mode
          let class_ctx : ExecContext = {
            strict: true,
            current_generator: None,
          }
          // Create the new instance with the class prototype
          let result = {
            // Create the new instance with the class prototype
            let new_obj = make_constructor_instance(proto, class_name)
            // Set up the constructor environment
            let ctor_env = Environment::new(parent=Some(closure))
            ctor_env.is_var_scope = true
            // For derived classes, 'this' is in TDZ until super() is called
            match super_ctor {
              Some(sc) => {
                // Put 'this' in TDZ - will be initialized by super() call
                ctor_env.def_tdz("this", LetBinding)
                ctor_env.def_builtin("[[SuperConstructor]]", sc)
                ctor_env.def_builtin("[[SuperPrototype]]", super_proto)
                // Store the new instance for super() to use
                ctor_env.def_builtin("[[PendingThis]]", new_obj)
                // For explicit constructors: fields are deferred; super() will
                // call [[InitInstanceFields]] after establishing `this`.
                // For implicit constructors (ctor_fn=None): fields are applied
                // directly at each return/fallthrough site in the None arm below.
                if ctor_fn is Some(_) && instance_fields.length() > 0 {
                  ctor_env.def_builtin(
                    "[[InitInstanceFields]]",
                    make_instance_fields_init(instance_fields, self.realm_state),
                  )
                }
              }
              None => {
                ctor_env.def_builtin("this", new_obj)
                // Base class: initialize instance fields before constructor body
                self.install_instance_fields(new_obj, instance_fields)
              }
            }
            ctor_env.def("<new.target>", new_target, LetBinding)
            // Execute the constructor if one was defined
            match ctor_fn {
              Some((params, rest_param, body)) => {
                // Class constructors are always strict — validate params
                check_duplicate_params_ext(params, rest_param)
                validate_strict_param_binding_names_ext(params, rest_param)
                let exec_result = self.bind_class_ctor_params_and_exec_body_signal(
                  params, rest_param, body, ctor, args, ctor_env, class_ctx,
                )
                raise_if_break_continue(exec_result)
                match exec_result {
                  Normal(_) =>
                    apply_class_constructor_return(
                      ctor_env,
                      super_ctor,
                      Undefined,
                    )
                  ReturnSignal(v) =>
                    apply_class_constructor_return(ctor_env, super_ctor, v)
                  _ =>
                    apply_class_constructor_return(
                      ctor_env,
                      super_ctor,
                      Undefined,
                    )
                }
              }
              None => {
                // No explicit constructor - if there's a super class, call super()
                // Save the derived class constructor for new.target propagation
                let derived_ctor = ctor
                match super_ctor {
                  Some(sc) =>
                    match sc {
                      Object(super_data) =>
                        match super_data.callable {
                          Some(
                            ClassConstructor(
                              {
                                super_ctor: grand_super,
                                instance_fields: super_instance_fields,
                                ctor_fn: ctor,
                                closure: senv,
                                super_proto: sproto,
                                ..,
                              }
                            )
                          ) => {
                            let super_env = Environment::new(parent=Some(senv))
                            super_env.def_builtin("this", new_obj)
                            super_env.def(
                              "<new.target>",
                              new_target,
                              LetBinding,
                            )
                            match grand_super {
                              Some(gs) => {
                                super_env.def_builtin(
                                  "[[SuperConstructor]]", gs,
                                )
                                super_env.def_builtin(
                                  "[[SuperPrototype]]", sproto,
                                )
                                // B is derived: defer B's fields to after B's own super()
                                if super_instance_fields.length() > 0 {
                                  super_env.def_builtin(
                                    "[[InitInstanceFields]]",
                                    make_instance_fields_init(
                                      super_instance_fields,
                                      self.realm_state,
                                    ),
                                  )
                                }
                              }
                              None =>
                                // B is a base class: initialize B's fields before its body
                                self.install_instance_fields(
                                  new_obj, super_instance_fields,
                                )
                            }
                            match ctor {
                              Some((params, rest_param, body)) => {
                                let exec_result = self.bind_class_ctor_params_and_exec_body_signal(
                                  params, rest_param, body, sc, args, super_env,
                                  class_ctx,
                                )
                                match exec_result {
                                  ReturnSignal(v) =>
                                    if is_object_like_for_constructor_return(v) {
                                      self.install_instance_fields(
                                        v, instance_fields,
                                      )
                                      return maybe_set_promise_constructor(
                                        v, derived_ctor,
                                      )
                                    }
                                  _ => ()
                                }
                              }
                              None => ()
                            }
                          }
                          Some(UserFunc(_))
                          | Some(UserFuncExt(_))
                          | Some(BoundFunc(_, _, _)) => {
                            let super_result = self.construct_value(
                              sc,
                              args,
                              @token.Loc::default(),
                              new_target=Some(new_target),
                            )
                            if is_object_like_for_constructor_return(
                                super_result,
                              ) {
                              self.install_instance_fields(
                                super_result, instance_fields,
                              )
                              return maybe_set_promise_constructor(
                                super_result, derived_ctor,
                              )
                            }
                          }
                          Some(ConstructorOnlyCallable(_, super_func)) => {
                            let super_result = super_func(self, args)
                            if is_object_like_for_constructor_return(
                                super_result,
                              ) {
                              set_derived_instance_prototype(
                                super_result, new_obj,
                              )
                              self.install_instance_fields(
                                super_result, instance_fields,
                              )
                              return maybe_set_promise_constructor(
                                super_result, derived_ctor,
                              )
                            }
                          }
                          Some(NativeCallable(_, _))
                          | Some(NativeCallableWithContext(_, _))
                          | Some(InterpreterCallable(_, _))
                          | Some(InterpreterCallableWithContext(_, _)) => {
                            // Built-in constructors like Error, Map, Set, etc.
                            let super_result = self.construct_value(
                              sc,
                              args,
                              @token.Loc::default(),
                              new_target=Some(new_target),
                            )
                            if is_object_like_for_constructor_return(
                                super_result,
                              ) {
                              set_derived_instance_prototype(
                                super_result, new_obj,
                              )
                              self.install_instance_fields(
                                super_result, instance_fields,
                              )
                              return maybe_set_promise_constructor(
                                super_result, derived_ctor,
                              )
                            }
                          }
                          _ => ()
                        }
                      _ => {
                        // Non-Object super (e.g. `extends null`): attempt
                        // Construct(sc, args) — construct_value throws TypeError
                        // for non-constructors like null, matching spec behaviour.
                        let _ = self.construct_value(
                          sc,
                          args,
                          @token.Loc::default(),
                          new_target=Some(new_target),
                        )
                      }
                    }
                  None => ()
                }
                // Apply derived class instance fields after implicit super() call
                if super_ctor is Some(_) {
                  self.install_instance_fields(new_obj, instance_fields)
                }
                new_obj
              }
            }
          }
          maybe_set_promise_constructor(result, ctor)
        }
        _ =>
          raise @errors.TypeError(
            message=format_loc_context("is not a constructor", loc),
          )
      }
    _ =>
      raise @errors.TypeError(
        message=format_loc_context("is not a constructor", loc),
      )
  }
}
