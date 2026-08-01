// See: https://tc39.es/ecma262/#sec-native-error-types-used-in-this-standard

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
pub impl Show for JsError with fn output(self, logger) {
  logger.write_string(self.name())
  logger.write_string(": ")
  logger.write_string(self.get_message())
}

// Canonical single source of truth for (name, message) pair.
// name() and get_message() delegate here; name_message_if_js_error cannot
// reuse this because it takes Error (not JsError) and MoonBit suberror
// variants cannot be pattern-matched as a group from the Error base type.

///|
fn JsError::parts(self : JsError) -> (String, String) noraise {
  match self {
    TypeError(message~) => ("TypeError", message)
    ReferenceError(message~) => ("ReferenceError", message)
    SyntaxError(message~) => ("SyntaxError", message)
    RangeError(message~) => ("RangeError", message)
    URIError(message~) => ("URIError", message)
    EvalError(message~) => ("EvalError", message)
    AggregateError(message~, errors=_) => ("AggregateError", message)
    InternalError(message~) => ("InternalError", message)
  }
}

///|
pub fn JsError::name(self : JsError) -> String noraise {
  self.parts().0
}

///|
pub fn JsError::get_message(self : JsError) -> String noraise {
  self.parts().1
}

///|
/// Format as "ErrorType: message" (for stack traces). Equivalent to to_string().
pub fn JsError::format(self : JsError) -> String noraise {
  self.to_string()
}

///|
/// If `err` is a JsError variant, return its formatted string; otherwise `None`.
///
/// Lets consumers handle all JsError variants in one catch arm without
/// enumerating each constructor. The `Error` type is used because suberror
/// constructors are individually promoted to `Error` and MoonBit does not
/// support catching a suberror parent type as a single pattern.
pub fn format_if_js_error(err : Error) -> String? noraise {
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
pub fn name_message_if_js_error(err : Error) -> (String, String)? noraise {
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
