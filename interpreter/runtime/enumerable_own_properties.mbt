///|
/// `EnumerableOwnProperties`-class operations (ES2024 §7.3.25) relocated from
/// `interpreter/stdlib/builtins_object.mbt` so that stdlib calls a runtime
/// operation instead of reaching into PropertyBag / ArrayData representation
/// internals (architecture redesign Stage 8).
///
/// `object_keys` / `object_values` / `object_entries` reproduce the existing
/// `Object.keys` / `Object.values` / `Object.entries` behavior verbatim; the
/// stdlib factories become thin wrappers that only extract the argument.
///
/// The module-namespace string-key ordering uses the existing runtime helper
/// `module_namespace_own_string_keys` (lexical order, distinct from the
/// integer-index-first `[[OwnPropertyKeys]]` ordering of `sort_property_keys`).

///|
pub fn object_keys(interp : Interpreter, obj : Value) -> Value raise Error {
  match obj {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Value::Proxy(proxy_data) => {
      // Call [[OwnPropertyKeys]] via proxy trap, then filter to enumerable strings
      let all_keys = proxy_own_property_keys(interp, proxy_data)
      let result : Array[Value] = []
      match all_keys {
        Value::Array(arr) =>
          for key in arr.elements {
            match key {
              Value::String_(_) => result.push(key)
              _ => () // Object.keys only returns strings
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
        let enumerable = if data.class_name == "Module" {
          match interp.get_own_property(obj, String_(k)) {
            Some((desc, _)) => desc.enumerable
            None => false
          }
        } else {
          match data.bag.descriptors.get(k) {
            Some(d) => d.enumerable
            None => true
          }
        }
        if enumerable {
          keys.push(Value::String_(k))
        }
      }
      make_array(keys)
    }
    Value::String_(s) => {
      // String objects have enumerable indexed properties
      let keys : Array[Value] = []
      for i in 0..<s.length() {
        keys.push(Value::String_(i.to_string()))
      }
      make_array(keys)
    }
    Value::Array(data) => {
      // Array objects have enumerable indexed properties followed by
      // enumerable own named properties in their embedded bag.
      let keys : Array[Value] = []
      for i in 0..<data.elements.length() {
        if data.holes.contains(i) {
          continue
        }
        let key = i.to_string()
        let enumerable = match data.bag.descriptors.get(key) {
          Some(d) => d.enumerable
          None => true
        }
        if enumerable {
          keys.push(Value::String_(key))
        }
      }
      let sorted = sort_property_keys(data.bag.properties)
      for k in sorted {
        if is_internal_array_bag_key(k) {
          continue
        }
        let enumerable = match data.bag.descriptors.get(k) {
          Some(d) => d.enumerable
          None => true
        }
        if enumerable {
          keys.push(Value::String_(k))
        }
      }
      make_array(keys)
    }
    _ => make_array([])
  }
}

///|
pub fn object_values(interp : Interpreter, obj : Value) -> Value raise Error {
  match obj {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Object(data) => {
      let vals : Array[Value] = []
      let sorted = if data.class_name == "Module" {
        module_namespace_own_string_keys(data)
      } else {
        sort_property_keys(data.bag.properties)
      }
      for k in sorted {
        if data.class_name == "Module" {
          match interp.get_own_property(obj, String_(k)) {
            Some((desc, value)) if desc.enumerable => vals.push(value)
            _ => ()
          }
        } else {
          let enumerable = match data.bag.descriptors.get(k) {
            Some(d) => d.enumerable
            None => true
          }
          if enumerable {
            match data.bag.properties.get(k) {
              Some(v) => vals.push(v)
              None => ()
            }
          }
        }
      }
      make_array(vals)
    }
    Value::String_(s) => {
      // String objects have enumerable indexed properties
      let vals : Array[Value] = []
      let chars = s.to_array()
      for ch in chars {
        vals.push(Value::String_(ch.to_string()))
      }
      make_array(vals)
    }
    Value::Array(data) => {
      // Array objects - return array elements, then enumerable own
      // named properties from the embedded bag.
      let loc = @token.Loc::default()
      let vals : Array[Value] = []
      for i in 0..<data.elements.length() {
        if data.holes.contains(i) {
          continue
        }
        let key = i.to_string()
        match data.bag.descriptors.get(key) {
          Some({ enumerable: false, .. }) => ()
          Some({ getter: Some(g), .. }) =>
            vals.push(interp.call_value(g, obj, [], loc))
          _ => vals.push(data.elements[i])
        }
      }
      let sorted = sort_property_keys(data.bag.properties)
      for k in sorted {
        if is_internal_array_bag_key(k) {
          continue
        }
        let enumerable = match data.bag.descriptors.get(k) {
          Some(d) => d.enumerable
          None => true
        }
        if enumerable {
          match data.bag.properties.get(k) {
            Some(v) => vals.push(v)
            None => ()
          }
        }
      }
      make_array(vals)
    }
    _ => make_array([])
  }
}

///|
pub fn object_entries(interp : Interpreter, obj : Value) -> Value raise Error {
  match obj {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Object(data) => {
      let entries : Array[Value] = []
      let sorted = if data.class_name == "Module" {
        module_namespace_own_string_keys(data)
      } else {
        sort_property_keys(data.bag.properties)
      }
      for k in sorted {
        if data.class_name == "Module" {
          match interp.get_own_property(obj, String_(k)) {
            Some((desc, value)) if desc.enumerable =>
              entries.push(make_array([Value::String_(k), value]))
            _ => ()
          }
        } else {
          let enumerable = match data.bag.descriptors.get(k) {
            Some(d) => d.enumerable
            None => true
          }
          if enumerable {
            match data.bag.properties.get(k) {
              Some(v) => entries.push(make_array([Value::String_(k), v]))
              None => ()
            }
          }
        }
      }
      make_array(entries)
    }
    Value::String_(s) => {
      // String objects have enumerable indexed properties
      let entries : Array[Value] = []
      let chars = s.to_array()
      for i in 0..<chars.length() {
        entries.push(
          make_array([
            Value::String_(i.to_string()),
            Value::String_(chars[i].to_string()),
          ]),
        )
      }
      make_array(entries)
    }
    Value::Array(data) => {
      // Array objects - keys must be strings per spec.
      let loc = @token.Loc::default()
      let entries : Array[Value] = []
      for i in 0..<data.elements.length() {
        if data.holes.contains(i) {
          continue
        }
        let key = i.to_string()
        match data.bag.descriptors.get(key) {
          Some({ enumerable: false, .. }) => ()
          Some({ getter: Some(g), .. }) =>
            entries.push(
              make_array([
                Value::String_(key),
                interp.call_value(g, obj, [], loc),
              ]),
            )
          _ => entries.push(make_array([Value::String_(key), data.elements[i]]))
        }
      }
      let sorted = sort_property_keys(data.bag.properties)
      for k in sorted {
        if is_internal_array_bag_key(k) {
          continue
        }
        let enumerable = match data.bag.descriptors.get(k) {
          Some(d) => d.enumerable
          None => true
        }
        if enumerable {
          match data.bag.properties.get(k) {
            Some(v) => entries.push(make_array([Value::String_(k), v]))
            None => ()
          }
        }
      }
      make_array(entries)
    }
    _ => make_array([])
  }
}
