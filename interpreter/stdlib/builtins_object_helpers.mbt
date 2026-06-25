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
        is_accessor: false,
      }
      for i = 0; i < chars.length(); i = i + 1 {
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
          internal_slots: {
            let m : Map[@runtime.InternalSlotKey, Value] = {}
            m[@runtime.StringData] = Value::String_(s)
            m
          },
        },
        prototype: string_proto,
        callable: None,
        class_name: "String",
        extensible: true,
        arraybuffer_state: None,
      })
    }
    Value::Number(n) => {
      let number_proto = interp.global.get("[[NumberPrototype]]") catch {
        _ => Null
      }
      Value::Object({
        bag: {
          properties: {},
          symbol_properties: {},
          descriptors: {},
          symbol_descriptors: {},
          internal_slots: {
            let m : Map[@runtime.InternalSlotKey, Value] = {}
            m[@runtime.NumberData] = Value::Number(n)
            m
          },
        },
        prototype: number_proto,
        callable: None,
        class_name: "Number",
        extensible: true,
        arraybuffer_state: None,
      })
    }
    Value::Bool(b) => {
      let boolean_proto = interp.global.get("[[BooleanPrototype]]") catch {
        _ => Null
      }
      Value::Object({
        bag: {
          properties: {},
          symbol_properties: {},
          descriptors: {},
          symbol_descriptors: {},
          internal_slots: {
            let m : Map[@runtime.InternalSlotKey, Value] = {}
            m[@runtime.BooleanData] = Value::Bool(b)
            m
          },
        },
        prototype: boolean_proto,
        callable: None,
        class_name: "Boolean",
        extensible: true,
        arraybuffer_state: None,
      })
    }
    Symbol(_) => {
      let symbol_proto = interp.global.get("[[SymbolPrototype]]") catch {
        _ => Null
      }
      Value::Object({
        bag: {
          properties: {},
          symbol_properties: {},
          descriptors: {},
          symbol_descriptors: {},
          internal_slots: {
            let m : Map[@runtime.InternalSlotKey, Value] = {}
            m[@runtime.SymbolData] = val
            m
          },
        },
        prototype: symbol_proto,
        callable: None,
        class_name: "Symbol",
        extensible: true,
        arraybuffer_state: None,
      })
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
  realm_state? : @runtime.RealmState? = None,
) -> Value {
  Value::Object({
    bag: {
      properties: {
        "value": value,
        "writable": Value::Bool(writable),
        "enumerable": Value::Bool(enumerable),
        "configurable": Value::Bool(configurable),
      },
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
      internal_slots: {},
    },
    prototype: @runtime.get_obj_proto(realm_state~),
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
/// Build an accessor property descriptor object {get, set, enumerable, configurable}.
pub fn make_accessor_desc_obj(
  getter_val : Value,
  setter_val : Value,
  enumerable : Bool,
  configurable : Bool,
  realm_state? : @runtime.RealmState? = None,
) -> Value {
  Value::Object({
    bag: {
      properties: {
        "get": getter_val,
        "set": setter_val,
        "enumerable": Value::Bool(enumerable),
        "configurable": Value::Bool(configurable),
      },
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
      internal_slots: {},
    },
    prototype: @runtime.get_obj_proto(realm_state~),
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
}
