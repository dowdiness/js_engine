///|
test "try completion precedence preserves loops and catch environments" {
  for
    (body, expected) in [
      (
        "for(var k=0;k<2;k++) { try { return 9; } finally { log.push(k); continue; } } return 3;",
        "[3,[0,1]]",
      ),
      (
        "outer: for(var k=0;k<2;k++) { for(var j=0;j<1;j++) { try { break outer; } finally { log.push(k); continue outer; } } } return 3;",
        "[3,[0,1]]",
      ),
      (
        "outer: for(var k=0;k<2;k++) { try { break outer; } finally { log.push(k); continue outer; } } return 3;",
        "[3,[0,1]]",
      ),
      (
        "try { throw 1; } catch(e) { try { return e; } finally { e=2; log.push(e); } }",
        "[1,[2]]",
      ),
      (
        "try { return 1; } finally { try { throw 2; } catch(e) { log.push(e); } }",
        "[1,[2]]",
      ),
      (
        "try { null?.x; throw 1; } catch(e) { log.push(({x:2})?.x); } return 3;",
        "[3,[2]]",
      ),
    ] {
    let source = "var log=[]; function probe(){" +
      body +
      "} JSON.stringify([probe(),log]);"
    let actual = run_bytecode_script(
      @interpreter.new_interpreter(),
      @parser.parse(source).stmts,
    )
    assert_eq(actual.to_string(), expected, msg=source)
  }
}

///|
test "try verifier rejects invalid region boundaries and handler entry" {
  for defect in 0..<6 {
    let function = prepare_candidate_program(
        @parser.parse("function probe(){ try { 1; } finally { 2; } return 3; }").stmts,
      ).root.children[0].bytecode.unwrap().function
    let code = function.code.copy()
    for index, instruction in function.code {
      match instruction {
        EnterHandler(kind, target, end) =>
          match defect {
            0 => code[index] = EnterHandler(kind, target, target - 1)
            1 => code[index + 1] = Jump(target)
            2 => code[end - 1] = Jump(end)
            3 => code[index + 1] = ResumeCompletion(end)
            4 => code[index] = EnterHandler(kind, target, code.length() + 1)
            _ => code[index + 1] = Return
          }
        _ => ()
      }
    }
    let broken = { ..function, code, }
    let rejected = try {
      verify_bytecode_function_control_flow(broken, [], recurse=false)
      false
    } catch {
      _ => true
    }
    assert_true(
      rejected,
      msg="accepted malformed try region: " + defect.to_string(),
    )
  }
}

///|
test "try bodies participate in function binding preparation" {
  for
    (source, expected) in [
      (
        "function probe(x){ try { return arguments[0]; } finally {} } probe(7);",
        "7",
      ),
      (
        "function probe(x){ try { eval('x=8'); } finally {} return x; } probe(7);",
        "8",
      ),
      (
        "function probe(x){ try { return function(){ return x; }; } finally { x=8; } } probe(7)();",
        "8",
      ),
      (
        "function probe(x){ try { throw 1; } catch(e) { return arguments[0]; } } probe(7);",
        "7",
      ),
      (
        "function probe(x){ try { return x; } finally { arguments[0]=8; } } probe(7);",
        "7",
      ),
    ] {
    let actual = run_bytecode_script(
      @interpreter.new_interpreter(),
      @parser.parse(source).stmts,
    )
    assert_eq(actual.to_string(), expected, msg=source)
  }
}

///|
test "finally overriding a labeled exit preserves enclosing enumeration" {
  let source =
    #|var log=[];
    #|function probe(){
    #|  var k, j;
    #|  outer: for(k in {a:1,b:2}) {
    #|    for(j in {x:1}) {
    #|      try { break outer; }
    #|      finally { log.push(k); continue outer; }
    #|    }
    #|  }
    #|  return log;
    #|}
    #|JSON.stringify(probe());
  let actual = run_bytecode_script(
    @interpreter.new_interpreter(),
    @parser.parse(source).stmts,
  )
  assert_eq(actual.to_string(), "[\"a\",\"b\"]")
}

///|
test "exception edges retain independent observation authority" {
  let function = prepare_candidate_program(
      @parser.parse("function probe(){ try { throw 1; } finally { 2; } }").stmts,
    ).root.children[0].bytecode.unwrap().function
  let edges = function.observation_edge_contexts.map(entries => entries.copy())
  let mut removed = false
  for index, instruction in function.code {
    match instruction {
      Throw if !edges[index].is_empty() => {
        edges[index].clear()
        removed = true
      }
      _ => ()
    }
  }
  assert_true(removed)
  let broken = { ..function, observation_edge_contexts: edges, }
  let rejected = try {
    verify_bytecode_function_observation_coverage(broken, [], recurse=false)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
