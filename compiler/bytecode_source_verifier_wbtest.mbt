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
      return SourcePointId(
        function.source_unit,
        function.source_point_owner,
        index,
      )
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
    | (ObservationSourceIdentity, ObservationSourceIdentity)
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
    (SourcePointOwner(left), SourcePointOwner(right)) => assert_eq(left, right)
    (
      SourcePointIdentity(left_unit, left_owner, left_index),
      SourcePointIdentity(right_unit, right_owner, right_index),
    ) => {
      assert_eq(left_unit, right_unit)
      assert_eq(left_owner, right_owner)
      assert_eq(left_index, right_index)
    }
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
    source_point_owner=function.source_point_owner,
    source_unit~,
    source_points=function.source_points,
    instruction_sources=function.instruction_sources,
    children=function.children,
  )
}

///|
fn source_point_id_with_owner_for_wb(
  source_id : SourcePointId,
  source_point_owner : SourcePointOwnerId,
) -> SourcePointId {
  let SourcePointId(source_unit, _, source_point_index) = source_id
  SourcePointId(source_unit, source_point_owner, source_point_index)
}

///|
fn bytecode_instruction_with_source_point_owner_for_wb(
  instruction : BytecodeInstr,
  source_point_owner : SourcePointOwnerId,
) -> BytecodeInstr {
  match instruction {
    ObserveStatement(source_id) =>
      ObserveStatement(
        source_point_id_with_owner_for_wb(source_id, source_point_owner),
      )
    ObserveExpression(source_id) =>
      ObserveExpression(
        source_point_id_with_owner_for_wb(source_id, source_point_owner),
      )
    _ => instruction
  }
}

///|
fn bytecode_function_with_source_point_owner_for_wb(
  function : BytecodeFunction,
  source_point_owner : SourcePointOwnerId,
) -> BytecodeFunction {
  let code = function.code.map(instruction => {
    bytecode_instruction_with_source_point_owner_for_wb(
      instruction, source_point_owner,
    )
  })
  let instruction_sources = function.instruction_sources.map(sources => {
    sources.map(source_id => {
      source_point_id_with_owner_for_wb(source_id, source_point_owner)
    })
  })
  let children = function.children.map(child => {
    bytecode_function_with_source_point_owner_for_wb(child, source_point_owner)
  })
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
    code~,
    source_point_owner~,
    source_unit=function.source_unit,
    source_points=function.source_points,
    instruction_sources~,
    children~,
  )
}

///|
fn source_point_id_with_different_index_for_wb(
  function : BytecodeFunction,
  source_id : SourcePointId,
  role : SourcePointRole,
) -> SourcePointId {
  let SourcePointId(source_unit, source_point_owner, source_point_index) = source_id
  for replacement_index, source_point in function.source_points {
    if replacement_index != source_point_index && source_point.role == role {
      return SourcePointId(source_unit, source_point_owner, replacement_index)
    }
  }
  abort("expected a second source point with the requested role")
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
  assert_true(
    finalized.main.source_point_owner !=
    finalized.main.children[0].source_point_owner,
  )
  assert_true(function_contains_construction_for_wb(finalized.main))
  assert_true(function_contains_property_preparation_for_wb(finalized.main))
}

///|
test "source metadata verifier rejects out-of-range references" {
  let program = unverified_source_program_for_wb("1;")
  let index = observe_statement_index_for_wb(program.main)
  program.main.instruction_sources[index][0] = SourcePointId(
    program.main.source_unit,
    program.main.source_point_owner,
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
  let SourcePointId(_, source_point_owner, source_point_index) = program.main.instruction_sources[index][0]
  program.main.instruction_sources[index][0] = SourcePointId(
    SourceUnitHandle(99),
    source_point_owner,
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
    left.main.source_point_owner,
    left.main.source_points.length(),
  )
  let right = unverified_source_program_for_wb("1;")
  let right_index = observe_statement_index_for_wb(right.main)
  right.main.instruction_sources[right_index][0] = SourcePointId(
    right.main.source_unit,
    right.main.source_point_owner,
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

///|
test "RED: same-handle cross-function source owner aliases are rejected" {
  let src =
    #|function child() { return 1; }
    #|child();
  let program = unverified_source_program_for_wb(src)
  guard program.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = program.main.children[0]
  guard child.source_points.length() > 0 else {
    abort("expected child source point")
  }
  let child_role = child.source_points[0].role
  let mut root_source_slot : (Int, Int)? = None
  for instruction_index, instruction in program.main.code {
    let required_roles = bytecode_instruction_contract(instruction).required_source_roles
    for
      source_slot, source_id in program.main.instruction_sources[instruction_index] {
      let SourcePointId(_, _, source_point_index) = source_id
      if source_point_index == 0 && required_roles[source_slot] == child_role {
        root_source_slot = Some((instruction_index, source_slot))
        break
      }
    }
    if root_source_slot is Some(_) {
      break
    }
  }
  let (instruction_index, source_slot) = match root_source_slot {
    Some(slot) => slot
    None => abort("expected root source point at index zero")
  }
  program.main.instruction_sources[instruction_index][source_slot] = SourcePointId(
    child.source_unit,
    child.source_point_owner,
    0,
  )
  try {
    let _ = finalize_bytecode_program(program)
    fail("expected typed source ownership defect")
  } catch {
    BytecodeVerifierDefect(defect) => {
      assert_eq(defect.function_path, [])
      assert_eq(defect.instruction_index, Some(instruction_index))
      assert_source_metadata_invariant_for_wb(
        defect.invariant,
        SourcePointOwnership,
      )
      match (defect.expected, defect.actual) {
        (SourcePointOwner(expected), SourcePointOwner(actual)) =>
          assert_true(expected != actual)
        _ => fail("expected source-point owner facts")
      }
    }
    _ => fail("expected typed source ownership defect")
  }
}

///|
test "RED: source owner tree order rejects reconstructed aliases" {
  let src =
    #|function child() { return 1; }
    #|child();
  let program = unverified_source_program_for_wb(src)
  guard program.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let root_owner = program.main.source_point_owner
  program.main.children[0] = bytecode_function_with_source_point_owner_for_wb(
    program.main.children[0],
    root_owner,
  )
  try {
    let _ = finalize_bytecode_program(program)
    fail("expected typed source ownership defect")
  } catch {
    BytecodeVerifierDefect(defect) => {
      assert_eq(defect.function_path, [0])
      assert_eq(defect.instruction_index, None)
      assert_source_metadata_invariant_for_wb(
        defect.invariant,
        SourcePointOwnership,
      )
      match (defect.expected, defect.actual) {
        (SourcePointOwner(expected), SourcePointOwner(actual)) =>
          assert_true(expected != actual)
        _ => fail("expected source-point owner facts")
      }
    }
    _ => fail("expected typed source ownership defect")
  }
}

///|
test "RED: observation opcode payload identity is verified" {
  let child_src =
    #|function child() { return 1; }
    #|child();
  let child_program = unverified_source_program_for_wb(child_src)
  let child_observation_index = observe_statement_index_for_wb(
    child_program.main,
  )
  let child_source_id = source_point_id_for_role_for_wb(
    child_program.main.children[0],
    StatementEntry,
  )
  child_program.main.code[child_observation_index] = ObserveStatement(
    child_source_id,
  )
  try {
    let _ = finalize_bytecode_program(child_program)
    fail("expected typed observation payload defect")
  } catch {
    BytecodeVerifierDefect(defect) => {
      assert_eq(defect.function_path, [])
      assert_eq(defect.instruction_index, Some(child_observation_index))
      assert_source_metadata_invariant_for_wb(
        defect.invariant,
        SourcePointOwnership,
      )
      match (defect.expected, defect.actual) {
        (SourcePointOwner(expected), SourcePointOwner(actual)) =>
          assert_true(expected != actual)
        _ => fail("expected source-point owner facts")
      }
    }
    _ => fail("expected typed observation payload defect")
  }

  let same_owner_program = unverified_source_program_for_wb("1; 2;")
  let same_owner_observation_index = observe_statement_index_for_wb(
    same_owner_program.main,
  )
  let same_owner_metadata_id = same_owner_program.main.instruction_sources[same_owner_observation_index][0]
  let same_owner_replacement = source_point_id_with_different_index_for_wb(
    same_owner_program.main,
    same_owner_metadata_id,
    StatementEntry,
  )
  same_owner_program.main.code[same_owner_observation_index] = ObserveStatement(
    same_owner_replacement,
  )
  try {
    let _ = finalize_bytecode_program(same_owner_program)
    fail("expected typed observation payload defect")
  } catch {
    BytecodeVerifierDefect(defect) => {
      assert_eq(defect.function_path, [])
      assert_eq(defect.instruction_index, Some(same_owner_observation_index))
      assert_source_metadata_invariant_for_wb(
        defect.invariant,
        ObservationSourceIdentity,
      )
      match (defect.expected, defect.actual) {
        (
          SourcePointIdentity(expected_unit, expected_owner, expected_index),
          SourcePointIdentity(actual_unit, actual_owner, actual_index),
        ) => {
          assert_eq(expected_unit, actual_unit)
          assert_eq(expected_owner, actual_owner)
          assert_true(expected_index != actual_index)
        }
        _ => fail("expected source-point identity facts")
      }
    }
    _ => fail("expected typed observation payload defect")
  }
}

///|
test "RED: source owner allocator refuses exhaustion without wrap-around" {
  let allocator : Ref[SourcePointOwnerAllocator] = {
    val: { next_id: MAX_SOURCE_POINT_OWNER_ID - 1 },
  }
  let last_owner = allocate_source_point_owner(allocator)
  match last_owner {
    SourcePointOwnerId(id) => assert_eq(id, MAX_SOURCE_POINT_OWNER_ID - 1)
  }
  assert_eq(allocator.val.next_id, MAX_SOURCE_POINT_OWNER_ID)
  let next_attempt : Result[
    SourcePointOwnerId,
    BytecodeSourcePointOwnerAllocationDefect,
  ] = Ok(allocate_source_point_owner(allocator)) catch { error => Err(error) }
  match next_attempt {
    Ok(SourcePointOwnerId(id)) =>
      fail("allocator wrapped or issued an exhausted owner: " + id.to_string())
    Err(BytecodeSourcePointOwnerAllocationDefect(next_id)) =>
      assert_eq(next_id, MAX_SOURCE_POINT_OWNER_ID)
  }
  assert_eq(allocator.val.next_id, MAX_SOURCE_POINT_OWNER_ID)
  let negative_allocator : Ref[SourcePointOwnerAllocator] = {
    val: { next_id: -1 },
  }
  let negative_attempt : Result[
    SourcePointOwnerId,
    BytecodeSourcePointOwnerAllocationDefect,
  ] = Ok(allocate_source_point_owner(negative_allocator)) catch {
    error => Err(error)
  }
  match negative_attempt {
    Ok(_) => fail("allocator accepted a negative owner state")
    Err(BytecodeSourcePointOwnerAllocationDefect(next_id)) =>
      assert_eq(next_id, -1)
  }
  assert_eq(negative_allocator.val.next_id, -1)
}

///|
test "source owner allocation is deterministic across compilations" {
  let src =
    #|function first() { return 1; }
    #|function second() { return 2; }
    #|first();
    #|second();
  let left = unverified_source_program_for_wb(src)
  let right = unverified_source_program_for_wb(src)
  assert_eq(left.main.children.length(), 2)
  assert_eq(right.main.children.length(), 2)
  match
    (
      left.main.source_point_owner,
      left.main.children[0].source_point_owner,
      left.main.children[1].source_point_owner,
      right.main.source_point_owner,
      right.main.children[0].source_point_owner,
      right.main.children[1].source_point_owner,
    ) {
    (
      SourcePointOwnerId(left_root),
      SourcePointOwnerId(left_first),
      SourcePointOwnerId(left_second),
      SourcePointOwnerId(right_root),
      SourcePointOwnerId(right_first),
      SourcePointOwnerId(right_second),
    ) => {
      assert_eq((left_root, left_first, left_second), (0, 1, 2))
      assert_eq((right_root, right_first, right_second), (0, 1, 2))
    }
  }
}

///|
test "RED: finalization rejects an unpatched control-flow target" {
  let program = unverified_source_program_for_wb("if (true) 1; else 2;")
  let mut jump_index : Int? = None
  for instruction_index, instruction in program.main.code {
    match instruction {
      JumpIfFalse(target) => {
        ignore(target)
        program.main.code[instruction_index] = JumpIfFalse(-1)
        jump_index = Some(instruction_index)
        break
      }
      _ => ()
    }
  }
  let instruction_index = match jump_index {
    Some(index) => index
    None => abort("expected conditional jump")
  }
  let defect = expect_control_flow_defect_for_wb(program, [], instruction_index)
  assert_eq(defect.expected_lower_bound, 0)
  assert_eq(defect.expected_upper_bound, program.main.code.length())
  assert_eq(defect.actual_target, -1)
}

///|
test "RED: finalization rejects an out-of-range child operand" {
  let program = unverified_source_program_for_wb("var f = function() {};")
  let child_count = program.main.children.length()
  guard child_count > 0 else { abort("expected one child function") }
  let mut found_instruction_index : Int? = None
  for instruction_index, instruction in program.main.code {
    match instruction {
      MakeFunction(_) => {
        program.main.code[instruction_index] = MakeFunction(child_count)
        found_instruction_index = Some(instruction_index)
        break
      }
      _ => ()
    }
  }
  let instruction_index = match found_instruction_index {
    Some(index) => index
    None => abort("expected MakeFunction instruction")
  }
  try {
    let _ = finalize_bytecode_program(program)
    fail("expected typed indexed operand defect")
  } catch {
    BytecodeIndexedOperandDefect(defect) => {
      assert_eq(defect.function_path, [])
      assert_eq(defect.instruction_index, instruction_index)
      match defect.family {
        ChildFunction => ()
        _ => fail("expected child-function family")
      }
      assert_eq(defect.exclusive_upper_bound, child_count)
      assert_eq(defect.actual_operand, child_count)
    }
    _ => fail("expected typed indexed operand defect")
  }
}

///|
fn indexed_operand_family_equal_for_wb(
  left : BytecodeIndexedOperandFamily,
  right : BytecodeIndexedOperandFamily,
) -> Bool {
  match (left, right) {
    (ChildFunction, ChildFunction)
    | (LocalSlot, LocalSlot)
    | (EnvironmentSlot, EnvironmentSlot) => true
    _ => false
  }
}

///|
fn bytecode_instruction_with_indexed_operand_for_wb(
  instruction : BytecodeInstr,
  operand : Int,
) -> BytecodeInstr {
  match instruction {
    MakeFunction(_) => MakeFunction(operand)
    MakeNamedFunction(_, name) => MakeNamedFunction(operand, name)
    MakeMethodFunction(_) => MakeMethodFunction(operand)
    MakeComputedMethodFunction(_) => MakeComputedMethodFunction(operand)
    MakeArrowFunction(_) => MakeArrowFunction(operand)
    DeclareFunction(name, _) => DeclareFunction(name, operand)
    LoadLocal(_) => LoadLocal(operand)
    StoreLocal(_) => StoreLocal(operand)
    DefineLocal(_, has_initializer) => DefineLocal(operand, has_initializer)
    UpdateLocal(_, op, prefix) => UpdateLocal(operand, op, prefix)
    LoadEnvSlot(_) => LoadEnvSlot(operand)
    StoreEnvSlot(_) => StoreEnvSlot(operand)
    DefineEnvSlot(_, has_initializer) => DefineEnvSlot(operand, has_initializer)
    UpdateEnvSlot(_, op, prefix) => UpdateEnvSlot(operand, op, prefix)
    _ => abort("expected indexed operand")
  }
}

///|
fn mutate_first_indexed_operand_for_wb(
  function : BytecodeFunction,
  family : BytecodeIndexedOperandFamily,
  operand : Int,
) -> Int {
  for instruction_index, instruction in function.code {
    match bytecode_indexed_operand(instruction) {
      Some((actual_family, _)) =>
        if indexed_operand_family_equal_for_wb(actual_family, family) {
          function.code[instruction_index] = bytecode_instruction_with_indexed_operand_for_wb(
            instruction, operand,
          )
          return instruction_index
        }
      None => ()
    }
  }
  abort("expected indexed operand")
}

///|
fn expect_indexed_operand_defect_for_wb(
  program : BytecodeUnverifiedProgram,
  expected_path : Array[Int],
  expected_instruction : Int,
) -> BytecodeIndexedOperandTargetDefect raise Error {
  try {
    let _ = finalize_bytecode_program(program)
    fail("expected typed indexed operand defect")
  } catch {
    BytecodeIndexedOperandDefect(defect) => {
      assert_eq(defect.function_path, expected_path)
      assert_eq(defect.instruction_index, expected_instruction)
      defect
    }
    _ => fail("expected typed indexed operand defect")
  }
}

///|
test "indexed operand classifier covers every indexed opcode" {
  let cases : Array[(BytecodeInstr, BytecodeIndexedOperandFamily)] = [
    (MakeFunction(7), ChildFunction),
    (MakeNamedFunction(7, "f"), ChildFunction),
    (MakeMethodFunction(7), ChildFunction),
    (MakeComputedMethodFunction(7), ChildFunction),
    (MakeArrowFunction(7), ChildFunction),
    (DeclareFunction("f", 7), ChildFunction),
    (LoadLocal(7), LocalSlot),
    (StoreLocal(7), LocalSlot),
    (DefineLocal(7, true), LocalSlot),
    (UpdateLocal(7, Increment, true), LocalSlot),
    (LoadEnvSlot(7), EnvironmentSlot),
    (StoreEnvSlot(7), EnvironmentSlot),
    (DefineEnvSlot(7, true), EnvironmentSlot),
    (UpdateEnvSlot(7, Increment, true), EnvironmentSlot),
  ]
  for case in cases {
    let (instruction, expected_family) = case
    match bytecode_indexed_operand(instruction) {
      Some((actual_family, actual_operand)) => {
        assert_true(
          indexed_operand_family_equal_for_wb(actual_family, expected_family),
        )
        assert_eq(actual_operand, 7)
      }
      None => fail("expected indexed operand classification")
    }
  }
}

///|
test "indexed operand verifier rejects every zero-length owning table" {
  let child_program = unverified_source_program_for_wb("var f = function() {};")
  guard child_program.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child_index = mutate_first_indexed_operand_for_wb(
    child_program.main,
    ChildFunction,
    0,
  )
  let _ = child_program.main.children.pop()
  let child_defect = expect_indexed_operand_defect_for_wb(
    child_program,
    [],
    child_index,
  )
  match child_defect.family {
    ChildFunction => ()
    _ => fail("expected child-function family")
  }
  assert_eq(child_defect.exclusive_upper_bound, 0)
  assert_eq(child_defect.actual_operand, 0)

  let local_program = unverified_source_program_for_wb(
    "function f(a) { return a; } f(1);",
  )
  guard local_program.main.children.length() == 1 else {
    abort("expected one local-slot child function")
  }
  let local_function = local_program.main.children[0]
  let local_name_count = local_function.local_names.length()
  guard local_name_count > 0 else { abort("expected local slots") }
  for _ in 0..<local_name_count {
    let _ = local_function.local_names.pop()
  }
  let local_index = mutate_first_indexed_operand_for_wb(
    local_function,
    LocalSlot,
    0,
  )
  let local_defect = expect_indexed_operand_defect_for_wb(
    local_program,
    [0],
    local_index,
  )
  match local_defect.family {
    LocalSlot => ()
    _ => fail("expected local-slot family")
  }
  assert_eq(local_defect.exclusive_upper_bound, 0)
  assert_eq(local_defect.actual_operand, 0)

  let env_src =
    #|function outer(a) {
    #|  function read() { return a; }
    #|  a = a + 1;
    #|  return read();
    #|}
    #|outer(1);
  let env_program = unverified_source_program_for_wb(env_src)
  guard env_program.main.children.length() == 1 else {
    abort("expected one environment-slot child function")
  }
  let env_function = env_program.main.children[0]
  let env_name_count = env_function.env_slot_names.length()
  guard env_name_count > 0 else { abort("expected environment slots") }
  for _ in 0..<env_name_count {
    let _ = env_function.env_slot_names.pop()
  }
  let env_index = mutate_first_indexed_operand_for_wb(
    env_function,
    EnvironmentSlot,
    0,
  )
  let env_defect = expect_indexed_operand_defect_for_wb(
    env_program,
    [0],
    env_index,
  )
  match env_defect.family {
    EnvironmentSlot => ()
    _ => fail("expected environment-slot family")
  }
  assert_eq(env_defect.exclusive_upper_bound, 0)
  assert_eq(env_defect.actual_operand, 0)
}

///|
test "indexed operand verifier preserves valid root and nested programs" {
  let root_program = unverified_source_program_for_wb("var x = 1; x = x + 1;")
  let root_finalized = finalize_bytecode_program(root_program)
  assert_eq(root_finalized.main.code.length(), root_program.main.code.length())
  assert_eq(
    root_finalized.main.local_names.length(),
    root_program.main.local_names.length(),
  )

  let nested_src =
    #|function outer(a) {
    #|  function read() { return a; }
    #|  a = a + 1;
    #|  return read();
    #|}
    #|outer(1);
  let nested_program = unverified_source_program_for_wb(nested_src)
  let nested_finalized = finalize_bytecode_program(nested_program)
  assert_eq(
    nested_finalized.main.children.length(),
    nested_program.main.children.length(),
  )
  assert_eq(
    nested_finalized.main.children[0].children.length(),
    nested_program.main.children[0].children.length(),
  )
  assert_eq(
    nested_finalized.main.children[0].env_slot_names.length(),
    nested_program.main.children[0].env_slot_names.length(),
  )
}

///|
test "indexed operand verifier rejects negative local slots" {
  let src =
    #|function f(a) {
    #|  var b = a;
    #|  return b;
    #|}
    #|f(1);
  let program = unverified_source_program_for_wb(src)
  guard program.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = program.main.children[0]
  guard child.local_names.length() > 0 else { abort("expected local slots") }
  let instruction_index = mutate_first_indexed_operand_for_wb(
    child,
    LocalSlot,
    -1,
  )
  let defect = expect_indexed_operand_defect_for_wb(
    program,
    [0],
    instruction_index,
  )
  match defect.family {
    LocalSlot => ()
    _ => fail("expected local-slot family")
  }
  assert_eq(defect.exclusive_upper_bound, child.local_names.length())
  assert_eq(defect.actual_operand, -1)
}

///|
test "indexed operand verifier rejects environment slot length" {
  let src =
    #|function outer(a) {
    #|  function read() { return a; }
    #|  a = a + 1;
    #|  return read();
    #|}
    #|outer(1);
  let program = unverified_source_program_for_wb(src)
  guard program.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let outer = program.main.children[0]
  guard outer.env_slot_names.length() > 0 else {
    abort("expected environment slots")
  }
  let invalid_operand = outer.env_slot_names.length()
  let instruction_index = mutate_first_indexed_operand_for_wb(
    outer,
    EnvironmentSlot,
    invalid_operand,
  )
  let defect = expect_indexed_operand_defect_for_wb(
    program,
    [0],
    instruction_index,
  )
  match defect.family {
    EnvironmentSlot => ()
    _ => fail("expected environment-slot family")
  }
  assert_eq(defect.exclusive_upper_bound, outer.env_slot_names.length())
  assert_eq(defect.actual_operand, invalid_operand)
}

///|
test "indexed operand verifier reports nested function path" {
  let src =
    #|function outer() {
    #|  function inner(a) {
    #|    var b = a;
    #|    return b;
    #|  }
    #|  return inner;
    #|}
    #|outer()();
  let program = unverified_source_program_for_wb(src)
  guard program.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let outer = program.main.children[0]
  guard outer.children.length() == 1 else {
    abort("expected nested child function")
  }
  let inner = outer.children[0]
  guard inner.local_names.length() > 0 else {
    abort("expected nested local slots")
  }
  let instruction_index = mutate_first_indexed_operand_for_wb(
    inner,
    LocalSlot,
    -1,
  )
  let defect = expect_indexed_operand_defect_for_wb(
    program,
    [0, 0],
    instruction_index,
  )
  match defect.family {
    LocalSlot => ()
    _ => fail("expected local-slot family")
  }
  assert_eq(defect.exclusive_upper_bound, inner.local_names.length())
  assert_eq(defect.actual_operand, -1)
}

///|
fn expect_shape_operand_defect_for_wb(
  program : BytecodeUnverifiedProgram,
  expected_path : Array[Int],
  expected_instruction : Int,
) -> BytecodeShapeOperandTargetDefect raise Error {
  try {
    let _ = finalize_bytecode_program(program)
    fail("expected typed shape operand defect")
  } catch {
    BytecodeShapeOperandDefect(defect) => {
      assert_eq(defect.function_path, expected_path)
      assert_eq(defect.instruction_index, expected_instruction)
      defect
    }
    _ => fail("expected typed shape operand defect")
  }
}

///|
test "shape operand verifier rejects negative fixed array element counts" {
  let program = unverified_source_program_for_wb("[1];")
  let mut instruction_index : Int? = None
  for index, instruction in program.main.code {
    match instruction {
      MakeArray(_) => {
        program.main.code[index] = MakeArray(-1)
        instruction_index = Some(index)
        break
      }
      _ => ()
    }
  }
  let instruction_index = match instruction_index {
    Some(index) => index
    None => abort("expected MakeArray instruction")
  }
  let defect = expect_shape_operand_defect_for_wb(
    program,
    [],
    instruction_index,
  )
  match defect.family {
    ArrayElementCount => ()
    _ => fail("expected array element count family")
  }
  assert_eq(defect.expected_lower_bound, 0)
  assert_eq(defect.exclusive_upper_bound, Some(program.main.code.length() + 1))
  assert_eq(defect.actual_operand, -1)
}

///|
test "RED: shape operand verifier rejects negative holey array counts" {
  let program = unverified_source_program_for_wb("[1,,3];")
  let mut instruction_index : Int? = None
  for index, instruction in program.main.code {
    match instruction {
      MakeArrayWithHoles(_, hole_indices) => {
        program.main.code[index] = MakeArrayWithHoles(-1, hole_indices)
        instruction_index = Some(index)
        break
      }
      _ => ()
    }
  }
  let instruction_index = match instruction_index {
    Some(index) => index
    None => abort("expected MakeArrayWithHoles instruction")
  }
  let defect = expect_shape_operand_defect_for_wb(
    program,
    [],
    instruction_index,
  )
  match defect.family {
    ArrayElementCount => ()
    _ => fail("expected array element count family")
  }
  assert_eq(defect.actual_operand, -1)
}

///|
test "RED: shape operand verifier rejects hole indices outside the array" {
  for invalid_hole in [-1, 3] {
    let program = unverified_source_program_for_wb("[1,,3];")
    let mut instruction_index : Int? = None
    for index, instruction in program.main.code {
      match instruction {
        MakeArrayWithHoles(count, _) => {
          program.main.code[index] = MakeArrayWithHoles(count, [invalid_hole])
          instruction_index = Some(index)
          break
        }
        _ => ()
      }
    }
    let instruction_index = match instruction_index {
      Some(index) => index
      None => abort("expected MakeArrayWithHoles instruction")
    }
    let defect = expect_shape_operand_defect_for_wb(
      program,
      [],
      instruction_index,
    )
    match defect.family {
      ArrayHoleIndex => ()
      _ => fail("expected array hole index family")
    }
    assert_eq(defect.expected_lower_bound, 0)
    assert_eq(defect.exclusive_upper_bound, Some(3))
    assert_eq(defect.actual_operand, invalid_hole)
  }
}

///|
priv enum FixedCallOpcodeForWb {
  PlainCall
  ReceiverCall
  Construction
}

///|
fn mutate_fixed_call_count_for_wb(
  function : BytecodeFunction,
  opcode : FixedCallOpcodeForWb,
  count : Int,
) -> Int {
  for instruction_index, instruction in function.code {
    match (instruction, opcode) {
      (Call(_, loc), PlainCall) => {
        function.code[instruction_index] = Call(count, loc)
        return instruction_index
      }
      (CallWithReceiver(_, loc), ReceiverCall) => {
        function.code[instruction_index] = CallWithReceiver(count, loc)
        return instruction_index
      }
      (Construct(_, loc), Construction) => {
        function.code[instruction_index] = Construct(count, loc)
        return instruction_index
      }
      _ => ()
    }
  }
  abort("expected fixed-count call opcode")
}

///|
test "RED: shape operand verifier rejects negative fixed call counts" {
  let fixtures : Array[(FixedCallOpcodeForWb, String)] = [
    (PlainCall, "f(1);"),
    (ReceiverCall, "object.f(1);"),
    (Construction, "new F(1);"),
  ]
  for fixture in fixtures {
    let (opcode, source) = fixture
    let program = unverified_source_program_for_wb(source)
    let instruction_index = mutate_fixed_call_count_for_wb(
      program.main,
      opcode,
      -1,
    )
    let defect = expect_shape_operand_defect_for_wb(
      program,
      [],
      instruction_index,
    )
    match defect.family {
      CallArgumentCount => ()
      _ => fail("expected call argument count family")
    }
    assert_eq(defect.expected_lower_bound, 0)
    assert_eq(
      defect.exclusive_upper_bound,
      Some(program.main.code.length() + 1),
    )
    assert_eq(defect.actual_operand, -1)
  }
}

///|
test "shape operand verifier rejects counts too large for the function" {
  let program = unverified_source_program_for_wb("object.f(1);")
  let invalid_count = program.main.code.length() + 1
  let instruction_index = mutate_fixed_call_count_for_wb(
    program.main,
    ReceiverCall,
    invalid_count,
  )
  let defect = expect_shape_operand_defect_for_wb(
    program,
    [],
    instruction_index,
  )
  match defect.family {
    CallArgumentCount => ()
    _ => fail("expected call argument count family")
  }
  assert_eq(defect.exclusive_upper_bound, Some(program.main.code.length() + 1))
  assert_eq(defect.actual_operand, invalid_count)
}

///|
test "shape operand verifier reports nested function provenance" {
  let program = unverified_source_program_for_wb(
    "function child() { return f(1); } child();",
  )
  guard program.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let instruction_index = mutate_fixed_call_count_for_wb(
    program.main.children[0],
    PlainCall,
    -1,
  )
  let defect = expect_shape_operand_defect_for_wb(
    program,
    [0],
    instruction_index,
  )
  match defect.family {
    CallArgumentCount => ()
    _ => fail("expected call argument count family")
  }
  assert_eq(defect.actual_operand, -1)
}

///|
test "shape operand verifier accepts valid boundary and lowering operands" {
  let sources = [
    "[];", "[1,,3];", "f();", "object.f();", "new F();", "function child() { return [,,]; } child();",
  ]
  for source in sources {
    let program = unverified_source_program_for_wb(source)
    let finalized = finalize_bytecode_program(program)
    assert_eq(finalized.main.code.length(), program.main.code.length())
  }
}

///|
fn expect_frame_shape_defect_for_wb(
  program : BytecodeUnverifiedProgram,
  expected_path : Array[Int],
  expected_instruction : Int,
) -> BytecodeFrameShapeDefect raise Error {
  try {
    let _ = finalize_bytecode_program(program)
    fail("expected typed frame-shape defect")
  } catch {
    BytecodeFrameShapeDefect(defect) => {
      assert_eq(defect.function_path, expected_path)
      assert_eq(defect.instruction_index, expected_instruction)
      defect
    }
    _ => fail("expected typed frame-shape defect")
  }
}

///|
test "frame-shape verifier rejects reachable operand stack underflow" {
  let program = unverified_source_program_for_wb("var value = 1;")
  let mut load_index : Int? = None
  for instruction_index, instruction in program.main.code {
    match instruction {
      LoadConst(_) => {
        program.main.code[instruction_index] = SetCompletionValue(
          Value::Undefined,
        )
        load_index = Some(instruction_index)
        break
      }
      _ => ()
    }
  }
  let instruction_index = match load_index {
    Some(index) => index + 1
    None => abort("expected LoadConst instruction")
  }
  let defect = expect_frame_shape_defect_for_wb(program, [], instruction_index)
  match defect.invariant {
    ResourceUnderflow => ()
    _ => fail("expected resource-underflow invariant")
  }
  assert_eq(defect.predecessor_index, None)
  assert_eq(defect.expected.operand_stack_height, 1)
  assert_eq(defect.actual.operand_stack_height, 0)
}

///|
test "frame-shape verifier rejects argument-list underflow" {
  let program = unverified_source_program_for_wb("f(...values);")
  let mut start_index : Int? = None
  for instruction_index, instruction in program.main.code {
    match instruction {
      StartArgs => {
        program.main.code[instruction_index] = SetCompletionValue(
          Value::Undefined,
        )
        start_index = Some(instruction_index)
        break
      }
      _ => ()
    }
  }
  let start_index = match start_index {
    Some(index) => index
    None => abort("expected StartArgs instruction")
  }
  let mut push_index : Int? = None
  for instruction_index = start_index + 1
      instruction_index < program.main.code.length()
      instruction_index = instruction_index + 1 {
    match program.main.code[instruction_index] {
      ArgPushValue | ArgPushSpread(_) => {
        push_index = Some(instruction_index)
        break
      }
      _ => ()
    }
  }
  let push_index = match push_index {
    Some(index) => index
    None => abort("expected argument push instruction")
  }
  let defect = expect_frame_shape_defect_for_wb(program, [], push_index)
  match defect.invariant {
    ResourceUnderflow => ()
    _ => fail("expected resource-underflow invariant")
  }
  assert_eq(defect.expected.argument_list_depth, 1)
  assert_eq(defect.actual.argument_list_depth, 0)
}

///|
test "frame-shape verifier rejects unequal control-flow joins" {
  let program = unverified_source_program_for_wb(
    "if (condition) { value = 1; } else { value = 2; }",
  )
  let mut mutated_index : Int? = None
  for instruction_index, instruction in program.main.code {
    match instruction {
      SetCompletion => {
        program.main.code[instruction_index] = SetCompletionValue(
          Value::Undefined,
        )
        mutated_index = Some(instruction_index)
        break
      }
      _ => ()
    }
  }
  guard mutated_index is Some(_) else {
    abort("expected SetCompletion instruction")
  }
  let mut defect : BytecodeFrameShapeDefect? = None
  try {
    let _ = finalize_bytecode_program(program)
  } catch {
    BytecodeFrameShapeDefect(actual) => defect = Some(actual)
    _ => fail("expected typed frame-shape defect")
  }
  let defect = defect.unwrap()
  assert_eq(defect.function_path, [])
  match defect.invariant {
    ControlFlowJoin => ()
    _ => fail("expected control-flow-join invariant")
  }
  assert_true(
    defect.expected.operand_stack_height != defect.actual.operand_stack_height,
  )
}

///|
test "frame-shape verifier rejects terminal auxiliary-state residue" {
  let program = unverified_source_program_for_wb("f(...values);")
  let mut call_index : Int? = None
  for instruction_index, instruction in program.main.code {
    match instruction {
      CallSpread(loc) => {
        program.main.code[instruction_index] = Call(0, loc)
        call_index = Some(instruction_index)
        break
      }
      _ => ()
    }
  }
  guard call_index is Some(_) else { abort("expected CallSpread instruction") }
  let mut defect : BytecodeFrameShapeDefect? = None
  try {
    let _ = finalize_bytecode_program(program)
  } catch {
    BytecodeFrameShapeDefect(actual) => defect = Some(actual)
    _ => fail("expected typed frame-shape defect")
  }
  let defect = defect.unwrap()
  match defect.invariant {
    TerminalShape => ()
    _ => fail("expected terminal-shape invariant")
  }
  assert_eq(defect.expected.argument_list_depth, 0)
  assert_eq(defect.actual.argument_list_depth, 1)
}

///|
test "frame-shape verifier rejects for-in iterator residue" {
  let program = unverified_source_program_for_wb(
    "var key; for (key in object) { value = key; }",
  )
  let mut branch_index : Int? = None
  for instruction_index, instruction in program.main.code {
    match instruction {
      ForInNext(target) => {
        program.main.code[instruction_index] = Jump(target)
        branch_index = Some(instruction_index)
        break
      }
      _ => ()
    }
  }
  guard branch_index is Some(_) else { abort("expected ForInNext instruction") }
  let mut defect : BytecodeFrameShapeDefect? = None
  try {
    let _ = finalize_bytecode_program(program)
  } catch {
    BytecodeFrameShapeDefect(actual) => defect = Some(actual)
    _ => fail("expected typed frame-shape defect")
  }
  let defect = defect.unwrap()
  match defect.invariant {
    TerminalShape => ()
    _ => fail("expected terminal-shape invariant")
  }
  assert_eq(defect.expected.for_in_iterator_depth, 0)
  assert_eq(defect.actual.for_in_iterator_depth, 1)
}

///|
test "frame-shape verifier reports nested function provenance" {
  let program = unverified_source_program_for_wb(
    "function child() { var value = 1; } child();",
  )
  guard program.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = program.main.children[0]
  let mut load_index : Int? = None
  for instruction_index, instruction in child.code {
    match instruction {
      LoadConst(_) => {
        child.code[instruction_index] = SetCompletionValue(Value::Undefined)
        load_index = Some(instruction_index)
        break
      }
      _ => ()
    }
  }
  let instruction_index = match load_index {
    Some(index) => index + 1
    None => abort("expected nested LoadConst instruction")
  }
  let defect = expect_frame_shape_defect_for_wb(program, [0], instruction_index)
  match defect.invariant {
    ResourceUnderflow => ()
    _ => fail("expected resource-underflow invariant")
  }
}

///|
test "frame-shape verifier accepts representative resource topologies" {
  let sources = [
    "if (condition) { value = 1; } else { value = 2; }", "while (condition) { if (stop) break; continue; }",
    "var key; for (key in object) { if (stop) break; }", "f(...values); object.f(...values); new F(...values);",
    "object?.value?.next;", "function child(value) { return value + 1; } child(1);",
    "({ method() { return 1; }, [key]() { return 2; } });",
  ]
  for source in sources {
    let program = unverified_source_program_for_wb(source)
    let finalized = finalize_bytecode_program(program)
    assert_eq(finalized.main.code.length(), program.main.code.length())
  }
}

///|
test "frame-shape verifier permits throw to discard active for-in state" {
  let program = unverified_source_program_for_wb(
    "var key; for (key in object) { throw key; }",
  )
  let finalized = finalize_bytecode_program(program)
  assert_eq(finalized.main.code.length(), program.main.code.length())
}

///|
test "frame-shape verifier permits return to discard active for-in state" {
  let program = unverified_source_program_for_wb(
    "function first(object) { var key; for (key in object) { return key; } return undefined; }",
  )
  let finalized = finalize_bytecode_program(program)
  assert_eq(finalized.main.children.length(), 1)
  assert_eq(
    finalized.main.children[0].code.length(),
    program.main.children[0].code.length(),
  )
}

///|
test "frame-shape verifier still rejects residual operands at throw" {
  let program = unverified_source_program_for_wb("value; throw error;")
  let mut mutated = false
  for instruction_index, instruction in program.main.code {
    match instruction {
      SetCompletion => {
        program.main.code[instruction_index] = LoadUndefined
        mutated = true
        break
      }
      _ => ()
    }
  }
  guard mutated else { abort("expected SetCompletion instruction") }
  let mut defect : BytecodeFrameShapeDefect? = None
  try {
    let _ = finalize_bytecode_program(program)
  } catch {
    BytecodeFrameShapeDefect(actual) => defect = Some(actual)
    _ => fail("expected typed frame-shape defect")
  }
  let defect = defect.unwrap()
  match defect.invariant {
    TerminalShape => ()
    _ => fail("expected terminal-shape invariant")
  }
  assert_true(defect.actual.operand_stack_height > 0)
  assert_eq(defect.expected.operand_stack_height, 0)
}

///|
fn expect_control_flow_defect_for_wb(
  program : BytecodeUnverifiedProgram,
  expected_path : Array[Int],
  expected_instruction : Int,
) -> BytecodeControlFlowTargetDefect raise Error {
  try {
    let _ = finalize_bytecode_program(program)
    fail("expected typed control-flow verifier defect")
  } catch {
    BytecodeControlFlowDefect(defect) => {
      assert_eq(defect.function_path, expected_path)
      assert_eq(defect.instruction_index, expected_instruction)
      defect
    }
    _ => fail("expected typed control-flow verifier defect")
  }
}

///|
priv enum ControlFlowOpcodeForWb {
  Jump
  JumpIfFalse
  JumpIfFalseKeep
  JumpIfTrueKeep
  JumpIfNotNullishKeep
  JumpIfNotOptionalChainShortCircuitKeep
  ForInNext
}

///|
fn is_control_flow_opcode_for_wb(
  instruction : BytecodeInstr,
  opcode : ControlFlowOpcodeForWb,
) -> Bool {
  match (instruction, opcode) {
    (Jump(_), Jump)
    | (JumpIfFalse(_), JumpIfFalse)
    | (JumpIfFalseKeep(_), JumpIfFalseKeep)
    | (JumpIfTrueKeep(_), JumpIfTrueKeep)
    | (JumpIfNotNullishKeep(_), JumpIfNotNullishKeep)
    | (
      JumpIfNotOptionalChainShortCircuitKeep(_),
      JumpIfNotOptionalChainShortCircuitKeep,
    )
    | (ForInNext(_), ForInNext) => true
    _ => false
  }
}

///|
fn bytecode_instruction_with_target_for_wb(
  instruction : BytecodeInstr,
  target : Int,
) -> BytecodeInstr {
  match instruction {
    Jump(_) => Jump(target)
    JumpIfFalse(_) => JumpIfFalse(target)
    JumpIfFalseKeep(_) => JumpIfFalseKeep(target)
    JumpIfTrueKeep(_) => JumpIfTrueKeep(target)
    JumpIfNotNullishKeep(_) => JumpIfNotNullishKeep(target)
    JumpIfNotOptionalChainShortCircuitKeep(_) =>
      JumpIfNotOptionalChainShortCircuitKeep(target)
    ForInNext(_) => ForInNext(target)
    _ => instruction
  }
}

///|
fn mutate_first_control_flow_target_for_wb(
  function : BytecodeFunction,
  opcode : ControlFlowOpcodeForWb,
  target : Int,
) -> Int {
  for instruction_index, instruction in function.code {
    if is_control_flow_opcode_for_wb(instruction, opcode) {
      function.code[instruction_index] = bytecode_instruction_with_target_for_wb(
        instruction, target,
      )
      return instruction_index
    }
  }
  abort("expected destination-bearing opcode")
}

///|
test "control-flow verifier rejects invalid targets for every destination opcode" {
  let fixtures : Array[(ControlFlowOpcodeForWb, String)] = [
    (Jump, "if (true) 1; else 2;"),
    (JumpIfFalse, "if (true) 1; else 2;"),
    (JumpIfFalseKeep, "false && 1;"),
    (JumpIfTrueKeep, "true || 1;"),
    (JumpIfNotNullishKeep, "var value = object?.value;"),
    (JumpIfNotOptionalChainShortCircuitKeep, "var value = object?.value.next;"),
    (ForInNext, "var key; for (key in object) { break; }"),
  ]
  for fixture in fixtures {
    let (opcode, source) = fixture
    let program = unverified_source_program_for_wb(source)
    let instruction_index = mutate_first_control_flow_target_for_wb(
      program.main,
      opcode,
      -1,
    )
    let defect = expect_control_flow_defect_for_wb(
      program,
      [],
      instruction_index,
    )
    assert_eq(defect.expected_lower_bound, 0)
    assert_eq(defect.expected_upper_bound, program.main.code.length())
    assert_eq(defect.actual_target, -1)
  }
}

///|
test "control-flow verifier rejects targets above the terminal boundary" {
  let program = unverified_source_program_for_wb("if (true) 1; else 2;")
  let target = program.main.code.length() + 1
  let instruction_index = mutate_first_control_flow_target_for_wb(
    program.main,
    JumpIfFalse,
    target,
  )
  let defect = expect_control_flow_defect_for_wb(program, [], instruction_index)
  assert_eq(defect.expected_lower_bound, 0)
  assert_eq(defect.expected_upper_bound, program.main.code.length())
  assert_eq(defect.actual_target, target)
}

///|
test "control-flow verifier accepts the inclusive terminal boundary" {
  let program = unverified_source_program_for_wb("if (true) 1; else 2;")
  let terminal = program.main.code.length()
  let instruction_index = mutate_first_control_flow_target_for_wb(
    program.main,
    JumpIfFalse,
    terminal,
  )
  let finalized = finalize_bytecode_program(program)
  match finalized.main.code[instruction_index] {
    JumpIfFalse(target) => assert_eq(target, terminal)
    _ => fail("expected mutated conditional jump")
  }
}

///|
test "control-flow verifier accepts zero and in-range targets" {
  let zero_program = unverified_source_program_for_wb("if (true) 1; else 2;")
  let zero_index = mutate_first_control_flow_target_for_wb(
    zero_program.main,
    JumpIfFalse,
    0,
  )
  let zero_finalized = finalize_bytecode_program(zero_program)
  match zero_finalized.main.code[zero_index] {
    JumpIfFalse(target) => assert_eq(target, 0)
    _ => fail("expected zero-target conditional jump")
  }

  let in_range_program = unverified_source_program_for_wb(
    "if (true) 1; else 2;",
  )
  let in_range_target = 1
  let in_range_index = mutate_first_control_flow_target_for_wb(
    in_range_program.main,
    JumpIfFalse,
    in_range_target,
  )
  guard in_range_target < in_range_program.main.code.length() else {
    abort("expected an in-range instruction target")
  }
  let in_range_finalized = finalize_bytecode_program(in_range_program)
  match in_range_finalized.main.code[in_range_index] {
    JumpIfFalse(target) => assert_eq(target, in_range_target)
    _ => fail("expected in-range conditional jump")
  }
}

///|
test "control-flow verifier reports nested function provenance" {
  let src =
    #|function child() { if (true) 1; else 2; }
    #|child();
  let program = unverified_source_program_for_wb(src)
  guard program.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let instruction_index = mutate_first_control_flow_target_for_wb(
    program.main.children[0],
    JumpIfFalse,
    -1,
  )
  let defect = expect_control_flow_defect_for_wb(
    program,
    [0],
    instruction_index,
  )
  assert_eq(defect.expected_lower_bound, 0)
  assert_eq(defect.expected_upper_bound, program.main.children[0].code.length())
  assert_eq(defect.actual_target, -1)
}

///|
test "control-flow verifier defects are deterministic" {
  let source = "if (true) 1; else 2;"
  let left = unverified_source_program_for_wb(source)
  let right = unverified_source_program_for_wb(source)
  let left_target = left.main.code.length() + 1
  let right_target = right.main.code.length() + 1
  let left_index = mutate_first_control_flow_target_for_wb(
    left.main,
    JumpIfFalse,
    left_target,
  )
  let right_index = mutate_first_control_flow_target_for_wb(
    right.main,
    JumpIfFalse,
    right_target,
  )
  let left_defect = expect_control_flow_defect_for_wb(left, [], left_index)
  let right_defect = expect_control_flow_defect_for_wb(right, [], right_index)
  assert_eq(left_defect.function_path, right_defect.function_path)
  assert_eq(left_defect.instruction_index, right_defect.instruction_index)
  assert_eq(left_defect.expected_lower_bound, right_defect.expected_lower_bound)
  assert_eq(left_defect.expected_upper_bound, right_defect.expected_upper_bound)
  assert_eq(left_defect.actual_target, right_defect.actual_target)
}

///|
test "control-flow verifier accepts representative valid programs" {
  let src =
    #|var object = {};
    #|if (true) { object.x = 1; } else { object.x = 2; }
    #|while (false) { break; }
    #|do { continue; } while (false);
    #|for (var i = 0; i < 1; i++) { if (i) continue; }
    #|switch (object.x) { case 1: break; default: break; }
    #|var key;
    #|for (key in object) { if (key) break; }
    #|var and_value = false && 1;
    #|var or_value = true || 1;
    #|var optional_value = object?.x;
  let program = unverified_source_program_for_wb(src)
  let _ = finalize_bytecode_program(program)
}

///|
test "control-flow terminal target falls out with normal completion" {
  let program = unverified_source_program_for_wb("1; if (false) 2;")
  let code_length = program.main.code.length()
  let mut jump_index : Int? = None
  for instruction_index, instruction in program.main.code {
    match instruction {
      JumpIfFalse(_) => {
        program.main.code[instruction_index] = JumpIfFalse(code_length)
        jump_index = Some(instruction_index)
        break
      }
      _ => ()
    }
  }
  let _ = match jump_index {
    Some(index) => index
    None => abort("expected conditional jump")
  }
  let finalized = finalize_bytecode_program(program)
  let value = finalized.run(@interpreter.new_interpreter())
  assert_eq(value.to_string(), "1")
}
