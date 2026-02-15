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
/// Get the well-known Symbol.hasInstance
pub fn get_hasinstance_symbol() -> SymbolData {
  match well_known_hasinstance_sym.val {
    Some(sym) => sym
    None => abort("Symbol.hasInstance not initialized")
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
/// Get the Symbol.toStringTag value by walking the prototype chain.
/// Checks symbol properties and evaluates getter descriptors if present.
pub fn get_tostringtag_value(data : ObjectData) -> String? {
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
                        let result = f(Object(data), []) catch { _ => return None }
                        match result {
                          String_(s) => return Some(s)
                          _ => return None
                        }
                      }
                      Some(NativeCallable(_, f)) => {
                        let result = f([Object(data)]) catch { _ => return None }
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
}

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
    prototype: Null,
    callable: None,
    class_name: "Object",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  let func_obj = Object({
    properties: { "prototype": proto },
    symbol_properties: {},
    prototype: Null,
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
    prototype: Null,
    callable: None,
    class_name: "Object",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  let func_obj = Object({
    properties: { "prototype": proto },
    symbol_properties: {},
    prototype: Null,
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
pub fn make_native_func(
  name : String,
  func : (Array[Value]) -> Value raise Error,
) -> Value {
  Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(NativeCallable(name, func)),
    class_name: "Function",
    descriptors: {},
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
  let props : Map[String, Value] = {}
  props["length"] = Number(length.to_double())
  Object({
    properties: props,
    symbol_properties: {},
    prototype: Null,
    callable: Some(NativeCallable(name, func)),
    class_name: "Function",
    descriptors: {},
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
pub fn to_number(val : Value) -> Double raise Error {
  match val {
    Number(n) => n
    String_(s) => {
      if s.length() == 0 {
        return 0.0
      }
      @strconv.parse_double(s) catch {
        _ => 0.0 / 0.0
      }
    }
    Bool(b) => if b { 1.0 } else { 0.0 }
    Null => 0.0
    Object(data) =>
      if data.class_name == "Date" {
        match data.properties.get("[[DateValue]]") {
          Some(Number(v)) => v
          _ => 0.0 / 0.0
        }
      } else if data.class_name == "Number" {
        match data.properties.get("[[NumberData]]") {
          Some(Number(v)) => v
          _ => 0.0 / 0.0
        }
      } else if data.class_name == "Boolean" {
        match data.properties.get("[[BooleanData]]") {
          Some(Bool(b)) => if b { 1.0 } else { 0.0 }
          _ => 0.0 / 0.0
        }
      } else if data.class_name == "String" {
        match data.properties.get("[[StringData]]") {
          Some(String_(s)) =>
            if s.length() == 0 {
              0.0
            } else {
              @strconv.parse_double(s) catch { _ => 0.0 / 0.0 }
            }
          _ => 0.0 / 0.0
        }
      } else {
        0.0 / 0.0
      }
    Undefined | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => 0.0 / 0.0
    Symbol(_) =>
      raise @errors.TypeError(
        message="Cannot convert a Symbol value to a number",
      )
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
    Proxy(_) => "object"
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
      proto_sym_props[iterator_sym.id] = Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("[Symbol.iterator]", fn(this_val, _args) { this_val }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
      proto_props["next"] = Object({
        properties: { "length": Number(0.0), "name": String_("next") },
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("next", fn(_this_val, _args) raise {
            raise @errors.TypeError(
              message="Array Iterator.prototype.next requires that |this| be an Array Iterator",
            )
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
      let proto = Object({
        properties: proto_props,
        symbol_properties: proto_sym_props,
        prototype: Null,
        callable: None,
        class_name: "Array Iterator",
        descriptors: {},
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
      proto_sym_props[iterator_sym.id] = Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("[Symbol.iterator]", fn(this_val, _args) { this_val }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
      proto_props["next"] = Object({
        properties: { "length": Number(0.0), "name": String_("next") },
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("next", fn(_this_val, _args) raise {
            raise @errors.TypeError(
              message="String Iterator.prototype.next requires that |this| be a String Iterator",
            )
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
      let proto = Object({
        properties: proto_props,
        symbol_properties: proto_sym_props,
        prototype: Null,
        callable: None,
        class_name: "String Iterator",
        descriptors: {},
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
