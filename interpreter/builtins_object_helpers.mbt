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
    String_(s) => {
      let string_proto = interp.global.get("[[StringPrototype]]") catch {
        _ => Null
      }
      let props : Map[String, Value] = {}
      props["[[StringData]]"] = String_(s)
      props["length"] = Number(s.length().to_double())
      let chars = s.to_array()
      for i = 0; i < chars.length(); i = i + 1 {
        let buf = StringBuilder::new()
        buf.write_char(chars[i])
        props[i.to_string()] = String_(buf.to_string())
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
      Object({
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
    Number(n) => {
      let number_proto = interp.global.get("[[NumberPrototype]]") catch {
        _ => Null
      }
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
    }
    Bool(b) => {
      let boolean_proto = interp.global.get("[[BooleanPrototype]]") catch {
        _ => Null
      }
      Object({
        properties: { "[[BooleanData]]": Bool(b) },
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
      Object({
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
  let desc_val = Object(desc)
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
      (true, v) => is_truthy(v)
      _ => false
    }
    let configurable = match get_value_property(desc_val, "configurable") {
      (true, v) => is_truthy(v)
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
      (true, v) => is_truthy(v)
      _ => false
    }
    let enumerable = match get_value_property(desc_val, "enumerable") {
      (true, v) => is_truthy(v)
      _ => false
    }
    let configurable = match get_value_property(desc_val, "configurable") {
      (true, v) => is_truthy(v)
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
/// Validate non-configurable property constraints.
/// Throws TypeError if the proposed descriptor change violates invariants.
fn validate_non_configurable(
  existing : PropDescriptor,
  prop_display : String,
  is_accessor : Bool,
  is_data : Bool,
  has_value : Bool,
  new_writable : Bool?,
  new_enumerable : Bool?,
  new_configurable : Bool?,
  new_getter : Value?,
  new_setter : Value?,
  get_old_value : () -> Value,
  get_new_value : () -> Value?,
) -> Unit raise Error {
  if existing.configurable {
    return
  }
  let existing_is_accessor = existing.getter is Some(_) ||
    existing.setter is Some(_)
  // Cannot change between accessor and data
  if existing_is_accessor && is_data {
    raise @errors.TypeError(
      message="Cannot redefine non-configurable property: \{prop_display}",
    )
  }
  if !existing_is_accessor && is_accessor {
    raise @errors.TypeError(
      message="Cannot redefine non-configurable property: \{prop_display}",
    )
  }
  let enumerable_ok = match new_enumerable {
    Some(e) => e == existing.enumerable
    None => true
  }
  let configurable_ok = match new_configurable {
    Some(c) => c == existing.configurable
    None => true
  }
  // Non-configurable accessor: validate getter/setter identity
  if existing_is_accessor && is_accessor {
    let getter_ok = match new_getter {
      Some(g) =>
        match existing.getter {
          Some(eg) => strict_equal_val(g, eg)
          None => g is Undefined
        }
      None => true
    }
    let setter_ok = match new_setter {
      Some(s) =>
        match existing.setter {
          Some(es) => strict_equal_val(s, es)
          None => s is Undefined
        }
      None => true
    }
    if !(enumerable_ok && configurable_ok && getter_ok && setter_ok) {
      raise @errors.TypeError(
        message="Cannot redefine non-configurable property: \{prop_display}",
      )
    }
  }
  // Non-configurable data: validate writable/value
  if !existing_is_accessor && !is_accessor {
    let writable_ok = match new_writable {
      Some(w) => if !existing.writable && w { false } else { true }
      None => true
    }
    let value_ok = if !existing.writable && has_value {
      match get_new_value() {
        Some(v) => strict_equal_val(v, get_old_value())
        None => true
      }
    } else {
      true
    }
    if !(writable_ok && enumerable_ok && configurable_ok && value_ok) {
      raise @errors.TypeError(
        message="Cannot redefine non-configurable property: \{prop_display}",
      )
    }
  }
  // Generic descriptor (no accessor/data fields)
  if !is_accessor && !is_data {
    if !(enumerable_ok && configurable_ok) {
      raise @errors.TypeError(
        message="Cannot redefine non-configurable property: \{prop_display}",
      )
    }
  }
}
