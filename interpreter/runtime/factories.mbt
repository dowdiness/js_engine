///|
// Engine-private negative symbol IDs are reserved in docs/development.md.
// -101 stores a function object's packed home-realm metadata (ten hot-path
// intrinsic prototypes plus the realm's constructor-prototype registry) and
// optional host-supplied source identity as an 11- or 12-element Array[Value].
// Identity-free functions use 11 elements so the call_value fast path can
// reject identity-bearing metadata with one length check.
// -102..-110 are freed. Keep this comment updated if the range changes.
const FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID = -101

///|
const FUNCTION_REALM_PROTO_SLOT_COUNT = 11

///|
const FUNCTION_METADATA_SLOT_COUNT = 12

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
const REALM_PROTO_IDX_CONSTRUCTOR_REGISTRY = 10

///|
const FUNCTION_SOURCE_IDENTITY_IDX = 11

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
  constructor_prototype_registry : Value?
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
  constructor_prototype_registry? : Value? = None,
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
    constructor_prototype_registry,
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
  let func_props : Map[String, Value] = Map([])
  let func_descs : Map[String, PropDescriptor] = Map([])
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
  let source_identity = source_identity_from_state(realm_state~)
  let func_symbol_props = function_realm_symbol_props(
    realm_protos, source_identity,
  )
  let func_obj = Object({
    bag: {
      properties: func_props,
      symbol_properties: func_symbol_props,
      descriptors: func_descs,
      symbol_descriptors: function_realm_symbol_descs(),
      internal_slots: Map([]),
      host_slots: Map([]),
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
  let func_props : Map[String, Value] = Map([])
  let func_descs : Map[String, PropDescriptor] = Map([])
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
  let source_identity = source_identity_from_state(realm_state~)
  let func_symbol_props = function_realm_symbol_props(
    realm_protos, source_identity,
  )
  let func_obj = Object({
    bag: {
      properties: func_props,
      symbol_properties: func_symbol_props,
      descriptors: func_descs,
      symbol_descriptors: function_realm_symbol_descs(),
      internal_slots: Map([]),
      host_slots: Map([]),
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
fn get_constructor_prototype_registry(
  realm_state? : RealmState? = None,
) -> Value {
  match realm_state {
    Some(realm_state) =>
      active_proto_or_base(
        realm_state.active_overrides,
        p => p.constructor_prototype_registry,
        realm_state.constructor_prototype_registry,
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
  let source_identity = source_identity_from_state(realm_state~)
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
        realm_protos, source_identity,
      ),
      descriptors: { "length": nf_desc, "name": nf_desc },
      symbol_descriptors: function_realm_symbol_descs(),
      internal_slots: Map([]),
      host_slots: Map([]),
    },
    prototype: function_proto,
    callable: Some(callable),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
/// Create the shared object representation for an ECMAScript bound function.
///
/// `prototype` is the exact result of the target's `[[GetPrototypeOf]]`
/// operation (§10.4.1.3 BoundFunctionCreate), so `Null` must not be replaced
/// with the realm's `Function.prototype`.
pub fn make_bound_func(
  target : Value,
  bound_this : Value,
  bound_args : Array[Value],
  prototype~ : Value,
  name~ : String,
  length~ : Double,
  realm_state? : RealmState? = None,
) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  stamp_function_realm_impl(
    Object({
      bag: {
        properties: { "length": Number(length), "name": String_(name) },
        symbol_properties: Map([]),
        descriptors: { "length": nf_desc, "name": nf_desc },
        symbol_descriptors: Map([]),
        internal_slots: Map([]),
        host_slots: Map([]),
      },
      prototype,
      callable: Some(BoundFunc(target, bound_this, bound_args.copy())),
      class_name: "Function",
      extensible: true,
      arraybuffer_state: None,
    }),
    function_realm_protos_from_state(realm_state~),
    source_identity_from_state(realm_state~),
    false,
  )
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
        constructor_prototype_registry: usable_realm_proto(
          get_constructor_prototype_registry(realm_state=Some(realm_state)),
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
    constructor_prototype_registry: usable_realm_proto(
      realm_state.constructor_prototype_registry,
    ),
  }
}

///|
fn make_realm_protos_packed_array(
  protos : FunctionRealmProtos,
  source_identity? : String? = None,
) -> Value {
  let slot_count = match source_identity {
    Some(_) => FUNCTION_METADATA_SLOT_COUNT
    None => FUNCTION_REALM_PROTO_SLOT_COUNT
  }
  let e : Array[Value] = Array::make(slot_count, Null)
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
  match protos.constructor_prototype_registry {
    Some(v) => e[REALM_PROTO_IDX_CONSTRUCTOR_REGISTRY] = v
    None => ()
  }
  match source_identity {
    Some(identity) => e[FUNCTION_SOURCE_IDENTITY_IDX] = String_(identity)
    None => ()
  }
  Array({
    elements: e,
    bag: PropertyBag(),
    length_writable: false,
    holes: Map([]),
    extensible: false,
  })
}

///|
fn source_identity_from_state(realm_state? : RealmState? = None) -> String? {
  match realm_state {
    Some(state) => state.active_source_identity.val
    None => None
  }
}

///|
fn function_realm_symbol_props(
  protos : FunctionRealmProtos,
  source_identity : String?,
) -> Map[Int, Value] {
  let props : Map[Int, Value] = Map([])
  props[FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID] = make_realm_protos_packed_array(
    protos,
    source_identity~,
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
fn function_realm_symbol_descs() -> Map[Int, PropDescriptor] {
  let descs : Map[Int, PropDescriptor] = Map([])
  descs[FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID] = function_realm_symbol_desc()
  descs
}

///|
fn stamp_function_source_identity(
  value : Value,
  source_identity : String?,
) -> Unit {
  match (value, source_identity) {
    (Object(data), Some(identity)) if data.callable is Some(_) =>
      match
        data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID) {
        Some(Array(arr_data)) =>
          if arr_data.elements.length() == FUNCTION_SOURCE_IDENTITY_IDX {
            arr_data.elements.push(String_(identity))
          } else if arr_data.elements.length() > FUNCTION_SOURCE_IDENTITY_IDX {
            arr_data.elements[FUNCTION_SOURCE_IDENTITY_IDX] = String_(identity)
          }
        _ => {
          data.bag.symbol_properties[FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID] = make_realm_protos_packed_array(
            empty_function_realm_protos(),
            source_identity=Some(identity),
          )
          data.bag.symbol_descriptors[FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID] = function_realm_symbol_desc()
        }
      }
    _ => ()
  }
}

///|
pub fn function_source_identity(value : Value) -> String? {
  match value {
    Object(data) =>
      match
        data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID) {
        Some(Array(arr_data)) => {
          let own_identity = if arr_data.elements.length() >
            FUNCTION_SOURCE_IDENTITY_IDX {
            match arr_data.elements[FUNCTION_SOURCE_IDENTITY_IDX] {
              String_(identity) => Some(identity)
              _ => None
            }
          } else {
            None
          }
          match own_identity {
            Some(_) => own_identity
            None =>
              match data.callable {
                Some(BoundFunc(target, _, _)) =>
                  function_source_identity(target)
                _ => None
              }
          }
        }
        _ =>
          match data.callable {
            Some(BoundFunc(target, _, _)) => function_source_identity(target)
            _ => None
          }
      }
    Proxy(proxy_data) =>
      match proxy_data.target {
        Some(target) => function_source_identity(target)
        None => None
      }
    _ => None
  }
}

///|
/// A runtime failure paired with the deepest source identity that propagated
/// unchanged to the observation boundary.
pub struct SourceObservedFailure {
  cause_ : Error
  source_identity_ : String?
}

///|
fn SourceObservedFailure::SourceObservedFailure(
  cause : Error,
  source_identity : String?,
) -> SourceObservedFailure {
  { cause_: cause, source_identity_: source_identity }
}

///|
pub fn SourceObservedFailure::cause(self : SourceObservedFailure) -> Error {
  self.cause_
}

///|
pub fn SourceObservedFailure::source_identity(
  self : SourceObservedFailure,
) -> String? {
  self.source_identity_
}

///|
// Preserve the recorded source when a runtime boundary translates an error
// without handling it. This runs only on the failure path.
fn remap_observed_source_failure(
  realm_state : RealmState,
  previous : Error,
  translated : Error,
) -> Unit {
  if realm_state.observing_source_failure.val {
    match realm_state.observed_source_failure.val {
      Some(observed) if physical_equal(observed, previous) =>
        realm_state.observed_source_failure.val = Some(translated)
      _ => ()
    }
  }
}

///|
/// Observe source provenance atomically without changing the raised error.
/// Nested call wrappers record an error only while this scope is active.
pub fn[T] observe_source_failure(
  realm_state : RealmState,
  eval : () -> T raise Error,
) -> Result[T, SourceObservedFailure] {
  let previous_observing = realm_state.observing_source_failure.val
  let previous_failure = realm_state.observed_source_failure.val
  let previous_identity = realm_state.observed_source_identity.val
  let previous_overrides = realm_state.active_overrides.val
  realm_state.observing_source_failure.val = true
  realm_state.observed_source_failure.val = None
  realm_state.observed_source_identity.val = None
  if previous_overrides is None {
    realm_state.active_overrides.val = Some(empty_function_realm_protos())
  }
  try {
    let result = eval()
    realm_state.observing_source_failure.val = previous_observing
    realm_state.observed_source_failure.val = previous_failure
    realm_state.observed_source_identity.val = previous_identity
    realm_state.active_overrides.val = previous_overrides
    Ok(result)
  } catch {
    error => {
      let source_identity = match realm_state.observed_source_failure.val {
        Some(observed) if physical_equal(observed, error) =>
          realm_state.observed_source_identity.val
        _ => None
      }
      realm_state.observing_source_failure.val = previous_observing
      realm_state.observed_source_failure.val = previous_failure
      realm_state.observed_source_identity.val = previous_identity
      realm_state.active_overrides.val = previous_overrides
      Err(SourceObservedFailure(error, source_identity))
    }
  }
}

///|
pub fn[T] with_source_identity(
  realm_state : RealmState,
  source_identity : String?,
  eval : () -> T raise Error,
) -> T raise Error {
  let previous = realm_state.active_source_identity.val
  realm_state.active_source_identity.val = source_identity
  try {
    let result = eval()
    realm_state.active_source_identity.val = previous
    result
  } catch {
    error => {
      realm_state.active_source_identity.val = previous
      raise error
    }
  }
}

///|
fn usable_realm_proto(proto : Value) -> Value? {
  match proto {
    Object(_) => Some(proto)
    _ => None
  }
}

///|
// Returns the packed function-metadata elements for the callee, following Proxy
// targets. Returns None when no packed entry is present (all slots absent).
fn get_callee_function_metadata(callee : Value) -> Array[Value]? {
  match callee {
    Object(data) =>
      match
        data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID) {
        Some(Array(arr_data)) => Some(arr_data.elements)
        _ => None
      }
    Proxy(proxy_data) =>
      match proxy_data.target {
        Some(target) => get_callee_function_metadata(target)
        None => None
      }
    _ => None
  }
}

///|
fn stamp_function_realm_impl(
  value : Value,
  protos : FunctionRealmProtos,
  active_source_identity : String?,
  set_function_prototype : Bool,
) -> Value {
  let stamped = stamp_function_realm_with_protos(
    value, protos, set_function_prototype,
  )
  let source_identity = match active_source_identity {
    Some(identity) => Some(identity)
    None =>
      match stamped {
        Object(data) =>
          match data.callable {
            Some(BoundFunc(target, _, _)) => function_source_identity(target)
            _ => None
          }
        _ => None
      }
  }
  stamp_function_source_identity(stamped, source_identity)
  stamped
}

///|
pub fn stamp_function_realm(
  value : Value,
  realm_state? : RealmState? = None,
) -> Value {
  stamp_function_realm_impl(
    value,
    function_realm_protos_from_state(realm_state~),
    source_identity_from_state(realm_state~),
    true,
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
  stamp_function_realm_with_protos(
    value,
    {
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
      constructor_prototype_registry: None,
    },
    true,
  )
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
          let e : Array[Value] = Array::make(
            FUNCTION_REALM_PROTO_SLOT_COUNT,
            Null,
          )
          e[idx] = proto
          data.bag.symbol_properties[FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID] = Array({
              elements: e,
              bag: PropertyBag(),
              length_writable: false,
              holes: Map([]),
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
  set_function_prototype : Bool,
) -> Value {
  match value {
    Object(data) =>
      match data.callable {
        Some(_) => {
          stamp_realm_proto(
            data,
            REALM_PROTO_IDX_FUNCTION,
            protos.function_proto,
            set_function_prototype~,
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
          stamp_realm_proto(
            data,
            REALM_PROTO_IDX_CONSTRUCTOR_REGISTRY,
            protos.constructor_prototype_registry,
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
          stamp_realm_proto_if_unstamped(
            data,
            REALM_PROTO_IDX_CONSTRUCTOR_REGISTRY,
            protos.constructor_prototype_registry,
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
            constructor_prototype_registry: usable_realm_proto(
              e[REALM_PROTO_IDX_CONSTRUCTOR_REGISTRY],
            ),
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
// GetFunctionRealm-style metadata lookup.  Bound functions recurse through
// their target and revoked proxies raise so callers can apply the spec's
// current-realm fallback for an abrupt GetFunctionRealm completion.
fn get_function_realm_protos(
  callee : Value,
) -> FunctionRealmProtos? raise Error {
  match callee {
    Proxy(proxy_data) => get_function_realm_protos(get_proxy_target(proxy_data))
    Object(data) =>
      match data.callable {
        Some(BoundFunc(target, _, _)) => get_function_realm_protos(target)
        Some(_) =>
          match get_callee_function_metadata(Object(data)) {
            Some(_) => Some(object_data_function_realm_protos(data))
            None => None
          }
        None => None
      }
    _ => None
  }
}

///|
/// Resolve the intrinsic prototype selected by GetPrototypeFromConstructor's
/// primitive-prototype fallback. Proxy and bound-function traversal mirrors
/// GetFunctionRealm; revoked proxies therefore raise before any fallback.
pub fn constructor_realm_intrinsic_prototype(
  new_target : Value,
  intrinsic_name : String,
  default_prototype : Value,
) -> Value raise Error {
  let protos = match get_function_realm_protos(new_target) {
    Some(protos) => protos
    None => empty_function_realm_protos()
  }
  let registered_prototype = match protos.constructor_prototype_registry {
    Some(Object(registry)) => registry.bag.properties.get(intrinsic_name)
    _ => None
  }
  match registered_prototype {
    Some(prototype) => prototype
    None if intrinsic_name == "Object" =>
      protos.object_proto.unwrap_or(default_prototype)
    None => default_prototype
  }
}

///|
// The packed slot represents a callable's own identity. Bound functions inherit
// their target's identity only when their own slot is absent. Proxy traversal is
// lookup-free here because get_callee_function_metadata already followed it.
fn inherited_function_source_identity(callee : Value) -> String? {
  match callee {
    Object(data) =>
      match data.callable {
        Some(BoundFunc(target, _, _)) => function_source_identity(target)
        _ => None
      }
    Proxy(proxy_data) =>
      match proxy_data.target {
        Some(target) => inherited_function_source_identity(target)
        None => None
      }
    _ => None
  }
}

///|
// Returns true when call_value can skip both realm-proto wrapper layers.
// Safe only when every active-override slot is None (no cross-realm context is
// active) AND every callee realm slot is absent or matches the main realm's
// corresponding prototype. All 11 slots are checked in both sets; sampling a
// subset is unsafe because stamp_function_realm_with
// accepts slots independently.
fn realm_fast_path_allowed(callee : Value, realm_state : RealmState) -> Bool {
  // Part 1: no active cross-realm override — one Ref read (None = no overrides active)
  guard realm_state.active_overrides.val is None else { return false }
  // Part 2: source identity and every stamped proto share one packed lookup.
  // This avoids both a second HashMap lookup and rebuilding FunctionRealmProtos.
  match get_callee_function_metadata(callee) {
    None => inherited_function_source_identity(callee) is None
    Some(e) => {
      guard e.length() == FUNCTION_REALM_PROTO_SLOT_COUNT else { return false }
      fn same(idx : Int, main_ref : Ref[Value?]) -> Bool {
        match (e[idx], main_ref.val) {
          (Null, _) => true // absent slot — inherits same-realm semantics
          (Object(c), Some(Object(m))) => physical_equal(c, m)
          _ => false // conservative: any mismatch forces slow path
        }
      }
      fn same_value(idx : Int, main : Value) -> Bool {
        match (e[idx], main) {
          (Null, _) => true
          (Object(c), Object(m)) => physical_equal(c, m)
          _ => false
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
      same(REALM_PROTO_IDX_PROMISE, realm_state.promise_prototype) &&
      same_value(
        REALM_PROTO_IDX_CONSTRUCTOR_REGISTRY,
        realm_state.constructor_prototype_registry,
      )
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
// Low-level realm snapshot, not a cleanup capability. Callback adapters and
// the dispatch shell must provide exactly-once, LIFO ownership around it.
priv struct ClearedActiveCalleeRealmScope {
  previous_realm_protos : FunctionRealmProtos
}

///|
// Low-level realm/source snapshot, not a cleanup capability. It remains
// copyable semantic data; the dispatch shell owns consumption and ordering.
priv struct ActiveCalleeRealmValueScope {
  previous_realm_protos : FunctionRealmProtos
  previous_source_identity : String?
  callee_source_identity : String?
}

///|
fn begin_cleared_active_callee_realm(
  realm_state : RealmState,
) -> ClearedActiveCalleeRealmScope {
  let previous_realm_protos = active_realm_protos(realm_state)
  apply_active_realm_protos(realm_state, empty_function_realm_protos())
  { previous_realm_protos, }
}

///|
fn finish_cleared_active_callee_realm(
  realm_state : RealmState,
  scope : ClearedActiveCalleeRealmScope,
) -> Unit {
  apply_active_realm_protos(realm_state, scope.previous_realm_protos)
}

///|
fn begin_active_callee_realm_value(
  realm_state : RealmState,
  callee : Value,
) -> ActiveCalleeRealmValueScope {
  let previous_realm_protos = active_realm_protos(realm_state)
  let previous_source_identity = realm_state.active_source_identity.val
  let callee_source_identity = function_source_identity(callee)
  apply_active_realm_protos(realm_state, callee_realm_protos(callee))
  realm_state.active_source_identity.val = callee_source_identity
  { previous_realm_protos, previous_source_identity, callee_source_identity }
}

///|
fn record_active_callee_source_failure(
  realm_state : RealmState,
  scope : ActiveCalleeRealmValueScope,
  failure : Error,
) -> Unit {
  if realm_state.observing_source_failure.val {
    let should_record = match scope.callee_source_identity {
      Some(_) =>
        match realm_state.observed_source_failure.val {
          Some(observed) => !physical_equal(observed, failure)
          None => true
        }
      None => false
    }
    if should_record {
      realm_state.observed_source_failure.val = Some(failure)
      realm_state.observed_source_identity.val = scope.callee_source_identity
    }
  }
}

///|
fn finish_active_callee_realm_value(
  realm_state : RealmState,
  scope : ActiveCalleeRealmValueScope,
  failure~ : Error?,
) -> Unit {
  match failure {
    Some(error) =>
      record_active_callee_source_failure(realm_state, scope, error)
    None => ()
  }
  apply_active_realm_protos(realm_state, scope.previous_realm_protos)
  realm_state.active_source_identity.val = scope.previous_source_identity
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
    protos.promise_proto is Some(_) ||
    protos.constructor_prototype_registry is Some(_)
  realm_state.active_overrides.val = if any_set ||
    realm_state.observing_source_failure.val {
    Some(protos)
  } else {
    None
  }
}

///|
fn with_active_callee_realm_value(
  realm_state : RealmState,
  callee : Value,
  eval : () -> Value raise Error,
) -> Value raise Error {
  let scope = begin_active_callee_realm_value(realm_state, callee)
  try {
    let result = eval()
    finish_active_callee_realm_value(realm_state, scope, failure=None)
    result
  } catch {
    e => {
      finish_active_callee_realm_value(realm_state, scope, failure=Some(e))
      raise e
    }
  }
}

///|
// Temporarily install a selected function realm while runtime-owned objects
// are created.  The caller supplies already-resolved metadata; this scope
// never performs guest lookup or call work.
fn[T] with_active_realm_protos(
  realm_state : RealmState,
  protos : FunctionRealmProtos,
  eval : () -> T raise Error,
) -> T raise Error {
  let previous_realm_protos = active_realm_protos(realm_state)
  apply_active_realm_protos(realm_state, protos)
  try {
    let result = eval()
    apply_active_realm_protos(realm_state, previous_realm_protos)
    result
  } catch {
    error => {
      apply_active_realm_protos(realm_state, previous_realm_protos)
      raise error
    }
  }
}

///|
fn[T] with_cleared_active_callee_realm(
  realm_state : RealmState,
  eval : () -> T raise Error,
) -> T raise Error {
  let scope = begin_cleared_active_callee_realm(realm_state)
  try {
    let result = eval()
    finish_cleared_active_callee_realm(realm_state, scope)
    result
  } catch {
    e => {
      finish_cleared_active_callee_realm(realm_state, scope)
      raise e
    }
  }
}

///|
fn with_cleared_active_callee_realm_unit(
  realm_state : RealmState,
  eval : () -> Unit,
) -> Unit {
  let scope = begin_cleared_active_callee_realm(realm_state)
  eval()
  finish_cleared_active_callee_realm(realm_state, scope)
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
      symbol_properties: Map([]),
      descriptors,
      symbol_descriptors: Map([]),
      internal_slots: Map([]),
      host_slots: Map([]),
    },
    prototype,
    callable,
    class_name,
    extensible,
    arraybuffer_state: None,
  })
}

///|
/// Create a host object with methods, accessors, intent-shaped data properties,
/// and embedder host slots (#517). Returns `Value` so callers need not match
/// on `ObjectData`. Composes `install_builtin_*` and `set_host_slot`.
///
/// **Parameters**
/// - `name` — `[[Class]]` / `class_name` string (e.g. `"Element"`).
/// - `proto` — `[[Prototype]]`. Defaults to `Null` (not `%Object.prototype%`);
///   pass a realm object prototype when the host object should inherit from it.
/// - `methods` — string-keyed callables with builtin method descriptors.
/// - `accessors` — map of name → `(getter?, setter?)`. At least one side must
///   be `Some`; use `None` for an absent side.
/// - `non_writable` / `frozen` — rare constant data props (builtin descriptors).
/// - `host_slots` — embedder-private state keyed by pre-reserved `HostSlotKey`
///   values (`HostSlotKey::reserve()` once per slot kind, then build the map).
/// - `extensible` — `[[Extensible]]` (default `true`).
///
/// **Install order:** `non_writable` → `frozen` → `methods` → `accessors` →
/// `host_slots`. Same string key across the JS maps: later step wins (factory
/// stomping, not `[[DefineOwnProperty]]` — avoid dual-defining the same name,
/// including overwriting a `frozen` key).
pub fn make_host_object(
  name~ : String,
  proto? : Value = Null,
  methods? : Map[String, Value] = Map([]),
  accessors? : Map[String, (Value?, Value?)] = Map([]),
  non_writable? : Map[String, Value] = Map([]),
  frozen? : Map[String, Value] = Map([]),
  host_slots? : Map[HostSlotKey, Value] = Map([]),
  extensible? : Bool = true,
) -> Value {
  let obj = make_object(Map([]), proto, None, name, Map([]), extensible)
  guard obj is Object(data) else {
    abort("make_host_object: make_object must return Object")
  }
  non_writable.each(fn(k, v) { install_builtin_non_writable(data, k, v) })
  frozen.each(fn(k, v) { install_builtin_frozen_data(data, k, v) })
  methods.each(fn(k, v) { install_builtin_method(data, k, v) })
  accessors.each(fn(k, pair) {
    let (getter, setter) = pair
    install_builtin_accessor(data, k, getter, setter)
  })
  host_slots.each(fn(k, v) { set_host_slot(data, k, v) })
  obj
}

///|
/// Create an iterator result object { value, done }
pub fn create_iter_result(value : Value, done : Bool) -> Value {
  let props : Map[String, Value] = Map([])
  props["value"] = value
  props["done"] = Bool(done)
  Object({
    bag: {
      properties: props,
      symbol_properties: Map([]),
      descriptors: Map([]),
      symbol_descriptors: Map([]),
      internal_slots: Map([]),
      host_slots: Map([]),
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
    holes: Map([]),
    extensible: true,
  })
}

///|
/// Wrap an Array[Value] with an explicit instance prototype.
/// Constructor adapters use this after resolving newTarget.prototype and
/// before exposing the newly allocated Array value.
pub fn make_array_with_prototype(
  elements : Array[Value],
  prototype : Value,
) -> Value {
  let data : ArrayData = {
    elements,
    bag: PropertyBag(),
    length_writable: true,
    holes: Map([]),
    extensible: true,
  }
  set_array_prototype_override(data, prototype)
  Array(data)
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
