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
