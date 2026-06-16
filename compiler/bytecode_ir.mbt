///|
using @runtime {type Binding}

///|
let empty_bytecode_env_slots : Array[Binding] = []

///|
pub const UNSUPPORTED_ARRAY_HOLE : String = "array hole expression"

///|
pub const UNSUPPORTED_ASYNC_ARROW_FUNCTION : String = "async arrow function"

///|
pub const UNSUPPORTED_ASYNC_FUNCTION_DECLARATION : String = "async function declaration"

///|
pub const UNSUPPORTED_ASYNC_FUNCTION_EXPRESSION : String = "async function expression"

///|
pub const UNSUPPORTED_ASYNC_GENERATOR_DECLARATION : String = "async generator declaration"

///|
pub const UNSUPPORTED_ASYNC_GENERATOR_EXPRESSION : String = "async generator expression"

///|
pub const UNSUPPORTED_AWAIT_EXPRESSION : String = "await expression"

///|
pub const UNSUPPORTED_BLOCK_FUNCTION_DECLARATION : String = "block function declaration"

///|
pub const UNSUPPORTED_BLOCK_LEXICAL_DECLARATION : String = "block lexical declaration"

///|
pub const UNSUPPORTED_BREAK_STATEMENT : String = "break statement"

///|
pub const UNSUPPORTED_CLASS_DECLARATION : String = "class declaration"

///|
pub const UNSUPPORTED_CLASS_EXPRESSION : String = "class expression"

///|
pub const UNSUPPORTED_COMPOUND_ASSIGNMENT_TARGET : String = "compound assignment target"

///|
pub const UNSUPPORTED_CONTINUE_STATEMENT : String = "continue statement"

///|
pub const UNSUPPORTED_CONTROL_FLOW_FUNCTION_DECLARATION : String = "control-flow function declaration"

///|
pub const UNSUPPORTED_DEFAULT_PARAMETER : String = "default parameter"

///|
pub const UNSUPPORTED_DELETE_NON_PROPERTY_OPERATOR : String = "delete non-property operator"

///|
pub const UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT : String = "destructuring declaration context"

///|
pub const UNSUPPORTED_DESTRUCTURING_DECLARATION_KIND : String = "destructuring declaration kind"

///|
pub const UNSUPPORTED_DESTRUCTURING_PARAMETER : String = "destructuring parameter"

///|
pub const UNSUPPORTED_DESTRUCTURING_PATTERN_COMPUTED_KEY : String = "destructuring pattern computed key"

///|
pub const UNSUPPORTED_DESTRUCTURING_PATTERN_DEFAULT : String = "destructuring pattern default"

///|
pub const UNSUPPORTED_DESTRUCTURING_PATTERN_MEMBER_TARGET : String = "destructuring pattern member target"

///|
pub const UNSUPPORTED_EXPORT_DECLARATION : String = "export declaration"

///|
pub const UNSUPPORTED_FOR_INITIALIZER : String = "for initializer"

///|
pub const UNSUPPORTED_FOR_IN_ASSIGNMENT_TARGET : String = "for-in assignment target"

///|
pub const UNSUPPORTED_FOR_IN_LEXICAL_DECLARATION : String = "for-in lexical declaration"

///|
pub const UNSUPPORTED_FOR_IN_VAR_DECLARATION : String = "for-in var declaration"

///|
pub const UNSUPPORTED_FOR_LEXICAL_INITIALIZER : String = "for lexical initializer"

///|
pub const UNSUPPORTED_FOR_OF_STATEMENT : String = "for-of statement"

///|
pub const UNSUPPORTED_GENERATOR_DECLARATION : String = "generator declaration"

///|
pub const UNSUPPORTED_GENERATOR_EXPRESSION : String = "generator expression"

///|
pub const UNSUPPORTED_IMPORT_DECLARATION : String = "import declaration"

///|
pub const UNSUPPORTED_LABEL_CONTEXT : String = "label context"

///|
pub const UNSUPPORTED_LABELED_BREAK_STATEMENT : String = "labeled break statement"

///|
pub const UNSUPPORTED_LABELED_CONTINUE_STATEMENT : String = "labeled continue statement"

///|
pub const UNSUPPORTED_LOGICAL_ASSIGNMENT_OPERATOR : String = "logical assignment operator"

///|
pub const UNSUPPORTED_LOOP_CONTEXT : String = "loop context"

///|
pub const UNSUPPORTED_OBJECT_LITERAL_ASYNC_GENERATOR_METHOD_PROPERTY : String = "object literal async generator method property"

///|
pub const UNSUPPORTED_OBJECT_LITERAL_ASYNC_METHOD_PROPERTY : String = "object literal async method property"

///|
pub const UNSUPPORTED_OBJECT_LITERAL_COMPUTED_ACCESSOR_PROPERTY : String = "object literal computed accessor property"

///|
pub const UNSUPPORTED_OBJECT_LITERAL_COMPUTED_PROPERTY : String = "object literal computed property"

///|
pub const UNSUPPORTED_OBJECT_LITERAL_DATA_PROPERTY_SUPER : String = "object literal data property super"

///|
pub const UNSUPPORTED_OBJECT_LITERAL_GENERATOR_METHOD_PROPERTY : String = "object literal generator method property"

///|
pub const UNSUPPORTED_OBJECT_LITERAL_METHOD_PROPERTY : String = "object literal method property"

///|
pub const UNSUPPORTED_OBJECT_LITERAL_PROPERTY_KEY : String = "object literal property key"

///|
pub const UNSUPPORTED_OBJECT_LITERAL_PROTO_METHOD_PROPERTY : String = "object literal __proto__ method property"

///|
pub const UNSUPPORTED_SPREAD_EXPRESSION : String = "spread expression"

///|
pub const UNSUPPORTED_SUPER_CALL : String = "super call"

///|
pub const UNSUPPORTED_SWITCH_CONTEXT : String = "switch context"

///|
pub const UNSUPPORTED_SWITCH_LEXICAL_DECLARATION : String = "switch lexical declaration"

///|
pub const UNSUPPORTED_TRY_CATCH_STATEMENT : String = "try/catch statement"

///|
pub const UNSUPPORTED_UPDATE_TARGET : String = "update target"

///|
pub const UNSUPPORTED_WITH_STATEMENT : String = "with statement"

///|
pub const UNSUPPORTED_YIELD_EXPRESSION : String = "yield expression"

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
  // True unless all of: no env-slot names, no env-var hoists, no arguments
  // object, no call_self_name, no inner functions, no rest param, no `this`
  // or super accesses, no `new.target`, no lexical decls, and no destructure
  // assign patterns (which disable local-slot param binding). When false,
  // call_compiled_func skips Environment::new + this/new.target inserts.
  needs_own_env : Bool
  local_names : Array[String]
  // O(1) slot lookup — same data as local_names but indexed; computed once at
  // lower time so BytecodeFrame and call_compiled_func avoid O(N) linear scans.
  local_indices : Map[String, Int]
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
  // Set when this function's body emits LoadThis / LoadNewTarget — used to
  // compute needs_own_env at the end of compile_bytecode_function.
  mut has_this : Bool
  mut has_new_target : Bool
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
    has_this: false,
    has_new_target: false,
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
      bytecode_unsupported(UNSUPPORTED_LOOP_CONTEXT)
      ctx
    }
    (None, _) => {
      bytecode_unsupported(UNSUPPORTED_LOOP_CONTEXT)
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
      bytecode_unsupported(UNSUPPORTED_SWITCH_CONTEXT)
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
        None => bytecode_unsupported(UNSUPPORTED_LABELED_BREAK_STATEMENT)
      }
    }
    None => {
      let jump = self.emit(Jump(-1))
      match self.current_break_context(UNSUPPORTED_BREAK_STATEMENT) {
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
        None => bytecode_unsupported(UNSUPPORTED_LABELED_CONTINUE_STATEMENT)
      }
    None => {
      let ctx = self.current_loop_context(UNSUPPORTED_CONTINUE_STATEMENT)
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
