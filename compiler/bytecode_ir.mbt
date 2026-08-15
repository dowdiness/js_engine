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
  // A single opaque token marks one lowering run. Every root/child identity
  // copied from this allocator shares it, while a separate compilation does
  // not accidentally reuse the numeric source handles.
  program_identity : Ref[Unit]
}

///|
priv suberror BytecodeSourcePointOwnerAllocationDefect {
  BytecodeSourcePointOwnerAllocationDefect(Int)
}

///|
fn new_source_point_owner_allocator() -> Ref[SourcePointOwnerAllocator] {
  { val: { next_id: 0, program_identity: { val: () } } }
}

///|
fn allocate_source_point_owner(
  allocator : Ref[SourcePointOwnerAllocator],
) -> SourcePointOwnerId raise BytecodeSourcePointOwnerAllocationDefect {
  let next_id = allocator.val.next_id
  guard next_id >= 0 && next_id < MAX_SOURCE_POINT_OWNER_ID else {
    raise BytecodeSourcePointOwnerAllocationDefect(next_id)
  }
  allocator.val = {
    next_id: next_id + 1,
    program_identity: allocator.val.program_identity,
  }
  SourcePointOwnerId(next_id)
}

///|
// Source-point references carry source-unit and function-local ownership tags
// that verification requires to match the owning function/root program;
// separate program identity remains the private facade boundary.

///|
priv struct SourcePointId(SourceUnitHandle, SourcePointOwnerId, Int) derive(Eq)

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
// Lowering records the observations active before each instruction.  The
// verifier uses this typed, source-linked context to distinguish a legal edge
// that skips an unevaluated region from an edge that enters that region after
// its mandatory observation barrier.
priv enum BytecodeObservationContextEntry {
  StatementObservation(SourcePointId)
  ExpressionObservation(SourcePointId)
} derive(Eq)

///|
priv struct BytecodeObservationContext {
  active : Array[BytecodeObservationContextEntry]
}

///|
// Lowering records the expected context for each non-fallthrough successor and
// each fallthrough whose context changes after a scope pop.  The verifier
// checks these edge facts against the actual instruction transfer and target
// context; snapshots alone cannot authorize a retargeted edge.
priv struct BytecodeObservationEdgeContext {
  successor : Int
  context : BytecodeObservationContext
}

///|
// This is an immutable lowering-time witness for observation region membership
// and successor topology.  The mutable snapshots above remain convenient
// inputs for the CFG proof, but finalization also compares them with this
// independently-owned linked fact sequence so coordinated edits cannot
// rewrite the proof's authority.
priv enum BytecodeObservationAuthorityContextEntries {
  EmptyObservationAuthorityContext
  MoreObservationAuthorityContext(
    BytecodeObservationContextEntry,
    BytecodeObservationAuthorityContextEntries
  )
}

///|
priv enum BytecodeObservationAuthoritySuccessors {
  EmptyObservationAuthoritySuccessors
  MoreObservationAuthoritySuccessors(
    Int,
    BytecodeObservationAuthoritySuccessors
  )
}

///|
priv struct BytecodeObservationAuthorityInstruction {
  context : BytecodeObservationAuthorityContextEntries
  successors : BytecodeObservationAuthoritySuccessors
}

///|
priv enum BytecodeObservationAuthorityInstructions {
  EmptyObservationAuthorityInstructions
  MoreObservationAuthorityInstructions(
    BytecodeObservationAuthorityInstruction,
    BytecodeObservationAuthorityInstructions
  )
}

///|
priv struct BytecodeObservationAuthority {
  program_identity : Ref[Unit]
  source_point_owner : SourcePointOwnerId
  code_length : Int
  instructions : BytecodeObservationAuthorityInstructions
}

///|
fn empty_bytecode_observation_authority() -> BytecodeObservationAuthority {
  {
    program_identity: { val: () },
    source_point_owner: SourcePointOwnerId(-1),
    code_length: -1,
    instructions: EmptyObservationAuthorityInstructions,
  }
}

///|
fn bytecode_observation_authority_context_entries(
  active : Array[BytecodeObservationContextEntry],
) -> BytecodeObservationAuthorityContextEntries {
  let mut entries = EmptyObservationAuthorityContext
  for index = active.length() - 1; index >= 0; index = index - 1 {
    entries = MoreObservationAuthorityContext(active[index], entries)
  }
  entries
}

///|
fn bytecode_observation_authority_successors(
  transfer : BytecodeInstructionTransfer,
  instruction_index : Int,
) -> BytecodeObservationAuthoritySuccessors {
  match transfer {
    Fallthrough(_) =>
      MoreObservationAuthoritySuccessors(
        instruction_index + 1,
        EmptyObservationAuthoritySuccessors,
      )
    JumpTo(target, _) | BranchTo(target, _) | SplitTo(target, _, _) => {
      let tail = match transfer {
        BranchTo(_, _) | SplitTo(_, _, _) =>
          MoreObservationAuthoritySuccessors(
            instruction_index + 1,
            EmptyObservationAuthoritySuccessors,
          )
        _ => EmptyObservationAuthoritySuccessors
      }
      MoreObservationAuthoritySuccessors(target, tail)
    }
    Terminate(_) => EmptyObservationAuthoritySuccessors
  }
}

///|
// Materialize edge contexts only after lowering has produced the final code.
// Every successor is derived from the exhaustive instruction transfer; the
// terminal successor uses the empty context because no instruction executes
// at code.length().
fn bytecode_observation_edge_contexts_from_lowering(
  code : Array[BytecodeInstr],
  observation_contexts : Array[BytecodeObservationContext],
) -> Array[Array[BytecodeObservationEdgeContext]] {
  let code_length = code.length()
  let edge_contexts : Array[Array[BytecodeObservationEdgeContext]] = Array::makei(
    code_length,
    _ => [],
  )
  for instruction_index, instruction in code {
    let transfer = bytecode_instruction_transfer(instruction)
    let append_edge = target => {
      if target >= 0 && target <= code_length {
        let context = if target == code_length {
          { active: [] }
        } else {
          observation_contexts[target]
        }
        edge_contexts[instruction_index].push({ successor: target, context })
      }
    }
    match transfer {
      Fallthrough(_) => append_edge(instruction_index + 1)
      JumpTo(target, _) => append_edge(target)
      BranchTo(target, _) => {
        append_edge(target)
        append_edge(instruction_index + 1)
      }
      SplitTo(target, _, _) => {
        append_edge(target)
        append_edge(instruction_index + 1)
      }
      Terminate(_) => ()
    }
  }
  edge_contexts
}

///|
fn bytecode_observation_authority_from_lowering(
  code : Array[BytecodeInstr],
  observation_contexts : Array[BytecodeObservationContext],
  source_identity : BytecodeSourceIdentity,
) -> BytecodeObservationAuthority {
  let mut instructions = EmptyObservationAuthorityInstructions
  for index = code.length() - 1; index >= 0; index = index - 1 {
    let context = if index < observation_contexts.length() {
      bytecode_observation_authority_context_entries(
        observation_contexts[index].active,
      )
    } else {
      EmptyObservationAuthorityContext
    }
    instructions = MoreObservationAuthorityInstructions(
      {
        context,
        successors: bytecode_observation_authority_successors(
          bytecode_instruction_transfer(code[index]),
          index,
        ),
      },
      instructions,
    )
  }
  {
    program_identity: source_identity.program_identity,
    source_point_owner: source_identity.source_point_owner,
    code_length: code.length(),
    instructions,
  }
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
// The origin is retained in the instruction itself because admission must
// never infer compound-assignment syntax from neighboring stack operations.
// Both origins currently share the pre-activation binary-operation contract;
// #886 later admits only the plain Add origin.
priv enum BytecodeBinaryOrigin {
  BinaryExpression
  CompoundAssignment
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
  BinaryOp(@ast.BinOp, BytecodeBinaryOrigin, @token.Loc)
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
  AssignDestructure(@runtime.DestructurePlan)
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
    BinaryOp(op, origin, _) => bytecode_binary_contract(op, origin)
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
    AssignDestructure(_) =>
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
fn bytecode_binary_contract(
  op : @ast.BinOp,
  origin : BytecodeBinaryOrigin,
) -> BytecodeInstructionContract {
  match (op, origin) {
    (EqEqEq, _)
    | (NotEqEq, _)
    | (And, _)
    | (Or, _)
    | (NullishCoalesce, _) =>
      bytecode_contract(false, SynchronousLeaf, [Operator])
    (Add, BinaryExpression)
    | (Add, CompoundAssignment)
    | (Sub, BinaryExpression)
    | (Sub, CompoundAssignment)
    | (Mul, BinaryExpression)
    | (Mul, CompoundAssignment)
    | (Div, BinaryExpression)
    | (Div, CompoundAssignment)
    | (Mod, BinaryExpression)
    | (Mod, CompoundAssignment)
    | (EqEq, BinaryExpression)
    | (EqEq, CompoundAssignment)
    | (NotEq, BinaryExpression)
    | (NotEq, CompoundAssignment)
    | (Lt, BinaryExpression)
    | (Lt, CompoundAssignment)
    | (Gt, BinaryExpression)
    | (Gt, CompoundAssignment)
    | (LtEq, BinaryExpression)
    | (LtEq, CompoundAssignment)
    | (GtEq, BinaryExpression)
    | (GtEq, CompoundAssignment)
    | (BitAnd, BinaryExpression)
    | (BitAnd, CompoundAssignment)
    | (BitOr, BinaryExpression)
    | (BitOr, CompoundAssignment)
    | (BitXor, BinaryExpression)
    | (BitXor, CompoundAssignment)
    | (LShift, BinaryExpression)
    | (LShift, CompoundAssignment)
    | (RShift, BinaryExpression)
    | (RShift, CompoundAssignment)
    | (URShift, BinaryExpression)
    | (URShift, CompoundAssignment)
    | (Exp, BinaryExpression)
    | (Exp, CompoundAssignment)
    | (In, BinaryExpression)
    | (In, CompoundAssignment)
    | (Instanceof, BinaryExpression)
    | (Instanceof, CompoundAssignment) =>
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
  source_identity : BytecodeSourceIdentity
}

///|
// The closed bytecode consumer is the independent authority for a child's
// effective signature policy.  Its payload is retained only for named forms.
#warnings("-unused_constructor")
priv enum BytecodeFunctionConsumerForm {
  DeclareFunctionConsumer(String)
  FunctionConsumer
  NamedFunctionConsumer(String)
  MethodFunctionConsumer
  ComputedMethodFunctionConsumer
  ArrowFunctionConsumer
} derive(Eq)

///|
// A function's source identity is composed from an opaque per-compilation
// token, the existing source-unit and function-local owner handles, and its
// parent consumer position. Separate compilations therefore do not share this
// private identity even when their numeric handles coincide.
priv struct BytecodeSourceIdentity {
  program_identity : Ref[Unit]
  source_unit : SourceUnitHandle
  source_point_owner : SourcePointOwnerId
  parent_source_point_owner : SourcePointOwnerId?
  child_index : Int?
  consumer_form : BytecodeFunctionConsumerForm?
}

///|
fn bytecode_source_identity_equal(
  left : BytecodeSourceIdentity,
  right : BytecodeSourceIdentity,
) -> Bool {
  physical_equal(left.program_identity, right.program_identity) &&
  left.source_unit == right.source_unit &&
  left.source_point_owner == right.source_point_owner &&
  left.parent_source_point_owner == right.parent_source_point_owner &&
  left.child_index == right.child_index &&
  left.consumer_form == right.consumer_form
}

///|
fn BytecodeSourceIdentity::root(
  source_unit : SourceUnitHandle,
  source_point_owner : SourcePointOwnerId,
  program_identity? : Ref[Unit]? = None,
) -> BytecodeSourceIdentity {
  let program_identity = match program_identity {
    Some(identity) => identity
    None => { val: () }
  }
  {
    program_identity,
    source_unit,
    source_point_owner,
    parent_source_point_owner: None,
    child_index: None,
    consumer_form: None,
  }
}

///|
fn BytecodeSourceIdentity::child(
  program_identity : Ref[Unit],
  source_unit : SourceUnitHandle,
  source_point_owner : SourcePointOwnerId,
  parent_source_point_owner : SourcePointOwnerId,
  child_index : Int,
  consumer_form : BytecodeFunctionConsumerForm,
) -> BytecodeSourceIdentity {
  {
    program_identity,
    source_unit,
    source_point_owner,
    parent_source_point_owner: Some(parent_source_point_owner),
    child_index: Some(child_index),
    consumer_form: Some(consumer_form),
  }
}

///|
// Lowering provenance binds a child header to its parent consumer and the
// immutable facts captured for the selected child.  It never retains source
// AST; exact source text is copied separately at the lowering boundary.
#warnings("-unused_field")
priv struct BytecodeHeaderProvenance {
  program_identity : Ref[Unit]
  name : String?
  signature_name : String?
  params : Array[String]
  rest_param : String?
  enclosing_strict : Bool
  parent_source_point_owner : SourcePointOwnerId
  child_index : Int
  consumer_form : BytecodeFunctionConsumerForm
  exact_source_text : String?
  child_source_identity : BytecodeSourceIdentity?
  expected_preparation : BytecodePreparation?
}

///|
#warnings("-unused_value")
fn BytecodeHeaderProvenance::BytecodeHeaderProvenance(
  program_identity : Ref[Unit],
  name : String?,
  params : Array[String],
  rest_param : String?,
  enclosing_strict : Bool,
  parent_source_point_owner : SourcePointOwnerId,
  child_index : Int,
  consumer_form : BytecodeFunctionConsumerForm,
  exact_source_text : String?,
) -> BytecodeHeaderProvenance {
  {
    program_identity,
    name,
    signature_name: match consumer_form {
      MethodFunctionConsumer
      | ComputedMethodFunctionConsumer
      | ArrowFunctionConsumer => None
      _ => name
    },
    params,
    rest_param,
    enclosing_strict,
    parent_source_point_owner,
    child_index,
    consumer_form,
    exact_source_text,
    child_source_identity: None,
    expected_preparation: None,
  }
}

///|
fn BytecodeHeaderProvenance::with_child_facts(
  self : BytecodeHeaderProvenance,
  child_source_identity : BytecodeSourceIdentity,
  preparation : BytecodePreparation,
) -> BytecodeHeaderProvenance {
  {
    program_identity: self.program_identity,
    name: self.name,
    signature_name: self.signature_name,
    params: self.params.copy(),
    rest_param: self.rest_param,
    enclosing_strict: self.enclosing_strict,
    parent_source_point_owner: self.parent_source_point_owner,
    child_index: self.child_index,
    consumer_form: self.consumer_form,
    exact_source_text: self.exact_source_text,
    child_source_identity: Some(child_source_identity),
    expected_preparation: Some(preparation.copy()),
  }
}

// Canonical signature inputs captured after the runtime-owned validator has
// accepted a function. The parameter array is a private copy, so preparation
// never shares the lowering/runtime input array.

///|
priv struct BytecodeSignatureValidation {
  effective_name : String?
  enclosing_strict : Bool
  params : Array[String]
  rest_param : String?
  body_has_use_strict : Bool
}

///|
priv struct BytecodePreparation {
  lexical_bindings : Array[BytecodeLexicalBinding]
  function_declarations : Array[BytecodeFunctionDeclaration]
  signature_validation : BytecodeSignatureValidation?
  activation_capability : @runtime.ExecutorActivationCapabilitySummary?
}

///|
fn BytecodePreparation::BytecodePreparation(
  lexical_bindings? : Array[BytecodeLexicalBinding] = [],
  function_declarations? : Array[BytecodeFunctionDeclaration] = [],
  signature_validation? : BytecodeSignatureValidation? = None,
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
fn BytecodePreparation::copy(self : BytecodePreparation) -> BytecodePreparation {
  let signature_validation = match self.signature_validation {
    Some(facts) =>
      Some({
        effective_name: facts.effective_name,
        enclosing_strict: facts.enclosing_strict,
        params: facts.params.copy(),
        rest_param: facts.rest_param,
        body_has_use_strict: facts.body_has_use_strict,
      })
    None => None
  }
  {
    lexical_bindings: self.lexical_bindings.copy(),
    function_declarations: self.function_declarations.copy(),
    signature_validation,
    activation_capability: self.activation_capability,
  }
}

///|
#warnings("-unused_field")
priv enum BytecodeActivationKind {
  ScriptRootActivation
  FunctionActivation
} derive(Eq)

///|
#warnings("-unused_field")
priv struct BytecodeFunction {
  name : String?
  signature_name : String?
  enclosing_strict : Bool
  params : Array[String]
  rest_param : String?
  // Exact parser text is source metadata only; executable preparation below
  // never depends on a reserialized or retained source tree.
  source_text : String?
  source_identity : BytecodeSourceIdentity
  activation_kind : BytecodeActivationKind
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
  // source input on every call (issue #325).
  env_var_hoist_names : Array[String]
  template_cache_key_prefix : String
  code : Array[BytecodeInstr]
  source_unit : SourceUnitHandle
  source_point_owner : SourcePointOwnerId
  source_points : Array[SourcePoint]
  instruction_sources : Array[Array[SourcePointId]]
  observation_contexts : Array[BytecodeObservationContext]
  observation_edge_contexts : Array[Array[BytecodeObservationEdgeContext]]
  observation_authority : BytecodeObservationAuthority
  children : Array[BytecodeFunction]
  header_provenance : BytecodeHeaderProvenance?
}

///|
fn BytecodeFunction::BytecodeFunction(
  name~ : String?,
  signature_name~ : String?,
  enclosing_strict~ : Bool,
  params~ : Array[String],
  rest_param~ : String?,
  source_text? : String? = None,
  source_identity? : BytecodeSourceIdentity? = None,
  activation_kind? : BytecodeActivationKind = FunctionActivation,
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
  observation_contexts? : Array[BytecodeObservationContext] = [],
  observation_edge_contexts? : Array[Array[BytecodeObservationEdgeContext]] = [],
  observation_authority? : BytecodeObservationAuthority? = None,
  children~ : Array[BytecodeFunction],
  header_provenance? : BytecodeHeaderProvenance? = None,
) -> BytecodeFunction {
  {
    name,
    signature_name,
    enclosing_strict,
    params,
    rest_param,
    source_text,
    source_identity: match source_identity {
      Some(identity) => identity
      None => BytecodeSourceIdentity::root(source_unit, source_point_owner)
    },
    activation_kind,
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
    observation_contexts,
    observation_edge_contexts,
    observation_authority: match observation_authority {
      Some(authority) => authority
      None => empty_bytecode_observation_authority()
    },
    children,
    header_provenance,
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
  observation_contexts : Array[BytecodeObservationContext]
  active_observation_entries : Array[BytecodeObservationContextEntry]
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
  // Candidate preparation may provide the immutable source-owner plan that
  // pairs tree and bytecode functions. Normal lowering leaves this absent.
  candidate_identity_plan : CandidateIdentityPlan?
  // Candidate lowering may retain a bytecode parent while replacing an
  // unsupported child with a non-executable candidate slot.
  candidate_mode : Bool
  // Candidate child indices include lowering-unsupported slots even though
  // those slots are intentionally absent from `children`.
  mut candidate_child_slot_count : Int
  // Extended-parameter rejection occurs before add_function receives the
  // child body; carry that typed skip to the next candidate child boundary.
  mut candidate_pending_unsupported_child : Bool
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
// Immutable lowering snapshot for the root script. This is separate from the
// mutable unverified function tree so coordinated edits to root signature or
// preparation facts cannot rewrite the evidence used by finalization.
priv struct BytecodeRootScriptProvenance {
  program_identity : Ref[Unit]
  strict : Bool
  var_names : Array[String]
  function_names : Array[String]
  lexical_bindings : Array[@runtime.CompiledScriptLexicalBinding]
  name : String?
  signature_name : String?
  enclosing_strict : Bool
  params : Array[String]
  rest_param : String?
  body_has_use_strict : Bool
  source_identity : BytecodeSourceIdentity
  activation_kind : BytecodeActivationKind
  preparation : BytecodePreparation
  env_var_hoist_names : Array[String]
  settlement : @runtime.CompiledScriptEarlyErrorSettlement
}

///|
fn BytecodeRootScriptProvenance::from_lowering(
  main : BytecodeFunction,
  strict : Bool,
  var_names : Array[String],
  function_names : Array[String],
  lexical_bindings : Array[@runtime.CompiledScriptLexicalBinding],
  settlement : @runtime.CompiledScriptEarlyErrorSettlement,
) -> BytecodeRootScriptProvenance {
  {
    program_identity: main.source_identity.program_identity,
    strict,
    var_names: var_names.copy(),
    function_names: function_names.copy(),
    lexical_bindings: lexical_bindings.copy(),
    name: main.name,
    signature_name: main.signature_name,
    enclosing_strict: main.enclosing_strict,
    params: main.params.copy(),
    rest_param: main.rest_param,
    body_has_use_strict: main.body_has_use_strict,
    source_identity: main.source_identity,
    activation_kind: main.activation_kind,
    preparation: main.preparation.copy(),
    env_var_hoist_names: main.env_var_hoist_names.copy(),
    settlement,
  }
}

///|
#warnings("-unused_value")
fn BytecodeRootScriptProvenance::with_settlement(
  self : BytecodeRootScriptProvenance,
  settlement : @runtime.CompiledScriptEarlyErrorSettlement,
) -> BytecodeRootScriptProvenance {
  {
    program_identity: self.program_identity,
    strict: self.strict,
    var_names: self.var_names.copy(),
    function_names: self.function_names.copy(),
    lexical_bindings: self.lexical_bindings.copy(),
    name: self.name,
    signature_name: self.signature_name,
    enclosing_strict: self.enclosing_strict,
    params: self.params.copy(),
    rest_param: self.rest_param,
    body_has_use_strict: self.body_has_use_strict,
    source_identity: self.source_identity,
    activation_kind: self.activation_kind,
    preparation: self.preparation.copy(),
    env_var_hoist_names: self.env_var_hoist_names.copy(),
    settlement,
  }
}

///|
pub struct BytecodeProgram {
  priv script_preparation : @runtime.CompiledScriptPreparation
  priv verified_main : VerifiedBytecodeFunction
}

///|
priv struct BytecodeUnverifiedProgram {
  script_preparation : @runtime.CompiledScriptPreparation
  root_provenance : BytecodeRootScriptProvenance
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
fn select_bytecode_code_activation(
  code : Array[BytecodeInstr],
  function_path : Array[Int],
) -> Result[BytecodeActivationDisposition, BytecodeActivationUnsupported] {
  let mut has_managed_suspension = false
  for instruction_index, instruction in code {
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
// Ordinary verified execution keeps its existing carrier.  Candidate
// preparation reuses only this pure instruction scan and never constructs a
// VerifiedBytecodeFunction from its sparse, candidate-local child facts.
#warnings("-unused_value")
fn select_bytecode_function_activation(
  function : VerifiedBytecodeFunction,
  function_path : Array[Int],
) -> Result[BytecodeActivationDisposition, BytecodeActivationUnsupported] {
  select_bytecode_code_activation(function.function.code, function_path)
}

///|
fn BytecodeBuilder::BytecodeBuilder(
  plan : BytecodeLocalPlan,
  template_cache_key_prefix : String,
  source_point_owner : SourcePointOwnerId,
  owner_allocator : Ref[SourcePointOwnerAllocator],
  source_unit? : SourceUnitHandle = SourceUnitHandle(0),
  enclosing_strict? : Bool = false,
  candidate_identity_plan? : CandidateIdentityPlan? = None,
  candidate_mode? : Bool = false,
) -> BytecodeBuilder {
  {
    code: [],
    source_unit,
    source_point_owner,
    owner_allocator,
    source_points: [],
    instruction_sources: [],
    observation_contexts: [],
    active_observation_entries: [],
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
    candidate_identity_plan,
    candidate_mode,
    candidate_child_slot_count: 0,
    candidate_pending_unsupported_child: false,
  }
}

///|
fn BytecodeBuilder::emit(self : BytecodeBuilder, instr : BytecodeInstr) -> Int {
  let idx = self.code.length()
  self.code.push(instr)
  self.instruction_sources.push([])
  self.observation_contexts.push({
    active: self.active_observation_entries.copy(),
  })
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
) -> SourcePointId {
  let source_id = self.allocate_source_point(StatementEntry, loc)
  let _ = self.emit_with_sources(ObserveStatement(source_id), [source_id])
  self.active_observation_entries.push(StatementObservation(source_id))
  source_id
}

///|
fn BytecodeBuilder::emit_expression_observation(
  self : BytecodeBuilder,
  loc : @token.Loc,
) -> SourcePointId {
  let source_id = self.allocate_source_point(ExpressionEntry, loc)
  let _ = self.emit_with_sources(ObserveExpression(source_id), [source_id])
  self.active_observation_entries.push(ExpressionObservation(source_id))
  source_id
}

///|
fn BytecodeBuilder::pop_observation(self : BytecodeBuilder) -> Unit {
  let _ = self.active_observation_entries.pop()
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
