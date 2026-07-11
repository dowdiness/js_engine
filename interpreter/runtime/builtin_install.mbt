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
fn ctor_object_data(ctor : Value, ctor_name : String) -> ObjectData {
  guard ctor is Object(data) else {
    abort("built-in constructor must be an object: \{ctor_name}")
  }
  data
}

///|
fn pin_realm_cache_and_register_builtin(
  env : Environment,
  realm_proto_cache : Ref[Value?],
  ctor_name : String,
  ctor : Value,
  proto : Value,
) -> Unit {
  realm_proto_cache.val = Some(proto)
  env.def_builtin(ctor_name, ctor)
}

///|
fn install_registered_proto_constructor(
  env : Environment,
  ctor_name : String,
  proto : Value,
) -> Unit {
  let registered_ctor = match env.bindings.get(ctor_name) {
    Some(binding) => binding.value
    None =>
      abort("built-in constructor missing from env after install: \{ctor_name}")
  }
  match proto {
    Object(data) => install_builtin_method(data, "constructor", registered_ctor)
    _ => ()
  }
}

///|
fn assert_ctor_bagged_prototype_matches(
  ctor : Value,
  proto : Value,
  ctor_name : String,
) -> Unit {
  let data = ctor_object_data(ctor, ctor_name)
  match data.bag.properties.get("prototype") {
    Some(bagged) =>
      match (bagged, proto) {
        (Object(bagged_data), Object(proto_data)) =>
          if !physical_equal(bagged_data, proto_data) {
            abort(
              "constructor bag .prototype must match pinned proto: \{ctor_name}",
            )
          }
        _ =>
          abort(
            "constructor bag .prototype must be an object value: \{ctor_name}",
          )
      }
    None => abort("constructor bag missing .prototype property: \{ctor_name}")
  }
}

///|
/// How the constructor object's `.prototype` property is prepared before the
/// cache-for-X install pins `proto` and registers `ctor` in `env`.
pub(all) enum BuiltinCtorPrototypeInstall {
  /// Install a frozen data `.prototype` on the constructor bag at install time
  /// (Map/Set, WeakMap/WeakSet, …).
  FrozenAtInstall
  /// `.prototype` is already on the constructor bag with its descriptor; only
  /// assert it matches `proto` (Array, boxed primitives, …).
  PreBagged
  /// `.prototype` descriptor is predeclared; assign `proto` at install time
  /// (Promise, …).
  AssignAtInstall
}

///|
fn apply_ctor_prototype_install(
  ctor : Value,
  ctor_name : String,
  proto : Value,
  mode : BuiltinCtorPrototypeInstall,
) -> Unit {
  match mode {
    FrozenAtInstall => {
      let data = ctor_object_data(ctor, ctor_name)
      install_builtin_frozen_data(data, "prototype", proto)
    }
    PreBagged => assert_ctor_bagged_prototype_matches(ctor, proto, ctor_name)
    AssignAtInstall => {
      let data = ctor_object_data(ctor, ctor_name)
      match data.bag.descriptors.get("prototype") {
        None => abort("constructor missing .prototype descriptor: \{ctor_name}")
        Some(_) => ()
      }
      data.bag.properties["prototype"] = proto
    }
  }
}

///|
/// Cache-for-X install contract (#504 / #512): atomically pin `proto` in the
/// realm dispatch cache (`realm_proto_cache`), prepare the constructor's
/// `.prototype` property per `prototype_install`, and register `ctor` in `env`.
///
/// **Invariant:** `realm_proto_cache.val` must equal the constructor object's
/// `.prototype` property in every realm. Splitting these updates causes silent
/// dual-source dispatch bugs (PR #138).
///
/// Set `wire_proto_constructor` when the family also needs
/// `proto.constructor = ctor` (Map/Set, Array, boxed primitives, Promise, …).
///
/// **Migrated families:** Map/Set, WeakMap/WeakSet, Array, Promise, boxed
/// primitives (String/Number/Boolean/Symbol). #512 rollout complete.
pub fn install_realm_pinned_builtin_constructor(
  env : Environment,
  realm_proto_cache : Ref[Value?],
  ctor_name : String,
  ctor : Value,
  proto : Value,
  prototype_install? : BuiltinCtorPrototypeInstall = FrozenAtInstall,
  wire_proto_constructor? : Bool = false,
) -> Unit {
  apply_ctor_prototype_install(ctor, ctor_name, proto, prototype_install)
  pin_realm_cache_and_register_builtin(
    env, realm_proto_cache, ctor_name, ctor, proto,
  )
  if wire_proto_constructor {
    install_registered_proto_constructor(env, ctor_name, proto)
  }
}
