///|
fn control_admission_test_program(source : String) -> Array[@ast.Stmt] raise {
  @parser.parse(source).stmts
}

///|
fn control_admission_test_accepts(source : String) -> Bool raise {
  preflight_control_lifecycle_program(control_admission_test_program(source))
  is Some(_)
}

///|
test "control lifecycle admission accepts only the two exact roots" {
  inspect(
    control_admission_test_accepts(
      "outer: try { break outer; } finally { 1; } 9;",
    ),
    content="true",
  )
  inspect(
    control_admission_test_accepts(
      "do try { continue; } finally { 2; } while(false); 8;",
    ),
    content="true",
  )
}

///|
test "labelled break admission rejects control and finalizer lookalikes" {
  for
    source in [
      "outer: try { break other; } finally { 1; } 9;", "outer: try { break; } finally { 1; } 9;",
      "outer: try { break outer; } catch(e) {} finally { 1; } 9;", "outer: try { break outer; } finally {} 9;",
      "outer: try { break outer; } finally { 1; 2; } 9;", "outer: try { break outer; } finally { f(); } 9;",
      "outer: try { break outer; } finally { +1; } 9;", "outer: try { break outer; } finally { 01; } 9;",
      "{ outer: try { break outer; } finally { 1; } } 9;", "outer: try { break outer; } finally { 1; } 9; 10;",
    ] {
    if control_admission_test_accepts(source) {
      fail("unexpected labelled-break admission: " + source)
    }
  }
}

///|
test "bounded continue admission rejects loop and condition lookalikes" {
  for
    source in [
      "outer: do try { continue outer; } finally { 2; } while(false); 8;", "do try { continue; } catch(e) {} finally { 2; } while(false); 8;",
      "do try { continue; } finally { 2; 3; } while(false); 8;", "do try { continue; } finally { f(); } while(false); 8;",
      "do try { continue; } finally { +2; } while(false); 8;", "do try { continue; } finally { 02; } while(false); 8;",
      "do try { continue; } finally { 2; } while(true); 8;", "do try { continue; } finally { 2; } while(flag); 8;",
      "do try { continue; } finally { 2; } while(f()); 8;", "while(false) try { break; } finally { 2; } 8;",
      "do { try { continue; } finally { 2; } } while(false); 8;", "do try { continue; } finally { 2; } while(false); 8; 9;",
    ] {
    if control_admission_test_accepts(source) {
      fail("unexpected bounded-continue admission: " + source)
    }
  }
}
