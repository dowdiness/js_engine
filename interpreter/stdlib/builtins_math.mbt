///|
fn setup_math_builtins(env : Environment) -> Unit {
  let math_props : Map[String, Value] = {}
  math_props["PI"] = Value::Number(3.141592653589793)
  math_props["E"] = Value::Number(2.718281828459045)
  math_props["LN2"] = Value::Number(0.6931471805599453)
  math_props["LN10"] = Value::Number(2.302585092994046)
  math_props["LOG2E"] = Value::Number(1.4426950408889634)
  math_props["LOG10E"] = Value::Number(0.4342944819032518)
  math_props["SQRT2"] = Value::Number(1.4142135623730951)
  math_props["SQRT1_2"] = Value::Number(0.7071067811865476)
  math_props["abs"] = @runtime.make_static_func_with_length("abs", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(n.abs())
  })
  math_props["floor"] = @runtime.make_static_func_with_length("floor", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(n.floor())
  })
  math_props["ceil"] = @runtime.make_static_func_with_length("ceil", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(n.ceil())
  })
  math_props["round"] = @runtime.make_static_func_with_length("round", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    if n.is_nan() || n.is_inf() || n == 0.0 {
      Value::Number(n)
    } else {
      let rounded = (n + 0.5).floor()
      if rounded == 0.0 && n < 0.0 {
        Value::Number(-0.0)
      } else {
        Value::Number(rounded)
      }
    }
  })
  math_props["trunc"] = @runtime.make_static_func_with_length("trunc", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    if n >= 0.0 {
      Value::Number(n.floor())
    } else {
      Value::Number(-(-n).floor())
    }
  })
  math_props["sqrt"] = @runtime.make_static_func_with_length("sqrt", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(n.sqrt())
  })
  math_props["pow"] = @runtime.make_static_func_with_length("pow", 2, fn(
    args,
  ) raise {
    let base = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    let exp = if args.length() > 1 {
      @runtime.to_number(args[1])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.pow(base, exp))
  })
  math_props["min"] = @runtime.make_static_func_with_length("min", 2, fn(
    args,
  ) raise {
    if args.length() == 0 {
      return Value::Number(1.0 / 0.0)
    }
    let mut result = @runtime.to_number(args[0])
    for i = 1; i < args.length(); i = i + 1 {
      let n = @runtime.to_number(args[i])
      if n.is_nan() {
        return Value::Number(0.0 / 0.0)
      }
      if n < result {
        result = n
      }
    }
    Value::Number(result)
  })
  math_props["max"] = @runtime.make_static_func_with_length("max", 2, fn(
    args,
  ) raise {
    if args.length() == 0 {
      return Value::Number(-1.0 / 0.0)
    }
    let mut result = @runtime.to_number(args[0])
    for i = 1; i < args.length(); i = i + 1 {
      let n = @runtime.to_number(args[i])
      if n.is_nan() {
        return Value::Number(0.0 / 0.0)
      }
      if n > result {
        result = n
      }
    }
    Value::Number(result)
  })
  let rng_state : Array[Int] = [123456789]
  math_props["random"] = @runtime.make_static_func_with_length("random", 0, fn(
    _args,
  ) {
    let mut s = rng_state[0]
    s = s ^ (s << 13)
    s = s ^ (s.reinterpret_as_uint() >> 17).reinterpret_as_int()
    s = s ^ (s << 5)
    rng_state[0] = s
    let normalized = (s & 0x7FFFFFFF).to_double() / 2147483648.0
    Value::Number(normalized)
  })
  math_props["sign"] = @runtime.make_static_func_with_length("sign", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    if n.is_nan() {
      Value::Number(0.0 / 0.0)
    } else if n > 0.0 {
      Value::Number(1.0)
    } else if n < 0.0 {
      Value::Number(-1.0)
    } else {
      Value::Number(n) // preserves +0/-0
    }
  })
  math_props["log"] = @runtime.make_static_func_with_length("log", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.ln(n))
  })
  math_props["log2"] = @runtime.make_static_func_with_length("log2", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.log2(n))
  })
  math_props["log10"] = @runtime.make_static_func_with_length("log10", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.log10(n))
  })
  math_props["sin"] = @runtime.make_static_func_with_length("sin", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.sin(n))
  })
  math_props["cos"] = @runtime.make_static_func_with_length("cos", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.cos(n))
  })
  math_props["tan"] = @runtime.make_static_func_with_length("tan", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.tan(n))
  })
  math_props["asin"] = @runtime.make_static_func_with_length("asin", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.asin(n))
  })
  math_props["acos"] = @runtime.make_static_func_with_length("acos", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.acos(n))
  })
  math_props["atan"] = @runtime.make_static_func_with_length("atan", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.atan(n))
  })
  math_props["atan2"] = @runtime.make_static_func_with_length("atan2", 2, fn(
    args,
  ) raise {
    let y = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    let x = if args.length() > 1 {
      @runtime.to_number(args[1])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.atan2(y, x))
  })
  math_props["sinh"] = @runtime.make_static_func_with_length("sinh", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.sinh(n))
  })
  math_props["cosh"] = @runtime.make_static_func_with_length("cosh", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.cosh(n))
  })
  math_props["tanh"] = @runtime.make_static_func_with_length("tanh", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.tanh(n))
  })
  math_props["asinh"] = @runtime.make_static_func_with_length("asinh", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.asinh(n))
  })
  math_props["acosh"] = @runtime.make_static_func_with_length("acosh", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.acosh(n))
  })
  math_props["atanh"] = @runtime.make_static_func_with_length("atanh", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.atanh(n))
  })
  math_props["exp"] = @runtime.make_static_func_with_length("exp", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.exp(n))
  })
  math_props["expm1"] = @runtime.make_static_func_with_length("expm1", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    Value::Number(@math.expm1(n))
  })
  math_props["log1p"] = @runtime.make_static_func_with_length("log1p", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    // log1p(x) = ln(1 + x), more accurate for small x
    if n.is_nan() || n < -1.0 {
      Value::Number(0.0 / 0.0)
    } else if n == -1.0 {
      Value::Number(-1.0 / 0.0)
    } else if n == 0.0 || n.is_inf() {
      Value::Number(n)
    } else {
      Value::Number(@math.ln(1.0 + n))
    }
  })
  math_props["hypot"] = @runtime.make_static_func_with_length("hypot", 2, fn(
    args,
  ) raise {
    if args.length() == 0 {
      return Value::Number(0.0)
    }
    let mut sum = 0.0
    for arg in args {
      let n = @runtime.to_number(arg)
      if n.is_inf() {
        return Value::Number(1.0 / 0.0)
      }
      if n.is_nan() {
        return Value::Number(0.0 / 0.0)
      }
      sum = sum + n * n
    }
    Value::Number(sum.sqrt())
  })
  math_props["cbrt"] = @runtime.make_static_func_with_length("cbrt", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    if n.is_nan() || n.is_inf() || n == 0.0 {
      Value::Number(n)
    } else {
      let sign : Double = if n < 0.0 { -1.0 } else { 1.0 }
      Value::Number(sign * @math.pow(n.abs(), 1.0 / 3.0))
    }
  })
  math_props["clz32"] = @runtime.make_static_func_with_length("clz32", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 { @runtime.to_number(args[0]) } else { 0.0 }
    let int_val = @runtime.to_int32(n)
    if int_val == 0 {
      return Value::Number(32.0)
    }
    let uint = int_val.reinterpret_as_uint()
    let mut count = 0
    let mut mask : UInt = 2147483648 // 0x80000000
    while mask > 0 && (uint & mask) == 0 {
      count = count + 1
      mask = mask >> 1
    }
    Value::Number(count.to_double())
  })
  math_props["imul"] = @runtime.make_static_func_with_length("imul", 2, fn(
    args,
  ) raise {
    let a = if args.length() > 0 { @runtime.to_number(args[0]) } else { 0.0 }
    let b = if args.length() > 1 { @runtime.to_number(args[1]) } else { 0.0 }
    let int_a = @runtime.to_int32(a)
    let int_b = @runtime.to_int32(b)
    // Perform 32-bit multiplication and mask to lower 32 bits as signed
    let product = int_a.to_int64() * int_b.to_int64()
    let masked = product & 0xFFFFFFFFL
    // Convert to signed 32-bit
    let result = if masked > 0x7FFFFFFFL {
      (masked - 0x100000000L).to_int()
    } else {
      masked.to_int()
    }
    Value::Number(result.to_double())
  })
  math_props["fround"] = @runtime.make_static_func_with_length("fround", 1, fn(
    args,
  ) raise {
    let n = if args.length() > 0 {
      @runtime.to_number(args[0])
    } else {
      0.0 / 0.0
    }
    // Round to nearest float32 (basic approximation)
    if n.is_nan() || n.is_inf() || n == 0.0 {
      Value::Number(n)
    } else {
      // Convert to float32 and back (approximation)
      Value::Number(Float::from_double(n).to_double())
    }
  })
  // Math.sumPrecise(items) - sums iterable of numbers
  math_props["sumPrecise"] = @runtime.make_interp_method_func("sumPrecise", 1, fn(
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
            Value::Number(n) => sum = sum + n
            _ =>
              raise @errors.TypeError(
                message="Math.sumPrecise: non-number value in iterable",
              )
          }
          count = count + 1
        }
      Object(_) => {
        // Try to use Symbol.iterator
        let iterator_sym = @runtime.get_iterator_symbol()
        let iter_fn = interp.get_computed_property(
          items,
          Symbol(iterator_sym),
          loc,
        )
        if @runtime.is_callable(iter_fn) {
          let iterator = interp.call_value(iter_fn, items, [], loc)
          let next_fn = interp.get_property(iterator, "next", loc)
          while true {
            let result = interp.call_value(next_fn, iterator, [], loc)
            let done = interp.get_property(result, "done", loc)
            if @runtime.is_truthy(done) {
              break
            }
            let value = interp.get_property(result, "value", loc)
            match value {
              Value::Number(n) => sum = sum + n
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
    Value::Number(sum)
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
  let tostringtag_sym = @runtime.get_tostringtag_symbol()
  math_symbol_props[tostringtag_sym.id] = Value::String_("Math")
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
    Value::Object({
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
