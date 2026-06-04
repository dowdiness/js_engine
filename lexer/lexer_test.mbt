///|
fn tok_kinds(source : String) -> Array[@token.TokenKind] raise Error {
  let tokens = @lexer.tokenize(source)
  tokens.map(fn(t) { t.kind })
}

///|
fn inspect_kinds(
  kinds : Array[@token.TokenKind],
  content~ : Json,
) -> Unit raise Error {
  json_inspect(kinds.map(fn(kind) { kind.to_string() }), content~)
}

///|
fn expect_lex_form(
  actual : @token.LexForm,
  expected : @token.LexForm,
) -> Unit raise Error {
  guard actual == expected else {
    fail(
      "expected lex_form " +
      expected.to_string() +
      ", got " +
      actual.to_string(),
    )
  }
}

///|
fn[T] expect_err(result : Result[T, Unit]) -> Unit raise Error {
  match result {
    Ok(_) => fail("expected lexer error")
    Err(_) => ()
  }
}

///|
test "lex arithmetic expression" {
  let kinds = tok_kinds("1 + 2 * 3")
  inspect_kinds(kinds, content=[
    "Number(1)", "Plus", "Number(2)", "Star", "Number(3)", "EOF",
  ])
}

///|
test "lex keywords" {
  let kinds = tok_kinds("let x = 10")
  inspect_kinds(kinds, content=[
    "Let", "Ident(\"x\")", "Assign", "Number(10)", "EOF",
  ])
}

///|
test "lex string" {
  let kinds = tok_kinds("\"hello world\"")
  inspect_kinds(kinds, content=["String_(\"hello world\")", "EOF"])
}

///|
test "lex single-quoted string" {
  let kinds = tok_kinds("'hi'")
  inspect_kinds(kinds, content=["String_(\"hi\")", "EOF"])
}

///|
test "lex string with escape" {
  let kinds = tok_kinds("\"a\\nb\"")
  inspect_kinds(kinds, content=["String_(\"a\\nb\")", "EOF"])
}

///|
test "lex comparison operators" {
  let kinds = tok_kinds("=== !== == != <= >=")
  inspect_kinds(kinds, content=[
    "EqEqEq", "BangEqEq", "EqEq", "BangEq", "LtEq", "GtEq", "EOF",
  ])
}

///|
test "lex logical operators" {
  let kinds = tok_kinds("&& ||")
  inspect_kinds(kinds, content=["And", "Or", "EOF"])
}

///|
test "lex single-line comment" {
  let kinds = tok_kinds("1 // comment\n2")
  inspect_kinds(kinds, content=["Number(1)", "Number(2)", "EOF"])
}

///|
test "lex multi-line comment" {
  let kinds = tok_kinds("1 /* comment */ 2")
  inspect_kinds(kinds, content=["Number(1)", "Number(2)", "EOF"])
}

///|
test "lex function" {
  let kinds = tok_kinds("function foo(x) { return x; }")
  inspect_kinds(kinds, content=[
    "Function", "Ident(\"foo\")", "LParen", "Ident(\"x\")", "RParen", "LBrace", "Return",
    "Ident(\"x\")", "Semicolon", "RBrace", "EOF",
  ])
}

///|
test "lex decimal number" {
  let kinds = tok_kinds("3.14")
  inspect_kinds(kinds, content=["Number(3.14)", "EOF"])
}

///|
test "lex boolean and null" {
  let kinds = tok_kinds("true false null undefined")
  inspect_kinds(kinds, content=["True", "False", "Null", "Undefined", "EOF"])
}

///|
test "lex dot and member" {
  let kinds = tok_kinds("console.log")
  inspect_kinds(kinds, content=[
    "Ident(\"console\")", "Dot", "Ident(\"log\")", "EOF",
  ])
}

///|
test "lex ternary" {
  let kinds = tok_kinds("x ? 1 : 2")
  inspect_kinds(kinds, content=[
    "Ident(\"x\")", "Question", "Number(1)", "Colon", "Number(2)", "EOF",
  ])
}

///|
test "lex typeof" {
  let kinds = tok_kinds("typeof x")
  inspect_kinds(kinds, content=["Typeof", "Ident(\"x\")", "EOF"])
}

///|
test "lex new keywords" {
  let kinds = tok_kinds("throw try catch finally")
  inspect_kinds(kinds, content=["Throw", "Try", "Catch", "Finally", "EOF"])
}

///|
test "lex new this switch" {
  let kinds = tok_kinds("new this switch case default")
  inspect_kinds(kinds, content=[
    "New", "This", "Switch", "Case", "Default", "EOF",
  ])
}

///|
test "lex void delete do in instanceof" {
  let kinds = tok_kinds("void delete do in instanceof")
  inspect_kinds(kinds, content=[
    "Void", "Delete", "Do", "In", "Instanceof", "EOF",
  ])
}

///|
test "lex increment decrement" {
  let kinds = tok_kinds("x++ y--")
  inspect_kinds(kinds, content=[
    "Ident(\"x\")", "PlusPlus", "Ident(\"y\")", "MinusMinus", "EOF",
  ])
}

///|
test "lex compound assignment" {
  let kinds = tok_kinds("+= -= *= /= %=")
  inspect_kinds(kinds, content=[
    "PlusAssign", "MinusAssign", "StarAssign", "SlashAssign", "PercentAssign", "EOF",
  ])
}

///|
test "lex bitwise operators" {
  let kinds = tok_kinds("& | ^ ~")
  inspect_kinds(kinds, content=["BitAnd", "BitOr", "BitXor", "Tilde", "EOF"])
}

///|
test "lex shift operators" {
  let kinds = tok_kinds("<< >> >>>")
  inspect_kinds(kinds, content=["LShift", "RShift", "URShift", "EOF"])
}

///|
test "lex compound bitwise assignment" {
  let kinds = tok_kinds("&= |= ^= <<= >>= >>>=")
  inspect_kinds(kinds, content=[
    "BitAndAssign", "BitOrAssign", "BitXorAssign", "LShiftAssign", "RShiftAssign",
    "URShiftAssign", "EOF",
  ])
}

///|
test "lex mixed new operators" {
  let kinds = tok_kinds("a++ + b")
  inspect_kinds(kinds, content=[
    "Ident(\"a\")", "PlusPlus", "Plus", "Ident(\"b\")", "EOF",
  ])
}

///|
test "lex try catch statement tokens" {
  let kinds = tok_kinds("try { x } catch (e) { throw e }")
  inspect_kinds(kinds, content=[
    "Try", "LBrace", "Ident(\"x\")", "RBrace", "Catch", "LParen", "Ident(\"e\")",
    "RParen", "LBrace", "Throw", "Ident(\"e\")", "RBrace", "EOF",
  ])
}

///|
test "lex switch statement tokens" {
  let kinds = tok_kinds("switch (x) { case 1: default: }")
  inspect_kinds(kinds, content=[
    "Switch", "LParen", "Ident(\"x\")", "RParen", "LBrace", "Case", "Number(1)",
    "Colon", "Default", "Colon", "RBrace", "EOF",
  ])
}

///|
test "lex do while tokens" {
  let kinds = tok_kinds("do { x } while (y)")
  inspect_kinds(kinds, content=[
    "Do", "LBrace", "Ident(\"x\")", "RBrace", "While", "LParen", "Ident(\"y\")",
    "RParen", "EOF",
  ])
}

///|
test "lex for in tokens" {
  let kinds = tok_kinds("for (k in obj) {}")
  inspect_kinds(kinds, content=[
    "For", "LParen", "Ident(\"k\")", "In", "Ident(\"obj\")", "RParen", "LBrace",
    "RBrace", "EOF",
  ])
}

///|
test "lex new expression tokens" {
  let kinds = tok_kinds("new Error()")
  inspect_kinds(kinds, content=[
    "New", "Ident(\"Error\")", "LParen", "RParen", "EOF",
  ])
}

///|
test "lex instanceof" {
  let kinds = tok_kinds("x instanceof Array")
  inspect_kinds(kinds, content=[
    "Ident(\"x\")", "Instanceof", "Ident(\"Array\")", "EOF",
  ])
}

///|
test "lex slash assign vs comment" {
  let kinds = tok_kinds("x /= 2")
  inspect_kinds(kinds, content=[
    "Ident(\"x\")", "SlashAssign", "Number(2)", "EOF",
  ])
}

///|
test "lex slash after sloppy yield identifier as division" {
  let kinds = tok_kinds("var yield = 8, x = 2, g = 4; yield / x / g;")
  inspect_kinds(kinds, content=[
    "Var", "Yield", "Assign", "Number(8)", "Comma", "Ident(\"x\")", "Assign", "Number(2)",
    "Comma", "Ident(\"g\")", "Assign", "Number(4)", "Semicolon", "Yield", "Slash",
    "Ident(\"x\")", "Slash", "Ident(\"g\")", "Semicolon", "EOF",
  ])
}

///|
test "lex slash after generator yield as regexp" {
  let kinds = tok_kinds("function* g() { yield /x/g; }")
  inspect_kinds(kinds, content=[
    "Function", "Star", "Ident(\"g\")", "LParen", "RParen", "LBrace", "Yield", "Regex(\"x\", \"g\")",
    "Semicolon", "RBrace", "EOF",
  ])
}

///|
test "lex unicode escape in string \\uXXXX" {
  let kinds = tok_kinds("\"\\u0041\"")
  inspect_kinds(kinds, content=["String_(\"A\")", "EOF"])
}

///|
test "lex unicode escape in string \\u{} extended" {
  let kinds = tok_kinds("\"\\u{42}\"")
  inspect_kinds(kinds, content=["String_(\"B\")", "EOF"])
}

///|
test "lex unicode escape in identifier start" {
  let kinds = tok_kinds("\\u0061")
  inspect_kinds(kinds, content=["Ident(\"a\")", "EOF"])
}

///|
test "lex unicode escape in identifier middle" {
  let kinds = tok_kinds("a\\u0062c")
  inspect_kinds(kinds, content=["Ident(\"abc\")", "EOF"])
}

///|
test "lex unicode escape identifier resolves to keyword" {
  // Per spec: escaped reserved words become Ident tokens (valid as IdentifierName
  // e.g. in property keys), not keyword tokens. Parser enforces binding restrictions.
  let kinds = tok_kinds("\\u0076\\u0061\\u0072")
  inspect_kinds(kinds, content=["Ident(\"var\")", "EOF"])
}

///|
test "lex unicode escape var decl" {
  let kinds = tok_kinds("var \\u0061 = 1")
  inspect_kinds(kinds, content=[
    "Var", "Ident(\"a\")", "Assign", "Number(1)", "EOF",
  ])
}

///|
test "lex unicode escape extended in identifier" {
  let kinds = tok_kinds("\\u{61}")
  inspect_kinds(kinds, content=["Ident(\"a\")", "EOF"])
}

///|
test "lex unicode escape in template literal" {
  let kinds = tok_kinds("`\\u0048i`")
  inspect_kinds(kinds, content=["NoSubTemplate(\"Hi\")", "EOF"])
}

///|
test "lex multiple unicode escapes in string" {
  let kinds = tok_kinds("\"\\u0048\\u0065\\u006C\\u006C\\u006F\"")
  inspect_kinds(kinds, content=["String_(\"Hello\")", "EOF"])
}

///|
test "lex unicode escape supplementary plane in string" {
  // \u{1F600} is U+1F600 (😀) — exercises surrogate pair path
  let tokens = @lexer.tokenize("\"\\u{1F600}\"")
  // Should produce a String_ token (surrogate pair encoded)
  match tokens[0].kind {
    String_(_) => ()
    _ => fail("Expected String_ token")
  }
}

///|
test "lex unicode escape invalid identifier start" {
  // \u0031 is '1' — not valid at identifier start
  let result = Ok(@lexer.tokenize("\\u0031")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "lex unicode escape invalid hex digits" {
  let result = Ok(@lexer.tokenize("\"\\u00GZ\"")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "lex unicode escape empty braces" {
  let result = Ok(@lexer.tokenize("\"\\u{}\"")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "lex unicode escape code point too large" {
  let result = Ok(@lexer.tokenize("\"\\u{110000}\"")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "lex hex number" {
  let kinds = tok_kinds("0xFF")
  inspect_kinds(kinds, content=["Number(255)", "EOF"])
}

///|
test "lex hex number uppercase prefix" {
  let kinds = tok_kinds("0XFF")
  inspect_kinds(kinds, content=["Number(255)", "EOF"])
}

///|
test "lex binary number" {
  let kinds = tok_kinds("0b1010")
  inspect_kinds(kinds, content=["Number(10)", "EOF"])
}

///|
test "lex octal number" {
  let kinds = tok_kinds("0o17")
  inspect_kinds(kinds, content=["Number(15)", "EOF"])
}

///|
test "lex legacy octal" {
  let kinds = tok_kinds("077")
  inspect_kinds(kinds, content=["Number(63)", "EOF"])
}

///|
test "lex leading decimal" {
  let kinds = tok_kinds(".5")
  inspect_kinds(kinds, content=["Number(0.5)", "EOF"])
}

///|
test "lex numeric separator in decimal" {
  let kinds = tok_kinds("1_000_000")
  inspect_kinds(kinds, content=["Number(1000000)", "EOF"])
}

///|
test "lex numeric separator in hex" {
  let kinds = tok_kinds("0xFF_AA")
  inspect_kinds(kinds, content=["Number(65450)", "EOF"])
}

///|
test "lex numeric separator in binary" {
  let kinds = tok_kinds("0b1010_1010")
  inspect_kinds(kinds, content=["Number(170)", "EOF"])
}

///|
test "lex numeric separator in octal" {
  let kinds = tok_kinds("0o7_7")
  inspect_kinds(kinds, content=["Number(63)", "EOF"])
}

///|
test "lex hex missing digits error" {
  let result = Ok(tok_kinds("0x")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "lex binary missing digits error" {
  let result = Ok(tok_kinds("0b")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "lex octal missing digits error" {
  let result = Ok(tok_kinds("0o")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "lex consecutive numeric separator error" {
  let result = Ok(tok_kinds("1__0")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "lex trailing numeric separator error" {
  let result = Ok(tok_kinds("1_")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "legacy octal escape: bare digit tags token" {
  let toks = @lexer.tokenize("\"\\1\"")
  expect_lex_form(toks[0].lex_form, @token.LexForm::StringLegacyOctalEscape)
}

///|
test "legacy octal escape: \\7 tags" {
  let toks = @lexer.tokenize("\"\\7\"")
  expect_lex_form(toks[0].lex_form, @token.LexForm::StringLegacyOctalEscape)
}

///|
test "non-octal decimal escape: \\8 tags" {
  let toks = @lexer.tokenize("\"\\8\"")
  expect_lex_form(toks[0].lex_form, @token.LexForm::StringLegacyOctalEscape)
}

///|
test "non-octal decimal escape: \\9 tags" {
  let toks = @lexer.tokenize("\"\\9\"")
  expect_lex_form(toks[0].lex_form, @token.LexForm::StringLegacyOctalEscape)
}

///|
test "bare \\0 (no following digit) does NOT tag" {
  let toks = @lexer.tokenize("\"\\0\"")
  expect_lex_form(toks[0].lex_form, @token.LexForm::LexNormal)
}

///|
test "bare \\0 followed by digit DOES tag" {
  let toks = @lexer.tokenize("\"\\08\"")
  expect_lex_form(toks[0].lex_form, @token.LexForm::StringLegacyOctalEscape)
}

///|
test "plain string is LexNormal" {
  let toks = @lexer.tokenize("\"hello\"")
  expect_lex_form(toks[0].lex_form, @token.LexForm::LexNormal)
}

///|
test "string with \\n escape is LexNormal" {
  let toks = @lexer.tokenize("\"a\\nb\"")
  expect_lex_form(toks[0].lex_form, @token.LexForm::LexNormal)
}

///|
test "numeric 0777 tags as NumberLegacyOctalInt" {
  let toks = @lexer.tokenize("0777")
  expect_lex_form(toks[0].lex_form, @token.LexForm::NumberLegacyOctalInt)
}

///|
test "numeric 08 tags as NumberNonOctalDecimalInt" {
  let toks = @lexer.tokenize("08")
  expect_lex_form(toks[0].lex_form, @token.LexForm::NumberNonOctalDecimalInt)
}

///|
test "numeric 09 tags as NumberNonOctalDecimalInt" {
  let toks = @lexer.tokenize("09")
  expect_lex_form(toks[0].lex_form, @token.LexForm::NumberNonOctalDecimalInt)
}

///|
test "numeric 0o777 (modern octal) is LexNormal" {
  let toks = @lexer.tokenize("0o777")
  expect_lex_form(toks[0].lex_form, @token.LexForm::LexNormal)
}

///|
test "plain numeric 100 is LexNormal" {
  let toks = @lexer.tokenize("100")
  expect_lex_form(toks[0].lex_form, @token.LexForm::LexNormal)
}

///|
test "numeric 08.1 (NonOctalDecimal + fraction) tags NumberNonOctalDecimalInt" {
  let toks = @lexer.tokenize("08.1")
  expect_lex_form(toks[0].lex_form, @token.LexForm::NumberNonOctalDecimalInt)
}

///|
test "numeric 08e2 (NonOctalDecimal + exponent) tags NumberNonOctalDecimalInt" {
  let toks = @lexer.tokenize("08e2")
  expect_lex_form(toks[0].lex_form, @token.LexForm::NumberNonOctalDecimalInt)
}

///|
test "numeric 09.5 (NonOctalDecimal + fraction) tags NumberNonOctalDecimalInt" {
  let toks = @lexer.tokenize("09.5")
  expect_lex_form(toks[0].lex_form, @token.LexForm::NumberNonOctalDecimalInt)
}

///|
test "numeric 08.1 has decimal value 8.1" {
  let kinds = tok_kinds("08.1")
  inspect_kinds(kinds, content=["Number(8.1)", "EOF"])
}

///|
test "numeric 08e2 has decimal value 800" {
  let kinds = tok_kinds("08e2")
  inspect_kinds(kinds, content=["Number(800)", "EOF"])
}

///|
test "numeric 0.5 (single-zero fractional) is LexNormal" {
  let toks = @lexer.tokenize("0.5")
  expect_lex_form(toks[0].lex_form, @token.LexForm::LexNormal)
}

///|
test "numeric 0.1e2 (single-zero exponent) is LexNormal" {
  let toks = @lexer.tokenize("0.1e2")
  expect_lex_form(toks[0].lex_form, @token.LexForm::LexNormal)
}

///|
test "numeric 01.2 (LegacyOctal + fraction) is SyntaxError in all modes" {
  let result = Ok(tok_kinds("01.2")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "numeric 01e2 (LegacyOctal + exponent) is SyntaxError in all modes" {
  let result = Ok(tok_kinds("01e2")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "numeric 01E2 (LegacyOctal + uppercase exponent) is SyntaxError" {
  let result = Ok(tok_kinds("01E2")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "numeric 00.5 (LegacyOctal + fraction) is SyntaxError" {
  let result = Ok(tok_kinds("00.5")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "numeric 001.2 (LegacyOctal + fraction) is SyntaxError" {
  let result = Ok(tok_kinds("001.2")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "numeric 07.5 (LegacyOctal + fraction) is SyntaxError" {
  let result = Ok(tok_kinds("07.5")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "LegacyOctal member access: 01.toString tokenizes as Number . Ident" {
  // Per V8: `01.toString()` evaluates to "1" — `.` is member access, not
  // a fractional continuation. The dot-followed-by-digit guard must NOT
  // fire here.
  let kinds = tok_kinds("01.toString")
  inspect_kinds(kinds, content=[
    "Number(1)", "Dot", "Ident(\"toString\")", "EOF",
  ])
}

///|
test "LegacyOctal member access: 01.a tokenizes as Number . Ident" {
  let kinds = tok_kinds("01.a")
  inspect_kinds(kinds, content=["Number(1)", "Dot", "Ident(\"a\")", "EOF"])
}

///|
test "LegacyOctal member access: 00.toString tokenizes as Number . Ident" {
  let kinds = tok_kinds("00.toString")
  inspect_kinds(kinds, content=[
    "Number(0)", "Dot", "Ident(\"toString\")", "EOF",
  ])
}

///|
test "LegacyOctal whitespace dot: 01 .toString tokenizes correctly" {
  let kinds = tok_kinds("01 .toString")
  inspect_kinds(kinds, content=[
    "Number(1)", "Dot", "Ident(\"toString\")", "EOF",
  ])
}

///|
test "numeric 0 is LexNormal" {
  let toks = @lexer.tokenize("0")
  expect_lex_form(toks[0].lex_form, @token.LexForm::LexNormal)
}
