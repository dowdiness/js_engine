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
  setup_builtins(global, output)
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
      env.def(name, make_func(func_data), LetBinding)
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
    ThrowStmt(expr, _) => {
      let value = self.eval_expr(expr, env)
      raise JsException(value)
    }
    TryCatchStmt(try_body, catch_param, catch_body, finally_body, _) =>
      self.exec_try_catch(try_body, catch_param, catch_body, finally_body, env)
    SwitchStmt(discriminant, cases, _) => {
      let disc_val = self.eval_expr(discriminant, env)
      let mut match_idx = -1
      let mut default_idx = -1
      for i = 0; i < cases.length(); i = i + 1 {
        match cases[i].condition {
          Some(test_expr) =>
            if match_idx < 0 {
              let test_val = self.eval_expr(test_expr, env)
              if strict_equal(disc_val, test_val) {
                match_idx = i
              }
            }
          None => default_idx = i
        }
      }
      let start = if match_idx >= 0 {
        match_idx
      } else if default_idx >= 0 {
        default_idx
      } else {
        cases.length()
      }
      for i = start; i < cases.length(); i = i + 1 {
        for stmt in cases[i].body {
          match self.exec_stmt(stmt, env) {
            Normal(_) => ()
            BreakSignal => return Normal(Undefined)
            other => return other
          }
        }
      }
      Normal(Undefined)
    }
    DoWhileStmt(body, cond, _) => {
      while true {
        match self.exec_stmt(body, env) {
          Normal(_) => ()
          ReturnSignal(v) => return ReturnSignal(v)
          BreakSignal => break
          ContinueSignal => ()
        }
        if not(is_truthy(self.eval_expr(cond, env))) {
          break
        }
      }
      Normal(Undefined)
    }
    ForInStmt(var_kind, name, obj_expr, body, _) => {
      let obj = self.eval_expr(obj_expr, env)
      let keys : Array[String] = []
      match obj {
        Object(data) => data.properties.each(fn(k, _v) { keys.push(k) })
        Array(data) =>
          for i = 0; i < data.elements.length(); i = i + 1 {
            keys.push(i.to_string())
          }
        _ => ()
      }
      for key in keys {
        let body_env = Environment::new(parent=Some(env))
        match var_kind {
          Some(kind) => {
            let bk : BindingKind = match kind {
              LetKind => LetBinding
              ConstKind => ConstBinding
              VarKind => VarBinding
            }
            body_env.def(name, String_(key), bk)
          }
          None => env.assign(name, String_(key))
        }
        match self.exec_stmt(body, body_env) {
          Normal(_) => ()
          ReturnSignal(v) => return ReturnSignal(v)
          BreakSignal => break
          ContinueSignal => continue
        }
      }
      Normal(Undefined)
    }
    LabeledStmt(_, body, _) => self.exec_stmt(body, env)
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
fn Interpreter::exec_try_catch(
  self : Interpreter,
  try_body : Array[@ast.Stmt],
  catch_param : String?,
  catch_body : Array[@ast.Stmt]?,
  finally_body : Array[@ast.Stmt]?,
  env : Environment,
) -> Signal raise Error {
  let try_env = Environment::new(parent=Some(env))
  let result : Signal = self.exec_stmts(try_body, try_env) catch {
    JsException(val) =>
      match (catch_param, catch_body) {
        (Some(param), Some(body)) => {
          let catch_env = Environment::new(parent=Some(env))
          catch_env.def(param, val, LetBinding)
          self.exec_stmts(body, catch_env)
        }
        _ => Normal(Undefined)
      }
    e => raise e
  }
  match finally_body {
    Some(body) => {
      let finally_result = self.exec_stmts(
        body,
        Environment::new(parent=Some(env)),
      )
      match finally_result {
        Normal(_) => result
        other => other
      }
    }
    None => result
  }
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
      make_func(func_data)
    }
    ObjectLit(props, _) => {
      let properties : Map[String, Value] = {}
      for prop in props {
        properties[prop.key] = self.eval_expr(prop.value, env)
      }
      Object({
        properties,
        prototype: Null,
        callable: None,
        class_name: "Object",
      })
    }
    ArrayLit(elements, _) => {
      let vals : Array[Value] = elements.map(fn(e) { self.eval_expr(e, env) })
      Array({ elements: vals })
    }
    ComputedMember(obj_expr, key_expr, loc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      self.get_computed_property(obj, key, loc)
    }
    MemberAssign(obj_expr, prop, value_expr, loc) => {
      let obj = self.eval_expr(obj_expr, env)
      let value = self.eval_expr(value_expr, env)
      match obj {
        Object(data) => {
          data.properties[prop] = value
          value
        }
        _ =>
          raise Failure::Failure(
            "Cannot set property '\{prop}' of \{type_of(obj)} at line \{loc.line}, col \{loc.col}",
          )
      }
    }
    ComputedAssign(obj_expr, key_expr, value_expr, loc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let value = self.eval_expr(value_expr, env)
      match obj {
        Object(data) => {
          data.properties[key.to_string()] = value
          value
        }
        Array(data) =>
          match key {
            Number(n) => {
              let i = n.to_int()
              if i >= 0 {
                while data.elements.length() <= i {
                  data.elements.push(Undefined)
                }
                data.elements[i] = value
              }
              value
            }
            _ => value
          }
        _ =>
          raise Failure::Failure(
            "Cannot set property of \{type_of(obj)} at line \{loc.line}, col \{loc.col}",
          )
      }
    }
    NewExpr(callee_expr, arg_exprs, loc) =>
      self.eval_new(callee_expr, arg_exprs, env, loc)
    ThisExpr(_) => env.get("this") catch { _ => Undefined }
    UpdateExpr(op, operand, prefix, loc) =>
      self.eval_update(op, operand, prefix, env, loc)
    CompoundAssign(op, target, value_expr, loc) =>
      self.eval_compound_assign(op, target, value_expr, env, loc)
    Comma(left, right, _) => {
      let _ = self.eval_expr(left, env)
      self.eval_expr(right, env)
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
    // Comparison (numeric)
    (Lt, Number(a), Number(b)) => Bool(a < b)
    (Gt, Number(a), Number(b)) => Bool(a > b)
    (LtEq, Number(a), Number(b)) => Bool(a <= b)
    (GtEq, Number(a), Number(b)) => Bool(a >= b)
    // Comparison (string — lexicographic)
    (Lt, String_(a), String_(b)) => Bool(a < b)
    (Gt, String_(a), String_(b)) => Bool(a > b)
    (LtEq, String_(a), String_(b)) => Bool(a <= b)
    (GtEq, String_(a), String_(b)) => Bool(a >= b)
    // Equality
    (EqEqEq, l, r) => Bool(strict_equal(l, r))
    (NotEqEq, l, r) => Bool(not(strict_equal(l, r)))
    (EqEq, l, r) => Bool(loose_equal(l, r))
    (NotEq, l, r) => Bool(not(loose_equal(l, r)))
    // Arithmetic fallbacks (type coercion)
    (Add, l, r) => Number(to_number(l) + to_number(r))
    (Sub, l, r) => Number(to_number(l) - to_number(r))
    (Mul, l, r) => Number(to_number(l) * to_number(r))
    (Div, l, r) => Number(to_number(l) / to_number(r))
    (Mod, l, r) => Number(to_number(l) % to_number(r))
    // Comparison fallbacks (type coercion)
    (Lt, l, r) => Bool(to_number(l) < to_number(r))
    (Gt, l, r) => Bool(to_number(l) > to_number(r))
    (LtEq, l, r) => Bool(to_number(l) <= to_number(r))
    (GtEq, l, r) => Bool(to_number(l) >= to_number(r))
    // Bitwise operations
    (BitAnd, l, r) =>
      Number(to_int32(to_number(l)).land(to_int32(to_number(r))).to_double())
    (BitOr, l, r) =>
      Number(to_int32(to_number(l)).lor(to_int32(to_number(r))).to_double())
    (BitXor, l, r) =>
      Number(to_int32(to_number(l)).lxor(to_int32(to_number(r))).to_double())
    // Shift operations
    (LShift, l, r) => {
      let a = to_int32(to_number(l))
      let shift = to_int32(to_number(r)) & 0x1f
      Number((a << shift).to_double())
    }
    (RShift, l, r) => {
      let a = to_int32(to_number(l))
      let shift = to_int32(to_number(r)) & 0x1f
      Number((a >> shift).to_double())
    }
    (URShift, l, r) => {
      let a = to_int32(to_number(l))
      let shift = to_int32(to_number(r)) & 0x1f
      if shift == 0 {
        if a < 0 {
          Number(a.to_double() + 4294967296.0)
        } else {
          Number(a.to_double())
        }
      } else {
        let shifted = a >> shift
        let all_bits : Int = 0x7FFFFFFF
        let mask = all_bits >> (shift - 1)
        Number(shifted.land(mask).to_double())
      }
    }
    // in operator
    (In, l, r) =>
      match r {
        Object(data) => Bool(data.properties.contains(l.to_string()))
        Array(data) => {
          let idx = to_number(l).to_int()
          Bool(idx >= 0 && idx < data.elements.length())
        }
        _ =>
          raise Failure::Failure(
            "Cannot use 'in' operator with \{type_of(r)} at line \{loc.line}, col \{loc.col}",
          )
      }
    // instanceof
    (Instanceof, l, r) =>
      match r {
        Object(r_data) => {
          let target_proto = match r_data.properties.get("prototype") {
            Some(v) => v
            None => Null
          }
          match l {
            Object(l_data) => {
              let mut current = l_data.prototype
              let mut found = false
              while true {
                match current {
                  Null | Undefined => break
                  _ =>
                    if strict_equal(current, target_proto) {
                      found = true
                      break
                    } else {
                      match current {
                        Object(data) => current = data.prototype
                        _ => break
                      }
                    }
                }
              }
              Bool(found)
            }
            _ => Bool(false)
          }
        }
        _ =>
          raise Failure::Failure(
            "Right-hand side of instanceof is not callable at line \{loc.line}, col \{loc.col}",
          )
      }
    // And/Or already handled by short-circuit
    (And, _, _) | (Or, _, _) =>
      raise Failure::Failure(
        "Internal error: logical operators should be short-circuited",
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
  match op {
    Typeof =>
      match operand {
        Ident(name, _) =>
          if env.has(name) {
            String_(type_of(env.get(name)))
          } else {
            String_("undefined")
          }
        _ => String_(type_of(self.eval_expr(operand, env)))
      }
    Void => {
      let _ = self.eval_expr(operand, env)
      Undefined
    }
    Delete =>
      match operand {
        Member(obj_expr, prop, _) => {
          let obj = self.eval_expr(obj_expr, env)
          match obj {
            Object(data) => {
              let _ = data.properties.remove(prop)
              Bool(true)
            }
            _ => Bool(true)
          }
        }
        ComputedMember(obj_expr, key_expr, _) => {
          let obj = self.eval_expr(obj_expr, env)
          let key = self.eval_expr(key_expr, env)
          match obj {
            Object(data) => {
              let _ = data.properties.remove(key.to_string())
              Bool(true)
            }
            _ => Bool(true)
          }
        }
        _ => Bool(true)
      }
    _ => {
      let val = self.eval_expr(operand, env)
      match op {
        Neg => Number(-to_number(val))
        Not => Bool(not(is_truthy(val)))
        BitNot => Number(to_int32(to_number(val)).lnot().to_double())
        _ =>
          raise Failure::Failure(
            "Unexpected unary operator at line \{loc.line}, col \{loc.col}",
          )
      }
    }
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
  let args : Array[Value] = arg_exprs.map(fn(a) { self.eval_expr(a, env) })
  match callee_expr {
    Member(obj_expr, prop, mloc) =>
      match obj_expr {
        Ident("console", _) => {
          let callee = self.eval_member(obj_expr, prop, env, mloc)
          self.call_value(callee, Undefined, args, loc)
        }
        _ => {
          let obj = self.eval_expr(obj_expr, env)
          let func_val = self.get_property(obj, prop, mloc)
          self.call_value(func_val, obj, args, loc)
        }
      }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let func_val = self.get_computed_property(obj, key, mloc)
      self.call_value(func_val, obj, args, loc)
    }
    _ => {
      let callee = self.eval_expr(callee_expr, env)
      self.call_value(callee, Undefined, args, loc)
    }
  }
}

///|
fn Interpreter::call_value(
  self : Interpreter,
  callee : Value,
  this_val : Value,
  args : Array[Value],
  loc : @token.Loc,
) -> Value raise Error {
  match callee {
    Object(obj_data) =>
      match obj_data.callable {
        Some(UserFunc(data)) => {
          let func_env = Environment::new(parent=Some(data.closure))
          func_env.def("this", this_val, LetBinding)
          for i = 0; i < data.params.length(); i = i + 1 {
            let val : Value = if i < args.length() {
              args[i]
            } else {
              Undefined
            }
            func_env.def(data.params[i], val, LetBinding)
          }
          match data.name {
            Some(name) =>
              if not(func_env.bindings.contains(name)) {
                func_env.def(name, callee, LetBinding)
              }
            None => ()
          }
          match self.exec_stmts(data.body, func_env) {
            Normal(v) => v
            ReturnSignal(v) => v
            BreakSignal =>
              raise Failure::Failure("break statement outside of loop")
            ContinueSignal =>
              raise Failure::Failure("continue statement outside of loop")
          }
        }
        Some(NativeCallable(_, func)) => func(args)
        None =>
          raise Failure::Failure(
            "Not a function at line \{loc.line}, col \{loc.col}",
          )
      }
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
  loc : @token.Loc,
) -> Value raise Error {
  // Special case: console.log
  match obj_expr {
    Ident("console", _) =>
      if prop == "log" {
        let output = self.output
        make_native_func("log", fn(args) {
          let parts : Array[String] = args.map(fn(a) { a.to_string() })
          output.push(parts.join(" "))
          Undefined
        })
      } else {
        raise Failure::Failure("console.\{prop} is not supported")
      }
    _ => {
      let obj = self.eval_expr(obj_expr, env)
      self.get_property(obj, prop, loc)
    }
  }
}

///|
fn Interpreter::get_property(
  _self : Interpreter,
  obj : Value,
  prop : String,
  loc : @token.Loc,
) -> Value raise Error {
  match obj {
    Object(data) =>
      match data.properties.get(prop) {
        Some(v) => v
        None => Undefined
      }
    Array(data) =>
      if prop == "length" {
        Number(data.elements.length().to_double())
      } else {
        Undefined
      }
    String_(s) =>
      if prop == "length" {
        Number(s.length().to_double())
      } else {
        Undefined
      }
    Null | Undefined =>
      raise Failure::Failure(
        "Cannot read property '\{prop}' of \{type_of(obj)} at line \{loc.line}, col \{loc.col}",
      )
    _ => Undefined
  }
}

///|
fn Interpreter::get_computed_property(
  _self : Interpreter,
  obj : Value,
  key : Value,
  loc : @token.Loc,
) -> Value raise Error {
  match obj {
    Object(data) => {
      let prop = key.to_string()
      match data.properties.get(prop) {
        Some(v) => v
        None => Undefined
      }
    }
    Array(data) =>
      match key {
        Number(n) => {
          let i = n.to_int()
          if i >= 0 && i < data.elements.length() {
            data.elements[i]
          } else {
            Undefined
          }
        }
        String_("length") => Number(data.elements.length().to_double())
        _ => Undefined
      }
    String_(s) =>
      match key {
        Number(n) => {
          let i = n.to_int()
          if i >= 0 && i < s.length() {
            let buf = StringBuilder::new()
            buf.write_char(s.to_array()[i])
            String_(buf.to_string())
          } else {
            Undefined
          }
        }
        String_("length") => Number(s.length().to_double())
        _ => Undefined
      }
    Null | Undefined =>
      raise Failure::Failure(
        "Cannot read property of \{type_of(obj)} at line \{loc.line}, col \{loc.col}",
      )
    _ => Undefined
  }
}

///|
fn Interpreter::eval_new(
  self : Interpreter,
  callee_expr : @ast.Expr,
  arg_exprs : Array[@ast.Expr],
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  let ctor = self.eval_expr(callee_expr, env)
  let args : Array[Value] = arg_exprs.map(fn(a) { self.eval_expr(a, env) })
  match ctor {
    Object(obj_data) =>
      match obj_data.callable {
        Some(UserFunc(data)) => {
          let proto = match obj_data.properties.get("prototype") {
            Some(v) => v
            None => Null
          }
          let new_obj = Object({
            properties: {},
            prototype: proto,
            callable: None,
            class_name: "Object",
          })
          let func_env = Environment::new(parent=Some(data.closure))
          func_env.def("this", new_obj, LetBinding)
          for i = 0; i < data.params.length(); i = i + 1 {
            let val : Value = if i < args.length() {
              args[i]
            } else {
              Undefined
            }
            func_env.def(data.params[i], val, LetBinding)
          }
          match data.name {
            Some(name) =>
              if not(func_env.bindings.contains(name)) {
                func_env.def(name, ctor, LetBinding)
              }
            None => ()
          }
          let result = self.exec_stmts(data.body, func_env)
          match result {
            Normal(_) => new_obj
            ReturnSignal(v) =>
              match v {
                Object(_) => v
                _ => new_obj
              }
            BreakSignal =>
              raise Failure::Failure("break statement outside of loop")
            ContinueSignal =>
              raise Failure::Failure("continue statement outside of loop")
          }
        }
        Some(NativeCallable(_, func)) => func(args)
        _ =>
          raise Failure::Failure(
            "Not a constructor at line \{loc.line}, col \{loc.col}",
          )
      }
    _ =>
      raise Failure::Failure(
        "Not a constructor at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
fn Interpreter::eval_update(
  self : Interpreter,
  op : @ast.UpdateOp,
  operand : @ast.Expr,
  prefix : Bool,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  let current = self.eval_expr(operand, env)
  let num = to_number(current)
  let new_val : Value = match op {
    Increment => Number(num + 1.0)
    Decrement => Number(num - 1.0)
  }
  match operand {
    Ident(name, _) => env.assign(name, new_val)
    Member(obj_expr, prop, _) => {
      let obj = self.eval_expr(obj_expr, env)
      match obj {
        Object(data) => data.properties[prop] = new_val
        _ =>
          raise Failure::Failure(
            "Invalid update target at line \{loc.line}, col \{loc.col}",
          )
      }
    }
    ComputedMember(obj_expr, key_expr, _) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      match obj {
        Object(data) => data.properties[key.to_string()] = new_val
        Array(data) =>
          match key {
            Number(n) => {
              let i = n.to_int()
              if i >= 0 && i < data.elements.length() {
                data.elements[i] = new_val
              }
            }
            _ => ()
          }
        _ =>
          raise Failure::Failure(
            "Invalid update target at line \{loc.line}, col \{loc.col}",
          )
      }
    }
    _ =>
      raise Failure::Failure(
        "Invalid update target at line \{loc.line}, col \{loc.col}",
      )
  }
  if prefix {
    new_val
  } else {
    Number(num)
  }
}

///|
fn Interpreter::eval_compound_assign(
  self : Interpreter,
  op : @ast.CompoundOp,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  let current = self.eval_expr(target, env)
  let rhs = self.eval_expr(value_expr, env)
  let bin_op : @ast.BinOp = match op {
    AddAssign => Add
    SubAssign => Sub
    MulAssign => Mul
    DivAssign => Div
    ModAssign => Mod
    BitAndAssign => BitAnd
    BitOrAssign => BitOr
    BitXorAssign => BitXor
    LShiftAssign => LShift
    RShiftAssign => RShift
    URShiftAssign => URShift
  }
  let result = eval_binary_op(bin_op, current, rhs, loc)
  match target {
    Ident(name, _) => {
      env.assign(name, result)
      result
    }
    Member(obj_expr, prop, _) => {
      let obj = self.eval_expr(obj_expr, env)
      match obj {
        Object(data) => {
          data.properties[prop] = result
          result
        }
        _ =>
          raise Failure::Failure(
            "Cannot set property at line \{loc.line}, col \{loc.col}",
          )
      }
    }
    ComputedMember(obj_expr, key_expr, _) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      match obj {
        Object(data) => {
          data.properties[key.to_string()] = result
          result
        }
        Array(data) =>
          match key {
            Number(n) => {
              let i = n.to_int()
              if i >= 0 && i < data.elements.length() {
                data.elements[i] = result
              }
              result
            }
            _ => result
          }
        _ =>
          raise Failure::Failure(
            "Cannot set property at line \{loc.line}, col \{loc.col}",
          )
      }
    }
    _ =>
      raise Failure::Failure(
        "Invalid compound assignment target at line \{loc.line}, col \{loc.col}",
      )
  }
}
