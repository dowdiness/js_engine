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
  // yield expression in generator context (very low precedence, near assignment)
  if self.at(Yield) && self.in_generator() {
    return self.parse_yield_expr()
  }
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
    Get | Set | From | As => {
      let name : String = match self.peek_kind() {
        Get => "get"
        Set => "set"
        From => "from"
        As => "as"
        _ => abort("unreachable")
      }
      match self.peek_kind_at(1) {
        Arrow => {
          let loc = self.advance().loc // consume keyword
          let _ = self.advance() // consume =>
          let body = self.parse_arrow_body()
          return ArrowFunc([name], body, loc)
        }
        _ => ()
      }
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
            ext_params
            .iter()
            .any(fn(p) { p.default_val is Some(_) || p.pattern is Some(_) })
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
      // Try simple params first, fall back to extended params for defaults/destructuring
      let simple_params : Array[String]? = Some(extract_arrow_params(expr)) catch {
        _ => None
      }
      match simple_params {
        Some(params) => {
          let body = self.parse_arrow_body()
          return ArrowFunc(params, body, loc)
        }
        None => {
          let (ext_params, rest_param) = expr_to_ext_arrow_params(expr)
          let body = self.parse_arrow_body()
          return ArrowFuncExt(ext_params, rest_param, body, loc)
        }
      }
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
    } else if self.peek_kind() is NoSubTemplate(_) ||
      self.peek_kind() is TemplateHead(_) {
      // Tagged template: tag`string` or tag`str${expr}str`
      let tloc = self.peek().loc
      match self.peek_kind() {
        NoSubTemplate(s) => {
          self.pos += 1
          expr = TaggedTemplate(expr, [s], [], tloc)
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
          expr = TaggedTemplate(expr, strings, exprs, tloc)
        }
        _ => ()
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
      // has_escape = true if the raw token contains escape sequences
      let has_escape = tok.raw.length() != s.length() + 2
      StringLit(s, has_escape, tok.loc)
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
    Get => {
      self.pos += 1
      Ident("get", tok.loc)
    }
    Set => {
      self.pos += 1
      Ident("set", tok.loc)
    }
    From => {
      self.pos += 1
      Ident("from", tok.loc)
    }
    As => {
      self.pos += 1
      Ident("as", tok.loc)
    }
    Of => {
      self.pos += 1
      Ident("of", tok.loc)
    }
    Yield =>
      // Outside generator context, yield is a valid identifier
      if not(self.in_generator()) {
        self.pos += 1
        Ident("yield", tok.loc)
      } else {
        raise @errors.SyntaxError(
          message="Unexpected yield in primary expression at line \{tok.loc.line}, col \{tok.loc.col}",
        )
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
      StringLit(s, false, tok.loc)
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
        let _ = self.advance()
        // consume comma
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
      props.push({
        key: expr,
        value: UndefinedLit(spread_loc),
        kind: @ast.Spread,
        computed: false,
      })
      if not(self.at(RBrace)) {
        if self.at(Comma) {
          let _ = self.advance()
        }
      }
      continue
    }
    // Check for generator method: { *gen() { yield 1; } }
    if self.at(Star) {
      let _ = self.advance() // consume '*'
      // Parse the method name
      let (gen_key_expr, gen_key_name, gen_computed) : (@ast.Expr, String, Bool) = match
        self.peek_kind() {
        Ident(name) => {
          let kloc = self.advance().loc
          (StringLit(name, false, kloc), name, false)
        }
        String_(s) => {
          let kloc = self.advance().loc
          (StringLit(s, false, kloc), s, false)
        }
        Number(n) => {
          let kloc = self.advance().loc
          let i = n.to_int()
          let name = if i.to_double() == n {
            i.to_string()
          } else {
            n.to_string()
          }
          (StringLit(name, false, kloc), name, false)
        }
        LBracket => {
          let _ = self.advance()
          let expr = self.parse_assignment()
          let _ = self.expect(RBracket)
          (expr, "", true)
        }
        _ => {
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
            Import => Some("import")
            Export => Some("export")
            From => Some("from")
            As => Some("as")
            Yield => Some("yield")
            _ => None
          }
          match kw_name {
            Some(name) => {
              let kloc = self.advance().loc
              (StringLit(name, false, kloc), name, false)
            }
            None => {
              let t = self.peek()
              raise @errors.SyntaxError(
                message="Expected method name after * at line \{t.loc.line}, col \{t.loc.col}",
              )
            }
          }
        }
      }
      // Parse generator method params and body
      let gen_mloc = self.peek().loc
      let gen_saved_pos = self.pos
      let gen_func_data : @ast.Expr = try {
        let params = self.parse_params()
        self.push_generator_context(true)
        let body = self.parse_block_body()
        self.pop_generator_context()
        @ast.Expr::GeneratorExpr(
          if gen_computed {
            None
          } else {
            Some(gen_key_name)
          },
          params,
          body,
          gen_mloc,
        )
      } catch {
        Failure::Failure(msg) =>
          if msg == "REST_PARAM_FOUND" ||
            msg == "DEFAULT_PARAM_FOUND" ||
            msg == "DESTRUCTURE_PARAM_FOUND" {
            self.pos = gen_saved_pos
            let (ext_params, rest_param) = self.parse_params_ext()
            self.push_generator_context(true)
            let body = self.parse_block_body()
            self.pop_generator_context()
            GeneratorExprExt(
              if gen_computed {
                None
              } else {
                Some(gen_key_name)
              },
              ext_params,
              rest_param,
              body,
              gen_mloc,
            )
          } else {
            raise @errors.SyntaxError(message=msg)
          }
        e => raise e
      }
      props.push({
        key: gen_key_expr,
        value: gen_func_data,
        kind: @ast.Init,
        computed: gen_computed,
      })
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
          Ident(_)
          | String_(_)
          | Number(_)
          | LBracket
          | Get
          | Set
          | From
          | As
          | Import
          | Export
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
          | True
          | False
          | Null
          | Undefined
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
          | Static => {
            // get <name>(...) - this is a getter
            self.pos += 1
            @ast.Get
          }
          _ => @ast.Init
        } // get: value, get(), get} etc.
      Set =>
        match self.peek_kind_at(1) {
          Ident(_)
          | String_(_)
          | Number(_)
          | LBracket
          | Get
          | Set
          | From
          | As
          | Import
          | Export
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
          | True
          | False
          | Null
          | Undefined
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
          | Static => {
            // set <name>(...) - this is a setter
            self.pos += 1
            @ast.Set
          }
          _ => @ast.Init
        } // set: value, set(), set} etc.
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
        (StringLit(name, false, kloc), name, false, true)
      }
      String_(s) => {
        let kloc = self.advance().loc
        (StringLit(s, false, kloc), s, false, false)
      }
      Number(n) => {
        let kloc = self.advance().loc
        let i = n.to_int()
        let name = if i.to_double() == n {
          i.to_string()
        } else {
          n.to_string()
        }
        (StringLit(name, false, kloc), name, false, false)
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
          Import => Some("import")
          Export => Some("export")
          From => Some("from")
          As => Some("as")
          Yield => Some("yield")
          _ => None
        }
        match kw_name {
          Some(name) => {
            let kloc = self.advance().loc
            // Keywords are not valid IdentifierReference, so is_ident_key = false
            // This prevents `{ for }` or `{ for = 42 }` shorthand syntax
            (StringLit(name, false, kloc), name, false, false)
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
      let saved_pos = self.pos
      let func_data : @ast.Expr = try {
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
        @ast.Expr::FuncExpr(
          if computed {
            None
          } else {
            Some(key_name)
          },
          params,
          body,
          mloc,
        )
      } catch {
        Failure::Failure(msg) =>
          if msg == "REST_PARAM_FOUND" ||
            msg == "DEFAULT_PARAM_FOUND" ||
            msg == "DESTRUCTURE_PARAM_FOUND" {
            self.pos = saved_pos
            let (ext_params, rest_param) = self.parse_params_ext()
            let body = self.parse_block_body()
            FuncExprExt(
              if computed {
                None
              } else {
                Some(key_name)
              },
              ext_params,
              rest_param,
              body,
              mloc,
            )
          } else {
            raise @errors.SyntaxError(message=msg)
          }
        e => raise e
      }
      props.push({ key: key_expr, value: func_data, kind: prop_kind, computed })
    } else if self.at(Colon) {
      // Normal property
      let _ = self.advance() // consume ':'
      let value = self.parse_assignment()
      props.push({ key: key_expr, value, kind: @ast.Init, computed })
    } else if self.at(Assign) && is_ident_key {
      // Shorthand with default (cover assignment pattern): { x = 42 }
      // This is valid in destructuring: { x = 42 } = obj
      let eq_tok = self.advance() // consume '='
      let default_val = self.parse_assignment()
      // Represent as Assign expr so destructuring can pick it up
      let value : @ast.Expr = Assign(key_name, default_val, eq_tok.loc)
      props.push({ key: key_expr, value, kind: @ast.Init, computed: false })
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
  // Check for function* (generator expression)
  if self.at(Star) {
    return self.parse_generator_expr(tok)
  }
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
      if msg == "REST_PARAM_FOUND" ||
        msg == "DEFAULT_PARAM_FOUND" ||
        msg == "DESTRUCTURE_PARAM_FOUND" {
        self.pos = saved_pos
        let (ext_params, rest_param) = self.parse_params_ext()
        self.push_generator_context(false)
        let body = self.parse_block_body()
        self.pop_generator_context()
        return FuncExprExt(name, ext_params, rest_param, body, tok.loc)
      } else {
        raise @errors.SyntaxError(message=msg)
      }
    e => raise e
  }
  self.push_generator_context(false)
  let body = self.parse_block_body()
  self.pop_generator_context()
  FuncExpr(name, params, body, tok.loc)
}

///|
fn Parser::parse_generator_expr(
  self : Parser,
  func_tok : @token.Token,
) -> @ast.Expr raise Error {
  let _ = self.expect(Star) // consume *
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
      if msg == "REST_PARAM_FOUND" ||
        msg == "DEFAULT_PARAM_FOUND" ||
        msg == "DESTRUCTURE_PARAM_FOUND" {
        self.pos = saved_pos
        let (ext_params, rest_param) = self.parse_params_ext()
        self.push_generator_context(true)
        let body = self.parse_block_body()
        self.pop_generator_context()
        return GeneratorExprExt(
          name,
          ext_params,
          rest_param,
          body,
          func_tok.loc,
        )
      } else {
        raise @errors.SyntaxError(message=msg)
      }
    e => raise e
  }
  self.push_generator_context(true)
  let body = self.parse_block_body()
  self.pop_generator_context()
  GeneratorExpr(name, params, body, func_tok.loc)
}

///|
fn Parser::parse_yield_expr(self : Parser) -> @ast.Expr raise Error {
  let tok = self.expect(Yield)
  // Check for yield* (delegate)
  // No LineTerminator between yield and * — we check if * is on same line
  let delegate = if self.at(Star) {
    let star_tok = self.peek()
    // Only treat as yield* if star is on the same line as yield
    if star_tok.loc.line == tok.loc.line {
      let _ = self.advance() // consume *
      true
    } else {
      false
    }
  } else {
    false
  }
  // Parse argument: yield is prefix unary with very low precedence
  // yield without argument (e.g., at statement end, before }, ), ], ;, comma)
  let has_argument = not(
    self.at(Semicolon) ||
    self.at(RParen) ||
    self.at(RBracket) ||
    self.at(RBrace) ||
    self.at(Comma) ||
    self.at(Colon) ||
    self.at(EOF),
  )
  // Also check if the next token is on a different line (ASI)
  let next_on_new_line = if has_argument {
    let next_tok = self.peek()
    next_tok.loc.line != tok.loc.line && not(delegate)
  } else {
    false
  }
  if delegate || (has_argument && not(next_on_new_line)) {
    let argument = self.parse_assignment()
    YieldExpr(Some(argument), delegate, tok.loc)
  } else {
    YieldExpr(None, false, tok.loc)
  }
}

///|
fn Parser::parse_arrow_body(self : Parser) -> Array[@ast.Stmt] raise Error {
  // Arrow functions are never generators; yield is illegal inside them
  self.push_generator_context(false)
  let result = if self.at(LBrace) {
    self.parse_block_body()
  } else {
    let expr = self.parse_assignment()
    let loc = @token.Loc::default()
    [@ast.ReturnStmt(Some(expr), loc)]
  }
  self.pop_generator_context()
  result
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
/// Convert an expression to extended arrow function parameters.
/// Handles defaults, destructuring, and rest params that extract_arrow_params cannot.
fn expr_to_ext_arrow_params(
  expr : @ast.Expr,
) -> (Array[@ast.Param], String?) raise Error {
  let params : Array[@ast.Param] = []
  let mut rest_param : String? = None
  let mut synth_idx = 0
  fn collect(e : @ast.Expr) -> Unit raise Error {
    match e {
      Ident(name, _) => params.push({ name, default_val: None, pattern: None })
      Assign(name, default_expr, _) =>
        params.push({ name, default_val: Some(default_expr), pattern: None })
      Grouping(inner, _) => collect(inner)
      Comma(left, right, _) => {
        collect(left)
        collect(right)
      }
      SpreadExpr(Ident(name, _), _) => rest_param = Some(name)
      ArrayLit(_, _) | ObjectLit(_, _) => {
        let pat = expr_to_pattern(e)
        let sname = "$" + synth_idx.to_string()
        synth_idx = synth_idx + 1
        params.push({ name: sname, default_val: None, pattern: Some(pat) })
      }
      DestructureAssign(pat, default_expr, _) => {
        let sname = "$" + synth_idx.to_string()
        synth_idx = synth_idx + 1
        params.push({
          name: sname,
          default_val: Some(default_expr),
          pattern: Some(pat),
        })
      }
      _ =>
        raise @errors.SyntaxError(
          message="Invalid arrow function parameter list",
        )
    }
  }

  collect(expr)
  (params, rest_param)
}

///|
fn expr_to_pattern(expr : @ast.Expr) -> @ast.Pattern raise Error {
  match expr {
    Ident(name, _) => IdentPat(name)
    ArrayLit(elements, _) => {
      let pats : Array[@ast.Pattern?] = []
      let mut rest : @ast.Pattern? = None
      let mut rest_seen = false
      for elem in elements {
        if rest_seen {
          raise @errors.SyntaxError(
            message="Rest element must be last in array destructuring pattern",
          )
        }
        match elem {
          SpreadExpr(inner, _) => {
            rest = Some(expr_to_pattern(inner))
            rest_seen = true
          }
          Assign(name, default_expr, _) =>
            // [a = 1] → DefaultPat(IdentPat("a"), NumberLit(1))
            pats.push(Some(DefaultPat(IdentPat(name), default_expr)))
          DestructureAssign(pat, default_expr, _) =>
            // [{x} = {x: 1}] → DefaultPat(ObjectPat(...), ObjectLit(...))
            pats.push(Some(DefaultPat(pat, default_expr)))
          UndefinedLit(_) =>
            // [,a] → hole (elision) in array pattern
            pats.push(None)
          _ => pats.push(Some(expr_to_pattern(elem)))
        }
      }
      ArrayPat(pats, rest)
    }
    ObjectLit(props, _) => {
      let prop_pats : Array[@ast.PropPat] = []
      let mut rest : @ast.Pattern? = None
      let mut rest_seen = false
      for prop in props {
        if rest_seen {
          raise @errors.SyntaxError(
            message="Rest element must be last in object destructuring pattern",
          )
        }
        if prop.kind == @ast.Spread {
          rest = Some(expr_to_pattern(prop.key))
          rest_seen = true
          continue
        }
        // key: value => { key, value: Pattern, default_val }
        // Extract string key from the key expression
        let key_str : String = match prop.key {
          StringLit(s, _, _) => s
          Ident(s, _) => s
          _ =>
            raise @errors.SyntaxError(
              message="Invalid key in destructuring pattern",
            )
        }
        // Convert value expression to pattern
        // Assign(name, default) becomes DefaultPat(IdentPat(name), default)
        // which correctly handles both shorthand {x = 5} and non-shorthand {a: b = 1}
        let pat = expr_to_pattern(prop.value)
        prop_pats.push({ key: key_str, value: pat, default_val: None })
      }
      ObjectPat(prop_pats, rest)
    }
    Assign(name, default_expr, _) =>
      // Handle default values in destructuring: { x = 5 } or [a = 1]
      DefaultPat(IdentPat(name), default_expr)
    DestructureAssign(pat, default_expr, _) =>
      // Handle complex patterns with defaults: [{x} = {}]
      DefaultPat(pat, default_expr)
    // Member expression targets for destructuring assignment: [obj.x] = [1]
    Member(_, _, _) | ComputedMember(_, _, _) => AssignTarget(expr)
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
  // Check for generator modifier: *method() {} or static *method() {}
  let is_generator = self.eat(Star)
  // Check for getter/setter (not valid with generator *)
  let mut method_kind : @ast.PropKind = @ast.Init
  if not(is_generator) {
    match self.peek_kind() {
      Get =>
        match self.peek_kind_at(1) {
          Ident(_)
          | String_(_)
          | Number(_)
          | LBracket
          | LParen
          | Get
          | Set
          | From
          | As
          | Import
          | Export
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
          | True
          | False
          | Null
          | Undefined
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
          | Static =>
            if not(self.at_kind_at(1, LParen)) {
              self.pos += 1
              method_kind = @ast.Get
            }
          _ => ()
        }
      Set =>
        match self.peek_kind_at(1) {
          Ident(_)
          | String_(_)
          | Number(_)
          | LBracket
          | LParen
          | Get
          | Set
          | From
          | As
          | Import
          | Export
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
          | True
          | False
          | Null
          | Undefined
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
          | Static =>
            if not(self.at_kind_at(1, LParen)) {
              self.pos += 1
              method_kind = @ast.Set
            }
          _ => ()
        }
      _ => ()
    }
  }
  // Parse method name (keywords can be used as method names)
  let (key_expr, computed) : (@ast.Expr, Bool) = match self.peek_kind() {
    Ident(name) => {
      let kloc = self.advance().loc
      (StringLit(name, false, kloc), false)
    }
    String_(s) => {
      let kloc = self.advance().loc
      (StringLit(s, false, kloc), false)
    }
    Number(n) => {
      let kloc = self.advance().loc
      let i = n.to_int()
      let name = if i.to_double() == n { i.to_string() } else { n.to_string() }
      (StringLit(name, false, kloc), false)
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
        Import => Some("import")
        Export => Some("export")
        From => Some("from")
        As => Some("as")
        Yield => Some("yield")
        _ => None
      }
      match kw_name {
        Some(name) => {
          let kloc = self.advance().loc
          (StringLit(name, false, kloc), false)
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
      if msg == "REST_PARAM_FOUND" ||
        msg == "DEFAULT_PARAM_FOUND" ||
        msg == "DESTRUCTURE_PARAM_FOUND" {
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
        self.push_generator_context(is_generator)
        let body = self.parse_block_body()
        self.pop_generator_context()
        let func_val : @ast.Expr = if is_generator {
          GeneratorExprExt(None, ext_params, rest_param, body, mloc)
        } else {
          FuncExprExt(None, ext_params, rest_param, body, mloc)
        }
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
  self.push_generator_context(is_generator)
  let body = self.parse_block_body()
  self.pop_generator_context()
  let func_val : @ast.Expr = if is_generator {
    GeneratorExpr(None, params, body, mloc)
  } else {
    FuncExpr(None, params, body, mloc)
  }
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
