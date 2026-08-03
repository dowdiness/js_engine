///|
#warnings("-unused_constructor")
priv enum BytecodeSourceMetadataInvariant {
  InstructionSourceCount
  SourcePointReference
  SourcePointOwnership
  SourceRoleOrder
  ObservationBarrier
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
  SourceRoles(Array[SourcePointRole])
  ObservationBarrierKind(BytecodeObservationBarrierKind)
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
  verify_bytecode_function_source_metadata(
    program.main,
    program.main.source_unit,
    [],
  )
}

///|
fn finalize_bytecode_program(
  program : BytecodeUnverifiedProgram,
) -> BytecodeProgram raise Error {
  verify_bytecode_source_metadata(program)
  { source_stmts: program.source_stmts, main: program.main }
}

///|
fn verify_bytecode_function_source_metadata(
  function : BytecodeFunction,
  root_source_unit : SourceUnitHandle,
  function_path : Array[Int],
) -> Unit raise Error {
  guard function.source_unit == root_source_unit else {
    raise bytecode_source_metadata_defect(
      function_path,
      None,
      NestedSourceUnit,
      SourceUnit(root_source_unit),
      SourceUnit(function.source_unit),
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
      let SourcePointId(source_unit, source_point_owner, source_point_index) = source_id
      guard source_unit == function.source_unit else {
        raise bytecode_source_metadata_defect(
          function_path,
          Some(instruction_index),
          SourcePointOwnership,
          SourceUnit(function.source_unit),
          SourceUnit(source_unit),
        )
      }
      guard source_point_owner == function.source_point_owner else {
        raise bytecode_source_metadata_defect(
          function_path,
          Some(instruction_index),
          SourcePointOwnership,
          SourcePointOwner(function.source_point_owner),
          SourcePointOwner(source_point_owner),
        )
      }
      guard source_point_index >= 0 &&
        source_point_index < function.source_points.length() else {
        raise bytecode_source_metadata_defect(
          function_path,
          Some(instruction_index),
          SourcePointReference,
          SourcePointTableLength(function.source_points.length()),
          SourcePointIndex(source_point_index),
        )
      }
      actual_roles.push(function.source_points[source_point_index].role)
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
  }
  for child_index, child in function.children {
    let child_path = function_path.copy()
    child_path.push(child_index)
    verify_bytecode_function_source_metadata(
      child, root_source_unit, child_path,
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
