///|
priv enum BytecodeInstr {
  LoadConst(Value)
  LoadUndefined
  LoadThis
  LoadConsoleMember(String)
  LoadName(String)
  LoadAssignmentName(String)
  StoreName(String)
  LoadLocal(Int)
  StoreLocal(Int)
  DefineBinding(@ast.VarKind, String, Bool) // kind, name, initializer-present
  DefineLocal(Int, Bool) // slot, initializer-present
  SetCompletion
  Pop
  BinaryOp(@ast.BinOp, @token.Loc)
  UnaryValueOp(@ast.UnaryOp, @token.Loc)
  TypeofName(String)
  DeleteName(String)
  DeleteProperty(String)
  DeleteComputed
  AppendTemplate(String)
  MakeRegExp(String, String)
  SetFunctionName(String)
  UpdateName(String, @ast.UpdateOp, Bool, @token.Loc) // name, op, prefix, loc
  UpdateLocal(Int, @ast.UpdateOp, Bool) // slot, op, prefix
  UpdateProperty(String, @ast.UpdateOp, Bool, @token.Loc, @token.Loc) // prop, op, prefix, member loc, op loc
  UpdateComputed(@ast.UpdateOp, Bool, @token.Loc, @token.Loc) // op, prefix, member loc, op loc
  Jump(Int)
  JumpIfFalse(Int)
  JumpIfFalseKeep(Int)
  JumpIfTrueKeep(Int)
  JumpIfNotNullishKeep(Int)
  MakeArray(Int)
  MakeArrayWithHoles(Int, Array[Int])
  StartArray
  ArrayPushValue
  ArrayPushSpread(@token.Loc)
  ArrayPushHole
  StartArgs
  ArgPushValue
  ArgPushSpread(@token.Loc)
  MakeObject(Array[String])
  StartObject
  ObjectSetStatic(String)
  ObjectSpread(@token.Loc)
  MakeFunction(Int)
  DeclareFunction(String, Int)
  GetProperty(String, @token.Loc)
  GetComputed(@token.Loc)
  ReadPropertyForAssign(String, @token.Loc)
  ReadComputedForAssign(@token.Loc)
  DropPropertyAssignReference
  DropComputedAssignReference
  SetProperty(String, @token.Loc)
  SetComputed(@token.Loc)
  PreparePropertyCall(String, @token.Loc)
  PrepareComputedCall(@token.Loc)
  Call(Int, @token.Loc)
  CallWithReceiver(Int, @token.Loc)
  CallSpread(@token.Loc)
  CallSpreadWithReceiver(@token.Loc)
  Construct(Int, @token.Loc)
  ConstructSpread(@token.Loc)
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
  loop_contexts : Array[LoopPatchContext]
}

///|
priv struct LoopPatchContext {
  break_jumps : Array[Int]
  continue_jumps : Array[Int]
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
    loop_contexts: [],
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
fn BytecodeBuilder::push_loop_context(self : BytecodeBuilder) -> Unit {
  self.loop_contexts.push({ break_jumps: [], continue_jumps: [] })
}

///|
fn BytecodeBuilder::pop_loop_context(
  self : BytecodeBuilder,
) -> LoopPatchContext raise Error {
  match self.loop_contexts.pop() {
    Some(ctx) => ctx
    None => {
      bytecode_unsupported("loop context")
      { break_jumps: [], continue_jumps: [] }
    }
  }
}

///|
fn BytecodeBuilder::current_loop_context(
  self : BytecodeBuilder,
  unsupported_kind : String,
) -> LoopPatchContext raise Error {
  if self.loop_contexts.length() == 0 {
    bytecode_unsupported(unsupported_kind)
  }
  self.loop_contexts[self.loop_contexts.length() - 1]
}

///|
fn BytecodeBuilder::emit_loop_break(
  self : BytecodeBuilder,
  label : String?,
) -> Unit raise Error {
  match label {
    Some(_) => bytecode_unsupported("labeled break statement")
    None => ()
  }
  let ctx = self.current_loop_context("break statement")
  let jump = self.emit(Jump(-1))
  ctx.break_jumps.push(jump)
}

///|
fn BytecodeBuilder::emit_loop_continue(
  self : BytecodeBuilder,
  label : String?,
) -> Unit raise Error {
  match label {
    Some(_) => bytecode_unsupported("labeled continue statement")
    None => ()
  }
  let ctx = self.current_loop_context("continue statement")
  let jump = self.emit(Jump(-1))
  ctx.continue_jumps.push(jump)
}

///|
fn BytecodeBuilder::patch_loop_jumps(
  self : BytecodeBuilder,
  jumps : Array[Int],
  target : Int,
) -> Unit {
  for jump in jumps {
    self.patch(jump, Jump(target))
  }
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
    LabeledStmt(_, body, _) => stmt_has_lexical_decl(body)
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
    WhileStmt(_, body, _) | DoWhileStmt(body, _, _) =>
      stmt_has_function_decl(body)
    ForStmt(init, _, _, body, _) => {
      let init_has = match init {
        Some(stmt) => stmt_has_function_decl(stmt)
        None => false
      }
      init_has || stmt_has_function_decl(body)
    }
    LabeledStmt(_, body, _) => stmt_has_function_decl(body)
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
    WhileStmt(_, body, _) | DoWhileStmt(body, _, _) =>
      collect_current_var_names_from_stmt(body, out)
    ForStmt(init, _, _, body, _) => {
      match init {
        Some(stmt) => collect_current_var_names_from_stmt(stmt, out)
        None => ()
      }
      collect_current_var_names_from_stmt(body, out)
    }
    LabeledStmt(_, body, _) => collect_current_var_names_from_stmt(body, out)
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
    DoWhileStmt(body, cond, _) => {
      collect_nested_function_refs_from_stmt(body, refs)
      collect_nested_function_refs_from_expr(cond, refs)
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
    LabeledStmt(_, body, _) =>
      collect_nested_function_refs_from_stmt(body, refs)
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
    Unary(_, operand, _) =>
      collect_nested_function_refs_from_expr(operand, refs)
    Binary(_, left, right, _) | Comma(left, right, _) => {
      collect_nested_function_refs_from_expr(left, refs)
      collect_nested_function_refs_from_expr(right, refs)
    }
    Assign(_, value, _) => collect_nested_function_refs_from_expr(value, refs)
    Call(callee, args, _)
    | OptionalCall(callee, args, _)
    | NewExpr(callee, args, _) => {
      collect_nested_function_refs_from_expr(callee, refs)
      for arg in args {
        collect_nested_function_refs_from_expr(arg, refs)
      }
    }
    Member(obj, _, _) | OptionalMember(obj, _, _) =>
      collect_nested_function_refs_from_expr(obj, refs)
    ComputedMember(obj, key, _) | OptionalComputedMember(obj, key, _) => {
      collect_nested_function_refs_from_expr(obj, refs)
      collect_nested_function_refs_from_expr(key, refs)
    }
    MemberAssign(obj, _, value, _) => {
      collect_nested_function_refs_from_expr(obj, refs)
      collect_nested_function_refs_from_expr(value, refs)
    }
    ComputedAssign(obj, key, value, _) => {
      collect_nested_function_refs_from_expr(obj, refs)
      collect_nested_function_refs_from_expr(key, refs)
      collect_nested_function_refs_from_expr(value, refs)
    }
    CompoundAssign(_, target, value, _) => {
      collect_nested_function_refs_from_expr(target, refs)
      collect_nested_function_refs_from_expr(value, refs)
    }
    UpdateExpr(_, operand, _, _) =>
      collect_nested_function_refs_from_expr(operand, refs)
    Grouping(inner, _) => collect_nested_function_refs_from_expr(inner, refs)
    ArrayLit(elements, _) =>
      for element in elements {
        collect_nested_function_refs_from_expr(element, refs)
      }
    ObjectLit(props, _) => collect_nested_function_refs_from_props(props, refs)
    TemplateLit(_, exprs, _) =>
      for expr in exprs {
        collect_nested_function_refs_from_expr(expr, refs)
      }
    SpreadExpr(inner, _) => collect_nested_function_refs_from_expr(inner, refs)
    _ => ()
  }
}

///|
fn collect_nested_function_refs_from_props(
  props : Array[@ast.Property],
  refs : Map[String, Bool],
) -> Unit {
  for prop in props {
    match prop.kind {
      Spread => collect_nested_function_refs_from_expr(prop.key, refs)
      _ => {
        if prop.computed {
          collect_nested_function_refs_from_expr(prop.key, refs)
        }
        collect_nested_function_refs_from_expr(prop.value, refs)
      }
    }
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
    DoWhileStmt(body, cond, _) => {
      collect_name_refs_from_stmt(body, refs)
      collect_name_refs_from_expr(cond, refs)
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
    LabeledStmt(_, body, _) => collect_name_refs_from_stmt(body, refs)
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
    Unary(_, operand, _) => collect_name_refs_from_expr(operand, refs)
    Binary(_, left, right, _) | Comma(left, right, _) => {
      collect_name_refs_from_expr(left, refs)
      collect_name_refs_from_expr(right, refs)
    }
    Call(callee, args, _)
    | OptionalCall(callee, args, _)
    | NewExpr(callee, args, _) => {
      collect_name_refs_from_expr(callee, refs)
      for arg in args {
        collect_name_refs_from_expr(arg, refs)
      }
    }
    Member(obj, _, _) | OptionalMember(obj, _, _) =>
      collect_name_refs_from_expr(obj, refs)
    ComputedMember(obj, key, _) | OptionalComputedMember(obj, key, _) => {
      collect_name_refs_from_expr(obj, refs)
      collect_name_refs_from_expr(key, refs)
    }
    MemberAssign(obj, _, value, _) => {
      collect_name_refs_from_expr(obj, refs)
      collect_name_refs_from_expr(value, refs)
    }
    ComputedAssign(obj, key, value, _) => {
      collect_name_refs_from_expr(obj, refs)
      collect_name_refs_from_expr(key, refs)
      collect_name_refs_from_expr(value, refs)
    }
    CompoundAssign(_, target, value, _) => {
      collect_name_refs_from_expr(target, refs)
      collect_name_refs_from_expr(value, refs)
    }
    UpdateExpr(_, operand, _, _) => collect_name_refs_from_expr(operand, refs)
    FuncExpr(_, _, body, _) | FuncExprExt(_, _, _, body, _) =>
      collect_name_refs_from_stmts(body, refs)
    Grouping(inner, _) => collect_name_refs_from_expr(inner, refs)
    ArrayLit(elements, _) =>
      for element in elements {
        collect_name_refs_from_expr(element, refs)
      }
    ObjectLit(props, _) => collect_name_refs_from_props(props, refs)
    TemplateLit(_, exprs, _) =>
      for expr in exprs {
        collect_name_refs_from_expr(expr, refs)
      }
    SpreadExpr(inner, _) => collect_name_refs_from_expr(inner, refs)
    _ => ()
  }
}

///|
fn collect_name_refs_from_props(
  props : Array[@ast.Property],
  refs : Map[String, Bool],
) -> Unit {
  for prop in props {
    match prop.kind {
      Spread => collect_name_refs_from_expr(prop.key, refs)
      _ => {
        if prop.computed {
          collect_name_refs_from_expr(prop.key, refs)
        }
        collect_name_refs_from_expr(prop.value, refs)
      }
    }
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
  declaration_updates_completion? : Bool = true,
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
      if declaration_updates_completion {
        self.emit_undefined_completion()
      }
    }
    StmtList(stmts, _) => {
      self.emit_undefined_completion()
      for child in stmts {
        self.compile_stmt(child, declaration_updates_completion=false)
      }
    }
    Block(stmts, _) => {
      if stmts_have_lexical_decl(stmts) {
        bytecode_unsupported("block lexical declaration")
      }
      if stmts_have_function_decl(stmts) {
        bytecode_unsupported("block function declaration")
      }
      self.emit_undefined_completion()
      for child in stmts {
        self.compile_stmt(child, declaration_updates_completion=false)
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
      self.compile_expr(cond)
      let else_jump = self.emit(JumpIfFalse(-1))
      self.compile_stmt(then_branch)
      let end_jump = self.emit(Jump(-1))
      self.patch(else_jump, JumpIfFalse(self.code.length()))
      match else_branch {
        Some(stmt) => self.compile_stmt(stmt)
        None => self.emit_undefined_completion()
      }
      self.patch(end_jump, Jump(self.code.length()))
    }
    WhileStmt(cond, body, _) => {
      if stmt_has_function_decl(body) {
        bytecode_unsupported("control-flow function declaration")
      }
      self.emit_undefined_completion()
      let cond_pos = self.code.length()
      self.compile_expr(cond)
      let exit_jump = self.emit(JumpIfFalse(-1))
      self.push_loop_context()
      self.compile_stmt(body)
      let loop_ctx = self.pop_loop_context()
      let _ = self.emit(Jump(cond_pos))
      let exit_pos = self.code.length()
      self.patch(exit_jump, JumpIfFalse(exit_pos))
      self.patch_loop_jumps(loop_ctx.break_jumps, exit_pos)
      self.patch_loop_jumps(loop_ctx.continue_jumps, cond_pos)
    }
    DoWhileStmt(body, cond, _) => {
      if stmt_has_function_decl(body) {
        bytecode_unsupported("control-flow function declaration")
      }
      self.emit_undefined_completion()
      let body_pos = self.code.length()
      self.push_loop_context()
      self.compile_stmt(body)
      let loop_ctx = self.pop_loop_context()
      let cond_pos = self.code.length()
      self.patch_loop_jumps(loop_ctx.continue_jumps, cond_pos)
      self.compile_expr(cond)
      let exit_jump = self.emit(JumpIfFalse(-1))
      let _ = self.emit(Jump(body_pos))
      let exit_pos = self.code.length()
      self.patch(exit_jump, JumpIfFalse(exit_pos))
      self.patch_loop_jumps(loop_ctx.break_jumps, exit_pos)
    }
    ForStmt(init, cond, update, body, _) => {
      if stmt_has_function_decl(body) {
        bytecode_unsupported("control-flow function declaration")
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
      self.push_loop_context()
      self.compile_stmt(body)
      let loop_ctx = self.pop_loop_context()
      let update_pos = self.code.length()
      self.patch_loop_jumps(loop_ctx.continue_jumps, update_pos)
      match update {
        Some(expr) => {
          self.compile_expr(expr)
          let _ = self.emit(Pop)
        }
        None => ()
      }
      let _ = self.emit(Jump(cond_pos))
      let exit_pos = self.code.length()
      self.patch(exit_jump, JumpIfFalse(exit_pos))
      self.patch_loop_jumps(loop_ctx.break_jumps, exit_pos)
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
    BreakStmt(label, _) => self.emit_loop_break(label)
    ContinueStmt(label, _) => self.emit_loop_continue(label)
    ThrowStmt(expr, _) => {
      self.compile_expr(expr)
      let _ = self.emit(Throw)
    }
    LabeledStmt(_, body, _) => {
      if stmt_has_function_decl(body) {
        bytecode_unsupported("control-flow function declaration")
      }
      self.compile_stmt(body, declaration_updates_completion~)
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
fn bytecode_args_have_spread(args : Array[@ast.Expr]) -> Bool {
  for arg in args {
    match arg {
      SpreadExpr(_, _) => return true
      _ => ()
    }
  }
  false
}

///|
fn BytecodeBuilder::compile_fixed_args(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
) -> Unit raise Error {
  for arg in args {
    self.compile_expr(arg)
  }
}

///|
fn BytecodeBuilder::compile_dynamic_args(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
) -> Unit raise Error {
  let _ = self.emit(StartArgs)
  for arg in args {
    match arg {
      SpreadExpr(inner, loc) => {
        self.compile_expr(inner)
        let _ = self.emit(ArgPushSpread(loc))
      }
      _ => {
        self.compile_expr(arg)
        let _ = self.emit(ArgPushValue)
      }
    }
  }
}

///|
fn BytecodeBuilder::compile_call_args(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
) -> Bool raise Error {
  if bytecode_args_have_spread(args) {
    self.compile_dynamic_args(args)
    true
  } else {
    self.compile_fixed_args(args)
    false
  }
}

///|
fn BytecodeBuilder::emit_call(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
  loc : @token.Loc,
) -> Unit raise Error {
  if self.compile_call_args(args) {
    let _ = self.emit(CallSpread(loc))
  } else {
    let _ = self.emit(Call(args.length(), loc))
  }
}

///|
fn BytecodeBuilder::emit_call_with_receiver(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
  loc : @token.Loc,
) -> Unit raise Error {
  if self.compile_call_args(args) {
    let _ = self.emit(CallSpreadWithReceiver(loc))
  } else {
    let _ = self.emit(CallWithReceiver(args.length(), loc))
  }
}

///|
fn BytecodeBuilder::emit_construct(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
  loc : @token.Loc,
) -> Unit raise Error {
  if self.compile_call_args(args) {
    let _ = self.emit(ConstructSpread(loc))
  } else {
    let _ = self.emit(Construct(args.length(), loc))
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
fn BytecodeBuilder::compile_optional_member(
  self : BytecodeBuilder,
  obj : @ast.Expr,
  prop : String,
  loc : @token.Loc,
) -> Unit raise Error {
  self.compile_expr(obj)
  let get_jump = self.emit(JumpIfNotNullishKeep(-1))
  let _ = self.emit(Pop)
  let _ = self.emit(LoadUndefined)
  let end_jump = self.emit(Jump(-1))
  self.patch(get_jump, JumpIfNotNullishKeep(self.code.length()))
  let _ = self.emit(GetProperty(prop, loc))
  self.patch(end_jump, Jump(self.code.length()))
}

///|
fn BytecodeBuilder::compile_optional_computed_member(
  self : BytecodeBuilder,
  obj : @ast.Expr,
  key : @ast.Expr,
  loc : @token.Loc,
) -> Unit raise Error {
  self.compile_expr(obj)
  let get_jump = self.emit(JumpIfNotNullishKeep(-1))
  let _ = self.emit(Pop)
  let _ = self.emit(LoadUndefined)
  let end_jump = self.emit(Jump(-1))
  self.patch(get_jump, JumpIfNotNullishKeep(self.code.length()))
  self.compile_expr(key)
  let _ = self.emit(GetComputed(loc))
  self.patch(end_jump, Jump(self.code.length()))
}

///|
fn BytecodeBuilder::compile_optional_plain_call(
  self : BytecodeBuilder,
  callee : @ast.Expr,
  args : Array[@ast.Expr],
  loc : @token.Loc,
) -> Unit raise Error {
  self.compile_expr(callee)
  let call_jump = self.emit(JumpIfNotNullishKeep(-1))
  let _ = self.emit(Pop)
  let _ = self.emit(LoadUndefined)
  let end_jump = self.emit(Jump(-1))
  self.patch(call_jump, JumpIfNotNullishKeep(self.code.length()))
  self.emit_call(args, loc)
  self.patch(end_jump, Jump(self.code.length()))
}

///|
fn BytecodeBuilder::compile_optional_call_with_receiver_tail(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
  loc : @token.Loc,
  end_jumps : Array[Int],
) -> Unit raise Error {
  let call_jump = self.emit(JumpIfNotNullishKeep(-1))
  let _ = self.emit(Pop)
  let _ = self.emit(Pop)
  let _ = self.emit(LoadUndefined)
  end_jumps.push(self.emit(Jump(-1)))
  self.patch(call_jump, JumpIfNotNullishKeep(self.code.length()))
  self.emit_call_with_receiver(args, loc)
  for jump in end_jumps {
    self.patch(jump, Jump(self.code.length()))
  }
}

///|
fn BytecodeBuilder::compile_optional_property_call(
  self : BytecodeBuilder,
  obj : @ast.Expr,
  prop : String,
  args : Array[@ast.Expr],
  member_loc : @token.Loc,
  loc : @token.Loc,
  optional_obj~ : Bool,
) -> Unit raise Error {
  let end_jumps : Array[Int] = []
  self.compile_expr(obj)
  if optional_obj {
    let member_jump = self.emit(JumpIfNotNullishKeep(-1))
    let _ = self.emit(Pop)
    let _ = self.emit(LoadUndefined)
    end_jumps.push(self.emit(Jump(-1)))
    self.patch(member_jump, JumpIfNotNullishKeep(self.code.length()))
  }
  let _ = self.emit(PreparePropertyCall(prop, member_loc))
  self.compile_optional_call_with_receiver_tail(args, loc, end_jumps)
}

///|
fn BytecodeBuilder::compile_optional_computed_call(
  self : BytecodeBuilder,
  obj : @ast.Expr,
  key : @ast.Expr,
  args : Array[@ast.Expr],
  member_loc : @token.Loc,
  loc : @token.Loc,
  optional_obj~ : Bool,
) -> Unit raise Error {
  let end_jumps : Array[Int] = []
  self.compile_expr(obj)
  if optional_obj {
    let member_jump = self.emit(JumpIfNotNullishKeep(-1))
    let _ = self.emit(Pop)
    let _ = self.emit(LoadUndefined)
    end_jumps.push(self.emit(Jump(-1)))
    self.patch(member_jump, JumpIfNotNullishKeep(self.code.length()))
  }
  self.compile_expr(key)
  let _ = self.emit(PrepareComputedCall(member_loc))
  self.compile_optional_call_with_receiver_tail(args, loc, end_jumps)
}

///|
fn BytecodeBuilder::compile_identifier_load(
  self : BytecodeBuilder,
  name : String,
) -> Unit {
  match self.local_slot(name) {
    Some(slot) => {
      let _ = self.emit(LoadLocal(slot))
    }
    None => {
      let _ = self.emit(LoadName(name))
    }
  }
}

///|
fn BytecodeBuilder::compile_identifier_store(
  self : BytecodeBuilder,
  name : String,
) -> Unit {
  match self.local_slot(name) {
    Some(slot) => {
      let _ = self.emit(StoreLocal(slot))
    }
    None => {
      let _ = self.emit(StoreName(name))
    }
  }
}

///|
fn BytecodeBuilder::compile_identifier_compound_load(
  self : BytecodeBuilder,
  name : String,
) -> Unit {
  match self.local_slot(name) {
    Some(slot) => {
      let _ = self.emit(LoadLocal(slot))
    }
    None => {
      let _ = self.emit(LoadAssignmentName(name))
    }
  }
}

///|
fn BytecodeBuilder::compile_identifier_logical_assign(
  self : BytecodeBuilder,
  op : @ast.CompoundOp,
  name : String,
  value : @ast.Expr,
) -> Unit raise Error {
  self.compile_identifier_compound_load(name)
  let keep_current = match op {
    LogicalAndAssign => self.emit(JumpIfFalseKeep(-1))
    LogicalOrAssign => self.emit(JumpIfTrueKeep(-1))
    NullishAssign => self.emit(JumpIfNotNullishKeep(-1))
    _ => {
      bytecode_unsupported("logical assignment operator")
      -1
    }
  }
  let _ = self.emit(Pop)
  self.compile_expr(value)
  self.compile_identifier_store(name)
  match op {
    LogicalAndAssign =>
      self.patch(keep_current, JumpIfFalseKeep(self.code.length()))
    LogicalOrAssign =>
      self.patch(keep_current, JumpIfTrueKeep(self.code.length()))
    NullishAssign =>
      self.patch(keep_current, JumpIfNotNullishKeep(self.code.length()))
    _ => ()
  }
}

///|
fn BytecodeBuilder::compile_property_logical_assign(
  self : BytecodeBuilder,
  op : @ast.CompoundOp,
  obj : @ast.Expr,
  prop : String,
  value : @ast.Expr,
  member_loc : @token.Loc,
  loc : @token.Loc,
) -> Unit raise Error {
  self.compile_expr(obj)
  let _ = self.emit(ReadPropertyForAssign(prop, member_loc))
  let keep_current = match op {
    LogicalAndAssign => self.emit(JumpIfFalseKeep(-1))
    LogicalOrAssign => self.emit(JumpIfTrueKeep(-1))
    NullishAssign => self.emit(JumpIfNotNullishKeep(-1))
    _ => {
      bytecode_unsupported("logical assignment operator")
      -1
    }
  }
  let _ = self.emit(Pop)
  self.compile_expr(value)
  let _ = self.emit(SetProperty(prop, loc))
  let end_jump = self.emit(Jump(-1))
  match op {
    LogicalAndAssign =>
      self.patch(keep_current, JumpIfFalseKeep(self.code.length()))
    LogicalOrAssign =>
      self.patch(keep_current, JumpIfTrueKeep(self.code.length()))
    NullishAssign =>
      self.patch(keep_current, JumpIfNotNullishKeep(self.code.length()))
    _ => ()
  }
  let _ = self.emit(DropPropertyAssignReference)
  self.patch(end_jump, Jump(self.code.length()))
}

///|
fn BytecodeBuilder::compile_computed_logical_assign(
  self : BytecodeBuilder,
  op : @ast.CompoundOp,
  obj : @ast.Expr,
  key : @ast.Expr,
  value : @ast.Expr,
  member_loc : @token.Loc,
  loc : @token.Loc,
) -> Unit raise Error {
  self.compile_expr(obj)
  self.compile_expr(key)
  let _ = self.emit(ReadComputedForAssign(member_loc))
  let keep_current = match op {
    LogicalAndAssign => self.emit(JumpIfFalseKeep(-1))
    LogicalOrAssign => self.emit(JumpIfTrueKeep(-1))
    NullishAssign => self.emit(JumpIfNotNullishKeep(-1))
    _ => {
      bytecode_unsupported("logical assignment operator")
      -1
    }
  }
  let _ = self.emit(Pop)
  self.compile_expr(value)
  let _ = self.emit(SetComputed(loc))
  let end_jump = self.emit(Jump(-1))
  match op {
    LogicalAndAssign =>
      self.patch(keep_current, JumpIfFalseKeep(self.code.length()))
    LogicalOrAssign =>
      self.patch(keep_current, JumpIfTrueKeep(self.code.length()))
    NullishAssign =>
      self.patch(keep_current, JumpIfNotNullishKeep(self.code.length()))
    _ => ()
  }
  let _ = self.emit(DropComputedAssignReference)
  self.patch(end_jump, Jump(self.code.length()))
}

///|
fn BytecodeBuilder::compile_identifier_compound_assign(
  self : BytecodeBuilder,
  op : @ast.CompoundOp,
  name : String,
  value : @ast.Expr,
  loc : @token.Loc,
) -> Unit raise Error {
  if name == "arguments" {
    bytecode_unsupported("arguments object")
  }
  match op {
    LogicalAndAssign | LogicalOrAssign | NullishAssign =>
      self.compile_identifier_logical_assign(op, name, value)
    _ => {
      let bin_op = match @runtime.compound_assign_binary_op(op) {
        Some(bin_op) => bin_op
        None => {
          bytecode_unsupported("logical assignment operator")
          Add
        }
      }
      self.compile_identifier_compound_load(name)
      self.compile_expr(value)
      let _ = self.emit(BinaryOp(bin_op, loc))
      self.compile_identifier_store(name)
    }
  }
}

///|
fn BytecodeBuilder::compile_property_compound_assign(
  self : BytecodeBuilder,
  op : @ast.CompoundOp,
  obj : @ast.Expr,
  prop : String,
  value : @ast.Expr,
  member_loc : @token.Loc,
  loc : @token.Loc,
) -> Unit raise Error {
  match op {
    LogicalAndAssign | LogicalOrAssign | NullishAssign =>
      return self.compile_property_logical_assign(
        op, obj, prop, value, member_loc, loc,
      )
    _ => ()
  }
  let bin_op = match @runtime.compound_assign_binary_op(op) {
    Some(bin_op) => bin_op
    None => {
      bytecode_unsupported("compound assignment target")
      Add
    }
  }
  self.compile_expr(obj)
  let _ = self.emit(ReadPropertyForAssign(prop, member_loc))
  self.compile_expr(value)
  let _ = self.emit(BinaryOp(bin_op, loc))
  let _ = self.emit(SetProperty(prop, loc))
}

///|
fn BytecodeBuilder::compile_computed_compound_assign(
  self : BytecodeBuilder,
  op : @ast.CompoundOp,
  obj : @ast.Expr,
  key : @ast.Expr,
  value : @ast.Expr,
  member_loc : @token.Loc,
  loc : @token.Loc,
) -> Unit raise Error {
  match op {
    LogicalAndAssign | LogicalOrAssign | NullishAssign =>
      return self.compile_computed_logical_assign(
        op, obj, key, value, member_loc, loc,
      )
    _ => ()
  }
  let bin_op = match @runtime.compound_assign_binary_op(op) {
    Some(bin_op) => bin_op
    None => {
      bytecode_unsupported("compound assignment target")
      Add
    }
  }
  self.compile_expr(obj)
  self.compile_expr(key)
  let _ = self.emit(ReadComputedForAssign(member_loc))
  self.compile_expr(value)
  let _ = self.emit(BinaryOp(bin_op, loc))
  let _ = self.emit(SetComputed(loc))
}

///|
fn bytecode_static_object_key(expr : @ast.Expr) -> String? {
  match expr {
    StringLit(s, _, _, _) => Some(s)
    Ident(name, _) => Some(name)
    NumberLit(n, _, _) => {
      let i = n.to_int()
      if i.to_double() == n {
        Some(i.to_string())
      } else {
        Some(n.to_string())
      }
    }
    _ => None
  }
}

///|
fn BytecodeBuilder::compile_object_lit(
  self : BytecodeBuilder,
  props : Array[@ast.Property],
  loc : @token.Loc,
) -> Unit raise Error {
  let mut has_spread = false
  for prop in props {
    match prop.kind {
      Spread => has_spread = true
      _ => ()
    }
  }
  if has_spread {
    let _ = self.emit(StartObject)
    for prop in props {
      match prop.kind {
        Spread => {
          self.compile_expr(prop.key)
          let _ = self.emit(ObjectSpread(loc))
          continue
        }
        Init => ()
        Get | Set => bytecode_unsupported("object literal accessor property")
      }
      if prop.computed {
        bytecode_unsupported("object literal computed property")
      }
      if prop.is_method {
        bytecode_unsupported("object literal method property")
      }
      let key = match bytecode_static_object_key(prop.key) {
        Some(key) => key
        None => {
          bytecode_unsupported("object literal property key")
          ""
        }
      }
      if key == "__proto__" {
        bytecode_unsupported("object literal __proto__ property")
      }
      self.compile_expr(prop.value)
      let _ = self.emit(SetFunctionName(key))
      let _ = self.emit(ObjectSetStatic(key))
    }
  } else {
    let keys : Array[String] = []
    for prop in props {
      match prop.kind {
        Get | Set => bytecode_unsupported("object literal accessor property")
        _ => ()
      }
      if prop.computed {
        bytecode_unsupported("object literal computed property")
      }
      if prop.is_method {
        bytecode_unsupported("object literal method property")
      }
      let key = match bytecode_static_object_key(prop.key) {
        Some(key) => key
        None => {
          bytecode_unsupported("object literal property key")
          ""
        }
      }
      if key == "__proto__" {
        bytecode_unsupported("object literal __proto__ property")
      }
      self.compile_expr(prop.value)
      let _ = self.emit(SetFunctionName(key))
      keys.push(key)
    }
    let _ = self.emit(MakeObject(keys))
  }
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
    ThisExpr(_) => {
      let _ = self.emit(LoadThis)
    }
    Ident("arguments", _) => bytecode_unsupported("arguments object")
    Ident(name, _) => self.compile_identifier_load(name)
    Binary(And, left, right, _) => self.compile_logical_and(left, right)
    Binary(Or, left, right, _) => self.compile_logical_or(left, right)
    Binary(NullishCoalesce, left, right, _) =>
      self.compile_nullish_coalesce(left, right)
    Unary(Delete, Member(obj, prop, _), _) => {
      self.compile_expr(obj)
      let _ = self.emit(DeleteProperty(prop))
    }
    Unary(Delete, ComputedMember(obj, key, _), _) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      let _ = self.emit(DeleteComputed)
    }
    Unary(Delete, Ident(name, _), _) => {
      let _ = self.emit(DeleteName(name))
    }
    Unary(Delete, _, _) => bytecode_unsupported("delete non-property operator")
    Unary(Typeof, Ident("arguments", _), _) =>
      bytecode_unsupported("arguments object")
    Unary(Typeof, Ident(name, _), loc) =>
      match self.local_slot(name) {
        Some(slot) => {
          let _ = self.emit(LoadLocal(slot))
          let _ = self.emit(UnaryValueOp(Typeof, loc))
        }
        None => {
          let _ = self.emit(TypeofName(name))
        }
      }
    Unary(Typeof, operand, loc) => {
      self.compile_expr(operand)
      let _ = self.emit(UnaryValueOp(Typeof, loc))
    }
    Unary(Void, operand, _) => {
      self.compile_expr(operand)
      let _ = self.emit(Pop)
      let _ = self.emit(LoadUndefined)
    }
    Unary(op, operand, loc) => {
      self.compile_expr(operand)
      let _ = self.emit(UnaryValueOp(op, loc))
    }
    Ternary(cond, then_expr, else_expr, _) => {
      self.compile_expr(cond)
      let else_jump = self.emit(JumpIfFalse(-1))
      self.compile_expr(then_expr)
      let end_jump = self.emit(Jump(-1))
      self.patch(else_jump, JumpIfFalse(self.code.length()))
      self.compile_expr(else_expr)
      self.patch(end_jump, Jump(self.code.length()))
    }
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
    TemplateLit(strings, exprs, _) => {
      let first = if strings.length() > 0 { strings[0] } else { "" }
      let _ = self.emit(LoadConst(Value::String_(first)))
      for i, expr in exprs {
        self.compile_expr(expr)
        let tail = if i + 1 < strings.length() { strings[i + 1] } else { "" }
        let _ = self.emit(AppendTemplate(tail))
      }
    }
    RegexLit(pattern, flags, _) => {
      let _ = self.emit(MakeRegExp(pattern, flags))
    }
    Assign("arguments", _, _) => bytecode_unsupported("arguments object")
    Assign(name, value, _) => {
      self.compile_expr(value)
      if bytecode_is_anonymous_function_definition(value) {
        let _ = self.emit(SetFunctionName(name))
      }
      self.compile_identifier_store(name)
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
    UpdateExpr(op, Member(obj, prop, member_loc), prefix, loc) => {
      self.compile_expr(obj)
      let _ = self.emit(UpdateProperty(prop, op, prefix, member_loc, loc))
    }
    UpdateExpr(op, ComputedMember(obj, key, member_loc), prefix, loc) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      let _ = self.emit(UpdateComputed(op, prefix, member_loc, loc))
    }
    CompoundAssign(op, Ident(name, _), value, loc) =>
      self.compile_identifier_compound_assign(op, name, value, loc)
    CompoundAssign(op, Member(obj, prop, member_loc), value, loc) =>
      self.compile_property_compound_assign(
        op, obj, prop, value, member_loc, loc,
      )
    CompoundAssign(op, ComputedMember(obj, key, member_loc), value, loc) =>
      self.compile_computed_compound_assign(
        op, obj, key, value, member_loc, loc,
      )
    CompoundAssign(_, _, _, _) =>
      bytecode_unsupported("compound assignment target")
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
    ObjectLit(props, loc) => self.compile_object_lit(props, loc)
    ArrayLit(elements, _) => {
      let mut has_spread = false
      for element in elements {
        match element {
          SpreadExpr(_, _) => has_spread = true
          _ => ()
        }
      }
      if has_spread {
        let _ = self.emit(StartArray)
        for element in elements {
          match element {
            ArrayHole(_) => {
              let _ = self.emit(ArrayPushHole)
            }
            SpreadExpr(inner, loc) => {
              self.compile_expr(inner)
              let _ = self.emit(ArrayPushSpread(loc))
            }
            _ => {
              self.compile_expr(element)
              let _ = self.emit(ArrayPushValue)
            }
          }
        }
      } else {
        let hole_idxs : Array[Int] = []
        for i, element in elements {
          match element {
            ArrayHole(_) => {
              hole_idxs.push(i)
              let _ = self.emit(LoadUndefined)
            }
            _ => self.compile_expr(element)
          }
        }
        if hole_idxs.length() > 0 {
          let _ = self.emit(MakeArrayWithHoles(elements.length(), hole_idxs))
        } else {
          let _ = self.emit(MakeArray(elements.length()))
        }
      }
    }
    Member(Ident("console", _), prop, _) => {
      let _ = self.emit(LoadConsoleMember(prop))
    }
    Member(obj, prop, loc) => {
      self.compile_expr(obj)
      let _ = self.emit(GetProperty(prop, loc))
    }
    ComputedMember(obj, key, loc) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      let _ = self.emit(GetComputed(loc))
    }
    OptionalMember(obj, prop, loc) =>
      self.compile_optional_member(obj, prop, loc)
    OptionalComputedMember(obj, key, loc) =>
      self.compile_optional_computed_member(obj, key, loc)
    MemberAssign(obj, prop, value, loc) => {
      self.compile_expr(obj)
      self.compile_expr(value)
      let _ = self.emit(SetProperty(prop, loc))
    }
    ComputedAssign(obj, key, value, loc) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      self.compile_expr(value)
      let _ = self.emit(SetComputed(loc))
    }
    NewExpr(callee, args, loc) => {
      self.compile_expr(callee)
      self.emit_construct(args, loc)
    }
    OptionalCall(callee, args, loc) =>
      match callee {
        OptionalMember(obj, prop, member_loc) =>
          self.compile_optional_property_call(
            obj,
            prop,
            args,
            member_loc,
            loc,
            optional_obj=true,
          )
        OptionalComputedMember(obj, key, member_loc) =>
          self.compile_optional_computed_call(
            obj,
            key,
            args,
            member_loc,
            loc,
            optional_obj=true,
          )
        Member(obj, prop, member_loc) =>
          self.compile_optional_property_call(
            obj,
            prop,
            args,
            member_loc,
            loc,
            optional_obj=false,
          )
        ComputedMember(obj, key, member_loc) =>
          self.compile_optional_computed_call(
            obj,
            key,
            args,
            member_loc,
            loc,
            optional_obj=false,
          )
        _ => self.compile_optional_plain_call(callee, args, loc)
      }
    Call(Member(Ident("console", _), prop, _), args, loc) => {
      let _ = self.emit(LoadConsoleMember(prop))
      self.emit_call(args, loc)
    }
    Call(Member(obj, prop, member_loc), args, loc) => {
      self.compile_expr(obj)
      let _ = self.emit(PreparePropertyCall(prop, member_loc))
      self.emit_call_with_receiver(args, loc)
    }
    Call(ComputedMember(obj, key, member_loc), args, loc) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      let _ = self.emit(PrepareComputedCall(member_loc))
      self.emit_call_with_receiver(args, loc)
    }
    Call(callee, args, loc) => {
      if bytecode_is_direct_eval_callee(callee) {
        bytecode_unsupported("direct eval call")
      }
      self.compile_expr(callee)
      self.emit_call(args, loc)
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
  arg_lists : Array[Array[Value]]
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
  {
    func_def,
    stack: [],
    arg_lists: [],
    locals,
    env,
    ctx,
    ip: 0,
    completion: Value::Undefined,
  }
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
fn BytecodeFrame::current_arg_list(
  self : BytecodeFrame,
) -> Array[Value] raise Error {
  guard self.arg_lists.length() > 0 else {
    raise @errors.InternalError(message="bytecode argument list underflow")
  }
  self.arg_lists[self.arg_lists.length() - 1]
}

///|
fn BytecodeFrame::pop_dynamic_args(
  self : BytecodeFrame,
) -> Array[Value] raise Error {
  match self.arg_lists.pop() {
    Some(args) => args
    None =>
      raise @errors.InternalError(message="bytecode argument list underflow")
  }
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
      LoadThis => frame.stack.push(@runtime.eval_this_value(frame.env))
      LoadConsoleMember(prop) =>
        frame.stack.push(interp.get_console_member(prop))
      LoadName(name) =>
        frame.stack.push(interp.get_compiled_name(frame.env, name))
      LoadAssignmentName(name) =>
        frame.stack.push(
          @runtime.get_assignment_name_value(frame.ctx, frame.env, name),
        )
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
      UnaryValueOp(op, loc) => {
        let value = frame.pop()
        frame.stack.push(@runtime.eval_unary_value_op(op, value, loc))
      }
      TypeofName(name) =>
        frame.stack.push(
          interp.typeof_compiled_name(frame.ctx, frame.env, name),
        )
      DeleteName(name) =>
        frame.stack.push(
          @runtime.eval_delete_identifier(interp, frame.ctx, frame.env, name),
        )
      DeleteProperty(prop) => {
        let obj = frame.pop()
        frame.stack.push(
          @runtime.eval_delete_property(interp, obj, prop, frame.ctx.strict),
        )
      }
      DeleteComputed => {
        let key = frame.pop()
        let obj = frame.pop()
        frame.stack.push(
          @runtime.eval_delete_computed_property(
            interp,
            obj,
            key,
            frame.ctx.strict,
          ),
        )
      }
      AppendTemplate(tail) => {
        let value = frame.pop()
        let acc = frame.pop()
        match acc {
          String_(prefix) =>
            frame.stack.push(
              Value::String_(
                prefix +
                @runtime.to_js_string(value, interp=Some(interp)) +
                tail,
              ),
            )
          _ =>
            raise @errors.InternalError(
              message="bytecode template accumulator was not a string",
            )
        }
      }
      MakeRegExp(pattern, flags) =>
        frame.stack.push(
          (interp.stdlib_hooks.make_regexp_object)(
            interp.realm_state,
            pattern,
            flags,
          ),
        )
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
      UpdateProperty(prop, op, prefix, member_loc, loc) => {
        let obj = frame.pop()
        frame.stack.push(
          interp.eval_update_property(
            frame.ctx,
            obj,
            prop,
            op,
            prefix,
            member_loc,
            loc,
          ),
        )
      }
      UpdateComputed(op, prefix, member_loc, loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        frame.stack.push(
          interp.eval_update_computed_property(
            frame.ctx,
            obj,
            key,
            op,
            prefix,
            member_loc,
            loc,
          ),
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
      MakeArrayWithHoles(count, hole_idxs) => {
        let elements = pop_args(frame, count)
        frame.stack.push(@runtime.make_array_with_holes(elements, hole_idxs))
      }
      StartArray => frame.stack.push(@runtime.make_array([]))
      ArrayPushValue => {
        let value = frame.pop()
        match frame.peek() {
          Array(data) => data.elements.push(value)
          _ =>
            raise @errors.InternalError(
              message="bytecode array accumulator was not an array",
            )
        }
      }
      ArrayPushSpread(loc) => {
        let value = frame.pop()
        let spread_values = interp.spread_iterable(value, loc)
        match frame.peek() {
          Array(data) =>
            for spread_value in spread_values {
              data.elements.push(spread_value)
            }
          _ =>
            raise @errors.InternalError(
              message="bytecode array accumulator was not an array",
            )
        }
      }
      ArrayPushHole =>
        match frame.peek() {
          Array(data) => {
            data.holes[data.elements.length()] = ()
            data.elements.push(Value::Undefined)
          }
          _ =>
            raise @errors.InternalError(
              message="bytecode array accumulator was not an array",
            )
        }
      StartArgs => frame.arg_lists.push([])
      ArgPushValue => {
        let value = frame.pop()
        let args = frame.current_arg_list()
        args.push(value)
      }
      ArgPushSpread(loc) => {
        let value = frame.pop()
        let spread_values = interp.spread_iterable(value, loc)
        let args = frame.current_arg_list()
        for spread_value in spread_values {
          args.push(spread_value)
        }
      }
      MakeObject(keys) => {
        let values = pop_args(frame, keys.length())
        let properties : Map[String, Value] = {}
        for i, key in keys {
          properties[key] = values[i]
        }
        let prototype = frame.env.get("[[ObjectPrototype]]") catch {
          _ => Value::Null
        }
        frame.stack.push(
          @runtime.make_object(properties, prototype, None, "Object", {}, true),
        )
      }
      StartObject => {
        let prototype = frame.env.get("[[ObjectPrototype]]") catch {
          _ => Value::Null
        }
        frame.stack.push(
          @runtime.make_object({}, prototype, None, "Object", {}, true),
        )
      }
      ObjectSetStatic(key) => {
        let value = frame.pop()
        match frame.peek() {
          Object(data) => data.bag.properties[key] = value
          _ =>
            raise @errors.InternalError(
              message="bytecode object accumulator was not an object",
            )
        }
      }
      ObjectSpread(loc) => {
        let source = frame.pop()
        interp.copy_object_spread_properties(frame.peek(), source, loc)
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
      ReadPropertyForAssign(prop, loc) => {
        let obj = frame.peek()
        frame.stack.push(interp.get_property(obj, prop, loc))
      }
      ReadComputedForAssign(loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        if obj is Null {
          raise @errors.TypeError(message="Cannot read properties of null")
        }
        if obj is Undefined {
          raise @errors.TypeError(message="Cannot read properties of undefined")
        }
        let prop_key = @runtime.to_property_key(key, interp=Some(interp))
        let current = interp.get_computed_property(obj, prop_key, loc)
        frame.stack.push(obj)
        frame.stack.push(prop_key)
        frame.stack.push(current)
      }
      DropPropertyAssignReference => {
        let current = frame.pop()
        let _ = frame.pop()
        frame.stack.push(current)
      }
      DropComputedAssignReference => {
        let current = frame.pop()
        let _ = frame.pop()
        let _ = frame.pop()
        frame.stack.push(current)
      }
      SetProperty(prop, loc) => {
        let value = frame.pop()
        let obj = frame.pop()
        frame.stack.push(
          interp.set_property(obj, prop, value, loc, strict=frame.ctx.strict),
        )
      }
      SetComputed(loc) => {
        let value = frame.pop()
        let key = frame.pop()
        let obj = frame.pop()
        frame.stack.push(
          interp.set_computed_property(
            obj,
            key,
            value,
            loc,
            strict=frame.ctx.strict,
          ),
        )
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
      CallSpread(loc) => {
        let args = frame.pop_dynamic_args()
        let callee = frame.pop()
        frame.stack.push(interp.call_value(callee, Value::Undefined, args, loc))
      }
      CallSpreadWithReceiver(loc) => {
        let args = frame.pop_dynamic_args()
        let callee = frame.pop()
        let receiver = frame.pop()
        frame.stack.push(interp.call_value(callee, receiver, args, loc))
      }
      Construct(arg_count, loc) => {
        let args = pop_args(frame, arg_count)
        let ctor = frame.pop()
        frame.stack.push(interp.construct_value(ctor, args, loc))
      }
      ConstructSpread(loc) => {
        let args = frame.pop_dynamic_args()
        let ctor = frame.pop()
        frame.stack.push(interp.construct_value(ctor, args, loc))
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
