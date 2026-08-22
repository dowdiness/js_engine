///|
pub(all) struct Loc {
  line : Int
  col : Int
  offset : Int
} derive(Eq, Debug)

///|
pub impl Show for Loc with fn output(self, logger) {
  logger.write(Debug::to_repr(self))
}

///|
pub fn Loc::default() -> Loc noraise {
  { line: 1, col: 1, offset: 0 }
}

///|
/// A half-open source range expressed in JavaScript source coordinates.
pub struct SourceSpan {
  start_ : Loc
  end_ : Loc
} derive(Eq, Debug)

///|
fn SourceSpan::SourceSpan(start : Loc, end : Loc) -> SourceSpan {
  { start_: start, end_: end }
}

///|
pub fn SourceSpan::start(self : SourceSpan) -> Loc {
  self.start_
}

///|
pub fn SourceSpan::end(self : SourceSpan) -> Loc {
  self.end_
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
  logger.write(Debug::to_repr(self))
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
  logger.write(Debug::to_repr(self))
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
  logger.write(Debug::to_repr(self))
}

///|
/// `end_offset` is the exclusive UTF-16 code-unit offset in the original source
/// string at which this token ends. When -1 (the default for call sites that
/// don't track source position, e.g. tests), it is derived as
/// `loc.offset + raw.length()`, which is correct for all tokens whose `raw`
/// field is the verbatim source slice. The lexer always supplies an explicit
/// value.
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

///|
/// Resolve this token's half-open source range. Offsets are UTF-16 code units,
/// columns count Unicode scalar values, and CRLF is treated as one line break.
/// Returns `None` when the token offsets do not describe a slice of `source`.
pub fn Token::source_span(self : Token, source : String) -> SourceSpan? {
  guard source.get_view(start=self.loc.offset, end=self.end_offset)
    is Some(token_source) else {
    return None
  }
  let (line, col, _) = token_source.fold(
    init=(self.loc.line, self.loc.col, false),
    (state, char) => {
      let (line, col, previous_was_cr) = state
      if previous_was_cr && char == '\n' {
        (line, col, false)
      } else {
        match char.to_int() {
          0x0A | 0x0D | 0x2028 | 0x2029 => (line + 1, 1, char == '\r')
          _ => (line, col + 1, false)
        }
      }
    },
  )
  Some(SourceSpan(self.loc, { line, col, offset: self.end_offset }))
}
