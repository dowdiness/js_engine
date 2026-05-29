///|
priv enum BytecodeInstr {
  LoadConst(Value)
  LoadUndefined
  LoadName(String)
  StoreName(String)
  LoadLocal(Int)
  StoreLocal(Int)
  DefineBinding(@ast.VarKind, String, Bool) // kind, name, initializer-present
  DefineLocal(Int, Bool) // slot, initializer-present
  SetCompletion
  Pop
  BinaryOp(@ast.BinOp, @token.Loc)
  SetFunctionName(String)
  UpdateName(String, @ast.UpdateOp, Bool, @token.Loc) // name, op, prefix, loc
  UpdateLocal(Int, @ast.UpdateOp, Bool) // slot, op, prefix
  Jump(Int)
  JumpIfFalse(Int)
  JumpIfFalseKeep(Int)
  JumpIfTrueKeep(Int)
  JumpIfNotNullishKeep(Int)
  MakeArray(Int)
  MakeFunction(Int)
  DeclareFunction(String, Int)
  GetProperty(String, @token.Loc)
  GetComputed(@token.Loc)
  PreparePropertyCall(String, @token.Loc)
  PrepareComputedCall(@token.Loc)
  Call(Int, @token.Loc)
  CallWithReceiver(Int, @token.Loc)
  Return
  Throw
}

///|
priv struct BytecodeFunction {
  name : String?
  params : Array[String]
  source_body : Array[@ast.Stmt]
  body_has_use_strict : Bool
  local_names : Array[String]
  code : Array[BytecodeInstr]
  children : Array[BytecodeFunction]
}

///|
priv struct BytecodeBuilder {
  code : Array[BytecodeInstr]
  children : Array[BytecodeFunction]
  local_names : Array[String]
  local_indices : Map[String, Int]
}

///|
priv struct BytecodeLocalPlan {
  names : Array[String]
  indices : Map[String, Int]
}

///|
pub struct BytecodeProgram {
  priv source_stmts : Array[@ast.Stmt]
  priv main : BytecodeFunction
}

///|
priv enum BytecodeRunResult {
  BytecodeNormal(Value)
  BytecodeReturn(Value)
}

///|
fn BytecodeBuilder::BytecodeBuilder(
  plan : BytecodeLocalPlan,
) -> BytecodeBuilder {
  {
    code: [],
    children: [],
    local_names: plan.names,
    local_indices: plan.indices,
  }
}

///|
fn BytecodeBuilder::emit(self : BytecodeBuilder, instr : BytecodeInstr) -> Int {
  let idx = self.code.length()
  self.code.push(instr)
  idx
}

///|
fn BytecodeBuilder::patch(
  self : BytecodeBuilder,
  idx : Int,
  instr : BytecodeInstr,
) -> Unit {
  self.code[idx] = instr
}

///|
fn BytecodeBuilder::local_slot(self : BytecodeBuilder, name : String) -> Int? {
  self.local_indices.get(name)
}

///|
fn BytecodeBuilder::emit_undefined_completion(self : BytecodeBuilder) -> Unit {
  let _ = self.emit(LoadUndefined)
  let _ = self.emit(SetCompletion)
}

///|
fn bytecode_unsupported(kind : String) -> Unit raise Error {
  raise @errors.InternalError(message="bytecode prototype unsupported: " + kind)
}

///|
fn stmt_has_lexical_decl(stmt : @ast.Stmt) -> Bool {
  match stmt {
    VarDecl(LetKind, _, _, _)
    | VarDecl(ConstKind, _, _, _)
    | DestructureDecl(LetKind, _, _, _)
    | DestructureDecl(ConstKind, _, _, _) => true
    StmtList(stmts, _) | Block(stmts, _) => stmts_have_lexical_decl(stmts)
    _ => false
  }
}

///|
fn stmts_have_lexical_decl(stmts : Array[@ast.Stmt]) -> Bool {
  for stmt in stmts {
    if stmt_has_lexical_decl(stmt) {
      return true
    }
  }
  false
}

///|
fn stmt_has_var_decl(stmt : @ast.Stmt) -> Bool {
  match stmt {
    VarDecl(VarKind, _, _, _) | DestructureDecl(VarKind, _, _, _) => true
    StmtList(stmts, _) | Block(stmts, _) => stmts_have_var_decl(stmts)
    IfStmt(_, then_branch, else_branch, _) => {
      let else_has = match else_branch {
        Some(stmt) => stmt_has_var_decl(stmt)
        None => false
      }
      stmt_has_var_decl(then_branch) || else_has
    }
    WhileStmt(_, body, _) => stmt_has_var_decl(body)
    ForStmt(init, _, _, body, _) => {
      let init_has = match init {
        Some(stmt) => stmt_has_var_decl(stmt)
        None => false
      }
      init_has || stmt_has_var_decl(body)
    }
    _ => false
  }
}

///|
fn stmts_have_var_decl(stmts : Array[@ast.Stmt]) -> Bool {
  for stmt in stmts {
    if stmt_has_var_decl(stmt) {
      return true
    }
  }
  false
}

///|
fn bytecode_is_direct_eval_callee(expr : @ast.Expr) -> Bool {
  match expr {
    Ident("eval", _) => true
    Grouping(inner, _) => bytecode_is_direct_eval_callee(inner)
    _ => false
  }
}

///|
fn bytecode_is_anonymous_function_definition(expr : @ast.Expr) -> Bool {
  match expr {
    FuncExpr(None, _, _, _) | FuncExprExt(None, _, _, _, _) => true
    Grouping(inner, _) => bytecode_is_anonymous_function_definition(inner)
    _ => false
  }
}

///|
fn stmt_has_function_decl(stmt : @ast.Stmt) -> Bool {
  match stmt {
    FuncDecl(_, _, _, _) | FuncDeclExt(_, _, _, _, _) => true
    StmtList(stmts, _) | Block(stmts, _) => stmts_have_function_decl(stmts)
    IfStmt(_, then_branch, else_branch, _) => {
      let else_has = match else_branch {
        Some(stmt) => stmt_has_function_decl(stmt)
        None => false
      }
      stmt_has_function_decl(then_branch) || else_has
    }
    WhileStmt(_, body, _) => stmt_has_function_decl(body)
    ForStmt(init, _, _, body, _) => {
      let init_has = match init {
        Some(stmt) => stmt_has_function_decl(stmt)
        None => false
      }
      init_has || stmt_has_function_decl(body)
    }
    _ => false
  }
}

///|
fn stmts_have_function_decl(stmts : Array[@ast.Stmt]) -> Bool {
  for stmt in stmts {
    if stmt_has_function_decl(stmt) {
      return true
    }
  }
  false
}

///|
fn add_local_candidate(
  names : Array[String],
  indices : Map[String, Int],
  captured : Map[String, Bool],
  name : String,
) -> Unit {
  if !captured.contains(name) && !indices.contains(name) {
    indices[name] = names.length()
    names.push(name)
  }
}

///|
fn collect_current_var_names_from_stmts(
  stmts : Array[@ast.Stmt],
  out : Array[String],
) -> Unit {
  for stmt in stmts {
    collect_current_var_names_from_stmt(stmt, out)
  }
}

///|
fn collect_current_var_names_from_stmt(
  stmt : @ast.Stmt,
  out : Array[String],
) -> Unit {
  match stmt {
    VarDecl(VarKind, name, _, _) | FuncDecl(name, _, _, _) => out.push(name)
    StmtList(stmts, _) | Block(stmts, _) =>
      collect_current_var_names_from_stmts(stmts, out)
    IfStmt(_, then_branch, else_branch, _) => {
      collect_current_var_names_from_stmt(then_branch, out)
      match else_branch {
        Some(stmt) => collect_current_var_names_from_stmt(stmt, out)
        None => ()
      }
    }
    WhileStmt(_, body, _) => collect_current_var_names_from_stmt(body, out)
    ForStmt(init, _, _, body, _) => {
      match init {
        Some(stmt) => collect_current_var_names_from_stmt(stmt, out)
        None => ()
      }
      collect_current_var_names_from_stmt(body, out)
    }
    _ => ()
  }
}

///|
fn collect_nested_function_refs_from_stmts(
  stmts : Array[@ast.Stmt],
  refs : Map[String, Bool],
) -> Unit {
  for stmt in stmts {
    collect_nested_function_refs_from_stmt(stmt, refs)
  }
}

///|
fn collect_nested_function_refs_from_stmt(
  stmt : @ast.Stmt,
  refs : Map[String, Bool],
) -> Unit {
  match stmt {
    FuncDecl(_, _, body, _) => collect_name_refs_from_stmts(body, refs)
    VarDecl(_, _, Some(expr), _)
    | ExprStmt(expr, _)
    | ReturnStmt(Some(expr), _)
    | ThrowStmt(expr, _) => collect_nested_function_refs_from_expr(expr, refs)
    StmtList(stmts, _) | Block(stmts, _) =>
      collect_nested_function_refs_from_stmts(stmts, refs)
    IfStmt(cond, then_branch, else_branch, _) => {
      collect_nested_function_refs_from_expr(cond, refs)
      collect_nested_function_refs_from_stmt(then_branch, refs)
      match else_branch {
        Some(stmt) => collect_nested_function_refs_from_stmt(stmt, refs)
        None => ()
      }
    }
    WhileStmt(cond, body, _) => {
      collect_nested_function_refs_from_expr(cond, refs)
      collect_nested_function_refs_from_stmt(body, refs)
    }
    ForStmt(init, cond, update, body, _) => {
      match init {
        Some(stmt) => collect_nested_function_refs_from_stmt(stmt, refs)
        None => ()
      }
      match cond {
        Some(expr) => collect_nested_function_refs_from_expr(expr, refs)
        None => ()
      }
      match update {
        Some(expr) => collect_nested_function_refs_from_expr(expr, refs)
        None => ()
      }
      collect_nested_function_refs_from_stmt(body, refs)
    }
    _ => ()
  }
}

///|
fn collect_nested_function_refs_from_expr(
  expr : @ast.Expr,
  refs : Map[String, Bool],
) -> Unit {
  match expr {
    FuncExpr(_, _, body, _) | FuncExprExt(_, _, _, body, _) =>
      collect_name_refs_from_stmts(body, refs)
    Binary(_, left, right, _) | Comma(left, right, _) => {
      collect_nested_function_refs_from_expr(left, refs)
      collect_nested_function_refs_from_expr(right, refs)
    }
    Assign(_, value, _) => collect_nested_function_refs_from_expr(value, refs)
    Call(callee, args, _) => {
      collect_nested_function_refs_from_expr(callee, refs)
      for arg in args {
        collect_nested_function_refs_from_expr(arg, refs)
      }
    }
    Member(obj, _, _) => collect_nested_function_refs_from_expr(obj, refs)
    ComputedMember(obj, key, _) => {
      collect_nested_function_refs_from_expr(obj, refs)
      collect_nested_function_refs_from_expr(key, refs)
    }
    UpdateExpr(_, operand, _, _) =>
      collect_nested_function_refs_from_expr(operand, refs)
    Grouping(inner, _) => collect_nested_function_refs_from_expr(inner, refs)
    ArrayLit(elements, _) =>
      for element in elements {
        collect_nested_function_refs_from_expr(element, refs)
      }
    _ => ()
  }
}

///|
fn collect_name_refs_from_stmts(
  stmts : Array[@ast.Stmt],
  refs : Map[String, Bool],
) -> Unit {
  for stmt in stmts {
    collect_name_refs_from_stmt(stmt, refs)
  }
}

///|
fn collect_name_refs_from_stmt(
  stmt : @ast.Stmt,
  refs : Map[String, Bool],
) -> Unit {
  match stmt {
    VarDecl(_, _, Some(expr), _)
    | ExprStmt(expr, _)
    | ReturnStmt(Some(expr), _)
    | ThrowStmt(expr, _) => collect_name_refs_from_expr(expr, refs)
    FuncDecl(_, _, body, _) | StmtList(body, _) | Block(body, _) =>
      collect_name_refs_from_stmts(body, refs)
    IfStmt(cond, then_branch, else_branch, _) => {
      collect_name_refs_from_expr(cond, refs)
      collect_name_refs_from_stmt(then_branch, refs)
      match else_branch {
        Some(stmt) => collect_name_refs_from_stmt(stmt, refs)
        None => ()
      }
    }
    WhileStmt(cond, body, _) => {
      collect_name_refs_from_expr(cond, refs)
      collect_name_refs_from_stmt(body, refs)
    }
    ForStmt(init, cond, update, body, _) => {
      match init {
        Some(stmt) => collect_name_refs_from_stmt(stmt, refs)
        None => ()
      }
      match cond {
        Some(expr) => collect_name_refs_from_expr(expr, refs)
        None => ()
      }
      match update {
        Some(expr) => collect_name_refs_from_expr(expr, refs)
        None => ()
      }
      collect_name_refs_from_stmt(body, refs)
    }
    _ => ()
  }
}

///|
fn collect_name_refs_from_expr(
  expr : @ast.Expr,
  refs : Map[String, Bool],
) -> Unit {
  match expr {
    Ident(name, _) => refs[name] = true
    Assign(name, value, _) => {
      refs[name] = true
      collect_name_refs_from_expr(value, refs)
    }
    Binary(_, left, right, _) | Comma(left, right, _) => {
      collect_name_refs_from_expr(left, refs)
      collect_name_refs_from_expr(right, refs)
    }
    Call(callee, args, _) => {
      collect_name_refs_from_expr(callee, refs)
      for arg in args {
        collect_name_refs_from_expr(arg, refs)
      }
    }
    Member(obj, _, _) => collect_name_refs_from_expr(obj, refs)
    ComputedMember(obj, key, _) => {
      collect_name_refs_from_expr(obj, refs)
      collect_name_refs_from_expr(key, refs)
    }
    UpdateExpr(_, operand, _, _) => collect_name_refs_from_expr(operand, refs)
    FuncExpr(_, _, body, _) | FuncExprExt(_, _, _, body, _) =>
      collect_name_refs_from_stmts(body, refs)
    Grouping(inner, _) => collect_name_refs_from_expr(inner, refs)
    ArrayLit(elements, _) =>
      for element in elements {
        collect_name_refs_from_expr(element, refs)
      }
    _ => ()
  }
}

///|
fn plan_bytecode_locals(
  params : Array[String],
  body : Array[@ast.Stmt],
  use_local_slots~ : Bool,
) -> BytecodeLocalPlan {
  let names : Array[String] = []
  let indices : Map[String, Int] = {}
  if use_local_slots {
    let captured : Map[String, Bool] = {}
    collect_nested_function_refs_from_stmts(body, captured)
    for param in params {
      add_local_candidate(names, indices, captured, param)
    }
    let vars : Array[String] = []
    collect_current_var_names_from_stmts(body, vars)
    for name in vars {
      add_local_candidate(names, indices, captured, name)
    }
  }
  { names, indices }
}

///|
fn compile_bytecode_function(
  name : String?,
  params : Array[String],
  body : Array[@ast.Stmt],
  use_local_slots? : Bool = true,
) -> BytecodeFunction raise Error {
  let plan = plan_bytecode_locals(params, body, use_local_slots~)
  let builder = BytecodeBuilder::BytecodeBuilder(plan)
  for stmt in body {
    builder.compile_stmt(stmt)
  }
  {
    name,
    params,
    source_body: body,
    body_has_use_strict: @runtime.has_use_strict(body),
    local_names: builder.local_names,
    code: builder.code,
    children: builder.children,
  }
}

///|
pub fn compile_script_to_bytecode(
  stmts : Array[@ast.Stmt],
) -> BytecodeProgram raise Error {
  {
    source_stmts: stmts,
    main: compile_bytecode_function(None, [], stmts, use_local_slots=false),
  }
}

///|
pub fn run_bytecode_script(
  interp : Interpreter,
  stmts : Array[@ast.Stmt],
) -> Value raise Error {
  compile_script_to_bytecode(stmts).run(interp)
}

///|
pub fn BytecodeProgram::run(
  self : BytecodeProgram,
  interp : Interpreter,
) -> Value raise Error {
  interp.run_compiled_script(self.source_stmts, fn(ctx, env) raise {
    match run_bytecode_function(interp, ctx, env, self.main) {
      BytecodeNormal(value) => value
      BytecodeReturn(_) =>
        raise @errors.SyntaxError(
          message="return statement outside of function",
        )
    }
  })
}

///|
fn BytecodeBuilder::add_function(
  self : BytecodeBuilder,
  name : String?,
  params : Array[String],
  body : Array[@ast.Stmt],
) -> Int raise Error {
  let idx = self.children.length()
  self.children.push(compile_bytecode_function(name, params, body))
  idx
}

///|
fn BytecodeBuilder::compile_stmt(
  self : BytecodeBuilder,
  stmt : @ast.Stmt,
) -> Unit raise Error {
  match stmt {
    ExprStmt(expr, _) => {
      self.compile_expr(expr)
      let _ = self.emit(SetCompletion)
    }
    VarDecl(kind, name, init, _) => {
      match init {
        Some(expr) => {
          self.compile_expr(expr)
          if bytecode_is_anonymous_function_definition(expr) {
            let _ = self.emit(SetFunctionName(name))
          }
        }
        None => {
          let _ = self.emit(LoadUndefined)
        }
      }
      match (kind, self.local_slot(name)) {
        (VarKind, Some(slot)) => {
          let _ = self.emit(DefineLocal(slot, init is Some(_)))
        }
        _ => {
          let _ = self.emit(DefineBinding(kind, name, init is Some(_)))
        }
      }
      self.emit_undefined_completion()
    }
    StmtList(stmts, _) =>
      for child in stmts {
        self.compile_stmt(child)
      }
    Block(stmts, _) => {
      if stmts_have_lexical_decl(stmts) {
        bytecode_unsupported("block lexical declaration")
      }
      if stmts_have_function_decl(stmts) {
        bytecode_unsupported("block function declaration")
      }
      if stmts_have_var_decl(stmts) {
        bytecode_unsupported("block var declaration")
      }
      self.emit_undefined_completion()
      for child in stmts {
        self.compile_stmt(child)
      }
    }
    IfStmt(cond, then_branch, else_branch, _) => {
      if stmt_has_function_decl(then_branch) {
        bytecode_unsupported("control-flow function declaration")
      }
      match else_branch {
        Some(stmt) =>
          if stmt_has_function_decl(stmt) {
            bytecode_unsupported("control-flow function declaration")
          }
        None => ()
      }
      if stmt_has_var_decl(then_branch) {
        bytecode_unsupported("control-flow var declaration")
      }
      match else_branch {
        Some(stmt) =>
          if stmt_has_var_decl(stmt) {
            bytecode_unsupported("control-flow var declaration")
          }
        None => ()
      }
      self.emit_undefined_completion()
      self.compile_expr(cond)
      let else_jump = self.emit(JumpIfFalse(-1))
      self.compile_stmt(then_branch)
      let end_jump = self.emit(Jump(-1))
      self.patch(else_jump, JumpIfFalse(self.code.length()))
      match else_branch {
        Some(stmt) => self.compile_stmt(stmt)
        None => ()
      }
      self.patch(end_jump, Jump(self.code.length()))
    }
    WhileStmt(cond, body, _) => {
      if stmt_has_function_decl(body) {
        bytecode_unsupported("control-flow function declaration")
      }
      if stmt_has_var_decl(body) {
        bytecode_unsupported("control-flow var declaration")
      }
      self.emit_undefined_completion()
      let cond_pos = self.code.length()
      self.compile_expr(cond)
      let exit_jump = self.emit(JumpIfFalse(-1))
      self.compile_stmt(body)
      let _ = self.emit(Jump(cond_pos))
      self.patch(exit_jump, JumpIfFalse(self.code.length()))
    }
    ForStmt(init, cond, update, body, _) => {
      if stmt_has_function_decl(body) {
        bytecode_unsupported("control-flow function declaration")
      }
      if stmt_has_var_decl(body) {
        bytecode_unsupported("control-flow var declaration")
      }
      match init {
        Some(stmt) => {
          if stmt_has_lexical_decl(stmt) {
            bytecode_unsupported("for lexical initializer")
          }
          self.compile_for_init(stmt)
        }
        None => ()
      }
      self.emit_undefined_completion()
      let cond_pos = self.code.length()
      match cond {
        Some(expr) => self.compile_expr(expr)
        None => {
          let _ = self.emit(LoadConst(Value::Bool(true)))
        }
      }
      let exit_jump = self.emit(JumpIfFalse(-1))
      self.compile_stmt(body)
      match update {
        Some(expr) => {
          self.compile_expr(expr)
          let _ = self.emit(Pop)
        }
        None => ()
      }
      let _ = self.emit(Jump(cond_pos))
      self.patch(exit_jump, JumpIfFalse(self.code.length()))
    }
    FuncDecl(name, params, body, _) => {
      let fn_idx = self.add_function(Some(name), params, body)
      let _ = self.emit(DeclareFunction(name, fn_idx))
      self.emit_undefined_completion()
    }
    ReturnStmt(expr, _) => {
      match expr {
        Some(value) => self.compile_expr(value)
        None => {
          let _ = self.emit(LoadUndefined)
        }
      }
      let _ = self.emit(Return)
    }
    ThrowStmt(expr, _) => {
      self.compile_expr(expr)
      let _ = self.emit(Throw)
    }
    _ => bytecode_unsupported("statement kind")
  }
}

///|
fn BytecodeBuilder::compile_for_init(
  self : BytecodeBuilder,
  stmt : @ast.Stmt,
) -> Unit raise Error {
  match stmt {
    ExprStmt(expr, _) => {
      self.compile_expr(expr)
      let _ = self.emit(Pop)
    }
    VarDecl(_, _, _, _) | StmtList(_, _) => self.compile_stmt(stmt)
    _ => bytecode_unsupported("for initializer")
  }
}

///|
fn BytecodeBuilder::compile_args(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
) -> Unit raise Error {
  for arg in args {
    match arg {
      SpreadExpr(_, _) => bytecode_unsupported("spread argument")
      _ => self.compile_expr(arg)
    }
  }
}

///|
fn BytecodeBuilder::compile_logical_and(
  self : BytecodeBuilder,
  left : @ast.Expr,
  right : @ast.Expr,
) -> Unit raise Error {
  self.compile_expr(left)
  let keep_left = self.emit(JumpIfFalseKeep(-1))
  let _ = self.emit(Pop)
  self.compile_expr(right)
  self.patch(keep_left, JumpIfFalseKeep(self.code.length()))
}

///|
fn BytecodeBuilder::compile_logical_or(
  self : BytecodeBuilder,
  left : @ast.Expr,
  right : @ast.Expr,
) -> Unit raise Error {
  self.compile_expr(left)
  let keep_left = self.emit(JumpIfTrueKeep(-1))
  let _ = self.emit(Pop)
  self.compile_expr(right)
  self.patch(keep_left, JumpIfTrueKeep(self.code.length()))
}

///|
fn BytecodeBuilder::compile_nullish_coalesce(
  self : BytecodeBuilder,
  left : @ast.Expr,
  right : @ast.Expr,
) -> Unit raise Error {
  self.compile_expr(left)
  let keep_left = self.emit(JumpIfNotNullishKeep(-1))
  let _ = self.emit(Pop)
  self.compile_expr(right)
  self.patch(keep_left, JumpIfNotNullishKeep(self.code.length()))
}

///|
fn BytecodeBuilder::compile_expr(
  self : BytecodeBuilder,
  expr : @ast.Expr,
) -> Unit raise Error {
  match expr {
    NumberLit(n, _, _) => {
      let _ = self.emit(LoadConst(Value::Number(n)))
    }
    StringLit(s, _, _, _) => {
      let _ = self.emit(LoadConst(Value::String_(s)))
    }
    BoolLit(b, _) => {
      let _ = self.emit(LoadConst(Value::Bool(b)))
    }
    NullLit(_) => {
      let _ = self.emit(LoadConst(Value::Null))
    }
    UndefinedLit(_) => {
      let _ = self.emit(LoadUndefined)
    }
    Ident("arguments", _) => bytecode_unsupported("arguments object")
    Ident(name, _) =>
      match self.local_slot(name) {
        Some(slot) => {
          let _ = self.emit(LoadLocal(slot))
        }
        None => {
          let _ = self.emit(LoadName(name))
        }
      }
    Binary(And, left, right, _) => self.compile_logical_and(left, right)
    Binary(Or, left, right, _) => self.compile_logical_or(left, right)
    Binary(NullishCoalesce, left, right, _) =>
      self.compile_nullish_coalesce(left, right)
    Binary(Instanceof, _, _, _) => bytecode_unsupported("instanceof operator")
    Binary(op, left, right, loc) => {
      self.compile_expr(left)
      self.compile_expr(right)
      let _ = self.emit(BinaryOp(op, loc))
    }
    Comma(left, right, _) => {
      self.compile_expr(left)
      let _ = self.emit(Pop)
      self.compile_expr(right)
    }
    Assign("arguments", _, _) => bytecode_unsupported("arguments object")
    Assign(name, value, _) => {
      self.compile_expr(value)
      if bytecode_is_anonymous_function_definition(value) {
        let _ = self.emit(SetFunctionName(name))
      }
      match self.local_slot(name) {
        Some(slot) => {
          let _ = self.emit(StoreLocal(slot))
        }
        None => {
          let _ = self.emit(StoreName(name))
        }
      }
    }
    UpdateExpr(_, Ident("arguments", _), _, _) =>
      bytecode_unsupported("arguments object")
    UpdateExpr(op, Ident(name, _), prefix, loc) =>
      match self.local_slot(name) {
        Some(slot) => {
          let _ = self.emit(UpdateLocal(slot, op, prefix))
        }
        None => {
          let _ = self.emit(UpdateName(name, op, prefix, loc))
        }
      }
    FuncExpr(Some(_), _, _, _) =>
      bytecode_unsupported("named function expression")
    FuncExpr(None, params, body, _) => {
      let fn_idx = self.add_function(None, params, body)
      let _ = self.emit(MakeFunction(fn_idx))
    }
    FuncExprExt(Some(_), _, _, _, _) =>
      bytecode_unsupported("named function expression")
    FuncExprExt(None, params, rest_param, body, _) => {
      let simple_params = simple_ext_param_names(params, rest_param)
      let fn_idx = self.add_function(None, simple_params, body)
      let _ = self.emit(MakeFunction(fn_idx))
    }
    Grouping(inner, _) => self.compile_expr(inner)
    ArrayLit(elements, _) => {
      for element in elements {
        match element {
          ArrayHole(_) | SpreadExpr(_, _) =>
            bytecode_unsupported("array hole or spread element")
          _ => self.compile_expr(element)
        }
      }
      let _ = self.emit(MakeArray(elements.length()))
    }
    Member(Ident("console", _), _, _) => bytecode_unsupported("console member")
    Member(obj, prop, loc) => {
      self.compile_expr(obj)
      let _ = self.emit(GetProperty(prop, loc))
    }
    ComputedMember(obj, key, loc) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      let _ = self.emit(GetComputed(loc))
    }
    Call(Member(Ident("console", _), _, _), _, _) =>
      bytecode_unsupported("console member")
    Call(Member(obj, prop, member_loc), args, loc) => {
      self.compile_expr(obj)
      let _ = self.emit(PreparePropertyCall(prop, member_loc))
      self.compile_args(args)
      let _ = self.emit(CallWithReceiver(args.length(), loc))
    }
    Call(ComputedMember(obj, key, member_loc), args, loc) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      let _ = self.emit(PrepareComputedCall(member_loc))
      self.compile_args(args)
      let _ = self.emit(CallWithReceiver(args.length(), loc))
    }
    Call(callee, args, loc) => {
      if bytecode_is_direct_eval_callee(callee) {
        bytecode_unsupported("direct eval call")
      }
      self.compile_expr(callee)
      self.compile_args(args)
      let _ = self.emit(Call(args.length(), loc))
    }
    _ => bytecode_unsupported("expression kind")
  }
}

///|
fn simple_ext_param_names(
  params : Array[@ast.Param],
  rest_param : String?,
) -> Array[String] raise Error {
  match rest_param {
    Some(_) => bytecode_unsupported("rest parameter")
    None => ()
  }
  let names : Array[String] = []
  for param in params {
    match (param.default_val, param.pattern) {
      (None, None) => names.push(param.name)
      _ => bytecode_unsupported("default or destructuring parameter")
    }
  }
  names
}

///|
fn local_index_from_names(xs : Array[String], name : String) -> Int? {
  for i, x in xs {
    if x == name {
      return Some(i)
    }
  }
  None
}

///|
fn string_array_contains(xs : Array[String], name : String) -> Bool {
  local_index_from_names(xs, name) is Some(_)
}

///|
priv struct BytecodeFrame {
  func_def : BytecodeFunction
  stack : Array[Value]
  locals : Array[Value]
  env : Environment
  ctx : ExecContext
  mut ip : Int
  mut completion : Value
}

///|
fn BytecodeFrame::BytecodeFrame(
  func_def : BytecodeFunction,
  env : Environment,
  ctx : ExecContext,
) -> BytecodeFrame raise Error {
  let locals = Array::make(func_def.local_names.length(), Value::Undefined)
  for i, name in func_def.local_names {
    if string_array_contains(func_def.params, name) && env.has(name) {
      locals[i] = env.get(name)
    }
  }
  { func_def, stack: [], locals, env, ctx, ip: 0, completion: Value::Undefined }
}

///|
fn BytecodeFrame::pop(self : BytecodeFrame) -> Value raise Error {
  match self.stack.pop() {
    Some(value) => value
    None => raise @errors.InternalError(message="bytecode stack underflow")
  }
}

///|
fn BytecodeFrame::peek(self : BytecodeFrame) -> Value raise Error {
  guard self.stack.length() > 0 else {
    raise @errors.InternalError(message="bytecode stack underflow")
  }
  self.stack[self.stack.length() - 1]
}

///|
fn pop_args(frame : BytecodeFrame, arg_count : Int) -> Array[Value] raise Error {
  let args = Array::make(arg_count, Value::Undefined)
  for i = arg_count - 1; i >= 0; i = i - 1 {
    args[i] = frame.pop()
  }
  args
}

///|
fn BytecodeFrame::hoist_env_var_bindings(
  self : BytecodeFrame,
  interp : Interpreter,
) -> Unit raise Error {
  let names : Array[String] = []
  collect_current_var_names_from_stmts(self.func_def.source_body, names)
  for name in names {
    if local_index_from_names(self.func_def.local_names, name) is None {
      interp.define_compiled_binding(
        self.env,
        VarKind,
        name,
        Value::Undefined,
        false,
      )
    }
  }
}

///|
fn BytecodeFrame::hoist_lexical_bindings(
  self : BytecodeFrame,
) -> Unit raise Error {
  for stmt in self.func_def.source_body {
    self.hoist_lexical_bindings_from_stmt(stmt)
  }
}

///|
fn BytecodeFrame::hoist_lexical_bindings_from_stmt(
  self : BytecodeFrame,
  stmt : @ast.Stmt,
) -> Unit raise Error {
  match stmt {
    VarDecl(LetKind, name, _, _) =>
      if !self.env.bindings.contains(name) {
        self.env.def_tdz(name, BindingKind::LetBinding)
      }
    VarDecl(ConstKind, name, _, _) =>
      if !self.env.bindings.contains(name) {
        self.env.def_tdz(name, BindingKind::ConstBinding)
      }
    StmtList(stmts, _) =>
      for child in stmts {
        self.hoist_lexical_bindings_from_stmt(child)
      }
    _ => ()
  }
}

///|
fn BytecodeFrame::define_function_decl(
  self : BytecodeFrame,
  interp : Interpreter,
  name : String,
  child_index : Int,
) -> Unit raise Error {
  let child = self.func_def.children[child_index]
  let func = make_bytecode_func(child, self.env, self.ctx)
  match local_index_from_names(self.func_def.local_names, name) {
    Some(slot) => self.locals[slot] = func
    None => interp.define_compiled_binding(self.env, VarKind, name, func, true)
  }
}

///|
fn BytecodeFrame::hoist_function_decls(
  self : BytecodeFrame,
  interp : Interpreter,
) -> Unit raise Error {
  for instr in self.func_def.code {
    match instr {
      DeclareFunction(name, child_index) =>
        self.define_function_decl(interp, name, child_index)
      _ => ()
    }
  }
}

///|
fn make_bytecode_func(
  func_def : BytecodeFunction,
  closure : Environment,
  enclosing_ctx : ExecContext,
) -> Value raise Error {
  @runtime.validate_function_signature(
    enclosing_ctx.strict,
    func_def.name,
    func_def.params,
    func_def.source_body,
  )
  let strict = enclosing_ctx.strict || func_def.body_has_use_strict
  make_compiled_func(
    func_def.name,
    func_def.params,
    closure,
    strict,
    CompiledBody(fn(interp, ctx, env) raise {
      match run_bytecode_function(interp, ctx, env, func_def) {
        BytecodeNormal(value) => Signal::Normal(value)
        BytecodeReturn(value) => Signal::ReturnSignal(value)
      }
    }),
  )
}

///|
fn run_bytecode_function(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  func_def : BytecodeFunction,
) -> BytecodeRunResult raise Error {
  let frame = BytecodeFrame(func_def, env, ctx)
  frame.hoist_env_var_bindings(interp)
  frame.hoist_lexical_bindings()
  frame.hoist_function_decls(interp)
  while frame.ip < frame.func_def.code.length() {
    let instr = frame.func_def.code[frame.ip]
    frame.ip += 1
    match instr {
      LoadConst(value) => frame.stack.push(value)
      LoadUndefined => frame.stack.push(Value::Undefined)
      LoadName(name) =>
        frame.stack.push(interp.get_compiled_name(frame.env, name))
      StoreName(name) => {
        let value = frame.pop()
        frame.stack.push(
          interp.assign_compiled_name(frame.ctx, frame.env, name, value),
        )
      }
      LoadLocal(slot) => frame.stack.push(frame.locals[slot])
      StoreLocal(slot) => {
        let value = frame.pop()
        frame.locals[slot] = value
        frame.stack.push(value)
      }
      DefineBinding(kind, name, has_initializer) => {
        let value = frame.pop()
        interp.define_compiled_binding(
          frame.env,
          kind,
          name,
          value,
          has_initializer,
        )
      }
      DefineLocal(slot, has_initializer) => {
        let value = frame.pop()
        if has_initializer {
          frame.locals[slot] = value
        }
      }
      SetCompletion => frame.completion = frame.pop()
      Pop => {
        let _ = frame.pop()
      }
      BinaryOp(op, loc) => {
        let right = frame.pop()
        let left = frame.pop()
        frame.stack.push(
          @runtime.eval_binary_op(op, left, right, loc, interp=Some(interp)),
        )
      }
      SetFunctionName(name) => {
        let value = frame.pop()
        @runtime.set_function_name(value, name)
        frame.stack.push(value)
      }
      UpdateName(name, op, prefix, loc) =>
        frame.stack.push(
          interp.update_compiled_name(
            frame.ctx,
            frame.env,
            name,
            op,
            prefix,
            loc,
          ),
        )
      UpdateLocal(slot, op, prefix) => {
        let old_number = @runtime.to_number(
          frame.locals[slot],
          interp=Some(interp),
        )
        let next_value = match op {
          Increment => Value::Number(old_number + 1.0)
          Decrement => Value::Number(old_number - 1.0)
        }
        frame.locals[slot] = next_value
        frame.stack.push(
          if prefix {
            next_value
          } else {
            Value::Number(old_number)
          },
        )
      }
      Jump(target) => frame.ip = target
      JumpIfFalse(target) => {
        let cond = frame.pop()
        if !@runtime.is_truthy(cond) {
          frame.ip = target
        }
      }
      JumpIfFalseKeep(target) => {
        let cond = frame.peek()
        if !@runtime.is_truthy(cond) {
          frame.ip = target
        }
      }
      JumpIfTrueKeep(target) => {
        let cond = frame.peek()
        if @runtime.is_truthy(cond) {
          frame.ip = target
        }
      }
      JumpIfNotNullishKeep(target) =>
        match frame.peek() {
          Null | Undefined => ()
          _ => frame.ip = target
        }
      MakeArray(count) => {
        let elements = pop_args(frame, count)
        frame.stack.push(@runtime.make_array(elements))
      }
      MakeFunction(index) => {
        let child = frame.func_def.children[index]
        frame.stack.push(make_bytecode_func(child, frame.env, frame.ctx))
      }
      DeclareFunction(_, _) => ()
      GetProperty(prop, loc) => {
        let obj = frame.pop()
        frame.stack.push(interp.get_property(obj, prop, loc))
      }
      GetComputed(loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        frame.stack.push(interp.get_computed_property(obj, key, loc))
      }
      PreparePropertyCall(prop, loc) => {
        let obj = frame.pop()
        let callee = interp.get_property(obj, prop, loc)
        frame.stack.push(obj)
        frame.stack.push(callee)
      }
      PrepareComputedCall(loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        let callee = interp.get_computed_property(obj, key, loc)
        frame.stack.push(obj)
        frame.stack.push(callee)
      }
      Call(arg_count, loc) => {
        let args = pop_args(frame, arg_count)
        let callee = frame.pop()
        frame.stack.push(interp.call_value(callee, Value::Undefined, args, loc))
      }
      CallWithReceiver(arg_count, loc) => {
        let args = pop_args(frame, arg_count)
        let callee = frame.pop()
        let receiver = frame.pop()
        frame.stack.push(interp.call_value(callee, receiver, args, loc))
      }
      Return => return BytecodeReturn(frame.pop())
      Throw => {
        let value = frame.pop()
        @runtime.raise_js_exception(value)
      }
    }
  }
  BytecodeNormal(frame.completion)
}
