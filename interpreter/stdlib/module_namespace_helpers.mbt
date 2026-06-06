///|
fn stdlib_module_namespace_own_string_keys(data : ObjectData) -> Array[String] {
  let keys : Array[String] = []
  data.bag.properties.each(fn(k, _) { if !k.has_prefix("[[") { keys.push(k) } })
  keys.sort_by(fn(a, b) { a.lexical_compare(b) })
  keys
}

///|
fn stdlib_module_namespace_set_prototype_result(
  data : ObjectData,
  proto : Value,
) -> Bool? {
  if data.class_name != "Module" {
    return None
  }
  match proto {
    Null => Some(true)
    _ => Some(false)
  }
}
