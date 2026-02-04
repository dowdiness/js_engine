///|
fn Parser::parse_stmt(self : Parser) -> @ast.Stmt raise Error {
  match self.peek_kind() {
    Let | Const | Var => self.parse_var_decl()
    Function => self.parse_func_decl()
    Class => self.parse_class_decl()
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
      raise @errors.SyntaxError(
        message="Expected let/const/var at line \{tok.loc.line}, col \{tok.loc.col}",
      )
  }
  // Check for destructuring pattern
  if self.at(LBracket) || self.at(LBrace) {
    let pat = self.parse_pattern()
    let _ = self.expect(Assign)
    let init = self.parse_assignment()
    self.eat_semicolon()
    return DestructureDecl(kind, pat, init, tok.loc)
  }
  // Parse first declarator
  let name = self.expect_ident()
  let init : @ast.Expr? = if self.eat(Assign) {
    Some(self.parse_assignment())
  } else {
    None
  }
  // Check for comma-separated declarations (e.g., var a, b, c;)
  if not(self.at(Comma)) {
    self.eat_semicolon()
    return VarDecl(kind, name, init, tok.loc)
  }
  // Multiple declarations - collect them all
  let decls : Array[@ast.Stmt] = []
  decls.push(VarDecl(kind, name, init, tok.loc))
  while self.eat(Comma) {
    // Check for destructuring in subsequent declarators
    if self.at(LBracket) || self.at(LBrace) {
      let pat = self.parse_pattern()
      let _ = self.expect(Assign)
      let decl_init = self.parse_assignment()
      decls.push(DestructureDecl(kind, pat, decl_init, tok.loc))
    } else {
      let decl_name = self.expect_ident()
      let decl_init : @ast.Expr? = if self.eat(Assign) {
        Some(self.parse_assignment())
      } else {
        None
      }
      decls.push(VarDecl(kind, decl_name, decl_init, tok.loc))
    }
  }
  self.eat_semicolon()
  // Return as StmtList (no new scope, preserves hoisting semantics)
  StmtList(decls, tok.loc)
}

///|
fn Parser::parse_func_decl(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Function)
  let name = self.expect_ident()
  let saved_pos = self.pos
  let params = self.parse_params() catch {
    Failure::Failure(msg) =>
      if msg == "REST_PARAM_FOUND" || msg == "DEFAULT_PARAM_FOUND" {
        self.pos = saved_pos
        let (ext_params, rest_param) = self.parse_params_ext()
        let body = self.parse_block_body()
        return FuncDeclExt(name, ext_params, rest_param, body, tok.loc)
      } else {
        raise @errors.SyntaxError(message=msg)
      }
    e => raise e
  }
  let body = self.parse_block_body()
  FuncDecl(name, params, body, tok.loc)
}

///|
fn Parser::parse_params(self : Parser) -> Array[String] raise Error {
  let _ = self.expect(LParen)
  let params : Array[String] = []
  if not(self.at(RParen)) {
    // Skip rest param in simple parse
    if self.at(DotDotDot) {
      // Let extended parse handle it
      raise Failure::Failure("REST_PARAM_FOUND")
    }
    params.push(self.expect_ident())
    // Check for default value — trigger extended parse
    if self.at(Assign) {
      raise Failure::Failure("DEFAULT_PARAM_FOUND")
    }
    while self.eat(Comma) {
      if self.at(DotDotDot) {
        raise Failure::Failure("REST_PARAM_FOUND")
      }
      params.push(self.expect_ident())
      if self.at(Assign) {
        raise Failure::Failure("DEFAULT_PARAM_FOUND")
      }
    }
  }
  let _ = self.expect(RParen)
  params
}

///|
fn Parser::parse_params_ext(
  self : Parser,
) -> (Array[@ast.Param], String?) raise Error {
  let _ = self.expect(LParen)
  let params : Array[@ast.Param] = []
  let mut rest_param : String? = None
  if not(self.at(RParen)) {
    // Check for rest param
    if self.eat(DotDotDot) {
      rest_param = Some(self.expect_ident())
    } else {
      let name = self.expect_ident()
      let default_val : @ast.Expr? = if self.eat(Assign) {
        Some(self.parse_assignment())
      } else {
        None
      }
      params.push({ name, default_val })
      while self.eat(Comma) {
        if rest_param is Some(_) {
          let t = self.peek()
          raise @errors.SyntaxError(
            message="Rest parameter must be last at line \{t.loc.line}, col \{t.loc.col}",
          )
        }
        if self.eat(DotDotDot) {
          rest_param = Some(self.expect_ident())
        } else {
          let pname = self.expect_ident()
          let pdefault : @ast.Expr? = if self.eat(Assign) {
            Some(self.parse_assignment())
          } else {
            None
          }
          params.push({ name: pname, default_val: pdefault })
        }
      }
    }
  }
  let _ = self.expect(RParen)
  (params, rest_param)
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
    if self.eat(Of) {
      // for-of with var declaration
      let obj = self.parse_expr()
      let _ = self.expect(RParen)
      let body = self.parse_stmt()
      return ForOfStmt(Some(var_kind), name, obj, body, tok.loc)
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
  // Check for for-in / for-of with bare identifier
  match self.peek_kind() {
    Ident(name) =>
      if self.peek_kind_at(1) == In {
        self.pos += 1 // consume ident
        self.pos += 1 // consume 'in'
        let obj = self.parse_expr()
        let _ = self.expect(RParen)
        let body = self.parse_stmt()
        return ForInStmt(None, name, obj, body, tok.loc)
      } else if self.peek_kind_at(1) == Of {
        self.pos += 1 // consume ident
        self.pos += 1 // consume 'of'
        let obj = self.parse_expr()
        let _ = self.expect(RParen)
        let body = self.parse_stmt()
        return ForOfStmt(None, name, obj, body, tok.loc)
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
    raise @errors.SyntaxError(
      message="Missing catch or finally after try at line \{tok.loc.line}, col \{tok.loc.col}",
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
      raise @errors.SyntaxError(
        message="Expected case or default in switch at line \{t.loc.line}, col \{t.loc.col}",
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
      raise @errors.SyntaxError(
        message="Expected label name at line \{tok.loc.line}, col \{tok.loc.col}",
      )
  }
  let _ = self.expect(Colon) // consume ':'
  let body = self.parse_stmt()
  LabeledStmt(label, body, tok.loc)
}

///|
fn Parser::parse_pattern(self : Parser) -> @ast.Pattern raise Error {
  if self.at(LBracket) {
    self.parse_array_pattern()
  } else if self.at(LBrace) {
    self.parse_object_pattern()
  } else {
    let name = self.expect_ident()
    IdentPat(name)
  }
}

///|
fn Parser::parse_array_pattern(self : Parser) -> @ast.Pattern raise Error {
  let _ = self.expect(LBracket)
  let elements : Array[@ast.Pattern?] = []
  let mut rest : @ast.Pattern? = None
  while not(self.at(RBracket)) && not(self.at(EOF)) {
    if self.at(Comma) {
      // Hole / elision
      elements.push(None)
      let _ = self.advance()
      continue
    }
    if self.at(DotDotDot) {
      let _ = self.advance()
      rest = Some(self.parse_pattern())
      break
    }
    elements.push(Some(self.parse_pattern()))
    if not(self.at(RBracket)) && not(self.at(DotDotDot)) {
      let _ = self.expect(Comma)

    }
  }
  let _ = self.expect(RBracket)
  ArrayPat(elements, rest)
}

///|
fn Parser::parse_object_pattern(self : Parser) -> @ast.Pattern raise Error {
  let _ = self.expect(LBrace)
  let props : Array[@ast.PropPat] = []
  let mut rest : @ast.Pattern? = None
  while not(self.at(RBrace)) && not(self.at(EOF)) {
    if self.at(DotDotDot) {
      let _ = self.advance()
      rest = Some(self.parse_pattern())
      break
    }
    let key = self.expect_ident()
    let (value, default_val) : (@ast.Pattern, @ast.Expr?) = if self.eat(Colon) {
      // { key: pattern }
      let pat = self.parse_pattern()
      let def : @ast.Expr? = if self.eat(Assign) {
        Some(self.parse_assignment())
      } else {
        None
      }
      (pat, def)
    } else {
      // Shorthand: { key } or { key = default }
      let def : @ast.Expr? = if self.eat(Assign) {
        Some(self.parse_assignment())
      } else {
        None
      }
      (IdentPat(key), def)
    }
    props.push({ key, value, default_val })
    if not(self.at(RBrace)) {
      let _ = self.expect(Comma)

    }
  }
  let _ = self.expect(RBrace)
  ObjectPat(props, rest)
}

///|
fn Parser::parse_expr_stmt(self : Parser) -> @ast.Stmt raise Error {
  let loc = self.peek().loc
  let expr = self.parse_expr()
  self.eat_semicolon()
  ExprStmt(expr, loc)
}

///|
fn Parser::parse_class_decl(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Class)
  let name = self.expect_ident()
  // Optional extends clause
  let superclass : @ast.Expr? = if self.eat(Extends) {
    Some(self.parse_class_heritage())
  } else {
    None
  }
  let methods = self.parse_class_body()
  ClassDecl(name, superclass, methods, tok.loc)
}
