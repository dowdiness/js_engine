///|
fn func_kind_prefix(class_name : String) -> String {
  match class_name {
    "AsyncFunction" => "async function "
    "GeneratorFunction" => "function* "
    "AsyncGeneratorFunction" => "async function* "
    _ => "function "
  }
}

///|
fn setup_function_builtins(
  env : Environment,
  realm_state : @runtime.RealmState,
) -> Unit {
  // Create Function.prototype
  let func_proto_props : Map[String, Value] = {}

  // Function.prototype.toString - returns function source or [native code]
  func_proto_props["toString"] = @runtime.make_method_func(
    name="toString",
    length=0,
    fn(this_val, _args) raise {
      match this_val {
        Object(data) => {
          let prefix = func_kind_prefix(data.class_name)
          match data.callable {
            Some(UserFunc(func_data)) => {
              let name = func_data.name.unwrap_or("")
              Value::String_(prefix + name + "() { [native code] }")
            }
            Some(UserFuncExt(func_data)) => {
              let name = func_data.name.unwrap_or("")
              Value::String_(prefix + name + "() { [native code] }")
            }
            Some(ArrowFunc(_)) =>
              if data.class_name == "AsyncFunction" {
                Value::String_("async () => { [native code] }")
              } else {
                Value::String_("() => { [native code] }")
              }
            Some(ArrowFuncExt(_)) =>
              if data.class_name == "AsyncFunction" {
                Value::String_("async () => { [native code] }")
              } else {
                Value::String_("() => { [native code] }")
              }
            Some(NativeCallable(name, _))
            | Some(NativeCallableWithContext(name, _)) =>
              Value::String_(prefix + name + "() { [native code] }")
            Some(NonConstructableCallable(name, _)) =>
              Value::String_(prefix + name + "() { [native code] }")
            Some(BoundFunc(_, _, _)) =>
              Value::String_(prefix + "() { [native code] }")
            Some(MethodCallable(name, _)) =>
              Value::String_(prefix + name + "() { [native code] }")
            Some(InterpreterCallable(name, _))
            | Some(InterpreterCallableWithContext(name, _)) =>
              Value::String_(prefix + name + "() { [native code] }")
            Some(NonConstructableInterpreterCallable(name, _)) =>
              Value::String_(prefix + name + "() { [native code] }")
            Some(ConstructorOnlyCallable(name, _)) =>
              Value::String_(prefix + name + "() { [native code] }")
            Some(FuncCallMethod(_)) =>
              Value::String_(prefix + "call() { [native code] }")
            Some(FuncApplyMethod(_)) =>
              Value::String_(prefix + "apply() { [native code] }")
            Some(ClassConstructor({ name, .. })) =>
              Value::String_("class " + name + " { [native code] }")
            None =>
              raise @errors.TypeError(
                message="Function.prototype.toString requires a function",
              )
          }
        }
        _ =>
          raise @errors.TypeError(
            message="Function.prototype.toString requires a function",
          )
      }
    },
  )

  // Function.prototype.call - placeholder (actual implementation in interpreter)
  func_proto_props["call"] = @runtime.make_interp_method_func(
    name="call",
    length=1,
    fn(interp, this_val, args) raise {
      let loc = @token.Loc::default()
      let call_this : Value = if args.length() > 0 {
        args[0]
      } else {
        Undefined
      }
      let call_args : Array[Value] = []
      for i = 1; i < args.length(); i = i + 1 {
        call_args.push(args[i])
      }
      interp.call_value(this_val, call_this, call_args, loc)
    },
  )

  // Function.prototype.apply — §20.2.3.1
  func_proto_props["apply"] = @runtime.make_interp_method_func(
    name="apply",
    length=2,
    fn(interp, this_val, args) raise {
      let loc = @token.Loc::default()
      let call_this : Value = if args.length() > 0 {
        args[0]
      } else {
        Undefined
      }
      // Step 2: argArray undefined/null → call with no args. Otherwise step 4
      // delegates to CreateListFromArrayLike which throws for non-Object.
      let call_args : Array[Value] = if args.length() > 1 {
        match args[1] {
          Null | Undefined => []
          other => create_list_from_array_like(interp, other)
        }
      } else {
        []
      }
      interp.call_value(this_val, call_this, call_args, loc)
    },
  )

  // Function.prototype.bind - placeholder (actual implementation in interpreter)
  func_proto_props["bind"] = @runtime.make_interp_method_func(
    name="bind",
    length=1,
    fn(_interp, this_val, args) raise {
      // Function.prototype.bind - §20.2.3.2
      // Step 1: If IsCallable(this) is false, throw a TypeError exception
      if !@runtime.is_function_value(this_val) {
        raise @errors.TypeError(
          message="Function.prototype.bind called on non-callable",
        )
      }
      let target_proto = match this_val {
        Object(data) =>
          match data.prototype {
            Null => @runtime.get_func_proto(realm_state=Some(realm_state))
            proto => proto
          }
        _ => @runtime.get_func_proto(realm_state=Some(realm_state))
      }
      let bind_this = if args.length() > 0 { args[0] } else { Undefined }
      let bound_args : Array[Value] = []
      for i = 1; i < args.length(); i = i + 1 {
        bound_args.push(args[i])
      }
      let bound_name = @runtime.get_bound_func_name(this_val)
      let target_length = @runtime.get_function_length(this_val)
      let bound_length = {
        let diff = target_length - bound_args.length()
        if diff < 0 {
          0
        } else {
          diff
        }
      }
      let nf_desc : PropDescriptor = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      }
      let bprops : Map[String, Value] = {}
      bprops["length"] = Value::Number(bound_length.to_double())
      bprops["name"] = Value::String_(bound_name)
      @runtime.stamp_function_realm(
        Value::Object({
          bag: {
            properties: bprops,
            symbol_properties: {},
            descriptors: { "length": nf_desc, "name": nf_desc },
            symbol_descriptors: {},
          },
          prototype: target_proto,
          callable: Some(BoundFunc(this_val, bind_this, bound_args)),
          class_name: "Function",
          extensible: true,
          arraybuffer_state: None,
        }),
        realm_state=Some(realm_state),
      )
    },
  )
  // %ThrowTypeError% intrinsic (ES spec §10.2.4)
  // A single frozen function that throws TypeError when called.
  let throw_type_error : Value = Value::Object({
    bag: {
      properties: { "length": Value::Number(0.0), "name": Value::String_("") },
      symbol_properties: {},
      descriptors: {
        "length": {
          writable: false,
          enumerable: false,
          configurable: false,
          getter: None,
          setter: None,
          is_accessor: false,
        },
        "name": {
          writable: false,
          enumerable: false,
          configurable: false,
          getter: None,
          setter: None,
          is_accessor: false,
        },
      },
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: Some(
      NonConstructableCallable("", fn(_args) raise {
        raise @errors.TypeError(
          message="'caller', 'callee', and 'arguments' properties may not be accessed on strict mode functions or the arguments objects for calls to them",
        )
      }),
    ),
    class_name: "Function",
    extensible: false,
    arraybuffer_state: None,
  })

  // Install ThrowTypeError accessors on Function.prototype for caller and arguments
  let func_proto_descs : Map[String, PropDescriptor] = {}
  func_proto_descs["caller"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(throw_type_error),
    setter: Some(throw_type_error),
    is_accessor: true,
  }
  func_proto_descs["arguments"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(throw_type_error),
    setter: Some(throw_type_error),
    is_accessor: true,
  }
  func_proto_descs["toString"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  func_proto_descs["call"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  func_proto_descs["apply"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  func_proto_descs["bind"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }

  // Function.prototype is callable per spec (returns undefined when called)
  // and has name="" and length=0 own properties
  func_proto_props["name"] = Value::String_("")
  func_proto_props["length"] = Value::Number(0.0)
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  func_proto_descs["name"] = nf_desc
  func_proto_descs["length"] = nf_desc
  let func_proto : Value = Value::Object({
    bag: {
      properties: func_proto_props,
      symbol_properties: {},
      descriptors: func_proto_descs,
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: Some(NonConstructableCallable("", fn(_args) { Undefined })),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })

  // Set ThrowTypeError's prototype to Function.prototype (after func_proto is created)
  match throw_type_error {
    Object(tte_data) => tte_data.prototype = func_proto
    _ => ()
  }

  // Register %ThrowTypeError% so it can be used for strict arguments objects
  env.def_builtin("[[ThrowTypeError]]", throw_type_error)

  // Function constructor properties
  let func_ctor_props : Map[String, Value] = {}
  func_ctor_props["prototype"] = func_proto
  func_ctor_props["length"] = Value::Number(1.0)
  func_ctor_props["name"] = Value::String_("Function")
  let prototype_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }

  // Create a single Function constructor object.
  // Function(p1, p2, ..., body) parses the body string and creates a real function.
  let func_ctor : Value = Value::Object({
    bag: {
      properties: func_ctor_props,
      symbol_properties: {},
      descriptors: {
        "name": nf_desc,
        "length": nf_desc,
        "prototype": prototype_desc,
      },
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: Some(
      InterpreterCallable("Function", fn(interp, _this, args) raise {
        if args.length() == 0 {
          return @runtime.stamp_function_realm(
            Value::Object({
              bag: @runtime.PropertyBag(),
              prototype: func_proto,
              callable: Some(NativeCallable("anonymous", fn(_) { Undefined })),
              class_name: "Function",
              extensible: true,
              arraybuffer_state: None,
            }),
            realm_state=Some(realm_state),
          )
        }
        // Last arg is body, previous args are parameter names
        let body_str = match args[args.length() - 1] {
          Value::String_(s) => s
          _ => args[args.length() - 1].to_string()
        }
        let param_parts : Array[String] = []
        for i = 0; i < args.length() - 1; i = i + 1 {
          match args[i] {
            Value::String_(s) => param_parts.push(s)
            _ => param_parts.push(args[i].to_string())
          }
        }
        let params_str = param_parts.join(",")
        let source = "function anonymous(" +
          params_str +
          ") {\n" +
          body_str +
          "\n}"
        let prog = @parser.parse(source)
        // The first statement should be a function declaration — extract its parts
        if prog.stmts.length() > 0 {
          match prog.stmts[0] {
            FuncDecl(_, params, body, _) => {
              let fn_props : Map[String, Value] = {}
              fn_props["length"] = Value::Number(params.length().to_double())
              // Validate static early errors against the function's strict context.
              let body_strict = @runtime.has_use_strict(body)
              @runtime.validate_function_constructor_params(
                true,
                params,
                None,
                body,
              )
              interp.validate_block_early_errors(body, body_strict)
              return @runtime.stamp_function_realm(
                Value::Object({
                  bag: {
                    properties: fn_props,
                    symbol_properties: {},
                    descriptors: { "length": nf_desc },
                    symbol_descriptors: {},
                  },
                  prototype: func_proto,
                  callable: Some(
                    UserFunc({
                      name: Some("anonymous"),
                      params,
                      body,
                      closure: env,
                      strict: body_strict,
                      // `new Function(...)` result has no self-name binding.
                      has_name_binding: false,
                      is_method: false,
                    }),
                  ),
                  class_name: "Function",
                  extensible: true,
                  arraybuffer_state: None,
                }),
                realm_state=Some(realm_state),
              )
            }
            FuncDeclExt(_, params, rest_param, body, _) => {
              let fn_props : Map[String, Value] = {}
              // ES262 §10.2.4 ExpectedArgumentCount: count params before
              // first default or rest. See factories.mbt for the
              // destructuring-rest note.
              let mut fn_length = 0
              for p in params {
                if p.default_val is Some(_) {
                  break
                }
                if rest_param is Some(rn) && p.name == rn {
                  break
                }
                fn_length += 1
              }
              fn_props["length"] = Value::Number(fn_length.to_double())
              // Validate static early errors against the function's strict context.
              let body_strict = @runtime.has_use_strict(body)
              let param_names : Array[String] = params.map(p => p.name)
              @runtime.validate_function_constructor_params(
                false, param_names, rest_param, body,
              )
              interp.validate_block_early_errors(body, body_strict)
              return @runtime.stamp_function_realm(
                Value::Object({
                  bag: {
                    properties: fn_props,
                    symbol_properties: {},
                    descriptors: { "length": nf_desc },
                    symbol_descriptors: {},
                  },
                  prototype: func_proto,
                  callable: Some(
                    UserFuncExt({
                      name: Some("anonymous"),
                      params,
                      rest_param,
                      body,
                      closure: env,
                      strict: body_strict,
                      has_name_binding: false,
                      is_method: false,
                    }),
                  ),
                  class_name: "Function",
                  extensible: true,
                  arraybuffer_state: None,
                }),
                realm_state=Some(realm_state),
              )
            }
            _ => ()
          }
        }
        // Fallback: empty function
        @runtime.stamp_function_realm(
          Value::Object({
            bag: @runtime.PropertyBag(),
            prototype: func_proto,
            callable: Some(NativeCallable("anonymous", fn(_) { Undefined })),
            class_name: "Function",
            extensible: true,
            arraybuffer_state: None,
          }),
          realm_state=Some(realm_state),
        )
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })

  // Add constructor back-reference to prototype (same object as global Function)
  match func_proto {
    Object(data) => {
      data.bag.properties["constructor"] = func_ctor
      data.bag.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      }
    }
    _ => ()
  }

  // Register Function.prototype so other builtins can look it up
  env.def_builtin("[[FunctionPrototype]]", func_proto)
  realm_state.function_prototype.val = Some(func_proto)
  // Register the same Function constructor object globally
  env.def_builtin("Function", func_ctor)
}
