///|
test "typeof string equality executes in bytecode in either operand order" {
  for
    pair in [
      ("'function' == typeof Symbol", "true"),
      ("typeof Symbol == 'function'", "true"),
      ("'function' != typeof Symbol", "false"),
      ("typeof Symbol != 'function'", "false"),
      ("'anything' == typeof 1", "false"),
      ("typeof 1 == 'anything'", "false"),
      ("'anything' != typeof 1", "true"),
      ("typeof 1 != 'anything'", "true"),
      ("'undefined' == typeof missingName", "true"),
    ] {
    let (expression, expected) = pair
    let source = expression + ";"
    let stmts = @parser.parse(source).stmts
    let root = prepare_candidate_program(stmts).root
    guard root.selection is UseBytecode(_) else {
      fail("comparison selected tree: " + expression)
    }
    let (actual, evidence) = candidate_run_with_evidence_for_wb(source)
    assert_eq(actual.to_string(), expected, msg=expression)
    assert_eq(@interpreter.new_interpreter().run(stmts).to_string(), expected)
    assert_candidate_function_started_for_wb(
      evidence,
      root,
      CandidateBytecodeExecutor,
    )
  }
}

///|
test "typeof comparison evaluates computed getter once and preserves thrown value" {
  let source =
    #|var log = [];
    #|var marker = {};
    #|var object = { get value() { log.push('get'); return 1; },
    #|               get bad() { log.push('throw'); throw marker; } };
    #|function key(name) { log.push('key'); return name; }
    #|function compare(name) { return 'number' == typeof object[key(name)]; }
    #|log.push('function');
    #|log.push(compare('value'));
    #|try { compare('bad'); }
    #|catch (error) { log.push(error === marker); }
    #|log.push('end');
    #|log.join(',');
  let expected = "function,key,get,true,key,throw,true,end"
  let stmts = @parser.parse(source).stmts
  assert_eq(@interpreter.new_interpreter().run(stmts).to_string(), expected)
  let (actual, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(actual.to_string(), expected)
  let root = prepare_candidate_program(stmts).root
  let compare = root.children[root.children.length() - 1]
  assert_candidate_function_started_for_wb(
    evidence,
    compare,
    CandidateBytecodeExecutor,
  )
}

///|
test "typeof comparison preserves lexical TDZ in bytecode" {
  let source =
    #|function compare() {
    #|  return 'undefined' == typeof value; let value;
    #|}
    #|var result;
    #|try { compare(); } catch (error) { result = error.name; }
    #|result;
  let stmts = @parser.parse(source).stmts
  assert_eq(
    @interpreter.new_interpreter().run(stmts).to_string(),
    "ReferenceError",
  )
  let (actual, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(actual.to_string(), "ReferenceError")
  assert_candidate_function_started_for_wb(
    evidence,
    prepare_candidate_program(stmts).root.children[0],
    CandidateBytecodeExecutor,
  )
}

///|
test "other loose comparisons retain typed fallback and coercion" {
  for
    pair in [
      ("'1' == 1", "true"),
      ("1 != '1'", "false"),
      ("typeof 1 == { toString() { return 'number'; } }", "true"),
      ("({ toString() { return 'number'; } }) != typeof 1", "false"),
      ("typeof 1 == typeof 2", "true"),
      ("typeof 1 == 0", "false"),
    ] {
    let (expression, expected) = pair
    let source = expression + ";"
    match
      prepare_candidate_program(@parser.parse(source).stmts).root.selection {
      UseTreeWalker(
        CandidateActivationUnsupported({ reason: BinaryOperation, .. })
      ) => ()
      _ => fail("comparison lost loose-equality fallback: " + expression)
    }
    let (actual, _) = candidate_run_with_evidence_for_wb(source)
    assert_eq(actual.to_string(), expected, msg=expression)
  }
}

///|
test "typeof equality retains original operator source ownership" {
  let stmts = @parser.parse("\n  'number' == typeof 1;").stmts
  guard stmts is [@ast.ExprStmt(@ast.Binary(_, _, _, expected_loc), _)] else {
    fail("expected comparison fixture")
  }
  guard lower_script_to_bytecode(stmts) is Ok(program) else {
    fail("comparison failed lowering")
  }
  let function = program.main_for_wb()
  let mut found = false
  for index, instruction in function.code {
    if instruction is BinaryOp(EqEqEq, BinaryExpression, loc) {
      found = true
      assert_eq(loc, expected_loc)
      guard function.instruction_sources[index] is [source_id] else {
        fail("comparison must retain one operator source")
      }
      let SourcePointId(unit, owner, _) = source_id
      assert_eq(unit, function.source_unit)
      assert_eq(owner, function.source_point_owner)
      let point = function.resolve_source_point(source_id)
      assert_true(point.role is Operator)
      assert_eq(point.loc, expected_loc)
    }
  }
  assert_true(found, msg="strict comparison instruction missing")
}
