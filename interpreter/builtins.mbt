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
      // Try parsing progressively longer prefixes
      let chars = trimmed.to_array()
      let mut last_valid = 0.0 / 0.0
      let buf = StringBuilder::new()
      for i = 0; i < chars.length(); i = i + 1 {
        buf.write_char(chars[i])
        let current = buf.to_string()
        try {
          let n = @strconv.parse_double(current)
          last_valid = n
        } catch {
          _ => {
            // If first char fails, check for sign
            if i == 0 && (chars[i] == '+' || chars[i] == '-') {
              continue
            }
            break
          }
        }
      }
      Number(last_valid)
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
}

///|
fn register_error_ctor(env : Environment, name : String) -> Unit {
  env.def_builtin(
    name,
    Object({
      properties: {
        "prototype": Object({
          properties: {},
          prototype: Null,
          callable: None,
          class_name: name,
        }),
      },
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
            prototype: Null,
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
