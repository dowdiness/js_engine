///|
// Assert both JavaScript results and the selected executor.
test "bytecode try catch finally preserves completion and uses bytecode" {
  let source =
    #|var log = [];
    #|function boom() { throw 7; }
    #|function probe(e) {
    #|  try { boom(); } catch (e) { log.push(e); }
    #|  try { return e; } finally { log.push("finally"); }
    #|}
    #|var result = probe(3);
    #|JSON.stringify([result, log]);
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "[3,[7,\"finally\"]]")
  let function = prepare_candidate_program(@parser.parse(source).stmts).root.children[1]
  assert_candidate_function_started_for_wb(
    evidence,
    function,
    CandidateBytecodeExecutor,
  )
}

///|
test "bytecode completion precedence and catch scope" {
  let cases = [
    (
      "function probe() { var n=41; try { return function() { return n+1; }; } finally {} } probe()();",
      "42",
    ),
    (
      "function probe() { try { throw 1; } finally { return 2; } } probe();", "2",
    ),
    (
      "function probe() { try { return 1; } finally { throw 2; } } var result; try { probe(); } catch(e) { result=e; } result;",
      "2",
    ),
    (
      "var log=[]; function probe() { try { try { return 1; } finally { log.push(2); } } finally { log.push(3); } } JSON.stringify([probe(),log]);",
      "[1,[2,3]]",
    ),
    (
      "var log=[]; function probe() { for(var i=0;i<3;i=i+1) { try { if(i===0) continue; if(i===1) break; } finally { log.push(i); } } } probe(); JSON.stringify(log);",
      "[0,1]",
    ),
    (
      "function probe(e) { try { throw 2; } catch(e) { return function() { return e; }; } } probe(1)();",
      "2",
    ),
    ("function probe() { try { throw 1; } catch { return 2; } } probe();", "2"),
    (
      "function probe() { try { null.x; } catch(e) { return e.name; } } probe();",
      "TypeError",
    ),
    (
      "function probe(e) { try { throw 2; } catch(e) { e=3; } return e; } probe(1);",
      "1",
    ),
  ]
  for (source, expected) in cases {
    assert_eq(
      @interpreter.new_interpreter()
      .run(@parser.parse(source).stmts)
      .to_string(),
      expected,
    )
    let (actual, evidence) = candidate_run_with_evidence_for_wb(source)
    assert_eq(actual.to_string(), expected, msg=source)
    let plan = prepare_candidate_program(@parser.parse(source).stmts)
    let function = plan.root.children.filter(child => {
        child.name == Some("probe")
      })[0]
    assert_candidate_function_started_for_wb(
      evidence,
      function,
      CandidateBytecodeExecutor,
    )
  }
}

///|
const ITERATOR_READ_HELPER : String =
  #|var read = function(t,e){var Q="function"==typeof Symbol&&t[Symbol.iterator];if(!Q)return t;var r,T,n=Q.call(t),o=[];try{for(;(void 0===e||e-- >0)&&!(r=n.next()).done;)o.push(r.value)}catch(t){T={error:t}}finally{try{r&&!r.done&&(Q=n.return)&&Q.call(n)}finally{if(T)throw T.error}}return o};

///|
test "bytecode exact read helper preserves iterator cleanup and throw precedence" {
  for scenario in 0..<4 {
    let source = ITERATOR_READ_HELPER +
      "var scenario=" +
      scenario.to_string() +
      ";" +
      (
        #|var closed=0, index=0, observed;
        #|var iterable={};
        #|iterable[Symbol.iterator]=function() { return {
        #|  next:function() { index=index+1; if(scenario===2 && index===2) throw "next"; return {value:index, done:index>3}; },
        #|  return:function() { closed=closed+1; if(scenario>=2) throw "close"; return {}; }
        #|}; };
        #|try { observed=read(iterable,scenario===0?undefined:scenario===2?undefined:1); } catch(e) { observed=e; }
        #|JSON.stringify([observed,closed]);
      )
    let expected = match scenario {
      0 => "[[1,2,3],0]"
      1 => "[[1],1]"
      2 => "[\"next\",1]"
      _ => "[\"close\",1]"
    }
    assert_eq(
      @interpreter.new_interpreter()
      .run(@parser.parse(source).stmts)
      .to_string(),
      expected,
    )
    let (actual, evidence) = candidate_run_with_evidence_for_wb(source)
    assert_eq(actual.to_string(), expected)
    let function = prepare_candidate_program(@parser.parse(source).stmts).root.children[0]
    assert_candidate_function_started_for_wb(
      evidence,
      function,
      CandidateBytecodeExecutor,
    )
  }
}

///|
test "bytecode catch var initializer does not overwrite the outer parameter" {
  // Node confirms 1; the existing explicit tree implementation returns 3.
  let source = "function probe(e) { try { throw 2; } catch(e) { var e=3; } return e; } probe(1);"
  let (actual, _) = candidate_run_with_evidence_for_wb(source)
  assert_eq(actual.to_string(), "1")
}
