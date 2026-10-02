///|
test "bytecode for let closures retain each iteration binding" {
  let source =
    #|function probe() {
    #|  const saved = [];
    #|  for (let i = 0; i < 3; i++) saved.push(() => i);
    #|  return saved.map(f => f());
    #|}
    #|JSON.stringify(probe());
  let (actual, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(actual.to_string(), "[0,1,2]")
  let function = prepare_candidate_program(@parser.parse(source).stmts).root.children[0]
  assert_true(function.bytecode is Some(_), msg="probe must have bytecode")
  assert_candidate_function_started_for_wb(
    evidence,
    function,
    CandidateBytecodeExecutor,
  )
}

///|
test "bytecode lexical for headers preserve initialization and completion semantics" {
  for
    (name, body, expected) in [
      (
        "initializer condition body and update closures",
        (
          #|var initial, body = [], test = [], step = [];
          #|for (let i = 0, get = () => i;
          #|     (test.push(() => i), i < 3);
          #|     (step.push(() => i), i++)) {
          #|  initial = get;
          #|  body.push(() => i);
          #|}
          #|return [initial(), body.map(f => f()), step.map(f => f()), test.map(f => f())];
        ),
        "[0,[0,1,2],[1,2,3],[0,1,2,3]]",
      ),
      (
        "body writes stay in the captured iteration",
        (
          #|var saved = [];
          #|for (let i = 0; i < 4; i++) {
          #|  saved.push(() => i);
          #|  i++;
          #|}
          #|return saved.map(f => f());
        ),
        "[1,3]",
      ),
      (
        "multiple ordered bindings",
        (
          #|var saved = [];
          #|for (let i = 0, j = i + 10; i < 3; i++, j = j + 10)
          #|  saved.push(() => [i, j]);
          #|return saved.map(f => f());
        ),
        "[[0,10],[1,20],[2,30]]",
      ),
      (
        "const stays immutable",
        (
          #|var more = true, saved, seen = [];
          #|for (const i = 1; more; more = false) {
          #|  saved = () => i;
          #|  seen.push(i);
          #|  try {
          #|    i = 2;
          #|  } catch (e) {
          #|    seen.push(e.name);
          #|  }
          #|}
          #|seen.push(saved());
          #|return seen;
        ),
        "[1,\"TypeError\",1]",
      ),
      (
        "initializer TDZ restores outer binding",
        (
          #|let i = 7;
          #|var seen;
          #|try {
          #|  for (let i = i;;) {}
          #|} catch (e) {
          #|  seen = e.name;
          #|}
          #|return [i, seen];
        ),
        "[7,\"ReferenceError\"]",
      ),
      (
        "zero iterations restore shadowed activation binding",
        (
          #|let i = 7;
          #|var seen;
          #|for (let i = (seen = 2); false;) {}
          #|return [i, seen];
        ),
        "[7,2]",
      ),
      (
        "finally replaces break with continue",
        (
          #|let i = 7;
          #|var saved = [];
          #|outer: for (let i = 0; i < 3; i++) {
          #|  try {
          #|    break outer;
          #|  } finally {
          #|    saved.push(() => i);
          #|    continue outer;
          #|  }
          #|}
          #|return [i, saved.map(f => f())];
        ),
        "[7,[0,1,2]]",
      ),
      (
        "finally replaces return with break",
        (
          #|let i = 7;
          #|var saved;
          #|outer: for (let i = 2;; i++) {
          #|  try {
          #|    return 9;
          #|  } finally {
          #|    saved = () => i;
          #|    break outer;
          #|  }
          #|}
          #|return [i, saved()];
        ),
        "[7,2]",
      ),
      (
        "nested labeled continue unwinds inner scope",
        (
          #|let i = 7;
          #|var saved = [];
          #|outer: for (let i = 0; i < 2; i++) {
          #|  for (let j = 0; j < 2; j++) {
          #|    saved.push(() => [i, j]);
          #|    continue outer;
          #|  }
          #|}
          #|return [i, saved.map(f => f())];
        ),
        "[7,[[0,0],[1,0]]]",
      ),
      (
        "condition throw restores outer binding",
        (
          #|let i = 7;
          #|var seen;
          #|var boom = () => { throw 4; };
          #|try {
          #|  for (let i = 0; boom(); i++) {}
          #|} catch (e) {
          #|  seen = e;
          #|}
          #|return [i, seen];
        ),
        "[7,4]",
      ),
      (
        "update throw preserves escaped closure",
        (
          #|let i = 7;
          #|var saved, seen;
          #|var boom = () => { throw 4; };
          #|try {
          #|  for (let i = 0; i < 1; boom()) {
          #|    saved = () => i;
          #|  }
          #|} catch (e) {
          #|  seen = e;
          #|}
          #|return [i, seen, saved()];
        ),
        "[7,4,0]",
      ),
      (
        "missing condition and update still creates cells",
        (
          #|var saved = [];
          #|for (let i = 0;;) {
          #|  saved.push(() => i);
          #|  i++;
          #|  if (i === 3) break;
          #|}
          #|return saved.map(f => f());
        ),
        "[1,2,3]",
      ),
      (
        "body lexical shadowing",
        (
          #|var saved = [];
          #|for (let i = 0; i < 2; i++) {
          #|  let i = 9;
          #|  saved.push(() => i);
          #|}
          #|return saved.map(f => f());
        ),
        "[9,9]",
      ),
      (
        "captured activation slots are restored",
        (
          #|var read = () => outer, saved = [];
          #|for (let outer = 0; outer < 2; outer++) saved.push(() => outer);
          #|return [outer, read(), saved.map(f => f())];
        ),
        "[7,7,[0,1]]",
      ),
      (
        "parameters are restored after loop",
        (
          #|for (let outer = 0; outer < 2; outer++) {}
          #|return outer;
        ),
        "7",
      ),
    ] {
    let source = "function probe(outer){" + body + "} JSON.stringify(probe(7));"
    let function = prepare_candidate_program(@parser.parse(source).stmts).root.children[0]
    assert_true(function.bytecode is Some(_), msg=name)
    let (actual, evidence) = candidate_run_with_evidence_for_wb(source)
    assert_eq(actual.to_string(), expected, msg=name)
    assert_candidate_function_started_for_wb(
      evidence,
      function,
      CandidateBytecodeExecutor,
    ) catch {
      error => fail(name + "\n" + error.to_string())
    }
  }
}

///|
test "explicit bytecode eval uses the current for iteration binding" {
  let value = run_bytecode_script(
    @interpreter.new_interpreter(),
    @parser.parse(
      "var i=7,saved=[]; for(let i=0;i<3;i++) { eval('saved.push(()=>i)'); } JSON.stringify([i,saved.map(f=>f())]);",
    ).stmts,
  )
  assert_eq(value.to_string(), "[7,[0,1,2]]")
}

///|
test "iteration environment verifier requires an active let scope" {
  for
    (name, source, target) in [
      ("outside scope", "function probe(){ return 1; }", "outside"),
      ("const scope", "function probe(){ for(const i=0;false;) {} }", "const"),
      (
        "active catch handler", "function probe(){ for(let i=0;i<1;i++) { try { throw 1; } catch(e) { return e; } } }",
        "catch",
      ),
    ] {
    let function = prepare_candidate_program(@parser.parse(source).stmts).root.children[0].bytecode.unwrap().function
    let code = function.code.copy()
    let mut index = 0
    for offset, instruction in code {
      match (target, instruction) {
        ("const", EnterHandler(LexicalScope(_), _, _))
        | ("catch", EnterHandler(CatchHandler(_), _, _)) => index = offset + 1
        _ => ()
      }
    }
    assert_true(target == "outside" || index > 0, msg=name)
    code[index] = CreatePerIterationEnvironment
    let broken = { ..function, code, }
    let rejected = try {
      verify_bytecode_function_control_flow(broken, [], recurse=false)
      false
    } catch {
      @errors.InternalError(_) => true
      error => raise error
    }
    assert_true(rejected, msg=name)
  }
}
