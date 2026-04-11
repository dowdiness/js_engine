///|
fn Interpreter::eval_new(
  self : Interpreter,
  callee_expr : @ast.Expr,
  arg_exprs : Array[@ast.Expr],
  env : Environment,
  _loc : @token.Loc,
) -> Value raise Error {
  let ctor = self.eval_expr(callee_expr, env)
  let args : Array[Value] = self.eval_args_with_spread(arg_exprs, env)
  self.construct_value(ctor, args, _loc)
}

///|
fn is_object_like_for_constructor_return(value : Value) -> Bool {
  match value {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => true
    _ => false
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
  let saved_strict = self.strict
  self.strict = true
  let field_desc : PropDescriptor = {
    writable: true,
    enumerable: true,
    configurable: true,
    getter: None,
    setter: None,
  }
  try {
    for field in fields {
      let field_value : Value = match field.initializer {
        Some(expr) => {
          let init_env = Environment::new(parent=Some(field.closure))
          init_env.def_builtin("this", this_arg)
          self.eval_expr(expr, init_env)
        }
        None => Undefined
      }
      match this_arg {
        Object(data) =>
          // For plain Objects set both value and descriptor (writable/enumerable/configurable:true)
          match field.key {
            Symbol(sym) => {
              data.symbol_properties[sym.id] = field_value
              data.symbol_descriptors[sym.id] = field_desc
            }
            String_(key_str) => {
              data.properties[key_str] = field_value
              data.descriptors[key_str] = field_desc
            }
            _ => {
              let key_str = to_js_string(field.key)
              data.properties[key_str] = field_value
              data.descriptors[key_str] = field_desc
            }
          }
        Proxy(proxy_data) => {
          // Use [[DefineOwnProperty]] semantics for Proxy: invoke the
          // "defineProperty" trap so the proxy observes definition rather than
          // [[Set]] (which would invoke the "set" trap instead).
          let trap = get_proxy_trap(proxy_data, "defineProperty")
          let target = get_proxy_target(proxy_data)
          let handler = get_proxy_handler(proxy_data)
          match trap {
            Some(trap_fn) => {
              let desc_obj = Object({
                properties: {
                  "value": field_value,
                  "writable": Bool(true),
                  "enumerable": Bool(true),
                  "configurable": Bool(true),
                },
                symbol_properties: {},
                prototype: Null,
                callable: None,
                class_name: "Object",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
              let _ = self.call_value(
                trap_fn,
                handler,
                [target, field.key, desc_obj],
                @token.Loc::default(),
              )
            }
            None => {
              // No defineProperty trap: define directly on the target
              let _ = self.set_computed_property(
                target,
                field.key,
                field_value,
                @token.Loc::default(),
              )
            }
          }
        }
        _ => {
          // Array, Promise, Map, Set — set_computed_property already has
          // define-own semantics for these (no prototype-chain setter lookup).
          let _ = self.set_computed_property(
            this_arg,
            field.key,
            field_value,
            @token.Loc::default(),
          )
        }
      }
    }
  } catch {
    e => {
      self.strict = saved_strict
      raise e
    }
  }
  self.strict = saved_strict
}

///|
/// Create a deferred instance-field initializer Value.
/// Stored as [[InitInstanceFields]] in the constructor env so the super()
/// call site can apply the fields to the actual `this` after super() returns.
fn make_instance_fields_init(fields : Array[ClassFieldInit]) -> Value {
  Object({
    properties: {},
    symbol_properties: {},
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
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
fn make_constructor_instance(proto : Value, class_name : String) -> Value {
  Object({
    properties: {},
    symbol_properties: {},
    prototype: proto,
    callable: None,
    class_name,
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
fn make_arguments_object(
  args : Array[Value],
  ctor : Value,
  strict : Bool,
  throw_type_error? : Value? = None,
) -> Value {
  let new_args_props : Map[String, Value] = {}
  let new_args_descs : Map[String, PropDescriptor] = {}
  for i = 0; i < args.length(); i = i + 1 {
    new_args_props[i.to_string()] = args[i]
    new_args_descs[i.to_string()] = {
      writable: true,
      enumerable: true,
      configurable: true,
      getter: None,
      setter: None,
    }
  }
  new_args_props["length"] = Number(args.length().to_double())
  new_args_descs["length"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  if !strict {
    new_args_props["callee"] = ctor
    new_args_descs["callee"] = {
      writable: true,
      enumerable: false,
      configurable: true,
      getter: None,
      setter: None,
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
        }
        new_args_descs["caller"] = {
          writable: false,
          enumerable: false,
          configurable: false,
          getter: Some(tte),
          setter: Some(tte),
        }
      }
      None => ()
    }
  }
  // Add Symbol.iterator - creates an iterator over the arguments
  let iter_sym = get_iterator_symbol()
  let args_copy = args
  let new_args_sym_props : Map[Int, Value] = {}
  new_args_sym_props[iter_sym.id] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("values", fn(_this_val, _args2) {
        let index_ref : Ref[Int] = { val: 0 }
        let len = args_copy.length()
        let next_fn = Object({
          properties: {},
          symbol_properties: {},
          prototype: Null,
          callable: Some(
            NativeCallable("next", fn(_a) {
              let idx = index_ref.val
              if idx < len {
                let value = args_copy[idx]
                index_ref.val = idx + 1
                Object({
                  properties: { "value": value, "done": Bool(false) },
                  symbol_properties: {},
                  prototype: Null,
                  callable: None,
                  class_name: "Object",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
              } else {
                Object({
                  properties: { "value": Undefined, "done": Bool(true) },
                  symbol_properties: {},
                  prototype: Null,
                  callable: None,
                  class_name: "Object",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
              }
            }),
          ),
          class_name: "Function",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
        Object({
          properties: { "next": next_fn },
          symbol_properties: {},
          prototype: Null,
          callable: None,
          class_name: "Array Iterator",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  Object({
    properties: new_args_props,
    symbol_properties: new_args_sym_props,
    prototype: get_obj_proto(),
    callable: None,
    class_name: "Arguments",
    descriptors: new_args_descs,
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
fn maybe_set_promise_constructor(value : Value, ctor : Value) -> Value {
  match value {
    Promise(data) => {
      data.properties["constructor"] = ctor
      data.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      value
    }
    _ => value
  }
}

///|
fn Interpreter::construct_value(
  self : Interpreter,
  ctor : Value,
  args : Array[Value],
  loc : @token.Loc,
  proto_override? : Value? = None,
) -> Value raise Error {
  match ctor {
    Proxy(proxy_data) => {
      // Verify target is constructible before checking trap
      let target = get_proxy_target(proxy_data)
      fn is_constructible(v : Value) -> Bool {
        match v {
          Object(t_data) => t_data.callable is Some(_)
          Proxy(pd) =>
            match pd.target {
              Some(inner) => is_constructible(inner)
              None => false
            }
          _ => false
        }
      }
      if !is_constructible(target) {
        raise @errors.TypeError(message="target is not a constructor")
      }
      let trap = get_proxy_trap(proxy_data, "construct")
      match trap {
        Some(trap_fn) => {
          let handler = get_proxy_handler(proxy_data)
          let args_array : Value = Array({ elements: args.copy() })
          let result = self.call_value(
            trap_fn,
            handler,
            [target, args_array, ctor],
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
        None => self.construct_value(target, args, loc)
      }
    }
    Object(obj_data) =>
      match obj_data.callable {
        Some(UserFunc(data)) => {
          let saved_strict = self.strict
          let result = try {
            let func_strict = data.strict
            self.strict = func_strict
            if func_strict {
              // Strict mode: check for duplicate parameters and reserved names
              check_duplicate_params(data.params)
              for p in data.params {
                validate_strict_binding_name(p)
              }
            }
            let proto = match proto_override {
              Some(p) => p
              None =>
                match obj_data.properties.get("prototype") {
                  Some(v) => v
                  None => Null
                }
            }
            let new_obj = make_constructor_instance(proto, "Object")
            let func_env = Environment::new(parent=Some(data.closure))
            func_env.is_var_scope = true
            func_env.def("this", new_obj, LetBinding)
            func_env.def("<new.target>", ctor, LetBinding)
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
                func_env.def(data.params[i], val, LetBinding)
              }
            }
            let tte : Value? = if func_env.has("[[ThrowTypeError]]") {
              Some(func_env.get("[[ThrowTypeError]]"))
            } else {
              None
            }
            func_env.def(
              "arguments",
              make_arguments_object(
                args,
                ctor,
                func_strict,
                throw_type_error=tte,
              ),
              VarBinding,
            )
            // Hoist var declarations and function declarations
            self.hoist_declarations(data.body, func_env)
            match data.name {
              Some(name) =>
                if !func_env.bindings.contains(name) {
                  func_env.def(name, ctor, LetBinding)
                }
              None => ()
            }
            let exec_result = self.exec_stmts(data.body, func_env)
            match exec_result {
              Normal(_) => new_obj
              ReturnSignal(v) =>
                if is_object_like_for_constructor_return(v) {
                  v
                } else {
                  new_obj
                }
              BreakSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="break statement outside of loop",
                )
              ContinueSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="continue statement outside of loop",
                )
            }
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
          result
        }
        Some(UserFuncExt(data)) => {
          let saved_strict = self.strict
          let result = try {
            let func_strict = data.strict
            self.strict = func_strict
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
            let proto = match proto_override {
              Some(p) => p
              None =>
                match obj_data.properties.get("prototype") {
                  Some(v) => v
                  None => Null
                }
            }
            let new_obj = make_constructor_instance(proto, "Object")
            let func_env = Environment::new(parent=Some(data.closure))
            func_env.is_var_scope = true
            func_env.def("this", new_obj, LetBinding)
            func_env.def("<new.target>", ctor, LetBinding)
            // Create arguments object BEFORE binding params so defaults can reference it
            let tte2 : Value? = if func_env.has("[[ThrowTypeError]]") {
              Some(func_env.get("[[ThrowTypeError]]"))
            } else {
              None
            }
            func_env.def(
              "arguments",
              make_arguments_object(
                args,
                ctor,
                func_strict,
                throw_type_error=tte2,
              ),
              VarBinding,
            )
            let mut effective_param_count = 0
            for i = 0; i < data.params.length(); i = i + 1 {
              let param = data.params[i]
              // Skip rest destructuring params
              if data.rest_param is Some(rn) && param.name == rn {
                continue
              }
              let val : Value = if effective_param_count < args.length() &&
                !(args[effective_param_count] is Undefined) {
                args[effective_param_count]
              } else {
                match param.default_val {
                  Some(default_expr) => self.eval_expr(default_expr, func_env)
                  None =>
                    if effective_param_count < args.length() {
                      args[effective_param_count]
                    } else {
                      Undefined
                    }
                }
              }
              func_env.def(param.name, val, LetBinding)
              match param.pattern {
                Some(pat) => self.bind_pattern(pat, val, func_env, LetBinding)
                None => ()
              }
              effective_param_count = effective_param_count + 1
            }
            match data.rest_param {
              Some(rest_name) => {
                let rest_elements : Array[Value] = []
                for i = effective_param_count; i < args.length(); i = i + 1 {
                  rest_elements.push(args[i])
                }
                let rest_val = Array({ elements: rest_elements })
                func_env.def(rest_name, rest_val, LetBinding)
                // Apply destructuring pattern if present
                for p in data.params {
                  if p.name == rest_name {
                    match p.pattern {
                      Some(pat) =>
                        self.bind_pattern(pat, rest_val, func_env, LetBinding)
                      None => ()
                    }
                    break
                  }
                }
              }
              None => ()
            }
            self.hoist_declarations(data.body, func_env)
            match data.name {
              Some(name) =>
                if !func_env.bindings.contains(name) {
                  func_env.def(name, ctor, LetBinding)
                }
              None => ()
            }
            let exec_result = self.exec_stmts(data.body, func_env)
            match exec_result {
              Normal(_) => new_obj
              ReturnSignal(v) =>
                if is_object_like_for_constructor_return(v) {
                  v
                } else {
                  new_obj
                }
              BreakSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="break statement outside of loop",
                )
              ContinueSignal(_, _) =>
                raise @errors.SyntaxError(
                  message="continue statement outside of loop",
                )
            }
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
          result
        }
        Some(BoundFunc(target, _, bound_args)) => {
          // new BoundFunc(...args) delegates to new Target(...boundArgs, ...args)
          let all_args : Array[Value] = []
          for a in bound_args {
            all_args.push(a)
          }
          for a in args {
            all_args.push(a)
          }
          self.construct_value(target, all_args, loc)
        }
        Some(NativeCallable(_, func)) => {
          is_constructing.val = true
          let result = func(args) catch {
            e => {
              is_constructing.val = false
              raise e
            }
          }
          is_constructing.val = false
          result
        }
        Some(NonConstructableCallable(name, _)) =>
          raise @errors.TypeError(
            message=format_loc_context(name + " is not a constructor", loc),
          )
        Some(InterpreterCallable(_name, func)) => {
          // Check if this function has a "prototype" property (constructors do, methods don't)
          let is_ctor = match obj_data.properties.get("prototype") {
            Some(_) => true
            None => false
          }
          if !is_ctor {
            raise @errors.TypeError(
              message=format_loc_context(_name + " is not a constructor", loc),
            )
          }
          is_constructing.val = true
          let result = func(self, Undefined, args) catch {
            e => {
              is_constructing.val = false
              raise e
            }
          }
          is_constructing.val = false
          result
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
          let saved_strict = self.strict
          self.strict = true
          let result = try {
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
                    make_instance_fields_init(instance_fields),
                  )
                }
              }
              None => {
                ctor_env.def_builtin("this", new_obj)
                // Base class: initialize instance fields before constructor body
                self.install_instance_fields(new_obj, instance_fields)
              }
            }
            ctor_env.def("<new.target>", ctor, LetBinding)
            // Execute the constructor if one was defined
            match ctor_fn {
              Some((params, body)) => {
                // Class constructors are always strict — validate params
                check_duplicate_params(params)
                for p in params {
                  validate_strict_binding_name(p)
                }
                // Bind parameters
                for i = 0; i < params.length(); i = i + 1 {
                  let val : Value = if i < args.length() {
                    args[i]
                  } else {
                    Undefined
                  }
                  ctor_env.def(params[i], val, LetBinding)
                }
                let ctor_tte : Value? = if ctor_env.has("[[ThrowTypeError]]") {
                  Some(ctor_env.get("[[ThrowTypeError]]"))
                } else {
                  None
                }
                ctor_env.def(
                  "arguments",
                  make_arguments_object(
                    args,
                    ctor,
                    true,
                    throw_type_error=ctor_tte,
                  ),
                  VarBinding,
                )
                // Hoist declarations and execute body
                self.hoist_declarations(body, ctor_env)
                let exec_result = self.exec_stmts(body, ctor_env)
                let current_this = ctor_env.get("this")
                match exec_result {
                  Normal(_) => current_this
                  ReturnSignal(v) =>
                    if is_object_like_for_constructor_return(v) {
                      v
                    } else {
                      current_this
                    }
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
                              derived_ctor,
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
                              Some((params, body)) => {
                                for i = 0; i < params.length(); i = i + 1 {
                                  let val : Value = if i < args.length() {
                                    args[i]
                                  } else {
                                    Undefined
                                  }
                                  super_env.def(params[i], val, LetBinding)
                                }
                                let super_tte : Value? = if super_env.has(
                                    "[[ThrowTypeError]]",
                                  ) {
                                  Some(super_env.get("[[ThrowTypeError]]"))
                                } else {
                                  None
                                }
                                super_env.def(
                                  "arguments",
                                  make_arguments_object(
                                    args,
                                    sc,
                                    true,
                                    throw_type_error=super_tte,
                                  ),
                                  VarBinding,
                                )
                                self.hoist_declarations(body, super_env)
                                let exec_result = self.exec_stmts(
                                  body, super_env,
                                )
                                // If super constructor returns an object, use it
                                match exec_result {
                                  ReturnSignal(v) =>
                                    if is_object_like_for_constructor_return(v) {
                                      // Apply C's instance fields to the override object
                                      self.install_instance_fields(
                                        v, instance_fields,
                                      )
                                      self.strict = saved_strict
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
                          Some(ConstructorOnlyCallable(_, super_func)) => {
                            let super_result = super_func(self, args)
                            if is_object_like_for_constructor_return(
                                super_result,
                              ) {
                              self.install_instance_fields(
                                super_result, instance_fields,
                              )
                              self.strict = saved_strict
                              return maybe_set_promise_constructor(
                                super_result, derived_ctor,
                              )
                            }
                          }
                          Some(NativeCallable(_, _))
                          | Some(InterpreterCallable(_, _)) => {
                            // Built-in constructors like Error, Map, Set, etc.
                            let super_result = self.construct_value(
                              sc,
                              args,
                              @token.Loc::default(),
                            )
                            match super_result {
                              Object(result_data) => {
                                // Set prototype to the subclass's prototype (newTarget semantics)
                                result_data.prototype = new_obj
                                  |> fn(v) {
                                    match v {
                                      Object(d) => d.prototype
                                      _ => Null
                                    }
                                  }
                                self.install_instance_fields(
                                  super_result, instance_fields,
                                )
                                self.strict = saved_strict
                                return maybe_set_promise_constructor(
                                  super_result, derived_ctor,
                                )
                              }
                              _ =>
                                // For Map, Set, Promise, etc. that return non-Object values
                                if is_object_like_for_constructor_return(
                                    super_result,
                                  ) {
                                  self.install_instance_fields(
                                    super_result, instance_fields,
                                  )
                                  self.strict = saved_strict
                                  return maybe_set_promise_constructor(
                                    super_result, derived_ctor,
                                  )
                                }
                            }
                          }
                          _ => ()
                        }
                      _ => ()
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
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
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
