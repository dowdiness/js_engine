///|
#warnings("-unused_constructor")
priv enum BytecodeSourceMetadataInvariant {
  InstructionSourceCount
  SourcePointReference
  SourcePointOwnership
  SourceRoleOrder
  ObservationBarrier
  ObservationSourceIdentity
  NestedSourceUnit
}

///|
#warnings("-unused_constructor")
priv enum BytecodeObservationCoverageInvariant {
  ContextCount
  EdgeCount
  ContextFact
  EdgeFact
  EdgePrefix
  AuthorityIdentity
  AuthorityContext
  AuthoritySuccessor
}

///|
#warnings("-unused_constructor")
priv enum BytecodeObservationCoverageFact {
  CodeLength(Int)
  ObservationContextsLength(Int)
  ObservationEdgeContextsLength(Int)
  ObservationContextDepth(Int)
  ObservationAuthorityLength(Int)
  ObservationAuthoritySuccessor(Int)
}

///|
#warnings("-unused_constructor")
priv enum BytecodeSourceMetadataFact {
  CodeLength(Int)
  InstructionSourcesLength(Int)
  SourcePointIndex(Int)
  SourcePointTableLength(Int)
  SourceUnit(SourceUnitHandle)
  SourcePointOwner(SourcePointOwnerId)
  SourcePointIdentity(SourceUnitHandle, SourcePointOwnerId, Int)
  SourceRoles(Array[SourcePointRole])
  ObservationBarrierKind(BytecodeObservationBarrierKind)
}

///|
#warnings("-unused_constructor")
priv enum BytecodeIndexedOperandFamily {
  ChildFunction
  LocalSlot
  EnvironmentSlot
}

///|
#warnings("-unused_constructor")
priv enum BytecodeShapeOperandFamily {
  ArrayElementCount
  ArrayHoleIndex
  CallArgumentCount
}

///|
#warnings("-unused_field")
priv struct BytecodeSourceMetadataDefect {
  function_path : Array[Int]
  instruction_index : Int?
  invariant : BytecodeSourceMetadataInvariant
  expected : BytecodeSourceMetadataFact
  actual : BytecodeSourceMetadataFact
}

///|
#warnings("-unused_field")
priv struct BytecodeObservationCoverageDefect {
  function_path : Array[Int]
  instruction_index : Int?
  predecessor_index : Int?
  target_index : Int?
  invariant : BytecodeObservationCoverageInvariant
  expected : BytecodeObservationCoverageFact
  actual : BytecodeObservationCoverageFact
}

///|
priv suberror BytecodeVerifierDefect {
  BytecodeVerifierDefect(BytecodeSourceMetadataDefect)
  BytecodeObservationCoverageDefect(BytecodeObservationCoverageDefect)
  BytecodeControlFlowDefect(BytecodeControlFlowTargetDefect)
  BytecodeIndexedOperandDefect(BytecodeIndexedOperandTargetDefect)
  BytecodeShapeOperandDefect(BytecodeShapeOperandTargetDefect)
  BytecodeFrameShapeDefect(BytecodeFrameShapeDefect)
}

///|
#warnings("-unused_field")
priv struct BytecodeShapeOperandTargetDefect {
  function_path : Array[Int]
  instruction_index : Int
  family : BytecodeShapeOperandFamily
  expected_lower_bound : Int
  exclusive_upper_bound : Int?
  actual_operand : Int
}

///|
#warnings("-unused_constructor")
priv enum BytecodeFrameShapeInvariant {
  ResourceUnderflow
  ControlFlowJoin
  TerminalShape
}

///|
#warnings("-unused_field")
priv struct BytecodeAbstractFrameShape {
  operand_stack_height : Int
  argument_list_depth : Int
  for_in_iterator_depth : Int
}

///|
#warnings("-unused_field")
priv struct BytecodeFrameShapeDefect {
  function_path : Array[Int]
  instruction_index : Int
  predecessor_index : Int?
  invariant : BytecodeFrameShapeInvariant
  expected : BytecodeAbstractFrameShape
  actual : BytecodeAbstractFrameShape
}

///|
priv struct BytecodeResourceEffect {
  required_stack_height : Int
  stack_height_delta : Int
  required_argument_list_depth : Int
  argument_list_depth_delta : Int
  required_for_in_iterator_depth : Int
  for_in_iterator_depth_delta : Int
}

///|
priv enum BytecodeInstructionTransfer {
  Fallthrough(BytecodeResourceEffect)
  JumpTo(Int, BytecodeResourceEffect)
  BranchTo(Int, BytecodeResourceEffect)
  SplitTo(Int, BytecodeResourceEffect, BytecodeResourceEffect)
  Terminate(BytecodeResourceEffect)
}

///|
#warnings("-unused_field")
priv struct BytecodeIndexedOperandTargetDefect {
  function_path : Array[Int]
  instruction_index : Int
  family : BytecodeIndexedOperandFamily
  exclusive_upper_bound : Int
  actual_operand : Int
}

///|
#warnings("-unused_field")
priv struct BytecodeControlFlowTargetDefect {
  function_path : Array[Int]
  instruction_index : Int
  expected_lower_bound : Int
  expected_upper_bound : Int
  actual_target : Int
}

///|
fn bytecode_source_metadata_defect(
  function_path : Array[Int],
  instruction_index : Int?,
  invariant : BytecodeSourceMetadataInvariant,
  expected : BytecodeSourceMetadataFact,
  actual : BytecodeSourceMetadataFact,
) -> BytecodeVerifierDefect {
  BytecodeVerifierDefect({
    function_path: function_path.copy(),
    instruction_index,
    invariant,
    expected,
    actual,
  })
}

///|
fn verify_bytecode_source_metadata(
  program : BytecodeUnverifiedProgram,
) -> Unit raise Error {
  let _ = verify_bytecode_function_source_metadata(
    program.main,
    program.main.source_unit,
    [],
    0,
  )
}

///|
fn bytecode_stack_effect(
  required_stack_height : Int,
  stack_height_delta : Int,
) -> BytecodeResourceEffect {
  {
    required_stack_height,
    stack_height_delta,
    required_argument_list_depth: 0,
    argument_list_depth_delta: 0,
    required_for_in_iterator_depth: 0,
    for_in_iterator_depth_delta: 0,
  }
}

///|
fn bytecode_argument_list_effect(
  required_stack_height : Int,
  stack_height_delta : Int,
  required_argument_list_depth : Int,
  argument_list_depth_delta : Int,
) -> BytecodeResourceEffect {
  {
    required_stack_height,
    stack_height_delta,
    required_argument_list_depth,
    argument_list_depth_delta,
    required_for_in_iterator_depth: 0,
    for_in_iterator_depth_delta: 0,
  }
}

///|
fn bytecode_for_in_effect(
  required_stack_height : Int,
  stack_height_delta : Int,
  required_for_in_iterator_depth : Int,
  for_in_iterator_depth_delta : Int,
) -> BytecodeResourceEffect {
  {
    required_stack_height,
    stack_height_delta,
    required_argument_list_depth: 0,
    argument_list_depth_delta: 0,
    required_for_in_iterator_depth,
    for_in_iterator_depth_delta,
  }
}

///|
fn bytecode_instruction_transfer(
  instruction : BytecodeInstr,
) -> BytecodeInstructionTransfer {
  // Keep this match exhaustive: a new opcode must declare its resource effect
  // and successor shape before the program can finalize.
  match instruction {
    ObserveStatement(_)
    | ObserveExpression(_)
    | SetCompletionValue(_)
    | BeginOptionalChain
    | MarkOptionalChainShortCircuit
    | EndOptionalChain
    | DeclareFunction(_, _) => Fallthrough(bytecode_stack_effect(0, 0))
    LoadConst(_)
    | LoadUndefined
    | LoadThis
    | LoadNewTarget
    | LoadSuperProperty(_, _)
    | LoadConsoleMember(_)
    | LoadDirectEvalCallee
    | LoadName(_)
    | LoadAssignmentName(_)
    | LoadLocal(_)
    | LoadEnvSlot(_)
    | TypeofName(_)
    | DeleteName(_)
    | MakeTemplateObject(_)
    | MakeRegExp(_, _)
    | UpdateName(_, _, _, _)
    | UpdateLocal(_, _, _)
    | UpdateEnvSlot(_, _, _)
    | StartArray
    | StartObject
    | MakeFunction(_)
    | MakeNamedFunction(_, _)
    | MakeArrowFunction(_) => Fallthrough(bytecode_stack_effect(0, 1))
    LoadSuperComputed(_)
    | StoreName(_)
    | StoreLocal(_)
    | StoreEnvSlot(_)
    | UnaryValueOp(_, _)
    | DeleteProperty(_)
    | SetFunctionName(_)
    | ToObjectLiteralPropertyKey
    | AssignDestructure(_) => Fallthrough(bytecode_stack_effect(1, 0))
    DefineBinding(_, _, _)
    | DefineLocal(_, _)
    | DefineEnvSlot(_, _)
    | SetCompletion
    | Pop => Fallthrough(bytecode_stack_effect(1, -1))
    Dup => Fallthrough(bytecode_stack_effect(1, 1))
    BinaryOp(_, _) | DeleteComputed | AppendTemplate(_) =>
      Fallthrough(bytecode_stack_effect(2, -1))
    UpdateProperty(_, _, _, _, _) => Fallthrough(bytecode_stack_effect(1, 0))
    UpdateComputed(_, _, _, _) => Fallthrough(bytecode_stack_effect(2, -1))
    Jump(target) => JumpTo(target, bytecode_stack_effect(0, 0))
    JumpIfFalse(target) => BranchTo(target, bytecode_stack_effect(1, -1))
    JumpIfFalseKeep(target)
    | JumpIfTrueKeep(target)
    | JumpIfNotNullishKeep(target) =>
      BranchTo(target, bytecode_stack_effect(1, 0))
    JumpIfNotOptionalChainShortCircuitKeep(target) =>
      BranchTo(target, bytecode_stack_effect(0, 0))
    StartForIn => Fallthrough(bytecode_for_in_effect(1, -1, 0, 1))
    ForInNext(target) =>
      SplitTo(
        target,
        bytecode_for_in_effect(0, 0, 1, -1),
        bytecode_for_in_effect(0, 1, 1, 0),
      )
    EndForIn => Fallthrough(bytecode_for_in_effect(0, 0, 1, -1))
    MakeArray(count) | MakeArrayWithHoles(count, _) =>
      Fallthrough(bytecode_stack_effect(count, 1 - count))
    ArrayPushValue | ArrayPushSpread(_) =>
      Fallthrough(bytecode_stack_effect(2, -1))
    ArrayPushHole => Fallthrough(bytecode_stack_effect(1, 0))
    StartArgs => Fallthrough(bytecode_argument_list_effect(0, 0, 0, 1))
    ArgPushValue | ArgPushSpread(_) =>
      Fallthrough(bytecode_argument_list_effect(1, -1, 1, 0))
    MakeObject(keys) =>
      Fallthrough(bytecode_stack_effect(keys.length(), 1 - keys.length()))
    ObjectSetStatic(_)
    | ObjectSetStaticGetter(_)
    | ObjectSetStaticSetter(_)
    | ObjectSpread(_)
    | ObjectSetProto => Fallthrough(bytecode_stack_effect(2, -1))
    ObjectSetComputedGetter | ObjectSetComputedSetter | ObjectSetComputed =>
      Fallthrough(bytecode_stack_effect(3, -2))
    MakeMethodFunction(_) => Fallthrough(bytecode_stack_effect(1, 1))
    MakeComputedMethodFunction(_) => Fallthrough(bytecode_stack_effect(2, 1))
    GetProperty(_, _) => Fallthrough(bytecode_stack_effect(1, 0))
    GetComputed(_) => Fallthrough(bytecode_stack_effect(2, -1))
    ReadPropertyForAssign(_, _) => Fallthrough(bytecode_stack_effect(1, 1))
    ReadComputedForAssign(_) => Fallthrough(bytecode_stack_effect(2, 1))
    DropPropertyAssignReference => Fallthrough(bytecode_stack_effect(2, -1))
    DropComputedAssignReference => Fallthrough(bytecode_stack_effect(3, -2))
    SetProperty(_, _) | SetForInProperty(_, _) =>
      Fallthrough(bytecode_stack_effect(2, -1))
    SetComputed(_) | SetForInComputed(_) =>
      Fallthrough(bytecode_stack_effect(3, -2))
    PreparePropertyCall(_, _) | PreparePlainPropertyCall(_, _) =>
      Fallthrough(bytecode_stack_effect(1, 1))
    PrepareComputedCall(_) => Fallthrough(bytecode_stack_effect(2, 0))
    PrepareSuperPropertyCall(_, _) => Fallthrough(bytecode_stack_effect(0, 2))
    PrepareSuperComputedCall(_) => Fallthrough(bytecode_stack_effect(1, 1))
    CallDirectEval(_) | CallSpread(_) | ConstructSpread(_) =>
      Fallthrough(bytecode_argument_list_effect(1, 0, 1, -1))
    Call(argument_count, _) | Construct(argument_count, _) =>
      Fallthrough(bytecode_stack_effect(argument_count + 1, -argument_count))
    CallWithReceiver(argument_count, _) =>
      Fallthrough(
        bytecode_stack_effect(argument_count + 2, -argument_count - 1),
      )
    CallSpreadWithReceiver(_) =>
      Fallthrough(bytecode_argument_list_effect(2, -1, 1, -1))
    Return | Throw => Terminate(bytecode_stack_effect(1, -1))
  }
}

///|
fn bytecode_observation_context_empty() -> BytecodeObservationContext {
  { active: [] }
}

///|
fn bytecode_observation_authority_context_entries_equal(
  actual : BytecodeObservationContext,
  expected : BytecodeObservationAuthorityContextEntries,
) -> Bool {
  let mut index = 0
  let mut remaining = expected
  let mut equal = false
  let mut done = false
  while !done {
    match remaining {
      EmptyObservationAuthorityContext => {
        equal = index == actual.active.length()
        done = true
      }
      MoreObservationAuthorityContext(entry, tail) =>
        if index >= actual.active.length() || actual.active[index] != entry {
          done = true
        } else {
          index += 1
          remaining = tail
        }
    }
  }
  equal
}

///|
fn bytecode_observation_authority_successors_equal(
  actual : BytecodeObservationAuthoritySuccessors,
  expected : BytecodeObservationAuthoritySuccessors,
) -> Bool {
  let mut actual_remaining = actual
  let mut expected_remaining = expected
  let mut equal = false
  let mut done = false
  while !done {
    match (actual_remaining, expected_remaining) {
      (EmptyObservationAuthoritySuccessors, EmptyObservationAuthoritySuccessors) => {
        equal = true
        done = true
      }
      (
        MoreObservationAuthoritySuccessors(actual_target, actual_tail),
        MoreObservationAuthoritySuccessors(expected_target, expected_tail),
      ) =>
        if actual_target != expected_target {
          done = true
        } else {
          actual_remaining = actual_tail
          expected_remaining = expected_tail
        }
      _ => done = true
    }
  }
  equal
}

///|
fn verify_bytecode_observation_authority(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  let authority = function.observation_authority
  guard physical_equal(
      authority.program_identity,
      function.source_identity.program_identity,
    ) &&
    authority.source_point_owner == function.source_point_owner else {
    raise bytecode_observation_coverage_defect(
      function_path,
      None,
      None,
      None,
      AuthorityIdentity,
      ObservationAuthorityLength(function.code.length()),
      ObservationAuthorityLength(authority.code_length),
    )
  }
  guard authority.code_length == function.code.length() else {
    raise bytecode_observation_coverage_defect(
      function_path,
      None,
      None,
      None,
      AuthorityIdentity,
      ObservationAuthorityLength(function.code.length()),
      ObservationAuthorityLength(authority.code_length),
    )
  }
  let mut remaining = authority.instructions
  for instruction_index, context in function.observation_contexts {
    match remaining {
      MoreObservationAuthorityInstructions(fact, tail) => {
        guard bytecode_observation_authority_context_entries_equal(
          context,
          fact.context,
        ) else {
          raise bytecode_observation_coverage_defect(
            function_path,
            Some(instruction_index),
            None,
            None,
            AuthorityContext,
            ObservationContextDepth(context.active.length()),
            ObservationContextDepth(context.active.length()),
          )
        }
        let actual_successors = bytecode_observation_authority_successors(
          bytecode_instruction_transfer(function.code[instruction_index]),
          instruction_index,
        )
        guard bytecode_observation_authority_successors_equal(
          actual_successors,
          fact.successors,
        ) else {
          raise bytecode_observation_coverage_defect(
            function_path,
            Some(instruction_index),
            Some(instruction_index),
            None,
            AuthoritySuccessor,
            ObservationAuthoritySuccessor(instruction_index),
            ObservationAuthoritySuccessor(instruction_index),
          )
        }
        remaining = tail
      }
      EmptyObservationAuthorityInstructions =>
        raise bytecode_observation_coverage_defect(
          function_path,
          Some(instruction_index),
          None,
          None,
          AuthorityIdentity,
          ObservationAuthorityLength(function.code.length()),
          ObservationAuthorityLength(instruction_index),
        )
    }
  }
  match remaining {
    EmptyObservationAuthorityInstructions => ()
    MoreObservationAuthorityInstructions(_, _) =>
      raise bytecode_observation_coverage_defect(
        function_path,
        None,
        None,
        None,
        AuthorityIdentity,
        ObservationAuthorityLength(function.code.length()),
        ObservationAuthorityLength(function.observation_contexts.length()),
      )
  }
}

///|
fn bytecode_observation_contexts_equal(
  left : BytecodeObservationContext,
  right : BytecodeObservationContext,
) -> Bool {
  guard left.active.length() == right.active.length() else { return false }
  for index in 0..<left.active.length() {
    if left.active[index] != right.active[index] {
      return false
    }
  }
  true
}

///|
fn bytecode_observation_context_is_prefix(
  prefix : BytecodeObservationContext,
  context : BytecodeObservationContext,
) -> Bool {
  guard prefix.active.length() <= context.active.length() else { return false }
  for index in 0..<prefix.active.length() {
    if prefix.active[index] != context.active[index] {
      return false
    }
  }
  true
}

///|
fn bytecode_observation_context_after(
  context : BytecodeObservationContext,
  instruction : BytecodeInstr,
) -> BytecodeObservationContext {
  match instruction {
    ObserveStatement(source_id) => {
      let active = context.active.copy()
      active.push(StatementObservation(source_id))
      { active, }
    }
    ObserveExpression(source_id) => {
      let active = context.active.copy()
      active.push(ExpressionObservation(source_id))
      { active, }
    }
    _ => context
  }
}

///|
fn bytecode_observation_entry_source_id(
  entry : BytecodeObservationContextEntry,
) -> SourcePointId {
  match entry {
    StatementObservation(source_id) | ExpressionObservation(source_id) =>
      source_id
  }
}

///|
fn bytecode_observation_entry_role(
  entry : BytecodeObservationContextEntry,
) -> SourcePointRole {
  match entry {
    StatementObservation(_) => StatementEntry
    ExpressionObservation(_) => ExpressionEntry
  }
}

///|
fn bytecode_observation_entry_matches_barrier(
  function : BytecodeFunction,
  entry : BytecodeObservationContextEntry,
) -> Bool {
  for instruction in function.code {
    match (entry, instruction) {
      (StatementObservation(expected), ObserveStatement(actual))
      | (ExpressionObservation(expected), ObserveExpression(actual)) =>
        if expected == actual {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn verify_bytecode_observation_entry(
  function : BytecodeFunction,
  entry : BytecodeObservationContextEntry,
  function_path : Array[Int],
  instruction_index : Int,
) -> Unit raise Error {
  let source_id = bytecode_observation_entry_source_id(entry)
  let expected_role = bytecode_observation_entry_role(entry)
  let _ = verify_source_point_reference(
    function,
    source_id,
    Some(expected_role),
    function_path,
    Some(instruction_index),
  )
  guard bytecode_observation_entry_matches_barrier(function, entry) else {
    raise bytecode_observation_coverage_defect(
      function_path,
      Some(instruction_index),
      None,
      None,
      ContextFact,
      ObservationContextDepth(1),
      ObservationContextDepth(0),
    )
  }
}

///|
fn bytecode_observation_coverage_defect(
  function_path : Array[Int],
  instruction_index : Int?,
  predecessor_index : Int?,
  target_index : Int?,
  invariant : BytecodeObservationCoverageInvariant,
  expected : BytecodeObservationCoverageFact,
  actual : BytecodeObservationCoverageFact,
) -> BytecodeVerifierDefect {
  BytecodeObservationCoverageDefect({
    function_path: function_path.copy(),
    instruction_index,
    predecessor_index,
    target_index,
    invariant,
    expected,
    actual,
  })
}

///|
fn bytecode_observation_context_for_target(
  function : BytecodeFunction,
  target : Int,
) -> BytecodeObservationContext {
  if target == function.code.length() {
    bytecode_observation_context_empty()
  } else {
    function.observation_contexts[target]
  }
}

///|
fn bytecode_observation_transfer_has_successor(
  transfer : BytecodeInstructionTransfer,
  instruction_index : Int,
  target : Int,
) -> Bool {
  match transfer {
    Fallthrough(_) => target == instruction_index + 1
    JumpTo(actual, _) => target == actual
    BranchTo(actual, _) => target == actual || target == instruction_index + 1
    SplitTo(actual, _, _) => target == actual || target == instruction_index + 1
    Terminate(_) => false
  }
}

///|
fn bytecode_observation_edge_context_for_target(
  function : BytecodeFunction,
  instruction_index : Int,
  target : Int,
) -> BytecodeObservationContext? {
  let mut found : BytecodeObservationContext? = None
  for edge in function.observation_edge_contexts[instruction_index] {
    if edge.successor == target {
      match found {
        None => found = Some(edge.context)
        Some(_) => ()
      }
    }
  }
  found
}

///|
fn require_bytecode_observation_edge_context(
  function : BytecodeFunction,
  instruction_index : Int,
  target : Int,
  source_post_context : BytecodeObservationContext,
  function_path : Array[Int],
) -> BytecodeObservationContext raise Error {
  match
    bytecode_observation_edge_context_for_target(
      function, instruction_index, target,
    ) {
    Some(context) => context
    None =>
      raise bytecode_observation_coverage_defect(
        function_path,
        Some(instruction_index),
        Some(instruction_index),
        Some(target),
        EdgeFact,
        ObservationContextDepth(source_post_context.active.length()),
        ObservationContextDepth(0),
      )
  }
}

///|
fn verify_bytecode_observation_edge_facts(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  for instruction_index, edges in function.observation_edge_contexts {
    let transfer = bytecode_instruction_transfer(
      function.code[instruction_index],
    )
    for edge in edges {
      guard edge.successor >= 0 && edge.successor <= function.code.length() else {
        raise bytecode_observation_coverage_defect(
          function_path,
          Some(instruction_index),
          Some(instruction_index),
          Some(edge.successor),
          EdgeFact,
          CodeLength(function.code.length()),
          ObservationContextDepth(edge.successor),
        )
      }
      guard bytecode_observation_transfer_has_successor(
        transfer,
        instruction_index,
        edge.successor,
      ) else {
        raise bytecode_observation_coverage_defect(
          function_path,
          Some(instruction_index),
          Some(instruction_index),
          Some(edge.successor),
          EdgeFact,
          ObservationContextDepth(instruction_index + 1),
          ObservationContextDepth(edge.successor),
        )
      }
      let target_context = bytecode_observation_context_for_target(
        function,
        edge.successor,
      )
      guard bytecode_observation_contexts_equal(edge.context, target_context) else {
        raise bytecode_observation_coverage_defect(
          function_path,
          Some(instruction_index),
          Some(instruction_index),
          Some(edge.successor),
          EdgeFact,
          ObservationContextDepth(target_context.active.length()),
          ObservationContextDepth(edge.context.active.length()),
        )
      }
    }
  }
}

///|
fn record_bytecode_observation_context(
  function : BytecodeFunction,
  states : Array[BytecodeObservationContext?],
  worklist : Array[Int],
  target : Int,
  expected_context : BytecodeObservationContext,
  source_post_context : BytecodeObservationContext,
  function_path : Array[Int],
  predecessor_index : Int,
) -> Unit raise Error {
  let target_context = bytecode_observation_context_for_target(function, target)
  guard bytecode_observation_context_is_prefix(
    target_context, source_post_context,
  ) else {
    raise bytecode_observation_coverage_defect(
      function_path,
      Some(target),
      Some(predecessor_index),
      Some(target),
      EdgePrefix,
      ObservationContextDepth(source_post_context.active.length()),
      ObservationContextDepth(target_context.active.length()),
    )
  }
  guard bytecode_observation_contexts_equal(target_context, expected_context) else {
    raise bytecode_observation_coverage_defect(
      function_path,
      Some(predecessor_index),
      Some(predecessor_index),
      Some(target),
      ContextFact,
      ObservationContextDepth(expected_context.active.length()),
      ObservationContextDepth(target_context.active.length()),
    )
  }
  match states[target] {
    None => {
      states[target] = Some(expected_context)
      worklist.push(target)
    }
    Some(existing_context) => {
      guard bytecode_observation_contexts_equal(
        existing_context, expected_context,
      ) else {
        raise bytecode_observation_coverage_defect(
          function_path,
          Some(target),
          Some(predecessor_index),
          Some(target),
          ContextFact,
          ObservationContextDepth(existing_context.active.length()),
          ObservationContextDepth(expected_context.active.length()),
        )
      }
    }
  }
}

///|
fn verify_bytecode_observation_coverage(
  program : BytecodeUnverifiedProgram,
) -> Unit raise Error {
  verify_bytecode_function_observation_coverage(program.main, [])
}

///|
fn verify_bytecode_function_observation_coverage(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  let code_length = function.code.length()
  guard function.observation_contexts.length() == code_length else {
    raise bytecode_observation_coverage_defect(
      function_path,
      None,
      None,
      None,
      ContextCount,
      CodeLength(code_length),
      ObservationContextsLength(function.observation_contexts.length()),
    )
  }
  guard function.observation_edge_contexts.length() == code_length else {
    raise bytecode_observation_coverage_defect(
      function_path,
      None,
      None,
      None,
      EdgeCount,
      CodeLength(code_length),
      ObservationEdgeContextsLength(function.observation_edge_contexts.length()),
    )
  }
  verify_bytecode_observation_authority(function, function_path)
  for instruction_index, context in function.observation_contexts {
    for entry in context.active {
      verify_bytecode_observation_entry(
        function, entry, function_path, instruction_index,
      )
    }
  }
  verify_bytecode_observation_edge_facts(function, function_path)
  let states : Array[BytecodeObservationContext?] = Array::make(
    code_length + 1,
    None,
  )
  states[0] = Some(bytecode_observation_context_empty())
  let worklist = [0]
  while worklist.length() > 0 {
    let instruction_index = worklist.pop().unwrap()
    let state = states[instruction_index].unwrap()
    if instruction_index == code_length {
      continue
    }
    let recorded_context = function.observation_contexts[instruction_index]
    guard bytecode_observation_contexts_equal(state, recorded_context) else {
      raise bytecode_observation_coverage_defect(
        function_path,
        Some(instruction_index),
        None,
        None,
        ContextFact,
        ObservationContextDepth(state.active.length()),
        ObservationContextDepth(recorded_context.active.length()),
      )
    }
    let source_post_context = bytecode_observation_context_after(
      recorded_context,
      function.code[instruction_index],
    )
    let transfer = bytecode_instruction_transfer(
      function.code[instruction_index],
    )
    let expected_context_for = target => {
      match
        bytecode_observation_edge_context_for_target(
          function, instruction_index, target,
        ) {
        Some(context) => context
        None => source_post_context
      }
    }
    match transfer {
      Fallthrough(_) => {
        let target = instruction_index + 1
        record_bytecode_observation_context(
          function,
          states,
          worklist,
          target,
          expected_context_for(target),
          source_post_context,
          function_path,
          instruction_index,
        )
      }
      JumpTo(target, _) => {
        let expected_context = require_bytecode_observation_edge_context(
          function, instruction_index, target, source_post_context, function_path,
        )
        record_bytecode_observation_context(
          function, states, worklist, target, expected_context, source_post_context,
          function_path, instruction_index,
        )
      }
      BranchTo(target, _) => {
        let expected_context = require_bytecode_observation_edge_context(
          function, instruction_index, target, source_post_context, function_path,
        )
        record_bytecode_observation_context(
          function, states, worklist, target, expected_context, source_post_context,
          function_path, instruction_index,
        )
        let fallthrough = instruction_index + 1
        record_bytecode_observation_context(
          function,
          states,
          worklist,
          fallthrough,
          expected_context_for(fallthrough),
          source_post_context,
          function_path,
          instruction_index,
        )
      }
      SplitTo(target, _, _) => {
        let expected_context = require_bytecode_observation_edge_context(
          function, instruction_index, target, source_post_context, function_path,
        )
        record_bytecode_observation_context(
          function, states, worklist, target, expected_context, source_post_context,
          function_path, instruction_index,
        )
        let fallthrough = instruction_index + 1
        record_bytecode_observation_context(
          function,
          states,
          worklist,
          fallthrough,
          expected_context_for(fallthrough),
          source_post_context,
          function_path,
          instruction_index,
        )
      }
      Terminate(_) => ()
    }
  }
  for child_index, child in function.children {
    let child_path = function_path.copy()
    child_path.push(child_index)
    verify_bytecode_function_observation_coverage(child, child_path)
  }
}

///|
fn bytecode_abstract_frame_shape(
  operand_stack_height : Int,
  argument_list_depth : Int,
  for_in_iterator_depth : Int,
) -> BytecodeAbstractFrameShape {
  { operand_stack_height, argument_list_depth, for_in_iterator_depth }
}

///|
fn bytecode_frame_shapes_equal(
  left : BytecodeAbstractFrameShape,
  right : BytecodeAbstractFrameShape,
) -> Bool {
  left.operand_stack_height == right.operand_stack_height &&
  left.argument_list_depth == right.argument_list_depth &&
  left.for_in_iterator_depth == right.for_in_iterator_depth
}

///|
fn bytecode_frame_shape_defect(
  function_path : Array[Int],
  instruction_index : Int,
  predecessor_index : Int?,
  invariant : BytecodeFrameShapeInvariant,
  expected : BytecodeAbstractFrameShape,
  actual : BytecodeAbstractFrameShape,
) -> BytecodeVerifierDefect {
  BytecodeFrameShapeDefect({
    function_path: function_path.copy(),
    instruction_index,
    predecessor_index,
    invariant,
    expected,
    actual,
  })
}

///|
fn apply_bytecode_resource_effect(
  state : BytecodeAbstractFrameShape,
  effect : BytecodeResourceEffect,
  function_path : Array[Int],
  instruction_index : Int,
) -> BytecodeAbstractFrameShape raise Error {
  let required = bytecode_abstract_frame_shape(
    effect.required_stack_height,
    effect.required_argument_list_depth,
    effect.required_for_in_iterator_depth,
  )
  guard state.operand_stack_height >= effect.required_stack_height &&
    state.argument_list_depth >= effect.required_argument_list_depth &&
    state.for_in_iterator_depth >= effect.required_for_in_iterator_depth else {
    raise bytecode_frame_shape_defect(
      function_path,
      instruction_index,
      None,
      ResourceUnderflow,
      required,
      state,
    )
  }
  bytecode_abstract_frame_shape(
    state.operand_stack_height + effect.stack_height_delta,
    state.argument_list_depth + effect.argument_list_depth_delta,
    state.for_in_iterator_depth + effect.for_in_iterator_depth_delta,
  )
}

///|
fn record_bytecode_frame_shape(
  states : Array[BytecodeAbstractFrameShape?],
  worklist : Array[Int],
  target : Int,
  incoming : BytecodeAbstractFrameShape,
  function_path : Array[Int],
  predecessor_index : Int,
) -> Unit raise Error {
  match states[target] {
    None => {
      states[target] = Some(incoming)
      worklist.push(target)
    }
    Some(expected) => {
      guard bytecode_frame_shapes_equal(expected, incoming) else {
        raise bytecode_frame_shape_defect(
          function_path,
          target,
          Some(predecessor_index),
          ControlFlowJoin,
          expected,
          incoming,
        )
      }
    }
  }
}

///|
fn verify_bytecode_terminal_shape(
  state : BytecodeAbstractFrameShape,
  function_path : Array[Int],
  instruction_index : Int,
  predecessor_index : Int?,
) -> Unit raise Error {
  let expected = bytecode_abstract_frame_shape(0, 0, 0)
  guard bytecode_frame_shapes_equal(expected, state) else {
    raise bytecode_frame_shape_defect(
      function_path,
      instruction_index,
      predecessor_index,
      TerminalShape,
      expected,
      state,
    )
  }
}

///|
fn verify_bytecode_terminator_shape(
  state : BytecodeAbstractFrameShape,
  function_path : Array[Int],
  instruction_index : Int,
) -> Unit raise Error {
  guard state.operand_stack_height == 0 else {
    raise bytecode_frame_shape_defect(
      function_path,
      instruction_index,
      Some(instruction_index),
      TerminalShape,
      bytecode_abstract_frame_shape(
        0,
        state.argument_list_depth,
        state.for_in_iterator_depth,
      ),
      state,
    )
  }
}

///|
fn verify_bytecode_frame_shapes(
  program : BytecodeUnverifiedProgram,
) -> Unit raise Error {
  verify_bytecode_function_frame_shapes(program.main, [])
}

///|
fn verify_bytecode_function_frame_shapes(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  let code_length = function.code.length()
  let states : Array[BytecodeAbstractFrameShape?] = Array::make(
    code_length + 1,
    None,
  )
  states[0] = Some(bytecode_abstract_frame_shape(0, 0, 0))
  let worklist = [0]
  while worklist.length() > 0 {
    let instruction_index = worklist.pop().unwrap()
    let state = states[instruction_index].unwrap()
    if instruction_index == code_length {
      continue
    }
    match bytecode_instruction_transfer(function.code[instruction_index]) {
      Fallthrough(effect) => {
        let next = apply_bytecode_resource_effect(
          state, effect, function_path, instruction_index,
        )
        record_bytecode_frame_shape(
          states,
          worklist,
          instruction_index + 1,
          next,
          function_path,
          instruction_index,
        )
      }
      JumpTo(target, effect) => {
        let next = apply_bytecode_resource_effect(
          state, effect, function_path, instruction_index,
        )
        record_bytecode_frame_shape(
          states, worklist, target, next, function_path, instruction_index,
        )
      }
      BranchTo(target, effect) => {
        let next = apply_bytecode_resource_effect(
          state, effect, function_path, instruction_index,
        )
        record_bytecode_frame_shape(
          states, worklist, target, next, function_path, instruction_index,
        )
        record_bytecode_frame_shape(
          states,
          worklist,
          instruction_index + 1,
          next,
          function_path,
          instruction_index,
        )
      }
      SplitTo(target, target_effect, fallthrough_effect) => {
        let target_state = apply_bytecode_resource_effect(
          state, target_effect, function_path, instruction_index,
        )
        let fallthrough_state = apply_bytecode_resource_effect(
          state, fallthrough_effect, function_path, instruction_index,
        )
        record_bytecode_frame_shape(
          states, worklist, target, target_state, function_path, instruction_index,
        )
        record_bytecode_frame_shape(
          states,
          worklist,
          instruction_index + 1,
          fallthrough_state,
          function_path,
          instruction_index,
        )
      }
      Terminate(effect) => {
        let terminal = apply_bytecode_resource_effect(
          state, effect, function_path, instruction_index,
        )
        verify_bytecode_terminator_shape(
          terminal, function_path, instruction_index,
        )
      }
    }
  }
  match states[code_length] {
    Some(terminal_state) =>
      verify_bytecode_terminal_shape(
        terminal_state,
        function_path,
        code_length,
        None,
      )
    None => ()
  }
  for child_index, child in function.children {
    let child_path = function_path.copy()
    child_path.push(child_index)
    verify_bytecode_function_frame_shapes(child, child_path)
  }
}

///|
// The runtime entry receives only this immutable setup envelope.  Rebuild the
// lowering facts at the compiler boundary so a mutation of the root plan
// cannot diverge from the verified main function.
fn bytecode_root_signature_facts_equal(
  left : BytecodeSignatureValidation?,
  right : BytecodeSignatureValidation?,
) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(left), Some(right)) => bytecode_signature_facts_equal(left, right)
    _ => false
  }
}

///|
fn bytecode_root_preparation_equal(
  left : BytecodePreparation,
  right : BytecodePreparation,
) -> Bool {
  if left.lexical_bindings.length() != right.lexical_bindings.length() ||
    left.function_declarations.length() != right.function_declarations.length() ||
    !bytecode_root_signature_facts_equal(
      left.signature_validation,
      right.signature_validation,
    ) ||
    !@runtime.executor_activation_capability_summary_equal(
      left.activation_capability,
      right.activation_capability,
    ) {
    return false
  }
  for index in 0..<left.lexical_bindings.length() {
    let actual = left.lexical_bindings[index]
    let expected = right.lexical_bindings[index]
    if !bytecode_lexical_kind_equal_for_verification(actual.kind, expected.kind) ||
      actual.name != expected.name ||
      actual.loc != expected.loc {
      return false
    }
  }
  for index in 0..<left.function_declarations.length() {
    let actual = left.function_declarations[index]
    let expected = right.function_declarations[index]
    if actual.name != expected.name ||
      actual.child_index != expected.child_index ||
      actual.loc != expected.loc ||
      !bytecode_source_identity_equal(
        actual.source_identity,
        expected.source_identity,
      ) {
      return false
    }
  }
  true
}

///|
fn verify_bytecode_root_provenance(
  program : BytecodeUnverifiedProgram,
) -> Unit raise Error {
  let main = program.main
  let provenance = program.root_provenance
  guard main.name == provenance.name &&
    main.signature_name == provenance.signature_name &&
    main.enclosing_strict == provenance.enclosing_strict &&
    Array::equal(main.params, provenance.params) &&
    main.rest_param == provenance.rest_param &&
    main.body_has_use_strict == provenance.body_has_use_strict &&
    physical_equal(
      main.source_identity.program_identity,
      provenance.program_identity,
    ) &&
    bytecode_source_identity_equal(
      main.source_identity,
      provenance.source_identity,
    ) &&
    main.activation_kind == provenance.activation_kind &&
    Array::equal(main.env_var_hoist_names, provenance.env_var_hoist_names) &&
    bytecode_root_preparation_equal(main.preparation, provenance.preparation) else {
    raise @errors.InternalError(
      message="bytecode root lowering provenance does not match current facts",
    )
  }
}

///|
fn compiled_script_lexical_bindings_from_main_for_verification(
  main : BytecodeFunction,
) -> Array[@runtime.CompiledScriptLexicalBinding] {
  main.preparation.lexical_bindings.map(binding => {
    let kind = match binding.kind {
      BytecodeLet => @runtime.LetBinding
      BytecodeConst => @runtime.ConstBinding
    }
    @runtime.CompiledScriptLexicalBinding(kind~, name=binding.name)
  })
}

///|
fn compiled_script_preparation_from_root_provenance_for_verification(
  provenance : BytecodeRootScriptProvenance,
) -> @runtime.CompiledScriptPreparation {
  @runtime.CompiledScriptPreparation::with_early_error_settlement(
    strict=provenance.strict,
    var_names=provenance.var_names,
    function_names=provenance.function_names,
    lexical_bindings=provenance.lexical_bindings,
    settlement=provenance.settlement,
  )
}

///|
fn verify_compiled_script_preparation(
  program : BytecodeUnverifiedProgram,
) -> Unit raise Error {
  verify_bytecode_root_provenance(program)
  let main = program.main
  let provenance = program.root_provenance
  let expected_strict = main.enclosing_strict || main.body_has_use_strict
  let expected_var_names = main.env_var_hoist_names
  let expected_function_names = main.preparation.function_declarations.map(declaration => {
    declaration.name
  })
  let expected_lexical_bindings = compiled_script_lexical_bindings_from_main_for_verification(
    main,
  )
  guard @runtime.compiled_script_preparation_matches(
    compiled_script_preparation_from_root_provenance_for_verification(
      provenance,
    ),
    expected_strict,
    expected_var_names,
    expected_function_names,
    expected_lexical_bindings,
    provenance.settlement,
    provenance_token=Some(main.source_identity.program_identity),
  ) else {
    raise @errors.InternalError(
      message="root script provenance does not match verified main facts",
    )
  }
  guard @runtime.compiled_script_preparation_matches(
    program.script_preparation,
    expected_strict,
    expected_var_names,
    expected_function_names,
    expected_lexical_bindings,
    provenance.settlement,
    provenance_token=Some(main.source_identity.program_identity),
  ) else {
    raise @errors.InternalError(
      message="compiled script preparation does not match verified root facts",
    )
  }
}

///|
fn finalize_bytecode_program(
  program : BytecodeUnverifiedProgram,
) -> BytecodeProgram raise Error {
  verify_compiled_script_preparation(program)
  verify_bytecode_source_metadata(program)
  verify_bytecode_preparation(program.main, [])
  verify_bytecode_control_flow(program)
  verify_bytecode_observation_coverage(program)
  verify_bytecode_indexed_operands(program)
  verify_bytecode_shape_operands(program)
  verify_bytecode_frame_shapes(program)
  let verified_main = make_verified_bytecode_function(program.main)
  { script_preparation: program.script_preparation, verified_main }
}

///|
fn make_verified_bytecode_function(
  function : BytecodeFunction,
) -> VerifiedBytecodeFunction {
  { function, preparation: function.preparation }
}

///|
fn bytecode_shape_operand_defect(
  function_path : Array[Int],
  instruction_index : Int,
  family : BytecodeShapeOperandFamily,
  exclusive_upper_bound : Int?,
  actual_operand : Int,
) -> BytecodeVerifierDefect {
  BytecodeShapeOperandDefect({
    function_path: function_path.copy(),
    instruction_index,
    family,
    expected_lower_bound: 0,
    exclusive_upper_bound,
    actual_operand,
  })
}

///|
fn verify_bytecode_shape_operands(
  program : BytecodeUnverifiedProgram,
) -> Unit raise Error {
  verify_bytecode_function_shape_operands(program.main, [])
}

///|
fn verify_bytecode_function_shape_operands(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  let maximum_shape_count = function.code.length()
  let shape_count_exclusive_upper_bound = maximum_shape_count + 1
  for instruction_index, instruction in function.code {
    match instruction {
      MakeArray(count) => {
        guard count >= 0 && count <= maximum_shape_count else {
          raise bytecode_shape_operand_defect(
            function_path,
            instruction_index,
            ArrayElementCount,
            Some(shape_count_exclusive_upper_bound),
            count,
          )
        }
      }
      MakeArrayWithHoles(count, hole_indices) => {
        guard count >= 0 && count <= maximum_shape_count else {
          raise bytecode_shape_operand_defect(
            function_path,
            instruction_index,
            ArrayElementCount,
            Some(shape_count_exclusive_upper_bound),
            count,
          )
        }
        for hole_index in hole_indices {
          guard hole_index >= 0 && hole_index < count else {
            raise bytecode_shape_operand_defect(
              function_path,
              instruction_index,
              ArrayHoleIndex,
              Some(count),
              hole_index,
            )
          }
        }
      }
      Call(argument_count, _)
      | CallWithReceiver(argument_count, _)
      | Construct(argument_count, _) => {
        guard argument_count >= 0 && argument_count <= maximum_shape_count else {
          raise bytecode_shape_operand_defect(
            function_path,
            instruction_index,
            CallArgumentCount,
            Some(shape_count_exclusive_upper_bound),
            argument_count,
          )
        }
      }
      _ => ()
    }
  }
  for child_index, child in function.children {
    let child_path = function_path.copy()
    child_path.push(child_index)
    verify_bytecode_function_shape_operands(child, child_path)
  }
}

///|
fn bytecode_indexed_operand(
  instruction : BytecodeInstr,
) -> (BytecodeIndexedOperandFamily, Int)? {
  // Keep this match exhaustive so every new instruction must declare whether
  // it owns a verifier-checked table index.
  match instruction {
    MakeFunction(index)
    | MakeNamedFunction(index, _)
    | MakeMethodFunction(index)
    | MakeComputedMethodFunction(index)
    | MakeArrowFunction(index)
    | DeclareFunction(_, index) => Some((ChildFunction, index))
    LoadLocal(index)
    | StoreLocal(index)
    | DefineLocal(index, _)
    | UpdateLocal(index, _, _) => Some((LocalSlot, index))
    LoadEnvSlot(index)
    | StoreEnvSlot(index)
    | DefineEnvSlot(index, _)
    | UpdateEnvSlot(index, _, _) => Some((EnvironmentSlot, index))
    ObserveStatement(_)
    | ObserveExpression(_)
    | LoadConst(_)
    | LoadUndefined
    | LoadThis
    | LoadNewTarget
    | LoadSuperProperty(_, _)
    | LoadSuperComputed(_)
    | LoadConsoleMember(_)
    | LoadDirectEvalCallee
    | LoadName(_)
    | LoadAssignmentName(_)
    | StoreName(_)
    | DefineBinding(_, _, _)
    | SetCompletion
    | SetCompletionValue(_)
    | Pop
    | Dup
    | BinaryOp(_, _)
    | UnaryValueOp(_, _)
    | TypeofName(_)
    | DeleteName(_)
    | DeleteProperty(_)
    | DeleteComputed
    | AppendTemplate(_)
    | MakeTemplateObject(_)
    | MakeRegExp(_, _)
    | SetFunctionName(_)
    | UpdateName(_, _, _, _)
    | UpdateProperty(_, _, _, _, _)
    | UpdateComputed(_, _, _, _)
    | Jump(_)
    | JumpIfFalse(_)
    | JumpIfFalseKeep(_)
    | JumpIfTrueKeep(_)
    | JumpIfNotNullishKeep(_)
    | BeginOptionalChain
    | MarkOptionalChainShortCircuit
    | JumpIfNotOptionalChainShortCircuitKeep(_)
    | EndOptionalChain
    | StartForIn
    | ForInNext(_)
    | EndForIn
    | MakeArray(_)
    | MakeArrayWithHoles(_, _)
    | StartArray
    | ArrayPushValue
    | ArrayPushSpread(_)
    | ArrayPushHole
    | StartArgs
    | ArgPushValue
    | ArgPushSpread(_)
    | MakeObject(_)
    | StartObject
    | ObjectSetStatic(_)
    | ObjectSetStaticGetter(_)
    | ObjectSetStaticSetter(_)
    | ObjectSetComputedGetter
    | ObjectSetComputedSetter
    | ToObjectLiteralPropertyKey
    | ObjectSetComputed
    | ObjectSpread(_)
    | ObjectSetProto
    | GetProperty(_, _)
    | GetComputed(_)
    | ReadPropertyForAssign(_, _)
    | ReadComputedForAssign(_)
    | DropPropertyAssignReference
    | DropComputedAssignReference
    | SetProperty(_, _)
    | SetComputed(_)
    | SetForInProperty(_, _)
    | SetForInComputed(_)
    | AssignDestructure(_)
    | PreparePropertyCall(_, _)
    | PreparePlainPropertyCall(_, _)
    | PrepareComputedCall(_)
    | PrepareSuperPropertyCall(_, _)
    | PrepareSuperComputedCall(_)
    | CallDirectEval(_)
    | Call(_, _)
    | CallWithReceiver(_, _)
    | CallSpread(_)
    | CallSpreadWithReceiver(_)
    | Construct(_, _)
    | ConstructSpread(_)
    | Return
    | Throw => None
  }
}

///|
fn bytecode_indexed_operand_defect(
  function_path : Array[Int],
  instruction_index : Int,
  family : BytecodeIndexedOperandFamily,
  exclusive_upper_bound : Int,
  actual_operand : Int,
) -> BytecodeVerifierDefect {
  let defect : BytecodeIndexedOperandTargetDefect = {
    function_path: function_path.copy(),
    instruction_index,
    family,
    exclusive_upper_bound,
    actual_operand,
  }
  BytecodeIndexedOperandDefect(defect)
}

///|
fn verify_bytecode_indexed_operands(
  program : BytecodeUnverifiedProgram,
) -> Unit raise Error {
  verify_bytecode_function_indexed_operands(program.main, [])
}

///|
fn verify_bytecode_function_indexed_operands(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  for instruction_index, instruction in function.code {
    match bytecode_indexed_operand(instruction) {
      Some((family, actual_operand)) => {
        let exclusive_upper_bound = match family {
          ChildFunction => function.children.length()
          LocalSlot => function.local_names.length()
          EnvironmentSlot => function.env_slot_names.length()
        }
        guard actual_operand >= 0 && actual_operand < exclusive_upper_bound else {
          raise bytecode_indexed_operand_defect(
            function_path, instruction_index, family, exclusive_upper_bound, actual_operand,
          )
        }
      }
      None => ()
    }
  }
  for child_index, child in function.children {
    let child_path = function_path.copy()
    child_path.push(child_index)
    verify_bytecode_function_indexed_operands(child, child_path)
  }
}

///|
fn bytecode_control_flow_target(instruction : BytecodeInstr) -> Int? {
  match instruction {
    Jump(target)
    | JumpIfFalse(target)
    | JumpIfFalseKeep(target)
    | JumpIfTrueKeep(target)
    | JumpIfNotNullishKeep(target)
    | JumpIfNotOptionalChainShortCircuitKeep(target)
    | ForInNext(target) => Some(target)
    _ => None
  }
}

///|
fn bytecode_control_flow_target_defect(
  function_path : Array[Int],
  instruction_index : Int,
  code_length : Int,
  actual_target : Int,
) -> BytecodeVerifierDefect {
  BytecodeControlFlowDefect({
    function_path: function_path.copy(),
    instruction_index,
    expected_lower_bound: 0,
    expected_upper_bound: code_length,
    actual_target,
  })
}

///|
fn verify_bytecode_control_flow(
  program : BytecodeUnverifiedProgram,
) -> Unit raise Error {
  verify_bytecode_function_control_flow(program.main, [])
}

///|
fn verify_bytecode_function_control_flow(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  let code_length = function.code.length()
  for instruction_index, instruction in function.code {
    match bytecode_control_flow_target(instruction) {
      Some(target) => {
        guard target >= 0 && target <= code_length else {
          raise bytecode_control_flow_target_defect(
            function_path, instruction_index, code_length, target,
          )
        }
      }
      None => ()
    }
  }
  for child_index, child in function.children {
    let child_path = function_path.copy()
    child_path.push(child_index)
    verify_bytecode_function_control_flow(child, child_path)
  }
}

///|
fn verify_bytecode_function_source_metadata(
  function : BytecodeFunction,
  root_source_unit : SourceUnitHandle,
  function_path : Array[Int],
  expected_owner_id : Int,
) -> Int raise Error {
  guard expected_owner_id >= 0 && expected_owner_id < MAX_SOURCE_POINT_OWNER_ID else {
    raise BytecodeSourcePointOwnerAllocationDefect(expected_owner_id)
  }
  let expected_owner = SourcePointOwnerId(expected_owner_id)
  guard function.source_unit == root_source_unit else {
    raise bytecode_source_metadata_defect(
      function_path,
      None,
      NestedSourceUnit,
      SourceUnit(root_source_unit),
      SourceUnit(function.source_unit),
    )
  }
  guard function.source_point_owner == expected_owner else {
    raise bytecode_source_metadata_defect(
      function_path,
      None,
      SourcePointOwnership,
      SourcePointOwner(expected_owner),
      SourcePointOwner(function.source_point_owner),
    )
  }
  guard function.instruction_sources.length() == function.code.length() else {
    raise bytecode_source_metadata_defect(
      function_path,
      None,
      InstructionSourceCount,
      CodeLength(function.code.length()),
      InstructionSourcesLength(function.instruction_sources.length()),
    )
  }
  for instruction_index, instruction in function.code {
    let sources = function.instruction_sources[instruction_index]
    let contract = bytecode_instruction_contract(instruction)
    verify_observation_barrier_contract(
      instruction,
      contract.observation_barrier,
      function_path,
      instruction_index,
    )
    let actual_roles : Array[SourcePointRole] = []
    for source_id in sources {
      actual_roles.push(
        verify_source_point_reference(
          function,
          source_id,
          None,
          function_path,
          Some(instruction_index),
        ),
      )
    }
    guard actual_roles == contract.required_source_roles else {
      raise bytecode_source_metadata_defect(
        function_path,
        Some(instruction_index),
        SourceRoleOrder,
        SourceRoles(contract.required_source_roles),
        SourceRoles(actual_roles),
      )
    }
    match instruction {
      ObserveStatement(source_id) | ObserveExpression(source_id) =>
        verify_observation_source_point(
          function,
          source_id,
          sources[0],
          contract.required_source_roles[0],
          function_path,
          instruction_index,
        )
      _ => ()
    }
  }
  let mut next_owner_id = expected_owner_id + 1
  for child_index, child in function.children {
    let child_path = function_path.copy()
    child_path.push(child_index)
    next_owner_id = verify_bytecode_function_source_metadata(
      child, root_source_unit, child_path, next_owner_id,
    )
  }
  next_owner_id
}

///|
fn verify_source_point_reference(
  function : BytecodeFunction,
  source_id : SourcePointId,
  expected_role : SourcePointRole?,
  function_path : Array[Int],
  instruction_index : Int?,
) -> SourcePointRole raise Error {
  let SourcePointId(source_unit, source_point_owner, source_point_index) = source_id
  guard source_unit == function.source_unit else {
    raise bytecode_source_metadata_defect(
      function_path,
      instruction_index,
      SourcePointOwnership,
      SourceUnit(function.source_unit),
      SourceUnit(source_unit),
    )
  }
  guard source_point_owner == function.source_point_owner else {
    raise bytecode_source_metadata_defect(
      function_path,
      instruction_index,
      SourcePointOwnership,
      SourcePointOwner(function.source_point_owner),
      SourcePointOwner(source_point_owner),
    )
  }
  guard source_point_index >= 0 &&
    source_point_index < function.source_points.length() else {
    raise bytecode_source_metadata_defect(
      function_path,
      instruction_index,
      SourcePointReference,
      SourcePointTableLength(function.source_points.length()),
      SourcePointIndex(source_point_index),
    )
  }
  let role = function.source_points[source_point_index].role
  match expected_role {
    Some(required_role) => {
      guard role == required_role else {
        raise bytecode_source_metadata_defect(
          function_path,
          instruction_index,
          SourceRoleOrder,
          SourceRoles([required_role]),
          SourceRoles([role]),
        )
      }
    }
    None => ()
  }
  role
}

///|
fn source_point_identity_fact(
  source_id : SourcePointId,
) -> BytecodeSourceMetadataFact {
  let SourcePointId(source_unit, source_point_owner, source_point_index) = source_id
  SourcePointIdentity(source_unit, source_point_owner, source_point_index)
}

///|
fn verify_observation_source_point(
  function : BytecodeFunction,
  source_id : SourcePointId,
  metadata_source_id : SourcePointId,
  required_role : SourcePointRole,
  function_path : Array[Int],
  instruction_index : Int,
) -> Unit raise Error {
  let _ = verify_source_point_reference(
    function,
    source_id,
    Some(required_role),
    function_path,
    Some(instruction_index),
  )
  let SourcePointId(
    expected_source_unit,
    expected_source_point_owner,
    expected_source_point_index
  ) = metadata_source_id
  let SourcePointId(
    actual_source_unit,
    actual_source_point_owner,
    actual_source_point_index
  ) = source_id
  guard expected_source_unit == actual_source_unit &&
    expected_source_point_owner == actual_source_point_owner &&
    expected_source_point_index == actual_source_point_index else {
    raise bytecode_source_metadata_defect(
      function_path,
      Some(instruction_index),
      ObservationSourceIdentity,
      source_point_identity_fact(metadata_source_id),
      source_point_identity_fact(source_id),
    )
  }
}

///|
fn verify_observation_barrier_contract(
  instruction : BytecodeInstr,
  barrier : BytecodeObservationBarrierKind,
  function_path : Array[Int],
  instruction_index : Int,
) -> Unit raise Error {
  match instruction {
    ObserveStatement(_) => {
      guard barrier is StatementObservationBarrier else {
        raise bytecode_source_metadata_defect(
          function_path,
          Some(instruction_index),
          ObservationBarrier,
          ObservationBarrierKind(StatementObservationBarrier),
          ObservationBarrierKind(barrier),
        )
      }
    }
    ObserveExpression(_) => {
      guard barrier is ExpressionObservationBarrier else {
        raise bytecode_source_metadata_defect(
          function_path,
          Some(instruction_index),
          ObservationBarrier,
          ObservationBarrierKind(ExpressionObservationBarrier),
          ObservationBarrierKind(barrier),
        )
      }
    }
    _ => ()
  }
}
