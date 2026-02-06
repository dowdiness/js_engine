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

///|
test "lex new keywords" {
  let kinds = tok_kinds("throw try catch finally")
  inspect(kinds, content="[Throw, Try, Catch, Finally, EOF]")
}

///|
test "lex new this switch" {
  let kinds = tok_kinds("new this switch case default")
  inspect(kinds, content="[New, This, Switch, Case, Default, EOF]")
}

///|
test "lex void delete do in instanceof" {
  let kinds = tok_kinds("void delete do in instanceof")
  inspect(kinds, content="[Void, Delete, Do, In, Instanceof, EOF]")
}

///|
test "lex increment decrement" {
  let kinds = tok_kinds("x++ y--")
  inspect(
    kinds,
    content="[Ident(\"x\"), PlusPlus, Ident(\"y\"), MinusMinus, EOF]",
  )
}

///|
test "lex compound assignment" {
  let kinds = tok_kinds("+= -= *= /= %=")
  inspect(
    kinds,
    content="[PlusAssign, MinusAssign, StarAssign, SlashAssign, PercentAssign, EOF]",
  )
}

///|
test "lex bitwise operators" {
  let kinds = tok_kinds("& | ^ ~")
  inspect(kinds, content="[BitAnd, BitOr, BitXor, Tilde, EOF]")
}

///|
test "lex shift operators" {
  let kinds = tok_kinds("<< >> >>>")
  inspect(kinds, content="[LShift, RShift, URShift, EOF]")
}

///|
test "lex compound bitwise assignment" {
  let kinds = tok_kinds("&= |= ^= <<= >>= >>>=")
  inspect(
    kinds,
    content="[BitAndAssign, BitOrAssign, BitXorAssign, LShiftAssign, RShiftAssign, URShiftAssign, EOF]",
  )
}

///|
test "lex mixed new operators" {
  let kinds = tok_kinds("a++ + b")
  inspect(kinds, content="[Ident(\"a\"), PlusPlus, Plus, Ident(\"b\"), EOF]")
}

///|
test "lex try catch statement tokens" {
  let kinds = tok_kinds("try { x } catch (e) { throw e }")
  inspect(
    kinds,
    content="[Try, LBrace, Ident(\"x\"), RBrace, Catch, LParen, Ident(\"e\"), RParen, LBrace, Throw, Ident(\"e\"), RBrace, EOF]",
  )
}

///|
test "lex switch statement tokens" {
  let kinds = tok_kinds("switch (x) { case 1: default: }")
  inspect(
    kinds,
    content="[Switch, LParen, Ident(\"x\"), RParen, LBrace, Case, Number(1), Colon, Default, Colon, RBrace, EOF]",
  )
}

///|
test "lex do while tokens" {
  let kinds = tok_kinds("do { x } while (y)")
  inspect(
    kinds,
    content="[Do, LBrace, Ident(\"x\"), RBrace, While, LParen, Ident(\"y\"), RParen, EOF]",
  )
}

///|
test "lex for in tokens" {
  let kinds = tok_kinds("for (k in obj) {}")
  inspect(
    kinds,
    content="[For, LParen, Ident(\"k\"), In, Ident(\"obj\"), RParen, LBrace, RBrace, EOF]",
  )
}

///|
test "lex new expression tokens" {
  let kinds = tok_kinds("new Error()")
  inspect(kinds, content="[New, Ident(\"Error\"), LParen, RParen, EOF]")
}

///|
test "lex instanceof" {
  let kinds = tok_kinds("x instanceof Array")
  inspect(kinds, content="[Ident(\"x\"), Instanceof, Ident(\"Array\"), EOF]")
}

///|
test "lex slash assign vs comment" {
  let kinds = tok_kinds("x /= 2")
  inspect(kinds, content="[Ident(\"x\"), SlashAssign, Number(2), EOF]")
}

///|
test "lex unicode escape in string \\uXXXX" {
  let kinds = tok_kinds("\"\\u0041\"")
  inspect(kinds, content="[String_(\"A\"), EOF]")
}

///|
test "lex unicode escape in string \\u{} extended" {
  let kinds = tok_kinds("\"\\u{42}\"")
  inspect(kinds, content="[String_(\"B\"), EOF]")
}

///|
test "lex unicode escape in identifier start" {
  let kinds = tok_kinds("\\u0061")
  inspect(kinds, content="[Ident(\"a\"), EOF]")
}

///|
test "lex unicode escape in identifier middle" {
  let kinds = tok_kinds("a\\u0062c")
  inspect(kinds, content="[Ident(\"abc\"), EOF]")
}

///|
test "lex unicode escape identifier resolves to keyword" {
  let kinds = tok_kinds("\\u0076\\u0061\\u0072")
  inspect(kinds, content="[Var, EOF]")
}

///|
test "lex unicode escape var decl" {
  let kinds = tok_kinds("var \\u0061 = 1")
  inspect(kinds, content="[Var, Ident(\"a\"), Assign, Number(1), EOF]")
}

///|
test "lex unicode escape extended in identifier" {
  let kinds = tok_kinds("\\u{61}")
  inspect(kinds, content="[Ident(\"a\"), EOF]")
}

///|
test "lex unicode escape in template literal" {
  let kinds = tok_kinds("`\\u0048i`")
  inspect(kinds, content="[NoSubTemplate(\"Hi\"), EOF]")
}

///|
test "lex multiple unicode escapes in string" {
  let kinds = tok_kinds("\"\\u0048\\u0065\\u006C\\u006C\\u006F\"")
  inspect(kinds, content="[String_(\"Hello\"), EOF]")
}
