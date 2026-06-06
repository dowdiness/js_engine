///|
/// Standard descriptor metadata for built-in prototype methods installed as
/// ordinary data properties.
fn builtin_method_desc() -> PropDescriptor {
  {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
/// Install a built-in prototype method and its standard method descriptor.
fn install_builtin_method(
  data : ObjectData,
  name : String,
  func : Value,
) -> Unit {
  data.bag.properties[name] = func
  data.bag.descriptors[name] = builtin_method_desc()
}
