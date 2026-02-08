///| Interpreter-specific error handling helpers

///|

///| Re-exports JsError from shared errors package and provides

///| Value conversion helpers for JavaScript try-catch handling.

///|
/// Create a JavaScript Error object Value with proper prototype chain
fn make_error_value_with_env(
  name : String,
  msg : String,
  env : Environment?,
) -> Value {
  let err_props : Map[String, Value] = {}
  err_props["message"] = String_(msg)
  err_props["name"] = String_(name)
  err_props["stack"] = String_(name + ": " + msg)
  // Try to look up the proper prototype from the environment
  let proto : Value = match env {
    Some(e) => {
      let ctor : Value = e.get(name) catch { _ => Null }
      match ctor {
        Object(ctor_data) =>
          match ctor_data.properties.get("prototype") {
            Some(p) => p
            None => Null
          }
        _ => Null
      }
    }
    None => Null
  }
  Object({
    properties: err_props,
    symbol_properties: {},
    prototype: proto,
    callable: None,
    class_name: name,
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Create an AggregateError with the errors array property
fn make_aggregate_error_value(
  msg : String,
  errors : Array[Error],
  env : Environment?,
) -> Value {
  let err_props : Map[String, Value] = {}
  err_props["message"] = String_(msg)
  err_props["name"] = String_("AggregateError")
  err_props["stack"] = String_("AggregateError: " + msg)
  // Convert errors array to JavaScript array
  let js_errors : Array[Value] = errors.map(fn(e) {
    js_error_to_value_with_env(e, env)
  })
  err_props["errors"] = Array({ elements: js_errors })
  // Try to look up the proper prototype from the environment
  let proto : Value = match env {
    Some(e) => {
      let ctor : Value = e.get("AggregateError") catch { _ => Null }
      match ctor {
        Object(ctor_data) =>
          match ctor_data.properties.get("prototype") {
            Some(p) => p
            None => Null
          }
        _ => Null
      }
    }
    None => Null
  }
  Object({
    properties: err_props,
    symbol_properties: {},
    prototype: proto,
    callable: None,
    class_name: "AggregateError",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Convert any catchable error to a JavaScript Error object Value
pub fn js_error_to_value(err : Error) -> Value {
  js_error_to_value_with_env(err, None)
}

///|
/// Convert any catchable error to a JavaScript Error object Value with proper prototype
pub fn js_error_to_value_with_env(err : Error, env : Environment?) -> Value {
  match err {
    @errors.TypeError(message~) =>
      make_error_value_with_env("TypeError", message, env)
    @errors.ReferenceError(message~) =>
      make_error_value_with_env("ReferenceError", message, env)
    @errors.SyntaxError(message~) =>
      make_error_value_with_env("SyntaxError", message, env)
    @errors.RangeError(message~) =>
      make_error_value_with_env("RangeError", message, env)
    @errors.URIError(message~) =>
      make_error_value_with_env("URIError", message, env)
    @errors.EvalError(message~) =>
      make_error_value_with_env("EvalError", message, env)
    @errors.InternalError(message~) =>
      make_error_value_with_env("InternalError", message, env)
    @errors.AggregateError(message~, errors~) =>
      make_aggregate_error_value(message, errors, env)
    JsException(val) => val // JavaScript throw statement value
    _ => make_error_value_with_env("Error", err.to_string(), env)
  }
}

///|
/// Convert a catchable error to the JS throw value used by this interpreter.
/// Runtime engine errors are surfaced as strings like "TypeError: ...".
pub fn js_error_to_throw_value(err : Error) -> Value {
  match err {
    @errors.TypeError(message~) => String_("TypeError: " + message)
    @errors.ReferenceError(message~) => String_("ReferenceError: " + message)
    @errors.SyntaxError(message~) => String_("SyntaxError: " + message)
    @errors.RangeError(message~) => String_("RangeError: " + message)
    @errors.URIError(message~) => String_("URIError: " + message)
    @errors.EvalError(message~) => String_("EvalError: " + message)
    @errors.InternalError(message~) => String_("InternalError: " + message)
    @errors.AggregateError(message~, errors~) => {
      let error_texts = errors.map(fn(e) {
        js_error_to_throw_value(e).to_string()
      })
      let errors_str = error_texts.join(", ")
      String_("AggregateError: " + message + " (errors: " + errors_str + ")")
    }
    JsException(val) => val
    _ => String_("Error: " + err.to_string())
  }
}

///|
/// Check if an error is a JavaScript catchable error
pub fn is_js_catchable_error(err : Error) -> Bool {
  match err {
    @errors.TypeError(_)
    | @errors.ReferenceError(_)
    | @errors.SyntaxError(_)
    | @errors.RangeError(_)
    | @errors.URIError(_)
    | @errors.EvalError(_)
    | @errors.InternalError(_)
    | @errors.AggregateError(_)
    | JsException(_) => true
    _ => false
  }
}
