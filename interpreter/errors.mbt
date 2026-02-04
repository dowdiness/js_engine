///| ECMAScript Specification Error Types
///|
///| These error types map directly to JavaScript's built-in error types
///| as specified in ECMA-262.
///|
///| Pattern inspired by: https://github.com/dowdiness/event-graph-walker
///| See: https://tc39.es/ecma262/#sec-native-error-types-used-in-this-standard

//==============================================================================
// Core JavaScript Error Type (unified enum-style suberror)
//==============================================================================

/// JsError - Unified error type for all JavaScript runtime errors
/// Each variant maps to a specific ECMAScript error type with named fields
pub(all) suberror JsError {
  /// TypeError - Operation could not be performed due to incompatible type
  /// https://tc39.es/ecma262/#sec-native-error-types-used-in-this-standard-typeerror
  TypeError(message~ : String)

  /// ReferenceError - Invalid reference detected (undefined variable, TDZ access)
  /// https://tc39.es/ecma262/#sec-native-error-types-used-in-this-standard-referenceerror
  ReferenceError(message~ : String)

  /// SyntaxError - Parsing or syntax-related error
  /// https://tc39.es/ecma262/#sec-native-error-types-used-in-this-standard-syntaxerror
  SyntaxError(message~ : String)

  /// RangeError - Value not in allowable range
  /// https://tc39.es/ecma262/#sec-native-error-types-used-in-this-standard-rangeerror
  RangeError(message~ : String)

  /// URIError - URI handling function used incorrectly
  /// https://tc39.es/ecma262/#sec-native-error-types-used-in-this-standard-urierror
  URIError(message~ : String)

  /// EvalError - Error regarding eval() function (legacy, rarely used)
  /// https://tc39.es/ecma262/#sec-native-error-types-used-in-this-standard-evalerror
  EvalError(message~ : String)

  /// AggregateError - Multiple errors wrapped in a single error
  /// https://tc39.es/ecma262/#sec-aggregate-error-objects
  AggregateError(message~ : String, errors~ : Array[Error])

  /// InternalError - Engine internal error (non-standard but useful for debugging)
  InternalError(message~ : String)
} derive(Show)

//==============================================================================
// Error helper methods (following event-graph-walker pattern)
//==============================================================================

///| Get the error type name as a string
pub fn JsError::name(self : JsError) -> String {
  match self {
    TypeError(_) => "TypeError"
    ReferenceError(_) => "ReferenceError"
    SyntaxError(_) => "SyntaxError"
    RangeError(_) => "RangeError"
    URIError(_) => "URIError"
    EvalError(_) => "EvalError"
    AggregateError(_) => "AggregateError"
    InternalError(_) => "InternalError"
  }
}

///| Get the error message
pub fn JsError::get_message(self : JsError) -> String {
  match self {
    TypeError(message~)
    | ReferenceError(message~)
    | SyntaxError(message~)
    | RangeError(message~)
    | URIError(message~)
    | EvalError(message~)
    | InternalError(message~) => message
    AggregateError(message~, errors=_) => message
  }
}

///| Format as "ErrorType: message" (for stack traces)
pub fn JsError::format(self : JsError) -> String {
  self.name() + ": " + self.get_message()
}

///| Get debug representation
pub fn JsError::debug(self : JsError) -> String {
  match self {
    TypeError(message~) => "JsError::TypeError { message: \"\{message}\" }"
    ReferenceError(message~) =>
      "JsError::ReferenceError { message: \"\{message}\" }"
    SyntaxError(message~) => "JsError::SyntaxError { message: \"\{message}\" }"
    RangeError(message~) => "JsError::RangeError { message: \"\{message}\" }"
    URIError(message~) => "JsError::URIError { message: \"\{message}\" }"
    EvalError(message~) => "JsError::EvalError { message: \"\{message}\" }"
    AggregateError(message~, errors~) =>
      "JsError::AggregateError { message: \"\{message}\", errors: [\{errors.length()}] }"
    InternalError(message~) =>
      "JsError::InternalError { message: \"\{message}\" }"
  }
}

//==============================================================================
// Helper functions to create error objects from suberrors
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
    ReferenceError(message~) => make_error_value("ReferenceError", message)
    SyntaxError(message~) => make_error_value("SyntaxError", message)
    RangeError(message~) => make_error_value("RangeError", message)
    URIError(message~) => make_error_value("URIError", message)
    EvalError(message~) => make_error_value("EvalError", message)
    InternalError(message~) => make_error_value("InternalError", message)
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
