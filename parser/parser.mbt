///|
/// Check if a string is a reserved word that cannot be used as a binding identifier.
/// Contextual keywords (get, set, from, as, of) are excluded since they ARE valid identifiers.
fn is_reserved_word(name : String) -> Bool {
  match name {
    "let" | "const" | "var" | "function" | "return" | "if" | "else" | "while"
    | "for" | "break" | "continue" | "true" | "false" | "null" | "undefined"
    | "typeof" | "throw" | "try" | "catch" | "finally" | "new" | "this"
    | "switch" | "case" | "default" | "void" | "delete" | "do" | "in"
    | "instanceof" | "class" | "extends" | "super" | "static" | "import"
    | "export" | "yield" | "enum" | "with" | "debugger" =>
      true
    _ => false
  }
}

///|
pub(all) struct Parser {
  tokens : Array[@token.Token]
  mut pos : Int
  mut allow_import_export : Bool // true at module top-level, false in nested blocks
  generator_depth : Array[Bool] // Stack: true when inside a generator function body
}

///|
pub fn Parser::new(tokens : Array[@token.Token]) -> Parser {
  { tokens, pos: 0, allow_import_export: true, generator_depth: [false] }
}

///|
fn Parser::in_generator(self : Parser) -> Bool {
  self.generator_depth[self.generator_depth.length() - 1]
}

///|
fn Parser::push_generator_context(self : Parser, is_generator : Bool) -> Unit {
  self.generator_depth.push(is_generator)
}

///|
fn Parser::pop_generator_context(self : Parser) -> Unit {
  let _ = self.generator_depth.pop()

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
      // Per spec: escaped reserved words (e.g. \u0076\u0061\u0072 = "var")
      // are valid as IdentifierName (property keys) but NOT as Identifier (bindings).
      // Since the lexer now emits them as Ident tokens, reject them here.
      if is_reserved_word(name) {
        let tok = self.peek()
        raise @errors.SyntaxError(
          message="Unexpected reserved word '\{name}' at line \{tok.loc.line}, col \{tok.loc.col}",
        )
      }
      self.pos += 1
      name
    }
    Get => {
      self.pos += 1
      "get"
    }
    Set => {
      self.pos += 1
      "set"
    }
    From => {
      self.pos += 1
      "from"
    }
    As => {
      self.pos += 1
      "as"
    }
    Of => {
      self.pos += 1
      "of"
    }
    Yield =>
      // yield is only a keyword inside generator bodies; outside it's an identifier
      if not(self.in_generator()) {
        self.pos += 1
        "yield"
      } else {
        let tok = self.peek()
        raise @errors.SyntaxError(
          message="Expected identifier, got \{tok.kind} at line \{tok.loc.line}, col \{tok.loc.col}",
        )
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
    Ident(_)
    | Let
    | Const
    | Var
    | Function
    | Return
    | If
    | Else
    | While
    | For
    | Break
    | Continue
    | Typeof
    | Throw
    | Try
    | Catch
    | Finally
    | New
    | This
    | Switch
    | Case
    | Default
    | Void
    | Delete
    | Do
    | In
    | Instanceof
    | Of
    | Class
    | Extends
    | Super
    | Static
    | Get
    | Set
    | Import
    | Export
    | From
    | As
    | Yield
    | True
    | False
    | Null
    | Undefined => {
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
