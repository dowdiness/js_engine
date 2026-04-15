///|
/// ToObject (ES spec 7.1.13): convert primitives to their wrapper objects.
/// Throws TypeError for null/undefined. Objects/Arrays/etc pass through unchanged.
fn to_object(val : Value, interp : Interpreter) -> Value raise Error {
  match val {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => val
    Value::String_(s) => {
      let string_proto = interp.global.get("[[StringPrototype]]") catch {
        _ => Null
      }
      let props : Map[String, Value] = {}
      props["[[StringData]]"] = Value::String_(s)
      props["length"] = Value::Number(s.length().to_double())
      let chars = s.to_array()
      for i = 0; i < chars.length(); i = i + 1 {
        let buf = StringBuilder::new()
        buf.write_char(chars[i])
        props[i.to_string()] = Value::String_(buf.to_string())
      }
      let descs : Map[String, PropDescriptor] = {}
      descs["length"] = {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
      }
      for i = 0; i < chars.length(); i = i + 1 {
        descs[i.to_string()] = {
          writable: false,
          enumerable: true,
          configurable: false,
          getter: None,
          setter: None,
        }
      }
      Value::Object({
        properties: props,
        symbol_properties: {},
        prototype: string_proto,
        callable: None,
        class_name: "String",
        descriptors: descs,
        symbol_descriptors: {},
        extensible: true,
      })
    }
    Value::Number(n) => {
      let number_proto = interp.global.get("[[NumberPrototype]]") catch {
        _ => Null
      }
      Value::Object({
        properties: { "[[NumberData]]": Value::Number(n) },
        symbol_properties: {},
        prototype: number_proto,
        callable: None,
        class_name: "Number",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    }
    Value::Bool(b) => {
      let boolean_proto = interp.global.get("[[BooleanPrototype]]") catch {
        _ => Null
      }
      Value::Object({
        properties: { "[[BooleanData]]": Value::Bool(b) },
        symbol_properties: {},
        prototype: boolean_proto,
        callable: None,
        class_name: "Boolean",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    }
    Symbol(_) => {
      let symbol_proto = interp.global.get("[[SymbolPrototype]]") catch {
        _ => Null
      }
      Value::Object({
        properties: { "[[SymbolData]]": val },
        symbol_properties: {},
        prototype: symbol_proto,
        callable: None,
        class_name: "Symbol",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    }
  }
}

///|
fn validate_accessor(value : Value?, label : String) -> Unit raise Error {
  match value {
    Some(Object(o)) =>
      if o.callable is None {
        raise @errors.TypeError(
          message="\{label} must be a function: [object Object]",
        )
      }
    Some(Undefined) | None => ()
    Some(v) =>
      raise @errors.TypeError(
        message="\{label} must be a function: \{v.to_string()}",
      )
  }
}

///|
/// Get a property from a Value by walking the prototype chain (like [[Get]])
fn get_value_property(val : Value, key : String) -> (Bool, Value) {
  match val {
    Object(data) =>
      match data.properties.get(key) {
        Some(v) =>
          // Check for accessor descriptor
          match data.descriptors.get(key) {
            Some(desc) =>
              match desc.getter {
                Some(_) => (true, Undefined) // accessor, but can't call getter without interp
                None => (true, v)
              }
            None => (true, v)
          }
        None => {
          // Walk prototype chain
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) =>
                match proto_data.properties.get(key) {
                  Some(v) =>
                    match proto_data.descriptors.get(key) {
                      Some(desc) =>
                        match desc.getter {
                          Some(_) => return (true, Undefined)
                          None => return (true, v)
                        }
                      None => return (true, v)
                    }
                  None => current = proto_data.prototype
                }
              _ => break
            }
          }
          (false, Undefined)
        }
      }
    _ => (false, Undefined)
  }
}

///|
fn apply_property_descriptor(
  data : ObjectData,
  prop_name : String,
  desc : ObjectData,
) -> Unit raise Error {
  // Per spec ToPropertyDescriptor, use [[Get]] which walks prototype chain
  let desc_val = Value::Object(desc)
  let (has_get, _) = get_value_property(desc_val, "get")
  let (has_set, _) = get_value_property(desc_val, "set")
  let is_accessor = has_get || has_set
  let (has_value, _) = get_value_property(desc_val, "value")
  let (has_writable, _) = get_value_property(desc_val, "writable")
  let is_data = has_value || has_writable
  if is_accessor && is_data {
    raise @errors.TypeError(
      message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute, #<Object>",
    )
  }
  if is_accessor {
    if !data.properties.contains(prop_name) {
      data.properties[prop_name] = Undefined
    }
    let getter : Value? = match get_value_property(desc_val, "get") {
      (true, Undefined) => None
      (true, v) => Some(v)
      _ => None
    }
    let setter : Value? = match get_value_property(desc_val, "set") {
      (true, Undefined) => None
      (true, v) => Some(v)
      _ => None
    }
    validate_accessor(getter, "Getter")
    validate_accessor(setter, "Setter")
    let enumerable = match get_value_property(desc_val, "enumerable") {
      (true, v) => @runtime.is_truthy(v)
      _ => false
    }
    let configurable = match get_value_property(desc_val, "configurable") {
      (true, v) => @runtime.is_truthy(v)
      _ => false
    }
    data.descriptors[prop_name] = {
      writable: false,
      enumerable,
      configurable,
      getter,
      setter,
    }
  } else {
    match get_value_property(desc_val, "value") {
      (true, v) => data.properties[prop_name] = v
      _ =>
        if !data.properties.contains(prop_name) {
          data.properties[prop_name] = Undefined
        }
    }
    let writable = match get_value_property(desc_val, "writable") {
      (true, v) => @runtime.is_truthy(v)
      _ => false
    }
    let enumerable = match get_value_property(desc_val, "enumerable") {
      (true, v) => @runtime.is_truthy(v)
      _ => false
    }
    let configurable = match get_value_property(desc_val, "configurable") {
      (true, v) => @runtime.is_truthy(v)
      _ => false
    }
    data.descriptors[prop_name] = {
      writable,
      enumerable,
      configurable,
      getter: None,
      setter: None,
    }
  }
}

///|
/// Build a data property descriptor object {value, writable, enumerable, configurable}.
pub fn make_data_desc_obj(
  value : Value,
  writable : Bool,
  enumerable : Bool,
  configurable : Bool,
) -> Value {
  Value::Object({
    properties: {
      "value": value,
      "writable": Value::Bool(writable),
      "enumerable": Value::Bool(enumerable),
      "configurable": Value::Bool(configurable),
    },
    symbol_properties: {},
    prototype: @runtime.get_obj_proto(),
    callable: None,
    class_name: "Object",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Build an accessor property descriptor object {get, set, enumerable, configurable}.
pub fn make_accessor_desc_obj(
  getter_val : Value,
  setter_val : Value,
  enumerable : Bool,
  configurable : Bool,
) -> Value {
  Value::Object({
    properties: {
      "get": getter_val,
      "set": setter_val,
      "enumerable": Value::Bool(enumerable),
      "configurable": Value::Bool(configurable),
    },
    symbol_properties: {},
    prototype: @runtime.get_obj_proto(),
    callable: None,
    class_name: "Object",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

