///|
fn parse_bytecode_for_wb(src : String) -> BytecodeProgram {
  let prog = @parser.parse(src) catch { _ => abort("parse raised") }
  compile_script_to_bytecode(prog.stmts) catch {
    _ => abort("bytecode compile raised")
  }
}

///|
fn source_table_has_role_for_wb(
  source_points : Array[SourcePoint],
  role : SourcePointRole,
) -> Bool {
  for source_point in source_points {
    if source_point.role == role {
      return true
    }
  }
  false
}

///|
test "RED: private finalization rejects malformed source metadata" {
  let parsed = @parser.parse("1;")
  let malformed = build_script_bytecode(parsed.stmts)
  let code_length = malformed.main.code.length()
  let _ = malformed.main.instruction_sources.pop()
  try {
    let _ = finalize_bytecode_program(malformed)
    fail("expected typed verifier defect")
  } catch {
    BytecodeVerifierDefect(
      { function_path, instruction_index, invariant, expected, actual }
    ) => {
      assert_eq(function_path, [])
      assert_eq(instruction_index, None)
      match invariant {
        InstructionSourceCount => ()
        _ => fail("expected instruction source count defect")
      }
      match (expected, actual) {
        (CodeLength(expected), InstructionSourcesLength(actual)) => {
          assert_eq(expected, code_length)
          assert_eq(actual, code_length - 1)
        }
        _ => fail("expected source-count facts")
      }
    }
    _ => fail("expected typed verifier defect")
  }
}

///|
fn activation_reason_matches_for_wb(
  actual : BytecodeActivationUnsupportedReason,
  expected : BytecodeActivationUnsupportedReason,
) -> Bool {
  match (actual, expected) {
    (DirectEval, DirectEval)
    | (SuperComputedPropertyCall, SuperComputedPropertyCall)
    | (ArgumentSpread, ArgumentSpread)
    | (BinaryOperation, BinaryOperation)
    | (SynchronousPropertyAssignment, SynchronousPropertyAssignment)
    | (
      SynchronousComputedPropertyAssignment,
      SynchronousComputedPropertyAssignment,
    )
    | (ConditionalComputedProperty, ConditionalComputedProperty) => true
    _ => false
  }
}

///|
fn assert_instruction_contract_for_wb(
  instr : BytecodeInstr,
  may_raise_js : Bool,
  activation_disposition : BytecodeActivationDisposition,
  required_source_roles : Array[SourcePointRole],
) -> Unit raise Error {
  let contract = bytecode_instruction_contract(instr)
  assert_eq(contract.may_raise_js, may_raise_js)
  match (contract.activation_disposition, activation_disposition) {
    (SynchronousLeaf, SynchronousLeaf) | (ManagedSuspension, ManagedSuspension) => ()
    (
      UnsupportedBeforeActivation(actual),
      UnsupportedBeforeActivation(expected),
    ) => assert_true(activation_reason_matches_for_wb(actual, expected))
    _ => fail("activation disposition mismatch")
  }
  assert_eq(contract.required_source_roles, required_source_roles)
  assert_true(contract.observation_barrier is NotObservationBarrier)
}

///|
test "RED: bytecode instruction contracts retain semantic source roles" {
  let loc = @token.Loc::default()
  assert_instruction_contract_for_wb(Throw, true, SynchronousLeaf, [Throw])
  assert_instruction_contract_for_wb(Call(0, loc), true, ManagedSuspension, [Call])
  assert_instruction_contract_for_wb(CallDirectEval(loc), true, UnsupportedBeforeActivation(DirectEval), [
    DirectEval,
    Call,
  ])
  assert_instruction_contract_for_wb(
    PreparePlainPropertyCall("method", loc),
    true,
    ManagedSuspension,
    [MemberAccess],
  )
  assert_instruction_contract_for_wb(
    UpdateProperty("count", Increment, true, loc, loc),
    true,
    ManagedSuspension,
    [MemberAccess, Operator],
  )
  assert_instruction_contract_for_wb(
    SetForInProperty("count", loc),
    true,
    UnsupportedBeforeActivation(SynchronousPropertyAssignment),
    [MemberAccess],
  )
  assert_instruction_contract_for_wb(
    SetForInComputed(loc),
    true,
    UnsupportedBeforeActivation(SynchronousComputedPropertyAssignment),
    [MemberAccess, PropertyKey],
  )
  assert_instruction_contract_for_wb(
    PrepareSuperComputedCall(loc),
    true,
    UnsupportedBeforeActivation(SuperComputedPropertyCall),
    [SuperMemberAccess, PropertyKey],
  )
  assert_instruction_contract_for_wb(ArgPushSpread(loc), true, UnsupportedBeforeActivation(ArgumentSpread), [
    Spread,
    Iterator,
  ])
  assert_instruction_contract_for_wb(BinaryOp(Add, loc), true, UnsupportedBeforeActivation(BinaryOperation), [Operator])
  assert_instruction_contract_for_wb(LoadName("binding"), true, SynchronousLeaf, [
    BindingAccess,
  ])
  assert_instruction_contract_for_wb(MakeRegExp("a", ""), true, SynchronousLeaf, [
    ExpressionEntry,
  ])
  assert_instruction_contract_for_wb(MakeFunction(0), true, SynchronousLeaf, [
    ExpressionEntry,
  ])
  assert_instruction_contract_for_wb(MakeNamedFunction(0, "f"), true, SynchronousLeaf, [
    ExpressionEntry,
  ])
  assert_instruction_contract_for_wb(MakeMethodFunction(0), true, SynchronousLeaf, [
    ExpressionEntry,
  ])
  assert_instruction_contract_for_wb(
    MakeComputedMethodFunction(0),
    true,
    SynchronousLeaf,
    [ExpressionEntry],
  )
  assert_instruction_contract_for_wb(MakeArrowFunction(0), true, SynchronousLeaf, [
    ExpressionEntry,
  ])
}

///|
test "RED: activation contract distinguishes leaf managed and unsupported" {
  let loc = @token.Loc::default()
  let leaf = bytecode_instruction_contract(LoadConst(Value::Undefined))
  let managed = bytecode_instruction_contract(Call(0, loc))
  let conditional = bytecode_instruction_contract(GetComputed(loc))
  match leaf.activation_disposition {
    SynchronousLeaf => ()
    _ => fail("constant load must be a synchronous leaf")
  }
  match managed.activation_disposition {
    ManagedSuspension => ()
    _ => fail("ordinary call must use managed suspension")
  }
  match conditional.activation_disposition {
    UnsupportedBeforeActivation(ConditionalComputedProperty) => ()
    _ => fail("conditional computed access must be unsupported before activation")
  }
}

///|
test "activation selection is per function and precedes frame construction" {
  let src =
    #|function child() { return 1 + 2; }
    #|1;
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  match select_bytecode_function_activation(bytecode.main, []) {
    Ok(SynchronousLeaf) => ()
    Ok(ManagedSuspension) =>
      fail("unsupported child body must not taint the parent")
    Ok(UnsupportedBeforeActivation(_)) =>
      fail("parent has no unsupported instruction")
    Err(_) => fail("parent activation must be selectable")
  }
  let child = bytecode.main.children[0]
  match select_bytecode_function_activation(child, [0]) {
    Err(unsupported) => {
      assert_eq(unsupported.function_path, [0])
      match unsupported.reason {
        BinaryOperation => ()
        _ => fail("child must retain its own binary-operation reason")
      }
      assert_true(unsupported.instruction_index >= 0)
    }
    Ok(_) => fail("unsupported child must be rejected at its own activation")
  }
}

///|
test "activation selection recomputes typed reasons without a cached summary" {
  let loc = @token.Loc::default()
  let bytecode = parse_bytecode_for_wb("1;")
  match bytecode_function_activation_disposition(bytecode.main, []) {
    SynchronousLeaf => ()
    _ => fail("literal-only function must be a synchronous leaf")
  }
  bytecode.main.code.push(BinaryOp(Add, loc))
  match select_bytecode_function_activation(bytecode.main, []) {
    Err(unsupported) => {
      match unsupported.reason {
        BinaryOperation => ()
        _ => fail("recomputed reason must identify binary operation")
      }
    }
    Ok(_) => fail("stale eligibility must not remain accepted")
  }
}

///|
test "RED: bytecode functions own typed source tables" {
  let src =
    #|function failer() { throw 1; }
    #|failer();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = bytecode.main.children[0]
  guard bytecode.main.source_points.length() > 0 else {
    abort("root function must own source points")
  }
  guard child.source_points.length() > 0 else {
    abort("nested function must own source points")
  }
  assert_eq(bytecode.main.source_unit, child.source_unit)
  let root_point = bytecode.main.resolve_source_point(
    SourcePointId(
      bytecode.main.source_unit,
      bytecode.main.source_point_owner,
      0,
    ),
  )
  let child_point = child.resolve_source_point(
    SourcePointId(child.source_unit, child.source_point_owner, 0),
  )
  assert_eq(root_point.source_unit, bytecode.main.source_unit)
  assert_eq(child_point.source_unit, child.source_unit)
  assert_true(
    source_table_has_role_for_wb(bytecode.main.source_points, StatementEntry),
  )
  assert_true(
    source_table_has_role_for_wb(bytecode.main.source_points, ExpressionEntry),
  )
  assert_true(source_table_has_role_for_wb(bytecode.main.source_points, Call))
  assert_true(source_table_has_role_for_wb(child.source_points, StatementEntry))
  assert_true(
    source_table_has_role_for_wb(child.source_points, ExpressionEntry),
  )
  assert_true(source_table_has_role_for_wb(child.source_points, Throw))
}

///|
fn instruction_source_roles_for_wb(
  function : BytecodeFunction,
  instruction_index : Int,
) -> Array[SourcePointRole] {
  function.instruction_sources[instruction_index].map(source_id => {
    function.resolve_source_point(source_id).role
  })
}

///|
fn assert_function_instruction_sources_for_wb(
  function : BytecodeFunction,
) -> Unit raise Error {
  assert_eq(function.instruction_sources.length(), function.code.length())
  for instruction_index, instruction in function.code {
    let expected = bytecode_instruction_contract(instruction).required_source_roles
    let actual = instruction_source_roles_for_wb(function, instruction_index)
    assert_eq(actual, expected)
  }
  for child in function.children {
    assert_function_instruction_sources_for_wb(child)
  }
}

///|
test "RED: lowered instructions satisfy their source contracts" {
  let src =
    #|function invoke(object, key, values) {
    #|  object.value = object[key] + 1;
    #|  object[key]++;
    #|  var property;
    #|  for (property in object) {
    #|    if (property) break;
    #|  }
    #|  return object.method(...values);
    #|}
    #|invoke({ value: 0, method: function(x) { return x; } }, "value", [1]);
    #|var pattern = /a/;
    #|var ordinary = function() {};
    #|var named = function f() {};
    #|var arrow = () => 0;
    #|var methods = { method() {}, ["computed"]() {} };
    #|eval("1");
    #|throw 1;
    #|
  let bytecode = parse_bytecode_for_wb(src)
  assert_function_instruction_sources_for_wb(bytecode.main)
}

///|
fn assert_bytecode_internal_error_for_wb(
  stmts : Array[@ast.Stmt],
  expected_message : String,
) -> Unit raise Error {
  try {
    let _ = compile_script_to_bytecode(stmts)
    fail("expected InternalError")
  } catch {
    @errors.InternalError(message~) => assert_eq(message, expected_message)
    BytecodeUnsupportedSignal(_) =>
      fail("synthetic invariant must not select another executor")
    _ => fail("expected InternalError")
  }
}

///|
fn assert_bytecode_syntax_error_for_wb(
  stmts : Array[@ast.Stmt],
  expected_message : String,
) -> Unit raise Error {
  try {
    let _ = compile_script_to_bytecode(stmts)
    fail("expected SyntaxError")
  } catch {
    @errors.SyntaxError(message~) => assert_eq(message, expected_message)
    BytecodeUnsupportedSignal(_) =>
      fail("frontend diagnostic must not select another executor")
    _ => fail("expected SyntaxError")
  }
}

///|
test "bytecode classifies synthetic expression invariants and diagnostics" {
  let loc = @token.Loc::default()
  assert_bytecode_internal_error_for_wb(
    [ExprStmt(ArrayHole(loc), loc)],
    "bytecode array hole escaped array literal lowering at line 1, col 1",
  )
  assert_bytecode_internal_error_for_wb(
    [ExprStmt(SpreadExpr(Ident("x", loc), loc), loc)],
    "bytecode spread expression escaped list lowering at line 1, col 1",
  )
  assert_bytecode_syntax_error_for_wb(
    [
      ExprStmt(
        UpdateExpr(Increment, NumberLit(1.0, LexNormal, loc), true, loc),
        loc,
      ),
    ],
    "Invalid update target at line 1, col 1",
  )
  assert_bytecode_internal_error_for_wb(
    [ExprStmt(YieldExpr(Some(UndefinedLit(loc)), false, loc), loc)],
    "bytecode yield expression escaped generator lowering at line 1, col 1",
  )
  assert_bytecode_internal_error_for_wb(
    [ExprStmt(AwaitExpr(UndefinedLit(loc), loc), loc)],
    "bytecode await expression escaped async lowering at line 1, col 1",
  )
}

///|
fn lower_source_for_wb(
  src : String,
) -> Result[BytecodeProgram, BytecodeUnsupported] raise Error {
  let prog = @parser.parse(src)
  lower_script_to_bytecode(prog.stmts)
}

///|
test "bytecode lowering outcome compiles supported source" {
  match lower_source_for_wb("1 + 2;") {
    Ok(_) => ()
    Err(_) => fail("expected supported source to compile")
  }
}

///|
test "bytecode lowering outcome identifies valid unsupported source" {
  match lower_source_for_wb("for (var x of [1, 2]) {}") {
    Ok(_) => fail("expected for-of to be unsupported")
    Err(unsupported) => {
      assert_true(unsupported.reason is ForOfStatement)
      assert_eq(unsupported.loc.offset, 0)
    }
  }
}

///|
test "bytecode lowering outcome preserves frontend and early errors" {
  try {
    let _ = lower_source_for_wb("var obj = {}; obj?.tag`a${1}b`;")
    fail("expected parser SyntaxError")
  } catch {
    @errors.SyntaxError(message~) => assert_eq(message, "Bad_optional_template")
    _ => fail("expected parser SyntaxError")
  }
  let program = match lower_source_for_wb("\"use strict\"; delete x;") {
    Ok(program) => program
    Err(_) => fail("early-error fixture must lower successfully")
  }
  try {
    let _ = program.run(@interpreter.new_interpreter())
    fail("expected early SyntaxError")
  } catch {
    @runtime.JsException(value) =>
      assert_eq(
        value.to_string(),
        "SyntaxError: Delete of an unqualified identifier in strict mode.",
      )
    _ => fail("expected JavaScript SyntaxError")
  }
}

///|
test "bytecode lowering outcome keeps builder invariant defects internal" {
  let builder = BytecodeBuilder::BytecodeBuilder(
    { names: [], indices: Map([]), env_names: [], env_indices: Map([]) },
    "invariant-test",
    SourcePointOwnerId(0),
    new_source_point_owner_allocator(),
  )
  try {
    let _ = builder.pop_loop_context()
    fail("expected loop-context invariant defect")
  } catch {
    @errors.InternalError(message~) =>
      assert_eq(message, "bytecode loop context invariant violated")
    BytecodeUnsupportedSignal(_) =>
      fail("builder invariant must not be an unsupported outcome")
    _ => fail("expected InternalError")
  }
}

///|
test "bytecode unsupported selection does not mutate runtime state" {
  let src =
    #|console.log("must-not-run");
    #|for (var x of [1]) {}
  let prog = @parser.parse(src)
  let interp = @interpreter.new_interpreter()
  try {
    let _ = run_bytecode_script(interp, prog.stmts)
    fail("expected for-of to be unsupported")
  } catch {
    BytecodeUnsupportedSignal(unsupported) => {
      assert_true(unsupported.reason is ForOfStatement)
      json_inspect(interp.host.output, content=[])
    }
    _ => fail("expected typed bytecode unsupported signal")
  }
}

///|
test "structured equivalence classifies normal completion" {
  match structured_bytecode_compare("1 + 2;") {
    Equivalent(Completed(observation)) => {
      assert_eq(observation.value.rendered, "3")
      json_inspect(observation.effects.host_output, content=[])
      assert_true(observation.effects.queues.policy is LeavesQueuesPending)
    }
    _ => fail("expected typed normal-completion equivalence")
  }
}

///|
test "structured equivalence preserves JavaScript throw observations" {
  let src =
    #|function failer() { throw new TypeError("boom"); }
    #|failer();
  match structured_bytecode_compare(src) {
    Equivalent(Threw(observation)) => {
      assert_true(observation.exception.class_name == Some("TypeError"))
      assert_true(observation.exception.name == Some("TypeError"))
      assert_true(observation.exception.message == Some("boom"))
      assert_true(
        observation.exception.source_identity == Some(EQUIVALENCE_SOURCE_ID),
      )
    }
    _ => fail("expected typed JavaScript-throw equivalence")
  }
}

///|
test "structured equivalence consumes typed unsupported lowering" {
  match structured_bytecode_compare("for (var x of [1, 2]) {}") {
    UnsupportedSelected(unsupported) => {
      assert_true(unsupported.reason is ForOfStatement)
      assert_eq(unsupported.loc.offset, 0)
    }
    _ => fail("expected typed unsupported selection")
  }
}

///|
test "structured equivalence separates frontend diagnostics" {
  match structured_bytecode_compare("var = ;") {
    FrontendRejected(diagnostic) => {
      assert_true(diagnostic.stage is ParserFrontend)
      assert_eq(diagnostic.name, "SyntaxError")
    }
    _ => fail("expected parser diagnostic")
  }
  match structured_bytecode_compare("let x; var x;") {
    FrontendRejected(diagnostic) => {
      assert_true(diagnostic.stage is StaticSemanticsFrontend)
      assert_eq(diagnostic.message, "Identifier 'x' has already been declared")
    }
    _ => fail("expected static-semantics diagnostic")
  }
  match structured_bytecode_compare("while (true) { break missing; }") {
    FrontendRejected(diagnostic) => {
      assert_true(diagnostic.stage is StaticSemanticsFrontend)
      assert_eq(diagnostic.message, "Undefined label 'missing'")
    }
    _ => fail("expected lowering-time frontend diagnostic")
  }
}

///|
test "structured equivalence mismatch retains expected and actual" {
  let expected = synthetic_completed_outcome_for_wb("same", ["first"])
  let actual = synthetic_completed_outcome_for_wb("same", ["second"])
  match reduce_equivalence(Some(expected), actual) {
    ObservableMismatch(Completed(expected), Completed(actual)) => {
      assert_eq(expected.value.rendered, "same")
      assert_eq(actual.value.rendered, "same")
      json_inspect(expected.effects.host_output, content=["first"])
      json_inspect(actual.effects.host_output, content=["second"])
    }
    _ => fail("expected typed observable mismatch")
  }
}

///|
test "structured equivalence separates compiler invariant defects" {
  let loc = @token.Loc::default()
  let observed = observe_bytecode_stmts_for_equivalence(
    @interpreter.new_interpreter(),
    [ExprStmt(ArrayHole(loc), loc)],
  )
  match reduce_equivalence(None, observed) {
    CompilerOrVerifierDefect(defect) => {
      assert_true(defect.stage is LoweringDefect)
      assert_eq(
        defect.message,
        "bytecode array hole escaped array literal lowering at line 1, col 1",
      )
    }
    _ => fail("expected compiler/verifier defect category")
  }
}

///|
test "structured equivalence separates runtime engine defects" {
  match reduce_equivalence(None, synthetic_runtime_defect_outcome_for_wb()) {
    RuntimeEngineDefect(defect) => {
      assert_true(defect.stage is BytecodeRuntimeDefect)
      assert_eq(defect.message, "synthetic runtime invariant")
    }
    _ => fail("expected runtime engine defect category")
  }
}

///|
test "structured equivalence preserves VM invariant defects through run envelope" {
  let parsed = @parser.parse("1;")
  let program = match lower_script_to_bytecode(parsed.stmts) {
    Ok(program) => program
    Err(_) => fail("expected supported bytecode fixture")
  }
  program.main.code[0] = Pop
  let interp = @interpreter.new_interpreter()
  let observed = observe_execution(interp, BytecodeRuntimeDefect, () => {
    program.run(interp)
  })
  match reduce_equivalence(None, observed) {
    RuntimeEngineDefect(defect) => {
      assert_true(defect.stage is BytecodeRuntimeDefect)
      assert_eq(defect.message, "bytecode stack underflow")
    }
    _ => fail("expected VM invariant to remain a runtime engine defect")
  }
}

///|
test "structured equivalence preserves host output order" {
  let src =
    #|console.log("first");
    #|console.log("second");
    #|"done";
  match structured_bytecode_compare(src) {
    Equivalent(Completed(observation)) => {
      assert_eq(observation.value.rendered, "done")
      json_inspect(observation.effects.host_output, content=["first", "second"])
    }
    _ => fail("expected output-preserving normal equivalence")
  }
}

///|
test "structured unsupported outcome precedes runtime mutation" {
  let interp = @interpreter.new_interpreter()
  let src =
    #|console.log("must-not-run");
    #|queueMicrotask(function() {});
    #|for (var x of [1]) {}
  match observe_bytecode_source_with_interpreter(interp, src) {
    Unsupported(unsupported) =>
      assert_true(unsupported.reason is ForOfStatement)
    _ => fail("expected typed unsupported observation")
  }
  json_inspect(interp.host.output, content=[])
  assert_eq(interp.host.microtask_queue.length(), 0)
  assert_eq(interp.host.timer_queue.length(), 0)
}

///|
test "structured equivalence records current pending queue policy" {
  let src =
    #|queueMicrotask(function() { console.log("microtask"); });
    #|setTimeout(function() { console.log("timer"); }, 0);
    #|console.log("sync");
    #|"done";
  match structured_bytecode_compare(src) {
    Equivalent(Completed(observation)) => {
      json_inspect(observation.effects.host_output, content=["sync"])
      assert_true(observation.effects.queues.policy is LeavesQueuesPending)
      assert_eq(observation.effects.queues.microtasks, 1)
      assert_eq(observation.effects.queues.timers, 1)
    }
    _ => fail("expected pending-queue equivalence")
  }
}

///|
test "RED: structured equivalence requires bytecode step observation" {
  match structured_step_limit_comparison_for_wb("1 + 2;") {
    Equivalent(ControlStopped(observation)) => {
      assert_true(observation.point is DispatchStepObservation)
      assert_true(observation.failure is ExecutionLimit)
    }
    _ => fail("bytecode must stop at the same typed step observation")
  }
  let activation = synthetic_control_outcome_for_wb(
    ActivationObservation,
    StackDepthLimit,
  )
  match reduce_equivalence(Some(activation), activation) {
    Equivalent(ControlStopped(observation)) => {
      assert_true(observation.point is ActivationObservation)
      assert_true(observation.failure is StackDepthLimit)
    }
    _ => fail("expected typed activation-limit observation")
  }
}

///|
fn assert_control_stopped_equivalently_for_wb(
  result : EquivalenceResult,
  failure : ExecutionControlFailure,
) -> Unit raise Error {
  match result {
    Equivalent(ControlStopped(observation)) => {
      assert_true(observation.point is DispatchStepObservation)
      assert_true(same_control_failure(observation.failure, failure))
    }
    _ => fail("bytecode and tree walker must stop at the same control point")
  }
}

///|
fn exact_matching_completion_budget_for_wb(
  source : String,
  maximum_budget : Int,
) -> Int raise Error {
  for budget in 0..<=maximum_budget {
    match
      structured_execution_policy_comparison_for_wb(source, budget.to_int64()) {
      Equivalent(ControlStopped(observation)) => {
        assert_true(observation.point is DispatchStepObservation)
        assert_true(observation.failure is ExecutionLimit)
      }
      Equivalent(Completed(_)) => return budget
      _ =>
        fail(
          "tree walker and bytecode diverged at observation budget " +
          budget.to_string() +
          " for " +
          source,
        )
    }
  }
  fail("source did not complete within the observation frontier: " + source)
}

///|
fn lowered_observation_kinds_for_wb(
  source : String,
) -> Array[String] raise Error {
  let bytecode = parse_bytecode_for_wb(source)
  let kinds : Array[String] = []
  for instruction in bytecode.main.code {
    match instruction {
      ObserveStatement(source_id) => {
        let point = bytecode.main.resolve_source_point(source_id)
        assert_true(point.role is StatementEntry)
        kinds.push("statement")
      }
      ObserveExpression(source_id) => {
        let point = bytecode.main.resolve_source_point(source_id)
        assert_true(point.role is ExpressionEntry)
        kinds.push("expression")
      }
      _ => ()
    }
  }
  kinds
}

///|
test "lowered barriers retain statement and expression identity" {
  json_inspect(lowered_observation_kinds_for_wb("1 + 2 * 3;"), content=[
    "statement", "expression", "expression", "expression", "expression", "expression",
  ])
  json_inspect(lowered_observation_kinds_for_wb("if (false) 1; else 2;"), content=[
    "statement", "expression", "statement", "expression", "statement", "expression",
  ])
  json_inspect(lowered_observation_kinds_for_wb("false && 1;"), content=[
    "statement", "expression", "expression", "expression",
  ])
  json_inspect(lowered_observation_kinds_for_wb("while (false) 1;"), content=[
    "statement", "expression", "statement", "expression",
  ])
}

///|
test "bounded bytecode matches exact dynamic observation frontiers" {
  json_inspect(
    [
      exact_matching_completion_budget_for_wb("1 + 2;", 8),
      exact_matching_completion_budget_for_wb("if (false) 1; else 2;", 8),
      exact_matching_completion_budget_for_wb("false && 1;", 8),
      exact_matching_completion_budget_for_wb("true && 1;", 8),
      exact_matching_completion_budget_for_wb(
        "var i = 0; while (i < 2) { i++; } i;", 32,
      ),
    ],
    content=[4, 4, 3, 4, 20],
  )
}

///|
test "RED: bounded bytecode observes nested branch loop and interruption entries" {
  assert_control_stopped_equivalently_for_wb(
    structured_execution_policy_comparison_for_wb("1 + 2;", 2L),
    ExecutionLimit,
  )
  assert_control_stopped_equivalently_for_wb(
    structured_execution_policy_comparison_for_wb(
      "if (false) { console.log('bad'); } else { 7; }", 3L,
    ),
    ExecutionLimit,
  )
  assert_control_stopped_equivalently_for_wb(
    structured_execution_policy_comparison_for_wb(
      "var i = 0; while (i < 2) { i++; } i;", 8L,
    ),
    ExecutionLimit,
  )
  assert_control_stopped_equivalently_for_wb(
    structured_execution_policy_comparison_for_wb(
      "1 + 2;",
      100L,
      interrupted=true,
    ),
    Interrupted,
  )
}

///|
test "bytecode uses local slots for function params and vars" {
  let src =
    #|function f(a) {
    #|  var b = a + 1;
    #|  return b;
    #|}
    #|f(1);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = bytecode.main.children[0]
  json_inspect(child.local_names, content=["a", "b"])
  inspect(child.needs_arguments_object, content="false")
}

///|
test "bytecode uses mixed slots when arguments is referenced" {
  let src =
    #|function f(a) {
    #|  var b = a;
    #|  return arguments[0] + b;
    #|}
    #|f(1);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = bytecode.main.children[0]
  json_inspect(child.local_names, content=["b"])
  json_inspect(child.env_slot_names, content=[])
  inspect(child.needs_arguments_object, content="true")
  let mut saw_arguments_load = false
  for instr in child.code {
    match instr {
      LoadName("arguments") => saw_arguments_load = true
      _ => ()
    }
  }
  guard saw_arguments_load else { abort("expected arguments name load") }
}

///|
test "bytecode ignores nested ordinary arguments references for outer slots" {
  let src =
    #|function outer(a) {
    #|  var b = a;
    #|  function inner() { return arguments[0]; }
    #|  return b + inner(2);
    #|}
    #|outer(1);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected outer child function")
  }
  let outer = bytecode.main.children[0]
  json_inspect(outer.local_names, content=["a", "b", "inner"])
  inspect(outer.needs_arguments_object, content="false")
  guard outer.children.length() == 1 else {
    abort("expected nested child function")
  }
  let inner = outer.children[0]
  json_inspect(inner.local_names, content=[])
  inspect(inner.needs_arguments_object, content="true")
}

///|
test "bytecode keeps arrow arguments references on the enclosing function" {
  let src =
    #|function outer(a) {
    #|  var b = a;
    #|  var read = () => arguments[0];
    #|  return b + read();
    #|}
    #|outer(1);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected outer child function")
  }
  let outer = bytecode.main.children[0]
  json_inspect(outer.local_names, content=["b", "read"])
  inspect(outer.needs_arguments_object, content="true")
}

///|
test "bytecode keeps direct eval functions on environment bindings" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  function inner() { eval("x = 2"); }
    #|  inner();
    #|  return x;
    #|}
    #|outer();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let outer = bytecode.main.children[0]
  json_inspect(outer.local_names, content=[])
  inspect(outer.needs_arguments_object, content="true")
  guard outer.children.length() == 1 else {
    abort("expected nested child function")
  }
  let inner = outer.children[0]
  json_inspect(inner.local_names, content=[])
  inspect(inner.needs_arguments_object, content="true")
}

///|
test "bytecode lowers direct eval calls to direct-eval instructions" {
  let bytecode = parse_bytecode_for_wb("eval(...[\"1\"]);")
  let mut saw_load = false
  let mut saw_call = false
  for instr in bytecode.main.code {
    match instr {
      LoadDirectEvalCallee => saw_load = true
      CallDirectEval(_) => saw_call = true
      _ => ()
    }
  }
  guard saw_load else { abort("expected direct eval callee load") }
  guard saw_call else { abort("expected direct eval call") }
}

///|
test "bytecode keeps destructuring assignment functions on environment bindings" {
  let src =
    #|function f() {
    #|  var x = 0;
    #|  [x] = [1];
    #|  return x;
    #|}
    #|f();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = bytecode.main.children[0]
  json_inspect(child.local_names, content=[])
  let mut saw_assign_pattern = false
  for instr in child.code {
    match instr {
      AssignPattern(_) => saw_assign_pattern = true
      _ => ()
    }
  }
  guard saw_assign_pattern else { abort("expected destructuring assignment") }
}

///|
test "bytecode keeps var destructuring declaration functions on environment bindings" {
  let src =
    #|function f() {
    #|  var [x] = [1];
    #|  return x;
    #|}
    #|f();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = bytecode.main.children[0]
  json_inspect(child.local_names, content=[])
  let mut saw_assign_pattern = false
  for instr in child.code {
    match instr {
      AssignPattern(_) => saw_assign_pattern = true
      _ => ()
    }
  }
  guard saw_assign_pattern else {
    abort("expected destructuring declaration assignment")
  }
}

///|
test "bytecode treats destructuring assignment targets as captured" {
  let src =
    #|function outer() {
    #|  var x = 0;
    #|  return function() { [x] = [1]; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode plans block var declarations as function locals" {
  let src =
    #|function f() {
    #|  { var x = 1; }
    #|  return x;
    #|}
    #|f();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=["x"])
}

///|
test "bytecode plans control-flow var declarations as function locals" {
  let src =
    #|function f(flag) {
    #|  if (flag) {
    #|    var x = 1;
    #|  }
    #|  return x;
    #|}
    #|f(true);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=["flag", "x"])
}

///|
test "bytecode plans labeled var declarations as function locals" {
  let src =
    #|function f() {
    #|  label: { var x = 1; }
    #|  return x;
    #|}
    #|f();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=["x"])
}

///|
test "bytecode plans switch var declarations as function locals" {
  let src =
    #|function f(flag) {
    #|  switch (flag) {
    #|    case true:
    #|      var x = 1;
    #|  }
    #|  return x;
    #|}
    #|f(true);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=["flag", "x"])
}

///|
test "bytecode treats names inside nested labeled statements as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  label: {
    #|    return function() { return x; };
    #|  }
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode omits captured vars from local slots" {
  let src =
    #|function outer(a) {
    #|  var b = a;
    #|  return function() { return b; };
    #|}
    #|outer(1)();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = bytecode.main.children[0]
  json_inspect(child.local_names, content=["a"])
  json_inspect(child.env_slot_names, content=[])
}

///|
test "bytecode uses env slots for captured vars read by the owning function" {
  let src =
    #|function outer(a) {
    #|  var b = a;
    #|  function read() { return b; }
    #|  b = b + 1;
    #|  return read();
    #|}
    #|outer(1);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = bytecode.main.children[0]
  json_inspect(child.local_names, content=["a", "read"])
  json_inspect(child.env_slot_names, content=["b"])
}

///|
test "bytecode uses env slots for captured params read by the owning function" {
  let src =
    #|function outer(a) {
    #|  function read() { return a; }
    #|  a = a + 1;
    #|  return read();
    #|}
    #|outer(1);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = bytecode.main.children[0]
  json_inspect(child.local_names, content=["read"])
  json_inspect(child.env_slot_names, content=["a"])
}

///|
test "bytecode lowers unary minus to a unary value instruction" {
  let bytecode = parse_bytecode_for_wb("var x = -1;")
  let mut saw_unary = false
  for instr in bytecode.main.code {
    match instr {
      UnaryValueOp(Neg, _) => saw_unary = true
      _ => ()
    }
  }
  guard saw_unary else { abort("expected unary value op") }
}

///|
test "bytecode lowers member and computed updates to update instructions" {
  let bytecode = parse_bytecode_for_wb("var o = { x: 1 }; o.x++; ++o['x'];")
  let mut saw_property_update = false
  let mut saw_computed_update = false
  for instr in bytecode.main.code {
    match instr {
      UpdateProperty("x", Increment, false, _, _) => saw_property_update = true
      UpdateComputed(Increment, true, _, _) => saw_computed_update = true
      _ => ()
    }
  }
  guard saw_property_update else { abort("expected property update") }
  guard saw_computed_update else { abort("expected computed update") }
}

///|
test "bytecode treats names inside nested computed updates as captured" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  return function(o) { return o[key]++; };
    #|}
    #|outer()({ x: 1 });
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers property delete expressions to delete instructions" {
  let bytecode = parse_bytecode_for_wb(
    "var xs = []; delete xs.foo; delete xs[0];",
  )
  let mut saw_property_delete = false
  let mut saw_computed_delete = false
  for instr in bytecode.main.code {
    match instr {
      DeleteProperty("foo") => saw_property_delete = true
      DeleteComputed => saw_computed_delete = true
      _ => ()
    }
  }
  guard saw_property_delete else { abort("expected property delete") }
  guard saw_computed_delete else { abort("expected computed delete") }
}

///|
test "bytecode lowers identifier delete expressions to delete-name instructions" {
  let bytecode = parse_bytecode_for_wb("delete missing;")
  let mut saw_name_delete = false
  for instr in bytecode.main.code {
    match instr {
      DeleteName("missing") => saw_name_delete = true
      _ => ()
    }
  }
  guard saw_name_delete else { abort("expected identifier delete") }
}

///|
test "bytecode lowers typeof identifiers to a typeof-name instruction" {
  let bytecode = parse_bytecode_for_wb("typeof missing;")
  let mut saw_typeof = false
  for instr in bytecode.main.code {
    match instr {
      TypeofName("missing") => saw_typeof = true
      _ => ()
    }
  }
  guard saw_typeof else { abort("expected typeof-name instruction") }
}

///|
test "bytecode lowers typeof local slots through value typeof" {
  let bytecode = parse_bytecode_for_wb(
    "function f(a) { return typeof a; } f(1);",
  )
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let mut saw_local = false
  let mut saw_typeof = false
  for instr in bytecode.main.children[0].code {
    match instr {
      LoadLocal(0) => saw_local = true
      UnaryValueOp(Typeof, _) => saw_typeof = true
      _ => ()
    }
  }
  guard saw_local else { abort("expected local load") }
  guard saw_typeof else { abort("expected value typeof") }
}

///|
test "bytecode treats names inside nested typeof expressions as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { return typeof x; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers instanceof to the shared binary op instruction" {
  let bytecode = parse_bytecode_for_wb("var r = 1 instanceof function() {};")
  let mut saw_instanceof = false
  for instr in bytecode.main.code {
    match instr {
      BinaryOp(Instanceof, _) => saw_instanceof = true
      _ => ()
    }
  }
  guard saw_instanceof else { abort("expected instanceof binary op") }
}

///|
test "bytecode lowers template literals to append instructions" {
  let bytecode = parse_bytecode_for_wb("var x = 1; `a${x}b`;")
  let mut saw_template = false
  for instr in bytecode.main.code {
    match instr {
      AppendTemplate("b") => saw_template = true
      _ => ()
    }
  }
  guard saw_template else { abort("expected template append instruction") }
}

///|
test "bytecode lowers literal computed member calls through plain preparation" {
  let bytecode = parse_bytecode_for_wb(
    "var receiver = { get step() { return receiver['step'](); } };" +
    "receiver['step'](); var key = 'step'; receiver[key]();",
  )
  let mut root_plain = 0
  let mut root_computed = 0
  let mut root_literal_observation = false
  for instr in bytecode.main.code {
    match instr {
      ObserveExpression(_) => root_literal_observation = true
      PreparePlainPropertyCall("step", _) => {
        assert_true(root_literal_observation)
        root_literal_observation = false
        root_plain += 1
      }
      PrepareComputedCall(_) => root_computed += 1
      _ => root_literal_observation = false
    }
  }
  assert_eq(root_plain, 1)
  assert_eq(root_computed, 1)
  guard bytecode.main.children.length() == 1 else {
    fail("expected one recursive getter child")
  }
  let getter = bytecode.main.children[0]
  let mut getter_plain = 0
  let mut getter_literal_observation = false
  for instr in getter.code {
    match instr {
      ObserveExpression(_) => getter_literal_observation = true
      PreparePlainPropertyCall("step", _) => {
        assert_true(getter_literal_observation)
        getter_literal_observation = false
        getter_plain += 1
      }
      PrepareComputedCall(_) =>
        fail("recursive literal computed call must not use PrepareComputedCall")
      _ => getter_literal_observation = false
    }
  }
  assert_eq(getter_plain, 1)
}

///|
test "bytecode keeps dynamic string member calls on computed preparation" {
  let bytecode = parse_bytecode_for_wb(
    "var key = 'step';" +
    "var receiver = { get step() { return receiver[key](); } };" +
    "receiver[key]();",
  )
  let mut root_computed = 0
  let mut root_plain = 0
  for instr in bytecode.main.code {
    match instr {
      PrepareComputedCall(_) => root_computed += 1
      PreparePlainPropertyCall(_, _) => root_plain += 1
      _ => ()
    }
  }
  assert_eq(root_computed, 1)
  assert_eq(root_plain, 0)
  guard bytecode.main.children.length() == 1 else {
    fail("expected one recursive getter child")
  }
  let mut recursive_computed = 0
  let mut recursive_plain = 0
  for instr in bytecode.main.children[0].code {
    match instr {
      PrepareComputedCall(_) => recursive_computed += 1
      PreparePlainPropertyCall(_, _) => recursive_plain += 1
      _ => ()
    }
  }
  assert_eq(recursive_computed, 1)
  assert_eq(recursive_plain, 0)
}

///|
test "bytecode lowers tagged templates to template-object calls" {
  let bytecode = parse_bytecode_for_wb("tag`a${x}b`;")
  let mut saw_template_object = false
  let mut saw_call = false
  for instr in bytecode.main.code {
    match instr {
      MakeTemplateObject(strings) => {
        saw_template_object = true
        json_inspect(strings, content=[["a", ["a"]], ["b", ["b"]]])
      }
      Call(2, _) => saw_call = true
      _ => ()
    }
  }
  guard saw_template_object else { abort("expected tagged template object") }
  guard saw_call else { abort("expected tagged template call") }
}

///|
test "bytecode lowers member tagged templates to receiver calls" {
  let bytecode = parse_bytecode_for_wb("obj.tag`a${x}b`; obj[key]`c`; ")
  let mut saw_property_prepare = false
  let mut saw_computed_prepare = false
  let mut saw_receiver_call = false
  for instr in bytecode.main.code {
    match instr {
      PreparePropertyCall("tag", _) => saw_property_prepare = true
      PrepareComputedCall(_) => saw_computed_prepare = true
      CallWithReceiver(_, _) => saw_receiver_call = true
      _ => ()
    }
  }
  guard saw_property_prepare else { abort("expected property tag receiver") }
  guard saw_computed_prepare else { abort("expected computed tag receiver") }
  guard saw_receiver_call else {
    abort("expected tagged template receiver call")
  }
}

///|
test "bytecode rejects optional tagged templates at parse time" {
  let outcome = try {
    let _ = @parser.parse("obj?.tag`a${x}b`; obj?.[key]`c`; ")
    "ok"
  } catch {
    @errors.SyntaxError(message~) => message
    err => err.to_string()
  }
  inspect(outcome, content="Bad_optional_template")
}

///|
test "bytecode treats names inside nested tagged templates as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  function tag(strings, value) { return value; }
    #|  return function() { return tag`${x}`; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers regex literals to a runtime regexp instruction" {
  let bytecode = parse_bytecode_for_wb("var r = /a/i;")
  let mut saw_regexp = false
  for instr in bytecode.main.code {
    match instr {
      MakeRegExp("a", "i") => saw_regexp = true
      _ => ()
    }
  }
  guard saw_regexp else { abort("expected regexp instruction") }
}

///|
test "bytecode lowers array holes to sparse make array instruction" {
  let bytecode = parse_bytecode_for_wb("var xs = [1,,3];")
  let mut saw_sparse_array = false
  for instr in bytecode.main.code {
    match instr {
      MakeArrayWithHoles(3, holes) => {
        saw_sparse_array = true
        json_inspect(holes, content=[1])
      }
      _ => ()
    }
  }
  guard saw_sparse_array else { abort("expected sparse array instruction") }
}

///|
test "bytecode lowers array spreads to incremental append instructions" {
  let bytecode = parse_bytecode_for_wb("var xs = [0, ...ys,, 3];")
  let mut saw_start = false
  let mut saw_value = false
  let mut saw_spread = false
  let mut saw_hole = false
  for instr in bytecode.main.code {
    match instr {
      StartArray => saw_start = true
      ArrayPushValue => saw_value = true
      ArrayPushSpread(_) => saw_spread = true
      ArrayPushHole => saw_hole = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected array accumulator") }
  guard saw_value else { abort("expected array value append") }
  guard saw_spread else { abort("expected array spread append") }
  guard saw_hole else { abort("expected array hole append") }
}

///|
test "bytecode lowers spread call arguments to dynamic arg instructions" {
  let bytecode = parse_bytecode_for_wb(
    "f(1, ...xs); obj.m(...ys); new C(...zs);",
  )
  let mut saw_start = false
  let mut saw_value = false
  let mut saw_spread = false
  let mut saw_call = false
  let mut saw_receiver_call = false
  let mut saw_construct = false
  for instr in bytecode.main.code {
    match instr {
      StartArgs => saw_start = true
      ArgPushValue => saw_value = true
      ArgPushSpread(_) => saw_spread = true
      CallSpread(_) => saw_call = true
      CallSpreadWithReceiver(_) => saw_receiver_call = true
      ConstructSpread(_) => saw_construct = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected dynamic argument list") }
  guard saw_value else { abort("expected plain argument append") }
  guard saw_spread else { abort("expected spread argument append") }
  guard saw_call else { abort("expected spread call") }
  guard saw_receiver_call else { abort("expected spread receiver call") }
  guard saw_construct else { abort("expected spread construct") }
}

///|
test "bytecode treats names inside nested array spreads as captured" {
  let src =
    #|function outer() {
    #|  var xs = [1, 2];
    #|  return function() { return [...xs][1]; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers simple object literals to a make object instruction" {
  let bytecode = parse_bytecode_for_wb("var o = { a: 1, b: 2 };")
  let mut saw_object = false
  for instr in bytecode.main.code {
    match instr {
      MakeObject(keys) => {
        saw_object = true
        json_inspect(keys, content=["a", "b"])
      }
      _ => ()
    }
  }
  guard saw_object else { abort("expected make object instruction") }
}

///|
test "bytecode lowers object literal methods to method functions" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { x: 1, m() { return this.x; } };",
  )
  let mut saw_start = false
  let mut saw_method = false
  let mut saw_set = false
  for instr in bytecode.main.code {
    match instr {
      StartObject => saw_start = true
      MakeMethodFunction(_) => saw_method = true
      ObjectSetStatic("m") => saw_set = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected object accumulator") }
  guard saw_method else { abort("expected method function") }
  guard saw_set else { abort("expected method static property") }
}

///|
test "bytecode does not mark object methods for call self binding" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { m() { return m; }, get x() { return x; } };",
  )
  guard bytecode.main.children.length() == 2 else {
    abort("expected method and getter children")
  }
  guard !bytecode.main.children[0].call_self_name else {
    abort("method should not get a self binding")
  }
  guard !bytecode.main.children[1].call_self_name else {
    abort("getter should not get a self binding")
  }
}

///|
test "bytecode lowers object literal static accessors to accessor instructions" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { get x() { return 1; }, set x(v) { this.v = v; } };",
  )
  let mut saw_getter = false
  let mut saw_setter = false
  for instr in bytecode.main.code {
    match instr {
      ObjectSetStaticGetter("x") => saw_getter = true
      ObjectSetStaticSetter("x") => saw_setter = true
      _ => ()
    }
  }
  guard saw_getter else { abort("expected static getter instruction") }
  guard saw_setter else { abort("expected static setter instruction") }
}

///|
test "bytecode lowers object literal computed accessors to computed accessor instructions" {
  let bytecode = parse_bytecode_for_wb(
    "var key = 'x'; var o = { get [key]() { return 1; }, set [key](v) { this.v = v; } };",
  )
  let mut saw_key = false
  let mut saw_method = false
  let mut saw_getter = false
  let mut saw_setter = false
  for instr in bytecode.main.code {
    match instr {
      ToObjectLiteralPropertyKey => saw_key = true
      MakeComputedMethodFunction(_) => saw_method = true
      ObjectSetComputedGetter => saw_getter = true
      ObjectSetComputedSetter => saw_setter = true
      _ => ()
    }
  }
  guard saw_key else {
    abort("expected computed accessor key canonicalization")
  }
  guard saw_method else { abort("expected computed accessor method function") }
  guard saw_getter else { abort("expected computed getter instruction") }
  guard saw_setter else { abort("expected computed setter instruction") }
}

///|
test "bytecode treats names inside nested computed accessors as captured" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  var value = 1;
    #|  return function() { return ({ get [key]() { return value; } }).x; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested object literal methods as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return { m() { return x; } };
    #|}
    #|outer().m();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers computed object literal methods with computed home object" {
  let bytecode = parse_bytecode_for_wb(
    "var key = 'm'; var o = { [key]() { return this; } };",
  )
  let mut saw_key = false
  let mut saw_method = false
  let mut saw_computed = false
  for instr in bytecode.main.code {
    match instr {
      ToObjectLiteralPropertyKey => saw_key = true
      MakeComputedMethodFunction(_) => saw_method = true
      ObjectSetComputed => saw_computed = true
      _ => ()
    }
  }
  guard saw_key else { abort("expected computed method key canonicalization") }
  guard saw_method else { abort("expected computed method function") }
  guard saw_computed else { abort("expected computed method property set") }
}

///|
test "bytecode lowers super property access and calls inside methods" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { m() { super.x; super['m'](); } };",
  )
  guard bytecode.main.children.length() == 1 else {
    abort("expected one method child")
  }
  let method_child = bytecode.main.children[0]
  let mut saw_property = false
  let mut saw_computed_call = false
  for instr in method_child.code {
    match instr {
      LoadSuperProperty("x", _) => saw_property = true
      PrepareSuperComputedCall(_) => saw_computed_call = true
      _ => ()
    }
  }
  guard saw_property else { abort("expected super property load") }
  guard saw_computed_call else { abort("expected super computed call") }
}

///|
test "bytecode gets this before computed super read and call keys" {
  let bytecode = parse_bytecode_for_wb(
    "var readKey = 'x'; var callKey = 'f'; var o = { m() { super[readKey]; super[callKey](); } };",
  )
  guard bytecode.main.children.length() == 1 else {
    abort("expected one method child")
  }
  let mut stage = 0
  let mut saw_guarded_read = false
  let mut saw_guarded_call = false
  for instr in bytecode.main.children[0].code {
    match instr {
      LoadThis => stage = 1
      Pop => stage = if stage == 1 { 2 } else { 0 }
      LoadName("readKey") => stage = if stage == 2 { 3 } else { 0 }
      LoadSuperComputed(_) => {
        if stage == 3 {
          saw_guarded_read = true
        }
        stage = 0
      }
      LoadName("callKey") => stage = if stage == 2 { 4 } else { 0 }
      PrepareSuperComputedCall(_) => {
        if stage == 4 {
          saw_guarded_call = true
        }
        stage = 0
      }
      ObserveStatement(_) | ObserveExpression(_) => ()
      _ => stage = 0
    }
  }
  guard saw_guarded_read else {
    abort("expected LoadThis; Pop before computed super read key")
  }
  guard saw_guarded_call else {
    abort("expected LoadThis; Pop before computed super call key")
  }
}

///|
test "bytecode treats names inside nested super computed keys as captured" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  return { m() { return super[key]; } };
    #|}
    #|outer().m();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers object spreads to incremental object instructions" {
  let bytecode = parse_bytecode_for_wb("var o = { a: 1, ...src, b: 2 };")
  let mut saw_start = false
  let mut saw_a = false
  let mut saw_spread = false
  let mut saw_b = false
  for instr in bytecode.main.code {
    match instr {
      StartObject => saw_start = true
      ObjectSetStatic("a") => saw_a = true
      ObjectSpread(_) => saw_spread = true
      ObjectSetStatic("b") => saw_b = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected object accumulator") }
  guard saw_a else { abort("expected static property before spread") }
  guard saw_spread else { abort("expected object spread") }
  guard saw_b else { abort("expected static property after spread") }
}

///|
test "bytecode lowers object literal __proto__ through proto instruction" {
  let bytecode = parse_bytecode_for_wb(
    "var proto = {}; var o = { a: 1, __proto__: proto, b: 2 };",
  )
  let mut saw_start = false
  let mut saw_proto = false
  let mut saw_a = false
  let mut saw_b = false
  for instr in bytecode.main.code {
    match instr {
      StartObject => saw_start = true
      ObjectSetStatic("a") => saw_a = true
      ObjectSetProto => saw_proto = true
      ObjectSetStatic("b") => saw_b = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected object accumulator") }
  guard saw_a else { abort("expected static property before __proto__") }
  guard saw_proto else { abort("expected object __proto__ instruction") }
  guard saw_b else { abort("expected static property after __proto__") }
}

///|
test "bytecode lowers computed object literal data properties" {
  let bytecode = parse_bytecode_for_wb(
    "var key = 'x'; var o = { [key]: 1, after: 2 };",
  )
  let mut saw_key = false
  let mut saw_computed = false
  let mut saw_after = false
  for instr in bytecode.main.code {
    match instr {
      ToObjectLiteralPropertyKey => saw_key = true
      ObjectSetComputed => saw_computed = true
      ObjectSetStatic("after") => saw_after = true
      _ => ()
    }
  }
  guard saw_key else { abort("expected object literal key canonicalization") }
  guard saw_computed else { abort("expected computed data property set") }
  guard saw_after else { abort("expected static property after computed") }
}

///|
test "bytecode lowers named function expressions with a self-name instruction" {
  let bytecode = parse_bytecode_for_wb("var f = function g() { return g; };")
  let mut saw_named_function = false
  for instr in bytecode.main.code {
    match instr {
      MakeNamedFunction(_, "g") => saw_named_function = true
      _ => ()
    }
  }
  guard saw_named_function else { abort("expected named function expression") }
}

///|
test "bytecode lowers arrow functions with a dedicated arrow instruction" {
  let bytecode = parse_bytecode_for_wb("var f = a => a + 1;")
  let mut saw_arrow_function = false
  for instr in bytecode.main.code {
    match instr {
      MakeArrowFunction(_) => saw_arrow_function = true
      _ => ()
    }
  }
  guard saw_arrow_function else { abort("expected arrow function") }
}

///|
test "bytecode lowers rest arrow functions as environment-backed children" {
  let bytecode = parse_bytecode_for_wb("var f = (a, ...rest) => rest[0];")
  guard bytecode.main.children.length() == 1 else {
    abort("expected one arrow child")
  }
  let child = bytecode.main.children[0]
  guard child.rest_param is Some("rest") else {
    abort("expected rest parameter metadata")
  }
  json_inspect(child.local_names, content=[])
}

///|
test "bytecode lowers ordinary rest functions as environment-backed children" {
  let bytecode = parse_bytecode_for_wb(
    "function f(a, ...rest) { return rest[0]; } f(1, 2);",
  )
  guard bytecode.main.children.length() == 1 else {
    abort("expected one function child")
  }
  let child = bytecode.main.children[0]
  guard child.rest_param is Some("rest") else {
    abort("expected rest parameter metadata")
  }
  json_inspect(child.local_names, content=[])
}

///|
test "bytecode lowers object method rest functions as environment-backed children" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { m(a, ...rest) { return rest[0]; } }; o.m(1, 2);",
  )
  guard bytecode.main.children.length() == 1 else {
    abort("expected one method child")
  }
  let child = bytecode.main.children[0]
  guard child.rest_param is Some("rest") else {
    abort("expected rest parameter metadata")
  }
  json_inspect(child.local_names, content=[])
}

///|
test "bytecode treats names inside nested arrow functions as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return () => x;
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers this expressions to a dedicated load instruction" {
  let bytecode = parse_bytecode_for_wb("function f() { return this; } f();")
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let mut saw_this = false
  for instr in bytecode.main.children[0].code {
    match instr {
      LoadThis => saw_this = true
      _ => ()
    }
  }
  guard saw_this else { abort("expected load this instruction") }
}

///|
test "bytecode lowers new.target expressions to a dedicated load instruction" {
  let bytecode = parse_bytecode_for_wb(
    "function f() { return new.target; } new f();",
  )
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let mut saw_new_target = false
  for instr in bytecode.main.children[0].code {
    match instr {
      LoadNewTarget => saw_new_target = true
      _ => ()
    }
  }
  guard saw_new_target else { abort("expected load new.target instruction") }
}

///|
test "bytecode lowers console members to a shared host helper load" {
  let bytecode = parse_bytecode_for_wb("console.log(1);")
  let mut saw_console = false
  for instr in bytecode.main.code {
    match instr {
      LoadConsoleMember("log") => saw_console = true
      _ => ()
    }
  }
  guard saw_console else { abort("expected console member load") }
}

///|
test "bytecode treats names inside nested unary expressions as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { return -x; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested template expressions as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { return `${x}`; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested do while statements as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() {
    #|    do { x = x + 1; } while (false);
    #|  };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers switch statements with duplicated discriminant dispatch" {
  let bytecode = parse_bytecode_for_wb(
    "switch (x) { case 1: 'one'; break; default: 'default'; }",
  )
  let mut saw_dup = false
  let mut saw_strict_equal = false
  let mut saw_patched_jump = false
  for instr in bytecode.main.code {
    match instr {
      Dup => saw_dup = true
      BinaryOp(EqEqEq, _) => saw_strict_equal = true
      Jump(target) => {
        if target == -1 {
          abort("unpatched switch jump")
        }
        saw_patched_jump = true
      }
      JumpIfFalse(target) =>
        if target == -1 {
          abort("unpatched switch test jump")
        }
      _ => ()
    }
  }
  guard saw_dup else { abort("expected switch discriminant duplication") }
  guard saw_strict_equal else { abort("expected strict equality test") }
  guard saw_patched_jump else { abort("expected switch dispatch jump") }
}

///|
test "bytecode treats names inside nested switch statements as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function(flag) {
    #|    switch (flag) {
    #|      case true:
    #|        return x;
    #|    }
    #|  };
    #|}
    #|outer()(true);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers for-in assignment loops to iterator instructions" {
  let bytecode = parse_bytecode_for_wb(
    "var k; for (k in obj) { if (k === 'a') break; }",
  )
  let mut saw_start = false
  let mut saw_next = false
  let mut saw_end = false
  for instr in bytecode.main.code {
    match instr {
      StartForIn => saw_start = true
      ForInNext(target) => {
        if target == -1 {
          abort("unpatched for-in exit jump")
        }
        saw_next = true
      }
      EndForIn => saw_end = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected for-in iterator start") }
  guard saw_next else { abort("expected for-in next instruction") }
  guard saw_end else { abort("expected for-in break cleanup") }
}

///|
test "bytecode treats names inside nested for-in assignment loops as captured" {
  let src =
    #|function outer() {
    #|  var obj = { a: 1 };
    #|  var k = "";
    #|  return function() { for (k in obj) {} };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers for-in member and computed assignment targets" {
  let bytecode = parse_bytecode_for_wb(
    "var target = {}; for (target.x in obj) {} for (target[key] in obj) {}",
  )
  let mut saw_property_set = false
  let mut saw_computed_set = false
  for instr in bytecode.main.code {
    match instr {
      SetForInProperty("x", _) => saw_property_set = true
      SetForInComputed(_) => saw_computed_set = true
      _ => ()
    }
  }
  guard saw_property_set else { abort("expected for-in property set") }
  guard saw_computed_set else { abort("expected for-in computed set") }
}

///|
test "bytecode lowers for-in destructuring assignment targets" {
  let bytecode = parse_bytecode_for_wb("var first; for ([first] in obj) {}")
  let mut saw_start = false
  let mut saw_assign_pattern = false
  for instr in bytecode.main.code {
    match instr {
      StartForIn => saw_start = true
      AssignPattern(_) => saw_assign_pattern = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected for-in iterator start") }
  guard saw_assign_pattern else { abort("expected for-in pattern assignment") }
}

///|
test "bytecode treats names inside nested for-in destructuring targets as captured" {
  let src =
    #|function outer() {
    #|  var first = "";
    #|  return function(src) { for ([first] in src) {} };
    #|}
    #|outer()({ xy: 1 });
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested for-in expression targets as captured" {
  let src =
    #|function outer() {
    #|  var target = {};
    #|  var key = "x";
    #|  return function(obj) { for (target[key] in obj) {} };
    #|}
    #|outer()({ x: 1 });
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode patches unlabeled break and continue jumps" {
  let break_bytecode = parse_bytecode_for_wb("while (true) break;")
  let mut saw_break_to_exit = false
  for instr in break_bytecode.main.code {
    match instr {
      Jump(target) => {
        if target == -1 {
          abort("unpatched break jump")
        }
        if target == break_bytecode.main.code.length() {
          saw_break_to_exit = true
        }
      }
      JumpIfFalse(target) =>
        if target == -1 {
          abort("unpatched loop exit jump")
        }
      _ => ()
    }
  }
  guard saw_break_to_exit else { abort("expected break jump to loop exit") }
  let continue_bytecode = parse_bytecode_for_wb("do continue; while (false);")
  let mut saw_continue_to_condition = false
  for i, instr in continue_bytecode.main.code {
    match instr {
      Jump(target) => {
        if target == -1 {
          abort("unpatched continue jump")
        }
        if target == i + 1 {
          saw_continue_to_condition = true
        }
      }
      JumpIfFalse(target) =>
        if target == -1 {
          abort("unpatched do-while exit jump")
        }
      _ => ()
    }
  }
  guard saw_continue_to_condition else {
    abort("expected continue jump to condition")
  }
}

///|
test "bytecode patches labeled break and continue jumps" {
  let break_bytecode = parse_bytecode_for_wb("label: { break label; }")
  let mut saw_labeled_break = false
  for instr in break_bytecode.main.code {
    match instr {
      Jump(target) => {
        if target == -1 {
          abort("unpatched labeled break jump")
        }
        if target == break_bytecode.main.code.length() {
          saw_labeled_break = true
        }
      }
      _ => ()
    }
  }
  guard saw_labeled_break else { abort("expected labeled break to label exit") }
  let continue_bytecode = parse_bytecode_for_wb(
    "outer: do continue outer; while (false);",
  )
  let mut saw_labeled_continue = false
  for i, instr in continue_bytecode.main.code {
    match instr {
      Jump(target) => {
        if target == -1 {
          abort("unpatched labeled continue jump")
        }
        if target == i + 1 {
          saw_labeled_continue = true
        }
      }
      JumpIfFalse(target) =>
        if target == -1 {
          abort("unpatched labeled do-while exit jump")
        }
      _ => ()
    }
  }
  guard saw_labeled_continue else {
    abort("expected labeled continue to loop condition")
  }
}

///|
test "bytecode treats names inside nested object literals as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { return { value: x }.value; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested computed object literal keys as captured" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  return function() { return ({ [key]: 1 }).x; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested object spreads as captured" {
  let src =
    #|function outer() {
    #|  var source = { x: 1 };
    #|  return function() { return { ...source }.x; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers optional member access with a nullish guard" {
  let bytecode = parse_bytecode_for_wb("var r = obj?.x;")
  let mut saw_guard = false
  let mut saw_get = false
  for instr in bytecode.main.code {
    match instr {
      JumpIfNotNullishKeep(target) => {
        if target == -1 {
          abort("unpatched optional member guard")
        }
        saw_guard = true
      }
      GetProperty("x", _) => saw_get = true
      _ => ()
    }
  }
  guard saw_guard else { abort("expected optional nullish guard") }
  guard saw_get else { abort("expected optional property get") }
}

///|
test "RED: bytecode keeps dynamic computed reads while normalizing literal keys" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { x: 1 }; var key = 'x'; o['x']; o['\\u0078']; o[key];",
  )
  let mut literal_gets = 0
  let mut computed_gets = 0
  for instr in bytecode.main.code {
    match instr {
      GetProperty("x", _) => literal_gets += 1
      GetComputed(_) => computed_gets += 1
      _ => ()
    }
  }
  assert_eq(literal_gets, 2)
  assert_eq(computed_gets, 1)
}

///|
test "computed literal reads observe the key without replaying its value" {
  let bytecode = parse_bytecode_for_wb("o['x'];")
  let mut expression_observations = 0
  let mut key_loads = 0
  let mut saw_get = false
  let ordered_events : Array[String] = []
  for instr in bytecode.main.code {
    match instr {
      ObserveExpression(_) => {
        expression_observations += 1
        ordered_events.push("observe")
      }
      LoadName("o") => ordered_events.push("object-value")
      LoadConst(@runtime.Value::String_("x")) => key_loads += 1
      GetProperty("x", _) => {
        saw_get = true
        ordered_events.push("get-property")
      }
      _ => ()
    }
  }
  assert_eq(expression_observations, 3)
  assert_eq(key_loads, 0)
  assert_true(saw_get)
  json_inspect(ordered_events, content=[
    "observe", "observe", "object-value", "observe", "get-property",
  ])
}

///|
test "bytecode treats names inside nested optional chains as captured" {
  let src =
    #|function outer() {
    #|  var obj = { x: 1 };
    #|  return function() { return obj?.x; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers member and computed assignments to property set instructions" {
  let src =
    #|var xs = [];
    #|xs.foo = 1;
    #|xs[0] = 2;
  let bytecode = parse_bytecode_for_wb(src)
  let mut saw_property_set = false
  let mut saw_computed_set = false
  for instr in bytecode.main.code {
    match instr {
      SetProperty("foo", _) => saw_property_set = true
      SetComputed(_) => saw_computed_set = true
      _ => ()
    }
  }
  guard saw_property_set else { abort("expected property set instruction") }
  guard saw_computed_set else { abort("expected computed set instruction") }
}

///|
test "bytecode lowers identifier compound assignment through binary op and local store" {
  let bytecode = parse_bytecode_for_wb(
    "function f() { var x = 1; x += 2; return x; } f();",
  )
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let mut saw_add = false
  let mut saw_store_local = false
  for instr in bytecode.main.children[0].code {
    match instr {
      BinaryOp(Add, _) => saw_add = true
      StoreLocal(0) => saw_store_local = true
      _ => ()
    }
  }
  guard saw_add else { abort("expected compound binary add") }
  guard saw_store_local else { abort("expected compound local store") }
}

///|
test "bytecode lowers global compound assignment reads through assignment names" {
  let bytecode = parse_bytecode_for_wb("x += 1;")
  let mut saw_assignment_load = false
  for instr in bytecode.main.code {
    match instr {
      LoadAssignmentName("x") => saw_assignment_load = true
      _ => ()
    }
  }
  guard saw_assignment_load else { abort("expected assignment-name load") }
}

///|
test "bytecode treats names inside nested compound assignments as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { x += 1; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers member compound assignments through reference-preserving reads" {
  let bytecode = parse_bytecode_for_wb("var o = { x: 1 }; o.x += 2;")
  let mut saw_add = false
  let mut saw_property_read = false
  let mut saw_property_set = false
  for instr in bytecode.main.code {
    match instr {
      ReadPropertyForAssign("x", _) => saw_property_read = true
      BinaryOp(Add, _) => saw_add = true
      SetProperty("x", _) => saw_property_set = true
      _ => ()
    }
  }
  guard saw_property_read else { abort("expected property assignment read") }
  guard saw_add else { abort("expected compound binary add") }
  guard saw_property_set else { abort("expected property set") }
}

///|
test "bytecode lowers computed compound assignments through canonicalized keys" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { x: 1 }; var k = 'x'; o[k] *= 3;",
  )
  let mut saw_mul = false
  let mut saw_computed_read = false
  let mut saw_computed_set = false
  for instr in bytecode.main.code {
    match instr {
      ReadComputedForAssign(_) => saw_computed_read = true
      BinaryOp(Mul, _) => saw_mul = true
      SetComputed(_) => saw_computed_set = true
      _ => ()
    }
  }
  guard saw_computed_read else { abort("expected computed assignment read") }
  guard saw_mul else { abort("expected compound binary multiply") }
  guard saw_computed_set else { abort("expected computed set") }
}

///|
test "bytecode lowers logical member compound assignments with reference cleanup" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { x: 0 }; o.x ||= 1; o['x'] &&= 2;",
  )
  let mut saw_or_guard = false
  let mut saw_and_guard = false
  let mut saw_property_cleanup = false
  let mut saw_computed_cleanup = false
  for instr in bytecode.main.code {
    match instr {
      JumpIfTrueKeep(target) => {
        if target == -1 {
          abort("unpatched property logical assignment guard")
        }
        saw_or_guard = true
      }
      JumpIfFalseKeep(target) => {
        if target == -1 {
          abort("unpatched computed logical assignment guard")
        }
        saw_and_guard = true
      }
      DropPropertyAssignReference => saw_property_cleanup = true
      DropComputedAssignReference => saw_computed_cleanup = true
      _ => ()
    }
  }
  guard saw_or_guard else { abort("expected logical-or guard") }
  guard saw_and_guard else { abort("expected logical-and guard") }
  guard saw_property_cleanup else {
    abort("expected property reference cleanup")
  }
  guard saw_computed_cleanup else {
    abort("expected computed reference cleanup")
  }
}

///|
test "bytecode treats names inside nested computed compound assignments as captured" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  return function(o) { o[key] += 1; };
    #|}
    #|outer()({ x: 1 });
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers new expressions to construct instructions" {
  let bytecode = parse_bytecode_for_wb("function C() {} new C();")
  let mut saw_construct = false
  for instr in bytecode.main.code {
    match instr {
      Construct(0, _) => saw_construct = true
      _ => ()
    }
  }
  guard saw_construct else { abort("expected construct instruction") }
}

///|
test "bytecode treats names inside nested computed assignments as captured" {
  let src =
    #|function outer() {
    #|  var key = 0;
    #|  return function(xs) { xs[key] = 1; };
    #|}
    #|outer()([]);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}
