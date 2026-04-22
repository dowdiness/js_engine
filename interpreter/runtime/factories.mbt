///|
pub fn make_func(data : FuncData) -> Value {
  let proto = Object({
    bag: PropertyBag::new(),
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
  let func_props : Map[String, Value] = {}
  let func_descs : Map[String, PropDescriptor] = {}
  if !data.is_method {
    func_props["prototype"] = proto
    func_descs["prototype"] = {
      writable: true,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
    }
  }
  func_props["length"] = Number(func_length)
  func_props["name"] = String_(func_name)
  func_descs["length"] = nf_desc
  func_descs["name"] = nf_desc
  let func_obj = Object({
    bag: {
      properties: func_props,
      symbol_properties: {},
      descriptors: func_descs,
      symbol_descriptors: {},
    },
    prototype: get_func_proto(),
    callable: Some(UserFunc(data)),
    class_name: "Function",
    extensible: true,
  })
  if !data.is_method {
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
  }
  func_obj
}

///|
pub fn make_func_ext(data : FuncDataExt) -> Value {
  let proto = Object({
    bag: PropertyBag::new(),
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
  let func_props : Map[String, Value] = {}
  let func_descs : Map[String, PropDescriptor] = {}
  if !data.is_method {
    func_props["prototype"] = proto
    func_descs["prototype"] = {
      writable: true,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
    }
  }
  func_props["length"] = Number(func_length.to_double())
  func_props["name"] = String_(func_name)
  func_descs["length"] = nf_desc
  func_descs["name"] = nf_desc
  let func_obj = Object({
    bag: {
      properties: func_props,
      symbol_properties: {},
      descriptors: func_descs,
      symbol_descriptors: {},
    },
    prototype: get_func_proto(),
    callable: Some(UserFuncExt(data)),
    class_name: "Function",
    extensible: true,
  })
  if !data.is_method {
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
  }
  func_obj
}

///|
/// Rebuild a function value with `has_name_binding: false` on its
/// FuncData/FuncDataExt. Used for method-shorthand definitions (in
/// object literals) where the parser emits FuncExpr/FuncExprExt with
/// `name = Some(key)` for `fn.name` purposes, but §15.2.5's self-name
/// binding does NOT apply. Non-UserFunc/UserFuncExt values pass
/// through unchanged (nothing to strip).
pub fn strip_self_name_binding(v : Value) -> Value {
  match v {
    Object(data) =>
      match data.callable {
        Some(UserFunc(fd)) if fd.has_name_binding =>
          Object({
            ..data,
            callable: Some(UserFunc({ ..fd, has_name_binding: false })),
          })
        Some(UserFuncExt(fd)) if fd.has_name_binding =>
          Object({
            ..data,
            callable: Some(UserFuncExt({ ..fd, has_name_binding: false })),
          })
        _ => v
      }
    _ => v
  }
}

///|
/// Mark a function value as a method-shorthand definition (`{ m() {} }`).
/// Per ES §15.4.5 MethodDefinitionEvaluation, such functions have no
/// [[Construct]] internal method and must throw TypeError when called via
/// `new`. Sets `is_method: true` on the FuncData/FuncDataExt.
/// Non-UserFunc/UserFuncExt values (generators, async functions, etc.)
/// pass through unchanged — they have their own non-constructor semantics.
pub fn mark_as_method(v : Value) -> Value {
  match v {
    Object(data) =>
      match data.callable {
        Some(UserFunc(fd)) => {
          let _ = data.bag.properties.remove("prototype")
          let _ = data.bag.descriptors.remove("prototype")
          Object({ ..data, callable: Some(UserFunc({ ..fd, is_method: true })) })
        }
        Some(UserFuncExt(fd)) => {
          let _ = data.bag.properties.remove("prototype")
          let _ = data.bag.descriptors.remove("prototype")
          Object({
            ..data,
            callable: Some(UserFuncExt({ ..fd, is_method: true })),
          })
        }
        _ => v
      }
    _ => v
  }
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
/// Build a Function-object shell: `length` and `name` own-data properties with
/// non-enumerable/non-writable/configurable descriptors, `[[Prototype]]` set to
/// `Function.prototype`, `class_name: "Function"`. Shared by all `make_*_func`
/// factories below.
///
/// Insertion order matters: `length` precedes `name` so that `Object.keys` /
/// `Reflect.ownKeys` report `[..., "length", "name"]`, matching the spec order
/// (SetFunctionLength runs before SetFunctionName) and the ordering that the
/// pre-consolidation wrappers produced.
fn build_func_object(name : String, length : Int, callable : Callable) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  Object({
    bag: {
      properties: {
        "length": Number(length.to_double()),
        "name": String_(name),
      },
      symbol_properties: {},
      descriptors: { "length": nf_desc, "name": nf_desc },
      symbol_descriptors: {},
    },
    prototype: get_func_proto(),
    callable: Some(callable),
    class_name: "Function",
    extensible: true,
  })
}

///|
/// Non-constructable native function: callback is `(Array[Value]) -> Value raise Error`.
/// Use for built-in free functions and static methods.
pub fn make_native_func(
  name~ : String,
  length? : Int = 0,
  func : (Array[Value]) -> Value raise Error,
) -> Value {
  build_func_object(name, length, NonConstructableCallable(name, func))
}

///|
/// Method function: callback receives `this`. Signature
/// `(Value, Array[Value]) -> Value raise Error`.
pub fn make_method_func(
  name~ : String,
  length? : Int = 0,
  func : (Value, Array[Value]) -> Value raise Error,
) -> Value {
  build_func_object(name, length, MethodCallable(name, func))
}

///|
/// Interpreter-aware method function: callback receives interpreter and `this`.
/// Signature `(Interpreter, Value, Array[Value]) -> Value raise Error`.
pub fn make_interp_method_func(
  name~ : String,
  length? : Int = 0,
  func : (Interpreter, Value, Array[Value]) -> Value raise Error,
) -> Value {
  build_func_object(name, length, InterpreterCallable(name, func))
}

///|
/// Interpreter-aware static function: callback receives interpreter but not `this`.
/// Signature `(Interpreter, Array[Value]) -> Value raise Error`.
pub fn make_interp_static_func(
  name~ : String,
  length? : Int = 0,
  func : (Interpreter, Array[Value]) -> Value raise Error,
) -> Value {
  build_func_object(
    name,
    length,
    NonConstructableInterpreterCallable(name, func),
  )
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
    bag: PropertyBag::new(),
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
  Array({ elements, bag: PropertyBag::new(), length_writable: true })
}
