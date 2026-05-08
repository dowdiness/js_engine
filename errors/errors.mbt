///| JavaScript Engine Error Types

///|

///| Comprehensive error handling for lexer, parser, and interpreter.

///| Pattern inspired by: https://github.com/dowdiness/event-graph-walker

///| See: https://tc39.es/ecma262/#sec-native-error-types-used-in-this-standard

//==============================================================================
// Core JavaScript Error Type (unified enum-style suberror)
//==============================================================================

///|
/// JsError - Unified error type for all JavaScript errors
/// Each variant maps to a specific ECMAScript error type with named fields
pub(all) suberror JsError {
  /// TypeError - Operation could not be performed due to incompatible type
  /// https://tc39.es/ecma262/#sec-native-error-types-used-in-this-standard-typeerror
  TypeError(message~ : String)
  /// ReferenceError - Invalid reference detected (undefined variable, TDZ access)
  /// https://tc39.es/ecma262/#sec-native-error-types-used-in-this-standard-referenceerror
  ReferenceError(message~ : String)
  /// SyntaxError - Parsing or syntax-related error (lexer/parser/runtime)
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
} derive(Debug)

///|
pub impl Show for JsError with output(self, logger) {
  Debug::to_repr(self).output(logger)
}

//==============================================================================
// Error helper methods
//==============================================================================

///|
/// Get the error type name as a string
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

///|
/// Get the error message
pub fn JsError::get_message(self : JsError) -> String {
  match self {
    TypeError(message~)
    | ReferenceError(message~)
    | SyntaxError(message~)
    | RangeError(message~)
    | URIError(message~)
    | EvalError(message~)
    | InternalError(message~)
    | AggregateError(message~, errors=_) => message
  }
}

///|
/// Format as "ErrorType: message" (for stack traces)
pub fn JsError::format(self : JsError) -> String {
  self.name() + ": " + self.get_message()
}

///|
/// If `err` is a JsError variant, return its formatted string; otherwise `None`.
///
/// Lets consumers handle all JsError variants in one catch arm without
/// enumerating each constructor. The `Error` type is used because suberror
/// constructors are individually promoted to `Error` and MoonBit does not
/// support catching a suberror parent type as a single pattern.
pub fn format_if_js_error(err : Error) -> String? {
  match name_message_if_js_error(err) {
    Some((name, msg)) => Some(name + ": " + msg)
    None => None
  }
}

///|
/// If `err` is a JsError variant, return its (name, message) pair; otherwise `None`.
///
/// Lower-level companion to `format_if_js_error` for consumers that need
/// the name and message as separate strings (e.g. to pass to a function that
/// takes them individually).
pub fn name_message_if_js_error(err : Error) -> (String, String)? {
  match err {
    TypeError(message~) => Some(("TypeError", message))
    ReferenceError(message~) => Some(("ReferenceError", message))
    SyntaxError(message~) => Some(("SyntaxError", message))
    RangeError(message~) => Some(("RangeError", message))
    URIError(message~) => Some(("URIError", message))
    EvalError(message~) => Some(("EvalError", message))
    AggregateError(message~, errors=_) => Some(("AggregateError", message))
    InternalError(message~) => Some(("InternalError", message))
    _ => None
  }
}
