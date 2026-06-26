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
/// ES262 §10.2.4 ExpectedArgumentCount for extended parameter lists:
/// count parameters before the first default initializer or rest parameter.
fn callable_source_text(data : @runtime.ObjectData) -> String? {
  match data.callable {
    Some(UserFunc(func_data)) | Some(ArrowFunc(func_data)) =>
      func_data.source_text
    Some(UserFuncExt(func_data)) | Some(ArrowFuncExt(func_data)) =>
      func_data.source_text
    Some(ClassConstructor({ source_text, .. })) => source_text
    Some(InterpreterCallable(_, _))
    | Some(InterpreterCallableWithContext(_, _)) =>
      match data.bag.internal_slots.get(@runtime.SourceText) {
        Some(String_(text)) => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
fn expected_argument_count_ext(params : Array[@ast.Param]) -> Int {
  for p in params; count = 0 {
    if p.default_val is Some(_) || p.is_rest_pattern {
      break count
    }
    continue count + 1
  } nobreak {
    count
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
          match callable_source_text(data) {
            Some(text) => Value::String_(text)
            None =>
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
                  Value::String_(prefix + "bound() { [native code] }")
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
        }
        Proxy(proxy_data) =>
          if proxy_data.is_callable {
            Value::String_("function proxy() { [native code] }")
          } else {
            raise @errors.TypeError(
              message="Function.prototype.toString requires a function",
            )
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
    fn(interp, this_val, args) raise {
      // Function.prototype.bind - §20.2.3.2
      // Step 1: If IsCallable(this) is false, throw a TypeError exception
      if !@runtime.is_function_value(this_val) {
        raise @errors.TypeError(
          message="Function.prototype.bind called on non-callable",
        )
      }
      let loc = @token.Loc::default()
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
      // §20.2.3.2 steps 5–6: HasOwnProperty("length"), then ToIntegerOrInfinity
      // Must come before the "name" Get so a name getter cannot mutate length first.
      let arg_count = bound_args.length().to_double()
      let bound_length : Double = match
        interp.get_own_property(this_val, Value::String_("length")) {
        Some(_) =>
          match interp.get_property(this_val, "length", loc) {
            Value::Number(n) =>
              if n.is_inf() && n > 0.0 {
                // +∞: L = +∞ (preserved as-is)
                n
              } else if n.is_inf() {
                // -∞: L = 0
                0.0
              } else {
                // ToIntegerOrInfinity: truncate toward zero (NaN → 0)
                let int_n : Double = if n.is_nan() {
                  0.0
                } else if n >= 0.0 {
                  n.floor()
                } else {
                  n.ceil()
                }
                (int_n - arg_count).max(0.0)
              }
            _ => 0.0
          }
        None => 0.0
      }
      // §20.2.3.2 steps 12–14: Get "name" via JS property access so getter errors propagate
      let raw_name = interp.get_property(this_val, "name", loc)
      let bound_name = match raw_name {
        Value::String_(s) => "bound " + s
        _ => "bound "
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
      bprops["length"] = Value::Number(bound_length)
      bprops["name"] = Value::String_(bound_name)
      @runtime.stamp_function_realm(
        Value::Object({
          bag: {
            properties: bprops,
            symbol_properties: {},
            descriptors: { "length": nf_desc, "name": nf_desc },
            symbol_descriptors: {},
            internal_slots: {},
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
      internal_slots: {},
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
  let fp_method_desc = @runtime.builtin_method_desc()
  func_proto_descs["toString"] = fp_method_desc
  func_proto_descs["call"] = fp_method_desc
  func_proto_descs["apply"] = fp_method_desc
  func_proto_descs["bind"] = fp_method_desc

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
      internal_slots: {},
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
      internal_slots: {},
    },
    prototype: Null,
    callable: Some(
      InterpreterCallable("Function", fn(interp, _this, args) raise {
        // §20.2.1.1.1 CreateDynamicFunction: coerce params first (step 5a), body second (step 6).
        // Order matters: a throwing body toString must not suppress param toString side-effects.
        let param_count = if args.length() == 0 { 0 } else { args.length() - 1 }
        let param_parts : Array[String] = []
        for i = 0; i < param_count; i = i + 1 {
          match args[i] {
            Value::String_(s) => param_parts.push(s)
            _ => param_parts.push(interp.to_js_string(args[i]))
          }
        }
        let params_str = param_parts.join(",")
        let body_str = if args.length() == 0 {
          ""
        } else {
          match args[args.length() - 1] {
            Value::String_(s) => s
            _ => interp.to_js_string(args[args.length() - 1])
          }
        }
        let source = "function anonymous(" +
          params_str +
          "\n) {\n" +
          body_str +
          "\n}"
        let prog = @parser.parse(source)
        // The first statement should be a function declaration — extract its parts
        if prog.stmts.length() > 0 {
          match prog.stmts[0] {
            FuncDecl(_, params, body, _, _) => {
              // §20.2.1.1.1 step 27a: create .prototype object inheriting from Object.prototype.
              let object_proto = @runtime.get_obj_proto(
                realm_state=Some(realm_state),
              )
              let proto = Value::Object({
                bag: @runtime.PropertyBag(),
                prototype: object_proto,
                callable: None,
                class_name: "Object",
                extensible: true,
                arraybuffer_state: None,
              })
              let fn_props : Map[String, Value] = {}
              fn_props["length"] = Value::Number(params.length().to_double())
              fn_props["name"] = Value::String_("anonymous")
              fn_props["prototype"] = proto
              // Validate static early errors against the function's strict context.
              let body_strict = @static_semantics.has_use_strict(body)
              @runtime.validate_function_constructor_params(
                true,
                params,
                None,
                body,
              )
              interp.validate_block_early_errors(body, body_strict)
              let result = @runtime.stamp_function_realm(
                Value::Object({
                  bag: {
                    properties: fn_props,
                    symbol_properties: {},
                    descriptors: {
                      "length": nf_desc,
                      "name": nf_desc,
                      "prototype": {
                        writable: true,
                        enumerable: false,
                        configurable: false,
                        getter: None,
                        setter: None,
                        is_accessor: false,
                      },
                    },
                    symbol_descriptors: {},
                    internal_slots: {},
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
                      source_text: Some(source),
                    }),
                  ),
                  class_name: "Function",
                  extensible: true,
                  arraybuffer_state: None,
                }),
                realm_state=Some(realm_state),
              )
              match proto {
                Object(proto_data) => {
                  proto_data.bag.properties["constructor"] = result
                  proto_data.bag.descriptors["constructor"] = {
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
              return result
            }
            FuncDeclExt(_, params, rest_param, body, _, _) => {
              let object_proto = @runtime.get_obj_proto(
                realm_state=Some(realm_state),
              )
              let proto = Value::Object({
                bag: @runtime.PropertyBag(),
                prototype: object_proto,
                callable: None,
                class_name: "Object",
                extensible: true,
                arraybuffer_state: None,
              })
              let fn_props : Map[String, Value] = {}
              let fn_length = expected_argument_count_ext(params)
              fn_props["length"] = Value::Number(fn_length.to_double())
              fn_props["name"] = Value::String_("anonymous")
              fn_props["prototype"] = proto
              // Validate static early errors against the function's strict context.
              let body_strict = @static_semantics.has_use_strict(body)
              @runtime.validate_function_constructor_params_ext(
                params, rest_param, body,
              )
              interp.validate_block_early_errors(body, body_strict)
              let result = @runtime.stamp_function_realm(
                Value::Object({
                  bag: {
                    properties: fn_props,
                    symbol_properties: {},
                    descriptors: {
                      "length": nf_desc,
                      "name": nf_desc,
                      "prototype": {
                        writable: true,
                        enumerable: false,
                        configurable: false,
                        getter: None,
                        setter: None,
                        is_accessor: false,
                      },
                    },
                    symbol_descriptors: {},
                    internal_slots: {},
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
                      source_text: Some(source),
                    }),
                  ),
                  class_name: "Function",
                  extensible: true,
                  arraybuffer_state: None,
                }),
                realm_state=Some(realm_state),
              )
              match proto {
                Object(proto_data) => {
                  proto_data.bag.properties["constructor"] = result
                  proto_data.bag.descriptors["constructor"] = {
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
              return result
            }
            _ => ()
          }
        }
        // Fallback: empty function (defensive — synthesized source always parses)
        let fb_object_proto = @runtime.get_obj_proto(
          realm_state=Some(realm_state),
        )
        let fb_proto = Value::Object({
          bag: @runtime.PropertyBag(),
          prototype: fb_object_proto,
          callable: None,
          class_name: "Object",
          extensible: true,
          arraybuffer_state: None,
        })
        let fb_result = @runtime.stamp_function_realm(
          Value::Object({
            bag: {
              properties: {
                "length": Value::Number(0.0),
                "name": Value::String_("anonymous"),
                "prototype": fb_proto,
              },
              symbol_properties: {},
              descriptors: {
                "length": nf_desc,
                "name": nf_desc,
                "prototype": {
                  writable: true,
                  enumerable: false,
                  configurable: false,
                  getter: None,
                  setter: None,
                  is_accessor: false,
                },
              },
              symbol_descriptors: {},
              internal_slots: {},
            },
            prototype: func_proto,
            callable: Some(NativeCallable("anonymous", fn(_) { Undefined })),
            class_name: "Function",
            extensible: true,
            arraybuffer_state: None,
          }),
          realm_state=Some(realm_state),
        )
        match fb_proto {
          Object(fb_proto_data) => {
            fb_proto_data.bag.properties["constructor"] = fb_result
            fb_proto_data.bag.descriptors["constructor"] = {
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
        fb_result
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })

  // Add constructor back-reference to prototype (same object as global Function)
  match func_proto {
    Object(data) =>
      @runtime.install_builtin_method(data, "constructor", func_ctor)
    _ => ()
  }

  // Register Function.prototype so other builtins can look it up
  env.def_builtin("[[FunctionPrototype]]", func_proto)
  realm_state.function_prototype.val = Some(func_proto)
  // Register the same Function constructor object globally
  env.def_builtin("Function", func_ctor)
}
