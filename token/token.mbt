///|
pub(all) struct Loc {
  line : Int
  col : Int
  offset : Int
} derive(Eq, Debug)

///|
pub impl Show for Loc with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub fn Loc::default() -> Loc noraise {
  { line: 1, col: 1, offset: 0 }
}

///|
pub(all) enum LexForm {
  LexNormal
  StringLegacyOctalEscape
  NumberLegacyOctalInt
  NumberNonOctalDecimalInt
} derive(Eq, Debug)

///|
pub impl Show for LexForm with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
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
  // Private identifier (#name)
  PrivateName(String)
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
  // Template literals — (raw, cooked) where cooked is None for invalid escapes
  NoSubTemplate(String, String?)
  TemplateHead(String, String?)
  TemplateMiddle(String, String?)
  TemplateTail(String, String?)
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
pub impl Show for TokenKind with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub(all) struct Token {
  kind : TokenKind
  loc : Loc
  raw : String
  lex_form : LexForm
  end_offset : Int
} derive(Eq, Debug)

///|
pub impl Show for Token with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
/// `end_offset` is the exclusive byte offset in the original source string at
/// which this token ends. When -1 (the default for call sites that don't track
/// source position, e.g. tests), it is derived as `loc.offset + raw.length()`,
/// which is correct for all tokens whose `raw` field is the verbatim source
/// slice. The lexer always supplies an explicit value.
pub fn Token::Token(
  kind : TokenKind,
  loc : Loc,
  raw : String,
  lex_form? : LexForm = LexNormal,
  end_offset? : Int = -1,
) -> Token noraise {
  let end_offset = if end_offset == -1 {
    loc.offset + raw.length()
  } else {
    end_offset
  }
  { kind, loc, raw, lex_form, end_offset }
}

///|
pub fn Token::new(
  kind : TokenKind,
  loc : Loc,
  raw : String,
  lex_form? : LexForm = LexNormal,
  end_offset? : Int = -1,
) -> Token noraise {
  Token(kind, loc, raw, lex_form~, end_offset~)
}

///|
pub fn Token::eof(loc : Loc) -> Token noraise {
  Token(EOF, loc, "", end_offset=loc.offset)
}
