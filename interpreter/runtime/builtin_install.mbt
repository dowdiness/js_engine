///|
/// Standard descriptor metadata for built-in prototype methods installed as
/// ordinary data properties.
pub fn builtin_method_desc() -> PropDescriptor {
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
fn builtin_accessor_desc(getter : Value, setter : Value?) -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(getter),
    setter,
    is_accessor: true,
  }
}

///|
fn builtin_non_writable_desc() -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
fn builtin_frozen_data_desc() -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
/// Install a built-in string-keyed method and its standard method descriptor.
pub fn install_builtin_method(
  data : ObjectData,
  name : String,
  func : Value,
) -> Unit {
  data.bag.properties[name] = func
  data.bag.descriptors[name] = builtin_method_desc()
}

///|
/// Install a built-in string-keyed accessor property.
pub fn install_builtin_accessor(
  data : ObjectData,
  name : String,
  getter : Value,
  setter : Value?,
) -> Unit {
  data.bag.properties[name] = Undefined
  data.bag.descriptors[name] = builtin_accessor_desc(getter, setter)
}

///|
/// Install a built-in string-keyed non-writable configurable data property.
pub fn install_builtin_non_writable(
  data : ObjectData,
  name : String,
  value : Value,
) -> Unit {
  data.bag.properties[name] = value
  data.bag.descriptors[name] = builtin_non_writable_desc()
}

///|
/// Install a built-in string-keyed non-writable non-configurable data property.
pub fn install_builtin_frozen_data(
  data : ObjectData,
  name : String,
  value : Value,
) -> Unit {
  data.bag.properties[name] = value
  data.bag.descriptors[name] = builtin_frozen_data_desc()
}

///|
/// Install a built-in symbol-keyed method and its standard method descriptor.
pub fn install_builtin_symbol_method(
  data : ObjectData,
  sym_id : Int,
  func : Value,
) -> Unit {
  data.bag.symbol_properties[sym_id] = func
  data.bag.symbol_descriptors[sym_id] = builtin_method_desc()
}

///|
/// Install a built-in symbol-keyed accessor property with no setter.
pub fn install_builtin_symbol_accessor(
  data : ObjectData,
  sym_id : Int,
  getter : Value,
) -> Unit {
  data.bag.symbol_properties[sym_id] = Undefined
  data.bag.symbol_descriptors[sym_id] = builtin_accessor_desc(getter, None)
}

///|
/// Install a built-in symbol-keyed non-writable configurable string data property.
pub fn install_builtin_symbol_string(
  data : ObjectData,
  sym_id : Int,
  tag : String,
) -> Unit {
  data.bag.symbol_properties[sym_id] = Value::String_(tag)
  data.bag.symbol_descriptors[sym_id] = builtin_non_writable_desc()
}
