///|
/// `[[OwnPropertyKeys]]`-class enumeration operations relocated from
/// `interpreter/stdlib/builtins_object_descriptors.mbt` so that stdlib calls a
/// runtime operation instead of reaching into PropertyBag / ArrayData
/// representation internals (architecture redesign Stage 8).
///
/// These reproduce the existing Object.getOwnPropertyNames /
/// getOwnPropertySymbols / getOwnPropertyDescriptors enumeration behavior
/// verbatim. They are intentionally NOT the canonical OrdinaryOwnPropertyKeys:
/// `collect_target_own_keys` (proxy_helpers.mbt) remains a separate enumeration
/// path with different array semantics. Unifying the two is tracked as a
/// follow-up slice, not done here.

///|
pub fn is_internal_array_bag_key(key : String) -> Bool {
  key.has_prefix("[[")
}

///|
fn is_hidden_internal_property_key(source : Value, key : String) -> Bool {
  let known_internal = key == "[[StringData]]" ||
    key == "[[NumberData]]" ||
    key == "[[BooleanData]]" ||
    key == "[[SymbolData]]" ||
    key == "[[PrimitiveValue]]" ||
    key == "[[ArrayLengthOverride]]" ||
    key == "[[TypedArrayName]]" ||
    key == "[[ViewedArrayBuffer]]" ||
    key == "[[ArrayBufferID]]" ||
    key == "[[ByteOffset]]" ||
    key == "[[ByteLength]]" ||
    key == "[[ArrayLength]]" ||
    key == "[[DateValue]]" ||
    key == "[[ArrayBufferByteLength]]" ||
    key == "[[RegExpStringIterator]]" ||
    key == "[[EvalFunctionReconcile]]"
  if !known_internal {
    return false
  }
  match source {
    Object(data) => data.class_name != "Object"
    Array(_) => key == "[[ArrayLengthOverride]]"
    _ => false
  }
}

///|
fn sort_visible_own_string_keys(
  source : Value,
  bag : PropertyBag,
) -> Array[String] {
  let int_keys : Array[String] = []
  let str_keys : Array[String] = []
  bag.properties.each(fn(k, _v) {
    if is_hidden_internal_property_key(source, k) {
      return
    }
    let idx = @string.parse_int(k) catch { _ => -1 }
    if idx >= 0 && idx.to_string() == k {
      int_keys.push(k)
    } else {
      str_keys.push(k)
    }
  })
  int_keys.sort_by(fn(a, b) {
    let na = @string.parse_int(a) catch { _ => 0 }
    let nb = @string.parse_int(b) catch { _ => 0 }
    na - nb
  })
  let result : Array[String] = []
  for k in int_keys {
    result.push(k)
  }
  for k in str_keys {
    result.push(k)
  }
  result
}

///|
fn append_bag_own_keys(
  keys : Array[Value],
  source : Value,
  bag : PropertyBag,
  sym_state : SymbolState,
) -> Unit {
  for prop_name in sort_visible_own_string_keys(source, bag) {
    keys.push(Value::String_(prop_name))
  }
  bag.symbol_properties.each(fn(sym_id, _raw) {
    match sym_state.get_symbol_by_id(sym_id) {
      Some(sym) => keys.push(Value::Symbol(sym))
      None => ()
    }
  })
}

///|
fn append_array_own_keys(
  keys : Array[Value],
  data : ArrayData,
  sym_state : SymbolState,
) -> Unit {
  let source = Value::Array(data)
  let element_len = data.elements.length()
  for i = 0; i < element_len; i = i + 1 {
    if !data.holes.contains(i) {
      keys.push(Value::String_(i.to_string()))
    }
  }
  keys.push(Value::String_("length"))
  for prop_name in sort_visible_own_string_keys(source, data.bag) {
    let idx = @string.parse_int(prop_name) catch { _ => -1 }
    if idx >= 0 && idx.to_string() == prop_name && idx < element_len {
      continue
    }
    keys.push(Value::String_(prop_name))
  }
  data.bag.symbol_properties.each(fn(sym_id, _raw) {
    match sym_state.get_symbol_by_id(sym_id) {
      Some(sym) => keys.push(Value::Symbol(sym))
      None => ()
    }
  })
}

///|
/// `[[OwnPropertyKeys]]` snapshot used by Object.getOwnPropertyDescriptors and
/// Object.defineProperties (§19.1.2.3 / §19.1.2.4 key snapshot). Preserves the
/// existing stdlib enumeration: hole-skipping for arrays, hidden engine-internal
/// `[[...]]` key filtering, integer-key-ascending then insertion-order string
/// keys, then symbol keys.
pub fn object_own_property_keys_snapshot(
  interp : Interpreter,
  source : Value,
) -> Array[Value] raise Error {
  let sym_state = interp.realm_state.symbols
  let keys : Array[Value] = []
  match source {
    Object(data) =>
      if data.class_name == "Module" {
        for prop_name in module_namespace_own_string_keys(data) {
          keys.push(Value::String_(prop_name))
        }
        data.bag.symbol_properties.each(fn(sym_id, _raw) {
          match sym_state.get_symbol_by_id(sym_id) {
            Some(sym) => keys.push(Value::Symbol(sym))
            None => ()
          }
        })
      } else {
        append_bag_own_keys(keys, source, data.bag, sym_state)
      }
    Array(data) => append_array_own_keys(keys, data, sym_state)
    Map(data) => append_bag_own_keys(keys, source, data.bag, sym_state)
    Set(data) => append_bag_own_keys(keys, source, data.bag, sym_state)
    Promise(data) => append_bag_own_keys(keys, source, data.bag, sym_state)
    Proxy(proxy_data) =>
      match proxy_own_property_keys(interp, proxy_data) {
        Value::Array(proxy_keys) =>
          for key in proxy_keys.elements {
            keys.push(key)
          }
        _ => ()
      }
    _ => ()
  }
  keys
}

///|
/// Object.getOwnPropertyNames enumeration (§19.1.2.10): own String-typed keys.
/// Preserves existing behavior, which for ordinary objects emits all visible
/// bag string keys (no hidden-internal filtering) and for arrays emits every
/// index slot plus "length".
pub fn own_string_property_names(
  interp : Interpreter,
  source : Value,
) -> Value raise Error {
  match source {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Value::Proxy(proxy_data) => {
      let all_keys = proxy_own_property_keys(interp, proxy_data)
      let result : Array[Value] = []
      match all_keys {
        Value::Array(arr) =>
          for key in arr.elements {
            match key {
              Value::String_(_) => result.push(key)
              _ => () // getOwnPropertyNames only returns strings
            }
          }
        _ => ()
      }
      make_array(result)
    }
    Object(data) => {
      let keys : Array[Value] = []
      let sorted = if data.class_name == "Module" {
        module_namespace_own_string_keys(data)
      } else {
        sort_property_keys(data.bag.properties)
      }
      for k in sorted {
        keys.push(Value::String_(k))
      }
      make_array(keys)
    }
    Value::Array(data) => {
      let keys : Array[Value] = []
      for i = 0; i < data.elements.length(); i = i + 1 {
        keys.push(Value::String_(i.to_string()))
      }
      keys.push(Value::String_("length"))
      let sorted = sort_property_keys(data.bag.properties)
      for k in sorted {
        if !is_internal_array_bag_key(k) {
          keys.push(Value::String_(k))
        }
      }
      make_array(keys)
    }
    Value::String_(s) => {
      let keys : Array[Value] = []
      let chars = s.to_array()
      for i = 0; i < chars.length(); i = i + 1 {
        keys.push(Value::String_(i.to_string()))
      }
      keys.push(Value::String_("length"))
      make_array(keys)
    }
    _ => make_array([])
  }
}

///|
/// Object.getOwnPropertySymbols enumeration (§19.1.2.11): own Symbol-typed keys.
pub fn own_symbol_properties(
  interp : Interpreter,
  source : Value,
) -> Value raise Error {
  let sym_state = interp.realm_state.symbols
  match source {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Value::Proxy(proxy_data) => {
      let all_keys = proxy_own_property_keys(interp, proxy_data)
      let result : Array[Value] = []
      match all_keys {
        Value::Array(arr) =>
          for key in arr.elements {
            match key {
              Value::Symbol(_) => result.push(key)
              _ => () // getOwnPropertySymbols only returns symbols
            }
          }
        _ => ()
      }
      make_array(result)
    }
    Object(data) => {
      let symbols : Array[Value] = []
      data.bag.symbol_properties.each(fn(sym_id, _val) {
        match sym_state.get_symbol_by_id(sym_id) {
          Some(sym_data) => symbols.push(Symbol(sym_data))
          None => ()
        }
      })
      make_array(symbols)
    }
    Value::Array(data) => {
      let symbols : Array[Value] = []
      data.bag.symbol_properties.each(fn(sym_id, _val) {
        match sym_state.get_symbol_by_id(sym_id) {
          Some(sym_data) => symbols.push(Symbol(sym_data))
          None => ()
        }
      })
      make_array(symbols)
    }
    _ => make_array([])
  }
}
