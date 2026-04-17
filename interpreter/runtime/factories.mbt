///|
pub fn make_func(data : FuncData) -> Value {
  let proto = Object({
    bag: new_property_bag(),
    prototype: get_obj_proto(),
    callable: None,
    class_name: "Object",
    extensible: true,
  })
  let func_name = match data.name {
    Some(n) => n
    None => ""
  }
  let func_length = data.params.length().to_double()
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let func_obj = Object({
    bag: {
      properties: {
        "prototype": proto,
        "name": String_(func_name),
        "length": Number(func_length),
      },
      symbol_properties: {},
      descriptors: {
        "prototype": {
          writable: true,
          enumerable: false,
          configurable: false,
          getter: None,
          setter: None,
        },
        "name": nf_desc,
        "length": nf_desc,
      },
      symbol_descriptors: {},
    },
    prototype: get_func_proto(),
    callable: Some(UserFunc(data)),
    class_name: "Function",
    extensible: true,
  })
  match proto {
    Object(proto_data) => {
      proto_data.bag.properties["constructor"] = func_obj
      proto_data.bag.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }
  func_obj
}

///|
pub fn make_func_ext(data : FuncDataExt) -> Value {
  let proto = Object({
    bag: new_property_bag(),
    prototype: get_obj_proto(),
    callable: None,
    class_name: "Object",
    extensible: true,
  })
  let func_name = match data.name {
    Some(n) => n
    None => ""
  }
  // Length = number of params before first default value
  let mut func_length = 0
  for p in data.params {
    if p.default_val is Some(_) {
      break
    }
    func_length += 1
  }
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let func_obj = Object({
    bag: {
      properties: {
        "prototype": proto,
        "name": String_(func_name),
        "length": Number(func_length.to_double()),
      },
      symbol_properties: {},
      descriptors: {
        "prototype": {
          writable: true,
          enumerable: false,
          configurable: false,
          getter: None,
          setter: None,
        },
        "name": nf_desc,
        "length": nf_desc,
      },
      symbol_descriptors: {},
    },
    prototype: get_func_proto(),
    callable: Some(UserFuncExt(data)),
    class_name: "Function",
    extensible: true,
  })
  match proto {
    Object(proto_data) => {
      proto_data.bag.properties["constructor"] = func_obj
      proto_data.bag.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }
  func_obj
}

///|
/// Global reference to Function.prototype, set during initialization
pub let function_prototype_ref : Ref[Value?] = { val: None }

///|
/// Global reference to Object.prototype, set during initialization
pub let object_prototype_ref : Ref[Value?] = { val: None }

///|
/// Global reference to String.prototype, set during initialization
pub let string_prototype_ref : Ref[Value?] = { val: None }

///|
/// Global reference to Number.prototype, set during initialization
pub let number_prototype_ref : Ref[Value?] = { val: None }

///|
/// Global reference to Boolean.prototype, set during initialization
pub let boolean_prototype_ref : Ref[Value?] = { val: None }

///|
/// Global reference to Symbol.prototype, set during initialization
pub let symbol_prototype_ref : Ref[Value?] = { val: None }

///|
pub fn get_func_proto() -> Value {
  match function_prototype_ref.val {
    Some(p) => p
    None => Null
  }
}

///|
pub fn get_obj_proto() -> Value {
  match object_prototype_ref.val {
    Some(p) => p
    None => Null
  }
}

///|
pub fn get_string_proto() -> Value {
  match string_prototype_ref.val {
    Some(p) => p
    None => Null
  }
}

///|
pub fn get_number_proto() -> Value {
  match number_prototype_ref.val {
    Some(p) => p
    None => Null
  }
}

///|
pub fn get_boolean_proto() -> Value {
  match boolean_prototype_ref.val {
    Some(p) => p
    None => Null
  }
}

///|
pub fn get_symbol_proto() -> Value {
  match symbol_prototype_ref.val {
    Some(p) => p
    None => Null
  }
}

///|
pub fn make_native_func(
  name : String,
  func : (Array[Value]) -> Value raise Error,
) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  Object({
    bag: {
      properties: { "name": String_(name), "length": Number(0.0) },
      symbol_properties: {},
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
    },
    prototype: get_func_proto(),
    callable: Some(NonConstructableCallable(name, func)),
    class_name: "Function",
    extensible: true,
  })
}

///|
/// Helper to create a native function with explicit length property
pub fn make_native_func_with_length(
  name : String,
  length : Int,
  func : (Array[Value]) -> Value raise Error,
) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let props : Map[String, Value] = {}
  props["length"] = Number(length.to_double())
  props["name"] = String_(name)
  Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
    },
    prototype: get_func_proto(),
    callable: Some(NonConstructableCallable(name, func)),
    class_name: "Function",
    extensible: true,
  })
}

///|
/// Helper to create a non-constructable native function (for static methods)
pub fn make_static_func(
  name : String,
  func : (Array[Value]) -> Value raise Error,
) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  Object({
    bag: {
      properties: { "name": String_(name), "length": Number(0.0) },
      symbol_properties: {},
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
    },
    prototype: get_func_proto(),
    callable: Some(NonConstructableCallable(name, func)),
    class_name: "Function",
    extensible: true,
  })
}

///|
/// Helper to create a non-constructable native function with explicit length (for static methods)
pub fn make_static_func_with_length(
  name : String,
  length : Int,
  func : (Array[Value]) -> Value raise Error,
) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let props : Map[String, Value] = {}
  props["length"] = Number(length.to_double())
  props["name"] = String_(name)
  Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
    },
    prototype: get_func_proto(),
    callable: Some(NonConstructableCallable(name, func)),
    class_name: "Function",
    extensible: true,
  })
}

///|
/// Helper to create a method function (MethodCallable) with name/length properties
pub fn make_method_func(
  name : String,
  length : Int,
  func : (Value, Array[Value]) -> Value raise Error,
) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let props : Map[String, Value] = {}
  props["length"] = Number(length.to_double())
  props["name"] = String_(name)
  Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
    },
    prototype: get_func_proto(),
    callable: Some(MethodCallable(name, func)),
    class_name: "Function",
    extensible: true,
  })
}

///|
/// Helper to create an interpreter method function (InterpreterCallable) with name/length properties
pub fn make_interp_method_func(
  name : String,
  length : Int,
  func : (Interpreter, Value, Array[Value]) -> Value raise Error,
) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let props : Map[String, Value] = {}
  props["length"] = Number(length.to_double())
  props["name"] = String_(name)
  Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
    },
    prototype: get_func_proto(),
    callable: Some(InterpreterCallable(name, func)),
    class_name: "Function",
    extensible: true,
  })
}

///|
/// Helper to create a non-constructable interpreter-aware static function with explicit length.
/// The callback receives the Interpreter as its first argument; this_val is ignored.
pub fn make_interp_static_func_with_length(
  name : String,
  length : Int,
  func : (Interpreter, Array[Value]) -> Value raise Error,
) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let props : Map[String, Value] = {}
  props["length"] = Number(length.to_double())
  props["name"] = String_(name)
  Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
    },
    prototype: get_func_proto(),
    callable: Some(
      InterpreterCallable(name, fn(interp, _this, args) raise {
        func(interp, args)
      }),
    ),
    class_name: "Function",
    extensible: true,
  })
}

///|
/// Helper to create a basic object with default empty symbol maps
pub fn make_object(
  properties : Map[String, Value],
  prototype : Value,
  callable : Callable?,
  class_name : String,
  descriptors : Map[String, PropDescriptor],
  extensible : Bool,
) -> Value {
  Object({
    bag: {
      properties,
      symbol_properties: {},
      descriptors,
      symbol_descriptors: {},
    },
    prototype,
    callable,
    class_name,
    extensible,
  })
}

///|
/// Create an iterator result object { value, done }
pub fn create_iter_result(value : Value, done : Bool) -> Value {
  let props : Map[String, Value] = {}
  props["value"] = value
  props["done"] = Bool(done)
  Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
  })
}

///|
/// Helper to create a plain object
pub fn make_plain_object() -> Value {
  Object({
    bag: new_property_bag(),
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
  })
}

///|
/// Wrap an Array[Value] in an Array Value with an empty property bag.
/// Dense-only arrays (no named props, no sparse length overrides) build via this.
pub fn make_array(elements : Array[Value]) -> Value {
  Array({ elements, bag: new_property_bag() })
}

///|
/// Construct MapData with entries and an empty property bag (no expando properties).
pub fn make_map_data(entries : Array[(Value, Value)]) -> MapData {
  { entries, bag: new_property_bag() }
}

///|
/// Construct SetData with values and an empty property bag (no expando properties).
pub fn make_set_data(values : Array[Value]) -> SetData {
  { values, bag: new_property_bag() }
}
