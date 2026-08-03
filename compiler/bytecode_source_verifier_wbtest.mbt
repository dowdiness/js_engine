///|
fn unverified_source_program_for_wb(
  src : String,
) -> BytecodeUnverifiedProgram raise Error {
  let parsed = @parser.parse(src)
  build_script_bytecode(parsed.stmts)
}

///|
fn source_point_id_for_role_for_wb(
  function : BytecodeFunction,
  role : SourcePointRole,
) -> SourcePointId {
  for index, source_point in function.source_points {
    if source_point.role == role {
      return SourcePointId(function.source_unit, index)
    }
  }
  abort("expected source point role")
}

///|
fn instruction_index_for_roles_for_wb(
  function : BytecodeFunction,
  roles : Array[SourcePointRole],
) -> Int {
  for index, instruction in function.code {
    if bytecode_instruction_contract(instruction).required_source_roles == roles {
      return index
    }
  }
  abort("expected instruction source roles")
}

///|
fn function_contains_construction_for_wb(function : BytecodeFunction) -> Bool {
  for instruction in function.code {
    match instruction {
      Construct(_, _) | ConstructSpread(_) => return true
      _ => ()
    }
  }
  for child in function.children {
    if function_contains_construction_for_wb(child) {
      return true
    }
  }
  false
}

///|
fn function_contains_property_preparation_for_wb(
  function : BytecodeFunction,
) -> Bool {
  for instruction in function.code {
    match instruction {
      PreparePropertyCall(_, _)
      | PreparePlainPropertyCall(_, _)
      | PrepareComputedCall(_)
      | PrepareSuperPropertyCall(_, _)
      | PrepareSuperComputedCall(_) => return true
      _ => ()
    }
  }
  for child in function.children {
    if function_contains_property_preparation_for_wb(child) {
      return true
    }
  }
  false
}

///|
fn observe_statement_index_for_wb(function : BytecodeFunction) -> Int {
  for index, instruction in function.code {
    match instruction {
      ObserveStatement(_) => return index
      _ => ()
    }
  }
  abort("expected statement observation")
}

///|
fn observe_expression_index_for_wb(function : BytecodeFunction) -> Int {
  for index, instruction in function.code {
    match instruction {
      ObserveExpression(_) => return index
      _ => ()
    }
  }
  abort("expected expression observation")
}

///|
fn assert_source_metadata_invariant_for_wb(
  actual : BytecodeSourceMetadataInvariant,
  expected : BytecodeSourceMetadataInvariant,
) -> Unit raise Error {
  match (actual, expected) {
    (InstructionSourceCount, InstructionSourceCount)
    | (SourcePointReference, SourcePointReference)
    | (SourcePointOwnership, SourcePointOwnership)
    | (SourceRoleOrder, SourceRoleOrder)
    | (ObservationBarrier, ObservationBarrier)
    | (NestedSourceUnit, NestedSourceUnit) => ()
    _ => fail("unexpected source metadata invariant")
  }
}

///|
fn assert_observation_barrier_kind_equal_for_wb(
  left : BytecodeObservationBarrierKind,
  right : BytecodeObservationBarrierKind,
) -> Unit raise Error {
  match (left, right) {
    (NotObservationBarrier, NotObservationBarrier)
    | (StatementObservationBarrier, StatementObservationBarrier)
    | (ExpressionObservationBarrier, ExpressionObservationBarrier) => ()
    _ => fail("unexpected observation barrier")
  }
}

///|
fn assert_source_metadata_fact_equal_for_wb(
  left : BytecodeSourceMetadataFact,
  right : BytecodeSourceMetadataFact,
) -> Unit raise Error {
  match (left, right) {
    (CodeLength(left), CodeLength(right))
    | (InstructionSourcesLength(left), InstructionSourcesLength(right))
    | (SourcePointIndex(left), SourcePointIndex(right))
    | (SourcePointTableLength(left), SourcePointTableLength(right)) =>
      assert_eq(left, right)
    (SourceUnit(left), SourceUnit(right)) => assert_eq(left, right)
    (SourceRoles(left), SourceRoles(right)) => assert_eq(left, right)
    (ObservationBarrierKind(left), ObservationBarrierKind(right)) =>
      assert_observation_barrier_kind_equal_for_wb(left, right)
    _ => fail("unexpected source metadata facts")
  }
}

///|
fn bytecode_function_with_source_unit_for_wb(
  function : BytecodeFunction,
  source_unit : SourceUnitHandle,
) -> BytecodeFunction {
  BytecodeFunction(
    name=function.name,
    params=function.params,
    rest_param=function.rest_param,
    source_body=function.source_body,
    body_has_use_strict=function.body_has_use_strict,
    call_self_name=function.call_self_name,
    needs_arguments_object=function.needs_arguments_object,
    needs_own_env=function.needs_own_env,
    local_names=function.local_names,
    local_indices=function.local_indices,
    env_slot_names=function.env_slot_names,
    env_var_hoist_names=function.env_var_hoist_names,
    template_cache_key_prefix=function.template_cache_key_prefix,
    code=function.code,
    source_unit~,
    source_points=function.source_points,
    instruction_sources=function.instruction_sources,
    children=function.children,
  )
}

///|
fn expect_source_metadata_defect_for_wb(
  program : BytecodeUnverifiedProgram,
  expected_invariant : BytecodeSourceMetadataInvariant,
  expected_path : Array[Int],
  expected_instruction : Int?,
) -> BytecodeSourceMetadataDefect raise Error {
  try {
    let _ = finalize_bytecode_program(program)
    fail("expected typed verifier defect")
  } catch {
    BytecodeVerifierDefect(defect) => {
      assert_source_metadata_invariant_for_wb(
        defect.invariant,
        expected_invariant,
      )
      assert_eq(defect.function_path, expected_path)
      assert_eq(defect.instruction_index, expected_instruction)
      defect
    }
    _ => fail("expected typed verifier defect")
  }
}

///|
test "source metadata verifier accepts nested valid programs" {
  let src =
    #|function compute(value) {
    #|  var object = {};
    #|  object.value = value;
    #|  object.toString();
    #|  for (var i = 0; i < 2; i++) {
    #|    if (i) continue;
    #|  }
    #|  return new Number(object.value) + /x/.source;
    #|}
    #|compute("ok");
  let program = unverified_source_program_for_wb(src)
  let finalized = finalize_bytecode_program(program)
  assert_true(finalized.main.children.length() == 1)
  assert_true(function_contains_construction_for_wb(finalized.main))
  assert_true(function_contains_property_preparation_for_wb(finalized.main))
}

///|
test "source metadata verifier rejects out-of-range references" {
  let program = unverified_source_program_for_wb("1;")
  let index = observe_statement_index_for_wb(program.main)
  program.main.instruction_sources[index][0] = SourcePointId(
    program.main.source_unit,
    program.main.source_points.length(),
  )
  let defect = expect_source_metadata_defect_for_wb(
    program,
    SourcePointReference,
    [],
    Some(index),
  )
  match (defect.expected, defect.actual) {
    (SourcePointTableLength(length), SourcePointIndex(actual)) =>
      assert_eq(actual, length)
    _ => fail("expected source-point bounds facts")
  }
}

///|
test "source metadata verifier rejects cross-unit references" {
  let program = unverified_source_program_for_wb("1;")
  let index = observe_statement_index_for_wb(program.main)
  let SourcePointId(_, source_point_index) = program.main.instruction_sources[index][0]
  program.main.instruction_sources[index][0] = SourcePointId(
    SourceUnitHandle(99),
    source_point_index,
  )
  let defect = expect_source_metadata_defect_for_wb(
    program,
    SourcePointOwnership,
    [],
    Some(index),
  )
  match (defect.expected, defect.actual) {
    (SourceUnit(expected), SourceUnit(actual)) =>
      assert_true(expected != actual)
    _ => fail("expected source-unit ownership facts")
  }
}

///|
test "source metadata verifier rejects reordered and missing roles" {
  let program = unverified_source_program_for_wb("object[key];")
  let index = instruction_index_for_roles_for_wb(program.main, [
    MemberAccess,
    PropertyKey,
  ])
  let sources = program.main.instruction_sources[index]
  program.main.instruction_sources[index] = [sources[1], sources[0]]
  let reordered = expect_source_metadata_defect_for_wb(
    program,
    SourceRoleOrder,
    [],
    Some(index),
  )
  match (reordered.expected, reordered.actual) {
    (SourceRoles(expected), SourceRoles(actual)) => {
      assert_true(expected != actual)
      assert_eq(expected.length(), actual.length())
    }
    _ => fail("expected ordered source-role facts")
  }

  let missing_program = unverified_source_program_for_wb("object[key];")
  let missing_index = instruction_index_for_roles_for_wb(missing_program.main, [
    MemberAccess,
    PropertyKey,
  ])
  let missing_sources = missing_program.main.instruction_sources[missing_index]
  missing_program.main.instruction_sources[missing_index] = [missing_sources[0]]
  let missing = expect_source_metadata_defect_for_wb(
    missing_program,
    SourceRoleOrder,
    [],
    Some(missing_index),
  )
  match (missing.expected, missing.actual) {
    (SourceRoles(expected), SourceRoles(actual)) => {
      assert_eq(expected, [MemberAccess, PropertyKey])
      assert_eq(actual, [MemberAccess])
    }
    _ => fail("expected missing source-role facts")
  }

  let extra_program = unverified_source_program_for_wb("object[key];")
  let extra_index = instruction_index_for_roles_for_wb(extra_program.main, [
    MemberAccess,
    PropertyKey,
  ])
  let extra_sources = extra_program.main.instruction_sources[extra_index]
  extra_program.main.instruction_sources[extra_index] = [
    extra_sources[0],
    extra_sources[1],
    extra_sources[0],
  ]
  let extra = expect_source_metadata_defect_for_wb(
    extra_program,
    SourceRoleOrder,
    [],
    Some(extra_index),
  )
  match (extra.expected, extra.actual) {
    (SourceRoles(expected), SourceRoles(actual)) => {
      assert_eq(expected, [MemberAccess, PropertyKey])
      assert_eq(actual, [MemberAccess, PropertyKey, MemberAccess])
    }
    _ => fail("expected extra source-role facts")
  }
}

///|
test "source metadata verifier checks observation source roles" {
  let statement_program = unverified_source_program_for_wb("1;")
  let statement_index = observe_statement_index_for_wb(statement_program.main)
  let expression_id = source_point_id_for_role_for_wb(
    statement_program.main,
    ExpressionEntry,
  )
  statement_program.main.instruction_sources[statement_index][0] = expression_id
  let statement_defect = expect_source_metadata_defect_for_wb(
    statement_program,
    SourceRoleOrder,
    [],
    Some(statement_index),
  )
  match (statement_defect.expected, statement_defect.actual) {
    (SourceRoles([StatementEntry]), SourceRoles([ExpressionEntry])) => ()
    _ => fail("expected statement observation roles")
  }

  let expression_program = unverified_source_program_for_wb("1;")
  let expression_index = observe_expression_index_for_wb(
    expression_program.main,
  )
  let statement_id = source_point_id_for_role_for_wb(
    expression_program.main,
    StatementEntry,
  )
  expression_program.main.instruction_sources[expression_index][0] = statement_id
  let expression_defect = expect_source_metadata_defect_for_wb(
    expression_program,
    SourceRoleOrder,
    [],
    Some(expression_index),
  )
  match (expression_defect.expected, expression_defect.actual) {
    (SourceRoles([ExpressionEntry]), SourceRoles([StatementEntry])) => ()
    _ => fail("expected expression observation roles")
  }
}

///|
test "source metadata verifier diagnoses mismatched observation barriers" {
  // The barrier is derived from the closed instruction contract, so malformed
  // program data cannot change it; exercise the private checker directly.
  let program = unverified_source_program_for_wb("1;")
  let index = observe_statement_index_for_wb(program.main)
  let source_id = program.main.instruction_sources[index][0]
  try {
    verify_observation_barrier_contract(
      ObserveStatement(source_id),
      ExpressionObservationBarrier,
      [],
      index,
    )
    fail("expected typed barrier defect")
  } catch {
    BytecodeVerifierDefect(
      { function_path, instruction_index, invariant, expected, actual }
    ) => {
      assert_eq(function_path, [])
      assert_eq(instruction_index, Some(index))
      assert_source_metadata_invariant_for_wb(invariant, ObservationBarrier)
      match (expected, actual) {
        (
          ObservationBarrierKind(StatementObservationBarrier),
          ObservationBarrierKind(ExpressionObservationBarrier),
        ) => ()
        _ => fail("expected statement barrier facts")
      }
    }
    _ => fail("expected typed barrier defect")
  }
}

///|
test "source metadata verifier defects are deterministic" {
  let left = unverified_source_program_for_wb("1;")
  let left_index = observe_statement_index_for_wb(left.main)
  left.main.instruction_sources[left_index][0] = SourcePointId(
    left.main.source_unit,
    left.main.source_points.length(),
  )
  let right = unverified_source_program_for_wb("1;")
  let right_index = observe_statement_index_for_wb(right.main)
  right.main.instruction_sources[right_index][0] = SourcePointId(
    right.main.source_unit,
    right.main.source_points.length(),
  )
  let left_defect = expect_source_metadata_defect_for_wb(
    left,
    SourcePointReference,
    [],
    Some(left_index),
  )
  let right_defect = expect_source_metadata_defect_for_wb(
    right,
    SourcePointReference,
    [],
    Some(right_index),
  )
  assert_eq(left_defect.function_path, right_defect.function_path)
  assert_eq(left_defect.instruction_index, right_defect.instruction_index)
  assert_source_metadata_invariant_for_wb(
    left_defect.invariant,
    right_defect.invariant,
  )
  assert_source_metadata_fact_equal_for_wb(
    left_defect.expected,
    right_defect.expected,
  )
  assert_source_metadata_fact_equal_for_wb(
    left_defect.actual,
    right_defect.actual,
  )
}

///|
test "source metadata verifier retains nested path and source unit" {
  let src =
    #|function child() { return 1; }
    #|child();
  let program = unverified_source_program_for_wb(src)
  program.main.children[0] = bytecode_function_with_source_unit_for_wb(
    program.main.children[0],
    SourceUnitHandle(99),
  )
  let defect = expect_source_metadata_defect_for_wb(
    program,
    NestedSourceUnit,
    [0],
    None,
  )
  match (defect.expected, defect.actual) {
    (SourceUnit(expected), SourceUnit(actual)) =>
      assert_true(expected != actual)
    _ => fail("expected nested source-unit facts")
  }
}
