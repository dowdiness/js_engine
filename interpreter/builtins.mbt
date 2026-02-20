///|
fn func_body_has_use_strict(body : Array[@ast.Stmt]) -> Bool {
  // Scan the directive prologue: the longest sequence of ExpressionStatements
  // consisting entirely of StringLiterals at the beginning of the body.
  // Only the literal string "use strict" WITHOUT escape sequences activates strict mode.
  for i = 0; i < body.length(); i = i + 1 {
    match body[i] {
      ExprStmt(StringLit(s, has_escape, _), _) =>
        if s == "use strict" && not(has_escape) {
          return true
        }
      _ => break
    }
  }
  false
}

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
      Bool(not(n.is_nan()) && not(n.is_inf()))
    }),
  )

  // parseInt(string, radix?)
  env.def_builtin(
    "parseInt",
    make_static_func("parseInt", fn(args) raise {
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
      let mut radix = if args.length() > 1 {
        let r = to_number(args[1]).to_int()
        if r < 2 || r > 36 {
          return Number(0.0 / 0.0)
        }
        r
      } else {
        10
      }
      // Detect 0x prefix for hex
      if radix == 16 || args.length() <= 1 || to_number(args[1]).to_int() == 0 {
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
      if not(found) {
        Number(0.0 / 0.0)
      } else {
        Number(sign * result)
      }
    }),
  )

  // parseFloat(string)
  env.def_builtin(
    "parseFloat",
    make_static_func("parseFloat", fn(args) raise {
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
      if not(has_digits) {
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
      let result = @strconv.parse_double(buf.to_string()) catch {
        _ => 0.0 / 0.0
      }
      Number(result)
    }),
  )

  // encodeURIComponent(string)
  env.def_builtin(
    "encodeURIComponent",
    make_static_func("encodeURIComponent", fn(args) raise {
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
    make_static_func("decodeURIComponent", fn(args) raise {
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
    make_static_func("encodeURI", fn(args) raise {
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
    make_static_func("decodeURI", fn(args) raise {
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
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "String",
    descriptors: {},
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
        "fromCharCode": make_static_func("fromCharCode", fn(args) raise {
          let buf = StringBuilder::new()
          for arg in args {
            let code = to_number(arg).to_int()
            // fromCharCode uses UTF-16 code units, modulo 2^16
            let code_unit = code & 0xFFFF
            buf.write_char(code_unit.unsafe_to_char())
          }
          String_(buf.to_string())
        }),
        "fromCodePoint": make_static_func("fromCodePoint", fn(args) raise {
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
        "raw": make_static_func("raw", fn(args) raise {
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
          let val = if args.length() > 0 { args[0] } else { Undefined }
          // Per spec: String(symbol) returns the symbol description
          let str = match val {
            Symbol(sym) =>
              match sym.description {
                Some(d) => "Symbol(" + d + ")"
                None => "Symbol()"
              }
            _ => to_js_string(val)
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
        "name": nf_desc, "length": nf_desc,
        "prototype": { writable: false, enumerable: false, configurable: false, getter: None, setter: None },
        "fromCharCode": { writable: true, enumerable: false, configurable: true, getter: None, setter: None },
        "fromCodePoint": { writable: true, enumerable: false, configurable: true, getter: None, setter: None },
        "raw": { writable: true, enumerable: false, configurable: true, getter: None, setter: None },
      },
      symbol_descriptors: {},
      extensible: true,
    }),
  )

  // Store String.prototype for ToObject wrapping
  env.def_builtin("[[StringPrototype]]", string_proto)
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
  boolean_proto_props["toString"] = make_method_func("toString", 0, fn(this_val, _args) raise {
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
  boolean_proto_props["valueOf"] = make_method_func("valueOf", 0, fn(this_val, _args) raise {
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
  let boolean_proto : Value = Object({
    properties: boolean_proto_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Boolean",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  // Store Boolean.prototype for ToObject wrapping
  env.def_builtin("[[BooleanPrototype]]", boolean_proto)
  env.def_builtin(
    "Boolean",
    Object({
      properties: { "prototype": boolean_proto, "name": String_("Boolean"), "length": Number(1.0) },
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
      descriptors: { "name": nf_desc, "length": nf_desc, "prototype": { writable: false, enumerable: false, configurable: false, getter: None, setter: None } },
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
  let error_proto = register_error_ctor(env, "Error", Null)
  register_error_ctor(env, "TypeError", error_proto) |> ignore
  register_error_ctor(env, "ReferenceError", error_proto) |> ignore
  register_error_ctor(env, "SyntaxError", error_proto) |> ignore
  register_error_ctor(env, "RangeError", error_proto) |> ignore
  register_error_ctor(env, "URIError", error_proto) |> ignore
  register_error_ctor(env, "EvalError", error_proto) |> ignore
  register_aggregate_error_ctor(env, error_proto) |> ignore

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
        "Boolean", "String", "Number", "Error", "TypeError", "ReferenceError",
        "SyntaxError", "RangeError", "URIError", "EvalError", "AggregateError",
        "Array", "Object", "Function",
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
        "TypeError", "ReferenceError", "SyntaxError", "RangeError",
        "URIError", "EvalError", "AggregateError",
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
        NativeCallable("RegExp", fn(args) {
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
        "Map", "Set", "WeakMap", "WeakSet", "Date", "RegExp", "Promise",
        "Proxy", "ArrayBuffer", "DataView",
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
  let species_sym = new_symbol(Some("Symbol.species"))
  let match_sym = new_symbol(Some("Symbol.match"))
  well_known_match_sym.val = Some(match_sym)
  let match_all_sym = new_symbol(Some("Symbol.matchAll"))
  let replace_sym = new_symbol(Some("Symbol.replace"))
  well_known_replace_sym.val = Some(replace_sym)
  let search_sym = new_symbol(Some("Symbol.search"))
  well_known_search_sym.val = Some(search_sym)
  let split_sym = new_symbol(Some("Symbol.split"))
  well_known_split_sym.val = Some(split_sym)
  let unscopables_sym = new_symbol(Some("Symbol.unscopables"))
  let async_iterator_sym = new_symbol(Some("Symbol.asyncIterator"))
  well_known_async_iterator_sym.val = Some(async_iterator_sym)

  // Symbol prototype
  let symbol_proto_props : Map[String, Value] = {}
  let symbol_proto_descs : Map[String, PropDescriptor] = {}
  symbol_proto_props["toString"] = make_method_func("toString", 0, fn(this_val, _args) raise {
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
  symbol_proto_props["valueOf"] = make_method_func("valueOf", 0, fn(this_val, _args) raise {
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
  let description_getter = make_method_func("get description", 0, fn(this_val, _args) raise {
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
  let toprimitive_method = make_method_func("[Symbol.toPrimitive]", 1, fn(this_val, _args) raise {
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
  symbol_proto_sym_descs[to_primitive_sym.id] = { ..wks_desc, configurable: true }

  // Symbol.prototype[@@toStringTag] = "Symbol"
  symbol_proto_sym_props[to_string_tag_sym.id] = String_("Symbol")
  symbol_proto_sym_descs[to_string_tag_sym.id] = nf_desc

  let symbol_proto : Value = Object({
    properties: symbol_proto_props,
    symbol_properties: symbol_proto_sym_props,
    prototype: Null,
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
  symbol_props["keyFor"] = make_static_func_with_length("keyFor", 1, fn(args) raise {
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
    let iter_obj = Object({
      properties: iter_props,
      symbol_properties: iter_symbol_props,
      prototype: Null,
      callable: None,
      class_name: "Array Iterator",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    })

    // Add [Symbol.iterator] that returns the iterator itself
    match iter_obj {
      Object(data) =>
        data.symbol_properties[iterator_sym.id] = make_method_func("[Symbol.iterator]", 0, fn(this_val, _args) { this_val })
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
        data.symbol_properties[iterator_sym.id] = make_method_func("[Symbol.iterator]", 0, fn(this_val, _args) { this_val })
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
          proto_data.symbol_properties[iterator_sym.id] = make_method_func("[Symbol.iterator]", 0, fn(this_val, _args) {
                match this_val {
                  Array(arr) => make_array_iterator(arr)
                  _ => make_array_like_iterator(this_val)
                }
              })

          // Also add values() method (alias for [Symbol.iterator])
          proto_data.properties["values"] = make_method_func("values", 0, fn(this_val, _args) {
                match this_val {
                  Array(arr) => make_array_iterator(arr)
                  _ => make_array_like_iterator(this_val)
                }
              })

          // Add keys() method that returns an iterator over indices
          proto_data.properties["keys"] = make_method_func("keys", 0, fn(this_val, _args) {
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
                    data.symbol_properties[iterator_sym.id] = make_method_func("[Symbol.iterator]", 0, fn(
                          this_val,
                          _args,
                        ) {
                          this_val
                        })
                  _ => ()
                }
                iter_obj
              })

          // Add entries() method that returns an iterator over [index, value] pairs
          proto_data.properties["entries"] = make_method_func("entries", 0, fn(this_val, _args) {
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
                    data.symbol_properties[iterator_sym.id] = make_method_func("[Symbol.iterator]", 0, fn(
                          this_val,
                          _args,
                        ) {
                          this_val
                        })
                  _ => ()
                }
                iter_obj
              })
        }
        _ => ()
      }
    _ => ()
  }

  // Add [Symbol.iterator] for String prototype
  // String's [Symbol.iterator] is accessed via get_string_method, so we store a reference
  // to tell the interpreter to use string iterator
  // We'll handle this in the interpreter by checking for Symbol.iterator access on strings
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
    "abs", "floor", "ceil", "round", "trunc", "sqrt", "pow", "min", "max",
    "random", "sign", "log", "log2", "log10", "sin", "cos", "tan", "asin",
    "acos", "atan", "atan2", "sinh", "cosh", "tanh", "asinh", "acosh",
    "atanh", "exp", "expm1", "log1p", "hypot", "cbrt", "clz32", "imul",
    "fround",
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
fn register_error_ctor(
  env : Environment,
  name : String,
  parent_proto : Value,
) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let proto_props : Map[String, Value] = {}
  proto_props["name"] = String_(name)
  proto_props["message"] = String_("")
  proto_props["toString"] = make_method_func("toString", 0, fn(this_val, _args) raise {
    // Step 1: If this is not an Object, throw TypeError
    match this_val {
      Object(_) => ()
      _ => raise @errors.TypeError(message="Error.prototype.toString requires that 'this' be an Object")
    }
    let name_val = match this_val {
      Object(data) => match data.properties.get("name") {
        Some(v) => v
        None => Undefined
      }
      _ => Undefined
    }
    let name_str = match name_val {
      Undefined => "Error"
      String_(s) => s
      other => other.to_string()
    }
    let msg_val = match this_val {
      Object(data) => match data.properties.get("message") {
        Some(v) => v
        None => Undefined
      }
      _ => Undefined
    }
    let msg_str = match msg_val {
      Undefined => ""
      String_(s) => s
      other => other.to_string()
    }
    if name_str == "" {
      String_(msg_str)
    } else if msg_str == "" {
      String_(name_str)
    } else {
      String_(name_str + ": " + msg_str)
    }
  })
  let proto_desc : PropDescriptor = { writable: true, enumerable: false, configurable: true, getter: None, setter: None }
  // Error.prototype class_name should be "Object" per spec (not error type name)
  let proto_obj : Value = Object({
    properties: proto_props,
    symbol_properties: {},
    prototype: parent_proto,
    callable: None,
    class_name: "Object",
    descriptors: { "name": proto_desc, "message": proto_desc, "toString": proto_desc },
    symbol_descriptors: {},
    extensible: true,
  })
  // Determine the parent constructor's [[Prototype]] for the error constructor
  // For Error itself, it should be Function.prototype (Null for now, set later)
  // For NativeErrors, it should be the Error constructor
  let ctor_proto : Value = if name == "Error" {
    Null
  } else {
    match env.bindings.get("Error") {
      Some(binding) => binding.value
      None => Null
    }
  }
  let proto_nw_desc : PropDescriptor = { writable: false, enumerable: false, configurable: false, getter: None, setter: None }
  env.def_builtin(
    name,
    Object({
      properties: { "prototype": proto_obj, "name": String_(name), "length": Number(1.0) },
      symbol_properties: {},
      prototype: ctor_proto,
      callable: Some(
        NativeCallable(name, fn(args) {
          let message = if args.length() > 0 {
            match args[0] {
              String_(s) => s
              Undefined => ""
              other => other.to_string()
            }
          } else {
            ""
          }
          let err_props : Map[String, Value] = {}
          err_props["message"] = String_(message)
          err_props["name"] = String_(name)
          err_props["stack"] = String_(name + ": " + message)
          let err_desc : PropDescriptor = { writable: true, enumerable: false, configurable: true, getter: None, setter: None }
          let err_descs : Map[String, PropDescriptor] = { "message": err_desc, "name": err_desc, "stack": err_desc }
          // Handle options parameter for cause
          if args.length() > 1 {
            match args[1] {
              Object(opts_data) => {
                if opts_data.properties.contains("cause") {
                  err_props["cause"] = opts_data.properties["cause"]
                  err_descs["cause"] = err_desc
                }
              }
              _ => ()
            }
          }
          Object({
            properties: err_props,
            symbol_properties: {},
            prototype: proto_obj,
            callable: None,
            class_name: name,
            descriptors: err_descs,
            symbol_descriptors: {},
            extensible: true,
          })
        }),
      ),
      class_name: "Function",
      descriptors: { "name": nf_desc, "length": nf_desc, "prototype": proto_nw_desc },
      symbol_descriptors: {},
      extensible: true,
    }),
  )
  // Set ErrorType.prototype.constructor = ErrorType
  match proto_obj {
    Object(data) => {
      let ctor = env.get(name) catch { _ => Undefined }
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
  proto_obj
}

///|
fn register_aggregate_error_ctor(
  env : Environment,
  parent_proto : Value,
) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let name = "AggregateError"
  let proto_props : Map[String, Value] = {}
  proto_props["name"] = String_(name)
  proto_props["message"] = String_("")
  proto_props["toString"] = make_method_func("toString", 0, fn(this_val, _args) raise {
    match this_val {
      Object(_) => ()
      _ => raise @errors.TypeError(message="Error.prototype.toString requires that 'this' be an Object")
    }
    let name_val = match this_val {
      Object(data) => match data.properties.get("name") {
        Some(v) => v
        None => Undefined
      }
      _ => Undefined
    }
    let name_str = match name_val {
      Undefined => "Error"
      String_(s) => s
      other => other.to_string()
    }
    let msg_val = match this_val {
      Object(data) => match data.properties.get("message") {
        Some(v) => v
        None => Undefined
      }
      _ => Undefined
    }
    let msg_str = match msg_val {
      Undefined => ""
      String_(s) => s
      other => other.to_string()
    }
    if name_str == "" {
      String_(msg_str)
    } else if msg_str == "" {
      String_(name_str)
    } else {
      String_(name_str + ": " + msg_str)
    }
  })
  let proto_desc : PropDescriptor = { writable: true, enumerable: false, configurable: true, getter: None, setter: None }
  let proto_obj : Value = Object({
    properties: proto_props,
    symbol_properties: {},
    prototype: parent_proto,
    callable: None,
    class_name: "Object",
    descriptors: { "name": proto_desc, "message": proto_desc, "toString": proto_desc },
    symbol_descriptors: {},
    extensible: true,
  })
  // AggregateError constructor's [[Prototype]] should be the Error constructor
  let ctor_proto : Value = match env.bindings.get("Error") {
    Some(binding) => binding.value
    None => Null
  }
  let proto_nw_desc : PropDescriptor = { writable: false, enumerable: false, configurable: false, getter: None, setter: None }
  env.def_builtin(
    name,
    Object({
      properties: { "prototype": proto_obj, "length": Number(2.0), "name": String_(name) },
      symbol_properties: {},
      prototype: ctor_proto,
      callable: Some(
        NativeCallable(name, fn(args) {
          let errors_value : Value = if args.length() > 0 {
            args[0]
          } else {
            Array({ elements: [] })
          }
          let message = if args.length() > 1 {
            match args[1] {
              String_(s) => s
              Undefined => ""
              other => other.to_string()
            }
          } else {
            ""
          }
          let err_props : Map[String, Value] = {}
          err_props["errors"] = errors_value
          err_props["message"] = String_(message)
          err_props["name"] = String_(name)
          err_props["stack"] = String_(name + ": " + message)
          // Handle options parameter for cause
          if args.length() > 2 {
            match args[2] {
              Object(opts_data) => {
                if opts_data.properties.contains("cause") {
                  err_props["cause"] = opts_data.properties["cause"]
                }
              }
              _ => ()
            }
          }
          let err_desc : PropDescriptor = { writable: true, enumerable: false, configurable: true, getter: None, setter: None }
          let err_descs : Map[String, PropDescriptor] = { "message": err_desc, "name": err_desc, "stack": err_desc }
          if err_props.contains("cause") {
            err_descs["cause"] = err_desc
          }
          Object({
            properties: err_props,
            symbol_properties: {},
            prototype: proto_obj,
            callable: None,
            class_name: name,
            descriptors: err_descs,
            symbol_descriptors: {},
            extensible: true,
          })
        }),
      ),
      class_name: "Function",
      descriptors: { "name": nf_desc, "length": nf_desc, "prototype": proto_nw_desc },
      symbol_descriptors: {},
      extensible: true,
    }),
  )
  match proto_obj {
    Object(data) => {
      let ctor = env.get(name) catch { _ => Undefined }
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
  proto_obj
}

///|
fn trim_start(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  while start < chars.length() {
    let c = chars[start]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      start = start + 1
    } else {
      break
    }
  }
  if start == 0 {
    return s
  }
  let buf = StringBuilder::new()
  for i = start; i < chars.length(); i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn char_to_digit(c : Char, radix : Int) -> Int {
  let code = c.to_int()
  let digit = if code >= 48 && code <= 57 {
    // '0' - '9'
    code - 48
  } else if code >= 65 && code <= 90 {
    // 'A' - 'Z'
    code - 65 + 10
  } else if code >= 97 && code <= 122 {
    // 'a' - 'z'
    code - 97 + 10
  } else {
    -1
  }
  if digit >= 0 && digit < radix {
    digit
  } else {
    -1
  }
}

///|
fn setup_number_builtins(env : Environment) -> Unit {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let number_proto_props : Map[String, Value] = {}
  number_proto_props["toFixed"] = make_method_func("toFixed", 1, fn(this_val, args) raise {
        let n : Double = match this_val {
          Number(v) => v
          Object(data) =>
            if data.class_name == "Number" {
              match data.properties.get("[[NumberData]]") {
                Some(Number(v)) => v
                _ =>
                  raise @errors.TypeError(
                    message="Number.prototype.toFixed requires that 'this' be a Number",
                  )
              }
            } else {
              raise @errors.TypeError(
                message="Number.prototype.toFixed requires that 'this' be a Number",
              )
            }
          _ =>
            raise @errors.TypeError(
              message="Number.prototype.toFixed requires that 'this' be a Number",
            )
        }
        let digits = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        if digits < 0 || digits > 100 {
          raise @errors.RangeError(
            message="toFixed() digits argument must be between 0 and 100",
          )
        }
        if n.is_nan() {
          return String_("NaN")
        }
        if n.is_inf() {
          return String_(if n > 0.0 { "Infinity" } else { "-Infinity" })
        }
        // Simple implementation using multiplier approach
        if digits == 0 {
          let rounded = if n >= 0.0 {
            (n + 0.5).floor()
          } else {
            -(-n + 0.5).floor()
          }
          return String_(rounded.to_int().to_string())
        }
        let multiplier = @math.pow(10.0, digits.to_double())
        let shifted = n * multiplier
        let rounded = if shifted >= 0.0 {
          (shifted + 0.5).floor()
        } else {
          -(-shifted + 0.5).floor()
        }
        let rounded_abs = rounded.abs()
        let int_part_abs = (rounded_abs / multiplier).floor()
        let frac_abs = rounded_abs - int_part_abs * multiplier
        let buf = StringBuilder::new()
        if rounded < 0.0 || (n < 0.0 && rounded == 0.0) {
          buf.write_string("-")
        }
        buf.write_string(int_part_abs.to_int().to_string())
        buf.write_string(".")
        let frac_str = frac_abs.to_int().to_string()
        // Pad with leading zeros
        for _i = 0; _i < digits - frac_str.length(); _i = _i + 1 {
          buf.write_string("0")
        }
        buf.write_string(frac_str)
        String_(buf.to_string())
      })
  number_proto_props["toString"] = make_method_func("toString", 0, fn(this_val, args) raise {
        // Validate this is a number
        let n : Double = match this_val {
          Number(v) => v
          Object(data) =>
            if data.class_name == "Number" {
              match data.properties.get("[[NumberData]]") {
                Some(Number(v)) => v
                _ =>
                  raise @errors.TypeError(
                    message="Number.prototype.toString requires that 'this' be a Number",
                  )
              }
            } else {
              raise @errors.TypeError(
                message="Number.prototype.toString requires that 'this' be a Number",
              )
            }
          _ =>
            raise @errors.TypeError(
              message="Number.prototype.toString requires that 'this' be a Number",
            )
        }
        let radix = if args.length() > 0 && not(args[0] is Undefined) {
          let r = to_number(args[0]).to_int()
          if r < 2 || r > 36 {
            raise @errors.RangeError(
              message="toString() radix must be between 2 and 36",
            )
          }
          r
        } else {
          10
        }
        if n.is_nan() {
          return String_("NaN")
        }
        if n.is_inf() {
          return String_(if n > 0.0 { "Infinity" } else { "-Infinity" })
        }
        if radix == 10 {
          return String_(n.to_string())
        }
        // Integer to string in given radix
        let is_neg = n < 0.0
        let mut val = n.abs().floor()
        if val == 0.0 {
          return String_("0")
        }
        let chars : Array[Char] = []
        let digits = "0123456789abcdefghijklmnopqrstuvwxyz"
        let digit_chars = digits.to_array()
        while val > 0.0 {
          let remainder = (val % radix.to_double()).to_int()
          chars.push(digit_chars[remainder])
          val = (val / radix.to_double()).floor()
        }
        chars.rev_in_place()
        let buf = StringBuilder::new()
        if is_neg {
          buf.write_string("-")
        }
        for c in chars {
          buf.write_char(c)
        }
        String_(buf.to_string())
      })
  number_proto_props["valueOf"] = make_method_func("valueOf", 0, fn(this_val, _args) raise {
        match this_val {
          Number(_) => this_val
          Object(data) =>
            if data.class_name == "Number" {
              match data.properties.get("[[NumberData]]") {
                Some(Number(v)) => Number(v)
                _ =>
                  raise @errors.TypeError(
                    message="Number.prototype.valueOf requires that 'this' be a Number",
                  )
              }
            } else {
              raise @errors.TypeError(
                message="Number.prototype.valueOf requires that 'this' be a Number",
              )
            }
          _ =>
            raise @errors.TypeError(
              message="Number.prototype.valueOf requires that 'this' be a Number",
            )
        }
      })
  number_proto_props["toPrecision"] = make_method_func("toPrecision", 1, fn(this_val, args) raise {
        let n = to_number(this_val)
        // If no argument or undefined, just return toString result
        if args.length() == 0 {
          return String_(n.to_string())
        }
        match args[0] {
          Undefined => return String_(n.to_string())
          _ => ()
        }
        let precision = to_number(args[0]).to_int()
        if precision < 1 || precision > 100 {
          raise @errors.RangeError(
            message="toPrecision() argument must be between 1 and 100",
          )
        }
        if n.is_nan() {
          return String_("NaN")
        }
        if n.is_inf() {
          return String_(if n > 0.0 { "Infinity" } else { "-Infinity" })
        }
        // Use exponential format when needed
        let is_neg = n < 0.0
        let abs_n = n.abs()
        if abs_n == 0.0 {
          let buf = StringBuilder::new()
          if is_neg {
            buf.write_string("-")
          }
          buf.write_char('0')
          if precision > 1 {
            buf.write_char('.')
            for _i = 1; _i < precision; _i = _i + 1 {
              buf.write_char('0')
            }
          }
          return String_(buf.to_string())
        }
        // Calculate exponent
        let log_val = @math.log10(abs_n)
        let mut exp = log_val.floor().to_int()
        // If exponent >= precision or < -6, use exponential notation
        if exp >= precision || exp < -6 {
          // Use exponential notation
          let mut mantissa = abs_n / @math.pow(10.0, exp.to_double())
          // Round mantissa and check for overflow
          let mult = @math.pow(10.0, (precision - 1).to_double())
          let rounded_mantissa = (mantissa * mult + 0.5).floor() / mult
          // If rounding caused overflow (mantissa >= 10), adjust
          if rounded_mantissa >= 10.0 {
            mantissa = rounded_mantissa / 10.0
            exp = exp + 1
          } else {
            mantissa = rounded_mantissa
          }
          let buf = StringBuilder::new()
          if is_neg {
            buf.write_string("-")
          }
          // Format mantissa with precision-1 decimal places
          let mantissa_str = format_number_precision(mantissa, precision)
          buf.write_string(mantissa_str)
          buf.write_char('e')
          if exp >= 0 {
            buf.write_char('+')
          }
          buf.write_string(exp.to_string())
          return String_(buf.to_string())
        }
        // Use fixed notation
        let decimal_places = precision - exp - 1
        let buf = StringBuilder::new()
        if is_neg {
          buf.write_string("-")
        }
        if decimal_places >= 0 {
          let multiplier = @math.pow(10.0, decimal_places.to_double())
          let shifted = abs_n * multiplier
          let rounded = (shifted + 0.5).floor()
          let int_val = rounded.to_int64()
          let int_str = int_val.to_string()
          let int_len = int_str.length()
          if int_len <= decimal_places {
            buf.write_string("0.")
            for _i = 0; _i < decimal_places - int_len; _i = _i + 1 {
              buf.write_char('0')
            }
            buf.write_string(int_str)
          } else {
            let int_part_len = int_len - decimal_places
            let chars = int_str.to_array()
            for i = 0; i < int_part_len; i = i + 1 {
              buf.write_char(chars[i])
            }
            if decimal_places > 0 {
              buf.write_char('.')
              for i = int_part_len; i < int_len; i = i + 1 {
                buf.write_char(chars[i])
              }
            }
          }
        } else {
          let multiplier = @math.pow(10.0, (-decimal_places).to_double())
          let shifted = abs_n / multiplier
          let rounded = (shifted + 0.5).floor()
          buf.write_string((rounded * multiplier).to_int().to_string())
        }
        String_(buf.to_string())
      })
  number_proto_props["toExponential"] = make_method_func("toExponential", 1, fn(this_val, args) raise {
        let n = to_number(this_val)
        if n.is_nan() {
          return String_("NaN")
        }
        if n.is_inf() {
          return String_(if n > 0.0 { "Infinity" } else { "-Infinity" })
        }
        let is_neg = n < 0.0
        let abs_n = n.abs()
        // Handle zero specially
        if abs_n == 0.0 {
          let buf = StringBuilder::new()
          if is_neg {
            buf.write_string("-")
          }
          buf.write_char('0')
          if args.length() > 0 {
            match args[0] {
              Undefined => ()
              _ => {
                let frac_digits = to_number(args[0]).to_int()
                if frac_digits < 0 || frac_digits > 100 {
                  raise @errors.RangeError(
                    message="toExponential() argument must be between 0 and 100",
                  )
                }
                if frac_digits > 0 {
                  buf.write_char('.')
                  for _i = 0; _i < frac_digits; _i = _i + 1 {
                    buf.write_char('0')
                  }
                }
              }
            }
          }
          buf.write_string("e+0")
          return String_(buf.to_string())
        }
        // Calculate exponent
        let log_val = @math.log10(abs_n)
        let mut exp = log_val.floor().to_int()
        let mut mantissa = abs_n / @math.pow(10.0, exp.to_double())
        let buf = StringBuilder::new()
        if is_neg {
          buf.write_string("-")
        }
        // Format mantissa
        if args.length() > 0 {
          match args[0] {
            Undefined => buf.write_string(mantissa.to_string())
            _ => {
              let frac_digits = to_number(args[0]).to_int()
              if frac_digits < 0 || frac_digits > 100 {
                raise @errors.RangeError(
                  message="toExponential() argument must be between 0 and 100",
                )
              }
              // Round mantissa and check for overflow
              let precision = frac_digits + 1
              let mult = @math.pow(10.0, (precision - 1).to_double())
              let rounded_mantissa = (mantissa * mult + 0.5).floor() / mult
              // If rounding caused overflow (mantissa >= 10), adjust
              if rounded_mantissa >= 10.0 {
                mantissa = rounded_mantissa / 10.0
                exp = exp + 1
              } else {
                mantissa = rounded_mantissa
              }
              let mantissa_str = format_number_precision(mantissa, precision)
              buf.write_string(mantissa_str)
            }
          }
        } else {
          buf.write_string(mantissa.to_string())
        }
        buf.write_char('e')
        if exp >= 0 {
          buf.write_char('+')
        }
        buf.write_string(exp.to_string())
        String_(buf.to_string())
      })
  number_proto_props["toLocaleString"] = make_method_func("toLocaleString", 0, fn(this_val, _args) raise {
        // Extract numeric value (same pattern as toFixed/toString)
        let n : Double = match this_val {
          Number(v) => v
          Object(data) =>
            if data.class_name == "Number" {
              match data.properties.get("[[NumberData]]") {
                Some(Number(v)) => v
                _ =>
                  raise @errors.TypeError(
                    message="Number.prototype.toLocaleString requires that 'this' be a Number",
                  )
              }
            } else {
              raise @errors.TypeError(
                message="Number.prototype.toLocaleString requires that 'this' be a Number",
              )
            }
          _ =>
            raise @errors.TypeError(
              message="Number.prototype.toLocaleString requires that 'this' be a Number",
            )
        }
        // Simple implementation: delegate to toString()
        // Full locale support would require Intl.NumberFormat (out of scope)
        String_(n.to_string())
      })
  // Per ES spec, Number.prototype has [[NumberData]] internal slot with value +0
  number_proto_props["[[NumberData]]"] = Number(0.0)
  let number_proto : Value = Object({
    properties: number_proto_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Number",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  // Store Number.prototype for ToObject wrapping
  env.def_builtin("[[NumberPrototype]]", number_proto)
  let number_props : Map[String, Value] = {}
  number_props["prototype"] = number_proto
  number_props["MAX_SAFE_INTEGER"] = Number(9007199254740991.0)
  number_props["MIN_SAFE_INTEGER"] = Number(-9007199254740991.0)
  number_props["EPSILON"] = Number(2.220446049250313e-16)
  number_props["MAX_VALUE"] = Number(1.7976931348623157e+308)
  number_props["MIN_VALUE"] = Number(5.0e-324)
  number_props["POSITIVE_INFINITY"] = Number(1.0 / 0.0)
  number_props["NEGATIVE_INFINITY"] = Number(-1.0 / 0.0)
  number_props["NaN"] = Number(0.0 / 0.0)
  number_props["isNaN"] = make_static_func("isNaN", fn(args) {
    let val = if args.length() > 0 { args[0] } else { Undefined }
    match val {
      Number(n) => Bool(n.is_nan())
      _ => Bool(false) // Number.isNaN does NOT coerce
    }
  })
  number_props["isFinite"] = make_static_func("isFinite", fn(args) {
    let val = if args.length() > 0 { args[0] } else { Undefined }
    match val {
      Number(n) => Bool(not(n.is_nan()) && not(n.is_inf()))
      _ => Bool(false) // Number.isFinite does NOT coerce
    }
  })
  number_props["isInteger"] = make_static_func("isInteger", fn(args) {
    let val = if args.length() > 0 { args[0] } else { Undefined }
    match val {
      Number(n) =>
        if n.is_nan() || n.is_inf() {
          Bool(false)
        } else {
          Bool(n.floor() == n)
        }
      _ => Bool(false)
    }
  })
  number_props["isSafeInteger"] = make_static_func("isSafeInteger", fn(args) {
    // Number.isSafeInteger() - check if value is a safe integer
    // Safe integers are integers in range -(2^53-1) to 2^53-1
    let val = if args.length() > 0 { args[0] } else { Undefined }
    match val {
      Number(n) =>
        if n.is_nan() || n.is_inf() {
          Bool(false)
        } else if n.floor() != n {
          Bool(false)
        } else {
          let max_safe = 9007199254740991.0
          Bool(n >= -max_safe && n <= max_safe)
        }
      _ => Bool(false)
    }
  })
  number_props["parseInt"] = env.get("parseInt") catch { _ => Undefined }
  number_props["parseFloat"] = env.get("parseFloat") catch { _ => Undefined }
  number_props["name"] = String_("Number")
  number_props["length"] = Number(1.0)
  // Non-writable, non-enumerable, non-configurable descriptors for constants
  let const_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
  }
  let number_descs : Map[String, PropDescriptor] = {}
  number_descs["name"] = nf_desc
  number_descs["length"] = nf_desc
  number_descs["MAX_SAFE_INTEGER"] = const_desc
  number_descs["MIN_SAFE_INTEGER"] = const_desc
  number_descs["EPSILON"] = const_desc
  number_descs["MAX_VALUE"] = const_desc
  number_descs["MIN_VALUE"] = const_desc
  number_descs["POSITIVE_INFINITY"] = const_desc
  number_descs["NEGATIVE_INFINITY"] = const_desc
  number_descs["NaN"] = const_desc
  number_descs["prototype"] = { writable: false, enumerable: false, configurable: false, getter: None, setter: None }
  let num_method_desc : PropDescriptor = { writable: true, enumerable: false, configurable: true, getter: None, setter: None }
  number_descs["isNaN"] = num_method_desc
  number_descs["isFinite"] = num_method_desc
  number_descs["isInteger"] = num_method_desc
  number_descs["isSafeInteger"] = num_method_desc
  number_descs["parseInt"] = num_method_desc
  number_descs["parseFloat"] = num_method_desc
  env.def_builtin(
    "Number",
    Object({
      properties: number_props,
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable("Number", fn(args) raise {
          // Per spec: Number() with no args returns +0, not NaN
          let n = if args.length() > 0 {
            to_number(args[0])
          } else {
            0.0
          }
          if is_constructing.val {
            // new Number(value) → boxed Number object
            Object({
              properties: { "[[NumberData]]": Number(n) },
              symbol_properties: {},
              prototype: number_proto,
              callable: None,
              class_name: "Number",
              descriptors: {},
              symbol_descriptors: {},
              extensible: true,
            })
          } else {
            Number(n)
          }
        }),
      ),
      class_name: "Function",
      descriptors: number_descs,
      symbol_descriptors: {},
      extensible: true,
    }),
  )
  // Set Number.prototype.constructor = Number
  match number_proto {
    Object(data) => {
      let ctor = env.get("Number") catch { _ => Undefined }
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
fn setup_json_builtins(env : Environment) -> Unit {
  let json_props : Map[String, Value] = {}
  let json_descs : Map[String, PropDescriptor] = {}
  let ne_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  json_props["parse"] = make_static_func_with_length("parse", 2, fn(args) raise {
    let str = if args.length() > 0 { to_js_string(args[0]) } else { "" }
    let result = json_parse(str)
    // Handle reviver
    if args.length() > 1 && is_callable(args[1]) {
      match current_interpreter.val {
        Some(interp) => {
          // Wrap in a root holder object
          let root_props : Map[String, Value] = {}
          root_props[""] = result
          let root : Value = Object({
            properties: root_props,
            symbol_properties: {},
            prototype: Null,
            callable: None,
            class_name: "Object",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
          return json_internalize(root, "", args[1], interp)
        }
        None => ()
      }
    }
    result
  })
  json_descs["parse"] = ne_desc
  json_props["stringify"] = make_interp_method_func("stringify", 3, fn(interp, _this, args) raise {
        let val = if args.length() > 0 { args[0] } else { Undefined }
        let indent = if args.length() > 2 {
          match args[2] {
            Number(n) => {
              let spaces = n.to_int()
              if spaces > 0 {
                let buf = StringBuilder::new()
                for _i = 0; _i < spaces; _i = _i + 1 {
                  buf.write_char(' ')
                }
                Some(buf.to_string())
              } else {
                None
              }
            }
            String_(s) => if s.length() > 0 { Some(s) } else { None }
            _ => None
          }
        } else {
          None
        }
        let replacer : Value? = if args.length() > 1 && is_callable(args[1]) {
          Some(args[1])
        } else {
          None
        }
        // Wrap value in root holder for replacer
        let root_props : Map[String, Value] = {}
        root_props[""] = val
        let root : Value = Object({
          properties: root_props,
          symbol_properties: {},
          prototype: Null,
          callable: None,
          class_name: "Object",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
        let seen : Array[Value] = []
        json_stringify_value(
          val, seen, indent, 0, Some(interp), replacer~, holder=root, key="",
        )
      })
  json_descs["stringify"] = ne_desc
  // Symbol.toStringTag = "JSON"
  let tostringtag_sym = get_tostringtag_symbol()
  let json_sym_props : Map[Int, Value] = {}
  let json_sym_descs : Map[Int, PropDescriptor] = {}
  json_sym_props[tostringtag_sym.id] = String_("JSON")
  json_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let obj_proto = match env.bindings.get("[[ObjectPrototype]]") {
    Some(b) => b.value
    None => Null
  }
  env.def_builtin(
    "JSON",
    Object({
      properties: json_props,
      symbol_properties: json_sym_props,
      prototype: obj_proto,
      callable: None,
      class_name: "JSON",
      descriptors: json_descs,
      symbol_descriptors: json_sym_descs,
      extensible: true,
    }),
  )
}

///|
fn json_parse(input : String) -> Value raise Error {
  let chars = input.to_array()
  let len = chars.length()
  let pos : Array[Int] = [0] // mutable position
  fn skip_ws() -> Unit {
    while pos[0] < len {
      let c = chars[pos[0]]
      if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
        pos[0] += 1
      } else {
        break
      }
    }
  }

  letrec parse_value = fn() -> Value raise Error {
    skip_ws()
    if pos[0] >= len {
      raise @errors.SyntaxError(message="Unexpected end of JSON input")
    }
    let c = chars[pos[0]]
    if c == '"' {
      parse_string()
    } else if c == '{' {
      parse_object()
    } else if c == '[' {
      parse_array()
    } else if c == 't' {
      if pos[0] + 4 <= len &&
        chars[pos[0] + 1] == 'r' &&
        chars[pos[0] + 2] == 'u' &&
        chars[pos[0] + 3] == 'e' {
        pos[0] += 4
        Bool(true)
      } else {
        raise @errors.SyntaxError(
          message="Unexpected token in JSON at position \{pos[0]}",
        )
      }
    } else if c == 'f' {
      if pos[0] + 5 <= len &&
        chars[pos[0] + 1] == 'a' &&
        chars[pos[0] + 2] == 'l' &&
        chars[pos[0] + 3] == 's' &&
        chars[pos[0] + 4] == 'e' {
        pos[0] += 5
        Bool(false)
      } else {
        raise @errors.SyntaxError(
          message="Unexpected token in JSON at position \{pos[0]}",
        )
      }
    } else if c == 'n' {
      if pos[0] + 4 <= len &&
        chars[pos[0] + 1] == 'u' &&
        chars[pos[0] + 2] == 'l' &&
        chars[pos[0] + 3] == 'l' {
        pos[0] += 4
        Null
      } else {
        raise @errors.SyntaxError(
          message="Unexpected token in JSON at position \{pos[0]}",
        )
      }
    } else if c == '-' || (c >= '0' && c <= '9') {
      parse_number()
    } else {
      raise @errors.SyntaxError(
        message="Unexpected token in JSON at position \{pos[0]}",
      )
    }
  }
  and parse_string = fn() -> Value raise Error {
    pos[0] += 1 // skip opening "
    let buf = StringBuilder::new()
    while pos[0] < len {
      let ch = chars[pos[0]]
      if ch == '"' {
        pos[0] += 1
        return String_(buf.to_string())
      }
      if ch == '\\' {
        pos[0] += 1
        if pos[0] >= len {
          raise @errors.SyntaxError(message="Unexpected end of JSON input")
        }
        let esc = chars[pos[0]]
        match esc {
          '"' => buf.write_char('"')
          '\\' => buf.write_char('\\')
          '/' => buf.write_char('/')
          'b' => buf.write_char('\u0008')
          'f' => buf.write_char('\u000C')
          'n' => buf.write_char('\n')
          'r' => buf.write_char('\r')
          't' => buf.write_char('\t')
          'u' =>
            if pos[0] + 4 < len {
              let mut code = 0
              for _j = 0; _j < 4; _j = _j + 1 {
                pos[0] += 1
                let hex_c = chars[pos[0]]
                let d = char_to_digit(hex_c, 16)
                if d < 0 {
                  raise @errors.SyntaxError(
                    message="Invalid unicode escape in JSON",
                  )
                }
                code = code * 16 + d
              }
              buf.write_char(code.unsafe_to_char())
            } else {
              raise @errors.SyntaxError(
                message="Invalid unicode escape in JSON",
              )
            }
          _ =>
            raise @errors.SyntaxError(
              message="Invalid escape character in JSON",
            )
        }
      } else {
        if ch.to_int() < 32 {
          raise @errors.SyntaxError(
            message="Unexpected control character in JSON",
          )
        }
        buf.write_char(ch)
      }
      pos[0] += 1
    }
    raise @errors.SyntaxError(message="Unterminated string in JSON")
  }
  and parse_number = fn() -> Value raise Error {
    let start = pos[0]
    if pos[0] < len && chars[pos[0]] == '-' {
      pos[0] += 1
    }
    while pos[0] < len && chars[pos[0]] >= '0' && chars[pos[0]] <= '9' {
      pos[0] += 1
    }
    if pos[0] < len && chars[pos[0]] == '.' {
      pos[0] += 1
      while pos[0] < len && chars[pos[0]] >= '0' && chars[pos[0]] <= '9' {
        pos[0] += 1
      }
    }
    if pos[0] < len && (chars[pos[0]] == 'e' || chars[pos[0]] == 'E') {
      pos[0] += 1
      if pos[0] < len && (chars[pos[0]] == '+' || chars[pos[0]] == '-') {
        pos[0] += 1
      }
      while pos[0] < len && chars[pos[0]] >= '0' && chars[pos[0]] <= '9' {
        pos[0] += 1
      }
    }
    let buf = StringBuilder::new()
    for i = start; i < pos[0]; i = i + 1 {
      buf.write_char(chars[i])
    }
    let n = @strconv.parse_double(buf.to_string()) catch {
      _ => raise @errors.SyntaxError(message="Invalid number in JSON")
    }
    Number(n)
  }
  and parse_object = fn() -> Value raise Error {
    pos[0] += 1 // skip {
    let properties : Map[String, Value] = {}
    skip_ws()
    if pos[0] < len && chars[pos[0]] == '}' {
      pos[0] += 1
      return Object({
        properties,
        symbol_properties: {},
        prototype: Null,
        callable: None,
        class_name: "Object",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    }
    while true {
      skip_ws()
      if pos[0] >= len || chars[pos[0]] != '"' {
        raise @errors.SyntaxError(
          message="Expected property name in JSON at position \{pos[0]}",
        )
      }
      let key = match parse_string() {
        String_(s) => s
        _ => ""
      }
      skip_ws()
      if pos[0] >= len || chars[pos[0]] != ':' {
        raise @errors.SyntaxError(
          message="Expected ':' in JSON at position \{pos[0]}",
        )
      }
      pos[0] += 1
      let value = parse_value()
      properties[key] = value
      skip_ws()
      if pos[0] < len && chars[pos[0]] == ',' {
        pos[0] += 1
      } else {
        break
      }
    }
    skip_ws()
    if pos[0] >= len || chars[pos[0]] != '}' {
      raise @errors.SyntaxError(
        message="Expected '}' in JSON at position \{pos[0]}",
      )
    }
    pos[0] += 1
    Object({
      properties,
      symbol_properties: {},
      prototype: Null,
      callable: None,
      class_name: "Object",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    })
  }
  and parse_array = fn() -> Value raise Error {
    pos[0] += 1 // skip [
    let elements : Array[Value] = []
    skip_ws()
    if pos[0] < len && chars[pos[0]] == ']' {
      pos[0] += 1
      return Array({ elements, })
    }
    while true {
      let val = parse_value()
      elements.push(val)
      skip_ws()
      if pos[0] < len && chars[pos[0]] == ',' {
        pos[0] += 1
      } else {
        break
      }
    }
    skip_ws()
    if pos[0] >= len || chars[pos[0]] != ']' {
      raise @errors.SyntaxError(
        message="Expected ']' in JSON at position \{pos[0]}",
      )
    }
    pos[0] += 1
    Array({ elements, })
  }

  let result = parse_value()
  skip_ws()
  if pos[0] < len {
    raise @errors.SyntaxError(
      message="Unexpected non-whitespace character after JSON at position \{pos[0]}",
    )
  }
  result
}

///|
/// InternalizeJSONProperty - walks the parsed value and calls the reviver
fn json_internalize(
  holder : Value,
  name : String,
  reviver : Value,
  interp : Interpreter,
) -> Value raise Error {
  let val = match holder {
    Object(data) =>
      match data.properties.get(name) {
        Some(v) => v
        None => Undefined
      }
    Array(arr_data) => {
      let idx = @strconv.parse_int(name) catch { _ => -1 }
      if idx >= 0 && idx < arr_data.elements.length() {
        arr_data.elements[idx]
      } else {
        Undefined
      }
    }
    _ => Undefined
  }
  // Recurse into objects and arrays
  match val {
    Object(data) => {
      let keys : Array[String] = []
      for key, _ in data.properties {
        keys.push(key)
      }
      for key in keys {
        let new_val = json_internalize(val, key, reviver, interp)
        match new_val {
          Undefined =>
            // Delete the property
            data.properties.remove(key)
          _ => data.properties[key] = new_val
        }
      }
    }
    Array(arr_data) => {
      for i = 0; i < arr_data.elements.length(); i = i + 1 {
        let new_val = json_internalize(
          val,
          i.to_string(),
          reviver,
          interp,
        )
        match new_val {
          Undefined => arr_data.elements[i] = Undefined
          _ => arr_data.elements[i] = new_val
        }
      }
    }
    _ => ()
  }
  // Call reviver with (holder, name, val)
  interp.call_value(
    reviver,
    holder,
    [String_(name), val],
    @token.Loc::default(),
  )
}

///|
fn json_stringify_value(
  val : Value,
  seen : Array[Value],
  indent : String?,
  depth : Int,
  interp : Interpreter?,
  replacer? : Value? = None,
  holder? : Value = Undefined,
  key? : String = "",
) -> Value raise Error {
  // Step 1: Apply replacer function if provided
  let val = match replacer {
    Some(replacer_fn) =>
      match interp {
        Some(ip) =>
          ip.call_value(
            replacer_fn,
            holder,
            [String_(key), val],
            @token.Loc::default(),
          )
        None => val
      }
    None => val
  }
  match val {
    Undefined => Undefined
    Null => String_("null")
    Bool(b) => String_(b.to_string())
    Number(n) =>
      if n.is_nan() || n.is_inf() {
        String_("null")
      } else {
        String_(val.to_string())
      }
    String_(s) => String_(json_escape_string(s))
    Symbol(_) => Undefined // Symbols are omitted from JSON
    Map(_) => String_("{}") // Maps serialize as empty objects
    Set(_) => String_("{}") // Sets serialize as empty objects
    Promise(_) => String_("{}") // Promises serialize as empty objects
    Proxy(proxy_data) =>
      // Unwrap proxy to its target and serialize that
      match proxy_data.target {
        Some(target) =>
          json_stringify_value(target, seen, indent, depth, interp, replacer~)
        None => String_("{}")
      }
    Array(data) => {
      // Cycle detection
      for s in seen {
        match s {
          Array(sd) =>
            if physical_equal(sd, data) {
              raise @errors.TypeError(
                message="Converting circular structure to JSON",
              )
            }
          _ => ()
        }
      }
      seen.push(val)
      let new_depth = depth + 1
      let buf = StringBuilder::new()
      buf.write_char('[')
      let mut first = true
      for idx, el in data.elements {
        let stringified = json_stringify_value(
          el, seen, indent, new_depth, interp, replacer~,
          holder=val, key=idx.to_string(),
        )
        match stringified {
          Undefined => {
            if not(first) {
              buf.write_char(',')
              match indent {
                Some(_) => ()
                None => ()
              }
            }
            first = false
            match indent {
              Some(ind) => {
                buf.write_char('\n')
                for _i = 0; _i < new_depth; _i = _i + 1 {
                  buf.write_string(ind)
                }
              }
              None => ()
            }
            buf.write_string("null")
          }
          String_(s) => {
            if not(first) {
              buf.write_char(',')
            }
            first = false
            match indent {
              Some(ind) => {
                buf.write_char('\n')
                for _i = 0; _i < new_depth; _i = _i + 1 {
                  buf.write_string(ind)
                }
              }
              None => ()
            }
            buf.write_string(s)
          }
          _ => ()
        }
      }
      match indent {
        Some(ind) =>
          if data.elements.length() > 0 {
            buf.write_char('\n')
            for _i = 0; _i < depth; _i = _i + 1 {
              buf.write_string(ind)
            }
          }
        None => ()
      }
      buf.write_char(']')
      let _ = seen.pop()
      String_(buf.to_string())
    }
    Object(data) =>
      match data.callable {
        Some(_) => Undefined // Functions are not serialized
        None => {
          // Unwrap boxed primitives per spec (SerializeJSONProperty step 4)
          if data.class_name == "Number" {
            match data.properties.get("[[NumberData]]") {
              Some(Number(n)) =>
                return if n.is_nan() || n.is_inf() {
                  String_("null")
                } else {
                  String_(Number(n).to_string())
                }
              _ => ()
            }
          } else if data.class_name == "String" {
            match data.properties.get("[[StringData]]") {
              Some(String_(s)) =>
                return String_(json_escape_string(s))
              _ => ()
            }
          } else if data.class_name == "Boolean" {
            match data.properties.get("[[BooleanData]]") {
              Some(Bool(b)) => return String_(b.to_string())
              _ => ()
            }
          }
          // Check for toJSON method by walking the full prototype chain
          let mut to_json_fn : Value? = None
          let mut cur : Value? = Some(val)
          while to_json_fn is None {
            match cur {
              Some(Object(obj_data)) =>
                match obj_data.properties.get("toJSON") {
                  Some(v) => to_json_fn = Some(v)
                  None => cur = Some(obj_data.prototype)
                }
              _ => break
            }
          }
          match to_json_fn {
            Some(Object(to_json_data)) =>
              match to_json_data.callable {
                Some(_) => {
                  let to_json_obj : Value = Object(to_json_data)
                  let json_val : Value? = match interp {
                    Some(ip) =>
                      Some(
                        ip.call_value(
                          to_json_obj,
                          val,
                          [],
                          @token.Loc::default(),
                        ),
                      )
                    None =>
                      // Fallback for calls without interpreter access
                      match to_json_data.callable {
                        Some(MethodCallable(_, func)) => Some(func(val, []))
                        Some(NativeCallable(_, func)) => Some(func([]))
                        Some(NonConstructableCallable(_, func)) =>
                          Some(func([]))
                        _ => None // cannot call without interpreter, skip
                      }
                  }
                  match json_val {
                    Some(v) =>
                      return json_stringify_value(
                        v, seen, indent, depth, interp, replacer~,
                      )
                    None => ()
                  }
                }
                None => ()
              }
            _ => ()
          }
          // Cycle detection
          for s in seen {
            match s {
              Object(sd) =>
                if physical_equal(sd, data) {
                  raise @errors.TypeError(
                    message="Converting circular structure to JSON",
                  )
                }
              _ => ()
            }
          }
          seen.push(val)
          let new_depth = depth + 1
          let buf = StringBuilder::new()
          buf.write_char('{')
          let mut first = true
          let sorted_keys = sort_property_keys(data.properties)
          for k in sorted_keys {
            // Skip internal properties (e.g., [[DateValue]], [[NumberData]])
            if k.has_prefix("[[") {
              continue
            }
            // Skip non-enumerable properties
            let enumerable = match data.descriptors.get(k) {
              Some(d) => d.enumerable
              None => true
            }
            if not(enumerable) {
              continue
            }
            let v = match data.properties.get(k) {
              Some(v) => v
              None => continue
            }
            let stringified = json_stringify_value(
              v, seen, indent, new_depth, interp, replacer~,
              holder=val, key=k,
            )
            match stringified {
              Undefined => () // Skip undefined values
              String_(s) => {
                if not(first) {
                  buf.write_char(',')
                }
                first = false
                match indent {
                  Some(ind) => {
                    buf.write_char('\n')
                    for _i = 0; _i < new_depth; _i = _i + 1 {
                      buf.write_string(ind)
                    }
                  }
                  None => ()
                }
                buf.write_string(json_escape_string(k))
                buf.write_char(':')
                match indent {
                  Some(_) => buf.write_char(' ')
                  None => ()
                }
                buf.write_string(s)
              }
              _ => ()
            }
          }
          match indent {
            Some(ind) =>
              if not(first) {
                buf.write_char('\n')
                for _i = 0; _i < depth; _i = _i + 1 {
                  buf.write_string(ind)
                }
              }
            None => ()
          }
          buf.write_char('}')
          let _ = seen.pop()
          String_(buf.to_string())
        }
      }
  }
}

///|

///|
pub fn get_number_method(num_val : Value, prop : String) -> Value {
  match prop {
    "toFixed" =>
      make_method_func("toFixed", 1, fn(this_val, args) raise {
            let n = to_number(this_val)
            let digits = if args.length() > 0 {
              to_number(args[0]).to_int()
            } else {
              0
            }
            if digits < 0 || digits > 100 {
              raise @errors.RangeError(
                message="toFixed() digits argument must be between 0 and 100",
              )
            }
            if n.is_nan() {
              return String_("NaN")
            }
            if n.is_inf() {
              return String_(if n > 0.0 { "Infinity" } else { "-Infinity" })
            }
            if digits == 0 {
              let rounded = if n >= 0.0 {
                (n + 0.5).floor()
              } else {
                -(-n + 0.5).floor()
              }
              return String_(rounded.to_int().to_string())
            }
            let multiplier = @math.pow(10.0, digits.to_double())
            let shifted = n * multiplier
            let rounded = if shifted >= 0.0 {
              (shifted + 0.5).floor()
            } else {
              -(-shifted + 0.5).floor()
            }
            let rounded_abs = rounded.abs()
            let int_part_abs = (rounded_abs / multiplier).floor()
            let frac_abs = rounded_abs - int_part_abs * multiplier
            let buf = StringBuilder::new()
            if rounded < 0.0 || (n < 0.0 && rounded == 0.0) {
              buf.write_string("-")
            }
            buf.write_string(int_part_abs.to_int().to_string())
            buf.write_string(".")
            let frac_str = frac_abs.to_int().to_string()
            for _i = 0; _i < digits - frac_str.length(); _i = _i + 1 {
              buf.write_string("0")
            }
            buf.write_string(frac_str)
            String_(buf.to_string())
          })
    "toString" =>
      make_method_func("toString", 0, fn(this_val, args) raise {
            let n = to_number(this_val)
            let radix = if args.length() > 0 {
              to_number(args[0]).to_int()
            } else {
              10
            }
            if radix < 2 || radix > 36 {
              raise @errors.RangeError(
                message="toString() radix must be between 2 and 36",
              )
            }
            if n.is_nan() {
              return String_("NaN")
            }
            if n.is_inf() {
              return String_(if n > 0.0 { "Infinity" } else { "-Infinity" })
            }
            if radix == 10 {
              return String_(num_val.to_string())
            }
            let is_neg = n < 0.0
            let mut val = n.abs().floor()
            if val == 0.0 {
              return String_("0")
            }
            let digits_arr : Array[Char] = []
            let digit_str = "0123456789abcdefghijklmnopqrstuvwxyz"
            let digit_chars = digit_str.to_array()
            while val > 0.0 {
              let remainder = (val % radix.to_double()).to_int()
              digits_arr.push(digit_chars[remainder])
              val = (val / radix.to_double()).floor()
            }
            digits_arr.rev_in_place()
            let buf = StringBuilder::new()
            if is_neg {
              buf.write_string("-")
            }
            for c in digits_arr {
              buf.write_char(c)
            }
            String_(buf.to_string())
          })
    "valueOf" =>
      make_method_func("valueOf", 0, fn(this_val, _args) raise {
            Number(to_number(this_val))
          })
    "toPrecision" =>
      make_method_func("toPrecision", 1, fn(this_val, args) raise {
            let n = to_number(this_val)
            if args.length() == 0 {
              return String_(n.to_string())
            }
            match args[0] {
              Undefined => return String_(n.to_string())
              _ => ()
            }
            let precision = to_number(args[0]).to_int()
            if precision < 1 || precision > 100 {
              raise @errors.RangeError(
                message="toPrecision() argument must be between 1 and 100",
              )
            }
            if n.is_nan() {
              return String_("NaN")
            }
            if n.is_inf() {
              return String_(if n > 0.0 { "Infinity" } else { "-Infinity" })
            }
            let is_neg = n < 0.0
            let abs_n = n.abs()
            if abs_n == 0.0 {
              let buf = StringBuilder::new()
              if is_neg {
                buf.write_string("-")
              }
              buf.write_char('0')
              if precision > 1 {
                buf.write_char('.')
                for _i = 1; _i < precision; _i = _i + 1 {
                  buf.write_char('0')
                }
              }
              return String_(buf.to_string())
            }
            let log_val = @math.log10(abs_n)
            let mut exp = log_val.floor().to_int()
            if exp >= precision || exp < -6 {
              let mut mantissa = abs_n / @math.pow(10.0, exp.to_double())
              // Round mantissa and check for overflow
              let mult = @math.pow(10.0, (precision - 1).to_double())
              let rounded_mantissa = (mantissa * mult + 0.5).floor() / mult
              if rounded_mantissa >= 10.0 {
                mantissa = rounded_mantissa / 10.0
                exp = exp + 1
              } else {
                mantissa = rounded_mantissa
              }
              let buf = StringBuilder::new()
              if is_neg {
                buf.write_string("-")
              }
              let mantissa_str = format_number_precision(mantissa, precision)
              buf.write_string(mantissa_str)
              buf.write_char('e')
              if exp >= 0 {
                buf.write_char('+')
              }
              buf.write_string(exp.to_string())
              return String_(buf.to_string())
            }
            let decimal_places = precision - exp - 1
            let buf = StringBuilder::new()
            if is_neg {
              buf.write_string("-")
            }
            if decimal_places >= 0 {
              let multiplier = @math.pow(10.0, decimal_places.to_double())
              let shifted = abs_n * multiplier
              let rounded = (shifted + 0.5).floor()
              let int_val = rounded.to_int64()
              let int_str = int_val.to_string()
              let int_len = int_str.length()
              if int_len <= decimal_places {
                buf.write_string("0.")
                for _i = 0; _i < decimal_places - int_len; _i = _i + 1 {
                  buf.write_char('0')
                }
                buf.write_string(int_str)
              } else {
                let int_part_len = int_len - decimal_places
                let chars = int_str.to_array()
                for i = 0; i < int_part_len; i = i + 1 {
                  buf.write_char(chars[i])
                }
                if decimal_places > 0 {
                  buf.write_char('.')
                  for i = int_part_len; i < int_len; i = i + 1 {
                    buf.write_char(chars[i])
                  }
                }
              }
            } else {
              let multiplier = @math.pow(10.0, (-decimal_places).to_double())
              let shifted = abs_n / multiplier
              let rounded = (shifted + 0.5).floor()
              buf.write_string((rounded * multiplier).to_int().to_string())
            }
            String_(buf.to_string())
          })
    "toExponential" =>
      make_method_func("toExponential", 1, fn(this_val, args) raise {
            let n = to_number(this_val)
            if n.is_nan() {
              return String_("NaN")
            }
            if n.is_inf() {
              return String_(if n > 0.0 { "Infinity" } else { "-Infinity" })
            }
            let is_neg = n < 0.0
            let abs_n = n.abs()
            if abs_n == 0.0 {
              let buf = StringBuilder::new()
              if is_neg {
                buf.write_string("-")
              }
              buf.write_char('0')
              if args.length() > 0 {
                match args[0] {
                  Undefined => ()
                  _ => {
                    let frac_digits = to_number(args[0]).to_int()
                    if frac_digits < 0 || frac_digits > 100 {
                      raise @errors.RangeError(
                        message="toExponential() argument must be between 0 and 100",
                      )
                    }
                    if frac_digits > 0 {
                      buf.write_char('.')
                      for _i = 0; _i < frac_digits; _i = _i + 1 {
                        buf.write_char('0')
                      }
                    }
                  }
                }
              }
              buf.write_string("e+0")
              return String_(buf.to_string())
            }
            let log_val = @math.log10(abs_n)
            let mut exp = log_val.floor().to_int()
            let mut mantissa = abs_n / @math.pow(10.0, exp.to_double())
            let buf = StringBuilder::new()
            if is_neg {
              buf.write_string("-")
            }
            if args.length() > 0 {
              match args[0] {
                Undefined => buf.write_string(mantissa.to_string())
                _ => {
                  let frac_digits = to_number(args[0]).to_int()
                  if frac_digits < 0 || frac_digits > 100 {
                    raise @errors.RangeError(
                      message="toExponential() argument must be between 0 and 100",
                    )
                  }
                  // Round mantissa and check for overflow
                  let precision = frac_digits + 1
                  let mult = @math.pow(10.0, (precision - 1).to_double())
                  let rounded_mantissa = (mantissa * mult + 0.5).floor() / mult
                  if rounded_mantissa >= 10.0 {
                    mantissa = rounded_mantissa / 10.0
                    exp = exp + 1
                  } else {
                    mantissa = rounded_mantissa
                  }
                  let mantissa_str = format_number_precision(
                    mantissa, precision,
                  )
                  buf.write_string(mantissa_str)
                }
              }
            } else {
              buf.write_string(mantissa.to_string())
            }
            buf.write_char('e')
            if exp >= 0 {
              buf.write_char('+')
            }
            buf.write_string(exp.to_string())
            String_(buf.to_string())
          })
    _ => Undefined
  }
}

///|
fn format_number_precision(n : Double, precision : Int) -> String {
  // Format a number with exactly `precision` significant digits
  // Used for toPrecision and toExponential
  // Returns mantissa only (e.g., "1.23" for 1.23, NOT including exponent)
  if precision <= 0 {
    return "0"
  }
  let abs_n = n.abs()
  if abs_n == 0.0 {
    let buf = StringBuilder::new()
    buf.write_char('0')
    if precision > 1 {
      buf.write_char('.')
      for _i = 1; _i < precision; _i = _i + 1 {
        buf.write_char('0')
      }
    }
    return buf.to_string()
  }
  // Round to precision significant digits
  let multiplier = @math.pow(10.0, (precision - 1).to_double())
  let shifted = abs_n * multiplier
  let rounded = (shifted + 0.5).floor()
  let int_val = rounded.to_int64()
  let int_str = int_val.to_string()
  let int_chars = int_str.to_array()
  // Handle rounding overflow (e.g., 9.99 with precision 2 rounds to 100)
  // When this happens, int_chars.length() > precision, and we need to truncate
  let actual_chars = if int_chars.length() > precision {
    // Rounding caused a carry, truncate to precision digits
    // The extra digit is always trailing (e.g., "100" -> "10" for precision 2)
    let truncated : Array[Char] = []
    for i = 0; i < precision; i = i + 1 {
      truncated.push(int_chars[i])
    }
    truncated
  } else {
    int_chars
  }
  let buf = StringBuilder::new()
  if actual_chars.length() == 1 {
    buf.write_char(actual_chars[0])
    if precision > 1 {
      buf.write_char('.')
      for _i = 1; _i < precision; _i = _i + 1 {
        buf.write_char('0')
      }
    }
  } else {
    buf.write_char(actual_chars[0])
    if actual_chars.length() > 1 {
      buf.write_char('.')
      for i = 1; i < actual_chars.length(); i = i + 1 {
        buf.write_char(actual_chars[i])
      }
    }
    // Pad with zeros if needed to reach precision
    let digits_so_far = actual_chars.length()
    if digits_so_far < precision {
      for _i = digits_so_far; _i < precision; _i = _i + 1 {
        buf.write_char('0')
      }
    }
  }
  buf.to_string()
}

///|
fn json_escape_string(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  let chars = s.to_array()
  for c in chars {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ =>
        if c.to_int() < 32 {
          buf.write_string("\\u")
          let code = c.to_int()
          let hex_digits = "0123456789abcdef"
          let hd = hex_digits.to_array()
          buf.write_char(hd[(code >> 12) & 0xf])
          buf.write_char(hd[(code >> 8) & 0xf])
          buf.write_char(hd[(code >> 4) & 0xf])
          buf.write_char(hd[code & 0xf])
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
fn setup_function_builtins(env : Environment) -> Unit {
  // Create Function.prototype
  let func_proto_props : Map[String, Value] = {}

  // Function.prototype.toString - returns function source or [native code]
  func_proto_props["toString"] = make_method_func("toString", 0, fn(this_val, _args) raise {
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
              Some(BoundFunc(_, _, _)) =>
                String_("function () { [native code] }")
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
              Some(ClassConstructor(name, _, _, _, _, _)) =>
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
  func_proto_props["call"] = make_interp_method_func("call", 1, fn(interp, this_val, args) raise {
        let loc = @token.Loc::default()
        let call_this : Value = if args.length() > 0 { args[0] } else { Undefined }
        let call_args : Array[Value] = []
        for i = 1; i < args.length(); i = i + 1 {
          call_args.push(args[i])
        }
        interp.call_value(this_val, call_this, call_args, loc)
      })

  // Function.prototype.apply
  func_proto_props["apply"] = make_interp_method_func("apply", 2, fn(interp, this_val, args) raise {
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
  func_proto_props["bind"] = make_interp_method_func("bind", 1, fn(_interp, this_val, args) raise {
    // Function.prototype.bind - §20.2.3.2
    // Step 1: If IsCallable(this) is false, throw a TypeError exception
    if not(is_function_value(this_val)) {
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
      if diff < 0 { 0 } else { diff }
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
      prototype: Null,
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
                    strict: func_body_has_use_strict(body),
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
                    strict: func_body_has_use_strict(body),
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
    Object(data) => data.properties["constructor"] = func_ctor
    _ => ()
  }

  // Register Function.prototype so other builtins can look it up
  env.def_builtin("[[FunctionPrototype]]", func_proto)
  // Register the same Function constructor object globally
  env.def_builtin("Function", func_ctor)
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
    } else if not(encode_component) &&
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
  dollar262_props["createRealm"] = make_interp_method_func("createRealm", 0, fn(_interp, _this_val, _args) {
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
        realm_props["detachArrayBuffer"] = make_native_func(
          "detachArrayBuffer",
          fn(a) raise {
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
          },
        )
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
  dollar262_props["evalScript"] = make_interp_method_func("evalScript", 0, fn(interp, _this_val, args) raise {
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
