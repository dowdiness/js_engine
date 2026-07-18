///| Tests for the errors package.

///|

///| These are black-box tests. They verify the public API (name, get_message,

///| to_string) without depending on internal representation details.

///|
fn expect_string(
  actual : String,
  expected : String,
  label : String,
) -> Unit raise Error {
  guard actual == expected else {
    fail(label + ": expected " + expected + ", got " + actual)
  }
}

///|
fn expect_true(actual : Bool, label : String) -> Unit raise Error {
  guard actual else { fail(label) }
}

///|
test "name - TypeError" {
  let e = @errors.JsError::TypeError(message="x")
  expect_string(e.name(), "TypeError", "name")
}

///|
test "name - ReferenceError" {
  let e = @errors.JsError::ReferenceError(message="x")
  expect_string(e.name(), "ReferenceError", "name")
}

///|
test "name - SyntaxError" {
  let e = @errors.JsError::SyntaxError(message="x")
  expect_string(e.name(), "SyntaxError", "name")
}

///|
test "name - RangeError" {
  let e = @errors.JsError::RangeError(message="x")
  expect_string(e.name(), "RangeError", "name")
}

///|
test "name - URIError" {
  let e = @errors.JsError::URIError(message="x")
  expect_string(e.name(), "URIError", "name")
}

///|
test "name - EvalError" {
  let e = @errors.JsError::EvalError(message="x")
  expect_string(e.name(), "EvalError", "name")
}

///|
test "name - AggregateError" {
  let e = @errors.JsError::AggregateError(message="x", errors=[])
  expect_string(e.name(), "AggregateError", "name")
}

///|
test "name - InternalError" {
  let e = @errors.JsError::InternalError(message="x")
  expect_string(e.name(), "InternalError", "name")
}

///|
test "get_message returns message field" {
  let e = @errors.JsError::TypeError(message="not a function")
  expect_string(e.get_message(), "not a function", "message")
}

///|
test "get_message - empty message" {
  let e = @errors.JsError::SyntaxError(message="")
  expect_string(e.get_message(), "", "message")
}

///|
test "get_message - AggregateError returns message, not errors list" {
  let e = @errors.JsError::AggregateError(message="all failed", errors=[])
  expect_string(e.get_message(), "all failed", "message")
}

///|
test "to_string produces ErrorType: message" {
  let e = @errors.JsError::TypeError(message="cannot read property")
  expect_string(e.to_string(), "TypeError: cannot read property", "to_string")
}

///|
test "to_string - SyntaxError" {
  let e = @errors.JsError::SyntaxError(message="Unexpected token '}'")
  expect_string(e.to_string(), "SyntaxError: Unexpected token '}'", "to_string")
}

///|
test "to_string - AggregateError" {
  let e = @errors.JsError::AggregateError(message="all promises rejected", errors=[])
  expect_string(e.to_string(), "AggregateError: all promises rejected", "to_string")
}

///|
test "format_if_js_error - consistent with to_string() for all variants" {
  let cases : Array[@errors.JsError] = [
    TypeError(message="a"),
    ReferenceError(message="b"),
    SyntaxError(message="c"),
    RangeError(message="d"),
    URIError(message="e"),
    EvalError(message="f"),
    AggregateError(message="g", errors=[]),
    InternalError(message="h"),
  ]
  for e in cases {
    expect_true(
      @errors.format_if_js_error(e) == Some(e.to_string()),
      "format_if_js_error mismatch for " + e.name(),
    )
  }
}

///|
test "format_if_js_error - None for non-JsError" {
  let err : Error = Failure::Failure("oops")
  expect_true(
    @errors.format_if_js_error(err) == (None : String?),
    "format_if_js_error should return None for non-JsError",
  )
}

///|
test "name_message_if_js_error - consistent with name() and get_message() for all variants" {
  let cases : Array[@errors.JsError] = [
    TypeError(message="a"),
    ReferenceError(message="b"),
    SyntaxError(message="c"),
    RangeError(message="d"),
    URIError(message="e"),
    EvalError(message="f"),
    AggregateError(message="g", errors=[]),
    InternalError(message="h"),
  ]
  for e in cases {
    let result = @errors.name_message_if_js_error(e)
    expect_true(
      result == Some((e.name(), e.get_message())),
      "name_message_if_js_error mismatch for " + e.name(),
    )
  }
}

///|
test "name_message_if_js_error - None for non-JsError" {
  let err : Error = Failure::Failure("oops")
  expect_true(
    @errors.name_message_if_js_error(err) == (None : (String, String)?),
    "name_message_if_js_error should return None for non-JsError",
  )
}

///|
test "to_string equals name + colon-space + get_message" {
  let cases : Array[@errors.JsError] = [
    TypeError(message="a"),
    ReferenceError(message="b"),
    SyntaxError(message="c"),
    RangeError(message="d"),
    URIError(message="e"),
    EvalError(message="f"),
    AggregateError(message="g", errors=[]),
    InternalError(message="h"),
  ]
  for e in cases {
    let expected = e.name() + ": " + e.get_message()
    expect_true(e.to_string() == expected, "to_string mismatch for " + e.name())
  }
}
