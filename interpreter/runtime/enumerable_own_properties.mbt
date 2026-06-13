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
    // Module namespaces resolve enumerability via the exotic [[Get]]
    // (`interp.get_own_property`, which raises), so they keep an imperative
    // loop; ordinary objects read the bag and reduce to a pipeline.
    Object(data) if data.class_name == "Module" => {
      let keys : Array[Value] = []
      for k in module_namespace_own_string_keys(data) {
        let enumerable = match interp.get_own_property(obj, String_(k)) {
          Some((desc, _)) => desc.enumerable
          None => false
        }
        if enumerable {
          keys.push(Value::String_(k))
        }
      }
      make_array(keys)
    }
    Object(data) =>
      make_array(
        sort_property_keys(data.bag.properties)
        .iter()
        .filter(fn(k) { bag_key_enumerable(data.bag, k) })
        .map(fn(k) { Value::String_(k) })
        .to_array(),
      )
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
    Object(data) if data.class_name == "Module" => {
      let vals : Array[Value] = []
      for k in module_namespace_own_string_keys(data) {
        match interp.get_own_property(obj, String_(k)) {
          Some((desc, value)) if desc.enumerable => vals.push(value)
          _ => ()
        }
      }
      make_array(vals)
    }
    Object(data) =>
      make_array(
        sort_property_keys(data.bag.properties)
        .iter()
        .filter(fn(k) { bag_key_enumerable(data.bag, k) })
        .filter_map(fn(k) { data.bag.properties.get(k) })
        .to_array(),
      )
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
      sort_property_keys(data.bag.properties)
      .iter()
      .filter(fn(k) {
        !is_internal_array_bag_key(k) && bag_key_enumerable(data.bag, k)
      })
      .filter_map(fn(k) { data.bag.properties.get(k) })
      .each(fn(v) { vals.push(v) })
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
    Object(data) if data.class_name == "Module" => {
      let entries : Array[Value] = []
      for k in module_namespace_own_string_keys(data) {
        match interp.get_own_property(obj, String_(k)) {
          Some((desc, value)) if desc.enumerable =>
            entries.push(make_array([Value::String_(k), value]))
          _ => ()
        }
      }
      make_array(entries)
    }
    Object(data) =>
      make_array(
        sort_property_keys(data.bag.properties)
        .iter()
        .filter(fn(k) { bag_key_enumerable(data.bag, k) })
        .filter_map(fn(k) {
          data.bag.properties
          .get(k)
          .map(fn(v) { make_array([Value::String_(k), v]) })
        })
        .to_array(),
      )
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
      sort_property_keys(data.bag.properties)
      .iter()
      .filter(fn(k) {
        !is_internal_array_bag_key(k) && bag_key_enumerable(data.bag, k)
      })
      .filter_map(fn(k) {
        data.bag.properties
        .get(k)
        .map(fn(v) { make_array([Value::String_(k), v]) })
      })
      .each(fn(e) { entries.push(e) })
      make_array(entries)
    }
    _ => make_array([])
  }
}
