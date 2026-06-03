///|
pub fn setup_builtins(
  env : Environment,
  output : Array[String],
  symbols : SymbolState,
  annex_b? : Bool = false,
) -> @runtime.RealmState {
  let realm_state = @runtime.RealmState::from_symbols(symbols)
  setup_builtins_with_realm_state(env, output, realm_state, annex_b~)
  realm_state
}

///|
// Engine-private negative symbol IDs are reserved in docs/development.md.
// This traversal marker is mirrored by the startup subphase benchmark; keep
// STARTUP_REALM_STAMP_VISITED_SYMBOL_ID synchronized with this value and
// update the benchmark mirror if the production traversal changes.
const REALM_STAMP_VISITED_SYMBOL_ID = -111

///|
fn stamp_realm_reachable_value(
  value : Value,
  realm_state : @runtime.RealmState,
  depth : Int,
  visited_objects : Array[@runtime.ObjectData],
) -> Unit {
  match value {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
      stamp_realm_functions_in_value(value, realm_state, depth, visited_objects)
    _ => ()
  }
}

///|
fn stamp_realm_functions_in_bag(
  bag : @runtime.PropertyBag,
  realm_state : @runtime.RealmState,
  depth : Int,
  visited_objects : Array[@runtime.ObjectData],
) -> Unit {
  bag.properties.each(fn(_key, value) {
    stamp_realm_reachable_value(value, realm_state, depth, visited_objects)
  })
  bag.symbol_properties.each(fn(key, value) {
    // Negative symbol IDs are internal metadata (including the hidden function
    // realm prototype slots that this stamp operation writes).  They point back
    // into the intrinsic graph and are not a source of user-visible built-in
    // functions, so following them makes the final stamp revisit the same realm
    // prototypes for every callable.
    if key >= 0 {
      stamp_realm_reachable_value(value, realm_state, depth, visited_objects)
    }
  })
}

///|
fn stamp_realm_object_seen_at_depth(
  data : @runtime.ObjectData,
  depth : Int,
  visited_objects : Array[@runtime.ObjectData],
) -> Bool {
  let current_depth = depth.to_double()
  match data.bag.symbol_properties.get(REALM_STAMP_VISITED_SYMBOL_ID) {
    Some(Number(seen_depth)) => {
      if seen_depth >= current_depth {
        return true
      }
      // Preserve the previous depth-aware traversal semantics: if an object is
      // first reached through a shallower path, revisit it once when a later
      // root reaches it with more remaining depth.
      data.bag.symbol_properties[REALM_STAMP_VISITED_SYMBOL_ID] = Number(
        current_depth,
      )
      false
    }
    Some(_) => true
    None => {
      data.bag.symbol_properties[REALM_STAMP_VISITED_SYMBOL_ID] = Number(
        current_depth,
      )
      visited_objects.push(data)
      false
    }
  }
}

///|
fn clear_realm_stamp_markers(
  visited_objects : Array[@runtime.ObjectData],
) -> Unit {
  for data in visited_objects {
    let _ = data.bag.symbol_properties.remove(REALM_STAMP_VISITED_SYMBOL_ID)
  }
}

///|
fn stamp_realm_functions_in_value(
  value : Value,
  realm_state : @runtime.RealmState,
  depth : Int,
  visited_objects : Array[@runtime.ObjectData],
) -> Unit {
  if depth == 0 {
    return
  }
  let next_depth = depth - 1
  match value {
    Object(data) => {
      if stamp_realm_object_seen_at_depth(data, depth, visited_objects) {
        return
      }
      match data.callable {
        Some(_) =>
          @runtime.stamp_function_realm(value, realm_state=Some(realm_state))
          |> ignore
        None => ()
      }
      stamp_realm_functions_in_bag(
        data.bag,
        realm_state,
        next_depth,
        visited_objects,
      )
    }
    Array(data) =>
      stamp_realm_functions_in_bag(
        data.bag,
        realm_state,
        next_depth,
        visited_objects,
      )
    Map(data) =>
      stamp_realm_functions_in_bag(
        data.bag,
        realm_state,
        next_depth,
        visited_objects,
      )
    Set(data) =>
      stamp_realm_functions_in_bag(
        data.bag,
        realm_state,
        next_depth,
        visited_objects,
      )
    Promise(data) =>
      stamp_realm_functions_in_bag(
        data.bag,
        realm_state,
        next_depth,
        visited_objects,
      )
    Proxy(proxy_data) =>
      match proxy_data.target {
        Some(target) =>
          stamp_realm_functions_in_value(
            target, realm_state, next_depth, visited_objects,
          )
        None => ()
      }
    _ => ()
  }
}

///|
fn stamp_realm_functions_in_env(
  env : Environment,
  realm_state : @runtime.RealmState,
) -> Unit {
  let visited_objects : Array[@runtime.ObjectData] = []
  env.bindings.each(fn(_name, binding) {
    stamp_realm_functions_in_value(
      binding.value,
      realm_state,
      4,
      visited_objects,
    )
  })
  clear_realm_stamp_markers(visited_objects)
}

///|
fn stamp_realm_functions_from_env(
  env : Environment,
  realm_state : @runtime.RealmState,
) -> Unit {
  stamp_realm_functions_in_env(env, realm_state)
}

///|
pub fn setup_builtins_with_realm_state(
  env : Environment,
  output : Array[String],
  realm_state : @runtime.RealmState,
  annex_b? : Bool = false,
) -> Unit {
  env.realm_state = Some(realm_state)
  @runtime.with_active_realm_state_unit(realm_state, fn() {
    setup_builtins_with_realm_state_active(env, output, realm_state, annex_b)
  })
}

///|
fn setup_builtins_with_realm_state_active(
  env : Environment,
  output : Array[String],
  realm_state : @runtime.RealmState,
  annex_b : Bool,
  profile? : BuiltinSetupProfiler,
) -> Unit {
  let _ = output
  let symbols = realm_state.symbols
  let well_known_symbols = realm_state.well_known_symbols
  // Global constants
  env.def_builtin("NaN", Value::Number(0.0 / 0.0))
  env.def_builtin("Infinity", Value::Number(1.0 / 0.0))
  env.def_builtin("undefined", Undefined)

  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  // eval(x) — NonConstructableCallable so that new eval() throws TypeError.
  // Direct eval is handled at the call-site in eval_call.
  // Indirect eval (0,eval)("code") is intercepted in call_value where the
  // interpreter is available for perform_eval.
  let eval_func : Value = Value::Object({
    bag: {
      properties: {
        "length": Value::Number(1.0),
        "name": Value::String_("eval"),
      },
      symbol_properties: {},
      descriptors: { "length": nf_desc, "name": nf_desc },
      symbol_descriptors: {},
    },
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
    extensible: true,
    arraybuffer_state: None,
  })
  env.def_builtin("eval", eval_func)

  // isNaN(value)
  env.def_builtin(
    "isNaN",
    @runtime.make_interp_static_func(name="isNaN", length=1, fn(
      interp,
      args,
    ) raise {
      let val = if args.length() > 0 { args[0] } else { Undefined }
      let n = @runtime.to_number(val, interp=Some(interp))
      Bool(n.is_nan())
    }),
  )

  // isFinite(value)
  env.def_builtin(
    "isFinite",
    @runtime.make_interp_static_func(name="isFinite", length=1, fn(
      interp,
      args,
    ) raise {
      let val = if args.length() > 0 { args[0] } else { Undefined }
      let n = @runtime.to_number(val, interp=Some(interp))
      Bool(!n.is_nan() && !n.is_inf())
    }),
  )

  // parseInt(string, radix?)
  env.def_builtin(
    "parseInt",
    @runtime.make_native_func(name="parseInt", length=2, fn(args) raise {
      let str_val = if args.length() > 0 { args[0] } else { Undefined }
      let s = @runtime.to_js_string(str_val)
      let trimmed = trim_start(s)
      if trimmed.length() == 0 {
        return Value::Number(0.0 / 0.0)
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
        @runtime.to_int32(@runtime.to_number(args[1]))
      } else {
        0
      }
      let mut radix = if radix_arg == 0 {
        10 // radix 0 defaults to 10
      } else if radix_arg < 2 || radix_arg > 36 {
        return Value::Number(0.0 / 0.0)
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
        Value::Number(0.0 / 0.0)
      } else {
        Value::Number(sign * result)
      }
    }),
  )

  // parseFloat(string)
  env.def_builtin(
    "parseFloat",
    @runtime.make_native_func(name="parseFloat", length=1, fn(args) raise {
      let str_val = if args.length() > 0 { args[0] } else { Undefined }
      let s = @runtime.to_js_string(str_val)
      let trimmed = trim_start(s)
      if trimmed.length() == 0 {
        return Value::Number(0.0 / 0.0)
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
        return Value::Number(sign * (1.0 / 0.0))
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
        return Value::Number(0.0 / 0.0)
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
      Value::Number(result)
    }),
  )

  // encodeURIComponent(string)
  env.def_builtin(
    "encodeURIComponent",
    @runtime.make_native_func(name="encodeURIComponent", length=1, fn(
      args,
    ) raise {
      let str = if args.length() > 0 {
        @runtime.to_js_string(args[0])
      } else {
        "undefined"
      }
      Value::String_(uri_encode(str, true))
    }),
  )

  // decodeURIComponent(string) - decodes everything
  env.def_builtin(
    "decodeURIComponent",
    @runtime.make_native_func(name="decodeURIComponent", length=1, fn(
      args,
    ) raise {
      let str = if args.length() > 0 {
        @runtime.to_js_string(args[0])
      } else {
        "undefined"
      }
      Value::String_(uri_decode(str, false))
    }),
  )

  // encodeURI(string)
  env.def_builtin(
    "encodeURI",
    @runtime.make_native_func(name="encodeURI", length=1, fn(args) raise {
      let str = if args.length() > 0 {
        @runtime.to_js_string(args[0])
      } else {
        "undefined"
      }
      Value::String_(uri_encode(str, false))
    }),
  )

  // decodeURI(string) - preserves reserved characters (; , / ? : @ & = + $ #)
  env.def_builtin(
    "decodeURI",
    @runtime.make_native_func(name="decodeURI", length=1, fn(args) raise {
      let str = if args.length() > 0 {
        @runtime.to_js_string(args[0])
      } else {
        "undefined"
      }
      Value::String_(uri_decode(str, true))
    }),
  )

  // escape(string) — Annex B
  env.def_builtin(
    "escape",
    @runtime.make_native_func(name="escape", length=1, fn(args) raise {
      let str = if args.length() > 0 {
        @runtime.to_js_string(args[0])
      } else {
        "undefined"
      }
      Value::String_(js_escape(str))
    }),
  )

  // unescape(string) — Annex B
  env.def_builtin(
    "unescape",
    @runtime.make_native_func(name="unescape", length=1, fn(args) raise {
      let str = if args.length() > 0 {
        @runtime.to_js_string(args[0])
      } else {
        "undefined"
      }
      Value::String_(js_unescape(str))
    }),
  )

  mark_builtin_setup_phase(profile, "global_functions")

  // String constructor with static methods
  let string_proto : Value = Value::Object({
    bag: {
      properties: {
        "[[StringData]]": Value::String_(""),
        "length": Value::Number(0.0),
      },
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
      },
      symbol_descriptors: {},
    },
    prototype: @runtime.get_obj_proto(realm_state=Some(realm_state)),
    callable: None,
    class_name: "String",
    extensible: true,
    arraybuffer_state: None,
  })
  env.def_builtin(
    "String",
    Value::Object({
      bag: {
        properties: {
          "prototype": string_proto,
          "name": Value::String_("String"),
          "length": Value::Number(1.0),
          "fromCharCode": @runtime.make_native_func(
            name="fromCharCode",
            length=1,
            fn(args) raise {
              let buf = StringBuilder::new()
              for arg in args {
                let code = @runtime.to_number(arg).to_int()
                // fromCharCode uses UTF-16 code units, modulo 2^16
                let code_unit = code & 0xFFFF
                buf.write_char(code_unit.unsafe_to_char())
              }
              Value::String_(buf.to_string())
            },
          ),
          "fromCodePoint": @runtime.make_native_func(
            name="fromCodePoint",
            length=1,
            fn(args) raise {
              // String.fromCodePoint() - accepts Unicode code points (not code units)
              let buf = StringBuilder::new()
              for arg in args {
                let num = @runtime.to_number(arg)
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
              Value::String_(buf.to_string())
            },
          ),
          "raw": @runtime.make_interp_static_func(name="raw", length=1, fn(
            interp,
            args,
          ) raise {
            // String.raw(template, ...substitutions)
            // Returns raw string content without processing escape sequences
            if args.length() == 0 {
              return Value::String_("")
            }
            let template = args[0]
            match template {
              Object(_) | Array(_) => {
                let raw = interp.get_property(
                  template,
                  "raw",
                  @token.Loc::default(),
                )
                match raw {
                  Array(raw_data) => {
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
                    Value::String_(buf.to_string())
                  }
                  Object(raw_obj) => {
                    // Handle object with numeric indices - use length property per spec
                    let buf = StringBuilder::new()
                    let sub_count = args.length() - 1

                    // Get length property (treat missing/invalid as 0)
                    let length = match raw_obj.bag.properties.get("length") {
                      Some(Value::Number(n)) => n.to_int().max(0)
                      _ => 0
                    }

                    // Iterate from 0 to length-1, treating missing indices as Undefined
                    for i = 0; i < length; i = i + 1 {
                      let str_val = match
                        raw_obj.bag.properties.get(i.to_string()) {
                        Some(v) => v
                        None => Undefined
                      }
                      buf.write_string(str_val.to_string())
                      // Add substitution if available
                      if i < sub_count {
                        buf.write_string(args[i + 1].to_string())
                      }
                    }
                    Value::String_(buf.to_string())
                  }
                  _ =>
                    raise @errors.TypeError(
                      message="Cannot convert to string template",
                    )
                }
              }
              _ =>
                raise @errors.TypeError(
                  message="Cannot convert to string template",
                )
            }
          }),
        },
        symbol_properties: {},
        descriptors: {
          "name": nf_desc,
          "length": nf_desc,
          "prototype": {
            writable: false,
            enumerable: false,
            configurable: false,
            getter: None,
            setter: None,
            is_accessor: false,
          },
          "fromCharCode": {
            writable: true,
            enumerable: false,
            configurable: true,
            getter: None,
            setter: None,
            is_accessor: false,
          },
          "fromCodePoint": {
            writable: true,
            enumerable: false,
            configurable: true,
            getter: None,
            setter: None,
            is_accessor: false,
          },
          "raw": {
            writable: true,
            enumerable: false,
            configurable: true,
            getter: None,
            setter: None,
            is_accessor: false,
          },
        },
        symbol_descriptors: {},
      },
      prototype: Null,
      callable: Some(
        NativeCallableWithContext("String", fn(context, args) raise {
          let str = if args.length() == 0 {
            // Per spec: String() with no args returns ""
            ""
          } else {
            let val = args[0]
            // Per spec: String(symbol) returns the symbol description
            match val {
              Value::Symbol(sym) =>
                match sym.description {
                  Some(d) => "Symbol(" + d + ")"
                  None => "Symbol()"
                }
              _ => @runtime.to_js_string(val)
            }
          }
          if context.is_constructing() {
            // new String(value) → boxed String object
            let props : Map[String, Value] = {}
            props["[[StringData]]"] = Value::String_(str)
            props["length"] = Value::Number(str.length().to_double())
            // Add indexed character properties
            for i = 0; i < str.length(); i = i + 1 {
              props[i.to_string()] = Value::String_(
                str.view()[i:i + 1].to_owned(),
              )
            }
            let descs : Map[String, PropDescriptor] = {}
            descs["length"] = {
              writable: false,
              enumerable: false,
              configurable: false,
              getter: None,
              setter: None,
              is_accessor: false,
            }
            for i = 0; i < str.length(); i = i + 1 {
              descs[i.to_string()] = {
                writable: false,
                enumerable: true,
                configurable: false,
                getter: None,
                setter: None,
                is_accessor: false,
              }
            }
            Value::Object({
              bag: {
                properties: props,
                symbol_properties: {},
                descriptors: descs,
                symbol_descriptors: {},
              },
              prototype: string_proto,
              callable: None,
              class_name: "String",
              extensible: true,
              arraybuffer_state: None,
            })
          } else {
            Value::String_(str)
          }
        }),
      ),
      class_name: "Function",
      extensible: true,
      arraybuffer_state: None,
    }),
  )

  // Store String.prototype for ToObject wrapping
  env.def_builtin("[[StringPrototype]]", string_proto)
  realm_state.string_prototype.val = Some(string_proto)
  // Populate String.prototype with methods for .call() support
  setup_string_prototype(string_proto, realm_state, annex_b~)
  // Set String.prototype.constructor = String
  match string_proto {
    Object(data) => {
      let ctor = env.get("String") catch { _ => Undefined }
      data.bag.properties["constructor"] = ctor
      data.bag.descriptors["constructor"] = {
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

  mark_builtin_setup_phase(profile, "string")

  // Number constructor with static methods and prototype
  setup_number_builtins(env, realm_state)
  mark_builtin_setup_phase(profile, "number")

  // Boolean constructor with prototype
  let boolean_proto_props : Map[String, Value] = {}
  boolean_proto_props["toString"] = @runtime.make_method_func(
    name="toString",
    length=0,
    fn(this_val, _args) raise {
      match this_val {
        Value::Bool(b) => Value::String_(b.to_string())
        Object(data) =>
          if data.class_name == "Boolean" {
            match data.bag.properties.get("[[BooleanData]]") {
              Some(Value::Bool(b)) => Value::String_(b.to_string())
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
    },
  )
  boolean_proto_props["valueOf"] = @runtime.make_method_func(
    name="valueOf",
    length=0,
    fn(this_val, _args) raise {
      match this_val {
        Value::Bool(b) => Value::Bool(b)
        Object(data) =>
          if data.class_name == "Boolean" {
            match data.bag.properties.get("[[BooleanData]]") {
              Some(Value::Bool(b)) => Value::Bool(b)
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
    },
  )
  // Boolean.prototype has [[BooleanData]] internal slot with value false
  boolean_proto_props["[[BooleanData]]"] = Value::Bool(false)
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let boolean_proto_descs : Map[String, PropDescriptor] = {}
  boolean_proto_descs["toString"] = method_desc
  boolean_proto_descs["valueOf"] = method_desc
  let boolean_proto : Value = Value::Object({
    bag: {
      properties: boolean_proto_props,
      symbol_properties: {},
      descriptors: boolean_proto_descs,
      symbol_descriptors: {},
    },
    prototype: @runtime.get_obj_proto(realm_state=Some(realm_state)),
    callable: None,
    class_name: "Boolean",
    extensible: true,
    arraybuffer_state: None,
  })
  // Store Boolean.prototype for ToObject wrapping
  env.def_builtin("[[BooleanPrototype]]", boolean_proto)
  realm_state.boolean_prototype.val = Some(boolean_proto)
  env.def_builtin(
    "Boolean",
    Value::Object({
      bag: {
        properties: {
          "prototype": boolean_proto,
          "name": Value::String_("Boolean"),
          "length": Value::Number(1.0),
        },
        symbol_properties: {},
        descriptors: {
          "name": nf_desc,
          "length": nf_desc,
          "prototype": {
            writable: false,
            enumerable: false,
            configurable: false,
            getter: None,
            setter: None,
            is_accessor: false,
          },
        },
        symbol_descriptors: {},
      },
      prototype: Null,
      callable: Some(
        NativeCallableWithContext("Boolean", fn(context, args) {
          let val = if args.length() > 0 { args[0] } else { Undefined }
          let b = @runtime.is_truthy(val)
          if context.is_constructing() {
            // new Boolean(value) → boxed Boolean object
            Value::Object({
              bag: {
                properties: { "[[BooleanData]]": Value::Bool(b) },
                symbol_properties: {},
                descriptors: {},
                symbol_descriptors: {},
              },
              prototype: boolean_proto,
              callable: None,
              class_name: "Boolean",
              extensible: true,
              arraybuffer_state: None,
            })
          } else {
            Value::Bool(b)
          }
        }),
      ),
      class_name: "Function",
      extensible: true,
      arraybuffer_state: None,
    }),
  )

  // Set Boolean.prototype.constructor = Boolean
  match boolean_proto {
    Object(data) => {
      let ctor = env.get("Boolean") catch { _ => Undefined }
      data.bag.properties["constructor"] = ctor
      data.bag.descriptors["constructor"] = {
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

  mark_builtin_setup_phase(profile, "boolean")

  // Function constructor with prototype
  setup_function_builtins(env, realm_state)
  mark_builtin_setup_phase(profile, "function")

  // Error constructors
  let error_proto = register_error_ctor(
    env,
    "Error",
    @runtime.get_obj_proto(realm_state=Some(realm_state)),
  )
  register_error_ctor(env, "TypeError", error_proto) |> ignore
  register_error_ctor(env, "ReferenceError", error_proto) |> ignore
  register_error_ctor(env, "SyntaxError", error_proto) |> ignore
  register_error_ctor(env, "RangeError", error_proto) |> ignore
  register_error_ctor(env, "URIError", error_proto) |> ignore
  register_error_ctor(env, "EvalError", error_proto) |> ignore
  register_error_ctor(env, "InternalError", error_proto) |> ignore
  register_aggregate_error_ctor(env, error_proto) |> ignore

  // Add Error.isError static method
  let error_ctor = env.get("Error") catch { _ => Undefined }
  match error_ctor {
    Object(error_data) => {
      error_data.bag.properties["isError"] = @runtime.make_native_func(
        name="isError",
        length=1,
        fn(args) {
          let arg = if args.length() > 0 { args[0] } else { Undefined }
          match arg {
            Object(data) =>
              // ES §21.5.2.1: return true iff arg has [[ErrorData]] slot.
              // The registry is populated at constructor registration time,
              // so new error types are automatically recognised without
              // requiring any change here.
              Bool(env.error_class_names.contains(data.class_name))
            _ => Value::Bool(false)
          }
        },
      )
      error_data.bag.descriptors["isError"] = {
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

  mark_builtin_setup_phase(profile, "errors")

  // Object, Array constructors and built-in methods
  setup_object_builtins(env, symbols, realm_state)

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

  mark_builtin_setup_phase(profile, "object_array_initial_patching")

  // Symbol constructor and well-known symbols (must be before Math for Symbol.toStringTag)
  setup_symbol_builtins(env, realm_state)
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

  mark_builtin_setup_phase(profile, "symbol")

  // Math object
  setup_math_builtins(env, well_known_symbols)
  mark_builtin_setup_phase(profile, "math")

  // JSON object
  setup_json_builtins(env, well_known_symbols)
  mark_builtin_setup_phase(profile, "json")

  // RegExp constructor
  env.def_builtin("RegExp", make_regexp_constructor(realm_state, nf_desc))

  // Set up RegExp.prototype and store it on the realm.
  match env.bindings.get("[[ObjectPrototype]]") {
    Some(obj_proto_binding) => {
      let obj_proto = obj_proto_binding.value
      let regexp_proto_props : Map[String, Value] = {}
      regexp_proto_props["constructor"] = match env.bindings.get("RegExp") {
        Some(b) => b.value
        None => Undefined
      }
      // Add RegExp.prototype methods. test() and exec() are interpreter-aware
      // because argument and lastIndex coercions can call user code.
      regexp_proto_props["test"] = @runtime.make_interp_method_func(
        name="test",
        length=1,
        realm_state=Some(realm_state),
        fn(interp, this_val, args) raise {
          if !(this_val is Object({ class_name: "RegExp", .. })) {
            raise @errors.TypeError(
              message="Method RegExp.prototype.test called on incompatible receiver",
            )
          }
          let str = interp.to_js_string(
            if args.length() > 0 {
              args[0]
            } else {
              Undefined
            },
          )
          let result = regexp_exec_for_symbol_method(interp, this_val, str)
          Value::Bool(!(result is Null))
        },
      )
      regexp_proto_props["exec"] = @runtime.make_interp_method_func(
        name="exec",
        length=1,
        realm_state=Some(realm_state),
        fn(interp, this_val, args) raise {
          if !(this_val is Object({ class_name: "RegExp", .. })) {
            raise @errors.TypeError(
              message="Method RegExp.prototype.exec called on incompatible receiver",
            )
          }
          let loc = @token.Loc::default()
          let str = interp.to_js_string(
            if args.length() > 0 {
              args[0]
            } else {
              Undefined
            },
          )
          regexp_builtin_exec(interp, this_val, str, loc)
        },
      )
      // RegExp.prototype.compile (Annex B)
      regexp_proto_props["compile"] = make_regexp_compile_method(realm_state)
      regexp_proto_props["toString"] = make_regexp_to_string_method(realm_state)
      // Add flag/source getter accessors to RegExp.prototype per spec
      let regexp_proto_descs : Map[String, PropDescriptor] = {}
      install_regexp_prototype_accessors(
        regexp_proto_props, regexp_proto_descs, realm_state,
      )
      let re_method_desc2 : PropDescriptor = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
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
        is_accessor: false,
      }
      match regexp_proto_props.get("constructor") {
        Some(ctor) =>
          set_regexp_intrinsic_constructor_slot(
            regexp_sym_props, regexp_sym_descs, ctor,
          )
        None => ()
      }
      // [Symbol.match]
      let match_sym = well_known_symbols.match_sym
      regexp_sym_props[match_sym.id] = make_regexp_match_method(realm_state)
      regexp_sym_descs[match_sym.id] = sym_method_desc
      // [Symbol.matchAll]
      let match_all_sym = well_known_symbols.match_all
      regexp_sym_props[match_all_sym.id] = make_regexp_match_all_method(
        realm_state,
      )
      regexp_sym_descs[match_all_sym.id] = sym_method_desc
      // [Symbol.search]
      let search_sym = well_known_symbols.search
      regexp_sym_props[search_sym.id] = @runtime.make_interp_method_func(
        name="[Symbol.search]",
        length=1,
        realm_state=Some(realm_state),
        fn(interp, this_val, args) raise {
          if !regexp_this_is_object(this_val) {
            return regexp_proto_incompatible("RegExp.prototype[Symbol.search]")
          }
          let loc = @token.Loc::default()
          let str = interp.to_js_string(
            if args.length() > 0 {
              args[0]
            } else {
              Undefined
            },
          )
          let previous_last_index = interp.get_property(
            this_val, "lastIndex", loc,
          )
          if !same_value(previous_last_index, Value::Number(0.0)) {
            let _ = interp.set_property(
              this_val,
              "lastIndex",
              Value::Number(0.0),
              loc,
              strict=true,
            )
          }
          let result = regexp_exec_for_symbol_method(interp, this_val, str)
          let current_last_index = interp.get_property(
            this_val, "lastIndex", loc,
          )
          if !same_value(current_last_index, previous_last_index) {
            let _ = interp.set_property(
              this_val,
              "lastIndex",
              previous_last_index,
              loc,
              strict=true,
            )
          }
          match result {
            Null => Value::Number(-1.0)
            _ => interp.get_property(result, "index", loc)
          }
        },
      )
      regexp_sym_descs[search_sym.id] = sym_method_desc
      // [Symbol.replace]
      let replace_sym = well_known_symbols.replace
      regexp_sym_props[replace_sym.id] = make_regexp_replace_method(realm_state)
      regexp_sym_descs[replace_sym.id] = sym_method_desc
      // [Symbol.split]
      let split_sym = well_known_symbols.split
      regexp_sym_props[split_sym.id] = make_regexp_split_method(realm_state)
      regexp_sym_descs[split_sym.id] = sym_method_desc
      let regexp_proto : Value = Value::Object({
        bag: {
          properties: regexp_proto_props,
          symbol_properties: regexp_sym_props,
          descriptors: regexp_proto_descs,
          symbol_descriptors: regexp_sym_descs,
        },
        prototype: obj_proto,
        callable: None,
        class_name: "Object",
        extensible: true,
        arraybuffer_state: None,
      })
      realm_state.regexp_prototype.val = Some(regexp_proto)
      // Set RegExp.prototype on the constructor
      match env.bindings.get("RegExp") {
        Some(b) =>
          match b.value {
            Object(ctor_data) => {
              ctor_data.bag.properties["prototype"] = regexp_proto
              ctor_data.bag.descriptors["prototype"] = {
                writable: false,
                enumerable: false,
                configurable: false,
                getter: None,
                setter: None,
                is_accessor: false,
              }
            }
            _ => ()
          }
        None => ()
      }
    }
    None => ()
  }

  mark_builtin_setup_phase(profile, "regexp")

  // Set up iterator protocol on Array and String prototypes
  // Use try/catch since setup_iterator_protocol can raise errors
  setup_iterator_protocol(env, realm_state) catch {
    _ => () // Ignore errors during initialization
  }

  mark_builtin_setup_phase(profile, "iterator_protocol")

  // Set up Map and Set collections
  setup_map_set_builtins(env, realm_state)
  mark_builtin_setup_phase(profile, "map_set")

  // Set up Promise constructor and prototype
  setup_promise(env, realm_state)
  mark_builtin_setup_phase(profile, "promise")

  // Set up Date constructor and prototype
  setup_date_builtins(env, well_known_symbols, realm_state)
  mark_builtin_setup_phase(profile, "date")

  // Set up timer APIs (setTimeout, clearTimeout, setInterval, clearInterval)
  setup_timers(env)
  mark_builtin_setup_phase(profile, "timers")

  // Set up Proxy constructor and Proxy.revocable
  setup_proxy_builtins(env)
  mark_builtin_setup_phase(profile, "proxy")

  // Set up Reflect global object
  setup_reflect_builtins(env, well_known_symbols)
  mark_builtin_setup_phase(profile, "reflect")

  // Set up ArrayBuffer, TypedArray, and DataView
  setup_arraybuffer_builtins(env, well_known_symbols, realm_state)
  setup_typedarray_builtins(env, well_known_symbols, realm_state)
  setup_dataview_builtins(env, well_known_symbols, realm_state)
  mark_builtin_setup_phase(profile, "arraybuffer_typedarray_dataview")

  // Set up WeakMap and WeakSet
  setup_weakmap_set_builtins(env, well_known_symbols, realm_state)
  mark_builtin_setup_phase(profile, "weak_collections")

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
                match ctor_data.bag.properties.get("prototype") {
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

  mark_builtin_setup_phase(profile, "final_prototype_patching")

  // Add Symbol.species getter to built-in constructors (Array, RegExp, Map, Set)
  // Per spec: static get [Symbol.species]() { return this; }
  let species_getter = @runtime.make_method_func(
    name="get [Symbol.species]",
    length=0,
    fn(this_val, _args) { this_val },
  )
  let species_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(species_getter),
    setter: None,
    is_accessor: true,
  }
  let ctors_to_add_species = ["Array", "RegExp", "Map", "Set"]
  for ctor_name in ctors_to_add_species {
    let ctor_val = env.get(ctor_name) catch { _ => Undefined }
    match ctor_val {
      Object(ctor_data) => {
        let sp_sym = well_known_symbols.species
        ctor_data.bag.symbol_properties[sp_sym.id] = Undefined
        ctor_data.bag.symbol_descriptors[sp_sym.id] = species_desc
      }
      _ => ()
    }
  }

  mark_builtin_setup_phase(profile, "species")

  // Add Function.prototype[Symbol.hasInstance]
  let has_instance_sym = well_known_symbols.has_instance
  let has_instance_fn = @runtime.make_interp_method_func(
    name="[Symbol.hasInstance]",
    length=1,
    fn(interp, this_val, args) raise {
      // OrdinaryHasInstance(C, O)
      let o = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(this_val) {
        return Value::Bool(false)
      }
      // Step 3 of OrdinaryHasInstance: If O is not an Object, return false.
      // MUST precede step 4's Get(C, "prototype") — both because primitives
      // must not trigger step 5's TypeError, and because a getter on "prototype"
      // must not observe a call when the short-circuit would have fired first.
      if !@runtime.is_object_value(o) {
        return Value::Bool(false)
      }
      // Steps 4-5 of OrdinaryHasInstance: Get(C, "prototype"); if not Object, TypeError.
      // Exception: return false when no own "prototype" bag entry exists (non-constructable
      // functions like bound/arrow/method callables have no prototype property at all).
      // Explicitly setting F.prototype = undefined must throw TypeError per step 6.
      let loc = @token.Loc::default()
      let p = interp.get_property(this_val, "prototype", loc)
      if @runtime.is_object_value(p) {
        @runtime.instanceof_prototype_chain(o, p, interp)
      } else if p is Undefined {
        let explicitly_set = match this_val {
          Object(d) => d.bag.properties.get("prototype") is Some(Undefined)
          _ => false
        }
        if explicitly_set {
          raise @errors.TypeError(
            message="Function has non-object prototype in instanceof check",
          )
        } else {
          Value::Bool(false)
        }
      } else {
        raise @errors.TypeError(
          message="Function has non-object prototype in instanceof check",
        )
      }
    },
  )
  match env.bindings.get("[[FunctionPrototype]]") {
    Some(binding) =>
      match binding.value {
        Object(fp_data) => {
          fp_data.bag.symbol_properties[has_instance_sym.id] = has_instance_fn
          fp_data.bag.symbol_descriptors[has_instance_sym.id] = {
            writable: false,
            enumerable: false,
            configurable: false,
            getter: None,
            setter: None,
            is_accessor: false,
          }
        }
        _ => ()
      }
    None => ()
  }
  mark_builtin_setup_phase(profile, "has_instance")
  stamp_realm_functions_from_env(env, realm_state)
  mark_builtin_setup_phase(profile, "final_realm_stamp")
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
/// Build a $262 handle object whose methods are bound to `ri` via NativeCallable
/// closures. Uses NativeCallable (not InterpreterCallable) so that evalScript
/// always executes in ri's global scope, not the caller's realm.
/// Recursive createRealm calls go through ri.stdlib_hooks.create_realm()
/// so all nested realms are also fully wired.
fn make_realm_dollar262(ri : Interpreter) -> Value raise Error {
  ri.with_active_value(fn() {
    let realm_props : Map[String, Value] = {}
    realm_props["global"] = ri.global_this
    realm_props["gc"] = @runtime.make_native_func(
      name="gc",
      realm_state=Some(ri.realm_state),
      fn(_a) { Undefined },
    )
    realm_props["evalScript"] = @runtime.make_native_func(
      name="evalScript",
      length=1,
      realm_state=Some(ri.realm_state),
      fn(es_args) raise {
        let code = if es_args.length() > 0 {
          match es_args[0] {
            Value::String_(s) => s
            _ => es_args[0].to_string()
          }
        } else {
          ""
        }
        let prog = @parser.parse(code)
        ri.run(prog.stmts)
      },
    )
    realm_props["createRealm"] = @runtime.make_native_func(
      name="createRealm",
      realm_state=Some(ri.realm_state),
      _a => {
        let inner = (ri.stdlib_hooks.create_realm)()
        make_realm_dollar262(inner)
      },
    )
    realm_props["detachArrayBuffer"] = @runtime.make_native_func(
      name="detachArrayBuffer",
      length=1,
      realm_state=Some(ri.realm_state),
      fn(a) raise {
        if a.length() == 0 {
          raise @errors.TypeError(
            message="$262.detachArrayBuffer requires an ArrayBuffer argument",
          )
        }
        if detach_arraybuffer_value(a[0], ri.realm_state) {
          Undefined
        } else {
          raise @errors.TypeError(
            message="$262.detachArrayBuffer requires an ArrayBuffer argument",
          )
        }
      },
    )
    Value::Object({
      bag: {
        properties: realm_props,
        symbol_properties: {},
        descriptors: {},
        symbol_descriptors: {},
      },
      prototype: Null,
      callable: None,
      class_name: "Object",
      extensible: true,
      arraybuffer_state: None,
    })
  })
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
  let realm_state = match env.realm_state {
    Some(state) => state
    None => {
      let state = @runtime.RealmState()
      env.realm_state = Some(state)
      state
    }
  }
  // print() - host-provided print function for test262 harness compatibility.
  // Joins arguments with spaces and appends to output (like console.log).
  let print_func = @runtime.make_native_func(
    name="print",
    realm_state=Some(realm_state),
    fn(args) {
      let parts : Array[String] = args.map(fn(a) { a.to_string() })
      output.push(parts.join(" "))
      Undefined
    },
  )
  env.def_builtin("print", print_func)

  // $262.agent - stub object for agent/worker testing (Atomics/SharedArrayBuffer).
  // All methods throw because the engine has no multi-agent support.
  let agent_props : Map[String, Value] = {}
  agent_props["start"] = @runtime.make_native_func(
    name="start",
    realm_state=Some(realm_state),
    fn(_args) raise {
      raise @errors.TypeError(message="$262.agent.start is not supported")
    },
  )
  agent_props["broadcast"] = @runtime.make_native_func(
    name="broadcast",
    realm_state=Some(realm_state),
    fn(_args) raise {
      raise @errors.TypeError(message="$262.agent.broadcast is not supported")
    },
  )
  agent_props["getReport"] = @runtime.make_native_func(
    name="getReport",
    realm_state=Some(realm_state),
    fn(_args) raise {
      raise @errors.TypeError(message="$262.agent.getReport is not supported")
    },
  )
  agent_props["sleep"] = @runtime.make_native_func(
    name="sleep",
    realm_state=Some(realm_state),
    fn(_args) raise {
      raise @errors.TypeError(message="$262.agent.sleep is not supported")
    },
  )
  agent_props["monotonicNow"] = @runtime.make_native_func(
    name="monotonicNow",
    realm_state=Some(realm_state),
    fn(_args) raise {
      raise @errors.TypeError(
        message="$262.agent.monotonicNow is not supported",
      )
    },
  )
  let agent : Value = Value::Object({
    bag: {
      properties: agent_props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })

  // $262 - the test262 host object providing host-level hooks.
  let dollar262_props : Map[String, Value] = {}
  dollar262_props["global"] = global_this
  dollar262_props["agent"] = agent
  dollar262_props["gc"] = @runtime.make_native_func(
    name="gc",
    realm_state=Some(realm_state),
    fn(_args) { Undefined },
  )

  // $262.createRealm() - creates a fresh realm with its own global environment
  // and returns a $262 handle bound to the new realm. The returned handle uses
  // NativeCallable closures so that evalScript always runs in the new realm
  // regardless of which interpreter invokes the method.
  dollar262_props["createRealm"] = @runtime.make_interp_method_func(
    name="createRealm",
    length=0,
    realm_state=Some(realm_state),
    (interp, _this_val, _args) => {
      let new_interp = (interp.stdlib_hooks.create_realm)()
      make_realm_dollar262(new_interp)
    },
  )

  // $262.evalScript(code) - parses and evaluates code as a script
  // in the current realm's global scope.
  dollar262_props["evalScript"] = @runtime.make_interp_method_func(
    name="evalScript",
    length=1,
    realm_state=Some(realm_state),
    fn(interp, _this_val, args) raise {
      let code = if args.length() > 0 {
        match args[0] {
          Value::String_(s) => s
          _ => args[0].to_string()
        }
      } else {
        ""
      }
      let prog = @parser.parse(code)
      interp.run(prog.stmts)
    },
  )
  dollar262_props["detachArrayBuffer"] = @runtime.make_native_func(
    name="detachArrayBuffer",
    length=1,
    realm_state=Some(realm_state),
    fn(args) raise {
      if args.length() == 0 {
        raise @errors.TypeError(
          message="$262.detachArrayBuffer requires an ArrayBuffer argument",
        )
      }
      if detach_arraybuffer_value(args[0], realm_state) {
        Undefined
      } else {
        raise @errors.TypeError(
          message="$262.detachArrayBuffer requires an ArrayBuffer argument",
        )
      }
    },
  )
  let dollar262 : Value = Value::Object({
    bag: {
      properties: dollar262_props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  env.def_builtin("$262", dollar262)

  // Mirror harness bindings onto the global object so that globalThis.$262,
  // this.$262, globalThis.print etc. also work (not just bare name resolution).
  match global_this {
    Object(data) => {
      data.bag.properties["$262"] = dollar262
      data.bag.properties["print"] = print_func
    }
    _ => ()
  }
}
