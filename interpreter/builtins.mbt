///|
pub fn setup_builtins(env : Environment, output : Array[String]) -> Unit {
  let _ = output
  // Global constants
  env.def_builtin("NaN", Number(0.0 / 0.0))
  env.def_builtin("Infinity", Number(1.0 / 0.0))
  env.def_builtin("undefined", Undefined)

  // isNaN(value)
  env.def_builtin(
    "isNaN",
    make_native_func("isNaN", fn(args) {
      let val = if args.length() > 0 { args[0] } else { Undefined }
      let n = to_number(val)
      Bool(n.is_nan())
    }),
  )

  // isFinite(value)
  env.def_builtin(
    "isFinite",
    make_native_func("isFinite", fn(args) {
      let val = if args.length() > 0 { args[0] } else { Undefined }
      let n = to_number(val)
      Bool(not(n.is_nan()) && not(n.is_inf()))
    }),
  )

  // parseInt(string, radix?)
  env.def_builtin(
    "parseInt",
    make_native_func("parseInt", fn(args) {
      let str_val = if args.length() > 0 { args[0] } else { Undefined }
      let s = match str_val {
        String_(s) => s
        Number(n) => n.to_string()
        Bool(b) => b.to_string()
        _ => return Number(0.0 / 0.0)
      }
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
    make_native_func("parseFloat", fn(args) {
      let str_val = if args.length() > 0 { args[0] } else { Undefined }
      let s = match str_val {
        String_(s) => s
        Number(n) => return Number(n)
        Bool(_) | Null | Undefined | Object(_) | Array(_) =>
          return Number(0.0 / 0.0)
      }
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

  // String constructor with static methods
  let string_proto : Value = Object({
    properties: {},
    prototype: Null,
    callable: None,
    class_name: "String",
    descriptors: {},
    extensible: true,
  })
  env.def_builtin(
    "String",
    Object({
      properties: {
        "prototype": string_proto,
        "fromCharCode": make_native_func("fromCharCode", fn(args) {
          let buf = StringBuilder::new()
          for arg in args {
            let code = to_number(arg).to_int()
            buf.write_char(code.unsafe_to_char())
          }
          String_(buf.to_string())
        }),
      },
      prototype: Null,
      callable: Some(
        NativeCallable("String", fn(args) {
          let val = if args.length() > 0 { args[0] } else { Undefined }
          String_(val.to_string())
        }),
      ),
      class_name: "Function",
      descriptors: {},
      extensible: true,
    }),
  )

  // Number constructor with static methods and prototype
  setup_number_builtins(env)

  // Boolean(value) conversion
  env.def_builtin(
    "Boolean",
    make_native_func("Boolean", fn(args) {
      let val = if args.length() > 0 { args[0] } else { Undefined }
      Bool(is_truthy(val))
    }),
  )

  // Error constructors
  let error_proto = register_error_ctor(env, "Error", Null)
  register_error_ctor(env, "TypeError", error_proto) |> ignore
  register_error_ctor(env, "ReferenceError", error_proto) |> ignore
  register_error_ctor(env, "SyntaxError", error_proto) |> ignore
  register_error_ctor(env, "RangeError", error_proto) |> ignore
  register_error_ctor(env, "URIError", error_proto) |> ignore
  register_error_ctor(env, "EvalError", error_proto) |> ignore

  // Object, Array constructors and built-in methods
  setup_object_builtins(env)

  // Math object
  setup_math_builtins(env)

  // JSON object
  setup_json_builtins(env)

  // RegExp constructor
  env.def_builtin(
    "RegExp",
    Object({
      properties: {},
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
      descriptors: {},
      extensible: true,
    }),
  )
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
  math_props["abs"] = make_native_func("abs", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(n.abs())
  })
  math_props["floor"] = make_native_func("floor", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(n.floor())
  })
  math_props["ceil"] = make_native_func("ceil", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(n.ceil())
  })
  math_props["round"] = make_native_func("round", fn(args) {
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
  math_props["trunc"] = make_native_func("trunc", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    if n >= 0.0 {
      Number(n.floor())
    } else {
      Number(-(-n).floor())
    }
  })
  math_props["sqrt"] = make_native_func("sqrt", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(n.sqrt())
  })
  math_props["pow"] = make_native_func("pow", fn(args) {
    let base = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    let exp = if args.length() > 1 { to_number(args[1]) } else { 0.0 / 0.0 }
    Number(@math.pow(base, exp))
  })
  math_props["min"] = make_native_func("min", fn(args) {
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
  math_props["max"] = make_native_func("max", fn(args) {
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
  math_props["random"] = make_native_func("random", fn(_args) {
    let mut s = rng_state[0]
    s = s ^ (s << 13)
    s = s ^ (s.reinterpret_as_uint() >> 17).reinterpret_as_int()
    s = s ^ (s << 5)
    rng_state[0] = s
    let normalized = s.land(0x7FFFFFFF).to_double() / 2147483648.0
    Number(normalized)
  })
  math_props["sign"] = make_native_func("sign", fn(args) {
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
  math_props["log"] = make_native_func("log", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.ln(n))
  })
  math_props["log2"] = make_native_func("log2", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.log2(n))
  })
  math_props["log10"] = make_native_func("log10", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.log10(n))
  })
  math_props["sin"] = make_native_func("sin", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.sin(n))
  })
  math_props["cos"] = make_native_func("cos", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.cos(n))
  })
  math_props["tan"] = make_native_func("tan", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.tan(n))
  })
  math_props["asin"] = make_native_func("asin", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.asin(n))
  })
  math_props["acos"] = make_native_func("acos", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.acos(n))
  })
  math_props["atan"] = make_native_func("atan", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.atan(n))
  })
  math_props["atan2"] = make_native_func("atan2", fn(args) {
    let y = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    let x = if args.length() > 1 { to_number(args[1]) } else { 0.0 / 0.0 }
    Number(@math.atan2(y, x))
  })
  math_props["sinh"] = make_native_func("sinh", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.sinh(n))
  })
  math_props["cosh"] = make_native_func("cosh", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.cosh(n))
  })
  math_props["tanh"] = make_native_func("tanh", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.tanh(n))
  })
  math_props["asinh"] = make_native_func("asinh", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.asinh(n))
  })
  math_props["acosh"] = make_native_func("acosh", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.acosh(n))
  })
  math_props["atanh"] = make_native_func("atanh", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.atanh(n))
  })
  math_props["exp"] = make_native_func("exp", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.exp(n))
  })
  math_props["expm1"] = make_native_func("expm1", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.expm1(n))
  })
  math_props["log1p"] = make_native_func("log1p", fn(args) {
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
  math_props["hypot"] = make_native_func("hypot", fn(args) {
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
  math_props["cbrt"] = make_native_func("cbrt", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    if n.is_nan() || n.is_inf() || n == 0.0 {
      Number(n)
    } else {
      let sign : Double = if n < 0.0 { -1.0 } else { 1.0 }
      Number(sign * @math.pow(n.abs(), 1.0 / 3.0))
    }
  })
  math_props["clz32"] = make_native_func("clz32", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 }
    let int_val = to_int32(n)
    if int_val == 0 {
      return Number(32.0)
    }
    let uint = int_val.reinterpret_as_uint()
    let mut count = 0
    let mut mask : UInt = 2147483648 // 0x80000000
    while mask > 0 && uint.land(mask) == 0 {
      count = count + 1
      mask = mask >> 1
    }
    Number(count.to_double())
  })
  math_props["imul"] = make_native_func("imul", fn(args) {
    let a = if args.length() > 0 { to_number(args[0]) } else { 0.0 }
    let b = if args.length() > 1 { to_number(args[1]) } else { 0.0 }
    let int_a = to_int32(a)
    let int_b = to_int32(b)
    // Perform 32-bit multiplication and mask to lower 32 bits as signed
    let product = int_a.to_int64() * int_b.to_int64()
    let masked = product.land(0xFFFFFFFFL)
    // Convert to signed 32-bit
    let result = if masked > 0x7FFFFFFFL {
      (masked - 0x100000000L).to_int()
    } else {
      masked.to_int()
    }
    Number(result.to_double())
  })
  math_props["fround"] = make_native_func("fround", fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    // Round to nearest float32 (basic approximation)
    if n.is_nan() || n.is_inf() || n == 0.0 {
      Number(n)
    } else {
      // Convert to float32 and back (approximation)
      Number(Float::from_double(n).to_double())
    }
  })
  env.def_builtin(
    "Math",
    Object({
      properties: math_props,
      prototype: Null,
      callable: None,
      class_name: "Math",
      descriptors: {},
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
  let proto_props : Map[String, Value] = {}
  proto_props["name"] = String_(name)
  proto_props["message"] = String_("")
  proto_props["toString"] = make_native_func("toString", fn(_args) {
    String_(name)
  })
  let proto_obj : Value = Object({
    properties: proto_props,
    prototype: parent_proto,
    callable: None,
    class_name: name,
    descriptors: {},
    extensible: true,
  })
  env.def_builtin(
    name,
    Object({
      properties: { "prototype": proto_obj },
      prototype: Null,
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
          Object({
            properties: err_props,
            prototype: proto_obj,
            callable: None,
            class_name: name,
            descriptors: {},
            extensible: true,
          })
        }),
      ),
      class_name: "Function",
      descriptors: {},
      extensible: true,
    }),
  )
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
  let number_proto_props : Map[String, Value] = {}
  number_proto_props["toFixed"] = Object({
    properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toFixed", fn(this_val, args) {
        let n = to_number(this_val)
        let digits = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        if digits < 0 || digits > 100 {
          raise JsException(
            String_(
              "RangeError: toFixed() digits argument must be between 0 and 100",
            ),
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    extensible: true,
  })
  number_proto_props["toString"] = Object({
    properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toString", fn(this_val, args) {
        let n = to_number(this_val)
        let radix = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          10
        }
        if radix < 2 || radix > 36 {
          raise JsException(
            String_("RangeError: toString() radix must be between 2 and 36"),
          )
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    extensible: true,
  })
  number_proto_props["valueOf"] = Object({
    properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("valueOf", fn(this_val, _args) {
        Number(to_number(this_val))
      }),
    ),
    class_name: "Function",
    descriptors: {},
    extensible: true,
  })
  number_proto_props["toPrecision"] = Object({
    properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toPrecision", fn(this_val, args) {
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
          raise JsException(
            String_(
              "RangeError: toPrecision() argument must be between 1 and 100",
            ),
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
          let rounded_mantissa = ((mantissa * mult) + 0.5).floor() / mult
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    extensible: true,
  })
  number_proto_props["toExponential"] = Object({
    properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toExponential", fn(this_val, args) {
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
                  raise JsException(
                    String_(
                      "RangeError: toExponential() argument must be between 0 and 100",
                    ),
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
                raise JsException(
                  String_(
                    "RangeError: toExponential() argument must be between 0 and 100",
                  ),
                )
              }
              // Round mantissa and check for overflow
              let precision = frac_digits + 1
              let mult = @math.pow(10.0, (precision - 1).to_double())
              let rounded_mantissa = ((mantissa * mult) + 0.5).floor() / mult
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    extensible: true,
  })
  let number_proto : Value = Object({
    properties: number_proto_props,
    prototype: Null,
    callable: None,
    class_name: "Number",
    descriptors: {},
    extensible: true,
  })
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
  number_props["isNaN"] = make_native_func("isNaN", fn(args) {
    let val = if args.length() > 0 { args[0] } else { Undefined }
    match val {
      Number(n) => Bool(n.is_nan())
      _ => Bool(false) // Number.isNaN does NOT coerce
    }
  })
  number_props["isFinite"] = make_native_func("isFinite", fn(args) {
    let val = if args.length() > 0 { args[0] } else { Undefined }
    match val {
      Number(n) => Bool(not(n.is_nan()) && not(n.is_inf()))
      _ => Bool(false) // Number.isFinite does NOT coerce
    }
  })
  number_props["isInteger"] = make_native_func("isInteger", fn(args) {
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
  number_props["isSafeInteger"] = make_native_func("isSafeInteger", fn(args) {
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
  env.def_builtin(
    "Number",
    Object({
      properties: number_props,
      prototype: Null,
      callable: Some(
        NativeCallable("Number", fn(args) {
          let val = if args.length() > 0 { args[0] } else { Undefined }
          Number(to_number(val))
        }),
      ),
      class_name: "Function",
      descriptors: {},
      extensible: true,
    }),
  )
}

///|
fn setup_json_builtins(env : Environment) -> Unit {
  let json_props : Map[String, Value] = {}
  json_props["parse"] = make_native_func("parse", fn(args) {
    let str = if args.length() > 0 { args[0].to_string() } else { "" }
    json_parse(str)
  })
  json_props["stringify"] = make_native_func("stringify", fn(args) {
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
    let seen : Array[Value] = []
    json_stringify_value(val, seen, indent, 0)
  })
  env.def_builtin(
    "JSON",
    Object({
      properties: json_props,
      prototype: Null,
      callable: None,
      class_name: "JSON",
      descriptors: {},
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

  letrec parse_value = fn () -> Value raise Error {
    skip_ws()
    if pos[0] >= len {
      raise JsException(String_("SyntaxError: Unexpected end of JSON input"))
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
        raise JsException(
          String_("SyntaxError: Unexpected token in JSON at position \{pos[0]}"),
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
        raise JsException(
          String_("SyntaxError: Unexpected token in JSON at position \{pos[0]}"),
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
        raise JsException(
          String_("SyntaxError: Unexpected token in JSON at position \{pos[0]}"),
        )
      }
    } else if c == '-' || (c >= '0' && c <= '9') {
      parse_number()
    } else {
      raise JsException(
        String_("SyntaxError: Unexpected token in JSON at position \{pos[0]}"),
      )
    }
  }

  and parse_string = fn () -> Value raise Error {
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
          raise JsException(
            String_("SyntaxError: Unexpected end of JSON input"),
          )
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
                  raise JsException(
                    String_("SyntaxError: Invalid unicode escape in JSON"),
                  )
                }
                code = code * 16 + d
              }
              buf.write_char(code.unsafe_to_char())
            } else {
              raise JsException(
                String_("SyntaxError: Invalid unicode escape in JSON"),
              )
            }
          _ =>
            raise JsException(
              String_("SyntaxError: Invalid escape character in JSON"),
            )
        }
      } else {
        if ch.to_int() < 32 {
          raise JsException(
            String_("SyntaxError: Unexpected control character in JSON"),
          )
        }
        buf.write_char(ch)
      }
      pos[0] += 1
    }
    raise JsException(String_("SyntaxError: Unterminated string in JSON"))
  }

  and parse_number = fn () -> Value raise Error {
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
      _ => raise JsException(String_("SyntaxError: Invalid number in JSON"))
    }
    Number(n)
  }

  and parse_object = fn () -> Value raise Error {
    pos[0] += 1 // skip {
    let properties : Map[String, Value] = {}
    skip_ws()
    if pos[0] < len && chars[pos[0]] == '}' {
      pos[0] += 1
      return Object({
        properties,
        prototype: Null,
        callable: None,
        class_name: "Object",
        descriptors: {},
        extensible: true,
      })
    }
    while true {
      skip_ws()
      if pos[0] >= len || chars[pos[0]] != '"' {
        raise JsException(
          String_(
            "SyntaxError: Expected property name in JSON at position \{pos[0]}",
          ),
        )
      }
      let key = match parse_string() {
        String_(s) => s
        _ => ""
      }
      skip_ws()
      if pos[0] >= len || chars[pos[0]] != ':' {
        raise JsException(
          String_("SyntaxError: Expected ':' in JSON at position \{pos[0]}"),
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
      raise JsException(
        String_("SyntaxError: Expected '}' in JSON at position \{pos[0]}"),
      )
    }
    pos[0] += 1
    Object({
      properties,
      prototype: Null,
      callable: None,
      class_name: "Object",
      descriptors: {},
      extensible: true,
    })
  }

  and parse_array = fn () -> Value raise Error {
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
      raise JsException(
        String_("SyntaxError: Expected ']' in JSON at position \{pos[0]}"),
      )
    }
    pos[0] += 1
    Array({ elements, })
  }

  let result = parse_value()
  skip_ws()
  if pos[0] < len {
    raise JsException(
      String_(
        "SyntaxError: Unexpected non-whitespace character after JSON at position \{pos[0]}",
      ),
    )
  }
  result
}

///|
fn json_stringify_value(
  val : Value,
  seen : Array[Value],
  indent : String?,
  depth : Int,
) -> Value raise Error {
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
    Array(data) => {
      // Cycle detection
      for s in seen {
        match s {
          Array(sd) =>
            if physical_equal(sd, data) {
              raise JsException(
                String_("TypeError: Converting circular structure to JSON"),
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
      for el in data.elements {
        let stringified = json_stringify_value(el, seen, indent, new_depth)
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
          // Cycle detection
          for s in seen {
            match s {
              Object(sd) =>
                if physical_equal(sd, data) {
                  raise JsException(
                    String_("TypeError: Converting circular structure to JSON"),
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
          data.properties.each(fn(k, v) {
            let stringified = json_stringify_value(v, seen, indent, new_depth)
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
          })
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
      Object({
        properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("toFixed", fn(this_val, args) {
            let n = to_number(this_val)
            let digits = if args.length() > 0 {
              to_number(args[0]).to_int()
            } else {
              0
            }
            if digits < 0 || digits > 100 {
              raise JsException(
                String_(
                  "RangeError: toFixed() digits argument must be between 0 and 100",
                ),
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
          }),
        ),
        class_name: "Function",
        descriptors: {},
        extensible: true,
      })
    "toString" =>
      Object({
        properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("toString", fn(this_val, args) {
            let n = to_number(this_val)
            let radix = if args.length() > 0 {
              to_number(args[0]).to_int()
            } else {
              10
            }
            if radix < 2 || radix > 36 {
              raise JsException(
                String_("RangeError: toString() radix must be between 2 and 36"),
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
          }),
        ),
        class_name: "Function",
        descriptors: {},
        extensible: true,
      })
    "valueOf" =>
      Object({
        properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("valueOf", fn(this_val, _args) {
            Number(to_number(this_val))
          }),
        ),
        class_name: "Function",
        descriptors: {},
        extensible: true,
      })
    "toPrecision" =>
      Object({
        properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("toPrecision", fn(this_val, args) {
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
              raise JsException(
                String_(
                  "RangeError: toPrecision() argument must be between 1 and 100",
                ),
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
              let rounded_mantissa = ((mantissa * mult) + 0.5).floor() / mult
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
          }),
        ),
        class_name: "Function",
        descriptors: {},
        extensible: true,
      })
    "toExponential" =>
      Object({
        properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("toExponential", fn(this_val, args) {
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
                      raise JsException(
                        String_(
                          "RangeError: toExponential() argument must be between 0 and 100",
                        ),
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
                    raise JsException(
                      String_(
                        "RangeError: toExponential() argument must be between 0 and 100",
                      ),
                    )
                  }
                  // Round mantissa and check for overflow
                  let precision = frac_digits + 1
                  let mult = @math.pow(10.0, (precision - 1).to_double())
                  let rounded_mantissa = ((mantissa * mult) + 0.5).floor() / mult
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
          }),
        ),
        class_name: "Function",
        descriptors: {},
        extensible: true,
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
