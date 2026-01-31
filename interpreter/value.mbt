///|
pub(all) struct FuncData {
  name : String?
  params : Array[String]
  body : Array[@ast.Stmt]
  closure : Environment
}

///|
pub(all) enum Value {
  Number(Double)
  String_(String)
  Bool(Bool)
  Null
  Undefined
  Function(FuncData)
  NativeFunc(String, (Array[Value]) -> Value)
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
    Function(data) =>
      match data.name {
        Some(n) => logger.write_string("function \{n}() { [code] }")
        None => logger.write_string("function() { [code] }")
      }
    NativeFunc(name, _) =>
      logger.write_string("function \{name}() { [native code] }")
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
    Function(_) => true
    NativeFunc(_, _) => true
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
    Function(_) => "function"
    NativeFunc(_, _) => "function"
  }
}
