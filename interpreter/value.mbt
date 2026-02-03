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
  BoundFunc(Value, Value, Array[Value]) // (target, this_val, bound_args)
  FuncCallMethod(Value) // .call proxy: captures target function
  FuncApplyMethod(Value) // .apply proxy: captures target function
  MethodCallable(String, (Value, Array[Value]) -> Value raise Error) // this-aware native method
  InterpreterCallable(
    String,
    (Interpreter, Value, Array[Value]) -> Value raise Error
  ) // needs interpreter for callback invocation
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
  prototype : Value
  callable : Callable?
  class_name : String
  descriptors : Map[String, PropDescriptor]
  mut extensible : Bool
}

///|
pub(all) struct ArrayData {
  elements : Array[Value]
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
        prototype: Null,
        callable: None,
        class_name: "Object",
        descriptors: {},
        extensible: true,
      }),
    },
    prototype: Null,
    callable: Some(UserFunc(data)),
    class_name: "Function",
    descriptors: {},
    extensible: true,
  })
}

///|
pub fn make_func_ext(data : FuncDataExt) -> Value {
  Object({
    properties: {
      "prototype": Object({
        properties: {},
        prototype: Null,
        callable: None,
        class_name: "Object",
        descriptors: {},
        extensible: true,
      }),
    },
    prototype: Null,
    callable: Some(UserFuncExt(data)),
    class_name: "Function",
    descriptors: {},
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
    prototype: Null,
    callable: Some(NativeCallable(name, func)),
    class_name: "Function",
    descriptors: {},
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
        Some(FuncCallMethod(_)) =>
          logger.write_string("function call() { [native code] }")
        Some(FuncApplyMethod(_)) =>
          logger.write_string("function apply() { [native code] }")
        Some(MethodCallable(name, _)) =>
          logger.write_string("function \{name}() { [native code] }")
        Some(InterpreterCallable(name, _)) =>
          logger.write_string("function \{name}() { [native code] }")
        None => logger.write_string("[object \{data.class_name}]")
      }
    Array(data) =>
      logger.write_string(data.elements.map(fn(v) { v.to_string() }).join(","))
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
  }
}

///|
pub fn to_number(val : Value) -> Double {
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
    Undefined | Object(_) | Array(_) => 0.0 / 0.0
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
  }
}
