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

  // String(value) conversion
  env.def_builtin(
    "String",
    make_native_func("String", fn(args) {
      let val = if args.length() > 0 { args[0] } else { Undefined }
      String_(val.to_string())
    }),
  )

  // Number(value) conversion
  env.def_builtin(
    "Number",
    make_native_func("Number", fn(args) {
      let val = if args.length() > 0 { args[0] } else { Undefined }
      Number(to_number(val))
    }),
  )

  // Boolean(value) conversion
  env.def_builtin(
    "Boolean",
    make_native_func("Boolean", fn(args) {
      let val = if args.length() > 0 { args[0] } else { Undefined }
      Bool(is_truthy(val))
    }),
  )

  // Error constructors
  register_error_ctor(env, "Error")
  register_error_ctor(env, "TypeError")
  register_error_ctor(env, "ReferenceError")
  register_error_ctor(env, "SyntaxError")
  register_error_ctor(env, "RangeError")
  register_error_ctor(env, "URIError")
  register_error_ctor(env, "EvalError")

  // Object, Array constructors and built-in methods
  setup_object_builtins(env)

  // Math object
  setup_math_builtins(env)
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
    Number((n + 0.5).floor())
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
  env.def_builtin(
    "Math",
    Object({
      properties: math_props,
      prototype: Null,
      callable: None,
      class_name: "Math",
    }),
  )
}

///|
fn register_error_ctor(env : Environment, name : String) -> Unit {
  let proto_obj : Value = Object({
    properties: {},
    prototype: Null,
    callable: None,
    class_name: name,
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
          Object({
            properties: { "message": String_(message), "name": String_(name) },
            prototype: proto_obj,
            callable: None,
            class_name: name,
          })
        }),
      ),
      class_name: "Function",
    }),
  )
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
