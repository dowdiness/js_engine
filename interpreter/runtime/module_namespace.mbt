///|
const MODULE_NAMESPACE_OBJECT_KEY = "[[NamespaceObject]]"

///|
const MODULE_NAMESPACE_EXPORT_VALUE_KEY = "[[ExportValue]]"

///|
const MODULE_NAMESPACE_CACHE_CLASS = "ModuleNamespaceCache"

///|
fn make_module_namespace_cache(ns_obj : Value) -> Value {
  let props : Map[String, Value] = {}
  props[MODULE_NAMESPACE_OBJECT_KEY] = ns_obj
  Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: None,
    class_name: MODULE_NAMESPACE_CACHE_CLASS,
    extensible: false,
    arraybuffer_state: None,
  })
}

///|
fn make_module_namespace_cache_with_export(
  ns_obj : Value,
  export_value : Value,
) -> Value {
  let props : Map[String, Value] = {}
  props[MODULE_NAMESPACE_OBJECT_KEY] = ns_obj
  props[MODULE_NAMESPACE_EXPORT_VALUE_KEY] = export_value
  Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: None,
    class_name: MODULE_NAMESPACE_CACHE_CLASS,
    extensible: false,
    arraybuffer_state: None,
  })
}

///|
fn module_namespace_cached_value(value : Value) -> Value? {
  match value {
    Object(data) if data.class_name == MODULE_NAMESPACE_CACHE_CLASS =>
      data.bag.properties.get(MODULE_NAMESPACE_OBJECT_KEY)
    _ => None
  }
}

///|
fn module_namespace_public_export_value(value : Value) -> Value? {
  match value {
    Object(data) if data.class_name == MODULE_NAMESPACE_CACHE_CLASS =>
      data.bag.properties.get(MODULE_NAMESPACE_EXPORT_VALUE_KEY)
    _ => None
  }
}

///|
fn is_private_module_export_entry(name : String, value : Value) -> Bool {
  name == MODULE_NAMESPACE_OBJECT_KEY &&
  module_namespace_cached_value(value) is Some(_) &&
  module_namespace_public_export_value(value) is None
}

///|
fn module_export_map_get_public(
  exports_map : Map[String, Value],
  export_name : String,
) -> Value? {
  match exports_map.get(export_name) {
    Some(value) =>
      match module_namespace_public_export_value(value) {
        Some(public_value) => Some(public_value)
        None =>
          if is_private_module_export_entry(export_name, value) {
            None
          } else {
            Some(value)
          }
      }
    _ => None
  }
}

///|
fn module_export_entry_is_live_cell(value : Value) -> Bool {
  let public_value = match module_namespace_public_export_value(value) {
    Some(v) => v
    None => value
  }
  match public_value {
    Object(data) => data.class_name == "ModuleExportCell"
    _ => false
  }
}

///|
/// A private marker for exported bindings that exist during module
/// instantiation but have not been initialized yet. Namespace access resolves
/// this marker to the ReferenceError required for TDZ exports.
fn make_module_tdz_marker(export_name : String) -> Value {
  let props : Map[String, Value] = { "[[ExportName]]": String_(export_name) }
  Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: None,
    class_name: "ModuleTDZ",
    extensible: false,
    arraybuffer_state: None,
  })
}

///|
/// A private cell used while a module is evaluating. It lets module namespace
/// getters observe the current value of a local export before final exports are
/// materialized into plain values.
fn make_module_export_cell(
  export_name : String,
  local_name : String,
  env : Environment,
) -> Value {
  Object({
    bag: PropertyBag(),
    prototype: Null,
    callable: Some(
      NonConstructableCallable("get export \{export_name}", fn(_args) raise {
        env.get(local_name)
      }),
    ),
    class_name: "ModuleExportCell",
    extensible: false,
    arraybuffer_state: None,
  })
}

///|
fn make_module_import_cell(
  export_name : String,
  module_exports : Map[String, Value],
) -> Value {
  Object({
    bag: PropertyBag(),
    prototype: Null,
    callable: Some(
      NonConstructableCallable("get import \{export_name}", fn(_args) raise {
        match module_export_map_get_public(module_exports, export_name) {
          Some(value) => resolve_module_export_value(value)
          None =>
            raise @errors.SyntaxError(
              message="Module does not export '\{export_name}'",
            )
        }
      }),
    ),
    class_name: "ModuleExportCell",
    extensible: false,
    arraybuffer_state: None,
  })
}

///|
fn resolve_module_export_value(value : Value) -> Value raise Error {
  match module_namespace_public_export_value(value) {
    Some(public_value) => return resolve_module_export_value(public_value)
    None => ()
  }
  match value {
    Object(data) if data.class_name == "ModuleTDZ" => {
      let export_name = match data.bag.properties.get("[[ExportName]]") {
        Some(String_(name)) => name
        _ => "export"
      }
      raise @errors.ReferenceError(
        message="Cannot access '\{export_name}' before initialization",
      )
    }
    Object(data) if data.class_name == "ModuleExportCell" =>
      match data.callable {
        Some(NonConstructableCallable(_, get_value)) => get_value([])
        _ => Undefined
      }
    _ => value
  }
}

///|
fn make_module_namespace_getter(
  module_exports : Map[String, Value],
  export_name : String,
) -> Value {
  make_native_func(name="get \{export_name}", length=0, fn(_args) raise {
    match module_exports.get(export_name) {
      Some(value) => resolve_module_export_value(value)
      None => Undefined
    }
  })
}

///|
fn Interpreter::create_module_namespace_object(
  self : Interpreter,
  module_exports : Map[String, Value],
) -> Value {
  match module_exports.get(MODULE_NAMESPACE_OBJECT_KEY) {
    Some(cached) =>
      match module_namespace_cached_value(cached) {
        Some(ns_obj) => return ns_obj
        None => ()
      }
    None => ()
  }
  let ns_props : Map[String, Value] = {}
  let ns_descs : Map[String, PropDescriptor] = {}
  module_exports.each(fn(k, v) {
    if is_private_module_export_entry(k, v) {
      return
    }
    ns_props[k] = Undefined
    ns_descs[k] = {
      writable: false,
      enumerable: true,
      configurable: false,
      getter: Some(make_module_namespace_getter(module_exports, k)),
      setter: None,
      is_accessor: true,
    }
  })
  let symbol_props : Map[Int, Value] = {}
  let symbol_descs : Map[Int, PropDescriptor] = {}
  let tag_sym = self.symbols.well_known_symbols().to_string_tag
  symbol_props[tag_sym.id] = String_("Module")
  symbol_descs[tag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let ns_obj : Value = Object({
    bag: {
      properties: ns_props,
      symbol_properties: symbol_props,
      descriptors: ns_descs,
      symbol_descriptors: symbol_descs,
    },
    prototype: Null,
    callable: None,
    class_name: "Module",
    extensible: false,
    arraybuffer_state: None,
  })
  match module_exports.get(MODULE_NAMESPACE_OBJECT_KEY) {
    Some(public_value) =>
      module_exports[MODULE_NAMESPACE_OBJECT_KEY] = make_module_namespace_cache_with_export(
        ns_obj, public_value,
      )
    None =>
      module_exports[MODULE_NAMESPACE_OBJECT_KEY] = make_module_namespace_cache(
        ns_obj,
      )
  }
  ns_obj
}

///|
fn module_namespace_export_descriptor() -> PropDescriptor {
  {
    writable: true,
    enumerable: true,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
fn module_namespace_own_string_keys(data : ObjectData) -> Array[String] {
  let keys : Array[String] = []
  data.bag.properties.each(fn(k, _) { keys.push(k) })
  keys.sort_by(fn(a, b) { a.lexical_compare(b) })
  keys
}

///|
fn Interpreter::module_namespace_get_own_property_pair(
  self : Interpreter,
  data : ObjectData,
  prop_key : Value,
) -> (PropDescriptor, Value)? raise Error {
  match prop_key {
    String_(key) =>
      if data.bag.properties.contains(key) {
        Some(
          (
            module_namespace_export_descriptor(),
            self.get_property(Object(data), key, @token.Loc::default()),
          ),
        )
      } else {
        None
      }
    _ => ordinary_get_own_property_pair(Object(data), prop_key)
  }
}

///|
fn Interpreter::module_namespace_define_own_property(
  self : Interpreter,
  data : ObjectData,
  prop_key : Value,
  partial : PartialDescriptor,
) -> Bool? raise Error {
  match prop_key {
    String_(key) => {
      if !data.bag.properties.contains(key) {
        return Some(false)
      }
      match partial.configurable {
        Some(true) => return Some(false)
        _ => ()
      }
      match partial.enumerable {
        Some(false) => return Some(false)
        _ => ()
      }
      match partial.writable {
        Some(false) => return Some(false)
        _ => ()
      }
      if partial.is_accessor() {
        return Some(false)
      }
      match partial.value {
        Some(value) => {
          let current = self.get_property(
            Object(data),
            key,
            @token.Loc::default(),
          )
          Some(same_value_for_vap(current, value))
        }
        None => Some(true)
      }
    }
    _ => None
  }
}

///|
priv struct ModuleRunRecord {
  specifier : String
  stmts : Array[@ast.Stmt]
  exports : Map[String, Value]
  env : Environment
}
