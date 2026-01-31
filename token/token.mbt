///|
pub(all) struct Loc {
  line : Int
  col : Int
  offset : Int
} derive(Eq, Show)

///|
pub fn Loc::default() -> Loc {
  { line: 1, col: 1, offset: 0 }
}

///|
pub(all) enum TokenKind {
  // Literals
  Number(Double)
  String_(String)
  True
  False
  Null
  Undefined
  // Identifier
  Ident(String)
  // Keywords
  Let
  Const
  Var
  Function
  Return
  If
  Else
  While
  For
  Break
  Continue
  Typeof
  // Operators
  Plus
  Minus
  Star
  Slash
  Percent
  Assign
  EqEq
  EqEqEq
  BangEq
  BangEqEq
  Lt
  Gt
  LtEq
  GtEq
  And
  Or
  Bang
  // Delimiters
  LParen
  RParen
  LBrace
  RBrace
  LBracket
  RBracket
  Comma
  Semicolon
  Dot
  Colon
  Question
  // Special
  EOF
} derive(Eq, Show)

///|
pub(all) struct Token {
  kind : TokenKind
  loc : Loc
  raw : String
} derive(Eq, Show)

///|
pub fn Token::new(kind : TokenKind, loc : Loc, raw : String) -> Token {
  { kind, loc, raw }
}

///|
pub fn Token::eof(loc : Loc) -> Token {
  { kind: EOF, loc, raw: "" }
}
