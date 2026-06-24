///|
/// Canonical `[[OwnPropertyKeys]]` enumeration for the runtime (ES §10.1.11
/// OrdinaryOwnPropertyKeys plus the Array §10.4.2.1, String, Module, TypedArray
/// §10.4.5, and Proxy §10.5.11 exotic variants).
///
/// `Interpreter::own_property_keys` is the single enumerator every consumer
/// routes through: Object.getOwnPropertyNames / getOwnPropertySymbols /
/// getOwnPropertyDescriptors / defineProperties (this file), Reflect.ownKeys
/// (builtins_reflect.mbt), and the Proxy ownKeys target-key enumeration
/// (proxy_helpers.mbt). Key order is integer indices ascending, then string
/// keys in insertion order, then symbol keys in insertion order; Array holes
/// are omitted everywhere (§10.4.2.1).
///
/// Known limitation (pre-existing, out of scope for the #336 unification):
/// Array index keys beyond `Int` range (≥ 2^31, stored on the bag rather than
/// in `elements`) are emitted among the trailing string keys, after "length",
/// instead of merged into the ascending integer-index run.

///|
/// Append the own symbol keys of a property bag (resolved id -> SymbolData) to
/// `out`, in insertion order. Unresolvable ids are skipped.
fn append_resolved_symbol_keys(
  out : Array[Value],
  symbol_props : Map[Int, Value],
  sym_state : SymbolState,
) -> Unit {
  symbol_props.each(fn(sym_id, _raw) {
    match sym_state.get_symbol_by_id(sym_id) {
      Some(sym) => out.push(Value::Symbol(sym))
      None => ()
    }
  })
}

///|
fn append_bag_own_keys(
  keys : Array[Value],
  bag : PropertyBag,
  sym_state : SymbolState,
) -> Unit {
  for prop_name in sort_property_keys(bag.properties) {
    keys.push(Value::String_(prop_name))
  }
  append_resolved_symbol_keys(keys, bag.symbol_properties, sym_state)
}

///|
fn append_array_own_keys(
  keys : Array[Value],
  data : ArrayData,
  sym_state : SymbolState,
) -> Unit {
  let element_len = data.elements.length()
  for i in 0..<element_len {
    if !data.holes.contains(i) {
      keys.push(Value::String_(i.to_string()))
    }
  }
  keys.push(Value::String_("length"))
  for prop_name in sort_property_keys(data.bag.properties) {
    match array_index_of_key(prop_name) {
      Some(idx) if idx < element_len => continue
      _ => keys.push(Value::String_(prop_name))
    }
  }
  append_resolved_symbol_keys(keys, data.bag.symbol_properties, sym_state)
}

///|
/// Append a TypedArray's own keys (§10.4.5.2 IntegerIndexedExoticObject
/// `[[OwnPropertyKeys]]`): the canonical numeric indices `0 .. [[ArrayLength]]`
/// that are still valid (the buffer may have detached), then non-index string
/// bag keys in insertion order, then symbol keys.
fn append_typedarray_own_keys(
  interp : Interpreter,
  keys : Array[Value],
  data : ObjectData,
  sym_state : SymbolState,
) -> Unit {
  let length = typedarray_declared_length(data)
  for i in 0..<length {
    if (interp.stdlib_hooks.typedarray_is_valid_index)(
        data,
        i,
        interp.realm_state,
      ) {
      keys.push(Value::String_(i.to_string()))
    }
  }
  for prop_name in sort_property_keys(data.bag.properties) {
    if is_typedarray_own_index_key(prop_name, length) {
      continue
    }
    keys.push(Value::String_(prop_name))
  }
  append_resolved_symbol_keys(keys, data.bag.symbol_properties, sym_state)
}

///|
/// Canonical `[[OwnPropertyKeys]]` (ES §10.1.11 + Array/String/Module/TypedArray
/// /Proxy exotic variants). Returns the own keys of `val` as String_/Symbol
/// Values in spec order: integer indices ascending, then insertion-order string
/// keys, then symbol keys. Array holes are omitted; TypedArray integer indices
/// surface; the Proxy variant runs the ownKeys trap. Every own-key consumer in
/// the runtime/stdlib routes through this op.
pub fn Interpreter::own_property_keys(
  self : Interpreter,
  val : Value,
) -> Array[Value] raise Error {
  let sym_state = self.realm_state.symbols
  let keys : Array[Value] = []
  match val {
    Object(data) =>
      if data.class_name == "Module" {
        for prop_name in module_namespace_own_string_keys(data) {
          keys.push(Value::String_(prop_name))
        }
        append_resolved_symbol_keys(keys, data.bag.symbol_properties, sym_state)
      } else if is_typedarray_class(data.class_name) {
        append_typedarray_own_keys(self, keys, data, sym_state)
      } else {
        append_bag_own_keys(keys, data.bag, sym_state)
      }
    Array(data) => append_array_own_keys(keys, data, sym_state)
    Map(data) => append_bag_own_keys(keys, data.bag, sym_state)
    Set(data) => append_bag_own_keys(keys, data.bag, sym_state)
    Promise(data) => append_bag_own_keys(keys, data.bag, sym_state)
    Value::String_(s) => {
      // ToObject(String) characterization (§10.4.3): indexed character slots
      // then "length". Only reached through getOwnPropertyNames coercion.
      let chars = s.to_array()
      for i in 0..<chars.length() {
        keys.push(Value::String_(i.to_string()))
      }
      keys.push(Value::String_("length"))
    }
    Value::Proxy(proxy_data) =>
      match proxy_own_property_keys(self, proxy_data) {
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
/// Object.getOwnPropertyNames (§20.1.2.11): the String-typed own keys from the
/// canonical `[[OwnPropertyKeys]]` enumeration. Array holes and TypedArray
/// validity are handled by the canonical op.
pub fn own_string_property_names(
  interp : Interpreter,
  source : Value,
) -> Value raise Error {
  match source {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    _ => {
      let result : Array[Value] = []
      for key in interp.own_property_keys(source) {
        if key is Value::String_(_) {
          result.push(key)
        }
      }
      make_array(result)
    }
  }
}

///|
/// Object.getOwnPropertySymbols (§20.1.2.12): the Symbol-typed own keys from the
/// canonical `[[OwnPropertyKeys]]` enumeration.
pub fn own_symbol_properties(
  interp : Interpreter,
  source : Value,
) -> Value raise Error {
  match source {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    _ => {
      let result : Array[Value] = []
      for key in interp.own_property_keys(source) {
        if key is Value::Symbol(_) {
          result.push(key)
        }
      }
      make_array(result)
    }
  }
}
