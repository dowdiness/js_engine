///|
/// Check if a name is a strict-mode reserved word (ES5 §7.6.1.2).
/// These identifiers cannot be used as variable names, function names,
/// or parameter names in strict mode code.
fn is_strict_reserved_word(name : String) -> Bool {
  match name {
    "implements"
    | "interface"
    | "let"
    | "package"
    | "private"
    | "protected"
    | "public"
    | "static"
    | "yield" => true
    _ => false
  }
}

///|
/// Validate that a binding name is legal in strict mode.
/// Raises SyntaxError if name is "eval", "arguments", or a strict reserved word.
pub fn validate_strict_binding_name(name : String) -> Unit raise Error {
  guard name != "eval" && name != "arguments" else {
    raise @errors.SyntaxError(
      message="Unexpected eval or arguments in strict mode",
    )
  }
  guard !is_strict_reserved_word(name) else {
    raise @errors.SyntaxError(message="Unexpected strict mode reserved word")
  }
}

///|
pub fn validate_strict_identifier_reference(
  strict : Bool,
  name : String,
) -> Unit raise Error {
  guard !(strict && is_strict_reserved_word(name)) else {
    raise @errors.SyntaxError(message="Unexpected strict mode reserved word")
  }
}

///|
pub fn validate_strict_assignment_target_name(
  strict : Bool,
  name : String,
) -> Unit raise Error {
  validate_strict_identifier_reference(strict, name)
  guard !(strict && (name == "eval" || name == "arguments")) else {
    raise @errors.SyntaxError(
      message="Unexpected eval or arguments in strict mode",
    )
  }
}
