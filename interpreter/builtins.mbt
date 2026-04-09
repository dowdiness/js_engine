///|
pub fn setup_builtins(
  env : Environment,
  output : Array[String],
  annex_b? : Bool = false,
) -> Unit {
  let _ = output
  // Global constants
  env.def_builtin("NaN", Number(0.0 / 0.0))
  env.def_builtin("Infinity", Number(1.0 / 0.0))
  env.def_builtin("undefined", Undefined)

  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  // eval(x) — NonConstructableCallable so that new eval() throws TypeError.
  // Direct eval is handled at the call-site in eval_call.
  // Indirect eval (0,eval)("code") is intercepted in call_value where the
  // interpreter is available for perform_eval.
  let eval_func : Value = Object({
    properties: { "length": Number(1.0), "name": String_("eval") },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NonConstructableCallable("eval", fn(args) {
        // Non-string argument returns as-is (string case handled in call_value)
        if args.length() == 0 {
          return Undefined
        }
        args[0]
      }),
    ),
    class_name: "Function",
    descriptors: { "length": nf_desc, "name": nf_desc },
    symbol_descriptors: {},
    extensible: true,
  })
  env.def_builtin("eval", eval_func)

  // isNaN(value)
  env.def_builtin(
    "isNaN",
    make_static_func_with_length("isNaN", 1, fn(args) raise {
      let val = if args.length() > 0 { args[0] } else { Undefined }
      let n = to_number(val)
      Bool(n.is_nan())
    }),
  )

  // isFinite(value)
  env.def_builtin(
    "isFinite",
    make_static_func_with_length("isFinite", 1, fn(args) raise {
      let val = if args.length() > 0 { args[0] } else { Undefined }
      let n = to_number(val)
      Bool(!n.is_nan() && !n.is_inf())
    }),
  )

  // parseInt(string, radix?)
  env.def_builtin(
    "parseInt",
    make_static_func_with_length("parseInt", 2, fn(args) raise {
      let str_val = if args.length() > 0 { args[0] } else { Undefined }
      let s = to_js_string(str_val)
      let trimmed = trim_start(s)
      if trimmed.length() == 0 {
        return Number(0.0 / 0.0)
      }
      let chars = trimmed.to_array()
      let mut pos = 0
      let mut sign = 1.0
      if pos < chars.length() && chars[pos] == '+' {
        pos = pos + 1
      } else if pos < chars.length() && chars[pos] == '-' {
        sign = -1.0
        pos = pos + 1
      }
      let radix_arg = if args.length() > 1 {
        to_int32(to_number(args[1]))
      } else {
        0
      }
      let mut radix = if radix_arg == 0 {
        10 // radix 0 defaults to 10
      } else if radix_arg < 2 || radix_arg > 36 {
        return Number(0.0 / 0.0)
      } else {
        radix_arg
      }
      // Detect 0x prefix for hex
      if radix == 16 || radix_arg == 0 {
        if pos + 1 < chars.length() &&
          chars[pos] == '0' &&
          (chars[pos + 1] == 'x' || chars[pos + 1] == 'X') {
          radix = 16
          pos = pos + 2
        }
      }
      let mut result = 0.0
      let mut found = false
      while pos < chars.length() {
        let c = chars[pos]
        let digit = char_to_digit(c, radix)
        if digit < 0 {
          break
        }
        result = result * radix.to_double() + digit.to_double()
        found = true
        pos = pos + 1
      }
      if !found {
        Number(0.0 / 0.0)
      } else {
        Number(sign * result)
      }
    }),
  )

  // parseFloat(string)
  env.def_builtin(
    "parseFloat",
    make_static_func_with_length("parseFloat", 1, fn(args) raise {
      let str_val = if args.length() > 0 { args[0] } else { Undefined }
      let s = to_js_string(str_val)
      let trimmed = trim_start(s)
      if trimmed.length() == 0 {
        return Number(0.0 / 0.0)
      }
      let chars = trimmed.to_array()
      let len = chars.length()
      let mut pos = 0
      // Optional sign
      if pos < len && (chars[pos] == '+' || chars[pos] == '-') {
        pos = pos + 1
      }
      // Check for Infinity
      let sign_end = pos
      if pos + 8 <= len &&
        chars[pos] == 'I' &&
        chars[pos + 1] == 'n' &&
        chars[pos + 2] == 'f' &&
        chars[pos + 3] == 'i' &&
        chars[pos + 4] == 'n' &&
        chars[pos + 5] == 'i' &&
        chars[pos + 6] == 't' &&
        chars[pos + 7] == 'y' {
        let sign : Double = if sign_end > 0 && chars[0] == '-' {
          -1.0
        } else {
          1.0
        }
        return Number(sign * (1.0 / 0.0))
      }
      // Single-pass scan: [+-]? digits? [. digits?] ([eE] [+-]? digits)?
      let mut has_digits = false
      // Integer part digits
      while pos < len && chars[pos] >= '0' && chars[pos] <= '9' {
        has_digits = true
        pos = pos + 1
      }
      // Fractional part
      if pos < len && chars[pos] == '.' {
        pos = pos + 1
        while pos < len && chars[pos] >= '0' && chars[pos] <= '9' {
          has_digits = true
          pos = pos + 1
        }
      }
      if !has_digits {
        return Number(0.0 / 0.0)
      }
      // Exponent part
      if pos < len && (chars[pos] == 'e' || chars[pos] == 'E') {
        let saved = pos
        pos = pos + 1
        if pos < len && (chars[pos] == '+' || chars[pos] == '-') {
          pos = pos + 1
        }
        let exp_start = pos
        while pos < len && chars[pos] >= '0' && chars[pos] <= '9' {
          pos = pos + 1
        }
        // If no exponent digits, revert to before 'e'/'E'
        if pos == exp_start {
          pos = saved
        }
      }
      // Build the prefix string and parse once
      let buf = StringBuilder::new()
      for i = 0; i < pos; i = i + 1 {
        buf.write_char(chars[i])
      }
      let result = @string.parse_double(buf.to_string()) catch {
        _ => 0.0 / 0.0
      }
      Number(result)
    }),
  )

  // encodeURIComponent(string)
  env.def_builtin(
    "encodeURIComponent",
    make_static_func_with_length("encodeURIComponent", 1, fn(args) raise {
      let str = if args.length() > 0 {
        to_js_string(args[0])
      } else {
        "undefined"
      }
      String_(uri_encode(str, true))
    }),
  )

  // decodeURIComponent(string) - decodes everything
  env.def_builtin(
    "decodeURIComponent",
    make_static_func_with_length("decodeURIComponent", 1, fn(args) raise {
      let str = if args.length() > 0 {
        to_js_string(args[0])
      } else {
        "undefined"
      }
      String_(uri_decode(str, false))
    }),
  )

  // encodeURI(string)
  env.def_builtin(
    "encodeURI",
    make_static_func_with_length("encodeURI", 1, fn(args) raise {
      let str = if args.length() > 0 {
        to_js_string(args[0])
      } else {
        "undefined"
      }
      String_(uri_encode(str, false))
    }),
  )

  // decodeURI(string) - preserves reserved characters (; , / ? : @ & = + $ #)
  env.def_builtin(
    "decodeURI",
    make_static_func_with_length("decodeURI", 1, fn(args) raise {
      let str = if args.length() > 0 {
        to_js_string(args[0])
      } else {
        "undefined"
      }
      String_(uri_decode(str, true))
    }),
  )

  // escape(string) — Annex B
  env.def_builtin(
    "escape",
    make_static_func_with_length("escape", 1, fn(args) raise {
      let str = if args.length() > 0 {
        to_js_string(args[0])
      } else {
        "undefined"
      }
      String_(js_escape(str))
    }),
  )

  // unescape(string) — Annex B
  env.def_builtin(
    "unescape",
    make_static_func_with_length("unescape", 1, fn(args) raise {
      let str = if args.length() > 0 {
        to_js_string(args[0])
      } else {
        "undefined"
      }
      String_(js_unescape(str))
    }),
  )

  // String constructor with static methods
  let string_proto : Value = Object({
    properties: { "[[StringData]]": String_(""), "length": Number(0.0) },
    symbol_properties: {},
    prototype: get_obj_proto(),
    callable: None,
    class_name: "String",
    descriptors: {
      "length": {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
      },
    },
    symbol_descriptors: {},
    extensible: true,
  })
  env.def_builtin(
    "String",
    Object({
      properties: {
        "prototype": string_proto,
        "name": String_("String"),
        "length": Number(1.0),
        "fromCharCode": make_static_func_with_length("fromCharCode", 1, fn(
          args,
        ) raise {
          let buf = StringBuilder::new()
          for arg in args {
            let code = to_number(arg).to_int()
            // fromCharCode uses UTF-16 code units, modulo 2^16
            let code_unit = code & 0xFFFF
            buf.write_char(code_unit.unsafe_to_char())
          }
          String_(buf.to_string())
        }),
        "fromCodePoint": make_static_func_with_length("fromCodePoint", 1, fn(
          args,
        ) raise {
          // String.fromCodePoint() - accepts Unicode code points (not code units)
          let buf = StringBuilder::new()
          for arg in args {
            let num = to_number(arg)
            // Check if it's a valid number
            if num.is_nan() || num.is_inf() {
              raise @errors.RangeError(message="Invalid code point")
            }
            // Check if it's an integer (no fractional part)
            let code = num.to_int()
            if code.to_double() != num {
              raise @errors.RangeError(message="Invalid code point")
            }
            // Valid Unicode code points: 0 to 0x10FFFF
            if code < 0 || code > 0x10FFFF {
              raise @errors.RangeError(
                message="Invalid code point \{code.to_string()}",
              )
            }
            // Convert code point to UTF-16
            if code <= 0xFFFF {
              // BMP (Basic Multilingual Plane) - single code unit
              buf.write_char(code.unsafe_to_char())
            } else {
              // Supplementary planes - surrogate pair
              let code_adj = code - 0x10000
              let high = 0xD800 + (code_adj >> 10)
              let low = 0xDC00 + (code_adj & 0x3FF)
              buf.write_char(high.unsafe_to_char())
              buf.write_char(low.unsafe_to_char())
            }
          }
          String_(buf.to_string())
        }),
        "raw": make_static_func_with_length("raw", 1, fn(args) raise {
          // String.raw(template, ...substitutions)
          // Returns raw string content without processing escape sequences
          if args.length() == 0 {
            return String_("")
          }
          let template = args[0]
          match template {
            Object(data) =>
              match data.properties.get("raw") {
                Some(Array(raw_data)) => {
                  let buf = StringBuilder::new()
                  let raw_strings = raw_data.elements
                  let sub_count = args.length() - 1
                  for i = 0; i < raw_strings.length(); i = i + 1 {
                    // Add raw string segment
                    buf.write_string(raw_strings[i].to_string())
                    // Add substitution if available
                    if i < sub_count {
                      buf.write_string(args[i + 1].to_string())
                    }
                  }
                  String_(buf.to_string())
                }
                Some(Object(raw_obj)) => {
                  // Handle object with numeric indices - use length property per spec
                  let buf = StringBuilder::new()
                  let sub_count = args.length() - 1

                  // Get length property (treat missing/invalid as 0)
                  let length = match raw_obj.properties.get("length") {
                    Some(Number(n)) => n.to_int().max(0)
                    _ => 0
                  }

                  // Iterate from 0 to length-1, treating missing indices as Undefined
                  for i = 0; i < length; i = i + 1 {
                    let str_val = match raw_obj.properties.get(i.to_string()) {
                      Some(v) => v
                      None => Undefined
                    }
                    buf.write_string(str_val.to_string())
                    // Add substitution if available
                    if i < sub_count {
                      buf.write_string(args[i + 1].to_string())
                    }
                  }
                  String_(buf.to_string())
                }
                _ =>
                  raise @errors.TypeError(
                    message="Cannot convert to string template",
                  )
              }
            _ =>
              raise @errors.TypeError(
                message="Cannot convert to string template",
              )
          }
        }),
      },
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable("String", fn(args) raise {
          let str = if args.length() == 0 {
            // Per spec: String() with no args returns ""
            ""
          } else {
            let val = args[0]
            // Per spec: String(symbol) returns the symbol description
            match val {
              Symbol(sym) =>
                match sym.description {
                  Some(d) => "Symbol(" + d + ")"
                  None => "Symbol()"
                }
              _ => to_js_string(val)
            }
          }
          if is_constructing.val {
            // new String(value) → boxed String object
            let props : Map[String, Value] = {}
            props["[[StringData]]"] = String_(str)
            props["length"] = Number(str.length().to_double())
            // Add indexed character properties
            for i = 0; i < str.length(); i = i + 1 {
              props[i.to_string()] = String_(str.view()[i:i + 1].to_string())
            }
            let descs : Map[String, PropDescriptor] = {}
            descs["length"] = {
              writable: false,
              enumerable: false,
              configurable: false,
              getter: None,
              setter: None,
            }
            for i = 0; i < str.length(); i = i + 1 {
              descs[i.to_string()] = {
                writable: false,
                enumerable: true,
                configurable: false,
                getter: None,
                setter: None,
              }
            }
            Object({
              properties: props,
              symbol_properties: {},
              prototype: string_proto,
              callable: None,
              class_name: "String",
              descriptors: descs,
              symbol_descriptors: {},
              extensible: true,
            })
          } else {
            String_(str)
          }
        }),
      ),
      class_name: "Function",
      descriptors: {
        "name": nf_desc,
        "length": nf_desc,
        "prototype": {
          writable: false,
          enumerable: false,
          configurable: false,
          getter: None,
          setter: None,
        },
        "fromCharCode": {
          writable: true,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        },
        "fromCodePoint": {
          writable: true,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        },
        "raw": {
          writable: true,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        },
      },
      symbol_descriptors: {},
      extensible: true,
    }),
  )

  // Store String.prototype for ToObject wrapping
  env.def_builtin("[[StringPrototype]]", string_proto)
  string_prototype_ref.val = Some(string_proto)
  // Populate String.prototype with methods for .call() support
  setup_string_prototype(string_proto, annex_b~)
  // Set String.prototype.constructor = String
  match string_proto {
    Object(data) => {
      let ctor = env.get("String") catch { _ => Undefined }
      data.properties["constructor"] = ctor
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

  // Number constructor with static methods and prototype
  setup_number_builtins(env)

  // Boolean constructor with prototype
  let boolean_proto_props : Map[String, Value] = {}
  boolean_proto_props["toString"] = make_method_func("toString", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Bool(b) => String_(b.to_string())
      Object(data) =>
        if data.class_name == "Boolean" {
          match data.properties.get("[[BooleanData]]") {
            Some(Bool(b)) => String_(b.to_string())
            _ =>
              raise @errors.TypeError(
                message="Boolean.prototype.toString requires a Boolean",
              )
          }
        } else {
          raise @errors.TypeError(
            message="Boolean.prototype.toString requires a Boolean",
          )
        }
      _ =>
        raise @errors.TypeError(
          message="Boolean.prototype.toString requires a Boolean",
        )
    }
  })
  boolean_proto_props["valueOf"] = make_method_func("valueOf", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Bool(b) => Bool(b)
      Object(data) =>
        if data.class_name == "Boolean" {
          match data.properties.get("[[BooleanData]]") {
            Some(Bool(b)) => Bool(b)
            _ =>
              raise @errors.TypeError(
                message="Boolean.prototype.valueOf requires a Boolean",
              )
          }
        } else {
          raise @errors.TypeError(
            message="Boolean.prototype.valueOf requires a Boolean",
          )
        }
      _ =>
        raise @errors.TypeError(
          message="Boolean.prototype.valueOf requires a Boolean",
        )
    }
  })
  // Boolean.prototype has [[BooleanData]] internal slot with value false
  boolean_proto_props["[[BooleanData]]"] = Bool(false)
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let boolean_proto_descs : Map[String, PropDescriptor] = {}
  boolean_proto_descs["toString"] = method_desc
  boolean_proto_descs["valueOf"] = method_desc
  let boolean_proto : Value = Object({
    properties: boolean_proto_props,
    symbol_properties: {},
    prototype: get_obj_proto(),
    callable: None,
    class_name: "Boolean",
    descriptors: boolean_proto_descs,
    symbol_descriptors: {},
    extensible: true,
  })
  // Store Boolean.prototype for ToObject wrapping
  env.def_builtin("[[BooleanPrototype]]", boolean_proto)
  boolean_prototype_ref.val = Some(boolean_proto)
  env.def_builtin(
    "Boolean",
    Object({
      properties: {
        "prototype": boolean_proto,
        "name": String_("Boolean"),
        "length": Number(1.0),
      },
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable("Boolean", fn(args) {
          let val = if args.length() > 0 { args[0] } else { Undefined }
          let b = is_truthy(val)
          if is_constructing.val {
            // new Boolean(value) → boxed Boolean object
            Object({
              properties: { "[[BooleanData]]": Bool(b) },
              symbol_properties: {},
              prototype: boolean_proto,
              callable: None,
              class_name: "Boolean",
              descriptors: {},
              symbol_descriptors: {},
              extensible: true,
            })
          } else {
            Bool(b)
          }
        }),
      ),
      class_name: "Function",
      descriptors: {
        "name": nf_desc,
        "length": nf_desc,
        "prototype": {
          writable: false,
          enumerable: false,
          configurable: false,
          getter: None,
          setter: None,
        },
      },
      symbol_descriptors: {},
      extensible: true,
    }),
  )

  // Set Boolean.prototype.constructor = Boolean
  match boolean_proto {
    Object(data) => {
      let ctor = env.get("Boolean") catch { _ => Undefined }
      data.properties["constructor"] = ctor
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

  // Function constructor with prototype
  setup_function_builtins(env)

  // Error constructors
  let error_proto = register_error_ctor(env, "Error", get_obj_proto())
  register_error_ctor(env, "TypeError", error_proto) |> ignore
  register_error_ctor(env, "ReferenceError", error_proto) |> ignore
  register_error_ctor(env, "SyntaxError", error_proto) |> ignore
  register_error_ctor(env, "RangeError", error_proto) |> ignore
  register_error_ctor(env, "URIError", error_proto) |> ignore
  register_error_ctor(env, "EvalError", error_proto) |> ignore
  register_aggregate_error_ctor(env, error_proto) |> ignore

  // Add Error.isError static method
  let error_ctor = env.get("Error") catch { _ => Undefined }
  match error_ctor {
    Object(error_data) => {
      error_data.properties["isError"] = make_static_func_with_length(
        "isError",
        1,
        fn(args) {
          let arg = if args.length() > 0 { args[0] } else { Undefined }
          match arg {
            Object(data) =>
              // Check if the object's class_name is an error type
              Bool(
                data.class_name == "Error" ||
                data.class_name == "TypeError" ||
                data.class_name == "SyntaxError" ||
                data.class_name == "RangeError" ||
                data.class_name == "ReferenceError" ||
                data.class_name == "URIError" ||
                data.class_name == "EvalError" ||
                data.class_name == "AggregateError",
              )
            _ => Bool(false)
          }
        },
      )
      error_data.descriptors["isError"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }

  // Object, Array constructors and built-in methods
  setup_object_builtins(env)

  // Now that Object.prototype and Function.prototype exist, patch built-in
  // prototype chains.  Boolean.prototype, String.prototype, Number.prototype
  // all need [[Prototype]] = Object.prototype.  Built-in constructors like
  // Boolean need [[Prototype]] = Function.prototype.
  match env.bindings.get("[[ObjectPrototype]]") {
    Some(binding) => {
      let obj_proto = binding.value
      // Patch Boolean.prototype.[[Prototype]]
      match env.bindings.get("[[BooleanPrototype]]") {
        Some(bp) =>
          match bp.value {
            Object(data) => data.prototype = obj_proto
            _ => ()
          }
        None => ()
      }
      // Patch String.prototype.[[Prototype]]
      match env.bindings.get("[[StringPrototype]]") {
        Some(sp) =>
          match sp.value {
            Object(data) => data.prototype = obj_proto
            _ => ()
          }
        None => ()
      }
      // Patch Number.prototype.[[Prototype]]
      match env.bindings.get("[[NumberPrototype]]") {
        Some(np) =>
          match np.value {
            Object(data) => data.prototype = obj_proto
            _ => ()
          }
        None => ()
      }
      // Patch Function.prototype.[[Prototype]]
      match env.bindings.get("[[FunctionPrototype]]") {
        Some(fp) =>
          match fp.value {
            Object(data) => data.prototype = obj_proto
            _ => ()
          }
        None => ()
      }
      // Patch Error.prototype.[[Prototype]] = Object.prototype
      match error_proto {
        Object(data) => data.prototype = obj_proto
        _ => ()
      }
    }
    None => ()
  }
  // Patch constructor [[Prototype]] to Function.prototype
  match env.bindings.get("[[FunctionPrototype]]") {
    Some(fp_binding) => {
      let func_proto = fp_binding.value
      let ctor_names = [
        "Boolean", "String", "Number", "Error", "TypeError", "ReferenceError", "SyntaxError",
        "RangeError", "URIError", "EvalError", "AggregateError", "Array", "Object",
        "Function",
      ]
      for name in ctor_names {
        match env.bindings.get(name) {
          Some(b) =>
            match b.value {
              Object(data) => data.prototype = func_proto
              _ => ()
            }
          None => ()
        }
      }
    }
    None => ()
  }

  // Patch NativeError constructors [[Prototype]] to Error (not Function.prototype)
  match env.bindings.get("Error") {
    Some(err_binding) => {
      let error_ctor = err_binding.value
      let native_errors = [
        "TypeError", "ReferenceError", "SyntaxError", "RangeError", "URIError", "EvalError",
        "AggregateError",
      ]
      for name in native_errors {
        match env.bindings.get(name) {
          Some(b) =>
            match b.value {
              Object(data) => data.prototype = error_ctor
              _ => ()
            }
          None => ()
        }
      }
    }
    None => ()
  }

  // Symbol constructor and well-known symbols (must be before Math for Symbol.toStringTag)
  setup_symbol_builtins(env)
  // Patch Symbol.prototype.[[Prototype]] = Object.prototype
  match env.bindings.get("[[ObjectPrototype]]") {
    Some(binding) => {
      let obj_proto = binding.value
      match env.bindings.get("[[SymbolPrototype]]") {
        Some(sp) =>
          match sp.value {
            Object(data) => data.prototype = obj_proto
            _ => ()
          }
        None => ()
      }
    }
    None => ()
  }

  // Math object
  setup_math_builtins(env)

  // JSON object
  setup_json_builtins(env)

  // RegExp constructor
  env.def_builtin(
    "RegExp",
    Object({
      properties: { "name": String_("RegExp"), "length": Number(2.0) },
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable("RegExp", fn(args) raise {
          let pattern = if args.length() > 0 {
            match args[0] {
              Object(data) =>
                if data.class_name == "RegExp" {
                  match data.properties.get("source") {
                    Some(String_(s)) => s
                    _ => args[0].to_string()
                  }
                } else {
                  args[0].to_string()
                }
              Undefined => ""
              _ => args[0].to_string()
            }
          } else {
            ""
          }
          let flags = if args.length() > 1 {
            match args[1] {
              Undefined => ""
              _ => args[1].to_string()
            }
          } else {
            ""
          }
          make_regexp_object(pattern, flags)
        }),
      ),
      class_name: "Function",
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
      extensible: true,
    }),
  )

  // Set up RegExp.prototype and store in regexp_prototype_ref
  match env.bindings.get("[[ObjectPrototype]]") {
    Some(obj_proto_binding) => {
      let obj_proto = obj_proto_binding.value
      let regexp_proto_props : Map[String, Value] = {}
      regexp_proto_props["constructor"] = match env.bindings.get("RegExp") {
        Some(b) => b.value
        None => Undefined
      }
      // Add RegExp.prototype methods
      // test() and exec() are placed on each instance by make_regexp_object
      // Here we add them to prototype so typeof checks work
      regexp_proto_props["test"] = make_method_func("test", 1, fn(
        this_val,
        args,
      ) raise {
        match this_val {
          Object(data) => {
            if data.class_name != "RegExp" {
              raise @errors.TypeError(
                message="Method RegExp.prototype.test called on incompatible receiver",
              )
            }
            let str = if args.length() > 0 { to_js_string(args[0]) } else { "" }
            let (pat, fl) = extract_regexp_source_flags(this_val)
            let has_global = fl.contains("g")
            let has_sticky = fl.contains("y")
            let start = if has_sticky || has_global {
              match data.properties.get("lastIndex") {
                Some(li) => to_int32(to_number(li))
                _ => 0
              }
            } else {
              0
            }
            let result = regex_search(pat, fl, str, start_pos=start) catch {
              _ => None
            }
            match result {
              Some(m) => {
                if has_sticky || has_global {
                  data.properties["lastIndex"] = Number(m.end_.to_double())
                }
                Bool(true)
              }
              None => {
                if has_sticky || has_global {
                  data.properties["lastIndex"] = Number(0.0)
                }
                Bool(false)
              }
            }
          }
          _ =>
            raise @errors.TypeError(
              message="Method RegExp.prototype.test called on incompatible receiver",
            )
        }
      })
      regexp_proto_props["exec"] = make_method_func("exec", 1, fn(
        this_val,
        args,
      ) raise {
        match this_val {
          Object(data) => {
            if data.class_name != "RegExp" {
              raise @errors.TypeError(
                message="Method RegExp.prototype.exec called on incompatible receiver",
              )
            }
            let str = if args.length() > 0 { to_js_string(args[0]) } else { "" }
            let (pat, fl) = extract_regexp_source_flags(this_val)
            let has_global = fl.contains("g")
            let has_sticky = fl.contains("y")
            let start = if has_sticky || has_global {
              match data.properties.get("lastIndex") {
                Some(li) => to_int32(to_number(li))
                _ => 0
              }
            } else {
              0
            }
            let result = regex_search(pat, fl, str, start_pos=start) catch {
              _ => None
            }
            match result {
              Some(m) => {
                if has_sticky || has_global {
                  data.properties["lastIndex"] = Number(m.end_.to_double())
                }
                make_regex_match_array(m, str)
              }
              None => {
                if has_sticky || has_global {
                  data.properties["lastIndex"] = Number(0.0)
                }
                Null
              }
            }
          }
          _ =>
            raise @errors.TypeError(
              message="Method RegExp.prototype.exec called on incompatible receiver",
            )
        }
      })
      // RegExp.prototype.compile (Annex B)
      regexp_proto_props["compile"] = make_method_func("compile", 2, fn(
        this_val,
        args,
      ) raise {
        match this_val {
          Object(data) => {
            if data.class_name != "RegExp" {
              raise @errors.TypeError(
                message="Method RegExp.prototype.compile called on incompatible receiver",
              )
            }
            let pattern_arg = if args.length() > 0 {
              args[0]
            } else {
              Undefined
            }
            let flags_arg = if args.length() > 1 { args[1] } else { Undefined }
            let (source, flags) : (String, String) = match pattern_arg {
              Object(re_data) =>
                if re_data.class_name == "RegExp" {
                  // If pattern is a RegExp and flags is not undefined, throw TypeError
                  if !(flags_arg is Undefined) {
                    raise @errors.TypeError(
                      message="Cannot supply flags when constructing one RegExp from another",
                    )
                  }
                  let s = match re_data.properties.get("source") {
                    Some(String_(s)) => s
                    _ => ""
                  }
                  let f = match re_data.properties.get("flags") {
                    Some(String_(f)) => f
                    _ => ""
                  }
                  (s, f)
                } else {
                  let s = to_js_string(pattern_arg)
                  let f = if flags_arg is Undefined {
                    ""
                  } else {
                    to_js_string(flags_arg)
                  }
                  (s, f)
                }
              Undefined => {
                let f = if flags_arg is Undefined {
                  ""
                } else {
                  to_js_string(flags_arg)
                }
                ("(?:)", f)
              }
              _ => {
                let s = to_js_string(pattern_arg)
                let f = if flags_arg is Undefined {
                  ""
                } else {
                  to_js_string(flags_arg)
                }
                (s, f)
              }
            }
            // Update the RegExp object in place
            data.properties["source"] = String_(source)
            data.properties["flags"] = String_(flags)
            data.properties["lastIndex"] = Number(0.0)
            // Update flag booleans
            data.properties["global"] = Bool(flags.contains("g"))
            data.properties["ignoreCase"] = Bool(flags.contains("i"))
            data.properties["multiline"] = Bool(flags.contains("m"))
            data.properties["dotAll"] = Bool(flags.contains("s"))
            data.properties["unicode"] = Bool(flags.contains("u"))
            data.properties["sticky"] = Bool(flags.contains("y"))
            this_val
          }
          _ =>
            raise @errors.TypeError(
              message="Method RegExp.prototype.compile called on incompatible receiver",
            )
        }
      })
      regexp_proto_props["toString"] = make_method_func("toString", 0, fn(
        this_val,
        _args,
      ) {
        match this_val {
          Object(data) => {
            let source = match data.properties.get("source") {
              Some(String_(s)) => s
              _ => ""
            }
            let flags = match data.properties.get("flags") {
              Some(String_(f)) => f
              _ => ""
            }
            String_("/" + source + "/" + flags)
          }
          _ => String_("/(?:)/")
        }
      })
      // Add flag getter accessors to RegExp.prototype per spec
      let regexp_proto_descs : Map[String, PropDescriptor] = {}
      // Helper: create a getter that reads a flag from the regexp's flags string
      fn make_flag_getter(flag_char : String) -> Value {
        make_method_func("get " + flag_char, 0, fn(this_val, _args) raise {
          match this_val {
            Object(data) => {
              if data.class_name != "RegExp" {
                // Per spec, RegExp.prototype itself returns undefined for flag getters
                if data.class_name == "Object" {
                  return Undefined
                }
                raise @errors.TypeError(
                  message="Method get RegExp.prototype." +
                    flag_char +
                    " called on incompatible receiver",
                )
              }
              let flags_str = match data.properties.get("flags") {
                Some(String_(f)) => f
                _ => ""
              }
              match flag_char {
                "global" => Bool(flags_str.contains("g"))
                "ignoreCase" => Bool(flags_str.contains("i"))
                "multiline" => Bool(flags_str.contains("m"))
                "dotAll" => Bool(flags_str.contains("s"))
                "unicode" => Bool(flags_str.contains("u"))
                "sticky" => Bool(flags_str.contains("y"))
                "unicodeSets" => Bool(flags_str.contains("v"))
                "hasIndices" => Bool(flags_str.contains("d"))
                _ => Undefined
              }
            }
            _ =>
              raise @errors.TypeError(
                message="Method get RegExp.prototype." +
                  flag_char +
                  " called on incompatible receiver",
              )
          }
        })
      }
      let flag_names = [
        "global", "ignoreCase", "multiline", "dotAll", "unicode", "sticky", "unicodeSets",
        "hasIndices",
      ]
      for flag_name in flag_names {
        let getter = make_flag_getter(flag_name)
        regexp_proto_props[flag_name] = Undefined
        regexp_proto_descs[flag_name] = {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: Some(getter),
          setter: None,
        }
      }
      // flags getter - computes flags string from individual flag getters
      let flags_getter = make_method_func("get flags", 0, fn(
        this_val,
        _args,
      ) raise {
        match this_val {
          Object(data) =>
            // For actual RegExp instances, read the stored flags
            match data.properties.get("flags") {
              Some(String_(f)) => String_(f)
              _ => {
                // Per spec, compute from individual flag getters
                fn is_flag_set(
                  props : Map[String, Value],
                  name : String,
                ) -> Bool {
                  match props.get(name) {
                    Some(Bool(true)) => true
                    _ => false
                  }
                }
                let p = data.properties
                let mut result = ""
                if is_flag_set(p, "hasIndices") {
                  result = result + "d"
                }
                if is_flag_set(p, "global") {
                  result = result + "g"
                }
                if is_flag_set(p, "ignoreCase") {
                  result = result + "i"
                }
                if is_flag_set(p, "multiline") {
                  result = result + "m"
                }
                if is_flag_set(p, "dotAll") {
                  result = result + "s"
                }
                if is_flag_set(p, "unicode") {
                  result = result + "u"
                }
                if is_flag_set(p, "unicodeSets") {
                  result = result + "v"
                }
                if is_flag_set(p, "sticky") {
                  result = result + "y"
                }
                String_(result)
              }
            }
          _ =>
            raise @errors.TypeError(
              message="Method get RegExp.prototype.flags called on incompatible receiver",
            )
        }
      })
      regexp_proto_props["flags"] = Undefined
      regexp_proto_descs["flags"] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: Some(flags_getter),
        setter: None,
      }
      // source getter
      let source_getter = make_method_func("get source", 0, fn(
        this_val,
        _args,
      ) raise {
        match this_val {
          Object(data) => {
            if data.class_name != "RegExp" {
              if data.class_name == "Object" {
                return String_("(?:)")
              }
              raise @errors.TypeError(
                message="Method get RegExp.prototype.source called on incompatible receiver",
              )
            }
            match data.properties.get("source") {
              Some(String_(s)) => String_(s)
              _ => String_("(?:)")
            }
          }
          _ =>
            raise @errors.TypeError(
              message="Method get RegExp.prototype.source called on incompatible receiver",
            )
        }
      })
      regexp_proto_props["source"] = Undefined
      regexp_proto_descs["source"] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: Some(source_getter),
        setter: None,
      }
      let re_method_desc2 : PropDescriptor = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      regexp_proto_descs["constructor"] = re_method_desc2
      regexp_proto_descs["exec"] = re_method_desc2
      regexp_proto_descs["test"] = re_method_desc2
      regexp_proto_descs["toString"] = re_method_desc2
      regexp_proto_descs["compile"] = re_method_desc2
      // Install well-known symbol methods on RegExp.prototype (not on instances)
      let regexp_sym_props : Map[Int, Value] = {}
      let regexp_sym_descs : Map[Int, PropDescriptor] = {}
      let sym_method_desc : PropDescriptor = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      // [Symbol.match]
      let match_sym = get_match_symbol()
      regexp_sym_props[match_sym.id] = make_method_func("[Symbol.match]", 1, fn(
        this_val,
        args,
      ) {
        let str = if args.length() > 0 { args[0].to_string() } else { "" }
        let (pat, fl) = extract_regexp_source_flags(this_val)
        string_match_regex(str, pat, fl)
      })
      regexp_sym_descs[match_sym.id] = sym_method_desc
      // [Symbol.matchAll]
      let match_all_sym = get_matchall_symbol()
      regexp_sym_props[match_all_sym.id] = make_method_func(
        "[Symbol.matchAll]",
        1,
        fn(this_val, args) {
          let str = if args.length() > 0 { args[0].to_string() } else { "" }
          let (pat, fl) = extract_regexp_source_flags(this_val)
          let flags = if fl.contains("g") { fl } else { fl + "g" }
          let matches = regex_search_all(pat, flags, str) catch { _ => [] }
          let input_chars = str.to_array()
          let index_ref : Ref[Int] = { val: 0 }
          let next_method = Object({
            properties: {},
            symbol_properties: {},
            prototype: Null,
            callable: Some(
              NativeCallable("next", fn(_args) {
                let idx = index_ref.val
                if idx < matches.length() {
                  let m = matches[idx]
                  index_ref.val = idx + 1
                  let elements : Array[Value] = []
                  elements.push(
                    String_(substring(input_chars, m.start, m.end_)),
                  )
                  for cap in m.captures {
                    match cap {
                      Some(c) => elements.push(String_(c))
                      None => elements.push(Undefined)
                    }
                  }
                  let match_array = Array({ elements, })
                  let result_props : Map[String, Value] = {}
                  result_props["value"] = match_array
                  result_props["done"] = Bool(false)
                  Object({
                    properties: result_props,
                    symbol_properties: {},
                    prototype: Null,
                    callable: None,
                    class_name: "Object",
                    descriptors: {},
                    symbol_descriptors: {},
                    extensible: true,
                  })
                } else {
                  let result_props : Map[String, Value] = {}
                  result_props["value"] = Undefined
                  result_props["done"] = Bool(true)
                  Object({
                    properties: result_props,
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
          let iter_props : Map[String, Value] = {}
          iter_props["next"] = next_method
          Object({
            properties: iter_props,
            symbol_properties: {},
            prototype: get_regexp_string_iterator_proto(),
            callable: None,
            class_name: "RegExp String Iterator",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
        },
      )
      regexp_sym_descs[match_all_sym.id] = sym_method_desc
      // [Symbol.search]
      let search_sym = get_search_symbol()
      regexp_sym_props[search_sym.id] = make_method_func("[Symbol.search]", 1, fn(
        this_val,
        args,
      ) {
        let str = if args.length() > 0 { args[0].to_string() } else { "" }
        let (pat, fl) = extract_regexp_source_flags(this_val)
        string_search_regex(str, pat, fl)
      })
      regexp_sym_descs[search_sym.id] = sym_method_desc
      // [Symbol.replace]
      let replace_sym = get_replace_symbol()
      regexp_sym_props[replace_sym.id] = make_method_func(
        "[Symbol.replace]",
        2,
        fn(this_val, args) {
          let str = if args.length() > 0 { args[0].to_string() } else { "" }
          let replacement = if args.length() > 1 {
            args[1].to_string()
          } else {
            "undefined"
          }
          let (pat, fl) = extract_regexp_source_flags(this_val)
          string_replace_regex(str, pat, fl, replacement)
        },
      )
      regexp_sym_descs[replace_sym.id] = sym_method_desc
      // [Symbol.split]
      let split_sym = get_split_symbol()
      regexp_sym_props[split_sym.id] = make_method_func("[Symbol.split]", 0, fn(
        this_val,
        args,
      ) raise {
        let str = if args.length() > 0 { args[0].to_string() } else { "" }
        let limit : Int64 = if args.length() > 1 {
          match args[1] {
            Undefined => 4294967295L
            _ => {
              let n = to_int32(to_number(args[1]))
              if n < 0 {
                n.to_int64() + 4294967296L
              } else {
                n.to_int64()
              }
            }
          }
        } else {
          4294967295L
        }
        if limit == 0L {
          return Array({ elements: [] })
        }
        let (pat, fl) = extract_regexp_source_flags(this_val)
        let input_chars = str.to_array()
        let slen = str.length()
        if slen == 0 {
          let m = regex_search(pat, fl, str) catch { _ => None }
          return match m {
            Some(_) => Array({ elements: [] })
            None => Array({ elements: [String_(str)] })
          }
        }
        let results : Array[Value] = []
        let mut last_end = 0
        let mut pos = 0
        while pos < slen {
          let m = regex_search(pat, fl, str, start_pos=pos) catch { _ => None }
          match m {
            None => break
            Some(match_data) => {
              if match_data.end_ == last_end && match_data.start == pos {
                pos = pos + 1
                continue
              }
              let buf = StringBuilder::new()
              for i = last_end; i < match_data.start; i = i + 1 {
                buf.write_char(input_chars[i])
              }
              results.push(String_(buf.to_string()))
              if results.length().to_int64() >= limit {
                return Array({ elements: results })
              }
              for cap in match_data.captures {
                match cap {
                  Some(c) => results.push(String_(c))
                  None => results.push(Undefined)
                }
                if results.length().to_int64() >= limit {
                  return Array({ elements: results })
                }
              }
              last_end = match_data.end_
              pos = if match_data.end_ == match_data.start {
                match_data.end_ + 1
              } else {
                match_data.end_
              }
            }
          }
        }
        let buf = StringBuilder::new()
        for i = last_end; i < slen; i = i + 1 {
          buf.write_char(input_chars[i])
        }
        results.push(String_(buf.to_string()))
        Array({ elements: results })
      })
      regexp_sym_descs[split_sym.id] = sym_method_desc
      let regexp_proto : Value = Object({
        properties: regexp_proto_props,
        symbol_properties: regexp_sym_props,
        prototype: obj_proto,
        callable: None,
        class_name: "Object",
        descriptors: regexp_proto_descs,
        symbol_descriptors: regexp_sym_descs,
        extensible: true,
      })
      regexp_prototype_ref.val = Some(regexp_proto)
      // Set RegExp.prototype on the constructor
      match env.bindings.get("RegExp") {
        Some(b) =>
          match b.value {
            Object(ctor_data) =>
              ctor_data.properties["prototype"] = regexp_proto
            _ => ()
          }
        None => ()
      }
    }
    None => ()
  }

  // Set up iterator protocol on Array and String prototypes
  // Use try/catch since setup_iterator_protocol can raise errors
  setup_iterator_protocol(env) catch {
    _ => () // Ignore errors during initialization
  }

  // Set up Map and Set collections
  setup_map_set_builtins(env)

  // Set up Promise constructor and prototype
  setup_promise(env)

  // Set up Date constructor and prototype
  setup_date_builtins(env)

  // Set up timer APIs (setTimeout, clearTimeout, setInterval, clearInterval)
  setup_timers(env)

  // Set up Proxy constructor and Proxy.revocable
  setup_proxy_builtins(env)

  // Set up Reflect global object
  setup_reflect_builtins(env)

  // Set up ArrayBuffer, TypedArray, and DataView
  setup_arraybuffer_builtins(env)
  setup_typedarray_builtins(env)
  setup_dataview_builtins(env)

  // Set up WeakMap and WeakSet
  setup_weakmap_set_builtins(env)

  // Final prototype chain patching for constructors registered after initial patch
  match env.bindings.get("[[FunctionPrototype]]") {
    Some(fp_binding) => {
      let func_proto = fp_binding.value
      let late_ctors = [
        "Map", "Set", "WeakMap", "WeakSet", "Date", "RegExp", "Promise", "Proxy",
        "ArrayBuffer", "DataView",
      ]
      for name in late_ctors {
        match env.bindings.get(name) {
          Some(b) =>
            match b.value {
              Object(data) =>
                if data.prototype is Null {
                  data.prototype = func_proto
                }
              _ => ()
            }
          None => ()
        }
      }
    }
    None => ()
  }
  // Patch Map.prototype, Set.prototype etc [[Prototype]] to Object.prototype
  match env.bindings.get("[[ObjectPrototype]]") {
    Some(binding) => {
      let obj_proto = binding.value
      let ctor_names = [
        "Map", "Set", "WeakMap", "WeakSet", "Date", "RegExp", "Promise",
      ]
      for cname in ctor_names {
        match env.bindings.get(cname) {
          Some(cb) =>
            match cb.value {
              Object(ctor_data) =>
                // Get prototype from constructor's "prototype" property
                match ctor_data.properties.get("prototype") {
                  Some(Object(proto_data)) =>
                    if proto_data.prototype is Null {
                      proto_data.prototype = obj_proto
                    }
                  _ => ()
                }
              _ => ()
            }
          None => ()
        }
      }
    }
    None => ()
  }

  // Add Symbol.species getter to built-in constructors (Array, RegExp, Map, Set)
  // Per spec: static get [Symbol.species]() { return this; }
  let species_getter = make_method_func("get [Symbol.species]", 0, fn(
    this_val,
    _args,
  ) {
    this_val
  })
  let species_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(species_getter),
    setter: None,
  }
  let ctors_to_add_species = ["Array", "RegExp", "Map", "Set"]
  for ctor_name in ctors_to_add_species {
    let ctor_val = env.get(ctor_name) catch { _ => Undefined }
    match ctor_val {
      Object(ctor_data) => {
        let sp_sym = get_species_symbol()
        ctor_data.symbol_properties[sp_sym.id] = Undefined
        ctor_data.symbol_descriptors[sp_sym.id] = species_desc
      }
      _ => ()
    }
  }

  // Add Function.prototype[Symbol.hasInstance]
  let has_instance_sym = get_hasinstance_symbol()
  let has_instance_fn = make_interp_method_func("[Symbol.hasInstance]", 1, fn(
    interp,
    this_val,
    args,
  ) raise {
    // OrdinaryHasInstance(C, O)
    let o = if args.length() > 0 { args[0] } else { Undefined }
    if !is_callable(this_val) {
      return Bool(false)
    }
    // Get C.prototype
    let loc = @token.Loc::default()
    let p = interp.get_property(this_val, "prototype", loc)
    match p {
      Object(_) => instanceof_prototype_chain(o, p, interp.global)
      _ => Bool(false)
    }
  })
  match env.bindings.get("[[FunctionPrototype]]") {
    Some(binding) =>
      match binding.value {
        Object(fp_data) => {
          fp_data.symbol_properties[has_instance_sym.id] = has_instance_fn
          fp_data.symbol_descriptors[has_instance_sym.id] = {
            writable: false,
            enumerable: false,
            configurable: false,
            getter: None,
            setter: None,
          }
        }
        _ => ()
      }
    None => ()
  }
}

///|
fn setup_symbol_builtins(env : Environment) -> Unit {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  // Descriptor for well-known symbol properties: { writable: false, enumerable: false, configurable: false }
  let wks_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
  }
  // Descriptor for methods: { writable: true, enumerable: false, configurable: true }
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  // Create well-known symbols
  let iterator_sym = new_symbol(Some("Symbol.iterator"))
  // Store globally for iterator protocol support
  well_known_iterator_sym.val = Some(iterator_sym)
  let to_primitive_sym = new_symbol(Some("Symbol.toPrimitive"))
  well_known_toprimitive_sym.val = Some(to_primitive_sym)
  let to_string_tag_sym = new_symbol(Some("Symbol.toStringTag"))
  well_known_tostringtag_sym.val = Some(to_string_tag_sym)
  let has_instance_sym = new_symbol(Some("Symbol.hasInstance"))
  // Store globally for instanceof operator support
  well_known_hasinstance_sym.val = Some(has_instance_sym)
  let is_concat_spreadable_sym = new_symbol(Some("Symbol.isConcatSpreadable"))
  well_known_isconcatspreadable_sym.val = Some(is_concat_spreadable_sym)
  let species_sym = new_symbol(Some("Symbol.species"))
  well_known_species_sym.val = Some(species_sym)
  let match_sym = new_symbol(Some("Symbol.match"))
  well_known_match_sym.val = Some(match_sym)
  let match_all_sym = new_symbol(Some("Symbol.matchAll"))
  well_known_matchall_sym.val = Some(match_all_sym)
  let replace_sym = new_symbol(Some("Symbol.replace"))
  well_known_replace_sym.val = Some(replace_sym)
  let search_sym = new_symbol(Some("Symbol.search"))
  well_known_search_sym.val = Some(search_sym)
  let split_sym = new_symbol(Some("Symbol.split"))
  well_known_split_sym.val = Some(split_sym)
  let unscopables_sym = new_symbol(Some("Symbol.unscopables"))
  well_known_unscopables_sym.val = Some(unscopables_sym)
  let async_iterator_sym = new_symbol(Some("Symbol.asyncIterator"))
  well_known_async_iterator_sym.val = Some(async_iterator_sym)

  // Symbol prototype
  let symbol_proto_props : Map[String, Value] = {}
  let symbol_proto_descs : Map[String, PropDescriptor] = {}
  symbol_proto_props["toString"] = make_method_func("toString", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Symbol(sym) =>
        match sym.description {
          Some(desc) => String_("Symbol(\{desc})")
          None => String_("Symbol()")
        }
      Object(data) =>
        // Support Symbol wrapper objects (e.g. Object(sym).toString())
        match data.properties.get("[[SymbolData]]") {
          Some(Symbol(sym)) =>
            match sym.description {
              Some(desc) => String_("Symbol(\{desc})")
              None => String_("Symbol()")
            }
          _ =>
            raise @errors.TypeError(
              message="Symbol.prototype.toString requires a Symbol",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Symbol.prototype.toString requires a Symbol",
        )
    }
  })
  symbol_proto_descs["toString"] = method_desc
  symbol_proto_props["valueOf"] = make_method_func("valueOf", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Symbol(_) => this_val
      Object(data) =>
        // Support Symbol wrapper objects
        match data.properties.get("[[SymbolData]]") {
          Some(sym) => sym
          _ =>
            raise @errors.TypeError(
              message="Symbol.prototype.valueOf requires a Symbol",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Symbol.prototype.valueOf requires a Symbol",
        )
    }
  })
  symbol_proto_descs["valueOf"] = method_desc
  // Symbol.prototype.description - getter per ES spec
  // Stored as a getter descriptor (not a plain value)
  let description_getter = make_method_func("get description", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Symbol(sym) =>
        match sym.description {
          Some(desc) => String_(desc)
          None => Undefined
        }
      Object(data) =>
        match data.properties.get("[[SymbolData]]") {
          Some(Symbol(sym)) =>
            match sym.description {
              Some(desc) => String_(desc)
              None => Undefined
            }
          _ =>
            raise @errors.TypeError(
              message="Symbol.prototype.description requires a Symbol",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Symbol.prototype.description requires a Symbol",
        )
    }
  })
  // Set a placeholder in properties so hasOwnProperty returns true
  symbol_proto_props["description"] = Undefined
  symbol_proto_descs["description"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(description_getter),
    setter: None,
  }

  // Symbol.prototype[@@toPrimitive](hint)
  let symbol_proto_sym_props : Map[Int, Value] = {}
  let symbol_proto_sym_descs : Map[Int, PropDescriptor] = {}
  let toprimitive_method = make_method_func("[Symbol.toPrimitive]", 1, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Symbol(_) => this_val
      Object(data) =>
        match data.properties.get("[[SymbolData]]") {
          Some(sym) => sym
          _ =>
            raise @errors.TypeError(
              message="Symbol[Symbol.toPrimitive] requires a Symbol",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Symbol[Symbol.toPrimitive] requires a Symbol",
        )
    }
  })
  symbol_proto_sym_props[to_primitive_sym.id] = toprimitive_method
  symbol_proto_sym_descs[to_primitive_sym.id] = {
    ..wks_desc,
    configurable: true,
  }

  // Symbol.prototype[@@toStringTag] = "Symbol"
  symbol_proto_sym_props[to_string_tag_sym.id] = String_("Symbol")
  symbol_proto_sym_descs[to_string_tag_sym.id] = nf_desc

  let symbol_proto : Value = Object({
    properties: symbol_proto_props,
    symbol_properties: symbol_proto_sym_props,
    prototype: get_obj_proto(),
    callable: None,
    class_name: "Symbol",
    descriptors: symbol_proto_descs,
    symbol_descriptors: symbol_proto_sym_descs,
    extensible: true,
  })

  // Symbol constructor properties
  let symbol_props : Map[String, Value] = {}
  let symbol_descs : Map[String, PropDescriptor] = {}
  symbol_props["prototype"] = symbol_proto
  symbol_descs["prototype"] = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
  }

  // Well-known symbols as static properties (all { writable: false, enumerable: false, configurable: false })
  symbol_props["iterator"] = Symbol(iterator_sym)
  symbol_descs["iterator"] = { ..wks_desc }
  symbol_props["toPrimitive"] = Symbol(to_primitive_sym)
  symbol_descs["toPrimitive"] = { ..wks_desc }
  symbol_props["toStringTag"] = Symbol(to_string_tag_sym)
  symbol_descs["toStringTag"] = { ..wks_desc }
  symbol_props["hasInstance"] = Symbol(has_instance_sym)
  symbol_descs["hasInstance"] = { ..wks_desc }
  symbol_props["isConcatSpreadable"] = Symbol(is_concat_spreadable_sym)
  symbol_descs["isConcatSpreadable"] = { ..wks_desc }
  symbol_props["species"] = Symbol(species_sym)
  symbol_descs["species"] = { ..wks_desc }
  symbol_props["match"] = Symbol(match_sym)
  symbol_descs["match"] = { ..wks_desc }
  symbol_props["matchAll"] = Symbol(match_all_sym)
  symbol_descs["matchAll"] = { ..wks_desc }
  symbol_props["replace"] = Symbol(replace_sym)
  symbol_descs["replace"] = { ..wks_desc }
  symbol_props["search"] = Symbol(search_sym)
  symbol_descs["search"] = { ..wks_desc }
  symbol_props["split"] = Symbol(split_sym)
  symbol_descs["split"] = { ..wks_desc }
  symbol_props["unscopables"] = Symbol(unscopables_sym)
  symbol_descs["unscopables"] = { ..wks_desc }
  symbol_props["asyncIterator"] = Symbol(async_iterator_sym)
  symbol_descs["asyncIterator"] = { ..wks_desc }

  // Symbol.for(key) - returns symbol from global registry
  // Spec: 1. Let stringKey be ? ToString(key).  (throws TypeError for symbols)
  symbol_props["for"] = make_static_func_with_length("for", 1, fn(args) raise {
    let arg = if args.length() > 0 { args[0] } else { Undefined }
    let key : String = match arg {
      Symbol(_) =>
        raise @errors.TypeError(
          message="Cannot convert a Symbol value to a string",
        )
      _ => arg.to_string()
    }
    match global_symbol_registry.get(key) {
      Some(sym) => Symbol(sym)
      None => {
        let sym = new_symbol(Some(key))
        global_symbol_registry[key] = sym
        symbol_registry_reverse[sym.id] = key // O(1) reverse lookup
        Symbol(sym)
      }
    }
  })
  symbol_descs["for"] = method_desc

  // Symbol.keyFor(sym) - returns key for symbol in global registry (O(1) via reverse lookup)
  symbol_props["keyFor"] = make_static_func_with_length("keyFor", 1, fn(
    args,
  ) raise {
    let sym = if args.length() > 0 { args[0] } else { Undefined }
    match sym {
      Symbol(sym_data) =>
        match symbol_registry_reverse.get(sym_data.id) {
          Some(key) => String_(key)
          None => Undefined
        }
      _ => raise @errors.TypeError(message="Symbol.keyFor requires a symbol")
    }
  })
  symbol_descs["keyFor"] = method_desc

  // Symbol constructor - cannot be called with new, only as function
  symbol_props["name"] = String_("Symbol")
  symbol_descs["name"] = nf_desc
  symbol_props["length"] = Number(0.0)
  symbol_descs["length"] = nf_desc
  env.def_builtin(
    "Symbol",
    Object({
      properties: symbol_props,
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NonConstructableCallable("Symbol", fn(args) raise {
          let description : String? = if args.length() > 0 {
            match args[0] {
              Undefined => None
              Symbol(_) =>
                raise @errors.TypeError(
                  message="Cannot convert a Symbol value to a string",
                )
              _ => Some(args[0].to_string())
            }
          } else {
            None
          }
          Symbol(new_symbol(description))
        }),
      ),
      class_name: "Function",
      descriptors: symbol_descs,
      symbol_descriptors: {},
      extensible: true,
    }),
  )
  env.def_builtin("[[SymbolPrototype]]", symbol_proto)
  symbol_prototype_ref.val = Some(symbol_proto)
  // Set Symbol.prototype.constructor = Symbol
  match symbol_proto {
    Object(data) => {
      let ctor = env.get("Symbol") catch { _ => Undefined }
      data.properties["constructor"] = ctor
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
}

///|
/// Set up iterator protocol on Array and String prototypes
fn setup_iterator_protocol(env : Environment) -> Unit raise Error {
  let iterator_sym = get_iterator_symbol()

  // Helper to create an array iterator object
  // Array iterator returns { value, done } for each element
  fn make_array_iterator(arr : ArrayData) -> Value {
    // Create mutable index state using a Ref
    let index_ref : Ref[Int] = { val: 0 }

    // Create the iterator next method
    let next_method = Object({
      properties: {},
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable("next", fn(_args) {
          let idx = index_ref.val
          if idx < arr.elements.length() {
            let value = arr.elements[idx]
            index_ref.val = idx + 1
            // Return { value: element, done: false }
            let result_props : Map[String, Value] = {}
            result_props["value"] = value
            result_props["done"] = Bool(false)
            Object({
              properties: result_props,
              symbol_properties: {},
              prototype: Null,
              callable: None,
              class_name: "Object",
              descriptors: {},
              symbol_descriptors: {},
              extensible: true,
            })
          } else {
            // Return { value: undefined, done: true }
            let result_props : Map[String, Value] = {}
            result_props["value"] = Undefined
            result_props["done"] = Bool(true)
            Object({
              properties: result_props,
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

    // Create the iterator object
    let iter_props : Map[String, Value] = {}
    iter_props["next"] = next_method

    // Iterator should also have Symbol.iterator returning itself
    let iter_symbol_props : Map[Int, Value] = {}
    let tostringtag_sym = get_tostringtag_symbol()
    iter_symbol_props[tostringtag_sym.id] = String_("Array Iterator")
    let iter_symbol_descs : Map[Int, PropDescriptor] = {}
    iter_symbol_descs[tostringtag_sym.id] = {
      writable: false,
      enumerable: false,
      configurable: true,
      getter: None,
      setter: None,
    }
    let iter_obj = Object({
      properties: iter_props,
      symbol_properties: iter_symbol_props,
      prototype: Null,
      callable: None,
      class_name: "Array Iterator",
      descriptors: {},
      symbol_descriptors: iter_symbol_descs,
      extensible: true,
    })

    // Add [Symbol.iterator] that returns the iterator itself
    match iter_obj {
      Object(data) =>
        data.symbol_properties[iterator_sym.id] = make_method_func(
          "[Symbol.iterator]",
          0,
          fn(this_val, _args) { this_val },
        )
      _ => ()
    }
    iter_obj
  }

  // Helper to create an array-like iterator for non-array objects
  fn make_array_like_iterator(val : Value) -> Value raise {
    let index_ref : Ref[Int] = { val: 0 }
    let len = to_array_like_length(val)

    let next_method = Object({
      properties: {},
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable("next", fn(_args) {
          let idx = index_ref.val
          if idx < len {
            let value = get_array_like_element(val, idx)
            index_ref.val = idx + 1
            let result_props : Map[String, Value] = {}
            result_props["value"] = value
            result_props["done"] = Bool(false)
            Object({
              properties: result_props,
              symbol_properties: {},
              prototype: Null,
              callable: None,
              class_name: "Object",
              descriptors: {},
              symbol_descriptors: {},
              extensible: true,
            })
          } else {
            let result_props : Map[String, Value] = {}
            result_props["value"] = Undefined
            result_props["done"] = Bool(true)
            Object({
              properties: result_props,
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

    let iter_props : Map[String, Value] = {}
    iter_props["next"] = next_method
    let iter_obj = Object({
      properties: iter_props,
      symbol_properties: {},
      prototype: Null,
      callable: None,
      class_name: "Array Iterator",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    })

    match iter_obj {
      Object(data) =>
        data.symbol_properties[iterator_sym.id] = make_method_func(
          "[Symbol.iterator]",
          0,
          fn(this_val, _args) { this_val },
        )
      _ => ()
    }
    iter_obj
  }

  // Get Array constructor and add Symbol.iterator to its prototype
  let array_val = env.get("Array")
  match array_val {
    Object(array_ctor) =>
      match array_ctor.properties.get("prototype") {
        Some(Object(proto_data)) => {
          // Add [Symbol.iterator] method that returns an array iterator
          proto_data.symbol_properties[iterator_sym.id] = make_method_func(
            "[Symbol.iterator]",
            0,
            fn(this_val, _args) raise {
              match this_val {
                Array(arr) => make_array_iterator(arr)
                _ => make_array_like_iterator(this_val)
              }
            },
          )

          // Also add values() method (alias for [Symbol.iterator])
          proto_data.properties["values"] = make_method_func("values", 0, fn(
            this_val,
            _args,
          ) raise {
            match this_val {
              Array(arr) => make_array_iterator(arr)
              _ => make_array_like_iterator(this_val)
            }
          })

          // Add keys() method that returns an iterator over indices
          proto_data.properties["keys"] = make_method_func("keys", 0, fn(
            this_val,
            _args,
          ) raise {
            let len = to_array_like_length(this_val)
            let index_ref : Ref[Int] = { val: 0 }
            let next_method = Object({
              properties: {},
              symbol_properties: {},
              prototype: Null,
              callable: Some(
                NativeCallable("next", fn(_args) {
                  let idx = index_ref.val
                  if idx < len {
                    index_ref.val = idx + 1
                    let result_props : Map[String, Value] = {}
                    result_props["value"] = Number(idx.to_double())
                    result_props["done"] = Bool(false)
                    Object({
                      properties: result_props,
                      symbol_properties: {},
                      prototype: Null,
                      callable: None,
                      class_name: "Object",
                      descriptors: {},
                      symbol_descriptors: {},
                      extensible: true,
                    })
                  } else {
                    let result_props : Map[String, Value] = {}
                    result_props["value"] = Undefined
                    result_props["done"] = Bool(true)
                    Object({
                      properties: result_props,
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
            let iter_props : Map[String, Value] = {}
            iter_props["next"] = next_method
            let iter_obj = Object({
              properties: iter_props,
              symbol_properties: {},
              prototype: Null,
              callable: None,
              class_name: "Array Iterator",
              descriptors: {},
              symbol_descriptors: {},
              extensible: true,
            })

            // Add [Symbol.iterator] to keys iterator
            match iter_obj {
              Object(data) =>
                data.symbol_properties[iterator_sym.id] = make_method_func(
                  "[Symbol.iterator]",
                  0,
                  fn(this_val, _args) { this_val },
                )
              _ => ()
            }
            iter_obj
          })

          // Add entries() method that returns an iterator over [index, value] pairs
          proto_data.properties["entries"] = make_method_func("entries", 0, fn(
            this_val,
            _args,
          ) raise {
            let the_val = this_val
            let len = to_array_like_length(the_val)
            let index_ref : Ref[Int] = { val: 0 }
            let next_method = Object({
              properties: {},
              symbol_properties: {},
              prototype: Null,
              callable: Some(
                NativeCallable("next", fn(_args) {
                  let idx = index_ref.val
                  if idx < len {
                    let value = get_array_like_element(the_val, idx)
                    index_ref.val = idx + 1
                    let result_props : Map[String, Value] = {}
                    result_props["value"] = Array({
                      elements: [Number(idx.to_double()), value],
                    })
                    result_props["done"] = Bool(false)
                    Object({
                      properties: result_props,
                      symbol_properties: {},
                      prototype: Null,
                      callable: None,
                      class_name: "Object",
                      descriptors: {},
                      symbol_descriptors: {},
                      extensible: true,
                    })
                  } else {
                    let result_props : Map[String, Value] = {}
                    result_props["value"] = Undefined
                    result_props["done"] = Bool(true)
                    Object({
                      properties: result_props,
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
            let iter_props : Map[String, Value] = {}
            iter_props["next"] = next_method
            let iter_obj = Object({
              properties: iter_props,
              symbol_properties: {},
              prototype: Null,
              callable: None,
              class_name: "Array Iterator",
              descriptors: {},
              symbol_descriptors: {},
              extensible: true,
            })

            // Add [Symbol.iterator] to entries iterator
            match iter_obj {
              Object(data) =>
                data.symbol_properties[iterator_sym.id] = make_method_func(
                  "[Symbol.iterator]",
                  0,
                  fn(this_val, _args) { this_val },
                )
              _ => ()
            }
            iter_obj
          })
          // Add @@unscopables to Array.prototype
          let unscopables_sym_data = match env.get("Symbol") {
            Object(s) =>
              match s.properties.get("unscopables") {
                Some(Symbol(sym)) => Some(sym)
                _ => None
              }
            _ => None
          }
          match unscopables_sym_data {
            Some(unscopables_sym2) => {
              let unscopable_props : Map[String, Value] = {}
              unscopable_props["at"] = Bool(true)
              unscopable_props["copyWithin"] = Bool(true)
              unscopable_props["entries"] = Bool(true)
              unscopable_props["fill"] = Bool(true)
              unscopable_props["find"] = Bool(true)
              unscopable_props["findIndex"] = Bool(true)
              unscopable_props["findLast"] = Bool(true)
              unscopable_props["findLastIndex"] = Bool(true)
              unscopable_props["flat"] = Bool(true)
              unscopable_props["flatMap"] = Bool(true)
              unscopable_props["includes"] = Bool(true)
              unscopable_props["keys"] = Bool(true)
              unscopable_props["toReversed"] = Bool(true)
              unscopable_props["toSorted"] = Bool(true)
              unscopable_props["toSpliced"] = Bool(true)
              unscopable_props["values"] = Bool(true)
              proto_data.symbol_properties[unscopables_sym2.id] = Object({
                properties: unscopable_props,
                symbol_properties: {},
                prototype: Null,
                callable: None,
                class_name: "Object",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
              proto_data.symbol_descriptors[unscopables_sym2.id] = {
                writable: false,
                enumerable: false,
                configurable: true,
                getter: None,
                setter: None,
              }
            }
            None => ()
          }
        }
        _ => ()
      }
    _ => ()
  }

  // Add [Symbol.iterator] for String prototype
  let string_proto = env.get("[[StringPrototype]]")
  match string_proto {
    Object(proto_data) => {
      let iter_method = make_method_func("[Symbol.iterator]", 0, fn(
        this_val,
        _args,
      ) {
        let s = this_val.to_string()
        make_string_iterator_value(s)
      })
      proto_data.symbol_properties[iterator_sym.id] = iter_method
      let iter_method_desc : PropDescriptor = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      proto_data.symbol_descriptors[iterator_sym.id] = iter_method_desc
    }
    _ => ()
  }
}

///|
fn setup_math_builtins(env : Environment) -> Unit {
  let math_props : Map[String, Value] = {}
  math_props["PI"] = Number(3.141592653589793)
  math_props["E"] = Number(2.718281828459045)
  math_props["LN2"] = Number(0.6931471805599453)
  math_props["LN10"] = Number(2.302585092994046)
  math_props["LOG2E"] = Number(1.4426950408889634)
  math_props["LOG10E"] = Number(0.4342944819032518)
  math_props["SQRT2"] = Number(1.4142135623730951)
  math_props["SQRT1_2"] = Number(0.7071067811865476)
  math_props["abs"] = make_static_func_with_length("abs", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(n.abs())
  })
  math_props["floor"] = make_static_func_with_length("floor", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(n.floor())
  })
  math_props["ceil"] = make_static_func_with_length("ceil", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(n.ceil())
  })
  math_props["round"] = make_static_func_with_length("round", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    if n.is_nan() || n.is_inf() || n == 0.0 {
      Number(n)
    } else {
      let rounded = (n + 0.5).floor()
      if rounded == 0.0 && n < 0.0 {
        Number(-0.0)
      } else {
        Number(rounded)
      }
    }
  })
  math_props["trunc"] = make_static_func_with_length("trunc", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    if n >= 0.0 {
      Number(n.floor())
    } else {
      Number(-(-n).floor())
    }
  })
  math_props["sqrt"] = make_static_func_with_length("sqrt", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(n.sqrt())
  })
  math_props["pow"] = make_static_func_with_length("pow", 2, fn(args) raise {
    let base = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    let exp = if args.length() > 1 { to_number(args[1]) } else { 0.0 / 0.0 }
    Number(@math.pow(base, exp))
  })
  math_props["min"] = make_static_func_with_length("min", 2, fn(args) raise {
    if args.length() == 0 {
      return Number(1.0 / 0.0)
    }
    let mut result = to_number(args[0])
    for i = 1; i < args.length(); i = i + 1 {
      let n = to_number(args[i])
      if n.is_nan() {
        return Number(0.0 / 0.0)
      }
      if n < result {
        result = n
      }
    }
    Number(result)
  })
  math_props["max"] = make_static_func_with_length("max", 2, fn(args) raise {
    if args.length() == 0 {
      return Number(-1.0 / 0.0)
    }
    let mut result = to_number(args[0])
    for i = 1; i < args.length(); i = i + 1 {
      let n = to_number(args[i])
      if n.is_nan() {
        return Number(0.0 / 0.0)
      }
      if n > result {
        result = n
      }
    }
    Number(result)
  })
  let rng_state : Array[Int] = [123456789]
  math_props["random"] = make_static_func_with_length("random", 0, fn(_args) {
    let mut s = rng_state[0]
    s = s ^ (s << 13)
    s = s ^ (s.reinterpret_as_uint() >> 17).reinterpret_as_int()
    s = s ^ (s << 5)
    rng_state[0] = s
    let normalized = (s & 0x7FFFFFFF).to_double() / 2147483648.0
    Number(normalized)
  })
  math_props["sign"] = make_static_func_with_length("sign", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    if n.is_nan() {
      Number(0.0 / 0.0)
    } else if n > 0.0 {
      Number(1.0)
    } else if n < 0.0 {
      Number(-1.0)
    } else {
      Number(n) // preserves +0/-0
    }
  })
  math_props["log"] = make_static_func_with_length("log", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.ln(n))
  })
  math_props["log2"] = make_static_func_with_length("log2", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.log2(n))
  })
  math_props["log10"] = make_static_func_with_length("log10", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.log10(n))
  })
  math_props["sin"] = make_static_func_with_length("sin", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.sin(n))
  })
  math_props["cos"] = make_static_func_with_length("cos", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.cos(n))
  })
  math_props["tan"] = make_static_func_with_length("tan", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.tan(n))
  })
  math_props["asin"] = make_static_func_with_length("asin", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.asin(n))
  })
  math_props["acos"] = make_static_func_with_length("acos", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.acos(n))
  })
  math_props["atan"] = make_static_func_with_length("atan", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.atan(n))
  })
  math_props["atan2"] = make_static_func_with_length("atan2", 2, fn(
    args,
  ) raise {
    let y = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    let x = if args.length() > 1 { to_number(args[1]) } else { 0.0 / 0.0 }
    Number(@math.atan2(y, x))
  })
  math_props["sinh"] = make_static_func_with_length("sinh", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.sinh(n))
  })
  math_props["cosh"] = make_static_func_with_length("cosh", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.cosh(n))
  })
  math_props["tanh"] = make_static_func_with_length("tanh", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.tanh(n))
  })
  math_props["asinh"] = make_static_func_with_length("asinh", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.asinh(n))
  })
  math_props["acosh"] = make_static_func_with_length("acosh", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.acosh(n))
  })
  math_props["atanh"] = make_static_func_with_length("atanh", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.atanh(n))
  })
  math_props["exp"] = make_static_func_with_length("exp", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.exp(n))
  })
  math_props["expm1"] = make_static_func_with_length("expm1", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.expm1(n))
  })
  math_props["log1p"] = make_static_func_with_length("log1p", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    // log1p(x) = ln(1 + x), more accurate for small x
    if n.is_nan() || n < -1.0 {
      Number(0.0 / 0.0)
    } else if n == -1.0 {
      Number(-1.0 / 0.0)
    } else if n == 0.0 || n.is_inf() {
      Number(n)
    } else {
      Number(@math.ln(1.0 + n))
    }
  })
  math_props["hypot"] = make_static_func_with_length("hypot", 2, fn(
    args,
  ) raise {
    if args.length() == 0 {
      return Number(0.0)
    }
    let mut sum = 0.0
    for arg in args {
      let n = to_number(arg)
      if n.is_inf() {
        return Number(1.0 / 0.0)
      }
      if n.is_nan() {
        return Number(0.0 / 0.0)
      }
      sum = sum + n * n
    }
    Number(sum.sqrt())
  })
  math_props["cbrt"] = make_static_func_with_length("cbrt", 1, fn(args) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    if n.is_nan() || n.is_inf() || n == 0.0 {
      Number(n)
    } else {
      let sign : Double = if n < 0.0 { -1.0 } else { 1.0 }
      Number(sign * @math.pow(n.abs(), 1.0 / 3.0))
    }
  })
  math_props["clz32"] = make_static_func_with_length("clz32", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 }
    let int_val = to_int32(n)
    if int_val == 0 {
      return Number(32.0)
    }
    let uint = int_val.reinterpret_as_uint()
    let mut count = 0
    let mut mask : UInt = 2147483648 // 0x80000000
    while mask > 0 && (uint & mask) == 0 {
      count = count + 1
      mask = mask >> 1
    }
    Number(count.to_double())
  })
  math_props["imul"] = make_static_func_with_length("imul", 2, fn(args) raise {
    let a = if args.length() > 0 { to_number(args[0]) } else { 0.0 }
    let b = if args.length() > 1 { to_number(args[1]) } else { 0.0 }
    let int_a = to_int32(a)
    let int_b = to_int32(b)
    // Perform 32-bit multiplication and mask to lower 32 bits as signed
    let product = int_a.to_int64() * int_b.to_int64()
    let masked = product & 0xFFFFFFFFL
    // Convert to signed 32-bit
    let result = if masked > 0x7FFFFFFFL {
      (masked - 0x100000000L).to_int()
    } else {
      masked.to_int()
    }
    Number(result.to_double())
  })
  math_props["fround"] = make_static_func_with_length("fround", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    // Round to nearest float32 (basic approximation)
    if n.is_nan() || n.is_inf() || n == 0.0 {
      Number(n)
    } else {
      // Convert to float32 and back (approximation)
      Number(Float::from_double(n).to_double())
    }
  })
  // Math.sumPrecise(items) - sums iterable of numbers
  math_props["sumPrecise"] = make_interp_method_func("sumPrecise", 1, fn(
    interp,
    _this_val,
    args,
  ) raise {
    let items = if args.length() > 0 { args[0] } else { Undefined }
    // items must be an iterable
    let loc = @token.Loc::default()
    let mut sum = 0.0
    let mut count = 0
    match items {
      Array(arr_data) =>
        for elem in arr_data.elements {
          match elem {
            Number(n) => sum = sum + n
            _ =>
              raise @errors.TypeError(
                message="Math.sumPrecise: non-number value in iterable",
              )
          }
          count = count + 1
        }
      Object(_) => {
        // Try to use Symbol.iterator
        let iterator_sym = get_iterator_symbol()
        let iter_fn = interp.get_computed_property(
          items,
          Symbol(iterator_sym),
          loc,
        )
        if is_callable(iter_fn) {
          let iterator = interp.call_value(iter_fn, items, [], loc)
          let next_fn = interp.get_property(iterator, "next", loc)
          while true {
            let result = interp.call_value(next_fn, iterator, [], loc)
            let done = interp.get_property(result, "done", loc)
            if is_truthy(done) {
              break
            }
            let value = interp.get_property(result, "value", loc)
            match value {
              Number(n) => sum = sum + n
              _ =>
                raise @errors.TypeError(
                  message="Math.sumPrecise: non-number value in iterable",
                )
            }
            count = count + 1
          }
        } else {
          raise @errors.TypeError(
            message="Math.sumPrecise: argument is not iterable",
          )
        }
      }
      _ =>
        raise @errors.TypeError(
          message="Math.sumPrecise: argument is not iterable",
        )
    }
    let _ = count
    Number(sum)
  })

  // Set up descriptors for Math properties
  let math_descs : Map[String, PropDescriptor] = {}
  let const_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
  }
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  // Constants are non-writable, non-enumerable, non-configurable
  let math_constants = [
    "PI", "E", "LN2", "LN10", "LOG2E", "LOG10E", "SQRT2", "SQRT1_2",
  ]
  for c in math_constants {
    math_descs[c] = const_desc
  }
  // Methods are writable, non-enumerable, configurable
  let math_methods = [
    "abs", "floor", "ceil", "round", "trunc", "sqrt", "pow", "min", "max", "random",
    "sign", "log", "log2", "log10", "sin", "cos", "tan", "asin", "acos", "atan",
    "atan2", "sinh", "cosh", "tanh", "asinh", "acosh", "atanh", "exp", "expm1", "log1p",
    "hypot", "cbrt", "clz32", "imul", "fround", "sumPrecise",
  ]
  for m in math_methods {
    math_descs[m] = method_desc
  }
  // Set up Symbol.toStringTag for Math
  let math_symbol_props : Map[Int, Value] = {}
  let tostringtag_sym = get_tostringtag_symbol()
  math_symbol_props[tostringtag_sym.id] = String_("Math")
  let math_symbol_descs : Map[Int, PropDescriptor] = {}
  math_symbol_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  env.def_builtin(
    "Math",
    Object({
      properties: math_props,
      symbol_properties: math_symbol_props,
      prototype: match env.bindings.get("[[ObjectPrototype]]") {
        Some(binding) => binding.value
        None => Null
      },
      callable: None,
      class_name: "Math",
      descriptors: math_descs,
      symbol_descriptors: math_symbol_descs,
      extensible: true,
    }),
  )
}

///|
fn uri_encode(s : String, encode_component : Bool) -> String {
  // Characters that are never encoded
  // For encodeURIComponent: A-Z a-z 0-9 - _ . ! ~ * ' ( )
  // For encodeURI: A-Z a-z 0-9 - _ . ! ~ * ' ( ) ; , / ? : @ & = + $ #
  let buf = StringBuilder::new()
  let chars = s.to_array()
  let hex_digits = "0123456789ABCDEF"
  let hd = hex_digits.to_array()
  for c in chars {
    let code = c.to_int()
    let should_encode = if code >= 65 && code <= 90 {
      // A-Z
      false
    } else if code >= 97 && code <= 122 {
      // a-z
      false
    } else if code >= 48 && code <= 57 {
      // 0-9
      false
    } else if c == '-' ||
      c == '_' ||
      c == '.' ||
      c == '!' ||
      c == '~' ||
      c == '*' ||
      c == '\'' ||
      c == '(' ||
      c == ')' {
      false
    } else if !encode_component &&
      (
        c == ';' ||
        c == ',' ||
        c == '/' ||
        c == '?' ||
        c == ':' ||
        c == '@' ||
        c == '&' ||
        c == '=' ||
        c == '+' ||
        c == '$' ||
        c == '#'
      ) {
      false
    } else {
      true
    }
    if should_encode {
      if code <= 0x7F {
        // Single byte
        buf.write_char('%')
        buf.write_char(hd[(code >> 4) & 0xF])
        buf.write_char(hd[code & 0xF])
      } else if code <= 0x7FF {
        // Two bytes
        let b1 = 0xC0 | (code >> 6)
        let b2 = 0x80 | (code & 0x3F)
        buf.write_char('%')
        buf.write_char(hd[(b1 >> 4) & 0xF])
        buf.write_char(hd[b1 & 0xF])
        buf.write_char('%')
        buf.write_char(hd[(b2 >> 4) & 0xF])
        buf.write_char(hd[b2 & 0xF])
      } else if code <= 0xFFFF {
        // Three bytes
        let b1 = 0xE0 | (code >> 12)
        let b2 = 0x80 | ((code >> 6) & 0x3F)
        let b3 = 0x80 | (code & 0x3F)
        buf.write_char('%')
        buf.write_char(hd[(b1 >> 4) & 0xF])
        buf.write_char(hd[b1 & 0xF])
        buf.write_char('%')
        buf.write_char(hd[(b2 >> 4) & 0xF])
        buf.write_char(hd[b2 & 0xF])
        buf.write_char('%')
        buf.write_char(hd[(b3 >> 4) & 0xF])
        buf.write_char(hd[b3 & 0xF])
      } else {
        // Four bytes
        let b1 = 0xF0 | (code >> 18)
        let b2 = 0x80 | ((code >> 12) & 0x3F)
        let b3 = 0x80 | ((code >> 6) & 0x3F)
        let b4 = 0x80 | (code & 0x3F)
        buf.write_char('%')
        buf.write_char(hd[(b1 >> 4) & 0xF])
        buf.write_char(hd[b1 & 0xF])
        buf.write_char('%')
        buf.write_char(hd[(b2 >> 4) & 0xF])
        buf.write_char(hd[b2 & 0xF])
        buf.write_char('%')
        buf.write_char(hd[(b3 >> 4) & 0xF])
        buf.write_char(hd[b3 & 0xF])
        buf.write_char('%')
        buf.write_char(hd[(b4 >> 4) & 0xF])
        buf.write_char(hd[b4 & 0xF])
      }
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Check if a character is a URI reserved character
fn is_uri_reserved(c : Char) -> Bool {
  // Reserved characters that decodeURI must preserve: ; , / ? : @ & = + $ #
  c == ';' ||
  c == ',' ||
  c == '/' ||
  c == '?' ||
  c == ':' ||
  c == '@' ||
  c == '&' ||
  c == '=' ||
  c == '+' ||
  c == '$' ||
  c == '#'
}

///|
fn uri_decode(s : String, preserve_reserved : Bool) -> String raise Error {
  let buf = StringBuilder::new()
  let chars = s.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    if chars[i] == '%' {
      // Check for valid percent-encoded sequence
      if i + 2 >= len {
        raise @errors.URIError(message="URI malformed")
      }
      let h1 = hex_char_value(chars[i + 1])
      let h2 = hex_char_value(chars[i + 2])
      if h1 < 0 || h2 < 0 {
        raise @errors.URIError(message="URI malformed")
      }
      let byte1 = (h1 << 4) | h2
      // Check for multi-byte UTF-8 sequences
      if byte1 >= 0xF0 {
        // 4-byte sequence
        if i + 11 >= len {
          raise @errors.URIError(message="URI malformed")
        }
        let b2 = decode_percent_byte(chars, i + 3)
        let b3 = decode_percent_byte(chars, i + 6)
        let b4 = decode_percent_byte(chars, i + 9)
        if b2 < 0 || b3 < 0 || b4 < 0 {
          raise @errors.URIError(message="URI malformed")
        }
        // Validate continuation bytes (must be 10xxxxxx)
        if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 || (b4 & 0xC0) != 0x80 {
          raise @errors.URIError(message="URI malformed")
        }
        let cp = ((byte1 & 0x07) << 18) |
          ((b2 & 0x3F) << 12) |
          ((b3 & 0x3F) << 6) |
          (b4 & 0x3F)
        buf.write_char(cp.unsafe_to_char())
        i = i + 12
        continue
      } else if byte1 >= 0xE0 {
        // 3-byte sequence
        if i + 8 >= len {
          raise @errors.URIError(message="URI malformed")
        }
        let b2 = decode_percent_byte(chars, i + 3)
        let b3 = decode_percent_byte(chars, i + 6)
        if b2 < 0 || b3 < 0 {
          raise @errors.URIError(message="URI malformed")
        }
        // Validate continuation bytes
        if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 {
          raise @errors.URIError(message="URI malformed")
        }
        let cp = ((byte1 & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
        buf.write_char(cp.unsafe_to_char())
        i = i + 9
        continue
      } else if byte1 >= 0xC0 {
        // 2-byte sequence
        if i + 5 >= len {
          raise @errors.URIError(message="URI malformed")
        }
        let b2 = decode_percent_byte(chars, i + 3)
        if b2 < 0 {
          raise @errors.URIError(message="URI malformed")
        }
        // Validate continuation byte
        if (b2 & 0xC0) != 0x80 {
          raise @errors.URIError(message="URI malformed")
        }
        let cp = ((byte1 & 0x1F) << 6) | (b2 & 0x3F)
        buf.write_char(cp.unsafe_to_char())
        i = i + 6
        continue
      } else if byte1 >= 0x80 {
        // Invalid: continuation byte without lead byte
        raise @errors.URIError(message="URI malformed")
      }
      // Single byte (ASCII)
      let decoded_char = byte1.unsafe_to_char()
      // For decodeURI, preserve reserved characters in encoded form
      if preserve_reserved && is_uri_reserved(decoded_char) {
        buf.write_char(chars[i])
        buf.write_char(chars[i + 1])
        buf.write_char(chars[i + 2])
      } else {
        buf.write_char(decoded_char)
      }
      i = i + 3
      continue
    }
    buf.write_char(chars[i])
    i = i + 1
  }
  buf.to_string()
}

///|
fn hex_char_value(c : Char) -> Int {
  let code = c.to_int()
  if code >= 48 && code <= 57 {
    code - 48
  } else if code >= 65 && code <= 70 {
    code - 55
  } else if code >= 97 && code <= 102 {
    code - 87
  } else {
    -1
  }
}

///|
fn decode_percent_byte(chars : Array[Char], pos : Int) -> Int {
  if chars[pos] == '%' {
    let h1 = hex_char_value(chars[pos + 1])
    let h2 = hex_char_value(chars[pos + 2])
    if h1 >= 0 && h2 >= 0 {
      return (h1 << 4) | h2
    }
  }
  -1
}

///|
/// escape() helper — Annex B encoding.
/// Characters A-Z, a-z, 0-9, @, *, _, +, -, ., / are left unchanged.
/// Code points < 256 are encoded as %XX, others as %uXXXX.
fn js_escape(s : String) -> String {
  let buf = StringBuilder::new()
  let hex_digits = "0123456789ABCDEF"
  let hd = hex_digits.to_array()
  let chars = s.to_array()
  for c in chars {
    let code = c.to_int()
    // Check if the character is in the "safe" set
    let safe = if code >= 65 && code <= 90 {
      // A-Z
      true
    } else if code >= 97 && code <= 122 {
      // a-z
      true
    } else if code >= 48 && code <= 57 {
      // 0-9
      true
    } else if c == '@' ||
      c == '*' ||
      c == '_' ||
      c == '+' ||
      c == '-' ||
      c == '.' ||
      c == '/' {
      true
    } else {
      false
    }
    if safe {
      buf.write_char(c)
    } else if code < 256 {
      // %XX
      buf.write_char('%')
      buf.write_char(hd[(code >> 4) & 0xF])
      buf.write_char(hd[code & 0xF])
    } else {
      // %uXXXX
      buf.write_char('%')
      buf.write_char('u')
      buf.write_char(hd[(code >> 12) & 0xF])
      buf.write_char(hd[(code >> 8) & 0xF])
      buf.write_char(hd[(code >> 4) & 0xF])
      buf.write_char(hd[code & 0xF])
    }
  }
  buf.to_string()
}

///|
/// unescape() helper — Annex B decoding.
/// Recognises %uXXXX and %XX sequences; everything else passes through.
fn js_unescape(s : String) -> String {
  let buf = StringBuilder::new()
  let chars = s.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    if chars[i] == '%' {
      // Try %uXXXX first
      if i + 5 < len && chars[i + 1] == 'u' {
        let h1 = hex_char_value(chars[i + 2])
        let h2 = hex_char_value(chars[i + 3])
        let h3 = hex_char_value(chars[i + 4])
        let h4 = hex_char_value(chars[i + 5])
        if h1 >= 0 && h2 >= 0 && h3 >= 0 && h4 >= 0 {
          let cp = (h1 << 12) | (h2 << 8) | (h3 << 4) | h4
          buf.write_char(cp.unsafe_to_char())
          i = i + 6
          continue
        }
      }
      // Try %XX
      if i + 2 < len {
        let h1 = hex_char_value(chars[i + 1])
        let h2 = hex_char_value(chars[i + 2])
        if h1 >= 0 && h2 >= 0 {
          let cp = (h1 << 4) | h2
          buf.write_char(cp.unsafe_to_char())
          i = i + 3
          continue
        }
      }
    }
    buf.write_char(chars[i])
    i = i + 1
  }
  buf.to_string()
}

///|
/// Set up test262 harness functions that require host-level support.
/// These are functions the test262 test suite expects the host environment
/// to provide. Unsupported operations throw TypeError with a descriptive message.
pub fn setup_harness_builtins(
  env : Environment,
  output : Array[String],
  global_this : Value,
) -> Unit {
  // print() - host-provided print function for test262 harness compatibility.
  // Joins arguments with spaces and appends to output (like console.log).
  let print_func = make_native_func("print", fn(args) {
    let parts : Array[String] = args.map(fn(a) { a.to_string() })
    output.push(parts.join(" "))
    Undefined
  })
  env.def_builtin("print", print_func)

  // $262.agent - stub object for agent/worker testing (Atomics/SharedArrayBuffer).
  // All methods throw because the engine has no multi-agent support.
  let agent_props : Map[String, Value] = {}
  agent_props["start"] = make_native_func("start", fn(_args) raise {
    raise @errors.TypeError(message="$262.agent.start is not supported")
  })
  agent_props["broadcast"] = make_native_func("broadcast", fn(_args) raise {
    raise @errors.TypeError(message="$262.agent.broadcast is not supported")
  })
  agent_props["getReport"] = make_native_func("getReport", fn(_args) raise {
    raise @errors.TypeError(message="$262.agent.getReport is not supported")
  })
  agent_props["sleep"] = make_native_func("sleep", fn(_args) raise {
    raise @errors.TypeError(message="$262.agent.sleep is not supported")
  })
  agent_props["monotonicNow"] = make_native_func("monotonicNow", fn(
    _args,
  ) raise {
    raise @errors.TypeError(message="$262.agent.monotonicNow is not supported")
  })
  let agent : Value = Object({
    properties: agent_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Object",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // $262 - the test262 host object providing host-level hooks.
  let dollar262_props : Map[String, Value] = {}
  dollar262_props["global"] = global_this
  dollar262_props["agent"] = agent
  dollar262_props["gc"] = make_native_func("gc", fn(_args) { Undefined })

  // $262.createRealm() - creates a fresh realm with its own global environment
  // and returns the new realm's $262 object. The returned object's methods
  // (evalScript, etc.) are bound to the new realm's interpreter via closures,
  // ensuring proper isolation.
  dollar262_props["createRealm"] = make_interp_method_func("createRealm", 0, fn(
    _interp,
    _this_val,
    _args,
  ) {
    let new_interp = Interpreter::new()
    // Build a $262 object with methods bound to the new interpreter.
    // Uses NativeCallable closures that capture new_interp so that
    // evalScript executes in the new realm, not the caller's.
    let realm_props : Map[String, Value] = {}
    realm_props["global"] = new_interp.global_this
    realm_props["gc"] = make_native_func("gc", fn(_a) { Undefined })
    realm_props["evalScript"] = make_native_func("evalScript", fn(
      es_args,
    ) raise {
      let code = if es_args.length() > 0 {
        match es_args[0] {
          String_(s) => s
          _ => es_args[0].to_string()
        }
      } else {
        ""
      }
      let prog = @parser.parse(code)
      new_interp.run(prog.stmts)
    })
    realm_props["createRealm"] = make_native_func("createRealm", fn(_a) {
      // Recursive: create yet another fresh realm
      let inner = Interpreter::new()
      inner.global.get("$262") catch {
        _ => Undefined
      }
    })
    realm_props["detachArrayBuffer"] = make_native_func("detachArrayBuffer", fn(
      a,
    ) raise {
      if a.length() == 0 {
        raise @errors.TypeError(
          message="$262.detachArrayBuffer requires an ArrayBuffer argument",
        )
      }
      match get_buffer_id(a[0]) {
        Some(id) => {
          detach_arraybuffer(id)
          Undefined
        }
        None =>
          raise @errors.TypeError(
            message="$262.detachArrayBuffer requires an ArrayBuffer argument",
          )
      }
    })
    Object({
      properties: realm_props,
      symbol_properties: {},
      prototype: Null,
      callable: None,
      class_name: "Object",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    })
  })

  // $262.evalScript(code) - parses and evaluates code as a script
  // in the current realm's global scope.
  dollar262_props["evalScript"] = make_interp_method_func("evalScript", 0, fn(
    interp,
    _this_val,
    args,
  ) raise {
    let code = if args.length() > 0 {
      match args[0] {
        String_(s) => s
        _ => args[0].to_string()
      }
    } else {
      ""
    }
    let prog = @parser.parse(code)
    interp.run(prog.stmts)
  })
  dollar262_props["detachArrayBuffer"] = make_native_func("detachArrayBuffer", fn(
    args,
  ) raise {
    if args.length() == 0 {
      raise @errors.TypeError(
        message="$262.detachArrayBuffer requires an ArrayBuffer argument",
      )
    }
    match get_buffer_id(args[0]) {
      Some(id) => {
        detach_arraybuffer(id)
        Undefined
      }
      None =>
        raise @errors.TypeError(
          message="$262.detachArrayBuffer requires an ArrayBuffer argument",
        )
    }
  })
  let dollar262 : Value = Object({
    properties: dollar262_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Object",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  env.def_builtin("$262", dollar262)

  // Mirror harness bindings onto the global object so that globalThis.$262,
  // this.$262, globalThis.print etc. also work (not just bare name resolution).
  match global_this {
    Object(data) => {
      data.properties["$262"] = dollar262
      data.properties["print"] = print_func
    }
    _ => ()
  }
}
