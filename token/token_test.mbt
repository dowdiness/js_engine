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
test "Token creation via Token::new (backward compat)" {
  let tok = @token.Token::new(
    @token.TokenKind::Number(42.0),
    @token.Loc::default(),
    "42",
  )
  expect_token_kind(tok.kind, @token.TokenKind::Number(42.0))
  expect_string(tok.raw, "42", "raw")
}

///|
test "Token EOF" {
  let loc : @token.Loc = { line: 1, col: 2, offset: 1 }
  let tok = @token.Token::eof(loc)
  expect_token_kind(tok.kind, @token.TokenKind::EOF)
  match tok.source_span("x") {
    None => fail("expected EOF to have a zero-width source span")
    Some(span) => {
      let start = span.start()
      let end = span.end()
      json_inspect(
        [start.line, start.col, start.offset, end.line, end.col, end.offset],
        content=[1, 2, 1, 1, 2, 1],
      )
    }
  }
}

///|
test "Token source span follows JavaScript source coordinates" {
  let source = "\"a\r\n𝒜\""
  let tok = @token.Token(
    @token.TokenKind::String_("a\r\n𝒜"),
    @token.Loc::default(),
    source,
    end_offset=source.length(),
  )
  match tok.source_span(source) {
    None => fail("expected a valid source span")
    Some(span) => {
      let start = span.start()
      let end = span.end()
      json_inspect(
        [start.line, start.col, start.offset, end.line, end.col, end.offset],
        content=[1, 1, 0, 2, 3, 7],
      )
    }
  }
}

///|
test "Token source span rejects an invalid offset range" {
  let source = "x"
  let tok = @token.Token(
    @token.TokenKind::Ident("x"),
    @token.Loc::default(),
    source,
    end_offset=source.length() + 1,
  )
  match tok.source_span(source) {
    None => ()
    Some(_) => fail("expected an invalid source span")
  }
  let split_surrogate = @token.Token(
    @token.TokenKind::Ident(""),
    { line: 1, col: 1, offset: 1 },
    "",
    end_offset=2,
  )
  match split_surrogate.source_span("𝒜") {
    None => ()
    Some(_) => fail("expected a split surrogate range to be invalid")
  }
}
