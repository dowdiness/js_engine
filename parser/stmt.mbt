///|
fn Parser::parse_stmt(self : Parser) -> @ast.Stmt raise Error {
  match self.peek_kind() {
    Let | Const | Var => self.parse_var_decl()
    Function => self.parse_func_decl()
    If => self.parse_if_stmt()
    While => self.parse_while_stmt()
    For => self.parse_for_stmt()
    Return => self.parse_return_stmt()
    Break => self.parse_break_stmt()
    Continue => self.parse_continue_stmt()
    LBrace => self.parse_block_stmt()
    _ => self.parse_expr_stmt()
  }
}

///|
fn Parser::parse_var_decl(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.advance()
  let kind : @ast.VarKind = match tok.kind {
    Let => LetKind
    Const => ConstKind
    Var => VarKind
    _ =>
      raise Failure::Failure(
        "Expected let/const/var at line \{tok.loc.line}, col \{tok.loc.col}",
      )
  }
  let name = self.expect_ident()
  let init : @ast.Expr? = if self.eat(Assign) {
    Some(self.parse_expr())
  } else {
    None
  }
  self.eat_semicolon()
  VarDecl(kind, name, init, tok.loc)
}

///|
fn Parser::parse_func_decl(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Function)
  let name = self.expect_ident()
  let params = self.parse_params()
  let body = self.parse_block_body()
  FuncDecl(name, params, body, tok.loc)
}

///|
fn Parser::parse_params(self : Parser) -> Array[String] raise Error {
  let _ = self.expect(LParen)
  let params : Array[String] = []
  if not(self.at(RParen)) {
    params.push(self.expect_ident())
    while self.eat(Comma) {
      params.push(self.expect_ident())
    }
  }
  let _ = self.expect(RParen)
  params
}

///|
fn Parser::parse_block_body(self : Parser) -> Array[@ast.Stmt] raise Error {
  let _ = self.expect(LBrace)
  let stmts : Array[@ast.Stmt] = []
  while not(self.at(RBrace)) && not(self.at(EOF)) {
    stmts.push(self.parse_stmt())
  }
  let _ = self.expect(RBrace)
  stmts
}

///|
fn Parser::parse_block_stmt(self : Parser) -> @ast.Stmt raise Error {
  let loc = self.peek().loc
  let stmts = self.parse_block_body()
  Block(stmts, loc)
}

///|
fn Parser::parse_if_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(If)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  let then_branch = self.parse_stmt()
  let else_branch : @ast.Stmt? = if self.eat(Else) {
    Some(self.parse_stmt())
  } else {
    None
  }
  IfStmt(cond, then_branch, else_branch, tok.loc)
}

///|
fn Parser::parse_while_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(While)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  let body = self.parse_stmt()
  WhileStmt(cond, body, tok.loc)
}

///|
fn Parser::parse_for_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(For)
  let _ = self.expect(LParen)
  // init
  let init : @ast.Stmt? = if self.at(Semicolon) {
    None
  } else if self.at(Let) || self.at(Const) || self.at(Var) {
    Some(self.parse_var_decl())
  } else {
    let expr = self.parse_expr()
    self.eat_semicolon()
    Some(ExprStmt(expr, tok.loc))
  }
  // For var_decl, semicolon was already consumed by parse_var_decl
  // For explicit semicolons, eat it
  if init is None {
    let _ = self.expect(Semicolon)

  }
  // condition
  let cond : @ast.Expr? = if self.at(Semicolon) {
    None
  } else {
    Some(self.parse_expr())
  }
  let _ = self.expect(Semicolon)
  // update
  let update : @ast.Expr? = if self.at(RParen) {
    None
  } else {
    Some(self.parse_expr())
  }
  let _ = self.expect(RParen)
  let body = self.parse_stmt()
  ForStmt(init, cond, update, body, tok.loc)
}

///|
fn Parser::parse_return_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Return)
  let value : @ast.Expr? = if self.at(Semicolon) ||
    self.at(RBrace) ||
    self.at(EOF) {
    None
  } else {
    Some(self.parse_expr())
  }
  self.eat_semicolon()
  ReturnStmt(value, tok.loc)
}

///|
fn Parser::parse_break_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Break)
  self.eat_semicolon()
  BreakStmt(tok.loc)
}

///|
fn Parser::parse_continue_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Continue)
  self.eat_semicolon()
  ContinueStmt(tok.loc)
}

///|
fn Parser::parse_expr_stmt(self : Parser) -> @ast.Stmt raise Error {
  let loc = self.peek().loc
  let expr = self.parse_expr()
  self.eat_semicolon()
  ExprStmt(expr, loc)
}
