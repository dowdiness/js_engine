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
        Symbol(_) =>
          raise @errors.TypeError(
            message="Cannot convert a Symbol value to a string",
          )
        Bool(_)
        | Null
        | Undefined
        | Object(_)
        | Array(_)
        | Map(_)
        | Set(_)
        | Promise(_) => return Number(0.0 / 0.0)
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

  // encodeURIComponent(string)
  env.def_builtin(
    "encodeURIComponent",
    make_native_func("encodeURIComponent", fn(args) {
      let str = if args.length() > 0 {
        args[0].to_string()
      } else {
        "undefined"
      }
      String_(uri_encode(str, true))
    }),
  )

  // decodeURIComponent(string) - decodes everything
  env.def_builtin(
    "decodeURIComponent",
    make_native_func("decodeURIComponent", fn(args) {
      let str = if args.length() > 0 {
        args[0].to_string()
      } else {
        "undefined"
      }
      String_(uri_decode(str, false))
    }),
  )

  // encodeURI(string)
  env.def_builtin(
    "encodeURI",
    make_native_func("encodeURI", fn(args) {
      let str = if args.length() > 0 {
        args[0].to_string()
      } else {
        "undefined"
      }
      String_(uri_encode(str, false))
    }),
  )

  // decodeURI(string) - preserves reserved characters (; , / ? : @ & = + $ #)
  env.def_builtin(
    "decodeURI",
    make_native_func("decodeURI", fn(args) {
      let str = if args.length() > 0 {
        args[0].to_string()
      } else {
        "undefined"
      }
      String_(uri_decode(str, true))
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
        "fromCharCode": make_native_func("fromCharCode", fn(args) {
          let buf = StringBuilder::new()
          for arg in args {
            let code = to_number(arg).to_int()
            // fromCharCode uses UTF-16 code units, modulo 2^16
            let code_unit = code & 0xFFFF
            buf.write_char(code_unit.unsafe_to_char())
          }
          String_(buf.to_string())
        }),
        "fromCodePoint": make_native_func("fromCodePoint", fn(args) {
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
        "raw": make_native_func("raw", fn(args) {
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
        NativeCallable("String", fn(args) {
          let val = if args.length() > 0 { args[0] } else { Undefined }
          String_(val.to_string())
        }),
      ),
      class_name: "Function",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    }),
  )

  // Populate String.prototype with methods for .call() support
  setup_string_prototype(string_proto)
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
  boolean_proto_props["toString"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toString", fn(this_val, _args) {
        match this_val {
          Bool(b) => String_(b.to_string())
          _ =>
            raise @errors.TypeError(
              message="Boolean.prototype.toString requires a Boolean",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  boolean_proto_props["valueOf"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("valueOf", fn(this_val, _args) {
        match this_val {
          Bool(b) => Bool(b)
          _ =>
            raise @errors.TypeError(
              message="Boolean.prototype.valueOf requires a Boolean",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
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
  env.def_builtin(
    "Boolean",
    Object({
      properties: { "prototype": boolean_proto },
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable("Boolean", fn(args) {
          let val = if args.length() > 0 { args[0] } else { Undefined }
          Bool(is_truthy(val))
        }),
      ),
      class_name: "Function",
      descriptors: {},
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

  // Object, Array constructors and built-in methods
  setup_object_builtins(env)

  // Symbol constructor and well-known symbols (must be before Math for Symbol.toStringTag)
  setup_symbol_builtins(env)

  // Math object
  setup_math_builtins(env)

  // JSON object
  setup_json_builtins(env)

  // RegExp constructor
  env.def_builtin(
    "RegExp",
    Object({
      properties: {},
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
      descriptors: {},
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
}

///|
fn setup_symbol_builtins(env : Environment) -> Unit {
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
  let replace_sym = new_symbol(Some("Symbol.replace"))
  let search_sym = new_symbol(Some("Symbol.search"))
  let split_sym = new_symbol(Some("Symbol.split"))
  let unscopables_sym = new_symbol(Some("Symbol.unscopables"))
  let async_iterator_sym = new_symbol(Some("Symbol.asyncIterator"))

  // Symbol prototype
  let symbol_proto_props : Map[String, Value] = {}
  symbol_proto_props["toString"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toString", fn(this_val, _args) {
        match this_val {
          Symbol(sym) =>
            match sym.description {
              Some(desc) => String_("Symbol(\{desc})")
              None => String_("Symbol()")
            }
          _ =>
            raise @errors.TypeError(
              message="Symbol.prototype.toString requires a Symbol",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  symbol_proto_props["valueOf"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("valueOf", fn(this_val, _args) {
        match this_val {
          Symbol(_) => this_val
          _ =>
            raise @errors.TypeError(
              message="Symbol.prototype.valueOf requires a Symbol",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  symbol_proto_props["description"] = Undefined // Getter, simplified
  let symbol_proto : Value = Object({
    properties: symbol_proto_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Symbol",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Symbol constructor properties
  let symbol_props : Map[String, Value] = {}
  symbol_props["prototype"] = symbol_proto

  // Well-known symbols as static properties
  symbol_props["iterator"] = Symbol(iterator_sym)
  symbol_props["toPrimitive"] = Symbol(to_primitive_sym)
  symbol_props["toStringTag"] = Symbol(to_string_tag_sym)
  symbol_props["hasInstance"] = Symbol(has_instance_sym)
  symbol_props["isConcatSpreadable"] = Symbol(is_concat_spreadable_sym)
  symbol_props["species"] = Symbol(species_sym)
  symbol_props["match"] = Symbol(match_sym)
  symbol_props["replace"] = Symbol(replace_sym)
  symbol_props["search"] = Symbol(search_sym)
  symbol_props["split"] = Symbol(split_sym)
  symbol_props["unscopables"] = Symbol(unscopables_sym)
  symbol_props["asyncIterator"] = Symbol(async_iterator_sym)

  // Symbol.for(key) - returns symbol from global registry
  symbol_props["for"] = make_native_func("for", fn(args) {
    let key = if args.length() > 0 { args[0].to_string() } else { "undefined" }
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

  // Symbol.keyFor(sym) - returns key for symbol in global registry (O(1) via reverse lookup)
  symbol_props["keyFor"] = make_native_func("keyFor", fn(args) {
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

  // Symbol constructor - cannot be called with new, only as function
  env.def_builtin(
    "Symbol",
    Object({
      properties: symbol_props,
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NonConstructableCallable("Symbol", fn(args) {
          let description : String? = if args.length() > 0 {
            match args[0] {
              Undefined => None
              _ => Some(args[0].to_string())
            }
          } else {
            None
          }
          Symbol(new_symbol(description))
        }),
      ),
      class_name: "Function",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    }),
  )
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
        data.symbol_properties[iterator_sym.id] = Object({
          properties: {},
          symbol_properties: {},
          prototype: Null,
          callable: Some(
            MethodCallable("[Symbol.iterator]", fn(this_val, _args) { this_val }),
          ),
          class_name: "Function",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
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
          proto_data.symbol_properties[iterator_sym.id] = Object({
            properties: {},
            symbol_properties: {},
            prototype: Null,
            callable: Some(
              MethodCallable("[Symbol.iterator]", fn(this_val, _args) {
                match this_val {
                  Array(arr) => make_array_iterator(arr)
                  _ =>
                    raise @errors.TypeError(
                      message="Array.prototype[Symbol.iterator] called on non-array",
                    )
                }
              }),
            ),
            class_name: "Function",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })

          // Also add values() method (alias for [Symbol.iterator])
          proto_data.properties["values"] = Object({
            properties: {},
            symbol_properties: {},
            prototype: Null,
            callable: Some(
              MethodCallable("values", fn(this_val, _args) {
                match this_val {
                  Array(arr) => make_array_iterator(arr)
                  _ =>
                    raise @errors.TypeError(
                      message="Array.prototype.values called on non-array",
                    )
                }
              }),
            ),
            class_name: "Function",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })

          // Add keys() method that returns an iterator over indices
          proto_data.properties["keys"] = Object({
            properties: {},
            symbol_properties: {},
            prototype: Null,
            callable: Some(
              MethodCallable("keys", fn(this_val, _args) {
                match this_val {
                  Array(arr) => {
                    let index_ref : Ref[Int] = { val: 0 }
                    let len = arr.elements.length()
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
                        data.symbol_properties[iterator_sym.id] = Object({
                          properties: {},
                          symbol_properties: {},
                          prototype: Null,
                          callable: Some(
                            MethodCallable("[Symbol.iterator]", fn(
                              this_val,
                              _args,
                            ) {
                              this_val
                            }),
                          ),
                          class_name: "Function",
                          descriptors: {},
                          symbol_descriptors: {},
                          extensible: true,
                        })
                      _ => ()
                    }
                    iter_obj
                  }
                  _ =>
                    raise @errors.TypeError(
                      message="Array.prototype.keys called on non-array",
                    )
                }
              }),
            ),
            class_name: "Function",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })

          // Add entries() method that returns an iterator over [index, value] pairs
          proto_data.properties["entries"] = Object({
            properties: {},
            symbol_properties: {},
            prototype: Null,
            callable: Some(
              MethodCallable("entries", fn(this_val, _args) {
                match this_val {
                  Array(arr) => {
                    let index_ref : Ref[Int] = { val: 0 }
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
                        data.symbol_properties[iterator_sym.id] = Object({
                          properties: {},
                          symbol_properties: {},
                          prototype: Null,
                          callable: Some(
                            MethodCallable("[Symbol.iterator]", fn(
                              this_val,
                              _args,
                            ) {
                              this_val
                            }),
                          ),
                          class_name: "Function",
                          descriptors: {},
                          symbol_descriptors: {},
                          extensible: true,
                        })
                      _ => ()
                    }
                    iter_obj
                  }
                  _ =>
                    raise @errors.TypeError(
                      message="Array.prototype.entries called on non-array",
                    )
                }
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
  math_props["abs"] = make_native_func_with_length("abs", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(n.abs())
  })
  math_props["floor"] = make_native_func_with_length("floor", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(n.floor())
  })
  math_props["ceil"] = make_native_func_with_length("ceil", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(n.ceil())
  })
  math_props["round"] = make_native_func_with_length("round", 1, fn(args) {
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
  math_props["trunc"] = make_native_func_with_length("trunc", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    if n >= 0.0 {
      Number(n.floor())
    } else {
      Number(-(-n).floor())
    }
  })
  math_props["sqrt"] = make_native_func_with_length("sqrt", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(n.sqrt())
  })
  math_props["pow"] = make_native_func_with_length("pow", 2, fn(args) {
    let base = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    let exp = if args.length() > 1 { to_number(args[1]) } else { 0.0 / 0.0 }
    Number(@math.pow(base, exp))
  })
  math_props["min"] = make_native_func_with_length("min", 2, fn(args) {
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
  math_props["max"] = make_native_func_with_length("max", 2, fn(args) {
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
  math_props["random"] = make_native_func_with_length("random", 0, fn(_args) {
    let mut s = rng_state[0]
    s = s ^ (s << 13)
    s = s ^ (s.reinterpret_as_uint() >> 17).reinterpret_as_int()
    s = s ^ (s << 5)
    rng_state[0] = s
    let normalized = s.land(0x7FFFFFFF).to_double() / 2147483648.0
    Number(normalized)
  })
  math_props["sign"] = make_native_func_with_length("sign", 1, fn(args) {
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
  math_props["log"] = make_native_func_with_length("log", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.ln(n))
  })
  math_props["log2"] = make_native_func_with_length("log2", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.log2(n))
  })
  math_props["log10"] = make_native_func_with_length("log10", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.log10(n))
  })
  math_props["sin"] = make_native_func_with_length("sin", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.sin(n))
  })
  math_props["cos"] = make_native_func_with_length("cos", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.cos(n))
  })
  math_props["tan"] = make_native_func_with_length("tan", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.tan(n))
  })
  math_props["asin"] = make_native_func_with_length("asin", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.asin(n))
  })
  math_props["acos"] = make_native_func_with_length("acos", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.acos(n))
  })
  math_props["atan"] = make_native_func_with_length("atan", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.atan(n))
  })
  math_props["atan2"] = make_native_func_with_length("atan2", 2, fn(args) {
    let y = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    let x = if args.length() > 1 { to_number(args[1]) } else { 0.0 / 0.0 }
    Number(@math.atan2(y, x))
  })
  math_props["sinh"] = make_native_func_with_length("sinh", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.sinh(n))
  })
  math_props["cosh"] = make_native_func_with_length("cosh", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.cosh(n))
  })
  math_props["tanh"] = make_native_func_with_length("tanh", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.tanh(n))
  })
  math_props["asinh"] = make_native_func_with_length("asinh", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.asinh(n))
  })
  math_props["acosh"] = make_native_func_with_length("acosh", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.acosh(n))
  })
  math_props["atanh"] = make_native_func_with_length("atanh", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.atanh(n))
  })
  math_props["exp"] = make_native_func_with_length("exp", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.exp(n))
  })
  math_props["expm1"] = make_native_func_with_length("expm1", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    Number(@math.expm1(n))
  })
  math_props["log1p"] = make_native_func_with_length("log1p", 1, fn(args) {
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
  math_props["hypot"] = make_native_func_with_length("hypot", 2, fn(args) {
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
  math_props["cbrt"] = make_native_func_with_length("cbrt", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    if n.is_nan() || n.is_inf() || n == 0.0 {
      Number(n)
    } else {
      let sign : Double = if n < 0.0 { -1.0 } else { 1.0 }
      Number(sign * @math.pow(n.abs(), 1.0 / 3.0))
    }
  })
  math_props["clz32"] = make_native_func_with_length("clz32", 1, fn(args) {
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
  math_props["imul"] = make_native_func_with_length("imul", 2, fn(args) {
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
  math_props["fround"] = make_native_func_with_length("fround", 1, fn(args) {
    let n = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
    // Round to nearest float32 (basic approximation)
    if n.is_nan() || n.is_inf() || n == 0.0 {
      Number(n)
    } else {
      // Convert to float32 and back (approximation)
      Number(Float::from_double(n).to_double())
    }
  })
  // Set up Symbol.toStringTag for Math
  let math_symbol_props : Map[Int, Value] = {}
  let tostringtag_sym = get_tostringtag_symbol()
  math_symbol_props[tostringtag_sym.id] = String_("Math")
  env.def_builtin(
    "Math",
    Object({
      properties: math_props,
      symbol_properties: math_symbol_props,
      prototype: Null,
      callable: None,
      class_name: "Math",
      descriptors: {},
      symbol_descriptors: {},
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
    symbol_properties: {},
    prototype: parent_proto,
    callable: None,
    class_name: name,
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  env.def_builtin(
    name,
    Object({
      properties: { "prototype": proto_obj },
      symbol_properties: {},
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
            symbol_properties: {},
            prototype: proto_obj,
            callable: None,
            class_name: name,
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
        }),
      ),
      class_name: "Function",
      descriptors: {},
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
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toFixed", fn(this_val, args) {
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  number_proto_props["toString"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toString", fn(this_val, args) {
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
    symbol_descriptors: {},
    extensible: true,
  })
  number_proto_props["valueOf"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("valueOf", fn(this_val, _args) {
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  number_proto_props["toPrecision"] = Object({
    properties: {},
    symbol_properties: {},
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  number_proto_props["toExponential"] = Object({
    properties: {},
    symbol_properties: {},
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
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
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable("Number", fn(args) {
          let val = if args.length() > 0 { args[0] } else { Undefined }
          Number(to_number(val))
        }),
      ),
      class_name: "Function",
      descriptors: {},
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
      symbol_properties: {},
      prototype: Null,
      callable: None,
      class_name: "JSON",
      descriptors: {},
      symbol_descriptors: {},
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
    Symbol(_) => Undefined // Symbols are omitted from JSON
    Map(_) => String_("{}") // Maps serialize as empty objects
    Set(_) => String_("{}") // Sets serialize as empty objects
    Promise(_) => String_("{}") // Promises serialize as empty objects
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
                Some(MethodCallable(_, func)) => {
                  let json_val = func(val, [])
                  return json_stringify_value(json_val, seen, indent, depth)
                }
                Some(NativeCallable(_, func)) => {
                  let json_val = func([])
                  return json_stringify_value(json_val, seen, indent, depth)
                }
                Some(NonConstructableCallable(_, func)) => {
                  let json_val = func([])
                  return json_stringify_value(json_val, seen, indent, depth)
                }
                // User-defined functions require the interpreter to call;
                // they are handled at a higher level. Skip here.
                _ => ()
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
          data.properties.each(fn(k, v) {
            // Skip internal properties (e.g., [[DateValue]], [[NumberData]])
            if k.has_prefix("[[") {
              return
            }
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
        symbol_properties: {},
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
          }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    "toString" =>
      Object({
        properties: {},
        symbol_properties: {},
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
          }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    "valueOf" =>
      Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("valueOf", fn(this_val, _args) {
            Number(to_number(this_val))
          }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    "toPrecision" =>
      Object({
        properties: {},
        symbol_properties: {},
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
          }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    "toExponential" =>
      Object({
        properties: {},
        symbol_properties: {},
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
          }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
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

///|
fn setup_function_builtins(env : Environment) -> Unit {
  // Create Function.prototype
  let func_proto_props : Map[String, Value] = {}

  // Function.prototype.toString - returns function source or [native code]
  func_proto_props["toString"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toString", fn(this_val, _args) {
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Function.prototype.call - placeholder (actual implementation in interpreter)
  func_proto_props["call"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("call", fn(_args) {
        // This is a placeholder - actual call is handled by FuncCallMethod in interpreter
        Undefined
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Function.prototype.apply - placeholder (actual implementation in interpreter)
  func_proto_props["apply"] = Object({
    properties: { "length": Number(2.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("apply", fn(_args) {
        // This is a placeholder - actual apply is handled by FuncApplyMethod in interpreter
        Undefined
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Function.prototype.bind - placeholder (actual implementation in interpreter)
  func_proto_props["bind"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("bind", fn(_args) {
        // This is a placeholder - actual bind is handled in interpreter
        Undefined
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  let func_proto : Value = Object({
    properties: func_proto_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Function constructor properties
  let func_ctor_props : Map[String, Value] = {}
  func_ctor_props["prototype"] = func_proto
  func_ctor_props["length"] = Number(1.0)

  // Create a single Function constructor object.
  // Function(p1, p2, ..., body) parses the body string and creates a real function.
  let func_ctor : Value = Object({
    properties: func_ctor_props,
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("Function", fn(args) {
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
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Add constructor back-reference to prototype (same object as global Function)
  match func_proto {
    Object(data) => data.properties["constructor"] = func_ctor
    _ => ()
  }

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
  agent_props["start"] = make_native_func("start", fn(_args) {
    raise @errors.TypeError(message="$262.agent.start is not supported")
  })
  agent_props["broadcast"] = make_native_func("broadcast", fn(_args) {
    raise @errors.TypeError(message="$262.agent.broadcast is not supported")
  })
  agent_props["getReport"] = make_native_func("getReport", fn(_args) {
    raise @errors.TypeError(message="$262.agent.getReport is not supported")
  })
  agent_props["sleep"] = make_native_func("sleep", fn(_args) {
    raise @errors.TypeError(message="$262.agent.sleep is not supported")
  })
  agent_props["monotonicNow"] = make_native_func("monotonicNow", fn(_args) {
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
  dollar262_props["createRealm"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("createRealm", fn(_interp, _this_val, _args) {
        let new_interp = Interpreter::new()
        // Build a $262 object with methods bound to the new interpreter.
        // Uses NativeCallable closures that capture new_interp so that
        // evalScript executes in the new realm, not the caller's.
        let realm_props : Map[String, Value] = {}
        realm_props["global"] = new_interp.global_this
        realm_props["gc"] = make_native_func("gc", fn(_a) { Undefined })
        realm_props["evalScript"] = make_native_func("evalScript", fn(es_args) {
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
          fn(_a) {
            raise @errors.TypeError(
              message="$262.detachArrayBuffer is not supported",
            )
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // $262.evalScript(code) - parses and evaluates code as a script
  // in the current realm's global scope.
  dollar262_props["evalScript"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("evalScript", fn(interp, _this_val, args) {
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  dollar262_props["detachArrayBuffer"] = make_native_func("detachArrayBuffer", fn(
    _args,
  ) {
    raise @errors.TypeError(message="$262.detachArrayBuffer is not supported")
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
