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
/// Install a built-in symbol-keyed non-writable non-configurable data property.
pub fn install_builtin_symbol_frozen_data(
  data : ObjectData,
  sym_id : Int,
  value : Value,
) -> Unit {
  data.bag.symbol_properties[sym_id] = value
  data.bag.symbol_descriptors[sym_id] = builtin_frozen_data_desc()
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

///|
/// Cache-for-X install contract (#504): atomically pin `proto` in the realm
/// dispatch cache (`realm_proto_cache`), on the constructor's frozen `.prototype`
/// property, and register `ctor` in `env`.
///
/// **Invariant:** `realm_proto_cache.val` must equal the constructor object's
/// `.prototype` property in every realm. Splitting these updates causes silent
/// dual-source dispatch bugs (PR #138).
///
/// **When to use:**
/// - This helper when `.prototype` is a frozen data property on the constructor.
/// - `install_realm_pinned_builtin_constructor_with_proto_constructor` when the
///   family also needs `proto.constructor = ctor` (Map/Set, WeakMap/WeakSet, …).
/// - A family-specific variant when `.prototype` is not frozen (Promise, Array, …).
///
/// **Migrated:** Map/Set, WeakMap/WeakSet. **Remaining:** Array, Promise, boxed
/// primitives, …
pub fn install_realm_pinned_builtin_constructor(
  env : Environment,
  realm_proto_cache : Ref[Value?],
  ctor_name : String,
  ctor : Value,
  proto : Value,
) -> Unit {
  guard ctor is Object(data) else {
    abort("built-in constructor must be an object: \{ctor_name}")
  }
  realm_proto_cache.val = Some(proto)
  install_builtin_frozen_data(data, "prototype", proto)
  env.def_builtin(ctor_name, ctor)
}

///|
/// Cache-for-X install contract for frozen-prototype builtins (#504 / #512):
/// `install_realm_pinned_builtin_constructor` plus `proto.constructor = ctor`.
///
/// Use for built-in families whose `%FooPrototype%` objects expose a spec
/// `constructor` property back to the realm's `%Foo%` function.
pub fn install_realm_pinned_builtin_constructor_with_proto_constructor(
  env : Environment,
  realm_proto_cache : Ref[Value?],
  ctor_name : String,
  ctor : Value,
  proto : Value,
) -> Unit {
  install_realm_pinned_builtin_constructor(
    env, realm_proto_cache, ctor_name, ctor, proto,
  )
  match proto {
    Object(data) => install_builtin_method(data, "constructor", ctor)
    _ => ()
  }
}
