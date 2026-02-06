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
  // Try to parse arrow function with extended params: (a = 1, ...rest) => ...
  // We detect LParen and tentatively try parse_params_ext
  if self.at(LParen) {
    let saved_pos = self.pos
    // Try extended params parse
    let try_ext : (Array[@ast.Param], String?)? = Some(self.parse_params_ext()) catch {
      _ => None
    }
    match try_ext {
      Some((ext_params, rest_param)) =>
        if self.at(Arrow) {
          // Check if this has defaults or rest
          let has_ext = rest_param is Some(_) ||
            ext_params.iter().any(fn(p) { p.default_val is Some(_) || p.pattern is Some(_) })
          if has_ext {
            let loc = self.advance().loc // consume =>
            let body = self.parse_arrow_body()
            return ArrowFuncExt(ext_params, rest_param, body, loc)
          } else {
            // Simple arrow func, extract names
            let loc = self.advance().loc // consume =>
            let param_names = ext_params.map(fn(p) { p.name })
            let body = self.parse_arrow_body()
            return ArrowFunc(param_names, body, loc)
          }
        } else {
          // Not an arrow function, backtrack
          self.pos = saved_pos
        }
      None => self.pos = saved_pos
    }
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
      ArrayLit(_, _) | ObjectLit(_, _) => {
        let pattern = expr_to_pattern(expr)
        return DestructureAssign(pattern, value, loc)
      }
      _ =>
        raise @errors.SyntaxError(
          message="Invalid assignment target at line \{loc.line}, col \{loc.col}",
        )
    }
  }
  // Compound assignment
  let compound_op : @ast.CompoundOp? = match self.peek_kind() {
    PlusAssign => Some(AddAssign)
    MinusAssign => Some(SubAssign)
    StarAssign => Some(MulAssign)
    StarStarAssign => Some(@ast.ExpAssign)
    SlashAssign => Some(DivAssign)
    PercentAssign => Some(ModAssign)
    BitAndAssign => Some(@ast.BitAndAssign)
    BitOrAssign => Some(@ast.BitOrAssign)
    BitXorAssign => Some(@ast.BitXorAssign)
    LShiftAssign => Some(@ast.LShiftAssign)
    RShiftAssign => Some(@ast.RShiftAssign)
    URShiftAssign => Some(@ast.URShiftAssign)
    AndAssign => Some(@ast.LogicalAndAssign)
    OrAssign => Some(@ast.LogicalOrAssign)
    NullishAssign => Some(@ast.NullishAssign)
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
  let mut seen_nullish = false
  let mut seen_or = false
  while self.at(Or) || self.at(QuestionQuestion) {
    let is_nullish = self.at(QuestionQuestion)
    // Check for illegal mixing of ?? with ||
    if is_nullish && seen_or {
      raise @errors.SyntaxError(
        message="Cannot mix nullish coalescing (??) with logical OR (||) without parentheses",
      )
    }
    if not(is_nullish) && seen_nullish {
      raise @errors.SyntaxError(
        message="Cannot mix logical OR (||) with nullish coalescing (??) without parentheses",
      )
    }
    if is_nullish {
      seen_nullish = true
      // Check if left contains && - this means "a && b ?? c" pattern
      match left {
        Binary(@ast.And, _, _, _) =>
          raise @errors.SyntaxError(
            message="Cannot mix logical AND (&&) with nullish coalescing (??) without parentheses",
          )
        _ => ()
      }
    } else {
      seen_or = true
    }
    let loc = self.advance().loc
    let right = self.parse_and()
    // Also check if right contains && when using ??
    if is_nullish {
      match right {
        Binary(@ast.And, _, _, _) =>
          raise @errors.SyntaxError(
            message="Cannot mix nullish coalescing (??) with logical AND (&&) without parentheses",
          )
        _ => ()
      }
    }
    if is_nullish {
      left = Binary(@ast.NullishCoalesce, left, right, loc)
    } else {
      left = Binary(@ast.Or, left, right, loc)
    }
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
  let mut left = self.parse_exponentiation()
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
        let right = self.parse_exponentiation()
        left = Binary(op, left, right, loc)
      }
      None => break
    }
  }
  left
}

///|
fn Parser::parse_exponentiation(self : Parser) -> @ast.Expr raise Error {
  let base = self.parse_unary()
  if self.at(StarStar) {
    // Check for unary operator on LHS - this is a syntax error in JS
    // Per ES spec, all unary operators (not just -, !, ~) are disallowed
    match base {
      Unary(op, _, _) =>
        match op {
          @ast.Neg
          | @ast.Pos
          | @ast.Not
          | @ast.BitNot
          | @ast.Typeof
          | @ast.Void
          | @ast.Delete =>
            raise @errors.SyntaxError(
              message="Unary operator used immediately before exponentiation expression. Parentheses must be used to disambiguate.",
            )
        }
      _ => ()
    }
    let loc = self.advance().loc
    // Right-associative: parse right side with exponentiation precedence
    let exp = self.parse_exponentiation()
    Binary(@ast.Exp, base, exp, loc)
  } else {
    base
  }
}

///|
fn Parser::parse_unary(self : Parser) -> @ast.Expr raise Error {
  match self.peek_kind() {
    Plus => {
      let loc = self.advance().loc
      let expr = self.parse_unary()
      Unary(@ast.Pos, expr, loc)
    }
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
  // Track if we're in an optional chain - once we see ?., all subsequent
  // member/computed/call accesses in the chain should short-circuit
  let mut in_optional_chain = false
  while true {
    if self.at(LParen) {
      let loc = self.advance().loc
      let args : Array[@ast.Expr] = []
      if not(self.at(RParen)) {
        if self.at(DotDotDot) {
          let sloc = self.advance().loc
          args.push(SpreadExpr(self.parse_assignment(), sloc))
        } else {
          args.push(self.parse_assignment())
        }
        while self.eat(Comma) {
          // Trailing comma support: if we see ) after comma, stop
          if self.at(RParen) {
            break
          }
          if self.at(DotDotDot) {
            let sloc = self.advance().loc
            args.push(SpreadExpr(self.parse_assignment(), sloc))
          } else {
            args.push(self.parse_assignment())
          }
        }
      }
      let _ = self.expect(RParen)
      if in_optional_chain {
        expr = OptionalCall(expr, args, loc)
      } else {
        expr = Call(expr, args, loc)
      }
    } else if self.at(Dot) {
      let _ = self.advance()
      let name = self.expect_ident_name()
      let loc = self.peek().loc
      if in_optional_chain {
        expr = OptionalMember(expr, name, loc)
      } else {
        expr = Member(expr, name, loc)
      }
    } else if self.at(LBracket) {
      let loc = self.advance().loc
      let key = self.parse_expr()
      let _ = self.expect(RBracket)
      if in_optional_chain {
        expr = OptionalComputedMember(expr, key, loc)
      } else {
        expr = ComputedMember(expr, key, loc)
      }
    } else if self.at(QuestionDot) {
      // Optional chaining: ?. - start/continue optional chain
      in_optional_chain = true
      let loc = self.advance().loc
      if self.at(LParen) {
        // Optional call: obj?.(args)
        let _ = self.advance()
        let args : Array[@ast.Expr] = []
        if not(self.at(RParen)) {
          if self.at(DotDotDot) {
            let sloc = self.advance().loc
            args.push(SpreadExpr(self.parse_assignment(), sloc))
          } else {
            args.push(self.parse_assignment())
          }
          while self.eat(Comma) {
            if self.at(RParen) { break }
            if self.at(DotDotDot) {
              let sloc = self.advance().loc
              args.push(SpreadExpr(self.parse_assignment(), sloc))
            } else {
              args.push(self.parse_assignment())
            }
          }
        }
        let _ = self.expect(RParen)
        expr = OptionalCall(expr, args, loc)
      } else if self.at(LBracket) {
        // Optional computed member: obj?.[expr]
        let _ = self.advance()
        let key = self.parse_expr()
        let _ = self.expect(RBracket)
        expr = OptionalComputedMember(expr, key, loc)
      } else {
        // Optional member: obj?.prop
        let name = self.expect_ident_name()
        expr = OptionalMember(expr, name, loc)
      }
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
            raise @errors.SyntaxError(
              message="Unexpected ) at line \{tok.loc.line}, col \{tok.loc.col}",
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
    Class => self.parse_class_expr()
    Super => self.parse_super_expr()
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
            raise @errors.SyntaxError(
              message="Expected template continuation, got \{t.kind} at line \{t.loc.line}, col \{t.loc.col}",
            )
          }
        }
      }
      TemplateLit(strings, exprs, tok.loc)
    }
    Regex(pattern, flags) => {
      self.pos += 1
      RegexLit(pattern, flags, tok.loc)
    }
    _ =>
      raise @errors.SyntaxError(
        message="Unexpected token \{tok.kind} at line \{tok.loc.line}, col \{tok.loc.col}",
      )
  }
}

///|
fn Parser::parse_new_expr(self : Parser) -> @ast.Expr raise Error {
  let loc = self.advance().loc // consume 'new'
  // Check for new.target meta-property
  if self.at(Dot) {
    match self.peek_kind_at(1) {
      Ident("target") => {
        let _ = self.advance() // consume '.'
        let _ = self.advance() // consume 'target'
        return NewTargetExpr(loc)
      }
      _ => ()
    }
  }
  // Parse constructor — allow member access (new Foo.Bar())
  let mut callee = self.parse_primary()
  while self.at(Dot) {
    let _ = self.advance()
    let name = self.expect_ident_name()
    let mloc = self.peek().loc
    callee = Member(callee, name, mloc)
  }
  // Optional argument list
  let args : Array[@ast.Expr] = []
  if self.at(LParen) {
    let _ = self.advance()
    if not(self.at(RParen)) {
      if self.at(DotDotDot) {
        let sloc = self.advance().loc
        args.push(SpreadExpr(self.parse_assignment(), sloc))
      } else {
        args.push(self.parse_assignment())
      }
      while self.eat(Comma) {
        if self.at(RParen) { break }
        if self.at(DotDotDot) {
          let sloc = self.advance().loc
          args.push(SpreadExpr(self.parse_assignment(), sloc))
        } else {
          args.push(self.parse_assignment())
        }
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
    // Handle elisions: [1,,3] or [,,] - consecutive commas create undefined holes
    if self.at(Comma) {
      elements.push(UndefinedLit(self.peek().loc))
      let _ = self.advance() // consume comma
      continue
    }
    if self.at(DotDotDot) {
      let sloc = self.advance().loc
      elements.push(SpreadExpr(self.parse_assignment(), sloc))
    } else {
      elements.push(self.parse_assignment())
    }
    if not(self.at(RBracket)) {
      if self.at(Comma) {
        let _ = self.advance() // consume comma
      }
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
    // Check for spread property: { ...expr }
    if self.at(DotDotDot) {
      let spread_loc = self.advance().loc
      let expr = self.parse_assignment()
      props.push(
        {
          key: expr,
          value: UndefinedLit(spread_loc),
          kind: @ast.Spread,
          computed: false,
        },
      )
      if not(self.at(RBrace)) {
        if self.at(Comma) {
          let _ = self.advance()
        }
      }
      continue
    }
    // Check for getter/setter
    // Note: The lexer produces Get/Set tokens for "get"/"set" keywords.
    // We need to distinguish: { get foo() {} } (getter) vs { get: 42 } (property named "get")
    // Also handle: { get() {} } (method named "get")
    let prop_kind : @ast.PropKind = match self.peek_kind() {
      Get =>
        match self.peek_kind_at(1) {
          Ident(_) | String_(_) | Number(_) | LBracket => {
            // get <name>(...) - this is a getter
            self.pos += 1
            @ast.Get
          }
          _ => @ast.Init // get: value, get(), get} etc.
        }
      Set =>
        match self.peek_kind_at(1) {
          Ident(_) | String_(_) | Number(_) | LBracket => {
            // set <name>(...) - this is a setter
            self.pos += 1
            @ast.Set
          }
          _ => @ast.Init // set: value, set(), set} etc.
        }
      _ => @ast.Init
    }
    // Parse the key - can be identifier, string, number, or computed [expr]
    // Track if key was an identifier (needed for shorthand validation)
    let (key_expr, key_name, computed, is_ident_key) : (
      @ast.Expr,
      String,
      Bool,
      Bool,
    ) = match self.peek_kind() {
      Ident(name) => {
        let kloc = self.advance().loc
        (StringLit(name, kloc), name, false, true)
      }
      String_(s) => {
        let kloc = self.advance().loc
        (StringLit(s, kloc), s, false, false)
      }
      Number(n) => {
        let kloc = self.advance().loc
        let i = n.to_int()
        let name = if i.to_double() == n {
          i.to_string()
        } else {
          n.to_string()
        }
        (StringLit(name, kloc), name, false, false)
      }
      LBracket => {
        // Computed property name: [expr]
        let _ = self.advance() // consume '['
        let expr = self.parse_assignment()
        let _ = self.expect(RBracket)
        (expr, "", true, false)
      }
      _ => {
        // Keywords can be used as property names in object literals
        let kw_name : String? = match self.peek_kind() {
          Get => Some("get")
          Set => Some("set")
          Let => Some("let")
          Const => Some("const")
          Var => Some("var")
          Function => Some("function")
          Return => Some("return")
          If => Some("if")
          Else => Some("else")
          While => Some("while")
          For => Some("for")
          Break => Some("break")
          Continue => Some("continue")
          True => Some("true")
          False => Some("false")
          Null => Some("null")
          Undefined => Some("undefined")
          Typeof => Some("typeof")
          Throw => Some("throw")
          Try => Some("try")
          Catch => Some("catch")
          Finally => Some("finally")
          New => Some("new")
          This => Some("this")
          Switch => Some("switch")
          Case => Some("case")
          Default => Some("default")
          Void => Some("void")
          Delete => Some("delete")
          Do => Some("do")
          In => Some("in")
          Instanceof => Some("instanceof")
          Of => Some("of")
          Class => Some("class")
          Extends => Some("extends")
          Super => Some("super")
          Static => Some("static")
          _ => None
        }
        match kw_name {
          Some(name) => {
            let kloc = self.advance().loc
            (StringLit(name, kloc), name, false, true)
          }
          None => {
            let t = self.peek()
            raise @errors.SyntaxError(
              message="Expected property name, got \{t.kind} at line \{t.loc.line}, col \{t.loc.col}",
            )
          }
        }
      }
    }
    // Check for method shorthand, getter, or setter: identifier followed by (
    if self.at(LParen) {
      // Method shorthand or getter/setter
      let mloc = self.peek().loc
      let params = self.parse_params()
      // Validate getter/setter arity
      match prop_kind {
        @ast.Get =>
          if params.length() != 0 {
            raise @errors.SyntaxError(
              message="Getter must have exactly zero parameters",
            )
          }
        @ast.Set =>
          if params.length() != 1 {
            raise @errors.SyntaxError(
              message="Setter must have exactly one parameter",
            )
          }
        @ast.Init | @ast.Spread => ()
      }
      let body = self.parse_block_body()
      let func_data : @ast.Expr = FuncExpr(
        if computed {
          None
        } else {
          Some(key_name)
        },
        params,
        body,
        mloc,
      )
      props.push({ key: key_expr, value: func_data, kind: prop_kind, computed })
    } else if self.at(Colon) {
      // Normal property
      let _ = self.advance() // consume ':'
      let value = self.parse_assignment()
      props.push({ key: key_expr, value, kind: @ast.Init, computed })
    } else if self.at(Comma) || self.at(RBrace) {
      // Shorthand property: { x } => { x: x }
      // Only identifier keys can use shorthand syntax
      if not(is_ident_key) {
        let t = self.peek()
        raise @errors.SyntaxError(
          message="Shorthand properties require identifier keys at line \{t.loc.line}, col \{t.loc.col}",
        )
      }
      let value : @ast.Expr = Ident(key_name, loc)
      props.push({ key: key_expr, value, kind: @ast.Init, computed: false })
    } else {
      let t = self.peek()
      raise @errors.SyntaxError(
        message="Expected ':' or '(' in object literal, got \{t.kind} at line \{t.loc.line}, col \{t.loc.col}",
      )
    }
    if not(self.at(RBrace)) {
      // Allow trailing comma
      if self.at(Comma) {
        let _ = self.advance()

      }
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
  let saved_pos = self.pos
  let params = self.parse_params() catch {
    Failure::Failure(msg) =>
      if msg == "REST_PARAM_FOUND" || msg == "DEFAULT_PARAM_FOUND" || msg == "DESTRUCTURE_PARAM_FOUND" {
        self.pos = saved_pos
        let (ext_params, rest_param) = self.parse_params_ext()
        let body = self.parse_block_body()
        return FuncExprExt(name, ext_params, rest_param, body, tok.loc)
      } else {
        raise @errors.SyntaxError(message=msg)
      }
    e => raise e
  }
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
    _ =>
      raise @errors.SyntaxError(message="Invalid arrow function parameter list")
  }
}

///|
fn expr_to_pattern(expr : @ast.Expr) -> @ast.Pattern raise Error {
  match expr {
    Ident(name, _) => IdentPat(name)
    ArrayLit(elements, _) => {
      let pats : Array[@ast.Pattern?] = []
      let mut rest : @ast.Pattern? = None
      for elem in elements {
        match elem {
          SpreadExpr(inner, _) => rest = Some(expr_to_pattern(inner))
          _ => pats.push(Some(expr_to_pattern(elem)))
        }
      }
      ArrayPat(pats, rest)
    }
    ObjectLit(props, _) => {
      let prop_pats : Array[@ast.PropPat] = []
      let rest : @ast.Pattern? = None
      for prop in props {
        // key: value => { key, value: Pattern, default_val }
        let pat = expr_to_pattern(prop.value)
        // Extract string key from the key expression
        let key_str : String = match prop.key {
          StringLit(s, _) => s
          Ident(s, _) => s
          _ =>
            raise @errors.SyntaxError(
              message="Invalid key in destructuring pattern",
            )
        }
        prop_pats.push({ key: key_str, value: pat, default_val: None })
      }
      ObjectPat(prop_pats, rest)
    }
    Assign(name, _default_expr, _) =>
      // Handle default values in destructuring: { x = 5 } or [a = 1]
      // This shouldn't appear in normal array/object expressions, but
      // the pattern `{x = 5} = obj` would need special parsing.
      // For now, treat as ident pattern (name is the binding)
      IdentPat(name)
    _ => raise @errors.SyntaxError(message="Invalid destructuring pattern")
  }
}

///|
fn Parser::parse_class_expr(self : Parser) -> @ast.Expr raise Error {
  let tok = self.expect(Class)
  // Optional name
  let name : String? = match self.peek_kind() {
    Ident(n) => {
      self.pos += 1
      Some(n)
    }
    _ => None
  }
  // Optional extends clause
  let superclass : @ast.Expr? = if self.eat(Extends) {
    Some(self.parse_class_heritage())
  } else {
    None
  }
  let methods = self.parse_class_body()
  ClassExpr(name, superclass, methods, tok.loc)
}

///|
/// Parse class heritage (superclass expression)
fn Parser::parse_class_heritage(self : Parser) -> @ast.Expr raise Error {
  // Parse the superclass expression - can be an identifier or member expression
  let mut expr = self.parse_primary()
  while self.at(Dot) {
    let _ = self.advance()
    let prop = self.expect_ident_name()
    let loc = self.peek().loc
    expr = Member(expr, prop, loc)
  }
  expr
}

///|
/// Parse class body (methods and properties)
fn Parser::parse_class_body(
  self : Parser,
) -> Array[@ast.ClassMethod] raise Error {
  let _ = self.expect(LBrace)
  let methods : Array[@ast.ClassMethod] = []
  while not(self.at(RBrace)) && not(self.at(EOF)) {
    // Skip semicolons (allowed in class bodies)
    if self.at(Semicolon) {
      let _ = self.advance()
      continue
    }
    methods.push(self.parse_class_method())
  }
  let _ = self.expect(RBrace)
  methods
}

///|
/// Parse a class method
fn Parser::parse_class_method(self : Parser) -> @ast.ClassMethod raise Error {
  // Check for static modifier
  let is_static = self.eat(Static)
  // Check for getter/setter
  let mut method_kind : @ast.PropKind = @ast.Init
  match self.peek_kind() {
    Get =>
      match self.peek_kind_at(1) {
        Ident(_) | String_(_) | Number(_) | LBracket | LParen =>
          if not(self.at_kind_at(1, LParen)) {
            self.pos += 1
            method_kind = @ast.Get
          }
        _ => ()
      }
    Set =>
      match self.peek_kind_at(1) {
        Ident(_) | String_(_) | Number(_) | LBracket | LParen =>
          if not(self.at_kind_at(1, LParen)) {
            self.pos += 1
            method_kind = @ast.Set
          }
        _ => ()
      }
    _ => ()
  }
  // Parse method name (keywords can be used as method names)
  let (key_expr, computed) : (@ast.Expr, Bool) = match self.peek_kind() {
    Ident(name) => {
      let kloc = self.advance().loc
      (StringLit(name, kloc), false)
    }
    String_(s) => {
      let kloc = self.advance().loc
      (StringLit(s, kloc), false)
    }
    Number(n) => {
      let kloc = self.advance().loc
      let i = n.to_int()
      let name = if i.to_double() == n { i.to_string() } else { n.to_string() }
      (StringLit(name, kloc), false)
    }
    LBracket => {
      let _ = self.advance()
      let expr = self.parse_assignment()
      let _ = self.expect(RBracket)
      (expr, true)
    }
    _ => {
      // Keywords can be used as method names in classes
      let kw_name : String? = match self.peek_kind() {
        Get => Some("get")
        Set => Some("set")
        Let => Some("let")
        Const => Some("const")
        Var => Some("var")
        Function => Some("function")
        Return => Some("return")
        If => Some("if")
        Else => Some("else")
        While => Some("while")
        For => Some("for")
        Break => Some("break")
        Continue => Some("continue")
        True => Some("true")
        False => Some("false")
        Null => Some("null")
        Undefined => Some("undefined")
        Typeof => Some("typeof")
        Throw => Some("throw")
        Try => Some("try")
        Catch => Some("catch")
        Finally => Some("finally")
        New => Some("new")
        This => Some("this")
        Switch => Some("switch")
        Case => Some("case")
        Default => Some("default")
        Void => Some("void")
        Delete => Some("delete")
        Do => Some("do")
        In => Some("in")
        Instanceof => Some("instanceof")
        Of => Some("of")
        Class => Some("class")
        Extends => Some("extends")
        Super => Some("super")
        Static => Some("static")
        _ => None
      }
      match kw_name {
        Some(name) => {
          let kloc = self.advance().loc
          (StringLit(name, kloc), false)
        }
        None => {
          let t = self.peek()
          raise @errors.SyntaxError(
            message="Expected method name at line \{t.loc.line}, col \{t.loc.col}",
          )
        }
      }
    }
  }
  // Parse method parameters and body
  let mloc = self.peek().loc
  let saved_pos = self.pos
  let params = self.parse_params() catch {
    Failure::Failure(msg) =>
      if msg == "REST_PARAM_FOUND" || msg == "DEFAULT_PARAM_FOUND" || msg == "DESTRUCTURE_PARAM_FOUND" {
        self.pos = saved_pos
        let (ext_params, rest_param) = self.parse_params_ext()
        match method_kind {
          @ast.Get =>
            if ext_params.length() != 0 {
              raise @errors.SyntaxError(
                message="Getter must have exactly zero parameters",
              )
            }
          @ast.Set =>
            if ext_params.length() != 1 {
              raise @errors.SyntaxError(
                message="Setter must have exactly one parameter",
              )
            }
          @ast.Init | @ast.Spread => ()
        }
        let body = self.parse_block_body()
        let func_val : @ast.Expr = FuncExprExt(
          None,
          ext_params,
          rest_param,
          body,
          mloc,
        )
        return {
          key: key_expr,
          value: func_val,
          kind: method_kind,
          computed,
          is_static,
        }
      } else {
        raise @errors.SyntaxError(message=msg)
      }
    e => raise e
  }
  match method_kind {
    @ast.Get =>
      if params.length() != 0 {
        raise @errors.SyntaxError(
          message="Getter must have exactly zero parameters",
        )
      }
    @ast.Set =>
      if params.length() != 1 {
        raise @errors.SyntaxError(
          message="Setter must have exactly one parameter",
        )
      }
    @ast.Init | @ast.Spread => ()
  }
  let body = self.parse_block_body()
  let func_val : @ast.Expr = FuncExpr(None, params, body, mloc)
  { key: key_expr, value: func_val, kind: method_kind, computed, is_static }
}

///|
fn Parser::at_kind_at(
  self : Parser,
  offset : Int,
  kind : @token.TokenKind,
) -> Bool {
  self.peek_kind_at(offset) == kind
}

///|
/// Parse super expression (super call or super member access)
fn Parser::parse_super_expr(self : Parser) -> @ast.Expr raise Error {
  let tok = self.expect(Super)
  // Check what follows super
  if self.at(LParen) {
    // super(args) - super call
    let _ = self.advance()
    let args : Array[@ast.Expr] = []
    if not(self.at(RParen)) {
      if self.at(DotDotDot) {
        let sloc = self.advance().loc
        args.push(SpreadExpr(self.parse_assignment(), sloc))
      } else {
        args.push(self.parse_assignment())
      }
      while self.eat(Comma) {
        if self.at(RParen) { break }
        if self.at(DotDotDot) {
          let sloc = self.advance().loc
          args.push(SpreadExpr(self.parse_assignment(), sloc))
        } else {
          args.push(self.parse_assignment())
        }
      }
    }
    let _ = self.expect(RParen)
    SuperCall(args, tok.loc)
  } else if self.at(Dot) {
    // super.prop - super member access
    let _ = self.advance()
    let name = self.expect_ident_name()
    SuperMember(name, tok.loc)
  } else if self.at(LBracket) {
    // super[expr] - super computed member access
    let _ = self.advance()
    let key = self.parse_expr()
    let _ = self.expect(RBracket)
    SuperComputedMember(key, tok.loc)
  } else {
    raise @errors.SyntaxError(
      message="'super' keyword is only valid inside class constructor and method bodies at line \{tok.loc.line}, col \{tok.loc.col}",
    )
  }
}
