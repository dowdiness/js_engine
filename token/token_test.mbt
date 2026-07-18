///|
fn expect_int(actual : Int, expected : Int, label : String) -> Unit raise Error {
  guard actual == expected else {
    fail(
      label +
      ": expected " +
      expected.to_string() +
      ", got " +
      actual.to_string(),
    )
  }
}

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
fn expect_token_kind(
  actual : @token.TokenKind,
  expected : @token.TokenKind,
) -> Unit raise Error {
  guard actual == expected else {
    fail(
      "expected token kind " +
      expected.to_string() +
      ", got " +
      actual.to_string(),
    )
  }
}

///|
test "Loc default" {
  let loc = @token.Loc::default()
  expect_int(loc.line, 1, "line")
  expect_int(loc.col, 1, "col")
  expect_int(loc.offset, 0, "offset")
}

///|
test "Token creation via constructor" {
  let tok = @token.Token(
    @token.TokenKind::Number(42.0),
    @token.Loc::default(),
    "42",
  )
  expect_token_kind(tok.kind, @token.TokenKind::Number(42.0))
  expect_string(tok.raw, "42", "raw")
}

///|
test "Token EOF" {
  let tok = @token.Token::eof(@token.Loc::default())
  expect_token_kind(tok.kind, @token.TokenKind::EOF)
}
