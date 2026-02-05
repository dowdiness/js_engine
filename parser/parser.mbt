///|
pub(all) struct Parser {
  tokens : Array[@token.Token]
  mut pos : Int
}

///|
pub fn Parser::new(tokens : Array[@token.Token]) -> Parser {
  { tokens, pos: 0 }
}

///|
fn Parser::peek(self : Parser) -> @token.Token {
  self.tokens[self.pos]
}

///|
fn Parser::peek_kind(self : Parser) -> @token.TokenKind {
  self.tokens[self.pos].kind
}

///|
fn Parser::advance(self : Parser) -> @token.Token {
  let tok = self.tokens[self.pos]
  self.pos += 1
  tok
}

///|
fn Parser::at(self : Parser, kind : @token.TokenKind) -> Bool {
  self.peek_kind() == kind
}

///|
fn Parser::eat(self : Parser, kind : @token.TokenKind) -> Bool {
  if self.at(kind) {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn Parser::expect(
  self : Parser,
  kind : @token.TokenKind,
) -> @token.Token raise Error {
  if self.peek_kind() == kind {
    self.advance()
  } else {
    let tok = self.peek()
    raise @errors.SyntaxError(
      message="Expected \{kind}, got \{tok.kind} at line \{tok.loc.line}, col \{tok.loc.col}",
    )
  }
}

///|
fn Parser::expect_ident(self : Parser) -> String raise Error {
  match self.peek_kind() {
    Ident(name) => {
      self.pos += 1
      name
    }
    _ => {
      let tok = self.peek()
      raise @errors.SyntaxError(
        message="Expected identifier, got \{tok.kind} at line \{tok.loc.line}, col \{tok.loc.col}",
      )
    }
  }
}

///|
/// Like expect_ident, but accepts reserved keywords as property names.
/// Used after `.` where ECMAScript allows any IdentifierName.
fn Parser::expect_ident_name(self : Parser) -> String raise Error {
  let tok = self.peek()
  match tok.kind {
    Ident(_) | Let | Const | Var | Function | Return | If | Else | While |
    For | Break | Continue | Typeof | Throw | Try | Catch | Finally | New |
    This | Switch | Case | Default | Void | Delete | Do | In | Instanceof |
    Of | Class | Extends | Super | Static | Get | Set | True | False | Null |
    Undefined => {
      self.pos += 1
      tok.raw
    }
    _ =>
      raise @errors.SyntaxError(
        message="Expected identifier, got \{tok.kind} at line \{tok.loc.line}, col \{tok.loc.col}",
      )
  }
}

///|
fn Parser::peek_kind_at(self : Parser, offset : Int) -> @token.TokenKind {
  let idx = self.pos + offset
  if idx < self.tokens.length() {
    self.tokens[idx].kind
  } else {
    EOF
  }
}

///|
fn Parser::eat_semicolon(self : Parser) -> Unit {
  // Lenient: consume semicolon if present, no error otherwise
  let _ = self.eat(Semicolon)

}

///|
pub fn parse(source : String) -> @ast.Program raise Error {
  let tokens = @lexer.tokenize(source)
  let parser = Parser::new(tokens)
  let stmts : Array[@ast.Stmt] = []
  while not(parser.at(EOF)) {
    stmts.push(parser.parse_stmt())
  }
  { stmts, }
}
