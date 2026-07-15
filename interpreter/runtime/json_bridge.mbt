///|
/// Internal failure used by the stable Engine JSON boundary.
pub(all) suberror JsonBridgeError {
  JsonBridgeFailure(String)
} derive(Debug)

///|
fn json_bridge_number_is_finite(value : Double) -> Bool {
  !value.is_nan() && value != 1.0 / 0.0 && value != -1.0 / 0.0
}

///|
/// Copy MoonBit JSON into a realm without consulting the realm's global JSON
/// object or invoking JavaScript code.
pub fn json_to_realm_value(
  realm_state : RealmState,
  json : Json,
) -> Value raise JsonBridgeError {
  match json {
    Json::Null => Null
    Json::True => Bool(true)
    Json::False => Bool(false)
    Json::String(value) => String_(value)
    Json::Number(value, ..) => {
      guard json_bridge_number_is_finite(value) else {
        raise JsonBridgeFailure("JSON numbers must be finite")
      }
      Number(value)
    }
    Json::Array(items) => {
      let values : Array[Value] = []
      for item in items {
        values.push(json_to_realm_value(realm_state, item))
      }
      make_array(values)
    }
    Json::Object(entries) => {
      let properties : Map[String, Value] = {}
      for entry in entries.iter() {
        let (key, value) = entry
        properties[key] = json_to_realm_value(realm_state, value)
      }
      make_object(
        properties,
        realm_state.get_obj_proto(),
        None,
        "Object",
        {},
        true,
      )
    }
  }
}

///|
fn json_bridge_same_container(left : Value, right : Value) -> Bool {
  match (left, right) {
    (Object(a), Object(b)) => physical_equal(a, b)
    (Array(a), Array(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
fn json_bridge_push_unique(
  stack : Array[Value],
  value : Value,
) -> Unit raise JsonBridgeError {
  for active in stack {
    if json_bridge_same_container(active, value) {
      raise JsonBridgeFailure("cyclic JavaScript values are not JSON data")
    }
  }
  stack.push(value)
}

///|
fn json_bridge_value_to_json(
  value : Value,
  object_prototype : Value,
  stack : Array[Value],
) -> Json raise JsonBridgeError {
  match value {
    Null => Json::null()
    Bool(value) => Json::boolean(value)
    String_(value) => Json::string(value)
    Number(value) => {
      guard json_bridge_number_is_finite(value) else {
        raise JsonBridgeFailure("JavaScript numbers must be finite")
      }
      Json::number(value)
    }
    Undefined => raise JsonBridgeFailure("undefined is not JSON data")
    Symbol(_) => raise JsonBridgeFailure("Symbol values are not JSON data")
    Promise(_) =>
      raise JsonBridgeFailure(
        "Promise results are asynchronous; call_json only accepts synchronous JSON results",
      )
    Proxy(_) =>
      raise JsonBridgeFailure(
        "Proxy values are not accepted because JSON conversion must not execute traps",
      )
    Map(_) => raise JsonBridgeFailure("Map values are not JSON data")
    Set(_) => raise JsonBridgeFailure("Set values are not JSON data")
    Array(data) => {
      guard data.holes.length() == 0 else {
        raise JsonBridgeFailure("sparse arrays are not accepted as JSON data")
      }
      guard data.bag.properties.length() == 0 &&
        data.bag.descriptors.length() == 0 &&
        data.bag.symbol_properties.length() == 0 &&
        data.bag.symbol_descriptors.length() == 0 else {
        raise JsonBridgeFailure(
          "arrays with custom properties or descriptors are not accepted as JSON data",
        )
      }
      json_bridge_push_unique(stack, value)
      let items : Array[Json] = []
      for item in data.elements {
        items.push(json_bridge_value_to_json(item, object_prototype, stack))
      }
      ignore(stack.pop())
      Json::array(items)
    }
    Object(data) => {
      let has_plain_prototype = data.prototype is Null ||
        strict_equal(data.prototype, object_prototype)
      guard data.class_name == "Object" &&
        data.callable is None &&
        has_plain_prototype else {
        raise JsonBridgeFailure(
          "only plain non-callable objects are accepted as JSON data",
        )
      }
      guard data.bag.symbol_properties.length() == 0 &&
        data.bag.symbol_descriptors.length() == 0 else {
        raise JsonBridgeFailure(
          "objects with symbol properties are not accepted as JSON data",
        )
      }
      guard data.bag.internal_slots.length() == 0 &&
        data.bag.host_slots.length() == 0 else {
        raise JsonBridgeFailure(
          "objects with internal or host state are not accepted as JSON data",
        )
      }
      json_bridge_push_unique(stack, value)
      let entries : Map[String, Json] = {}
      for entry in data.bag.properties.iter() {
        let (key, property) = entry
        match data.bag.descriptors.get(key) {
          Some(descriptor) if descriptor.is_accessor =>
            raise JsonBridgeFailure(
              "accessor properties are not accepted as JSON data: " + key,
            )
          Some(descriptor) if !descriptor.enumerable =>
            raise JsonBridgeFailure(
              "non-enumerable properties are not accepted as JSON data: " + key,
            )
          _ =>
            entries[key] = json_bridge_value_to_json(
              property, object_prototype, stack,
            )
        }
      }
      ignore(stack.pop())
      Json::object(entries)
    }
  }
}

///|
/// Copy a runtime value into strict JSON data without performing property
/// lookup, calling getters or `toJSON`, or consulting a mutable global.
pub fn realm_value_to_json(
  realm_state : RealmState,
  value : Value,
) -> Json raise JsonBridgeError {
  json_bridge_value_to_json(value, realm_state.get_obj_proto(), [])
}
