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
  ClassConstructor(ClassConstructorData)
}

///|
/// Named fields for a class constructor callable.
/// Replaces the former anonymous 6-tuple so call sites are self-documenting
/// and future fields (e.g. instance fields, private names) can be added
/// without positional reasoning.

///|
/// A single instance field initializer, captured at class definition time.
pub(all) struct ClassFieldInit {
  key : Value // already-evaluated key (String_ for string keys, Symbol for symbol keys)
  initializer : @ast.Expr? // None if no `= expr`; evaluated with `this` = new instance
  closure : Environment // lexical closure for evaluating the initializer
}

///|
pub(all) struct ClassConstructorData {
  name : String // class name
  proto : Value // prototype object given to new instances
  super_ctor : Value? // super constructor when class uses `extends`
  ctor_fn : (Array[String], Array[@ast.Stmt])? // constructor params + body; None = no explicit ctor
  closure : Environment // lexical environment where the class was defined
  super_proto : Value // super class's prototype (bound as [[SuperPrototype]])
  instance_fields : Array[ClassFieldInit] // instance field initializers, run before ctor body
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
        Some(ClassConstructor({ name, .. })) =>
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
