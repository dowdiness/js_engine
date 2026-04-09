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
          // InterpreterCallable is a constructor if it has a prototype property
          // (builtin constructors like Map, Set, Promise have prototype)
          data.properties.contains("prototype")
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
                      Some(NativeCallable(_, f))
                      | Some(NonConstructableCallable(_, f)) => {
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
pub impl Show for Value with output(self, logger) {
  match self {
    Number(n) => {
      // Format integers without decimal point
      let i = n.to_int()
      if i.to_double() == n && !n.is_inf() && !n.is_nan() {
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


