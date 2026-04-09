///|
fn trim_start(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  while start < chars.length() {
    if is_parse_whitespace(chars[start]) {
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
/// Check if a character is ECMAScript whitespace for parsing (parseInt, parseFloat, Number)
fn is_parse_whitespace(c : Char) -> Bool {
  let code = c.to_int()
  code == 0x0009 || // TAB
  code == 0x000A || // LF
  code == 0x000B || // VT
  code == 0x000C || // FF
  code == 0x000D || // CR
  code == 0x0020 || // SPACE
  code == 0x00A0 || // NBSP
  code == 0x1680 || // OGHAM SPACE MARK
  code == 0x2000 || // EN QUAD
  code == 0x2001 || // EM QUAD
  code == 0x2002 || // EN SPACE
  code == 0x2003 || // EM SPACE
  code == 0x2004 || // THREE-PER-EM SPACE
  code == 0x2005 || // FOUR-PER-EM SPACE
  code == 0x2006 || // SIX-PER-EM SPACE
  code == 0x2007 || // FIGURE SPACE
  code == 0x2008 || // PUNCTUATION SPACE
  code == 0x2009 || // THIN SPACE
  code == 0x200A || // HAIR SPACE
  code == 0x2028 || // LINE SEPARATOR
  code == 0x2029 || // PARAGRAPH SEPARATOR
  code == 0x202F || // NARROW NO-BREAK SPACE
  code == 0x205F || // MEDIUM MATHEMATICAL SPACE
  code == 0x3000 || // IDEOGRAPHIC SPACE
  code == 0xFEFF // BOM
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
  number_proto_props["toFixed"] = make_method_func("toFixed", 1, fn(
    this_val,
    args,
  ) raise {
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
    let digits = if args.length() > 0 { to_number(args[0]).to_int() } else { 0 }
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
  number_proto_props["toString"] = make_method_func("toString", 1, fn(
    this_val,
    args,
  ) raise {
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
    let radix = if args.length() > 0 && !(args[0] is Undefined) {
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
  number_proto_props["valueOf"] = make_method_func("valueOf", 0, fn(
    this_val,
    _args,
  ) raise {
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
  number_proto_props["toPrecision"] = make_method_func("toPrecision", 1, fn(
    this_val,
    args,
  ) raise {
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
  number_proto_props["toExponential"] = make_method_func("toExponential", 1, fn(
    this_val,
    args,
  ) raise {
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
  number_proto_props["toLocaleString"] = make_method_func("toLocaleString", 0, fn(
    this_val,
    _args,
  ) raise {
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
  let num_method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let number_proto_descs : Map[String, PropDescriptor] = {}
  number_proto_descs["toString"] = num_method_desc
  number_proto_descs["toLocaleString"] = num_method_desc
  number_proto_descs["toFixed"] = num_method_desc
  number_proto_descs["toExponential"] = num_method_desc
  number_proto_descs["toPrecision"] = num_method_desc
  number_proto_descs["valueOf"] = num_method_desc
  number_proto_descs["constructor"] = num_method_desc
  let number_proto : Value = Object({
    properties: number_proto_props,
    symbol_properties: {},
    prototype: get_obj_proto(),
    callable: None,
    class_name: "Number",
    descriptors: number_proto_descs,
    symbol_descriptors: {},
    extensible: true,
  })
  // Store Number.prototype for ToObject wrapping
  env.def_builtin("[[NumberPrototype]]", number_proto)
  number_prototype_ref.val = Some(number_proto)
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
  number_props["isNaN"] = make_static_func_with_length("isNaN", 1, fn(args) {
    let val = if args.length() > 0 { args[0] } else { Undefined }
    match val {
      Number(n) => Bool(n.is_nan())
      _ => Bool(false) // Number.isNaN does NOT coerce
    }
  })
  number_props["isFinite"] = make_static_func_with_length("isFinite", 1, fn(
    args,
  ) {
    let val = if args.length() > 0 { args[0] } else { Undefined }
    match val {
      Number(n) => Bool(!n.is_nan() && !n.is_inf())
      _ => Bool(false) // Number.isFinite does NOT coerce
    }
  })
  number_props["isInteger"] = make_static_func_with_length("isInteger", 1, fn(
    args,
  ) {
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
  number_props["isSafeInteger"] = make_static_func_with_length(
    "isSafeInteger",
    1,
    fn(args) {
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
    },
  )
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
  number_descs["prototype"] = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
  }
  let num_method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
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
          let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 }
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
