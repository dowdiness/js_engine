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
    Throw => self.parse_throw_stmt()
    Try => self.parse_try_catch_stmt()
    Switch => self.parse_switch_stmt()
    Do => self.parse_do_while_stmt()
    LBrace => self.parse_block_stmt()
    Ident(_) =>
      // Labeled statement: ident ':'
      if self.peek_kind_at(1) == Colon {
        self.parse_labeled_stmt()
      } else {
        self.parse_expr_stmt()
      }
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
    Some(self.parse_assignment())
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
  // Check for for-in with var/let/const
  if self.at(Let) || self.at(Const) || self.at(Var) {
    let var_tok = self.advance()
    let var_kind : @ast.VarKind = match var_tok.kind {
      Let => LetKind
      Const => ConstKind
      _ => VarKind
    }
    let name = self.expect_ident()
    if self.eat(In) {
      // for-in with var declaration
      let obj = self.parse_expr()
      let _ = self.expect(RParen)
      let body = self.parse_stmt()
      return ForInStmt(Some(var_kind), name, obj, body, tok.loc)
    }
    // Regular for — finish parsing the var decl init
    let init_val : @ast.Expr? = if self.eat(Assign) {
      Some(self.parse_assignment())
    } else {
      None
    }
    self.eat_semicolon()
    let init : @ast.Stmt? = Some(VarDecl(var_kind, name, init_val, var_tok.loc))
    return self.parse_for_rest(init, tok.loc)
  }
  // Check for for-in with bare identifier
  match self.peek_kind() {
    Ident(name) =>
      if self.peek_kind_at(1) == In {
        self.pos += 1 // consume ident
        self.pos += 1 // consume 'in'
        let obj = self.parse_expr()
        let _ = self.expect(RParen)
        let body = self.parse_stmt()
        return ForInStmt(None, name, obj, body, tok.loc)
      }
    _ => ()
  }
  // Regular for-loop
  let init : @ast.Stmt? = if self.at(Semicolon) {
    None
  } else {
    let expr = self.parse_expr()
    self.eat_semicolon()
    Some(ExprStmt(expr, tok.loc))
  }
  if init is None {
    let _ = self.expect(Semicolon)

  }
  self.parse_for_rest(init, tok.loc)
}

///|
fn Parser::parse_for_rest(
  self : Parser,
  init : @ast.Stmt?,
  loc : @token.Loc,
) -> @ast.Stmt raise Error {
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
  ForStmt(init, cond, update, body, loc)
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
  let label : String? = match self.peek_kind() {
    Ident(name) =>
      if self.peek().loc.line == tok.loc.line {
        self.pos += 1
        Some(name)
      } else {
        None
      }
    _ => None
  }
  self.eat_semicolon()
  BreakStmt(label, tok.loc)
}

///|
fn Parser::parse_continue_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Continue)
  let label : String? = match self.peek_kind() {
    Ident(name) =>
      if self.peek().loc.line == tok.loc.line {
        self.pos += 1
        Some(name)
      } else {
        None
      }
    _ => None
  }
  self.eat_semicolon()
  ContinueStmt(label, tok.loc)
}

///|
fn Parser::parse_throw_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Throw)
  let expr = self.parse_expr()
  self.eat_semicolon()
  ThrowStmt(expr, tok.loc)
}

///|
fn Parser::parse_try_catch_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Try)
  let try_body = self.parse_block_body()
  let mut catch_param : String? = None
  let mut catch_body : Array[@ast.Stmt]? = None
  let mut finally_body : Array[@ast.Stmt]? = None
  if self.eat(Catch) {
    let _ = self.expect(LParen)
    catch_param = Some(self.expect_ident())
    let _ = self.expect(RParen)
    catch_body = Some(self.parse_block_body())
  }
  if self.eat(Finally) {
    finally_body = Some(self.parse_block_body())
  }
  if catch_body is None && finally_body is None {
    raise Failure::Failure(
      "Missing catch or finally after try at line \{tok.loc.line}, col \{tok.loc.col}",
    )
  }
  TryCatchStmt(try_body, catch_param, catch_body, finally_body, tok.loc)
}

///|
fn Parser::parse_switch_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Switch)
  let _ = self.expect(LParen)
  let discriminant = self.parse_expr()
  let _ = self.expect(RParen)
  let _ = self.expect(LBrace)
  let cases : Array[@ast.SwitchCase] = []
  while not(self.at(RBrace)) && not(self.at(EOF)) {
    if self.eat(Case) {
      let test_expr = self.parse_expr()
      let _ = self.expect(Colon)
      let body : Array[@ast.Stmt] = []
      while not(self.at(Case)) &&
            not(self.at(Default)) &&
            not(self.at(RBrace)) &&
            not(self.at(EOF)) {
        body.push(self.parse_stmt())
      }
      cases.push({ condition: Some(test_expr), body })
    } else if self.eat(Default) {
      let _ = self.expect(Colon)
      let body : Array[@ast.Stmt] = []
      while not(self.at(Case)) &&
            not(self.at(Default)) &&
            not(self.at(RBrace)) &&
            not(self.at(EOF)) {
        body.push(self.parse_stmt())
      }
      cases.push({ condition: None, body })
    } else {
      let t = self.peek()
      raise Failure::Failure(
        "Expected case or default in switch at line \{t.loc.line}, col \{t.loc.col}",
      )
    }
  }
  let _ = self.expect(RBrace)
  SwitchStmt(discriminant, cases, tok.loc)
}

///|
fn Parser::parse_do_while_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Do)
  let body = self.parse_stmt()
  let _ = self.expect(While)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  self.eat_semicolon()
  DoWhileStmt(body, cond, tok.loc)
}

///|
fn Parser::parse_labeled_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.advance() // consume identifier
  let label : String = match tok.kind {
    Ident(name) => name
    _ =>
      raise Failure::Failure(
        "Expected label name at line \{tok.loc.line}, col \{tok.loc.col}",
      )
  }
  let _ = self.expect(Colon) // consume ':'
  let body = self.parse_stmt()
  LabeledStmt(label, body, tok.loc)
}

///|
fn Parser::parse_expr_stmt(self : Parser) -> @ast.Stmt raise Error {
  let loc = self.peek().loc
  let expr = self.parse_expr()
  self.eat_semicolon()
  ExprStmt(expr, loc)
}
