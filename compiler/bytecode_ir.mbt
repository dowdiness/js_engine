///|
using @runtime {type Binding}

///|
let empty_bytecode_env_slots : Array[Binding] = []

///|
priv enum BytecodeInstr {
  LoadConst(Value)
  LoadUndefined
  LoadThis
  LoadNewTarget
  LoadSuperProperty(String, @token.Loc)
  LoadSuperComputed(@token.Loc)
  LoadConsoleMember(String)
  LoadDirectEvalCallee
  LoadName(String)
  LoadAssignmentName(String)
  StoreName(String)
  LoadLocal(Int)
  StoreLocal(Int)
  LoadEnvSlot(Int)
  StoreEnvSlot(Int)
  DefineBinding(@ast.VarKind, String, Bool) // kind, name, initializer-present
  DefineLocal(Int, Bool) // slot, initializer-present
  DefineEnvSlot(Int, Bool) // slot, initializer-present
  SetCompletion
  SetCompletionValue(Value) // direct completion update for constants/empty statements
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
  UpdateEnvSlot(Int, @ast.UpdateOp, Bool) // slot, op, prefix
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
  ObjectSetStaticGetter(String)
  ObjectSetStaticSetter(String)
  ObjectSetComputedGetter
  ObjectSetComputedSetter
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
  SetForInProperty(String, @token.Loc)
  SetForInComputed(@token.Loc)
  AssignPattern(@ast.Pattern)
  PreparePropertyCall(String, @token.Loc)
  PrepareComputedCall(@token.Loc)
  PrepareSuperPropertyCall(String, @token.Loc)
  PrepareSuperComputedCall(@token.Loc)
  CallDirectEval(@token.Loc)
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
  rest_param : String?
  source_body : Array[@ast.Stmt]
  body_has_use_strict : Bool
  call_self_name : Bool
  // Direct eval can read `arguments` by string, so only skip arguments-object
  // setup when both direct references and eval references are absent.
  needs_arguments_object : Bool
  local_names : Array[String]
  env_slot_names : Array[String]
  // Var-declared names that are NOT local slots, in source order with duplicates
  // preserved — precomputed at lowering so the VM hoists them without re-walking
  // source_body on every call (issue #325). Equals, by construction,
  // collect_var_declared_names(source_body) filtered to names absent from
  // local_names; the VM's old runtime filter agreed with this exactly.
  env_var_hoist_names : Array[String]
  template_cache_key_prefix : String
  code : Array[BytecodeInstr]
  children : Array[BytecodeFunction]
}

///|
priv struct BytecodeBuilder {
  code : Array[BytecodeInstr]
  children : Array[BytecodeFunction]
  local_names : Array[String]
  local_indices : Map[String, Int]
  env_slot_names : Array[String]
  env_slot_indices : Map[String, Int]
  template_cache_key_prefix : String
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
  cleanup_for_in : Bool
}

///|
priv struct LabelPatchContext {
  label : String
  break_jumps : Array[Int]
  loop_depth : Int
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
  env_names : Array[String]
  env_indices : Map[String, Int]
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
  template_cache_key_prefix : String,
) -> BytecodeBuilder {
  {
    code: [],
    children: [],
    local_names: plan.names,
    local_indices: plan.indices,
    env_slot_names: plan.env_names,
    env_slot_indices: plan.env_indices,
    template_cache_key_prefix,
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
fn BytecodeBuilder::env_slot(self : BytecodeBuilder, name : String) -> Int? {
  self.env_slot_indices.get(name)
}

///|
fn BytecodeBuilder::emit_completion_value(
  self : BytecodeBuilder,
  value : Value,
) -> Unit {
  let _ = self.emit(SetCompletionValue(value))
}

///|
fn BytecodeBuilder::emit_undefined_completion(self : BytecodeBuilder) -> Unit {
  self.emit_completion_value(Value::Undefined)
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
  cleanup_for_in? : Bool = false,
) -> Unit {
  let ctx = { labels, break_jumps: [], continue_jumps: [], cleanup_for_in }
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
      { labels: [], break_jumps: [], continue_jumps: [], cleanup_for_in: false }
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
fn BytecodeBuilder::find_labeled_loop_context_index(
  self : BytecodeBuilder,
  label : String,
) -> Int? {
  for i = self.loop_contexts.length() - 1; i >= 0; i = i - 1 {
    let ctx = self.loop_contexts[i]
    if string_array_contains(ctx.labels, label) {
      return Some(i)
    }
  }
  None
}

///|
fn BytecodeBuilder::emit_for_in_cleanups_after_loop_index(
  self : BytecodeBuilder,
  loop_index : Int,
) -> Unit {
  for i = self.loop_contexts.length() - 1; i > loop_index; i = i - 1 {
    if self.loop_contexts[i].cleanup_for_in {
      let _ = self.emit(EndForIn)
    }
  }
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
          self.emit_for_in_cleanups_after_loop_index(ctx.loop_depth - 1)
          let jump = self.emit(Jump(-1))
          ctx.break_jumps.push(jump)
          return
        }
        None => ()
      }
      match self.find_labeled_loop_context_index(target) {
        Some(idx) => {
          let ctx = self.loop_contexts[idx]
          self.emit_for_in_cleanups_after_loop_index(idx)
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
      match self.find_labeled_loop_context_index(target) {
        Some(idx) => {
          let ctx = self.loop_contexts[idx]
          self.emit_for_in_cleanups_after_loop_index(idx)
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
