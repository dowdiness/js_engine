///|
test "Loc default" {
  let loc = @token.Loc::default()
  inspect(loc.line, content="1")
  inspect(loc.col, content="1")
  inspect(loc.offset, content="0")
}

///|
test "Token creation" {
  let tok = @token.Token::new(
    @token.TokenKind::Number(42.0),
    @token.Loc::default(),
    "42",
  )
  inspect(tok.kind, content="Number(42)")
  inspect(tok.raw, content="42")
}

///|
test "Token EOF" {
  let tok = @token.Token::eof(@token.Loc::default())
  inspect(tok.kind, content="EOF")
}
