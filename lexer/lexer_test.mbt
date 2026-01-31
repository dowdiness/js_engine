///|
fn tok_kinds(source : String) -> Array[@token.TokenKind] raise Error {
  let tokens = @lexer.tokenize(source)
  tokens.map(fn(t) { t.kind })
}

///|
test "lex arithmetic expression" {
  let kinds = tok_kinds("1 + 2 * 3")
  inspect(kinds, content="[Number(1), Plus, Number(2), Star, Number(3), EOF]")
}

///|
test "lex keywords" {
  let kinds = tok_kinds("let x = 10")
  inspect(kinds, content="[Let, Ident(\"x\"), Assign, Number(10), EOF]")
}

///|
test "lex string" {
  let kinds = tok_kinds("\"hello world\"")
  inspect(kinds, content="[String_(\"hello world\"), EOF]")
}

///|
test "lex single-quoted string" {
  let kinds = tok_kinds("'hi'")
  inspect(kinds, content="[String_(\"hi\"), EOF]")
}

///|
test "lex string with escape" {
  let kinds = tok_kinds("\"a\\nb\"")
  inspect(kinds, content="[String_(\"a\\nb\"), EOF]")
}

///|
test "lex comparison operators" {
  let kinds = tok_kinds("=== !== == != <= >=")
  inspect(kinds, content="[EqEqEq, BangEqEq, EqEq, BangEq, LtEq, GtEq, EOF]")
}

///|
test "lex logical operators" {
  let kinds = tok_kinds("&& ||")
  inspect(kinds, content="[And, Or, EOF]")
}

///|
test "lex single-line comment" {
  let kinds = tok_kinds("1 // comment\n2")
  inspect(kinds, content="[Number(1), Number(2), EOF]")
}

///|
test "lex multi-line comment" {
  let kinds = tok_kinds("1 /* comment */ 2")
  inspect(kinds, content="[Number(1), Number(2), EOF]")
}

///|
test "lex function" {
  let kinds = tok_kinds("function foo(x) { return x; }")
  inspect(
    kinds,
    content="[Function, Ident(\"foo\"), LParen, Ident(\"x\"), RParen, LBrace, Return, Ident(\"x\"), Semicolon, RBrace, EOF]",
  )
}

///|
test "lex decimal number" {
  let kinds = tok_kinds("3.14")
  inspect(kinds, content="[Number(3.14), EOF]")
}

///|
test "lex boolean and null" {
  let kinds = tok_kinds("true false null undefined")
  inspect(kinds, content="[True, False, Null, Undefined, EOF]")
}

///|
test "lex dot and member" {
  let kinds = tok_kinds("console.log")
  inspect(kinds, content="[Ident(\"console\"), Dot, Ident(\"log\"), EOF]")
}

///|
test "lex ternary" {
  let kinds = tok_kinds("x ? 1 : 2")
  inspect(
    kinds,
    content="[Ident(\"x\"), Question, Number(1), Colon, Number(2), EOF]",
  )
}

///|
test "lex typeof" {
  let kinds = tok_kinds("typeof x")
  inspect(kinds, content="[Typeof, Ident(\"x\"), EOF]")
}
