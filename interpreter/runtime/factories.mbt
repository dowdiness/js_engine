///|
// Engine-private negative symbol IDs are reserved in docs/development.md.
// -101 stores a function object's packed home-realm intrinsic prototypes as a
// 10-element Array[Value] (indices REALM_PROTO_IDX_*), enabling the call_value
// fast path to do 1 HashMap lookup + 10 array reads instead of 10 HashMap lookups.
// -102..-110 are freed. Keep this comment updated if the range changes.
const FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID = -101

///|
const REALM_PROTO_IDX_FUNCTION = 0

///|
const REALM_PROTO_IDX_OBJECT = 1

///|
const REALM_PROTO_IDX_STRING = 2

///|
const REALM_PROTO_IDX_NUMBER = 3

///|
const REALM_PROTO_IDX_BOOLEAN = 4

///|
const REALM_PROTO_IDX_SYMBOL = 5

///|
const REALM_PROTO_IDX_ARRAY = 6

///|
const REALM_PROTO_IDX_MAP = 7

///|
const REALM_PROTO_IDX_SET = 8

///|
const REALM_PROTO_IDX_PROMISE = 9

///|
pub(all) struct FunctionRealmProtos {
  function_proto : Value?
  object_proto : Value?
  string_proto : Value?
  number_proto : Value?
  boolean_proto : Value?
  symbol_proto : Value?
  array_proto : Value?
  map_proto : Value?
  set_proto : Value?
  promise_proto : Value?
}

///|
pub fn FunctionRealmProtos::FunctionRealmProtos(
  function_proto? : Value? = None,
  object_proto? : Value? = None,
  string_proto? : Value? = None,
  number_proto? : Value? = None,
  boolean_proto? : Value? = None,
  symbol_proto? : Value? = None,
  array_proto? : Value? = None,
  map_proto? : Value? = None,
  set_proto? : Value? = None,
  promise_proto? : Value? = None,
) -> FunctionRealmProtos {
  {
    function_proto,
    object_proto,
    string_proto,
    number_proto,
    boolean_proto,
    symbol_proto,
    array_proto,
    map_proto,
    set_proto,
    promise_proto,
  }
}

///|
fn empty_function_realm_protos() -> FunctionRealmProtos {
  FunctionRealmProtos()
}

///|
fn active_proto_or_base(
  overrides : Ref[FunctionRealmProtos?],
  get_proto : (FunctionRealmProtos) -> Value?,
  base : Value,
) -> Value {
  match overrides.val {
    None => base
    Some(protos) =>
      match get_proto(protos) {
        Some(p) => p
        None => base
      }
  }
}

///|
pub fn make_func(data : FuncData) -> Value {
  let realm_state = match data.closure.interpreter_context {
    Some(interp) => Some(interp.realm_state)
    None => data.closure.realm_state
  }
  let object_proto = get_obj_proto(realm_state~)
  let function_proto = get_func_proto(realm_state~)
  let realm_protos = function_realm_protos_from_state(realm_state~)
  let proto = Object({
    bag: PropertyBag(),
    prototype: object_proto,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
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
  let func_symbol_props = function_realm_symbol_props(realm_protos)
  let func_obj = Object({
    bag: {
      properties: func_props,
      symbol_properties: func_symbol_props,
      descriptors: func_descs,
      symbol_descriptors: function_realm_symbol_descs(realm_protos),
      internal_slots: {},
      host_slots: {},
    },
    prototype: function_proto,
    callable: Some(UserFunc(data)),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
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
/// ES262 §10.2.4 ExpectedArgumentCount for extended parameter lists:
/// count parameters before the first default initializer or rest parameter.
fn expected_argument_count_ext(params : Array[@ast.Param]) -> Int {
  for p in params; count = 0 {
    if p.default_val is Some(_) || p.is_rest_pattern {
      break count
    }
    continue count + 1
  } nobreak {
    count
  }
}

///|
pub fn make_func_ext(data : FuncDataExt) -> Value {
  let realm_state = match data.closure.interpreter_context {
    Some(interp) => Some(interp.realm_state)
    None => data.closure.realm_state
  }
  let object_proto = get_obj_proto(realm_state~)
  let function_proto = get_func_proto(realm_state~)
  let realm_protos = function_realm_protos_from_state(realm_state~)
  let proto = Object({
    bag: PropertyBag(),
    prototype: object_proto,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  let func_name = match data.name {
    Some(n) => n
    None => ""
  }
  let func_length = expected_argument_count_ext(data.params)
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
  let func_symbol_props = function_realm_symbol_props(realm_protos)
  let func_obj = Object({
    bag: {
      properties: func_props,
      symbol_properties: func_symbol_props,
      descriptors: func_descs,
      symbol_descriptors: function_realm_symbol_descs(realm_protos),
      internal_slots: {},
      host_slots: {},
    },
    prototype: function_proto,
    callable: Some(UserFuncExt(data)),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
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
pub fn get_func_proto(realm_state? : RealmState? = None) -> Value {
  match realm_state {
    Some(realm_state) =>
      active_proto_or_base(
        realm_state.active_overrides,
        p => p.function_proto,
        realm_state.get_func_proto(),
      )
    None => Null
  }
}

///|
pub fn get_obj_proto(realm_state? : RealmState? = None) -> Value {
  match realm_state {
    Some(realm_state) =>
      active_proto_or_base(
        realm_state.active_overrides,
        p => p.object_proto,
        realm_state.get_obj_proto(),
      )
    None => Null
  }
}

///|
pub fn get_string_proto(realm_state? : RealmState? = None) -> Value {
  match realm_state {
    Some(realm_state) =>
      active_proto_or_base(
        realm_state.active_overrides,
        p => p.string_proto,
        realm_state.get_string_proto(),
      )
    None => Null
  }
}

///|
pub fn get_number_proto(realm_state? : RealmState? = None) -> Value {
  match realm_state {
    Some(realm_state) =>
      active_proto_or_base(
        realm_state.active_overrides,
        p => p.number_proto,
        realm_state.get_number_proto(),
      )
    None => Null
  }
}

///|
pub fn get_boolean_proto(realm_state? : RealmState? = None) -> Value {
  match realm_state {
    Some(realm_state) =>
      active_proto_or_base(
        realm_state.active_overrides,
        p => p.boolean_proto,
        realm_state.get_boolean_proto(),
      )
    None => Null
  }
}

///|
pub fn get_symbol_proto(realm_state? : RealmState? = None) -> Value {
  match realm_state {
    Some(realm_state) =>
      active_proto_or_base(
        realm_state.active_overrides,
        p => p.symbol_proto,
        realm_state.get_symbol_proto(),
      )
    None => Null
  }
}

///|
pub fn get_array_proto(realm_state? : RealmState? = None) -> Value {
  match realm_state {
    Some(realm_state) =>
      active_proto_or_base(
        realm_state.active_overrides,
        p => p.array_proto,
        realm_state.get_array_proto(),
      )
    None => Null
  }
}

///|
pub fn get_map_proto(realm_state? : RealmState? = None) -> Value {
  match realm_state {
    Some(realm_state) =>
      active_proto_or_base(
        realm_state.active_overrides,
        p => p.map_proto,
        realm_state.get_map_proto(),
      )
    None => Null
  }
}

///|
pub fn get_set_proto(realm_state? : RealmState? = None) -> Value {
  match realm_state {
    Some(realm_state) =>
      active_proto_or_base(
        realm_state.active_overrides,
        p => p.set_proto,
        realm_state.get_set_proto(),
      )
    None => Null
  }
}

///|
pub fn get_promise_proto(realm_state? : RealmState? = None) -> Value {
  match realm_state {
    Some(realm_state) =>
      active_proto_or_base(
        realm_state.active_overrides,
        p => p.promise_proto,
        realm_state.get_promise_proto(),
      )
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
fn build_func_object(
  name : String,
  length : Int,
  callable : Callable,
  realm_state? : RealmState? = None,
) -> Value {
  let function_proto = get_func_proto(realm_state~)
  let realm_protos = function_realm_protos_from_state(realm_state~)
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
      symbol_properties: function_realm_symbol_props(realm_protos),
      descriptors: { "length": nf_desc, "name": nf_desc },
      symbol_descriptors: function_realm_symbol_descs(realm_protos),
      internal_slots: {},
      host_slots: {},
    },
    prototype: function_proto,
    callable: Some(callable),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
fn function_realm_protos_from_state(
  realm_state? : RealmState? = None,
) -> FunctionRealmProtos {
  match realm_state {
    Some(realm_state) =>
      {
        function_proto: usable_realm_proto(
          get_func_proto(realm_state=Some(realm_state)),
        ),
        object_proto: usable_realm_proto(
          get_obj_proto(realm_state=Some(realm_state)),
        ),
        string_proto: usable_realm_proto(
          get_string_proto(realm_state=Some(realm_state)),
        ),
        number_proto: usable_realm_proto(
          get_number_proto(realm_state=Some(realm_state)),
        ),
        boolean_proto: usable_realm_proto(
          get_boolean_proto(realm_state=Some(realm_state)),
        ),
        symbol_proto: usable_realm_proto(
          get_symbol_proto(realm_state=Some(realm_state)),
        ),
        array_proto: usable_realm_proto(
          get_array_proto(realm_state=Some(realm_state)),
        ),
        map_proto: usable_realm_proto(
          get_map_proto(realm_state=Some(realm_state)),
        ),
        set_proto: usable_realm_proto(
          get_set_proto(realm_state=Some(realm_state)),
        ),
        promise_proto: usable_realm_proto(
          get_promise_proto(realm_state=Some(realm_state)),
        ),
      }
    None => empty_function_realm_protos()
  }
}

///|
fn function_realm_protos_from_realm_state(
  realm_state : RealmState,
) -> FunctionRealmProtos {
  {
    function_proto: usable_realm_proto(realm_state.get_func_proto()),
    object_proto: usable_realm_proto(realm_state.get_obj_proto()),
    string_proto: usable_realm_proto(realm_state.get_string_proto()),
    number_proto: usable_realm_proto(realm_state.get_number_proto()),
    boolean_proto: usable_realm_proto(realm_state.get_boolean_proto()),
    symbol_proto: usable_realm_proto(realm_state.get_symbol_proto()),
    array_proto: usable_realm_proto(realm_state.get_array_proto()),
    map_proto: usable_realm_proto(realm_state.get_map_proto()),
    set_proto: usable_realm_proto(realm_state.get_set_proto()),
    promise_proto: usable_realm_proto(realm_state.get_promise_proto()),
  }
}

///|
fn make_realm_protos_packed_array(protos : FunctionRealmProtos) -> Value {
  let e : Array[Value] = Array::make(10, Null)
  match protos.function_proto {
    Some(v) => e[REALM_PROTO_IDX_FUNCTION] = v
    None => ()
  }
  match protos.object_proto {
    Some(v) => e[REALM_PROTO_IDX_OBJECT] = v
    None => ()
  }
  match protos.string_proto {
    Some(v) => e[REALM_PROTO_IDX_STRING] = v
    None => ()
  }
  match protos.number_proto {
    Some(v) => e[REALM_PROTO_IDX_NUMBER] = v
    None => ()
  }
  match protos.boolean_proto {
    Some(v) => e[REALM_PROTO_IDX_BOOLEAN] = v
    None => ()
  }
  match protos.symbol_proto {
    Some(v) => e[REALM_PROTO_IDX_SYMBOL] = v
    None => ()
  }
  match protos.array_proto {
    Some(v) => e[REALM_PROTO_IDX_ARRAY] = v
    None => ()
  }
  match protos.map_proto {
    Some(v) => e[REALM_PROTO_IDX_MAP] = v
    None => ()
  }
  match protos.set_proto {
    Some(v) => e[REALM_PROTO_IDX_SET] = v
    None => ()
  }
  match protos.promise_proto {
    Some(v) => e[REALM_PROTO_IDX_PROMISE] = v
    None => ()
  }
  Array({
    elements: e,
    bag: PropertyBag(),
    length_writable: false,
    holes: {},
    extensible: false,
  })
}

///|
fn function_realm_symbol_props(protos : FunctionRealmProtos) -> Map[Int, Value] {
  let props : Map[Int, Value] = {}
  props[FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID] = make_realm_protos_packed_array(
    protos,
  )
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
  _ : FunctionRealmProtos,
) -> Map[Int, PropDescriptor] {
  let descs : Map[Int, PropDescriptor] = {}
  descs[FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID] = function_realm_symbol_desc()
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
// Returns the 10-element packed-proto array elements for the callee, following
// Proxy targets. Returns None when no packed entry is present (all slots absent).
fn get_callee_packed_realm_protos(callee : Value) -> Array[Value]? {
  match callee {
    Object(data) =>
      match
        data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID) {
        Some(Array(arr_data)) => Some(arr_data.elements)
        _ => None
      }
    Proxy(proxy_data) =>
      match proxy_data.target {
        Some(target) => get_callee_packed_realm_protos(target)
        None => None
      }
    _ => None
  }
}

///|
pub fn stamp_function_realm(
  value : Value,
  realm_state? : RealmState? = None,
) -> Value {
  stamp_function_realm_with_protos(
    value,
    function_realm_protos_from_state(realm_state~),
  )
}

///|
pub fn stamp_function_realm_with(
  value : Value,
  function_proto : Value,
  object_proto : Value,
  string_proto? : Value = Null,
  number_proto? : Value = Null,
  boolean_proto? : Value = Null,
  symbol_proto? : Value = Null,
  array_proto? : Value = Null,
  map_proto? : Value = Null,
  set_proto? : Value = Null,
  promise_proto? : Value = Null,
) -> Value {
  stamp_function_realm_with_protos(value, {
    function_proto: usable_realm_proto(function_proto),
    object_proto: usable_realm_proto(object_proto),
    string_proto: usable_realm_proto(string_proto),
    number_proto: usable_realm_proto(number_proto),
    boolean_proto: usable_realm_proto(boolean_proto),
    symbol_proto: usable_realm_proto(symbol_proto),
    array_proto: usable_realm_proto(array_proto),
    map_proto: usable_realm_proto(map_proto),
    set_proto: usable_realm_proto(set_proto),
    promise_proto: usable_realm_proto(promise_proto),
  })
}

///|
fn stamp_realm_proto(
  data : ObjectData,
  idx : Int,
  proto : Value?,
  set_function_prototype? : Bool = false,
) -> Unit {
  match proto {
    Some(proto) => {
      if set_function_prototype {
        match data.prototype {
          Null => data.prototype = proto
          _ => ()
        }
      }
      match
        data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID) {
        Some(Array(arr_data)) => arr_data.elements[idx] = proto
        _ => {
          let e : Array[Value] = Array::make(10, Null)
          e[idx] = proto
          data.bag.symbol_properties[FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID] = Array({
              elements: e,
              bag: PropertyBag(),
              length_writable: false,
              holes: {},
              extensible: false,
            },
          )
          data.bag.symbol_descriptors[FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID] = function_realm_symbol_desc()
        }
      }
    }
    None => ()
  }
}

///|
fn stamp_realm_proto_if_unstamped(
  data : ObjectData,
  idx : Int,
  proto : Value?,
  set_function_prototype? : Bool = false,
) -> Unit {
  match proto {
    None => ()
    Some(proto) => {
      let already_set = match
        data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID) {
        Some(Array(arr_data)) =>
          match arr_data.elements[idx] {
            Null => false
            _ => true
          }
        _ => false
      }
      if !already_set {
        stamp_realm_proto(data, idx, Some(proto), set_function_prototype~)
      }
    }
  }
}

///|
fn stamp_function_realm_with_protos(
  value : Value,
  protos : FunctionRealmProtos,
) -> Value {
  match value {
    Object(data) =>
      match data.callable {
        Some(_) => {
          stamp_realm_proto(
            data,
            REALM_PROTO_IDX_FUNCTION,
            protos.function_proto,
            set_function_prototype=true,
          )
          stamp_realm_proto(data, REALM_PROTO_IDX_OBJECT, protos.object_proto)
          stamp_realm_proto(data, REALM_PROTO_IDX_STRING, protos.string_proto)
          stamp_realm_proto(data, REALM_PROTO_IDX_NUMBER, protos.number_proto)
          stamp_realm_proto(data, REALM_PROTO_IDX_BOOLEAN, protos.boolean_proto)
          stamp_realm_proto(data, REALM_PROTO_IDX_SYMBOL, protos.symbol_proto)
          stamp_realm_proto(data, REALM_PROTO_IDX_ARRAY, protos.array_proto)
          stamp_realm_proto(data, REALM_PROTO_IDX_MAP, protos.map_proto)
          stamp_realm_proto(data, REALM_PROTO_IDX_SET, protos.set_proto)
          stamp_realm_proto(data, REALM_PROTO_IDX_PROMISE, protos.promise_proto)
        }
        None => ()
      }
    _ => ()
  }
  value
}

///|
fn stamp_function_realm_if_unstamped_with_protos(
  value : Value,
  protos : FunctionRealmProtos,
) -> Value {
  match value {
    Object(data) =>
      match data.callable {
        Some(_) => {
          stamp_realm_proto_if_unstamped(
            data,
            REALM_PROTO_IDX_FUNCTION,
            protos.function_proto,
            set_function_prototype=true,
          )
          stamp_realm_proto_if_unstamped(
            data,
            REALM_PROTO_IDX_OBJECT,
            protos.object_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            REALM_PROTO_IDX_STRING,
            protos.string_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            REALM_PROTO_IDX_NUMBER,
            protos.number_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            REALM_PROTO_IDX_BOOLEAN,
            protos.boolean_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            REALM_PROTO_IDX_SYMBOL,
            protos.symbol_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            REALM_PROTO_IDX_ARRAY,
            protos.array_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            REALM_PROTO_IDX_MAP,
            protos.map_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            REALM_PROTO_IDX_SET,
            protos.set_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            REALM_PROTO_IDX_PROMISE,
            protos.promise_proto,
          )
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
  stamp_function_realm_if_unstamped_with_protos(
    value,
    function_realm_protos_from_realm_state(realm_state),
  )
}

///|
fn object_data_function_realm_protos(data : ObjectData) -> FunctionRealmProtos {
  match data.callable {
    None => empty_function_realm_protos()
    Some(_) =>
      match
        data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID) {
        Some(Array(arr_data)) => {
          let e = arr_data.elements
          {
            function_proto: usable_realm_proto(e[REALM_PROTO_IDX_FUNCTION]),
            object_proto: usable_realm_proto(e[REALM_PROTO_IDX_OBJECT]),
            string_proto: usable_realm_proto(e[REALM_PROTO_IDX_STRING]),
            number_proto: usable_realm_proto(e[REALM_PROTO_IDX_NUMBER]),
            boolean_proto: usable_realm_proto(e[REALM_PROTO_IDX_BOOLEAN]),
            symbol_proto: usable_realm_proto(e[REALM_PROTO_IDX_SYMBOL]),
            array_proto: usable_realm_proto(e[REALM_PROTO_IDX_ARRAY]),
            map_proto: usable_realm_proto(e[REALM_PROTO_IDX_MAP]),
            set_proto: usable_realm_proto(e[REALM_PROTO_IDX_SET]),
            promise_proto: usable_realm_proto(e[REALM_PROTO_IDX_PROMISE]),
          }
        }
        _ => empty_function_realm_protos()
      }
  }
}

///|
fn callee_realm_protos(callee : Value) -> FunctionRealmProtos {
  match callee {
    Object(data) => object_data_function_realm_protos(data)
    Proxy(proxy_data) =>
      match proxy_data.target {
        Some(target) => callee_realm_protos(target)
        None => empty_function_realm_protos()
      }
    _ => empty_function_realm_protos()
  }
}

///|
// Returns true when call_value can skip both realm-proto wrapper layers.
// Safe only when every active-override slot is None (no cross-realm context is
// active) AND every callee realm slot is absent or matches the main realm's
// corresponding prototype. All 10 slots are checked in both sets; sampling a
// subset is unsafe because stamp_function_realm_with
// accepts slots independently.
fn realm_fast_path_allowed(callee : Value, realm_state : RealmState) -> Bool {
  // Part 1: no active cross-realm override — one Ref read (None = no overrides active)
  guard realm_state.active_overrides.val is None else { return false }
  // Part 2: every callee stamped proto is absent or pointer-equal to the main realm's.
  // One HashMap lookup + 10 array reads — avoids rebuilding a FunctionRealmProtos struct.
  match get_callee_packed_realm_protos(callee) {
    None => true // no protos stamped at all — all slots absent → same-realm
    Some(e) => {
      fn same(idx : Int, main_ref : Ref[Value?]) -> Bool {
        match (e[idx], main_ref.val) {
          (Null, _) => true // absent slot — inherits same-realm semantics
          (Object(c), Some(Object(m))) => physical_equal(c, m)
          _ => false // conservative: any mismatch forces slow path
        }
      }
      same(REALM_PROTO_IDX_FUNCTION, realm_state.function_prototype) &&
      same(REALM_PROTO_IDX_OBJECT, realm_state.object_prototype) &&
      same(REALM_PROTO_IDX_STRING, realm_state.string_prototype) &&
      same(REALM_PROTO_IDX_NUMBER, realm_state.number_prototype) &&
      same(REALM_PROTO_IDX_BOOLEAN, realm_state.boolean_prototype) &&
      same(REALM_PROTO_IDX_SYMBOL, realm_state.symbol_prototype) &&
      same(REALM_PROTO_IDX_ARRAY, realm_state.array_prototype) &&
      same(REALM_PROTO_IDX_MAP, realm_state.map_prototype) &&
      same(REALM_PROTO_IDX_SET, realm_state.set_prototype) &&
      same(REALM_PROTO_IDX_PROMISE, realm_state.promise_prototype)
    }
  }
}

///|
fn active_realm_protos(realm_state : RealmState) -> FunctionRealmProtos {
  match realm_state.active_overrides.val {
    None => empty_function_realm_protos()
    Some(protos) => protos
  }
}

///|
pub fn apply_active_realm_protos(
  realm_state : RealmState,
  protos : FunctionRealmProtos,
) -> Unit {
  let any_set = protos.function_proto is Some(_) ||
    protos.object_proto is Some(_) ||
    protos.string_proto is Some(_) ||
    protos.number_proto is Some(_) ||
    protos.boolean_proto is Some(_) ||
    protos.symbol_proto is Some(_) ||
    protos.array_proto is Some(_) ||
    protos.map_proto is Some(_) ||
    protos.set_proto is Some(_) ||
    protos.promise_proto is Some(_)
  realm_state.active_overrides.val = if any_set { Some(protos) } else { None }
}

///|
fn with_active_callee_realm_value(
  realm_state : RealmState,
  callee : Value,
  eval : () -> Value raise Error,
) -> Value raise Error {
  let prev = active_realm_protos(realm_state)
  apply_active_realm_protos(realm_state, callee_realm_protos(callee))
  try {
    let result = eval()
    apply_active_realm_protos(realm_state, prev)
    result
  } catch {
    e => {
      apply_active_realm_protos(realm_state, prev)
      raise e
    }
  }
}

///|
fn[T] with_cleared_active_callee_realm(
  realm_state : RealmState,
  eval : () -> T raise Error,
) -> T raise Error {
  let prev = active_realm_protos(realm_state)
  apply_active_realm_protos(realm_state, empty_function_realm_protos())
  try {
    let result = eval()
    apply_active_realm_protos(realm_state, prev)
    result
  } catch {
    e => {
      apply_active_realm_protos(realm_state, prev)
      raise e
    }
  }
}

///|
fn with_cleared_active_callee_realm_unit(
  realm_state : RealmState,
  eval : () -> Unit,
) -> Unit {
  let prev = active_realm_protos(realm_state)
  apply_active_realm_protos(realm_state, empty_function_realm_protos())
  eval()
  apply_active_realm_protos(realm_state, prev)
}

///|
pub fn with_active_realm_state_unit(
  realm_state : RealmState,
  eval : () -> Unit,
) -> Unit {
  with_cleared_active_callee_realm_unit(realm_state, fn() { eval() })
}

///|
/// Non-constructable native function: callback is `(Array[Value]) -> Value raise Error`.
/// Use for built-in free functions and static methods.
pub fn make_native_func(
  name~ : String,
  length? : Int = 0,
  realm_state? : RealmState? = None,
  func : (Array[Value]) -> Value raise Error,
) -> Value {
  build_func_object(
    name,
    length,
    NonConstructableCallable(name, func),
    realm_state~,
  )
}

///|
/// Method function: callback receives `this`. Signature
/// `(Value, Array[Value]) -> Value raise Error`.
pub fn make_method_func(
  name~ : String,
  length? : Int = 0,
  realm_state? : RealmState? = None,
  func : (Value, Array[Value]) -> Value raise Error,
) -> Value {
  build_func_object(name, length, MethodCallable(name, func), realm_state~)
}

///|
/// Interpreter-aware method function: callback receives interpreter and `this`.
/// Signature `(Interpreter, Value, Array[Value]) -> Value raise Error`.
pub fn make_interp_method_func(
  name~ : String,
  length? : Int = 0,
  realm_state? : RealmState? = None,
  func : (Interpreter, Value, Array[Value]) -> Value raise Error,
) -> Value {
  build_func_object(name, length, InterpreterCallable(name, func), realm_state~)
}

///|
/// Interpreter-aware method function with explicit call/construct context.
pub fn make_interp_method_func_with_context(
  name~ : String,
  length? : Int = 0,
  func : (Interpreter, CallContext, Value, Array[Value]) -> Value raise Error,
) -> Value {
  build_func_object(name, length, InterpreterCallableWithContext(name, func))
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
      internal_slots: {},
      host_slots: {},
    },
    prototype,
    callable,
    class_name,
    extensible,
    arraybuffer_state: None,
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
      internal_slots: {},
      host_slots: {},
    },
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
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
    arraybuffer_state: None,
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

///|
/// Wrap an Array[Value] and mark selected indices as array holes.
pub fn make_array_with_holes(
  elements : Array[Value],
  hole_indices : Array[Int],
) -> Value {
  let arr = make_array(elements)
  match arr {
    Array(data) =>
      for i in hole_indices {
        data.holes[i] = ()
      }
    _ => ()
  }
  arr
}
