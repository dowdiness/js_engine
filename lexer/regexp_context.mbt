///|
/// Decide whether `/` starts a RegExp literal after the previous token.
///
/// The boolean arguments carry the lexer state needed for tokens whose meaning
/// depends on their surrounding grammar context.
fn slash_starts_regexp_after(
  previous : @token.TokenKind,
  yield_allows_regexp~ : Bool,
  rparen_is_control_flow~ : Bool,
  rbrace_is_block~ : Bool,
) -> Bool {
  match previous {
    Assign
    | EqEq
    | EqEqEq
    | BangEq
    | BangEqEq
    | LParen
    | LBracket
    | LBrace
    | Comma
    | Semicolon
    | Colon
    | Question
    | QuestionQuestion
    | QuestionDot
    | And
    | Or
    | Bang
    | Plus
    | Minus
    | Star
    | StarStar
    | Slash
    | Percent
    | Lt
    | Gt
    | LtEq
    | GtEq
    | Return
    | Typeof
    | Throw
    | New
    | Delete
    | Void
    | In
    | Instanceof
    | PlusAssign
    | MinusAssign
    | StarAssign
    | StarStarAssign
    | SlashAssign
    | PercentAssign
    | BitAnd
    | BitOr
    | BitXor
    | Tilde
    | LShift
    | RShift
    | URShift
    | BitAndAssign
    | BitOrAssign
    | BitXorAssign
    | LShiftAssign
    | RShiftAssign
    | URShiftAssign
    | AndAssign
    | OrAssign
    | NullishAssign
    | Case
    | Arrow => true
    Yield => yield_allows_regexp
    RParen => rparen_is_control_flow
    RBrace => rbrace_is_block
    _ => false
  }
}
