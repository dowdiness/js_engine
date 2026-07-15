///|
/// `EnumerableOwnProperties`-class operations (ES2024 §7.3.25) relocated from
/// `interpreter/stdlib/builtins_object.mbt` so that stdlib calls a runtime
/// operation instead of reaching into PropertyBag / ArrayData representation
/// internals (architecture redesign Stage 8).
///
/// `object_keys` / `object_values` / `object_entries` implement
/// `Object.keys` / `Object.values` / `Object.entries`; the stdlib factories are
/// thin wrappers that only extract the argument.
///
/// The module-namespace string-key ordering uses the existing runtime helper
/// `module_namespace_own_string_keys` (lexical order, distinct from the
/// integer-index-first `[[OwnPropertyKeys]]` ordering of `sort_property_keys`).

///|
/// Whether an own string key is enumerable, defaulting to `true` when no
/// descriptor is recorded (the ordinary-object convention for data properties
/// created without an explicit descriptor).
fn bag_key_enumerable(bag : PropertyBag, key : String) -> Bool {
  bag.descriptors.get(key).map(d => d.enumerable).unwrap_or(true)
}

///|
/// Enumerable own String keys of a Proxy, in `[[OwnPropertyKeys]]` trap order.
/// Mirrors `EnumerableOwnProperties`: keep a String key only when its
/// `[[GetOwnProperty]]` (the `getOwnPropertyDescriptor` trap) reports it present
/// and enumerable. `proxy_own_property_keys` already enforces the no-duplicate
/// invariant, so no deduplication is needed here.
fn proxy_enumerable_own_string_keys(
  interp : Interpreter,
  obj : Value,
  proxy_data : ProxyData,
) -> Array[String] raise Error {
  let result : Array[String] = []
  match proxy_own_property_keys(interp, proxy_data) {
    Value::Array(arr) =>
      for key in arr.elements {
        guard key is Value::String_(s) else { continue }
        match interp.get_own_property(obj, key) {
          Some((desc, _)) if desc.enumerable => result.push(s)
          _ => ()
        }
      }
    _ => ()
  }
  result
}

///|
pub fn object_keys(interp : Interpreter, obj : Value) -> Value raise Error {
  match obj {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Value::Proxy(proxy_data) =>
      // [[OwnPropertyKeys]] via proxy trap, filtered to enumerable own string
      // keys ([[GetOwnProperty]].[[Enumerable]]).
      make_array(
        proxy_enumerable_own_string_keys(interp, obj, proxy_data).map(s => {
          Value::String_(s)
        }),
      )
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
        .filter(k => bag_key_enumerable(data.bag, k))
        .map(k => Value::String_(k))
        .to_array(),
      )
    Value::String_(s) =>
      // String objects have enumerable indexed properties
      make_array(Array::makei(s.length(), i => Value::String_(i.to_string())))
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
            for k in sort_property_keys(data.bag.properties) if bag_key_enumerable(
              data.bag,
              k,
            ) => Value::String_(k)
          ],
        ],
      )
    Map(data) =>
      make_array(
        sort_property_keys(data.bag.properties)
        .iter()
        .filter(k => bag_key_enumerable(data.bag, k))
        .map(k => Value::String_(k))
        .to_array(),
      )
    Set(data) =>
      make_array(
        sort_property_keys(data.bag.properties)
        .iter()
        .filter(k => bag_key_enumerable(data.bag, k))
        .map(k => Value::String_(k))
        .to_array(),
      )
    Promise(data) =>
      make_array(
        sort_property_keys(data.bag.properties)
        .iter()
        .filter(k => bag_key_enumerable(data.bag, k))
        .map(k => Value::String_(k))
        .to_array(),
      )
    _ => make_array([])
  }
}

///|
pub fn object_values(interp : Interpreter, obj : Value) -> Value raise Error {
  let loc = @token.Loc::default()
  match obj {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Value::Proxy(proxy_data) => {
      // Enumerable own string keys via the proxy traps, then [[Get]] each value.
      let vals : Array[Value] = []
      for s in proxy_enumerable_own_string_keys(interp, obj, proxy_data) {
        vals.push(interp.get_property(obj, s, loc))
      }
      make_array(vals)
    }
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
    Object(data) => {
      // Ordinary objects: each enumerable own key's value via [[Get]] so
      // accessor getters run (spec EnumerableOwnProperties, kind=value).
      let vals : Array[Value] = []
      for k in sort_property_keys(data.bag.properties) {
        if bag_key_enumerable(data.bag, k) {
          vals.push(interp.get_property(obj, k, loc))
        }
      }
      make_array(vals)
    }
    Value::String_(s) =>
      // String objects have enumerable indexed properties
      make_array(s.to_array().map(ch => Value::String_(ch.to_string())))
    Value::Array(data) => {
      // Array objects - enumerable indexed slots (getter-aware), then enumerable
      // own named properties read through [[Get]].
      let vals : Array[Value] = []
      for i in 0..<data.elements.length() {
        if data.holes.contains(i) {
          continue
        }
        let key = i.to_string()
        if bag_key_enumerable(data.bag, key) {
          vals.push(interp.get_property(obj, key, loc))
        }
      }
      for k in sort_property_keys(data.bag.properties) {
        if bag_key_enumerable(data.bag, k) {
          vals.push(interp.get_property(obj, k, loc))
        }
      }
      make_array(vals)
    }
    _ => make_array([])
  }
}

///|
pub fn object_entries(interp : Interpreter, obj : Value) -> Value raise Error {
  let loc = @token.Loc::default()
  match obj {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Value::Proxy(proxy_data) => {
      // Enumerable own string keys via the proxy traps, then [[Get]] each value.
      let entries : Array[Value] = []
      for s in proxy_enumerable_own_string_keys(interp, obj, proxy_data) {
        entries.push(
          make_array([Value::String_(s), interp.get_property(obj, s, loc)]),
        )
      }
      make_array(entries)
    }
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
    Object(data) => {
      // Ordinary objects: [key, [[Get]] value] for each enumerable own key.
      let entries : Array[Value] = []
      for k in sort_property_keys(data.bag.properties) {
        if bag_key_enumerable(data.bag, k) {
          entries.push(
            make_array([Value::String_(k), interp.get_property(obj, k, loc)]),
          )
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
      // Array objects - enumerable indexed slots (getter-aware), then enumerable
      // own named properties read through [[Get]]. Keys must be strings per spec.
      let entries : Array[Value] = []
      for i in 0..<data.elements.length() {
        if data.holes.contains(i) {
          continue
        }
        let key = i.to_string()
        if bag_key_enumerable(data.bag, key) {
          entries.push(
            make_array([Value::String_(key), interp.get_property(obj, key, loc)]),
          )
        }
      }
      for k in sort_property_keys(data.bag.properties) {
        if bag_key_enumerable(data.bag, k) {
          entries.push(
            make_array([Value::String_(k), interp.get_property(obj, k, loc)]),
          )
        }
      }
      make_array(entries)
    }
    _ => make_array([])
  }
}
