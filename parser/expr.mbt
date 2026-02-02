///|
fn Parser::parse_expr(self : Parser) -> @ast.Expr raise Error {
  self.parse_comma()
}

///|
fn Parser::parse_comma(self : Parser) -> @ast.Expr raise Error {
  let mut left = self.parse_assignment()
  while self.at(Comma) {
    let loc = self.advance().loc
    let right = self.parse_assignment()
    left = Comma(left, right, loc)
  }
  left
}

///|
fn Parser::parse_assignment(self : Parser) -> @ast.Expr raise Error {
  // Check for single-param arrow: ident => ...
  match self.peek_kind() {
    Ident(name) =>
      match self.peek_kind_at(1) {
        Arrow => {
          let loc = self.advance().loc // consume ident
          let _ = self.advance() // consume =>
          let body = self.parse_arrow_body()
          return ArrowFunc([name], body, loc)
        }
        _ => ()
      }
    _ => ()
  }
  let expr = self.parse_ternary()
  // Check for multi-param arrow: (a, b) => ... parsed as Grouping/Comma/Ident then Arrow
  match self.peek_kind() {
    Arrow => {
      let loc = self.advance().loc // consume =>
      let params = extract_arrow_params(expr)
      let body = self.parse_arrow_body()
      return ArrowFunc(params, body, loc)
    }
    _ => ()
  }
  // Plain assignment
  if self.at(Assign) {
    let loc = self.advance().loc
    let value = self.parse_assignment()
    match expr {
      Ident(name, _) => return Assign(name, value, loc)
      Member(obj, prop, _) => return MemberAssign(obj, prop, value, loc)
      ComputedMember(obj, key, _) => return ComputedAssign(obj, key, value, loc)
      _ =>
        raise Failure::Failure(
          "Invalid assignment target at line \{loc.line}, col \{loc.col}",
        )
    }
  }
  // Compound assignment
  let compound_op : @ast.CompoundOp? = match self.peek_kind() {
    PlusAssign => Some(AddAssign)
    MinusAssign => Some(SubAssign)
    StarAssign => Some(MulAssign)
    SlashAssign => Some(DivAssign)
    PercentAssign => Some(ModAssign)
    BitAndAssign => Some(@ast.BitAndAssign)
    BitOrAssign => Some(@ast.BitOrAssign)
    BitXorAssign => Some(@ast.BitXorAssign)
    LShiftAssign => Some(@ast.LShiftAssign)
    RShiftAssign => Some(@ast.RShiftAssign)
    URShiftAssign => Some(@ast.URShiftAssign)
    _ => None
  }
  match compound_op {
    Some(op) => {
      let loc = self.advance().loc
      let value = self.parse_assignment()
      CompoundAssign(op, expr, value, loc)
    }
    None => expr
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
  let mut left = self.parse_bitwise_or()
  while self.at(And) {
    let loc = self.advance().loc
    let right = self.parse_bitwise_or()
    left = Binary(@ast.And, left, right, loc)
  }
  left
}

///|
fn Parser::parse_bitwise_or(self : Parser) -> @ast.Expr raise Error {
  let mut left = self.parse_bitwise_xor()
  while self.at(BitOr) {
    let loc = self.advance().loc
    let right = self.parse_bitwise_xor()
    left = Binary(@ast.BitOr, left, right, loc)
  }
  left
}

///|
fn Parser::parse_bitwise_xor(self : Parser) -> @ast.Expr raise Error {
  let mut left = self.parse_bitwise_and()
  while self.at(BitXor) {
    let loc = self.advance().loc
    let right = self.parse_bitwise_and()
    left = Binary(@ast.BitXor, left, right, loc)
  }
  left
}

///|
fn Parser::parse_bitwise_and(self : Parser) -> @ast.Expr raise Error {
  let mut left = self.parse_equality()
  while self.at(BitAnd) {
    let loc = self.advance().loc
    let right = self.parse_equality()
    left = Binary(@ast.BitAnd, left, right, loc)
  }
  left
}

///|
fn Parser::parse_equality(self : Parser) -> @ast.Expr raise Error {
  let mut left = self.parse_relational()
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
        let right = self.parse_relational()
        left = Binary(op, left, right, loc)
      }
      None => break
    }
  }
  left
}

///|
fn Parser::parse_relational(self : Parser) -> @ast.Expr raise Error {
  let mut left = self.parse_shift()
  while true {
    let op : @ast.BinOp? = match self.peek_kind() {
      Lt => Some(@ast.Lt)
      Gt => Some(@ast.Gt)
      LtEq => Some(@ast.LtEq)
      GtEq => Some(@ast.GtEq)
      In => Some(@ast.In)
      Instanceof => Some(@ast.Instanceof)
      _ => None
    }
    match op {
      Some(op) => {
        let loc = self.advance().loc
        let right = self.parse_shift()
        left = Binary(op, left, right, loc)
      }
      None => break
    }
  }
  left
}

///|
fn Parser::parse_shift(self : Parser) -> @ast.Expr raise Error {
  let mut left = self.parse_additive()
  while true {
    let op : @ast.BinOp? = match self.peek_kind() {
      LShift => Some(@ast.LShift)
      RShift => Some(@ast.RShift)
      URShift => Some(@ast.URShift)
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
    Void => {
      let loc = self.advance().loc
      let expr = self.parse_unary()
      Unary(@ast.Void, expr, loc)
    }
    Delete => {
      let loc = self.advance().loc
      let expr = self.parse_unary()
      Unary(@ast.Delete, expr, loc)
    }
    Tilde => {
      let loc = self.advance().loc
      let expr = self.parse_unary()
      Unary(@ast.BitNot, expr, loc)
    }
    PlusPlus => {
      let loc = self.advance().loc
      let expr = self.parse_unary()
      UpdateExpr(@ast.Increment, expr, true, loc)
    }
    MinusMinus => {
      let loc = self.advance().loc
      let expr = self.parse_unary()
      UpdateExpr(@ast.Decrement, expr, true, loc)
    }
    _ => self.parse_postfix()
  }
}

///|
fn Parser::parse_postfix(self : Parser) -> @ast.Expr raise Error {
  let expr = self.parse_call()
  match self.peek_kind() {
    PlusPlus => {
      let loc = self.advance().loc
      UpdateExpr(@ast.Increment, expr, false, loc)
    }
    MinusMinus => {
      let loc = self.advance().loc
      UpdateExpr(@ast.Decrement, expr, false, loc)
    }
    _ => expr
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
        args.push(self.parse_assignment())
        while self.eat(Comma) {
          args.push(self.parse_assignment())
        }
      }
      let _ = self.expect(RParen)
      expr = Call(expr, args, loc)
    } else if self.at(Dot) {
      let _ = self.advance()
      let name = self.expect_ident()
      let loc = self.peek().loc
      expr = Member(expr, name, loc)
    } else if self.at(LBracket) {
      let loc = self.advance().loc
      let key = self.parse_expr()
      let _ = self.expect(RBracket)
      expr = ComputedMember(expr, key, loc)
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
    This => {
      self.pos += 1
      ThisExpr(tok.loc)
    }
    New => self.parse_new_expr()
    LParen => {
      self.pos += 1
      // Check for empty parens arrow: () =>
      if self.at(RParen) {
        let _ = self.advance() // consume )
        match self.peek_kind() {
          Arrow => {
            let _ = self.advance() // consume =>
            let body = self.parse_arrow_body()
            return ArrowFunc([], body, tok.loc)
          }
          _ =>
            raise Failure::Failure(
              "Unexpected ) at line \{tok.loc.line}, col \{tok.loc.col}",
            )
        }
      }
      let expr = self.parse_expr()
      let _ = self.expect(RParen)
      Grouping(expr, tok.loc)
    }
    LBracket => self.parse_array_literal()
    LBrace => self.parse_object_literal()
    Function => self.parse_func_expr()
    NoSubTemplate(s) => {
      self.pos += 1
      StringLit(s, tok.loc)
    }
    TemplateHead(first_str) => {
      self.pos += 1
      let strings : Array[String] = [first_str]
      let exprs : Array[@ast.Expr] = []
      while true {
        exprs.push(self.parse_expr())
        match self.peek_kind() {
          TemplateMiddle(s) => {
            self.pos += 1
            strings.push(s)
          }
          TemplateTail(s) => {
            self.pos += 1
            strings.push(s)
            break
          }
          _ => {
            let t = self.peek()
            raise Failure::Failure(
              "Expected template continuation, got \{t.kind} at line \{t.loc.line}, col \{t.loc.col}",
            )
          }
        }
      }
      TemplateLit(strings, exprs, tok.loc)
    }
    _ =>
      raise Failure::Failure(
        "Unexpected token \{tok.kind} at line \{tok.loc.line}, col \{tok.loc.col}",
      )
  }
}

///|
fn Parser::parse_new_expr(self : Parser) -> @ast.Expr raise Error {
  let loc = self.advance().loc // consume 'new'
  // Parse constructor — allow member access (new Foo.Bar())
  let mut callee = self.parse_primary()
  while self.at(Dot) {
    let _ = self.advance()
    let name = self.expect_ident()
    let mloc = self.peek().loc
    callee = Member(callee, name, mloc)
  }
  // Optional argument list
  let args : Array[@ast.Expr] = []
  if self.at(LParen) {
    let _ = self.advance()
    if not(self.at(RParen)) {
      args.push(self.parse_assignment())
      while self.eat(Comma) {
        args.push(self.parse_assignment())
      }
    }
    let _ = self.expect(RParen)

  }
  NewExpr(callee, args, loc)
}

///|
fn Parser::parse_array_literal(self : Parser) -> @ast.Expr raise Error {
  let loc = self.advance().loc // consume '['
  let elements : Array[@ast.Expr] = []
  while not(self.at(RBracket)) && not(self.at(EOF)) {
    elements.push(self.parse_assignment())
    if not(self.at(RBracket)) {
      let _ = self.expect(Comma)

    }
  }
  let _ = self.expect(RBracket)
  ArrayLit(elements, loc)
}

///|
fn Parser::parse_object_literal(self : Parser) -> @ast.Expr raise Error {
  let loc = self.advance().loc // consume '{'
  let props : Array[@ast.Property] = []
  while not(self.at(RBrace)) && not(self.at(EOF)) {
    let key : String = match self.peek_kind() {
      Ident(name) => {
        self.pos += 1
        name
      }
      String_(s) => {
        self.pos += 1
        s
      }
      Number(n) => {
        self.pos += 1
        let i = n.to_int()
        if i.to_double() == n {
          i.to_string()
        } else {
          n.to_string()
        }
      }
      _ => {
        let t = self.peek()
        raise Failure::Failure(
          "Expected property name, got \{t.kind} at line \{t.loc.line}, col \{t.loc.col}",
        )
      }
    }
    let _ = self.expect(Colon)
    let value = self.parse_assignment()
    props.push({ key, value })
    if not(self.at(RBrace)) {
      let _ = self.expect(Comma)

    }
  }
  let _ = self.expect(RBrace)
  ObjectLit(props, loc)
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

///|
fn Parser::parse_arrow_body(self : Parser) -> Array[@ast.Stmt] raise Error {
  if self.at(LBrace) {
    self.parse_block_body()
  } else {
    let expr = self.parse_assignment()
    let loc = @token.Loc::default()
    [ReturnStmt(Some(expr), loc)]
  }
}

///|
fn extract_arrow_params(expr : @ast.Expr) -> Array[String] raise Error {
  match expr {
    Ident(name, _) => [name]
    Grouping(inner, _) => extract_arrow_params(inner)
    Comma(left, right, _) => {
      let params = extract_arrow_params(left)
      let right_params = extract_arrow_params(right)
      for p in right_params {
        params.push(p)
      }
      params
    }
    _ => raise Failure::Failure("Invalid arrow function parameter list")
  }
}
