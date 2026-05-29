///|
priv enum BytecodeInstr {
  LoadConst(Value)
  LoadUndefined
  LoadThis
  LoadNewTarget
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
  Dup
  BinaryOp(@ast.BinOp, @token.Loc)
  UnaryValueOp(@ast.UnaryOp, @token.Loc)
  TypeofName(String)
  DeleteName(String)
  DeleteProperty(String)
  DeleteComputed
  AppendTemplate(String)
  MakeTemplateObject(Array[String])
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
  StartForIn
  ForInNext(Int)
  EndForIn
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
  ToObjectLiteralPropertyKey
  ObjectSetComputed
  ObjectSpread(@token.Loc)
  ObjectSetProto
  MakeFunction(Int)
  MakeNamedFunction(Int, String)
  MakeMethodFunction(Int)
  MakeComputedMethodFunction(Int)
  MakeArrowFunction(Int)
  DeclareFunction(String, Int)
  GetProperty(String, @token.Loc)
  GetComputed(@token.Loc)
  ReadPropertyForAssign(String, @token.Loc)
  ReadComputedForAssign(@token.Loc)
  DropPropertyAssignReference
  DropComputedAssignReference
  SetProperty(String, @token.Loc)
  SetComputed(@token.Loc)
  AssignPattern(@ast.Pattern)
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
  break_contexts : Array[BreakPatchContext]
  label_contexts : Array[LabelPatchContext]
  pending_loop_labels : Array[String]
}

///|
priv struct LoopPatchContext {
  labels : Array[String]
  break_jumps : Array[Int]
  continue_jumps : Array[Int]
}

///|
priv struct LabelPatchContext {
  label : String
  break_jumps : Array[Int]
}

///|
priv struct SwitchPatchContext {
  break_jumps : Array[Int]
}

///|
priv enum BreakPatchContext {
  LoopBreakContext(LoopPatchContext)
  SwitchBreakContext(SwitchPatchContext)
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
    break_contexts: [],
    label_contexts: [],
    pending_loop_labels: [],
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
fn BytecodeBuilder::take_pending_loop_labels(
  self : BytecodeBuilder,
) -> Array[String] {
  let labels = self.pending_loop_labels.copy()
  while self.pending_loop_labels.length() > 0 {
    let _ = self.pending_loop_labels.pop()
  }
  labels
}

///|
fn BytecodeBuilder::restore_pending_loop_labels(
  self : BytecodeBuilder,
  labels : Array[String],
) -> Unit {
  for label in labels {
    self.pending_loop_labels.push(label)
  }
}

///|
fn BytecodeBuilder::push_loop_context(
  self : BytecodeBuilder,
  labels : Array[String],
) -> Unit {
  let ctx = { labels, break_jumps: [], continue_jumps: [] }
  self.loop_contexts.push(ctx)
  self.break_contexts.push(LoopBreakContext(ctx))
}

///|
fn BytecodeBuilder::pop_loop_context(
  self : BytecodeBuilder,
) -> LoopPatchContext raise Error {
  let break_ctx = self.break_contexts.pop()
  match (self.loop_contexts.pop(), break_ctx) {
    (Some(ctx), Some(LoopBreakContext(_))) => ctx
    (Some(ctx), _) => {
      bytecode_unsupported("loop context")
      ctx
    }
    (None, _) => {
      bytecode_unsupported("loop context")
      { labels: [], break_jumps: [], continue_jumps: [] }
    }
  }
}

///|
fn BytecodeBuilder::push_switch_context(self : BytecodeBuilder) -> Unit {
  self.break_contexts.push(SwitchBreakContext({ break_jumps: [] }))
}

///|
fn BytecodeBuilder::pop_switch_context(
  self : BytecodeBuilder,
) -> SwitchPatchContext raise Error {
  match self.break_contexts.pop() {
    Some(SwitchBreakContext(ctx)) => ctx
    _ => {
      bytecode_unsupported("switch context")
      { break_jumps: [] }
    }
  }
}

///|
fn BytecodeBuilder::current_break_context(
  self : BytecodeBuilder,
  unsupported_kind : String,
) -> BreakPatchContext raise Error {
  if self.break_contexts.length() == 0 {
    bytecode_unsupported(unsupported_kind)
  }
  self.break_contexts[self.break_contexts.length() - 1]
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
fn BytecodeBuilder::find_label_context(
  self : BytecodeBuilder,
  label : String,
) -> LabelPatchContext? {
  for i = self.label_contexts.length() - 1; i >= 0; i = i - 1 {
    let ctx = self.label_contexts[i]
    if ctx.label == label {
      return Some(ctx)
    }
  }
  None
}

///|
fn BytecodeBuilder::find_labeled_loop_context(
  self : BytecodeBuilder,
  label : String,
) -> LoopPatchContext? {
  for i = self.loop_contexts.length() - 1; i >= 0; i = i - 1 {
    let ctx = self.loop_contexts[i]
    if string_array_contains(ctx.labels, label) {
      return Some(ctx)
    }
  }
  None
}

///|
fn BytecodeBuilder::emit_loop_break(
  self : BytecodeBuilder,
  label : String?,
) -> Unit raise Error {
  match label {
    Some(target) => {
      match self.find_label_context(target) {
        Some(ctx) => {
          let jump = self.emit(Jump(-1))
          ctx.break_jumps.push(jump)
          return
        }
        None => ()
      }
      match self.find_labeled_loop_context(target) {
        Some(ctx) => {
          let jump = self.emit(Jump(-1))
          ctx.break_jumps.push(jump)
        }
        None => bytecode_unsupported("labeled break statement")
      }
    }
    None => {
      let jump = self.emit(Jump(-1))
      match self.current_break_context("break statement") {
        LoopBreakContext(ctx) => ctx.break_jumps.push(jump)
        SwitchBreakContext(ctx) => ctx.break_jumps.push(jump)
      }
    }
  }
}

///|
fn BytecodeBuilder::emit_loop_continue(
  self : BytecodeBuilder,
  label : String?,
) -> Unit raise Error {
  match label {
    Some(target) =>
      match self.find_labeled_loop_context(target) {
        Some(ctx) => {
          let jump = self.emit(Jump(-1))
          ctx.continue_jumps.push(jump)
        }
        None => bytecode_unsupported("labeled continue statement")
      }
    None => {
      let ctx = self.current_loop_context("continue statement")
      let jump = self.emit(Jump(-1))
      ctx.continue_jumps.push(jump)
    }
  }
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
    ForInStmt(Some(LetKind), _, _, _, _)
    | ForInStmt(Some(ConstKind), _, _, _, _) => true
    ForInStmt(_, _, _, body, _) => stmt_has_lexical_decl(body)
    SwitchStmt(_, cases, _) => switch_cases_have_lexical_decl(cases)
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
fn switch_cases_have_lexical_decl(cases : Array[@ast.SwitchCase]) -> Bool {
  for case in cases {
    if stmts_have_lexical_decl(case.body) {
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
    FuncExpr(None, _, _, _)
    | FuncExprExt(None, _, _, _, _)
    | ArrowFunc(_, _, _)
    | ArrowFuncExt(_, _, _, _) => true
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
    ForInStmt(_, _, _, body, _) => stmt_has_function_decl(body)
    SwitchStmt(_, cases, _) => switch_cases_have_function_decl(cases)
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
fn switch_cases_have_function_decl(cases : Array[@ast.SwitchCase]) -> Bool {
  for case in cases {
    if stmts_have_function_decl(case.body) {
      return true
    }
  }
  false
}

///|
fn stmt_has_destructure_decl(stmt : @ast.Stmt) -> Bool {
  match stmt {
    DestructureDecl(_, _, _, _) => true
    StmtList(stmts, _) | Block(stmts, _) => stmts_have_destructure_decl(stmts)
    IfStmt(_, then_branch, else_branch, _) => {
      let else_has = match else_branch {
        Some(stmt) => stmt_has_destructure_decl(stmt)
        None => false
      }
      stmt_has_destructure_decl(then_branch) || else_has
    }
    WhileStmt(_, body, _) | DoWhileStmt(body, _, _) =>
      stmt_has_destructure_decl(body)
    ForStmt(init, _, _, body, _) => {
      let init_has = match init {
        Some(stmt) => stmt_has_destructure_decl(stmt)
        None => false
      }
      init_has || stmt_has_destructure_decl(body)
    }
    ForInStmt(_, _, _, body, _) => stmt_has_destructure_decl(body)
    SwitchStmt(_, cases, _) => switch_cases_have_destructure_decl(cases)
    LabeledStmt(_, body, _) => stmt_has_destructure_decl(body)
    _ => false
  }
}

///|
fn stmts_have_destructure_decl(stmts : Array[@ast.Stmt]) -> Bool {
  for stmt in stmts {
    if stmt_has_destructure_decl(stmt) {
      return true
    }
  }
  false
}

///|
fn switch_cases_have_destructure_decl(cases : Array[@ast.SwitchCase]) -> Bool {
  for case in cases {
    if stmts_have_destructure_decl(case.body) {
      return true
    }
  }
  false
}

///|
fn stmt_is_iteration_label_target(stmt : @ast.Stmt) -> Bool {
  match stmt {
    WhileStmt(_, _, _)
    | DoWhileStmt(_, _, _)
    | ForStmt(_, _, _, _, _)
    | ForInStmt(_, _, _, _, _)
    | ForOfStmt(_, _, _, _, _)
    | ForInStmtPat(_, _, _, _, _)
    | ForOfStmtPat(_, _, _, _, _)
    | ForInExpr(_, _, _, _)
    | ForOfExpr(_, _, _, _) => true
    LabeledStmt(_, body, _) => stmt_is_iteration_label_target(body)
    _ => false
  }
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
    DestructureDecl(VarKind, pattern, _, _) =>
      collect_current_var_names_from_pattern(pattern, out)
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
    ForInStmt(Some(VarKind), name, _, body, _) => {
      out.push(name)
      collect_current_var_names_from_stmt(body, out)
    }
    ForInStmt(_, _, _, body, _) =>
      collect_current_var_names_from_stmt(body, out)
    SwitchStmt(_, cases, _) =>
      for case in cases {
        collect_current_var_names_from_stmts(case.body, out)
      }
    LabeledStmt(_, body, _) => collect_current_var_names_from_stmt(body, out)
    _ => ()
  }
}

///|
fn collect_current_var_names_from_pattern(
  pattern : @ast.Pattern,
  out : Array[String],
) -> Unit {
  match pattern {
    IdentPat(name) => out.push(name)
    ArrayPat(elements, rest) => {
      for element in elements {
        match element {
          Some(pat) => collect_current_var_names_from_pattern(pat, out)
          None => ()
        }
      }
      match rest {
        Some(pat) => collect_current_var_names_from_pattern(pat, out)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        collect_current_var_names_from_pattern(prop.value, out)
      }
      match rest {
        Some(pat) => collect_current_var_names_from_pattern(pat, out)
        None => ()
      }
    }
    DefaultPat(inner, _) => collect_current_var_names_from_pattern(inner, out)
    AssignTarget(_) => ()
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
    DestructureDecl(_, pattern, init, _) => {
      collect_nested_function_refs_from_pattern(pattern, refs)
      collect_nested_function_refs_from_expr(init, refs)
    }
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
    ForInStmt(_, _, obj_expr, body, _) => {
      collect_nested_function_refs_from_expr(obj_expr, refs)
      collect_nested_function_refs_from_stmt(body, refs)
    }
    SwitchStmt(discriminant, cases, _) => {
      collect_nested_function_refs_from_expr(discriminant, refs)
      for case in cases {
        match case.condition {
          Some(expr) => collect_nested_function_refs_from_expr(expr, refs)
          None => ()
        }
        collect_nested_function_refs_from_stmts(case.body, refs)
      }
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
    FuncExpr(_, _, body, _)
    | FuncExprExt(_, _, _, body, _)
    | ArrowFunc(_, body, _)
    | ArrowFuncExt(_, _, body, _) => collect_name_refs_from_stmts(body, refs)
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
    DestructureAssign(pattern, value, _) => {
      collect_nested_function_refs_from_pattern(pattern, refs)
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
    TaggedTemplate(tag, _, exprs, _) => {
      collect_nested_function_refs_from_expr(tag, refs)
      for expr in exprs {
        collect_nested_function_refs_from_expr(expr, refs)
      }
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
fn collect_nested_function_refs_from_pattern(
  pattern : @ast.Pattern,
  refs : Map[String, Bool],
) -> Unit {
  match pattern {
    IdentPat(_) => ()
    ArrayPat(elements, rest) => {
      for element in elements {
        match element {
          Some(pat) => collect_nested_function_refs_from_pattern(pat, refs)
          None => ()
        }
      }
      match rest {
        Some(pat) => collect_nested_function_refs_from_pattern(pat, refs)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        match prop.computed_key {
          Some(expr) => collect_nested_function_refs_from_expr(expr, refs)
          None => ()
        }
        match prop.default_val {
          Some(expr) => collect_nested_function_refs_from_expr(expr, refs)
          None => ()
        }
        collect_nested_function_refs_from_pattern(prop.value, refs)
      }
      match rest {
        Some(pat) => collect_nested_function_refs_from_pattern(pat, refs)
        None => ()
      }
    }
    DefaultPat(inner, expr) => {
      collect_nested_function_refs_from_pattern(inner, refs)
      collect_nested_function_refs_from_expr(expr, refs)
    }
    AssignTarget(expr) => collect_nested_function_refs_from_expr(expr, refs)
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
    DestructureDecl(_, pattern, init, _) => {
      collect_name_refs_from_binding_pattern_exprs(pattern, refs)
      collect_name_refs_from_expr(init, refs)
    }
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
    ForInStmt(None, name, obj_expr, body, _) => {
      refs[name] = true
      collect_name_refs_from_expr(obj_expr, refs)
      collect_name_refs_from_stmt(body, refs)
    }
    ForInStmt(Some(_), _, obj_expr, body, _) => {
      collect_name_refs_from_expr(obj_expr, refs)
      collect_name_refs_from_stmt(body, refs)
    }
    SwitchStmt(discriminant, cases, _) => {
      collect_name_refs_from_expr(discriminant, refs)
      for case in cases {
        match case.condition {
          Some(expr) => collect_name_refs_from_expr(expr, refs)
          None => ()
        }
        collect_name_refs_from_stmts(case.body, refs)
      }
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
    DestructureAssign(pattern, value, _) => {
      collect_name_refs_from_pattern(pattern, refs)
      collect_name_refs_from_expr(value, refs)
    }
    UpdateExpr(_, operand, _, _) => collect_name_refs_from_expr(operand, refs)
    FuncExpr(_, _, body, _)
    | FuncExprExt(_, _, _, body, _)
    | ArrowFunc(_, body, _)
    | ArrowFuncExt(_, _, body, _) => collect_name_refs_from_stmts(body, refs)
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
    TaggedTemplate(tag, _, exprs, _) => {
      collect_name_refs_from_expr(tag, refs)
      for expr in exprs {
        collect_name_refs_from_expr(expr, refs)
      }
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
fn collect_name_refs_from_pattern(
  pattern : @ast.Pattern,
  refs : Map[String, Bool],
) -> Unit {
  match pattern {
    IdentPat(name) => refs[name] = true
    ArrayPat(elements, rest) => {
      for element in elements {
        match element {
          Some(pat) => collect_name_refs_from_pattern(pat, refs)
          None => ()
        }
      }
      match rest {
        Some(pat) => collect_name_refs_from_pattern(pat, refs)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        match prop.computed_key {
          Some(expr) => collect_name_refs_from_expr(expr, refs)
          None => ()
        }
        match prop.default_val {
          Some(expr) => collect_name_refs_from_expr(expr, refs)
          None => ()
        }
        collect_name_refs_from_pattern(prop.value, refs)
      }
      match rest {
        Some(pat) => collect_name_refs_from_pattern(pat, refs)
        None => ()
      }
    }
    DefaultPat(inner, expr) => {
      collect_name_refs_from_pattern(inner, refs)
      collect_name_refs_from_expr(expr, refs)
    }
    AssignTarget(expr) => collect_name_refs_from_expr(expr, refs)
  }
}

///|
fn collect_name_refs_from_binding_pattern_exprs(
  pattern : @ast.Pattern,
  refs : Map[String, Bool],
) -> Unit {
  match pattern {
    IdentPat(_) => ()
    ArrayPat(elements, rest) => {
      for element in elements {
        match element {
          Some(pat) => collect_name_refs_from_binding_pattern_exprs(pat, refs)
          None => ()
        }
      }
      match rest {
        Some(pat) => collect_name_refs_from_binding_pattern_exprs(pat, refs)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        match prop.computed_key {
          Some(expr) => collect_name_refs_from_expr(expr, refs)
          None => ()
        }
        match prop.default_val {
          Some(expr) => collect_name_refs_from_expr(expr, refs)
          None => ()
        }
        collect_name_refs_from_binding_pattern_exprs(prop.value, refs)
      }
      match rest {
        Some(pat) => collect_name_refs_from_binding_pattern_exprs(pat, refs)
        None => ()
      }
    }
    DefaultPat(inner, expr) => {
      collect_name_refs_from_binding_pattern_exprs(inner, refs)
      collect_name_refs_from_expr(expr, refs)
    }
    AssignTarget(expr) => collect_name_refs_from_expr(expr, refs)
  }
}

///|
fn bytecode_body_references_arguments(body : Array[@ast.Stmt]) -> Bool {
  let refs : Map[String, Bool] = {}
  collect_name_refs_from_stmts(body, refs)
  refs.contains("arguments")
}

///|
fn bytecode_body_contains_destructure_assign(body : Array[@ast.Stmt]) -> Bool {
  for stmt in body {
    if bytecode_stmt_contains_destructure_assign(stmt) {
      return true
    }
  }
  false
}

///|
fn bytecode_stmt_contains_destructure_assign(stmt : @ast.Stmt) -> Bool {
  match stmt {
    DestructureDecl(_, _, _, _) => true
    VarDecl(_, _, Some(expr), _)
    | ExprStmt(expr, _)
    | ReturnStmt(Some(expr), _)
    | ThrowStmt(expr, _) => bytecode_expr_contains_destructure_assign(expr)
    StmtList(stmts, _) | Block(stmts, _) =>
      bytecode_body_contains_destructure_assign(stmts)
    IfStmt(cond, then_branch, else_branch, _) => {
      if bytecode_expr_contains_destructure_assign(cond) {
        return true
      }
      if bytecode_stmt_contains_destructure_assign(then_branch) {
        return true
      }
      match else_branch {
        Some(stmt) => bytecode_stmt_contains_destructure_assign(stmt)
        None => false
      }
    }
    WhileStmt(cond, body, _) =>
      bytecode_expr_contains_destructure_assign(cond) ||
      bytecode_stmt_contains_destructure_assign(body)
    DoWhileStmt(body, cond, _) =>
      bytecode_stmt_contains_destructure_assign(body) ||
      bytecode_expr_contains_destructure_assign(cond)
    ForStmt(init, cond, update, body, _) => {
      match init {
        Some(stmt) =>
          if bytecode_stmt_contains_destructure_assign(stmt) {
            return true
          }
        None => ()
      }
      match cond {
        Some(expr) =>
          if bytecode_expr_contains_destructure_assign(expr) {
            return true
          }
        None => ()
      }
      match update {
        Some(expr) =>
          if bytecode_expr_contains_destructure_assign(expr) {
            return true
          }
        None => ()
      }
      bytecode_stmt_contains_destructure_assign(body)
    }
    ForInStmt(_, _, obj_expr, body, _) =>
      bytecode_expr_contains_destructure_assign(obj_expr) ||
      bytecode_stmt_contains_destructure_assign(body)
    SwitchStmt(discriminant, cases, _) => {
      if bytecode_expr_contains_destructure_assign(discriminant) {
        return true
      }
      for case in cases {
        match case.condition {
          Some(expr) =>
            if bytecode_expr_contains_destructure_assign(expr) {
              return true
            }
          None => ()
        }
        if bytecode_body_contains_destructure_assign(case.body) {
          return true
        }
      }
      false
    }
    LabeledStmt(_, body, _) => bytecode_stmt_contains_destructure_assign(body)
    _ => false
  }
}

///|
fn bytecode_expr_contains_destructure_assign(expr : @ast.Expr) -> Bool {
  match expr {
    DestructureAssign(_, _, _) => true
    Unary(_, operand, _) | Grouping(operand, _) | SpreadExpr(operand, _) =>
      bytecode_expr_contains_destructure_assign(operand)
    Binary(_, left, right, _) | Comma(left, right, _) =>
      bytecode_expr_contains_destructure_assign(left) ||
      bytecode_expr_contains_destructure_assign(right)
    Ternary(cond, then_expr, else_expr, _) =>
      bytecode_expr_contains_destructure_assign(cond) ||
      bytecode_expr_contains_destructure_assign(then_expr) ||
      bytecode_expr_contains_destructure_assign(else_expr)
    Assign(_, value, _) => bytecode_expr_contains_destructure_assign(value)
    Call(callee, args, _)
    | OptionalCall(callee, args, _)
    | NewExpr(callee, args, _) => {
      if bytecode_expr_contains_destructure_assign(callee) {
        return true
      }
      for arg in args {
        if bytecode_expr_contains_destructure_assign(arg) {
          return true
        }
      }
      false
    }
    Member(obj, _, _) | OptionalMember(obj, _, _) =>
      bytecode_expr_contains_destructure_assign(obj)
    ComputedMember(obj, key, _) | OptionalComputedMember(obj, key, _) =>
      bytecode_expr_contains_destructure_assign(obj) ||
      bytecode_expr_contains_destructure_assign(key)
    MemberAssign(obj, _, value, _) =>
      bytecode_expr_contains_destructure_assign(obj) ||
      bytecode_expr_contains_destructure_assign(value)
    ComputedAssign(obj, key, value, _) =>
      bytecode_expr_contains_destructure_assign(obj) ||
      bytecode_expr_contains_destructure_assign(key) ||
      bytecode_expr_contains_destructure_assign(value)
    CompoundAssign(_, target, value, _) =>
      bytecode_expr_contains_destructure_assign(target) ||
      bytecode_expr_contains_destructure_assign(value)
    UpdateExpr(_, operand, _, _) =>
      bytecode_expr_contains_destructure_assign(operand)
    FuncExpr(_, _, body, _)
    | FuncExprExt(_, _, _, body, _)
    | ArrowFunc(_, body, _)
    | ArrowFuncExt(_, _, body, _) =>
      bytecode_body_contains_destructure_assign(body)
    ArrayLit(elements, _) => {
      for element in elements {
        if bytecode_expr_contains_destructure_assign(element) {
          return true
        }
      }
      false
    }
    ObjectLit(props, _) => bytecode_props_contain_destructure_assign(props)
    TemplateLit(_, exprs, _) => {
      for expr in exprs {
        if bytecode_expr_contains_destructure_assign(expr) {
          return true
        }
      }
      false
    }
    TaggedTemplate(tag, _, exprs, _) => {
      if bytecode_expr_contains_destructure_assign(tag) {
        return true
      }
      for expr in exprs {
        if bytecode_expr_contains_destructure_assign(expr) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn bytecode_props_contain_destructure_assign(
  props : Array[@ast.Property],
) -> Bool {
  for prop in props {
    match prop.kind {
      Spread =>
        if bytecode_expr_contains_destructure_assign(prop.key) {
          return true
        }
      _ => {
        if prop.computed && bytecode_expr_contains_destructure_assign(prop.key) {
          return true
        }
        if bytecode_expr_contains_destructure_assign(prop.value) {
          return true
        }
      }
    }
  }
  false
}

///|
fn plan_bytecode_locals(
  params : Array[String],
  body : Array[@ast.Stmt],
  use_local_slots~ : Bool,
) -> BytecodeLocalPlan {
  let names : Array[String] = []
  let indices : Map[String, Int] = {}
  if use_local_slots &&
    !bytecode_body_references_arguments(body) &&
    !bytecode_body_contains_destructure_assign(body) {
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
fn BytecodeBuilder::compile_switch(
  self : BytecodeBuilder,
  discriminant : @ast.Expr,
  cases : Array[@ast.SwitchCase],
) -> Unit raise Error {
  if switch_cases_have_lexical_decl(cases) {
    bytecode_unsupported("switch lexical declaration")
  }
  if switch_cases_have_function_decl(cases) {
    bytecode_unsupported("control-flow function declaration")
  }
  if switch_cases_have_destructure_decl(cases) {
    bytecode_unsupported("destructuring declaration context")
  }
  self.emit_undefined_completion()
  self.compile_expr(discriminant)
  let case_jumps = Array::make(cases.length(), -1)
  let mut default_idx = -1
  for i, case in cases {
    match case.condition {
      Some(cond) => {
        let _ = self.emit(Dup)
        self.compile_expr(cond)
        let _ = self.emit(BinaryOp(EqEqEq, @token.Loc::default()))
        let no_match = self.emit(JumpIfFalse(-1))
        let _ = self.emit(Pop)
        case_jumps[i] = self.emit(Jump(-1))
        self.patch(no_match, JumpIfFalse(self.code.length()))
      }
      None => default_idx = i
    }
  }
  let _ = self.emit(Pop)
  let no_match_jump = self.emit(Jump(-1))
  self.push_switch_context()
  let case_starts = Array::make(cases.length(), 0)
  for i, case in cases {
    case_starts[i] = self.code.length()
    for child in case.body {
      self.compile_stmt(child)
    }
  }
  let switch_ctx = self.pop_switch_context()
  let exit_pos = self.code.length()
  for i, jump in case_jumps {
    if jump >= 0 {
      self.patch(jump, Jump(case_starts[i]))
    }
  }
  if default_idx >= 0 {
    self.patch(no_match_jump, Jump(case_starts[default_idx]))
  } else {
    self.patch(no_match_jump, Jump(exit_pos))
  }
  self.patch_loop_jumps(switch_ctx.break_jumps, exit_pos)
}

///|
fn BytecodeBuilder::compile_for_in_identifier(
  self : BytecodeBuilder,
  var_kind : @ast.VarKind?,
  name : String,
  obj_expr : @ast.Expr,
  body : @ast.Stmt,
) -> Unit raise Error {
  match var_kind {
    Some(VarKind) => bytecode_unsupported("for-in var declaration")
    Some(LetKind) | Some(ConstKind) =>
      bytecode_unsupported("for-in lexical declaration")
    None => ()
  }
  if stmt_has_function_decl(body) {
    bytecode_unsupported("control-flow function declaration")
  }
  if stmt_has_destructure_decl(body) {
    bytecode_unsupported("destructuring declaration context")
  }
  self.emit_undefined_completion()
  self.compile_expr(obj_expr)
  let _ = self.emit(StartForIn)
  let loop_pos = self.code.length()
  let done_jump = self.emit(ForInNext(-1))
  self.compile_identifier_store(name)
  let _ = self.emit(Pop)
  let labels = self.take_pending_loop_labels()
  self.push_loop_context(labels)
  self.compile_stmt(body)
  let loop_ctx = self.pop_loop_context()
  self.restore_pending_loop_labels(labels)
  let continue_pos = self.code.length()
  self.patch_loop_jumps(loop_ctx.continue_jumps, continue_pos)
  let _ = self.emit(Jump(loop_pos))
  let cleanup_pos = self.code.length()
  let _ = self.emit(EndForIn)
  let exit_pos = self.code.length()
  self.patch(done_jump, ForInNext(exit_pos))
  self.patch_loop_jumps(loop_ctx.break_jumps, cleanup_pos)
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
    DestructureDecl(VarKind, pattern, init, _) => {
      bytecode_validate_destructure_assignment_pattern(pattern)
      self.compile_expr(init)
      let _ = self.emit(AssignPattern(pattern))
      let _ = self.emit(Pop)
      if declaration_updates_completion {
        self.emit_undefined_completion()
      }
    }
    DestructureDecl(_, _, _, _) =>
      bytecode_unsupported("destructuring declaration kind")
    StmtList(stmts, _) => {
      if stmts_have_destructure_decl(stmts) {
        bytecode_unsupported("destructuring declaration context")
      }
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
      if stmts_have_destructure_decl(stmts) {
        bytecode_unsupported("destructuring declaration context")
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
      if stmt_has_destructure_decl(then_branch) {
        bytecode_unsupported("destructuring declaration context")
      }
      match else_branch {
        Some(stmt) =>
          if stmt_has_destructure_decl(stmt) {
            bytecode_unsupported("destructuring declaration context")
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
      if stmt_has_destructure_decl(body) {
        bytecode_unsupported("destructuring declaration context")
      }
      self.emit_undefined_completion()
      let cond_pos = self.code.length()
      self.compile_expr(cond)
      let exit_jump = self.emit(JumpIfFalse(-1))
      let labels = self.take_pending_loop_labels()
      self.push_loop_context(labels)
      self.compile_stmt(body)
      let loop_ctx = self.pop_loop_context()
      self.restore_pending_loop_labels(labels)
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
      if stmt_has_destructure_decl(body) {
        bytecode_unsupported("destructuring declaration context")
      }
      self.emit_undefined_completion()
      let body_pos = self.code.length()
      let labels = self.take_pending_loop_labels()
      self.push_loop_context(labels)
      self.compile_stmt(body)
      let loop_ctx = self.pop_loop_context()
      self.restore_pending_loop_labels(labels)
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
      if stmt_has_destructure_decl(body) {
        bytecode_unsupported("destructuring declaration context")
      }
      match init {
        Some(stmt) => {
          if stmt_has_lexical_decl(stmt) {
            bytecode_unsupported("for lexical initializer")
          }
          if stmt_has_destructure_decl(stmt) {
            bytecode_unsupported("destructuring declaration context")
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
      let labels = self.take_pending_loop_labels()
      self.push_loop_context(labels)
      self.compile_stmt(body)
      let loop_ctx = self.pop_loop_context()
      self.restore_pending_loop_labels(labels)
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
    ForInStmt(var_kind, name, obj_expr, body, _) =>
      self.compile_for_in_identifier(var_kind, name, obj_expr, body)
    SwitchStmt(discriminant, cases, _) =>
      self.compile_switch(discriminant, cases)
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
    LabeledStmt(label, body, _) => {
      if stmt_has_function_decl(body) {
        bytecode_unsupported("control-flow function declaration")
      }
      if stmt_has_destructure_decl(body) {
        bytecode_unsupported("destructuring declaration context")
      }
      if stmt_is_iteration_label_target(body) {
        self.pending_loop_labels.push(label)
        self.compile_stmt(body, declaration_updates_completion~)
        let _ = self.pending_loop_labels.pop()
      } else {
        self.label_contexts.push({ label, break_jumps: [] })
        self.compile_stmt(body, declaration_updates_completion~)
        let label_ctx = match self.label_contexts.pop() {
          Some(ctx) => ctx
          None => {
            bytecode_unsupported("label context")
            { label, break_jumps: [] }
          }
        }
        self.patch_loop_jumps(label_ctx.break_jumps, self.code.length())
      }
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
fn bytecode_object_lit_uses_incremental(props : Array[@ast.Property]) -> Bool {
  for prop in props {
    match prop.kind {
      Spread => return true
      Init =>
        if prop.is_method {
          return true
        } else if prop.computed {
          return true
        } else {
          match bytecode_static_object_key(prop.key) {
            Some(key) => if key == "__proto__" { return true }
            None => ()
          }
        }
      Get | Set => ()
    }
  }
  false
}

///|
fn bytecode_method_body_references_name(
  name : String,
  body : Array[@ast.Stmt],
) -> Bool {
  let refs : Map[String, Bool] = {}
  collect_name_refs_from_stmts(body, refs)
  refs.contains(name)
}

///|
fn BytecodeBuilder::compile_object_method(
  self : BytecodeBuilder,
  prop : @ast.Property,
  computed_key_on_stack? : Bool = false,
) -> Unit raise Error {
  let fn_idx = match prop.value {
    FuncExpr(Some(name), params, body, _) => {
      if bytecode_method_body_references_name(name, body) {
        bytecode_unsupported("object literal method self reference")
      }
      self.add_function(Some(name), params, body)
    }
    FuncExpr(None, params, body, _) => self.add_function(None, params, body)
    FuncExprExt(Some(name), params, rest_param, body, _) => {
      if bytecode_method_body_references_name(name, body) {
        bytecode_unsupported("object literal method self reference")
      }
      let simple_params = simple_ext_param_names(params, rest_param)
      self.add_function(Some(name), simple_params, body)
    }
    FuncExprExt(None, params, rest_param, body, _) => {
      let simple_params = simple_ext_param_names(params, rest_param)
      self.add_function(None, simple_params, body)
    }
    _ => {
      bytecode_unsupported("object literal method property")
      0
    }
  }
  if computed_key_on_stack {
    let _ = self.emit(MakeComputedMethodFunction(fn_idx))
  } else {
    let _ = self.emit(MakeMethodFunction(fn_idx))
  }
}

///|
fn BytecodeBuilder::compile_object_lit(
  self : BytecodeBuilder,
  props : Array[@ast.Property],
  loc : @token.Loc,
) -> Unit raise Error {
  if bytecode_object_lit_uses_incremental(props) {
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
      if prop.is_method {
        if prop.computed {
          self.compile_expr(prop.key)
          let _ = self.emit(ToObjectLiteralPropertyKey)
          self.compile_object_method(prop, computed_key_on_stack=true)
          let _ = self.emit(ObjectSetComputed)
          continue
        }
        let key = match bytecode_static_object_key(prop.key) {
          Some(key) => key
          None => {
            bytecode_unsupported("object literal property key")
            ""
          }
        }
        if key == "__proto__" {
          bytecode_unsupported("object literal __proto__ method property")
        }
        self.compile_object_method(prop)
        let _ = self.emit(ObjectSetStatic(key))
        continue
      }
      if prop.computed {
        self.compile_expr(prop.key)
        let _ = self.emit(ToObjectLiteralPropertyKey)
        self.compile_expr(prop.value)
        let _ = self.emit(ObjectSetComputed)
        continue
      }
      let key = match bytecode_static_object_key(prop.key) {
        Some(key) => key
        None => {
          bytecode_unsupported("object literal property key")
          ""
        }
      }
      self.compile_expr(prop.value)
      if key == "__proto__" {
        let _ = self.emit(ObjectSetProto)
      } else {
        let _ = self.emit(SetFunctionName(key))
        let _ = self.emit(ObjectSetStatic(key))
      }
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
      self.compile_expr(prop.value)
      let _ = self.emit(SetFunctionName(key))
      keys.push(key)
    }
    let _ = self.emit(MakeObject(keys))
  }
}

///|
fn bytecode_validate_destructure_assignment_pattern(
  pattern : @ast.Pattern,
) -> Unit raise Error {
  match pattern {
    IdentPat(_) => ()
    ArrayPat(elements, rest) => {
      for element in elements {
        match element {
          Some(pat) => bytecode_validate_destructure_assignment_pattern(pat)
          None => ()
        }
      }
      match rest {
        Some(pat) => bytecode_validate_destructure_assignment_pattern(pat)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        match (prop.default_val, prop.computed_key) {
          (None, None) => ()
          _ => bytecode_unsupported("destructuring assignment pattern")
        }
        bytecode_validate_destructure_assignment_pattern(prop.value)
      }
      match rest {
        Some(pat) => bytecode_validate_destructure_assignment_pattern(pat)
        None => ()
      }
    }
    DefaultPat(_, _) | AssignTarget(_) =>
      bytecode_unsupported("destructuring assignment pattern")
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
    NewTargetExpr(_) => {
      let _ = self.emit(LoadNewTarget)
    }
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
    TaggedTemplate(Member(obj, prop, member_loc), strings, exprs, loc) => {
      self.compile_expr(obj)
      let _ = self.emit(PreparePropertyCall(prop, member_loc))
      let _ = self.emit(MakeTemplateObject(strings))
      for expr in exprs {
        self.compile_expr(expr)
      }
      let _ = self.emit(CallWithReceiver(1 + exprs.length(), loc))
    }
    TaggedTemplate(ComputedMember(obj, key, member_loc), strings, exprs, loc) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      let _ = self.emit(PrepareComputedCall(member_loc))
      let _ = self.emit(MakeTemplateObject(strings))
      for expr in exprs {
        self.compile_expr(expr)
      }
      let _ = self.emit(CallWithReceiver(1 + exprs.length(), loc))
    }
    TaggedTemplate(OptionalMember(_, _, _), _, _, _)
    | TaggedTemplate(OptionalComputedMember(_, _, _), _, _, _) =>
      bytecode_unsupported("tagged template optional member call")
    TaggedTemplate(tag, strings, exprs, loc) => {
      self.compile_expr(tag)
      let _ = self.emit(MakeTemplateObject(strings))
      for expr in exprs {
        self.compile_expr(expr)
      }
      let _ = self.emit(Call(1 + exprs.length(), loc))
    }
    RegexLit(pattern, flags, _) => {
      let _ = self.emit(MakeRegExp(pattern, flags))
    }
    DestructureAssign(pattern, value, _) => {
      bytecode_validate_destructure_assignment_pattern(pattern)
      self.compile_expr(value)
      let _ = self.emit(AssignPattern(pattern))
    }
    Assign(name, value, _) => {
      self.compile_expr(value)
      if bytecode_is_anonymous_function_definition(value) {
        let _ = self.emit(SetFunctionName(name))
      }
      self.compile_identifier_store(name)
    }
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
    FuncExpr(Some(name), params, body, _) => {
      let fn_idx = self.add_function(Some(name), params, body)
      let _ = self.emit(MakeNamedFunction(fn_idx, name))
    }
    FuncExpr(None, params, body, _) => {
      let fn_idx = self.add_function(None, params, body)
      let _ = self.emit(MakeFunction(fn_idx))
    }
    FuncExprExt(Some(name), params, rest_param, body, _) => {
      let simple_params = simple_ext_param_names(params, rest_param)
      let fn_idx = self.add_function(Some(name), simple_params, body)
      let _ = self.emit(MakeNamedFunction(fn_idx, name))
    }
    FuncExprExt(None, params, rest_param, body, _) => {
      let simple_params = simple_ext_param_names(params, rest_param)
      let fn_idx = self.add_function(None, simple_params, body)
      let _ = self.emit(MakeFunction(fn_idx))
    }
    ArrowFunc(params, body, _) => {
      let fn_idx = self.add_function(None, params, body)
      let _ = self.emit(MakeArrowFunction(fn_idx))
    }
    ArrowFuncExt(params, rest_param, body, _) => {
      let simple_params = simple_ext_param_names(params, rest_param)
      let fn_idx = self.add_function(None, simple_params, body)
      let _ = self.emit(MakeArrowFunction(fn_idx))
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
priv struct BytecodeForInState {
  keys : Array[String]
  mut index : Int
}

///|
priv struct BytecodeFrame {
  func_def : BytecodeFunction
  stack : Array[Value]
  arg_lists : Array[Array[Value]]
  for_in_iters : Array[BytecodeForInState]
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
    for_in_iters: [],
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
fn make_named_bytecode_func(
  func_def : BytecodeFunction,
  closure : Environment,
  enclosing_ctx : ExecContext,
  name : String,
) -> Value raise Error {
  let self_name_env = Environment::new(parent=Some(closure))
  let func = make_bytecode_func(func_def, self_name_env, enclosing_ctx)
  self_name_env.def(name, func, LetBinding)
  func
}

///|
fn make_bytecode_method_func(
  func_def : BytecodeFunction,
  closure : Environment,
  enclosing_ctx : ExecContext,
  home_object : Value,
) -> Value raise Error {
  @runtime.validate_function_signature(
    enclosing_ctx.strict,
    None,
    func_def.params,
    func_def.source_body,
  )
  let strict = enclosing_ctx.strict || func_def.body_has_use_strict
  let method_env = Environment::new(parent=Some(closure))
  method_env.def_builtin("[[HomeObject]]", home_object)
  make_compiled_func(
    func_def.name,
    func_def.params,
    method_env,
    strict,
    CompiledBody(fn(interp, ctx, env) raise {
      match run_bytecode_function(interp, ctx, env, func_def) {
        BytecodeNormal(value) => Signal::Normal(value)
        BytecodeReturn(value) => Signal::ReturnSignal(value)
      }
    }),
    constructable=false,
  )
}

///|
fn make_bytecode_arrow_func(
  func_def : BytecodeFunction,
  closure : Environment,
  enclosing_ctx : ExecContext,
) -> Value raise Error {
  @runtime.validate_function_signature(
    enclosing_ctx.strict,
    None,
    func_def.params,
    func_def.source_body,
  )
  let strict = enclosing_ctx.strict || func_def.body_has_use_strict
  make_compiled_arrow_func(
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
      LoadNewTarget =>
        frame.stack.push(@runtime.eval_new_target_value(frame.env))
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
      Dup => frame.stack.push(frame.peek())
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
      MakeTemplateObject(strings) =>
        frame.stack.push(@runtime.make_tagged_template_object(strings))
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
      StartForIn => {
        let obj = frame.pop()
        frame.for_in_iters.push({
          keys: @runtime.collect_for_in_keys(obj, interp),
          index: 0,
        })
      }
      ForInNext(target) => {
        guard frame.for_in_iters.length() > 0 else {
          raise @errors.InternalError(
            message="bytecode for-in iterator underflow",
          )
        }
        let state = frame.for_in_iters[frame.for_in_iters.length() - 1]
        if state.index >= state.keys.length() {
          let _ = frame.for_in_iters.pop()
          frame.ip = target
        } else {
          let key = state.keys[state.index]
          state.index += 1
          frame.stack.push(Value::String_(key))
        }
      }
      EndForIn =>
        match frame.for_in_iters.pop() {
          Some(_) => ()
          None =>
            raise @errors.InternalError(
              message="bytecode for-in iterator underflow",
            )
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
      ToObjectLiteralPropertyKey => {
        let key = frame.pop()
        frame.stack.push(interp.to_object_literal_property_key(key))
      }
      ObjectSetComputed => {
        let value = frame.pop()
        let key = frame.pop()
        @runtime.apply_object_literal_data_property(frame.peek(), key, value)
      }
      ObjectSpread(loc) => {
        let source = frame.pop()
        interp.copy_object_spread_properties(frame.peek(), source, loc)
      }
      ObjectSetProto => {
        let value = frame.pop()
        @runtime.apply_object_literal_proto_property(frame.peek(), value)
      }
      MakeFunction(index) => {
        let child = frame.func_def.children[index]
        frame.stack.push(make_bytecode_func(child, frame.env, frame.ctx))
      }
      MakeNamedFunction(index, name) => {
        let child = frame.func_def.children[index]
        frame.stack.push(
          make_named_bytecode_func(child, frame.env, frame.ctx, name),
        )
      }
      MakeMethodFunction(index) => {
        let child = frame.func_def.children[index]
        let home_object = frame.peek()
        frame.stack.push(
          make_bytecode_method_func(child, frame.env, frame.ctx, home_object),
        )
      }
      MakeComputedMethodFunction(index) => {
        let child = frame.func_def.children[index]
        guard frame.stack.length() >= 2 else {
          raise @errors.InternalError(
            message="bytecode computed method missing home object",
          )
        }
        let home_object = frame.stack[frame.stack.length() - 2]
        frame.stack.push(
          make_bytecode_method_func(child, frame.env, frame.ctx, home_object),
        )
      }
      MakeArrowFunction(index) => {
        let child = frame.func_def.children[index]
        frame.stack.push(make_bytecode_arrow_func(child, frame.env, frame.ctx))
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
      AssignPattern(pattern) => {
        let value = frame.pop()
        frame.stack.push(
          interp.eval_destructure_assign(frame.ctx, pattern, value, frame.env),
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
