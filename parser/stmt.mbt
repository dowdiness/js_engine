///|
fn Parser::parse_stmt(self : Parser) -> @ast.Stmt raise Error {
  match self.peek_kind() {
    Semicolon => {
      // Empty statement
      let loc = self.advance().loc
      ExprStmt(UndefinedLit(loc), loc)
    }
    Let | Const | Var => self.parse_var_decl()
    Function =>
      // Check for function* (generator declaration)
      if self.peek_kind_at(1) == Star {
        self.parse_generator_decl()
      } else {
        self.parse_func_decl()
      }
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
    Import =>
      if self.allow_import_export {
        self.parse_import_decl()
      } else {
        let tok = self.peek()
        raise @errors.SyntaxError(
          message="'import' declarations may only appear at top level of a module at line \{tok.loc.line}, col \{tok.loc.col}",
        )
      }
    Export =>
      if self.allow_import_export {
        self.parse_export_decl()
      } else {
        let tok = self.peek()
        raise @errors.SyntaxError(
          message="'export' declarations may only appear at top level of a module at line \{tok.loc.line}, col \{tok.loc.col}",
        )
      }
    Yield =>
      // In generator context, yield is an expression statement; outside it's an identifier
      self.parse_expr_stmt()
    Ident(_) | Get | Set | From | As =>
      // Check for async function declaration: async [no LineTerminator] function
      if self.is_async_function() {
        if self.is_async_generator() {
          self.parse_async_generator_decl()
        } else {
          self.parse_async_func_decl()
        }
      } else if self.peek_kind() is Ident(name) && name == "with" {
        // Check for 'with' statement
        self.parse_with_stmt()
      } else if self.peek_kind_at(1) == Colon {
        // Labeled statement: ident ':'
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
      if msg == "REST_PARAM_FOUND" ||
        msg == "DEFAULT_PARAM_FOUND" ||
        msg == "DESTRUCTURE_PARAM_FOUND" {
        self.pos = saved_pos
        let (ext_params, rest_param) = self.parse_params_ext()
        self.push_generator_context(false)
        self.push_async_context(false)
        let body = self.parse_block_body()
        self.pop_async_context()
        self.pop_generator_context()
        return FuncDeclExt(name, ext_params, rest_param, body, tok.loc)
      } else {
        raise @errors.SyntaxError(message=msg)
      }
    e => raise e
  }
  self.push_generator_context(false)
  self.push_async_context(false)
  let body = self.parse_block_body()
  self.pop_async_context()
  self.pop_generator_context()
  FuncDecl(name, params, body, tok.loc)
}

///|
fn Parser::parse_generator_decl(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Function)
  let _ = self.expect(Star) // consume *
  let name = self.expect_ident()
  let saved_pos = self.pos
  let params = self.parse_params() catch {
    Failure::Failure(msg) =>
      if msg == "REST_PARAM_FOUND" ||
        msg == "DEFAULT_PARAM_FOUND" ||
        msg == "DESTRUCTURE_PARAM_FOUND" {
        self.pos = saved_pos
        let (ext_params, rest_param) = self.parse_params_ext()
        self.push_generator_context(true)
        self.push_async_context(false)
        let body = self.parse_block_body()
        self.pop_async_context()
        self.pop_generator_context()
        return GeneratorDeclExt(name, ext_params, rest_param, body, tok.loc)
      } else {
        raise @errors.SyntaxError(message=msg)
      }
    e => raise e
  }
  self.push_generator_context(true)
  self.push_async_context(false)
  let body = self.parse_block_body()
  self.pop_async_context()
  self.pop_generator_context()
  GeneratorDecl(name, params, body, tok.loc)
}

///|
fn Parser::parse_async_func_decl(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.advance() // consume 'async'
  let _ = self.expect(Function)
  let name = self.expect_ident()
  let saved_pos = self.pos
  let params = self.parse_params() catch {
    Failure::Failure(msg) =>
      if msg == "REST_PARAM_FOUND" ||
        msg == "DEFAULT_PARAM_FOUND" ||
        msg == "DESTRUCTURE_PARAM_FOUND" {
        self.pos = saved_pos
        let (ext_params, rest_param) = self.parse_params_ext()
        self.push_generator_context(false)
        self.push_async_context(true)
        let body = self.parse_block_body()
        self.pop_async_context()
        self.pop_generator_context()
        return AsyncFuncDeclExt(name, ext_params, rest_param, body, tok.loc)
      } else {
        raise @errors.SyntaxError(message=msg)
      }
    e => raise e
  }
  self.push_generator_context(false)
  self.push_async_context(true)
  let body = self.parse_block_body()
  self.pop_async_context()
  self.pop_generator_context()
  AsyncFuncDecl(name, params, body, tok.loc)
}

///|
fn Parser::parse_async_generator_decl(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.advance() // consume 'async'
  let _ = self.expect(Function)
  let _ = self.expect(Star) // consume *
  let name = self.expect_ident()
  let saved_pos = self.pos
  let params = self.parse_params() catch {
    Failure::Failure(msg) =>
      if msg == "REST_PARAM_FOUND" ||
        msg == "DEFAULT_PARAM_FOUND" ||
        msg == "DESTRUCTURE_PARAM_FOUND" {
        self.pos = saved_pos
        let (ext_params, rest_param) = self.parse_params_ext()
        self.push_generator_context(true)
        self.push_async_context(true)
        let body = self.parse_block_body()
        self.pop_async_context()
        self.pop_generator_context()
        return AsyncGeneratorDeclExt(name, ext_params, rest_param, body, tok.loc)
      } else {
        raise @errors.SyntaxError(message=msg)
      }
    e => raise e
  }
  self.push_generator_context(true)
  self.push_async_context(true)
  let body = self.parse_block_body()
  self.pop_async_context()
  self.pop_generator_context()
  AsyncGeneratorDecl(name, params, body, tok.loc)
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
    // Destructuring patterns trigger extended parse
    if self.at(LBrace) || self.at(LBracket) {
      raise Failure::Failure("DESTRUCTURE_PARAM_FOUND")
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
      if self.at(LBrace) || self.at(LBracket) {
        raise Failure::Failure("DESTRUCTURE_PARAM_FOUND")
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
  let mut synth_idx = 0
  if not(self.at(RParen)) {
    // Check for rest param
    if self.eat(DotDotDot) {
      if self.at(LBrace) || self.at(LBracket) {
        let pat = self.parse_pattern()
        let sname = "$rest"
        rest_param = Some(sname)
        params.push({ name: sname, default_val: None, pattern: Some(pat) })
      } else {
        rest_param = Some(self.expect_ident())
      }
    } else if self.at(LBrace) || self.at(LBracket) {
      // Destructuring parameter
      let pat = self.parse_pattern()
      let sname = "$" + synth_idx.to_string()
      synth_idx = synth_idx + 1
      let default_val : @ast.Expr? = if self.eat(Assign) {
        Some(self.parse_assignment())
      } else {
        None
      }
      params.push({ name: sname, default_val, pattern: Some(pat) })
    } else {
      let name = self.expect_ident()
      let default_val : @ast.Expr? = if self.eat(Assign) {
        Some(self.parse_assignment())
      } else {
        None
      }
      params.push({ name, default_val, pattern: None })
    }
    while self.eat(Comma) {
      if self.at(RParen) {
        break
      } // trailing comma
      if rest_param is Some(_) {
        let t = self.peek()
        raise @errors.SyntaxError(
          message="Rest parameter must be last at line \{t.loc.line}, col \{t.loc.col}",
        )
      }
      if self.eat(DotDotDot) {
        if self.at(LBrace) || self.at(LBracket) {
          let pat = self.parse_pattern()
          let sname = "$rest"
          rest_param = Some(sname)
          params.push({ name: sname, default_val: None, pattern: Some(pat) })
        } else {
          rest_param = Some(self.expect_ident())
        }
      } else if self.at(LBrace) || self.at(LBracket) {
        let pat = self.parse_pattern()
        let sname = "$" + synth_idx.to_string()
        synth_idx = synth_idx + 1
        let pdefault : @ast.Expr? = if self.eat(Assign) {
          Some(self.parse_assignment())
        } else {
          None
        }
        params.push({ name: sname, default_val: pdefault, pattern: Some(pat) })
      } else {
        let pname = self.expect_ident()
        let pdefault : @ast.Expr? = if self.eat(Assign) {
          Some(self.parse_assignment())
        } else {
          None
        }
        params.push({ name: pname, default_val: pdefault, pattern: None })
      }
    }
  }
  let _ = self.expect(RParen)
  (params, rest_param)
}

///|
fn Parser::parse_block_body(self : Parser) -> Array[@ast.Stmt] raise Error {
  let _ = self.expect(LBrace)
  let saved_allow = self.allow_import_export
  self.allow_import_export = false
  let stmts : Array[@ast.Stmt] = []
  while not(self.at(RBrace)) && not(self.at(EOF)) {
    stmts.push(self.parse_stmt())
  }
  let _ = self.expect(RBrace)
  self.allow_import_export = saved_allow
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
fn reject_function_decl_in_stmt_position(stmt : @ast.Stmt) -> Unit raise Error {
  match stmt {
    FuncDecl(_, _, _, _)
    | FuncDeclExt(_, _, _, _, _)
    | GeneratorDecl(_, _, _, _)
    | GeneratorDeclExt(_, _, _, _, _)
    | AsyncFuncDecl(_, _, _, _)
    | AsyncFuncDeclExt(_, _, _, _, _)
    | AsyncGeneratorDecl(_, _, _, _)
    | AsyncGeneratorDeclExt(_, _, _, _, _) =>
      raise @errors.SyntaxError(
        message="Function declaration in statement position is not allowed",
      )
    _ => ()
  }
}

///|
fn Parser::parse_while_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(While)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  let body = self.parse_stmt()
  reject_function_decl_in_stmt_position(body)
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
    // Check for destructuring pattern in for-of/for-in: for (let [a,b] of ...) or for (let {x,y} of ...)
    if self.at(LBracket) || self.at(LBrace) {
      let pat = self.parse_pattern()
      if self.eat(Of) {
        let obj = self.parse_assignment()
        let _ = self.expect(RParen)
        let body = self.parse_stmt()
        reject_function_decl_in_stmt_position(body)
        return ForOfStmtPat(Some(var_kind), pat, obj, body, tok.loc)
      }
      if self.eat(In) {
        let obj = self.parse_expr()
        let _ = self.expect(RParen)
        let body = self.parse_stmt()
        reject_function_decl_in_stmt_position(body)
        return ForInStmtPat(Some(var_kind), pat, obj, body, tok.loc)
      }
      // Destructuring in regular for: for (let [a,b] = ...; ...; ...)
      let _ = self.expect(Assign)
      let init_expr = self.parse_assignment()
      self.eat_semicolon()
      let init : @ast.Stmt? = Some(
        DestructureDecl(var_kind, pat, init_expr, var_tok.loc),
      )
      return self.parse_for_rest(init, tok.loc)
    }
    let name = self.expect_ident()
    if self.eat(In) {
      // for-in with var declaration
      let obj = self.parse_expr()
      let _ = self.expect(RParen)
      let body = self.parse_stmt()
      reject_function_decl_in_stmt_position(body)
      return ForInStmt(Some(var_kind), name, obj, body, tok.loc)
    }
    if self.eat(Of) {
      // for-of with var declaration
      let obj = self.parse_expr()
      let _ = self.expect(RParen)
      let body = self.parse_stmt()
      reject_function_decl_in_stmt_position(body)
      return ForOfStmt(Some(var_kind), name, obj, body, tok.loc)
    }
    // Regular for — finish parsing the var decl init (may have multiple comma-separated decls)
    let init_val : @ast.Expr? = if self.eat(Assign) {
      Some(self.parse_assignment())
    } else {
      None
    }
    let decls : Array[@ast.Stmt] = [
      VarDecl(var_kind, name, init_val, var_tok.loc),
    ]
    while self.eat(Comma) {
      // Handle destructuring in for-init: for (var i = 0, {x} = obj; ...)
      if self.at(LBracket) || self.at(LBrace) {
        let pat = self.parse_pattern()
        let _ = self.expect(Assign)
        let val = self.parse_assignment()
        decls.push(DestructureDecl(var_kind, pat, val, var_tok.loc))
      } else {
        let next_name = self.expect_ident()
        let next_val : @ast.Expr? = if self.eat(Assign) {
          Some(self.parse_assignment())
        } else {
          None
        }
        decls.push(VarDecl(var_kind, next_name, next_val, var_tok.loc))
      }
    }
    self.eat_semicolon()
    let init : @ast.Stmt? = if decls.length() == 1 {
      Some(decls[0])
    } else {
      Some(StmtList(decls, var_tok.loc))
    }
    return self.parse_for_rest(init, tok.loc)
  }
  // Check for for-in / for-of with bare expression (no let/var/const)
  // This handles: for (x of arr), for ({x} of arr), for ([x] of arr), for (a.b of arr), etc.
  if not(self.at(Semicolon)) {
    let saved_pos = self.pos
    let try_expr : @ast.Expr? = Some(self.parse_call()) catch { _ => None }
    match try_expr {
      Some(expr) => {
        if self.at(Of) {
          self.pos += 1 // consume 'of'
          let iterable = self.parse_assignment()
          let _ = self.expect(RParen)
          let body = self.parse_stmt()
          reject_function_decl_in_stmt_position(body)
          match expr {
            Ident(name, _) =>
              return ForOfStmt(None, name, iterable, body, tok.loc)
            ArrayLit(_, _) | ObjectLit(_, _) => {
              let pattern = expr_to_pattern(expr)
              return ForOfStmtPat(None, pattern, iterable, body, tok.loc)
            }
            Member(_, _, _) | ComputedMember(_, _, _) =>
              return ForOfExpr(expr, iterable, body, tok.loc)
            _ =>
              raise @errors.SyntaxError(
                message="Invalid left-hand side in for-of at line \{tok.loc.line}, col \{tok.loc.col}",
              )
          }
        }
        if self.at(In) {
          self.pos += 1 // consume 'in'
          let obj = self.parse_expr()
          let _ = self.expect(RParen)
          let body = self.parse_stmt()
          reject_function_decl_in_stmt_position(body)
          match expr {
            Ident(name, _) => return ForInStmt(None, name, obj, body, tok.loc)
            ArrayLit(_, _) | ObjectLit(_, _) => {
              let pattern = expr_to_pattern(expr)
              return ForInStmtPat(None, pattern, obj, body, tok.loc)
            }
            Member(_, _, _) | ComputedMember(_, _, _) =>
              return ForInExpr(expr, obj, body, tok.loc)
            _ =>
              raise @errors.SyntaxError(
                message="Invalid left-hand side in for-in at line \{tok.loc.line}, col \{tok.loc.col}",
              )
          }
        }
        // Not for-in/for-of, restore position
        self.pos = saved_pos
      }
      None => self.pos = saved_pos
    }
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
  reject_function_decl_in_stmt_position(body)
  ForStmt(init, cond, update, body, loc)
}

///|
fn Parser::parse_return_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Return)
  // [no LineTerminator here] — ASI inserts semicolon if next token is on a new line
  let value : @ast.Expr? = if self.at(Semicolon) ||
    self.at(RBrace) ||
    self.at(EOF) ||
    self.peek().loc.line != tok.loc.line {
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
  // [no LineTerminator here] — a line terminator between throw and expression is illegal
  let next = self.peek()
  if next.loc.line != tok.loc.line || self.at(Semicolon) || self.at(EOF) {
    raise @errors.SyntaxError(
      message="Illegal newline after throw at line \{tok.loc.line}, col \{tok.loc.col}",
    )
  }
  let expr = self.parse_expr()
  self.eat_semicolon()
  ThrowStmt(expr, tok.loc)
}

///|
fn Parser::parse_try_catch_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Try)
  let try_body = self.parse_block_body()
  let mut catch_param : @ast.Pattern? = None
  let mut catch_body : Array[@ast.Stmt]? = None
  let mut finally_body : Array[@ast.Stmt]? = None
  if self.eat(Catch) {
    // Optional catch binding: catch { ... } without parameter
    if self.eat(LParen) {
      // catch(ident), catch({destructure}), catch([destructure])
      match self.peek_kind() {
        LBrace | LBracket =>
          // Destructuring pattern in catch clause
          catch_param = Some(self.parse_pattern())
        _ => {
          let name = self.expect_ident()
          catch_param = Some(@ast.IdentPat(name))
        }
      }
      let _ = self.expect(RParen)
    }
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
  reject_function_decl_in_stmt_position(body)
  let _ = self.expect(While)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  self.eat_semicolon()
  DoWhileStmt(body, cond, tok.loc)
}

///|
fn Parser::parse_with_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.advance() // consume 'with'
  let _ = self.expect(LParen)
  let expr = self.parse_expr()
  let _ = self.expect(RParen)
  let body = self.parse_stmt()
  WithStmt(expr, body, tok.loc)
}

///|
fn Parser::parse_labeled_stmt(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.advance() // consume identifier
  let label : String = match tok.kind {
    Ident(name) => name
    Get => "get"
    Set => "set"
    From => "from"
    As => "as"
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
    let pat = self.parse_pattern()
    // Check for default value: element = expr
    if self.eat(Assign) {
      let default_expr = self.parse_assignment()
      elements.push(Some(DefaultPat(pat, default_expr)))
    } else {
      elements.push(Some(pat))
    }
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
    // Parse key: identifier, string literal, number literal, or computed [expr]
    let (key, computed_key) : (String, @ast.Expr?) = match self.peek_kind() {
      LBracket => {
        let _ = self.advance()
        let key_expr = self.parse_assignment()
        let _ = self.expect(RBracket)
        ("", Some(key_expr))
      }
      String_(s) => {
        let _ = self.advance()
        (s, None)
      }
      Number(n) => {
        let _ = self.advance()
        let i = n.to_int()
        let name = if i.to_double() == n { i.to_string() } else { n.to_string() }
        (name, None)
      }
      _ => (self.expect_ident(), None)
    }
    let (value, default_val) : (@ast.Pattern, @ast.Expr?) = if self.eat(Colon) {
      // { key: pattern } or { [expr]: pattern }
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
    props.push({ key, value, default_val, computed_key })
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
  // Use strict ASI for expression statements.
  // This correctly rejects code like: `// comment\ncode_on_same_line`
  // While still allowing valid ASI cases (newline, }, EOF, ;).
  self.eat_semicolon_strict()
  ExprStmt(expr, loc)
}

///|
/// Strict ASI check: used after expression statements where proper ASI enforcement is needed.
/// Returns error if no valid semicolon termination exists on the same line.
fn Parser::eat_semicolon_strict(self : Parser) -> Unit raise Error {
  // Consume explicit semicolon if present
  if self.eat(Semicolon) {
    return
  }
  // ASI: automatic semicolon insertion allowed when:
  // 1. Next token is }
  // 2. Next token is EOF
  if self.at(RBrace) || self.at(EOF) {
    return
  }
  // 3. Next token is on a different line than the previous token
  if self.pos > 0 {
    let prev_line = self.tokens[self.pos - 1].loc.line
    let next_line = self.peek().loc.line
    if next_line != prev_line {
      return
    }
  }
  // No valid ASI condition — raise a syntax error
  let next = self.peek()
  raise @errors.SyntaxError(
    message="Unexpected token '\{next.kind}' at line \{next.loc.line}, col \{next.loc.col}",
  )
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

///|
/// Expect the contextual keyword 'from' (which is tokenized as From)
fn Parser::expect_from(self : Parser) -> @token.Token raise Error {
  if self.at(From) {
    self.advance()
  } else {
    let tok = self.peek()
    raise @errors.SyntaxError(
      message="Expected 'from', got \{tok.kind} at line \{tok.loc.line}, col \{tok.loc.col}",
    )
  }
}

///|
/// Expect 'as' contextual keyword
fn Parser::expect_as(self : Parser) -> @token.Token raise Error {
  if self.at(As) {
    self.advance()
  } else {
    let tok = self.peek()
    raise @errors.SyntaxError(
      message="Expected 'as', got \{tok.kind} at line \{tok.loc.line}, col \{tok.loc.col}",
    )
  }
}

///|
/// Accept an identifier or a keyword-as-identifier for import/export specifiers
/// In import/export specifiers, keywords like 'default' can be used: export { x as default }
fn Parser::expect_module_export_name(self : Parser) -> String raise Error {
  let tok = self.peek()
  match tok.kind {
    Ident(name) => {
      self.pos += 1
      name
    }
    Default => {
      self.pos += 1
      "default"
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
    Let => {
      self.pos += 1
      "let"
    }
    Const => {
      self.pos += 1
      "const"
    }
    Var => {
      self.pos += 1
      "var"
    }
    Class => {
      self.pos += 1
      "class"
    }
    Function => {
      self.pos += 1
      "function"
    }
    If => {
      self.pos += 1
      "if"
    }
    Else => {
      self.pos += 1
      "else"
    }
    Return => {
      self.pos += 1
      "return"
    }
    Typeof => {
      self.pos += 1
      "typeof"
    }
    New => {
      self.pos += 1
      "new"
    }
    This => {
      self.pos += 1
      "this"
    }
    Void => {
      self.pos += 1
      "void"
    }
    Delete => {
      self.pos += 1
      "delete"
    }
    In => {
      self.pos += 1
      "in"
    }
    Instanceof => {
      self.pos += 1
      "instanceof"
    }
    Static => {
      self.pos += 1
      "static"
    }
    Import => {
      self.pos += 1
      "import"
    }
    Export => {
      self.pos += 1
      "export"
    }
    _ =>
      raise @errors.SyntaxError(
        message="Expected identifier or keyword in module specifier, got \{tok.kind} at line \{tok.loc.line}, col \{tok.loc.col}",
      )
  }
}

///|
/// Parse import declaration
/// Forms:
///   import 'source'
///   import defaultExport from 'source'
///   import { name1, name2 as alias } from 'source'
///   import * as namespace from 'source'
///   import defaultExport, { name1 } from 'source'
///   import defaultExport, * as namespace from 'source'
fn Parser::parse_import_decl(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Import)
  // import 'source' - side effect only import
  if self.peek_kind() is String_(_) {
    let source = match self.advance().kind {
      String_(s) => s
      _ => abort("unreachable")
    }
    self.eat_semicolon()
    return ImportDecl(None, [], None, source, tok.loc)
  }
  let mut default_import : String? = None
  let mut specifiers : Array[@ast.ImportSpecifier] = []
  let mut namespace_import : String? = None
  // Check for * as namespace
  if self.at(Star) {
    let _ = self.advance() // consume *
    let _ = self.expect_as()
    namespace_import = Some(self.expect_ident())
  } else if self.at(LBrace) {
    // { name1, name2 as alias }
    specifiers = self.parse_import_specifiers()
  } else {
    // default import name
    default_import = Some(self.expect_ident())
    // May be followed by , { ... } or , * as name
    if self.eat(Comma) {
      if self.at(Star) {
        let _ = self.advance() // consume *
        let _ = self.expect_as()
        namespace_import = Some(self.expect_ident())
      } else if self.at(LBrace) {
        specifiers = self.parse_import_specifiers()
      } else {
        let t = self.peek()
        raise @errors.SyntaxError(
          message="Expected '{' or '*' after ',' in import at line \{t.loc.line}, col \{t.loc.col}",
        )
      }
    }
  }
  let _ = self.expect_from()
  let source = match self.peek_kind() {
    String_(s) => {
      self.pos += 1
      s
    }
    _ => {
      let t = self.peek()
      raise @errors.SyntaxError(
        message="Expected module source string after 'from' at line \{t.loc.line}, col \{t.loc.col}",
      )
    }
  }
  self.eat_semicolon()
  // Validate: no duplicate bound names in import
  let bound_names : Map[String, Bool] = {}
  match default_import {
    Some(name) => bound_names[name] = true
    None => ()
  }
  match namespace_import {
    Some(name) =>
      if bound_names.contains(name) {
        raise @errors.SyntaxError(message="Duplicate import binding '\{name}'")
      } else {
        bound_names[name] = true
      }
    None => ()
  }
  for spec in specifiers {
    if bound_names.contains(spec.local_name) {
      raise @errors.SyntaxError(
        message="Duplicate import binding '\{spec.local_name}'",
      )
    }
    bound_names[spec.local_name] = true
  }
  ImportDecl(default_import, specifiers, namespace_import, source, tok.loc)
}

///|
/// Parse import specifiers: { name1, name2 as alias, ... }
fn Parser::parse_import_specifiers(
  self : Parser,
) -> Array[@ast.ImportSpecifier] raise Error {
  let _ = self.expect(LBrace)
  let specs : Array[@ast.ImportSpecifier] = []
  while not(self.at(RBrace)) && not(self.at(EOF)) {
    let imported = self.expect_module_export_name()
    let local_name = if self.at(As) {
      let _ = self.advance() // consume 'as'
      self.expect_ident()
    } else {
      imported
    }
    specs.push({ local_name, imported })
    if not(self.at(RBrace)) {
      let _ = self.expect(Comma)
    }
  }
  let _ = self.expect(RBrace)
  specs
}

///|
/// Parse export declaration
/// Forms:
///   export { name1, name2 as alias }
///   export { name1 } from 'source'
///   export let/const/var name = value
///   export function name() {}
///   export class Name {}
///   export default expression
///   export default function name() {}
///   export default class Name {}
///   export * from 'source'
///   export * as name from 'source'
fn Parser::parse_export_decl(self : Parser) -> @ast.Stmt raise Error {
  let tok = self.expect(Export)
  // export default ...
  if self.at(Default) {
    let _ = self.advance() // consume 'default'
    // export default function [name]() {} - name is optional
    if self.at(Function) {
      let expr = self.parse_func_expr()
      return ExportDefaultDecl(expr, tok.loc)
    }
    // export default async function [name]() {} - name is optional
    if self.is_async_function() {
      let expr = self.parse_async_func_expr()
      return ExportDefaultDecl(expr, tok.loc)
    }
    // export default class [Name] {} - name is optional
    if self.at(Class) {
      let expr = self.parse_class_expr()
      return ExportDefaultDecl(expr, tok.loc)
    }
    // export default expression
    let expr = self.parse_assignment()
    self.eat_semicolon()
    return ExportDefaultDecl(expr, tok.loc)
  }
  // export * from 'source' or export * as name from 'source'
  if self.at(Star) {
    let _ = self.advance() // consume *
    let ns_alias : String? = if self.at(As) {
      let _ = self.advance() // consume 'as'
      Some(self.expect_module_export_name())
    } else {
      None
    }
    let _ = self.expect_from()
    let source = match self.peek_kind() {
      String_(s) => {
        self.pos += 1
        s
      }
      _ => {
        let t = self.peek()
        raise @errors.SyntaxError(
          message="Expected module source string at line \{t.loc.line}, col \{t.loc.col}",
        )
      }
    }
    self.eat_semicolon()
    return ExportAllDecl(ns_alias, source, tok.loc)
  }
  // export { name1, name2 as alias } [from 'source']
  if self.at(LBrace) {
    let specs = self.parse_export_specifiers()
    let source : String? = if self.at(From) {
      let _ = self.advance() // consume 'from'
      match self.peek_kind() {
        String_(s) => {
          self.pos += 1
          Some(s)
        }
        _ => {
          let t = self.peek()
          raise @errors.SyntaxError(
            message="Expected module source string at line \{t.loc.line}, col \{t.loc.col}",
          )
        }
      }
    } else {
      None
    }
    self.eat_semicolon()
    return ExportNamedDecl(None, specs, source, tok.loc)
  }
  // export let/const/var ...
  if self.at(Let) || self.at(Const) || self.at(Var) {
    let decl = self.parse_var_decl()
    return ExportNamedDecl(Some(decl), [], None, tok.loc)
  }
  // export function name() {}
  if self.at(Function) {
    let decl = self.parse_func_decl()
    return ExportNamedDecl(Some(decl), [], None, tok.loc)
  }
  // export async function name() {}
  if self.is_async_function() {
    let decl = if self.is_async_generator() {
      self.parse_async_generator_decl()
    } else {
      self.parse_async_func_decl()
    }
    return ExportNamedDecl(Some(decl), [], None, tok.loc)
  }
  // export class Name {}
  if self.at(Class) {
    let decl = self.parse_class_decl()
    return ExportNamedDecl(Some(decl), [], None, tok.loc)
  }
  let t = self.peek()
  raise @errors.SyntaxError(
    message="Unexpected token after export at line \{t.loc.line}, col \{t.loc.col}",
  )
}

///|
/// Parse export specifiers: { name1, name2 as alias, ... }
fn Parser::parse_export_specifiers(
  self : Parser,
) -> Array[@ast.ExportSpecifier] raise Error {
  let _ = self.expect(LBrace)
  let specs : Array[@ast.ExportSpecifier] = []
  while not(self.at(RBrace)) && not(self.at(EOF)) {
    let local_name = self.expect_module_export_name()
    let exported = if self.at(As) {
      let _ = self.advance() // consume 'as'
      self.expect_module_export_name()
    } else {
      local_name
    }
    specs.push({ local_name, exported })
    if not(self.at(RBrace)) {
      let _ = self.expect(Comma)
    }
  }
  let _ = self.expect(RBrace)
  specs
}
