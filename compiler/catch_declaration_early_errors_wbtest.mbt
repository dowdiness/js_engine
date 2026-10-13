///|
fn assert_syntax_error_value_for_wb(
  interp : @interpreter.Interpreter,
  value : @runtime.Value,
  source : String,
) -> Unit raise Error {
  match interp.get_property(value, "name", @token.Loc::default()) {
    @runtime.Value::String_(name) => assert_eq(name, "SyntaxError", msg=source)
    _ => fail("exception name is not a string: " + source)
  }
}

///|
fn assert_catch_declaration_rejected_for_wb(
  source : String,
) -> Unit raise Error {
  let tree = @interpreter.new_interpreter()
  ignore(tree.run(@parser.parse("var marker = 0;").stmts))
  let tree_failed = try {
    ignore(tree.run(@parser.parse(source).stmts))
    false
  } catch {
    @runtime.JsException(value) => {
      assert_syntax_error_value_for_wb(tree, value, source)
      true
    }
    error => raise error
  }
  assert_true(tree_failed, msg=source)
  assert_eq(tree.global.get("marker").to_string(), "0", msg=source)

  let candidate = @interpreter.new_interpreter()
  ignore(candidate.run(@parser.parse("var marker = 0;").stmts))
  let candidate_failed = try {
    ignore(run_candidate_program(candidate, @parser.parse(source).stmts))
    false
  } catch {
    @runtime.JsException(value) => {
      assert_syntax_error_value_for_wb(candidate, value, source)
      true
    }
    error => raise error
  }
  assert_true(candidate_failed, msg=source)
  assert_eq(candidate.global.get("marker").to_string(), "0", msg=source)
}

///|
fn assert_catch_declaration_accepted_for_wb(
  source : String,
) -> Unit raise Error {
  ignore(@interpreter.new_interpreter().run(@parser.parse(source).stmts))
  ignore(
    run_candidate_program(
      @interpreter.new_interpreter(),
      @parser.parse(source).stmts,
    ),
  )
}

///|
test "catch declaration early errors reject before guest effects" {
  for
    source in [
      "marker=1; try { throw {}; } catch ({a:x,b:x}) {}", "marker=1; try { throw []; } catch ([x,x]) {}",
      "marker=1; try { throw 1; } catch (x) { let x; }", "marker=1; try { throw 1; } catch (x) { const x = 1; }",
      "marker=1; try { throw 1; } catch (x) { class x {} }", "marker=1; try { throw 1; } catch (x) { function x() {} }",
      "marker=1; try { throw 1; } catch (x) { function* x() {} }", "marker=1; try { throw 1; } catch (x) { async function x() {} }",
      "marker=1; try { throw 1; } catch (x) { async function* x() {} }", "marker=1; try { throw {}; } catch ({x}) { var x; }",
      "marker=1; try { throw {}; } catch ({x}) { if (false) { var x; } }", "marker=1; function unused() { try { throw {}; } catch ({a:x,b:x}) {} }",
    ] {
    assert_catch_declaration_rejected_for_wb(source)
  }
}

///|
test "catch declaration early errors preserve legal bindings" {
  for
    source in [
      "try { throw 1; } catch (x) { var x = 7; }", "'use strict'; try { throw 1; } catch (x) { var x = 7; }",
      "try { throw 1; } catch (x) { { let x; } }", "try { throw 1; } catch { let x = 1; }",
      "try { throw {}; } catch ({x}) { let y; var z; }", "try { throw {}; } catch ({x}) { function f() { var x; } }",
    ] {
    assert_catch_declaration_accepted_for_wb(source)
  }
}
