///|
const FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID = -101

///|
const FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID = -102

///|
const FUNCTION_REALM_STRING_PROTO_SYMBOL_ID = -103

///|
const FUNCTION_REALM_NUMBER_PROTO_SYMBOL_ID = -104

///|
const FUNCTION_REALM_BOOLEAN_PROTO_SYMBOL_ID = -105

///|
const FUNCTION_REALM_SYMBOL_PROTO_SYMBOL_ID = -106

///|
const FUNCTION_REALM_ARRAY_PROTO_SYMBOL_ID = -107

///|
const FUNCTION_REALM_MAP_PROTO_SYMBOL_ID = -108

///|
const FUNCTION_REALM_SET_PROTO_SYMBOL_ID = -109

///|
const FUNCTION_REALM_PROMISE_PROTO_SYMBOL_ID = -110

///|
priv struct FunctionRealmProtos {
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
fn empty_function_realm_protos() -> FunctionRealmProtos {
  {
    function_proto: None,
    object_proto: None,
    string_proto: None,
    number_proto: None,
    boolean_proto: None,
    symbol_proto: None,
    array_proto: None,
    map_proto: None,
    set_proto: None,
    promise_proto: None,
  }
}

///|
fn active_proto_or_base(active : Ref[Value?], base : Value) -> Value {
  match active.val {
    Some(proto) => proto
    None => base
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
  // ES262 §10.2.4 ExpectedArgumentCount: count params before the first
  // one with a default initializer or rest.
  let mut func_length = 0
  for p in data.params {
    if p.default_val is Some(_) {
      break
    }
    if p.is_rest_pattern {
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
  let func_symbol_props = function_realm_symbol_props(realm_protos)
  let func_obj = Object({
    bag: {
      properties: func_props,
      symbol_properties: func_symbol_props,
      descriptors: func_descs,
      symbol_descriptors: function_realm_symbol_descs(realm_protos),
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
      match realm_state.active_function_prototype_override.val {
        Some(proto) => proto
        None => realm_state.get_func_proto()
      }
    None => Null
  }
}

///|
pub fn get_obj_proto(realm_state? : RealmState? = None) -> Value {
  match realm_state {
    Some(realm_state) =>
      match realm_state.active_object_prototype_override.val {
        Some(proto) => proto
        None => realm_state.get_obj_proto()
      }
    None => Null
  }
}

///|
pub fn get_string_proto(realm_state? : RealmState? = None) -> Value {
  match realm_state {
    Some(realm_state) =>
      active_proto_or_base(
        realm_state.active_string_prototype_override,
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
        realm_state.active_number_prototype_override,
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
        realm_state.active_boolean_prototype_override,
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
        realm_state.active_symbol_prototype_override,
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
        realm_state.active_array_prototype_override,
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
        realm_state.active_map_prototype_override,
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
        realm_state.active_set_prototype_override,
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
        realm_state.active_promise_prototype_override,
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
fn put_function_realm_symbol_prop(
  props : Map[Int, Value],
  id : Int,
  proto : Value?,
) -> Unit {
  match proto {
    Some(proto) => props[id] = proto
    None => ()
  }
}

///|
fn function_realm_symbol_props(protos : FunctionRealmProtos) -> Map[Int, Value] {
  let props : Map[Int, Value] = {}
  put_function_realm_symbol_prop(
    props,
    FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID,
    protos.function_proto,
  )
  put_function_realm_symbol_prop(
    props,
    FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID,
    protos.object_proto,
  )
  put_function_realm_symbol_prop(
    props,
    FUNCTION_REALM_STRING_PROTO_SYMBOL_ID,
    protos.string_proto,
  )
  put_function_realm_symbol_prop(
    props,
    FUNCTION_REALM_NUMBER_PROTO_SYMBOL_ID,
    protos.number_proto,
  )
  put_function_realm_symbol_prop(
    props,
    FUNCTION_REALM_BOOLEAN_PROTO_SYMBOL_ID,
    protos.boolean_proto,
  )
  put_function_realm_symbol_prop(
    props,
    FUNCTION_REALM_SYMBOL_PROTO_SYMBOL_ID,
    protos.symbol_proto,
  )
  put_function_realm_symbol_prop(
    props,
    FUNCTION_REALM_ARRAY_PROTO_SYMBOL_ID,
    protos.array_proto,
  )
  put_function_realm_symbol_prop(
    props,
    FUNCTION_REALM_MAP_PROTO_SYMBOL_ID,
    protos.map_proto,
  )
  put_function_realm_symbol_prop(
    props,
    FUNCTION_REALM_SET_PROTO_SYMBOL_ID,
    protos.set_proto,
  )
  put_function_realm_symbol_prop(
    props,
    FUNCTION_REALM_PROMISE_PROTO_SYMBOL_ID,
    protos.promise_proto,
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
fn put_function_realm_symbol_desc(
  descs : Map[Int, PropDescriptor],
  id : Int,
  proto : Value?,
) -> Unit {
  match proto {
    Some(_) => descs[id] = function_realm_symbol_desc()
    None => ()
  }
}

///|
fn function_realm_symbol_descs(
  protos : FunctionRealmProtos,
) -> Map[Int, PropDescriptor] {
  let descs : Map[Int, PropDescriptor] = {}
  put_function_realm_symbol_desc(
    descs,
    FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID,
    protos.function_proto,
  )
  put_function_realm_symbol_desc(
    descs,
    FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID,
    protos.object_proto,
  )
  put_function_realm_symbol_desc(
    descs,
    FUNCTION_REALM_STRING_PROTO_SYMBOL_ID,
    protos.string_proto,
  )
  put_function_realm_symbol_desc(
    descs,
    FUNCTION_REALM_NUMBER_PROTO_SYMBOL_ID,
    protos.number_proto,
  )
  put_function_realm_symbol_desc(
    descs,
    FUNCTION_REALM_BOOLEAN_PROTO_SYMBOL_ID,
    protos.boolean_proto,
  )
  put_function_realm_symbol_desc(
    descs,
    FUNCTION_REALM_SYMBOL_PROTO_SYMBOL_ID,
    protos.symbol_proto,
  )
  put_function_realm_symbol_desc(
    descs,
    FUNCTION_REALM_ARRAY_PROTO_SYMBOL_ID,
    protos.array_proto,
  )
  put_function_realm_symbol_desc(
    descs,
    FUNCTION_REALM_MAP_PROTO_SYMBOL_ID,
    protos.map_proto,
  )
  put_function_realm_symbol_desc(
    descs,
    FUNCTION_REALM_SET_PROTO_SYMBOL_ID,
    protos.set_proto,
  )
  put_function_realm_symbol_desc(
    descs,
    FUNCTION_REALM_PROMISE_PROTO_SYMBOL_ID,
    protos.promise_proto,
  )
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
  id : Int,
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
      data.bag.symbol_properties[id] = proto
      data.bag.symbol_descriptors[id] = function_realm_symbol_desc()
    }
    None => ()
  }
}

///|
fn stamp_realm_proto_if_unstamped(
  data : ObjectData,
  id : Int,
  proto : Value?,
  set_function_prototype? : Bool = false,
) -> Unit {
  match (function_realm_symbol_prop(data, id), proto) {
    (None, Some(proto)) =>
      stamp_realm_proto(data, id, Some(proto), set_function_prototype~)
    _ => ()
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
            FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID,
            protos.function_proto,
            set_function_prototype=true,
          )
          stamp_realm_proto(
            data,
            FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID,
            protos.object_proto,
          )
          stamp_realm_proto(
            data,
            FUNCTION_REALM_STRING_PROTO_SYMBOL_ID,
            protos.string_proto,
          )
          stamp_realm_proto(
            data,
            FUNCTION_REALM_NUMBER_PROTO_SYMBOL_ID,
            protos.number_proto,
          )
          stamp_realm_proto(
            data,
            FUNCTION_REALM_BOOLEAN_PROTO_SYMBOL_ID,
            protos.boolean_proto,
          )
          stamp_realm_proto(
            data,
            FUNCTION_REALM_SYMBOL_PROTO_SYMBOL_ID,
            protos.symbol_proto,
          )
          stamp_realm_proto(
            data,
            FUNCTION_REALM_ARRAY_PROTO_SYMBOL_ID,
            protos.array_proto,
          )
          stamp_realm_proto(
            data,
            FUNCTION_REALM_MAP_PROTO_SYMBOL_ID,
            protos.map_proto,
          )
          stamp_realm_proto(
            data,
            FUNCTION_REALM_SET_PROTO_SYMBOL_ID,
            protos.set_proto,
          )
          stamp_realm_proto(
            data,
            FUNCTION_REALM_PROMISE_PROTO_SYMBOL_ID,
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
            FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID,
            protos.function_proto,
            set_function_prototype=true,
          )
          stamp_realm_proto_if_unstamped(
            data,
            FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID,
            protos.object_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            FUNCTION_REALM_STRING_PROTO_SYMBOL_ID,
            protos.string_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            FUNCTION_REALM_NUMBER_PROTO_SYMBOL_ID,
            protos.number_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            FUNCTION_REALM_BOOLEAN_PROTO_SYMBOL_ID,
            protos.boolean_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            FUNCTION_REALM_SYMBOL_PROTO_SYMBOL_ID,
            protos.symbol_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            FUNCTION_REALM_ARRAY_PROTO_SYMBOL_ID,
            protos.array_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            FUNCTION_REALM_MAP_PROTO_SYMBOL_ID,
            protos.map_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            FUNCTION_REALM_SET_PROTO_SYMBOL_ID,
            protos.set_proto,
          )
          stamp_realm_proto_if_unstamped(
            data,
            FUNCTION_REALM_PROMISE_PROTO_SYMBOL_ID,
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
    Some(_) =>
      {
        function_proto: function_realm_symbol_prop(
          data,
          FUNCTION_REALM_FUNCTION_PROTO_SYMBOL_ID,
        ),
        object_proto: function_realm_symbol_prop(
          data,
          FUNCTION_REALM_OBJECT_PROTO_SYMBOL_ID,
        ),
        string_proto: function_realm_symbol_prop(
          data,
          FUNCTION_REALM_STRING_PROTO_SYMBOL_ID,
        ),
        number_proto: function_realm_symbol_prop(
          data,
          FUNCTION_REALM_NUMBER_PROTO_SYMBOL_ID,
        ),
        boolean_proto: function_realm_symbol_prop(
          data,
          FUNCTION_REALM_BOOLEAN_PROTO_SYMBOL_ID,
        ),
        symbol_proto: function_realm_symbol_prop(
          data,
          FUNCTION_REALM_SYMBOL_PROTO_SYMBOL_ID,
        ),
        array_proto: function_realm_symbol_prop(
          data,
          FUNCTION_REALM_ARRAY_PROTO_SYMBOL_ID,
        ),
        map_proto: function_realm_symbol_prop(
          data,
          FUNCTION_REALM_MAP_PROTO_SYMBOL_ID,
        ),
        set_proto: function_realm_symbol_prop(
          data,
          FUNCTION_REALM_SET_PROTO_SYMBOL_ID,
        ),
        promise_proto: function_realm_symbol_prop(
          data,
          FUNCTION_REALM_PROMISE_PROTO_SYMBOL_ID,
        ),
      }
    None => empty_function_realm_protos()
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
fn active_realm_protos(realm_state : RealmState) -> FunctionRealmProtos {
  {
    function_proto: realm_state.active_function_prototype_override.val,
    object_proto: realm_state.active_object_prototype_override.val,
    string_proto: realm_state.active_string_prototype_override.val,
    number_proto: realm_state.active_number_prototype_override.val,
    boolean_proto: realm_state.active_boolean_prototype_override.val,
    symbol_proto: realm_state.active_symbol_prototype_override.val,
    array_proto: realm_state.active_array_prototype_override.val,
    map_proto: realm_state.active_map_prototype_override.val,
    set_proto: realm_state.active_set_prototype_override.val,
    promise_proto: realm_state.active_promise_prototype_override.val,
  }
}

///|
fn apply_active_realm_protos(
  realm_state : RealmState,
  protos : FunctionRealmProtos,
) -> Unit {
  realm_state.active_function_prototype_override.val = protos.function_proto
  realm_state.active_object_prototype_override.val = protos.object_proto
  realm_state.active_string_prototype_override.val = protos.string_proto
  realm_state.active_number_prototype_override.val = protos.number_proto
  realm_state.active_boolean_prototype_override.val = protos.boolean_proto
  realm_state.active_symbol_prototype_override.val = protos.symbol_proto
  realm_state.active_array_prototype_override.val = protos.array_proto
  realm_state.active_map_prototype_override.val = protos.map_proto
  realm_state.active_set_prototype_override.val = protos.set_proto
  realm_state.active_promise_prototype_override.val = protos.promise_proto
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
