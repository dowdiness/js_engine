///| JavaScript Engine Error Types
///|
///| Comprehensive error handling for lexer, parser, and interpreter.
///| Pattern inspired by: https://github.com/dowdiness/event-graph-walker
///| See: https://tc39.es/ecma262/#sec-native-error-types-used-in-this-standard

//==============================================================================
// Core JavaScript Error Type (unified enum-style suberror)
//==============================================================================

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
} derive(Show)

//==============================================================================
// Error helper methods
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
// Convenience functions for raising errors with source location
//==============================================================================

///| Raise a SyntaxError with source location
pub fn syntax_error(
  message : String,
  loc : @token.Loc
) -> Unit raise JsError {
  raise SyntaxError(message="\{message} at line \{loc.line}, col \{loc.col}")
}

///| Raise a SyntaxError with just a message (no location)
pub fn syntax_error_msg(message : String) -> Unit raise JsError {
  raise SyntaxError(message~)
}

///| Raise a TypeError with source location
pub fn type_error(message : String, loc : @token.Loc) -> Unit raise JsError {
  raise TypeError(message="\{message} at line \{loc.line}, col \{loc.col}")
}

///| Raise a TypeError with just a message (no location)
pub fn type_error_msg(message : String) -> Unit raise JsError {
  raise TypeError(message~)
}

///| Raise a ReferenceError with source location
pub fn reference_error(
  message : String,
  loc : @token.Loc
) -> Unit raise JsError {
  raise ReferenceError(message="\{message} at line \{loc.line}, col \{loc.col}")
}

///| Raise a ReferenceError with just a message (no location)
pub fn reference_error_msg(message : String) -> Unit raise JsError {
  raise ReferenceError(message~)
}

///| Raise a RangeError with just a message
pub fn range_error_msg(message : String) -> Unit raise JsError {
  raise RangeError(message~)
}

///| Raise a URIError with just a message
pub fn uri_error_msg(message : String) -> Unit raise JsError {
  raise URIError(message~)
}

///| Raise an InternalError with just a message
pub fn internal_error_msg(message : String) -> Unit raise JsError {
  raise InternalError(message~)
}

//==============================================================================
// Error classification helpers
//==============================================================================

///| Check if an error is a JavaScript catchable error (JsError variant)
pub fn is_js_error(err : Error) -> Bool {
  match err {
    TypeError(_)
    | ReferenceError(_)
    | SyntaxError(_)
    | RangeError(_)
    | URIError(_)
    | EvalError(_)
    | InternalError(_)
    | AggregateError(_) => true
    _ => false
  }
}
