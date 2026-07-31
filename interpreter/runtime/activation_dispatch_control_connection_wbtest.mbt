///|
fn control_connection_test_program(source : String) -> Array[@ast.Stmt] raise {
  @parser.parse(source).stmts
}

///|
test "Interpreter run connects both exact control lifecycle plans" {
  for
    pair in [
      ("outer: try { break outer; } finally { 1; } 9;", 9.0),
      ("do try { continue; } finally { 2; } while(false); 8;", 8.0),
    ] {
    let (source, expected) = pair
    let stmts = control_connection_test_program(source)
    guard preflight_control_lifecycle_program(stmts) is Some(_) else {
      fail("expected public connection source to pass exact admission")
    }
    match Interpreter::new().run(stmts) {
      Number(value) => inspect(value, content=expected.to_string())
      _ => fail("expected exact control lifecycle result")
    }
  }
}

///|
test "Interpreter run keeps valid control lookalikes on legacy execution" {
  for
    pair in [
      ("outer: try { break outer; } finally { 1; 2; } 9;", 9.0),
      ("do try { continue; } finally { 2; 3; } while(false); 8;", 8.0),
    ] {
    let (source, expected) = pair
    let stmts = control_connection_test_program(source)
    guard preflight_control_lifecycle_program(stmts) is None else {
      fail("control lookalike must remain outside exact admission")
    }
    match Interpreter::new().run(stmts) {
      Number(value) => inspect(value, content=expected.to_string())
      _ => fail("expected legacy control lookalike result")
    }
  }
}
