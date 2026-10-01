///|
test "bytecode block scopes preserve bindings across completion changes" {
  for
    (body, expected) in [
      (
        "var x=1; var outer=function(){return x;}; { let x=2; log.push(outer(),x); } return x;",
        "[1,[1,2]]",
      ),
      (
        "var x=1; var boom=function(){throw 7;}; try { let x=2; boom(); } catch(e) { log.push(e); } return x;",
        "[1,[7]]",
      ),
      (
        "var x=1; { let x=2; { const x=3; log.push(x); } log.push(x); } return x;",
        "[1,[3,2]]",
      ),
      (
        "var x=1; { try { log.push(typeof x); } catch(e) { log.push(e.name); } let x=2; } return x;",
        "[1,[\"ReferenceError\"]]",
      ),
      (
        "{ let a=2,b=a+1; const c=b+1; try { c=5; } catch(e) { log.push(e.name); } return c; }",
        "[4,[\"TypeError\"]]",
      ),
      (
        "var x=1; try { let x=2; throw x; } catch(e) { let x=e+1; log.push(x); } finally { let x=4; log.push(x); } return x;",
        "[1,[3,4]]",
      ),
      (
        "var x=1; for(var i=0;i<3;i++) { let x=i+2; try { if(i===0) continue; break; } finally { log.push(x); } } return x;",
        "[1,[2,3]]",
      ),
      (
        "let x=1; var f; { let x=2; f=function(){return x;}; x=3; } log.push(f()); return x;",
        "[1,[3]]",
      ),
      ("let x=1; { let x=2; log.push(x); } return x;", "[1,[2]]"),
      (
        "let x=1; inner: { let x=2; try { return x; } finally { log.push(x); break inner; } } return x;",
        "[1,[2]]",
      ),
      (
        "var saved=[]; for(var i=0;i<2;i++) { let x=i; saved.push(function(){return x;}); x=x+10; } return saved[0]()+saved[1]();",
        "[21,[]]",
      ),
    ] {
    let source = "var log=[]; function probe(){" +
      body +
      "} JSON.stringify([probe(),log]);"
    let (actual, evidence) = candidate_run_with_evidence_for_wb(source)
    assert_eq(actual.to_string(), expected, msg=source)
    let function = prepare_candidate_program(@parser.parse(source).stmts).root.children[0]
    assert_true(function.bytecode is Some(_), msg=source)
    assert_candidate_function_started_for_wb(
      evidence,
      function,
      CandidateBytecodeExecutor,
    ) catch {
      error => fail(source + "\n" + error.to_string())
    }
  }
}

///|
test "explicit bytecode eval resolves the active block environment" {
  let value = run_bytecode_script(
    @interpreter.new_interpreter(),
    @parser.parse("let x=1; { let x=2; eval('x=3'); if(x!==3) throw x; } x;").stmts,
  )
  assert_eq(value.to_string(), "1")
}

///|
test "explicit bytecode enumeration retains scope when finally replaces break" {
  let value = run_bytecode_script(
    @interpreter.new_interpreter(),
    @parser.parse(
      "var log=[],x=1,k; outer: for(k in {a:1,b:2}) { let x=k; try { break outer; } finally { log.push(x); continue outer; } } JSON.stringify([x,log]);",
    ).stmts,
  )
  assert_eq(value.to_string(), "[1,[\"a\",\"b\"]]")
}

///|
test "block declaration conflicts fail before body effects" {
  for declaration in ["let x; let x;", "const x=1; var x;", "let x; { var x; }"] {
    let source = "var effect=0; try { eval('effect=1; {" +
      declaration +
      "}'); } catch(e) { if(e.name!=='SyntaxError') throw e; } effect;"
    let (actual, _) = candidate_run_with_evidence_for_wb(source)
    assert_eq(actual.to_string(), "0", msg=declaration)
  }
}

///|
test "block verifier rejects bypassed entry and sibling scope transfers" {
  let function = prepare_candidate_program(
      @parser.parse("function probe(){ { let x=1; x; } { let x=2; x; } }").stmts,
    ).root.children[0].bytecode.unwrap().function
  let scopes : Array[Int] = []
  for index, instruction in function.code {
    if instruction is EnterHandler(LexicalScope(_), _, _) {
      scopes.push(index)
    }
  }
  assert_eq(scopes.length(), 2)
  for defect in 0..<3 {
    let code = function.code.copy()
    match defect {
      0 => code[scopes[0] - 1] = Jump(scopes[0] + 1)
      1 => code[scopes[0] + 1] = LeaveHandler(scopes[1] + 1)
      _ => code[scopes[0] + 1] = Return
    }
    let broken = { ..function, code, }
    let rejected = try {
      verify_bytecode_function_control_flow(broken, [], recurse=false)
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg="accepted invalid scope transfer")
  }
}
