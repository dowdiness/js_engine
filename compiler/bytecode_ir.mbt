///|
// A handle is scoped to one BytecodeProgram. Separate compilations need not
// produce numerically distinct handles; the owning program provides the
// identity boundary, while every nested function shares this source unit.
#warnings("-unused_value")
priv struct SourceUnitHandle(Int) derive(Eq, Debug)

///|
const MAX_SOURCE_POINT_OWNER_ID : Int = 0x7FFFFFFF

///|
#warnings("-unused_value")
priv struct SourcePointOwnerId(Int) derive(Eq, Debug)

///|
priv struct SourcePointOwnerAllocator {
  next_id : Int
}

///|
priv suberror BytecodeSourcePointOwnerAllocationDefect {
  BytecodeSourcePointOwnerAllocationDefect(Int)
}

///|
fn new_source_point_owner_allocator() -> Ref[SourcePointOwnerAllocator] {
  { val: { next_id: 0 } }
}

///|
fn allocate_source_point_owner(
  allocator : Ref[SourcePointOwnerAllocator],
) -> SourcePointOwnerId raise BytecodeSourcePointOwnerAllocationDefect {
  let next_id = allocator.val.next_id
  guard next_id >= 0 && next_id < MAX_SOURCE_POINT_OWNER_ID else {
    raise BytecodeSourcePointOwnerAllocationDefect(next_id)
  }
  allocator.val = { next_id: next_id + 1 }
  SourcePointOwnerId(next_id)
}

///|
// Source-point references carry source-unit and function-local ownership tags
// that verification requires to match the owning function/root program;
// separate program identity remains the private facade boundary.

///|
priv struct SourcePointId(SourceUnitHandle, SourcePointOwnerId, Int)

///|
#warnings("-unused_value")
priv enum SourcePointRole {
  StatementEntry
  ExpressionEntry
  BindingAccess
  MemberAccess
  SuperMemberAccess
  PropertyKey
  Operator
  Call
  Construct
  Throw
  Spread
  DirectEval
  Iterator
} derive(Eq, Debug)

///|
#warnings("-unused_field")
priv struct SourcePoint {
  role : SourcePointRole
  loc : @token.Loc
}

///|
#warnings("-unused_field")
priv struct ResolvedSourcePoint {
  source_unit : SourceUnitHandle
  role : SourcePointRole
  loc : @token.Loc
}

///|
#warnings("-unused_constructor")
priv enum BytecodeObservationBarrierKind {
  NotObservationBarrier
  StatementObservationBarrier
  ExpressionObservationBarrier
}

///|
// Activation eligibility is intentionally a closed compiler-owned decision.
// The runtime request remains the authority for managed execution; this
// disposition only decides whether a verified function may start in bytecode.
#warnings("-unused_constructor")
priv enum BytecodeActivationDisposition {
  SynchronousLeaf
  ManagedSuspension
  UnsupportedBeforeActivation(BytecodeActivationUnsupportedReason)
}

///|
// These reasons describe activation admission, not lowering/front-end
// rejection. Keep this type private so the lowering and selection contracts
// cannot accidentally share a phase-specific diagnostic.
#warnings("-unused_constructor")
priv enum BytecodeActivationUnsupportedReason {
  SuperPropertyAccess
  SuperComputedPropertyAccess
  BinaryOperation
  UnaryNumericConversion
  DeleteName
  DeleteProperty
  DeleteComputedProperty
  TemplateInterpolation
  UpdateName
  UpdateLocal
  UpdateEnvSlot
  ConditionalComputedUpdate
  ForInEnumeration
  ArraySpread
  ArgumentSpread
  ObjectPropertyKey
  ObjectSpread
  SynchronousPropertyAssignment
  SynchronousComputedPropertyAssignment
  ConditionalComputedProperty
  ComputedAssignmentRead
  ConditionalComputedAssignment
  DestructuringAssignment
  SuperPropertyCall
  SuperComputedPropertyCall
  DirectEval
  ConditionalComputedCall
}

///|
#warnings("-unused_field")
priv struct BytecodeInstructionContract {
  may_raise_js : Bool
  activation_disposition : BytecodeActivationDisposition
  required_source_roles : Array[SourcePointRole]
  observation_barrier : BytecodeObservationBarrierKind
}

///|
priv enum BytecodeInstr {
  ObserveStatement(SourcePointId)
  ObserveExpression(SourcePointId)
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
  MakeTemplateObject(Array[(String, String?)])
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
  BeginOptionalChain
  MarkOptionalChainShortCircuit
  JumpIfNotOptionalChainShortCircuitKeep(Int)
  EndOptionalChain
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
  PreparePlainPropertyCall(String, @token.Loc)
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
fn bytecode_instruction_contract(
  instr : BytecodeInstr,
) -> BytecodeInstructionContract {
  match instr {
    ObserveStatement(_) =>
      {
        may_raise_js: false,
        activation_disposition: SynchronousLeaf,
        required_source_roles: [StatementEntry],
        observation_barrier: StatementObservationBarrier,
      }
    ObserveExpression(_) =>
      {
        may_raise_js: false,
        activation_disposition: SynchronousLeaf,
        required_source_roles: [ExpressionEntry],
        observation_barrier: ExpressionObservationBarrier,
      }
    LoadConst(_)
    | LoadUndefined
    | LoadNewTarget
    | LoadLocal(_)
    | StoreLocal(_)
    | DefineBinding(_, _, _)
    | DefineLocal(_, _)
    | DefineEnvSlot(_, _)
    | SetCompletion
    | SetCompletionValue(_)
    | Pop
    | Dup
    | Jump(_)
    | JumpIfFalse(_)
    | JumpIfFalseKeep(_)
    | JumpIfTrueKeep(_)
    | JumpIfNotNullishKeep(_)
    | BeginOptionalChain
    | MarkOptionalChainShortCircuit
    | JumpIfNotOptionalChainShortCircuitKeep(_)
    | EndOptionalChain
    | ForInNext(_)
    | EndForIn
    | MakeArray(_)
    | MakeArrayWithHoles(_, _)
    | StartArray
    | ArrayPushValue
    | ArrayPushHole
    | StartArgs
    | ArgPushValue
    | MakeObject(_)
    | StartObject
    | ObjectSetStatic(_)
    | ObjectSetStaticGetter(_)
    | ObjectSetStaticSetter(_)
    | ObjectSetComputedGetter
    | ObjectSetComputedSetter
    | ObjectSetComputed
    | ObjectSetProto
    | SetFunctionName(_)
    | DeclareFunction(_, _)
    | DropPropertyAssignReference
    | DropComputedAssignReference
    | Return => bytecode_contract(false, SynchronousLeaf, [])
    LoadThis
    | LoadName(_)
    | LoadAssignmentName(_)
    | StoreName(_)
    | LoadEnvSlot(_)
    | StoreEnvSlot(_)
    | TypeofName(_) => bytecode_contract(true, SynchronousLeaf, [BindingAccess])
    DeleteName(_) =>
      bytecode_contract(true, UnsupportedBeforeActivation(DeleteName), [
        BindingAccess,
      ])
    LoadDirectEvalCallee =>
      bytecode_contract(true, SynchronousLeaf, [BindingAccess, DirectEval])
    LoadConsoleMember(_) =>
      bytecode_contract(true, SynchronousLeaf, [MemberAccess])
    LoadSuperProperty(_, _) =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(SuperPropertyAccess),
        [SuperMemberAccess],
      )
    LoadSuperComputed(_) =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(SuperComputedPropertyAccess),
        [SuperMemberAccess, PropertyKey],
      )
    BinaryOp(op, _) => bytecode_binary_contract(op)
    UnaryValueOp(op, _) => bytecode_unary_contract(op)
    DeleteProperty(_) =>
      bytecode_contract(true, UnsupportedBeforeActivation(DeleteProperty), [
        MemberAccess,
      ])
    DeleteComputed =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(DeleteComputedProperty),
        [MemberAccess, PropertyKey],
      )
    AppendTemplate(_) =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(TemplateInterpolation),
        [Operator],
      )
    MakeTemplateObject(_) => bytecode_contract(false, SynchronousLeaf, [])
    MakeRegExp(_, _) =>
      bytecode_contract(true, SynchronousLeaf, [ExpressionEntry])
    UpdateName(_, _, _, _) =>
      bytecode_contract(true, UnsupportedBeforeActivation(UpdateName), [
        BindingAccess,
        Operator,
      ])
    UpdateLocal(_, _, _) =>
      bytecode_contract(true, UnsupportedBeforeActivation(UpdateLocal), [
        BindingAccess,
        Operator,
      ])
    UpdateEnvSlot(_, _, _) =>
      bytecode_contract(true, UnsupportedBeforeActivation(UpdateEnvSlot), [
        BindingAccess,
        Operator,
      ])
    UpdateProperty(_, _, _, _, _) =>
      bytecode_contract(true, ManagedSuspension, [MemberAccess, Operator])
    UpdateComputed(_, _, _, _) =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(ConditionalComputedUpdate),
        [MemberAccess, PropertyKey, Operator],
      )
    StartForIn =>
      bytecode_contract(true, UnsupportedBeforeActivation(ForInEnumeration), [
        Iterator,
      ])
    ArrayPushSpread(_) =>
      bytecode_contract(true, UnsupportedBeforeActivation(ArraySpread), [
        Spread,
        Iterator,
      ])
    ArgPushSpread(_) =>
      bytecode_contract(true, UnsupportedBeforeActivation(ArgumentSpread), [
        Spread,
        Iterator,
      ])
    ToObjectLiteralPropertyKey =>
      bytecode_contract(true, UnsupportedBeforeActivation(ObjectPropertyKey), [
        PropertyKey,
      ])
    ObjectSpread(_) =>
      bytecode_contract(true, UnsupportedBeforeActivation(ObjectSpread), [
        Spread,
      ])
    MakeFunction(_)
    | MakeNamedFunction(_, _)
    | MakeMethodFunction(_)
    | MakeComputedMethodFunction(_)
    | MakeArrowFunction(_) =>
      bytecode_contract(true, SynchronousLeaf, [ExpressionEntry])
    GetProperty(_, _)
    | ReadPropertyForAssign(_, _)
    | SetProperty(_, _)
    | PreparePropertyCall(_, _)
    | PreparePlainPropertyCall(_, _) =>
      bytecode_contract(true, ManagedSuspension, [MemberAccess])
    SetForInProperty(_, _) =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(SynchronousPropertyAssignment),
        [MemberAccess],
      )
    GetComputed(_) =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(ConditionalComputedProperty),
        [MemberAccess, PropertyKey],
      )
    ReadComputedForAssign(_) =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(ComputedAssignmentRead),
        [MemberAccess, PropertyKey],
      )
    SetComputed(_) =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(ConditionalComputedAssignment),
        [MemberAccess, PropertyKey],
      )
    SetForInComputed(_) =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(SynchronousComputedPropertyAssignment),
        [MemberAccess, PropertyKey],
      )
    PrepareComputedCall(_) =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(ConditionalComputedCall),
        [MemberAccess, PropertyKey],
      )
    AssignPattern(_) =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(DestructuringAssignment),
        [BindingAccess, MemberAccess, Iterator],
      )
    PrepareSuperPropertyCall(_, _) =>
      bytecode_contract(true, UnsupportedBeforeActivation(SuperPropertyCall), [
        SuperMemberAccess,
      ])
    PrepareSuperComputedCall(_) =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(SuperComputedPropertyCall),
        [SuperMemberAccess, PropertyKey],
      )
    CallDirectEval(_) =>
      bytecode_contract(true, UnsupportedBeforeActivation(DirectEval), [
        DirectEval,
        Call,
      ])
    Call(_, _)
    | CallWithReceiver(_, _)
    | CallSpread(_)
    | CallSpreadWithReceiver(_) =>
      bytecode_contract(true, ManagedSuspension, [Call])
    Construct(_, _) | ConstructSpread(_) =>
      bytecode_contract(true, ManagedSuspension, [Construct])
    Throw => bytecode_contract(true, SynchronousLeaf, [Throw])
  }
}

///|
fn bytecode_contract(
  may_raise_js : Bool,
  activation_disposition : BytecodeActivationDisposition,
  required_source_roles : Array[SourcePointRole],
) -> BytecodeInstructionContract {
  {
    may_raise_js,
    activation_disposition,
    required_source_roles,
    observation_barrier: NotObservationBarrier,
  }
}

///|
fn bytecode_binary_contract(op : @ast.BinOp) -> BytecodeInstructionContract {
  match op {
    EqEqEq | NotEqEq | And | Or | NullishCoalesce =>
      bytecode_contract(false, SynchronousLeaf, [Operator])
    Add
    | Sub
    | Mul
    | Div
    | Mod
    | EqEq
    | NotEq
    | Lt
    | Gt
    | LtEq
    | GtEq
    | BitAnd
    | BitOr
    | BitXor
    | LShift
    | RShift
    | URShift
    | Exp
    | In
    | Instanceof =>
      bytecode_contract(true, UnsupportedBeforeActivation(BinaryOperation), [
        Operator,
      ])
  }
}

///|
fn bytecode_unary_contract(op : @ast.UnaryOp) -> BytecodeInstructionContract {
  match op {
    Not | Typeof | Void | Delete =>
      bytecode_contract(false, SynchronousLeaf, [Operator])
    Neg | Pos | BitNot =>
      bytecode_contract(
        true,
        UnsupportedBeforeActivation(UnaryNumericConversion),
        [Operator],
      )
  }
}

///|
priv enum BytecodeLexicalKind {
  BytecodeLet
  BytecodeConst
}

///|
// Immutable declaration facts prepared from a function's own body.  These
// facts intentionally use compiler-owned tags and source locations rather
// than runtime Binding values or executable AST nodes.
priv struct BytecodeLexicalBinding {
  kind : BytecodeLexicalKind
  name : String
  loc : @token.Loc
}

///|
priv struct BytecodeFunctionDeclaration {
  name : String
  child_index : Int
  loc : @token.Loc
}

///|
priv enum BytecodeSignatureValidation {
  SignaturePending
  SignatureValidated
}

///|
priv struct BytecodePreparation {
  lexical_bindings : Array[BytecodeLexicalBinding]
  function_declarations : Array[BytecodeFunctionDeclaration]
  signature_validation : BytecodeSignatureValidation
  activation_capability : @runtime.ExecutorActivationCapabilitySummary?
}

///|
fn BytecodePreparation::BytecodePreparation(
  lexical_bindings? : Array[BytecodeLexicalBinding] = [],
  function_declarations? : Array[BytecodeFunctionDeclaration] = [],
  signature_validation? : BytecodeSignatureValidation = SignaturePending,
  activation_capability? : @runtime.ExecutorActivationCapabilitySummary? = None,
) -> BytecodePreparation {
  {
    lexical_bindings,
    function_declarations,
    signature_validation,
    activation_capability,
  }
}

///|
#warnings("-unused_field")
priv struct BytecodeFunction {
  name : String?
  params : Array[String]
  rest_param : String?
  // Temporary source metadata retained until the remaining AST representation
  // debt is removed. VM preparation and execution must use the verified facts
  // below, never traverse this tree.
  source_body : Array[@ast.Stmt]
  preparation : BytecodePreparation
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
  source_unit : SourceUnitHandle
  source_point_owner : SourcePointOwnerId
  source_points : Array[SourcePoint]
  instruction_sources : Array[Array[SourcePointId]]
  children : Array[BytecodeFunction]
}

///|
fn BytecodeFunction::BytecodeFunction(
  name~ : String?,
  params~ : Array[String],
  rest_param~ : String?,
  source_body~ : Array[@ast.Stmt],
  preparation~ : BytecodePreparation,
  body_has_use_strict~ : Bool,
  call_self_name~ : Bool,
  needs_arguments_object~ : Bool,
  needs_own_env~ : Bool,
  local_names~ : Array[String],
  local_indices~ : Map[String, Int],
  env_slot_names~ : Array[String],
  env_var_hoist_names~ : Array[String],
  template_cache_key_prefix~ : String,
  code~ : Array[BytecodeInstr],
  source_point_owner~ : SourcePointOwnerId,
  source_unit? : SourceUnitHandle = SourceUnitHandle(0),
  source_points? : Array[SourcePoint] = [],
  instruction_sources? : Array[Array[SourcePointId]] = [],
  children~ : Array[BytecodeFunction],
) -> BytecodeFunction {
  {
    name,
    params,
    rest_param,
    source_body,
    preparation,
    body_has_use_strict,
    call_self_name,
    needs_arguments_object,
    needs_own_env,
    local_names,
    local_indices,
    env_slot_names,
    env_var_hoist_names,
    template_cache_key_prefix,
    code,
    source_unit,
    source_point_owner,
    source_points,
    instruction_sources,
    children,
  }
}

///|
fn BytecodeFunction::resolve_source_point(
  self : BytecodeFunction,
  id : SourcePointId,
) -> ResolvedSourcePoint {
  let SourcePointId(_, _, index) = id
  let point = self.source_points[index]
  { source_unit: self.source_unit, role: point.role, loc: point.loc }
}

///|
// This carrier is created only by bytecode finalization after the complete
// function tree has passed every verifier. Its private representation keeps
// the verification provenance attached to every nested activation.
priv struct VerifiedBytecodeFunction {
  function : BytecodeFunction
  preparation : BytecodePreparation
}

///|
fn VerifiedBytecodeFunction::child(
  self : VerifiedBytecodeFunction,
  index : Int,
) -> VerifiedBytecodeFunction {
  let function = self.function.children[index]
  { function, preparation: function.preparation }
}

///|
priv struct BytecodeBuilder {
  code : Array[BytecodeInstr]
  source_unit : SourceUnitHandle
  source_point_owner : SourcePointOwnerId
  owner_allocator : Ref[SourcePointOwnerAllocator]
  source_points : Array[SourcePoint]
  instruction_sources : Array[Array[SourcePointId]]
  children : Array[BytecodeFunction]
  function_declarations : Array[BytecodeFunctionDeclaration]
  enclosing_strict : Bool
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
  priv verified_main : VerifiedBytecodeFunction
}

///|
priv struct BytecodeUnverifiedProgram {
  source_stmts : Array[@ast.Stmt]
  main : BytecodeFunction
}

///|
priv enum BytecodeRunResult {
  BytecodeNormal(Value)
  BytecodeReturn(Value)
}

///|
#warnings("-unused_field")
priv struct BytecodeActivationUnsupported {
  function_path : Array[Int]
  instruction_index : Int
  reason : BytecodeActivationUnsupportedReason
}

///|
// This selection is pure and does not construct a BytecodeFrame.  It scans
// only the function whose activation is being admitted; child functions are
// selected when their own executor activation starts.
#warnings("-unused_value")
fn select_bytecode_function_activation(
  function : VerifiedBytecodeFunction,
  function_path : Array[Int],
) -> Result[BytecodeActivationDisposition, BytecodeActivationUnsupported] {
  let mut has_managed_suspension = false
  for instruction_index, instruction in function.function.code {
    match bytecode_instruction_contract(instruction).activation_disposition {
      UnsupportedBeforeActivation(reason) =>
        return Err({
          function_path: function_path.copy(),
          instruction_index,
          reason,
        })
      SynchronousLeaf => ()
      ManagedSuspension => has_managed_suspension = true
    }
  }
  Ok(if has_managed_suspension { ManagedSuspension } else { SynchronousLeaf })
}

///|
fn BytecodeBuilder::BytecodeBuilder(
  plan : BytecodeLocalPlan,
  template_cache_key_prefix : String,
  source_point_owner : SourcePointOwnerId,
  owner_allocator : Ref[SourcePointOwnerAllocator],
  source_unit? : SourceUnitHandle = SourceUnitHandle(0),
  enclosing_strict? : Bool = false,
) -> BytecodeBuilder {
  {
    code: [],
    source_unit,
    source_point_owner,
    owner_allocator,
    source_points: [],
    instruction_sources: [],
    children: [],
    function_declarations: [],
    enclosing_strict,
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
  self.instruction_sources.push([])
  idx
}

///|
fn BytecodeBuilder::allocate_source_point(
  self : BytecodeBuilder,
  role : SourcePointRole,
  loc : @token.Loc,
) -> SourcePointId {
  let id = SourcePointId(
    self.source_unit,
    self.source_point_owner,
    self.source_points.length(),
  )
  self.source_points.push({ role, loc })
  id
}

///|
fn BytecodeBuilder::emit_with_sources(
  self : BytecodeBuilder,
  instr : BytecodeInstr,
  sources : Array[SourcePointId],
) -> Int {
  let idx = self.emit(instr)
  self.instruction_sources[idx] = sources
  idx
}

///|
fn BytecodeBuilder::emit_with_source_locations(
  self : BytecodeBuilder,
  instr : BytecodeInstr,
  source_locations : Array[(SourcePointRole, @token.Loc)],
) -> Int raise Error {
  let required = bytecode_instruction_contract(instr).required_source_roles
  guard required.length() == source_locations.length() else {
    raise @errors.InternalError(
      message="bytecode instruction source-role count mismatch",
    )
  }
  let sources : Array[SourcePointId] = []
  for index, required_role in required {
    let (actual_role, loc) = source_locations[index]
    guard actual_role == required_role else {
      raise @errors.InternalError(
        message="bytecode instruction source-role order mismatch",
      )
    }
    sources.push(self.allocate_source_point(actual_role, loc))
  }
  self.emit_with_sources(instr, sources)
}

///|
fn BytecodeBuilder::emit_statement_observation(
  self : BytecodeBuilder,
  loc : @token.Loc,
) -> Unit {
  let source_id = self.allocate_source_point(StatementEntry, loc)
  let _ = self.emit_with_sources(ObserveStatement(source_id), [source_id])
}

///|
fn BytecodeBuilder::emit_expression_observation(
  self : BytecodeBuilder,
  loc : @token.Loc,
) -> Unit {
  let source_id = self.allocate_source_point(ExpressionEntry, loc)
  let _ = self.emit_with_sources(ObserveExpression(source_id), [source_id])
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
      raise @errors.InternalError(
        message="bytecode loop context invariant violated",
      )
      ctx
    }
    (None, _) => {
      raise @errors.InternalError(
        message="bytecode loop context invariant violated",
      )
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
      raise @errors.InternalError(
        message="bytecode switch context invariant violated",
      )
      { break_jumps: [] }
    }
  }
}

///|
fn BytecodeBuilder::current_break_context(
  self : BytecodeBuilder,
) -> BreakPatchContext raise Error {
  if self.break_contexts.length() == 0 {
    raise @errors.SyntaxError(message="break statement outside of loop")
  }
  self.break_contexts[self.break_contexts.length() - 1]
}

///|
fn BytecodeBuilder::current_loop_context(
  self : BytecodeBuilder,
) -> LoopPatchContext raise Error {
  if self.loop_contexts.length() == 0 {
    raise @errors.SyntaxError(message="continue statement outside of loop")
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
        None => raise @errors.SyntaxError(message="Undefined label '\{target}'")
      }
    }
    None => {
      let jump = self.emit(Jump(-1))
      match self.current_break_context() {
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
        None =>
          match self.find_label_context(target) {
            Some(_) =>
              raise @errors.SyntaxError(
                message="Illegal continue statement: '\{target}' does not denote an iteration statement",
              )
            None =>
              raise @errors.SyntaxError(message="Undefined label '\{target}'")
          }
      }
    None => {
      let ctx = self.current_loop_context()
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
