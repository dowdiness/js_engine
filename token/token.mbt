///|
pub(all) struct Loc {
  line : Int
  col : Int
  offset : Int
} derive(Eq, Debug)

///|
pub impl Show for Loc with output(self, logger) {
  Debug::to_repr(self).output(logger)
}

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
  Throw
  Try
  Catch
  Finally
  New
  This
  Switch
  Case
  Default
  Void
  Delete
  Do
  In
  Instanceof
  // Class-related
  Class
  Extends
  Super
  Static
  Get
  Set
  // Generator-related
  Yield
  // Module-related
  Import
  Export
  From
  As
  // Operators
  Plus
  Minus
  Star
  StarStar
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
  QuestionQuestion // ??
  QuestionDot // ?.
  Bang
  // Update / Compound assignment
  PlusPlus
  MinusMinus
  PlusAssign
  MinusAssign
  StarAssign
  StarStarAssign
  SlashAssign
  PercentAssign
  // Bitwise
  BitAnd
  BitOr
  BitXor
  Tilde
  LShift
  RShift
  URShift
  // Compound bitwise assignment
  BitAndAssign
  BitOrAssign
  BitXorAssign
  LShiftAssign
  RShiftAssign
  URShiftAssign
  // Logical assignment
  AndAssign // &&=
  OrAssign // ||=
  NullishAssign // ??=
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
  // Template literals
  NoSubTemplate(String)
  TemplateHead(String)
  TemplateMiddle(String)
  TemplateTail(String)
  // Arrow
  Arrow
  // Spread/Rest
  DotDotDot
  // Regex
  Regex(String, String) // pattern, flags
  // Special
  Of
  EOF
} derive(Eq, Debug)

///|
pub impl Show for TokenKind with output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub(all) struct Token {
  kind : TokenKind
  loc : Loc
  raw : String
} derive(Eq, Debug)

///|
pub impl Show for Token with output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub fn Token::new(kind : TokenKind, loc : Loc, raw : String) -> Token {
  { kind, loc, raw }
}

///|
pub fn Token::eof(loc : Loc) -> Token {
  { kind: EOF, loc, raw: "" }
}
