///|
fn assert_loop_declaration_rejected_before_effect_for_wb(
  source : String,
) -> Unit raise Error {
  let interp = @interpreter.new_interpreter()
  ignore(run_candidate_program(interp, @parser.parse("var effect=0;").stmts))
  let failure : String? = try {
    ignore(run_candidate_program(interp, @parser.parse(source).stmts))
    None
  } catch {
    @runtime.JsException(value) => Some(value.to_string())
    error => raise error
  }
  match failure {
    Some(message) => assert_true(message.contains("SyntaxError"))
    None => fail("expected a declaration SyntaxError")
  }
  assert_eq(interp.global.get("effect").to_string(), "0")
}

///|
test "duplicate let and const for header bindings reject before effects" {
  for
    source in [
      "effect=1; for (let i=0, i=1; false;) effect=2; effect;", "effect=1; for (const i=0, i=1; false;) effect=2; effect;",
    ] {
    assert_loop_declaration_rejected_before_effect_for_wb(source)
  }
}

///|
test "lexical loop headers reject body var collisions" {
  for
    source in [
      "effect=1; for (let i=0; false;) { var i; }", "effect=1; for (let i in {}) { var i; }",
      "effect=1; for (let i of []) { var i; }", "effect=1; for (let [i] = [0]; false;) { var i; }",
      "effect=1; for (let [i] in {}) { var i; }", "effect=1; for (let [i] of []) { var i; }",
      "effect=1; for (let i=0; false;) { if (false) { var i; } }", "effect=1; async function never() { for await (let i of []) { var i; } }",
      "effect=1; async function never() { for await (let [i] of []) { var i; } }",
    ] {
    assert_loop_declaration_rejected_before_effect_for_wb(source)
  }
}

///|
test "destructured lexical loop headers reject repeated bound names" {
  for
    source in [
      "effect=1; for (let [i,i] = [0,0]; false;) {}", "effect=1; for (let [i,i] in {}) {}",
      "effect=1; for (let [i,i] of []) {}", "effect=1; async function never() { for await (let [i,i] of []) {} }",
    ] {
    assert_loop_declaration_rejected_before_effect_for_wb(source)
  }
}

///|
test "unreachable and never-called loops still reject declaration errors" {
  for
    source in [
      "effect=1; if (false) { for (let i=0, i=1; false;) {} }", "effect=1; function never() { for (let i=0, i=1; false;) {} }",
      "effect=1; function never() { for (let i=0; false;) { var i; } }",
    ] {
    assert_loop_declaration_rejected_before_effect_for_wb(source)
  }
}

///|
test "legal loop declarations preserve nested scopes and assignment targets" {
  for
    source in [
      "effect=1; for (let i=0; false;) { function nested() { var i; } } effect;",
      "effect=1; for (let i=0; false;) { { let i; } } effect;", "effect=1; for (var i=0, i=1; false;) {} effect;",
      "effect=1; var target={}; for (target.x in {}) {} effect;",
    ] {
    let interp = @interpreter.new_interpreter()
    let actual = interp.run(@parser.parse(source).stmts)
    assert_eq(actual.to_string(), "1", msg=source)
    assert_eq(interp.global.get("effect").to_string(), "1", msg=source)
  }
}

///|
test "eval loop declaration errors reject before eval effects" {
  let source = "var effect=0; try { eval(\"effect=1; for (let i=0, i=1; false;) {}\"); } catch (e) { if (e.name !== \"SyntaxError\") throw e; } effect;"
  let interp = @interpreter.new_interpreter()
  let actual = interp.run(@parser.parse(source).stmts)
  assert_eq(actual.to_string(), "0")
  assert_eq(interp.global.get("effect").to_string(), "0")
}

///|
test "valid lexical loop shadowing agrees across tree and candidate bytecode" {
  let source =
    #|function probe() {
    #|  var seen = [];
    #|  for (let i = 0; i < 2; i++) {
    #|    { let i = 9; seen.push(i); }
    #|  }
    #|  return seen.join(",");
    #|}
    #|probe();
  let tree_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  assert_eq(tree_value.to_string(), "9,9")
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  let probe = program.root.children[0]
  guard probe.bytecode is Some(_) else {
    fail("valid C-style lexical loop did not admit bytecode")
  }
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(candidate_value.to_string(), "9,9")
  assert_candidate_function_started_for_wb(
    evidence,
    probe,
    CandidateBytecodeExecutor,
  )
}
