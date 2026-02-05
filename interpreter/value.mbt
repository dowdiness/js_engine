///|
pub(all) struct FuncData {
  name : String?
  params : Array[String]
  body : Array[@ast.Stmt]
  closure : Environment
}

///|
pub(all) struct FuncDataExt {
  name : String?
  params : Array[@ast.Param]
  rest_param : String?
  body : Array[@ast.Stmt]
  closure : Environment
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
    Value, // prototype object reference for super
  )
}

///|
pub(all) struct PropDescriptor {
  mut writable : Bool
  mut enumerable : Bool
  mut configurable : Bool
}

///|
pub(all) struct ObjectData {
  properties : Map[String, Value]
  symbol_properties : Map[Int, Value] // Symbol-keyed properties (key is symbol ID)
  prototype : Value
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
}

///|
pub suberror JsException {
  JsException(Value)
}

///|
pub fn make_func(data : FuncData) -> Value {
  Object({
    properties: {
      "prototype": Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: None,
        class_name: "Object",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      }),
    },
    symbol_properties: {},
    prototype: Null,
    callable: Some(UserFunc(data)),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
pub fn make_func_ext(data : FuncDataExt) -> Value {
  Object({
    properties: {
      "prototype": Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: None,
        class_name: "Object",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      }),
    },
    symbol_properties: {},
    prototype: Null,
    callable: Some(UserFuncExt(data)),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
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
        None => logger.write_string("[object \{data.class_name}]")
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
    Undefined | Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) => 0.0 / 0.0
    Symbol(_) =>
      raise @errors.TypeError(message="Cannot convert a Symbol value to a number")
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
  }
}

///|
/// Create an array iterator object that iterates over array elements
pub fn make_array_iterator_value(arr : ArrayData) -> Value {
  let iterator_sym = get_iterator_symbol()
  let index_ref : Ref[Int] = { val: 0 }

  // Create the next method
  let next_method = Object({
    properties: {},
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
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Create the iterator object with next method
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method

  // Create symbol properties map with Symbol.iterator
  let iter_symbol_props : Map[Int, Value] = {}

  let iter_obj = Object({
    properties: iter_props,
    symbol_properties: iter_symbol_props,
    prototype: Null,
    callable: None,
    class_name: "Array Iterator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Add [Symbol.iterator] that returns the iterator itself
  match iter_obj {
    Object(data) => data.symbol_properties[iterator_sym.id] = Object({
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
    _ => ()
  }

  iter_obj
}

///|
/// Create a string iterator object that iterates over string characters
/// Handles Unicode surrogate pairs correctly per ES6 spec
pub fn make_string_iterator_value(s : String) -> Value {
  let iterator_sym = get_iterator_symbol()
  let chars = s.to_array()
  let index_ref : Ref[Int] = { val: 0 }

  let next_method = Object({
    properties: {},
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
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method

  let iter_obj = Object({
    properties: iter_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "String Iterator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Add [Symbol.iterator] that returns the iterator itself
  match iter_obj {
    Object(data) => data.symbol_properties[iterator_sym.id] = Object({
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
    _ => ()
  }

  iter_obj
}
