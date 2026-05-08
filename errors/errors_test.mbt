///| Tests for the errors package.

///|

///| These are black-box tests. They verify the public API (name, get_message,

///| format) without depending on internal representation details.

///|
test "name - TypeError" {
  let e = @errors.JsError::TypeError(message="x")
  inspect(e.name(), content="TypeError")
}

///|
test "name - ReferenceError" {
  let e = @errors.JsError::ReferenceError(message="x")
  inspect(e.name(), content="ReferenceError")
}

///|
test "name - SyntaxError" {
  let e = @errors.JsError::SyntaxError(message="x")
  inspect(e.name(), content="SyntaxError")
}

///|
test "name - RangeError" {
  let e = @errors.JsError::RangeError(message="x")
  inspect(e.name(), content="RangeError")
}

///|
test "name - URIError" {
  let e = @errors.JsError::URIError(message="x")
  inspect(e.name(), content="URIError")
}

///|
test "name - EvalError" {
  let e = @errors.JsError::EvalError(message="x")
  inspect(e.name(), content="EvalError")
}

///|
test "name - AggregateError" {
  let e = @errors.JsError::AggregateError(message="x", errors=[])
  inspect(e.name(), content="AggregateError")
}

///|
test "name - InternalError" {
  let e = @errors.JsError::InternalError(message="x")
  inspect(e.name(), content="InternalError")
}

///|
test "get_message returns message field" {
  let e = @errors.JsError::TypeError(message="not a function")
  inspect(e.get_message(), content="not a function")
}

///|
test "get_message - empty message" {
  let e = @errors.JsError::SyntaxError(message="")
  inspect(e.get_message(), content="")
}

///|
test "get_message - AggregateError returns message, not errors list" {
  let e = @errors.JsError::AggregateError(message="all failed", errors=[])
  inspect(e.get_message(), content="all failed")
}

///|
test "format produces ErrorType: message" {
  let e = @errors.JsError::TypeError(message="cannot read property")
  inspect(e.format(), content="TypeError: cannot read property")
}

///|
test "format - SyntaxError" {
  let e = @errors.JsError::SyntaxError(message="Unexpected token '}'")
  inspect(e.format(), content="SyntaxError: Unexpected token '}'")
}

///|
test "format - AggregateError" {
  let e = @errors.JsError::AggregateError(message="all promises rejected", errors=[])
  inspect(e.format(), content="AggregateError: all promises rejected")
}

///|
test "format_if_js_error - consistent with format() for all variants" {
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
    inspect(@errors.format_if_js_error(e) == Some(e.format()), content="true")
  }
}

///|
test "format_if_js_error - None for non-JsError" {
  let err : Error = Failure::Failure("oops")
  inspect(@errors.format_if_js_error(err) == (None : String?), content="true")
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
    inspect(result == Some((e.name(), e.get_message())), content="true")
  }
}

///|
test "name_message_if_js_error - None for non-JsError" {
  let err : Error = Failure::Failure("oops")
  inspect(
    @errors.name_message_if_js_error(err) == (None : (String, String)?),
    content="true",
  )
}

///|
test "format equals name + colon-space + get_message" {
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
    inspect(e.format() == expected, content="true")
  }
}
