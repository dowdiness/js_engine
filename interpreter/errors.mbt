///| Interpreter-specific error handling helpers
///|
///| Re-exports JsError from shared errors package and provides
///| Value conversion helpers for JavaScript try-catch handling.

///|
using @errors {
  JsError,
  TypeError,
  ReferenceError,
  SyntaxError,
  RangeError,
  URIError,
  EvalError,
  InternalError,
  AggregateError,
}

//==============================================================================
// Helper functions to create JavaScript Error object Values
//==============================================================================

///| Create a JavaScript Error object Value with the given name and message
fn make_error_value(name : String, msg : String) -> Value {
  let err_props : Map[String, Value] = {}
  err_props["message"] = String_(msg)
  err_props["name"] = String_(name)
  err_props["stack"] = String_(name + ": " + msg)
  Object({
    properties: err_props,
    symbol_properties: {},
    prototype: Null, // Will be set properly when builtins are initialized
    callable: None,
    class_name: name,
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///| Convert a JsError to a JavaScript Error object Value
pub fn JsError::to_value(self : JsError) -> Value {
  make_error_value(self.name(), self.get_message())
}

///| Convert any catchable error to a JavaScript Error object Value
pub fn js_error_to_value(err : Error) -> Value {
  match err {
    TypeError(message~) => make_error_value("TypeError", message)
    ReferenceError(message~) =>
      make_error_value("ReferenceError", message)
    SyntaxError(message~) => make_error_value("SyntaxError", message)
    RangeError(message~) => make_error_value("RangeError", message)
    URIError(message~) => make_error_value("URIError", message)
    EvalError(message~) => make_error_value("EvalError", message)
    InternalError(message~) =>
      make_error_value("InternalError", message)
    AggregateError(message~, errors=_) =>
      make_error_value("AggregateError", message)
    JsException(val) => val // JavaScript throw statement value
    _ => make_error_value("Error", err.to_string())
  }
}

///| Check if an error is a JavaScript catchable error
pub fn is_js_catchable_error(err : Error) -> Bool {
  match err {
    TypeError(_)
    | ReferenceError(_)
    | SyntaxError(_)
    | RangeError(_)
    | URIError(_)
    | EvalError(_)
    | InternalError(_)
    | AggregateError(_)
    | JsException(_) => true
    _ => false
  }
}
