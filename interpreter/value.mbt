///|
pub(all) struct FuncData {
  name : String?
  params : Array[String]
  body : Array[@ast.Stmt]
  closure : Environment
  strict : Bool
}

///|
pub(all) struct FuncDataExt {
  name : String?
  params : Array[@ast.Param]
  rest_param : String?
  body : Array[@ast.Stmt]
  closure : Environment
  strict : Bool
}

///|
pub(all) enum Callable {
  UserFunc(FuncData)
  ArrowFunc(FuncData)
  UserFuncExt(FuncDataExt)
  ArrowFuncExt(FuncDataExt)
  NativeCallable(String, (Array[Value]) -> Value raise Error)
  NonConstructableCallable(String, (Array[Value]) -> Value raise Error) // like NativeCallable but throws on new
  BoundFunc(Value, Value, Array[Value]) // (target, this_val, bound_args)
  FuncCallMethod(Value) // .call proxy: captures target function
  FuncApplyMethod(Value) // .apply proxy: captures target function
  MethodCallable(String, (Value, Array[Value]) -> Value raise Error) // this-aware native method
  InterpreterCallable(
    String,
    (Interpreter, Value, Array[Value]) -> Value raise Error
  ) // needs interpreter for callback invocation
  ConstructorOnlyCallable(
    String,
    (Interpreter, Array[Value]) -> Value raise Error
  ) // like InterpreterCallable but throws on call without new
  // Class constructor: (name, prototype, super_ctor, constructor_fn, closure, static_methods)
  // constructor_fn is (params, body) tuple, or None if no explicit constructor
  ClassConstructor(
    String, // class name
    Value, // prototype object
    Value?, // super constructor (if extends)
    (Array[String], Array[@ast.Stmt])?, // constructor params and body
    Environment, // closure environment
    Value
  ) // prototype object reference for super
}

///|
pub(all) struct PropDescriptor {
  mut writable : Bool
  mut enumerable : Bool
  mut configurable : Bool
  mut getter : Value? // Accessor descriptor: get function (None = not an accessor)
  mut setter : Value? // Accessor descriptor: set function (None = not an accessor)
}

///|
pub(all) struct ObjectData {
  properties : Map[String, Value]
  symbol_properties : Map[Int, Value] // Symbol-keyed properties (key is symbol ID)
  mut prototype : Value // Mutable to support Object.setPrototypeOf()
  callable : Callable?
  class_name : String
  descriptors : Map[String, PropDescriptor]
  symbol_descriptors : Map[Int, PropDescriptor] // Descriptors for symbol properties
  mut extensible : Bool
}

///|
pub(all) struct ArrayData {
  elements : Array[Value]
}

///|
/// Symbol data structure - each symbol has a unique ID and optional description
pub(all) struct SymbolData {
  id : Int // Unique identifier for this symbol
  description : String? // Optional description (the argument to Symbol())
}

///|
/// Map data structure - stores key-value pairs with insertion order preservation
/// Uses SameValueZero for key comparison (NaN === NaN, +0 === -0)
pub(all) struct MapData {
  entries : Array[(Value, Value)] // Array of (key, value) pairs
}

///|
/// Set data structure - stores unique values with insertion order preservation
/// Uses SameValueZero for value comparison (NaN === NaN, +0 === -0)
pub(all) struct SetData {
  values : Array[Value] // Array of unique values
}

///|
/// Promise state per ECMAScript spec
pub(all) enum PromiseState {
  Pending
  Fulfilled
  Rejected
}

///|
/// Promise reaction record - stores callbacks for promise resolution
/// Each reaction contains the handler (onFulfilled or onRejected) and the
/// dependent promise's resolve/reject capabilities
pub(all) struct PromiseReaction {
  handler : Value? // The callback function (None means identity/thrower)
  resolve : Value // Resolve function for the dependent promise
  reject : Value // Reject function for the dependent promise
  reaction_type : PromiseReactionType // Fulfill or Reject
}

///|
pub(all) enum PromiseReactionType {
  Fulfill
  Reject
}

///|
/// Promise data structure per ECMAScript spec
/// Promises have a state, result value, and queues of pending reactions
pub(all) struct PromiseData {
  mut state : PromiseState
  mut result : Value // undefined when pending, result when settled
  fulfill_reactions : Array[PromiseReaction] // Called when fulfilled
  reject_reactions : Array[PromiseReaction] // Called when rejected
  mut is_handled : Bool // Whether .catch or second arg to .then was provided
  properties : Map[String, Value] // User-defined properties (p.foo = 1)
  symbol_properties : Map[Int, Value] // Symbol-keyed properties (p[Symbol()] = 1)
  descriptors : Map[String, PropDescriptor]
  symbol_descriptors : Map[Int, PropDescriptor]
}

///|
/// Create a new pending promise data structure
pub fn new_promise_data() -> PromiseData {
  {
    state: Pending,
    result: Undefined,
    fulfill_reactions: [],
    reject_reactions: [],
    is_handled: false,
    properties: {},
    symbol_properties: {},
    descriptors: {},
    symbol_descriptors: {},
  }
}

///|
/// Per-array override for Symbol.iterator defined via Object.defineProperty on
/// Array instances. Stored out-of-line because ArrayData currently models only
/// indexed elements.
let array_iterator_overrides : Array[(ArrayData, Value?, Value?)] = []

///|
/// Named properties on arrays (e.g., index, input on RegExp exec results)
let array_named_props : Array[(ArrayData, Map[String, Value])] = []

///|
pub fn set_array_named_prop(
  arr : ArrayData,
  key : String,
  value : Value,
) -> Unit {
  for i = 0; i < array_named_props.length(); i = i + 1 {
    let (existing, props) = array_named_props[i]
    if physical_equal(existing, arr) {
      props[key] = value
      return
    }
  }
  let props : Map[String, Value] = {}
  props[key] = value
  array_named_props.push((arr, props))
}

///|
pub fn get_array_named_prop(arr : ArrayData, key : String) -> Value? {
  for i = 0; i < array_named_props.length(); i = i + 1 {
    let (existing, props) = array_named_props[i]
    if physical_equal(existing, arr) {
      return props.get(key)
    }
  }
  None
}

///|
/// Symbol properties on arrays (side-table, same approach as named props)
let array_symbol_props : Array[(ArrayData, Map[Int, Value])] = []

///|
pub fn set_array_symbol_prop(
  arr : ArrayData,
  sym_id : Int,
  value : Value,
) -> Unit {
  for i = 0; i < array_symbol_props.length(); i = i + 1 {
    let (existing, props) = array_symbol_props[i]
    if physical_equal(existing, arr) {
      props[sym_id] = value
      return
    }
  }
  let props : Map[Int, Value] = {}
  props[sym_id] = value
  array_symbol_props.push((arr, props))
}

///|
pub fn get_array_symbol_prop(arr : ArrayData, sym_id : Int) -> Value? {
  for i = 0; i < array_symbol_props.length(); i = i + 1 {
    let (existing, props) = array_symbol_props[i]
    if physical_equal(existing, arr) {
      return props.get(sym_id)
    }
  }
  None
}

///|
pub fn set_array_iterator_override(
  arr : ArrayData,
  getter : Value?,
  value : Value?,
) -> Unit {
  for i = 0; i < array_iterator_overrides.length(); i = i + 1 {
    let (existing, _g, _v) = array_iterator_overrides[i]
    if physical_equal(existing, arr) {
      array_iterator_overrides[i] = (arr, getter, value)
      return
    }
  }
  array_iterator_overrides.push((arr, getter, value))
}

///|
pub fn get_array_iterator_override(arr : ArrayData) -> (Value?, Value?) {
  for i = 0; i < array_iterator_overrides.length(); i = i + 1 {
    let (existing, getter, value) = array_iterator_overrides[i]
    if physical_equal(existing, arr) {
      return (getter, value)
    }
  }
  (None, None)
}

///|
/// Flag set by eval_new before calling a NativeCallable so the callee can
/// distinguish `new Foo()` from `Foo()`.  Safe because NativeCallable has
/// no Interpreter access and therefore cannot re-enter eval_new.
pub let is_constructing : Ref[Bool] = { val: false }

///|
/// Check if a Value is a constructor (has [[Construct]] internal method)
pub fn is_constructor_value(v : Value) -> Bool {
  match v {
    Object(data) =>
      match data.callable {
        Some(UserFunc(_)) | Some(UserFuncExt(_)) => true
        Some(NativeCallable(_, _)) => true
        Some(ClassConstructor(_, _, _, _, _, _)) => true
        Some(ConstructorOnlyCallable(_, _)) => true
        Some(BoundFunc(target, _, _)) => is_constructor_value(target)
        Some(NonConstructableCallable(_, _)) => false
        Some(MethodCallable(_, _)) => false
        Some(InterpreterCallable(_, _)) =>
          // GeneratorFunction callables are not constructors;
          // other InterpreterCallable like builtins also aren't
          false
        Some(ArrowFunc(_)) | Some(ArrowFuncExt(_)) => false
        Some(FuncCallMethod(_)) | Some(FuncApplyMethod(_)) => false
        None => false
      }
    Proxy(pd) =>
      match pd.target {
        Some(inner) => is_constructor_value(inner)
        None => false
      }
    _ => false
  }
}

///|
/// Check if a Value is a function (has a callable)
pub fn is_function_value(v : Value) -> Bool {
  match v {
    Object(data) => data.callable is Some(_)
    _ => false
  }
}

///|
/// Global counter for generating unique symbol IDs
let symbol_id_counter : Ref[Int] = { val: 0 }

///|
/// Global map of all symbols by ID (for looking up symbols from property keys)
let all_symbols : Map[Int, SymbolData] = {}

///|
/// Create a new symbol with a unique ID
pub fn new_symbol(description : String?) -> SymbolData {
  let id = symbol_id_counter.val
  symbol_id_counter.val = id + 1
  let sym : SymbolData = { id, description }
  all_symbols[id] = sym
  sym
}

///|
/// Get a symbol by its ID
pub fn get_symbol_by_id(id : Int) -> SymbolData? {
  all_symbols.get(id)
}

///|
/// Global symbol registry for Symbol.for() and Symbol.keyFor()
let global_symbol_registry : Map[String, SymbolData] = {}

///|
/// Reverse lookup: symbol ID -> registry key (for O(1) Symbol.keyFor)
let symbol_registry_reverse : Map[Int, String] = {}

///|
/// Well-known Symbol.iterator - stored globally for iterator protocol support
pub let well_known_iterator_sym : Ref[SymbolData?] = { val: None }

///|
/// Well-known Symbol.asyncIterator - stored globally for async iteration support
pub let well_known_async_iterator_sym : Ref[SymbolData?] = { val: None }

///|
/// Well-known Symbol.hasInstance - stored globally for instanceof operator support
pub let well_known_hasinstance_sym : Ref[SymbolData?] = { val: None }

///|
/// Get the well-known Symbol.iterator
pub fn get_iterator_symbol() -> SymbolData {
  match well_known_iterator_sym.val {
    Some(sym) => sym
    None => abort("Symbol.iterator not initialized")
  }
}

///|
/// Get the well-known Symbol.asyncIterator
pub fn get_async_iterator_symbol() -> SymbolData {
  match well_known_async_iterator_sym.val {
    Some(sym) => sym
    None => abort("Symbol.asyncIterator not initialized")
  }
}

///|
/// Get the well-known Symbol.hasInstance
pub fn get_hasinstance_symbol() -> SymbolData {
  match well_known_hasinstance_sym.val {
    Some(sym) => sym
    None => abort("Symbol.hasInstance not initialized")
  }
}

///|
/// Well-known Symbol.isConcatSpreadable
pub let well_known_isconcatspreadable_sym : Ref[SymbolData?] = { val: None }

///|
pub fn get_isconcatspreadable_symbol() -> SymbolData {
  match well_known_isconcatspreadable_sym.val {
    Some(sym) => sym
    None => abort("Symbol.isConcatSpreadable not initialized")
  }
}

///|
/// Well-known Symbol.toPrimitive - stored globally for @@toPrimitive support
pub let well_known_toprimitive_sym : Ref[SymbolData?] = { val: None }

///|
/// Get the well-known Symbol.toPrimitive
pub fn get_toprimitive_symbol() -> SymbolData {
  match well_known_toprimitive_sym.val {
    Some(sym) => sym
    None => abort("Symbol.toPrimitive not initialized")
  }
}

///|
/// Well-known Symbol.toStringTag - stored globally for @@toStringTag support
pub let well_known_tostringtag_sym : Ref[SymbolData?] = { val: None }

///|
/// Get the well-known Symbol.toStringTag
pub fn get_tostringtag_symbol() -> SymbolData {
  match well_known_tostringtag_sym.val {
    Some(sym) => sym
    None => abort("Symbol.toStringTag not initialized")
  }
}

///|
/// Well-known Symbol.match - stored globally for RegExp @@match support
pub let well_known_match_sym : Ref[SymbolData?] = { val: None }

///|
/// Well-known Symbol.replace - stored globally for RegExp @@replace support
pub let well_known_replace_sym : Ref[SymbolData?] = { val: None }

///|
/// Well-known Symbol.search - stored globally for RegExp @@search support
pub let well_known_search_sym : Ref[SymbolData?] = { val: None }

///|
/// Well-known Symbol.species - stored globally for @@species support
pub let well_known_species_sym : Ref[SymbolData?] = { val: None }

///|
/// Get the well-known Symbol.species
pub fn get_species_symbol() -> SymbolData {
  match well_known_species_sym.val {
    Some(sym) => sym
    None => abort("Symbol.species not initialized")
  }
}

///|
/// Well-known Symbol.matchAll - stored globally for RegExp @@matchAll support
pub let well_known_matchall_sym : Ref[SymbolData?] = { val: None }

///|
/// Well-known Symbol.split - stored globally for RegExp @@split support
pub let well_known_split_sym : Ref[SymbolData?] = { val: None }

///|
/// Get the well-known Symbol.match
pub fn get_match_symbol() -> SymbolData {
  match well_known_match_sym.val {
    Some(sym) => sym
    None => abort("Symbol.match not initialized")
  }
}

///|
/// Get the well-known Symbol.replace
pub fn get_replace_symbol() -> SymbolData {
  match well_known_replace_sym.val {
    Some(sym) => sym
    None => abort("Symbol.replace not initialized")
  }
}

///|
/// Get the well-known Symbol.search
pub fn get_search_symbol() -> SymbolData {
  match well_known_search_sym.val {
    Some(sym) => sym
    None => abort("Symbol.search not initialized")
  }
}

///|
/// Get the well-known Symbol.split
pub fn get_split_symbol() -> SymbolData {
  match well_known_split_sym.val {
    Some(sym) => sym
    None => abort("Symbol.split not initialized")
  }
}

///|
/// Get the well-known Symbol.matchAll
pub fn get_matchall_symbol() -> SymbolData {
  match well_known_matchall_sym.val {
    Some(sym) => sym
    None => abort("Symbol.matchAll not initialized")
  }
}

///|
/// Well-known Symbol.unscopables - stored globally for with statement support
pub let well_known_unscopables_sym : Ref[SymbolData?] = { val: None }

///|
/// Get the well-known Symbol.unscopables
pub fn get_unscopables_symbol() -> SymbolData {
  match well_known_unscopables_sym.val {
    Some(sym) => sym
    None => abort("Symbol.unscopables not initialized")
  }
}

///|
/// Get the Symbol.toStringTag value by walking the prototype chain.
/// Checks symbol properties and evaluates getter descriptors if present.
/// Per spec, errors thrown by @@toStringTag getters propagate to the caller.
pub fn get_tostringtag_value(data : ObjectData) -> String? raise Error {
  let sym = get_tostringtag_symbol()
  // Walk the object and its prototype chain
  let mut current : Value = Object(data)
  while true {
    match current {
      Object(obj_data) => {
        // Check for getter descriptor on symbol property
        match obj_data.symbol_descriptors.get(sym.id) {
          Some(desc) =>
            match desc.getter {
              Some(getter_fn) =>
                // Call the getter with the original object as `this`
                match getter_fn {
                  Object(getter_data) =>
                    match getter_data.callable {
                      Some(MethodCallable(_, f)) => {
                        let result = f(Object(data), [])
                        match result {
                          String_(s) => return Some(s)
                          _ => return None
                        }
                      }
                      Some(NativeCallable(_, f)) | Some(NonConstructableCallable(_, f)) => {
                        let result = f([Object(data)])
                        match result {
                          String_(s) => return Some(s)
                          _ => return None
                        }
                      }
                      _ => return None
                    }
                  _ => return None
                }
              None => ()
            }
          None => ()
        }
        // Check direct symbol property value
        match obj_data.symbol_properties.get(sym.id) {
          Some(String_(s)) => return Some(s)
          Some(_) => return None // non-string toStringTag, short-circuit per spec
          None => ()
        }
        current = obj_data.prototype
      }
      _ => break
    }
  }
  None
}

///|
/// Proxy data structure - wraps a target and handler for meta-programming
pub(all) struct ProxyData {
  mut target : Value? // None when revoked
  mut handler : Value? // None when revoked
  is_callable : Bool // Set at creation time, persists after revocation
}

///|
pub(all) enum Value {
  Number(Double)
  String_(String)
  Bool(Bool)
  Null
  Undefined
  Object(ObjectData)
  Array(ArrayData)
  Symbol(SymbolData)
  Map(MapData)
  Set(SetData)
  Promise(PromiseData)
  Proxy(ProxyData)
}

///|
pub suberror JsException {
  JsException(Value)
}

///|
pub fn make_func(data : FuncData) -> Value {
  let proto = Object({
    properties: {},
    symbol_properties: {},
    prototype: get_obj_proto(),
    callable: None,
    class_name: "Object",
    descriptors: {},
    symbol_descriptors: {},
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
    properties: {
      "prototype": proto,
      "name": String_(func_name),
      "length": Number(func_length),
    },
    symbol_properties: {},
    prototype: get_func_proto(),
    callable: Some(UserFunc(data)),
    class_name: "Function",
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
    extensible: true,
  })
  match proto {
    Object(proto_data) => {
      proto_data.properties["constructor"] = func_obj
      proto_data.descriptors["constructor"] = {
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
    properties: {},
    symbol_properties: {},
    prototype: get_obj_proto(),
    callable: None,
    class_name: "Object",
    descriptors: {},
    symbol_descriptors: {},
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
    properties: {
      "prototype": proto,
      "name": String_(func_name),
      "length": Number(func_length.to_double()),
    },
    symbol_properties: {},
    prototype: get_func_proto(),
    callable: Some(UserFuncExt(data)),
    class_name: "Function",
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
    extensible: true,
  })
  match proto {
    Object(proto_data) => {
      proto_data.properties["constructor"] = func_obj
      proto_data.descriptors["constructor"] = {
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
fn get_func_proto() -> Value {
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
    properties: { "name": String_(name), "length": Number(0.0) },
    symbol_properties: {},
    prototype: get_func_proto(),
    callable: Some(NonConstructableCallable(name, func)),
    class_name: "Function",
    descriptors: { "name": nf_desc, "length": nf_desc },
    symbol_descriptors: {},
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
    properties: props,
    symbol_properties: {},
    prototype: get_func_proto(),
    callable: Some(NonConstructableCallable(name, func)),
    class_name: "Function",
    descriptors: { "name": nf_desc, "length": nf_desc },
    symbol_descriptors: {},
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
    properties: { "name": String_(name), "length": Number(0.0) },
    symbol_properties: {},
    prototype: get_func_proto(),
    callable: Some(NonConstructableCallable(name, func)),
    class_name: "Function",
    descriptors: { "name": nf_desc, "length": nf_desc },
    symbol_descriptors: {},
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
    properties: props,
    symbol_properties: {},
    prototype: get_func_proto(),
    callable: Some(NonConstructableCallable(name, func)),
    class_name: "Function",
    descriptors: { "name": nf_desc, "length": nf_desc },
    symbol_descriptors: {},
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
    properties: props,
    symbol_properties: {},
    prototype: get_func_proto(),
    callable: Some(MethodCallable(name, func)),
    class_name: "Function",
    descriptors: { "name": nf_desc, "length": nf_desc },
    symbol_descriptors: {},
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
    properties: props,
    symbol_properties: {},
    prototype: get_func_proto(),
    callable: Some(InterpreterCallable(name, func)),
    class_name: "Function",
    descriptors: { "name": nf_desc, "length": nf_desc },
    symbol_descriptors: {},
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
    properties,
    symbol_properties: {},
    prototype,
    callable,
    class_name,
    descriptors,
    symbol_descriptors: {},
    extensible,
  })
}

///|
/// Helper to create a plain object
pub fn make_plain_object() -> Value {
  Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Object",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
pub impl Show for Value with output(self, logger) {
  match self {
    Number(n) => {
      // Format integers without decimal point
      let i = n.to_int()
      if i.to_double() == n && not(n.is_inf()) && not(n.is_nan()) {
        logger.write_string(i.to_string())
      } else {
        logger.write_string(n.to_string())
      }
    }
    String_(s) => logger.write_string(s)
    Bool(b) => logger.write_string(b.to_string())
    Null => logger.write_string("null")
    Undefined => logger.write_string("undefined")
    Object(data) =>
      match data.callable {
        Some(UserFunc(func)) =>
          match func.name {
            Some(n) => logger.write_string("function \{n}() { [code] }")
            None => logger.write_string("function() { [code] }")
          }
        Some(ArrowFunc(_)) | Some(ArrowFuncExt(_)) =>
          logger.write_string("() => { [code] }")
        Some(UserFuncExt(func)) =>
          match func.name {
            Some(n) => logger.write_string("function \{n}() { [code] }")
            None => logger.write_string("function() { [code] }")
          }
        Some(BoundFunc(_, _, _)) =>
          logger.write_string("function bound() { [native code] }")
        Some(NativeCallable(name, _)) =>
          logger.write_string("function \{name}() { [native code] }")
        Some(NonConstructableCallable(name, _)) =>
          logger.write_string("function \{name}() { [native code] }")
        Some(FuncCallMethod(_)) =>
          logger.write_string("function call() { [native code] }")
        Some(FuncApplyMethod(_)) =>
          logger.write_string("function apply() { [native code] }")
        Some(MethodCallable(name, _)) =>
          logger.write_string("function \{name}() { [native code] }")
        Some(InterpreterCallable(name, _)) =>
          logger.write_string("function \{name}() { [native code] }")
        Some(ConstructorOnlyCallable(name, _)) =>
          logger.write_string("function \{name}() { [native code] }")
        Some(ClassConstructor(name, _, _, _, _, _)) =>
          logger.write_string("class \{name} { [code] }")
        None =>
          // Boxed primitive objects: unwrap to primitive string representation
          if data.class_name == "String" {
            match data.properties.get("[[StringData]]") {
              Some(String_(s)) => logger.write_string(s)
              _ => logger.write_string("[object String]")
            }
          } else if data.class_name == "Number" {
            match data.properties.get("[[NumberData]]") {
              Some(n) => n.output(logger)
              _ => logger.write_string("[object Number]")
            }
          } else if data.class_name == "Boolean" {
            match data.properties.get("[[BooleanData]]") {
              Some(Bool(b)) => logger.write_string(b.to_string())
              _ => logger.write_string("[object Boolean]")
            }
          } else if data.class_name.has_suffix("Error") {
            let name = match data.properties.get("name") {
              Some(String_(s)) => s
              _ => data.class_name
            }
            let msg = match data.properties.get("message") {
              Some(String_(s)) => s
              _ => ""
            }
            if msg == "" {
              logger.write_string(name)
            } else {
              logger.write_string(name + ": " + msg)
            }
          } else {
            logger.write_string("[object \{data.class_name}]")
          }
      }
    Array(data) =>
      logger.write_string(data.elements.map(fn(v) { v.to_string() }).join(","))
    Symbol(sym) =>
      match sym.description {
        Some(desc) => logger.write_string("Symbol(\{desc})")
        None => logger.write_string("Symbol()")
      }
    Map(_) => logger.write_string("[object Map]")
    Set(_) => logger.write_string("[object Set]")
    Promise(_) => logger.write_string("[object Promise]")
    Proxy(_) => logger.write_string("[object Object]")
  }
}

///|
pub fn is_truthy(val : Value) -> Bool {
  match val {
    Number(n) => n != 0.0 && not(n.is_nan())
    String_(s) => s.length() > 0
    Bool(b) => b
    Null => false
    Undefined => false
    Object(_) => true
    Array(_) => true
    Symbol(_) => true // Symbols are always truthy
    Map(_) => true // Maps are always truthy
    Set(_) => true // Sets are always truthy
    Promise(_) => true // Promises are always truthy
    Proxy(_) => true // Proxies are always truthy
  }
}

///|
/// Global ref to current interpreter, set during execution so that
/// ToPrimitive can call user-defined valueOf/toString/@@toPrimitive.
pub let current_interpreter : Ref[Interpreter?] = { val: None }

///|
/// Call a callable value, dispatching to the interpreter for UserFunc types.
/// Supports all callable types including user-defined functions.
fn call_callable_direct(
  callable_val : Value,
  this_val : Value,
  args : Array[Value],
) -> Value raise Error {
  match callable_val {
    Object(obj_data) =>
      match obj_data.callable {
        Some(MethodCallable(_, f)) => f(this_val, args)
        Some(NativeCallable(_, f)) => f(args)
        Some(NonConstructableCallable(_, f)) => f(args)
        Some(UserFunc(_)) | Some(ArrowFunc(_)) | Some(UserFuncExt(_)) |
        Some(ArrowFuncExt(_)) | Some(BoundFunc(_, _, _)) |
        Some(InterpreterCallable(_, _)) | Some(ClassConstructor(_, _, _, _, _, _)) =>
          // Use the current interpreter to call user-defined functions
          match current_interpreter.val {
            Some(interp) =>
              interp.call_value(
                callable_val,
                this_val,
                args,
                @token.Loc::default(),
              )
            None =>
              raise @errors.TypeError(
                message="Cannot call user function without interpreter context",
              )
          }
        _ =>
          raise @errors.TypeError(message="Value is not callable")
      }
    _ => raise @errors.TypeError(message="Value is not callable")
  }
}

///|
/// SetFunctionName: set name property on anonymous functions per ES2015+.
/// Only sets name if the current name is empty (anonymous).
pub fn set_function_name(val : Value, name : String) -> Unit {
  match val {
    Object(data) =>
      match data.callable {
        Some(_) =>
          // Only set if current name is empty (anonymous)
          match data.properties.get("name") {
            Some(String_(s)) =>
              if s == "" {
                data.properties["name"] = String_(name)
              }
            None => data.properties["name"] = String_(name)
            _ => ()
          }
        None => ()
      }
    _ => ()
  }
}

///|
/// Check if a value is callable
fn is_callable(val : Value) -> Bool {
  match val {
    Object(obj_data) =>
      match obj_data.callable {
        Some(_) => true
        None => false
      }
    _ => false
  }
}

///|
/// Look up a string-keyed property on an object, walking the prototype chain.
/// HasProperty: check if a named property exists on the object or its prototype chain
pub fn has_property(val : Value, name : String) -> Bool {
  match val {
    Object(data) => lookup_property_chain(data, name) is Some(_)
    Array(data) => {
      if name == "length" {
        return true
      }
      try {
        let n = @strconv.parse_double(name)
        let i = n.to_int()
        if i.to_double() == n && i >= 0 && i < data.elements.length() {
          return true
        }
      } catch {
        _ => ()
      }
      if get_array_named_prop(data, name) is Some(_) {
        return true
      }
      // Walk Array.prototype chain for inherited properties
      match current_interpreter.val {
        Some(interp) => {
          let ctor = interp.global.get("Array") catch { _ => return false }
          match ctor {
            Object(ctor_data) =>
              match ctor_data.properties.get("prototype") {
                Some(Object(proto_data)) =>
                  lookup_property_chain(proto_data, name) is Some(_)
                _ => false
              }
            _ => false
          }
        }
        None => false
      }
    }
    _ => false
  }
}

fn lookup_property_chain(data : ObjectData, name : String) -> Value? {
  // Check own properties first
  match data.properties.get(name) {
    Some(v) => return Some(v)
    None => ()
  }
  // Walk prototype chain
  let mut current = data.prototype
  let mut func_fallback_used = false
  while true {
    match current {
      Object(proto_data) => {
        match proto_data.properties.get(name) {
          Some(v) => return Some(v)
          None => current = proto_data.prototype
        }
      }
      Null => {
        // For function objects, fall back to Function.prototype once
        if not(func_fallback_used) {
          match data.callable {
            Some(_) =>
              match current_interpreter.val {
                Some(interp) => {
                  let fp = interp.global.get("[[FunctionPrototype]]") catch {
                    _ => break
                  }
                  func_fallback_used = true
                  current = fp
                }
                None => break
              }
            None => break
          }
        } else {
          break
        }
      }
      _ => break
    }
  }
  None
}

///|
/// Look up a symbol-keyed property on an object, walking the prototype chain.
/// Also handles getter descriptors - invokes them and returns the result.
fn lookup_symbol_property_chain(
  obj_val : Value,
  data : ObjectData,
  sym_id : Int,
) -> Value? raise Error {
  // Check own symbol descriptors for getter first
  match data.symbol_descriptors.get(sym_id) {
    Some(desc) =>
      match desc.getter {
        Some(getter_fn) => {
          let result = call_callable_direct(getter_fn, obj_val, [])
          return Some(result)
        }
        None => ()
      }
    None => ()
  }
  // Check own symbol properties
  match data.symbol_properties.get(sym_id) {
    Some(v) => return Some(v)
    None => ()
  }
  // Walk prototype chain
  let mut current = data.prototype
  while true {
    match current {
      Object(proto_data) => {
        // Check symbol descriptors for getter
        match proto_data.symbol_descriptors.get(sym_id) {
          Some(desc) =>
            match desc.getter {
              Some(getter_fn) => {
                let result = call_callable_direct(getter_fn, obj_val, [])
                return Some(result)
              }
              None => ()
            }
          None => ()
        }
        match proto_data.symbol_properties.get(sym_id) {
          Some(v) => return Some(v)
          None => current = proto_data.prototype
        }
      }
      _ => break
    }
  }
  None
}

///|
/// ToPrimitive(input, hint "number") - converts an object to a primitive value.
/// Follows the ECMAScript spec: check @@toPrimitive, then valueOf, then toString.
fn to_primitive_number(obj_val : Value, data : ObjectData) -> Value raise Error {
  // Step 1: Check for Symbol.toPrimitive
  let to_prim_sym = get_toprimitive_symbol()
  match lookup_symbol_property_chain(obj_val, data, to_prim_sym.id) {
    Some(exotic_to_prim) => {
      // If it's not callable, throw TypeError (GetMethod step 4)
      if not(is_callable(exotic_to_prim)) {
        raise @errors.TypeError(
          message="Symbol.toPrimitive is not a function",
        )
      }
      // Call it with hint "number"
      let result = call_callable_direct(
        exotic_to_prim,
        obj_val,
        [String_("number")],
      )
      // If result is an object, throw TypeError
      match result {
        Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
          raise @errors.TypeError(
            message="Cannot convert object to primitive value",
          )
        _ => return result
      }
    }
    None => ()
  }
  // Step 2: OrdinaryToPrimitive with hint "number" - try valueOf first, then toString
  // Use interpreter for property lookup if available (handles synthetic props on functions etc.)
  let value_of_fn : Value? = match lookup_property_chain(data, "valueOf") {
    Some(f) => Some(f)
    None =>
      match current_interpreter.val {
        Some(interp) => {
          let v = interp.get_property(
            obj_val,
            "valueOf",
            @token.Loc::default(),
          ) catch { _ => Undefined }
          if is_callable(v) { Some(v) } else { None }
        }
        None => None
      }
  }
  match value_of_fn {
    Some(vo_fn) =>
      if is_callable(vo_fn) {
        let result = call_callable_direct(vo_fn, obj_val, [])
        match result {
          Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
            () // result is object, try toString next
          _ => return result
        }
      }
    None => ()
  }
  let to_string_fn : Value? = match lookup_property_chain(data, "toString") {
    Some(f) => Some(f)
    None =>
      match current_interpreter.val {
        Some(interp) => {
          let v = interp.get_property(
            obj_val,
            "toString",
            @token.Loc::default(),
          ) catch { _ => Undefined }
          if is_callable(v) { Some(v) } else { None }
        }
        None => None
      }
  }
  match to_string_fn {
    Some(ts_fn) =>
      if is_callable(ts_fn) {
        let result = call_callable_direct(ts_fn, obj_val, [])
        match result {
          Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
            raise @errors.TypeError(
              message="Cannot convert object to primitive value",
            )
          _ => return result
        }
      }
    None => ()
  }
  raise @errors.TypeError(
    message="Cannot convert object to primitive value",
  )
}

///|
/// ToPrimitive(input, hint "default") - for + operator.
/// Same as "number" except passes "default" to @@toPrimitive.
pub fn to_primitive_default(obj_val : Value, data : ObjectData) -> Value raise Error {
  // Step 1: Check for Symbol.toPrimitive
  let to_prim_sym = get_toprimitive_symbol()
  match lookup_symbol_property_chain(obj_val, data, to_prim_sym.id) {
    Some(exotic_to_prim) => {
      if not(is_callable(exotic_to_prim)) {
        raise @errors.TypeError(
          message="Symbol.toPrimitive is not a function",
        )
      }
      // Call it with hint "default"
      let result = call_callable_direct(
        exotic_to_prim,
        obj_val,
        [String_("default")],
      )
      match result {
        Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
          raise @errors.TypeError(
            message="Cannot convert object to primitive value",
          )
        _ => return result
      }
    }
    None => ()
  }
  // Step 2: OrdinaryToPrimitive with hint "number" (default falls through to number behavior)
  to_primitive_number(obj_val, data)
}

///|
fn is_js_whitespace_code(ch : UInt16) -> Bool {
  ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D ||
  ch == 0x0B || ch == 0x0C ||
  ch == 0x00A0 || ch == 0xFEFF ||
  ch == 0x1680 ||
  (ch >= 0x2000 && ch <= 0x200A) ||
  ch == 0x2028 || ch == 0x2029 ||
  ch == 0x202F || ch == 0x205F || ch == 0x3000
}

///|
fn js_trim_whitespace(s : String) -> String {
  let len = s.length()
  let mut start = 0
  let mut end = len
  while start < end && is_js_whitespace_code(s[start]) {
    start = start + 1
  }
  while end > start && is_js_whitespace_code(s[end - 1]) {
    end = end - 1
  }
  if start == 0 && end == len {
    s
  } else {
    s.substring(start~, end~)
  }
}

///|
pub fn to_number(val : Value) -> Double raise Error {
  match val {
    Number(n) => n
    String_(s) => {
      // Trim whitespace per spec (including Unicode whitespace)
      let trimmed = js_trim_whitespace(s)
      if trimmed.length() == 0 {
        return 0.0
      }
      // Handle hex, binary, octal literals
      if trimmed.length() > 2 {
        let prefix = trimmed.view()[:2].to_string()
        if prefix == "0x" || prefix == "0X" {
          // Parse hex
          let hex_str = trimmed.view()[2:].to_string()
          if hex_str.length() == 0 {
            return 0.0 / 0.0
          }
          let mut result : Double = 0.0
          for ch in hex_str {
            let digit = if ch >= '0' && ch <= '9' {
              ch.to_int() - '0'.to_int()
            } else if ch >= 'a' && ch <= 'f' {
              ch.to_int() - 'a'.to_int() + 10
            } else if ch >= 'A' && ch <= 'F' {
              ch.to_int() - 'A'.to_int() + 10
            } else {
              return 0.0 / 0.0
            }
            result = result * 16.0 + digit.to_double()
          }
          return result
        }
        if prefix == "0b" || prefix == "0B" {
          // Parse binary
          let bin_str = trimmed.view()[2:].to_string()
          if bin_str.length() == 0 {
            return 0.0 / 0.0
          }
          let mut result : Double = 0.0
          for ch in bin_str {
            if ch == '0' {
              result = result * 2.0
            } else if ch == '1' {
              result = result * 2.0 + 1.0
            } else {
              return 0.0 / 0.0
            }
          }
          return result
        }
        if prefix == "0o" || prefix == "0O" {
          // Parse octal
          let oct_str = trimmed.view()[2:].to_string()
          if oct_str.length() == 0 {
            return 0.0 / 0.0
          }
          let mut result : Double = 0.0
          for ch in oct_str {
            if ch >= '0' && ch <= '7' {
              result = result * 8.0 + (ch.to_int() - '0'.to_int()).to_double()
            } else {
              return 0.0 / 0.0
            }
          }
          return result
        }
      }
      // Handle Infinity
      if trimmed == "Infinity" || trimmed == "+Infinity" {
        return 1.0 / 0.0
      }
      if trimmed == "-Infinity" {
        return -1.0 / 0.0
      }
      // Per spec: numeric separators (_) are only valid in source code literals,
      // not in Number() string-to-number conversion
      if trimmed.contains("_") {
        return 0.0 / 0.0
      }
      // Validate the string only contains valid Number() characters.
      // parse_double may accept non-spec things like "INFINITY", "inf", etc.
      let valid = trimmed.iter().fold(init=true, fn(acc, ch) {
        acc && (ch >= '0' && ch <= '9' || ch == '.' || ch == 'e' || ch == 'E' ||
                ch == '+' || ch == '-')
      })
      if not(valid) {
        return 0.0 / 0.0
      }
      @strconv.parse_double(trimmed) catch {
        _ => 0.0 / 0.0
      }
    }
    Bool(b) => if b { 1.0 } else { 0.0 }
    Null => 0.0
    Object(data) => {
      // Use ToPrimitive to convert object to a primitive, then ToNumber on the result
      let prim = to_primitive_number(Object(data), data)
      to_number(prim)
    }
    Array(arr_data) => {
      // Arrays: convert to string via join(","), then to number
      let s = arr_data.elements.map(fn(v) { v.to_string() }).join(",")
      if s.length() == 0 {
        0.0
      } else {
        @strconv.parse_double(s) catch {
          _ => 0.0 / 0.0
        }
      }
    }
    Undefined | Map(_) | Set(_) | Promise(_) | Proxy(_) => 0.0 / 0.0
    Symbol(_) =>
      raise @errors.TypeError(
        message="Cannot convert a Symbol value to a number",
      )
  }
}

///|
/// ToPrimitive(input, hint "string") - converts an object to a primitive value.
/// Follows the ECMAScript spec: check @@toPrimitive, then toString, then valueOf.
fn to_primitive_string(obj_val : Value, data : ObjectData) -> Value raise Error {
  // Step 1: Check for Symbol.toPrimitive
  let to_prim_sym = get_toprimitive_symbol()
  match lookup_symbol_property_chain(obj_val, data, to_prim_sym.id) {
    Some(exotic_to_prim) => {
      if not(is_callable(exotic_to_prim)) {
        raise @errors.TypeError(
          message="Symbol.toPrimitive is not a function",
        )
      }
      let result = call_callable_direct(
        exotic_to_prim,
        obj_val,
        [String_("string")],
      )
      match result {
        Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
          raise @errors.TypeError(
            message="Cannot convert object to primitive value",
          )
        _ => return result
      }
    }
    None => ()
  }
  // Step 2: OrdinaryToPrimitive with hint "string" - try toString first, then valueOf
  // Use interpreter for property lookup if available (handles synthetic props on functions etc.)
  let to_string_fn : Value? = match lookup_property_chain(data, "toString") {
    Some(f) => Some(f)
    None =>
      match current_interpreter.val {
        Some(interp) => {
          let v = interp.get_property(
            obj_val,
            "toString",
            @token.Loc::default(),
          ) catch { _ => Undefined }
          if is_callable(v) { Some(v) } else { None }
        }
        None => None
      }
  }
  match to_string_fn {
    Some(ts_fn) =>
      if is_callable(ts_fn) {
        let result = call_callable_direct(ts_fn, obj_val, [])
        match result {
          Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
            () // result is object, try valueOf next
          _ => return result
        }
      }
    None => ()
  }
  let value_of_fn : Value? = match lookup_property_chain(data, "valueOf") {
    Some(f) => Some(f)
    None =>
      match current_interpreter.val {
        Some(interp) => {
          let v = interp.get_property(
            obj_val,
            "valueOf",
            @token.Loc::default(),
          ) catch { _ => Undefined }
          if is_callable(v) { Some(v) } else { None }
        }
        None => None
      }
  }
  match value_of_fn {
    Some(vo_fn) =>
      if is_callable(vo_fn) {
        let result = call_callable_direct(vo_fn, obj_val, [])
        match result {
          Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
            raise @errors.TypeError(
              message="Cannot convert object to primitive value",
            )
          _ => return result
        }
      }
    None => ()
  }
  raise @errors.TypeError(
    message="Cannot convert object to primitive value",
  )
}

///|
/// ECMAScript ToString - converts a value to a string following the spec.
/// For objects, calls ToPrimitive(hint: "string") then converts result to string.
pub fn to_js_string(val : Value) -> String raise Error {
  match val {
    String_(s) => s
    Number(n) => {
      let i = n.to_int()
      if i.to_double() == n && not(n.is_inf()) && not(n.is_nan()) {
        i.to_string()
      } else {
        n.to_string()
      }
    }
    Bool(b) => b.to_string()
    Null => "null"
    Undefined => "undefined"
    Symbol(_) =>
      raise @errors.TypeError(
        message="Cannot convert a Symbol value to a string",
      )
    Object(data) => {
      let prim = to_primitive_string(Object(data), data)
      to_js_string(prim)
    }
    Array(arr_data) => {
      // Arrays: join elements with commas
      arr_data.elements.map(fn(v) { v.to_string() }).join(",")
    }
    Map(_) | Set(_) | Promise(_) | Proxy(_) => "[object Object]"
  }
}

///|
/// ECMAScript ToIndex: converts a value to a non-negative integer index.
/// Throws RangeError for negative values or values >= 2^53.
/// Returns 0 for undefined.
pub fn to_index(val : Value) -> Int raise {
  match val {
    Undefined => 0
    _ => {
      let n = to_number(val)
      if n.is_nan() || n == 0.0 {
        return 0
      }
      if n.is_inf() || n < 0.0 || n >= 9007199254740992.0 {
        raise @errors.RangeError(message="Invalid index")
      }
      n.to_int()
    }
  }
}

///|
pub fn to_int32(n : Double) -> Int {
  if n.is_nan() || n.is_inf() || n == 0.0 {
    return 0
  }
  // ECMAScript ToInt32: truncate toward zero, modulo 2^32, map to signed range
  let two32 : Double = 4294967296.0
  // Truncate toward zero
  let abs_n = n.abs()
  let sign : Double = if n < 0.0 { -1.0 } else { 1.0 }
  let truncated = abs_n.floor() * sign
  // Modulo 2^32 (always positive)
  let remainder = truncated % two32
  let pos_mod = if remainder < 0.0 { remainder + two32 } else { remainder }
  // Map to signed 32-bit range
  if pos_mod >= 2147483648.0 {
    (pos_mod - two32).to_int()
  } else {
    pos_mod.to_int()
  }
}

///|
pub fn type_of(val : Value) -> String {
  match val {
    Number(_) => "number"
    String_(_) => "string"
    Bool(_) => "boolean"
    Null => "object" // JS quirk
    Undefined => "undefined"
    Object(data) =>
      match data.callable {
        Some(_) => "function"
        None => "object"
      }
    Array(_) => "object"
    Symbol(_) => "symbol"
    Map(_) => "object"
    Set(_) => "object"
    Promise(_) => "object"
    Proxy(proxy_data) =>
      if proxy_data.is_callable {
        "function"
      } else {
        "object"
      }
  }
}

///|
/// Shared %IteratorPrototype% - lazily initialized (ES spec §27.1.2)
let iterator_proto_ref : Ref[Value?] = { val: None }

///|
/// Get or create the shared %IteratorPrototype%
/// Per ES spec, %IteratorPrototype% has [Symbol.iterator] that returns `this`
/// and its [[Prototype]] is %Object.prototype% (Null for now since we don't
/// thread Object.prototype here — iterators still function correctly).
pub fn get_iterator_proto() -> Value {
  match iterator_proto_ref.val {
    Some(proto) => proto
    None => {
      let iterator_sym = get_iterator_symbol()
      let proto_sym_props : Map[Int, Value] = {}
      proto_sym_props[iterator_sym.id] = make_method_func("[Symbol.iterator]", 0, fn(this_val, _args) { this_val })
      let proto : Value = Object({
        properties: {},
        symbol_properties: proto_sym_props,
        prototype: Null,
        callable: None,
        class_name: "Iterator",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
      iterator_proto_ref.val = Some(proto)
      proto
    }
  }
}

///|
/// Shared %ArrayIteratorPrototype% - lazily initialized
let array_iterator_proto_ref : Ref[Value?] = { val: None }

///|
/// Get or create the shared %ArrayIteratorPrototype%
pub fn get_array_iterator_proto() -> Value {
  match array_iterator_proto_ref.val {
    Some(proto) => proto
    None => {
      let iterator_sym = get_iterator_symbol()
      let tostringtag_sym = get_tostringtag_symbol()
      let proto_sym_props : Map[Int, Value] = {}
      proto_sym_props[tostringtag_sym.id] = String_("Array Iterator")
      let proto_props : Map[String, Value] = {}
      let proto_sym_descs : Map[Int, PropDescriptor] = {}
      proto_sym_descs[tostringtag_sym.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      proto_sym_props[iterator_sym.id] = make_method_func("[Symbol.iterator]", 0, fn(this_val, _args) { this_val })
      proto_props["next"] = make_method_func("next", 0, fn(_this_val, _args) raise {
            raise @errors.TypeError(
              message="Array Iterator.prototype.next requires that |this| be an Array Iterator",
            )
          })
      let proto_descs : Map[String, PropDescriptor] = {}
      proto_descs["next"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      let proto = Object({
        properties: proto_props,
        symbol_properties: proto_sym_props,
        prototype: get_iterator_proto(),
        callable: None,
        class_name: "Array Iterator",
        descriptors: proto_descs,
        symbol_descriptors: proto_sym_descs,
        extensible: true,
      })
      array_iterator_proto_ref.val = Some(proto)
      proto
    }
  }
}

///|
/// Create an array iterator object that iterates over array elements
pub fn make_array_iterator_value(arr : ArrayData) -> Value {
  let arr_iter_proto = get_array_iterator_proto()
  let index_ref : Ref[Int] = { val: 0 }

  // Create the next method
  let next_method = Object({
    properties: { "length": Number(0.0), "name": String_("next") },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("next", fn(_args) {
        let idx = index_ref.val
        if idx < arr.elements.length() {
          let value = arr.elements[idx]
          index_ref.val = idx + 1
          let result_props : Map[String, Value] = {}
          result_props["value"] = value
          result_props["done"] = Bool(false)
          Object({
            properties: result_props,
            symbol_properties: {},
            prototype: Null,
            callable: None,
            class_name: "Object",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
        } else {
          let result_props : Map[String, Value] = {}
          result_props["value"] = Undefined
          result_props["done"] = Bool(true)
          Object({
            properties: result_props,
            symbol_properties: {},
            prototype: Null,
            callable: None,
            class_name: "Object",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
        }
      }),
    ),
    class_name: "Function",
    descriptors: {
      "length": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
      "name": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
    },
    symbol_descriptors: {},
    extensible: true,
  })

  // Create the iterator object with next method
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method

  Object({
    properties: iter_props,
    symbol_properties: {},
    prototype: arr_iter_proto,
    callable: None,
    class_name: "Array Iterator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Shared %StringIteratorPrototype% - lazily initialized
let string_iterator_proto_ref : Ref[Value?] = { val: None }

///|
/// Get or create the shared %StringIteratorPrototype%
pub fn get_string_iterator_proto() -> Value {
  match string_iterator_proto_ref.val {
    Some(proto) => proto
    None => {
      let iterator_sym = get_iterator_symbol()
      let tostringtag_sym = get_tostringtag_symbol()
      let proto_sym_props : Map[Int, Value] = {}
      proto_sym_props[tostringtag_sym.id] = String_("String Iterator")
      let proto_props : Map[String, Value] = {}
      let proto_sym_descs : Map[Int, PropDescriptor] = {}
      proto_sym_descs[tostringtag_sym.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      proto_sym_props[iterator_sym.id] = make_method_func("[Symbol.iterator]", 0, fn(this_val, _args) { this_val })
      proto_props["next"] = make_method_func("next", 0, fn(_this_val, _args) raise {
            raise @errors.TypeError(
              message="String Iterator.prototype.next requires that |this| be a String Iterator",
            )
          })
      let str_proto_descs : Map[String, PropDescriptor] = {}
      str_proto_descs["next"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      let proto = Object({
        properties: proto_props,
        symbol_properties: proto_sym_props,
        prototype: get_iterator_proto(),
        callable: None,
        class_name: "String Iterator",
        descriptors: str_proto_descs,
        symbol_descriptors: proto_sym_descs,
        extensible: true,
      })
      string_iterator_proto_ref.val = Some(proto)
      proto
    }
  }
}

///|
/// Create a string iterator object that iterates over string characters
/// Handles Unicode surrogate pairs correctly per ES6 spec
pub fn make_string_iterator_value(s : String) -> Value {
  let str_iter_proto = get_string_iterator_proto()
  let chars = s.to_array()
  let index_ref : Ref[Int] = { val: 0 }
  let next_method = Object({
    properties: { "length": Number(0.0), "name": String_("next") },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("next", fn(_args) {
        let idx = index_ref.val
        if idx < chars.length() {
          let buf = StringBuilder::new()
          let c = chars[idx]
          let code = c.to_int()

          // Check if this is a high surrogate (0xD800-0xDBFF)
          // and the next char is a low surrogate (0xDC00-0xDFFF)
          if code >= 0xD800 && code <= 0xDBFF && idx + 1 < chars.length() {
            let next_code = chars[idx + 1].to_int()
            if next_code >= 0xDC00 && next_code <= 0xDFFF {
              // This is a surrogate pair - yield both together
              buf.write_char(c)
              buf.write_char(chars[idx + 1])
              index_ref.val = idx + 2
            } else {
              // High surrogate without valid low surrogate - yield as-is
              buf.write_char(c)
              index_ref.val = idx + 1
            }
          } else {
            // Regular character or lone surrogate
            buf.write_char(c)
            index_ref.val = idx + 1
          }
          let value = String_(buf.to_string())
          let result_props : Map[String, Value] = {}
          result_props["value"] = value
          result_props["done"] = Bool(false)
          Object({
            properties: result_props,
            symbol_properties: {},
            prototype: Null,
            callable: None,
            class_name: "Object",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
        } else {
          let result_props : Map[String, Value] = {}
          result_props["value"] = Undefined
          result_props["done"] = Bool(true)
          Object({
            properties: result_props,
            symbol_properties: {},
            prototype: Null,
            callable: None,
            class_name: "Object",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
        }
      }),
    ),
    class_name: "Function",
    descriptors: {
      "length": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
      "name": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
    },
    symbol_descriptors: {},
    extensible: true,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method
  Object({
    properties: iter_props,
    symbol_properties: {},
    prototype: str_iter_proto,
    callable: None,
    class_name: "String Iterator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///| Sort property keys per OrdinaryOwnPropertyKeys spec order:
/// 1. Integer indices in ascending numeric order
/// 2. Other string keys in insertion order
pub fn sort_property_keys(props : Map[String, Value]) -> Array[String] {
  let int_keys : Array[String] = []
  let str_keys : Array[String] = []
  props.each(fn(k, _v) {
    // Skip internal slots (e.g., [[BooleanData]], [[NumberData]], [[StringData]])
    if k.has_prefix("[[") {
      return
    }
    let idx = @strconv.parse_int(k) catch { _ => -1 }
    if idx >= 0 && idx.to_string() == k {
      int_keys.push(k)
    } else {
      str_keys.push(k)
    }
  })
  // Sort integer keys by numeric value
  int_keys.sort_by(fn(a, b) {
    let na = @strconv.parse_int(a) catch { _ => 0 }
    let nb = @strconv.parse_int(b) catch { _ => 0 }
    na - nb
  })
  let result : Array[String] = []
  for k in int_keys {
    result.push(k)
  }
  for k in str_keys {
    result.push(k)
  }
  result
}
