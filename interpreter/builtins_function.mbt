///|
fn setup_function_builtins(env : Environment) -> Unit {
  // Create Function.prototype
  let func_proto_props : Map[String, Value] = {}

  // Function.prototype.toString - returns function source or [native code]
  func_proto_props["toString"] = make_method_func("toString", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Object(data) =>
        match data.callable {
          Some(UserFunc(func_data)) => {
            let name = func_data.name.unwrap_or("")
            String_("function " + name + "() { [native code] }")
          }
          Some(UserFuncExt(func_data)) => {
            let name = func_data.name.unwrap_or("")
            String_("function " + name + "() { [native code] }")
          }
          Some(ArrowFunc(_)) => String_("() => { [native code] }")
          Some(ArrowFuncExt(_)) => String_("() => { [native code] }")
          Some(NativeCallable(name, _)) =>
            String_("function " + name + "() { [native code] }")
          Some(NonConstructableCallable(name, _)) =>
            String_("function " + name + "() { [native code] }")
          Some(BoundFunc(_, _, _)) => String_("function () { [native code] }")
          Some(MethodCallable(name, _)) =>
            String_("function " + name + "() { [native code] }")
          Some(InterpreterCallable(name, _)) =>
            String_("function " + name + "() { [native code] }")
          Some(ConstructorOnlyCallable(name, _)) =>
            String_("function " + name + "() { [native code] }")
          Some(FuncCallMethod(_)) =>
            String_("function call() { [native code] }")
          Some(FuncApplyMethod(_)) =>
            String_("function apply() { [native code] }")
          Some(ClassConstructor({ name, .. })) =>
            String_("class " + name + " { [native code] }")
          None =>
            raise @errors.TypeError(
              message="Function.prototype.toString requires a function",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Function.prototype.toString requires a function",
        )
    }
  })

  // Function.prototype.call - placeholder (actual implementation in interpreter)
  func_proto_props["call"] = make_interp_method_func("call", 1, fn(
    interp,
    this_val,
    args,
  ) raise {
    let loc = @token.Loc::default()
    let call_this : Value = if args.length() > 0 { args[0] } else { Undefined }
    let call_args : Array[Value] = []
    for i = 1; i < args.length(); i = i + 1 {
      call_args.push(args[i])
    }
    interp.call_value(this_val, call_this, call_args, loc)
  })

  // Function.prototype.apply
  func_proto_props["apply"] = make_interp_method_func("apply", 2, fn(
    interp,
    this_val,
    args,
  ) raise {
    let loc = @token.Loc::default()
    let call_this : Value = if args.length() > 0 { args[0] } else { Undefined }
    let call_args : Array[Value] = []
    if args.length() > 1 {
      // Convert args[1] to array-like
      match args[1] {
        Array(data) =>
          for el in data.elements {
            call_args.push(el)
          }
        Object(data) => {
          let len = match data.properties.get("length") {
            Some(Number(n)) => n.to_int()
            _ => 0
          }
          for i = 0; i < len; i = i + 1 {
            let val = match data.properties.get(i.to_string()) {
              Some(v) => v
              None => Undefined
            }
            call_args.push(val)
          }
        }
        Null | Undefined => ()
        _ => ()
      }
    }
    interp.call_value(this_val, call_this, call_args, loc)
  })

  // Function.prototype.bind - placeholder (actual implementation in interpreter)
  func_proto_props["bind"] = make_interp_method_func("bind", 1, fn(
    _interp,
    this_val,
    args,
  ) raise {
    // Function.prototype.bind - §20.2.3.2
    // Step 1: If IsCallable(this) is false, throw a TypeError exception
    if !is_function_value(this_val) {
      raise @errors.TypeError(
        message="Function.prototype.bind called on non-callable",
      )
    }
    let bind_this = if args.length() > 0 { args[0] } else { Undefined }
    let bound_args : Array[Value] = []
    for i = 1; i < args.length(); i = i + 1 {
      bound_args.push(args[i])
    }
    let bound_name = get_bound_func_name(this_val)
    let target_length = match this_val {
      Object(data) =>
        match data.callable {
          Some(c) => get_func_length(c)
          None => 0
        }
      _ => 0
    }
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
    }
    let bprops : Map[String, Value] = {}
    bprops["name"] = String_(bound_name)
    bprops["length"] = Number(bound_length.to_double())
    Object({
      properties: bprops,
      symbol_properties: {},
      prototype: get_func_proto(),
      callable: Some(BoundFunc(this_val, bind_this, bound_args)),
      class_name: "Function",
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
      extensible: true,
    })
  })
  // %ThrowTypeError% intrinsic (ES spec §10.2.4)
  // A single frozen function that throws TypeError when called.
  let throw_type_error : Value = Object({
    properties: { "length": Number(0.0), "name": String_("") },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NonConstructableCallable("", fn(_args) raise {
        raise @errors.TypeError(
          message="'caller', 'callee', and 'arguments' properties may not be accessed on strict mode functions or the arguments objects for calls to them",
        )
      }),
    ),
    class_name: "Function",
    descriptors: {
      "length": {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
      },
      "name": {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
      },
    },
    symbol_descriptors: {},
    extensible: false,
  })

  // Install ThrowTypeError accessors on Function.prototype for caller and arguments
  let func_proto_descs : Map[String, PropDescriptor] = {}
  func_proto_descs["caller"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(throw_type_error),
    setter: Some(throw_type_error),
  }
  func_proto_descs["arguments"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(throw_type_error),
    setter: Some(throw_type_error),
  }
  func_proto_descs["toString"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  func_proto_descs["call"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  func_proto_descs["apply"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  func_proto_descs["bind"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }

  // Function.prototype is callable per spec (returns undefined when called)
  // and has name="" and length=0 own properties
  func_proto_props["name"] = String_("")
  func_proto_props["length"] = Number(0.0)
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  func_proto_descs["name"] = nf_desc
  func_proto_descs["length"] = nf_desc
  let func_proto : Value = Object({
    properties: func_proto_props,
    symbol_properties: {},
    prototype: Null,
    callable: Some(NonConstructableCallable("", fn(_args) { Undefined })),
    class_name: "Function",
    descriptors: func_proto_descs,
    symbol_descriptors: {},
    extensible: true,
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
  func_ctor_props["length"] = Number(1.0)
  func_ctor_props["name"] = String_("Function")

  // Create a single Function constructor object.
  // Function(p1, p2, ..., body) parses the body string and creates a real function.
  let func_ctor : Value = Object({
    properties: func_ctor_props,
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("Function", fn(args) raise {
        if args.length() == 0 {
          return Object({
            properties: {},
            symbol_properties: {},
            prototype: func_proto,
            callable: Some(NativeCallable("anonymous", fn(_) { Undefined })),
            class_name: "Function",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
        }
        // Last arg is body, previous args are parameter names
        let body_str = match args[args.length() - 1] {
          String_(s) => s
          _ => args[args.length() - 1].to_string()
        }
        let param_parts : Array[String] = []
        for i = 0; i < args.length() - 1; i = i + 1 {
          match args[i] {
            String_(s) => param_parts.push(s)
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
              fn_props["length"] = Number(params.length().to_double())
              return Object({
                properties: fn_props,
                symbol_properties: {},
                prototype: func_proto,
                callable: Some(
                  UserFunc({
                    name: Some("anonymous"),
                    params,
                    body,
                    closure: env,
                    strict: has_use_strict(body),
                  }),
                ),
                class_name: "Function",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            }
            FuncDeclExt(_, params, rest_param, body, _) => {
              let fn_props : Map[String, Value] = {}
              fn_props["length"] = Number(params.length().to_double())
              return Object({
                properties: fn_props,
                symbol_properties: {},
                prototype: func_proto,
                callable: Some(
                  UserFuncExt({
                    name: Some("anonymous"),
                    params,
                    rest_param,
                    body,
                    closure: env,
                    strict: has_use_strict(body),
                  }),
                ),
                class_name: "Function",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            }
            _ => ()
          }
        }
        // Fallback: empty function
        Object({
          properties: {},
          symbol_properties: {},
          prototype: func_proto,
          callable: Some(NativeCallable("anonymous", fn(_) { Undefined })),
          class_name: "Function",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
      }),
    ),
    class_name: "Function",
    descriptors: { "name": nf_desc, "length": nf_desc },
    symbol_descriptors: {},
    extensible: true,
  })

  // Add constructor back-reference to prototype (same object as global Function)
  match func_proto {
    Object(data) => {
      data.properties["constructor"] = func_ctor
      data.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }

  // Register Function.prototype so other builtins can look it up
  env.def_builtin("[[FunctionPrototype]]", func_proto)
  function_prototype_ref.val = Some(func_proto)
  // Register the same Function constructor object globally
  env.def_builtin("Function", func_ctor)
}
