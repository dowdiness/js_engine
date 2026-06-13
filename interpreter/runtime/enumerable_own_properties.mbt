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
/// Whether an own string key is enumerable, defaulting to `true` when no
/// descriptor is recorded (the ordinary-object convention for data properties
/// created without an explicit descriptor).
fn bag_key_enumerable(bag : PropertyBag, key : String) -> Bool {
  bag.descriptors.get(key).map(fn(d) { d.enumerable }).unwrap_or(true)
}

///|
pub fn object_keys(interp : Interpreter, obj : Value) -> Value raise Error {
  match obj {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Value::Proxy(proxy_data) =>
      // Call [[OwnPropertyKeys]] via proxy trap, then keep only the string keys
      // (Object.keys only returns strings).
      match proxy_own_property_keys(interp, proxy_data) {
        Value::Array(arr) =>
          make_array(arr.elements.filter(fn(key) { key is Value::String_(_) }))
        _ => make_array([])
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
          bag_key_enumerable(data.bag, k)
        }
        if enumerable {
          keys.push(Value::String_(k))
        }
      }
      make_array(keys)
    }
    Value::String_(s) =>
      // String objects have enumerable indexed properties
      make_array(
        Array::makei(s.length(), fn(i) { Value::String_(i.to_string()) }),
      )
    Value::Array(data) =>
      // Array objects have enumerable indexed properties followed by
      // enumerable own named properties in their embedded bag.
      make_array(
        [
          ..[
            for i in 0..<data.elements.length() if !data.holes.contains(i) &&
            bag_key_enumerable(data.bag, i.to_string()) => {
              Value::String_(i.to_string())
            }
          ],
          ..[
            for k in sort_property_keys(data.bag.properties) if !is_internal_array_bag_key(
              k,
            ) &&
            bag_key_enumerable(data.bag, k) => Value::String_(k)
          ],
        ],
      )
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
        } else if bag_key_enumerable(data.bag, k) {
          match data.bag.properties.get(k) {
            Some(v) => vals.push(v)
            None => ()
          }
        }
      }
      make_array(vals)
    }
    Value::String_(s) =>
      // String objects have enumerable indexed properties
      make_array(s.to_array().map(fn(ch) { Value::String_(ch.to_string()) }))
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
        if bag_key_enumerable(data.bag, k) {
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
        } else if bag_key_enumerable(data.bag, k) {
          match data.bag.properties.get(k) {
            Some(v) => entries.push(make_array([Value::String_(k), v]))
            None => ()
          }
        }
      }
      make_array(entries)
    }
    Value::String_(s) =>
      // String objects have enumerable indexed properties
      make_array(
        s
        .to_array()
        .mapi(fn(i, ch) {
          make_array([
            Value::String_(i.to_string()),
            Value::String_(ch.to_string()),
          ])
        }),
      )
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
        if bag_key_enumerable(data.bag, k) {
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
