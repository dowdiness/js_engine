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
#warnings("-unused_field")
priv struct BytecodeSourceMetadataDefect {
  function_path : Array[Int]
  instruction_index : Int?
  invariant : BytecodeSourceMetadataInvariant
  expected : BytecodeSourceMetadataFact
  actual : BytecodeSourceMetadataFact
}

///|
priv suberror BytecodeVerifierDefect {
  BytecodeVerifierDefect(BytecodeSourceMetadataDefect)
  BytecodeControlFlowDefect(BytecodeControlFlowTargetDefect)
  BytecodeIndexedOperandDefect(BytecodeIndexedOperandTargetDefect)
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
fn finalize_bytecode_program(
  program : BytecodeUnverifiedProgram,
) -> BytecodeProgram raise Error {
  verify_bytecode_source_metadata(program)
  verify_bytecode_control_flow(program)
  verify_bytecode_indexed_operands(program)
  { source_stmts: program.source_stmts, main: program.main }
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
    | AssignPattern(_)
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
