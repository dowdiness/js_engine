///|
test "validate_strict_binding_name: eval rejected" {
  let result = try {
    validate_strict_binding_name("eval")
    "ok"
  } catch {
    _ => "error"
  }
  inspect(result, content="error")
}

///|
test "validate_strict_binding_name: arguments rejected" {
  let result = try {
    validate_strict_binding_name("arguments")
    "ok"
  } catch {
    _ => "error"
  }
  inspect(result, content="error")
}

///|
test "validate_strict_binding_name: reserved word rejected" {
  let result = try {
    validate_strict_binding_name("yield")
    "ok"
  } catch {
    _ => "error"
  }
  inspect(result, content="error")
}

///|
test "validate_strict_binding_name: normal name accepted" {
  let result = try {
    validate_strict_binding_name("x")
    "ok"
  } catch {
    _ => "error"
  }
  inspect(result, content="ok")
}

///|
test "validate_strict_identifier_reference: reserved word rejected in strict" {
  let result = try {
    validate_strict_identifier_reference(true, "static")
    "ok"
  } catch {
    _ => "error"
  }
  inspect(result, content="error")
}

///|
test "validate_strict_identifier_reference: reserved word allowed in sloppy" {
  let result = try {
    validate_strict_identifier_reference(false, "static")
    "ok"
  } catch {
    _ => "error"
  }
  inspect(result, content="ok")
}

///|
test "validate_strict_assignment_target_name: eval rejected in strict" {
  let result = try {
    validate_strict_assignment_target_name(true, "eval")
    "ok"
  } catch {
    _ => "error"
  }
  inspect(result, content="error")
}

///|
test "validate_strict_assignment_target_name: eval allowed in sloppy" {
  let result = try {
    validate_strict_assignment_target_name(false, "eval")
    "ok"
  } catch {
    _ => "error"
  }
  inspect(result, content="ok")
}
