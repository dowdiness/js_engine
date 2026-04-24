///|
pub fn is_truthy(val : Value) -> Bool {
  match val {
    Number(n) => n != 0.0 && !n.is_nan()
    String_(s) => s.length() > 0
    Bool(b) => b
    Null => false
    Undefined => false
    Object(_) => true
    Array(_) => true
    Symbol(_) => true // Symbols are always truthy
    Map(_) => true // Maps are always truthy
    Set(_) => true // Sets are always truthy
    Promise(_) => true // Promises are always truthy
    Proxy(_) => true // Proxies are always truthy
  }
}

///|
/// Global ref to current interpreter, set during execution so that
/// ToPrimitive can call user-defined valueOf/toString/@@toPrimitive
/// from NativeCallable builtins that do not receive an explicit interpreter.
let current_interpreter : Ref[Interpreter?] = { val: None }

///|
/// Call a callable value, dispatching to the interpreter for UserFunc types.
/// Supports all callable types including user-defined functions.
/// Pass `interp` explicitly when available; falls back to the module global.
pub fn call_callable_direct(
  callable_val : Value,
  this_val : Value,
  args : Array[Value],
  interp? : Interpreter? = None,
) -> Value raise Error {
  match callable_val {
    Object(obj_data) =>
      match obj_data.callable {
        Some(MethodCallable(_, f)) => f(this_val, args)
        Some(NativeCallable(_, f)) => f(args)
        Some(NonConstructableCallable(_, f)) => f(args)
        Some(UserFunc(_))
        | Some(ArrowFunc(_))
        | Some(UserFuncExt(_))
        | Some(ArrowFuncExt(_))
        | Some(BoundFunc(_, _, _))
        | Some(InterpreterCallable(_, _))
        | Some(NonConstructableInterpreterCallable(_, _))
        | Some(ClassConstructor(_)) => {
          // Prefer explicitly passed interp, fall back to module global
          let effective = match interp {
            Some(_) => interp
            None => current_interpreter.val
          }
          match effective {
            Some(ip) =>
              ip.call_value(callable_val, this_val, args, @token.Loc::default())
            None =>
              raise @errors.TypeError(
                message="Cannot call user function without interpreter context",
              )
          }
        }
        _ => raise @errors.TypeError(message="Value is not callable")
      }
    _ => raise @errors.TypeError(message="Value is not callable")
  }
}

///|
/// SetFunctionName: set name property on anonymous functions per ES2015+.
/// Only sets name if the current name is empty (anonymous).
pub fn set_function_name(val : Value, name : String) -> Unit {
  match val {
    Object(data) =>
      match data.callable {
        Some(_) =>
          // Only set if current name is empty (anonymous)
          match data.bag.properties.get("name") {
            Some(String_(s)) =>
              if s == "" {
                data.bag.properties["name"] = String_(name)
              }
            None => data.bag.properties["name"] = String_(name)
            _ => ()
          }
        None => ()
      }
    _ => ()
  }
}

///|
/// Check if a value is callable
pub fn is_callable(val : Value) -> Bool {
  match val {
    Object(obj_data) =>
      match obj_data.callable {
        Some(_) => true
        None => false
      }
    _ => false
  }
}

///|
/// Look up a string-keyed property on an object, walking the prototype chain.
/// HasProperty: check if a named property exists on the object or its prototype chain
pub fn has_property(
  val : Value,
  name : String,
  interp? : Interpreter? = None,
) -> Bool {
  match val {
    Object(data) => {
      // Pure slot-presence check per ES [[HasProperty]] — must NOT invoke getters.
      // Route through has_object_property (uses .contains(), no getter calls) when
      // an interpreter is available; fall back to own-slot only when there is none.
      let effective = match interp {
        Some(_) => interp
        None => current_interpreter.val
      }
      match effective {
        Some(ip) =>
          ip.has_object_property(data, String_(name)) catch {
            _ => false
          }
        None =>
          data.bag.properties.contains(name) ||
          data.bag.descriptors.contains(name)
      }
    }
    Array(data) => {
      if name == "length" {
        return true
      }
      try {
        let n = @string.parse_double(name)
        let i = n.to_int()
        if i.to_double() == n && i >= 0 && i < data.elements.length() {
          return true
        }
      } catch {
        _ => ()
      }
      if get_array_named_prop(data, name) is Some(_) {
        return true
      }
      // Walk Array.prototype chain for inherited properties
      let effective = match interp {
        Some(_) => interp
        None => current_interpreter.val
      }
      match effective {
        Some(ip) => {
          let ctor = ip.global.get("Array") catch { _ => return false }
          match ctor {
            Object(ctor_data) =>
              match ctor_data.bag.properties.get("prototype") {
                Some(Object(proto_data)) =>
                  ip.has_object_property(proto_data, String_(name)) catch {
                    _ => false
                  }
                _ => false
              }
            _ => false
          }
        }
        None => false
      }
    }
    _ => false
  }
}

///|
/// Invoke bag.descriptors[name].getter with obj_val as receiver, if one exists.
/// Returns Some(result) if an accessor getter was found and invoked (or if no
/// interpreter is available, Some(Undefined) signals property existence).
/// Returns None if no accessor descriptor with a getter exists for name.
fn invoke_accessor_getter(
  bag : PropertyBag,
  name : String,
  obj_val : Value,
  effective : Interpreter?,
) -> Value? raise Error {
  match bag.descriptors.get(name) {
    Some(desc) =>
      match desc.getter {
        Some(getter_fn) =>
          match effective {
            Some(_) =>
              Some(
                call_callable_direct(getter_fn, obj_val, [], interp=effective),
              )
            None => Some(Undefined)
          }
        None => None
      }
    None => None
  }
}

///|
/// Look up a string-keyed property on an object, walking the prototype chain.
/// Handles both data properties (bag.properties) and accessor properties
/// (bag.descriptors with getter), invoking getters with obj_val as receiver.
fn lookup_property_chain(
  obj_val : Value,
  data : ObjectData,
  name : String,
  interp? : Interpreter? = None,
) -> Value? raise Error {
  let effective = match interp {
    Some(_) => interp
    None => current_interpreter.val
  }
  // Descriptor check first: accessors write Undefined into bag.properties as a
  // sentinel (see apply_descriptor_to_bag / eval_expr ObjectLit Get/Set arms),
  // so checking bag.properties first would return that sentinel and skip the
  // getter. Mirror get_property_of_object: descriptor → data.
  match invoke_accessor_getter(data.bag, name, obj_val, effective) {
    Some(v) => return Some(v)
    None => ()
  }
  match data.bag.properties.get(name) {
    Some(v) => return Some(v)
    None => ()
  }
  // Walk prototype chain
  let mut current = data.prototype
  let mut func_fallback_used = false
  while true {
    match current {
      Object(proto_data) => {
        match invoke_accessor_getter(proto_data.bag, name, obj_val, effective) {
          Some(v) => return Some(v)
          None => ()
        }
        match proto_data.bag.properties.get(name) {
          Some(v) => return Some(v)
          None => ()
        }
        current = proto_data.prototype
      }
      Null =>
        // For function objects, fall back to Function.prototype once
        if !func_fallback_used {
          match data.callable {
            Some(_) =>
              match effective {
                Some(ip) => {
                  let fp = ip.global.get("[[FunctionPrototype]]") catch {
                    _ => break
                  }
                  func_fallback_used = true
                  current = fp
                }
                None => break
              }
            None => break
          }
        } else {
          break
        }
      _ => break
    }
  }
  None
}

///|
/// Look up a symbol-keyed property on an object, walking the prototype chain.
/// Also handles getter descriptors - invokes them and returns the result.
pub fn lookup_symbol_property_chain(
  obj_val : Value,
  data : ObjectData,
  sym_id : Int,
  interp? : Interpreter? = None,
) -> Value? raise Error {
  // Check own symbol descriptors for getter first
  match data.bag.symbol_descriptors.get(sym_id) {
    Some(desc) =>
      match desc.getter {
        Some(getter_fn) => {
          let result = call_callable_direct(getter_fn, obj_val, [], interp~)
          return Some(result)
        }
        None => ()
      }
    None => ()
  }
  // Check own symbol properties
  match data.bag.symbol_properties.get(sym_id) {
    Some(v) => return Some(v)
    None => ()
  }
  // Walk prototype chain
  let mut current = data.prototype
  while true {
    match current {
      Object(proto_data) => {
        // Check symbol descriptors for getter
        match proto_data.bag.symbol_descriptors.get(sym_id) {
          Some(desc) =>
            match desc.getter {
              Some(getter_fn) => {
                let result = call_callable_direct(
                  getter_fn,
                  obj_val,
                  [],
                  interp~,
                )
                return Some(result)
              }
              None => ()
            }
          None => ()
        }
        match proto_data.bag.symbol_properties.get(sym_id) {
          Some(v) => return Some(v)
          None => current = proto_data.prototype
        }
      }
      _ => break
    }
  }
  None
}

///|
/// ToPrimitive(input, hint "number") - converts an object to a primitive value.
/// Follows the ECMAScript spec: check @@toPrimitive, then valueOf, then toString.
fn to_primitive_number(
  obj_val : Value,
  data : ObjectData,
  interp? : Interpreter? = None,
) -> Value raise Error {
  // Step 1: Check for Symbol.toPrimitive
  let to_prim_sym = get_toprimitive_symbol()
  match lookup_symbol_property_chain(obj_val, data, to_prim_sym.id, interp~) {
    Some(exotic_to_prim) => {
      // If it's not callable, throw TypeError (GetMethod step 4)
      if !is_callable(exotic_to_prim) {
        raise @errors.TypeError(message="Symbol.toPrimitive is not a function")
      }
      // Call it with hint "number"
      let result = call_callable_direct(
        exotic_to_prim,
        obj_val,
        [String_("number")],
        interp~,
      )
      // If result is an object, throw TypeError
      match result {
        Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
          raise @errors.TypeError(
            message="Cannot convert object to primitive value",
          )
        _ => return result
      }
    }
    None => ()
  }
  // Step 2: OrdinaryToPrimitive with hint "number" - try valueOf first, then toString
  // Use interpreter for property lookup if available (handles synthetic props on functions etc.)
  let effective = match interp {
    Some(_) => interp
    None => current_interpreter.val
  }
  let value_of_fn : Value? = match
    lookup_property_chain(obj_val, data, "valueOf", interp~) {
    Some(f) => Some(f)
    None =>
      match effective {
        Some(ip) => {
          let v = ip.get_property(obj_val, "valueOf", @token.Loc::default()) catch {
            _ => Undefined
          }
          if is_callable(v) {
            Some(v)
          } else {
            None
          }
        }
        None => None
      }
  }
  match value_of_fn {
    Some(vo_fn) =>
      if is_callable(vo_fn) {
        let result = call_callable_direct(vo_fn, obj_val, [], interp~)
        match result {
          Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => () // result is object, try toString next
          _ => return result
        }
      }
    None => ()
  }
  let to_string_fn : Value? = match
    lookup_property_chain(obj_val, data, "toString", interp~) {
    Some(f) => Some(f)
    None =>
      match effective {
        Some(ip) => {
          let v = ip.get_property(obj_val, "toString", @token.Loc::default()) catch {
            _ => Undefined
          }
          if is_callable(v) {
            Some(v)
          } else {
            None
          }
        }
        None => None
      }
  }
  match to_string_fn {
    Some(ts_fn) =>
      if is_callable(ts_fn) {
        let result = call_callable_direct(ts_fn, obj_val, [], interp~)
        match result {
          Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
            raise @errors.TypeError(
              message="Cannot convert object to primitive value",
            )
          _ => return result
        }
      }
    None => ()
  }
  raise @errors.TypeError(message="Cannot convert object to primitive value")
}

///|
/// ToPrimitive(input, hint "default") - for + operator.
/// Same as "number" except passes "default" to @@toPrimitive.
pub fn to_primitive_default(
  obj_val : Value,
  data : ObjectData,
  interp? : Interpreter? = None,
) -> Value raise Error {
  // Step 1: Check for Symbol.toPrimitive
  let to_prim_sym = get_toprimitive_symbol()
  match lookup_symbol_property_chain(obj_val, data, to_prim_sym.id, interp~) {
    Some(exotic_to_prim) => {
      if !is_callable(exotic_to_prim) {
        raise @errors.TypeError(message="Symbol.toPrimitive is not a function")
      }
      // Call it with hint "default"
      let result = call_callable_direct(
        exotic_to_prim,
        obj_val,
        [String_("default")],
        interp~,
      )
      match result {
        Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
          raise @errors.TypeError(
            message="Cannot convert object to primitive value",
          )
        _ => return result
      }
    }
    None => ()
  }
  // Step 2: OrdinaryToPrimitive with hint "number" (default falls through to number behavior)
  to_primitive_number(obj_val, data, interp~)
}

///|
pub fn is_es_whitespace_cp(cp : Int) -> Bool {
  cp == 0x09 ||
  cp == 0x0A ||
  cp == 0x0B ||
  cp == 0x0C ||
  cp == 0x0D ||
  cp == 0x20 || // Space
  cp == 0x00A0 || // No-Break Space
  cp == 0xFEFF || // Zero Width No-Break Space (BOM)
  cp == 0x1680 || // OGHAM SPACE MARK
  (cp >= 0x2000 && cp <= 0x200A) || // EN QUAD through HAIR SPACE
  cp == 0x2028 || // Line Separator
  cp == 0x2029 || // Paragraph Separator
  cp == 0x202F || // NARROW NO-BREAK SPACE
  cp == 0x205F || // MEDIUM MATHEMATICAL SPACE
  cp == 0x3000 // IDEOGRAPHIC SPACE
}

///|
fn is_js_whitespace_code(ch : UInt16) -> Bool {
  is_es_whitespace_cp(ch.to_int())
}

///|
fn js_trim_whitespace(s : String) -> String {
  let len = s.length()
  let mut start = 0
  let mut end = len
  while start < end && is_js_whitespace_code(s[start]) {
    start = start + 1
  }
  while end > start && is_js_whitespace_code(s[end - 1]) {
    end = end - 1
  }
  if start == 0 && end == len {
    s
  } else {
    s[start:end].to_string()
  }
}

///|
pub fn to_number(
  val : Value,
  interp? : Interpreter? = None,
) -> Double raise Error {
  match val {
    Number(n) => n
    String_(s) => {
      // Trim whitespace per spec (including Unicode whitespace)
      let trimmed = js_trim_whitespace(s)
      if trimmed.length() == 0 {
        return 0.0
      }
      // Handle hex, binary, octal literals
      if trimmed.length() > 2 {
        let prefix = trimmed.view()[:2].to_string()
        if prefix == "0x" || prefix == "0X" {
          // Parse hex
          let hex_str = trimmed.view()[2:].to_string()
          if hex_str.length() == 0 {
            return 0.0 / 0.0
          }
          let mut result : Double = 0.0
          for ch in hex_str {
            let digit = if ch >= '0' && ch <= '9' {
              ch.to_int() - '0'.to_int()
            } else if ch >= 'a' && ch <= 'f' {
              ch.to_int() - 'a'.to_int() + 10
            } else if ch >= 'A' && ch <= 'F' {
              ch.to_int() - 'A'.to_int() + 10
            } else {
              return 0.0 / 0.0
            }
            result = result * 16.0 + digit.to_double()
          }
          return result
        }
        if prefix == "0b" || prefix == "0B" {
          // Parse binary
          let bin_str = trimmed.view()[2:].to_string()
          if bin_str.length() == 0 {
            return 0.0 / 0.0
          }
          let mut result : Double = 0.0
          for ch in bin_str {
            if ch == '0' {
              result = result * 2.0
            } else if ch == '1' {
              result = result * 2.0 + 1.0
            } else {
              return 0.0 / 0.0
            }
          }
          return result
        }
        if prefix == "0o" || prefix == "0O" {
          // Parse octal
          let oct_str = trimmed.view()[2:].to_string()
          if oct_str.length() == 0 {
            return 0.0 / 0.0
          }
          let mut result : Double = 0.0
          for ch in oct_str {
            if ch >= '0' && ch <= '7' {
              result = result * 8.0 + (ch.to_int() - '0'.to_int()).to_double()
            } else {
              return 0.0 / 0.0
            }
          }
          return result
        }
      }
      // Handle Infinity
      if trimmed == "Infinity" || trimmed == "+Infinity" {
        return 1.0 / 0.0
      }
      if trimmed == "-Infinity" {
        return -1.0 / 0.0
      }
      // Per spec: numeric separators (_) are only valid in source code literals,
      // not in Number() string-to-number conversion
      if trimmed.contains("_") {
        return 0.0 / 0.0
      }
      // Validate the string only contains valid Number() characters.
      // parse_double may accept non-spec things like "INFINITY", "inf", etc.
      let valid = trimmed
        .iter()
        .fold(init=true, fn(acc, ch) {
          acc &&
          (
            (ch >= '0' && ch <= '9') ||
            ch == '.' ||
            ch == 'e' ||
            ch == 'E' ||
            ch == '+' ||
            ch == '-'
          )
        })
      if !valid {
        return 0.0 / 0.0
      }
      @string.parse_double(trimmed) catch {
        _ => 0.0 / 0.0
      }
    }
    Bool(b) => if b { 1.0 } else { 0.0 }
    Null => 0.0
    Object(data) => {
      // Use ToPrimitive to convert object to a primitive, then ToNumber on the result
      let prim = to_primitive_number(Object(data), data, interp~)
      to_number(prim, interp~)
    }
    Array(arr_data) => {
      // Arrays: convert to string via join(","), then to number
      let s = arr_data.elements.map(fn(v) { v.to_string() }).join(",")
      if s.length() == 0 {
        0.0
      } else {
        @string.parse_double(s) catch {
          _ => 0.0 / 0.0
        }
      }
    }
    Undefined | Map(_) | Set(_) | Promise(_) | Proxy(_) => 0.0 / 0.0
    Symbol(_) =>
      raise @errors.TypeError(
        message="Cannot convert a Symbol value to a number",
      )
  }
}

///|
/// ToPrimitive(input, hint "string") - converts an object to a primitive value.
/// Follows the ECMAScript spec: check @@toPrimitive, then toString, then valueOf.
fn to_primitive_string(
  obj_val : Value,
  data : ObjectData,
  interp? : Interpreter? = None,
) -> Value raise Error {
  // Step 1: Check for Symbol.toPrimitive
  let to_prim_sym = get_toprimitive_symbol()
  match lookup_symbol_property_chain(obj_val, data, to_prim_sym.id, interp~) {
    Some(exotic_to_prim) => {
      if !is_callable(exotic_to_prim) {
        raise @errors.TypeError(message="Symbol.toPrimitive is not a function")
      }
      let result = call_callable_direct(
        exotic_to_prim,
        obj_val,
        [String_("string")],
        interp~,
      )
      match result {
        Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
          raise @errors.TypeError(
            message="Cannot convert object to primitive value",
          )
        _ => return result
      }
    }
    None => ()
  }
  // Step 2: OrdinaryToPrimitive with hint "string" - try toString first, then valueOf
  // Use interpreter for property lookup if available (handles synthetic props on functions etc.)
  let effective = match interp {
    Some(_) => interp
    None => current_interpreter.val
  }
  let to_string_fn : Value? = match
    lookup_property_chain(obj_val, data, "toString", interp~) {
    Some(f) => Some(f)
    None =>
      match effective {
        Some(ip) => {
          let v = ip.get_property(obj_val, "toString", @token.Loc::default()) catch {
            _ => Undefined
          }
          if is_callable(v) {
            Some(v)
          } else {
            None
          }
        }
        None => None
      }
  }
  match to_string_fn {
    Some(ts_fn) =>
      if is_callable(ts_fn) {
        let result = call_callable_direct(ts_fn, obj_val, [], interp~)
        match result {
          Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => () // result is object, try valueOf next
          _ => return result
        }
      }
    None => ()
  }
  let value_of_fn : Value? = match
    lookup_property_chain(obj_val, data, "valueOf", interp~) {
    Some(f) => Some(f)
    None =>
      match effective {
        Some(ip) => {
          let v = ip.get_property(obj_val, "valueOf", @token.Loc::default()) catch {
            _ => Undefined
          }
          if is_callable(v) {
            Some(v)
          } else {
            None
          }
        }
        None => None
      }
  }
  match value_of_fn {
    Some(vo_fn) =>
      if is_callable(vo_fn) {
        let result = call_callable_direct(vo_fn, obj_val, [], interp~)
        match result {
          Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
            raise @errors.TypeError(
              message="Cannot convert object to primitive value",
            )
          _ => return result
        }
      }
    None => ()
  }
  raise @errors.TypeError(message="Cannot convert object to primitive value")
}

///|
/// ECMAScript ToPropertyKey §7.1.19 — canonicalize a Value into a property
/// key. Symbols pass through; anything else is ToPrimitive(hint:"string") +
/// ToString via `to_js_string`, which invokes user-land Symbol.toPrimitive
/// / toString hooks (so the caller observes side-effects in spec order).
pub fn to_property_key(
  val : Value,
  interp? : Interpreter? = None,
) -> Value raise Error {
  match val {
    Symbol(_) => val
    _ => Value::String_(to_js_string(val, interp~))
  }
}

///|
/// ECMAScript ToString - converts a value to a string following the spec.
/// For objects, calls ToPrimitive(hint: "string") then converts result to string.
pub fn to_js_string(
  val : Value,
  interp? : Interpreter? = None,
) -> String raise Error {
  match val {
    String_(s) => s
    Number(n) => {
      let i = n.to_int()
      if i.to_double() == n && !n.is_inf() && !n.is_nan() {
        i.to_string()
      } else {
        n.to_string()
      }
    }
    Bool(b) => b.to_string()
    Null => "null"
    Undefined => "undefined"
    Symbol(_) =>
      raise @errors.TypeError(
        message="Cannot convert a Symbol value to a string",
      )
    Object(data) => {
      let prim = to_primitive_string(Object(data), data, interp~)
      to_js_string(prim, interp~)
    }
    Array(arr_data) =>
      // Arrays: join elements with commas
      arr_data.elements.map(fn(v) { v.to_string() }).join(",")
    Map(_) | Set(_) | Promise(_) | Proxy(_) => "[object Object]"
  }
}

///|
/// Interpreter method: ToNumber with explicit interpreter context.
pub fn Interpreter::to_number(
  self : Interpreter,
  val : Value,
) -> Double raise Error {
  to_number(val, interp=Some(self))
}

///|
/// Interpreter method: ToString with explicit interpreter context.
pub fn Interpreter::to_js_string(
  self : Interpreter,
  val : Value,
) -> String raise Error {
  to_js_string(val, interp=Some(self))
}

///|
/// Interpreter method: HasProperty with explicit interpreter context.
pub fn Interpreter::has_property(
  self : Interpreter,
  val : Value,
  name : String,
) -> Bool raise Error {
  self.has_property_key(val, String_(name))
}

///|
/// ES §7.3.11 `HasProperty` with a pre-computed property key.
pub fn Interpreter::has_property_key(
  self : Interpreter,
  val : Value,
  key : Value,
) -> Bool raise Error {
  match val {
    Proxy(proxy_data) => proxy_has_property_key(self, proxy_data, key)
    Object(data) => self.has_object_property(data, key)
    Array(data) => self.has_array_property(data, key)
    // Map/Set/Promise share a uniform shape: an expando bag plus a builtin
    // prototype reachable via globalThis[ctor].prototype. Implement
    // OrdinaryHasProperty (ES §7.3.11): own bag → proto chain → bool,
    // with no value inspection.
    Map(data) => self.has_bag_or_builtin_proto_key(data.bag, "Map", key)
    Set(data) => self.has_bag_or_builtin_proto_key(data.bag, "Set", key)
    Promise(data) => self.has_bag_or_builtin_proto_key(data.bag, "Promise", key)
    _ => false
  }
}

///|
fn Interpreter::has_object_property(
  self : Interpreter,
  data : ObjectData,
  key : Value,
) -> Bool raise Error {
  match key {
    Symbol(sym) =>
      if data.bag.symbol_properties.contains(sym.id) ||
        data.bag.symbol_descriptors.contains(sym.id) {
        return true
      }
    _ => {
      let name = to_js_string(key)
      if data.bag.properties.contains(name) ||
        data.bag.descriptors.contains(name) {
        return true
      }
    }
  }
  if self.has_property_on_proto(data.prototype, key) {
    return true
  }
  match data.callable {
    Some(_) => {
      let func_proto = self.global.get("[[FunctionPrototype]]") catch {
        _ => return false
      }
      self.has_property_on_proto(func_proto, key)
    }
    None => false
  }
}

///|
fn Interpreter::has_array_property(
  self : Interpreter,
  data : ArrayData,
  key : Value,
) -> Bool raise Error {
  match key {
    Symbol(sym) =>
      if get_array_symbol_prop(data, sym.id) is Some(_) ||
        data.bag.symbol_descriptors.contains(sym.id) {
        return true
      }
    _ => {
      let name = to_js_string(key)
      if name == "length" {
        return true
      }
      let idx = @string.parse_int(name) catch { _ => -1 }
      if idx >= 0 && idx.to_string() == name && idx < data.elements.length() {
        return true
      }
      if data.bag.properties.contains(name) ||
        data.bag.descriptors.contains(name) {
        return true
      }
    }
  }
  self.has_property_on_proto(get_array_prototype(self.global, data), key)
}

///|
fn Interpreter::has_property_on_proto(
  self : Interpreter,
  proto : Value,
  key : Value,
) -> Bool raise Error {
  match proto {
    Null | Undefined => false
    Proxy(proxy_data) => proxy_has_property_key(self, proxy_data, key)
    Object(proto_data) => self.has_object_property(proto_data, key)
    Array(arr_data) => self.has_array_property(arr_data, key)
    Map(data) => self.has_bag_or_builtin_proto_key(data.bag, "Map", key)
    Set(data) => self.has_bag_or_builtin_proto_key(data.bag, "Set", key)
    Promise(data) => self.has_bag_or_builtin_proto_key(data.bag, "Promise", key)
    _ => false
  }
}

///|
fn bag_has_key(bag : PropertyBag, key : Value) -> Bool raise Error {
  match key {
    Symbol(sym) =>
      bag.symbol_properties.contains(sym.id) ||
      bag.symbol_descriptors.contains(sym.id)
    _ => {
      let name = to_js_string(key)
      bag.properties.contains(name) || bag.descriptors.contains(name)
    }
  }
}

///|
/// OrdinaryHasProperty for exotic values whose prototype is stored globally
/// (Map, Set, Promise). Checks own-bag descriptors and properties first, then
/// walks the prototype chain starting from globalThis[ctor_name].prototype.
fn Interpreter::has_bag_or_builtin_proto_key(
  self : Interpreter,
  bag : PropertyBag,
  ctor_name : String,
  key : Value,
) -> Bool raise Error {
  if bag_has_key(bag, key) {
    return true
  }
  let ctor = self.global.get(ctor_name) catch { _ => return false }
  let current = match ctor {
    Object(ctor_data) =>
      match ctor_data.bag.properties.get("prototype") {
        Some(p) => p
        None => return false
      }
    _ => return false
  }
  self.has_property_on_proto(current, key)
}

///|
/// Interpreter method: ToPrimitive (default hint) with explicit interpreter context.
pub fn Interpreter::to_primitive_default(
  self : Interpreter,
  obj_val : Value,
  data : ObjectData,
) -> Value raise Error {
  to_primitive_default(obj_val, data, interp=Some(self))
}

///|
/// ECMAScript ToIndex: converts a value to a non-negative integer index.
/// Throws RangeError for negative values or values >= 2^53.
/// Returns 0 for undefined.
pub fn to_index(val : Value) -> Int raise {
  match val {
    Undefined => 0
    _ => {
      let n = to_number(val)
      if n.is_nan() || n == 0.0 {
        return 0
      }
      if n.is_inf() || n < 0.0 || n >= 9007199254740992.0 {
        raise @errors.RangeError(message="Invalid index")
      }
      n.to_int()
    }
  }
}

///|
pub fn to_int32(n : Double) -> Int {
  if n.is_nan() || n.is_inf() || n == 0.0 {
    return 0
  }
  // ECMAScript ToInt32: truncate toward zero, modulo 2^32, map to signed range
  let two32 : Double = 4294967296.0
  // Truncate toward zero
  let abs_n = n.abs()
  let sign : Double = if n < 0.0 { -1.0 } else { 1.0 }
  let truncated = abs_n.floor() * sign
  // Modulo 2^32 (always positive)
  let remainder = truncated % two32
  let pos_mod = if remainder < 0.0 { remainder + two32 } else { remainder }
  // Map to signed 32-bit range
  if pos_mod >= 2147483648.0 {
    (pos_mod - two32).to_int()
  } else {
    pos_mod.to_int()
  }
}

///|
pub fn type_of(val : Value) -> String {
  match val {
    Number(_) => "number"
    String_(_) => "string"
    Bool(_) => "boolean"
    Null => "object" // JS quirk
    Undefined => "undefined"
    Object(data) =>
      match data.callable {
        Some(_) => "function"
        None => "object"
      }
    Array(_) => "object"
    Symbol(_) => "symbol"
    Map(_) => "object"
    Set(_) => "object"
    Promise(_) => "object"
    Proxy(proxy_data) =>
      if proxy_data.is_callable {
        "function"
      } else {
        "object"
      }
  }
}
