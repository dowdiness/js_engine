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
    | InternalError(message~) => message
    AggregateError(message~, errors=_) => message
  }
}

///|
/// Format as "ErrorType: message" (for stack traces)
pub fn JsError::format(self : JsError) -> String {
  self.name() + ": " + self.get_message()
}

