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
