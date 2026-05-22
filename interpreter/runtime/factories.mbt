///|
const FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID = -101

///|
const FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID = -102

///|
pub fn make_func(data : FuncData) -> Value {
  let object_proto = get_obj_proto()
  let function_proto = get_func_proto()
  let proto = Object({
    bag: PropertyBag(),
    prototype: object_proto,
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
    is_accessor: false,
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
      is_accessor: false,
    }
  }
  func_props["length"] = Number(func_length)
  func_props["name"] = String_(func_name)
  func_descs["length"] = nf_desc
  func_descs["name"] = nf_desc
  let func_symbol_props = function_realm_symbol_props(
    function_proto, object_proto,
  )
  let func_obj = Object({
    bag: {
      properties: func_props,
      symbol_properties: func_symbol_props,
      descriptors: func_descs,
      symbol_descriptors: function_realm_symbol_descs(
        function_proto, object_proto,
      ),
    },
    prototype: function_proto,
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
          is_accessor: false,
        }
      }
      _ => ()
    }
  }
  func_obj
}

///|
pub fn make_func_ext(data : FuncDataExt) -> Value {
  let object_proto = get_obj_proto()
  let function_proto = get_func_proto()
  let proto = Object({
    bag: PropertyBag(),
    prototype: object_proto,
    callable: None,
    class_name: "Object",
    extensible: true,
  })
  let func_name = match data.name {
    Some(n) => n
    None => ""
  }
  // ES262 §10.2.4 ExpectedArgumentCount: count params before the first
  // one with a default initializer or rest. Destructuring rest is
  // represented as both `rest_param = Some(name)` and a synthetic Param
  // with the same name pushed into `params` (parser/stmt.mbt:314, :353),
  // so the rest-name check is required to avoid overcounting it.
  let mut func_length = 0
  for p in data.params {
    if p.default_val is Some(_) {
      break
    }
    if data.rest_param is Some(rn) && p.name == rn {
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
    is_accessor: false,
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
      is_accessor: false,
    }
  }
  func_props["length"] = Number(func_length.to_double())
  func_props["name"] = String_(func_name)
  func_descs["length"] = nf_desc
  func_descs["name"] = nf_desc
  let func_symbol_props = function_realm_symbol_props(
    function_proto, object_proto,
  )
  let func_obj = Object({
    bag: {
      properties: func_props,
      symbol_properties: func_symbol_props,
      descriptors: func_descs,
      symbol_descriptors: function_realm_symbol_descs(
        function_proto, object_proto,
      ),
    },
    prototype: function_proto,
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
          is_accessor: false,
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
/// Active realm for compatibility getters while code is executing.
fn get_active_realm_state() -> RealmState? {
  current_interpreter.val.map(fn(interp) { interp.realm_state })
}

///|
pub fn get_func_proto() -> Value {
  match get_active_realm_state() {
    Some(realm_state) =>
      match realm_state.active_function_prototype_override.val {
        Some(proto) => proto
        None => realm_state.get_func_proto()
      }
    None => Null
  }
}

///|
pub fn get_obj_proto() -> Value {
  match get_active_realm_state() {
    Some(realm_state) =>
      match realm_state.active_object_prototype_override.val {
        Some(proto) => proto
        None => realm_state.get_obj_proto()
      }
    None => Null
  }
}

///|
pub fn get_string_proto() -> Value {
  match get_active_realm_state() {
    Some(realm_state) => realm_state.get_string_proto()
    None => Null
  }
}

///|
pub fn get_number_proto() -> Value {
  match get_active_realm_state() {
    Some(realm_state) => realm_state.get_number_proto()
    None => Null
  }
}

///|
pub fn get_boolean_proto() -> Value {
  match get_active_realm_state() {
    Some(realm_state) => realm_state.get_boolean_proto()
    None => Null
  }
}

///|
pub fn get_symbol_proto() -> Value {
  match get_active_realm_state() {
    Some(realm_state) => realm_state.get_symbol_proto()
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
  let object_proto = get_obj_proto()
  let function_proto = get_func_proto()
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  Object({
    bag: {
      properties: {
        "length": Number(length.to_double()),
        "name": String_(name),
      },
      symbol_properties: function_realm_symbol_props(
        function_proto, object_proto,
      ),
      descriptors: { "length": nf_desc, "name": nf_desc },
      symbol_descriptors: function_realm_symbol_descs(
        function_proto, object_proto,
      ),
    },
    prototype: function_proto,
    callable: Some(callable),
    class_name: "Function",
    extensible: true,
  })
}

///|
fn function_realm_symbol_props(
  function_proto : Value,
  object_proto : Value,
) -> Map[Int, Value] {
  let props : Map[Int, Value] = {}
  match usable_realm_proto(function_proto) {
    Some(proto) => props[FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID] = proto
    None => ()
  }
  match usable_realm_proto(object_proto) {
    Some(proto) => props[FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID] = proto
    None => ()
  }
  props
}

///|
fn function_realm_symbol_desc() -> PropDescriptor {
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
fn function_realm_symbol_descs(
  function_proto : Value,
  object_proto : Value,
) -> Map[Int, PropDescriptor] {
  let descs : Map[Int, PropDescriptor] = {}
  match usable_realm_proto(function_proto) {
    Some(_) =>
      descs[FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID] = function_realm_symbol_desc()
    None => ()
  }
  match usable_realm_proto(object_proto) {
    Some(_) =>
      descs[FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID] = function_realm_symbol_desc()
    None => ()
  }
  descs
}

///|
fn usable_realm_proto(proto : Value) -> Value? {
  match proto {
    Object(_) => Some(proto)
    _ => None
  }
}

///|
fn function_realm_symbol_prop(data : ObjectData, id : Int) -> Value? {
  match data.bag.symbol_properties.get(id) {
    Some(proto) => usable_realm_proto(proto)
    None => None
  }
}

///|
pub fn stamp_function_realm(value : Value) -> Value {
  stamp_function_realm_with(value, get_func_proto(), get_obj_proto())
}

///|
pub fn stamp_function_realm_with(
  value : Value,
  function_proto : Value,
  object_proto : Value,
) -> Value {
  match value {
    Object(data) =>
      match data.callable {
        Some(_) => {
          match usable_realm_proto(function_proto) {
            Some(proto) => {
              match data.prototype {
                Null => data.prototype = proto
                _ => ()
              }
              data.bag.symbol_properties[FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID] = proto
              data.bag.symbol_descriptors[FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID] = function_realm_symbol_desc()
            }
            None => ()
          }
          match usable_realm_proto(object_proto) {
            Some(proto) => {
              data.bag.symbol_properties[FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID] = proto
              data.bag.symbol_descriptors[FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID] = function_realm_symbol_desc()
            }
            None => ()
          }
        }
        None => ()
      }
    _ => ()
  }
  value
}

///|
fn stamp_function_realm_if_unstamped_with(
  value : Value,
  function_proto : Value,
  object_proto : Value,
) -> Value {
  match value {
    Object(data) =>
      match data.callable {
        Some(_) => {
          match
            (
              function_realm_symbol_prop(
                data,
                FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID,
              ),
              usable_realm_proto(function_proto),
            ) {
            (None, Some(proto)) => {
              match data.prototype {
                Null => data.prototype = proto
                _ => ()
              }
              data.bag.symbol_properties[FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID] = proto
              data.bag.symbol_descriptors[FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID] = function_realm_symbol_desc()
            }
            _ => ()
          }
          match
            (
              function_realm_symbol_prop(
                data,
                FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID,
              ),
              usable_realm_proto(object_proto),
            ) {
            (None, Some(proto)) => {
              data.bag.symbol_properties[FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID] = proto
              data.bag.symbol_descriptors[FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID] = function_realm_symbol_desc()
            }
            _ => ()
          }
        }
        None => ()
      }
    _ => ()
  }
  value
}

///|
fn stamp_function_realm_from_state_if_unstamped(
  value : Value,
  realm_state : RealmState,
) -> Value {
  stamp_function_realm_if_unstamped_with(
    value,
    realm_state.get_func_proto(),
    realm_state.get_obj_proto(),
  )
}

///|
fn object_data_function_realm_protos(data : ObjectData) -> (Value?, Value?) {
  match data.callable {
    Some(_) =>
      (
        function_realm_symbol_prop(
          data,
          FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID,
        ),
        function_realm_symbol_prop(data, FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID),
      )
    None => (None, None)
  }
}

///|
fn callee_realm_protos(callee : Value) -> (Value?, Value?) {
  match callee {
    Object(data) => object_data_function_realm_protos(data)
    Proxy(proxy_data) =>
      match proxy_data.target {
        Some(target) => callee_realm_protos(target)
        None => (None, None)
      }
    _ => (None, None)
  }
}

///|
fn with_active_callee_realm_value(
  callee : Value,
  eval : () -> Value raise Error,
) -> Value raise Error {
  let (function_proto, object_proto) = callee_realm_protos(callee)
  match get_active_realm_state() {
    Some(realm_state) => {
      let prev_function_proto = realm_state.active_function_prototype_override.val
      let prev_object_proto = realm_state.active_object_prototype_override.val
      match function_proto {
        Some(proto) =>
          realm_state.active_function_prototype_override.val = Some(proto)
        None => realm_state.active_function_prototype_override.val = None
      }
      match object_proto {
        Some(proto) =>
          realm_state.active_object_prototype_override.val = Some(proto)
        None => realm_state.active_object_prototype_override.val = None
      }
      try {
        let result = eval()
        realm_state.active_function_prototype_override.val = prev_function_proto
        realm_state.active_object_prototype_override.val = prev_object_proto
        result
      } catch {
        e => {
          realm_state.active_function_prototype_override.val = prev_function_proto
          realm_state.active_object_prototype_override.val = prev_object_proto
          raise e
        }
      }
    }
    None => eval()
  }
}

///|
fn[T] with_cleared_active_callee_realm(
  eval : () -> T raise Error,
) -> T raise Error {
  match get_active_realm_state() {
    Some(realm_state) => {
      let prev_function_proto = realm_state.active_function_prototype_override.val
      let prev_object_proto = realm_state.active_object_prototype_override.val
      realm_state.active_function_prototype_override.val = None
      realm_state.active_object_prototype_override.val = None
      try {
        let result = eval()
        realm_state.active_function_prototype_override.val = prev_function_proto
        realm_state.active_object_prototype_override.val = prev_object_proto
        result
      } catch {
        e => {
          realm_state.active_function_prototype_override.val = prev_function_proto
          realm_state.active_object_prototype_override.val = prev_object_proto
          raise e
        }
      }
    }
    None => eval()
  }
}

///|
fn with_cleared_active_callee_realm_unit(eval : () -> Unit) -> Unit {
  match get_active_realm_state() {
    Some(realm_state) => {
      let prev_function_proto = realm_state.active_function_prototype_override.val
      let prev_object_proto = realm_state.active_object_prototype_override.val
      realm_state.active_function_prototype_override.val = None
      realm_state.active_object_prototype_override.val = None
      eval()
      realm_state.active_function_prototype_override.val = prev_function_proto
      realm_state.active_object_prototype_override.val = prev_object_proto
    }
    None => eval()
  }
}

///|
fn same_realm_state(left : RealmState, right : RealmState) -> Bool {
  physical_equal(
    left.symbols.symbol_id_counter,
    right.symbols.symbol_id_counter,
  )
}

///|
fn standalone_realm_interpreter(realm_state : RealmState) -> Interpreter {
  let global = Environment::new()
  global.realm_state = Some(realm_state)
  let output : Array[String] = []
  let host : HostEnv = {
    output,
    microtask_queue: [],
    timer_queue: [],
    timer_id_counter: { val: 1 },
    timer_insertion_counter: { val: 0 },
    cancelled_timer_ids: {},
    module_loader: None,
  }
  {
    host,
    global,
    global_this: Null,
    annex_b: false,
    realm_state,
    module_registry: {},
    module_exports: {},
    module_export_bindings: [],
    generator_objects: {},
    gen_id_counter: { val: 0 },
    symbols: realm_state.symbols,
    stdlib_hooks: default_stdlib_hooks(),
    in_nonarrow_param_default_eval: false,
  }
}

///|
pub fn with_active_realm_state_unit(
  realm_state : RealmState,
  eval : () -> Unit,
) -> Unit {
  match current_interpreter.val {
    Some(interp) if same_realm_state(interp.realm_state, realm_state) =>
      with_cleared_active_callee_realm_unit(fn() { eval() })
    _ => {
      let prev_interpreter = current_interpreter.val
      current_interpreter.val = Some(standalone_realm_interpreter(realm_state))
      with_cleared_active_callee_realm_unit(fn() { eval() })
      current_interpreter.val = prev_interpreter
    }
  }
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
    bag: PropertyBag(),
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
  Array({
    elements,
    bag: PropertyBag(),
    length_writable: true,
    holes: {},
    extensible: true,
  })
}
