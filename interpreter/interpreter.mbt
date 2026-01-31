///|
pub(all) enum Signal {
  Normal(Value)
  ReturnSignal(Value)
  BreakSignal
  ContinueSignal
}

///|
pub(all) struct Interpreter {
  output : Array[String]
  global : Environment
}

///|
pub fn Interpreter::new() -> Interpreter {
  let global = Environment::new()
  let output : Array[String] = []
  { output, global }
}

///|
pub fn Interpreter::run(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> Value raise Error {
  let mut last : Value = Undefined
  for stmt in stmts {
    match self.exec_stmt(stmt, self.global) {
      Normal(v) => last = v
      ReturnSignal(_) =>
        raise Failure::Failure("return statement outside of function")
      BreakSignal => raise Failure::Failure("break statement outside of loop")
      ContinueSignal =>
        raise Failure::Failure("continue statement outside of loop")
    }
  }
  last
}

///|
fn Interpreter::exec_stmt(
  self : Interpreter,
  stmt : @ast.Stmt,
  env : Environment,
) -> Signal raise Error {
  match stmt {
    ExprStmt(expr, _) => Normal(self.eval_expr(expr, env))
    VarDecl(kind, name, init, _) => {
      let bk : BindingKind = match kind {
        LetKind => LetBinding
        ConstKind => ConstBinding
        VarKind => VarBinding
      }
      let value : Value = match init {
        Some(expr) => self.eval_expr(expr, env)
        None => Undefined
      }
      env.def(name, value, bk)
      Normal(Undefined)
    }
    Block(stmts, _) => {
      let block_env = Environment::new(parent=Some(env))
      self.exec_stmts(stmts, block_env)
    }
    IfStmt(cond, then_branch, else_branch, _) => {
      let cond_val = self.eval_expr(cond, env)
      if is_truthy(cond_val) {
        self.exec_stmt(then_branch, env)
      } else {
        match else_branch {
          Some(eb) => self.exec_stmt(eb, env)
          None => Normal(Undefined)
        }
      }
    }
    WhileStmt(cond, body, _) => {
      while is_truthy(self.eval_expr(cond, env)) {
        match self.exec_stmt(body, env) {
          Normal(_) => ()
          ReturnSignal(v) => return ReturnSignal(v)
          BreakSignal => break
          ContinueSignal => continue
        }
      }
      Normal(Undefined)
    }
    ForStmt(init, cond, update, body, _) => {
      let for_env = Environment::new(parent=Some(env))
      match init {
        Some(init_stmt) => {
          let _ = self.exec_stmt(init_stmt, for_env)

        }
        None => ()
      }
      while true {
        match cond {
          Some(c) => if not(is_truthy(self.eval_expr(c, for_env))) { break }
          None => ()
        }
        match self.exec_stmt(body, for_env) {
          Normal(_) => ()
          ReturnSignal(v) => return ReturnSignal(v)
          BreakSignal => break
          ContinueSignal => ()
        }
        match update {
          Some(u) => {
            let _ = self.eval_expr(u, for_env)

          }
          None => ()
        }
      }
      Normal(Undefined)
    }
    FuncDecl(name, params, body, _) => {
      let func_data : FuncData = {
        name: Some(name),
        params,
        body,
        closure: env,
      }
      env.def(name, Function(func_data), LetBinding)
      Normal(Undefined)
    }
    ReturnStmt(expr, _) => {
      let value : Value = match expr {
        Some(e) => self.eval_expr(e, env)
        None => Undefined
      }
      ReturnSignal(value)
    }
    BreakStmt(_) => BreakSignal
    ContinueStmt(_) => ContinueSignal
  }
}

///|
fn Interpreter::exec_stmts(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  env : Environment,
) -> Signal raise Error {
  let mut last : Value = Undefined
  for stmt in stmts {
    match self.exec_stmt(stmt, env) {
      Normal(v) => last = v
      other => return other
    }
  }
  Normal(last)
}

///|
fn Interpreter::eval_expr(
  self : Interpreter,
  expr : @ast.Expr,
  env : Environment,
) -> Value raise Error {
  match expr {
    NumberLit(n, _) => Number(n)
    StringLit(s, _) => String_(s)
    BoolLit(b, _) => Bool(b)
    NullLit(_) => Null
    UndefinedLit(_) => Undefined
    Ident(name, _) => env.get(name)
    Grouping(e, _) => self.eval_expr(e, env)
    Binary(op, left, right, loc) => self.eval_binary(op, left, right, env, loc)
    Unary(op, operand, loc) => self.eval_unary(op, operand, env, loc)
    Assign(name, value_expr, _) => {
      let value = self.eval_expr(value_expr, env)
      env.assign(name, value)
      value
    }
    Ternary(cond, then_expr, else_expr, _) =>
      if is_truthy(self.eval_expr(cond, env)) {
        self.eval_expr(then_expr, env)
      } else {
        self.eval_expr(else_expr, env)
      }
    Call(callee, args, loc) => self.eval_call(callee, args, env, loc)
    Member(obj_expr, prop, loc) => self.eval_member(obj_expr, prop, env, loc)
    FuncExpr(name, params, body, _) => {
      let func_data : FuncData = { name, params, body, closure: env }
      Function(func_data)
    }
  }
}

///|
fn Interpreter::eval_binary(
  self : Interpreter,
  op : @ast.BinOp,
  left_expr : @ast.Expr,
  right_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // Short-circuit for && and ||
  match op {
    And => {
      let left = self.eval_expr(left_expr, env)
      if not(is_truthy(left)) {
        return left
      }
      self.eval_expr(right_expr, env)
    }
    Or => {
      let left = self.eval_expr(left_expr, env)
      if is_truthy(left) {
        return left
      }
      self.eval_expr(right_expr, env)
    }
    _ => {
      let left = self.eval_expr(left_expr, env)
      let right = self.eval_expr(right_expr, env)
      eval_binary_op(op, left, right, loc)
    }
  }
}

///|
fn eval_binary_op(
  op : @ast.BinOp,
  left : Value,
  right : Value,
  loc : @token.Loc,
) -> Value raise Error {
  match (op, left, right) {
    // String concatenation
    (Add, String_(a), String_(b)) => String_(a + b)
    (Add, String_(a), b) => String_(a + b.to_string())
    (Add, a, String_(b)) => String_(a.to_string() + b)
    // Numeric operations
    (Add, Number(a), Number(b)) => Number(a + b)
    (Sub, Number(a), Number(b)) => Number(a - b)
    (Mul, Number(a), Number(b)) => Number(a * b)
    (Div, Number(a), Number(b)) => Number(a / b)
    (Mod, Number(a), Number(b)) => Number(a % b)
    // Comparison
    (Lt, Number(a), Number(b)) => Bool(a < b)
    (Gt, Number(a), Number(b)) => Bool(a > b)
    (LtEq, Number(a), Number(b)) => Bool(a <= b)
    (GtEq, Number(a), Number(b)) => Bool(a >= b)
    // Equality
    (EqEqEq, l, r) => Bool(strict_equal(l, r))
    (NotEqEq, l, r) => Bool(not(strict_equal(l, r)))
    (EqEq, l, r) => Bool(loose_equal(l, r))
    (NotEq, l, r) => Bool(not(loose_equal(l, r)))
    // And/Or already handled by short-circuit
    (And, _, _) | (Or, _, _) =>
      raise Failure::Failure(
        "Internal error: logical operators should be short-circuited",
      )
    _ =>
      raise Failure::Failure(
        "Invalid binary operation at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
fn strict_equal(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Number(a), Number(b)) => a == b
    (String_(a), String_(b)) => a == b
    (Bool(a), Bool(b)) => a == b
    (Null, Null) => true
    (Undefined, Undefined) => true
    _ => false
  }
}

///|
fn loose_equal(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Null, Undefined) | (Undefined, Null) => true
    _ => strict_equal(a, b)
  }
}

///|
fn Interpreter::eval_unary(
  self : Interpreter,
  op : @ast.UnaryOp,
  operand : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  let val = self.eval_expr(operand, env)
  match op {
    Neg =>
      match val {
        Number(n) => Number(-n)
        _ =>
          raise Failure::Failure(
            "Cannot negate non-number at line \{loc.line}, col \{loc.col}",
          )
      }
    Not => Bool(not(is_truthy(val)))
    Typeof => String_(type_of(val))
  }
}

///|
fn Interpreter::eval_call(
  self : Interpreter,
  callee_expr : @ast.Expr,
  arg_exprs : Array[@ast.Expr],
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  let callee = self.eval_expr(callee_expr, env)
  let args : Array[Value] = arg_exprs.map(fn(a) { self.eval_expr(a, env) })
  match callee {
    Function(data) => {
      let func_env = Environment::new(parent=Some(data.closure))
      // Bind params
      for i = 0; i < data.params.length(); i = i + 1 {
        let val : Value = if i < args.length() { args[i] } else { Undefined }
        func_env.def(data.params[i], val, LetBinding)
      }
      // If function is named, bind it in its own scope for recursion
      match data.name {
        Some(name) =>
          if not(func_env.bindings.contains(name)) {
            func_env.def(name, Function(data), LetBinding)
          }
        None => ()
      }
      match self.exec_stmts(data.body, func_env) {
        Normal(v) => v
        ReturnSignal(v) => v
        BreakSignal => raise Failure::Failure("break statement outside of loop")
        ContinueSignal =>
          raise Failure::Failure("continue statement outside of loop")
      }
    }
    NativeFunc(_, func) => func(args)
    _ =>
      raise Failure::Failure(
        "Not a function at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
fn Interpreter::eval_member(
  self : Interpreter,
  obj_expr : @ast.Expr,
  prop : String,
  env : Environment,
  _loc : @token.Loc,
) -> Value raise Error {
  // Special case: console.log
  match obj_expr {
    Ident("console", _) =>
      if prop == "log" {
        let output = self.output
        NativeFunc("log", fn(args) {
          let parts : Array[String] = args.map(fn(a) { a.to_string() })
          output.push(parts.join(" "))
          Undefined
        })
      } else {
        raise Failure::Failure("console.\{prop} is not supported")
      }
    _ => {
      // For non-console members, evaluate the object
      let _obj = self.eval_expr(obj_expr, env)
      raise Failure::Failure(
        "Member access on non-console objects is not supported",
      )
    }
  }
}
