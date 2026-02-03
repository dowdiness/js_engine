///|
pub(all) enum Signal {
  Normal(Value)
  ReturnSignal(Value)
  BreakSignal(String?)
  ContinueSignal(String?)
}

///|
pub(all) struct Interpreter {
  output : Array[String]
  global : Environment
  global_this : Value
  mut strict : Bool
}

///|
pub fn Interpreter::new() -> Interpreter {
  let global = Environment::new()
  let output : Array[String] = []
  // Create global object for 'this' in global context
  let global_this : Value = Object(
    {
      properties: {},
      prototype: Null,
      callable: None,
      class_name: "global",
      descriptors: {},
      extensible: true,
    },
  )
  setup_builtins(global, output)
  // Bind 'this' and 'globalThis' in global scope
  global.def_builtin("this", global_this)
  global.def_builtin("globalThis", global_this)
  { output, global, global_this, strict: false }
}

///|
fn has_use_strict(stmts : Array[@ast.Stmt]) -> Bool {
  if stmts.length() > 0 {
    match stmts[0] {
      ExprStmt(StringLit("use strict", _), _) => true
      _ => false
    }
  } else {
    false
  }
}

///|
pub fn Interpreter::run(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> Value raise Error {
  // Check for "use strict" directive
  if has_use_strict(stmts) {
    self.strict = true
  }
  // Hoist var declarations and function declarations at global level
  self.hoist_declarations(stmts, self.global)
  let mut last : Value = Undefined
  for stmt in stmts {
    match self.exec_stmt(stmt, self.global) {
      Normal(v) => last = v
      ReturnSignal(_) =>
        raise Failure::Failure("return statement outside of function")
      BreakSignal(_) =>
        raise Failure::Failure("break statement outside of loop")
      ContinueSignal(_) =>
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
  label? : String? = None,
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
      // For var declarations that were hoisted, use assign instead of def
      if bk == VarBinding && env.bindings.contains(name) {
        if init is Some(_) {
          env.assign(name, value)
        }
      } else if (bk == LetBinding || bk == ConstBinding) &&
        env.bindings.contains(name) {
        // let/const hoisted with TDZ - initialize it
        env.initialize(name, value)
      } else {
        env.def(name, value, bk)
      }
      Normal(Undefined)
    }
    Block(stmts, _) => {
      let block_env = Environment::new(parent=Some(env))
      // Hoist let/const with TDZ markers
      hoist_block_tdz(stmts, block_env)
      self.exec_stmts(stmts, block_env)
    }
    StmtList(stmts, _) => {
      // Execute statements in same scope (no new environment)
      // Used for comma-separated declarations like: var a, b, c;
      self.exec_stmts(stmts, env)
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
          BreakSignal(None) => break
          BreakSignal(Some(l)) =>
            if label == Some(l) {
              break
            } else {
              return BreakSignal(Some(l))
            }
          ContinueSignal(None) => continue
          ContinueSignal(Some(l)) =>
            if label == Some(l) {
              continue
            } else {
              return ContinueSignal(Some(l))
            }
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
        let mut do_continue = false
        match self.exec_stmt(body, for_env) {
          Normal(_) => ()
          ReturnSignal(v) => return ReturnSignal(v)
          BreakSignal(None) => break
          BreakSignal(Some(l)) =>
            if label == Some(l) {
              break
            } else {
              return BreakSignal(Some(l))
            }
          ContinueSignal(None) => do_continue = true
          ContinueSignal(Some(l)) =>
            if label == Some(l) {
              do_continue = true
            } else {
              return ContinueSignal(Some(l))
            }
        }
        if do_continue {
          match update {
            Some(u) => {
              let _ = self.eval_expr(u, for_env)

            }
            None => ()
          }
          continue
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
      // If already hoisted, just assign; otherwise define
      if env.bindings.contains(name) {
        env.assign(name, make_func(func_data))
      } else {
        env.def(name, make_func(func_data), VarBinding)
      }
      Normal(Undefined)
    }
    ReturnStmt(expr, _) => {
      let value : Value = match expr {
        Some(e) => self.eval_expr(e, env)
        None => Undefined
      }
      ReturnSignal(value)
    }
    BreakStmt(label, _) => BreakSignal(label)
    ContinueStmt(label, _) => ContinueSignal(label)
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
            BreakSignal(None) => return Normal(Undefined)
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
          BreakSignal(None) => break
          BreakSignal(Some(l)) =>
            if label == Some(l) {
              break
            } else {
              return BreakSignal(Some(l))
            }
          ContinueSignal(None) => ()
          ContinueSignal(Some(l)) =>
            if label == Some(l) {
              // continue — fall through to condition check
            } else {
              return ContinueSignal(Some(l))
            }
        }
        if not(is_truthy(self.eval_expr(cond, env))) {
          break
        }
      }
      Normal(Undefined)
    }
    ForInStmt(var_kind, name, obj_expr, body, _) => {
      let obj = self.eval_expr(obj_expr, env)
      let keys = collect_for_in_keys(obj)
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
          BreakSignal(None) => break
          BreakSignal(Some(l)) =>
            if label == Some(l) {
              break
            } else {
              return BreakSignal(Some(l))
            }
          ContinueSignal(None) => continue
          ContinueSignal(Some(l)) =>
            if label == Some(l) {
              continue
            } else {
              return ContinueSignal(Some(l))
            }
        }
      }
      Normal(Undefined)
    }
    ForOfStmt(var_kind, name, iterable_expr, body, _) => {
      let iterable = self.eval_expr(iterable_expr, env)
      let items : Array[Value] = match iterable {
        Array(data) => {
          let result : Array[Value] = []
          for el in data.elements {
            result.push(el)
          }
          result
        }
        String_(s) => {
          let result : Array[Value] = []
          let chars = s.to_array()
          for c in chars {
            let buf = StringBuilder::new()
            buf.write_char(c)
            result.push(String_(buf.to_string()))
          }
          result
        }
        _ =>
          raise JsException(
            String_("TypeError: is not iterable"),
          )
      }
      for item in items {
        let body_env = Environment::new(parent=Some(env))
        match var_kind {
          Some(VarKind) =>
            if env.bindings.contains(name) {
              env.assign(name, item)
            } else {
              env.def(name, item, VarBinding)
            }
          Some(kind) => {
            let bk : BindingKind = match kind {
              LetKind => LetBinding
              ConstKind => ConstBinding
              _ => fail("unreachable")
            }
            body_env.def(name, item, bk)
          }
          None => env.assign(name, item)
        }
        match self.exec_stmt(body, body_env) {
          Normal(_) => ()
          ReturnSignal(v) => return ReturnSignal(v)
          BreakSignal(None) => break
          BreakSignal(Some(l)) =>
            if label == Some(l) {
              break
            } else {
              return BreakSignal(Some(l))
            }
          ContinueSignal(None) => continue
          ContinueSignal(Some(l)) =>
            if label == Some(l) {
              continue
            } else {
              return ContinueSignal(Some(l))
            }
        }
      }
      Normal(Undefined)
    }
    DestructureDecl(kind, pattern, init_expr, _) => {
      let bk : BindingKind = match kind {
        LetKind => LetBinding
        ConstKind => ConstBinding
        VarKind => VarBinding
      }
      let value = self.eval_expr(init_expr, env)
      self.bind_pattern(pattern, value, env, bk)
      Normal(Undefined)
    }
    FuncDeclExt(name, params, rest_param, body, _) => {
      let func_data : FuncDataExt = {
        name: Some(name),
        params,
        rest_param,
        body,
        closure: env,
      }
      if env.bindings.contains(name) {
        env.assign(name, make_func_ext(func_data))
      } else {
        env.def(name, make_func_ext(func_data), VarBinding)
      }
      Normal(Undefined)
    }
    LabeledStmt(lbl, body, _) =>
      match self.exec_stmt(body, env, label=Some(lbl)) {
        BreakSignal(Some(l)) =>
          if l == lbl {
            Normal(Undefined)
          } else {
            BreakSignal(Some(l))
          }
        other => other
      }
  }
}

///|
fn collect_for_in_keys(obj : Value) -> Array[String] {
  let keys : Array[String] = []
  let seen : Map[String, Bool] = {}
  let mut current = obj
  while true {
    match current {
      Object(data) => {
        data.properties.each(fn(k, _v) {
          if not(seen.contains(k)) {
            seen[k] = true
            let enumerable = match data.descriptors.get(k) {
              Some(d) => d.enumerable
              None => true
            }
            if enumerable {
              keys.push(k)
            }
          }
        })
        current = data.prototype
      }
      Array(data) => {
        for i = 0; i < data.elements.length(); i = i + 1 {
          let k = i.to_string()
          if not(seen.contains(k)) {
            seen[k] = true
            keys.push(k)
          }
        }
        break
      }
      _ => break
    }
  }
  keys
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
fn hoist_pattern(pattern : @ast.Pattern, env : Environment) -> Unit raise Error {
  match pattern {
    IdentPat(name) =>
      if not(env.bindings.contains(name)) {
        env.def(name, Undefined, VarBinding)
      }
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => hoist_pattern(p, env)
          None => ()
        }
      }
      match rest {
        Some(p) => hoist_pattern(p, env)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        hoist_pattern(prop.value, env)
      }
      match rest {
        Some(p) => hoist_pattern(p, env)
        None => ()
      }
    }
  }
}

///|
fn Interpreter::hoist_declarations(
  _self : Interpreter,
  stmts : Array[@ast.Stmt],
  env : Environment,
) -> Unit raise Error {
  for stmt in stmts {
    match stmt {
      VarDecl(VarKind, name, _, _) =>
        if not(env.bindings.contains(name)) {
          env.def(name, Undefined, VarBinding)
        }
      FuncDecl(name, params, body, _) => {
        let func_data : FuncData = {
          name: Some(name),
          params,
          body,
          closure: env,
        }
        if env.bindings.contains(name) {
          env.assign(name, make_func(func_data))
        } else {
          env.def(name, make_func(func_data), VarBinding)
        }
      }
      FuncDeclExt(name, params, rest_param, body, _) => {
        let func_data : FuncDataExt = {
          name: Some(name),
          params,
          rest_param,
          body,
          closure: env,
        }
        if env.bindings.contains(name) {
          env.assign(name, make_func_ext(func_data))
        } else {
          env.def(name, make_func_ext(func_data), VarBinding)
        }
      }
      DestructureDecl(VarKind, pattern, _, _) => hoist_pattern(pattern, env)
      StmtList(inner_stmts, _) => {
        // Recursively hoist declarations from StmtList (comma-separated decls)
        for inner in inner_stmts {
          match inner {
            VarDecl(VarKind, name, _, _) =>
              if not(env.bindings.contains(name)) {
                env.def(name, Undefined, VarBinding)
              }
            DestructureDecl(VarKind, pattern, _, _) => hoist_pattern(pattern, env)
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
}

///| Hoist let/const declarations with TDZ markers at block scope
fn hoist_block_tdz(stmts : Array[@ast.Stmt], env : Environment) -> Unit raise Error {
  for stmt in stmts {
    match stmt {
      VarDecl(LetKind, name, _, _) =>
        if not(env.bindings.contains(name)) {
          env.def_tdz(name, LetBinding)
        }
      VarDecl(ConstKind, name, _, _) =>
        if not(env.bindings.contains(name)) {
          env.def_tdz(name, ConstBinding)
        }
      // DestructureDecl with let/const also needs TDZ
      DestructureDecl(LetKind, pattern, _, _) =>
        hoist_pattern_tdz(pattern, env, LetBinding)
      DestructureDecl(ConstKind, pattern, _, _) =>
        hoist_pattern_tdz(pattern, env, ConstBinding)
      _ => ()
    }
  }
}

///| Hoist pattern bindings with TDZ markers
fn hoist_pattern_tdz(
  pattern : @ast.Pattern,
  env : Environment,
  kind : BindingKind,
) -> Unit raise Error {
  match pattern {
    IdentPat(name) =>
      if not(env.bindings.contains(name)) {
        env.def_tdz(name, kind)
      }
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => hoist_pattern_tdz(p, env, kind)
          None => ()
        }
      }
      match rest {
        Some(p) => hoist_pattern_tdz(p, env, kind)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        hoist_pattern_tdz(prop.value, env, kind)
      }
      match rest {
        Some(p) => hoist_pattern_tdz(p, env, kind)
        None => ()
      }
    }
  }
}

///|
fn Interpreter::bind_pattern(
  self : Interpreter,
  pattern : @ast.Pattern,
  value : Value,
  env : Environment,
  bk : BindingKind,
) -> Unit raise Error {
  match pattern {
    IdentPat(name) =>
      if bk == VarBinding && env.bindings.contains(name) {
        env.assign(name, value)
      } else if (bk == LetBinding || bk == ConstBinding) &&
        env.bindings.contains(name) {
        // let/const hoisted with TDZ - initialize it
        env.initialize(name, value)
      } else {
        env.def(name, value, bk)
      }
    ArrayPat(elements, rest) => {
      let arr_elements : Array[Value] = match value {
        Array(data) => data.elements
        _ => []
      }
      for i = 0; i < elements.length(); i = i + 1 {
        match elements[i] {
          Some(pat) => {
            let val : Value = if i < arr_elements.length() {
              arr_elements[i]
            } else {
              Undefined
            }
            self.bind_pattern(pat, val, env, bk)
          }
          None => () // hole — skip
        }
      }
      match rest {
        Some(rest_pat) => {
          let rest_elements : Array[Value] = []
          for i = elements.length(); i < arr_elements.length(); i = i + 1 {
            rest_elements.push(arr_elements[i])
          }
          self.bind_pattern(
            rest_pat,
            Array({ elements: rest_elements }),
            env,
            bk,
          )
        }
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      let used_keys : Map[String, Bool] = {}
      for prop in props {
        used_keys[prop.key] = true
        let val : Value = match value {
          Object(data) =>
            match data.properties.get(prop.key) {
              Some(v) => v
              None => Undefined
            }
          _ => Undefined
        }
        let final_val : Value = if val is Undefined {
          match prop.default_val {
            Some(default_expr) => self.eval_expr(default_expr, env)
            None => Undefined
          }
        } else {
          val
        }
        self.bind_pattern(prop.value, final_val, env, bk)
      }
      match rest {
        Some(rest_pat) => {
          let rest_props : Map[String, Value] = {}
          match value {
            Object(data) =>
              data.properties.each(fn(k, v) {
                if not(used_keys.contains(k)) {
                  rest_props[k] = v
                }
              })
            _ => ()
          }
          self.bind_pattern(
            rest_pat,
            Object({
              properties: rest_props,
              prototype: Null,
              callable: None,
              class_name: "Object",
              descriptors: {},
              extensible: true,
            }),
            env,
            bk,
          )
        }
        None => ()
      }
    }
  }
}

///|
fn Interpreter::assign_pattern(
  self : Interpreter,
  pattern : @ast.Pattern,
  value : Value,
  env : Environment,
) -> Unit raise Error {
  match pattern {
    IdentPat(name) => env.assign(name, value)
    ArrayPat(elements, rest) => {
      let arr_elements : Array[Value] = match value {
        Array(data) => data.elements
        _ => []
      }
      for i = 0; i < elements.length(); i = i + 1 {
        match elements[i] {
          Some(pat) => {
            let val : Value = if i < arr_elements.length() {
              arr_elements[i]
            } else {
              Undefined
            }
            self.assign_pattern(pat, val, env)
          }
          None => ()
        }
      }
      match rest {
        Some(rest_pat) => {
          let rest_elements : Array[Value] = []
          for i = elements.length(); i < arr_elements.length(); i = i + 1 {
            rest_elements.push(arr_elements[i])
          }
          self.assign_pattern(rest_pat, Array({ elements: rest_elements }), env)
        }
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      let used_keys : Map[String, Bool] = {}
      for prop in props {
        used_keys[prop.key] = true
        let val : Value = match value {
          Object(data) =>
            match data.properties.get(prop.key) {
              Some(v) => v
              None => Undefined
            }
          _ => Undefined
        }
        let final_val : Value = if val is Undefined {
          match prop.default_val {
            Some(default_expr) => self.eval_expr(default_expr, env)
            None => Undefined
          }
        } else {
          val
        }
        self.assign_pattern(prop.value, final_val, env)
      }
      match rest {
        Some(rest_pat) => {
          let rest_props : Map[String, Value] = {}
          match value {
            Object(data) =>
              data.properties.each(fn(k, v) {
                if not(used_keys.contains(k)) {
                  rest_props[k] = v
                }
              })
            _ => ()
          }
          self.assign_pattern(
            rest_pat,
            Object({
              properties: rest_props,
              prototype: Null,
              callable: None,
              class_name: "Object",
              descriptors: {},
              extensible: true,
            }),
            env,
          )
        }
        None => ()
      }
    }
  }
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
      let descriptors : Map[String, PropDescriptor] = {}
      for prop in props {
        // Get the key string - either from static StringLit or by evaluating computed key
        let key_str : String = if prop.computed {
          // Evaluate the computed key and convert to string
          let key_val = self.eval_expr(prop.key, env)
          match key_val {
            String_(s) => s
            Number(n) => {
              let i = n.to_int()
              if i.to_double() == n { i.to_string() } else { n.to_string() }
            }
            Bool(b) => b.to_string()
            Null => "null"
            Undefined => "undefined"
            _ => key_val.to_string()
          }
        } else {
          // Static key - extract from StringLit
          match prop.key {
            StringLit(s, _) => s
            _ => prop.key.to_string() // fallback
          }
        }
        match prop.kind {
          Init => properties[key_str] = self.eval_expr(prop.value, env)
          Get => {
            // Getter: store the function as __get__<key> for now
            // Real implementation would use accessor descriptors
            let getter = self.eval_expr(prop.value, env)
            properties["__get__" + key_str] = getter
          }
          Set => {
            // Setter: store the function as __set__<key> for now
            let setter = self.eval_expr(prop.value, env)
            properties["__set__" + key_str] = setter
          }
        }
      }
      Object({
        properties,
        prototype: Null,
        callable: None,
        class_name: "Object",
        descriptors,
        extensible: true,
      })
    }
    ArrayLit(elements, _) => {
      let vals : Array[Value] = []
      for e in elements {
        match e {
          SpreadExpr(inner, _) => {
            let val = self.eval_expr(inner, env)
            match val {
              Array(data) =>
                for el in data.elements {
                  vals.push(el)
                }
              String_(s) => {
                let chars = s.to_array()
                for c in chars {
                  let buf = StringBuilder::new()
                  buf.write_char(c)
                  vals.push(String_(buf.to_string()))
                }
              }
              _ => vals.push(val)
            }
          }
          _ => vals.push(self.eval_expr(e, env))
        }
      }
      Array({ elements: vals })
    }
    ComputedMember(obj_expr, key_expr, loc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      self.get_computed_property(obj, key, loc)
    }
    MemberAssign(obj_expr, prop, value_expr, _loc) => {
      let obj = self.eval_expr(obj_expr, env)
      let value = self.eval_expr(value_expr, env)
      match obj {
        Object(data) => {
          // Check writable descriptor
          match data.descriptors.get(prop) {
            Some(desc) =>
              if not(desc.writable) {
                if self.strict {
                  raise JsException(
                    String_(
                      "TypeError: Cannot assign to read only property '\{prop}'",
                    ),
                  )
                }
                return value
              }
            None => ()
          }
          // Check extensible for new properties
          if not(data.properties.contains(prop)) && not(data.extensible) {
            if self.strict {
              raise JsException(
                String_(
                  "TypeError: Cannot add property \{prop}, object is not extensible",
                ),
              )
            }
            return value
          }
          data.properties[prop] = value
          value
        }
        _ =>
          raise JsException(
            String_("TypeError: Cannot set property '\{prop}' of \{type_of(obj)}"),
          )
      }
    }
    ComputedAssign(obj_expr, key_expr, value_expr, _loc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let value = self.eval_expr(value_expr, env)
      match obj {
        Object(data) => {
          let prop = key.to_string()
          match data.descriptors.get(prop) {
            Some(desc) =>
              if not(desc.writable) {
                if self.strict {
                  raise JsException(
                    String_(
                      "TypeError: Cannot assign to read only property '\{prop}'",
                    ),
                  )
                }
                return value
              }
            None => ()
          }
          if not(data.properties.contains(prop)) && not(data.extensible) {
            if self.strict {
              raise JsException(
                String_(
                  "TypeError: Cannot add property \{prop}, object is not extensible",
                ),
              )
            }
            return value
          }
          data.properties[prop] = value
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
          raise JsException(
            String_("TypeError: Cannot set property of \{type_of(obj)}"),
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
    TemplateLit(strings, exprs, _) => {
      let buf = StringBuilder::new()
      for i = 0; i < strings.length(); i = i + 1 {
        buf.write_string(strings[i])
        if i < exprs.length() {
          let val = self.eval_expr(exprs[i], env)
          buf.write_string(val.to_string())
        }
      }
      String_(buf.to_string())
    }
    ArrowFunc(params, body, _) => {
      let func_data : FuncData = { name: None, params, body, closure: env }
      Object({
        properties: {},
        prototype: Null,
        callable: Some(ArrowFunc(func_data)),
        class_name: "Function",
        descriptors: {},
        extensible: true,
      })
    }
    ArrowFuncExt(params, rest_param, body, _) => {
      let func_data : FuncDataExt = {
        name: None,
        params,
        rest_param,
        body,
        closure: env,
      }
      Object({
        properties: {},
        prototype: Null,
        callable: Some(ArrowFuncExt(func_data)),
        class_name: "Function",
        descriptors: {},
        extensible: true,
      })
    }
    FuncExprExt(name, params, rest_param, body, _) => {
      let func_data : FuncDataExt = {
        name,
        params,
        rest_param,
        body,
        closure: env,
      }
      make_func_ext(func_data)
    }
    RegexLit(pattern, flags, _) => make_regexp_object(pattern, flags)
    SpreadExpr(_, _) =>
      raise Failure::Failure(
        "Spread expression used outside of call or array literal",
      )
    DestructureAssign(pattern, value_expr, _) => {
      let value = self.eval_expr(value_expr, env)
      self.assign_pattern(pattern, value, env)
      value
    }
    OptionalMember(obj_expr, prop, loc) => {
      // obj?.prop - return undefined if obj is null/undefined
      let obj = self.eval_expr(obj_expr, env)
      match obj {
        Null | Undefined => Undefined
        _ => self.get_property(obj, prop, loc)
      }
    }
    OptionalComputedMember(obj_expr, key_expr, loc) => {
      // obj?.[key] - return undefined if obj is null/undefined
      let obj = self.eval_expr(obj_expr, env)
      match obj {
        Null | Undefined => Undefined
        _ => {
          let key = self.eval_expr(key_expr, env)
          self.get_computed_property(obj, key, loc)
        }
      }
    }
    OptionalCall(callee_expr, arg_exprs, loc) => {
      // func?.(args) - return undefined if func is null/undefined
      // Per ES spec, arguments are NOT evaluated if function is nullish
      // Need to preserve receiver for method calls
      match callee_expr {
        OptionalMember(obj_expr, prop, mloc) => {
          let obj = self.eval_expr(obj_expr, env)
          match obj {
            Null | Undefined => Undefined
            _ => {
              let func_val = self.get_property(obj, prop, mloc)
              match func_val {
                Null | Undefined => Undefined
                _ => {
                  let args = self.eval_args_with_spread(arg_exprs, env)
                  self.call_value(func_val, obj, args, loc)
                }
              }
            }
          }
        }
        OptionalComputedMember(obj_expr, key_expr, mloc) => {
          let obj = self.eval_expr(obj_expr, env)
          match obj {
            Null | Undefined => Undefined
            _ => {
              let key = self.eval_expr(key_expr, env)
              let func_val = self.get_computed_property(obj, key, mloc)
              match func_val {
                Null | Undefined => Undefined
                _ => {
                  let args = self.eval_args_with_spread(arg_exprs, env)
                  self.call_value(func_val, obj, args, loc)
                }
              }
            }
          }
        }
        Member(obj_expr, prop, mloc) => {
          let obj = self.eval_expr(obj_expr, env)
          let func_val = self.get_property(obj, prop, mloc)
          match func_val {
            Null | Undefined => Undefined
            _ => {
              let args = self.eval_args_with_spread(arg_exprs, env)
              self.call_value(func_val, obj, args, loc)
            }
          }
        }
        ComputedMember(obj_expr, key_expr, mloc) => {
          let obj = self.eval_expr(obj_expr, env)
          let key = self.eval_expr(key_expr, env)
          let func_val = self.get_computed_property(obj, key, mloc)
          match func_val {
            Null | Undefined => Undefined
            _ => {
              let args = self.eval_args_with_spread(arg_exprs, env)
              self.call_value(func_val, obj, args, loc)
            }
          }
        }
        _ => {
          let callee = self.eval_expr(callee_expr, env)
          match callee {
            Null | Undefined => Undefined
            _ => {
              let args = self.eval_args_with_spread(arg_exprs, env)
              self.call_value(callee, Undefined, args, loc)
            }
          }
        }
      }
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
  // Short-circuit for &&, ||, and ??
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
    NullishCoalesce => {
      // ?? returns left if it's not null/undefined, otherwise right
      let left = self.eval_expr(left_expr, env)
      match left {
        Null | Undefined => self.eval_expr(right_expr, env)
        _ => left
      }
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
  _loc : @token.Loc,
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
    // Exponentiation
    (Exp, Number(a), Number(b)) => Number(@math.pow(a, b))
    (Exp, l, r) => Number(@math.pow(to_number(l), to_number(r)))
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
    // in operator - walks prototype chain
    (In, l, r) =>
      match r {
        Object(data) => {
          let key = l.to_string()
          // Check own property first
          if data.properties.contains(key) {
            return Bool(true)
          }
          // Walk prototype chain
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) =>
                if proto_data.properties.contains(key) {
                  return Bool(true)
                } else {
                  current = proto_data.prototype
                }
              _ => break
            }
          }
          Bool(false)
        }
        Array(data) => {
          let idx = to_number(l).to_int()
          Bool(idx >= 0 && idx < data.elements.length())
        }
        _ =>
          raise JsException(
            String_(
              "TypeError: Cannot use 'in' operator to search for '\{l.to_string()}' in \{type_of(r)}",
            ),
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
          raise JsException(
            String_(
              "TypeError: Right-hand side of 'instanceof' is not an object",
            ),
          )
      }
    // And/Or/?? already handled by short-circuit
    (And, _, _) | (Or, _, _) | (NullishCoalesce, _, _) =>
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
    (Object(a), Object(b)) => physical_equal(a, b)
    (Array(a), Array(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
fn loose_equal(a : Value, b : Value) -> Bool {
  // Abstract Equality Comparison Algorithm (ES spec 7.2.14)
  match (a, b) {
    // Same type: use strict equality
    (Number(x), Number(y)) => x == y
    (String_(x), String_(y)) => x == y
    (Bool(x), Bool(y)) => x == y
    (Null, Null) => true
    (Undefined, Undefined) => true
    (Object(x), Object(y)) => physical_equal(x, y)
    (Array(x), Array(y)) => physical_equal(x, y)
    // null == undefined
    (Null, Undefined) | (Undefined, Null) => true
    // Number == String: convert string to number
    (Number(n), String_(s)) => n == to_number(String_(s))
    (String_(s), Number(n)) => to_number(String_(s)) == n
    // Boolean == anything: convert boolean to number first
    (Bool(bval), _) => loose_equal(Number(if bval { 1.0 } else { 0.0 }), b)
    (_, Bool(bval)) => loose_equal(a, Number(if bval { 1.0 } else { 0.0 }))
    // Object/Array == Number/String: try ToPrimitive (simplified: use to_string)
    (Object(_), Number(_)) | (Object(_), String_(_)) => {
      let prim = String_(a.to_string())
      loose_equal(prim, b)
    }
    (Number(_), Object(_)) | (String_(_), Object(_)) => {
      let prim = String_(b.to_string())
      loose_equal(a, prim)
    }
    (Array(_), Number(_)) | (Array(_), String_(_)) => {
      let prim = String_(a.to_string())
      loose_equal(prim, b)
    }
    (Number(_), Array(_)) | (String_(_), Array(_)) => {
      let prim = String_(b.to_string())
      loose_equal(a, prim)
    }
    // Everything else is false
    _ => false
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
              match data.descriptors.get(prop) {
                Some(desc) =>
                  if not(desc.configurable) {
                    if self.strict {
                      raise JsException(
                        String_("TypeError: Cannot delete property '\{prop}'"),
                      )
                    }
                    return Bool(false)
                  }
                None => ()
              }
              let _ = data.properties.remove(prop)
              let _ = data.descriptors.remove(prop)
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
              let k = key.to_string()
              match data.descriptors.get(k) {
                Some(desc) =>
                  if not(desc.configurable) {
                    if self.strict {
                      raise JsException(
                        String_("TypeError: Cannot delete property '\{k}'"),
                      )
                    }
                    return Bool(false)
                  }
                None => ()
              }
              let _ = data.properties.remove(k)
              let _ = data.descriptors.remove(k)
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

///|
fn Interpreter::eval_args_with_spread(
  self : Interpreter,
  arg_exprs : Array[@ast.Expr],
  env : Environment,
) -> Array[Value] raise Error {
  let args : Array[Value] = []
  for a in arg_exprs {
    match a {
      SpreadExpr(inner, _) => {
        let val = self.eval_expr(inner, env)
        match val {
          Array(data) =>
            for el in data.elements {
              args.push(el)
            }
          String_(s) => {
            let chars = s.to_array()
            for c in chars {
              let buf = StringBuilder::new()
              buf.write_char(c)
              args.push(String_(buf.to_string()))
            }
          }
          _ => args.push(val)
        }
      }
      _ => args.push(self.eval_expr(a, env))
    }
  }
  args
}

///|
fn Interpreter::eval_call(
  self : Interpreter,
  callee_expr : @ast.Expr,
  arg_exprs : Array[@ast.Expr],
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  let args : Array[Value] = self.eval_args_with_spread(arg_exprs, env)
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
          let saved_strict = self.strict
          let result = try {
            let func_env = Environment::new(parent=Some(data.closure))
            let func_strict = self.strict || has_use_strict(data.body)
            if func_strict {
              self.strict = true
            }
            func_env.def("this", this_val, LetBinding)
            for i = 0; i < data.params.length(); i = i + 1 {
              let val : Value = if i < args.length() {
                args[i]
              } else {
                Undefined
              }
              func_env.def(data.params[i], val, LetBinding)
            }
            // Create arguments object
            let args_props : Map[String, Value] = {}
            for i = 0; i < args.length(); i = i + 1 {
              args_props[i.to_string()] = args[i]
            }
            args_props["length"] = Number(args.length().to_double())
            if not(func_strict) {
              args_props["callee"] = callee
            }
            func_env.def(
              "arguments",
              Object({
                properties: args_props,
                prototype: Null,
                callable: None,
                class_name: "Arguments",
                descriptors: {},
                extensible: true,
              }),
              VarBinding,
            )
            // Hoist var declarations and function declarations within function body
            self.hoist_declarations(data.body, func_env)
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
              BreakSignal(_) =>
                raise Failure::Failure("break statement outside of loop")
              ContinueSignal(_) =>
                raise Failure::Failure("continue statement outside of loop")
            }
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
          result
        }
        Some(ArrowFunc(data)) => {
          let func_env = Environment::new(parent=Some(data.closure))
          // Arrow functions do NOT rebind this — use closure's this
          for i = 0; i < data.params.length(); i = i + 1 {
            let val : Value = if i < args.length() {
              args[i]
            } else {
              Undefined
            }
            func_env.def(data.params[i], val, LetBinding)
          }
          self.hoist_declarations(data.body, func_env)
          match self.exec_stmts(data.body, func_env) {
            Normal(v) => v
            ReturnSignal(v) => v
            BreakSignal(_) =>
              raise Failure::Failure("break statement outside of loop")
            ContinueSignal(_) =>
              raise Failure::Failure("continue statement outside of loop")
          }
        }
        Some(UserFuncExt(data)) => {
          let saved_strict = self.strict
          let result = try {
            let func_env = Environment::new(parent=Some(data.closure))
            let func_strict = self.strict || has_use_strict(data.body)
            if func_strict {
              self.strict = true
            }
            func_env.def("this", this_val, LetBinding)
            // Bind params with defaults
            for i = 0; i < data.params.length(); i = i + 1 {
              let param = data.params[i]
              let val : Value = if i < args.length() &&
                not(args[i] is Undefined) {
                args[i]
              } else {
                match param.default_val {
                  Some(default_expr) => self.eval_expr(default_expr, func_env)
                  None => if i < args.length() { args[i] } else { Undefined }
                }
              }
              func_env.def(param.name, val, LetBinding)
            }
            // Rest param
            match data.rest_param {
              Some(rest_name) => {
                let rest_elements : Array[Value] = []
                for i = data.params.length(); i < args.length(); i = i + 1 {
                  rest_elements.push(args[i])
                }
                func_env.def(
                  rest_name,
                  Array({ elements: rest_elements }),
                  LetBinding,
                )
              }
              None => ()
            }
            // Create arguments object
            let args_props : Map[String, Value] = {}
            for i = 0; i < args.length(); i = i + 1 {
              args_props[i.to_string()] = args[i]
            }
            args_props["length"] = Number(args.length().to_double())
            if not(func_strict) {
              args_props["callee"] = callee
            }
            func_env.def(
              "arguments",
              Object({
                properties: args_props,
                prototype: Null,
                callable: None,
                class_name: "Arguments",
                descriptors: {},
                extensible: true,
              }),
              VarBinding,
            )
            self.hoist_declarations(data.body, func_env)
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
              BreakSignal(_) =>
                raise Failure::Failure("break statement outside of loop")
              ContinueSignal(_) =>
                raise Failure::Failure("continue statement outside of loop")
            }
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
          result
        }
        Some(ArrowFuncExt(data)) => {
          let func_env = Environment::new(parent=Some(data.closure))
          // Arrow functions do NOT rebind this
          for i = 0; i < data.params.length(); i = i + 1 {
            let param = data.params[i]
            let val : Value = if i < args.length() && not(args[i] is Undefined) {
              args[i]
            } else {
              match param.default_val {
                Some(default_expr) => self.eval_expr(default_expr, func_env)
                None => if i < args.length() { args[i] } else { Undefined }
              }
            }
            func_env.def(param.name, val, LetBinding)
          }
          // Rest param
          match data.rest_param {
            Some(rest_name) => {
              let rest_elements : Array[Value] = []
              for i = data.params.length(); i < args.length(); i = i + 1 {
                rest_elements.push(args[i])
              }
              func_env.def(
                rest_name,
                Array({ elements: rest_elements }),
                LetBinding,
              )
            }
            None => ()
          }
          self.hoist_declarations(data.body, func_env)
          match self.exec_stmts(data.body, func_env) {
            Normal(v) => v
            ReturnSignal(v) => v
            BreakSignal(_) =>
              raise Failure::Failure("break statement outside of loop")
            ContinueSignal(_) =>
              raise Failure::Failure("continue statement outside of loop")
          }
        }
        Some(BoundFunc(target, bound_this, bound_args)) => {
          let all_args : Array[Value] = []
          for a in bound_args {
            all_args.push(a)
          }
          for a in args {
            all_args.push(a)
          }
          self.call_value(target, bound_this, all_args, loc)
        }
        Some(FuncCallMethod(target)) => {
          let call_this = if args.length() > 0 { args[0] } else { Undefined }
          let call_args : Array[Value] = []
          for i = 1; i < args.length(); i = i + 1 {
            call_args.push(args[i])
          }
          self.call_value(target, call_this, call_args, loc)
        }
        Some(FuncApplyMethod(target)) => {
          let call_this = if args.length() > 0 { args[0] } else { Undefined }
          let call_args : Array[Value] = if args.length() > 1 {
            match args[1] {
              Array(data) => {
                let a : Array[Value] = []
                for el in data.elements {
                  a.push(el)
                }
                a
              }
              _ => []
            }
          } else {
            []
          }
          self.call_value(target, call_this, call_args, loc)
        }
        Some(MethodCallable(_, func)) => func(this_val, args)
        Some(NativeCallable(_, func)) => func(args)
        Some(InterpreterCallable(_, func)) => func(self, this_val, args)
        None =>
          raise JsException(String_("TypeError: is not a function"))
      }
    _ => raise JsException(String_("TypeError: is not a function"))
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
  _loc : @token.Loc,
) -> Value raise Error {
  match obj {
    Object(data) =>
      match data.properties.get(prop) {
        Some(v) => v
        None => {
          // Walk prototype chain
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) =>
                match proto_data.properties.get(prop) {
                  Some(v) => return v
                  None => current = proto_data.prototype
                }
              _ => break
            }
          }
          // Built-in Function methods (for callable objects)
          match data.callable {
            Some(callable) =>
              if prop == "call" {
                return Object({
                  properties: {},
                  prototype: Null,
                  callable: Some(FuncCallMethod(obj)),
                  class_name: "Function",
                  descriptors: {},
                  extensible: true,
                })
              } else if prop == "apply" {
                return Object({
                  properties: {},
                  prototype: Null,
                  callable: Some(FuncApplyMethod(obj)),
                  class_name: "Function",
                  descriptors: {},
                  extensible: true,
                })
              } else if prop == "bind" {
                let target = obj
                return make_native_func("bind", fn(args) {
                  let bind_this = if args.length() > 0 {
                    args[0]
                  } else {
                    Undefined
                  }
                  let bound_args : Array[Value] = []
                  for i = 1; i < args.length(); i = i + 1 {
                    bound_args.push(args[i])
                  }
                  Object({
                    properties: {},
                    prototype: Null,
                    callable: Some(BoundFunc(target, bind_this, bound_args)),
                    class_name: "Function",
                    descriptors: {},
                    extensible: true,
                  })
                })
              } else if prop == "length" {
                // Return the number of formal parameters
                let param_count = match callable {
                  UserFunc(func_data) => func_data.params.length()
                  UserFuncExt(func_data) => func_data.params.length()
                  ArrowFunc(func_data) => func_data.params.length()
                  ArrowFuncExt(func_data) => func_data.params.length()
                  BoundFunc(target, _, bound_args) =>
                    match target {
                      Object(td) =>
                        match td.callable {
                          Some(UserFunc(fd)) => {
                            let diff = fd.params.length() - bound_args.length()
                            if diff < 0 { 0 } else { diff }
                          }
                          Some(UserFuncExt(fd)) => {
                            let diff = fd.params.length() - bound_args.length()
                            if diff < 0 { 0 } else { diff }
                          }
                          Some(ArrowFunc(fd)) => {
                            let diff = fd.params.length() - bound_args.length()
                            if diff < 0 { 0 } else { diff }
                          }
                          Some(ArrowFuncExt(fd)) => {
                            let diff = fd.params.length() - bound_args.length()
                            if diff < 0 { 0 } else { diff }
                          }
                          _ => 0
                        }
                      _ => 0
                    }
                  NativeCallable(_, _) => 0
                  FuncCallMethod(_) => 1
                  FuncApplyMethod(_) => 2
                  MethodCallable(_, _) => 0
                  InterpreterCallable(_, _) => 0
                }
                return Number(param_count.to_double())
              } else if prop == "name" {
                // Return the function name
                let func_name = match callable {
                  UserFunc(func_data) =>
                    match func_data.name {
                      Some(n) => n
                      None => ""
                    }
                  UserFuncExt(func_data) =>
                    match func_data.name {
                      Some(n) => n
                      None => ""
                    }
                  ArrowFunc(_) | ArrowFuncExt(_) => ""
                  BoundFunc(target, _, _) =>
                    match target {
                      Object(td) =>
                        match td.callable {
                          Some(UserFunc(fd)) =>
                            "bound " +
                            match fd.name {
                              Some(n) => n
                              None => ""
                            }
                          Some(UserFuncExt(fd)) =>
                            "bound " +
                            match fd.name {
                              Some(n) => n
                              None => ""
                            }
                          Some(NativeCallable(n, _)) => "bound " + n
                          _ => "bound "
                        }
                      _ => "bound "
                    }
                  NativeCallable(n, _) => n
                  FuncCallMethod(_) => "call"
                  FuncApplyMethod(_) => "apply"
                  MethodCallable(n, _) => n
                  InterpreterCallable(n, _) => n
                }
                return String_(func_name)
              }
            None => ()
          }
          // Built-in Object methods
          if prop == "hasOwnProperty" {
            return Object({
              properties: {},
              prototype: Null,
              callable: Some(
                MethodCallable("hasOwnProperty", fn(this_val, args) {
                  let key = if args.length() > 0 {
                    args[0].to_string()
                  } else {
                    "undefined"
                  }
                  match this_val {
                    Object(d) => Bool(d.properties.contains(key))
                    _ => Bool(false)
                  }
                }),
              ),
              class_name: "Function",
              descriptors: {},
              extensible: true,
            })
          }
          if prop == "toString" {
            return make_native_func("toString", fn(_args) {
              String_("[object Object]")
            })
          }
          Undefined
        }
      }
    Array(data) =>
      if prop == "length" {
        Number(data.elements.length().to_double())
      } else {
        get_array_method_with_interp(data, prop)
      }
    String_(s) =>
      if prop == "length" {
        Number(s.length().to_double())
      } else {
        get_string_method(s, prop)
      }
    Number(_) => get_number_method(obj, prop)
    Null | Undefined =>
      raise JsException(
        String_("TypeError: Cannot read property '\{prop}' of \{type_of(obj)}"),
      )
    _ => Undefined
  }
}

///|
fn Interpreter::get_computed_property(
  _self : Interpreter,
  obj : Value,
  key : Value,
  _loc : @token.Loc,
) -> Value raise Error {
  match obj {
    Object(data) => {
      let prop = key.to_string()
      match data.properties.get(prop) {
        Some(v) => v
        None => {
          // Walk prototype chain
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) =>
                match proto_data.properties.get(prop) {
                  Some(v) => return v
                  None => current = proto_data.prototype
                }
              _ => break
            }
          }
          // Built-in Function methods (for callable objects)
          match data.callable {
            Some(callable) =>
              if prop == "call" {
                return Object({
                  properties: {},
                  prototype: Null,
                  callable: Some(FuncCallMethod(obj)),
                  class_name: "Function",
                  descriptors: {},
                  extensible: true,
                })
              } else if prop == "apply" {
                return Object({
                  properties: {},
                  prototype: Null,
                  callable: Some(FuncApplyMethod(obj)),
                  class_name: "Function",
                  descriptors: {},
                  extensible: true,
                })
              } else if prop == "bind" {
                let target = obj
                return make_native_func("bind", fn(args) {
                  let bind_this = if args.length() > 0 {
                    args[0]
                  } else {
                    Undefined
                  }
                  let bound_args : Array[Value] = []
                  for i = 1; i < args.length(); i = i + 1 {
                    bound_args.push(args[i])
                  }
                  Object({
                    properties: {},
                    prototype: Null,
                    callable: Some(BoundFunc(target, bind_this, bound_args)),
                    class_name: "Function",
                    descriptors: {},
                    extensible: true,
                  })
                })
              } else if prop == "length" {
                // Return the number of formal parameters
                let param_count = match callable {
                  UserFunc(func_data) => func_data.params.length()
                  UserFuncExt(func_data) => func_data.params.length()
                  ArrowFunc(func_data) => func_data.params.length()
                  ArrowFuncExt(func_data) => func_data.params.length()
                  BoundFunc(target, _, bound_args) =>
                    match target {
                      Object(td) =>
                        match td.callable {
                          Some(UserFunc(fd)) => {
                            let diff = fd.params.length() - bound_args.length()
                            if diff < 0 { 0 } else { diff }
                          }
                          Some(UserFuncExt(fd)) => {
                            let diff = fd.params.length() - bound_args.length()
                            if diff < 0 { 0 } else { diff }
                          }
                          Some(ArrowFunc(fd)) => {
                            let diff = fd.params.length() - bound_args.length()
                            if diff < 0 { 0 } else { diff }
                          }
                          Some(ArrowFuncExt(fd)) => {
                            let diff = fd.params.length() - bound_args.length()
                            if diff < 0 { 0 } else { diff }
                          }
                          _ => 0
                        }
                      _ => 0
                    }
                  NativeCallable(_, _) => 0
                  FuncCallMethod(_) => 1
                  FuncApplyMethod(_) => 2
                  MethodCallable(_, _) => 0
                  InterpreterCallable(_, _) => 0
                }
                return Number(param_count.to_double())
              } else if prop == "name" {
                // Return the function name
                let func_name = match callable {
                  UserFunc(func_data) =>
                    match func_data.name {
                      Some(n) => n
                      None => ""
                    }
                  UserFuncExt(func_data) =>
                    match func_data.name {
                      Some(n) => n
                      None => ""
                    }
                  ArrowFunc(_) | ArrowFuncExt(_) => ""
                  BoundFunc(target, _, _) =>
                    match target {
                      Object(td) =>
                        match td.callable {
                          Some(UserFunc(fd)) =>
                            "bound " +
                            match fd.name {
                              Some(n) => n
                              None => ""
                            }
                          Some(UserFuncExt(fd)) =>
                            "bound " +
                            match fd.name {
                              Some(n) => n
                              None => ""
                            }
                          Some(NativeCallable(n, _)) => "bound " + n
                          _ => "bound "
                        }
                      _ => "bound "
                    }
                  NativeCallable(n, _) => n
                  FuncCallMethod(_) => "call"
                  FuncApplyMethod(_) => "apply"
                  MethodCallable(n, _) => n
                  InterpreterCallable(n, _) => n
                }
                return String_(func_name)
              }
            None => ()
          }
          // Built-in Object methods
          if prop == "hasOwnProperty" {
            return Object({
              properties: {},
              prototype: Null,
              callable: Some(
                MethodCallable("hasOwnProperty", fn(this_val, args) {
                  let k = if args.length() > 0 {
                    args[0].to_string()
                  } else {
                    "undefined"
                  }
                  match this_val {
                    Object(d) => Bool(d.properties.contains(k))
                    _ => Bool(false)
                  }
                }),
              ),
              class_name: "Function",
              descriptors: {},
              extensible: true,
            })
          }
          if prop == "toString" {
            return make_native_func("toString", fn(_args) {
              String_("[object Object]")
            })
          }
          Undefined
        }
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
        String_(s) => get_array_method_with_interp(data, s)
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
        String_(method_name) => get_string_method(s, method_name)
        _ => Undefined
      }
    Number(_) =>
      match key {
        String_(method_name) => get_number_method(obj, method_name)
        _ => Undefined
      }
    Null | Undefined =>
      raise JsException(
        String_("TypeError: Cannot read property of \{type_of(obj)}"),
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
  _loc : @token.Loc,
) -> Value raise Error {
  let ctor = self.eval_expr(callee_expr, env)
  let args : Array[Value] = self.eval_args_with_spread(arg_exprs, env)
  match ctor {
    Object(obj_data) =>
      match obj_data.callable {
        Some(UserFunc(data)) => {
          let saved_strict = self.strict
          let result = try {
            let func_strict = self.strict || has_use_strict(data.body)
            if func_strict {
              self.strict = true
            }
            let proto = match obj_data.properties.get("prototype") {
              Some(v) => v
              None => Null
            }
            let new_obj = Object({
              properties: {},
              prototype: proto,
              callable: None,
              class_name: "Object",
              descriptors: {},
              extensible: true,
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
            // Create arguments object
            let new_args_props : Map[String, Value] = {}
            for i = 0; i < args.length(); i = i + 1 {
              new_args_props[i.to_string()] = args[i]
            }
            new_args_props["length"] = Number(args.length().to_double())
            if not(func_strict) {
              new_args_props["callee"] = ctor
            }
            func_env.def(
              "arguments",
              Object({
                properties: new_args_props,
                prototype: Null,
                callable: None,
                class_name: "Arguments",
                descriptors: {},
                extensible: true,
              }),
              VarBinding,
            )
            // Hoist var declarations and function declarations
            self.hoist_declarations(data.body, func_env)
            match data.name {
              Some(name) =>
                if not(func_env.bindings.contains(name)) {
                  func_env.def(name, ctor, LetBinding)
                }
              None => ()
            }
            let exec_result = self.exec_stmts(data.body, func_env)
            match exec_result {
              Normal(_) => new_obj
              ReturnSignal(v) =>
                match v {
                  Object(_) => v
                  _ => new_obj
                }
              BreakSignal(_) =>
                raise Failure::Failure("break statement outside of loop")
              ContinueSignal(_) =>
                raise Failure::Failure("continue statement outside of loop")
            }
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
          result
        }
        Some(UserFuncExt(data)) => {
          let saved_strict = self.strict
          let result = try {
            let func_strict = self.strict || has_use_strict(data.body)
            if func_strict {
              self.strict = true
            }
            let proto = match obj_data.properties.get("prototype") {
              Some(v) => v
              None => Null
            }
            let new_obj = Object({
              properties: {},
              prototype: proto,
              callable: None,
              class_name: "Object",
              descriptors: {},
              extensible: true,
            })
            let func_env = Environment::new(parent=Some(data.closure))
            func_env.def("this", new_obj, LetBinding)
            for i = 0; i < data.params.length(); i = i + 1 {
              let param = data.params[i]
              let val : Value = if i < args.length() &&
                not(args[i] is Undefined) {
                args[i]
              } else {
                match param.default_val {
                  Some(default_expr) => self.eval_expr(default_expr, func_env)
                  None => if i < args.length() { args[i] } else { Undefined }
                }
              }
              func_env.def(param.name, val, LetBinding)
            }
            match data.rest_param {
              Some(rest_name) => {
                let rest_elements : Array[Value] = []
                for i = data.params.length(); i < args.length(); i = i + 1 {
                  rest_elements.push(args[i])
                }
                func_env.def(
                  rest_name,
                  Array({ elements: rest_elements }),
                  LetBinding,
                )
              }
              None => ()
            }
            let new_args_props : Map[String, Value] = {}
            for i = 0; i < args.length(); i = i + 1 {
              new_args_props[i.to_string()] = args[i]
            }
            new_args_props["length"] = Number(args.length().to_double())
            if not(func_strict) {
              new_args_props["callee"] = ctor
            }
            func_env.def(
              "arguments",
              Object({
                properties: new_args_props,
                prototype: Null,
                callable: None,
                class_name: "Arguments",
                descriptors: {},
                extensible: true,
              }),
              VarBinding,
            )
            self.hoist_declarations(data.body, func_env)
            match data.name {
              Some(name) =>
                if not(func_env.bindings.contains(name)) {
                  func_env.def(name, ctor, LetBinding)
                }
              None => ()
            }
            let exec_result = self.exec_stmts(data.body, func_env)
            match exec_result {
              Normal(_) => new_obj
              ReturnSignal(v) =>
                match v {
                  Object(_) => v
                  _ => new_obj
                }
              BreakSignal(_) =>
                raise Failure::Failure("break statement outside of loop")
              ContinueSignal(_) =>
                raise Failure::Failure("continue statement outside of loop")
            }
          } catch {
            e => {
              self.strict = saved_strict
              raise e
            }
          }
          self.strict = saved_strict
          result
        }
        Some(NativeCallable(_, func)) => func(args)
        Some(InterpreterCallable(_, func)) => func(self, Undefined, args)
        Some(ArrowFunc(_)) | Some(ArrowFuncExt(_)) =>
          raise JsException(
            String_("TypeError: arrow functions cannot be used as constructors"),
          )
        _ => raise JsException(String_("TypeError: is not a constructor"))
      }
    _ => raise JsException(String_("TypeError: is not a constructor"))
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
  match operand {
    Ident(name, _) => {
      let current = env.get(name)
      let num = to_number(current)
      let new_val : Value = match op {
        Increment => Number(num + 1.0)
        Decrement => Number(num - 1.0)
      }
      env.assign(name, new_val)
      if prefix {
        new_val
      } else {
        Number(num)
      }
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      let num = to_number(current)
      let new_val : Value = match op {
        Increment => Number(num + 1.0)
        Decrement => Number(num - 1.0)
      }
      match obj {
        Object(data) => data.properties[prop] = new_val
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
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let current = self.get_computed_property(obj, key, mloc)
      let num = to_number(current)
      let new_val : Value = match op {
        Increment => Number(num + 1.0)
        Decrement => Number(num - 1.0)
      }
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
      if prefix {
        new_val
      } else {
        Number(num)
      }
    }
    _ =>
      raise Failure::Failure(
        "Invalid update target at line \{loc.line}, col \{loc.col}",
      )
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
  // Handle logical assignment operators with short-circuit semantics
  match op {
    LogicalAndAssign => return self.eval_logical_assign_and(target, value_expr, env, loc)
    LogicalOrAssign => return self.eval_logical_assign_or(target, value_expr, env, loc)
    NullishAssign => return self.eval_nullish_assign(target, value_expr, env, loc)
    _ => ()
  }
  let bin_op : @ast.BinOp = match op {
    AddAssign => Add
    SubAssign => Sub
    MulAssign => Mul
    ExpAssign => Exp
    DivAssign => Div
    ModAssign => Mod
    BitAndAssign => BitAnd
    BitOrAssign => BitOr
    BitXorAssign => BitXor
    LShiftAssign => LShift
    RShiftAssign => RShift
    URShiftAssign => URShift
    LogicalAndAssign | LogicalOrAssign | NullishAssign => Add // unreachable
  }
  match target {
    Ident(name, _) => {
      let current = env.get(name)
      let rhs = self.eval_expr(value_expr, env)
      let result = eval_binary_op(bin_op, current, rhs, loc)
      env.assign(name, result)
      result
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      let rhs = self.eval_expr(value_expr, env)
      let result = eval_binary_op(bin_op, current, rhs, loc)
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
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let current = self.get_computed_property(obj, key, mloc)
      let rhs = self.eval_expr(value_expr, env)
      let result = eval_binary_op(bin_op, current, rhs, loc)
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

///|
fn Interpreter::eval_logical_assign_and(
  self : Interpreter,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // x &&= y: if x is truthy, assign y to x; return final value
  match target {
    Ident(name, _) => {
      let current = env.get(name)
      if is_truthy(current) {
        let rhs = self.eval_expr(value_expr, env)
        env.assign(name, rhs)
        rhs
      } else {
        current
      }
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      if is_truthy(current) {
        let rhs = self.eval_expr(value_expr, env)
        match obj {
          Object(data) => {
            // Check writable descriptor
            match data.descriptors.get(prop) {
              Some(desc) =>
                if not(desc.writable) {
                  if self.strict {
                    raise JsException(
                      String_(
                        "TypeError: Cannot assign to read only property '\{prop}'",
                      ),
                    )
                  }
                  return rhs
                }
              None => ()
            }
            // Check extensible for new properties
            if not(data.properties.contains(prop)) && not(data.extensible) {
              if self.strict {
                raise JsException(
                  String_(
                    "TypeError: Cannot add property \{prop}, object is not extensible",
                  ),
                )
              }
              return rhs
            }
            data.properties[prop] = rhs
            rhs
          }
          _ =>
            raise JsException(
              String_("TypeError: Cannot set property '\{prop}' of \{type_of(obj)}"),
            )
        }
      } else {
        current
      }
    }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let current = self.get_computed_property(obj, key, mloc)
      if is_truthy(current) {
        let rhs = self.eval_expr(value_expr, env)
        match obj {
          Object(data) => {
            let prop = key.to_string()
            // Check writable descriptor
            match data.descriptors.get(prop) {
              Some(desc) =>
                if not(desc.writable) {
                  if self.strict {
                    raise JsException(
                      String_(
                        "TypeError: Cannot assign to read only property '\{prop}'",
                      ),
                    )
                  }
                  return rhs
                }
              None => ()
            }
            // Check extensible for new properties
            if not(data.properties.contains(prop)) && not(data.extensible) {
              if self.strict {
                raise JsException(
                  String_(
                    "TypeError: Cannot add property \{prop}, object is not extensible",
                  ),
                )
              }
              return rhs
            }
            data.properties[prop] = rhs
            rhs
          }
          Array(data) =>
            match key {
              Number(n) => {
                let i = n.to_int()
                if i >= 0 && i < data.elements.length() {
                  data.elements[i] = rhs
                }
                rhs
              }
              _ => rhs
            }
          _ =>
            raise JsException(
              String_("TypeError: Cannot set property of \{type_of(obj)}"),
            )
        }
      } else {
        current
      }
    }
    _ =>
      raise Failure::Failure(
        "Invalid assignment target at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
fn Interpreter::eval_logical_assign_or(
  self : Interpreter,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // x ||= y: if x is falsy, assign y to x; return final value
  match target {
    Ident(name, _) => {
      let current = env.get(name)
      if not(is_truthy(current)) {
        let rhs = self.eval_expr(value_expr, env)
        env.assign(name, rhs)
        rhs
      } else {
        current
      }
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      if not(is_truthy(current)) {
        let rhs = self.eval_expr(value_expr, env)
        match obj {
          Object(data) => {
            // Check writable descriptor
            match data.descriptors.get(prop) {
              Some(desc) =>
                if not(desc.writable) {
                  if self.strict {
                    raise JsException(
                      String_(
                        "TypeError: Cannot assign to read only property '\{prop}'",
                      ),
                    )
                  }
                  return rhs
                }
              None => ()
            }
            // Check extensible for new properties
            if not(data.properties.contains(prop)) && not(data.extensible) {
              if self.strict {
                raise JsException(
                  String_(
                    "TypeError: Cannot add property \{prop}, object is not extensible",
                  ),
                )
              }
              return rhs
            }
            data.properties[prop] = rhs
            rhs
          }
          _ =>
            raise JsException(
              String_("TypeError: Cannot set property '\{prop}' of \{type_of(obj)}"),
            )
        }
      } else {
        current
      }
    }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let current = self.get_computed_property(obj, key, mloc)
      if not(is_truthy(current)) {
        let rhs = self.eval_expr(value_expr, env)
        match obj {
          Object(data) => {
            let prop = key.to_string()
            // Check writable descriptor
            match data.descriptors.get(prop) {
              Some(desc) =>
                if not(desc.writable) {
                  if self.strict {
                    raise JsException(
                      String_(
                        "TypeError: Cannot assign to read only property '\{prop}'",
                      ),
                    )
                  }
                  return rhs
                }
              None => ()
            }
            // Check extensible for new properties
            if not(data.properties.contains(prop)) && not(data.extensible) {
              if self.strict {
                raise JsException(
                  String_(
                    "TypeError: Cannot add property \{prop}, object is not extensible",
                  ),
                )
              }
              return rhs
            }
            data.properties[prop] = rhs
            rhs
          }
          Array(data) =>
            match key {
              Number(n) => {
                let i = n.to_int()
                if i >= 0 && i < data.elements.length() {
                  data.elements[i] = rhs
                }
                rhs
              }
              _ => rhs
            }
          _ =>
            raise JsException(
              String_("TypeError: Cannot set property of \{type_of(obj)}"),
            )
        }
      } else {
        current
      }
    }
    _ =>
      raise Failure::Failure(
        "Invalid assignment target at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
fn Interpreter::eval_nullish_assign(
  self : Interpreter,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // x ??= y: if x is null or undefined, assign y to x; return final value
  match target {
    Ident(name, _) => {
      let current = env.get(name)
      match current {
        Null | Undefined => {
          let rhs = self.eval_expr(value_expr, env)
          env.assign(name, rhs)
          rhs
        }
        _ => current
      }
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      match current {
        Null | Undefined => {
          let rhs = self.eval_expr(value_expr, env)
          match obj {
            Object(data) => {
              // Check writable descriptor
              match data.descriptors.get(prop) {
                Some(desc) =>
                  if not(desc.writable) {
                    if self.strict {
                      raise JsException(
                        String_(
                          "TypeError: Cannot assign to read only property '\{prop}'",
                        ),
                      )
                    }
                    return rhs
                  }
                None => ()
              }
              // Check extensible for new properties
              if not(data.properties.contains(prop)) && not(data.extensible) {
                if self.strict {
                  raise JsException(
                    String_(
                      "TypeError: Cannot add property \{prop}, object is not extensible",
                    ),
                  )
                }
                return rhs
              }
              data.properties[prop] = rhs
              rhs
            }
            _ =>
              raise JsException(
                String_("TypeError: Cannot set property '\{prop}' of \{type_of(obj)}"),
              )
          }
        }
        _ => current
      }
    }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(obj_expr, env)
      let key = self.eval_expr(key_expr, env)
      let current = self.get_computed_property(obj, key, mloc)
      match current {
        Null | Undefined => {
          let rhs = self.eval_expr(value_expr, env)
          match obj {
            Object(data) => {
              let prop = key.to_string()
              // Check writable descriptor
              match data.descriptors.get(prop) {
                Some(desc) =>
                  if not(desc.writable) {
                    if self.strict {
                      raise JsException(
                        String_(
                          "TypeError: Cannot assign to read only property '\{prop}'",
                        ),
                      )
                    }
                    return rhs
                  }
                None => ()
              }
              // Check extensible for new properties
              if not(data.properties.contains(prop)) && not(data.extensible) {
                if self.strict {
                  raise JsException(
                    String_(
                      "TypeError: Cannot add property \{prop}, object is not extensible",
                    ),
                  )
                }
                return rhs
              }
              data.properties[prop] = rhs
              rhs
            }
            Array(data) =>
              match key {
                Number(n) => {
                  let i = n.to_int()
                  if i >= 0 && i < data.elements.length() {
                    data.elements[i] = rhs
                  }
                  rhs
                }
                _ => rhs
              }
            _ =>
              raise JsException(
                String_("TypeError: Cannot set property of \{type_of(obj)}"),
              )
          }
        }
        _ => current
      }
    }
    _ =>
      raise Failure::Failure(
        "Invalid assignment target at line \{loc.line}, col \{loc.col}",
      )
  }
}
