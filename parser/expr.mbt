///|
fn Parser::parse_expr(self : Parser) -> @ast.Expr raise Error {
  self.parse_assignment()
}

///|
fn Parser::parse_assignment(self : Parser) -> @ast.Expr raise Error {
  let expr = self.parse_ternary()
  if self.at(Assign) {
    let loc = self.advance().loc
    let value = self.parse_assignment()
    match expr {
      Ident(name, _) => Assign(name, value, loc)
      _ =>
        raise Failure::Failure(
          "Invalid assignment target at line \{loc.line}, col \{loc.col}",
        )
    }
  } else {
    expr
  }
}

///|
fn Parser::parse_ternary(self : Parser) -> @ast.Expr raise Error {
  let expr = self.parse_or()
  if self.at(Question) {
    let loc = self.advance().loc
    let then_expr = self.parse_assignment()
    let _ = self.expect(Colon)
    let else_expr = self.parse_assignment()
    Ternary(expr, then_expr, else_expr, loc)
  } else {
    expr
  }
}

///|
fn Parser::parse_or(self : Parser) -> @ast.Expr raise Error {
  let mut left = self.parse_and()
  while self.at(Or) {
    let loc = self.advance().loc
    let right = self.parse_and()
    left = Binary(@ast.Or, left, right, loc)
  }
  left
}

///|
fn Parser::parse_and(self : Parser) -> @ast.Expr raise Error {
  let mut left = self.parse_equality()
  while self.at(And) {
    let loc = self.advance().loc
    let right = self.parse_equality()
    left = Binary(@ast.And, left, right, loc)
  }
  left
}

///|
fn Parser::parse_equality(self : Parser) -> @ast.Expr raise Error {
  let mut left = self.parse_comparison()
  while true {
    let op : @ast.BinOp? = match self.peek_kind() {
      EqEq => Some(@ast.EqEq)
      EqEqEq => Some(@ast.EqEqEq)
      BangEq => Some(@ast.NotEq)
      BangEqEq => Some(@ast.NotEqEq)
      _ => None
    }
    match op {
      Some(op) => {
        let loc = self.advance().loc
        let right = self.parse_comparison()
        left = Binary(op, left, right, loc)
      }
      None => break
    }
  }
  left
}

///|
fn Parser::parse_comparison(self : Parser) -> @ast.Expr raise Error {
  let mut left = self.parse_additive()
  while true {
    let op : @ast.BinOp? = match self.peek_kind() {
      Lt => Some(@ast.Lt)
      Gt => Some(@ast.Gt)
      LtEq => Some(@ast.LtEq)
      GtEq => Some(@ast.GtEq)
      _ => None
    }
    match op {
      Some(op) => {
        let loc = self.advance().loc
        let right = self.parse_additive()
        left = Binary(op, left, right, loc)
      }
      None => break
    }
  }
  left
}

///|
fn Parser::parse_additive(self : Parser) -> @ast.Expr raise Error {
  let mut left = self.parse_multiplicative()
  while true {
    let op : @ast.BinOp? = match self.peek_kind() {
      Plus => Some(@ast.Add)
      Minus => Some(@ast.Sub)
      _ => None
    }
    match op {
      Some(op) => {
        let loc = self.advance().loc
        let right = self.parse_multiplicative()
        left = Binary(op, left, right, loc)
      }
      None => break
    }
  }
  left
}

///|
fn Parser::parse_multiplicative(self : Parser) -> @ast.Expr raise Error {
  let mut left = self.parse_unary()
  while true {
    let op : @ast.BinOp? = match self.peek_kind() {
      Star => Some(@ast.Mul)
      Slash => Some(@ast.Div)
      Percent => Some(@ast.Mod)
      _ => None
    }
    match op {
      Some(op) => {
        let loc = self.advance().loc
        let right = self.parse_unary()
        left = Binary(op, left, right, loc)
      }
      None => break
    }
  }
  left
}

///|
fn Parser::parse_unary(self : Parser) -> @ast.Expr raise Error {
  match self.peek_kind() {
    Minus => {
      let loc = self.advance().loc
      let expr = self.parse_unary()
      Unary(@ast.Neg, expr, loc)
    }
    Bang => {
      let loc = self.advance().loc
      let expr = self.parse_unary()
      Unary(@ast.Not, expr, loc)
    }
    Typeof => {
      let loc = self.advance().loc
      let expr = self.parse_unary()
      Unary(@ast.Typeof, expr, loc)
    }
    _ => self.parse_call()
  }
}

///|
fn Parser::parse_call(self : Parser) -> @ast.Expr raise Error {
  let mut expr = self.parse_primary()
  while true {
    if self.at(LParen) {
      let loc = self.advance().loc
      let args : Array[@ast.Expr] = []
      if not(self.at(RParen)) {
        args.push(self.parse_expr())
        while self.eat(Comma) {
          args.push(self.parse_expr())
        }
      }
      let _ = self.expect(RParen)
      expr = Call(expr, args, loc)
    } else if self.at(Dot) {
      let _ = self.advance()
      let name = self.expect_ident()
      let loc = self.peek().loc
      expr = Member(expr, name, loc)
    } else {
      break
    }
  }
  expr
}

///|
fn Parser::parse_primary(self : Parser) -> @ast.Expr raise Error {
  let tok = self.peek()
  match tok.kind {
    Number(n) => {
      self.pos += 1
      NumberLit(n, tok.loc)
    }
    String_(s) => {
      self.pos += 1
      StringLit(s, tok.loc)
    }
    True => {
      self.pos += 1
      BoolLit(true, tok.loc)
    }
    False => {
      self.pos += 1
      BoolLit(false, tok.loc)
    }
    Null => {
      self.pos += 1
      NullLit(tok.loc)
    }
    Undefined => {
      self.pos += 1
      UndefinedLit(tok.loc)
    }
    Ident(name) => {
      self.pos += 1
      Ident(name, tok.loc)
    }
    LParen => {
      self.pos += 1
      let expr = self.parse_expr()
      let _ = self.expect(RParen)
      Grouping(expr, tok.loc)
    }
    Function => self.parse_func_expr()
    _ =>
      raise Failure::Failure(
        "Unexpected token \{tok.kind} at line \{tok.loc.line}, col \{tok.loc.col}",
      )
  }
}

///|
fn Parser::parse_func_expr(self : Parser) -> @ast.Expr raise Error {
  let tok = self.expect(Function)
  // Optional name
  let name : String? = match self.peek_kind() {
    Ident(n) => {
      self.pos += 1
      Some(n)
    }
    _ => None
  }
  let params = self.parse_params()
  let body = self.parse_block_body()
  FuncExpr(name, params, body, tok.loc)
}
