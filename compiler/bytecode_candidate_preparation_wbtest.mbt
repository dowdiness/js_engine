///|
// Characterizes the pre-#911 all-or-nothing lowering boundary.  The parent is
// otherwise eligible, but the nested child uses a lowering-unsupported form.
test "characterization: unsupported nested lowering rejects whole script" {
  let source =
    #|function parent() { return 1; }
    #|function child() { for (var value of [1]) {} }
  match lower_source_for_wb(source) {
    Ok(_) => fail("current lowering unexpectedly accepted unsupported child")
    Err(unsupported) => {
      guard unsupported.reason is ForOfStatement else {
        fail("expected nested for-of lowering rejection")
      }
    }
  }
}

///|
// The runtime wiring in #885 consumes this closed evidence seam.  Keeping the
// transition test beside candidate preparation makes an accidental fallback
// or second start a compiler defect rather than an observable log convention.
test "candidate route evidence permits exactly one typed start and completion" {
  let program = prepare_candidate_program(
    @parser.parse("function child() {}").stmts,
  )
  let evidence : Ref[CandidateRouteEvidence] = { val: CandidateRouteEvidence() }
  let activation = candidate_route_prepare(
    evidence,
    program.root.source_identity,
    program.root.selection,
  )
  candidate_route_start(activation, CandidateBytecodeExecutor)
  candidate_route_complete(activation, CandidateRouteNormal)
  guard evidence.val.events.length() == 3 else {
    fail("candidate route evidence did not record prepare/start/complete")
  }
  match evidence.val.events[0] {
    CandidateRoutePreparedEvent(prepared) =>
      if prepared.activation_id != 0 {
        fail("first candidate activation did not start at zero")
      }
    _ => fail("candidate route evidence did not begin with preparation")
  }
}

///|
// RED characterization for the first production seam: both parent directions
// are already visible in the pure candidate tree, but neither is materialized
// into an Engine activation yet.
test "RED: candidate tree retains both mixed parent directions" {
  let source =
    #|function bytecodeParent() {
    #|  function treeChild() { for (var value of [1]) {} }
    #|  return treeChild;
    #|}
    #|function treeParent() {
    #|  function bytecodeChild() { return 1; }
    #|  return bytecodeChild;
    #|}
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  let bytecode_parent = root.children[0]
  let tree_parent = root.children[1]
  guard bytecode_parent.bytecode is Some(_) else {
    fail("bytecode parent lost candidate carrier")
  }
  guard tree_parent.bytecode is Some(_) else {
    fail("tree parent fixture did not retain a candidate carrier")
  }
  match bytecode_parent.children[0].selection {
    UseTreeWalker(CandidateLoweringUnsupported(_)) => ()
    _ => fail("bytecode parent did not retain typed tree child")
  }
  match tree_parent.children[0].selection {
    UseBytecode(_) => ()
    _ => fail("tree parent did not retain eligible bytecode child")
  }
}

///|
// RED for the pure candidate seam: this intentionally names the API that the
// next slice introduces.  It must preserve an eligible parent candidate while
// retaining a typed tree-only child candidate.
test "RED: candidate preparation keeps eligible parent with lowering-unsupported child" {
  let source =
    #|function parent() { return 1; }
    #|function child() { for (var value of [1]) {} }
  let parsed = @parser.parse(source)
  let _candidates = prepare_candidate_program(parsed.stmts)
  ()
}

///|
test "candidate tree separates parent and child outcomes" {
  let source =
    #|function parent() { return 1; }
    #|function child() { for (var value of [1]) {} }
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.bytecode is Some(_) else {
    fail("candidate root should retain bytecode")
  }
  guard program.root.children.length() == 2 else {
    fail("candidate root should retain both declarations")
  }
  match program.root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) =>
      fail("eligible parent unexpectedly selected tree walker")
  }
  match program.root.children[1].selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      if unsupported.reason is ForOfStatement {
        ()
      } else {
        fail("child fallback lost its lowering reason")
      }
    UseTreeWalker(_) =>
      fail("child fallback was not typed as lowering unsupported")
    UseBytecode(_) => fail("unsupported child unexpectedly selected bytecode")
  }
}

///|
test "candidate selection keeps activation unsupported local to a function" {
  let source =
    #|function parent() { return 1; }
    #|function child() { return 1 + 2; }
  let root = (prepare_candidate_program(@parser.parse(source).stmts) catch {
      error => {
        debug_inspect(error.to_string())
        fail("candidate consumer preparation failed")
      }
    }).root
  match root.selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("eligible script root should remain bytecode")
  }
  match root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("eligible parent should remain bytecode")
  }
  match root.children[1].selection {
    UseTreeWalker(CandidateActivationUnsupported(unsupported)) =>
      match unsupported.reason {
        BinaryOperation => ()
        _ => fail("child activation fallback lost its reason")
      }
    UseTreeWalker(_) => fail("child fallback was not activation unsupported")
    UseBytecode(_) => fail("activation-unsupported child selected bytecode")
  }
}

///|
test "candidate nested eligible parent keeps activation fallback local" {
  let source =
    #|function outer() {
    #|  function parent() { return 1; }
    #|  function child() { return 1 + 2; }
    #|}
  let outer = prepare_candidate_program(@parser.parse(source).stmts).root.children[0]
  match outer.selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("eligible outer should remain bytecode")
  }
  match outer.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("eligible nested parent should remain bytecode")
  }
  match outer.children[1].selection {
    UseTreeWalker(CandidateActivationUnsupported(unsupported)) =>
      match unsupported.reason {
        BinaryOperation => ()
        _ => fail("nested activation fallback lost its reason")
      }
    UseTreeWalker(_) =>
      fail("nested child fallback was not activation unsupported")
    UseBytecode(_) =>
      fail("nested activation-unsupported child selected bytecode")
  }
}

///|
test "candidate root selection distinguishes activation fallback" {
  let program = prepare_candidate_program(@parser.parse("1 + 2;").stmts)
  match program.root.selection {
    UseTreeWalker(CandidateActivationUnsupported(unsupported)) =>
      match unsupported.reason {
        BinaryOperation => ()
        _ => fail("root activation fallback lost its reason")
      }
    UseTreeWalker(CandidateLoweringUnsupported(_)) =>
      fail("root activation fallback was mislabeled as lowering unsupported")
    UseBytecode(_) => fail("activation-unsupported root selected bytecode")
  }
}

///|
test "candidate root selection retains lowering fallback" {
  let program = prepare_candidate_program(
    @parser.parse("for (var value of [1]) {};").stmts,
  )
  match program.root.selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        ForOfStatement => ()
        _ => fail("root lowering fallback lost its reason")
      }
    UseTreeWalker(_) => fail("root fallback was not lowering unsupported")
    UseBytecode(_) => fail("lowering-unsupported root selected bytecode")
  }
}

///|
fn candidate_run_with_evidence_for_wb(
  source : String,
) -> (@runtime.Value, Ref[CandidateRouteEvidence]) raise Error {
  let interp = @interpreter.new_interpreter()
  run_candidate_program_with_evidence(interp, @parser.parse(source).stmts) catch {
    @runtime.JsException(value) =>
      fail("candidate execution threw: " + value.to_string())
    error => fail("candidate execution failed: " + error.to_string())
  }
}

///|
fn candidate_started_executors_for_wb(
  evidence : Ref[CandidateRouteEvidence],
) -> Array[CandidateRouteExecutor] {
  evidence.val.events
  .map(event => {
    match event {
      CandidateRouteStartedEvent(started) => Some(started.executor)
      _ => None
    }
  })
  .filter_map(x => x)
}

///|
fn candidate_started_executor_labels_for_wb(
  evidence : Ref[CandidateRouteEvidence],
) -> String {
  candidate_started_executors_for_wb(evidence)
  .map(executor => {
    match executor {
      CandidateBytecodeExecutor => "bytecode"
      CandidateTreeWalkerExecutor => "tree"
    }
  })
  .join(",")
}

///|
test "candidate runner starts an eligible root through bytecode" {
  let (value, evidence) = candidate_run_with_evidence_for_wb(
    "function answer() { return 42; } answer();",
  )
  if value.to_string() != "42" {
    fail("eligible candidate root returned an unexpected value")
  }
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() >= 2 else {
    fail("candidate root and callable did not both start")
  }
  if starts[0] != CandidateBytecodeExecutor {
    fail("eligible root did not start through bytecode")
  }
  guard evidence.val.events.length() == starts.length() * 3 else {
    fail("candidate route evidence did not close every activation")
  }
}

///|
test "candidate runner starts unsupported root through tree before effects" {
  let (value, evidence) = candidate_run_with_evidence_for_wb(
    "for (var value of [1]) {}; 42;",
  )
  if value.to_string() != "42" {
    fail("unsupported candidate root returned an unexpected value")
  }
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() == 1 else {
    fail("unsupported root started more than one executor")
  }
  if starts[0] != CandidateTreeWalkerExecutor {
    fail("unsupported root did not start through tree walker")
  }
  match evidence.val.events[0] {
    CandidateRoutePreparedEvent(prepared) =>
      match prepared.decision {
        UseTreeWalker(CandidateLoweringUnsupported(_)) => ()
        _ => fail("unsupported root was not decided before tree start")
      }
    _ => fail("candidate root did not prepare before starting")
  }
}

///|
test "candidate runner materializes bytecode parent with tree child" {
  let source =
    #|function parent() {
    #|  function child() { for (var value of [1]) {} }
    #|  return child();
    #|}
    #|parent();
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  let parent = program.root.children[0]
  guard parent.bytecode is Some(bytecode) else {
    fail("mixed parent was not bytecode")
  }
  if bytecode.function.preparation.function_declarations.length() != 1 {
    fail("mixed bytecode parent did not retain its declaration")
  }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  if value.to_string() != "undefined" {
    fail("mixed bytecode-parent result was unexpected")
  }
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() >= 3 else {
    fail("mixed bytecode-parent route did not start root, parent, and child")
  }
  if starts[0] != CandidateBytecodeExecutor ||
    starts[1] != CandidateBytecodeExecutor ||
    starts[2] != CandidateTreeWalkerExecutor {
    fail("bytecode parent did not retain an independent tree child route")
  }
}

///|
test "candidate runner materializes tree parent with bytecode child" {
  let source =
    #|function parent() {
    #|  for (var value of [1]) {}
    #|  function child() { return 7; }
    #|  return child();
    #|}
    #|parent();
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  if value.to_string() != "7" {
    fail("mixed tree-parent result was unexpected")
  }
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() >= 3 else {
    fail("mixed tree-parent route did not start root, parent, and child")
  }
  if starts[0] != CandidateBytecodeExecutor ||
    starts[1] != CandidateTreeWalkerExecutor ||
    starts[2] != CandidateBytecodeExecutor {
    fail("tree parent did not retain an independent bytecode child route")
  }
}

///|
// RED: a skipped expression must not consume the later expression's
// candidate.  Both anonymous functions have the same consumer form and
// signature, but the earlier branch is never entered and is tree-only due to
// its unsupported body.
test "RED: tree materialization resolves an executed anonymous site" {
  let source =
    #|function parent(value) {
    #|  for (var guard of [1]) {}
    #|  if (value) {
    #|    let skipped = function(x) {
    #|      for (var inner of [1]) {}
    #|      return 10;
    #|    };
    #|  }
    #|  let later = function(x) { return 20; };
    #|  return later(0);
    #|}
    #|parent(false);
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  if value.to_string() != "20" {
    fail("tree materialization consumed a skipped anonymous child")
  }
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() >= 3 else {
    fail("tree anonymous site did not start root, parent, and child")
  }
  if starts[0] != CandidateBytecodeExecutor ||
    starts[1] != CandidateTreeWalkerExecutor ||
    starts[2] != CandidateBytecodeExecutor {
    fail("executed anonymous site did not retain its bytecode selection")
  }
}

///|
test "candidate tree routes hoisted declarations by syntax site" {
  let source =
    #|function parent() {
    #|  for (var guard of [1]) {}
    #|  let first = function(x) { return 10; };
    #|  function hoisted() { return 20; }
    #|  return first(0) + hoisted();
    #|}
    #|parent();
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  if value.to_string() != "30" {
    fail("hoisted declaration route returned an unexpected value")
  }
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() >= 4 else {
    fail("hoisted declaration route did not start both children")
  }
  if starts[0] != CandidateBytecodeExecutor ||
    starts[1] != CandidateTreeWalkerExecutor ||
    starts[2] != CandidateBytecodeExecutor ||
    starts[3] != CandidateBytecodeExecutor {
    fail("hoisted declaration did not retain its site selection")
  }
}

///|
test "candidate tree repeats one materialization site without consumption" {
  let source =
    #|function parent() {
    #|  for (var guard of [1]) {}
    #|  let total = 0;
    #|  for (var value of [1, 2]) {
    #|    let increment = function(x) { return 2; };
    #|    total += increment(value);
    #|  }
    #|  return total;
    #|}
    #|parent();
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  if value.to_string() != "4" {
    fail("repeated materialization site returned an unexpected value")
  }
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() >= 4 else {
    fail("repeated materialization site did not start both iterations")
  }
  if starts[0] != CandidateBytecodeExecutor ||
    starts[1] != CandidateTreeWalkerExecutor ||
    starts[2] != CandidateBytecodeExecutor ||
    starts[3] != CandidateBytecodeExecutor {
    fail(
      "repeated materialization site changed executor selection: " +
      candidate_started_executor_labels_for_wb(evidence),
    )
  }
}

///|
test "candidate tree separates same-name same-signature siblings" {
  let source =
    #|function parent(value) {
    #|  for (var guard of [1]) {}
    #|  if (value) {
    #|    let same = function same(x) {
    #|      for (var inner of [1]) {}
    #|      return 10;
    #|    };
    #|    return same(0);
    #|  }
    #|  let same = function same(x) { return 20; };
    #|  return same(0);
    #|}
    #|parent(false) + parent(true);
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  if value.to_string() != "30" {
    fail("same-name sibling route returned an unexpected value")
  }
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() >= 5 else {
    fail("same-name sibling route did not start both activations")
  }
  if starts[0] != CandidateTreeWalkerExecutor ||
    starts[1] != CandidateTreeWalkerExecutor ||
    starts[2] != CandidateBytecodeExecutor ||
    starts[3] != CandidateTreeWalkerExecutor ||
    starts[4] != CandidateTreeWalkerExecutor {
    fail(
      "same-name siblings were paired by runtime order: " +
      candidate_started_executor_labels_for_wb(evidence),
    )
  }
}

///|
test "candidate tree restores site routing after abrupt activation" {
  let source =
    #|function parent(shouldThrow) {
    #|  for (var guard of [1]) {}
    #|  if (shouldThrow) {
    #|    try {
    #|      throw "stop";
    #|      let skipped = function(x) {
    #|        for (var inner of [1]) {}
    #|        return 10;
    #|      };
    #|    } catch (error) {}
    #|    throw "stop";
    #|  }
    #|  let later = function() { return 9; };
    #|  return later();
    #|}
    #|try { parent(true); } catch (error) {}
    #|parent(false);
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  if value.to_string() != "9" {
    fail("post-abrupt activation returned an unexpected value")
  }
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() >= 4 else {
    fail("post-abrupt activation did not restart the parent route")
  }
  if starts[0] != CandidateTreeWalkerExecutor ||
    starts[1] != CandidateTreeWalkerExecutor ||
    starts[2] != CandidateTreeWalkerExecutor ||
    starts[3] != CandidateBytecodeExecutor {
    fail(
      "post-abrupt activation reused stale routing state: " +
      candidate_started_executor_labels_for_wb(evidence),
    )
  }
}

///|
test "candidate tree excludes fresh direct eval definitions from its plan" {
  let source =
    #|function parent() {
    #|  for (var guard of [1]) {}
    #|  eval("var dynamic = function(x) { return 99; };");
    #|  let later = function(x) { return 20; };
    #|  return later(0);
    #|}
    #|parent();
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  if value.to_string() != "20" {
    fail("direct eval consumed the enclosing candidate plan")
  }
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() >= 3 else {
    fail("direct eval route did not retain the later candidate child")
  }
  if starts[0] != CandidateBytecodeExecutor ||
    starts[1] != CandidateTreeWalkerExecutor ||
    starts[2] != CandidateBytecodeExecutor {
    fail("direct eval changed the enclosing child route")
  }
}

///|
test "candidate verification rejects duplicate materialization sites" {
  let program = prepare_candidate_program(
    @parser.parse("function first() {}; function second() {};").stmts,
  )
  let first = program.root.children[0]
  let second = {
    ..program.root.children[1],
    materialization_site: first.materialization_site,
  }
  let duplicate_root = { ..program.root, children: [first, second] }
  let duplicate_program = { ..program, root: duplicate_root }
  let rejected = try {
    verify_candidate_program(duplicate_program)
    false
  } catch {
    _ => true
  }
  if !rejected {
    fail("candidate verification accepted duplicate materialization sites")
  }
}

///|
test "candidate tree retains eligible descendants of an unsupported parent" {
  let source =
    #|function parent() {
    #|  for (var value of [1]) {}
    #|  function child() { return 1; }
    #|}
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  guard root.children.length() == 1 else {
    fail("expected one parent declaration")
  }
  let parent = root.children[0]
  match parent.selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        ForOfStatement => ()
        _ => fail("parent fallback lost its lowering reason")
      }
    UseTreeWalker(_) => fail("parent fallback was not lowering unsupported")
    UseBytecode(_) => fail("unsupported parent selected bytecode")
  }
  guard parent.children.length() == 1 else {
    fail("unsupported parent must retain its child candidate")
  }
  match parent.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("eligible child was downgraded with its parent")
  }
}

///|
test "candidate eligible nested parent keeps lowering fallback local" {
  let source =
    #|function outer() {
    #|  function parent() { return 1; }
    #|  function child() { for (var value of [1]) {} }
    #|}
  let outer = prepare_candidate_program(@parser.parse(source).stmts).root.children[0]
  match outer.selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("eligible outer should remain bytecode")
  }
  match outer.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("eligible nested parent should remain bytecode")
  }
  match outer.children[1].selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        ForOfStatement => ()
        _ => fail("nested lowering fallback lost its reason")
      }
    UseTreeWalker(_) =>
      fail("nested child fallback was not lowering unsupported")
    UseBytecode(_) =>
      fail("nested lowering-unsupported child selected bytecode")
  }
}

///|
test "RED: strictness lineage reaches bytecode below a tree-only ancestor" {
  let source =
    #|function outer() {
    #|  "use strict";
    #|  for (var value of [1]) {}
    #|  function middle() {
    #|    function leaf() { return 1; }
    #|  }
    #|}
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  let outer = root.children[0]
  match outer.selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        ForOfStatement => ()
        _ => fail("outer fallback lost its lowering reason")
      }
    UseTreeWalker(_) => fail("outer fallback was not lowering unsupported")
    UseBytecode(_) => fail("strict outer unexpectedly selected bytecode")
  }
  let middle = outer.children[0]
  let leaf = middle.children[0]
  guard middle.bytecode is Some(_) && leaf.bytecode is Some(_) else {
    fail("nested strict lineage lost independently prepared bytecode")
  }
  guard middle.bytecode.unwrap().function.enclosing_strict else {
    fail("middle function lost strictness inherited from outer")
  }
  guard leaf.bytecode.unwrap().function.enclosing_strict else {
    fail("leaf function lost transitive strictness inherited from outer")
  }
}

///|
test "RED: lowering-unsupported children occupy non-executable candidate slots" {
  let source =
    #|function parent() { return 1; }
    #|function child() { for (var value of [1]) {} }
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  let root_bytecode = program.root.bytecode.unwrap()
  guard root_bytecode.function.children.length() == 1 else {
    fail("candidate bytecode retained a fabricated executable child")
  }
  guard root_bytecode.child_slots.length() == 2 else {
    fail("candidate bytecode lost a typed child slot")
  }
  match root_bytecode.child_slots[1] {
    CandidateTreeChild(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        ForOfStatement => ()
        _ => fail("tree child slot lost its lowering reason")
      }
    CandidateTreeChild(_) =>
      fail("tree child slot has the wrong fallback reason")
    CandidateBytecodeChild(_) =>
      fail("lowering-unsupported child became an executable candidate")
  }
}

///|
test "candidate extended signatures keep lowering fallback local" {
  let source =
    #|function parent() { return 1; }
    #|function child(value = 1) { return value; }
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  match root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) =>
      fail("eligible parent unexpectedly selected tree walker")
  }
  match root.children[1].selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        DefaultParameter => ()
        _ => fail("extended parameter fallback lost its lowering reason")
      }
    UseTreeWalker(_) =>
      fail("extended parameter fallback was not lowering unsupported")
    UseBytecode(_) => fail("unsupported extended child selected bytecode")
  }
}

///|
test "candidate lowering owns unsupported nested function-form outcomes" {
  let source =
    #|function parent() {
    #|  function* child() { yield 1; }
    #|  var asyncChild = async function named() { return 1; };
    #|}
  let parent = prepare_candidate_program(@parser.parse(source).stmts).root.children[0]
  guard parent.bytecode is Some(_) else {
    fail("eligible parent lost bytecode around unsupported function forms")
  }
  guard parent.children.length() == 2 else {
    fail("unsupported function forms were not retained as child slots")
  }
  match parent.children[0].selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        GeneratorDeclaration => ()
        _ => fail("generator declaration was classified outside lowering")
      }
    UseTreeWalker(_) => fail("generator declaration lost its typed fallback")
    UseBytecode(_) => fail("generator declaration selected bytecode")
  }
  match parent.children[1].selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        AsyncFunctionExpression => ()
        _ => fail("async function expression was classified outside lowering")
      }
    UseTreeWalker(_) =>
      fail("async function expression lost its typed fallback")
    UseBytecode(_) => fail("async function expression selected bytecode")
  }
}

///|
test "candidate object method forms retain ordered typed slots" {
  let source =
    #|var holder = {
    #|  *generator() { yield 1; },
    #|  async method() { return 1; },
    #|  async *combined() { yield 1; },
    #|};
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  guard root.bytecode is Some(_) else {
    fail("object method parent lost bytecode")
  }
  guard root.children.length() == 3 else {
    fail("object method consumer order was not retained")
  }
  match root.children[0].selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        ObjectLiteralGeneratorMethodProperty => ()
        _ => fail("generator method lost its lowering reason")
      }
    UseTreeWalker(_) => fail("generator method lost its typed fallback")
    UseBytecode(_) => fail("generator method selected bytecode")
  }
  match root.children[1].selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        ObjectLiteralAsyncMethodProperty => ()
        _ => fail("async method lost its lowering reason")
      }
    UseTreeWalker(_) => fail("async method lost its typed fallback")
    UseBytecode(_) => fail("async method selected bytecode")
  }
  match root.children[2].selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        ObjectLiteralAsyncGeneratorMethodProperty => ()
        _ => fail("async generator method lost its lowering reason")
      }
    UseTreeWalker(_) => fail("async generator method lost its typed fallback")
    UseBytecode(_) => fail("async generator method selected bytecode")
  }
}

///|
test "candidate consumer forms and same-name siblings retain immutable identities" {
  let source =
    #|function same() { return 1; }
    #|function same() { return 2; }
    #|var holder = {
    #|  anonymous: function() { return 3; },
    #|  named: function named() { return 4; },
    #|  method() { return 5; },
    #|  ["computed"]() { return 6; },
    #|  arrow: () => 7,
    #|};
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  guard root.children.length() == 7 else {
    fail("expected every declaration and consumer form")
  }
  guard root.children[0].name == Some("same") &&
    root.children[1].name == Some("same") else {
    fail("same-name declaration order was not retained")
  }
  guard root.children[0].source_identity.child_index == Some(0) &&
    root.children[1].source_identity.child_index == Some(1) else {
    fail("same-name siblings lost source positions")
  }
  guard !bytecode_source_identity_equal(
    root.children[0].source_identity,
    root.children[1].source_identity,
  ) else {
    fail("same-name siblings must have distinct identities")
  }
  match root.children[2].consumer_form {
    Some(FunctionConsumer) => ()
    _ => fail("anonymous function consumer form changed")
  }
  match root.children[3].consumer_form {
    Some(NamedFunctionConsumer("named")) => ()
    _ => fail("named function consumer form changed")
  }
  match root.children[4].consumer_form {
    Some(MethodFunctionConsumer) => ()
    _ => fail("method consumer form changed")
  }
  match root.children[5].consumer_form {
    Some(ComputedMethodFunctionConsumer) => ()
    _ => fail("computed method consumer form changed")
  }
  match root.children[6].consumer_form {
    Some(ArrowFunctionConsumer) => ()
    _ => fail("arrow consumer form changed")
  }
}

///|
test "candidate verification rejects a same-name sibling swap" {
  let source =
    #|function same() { return 1; }
    #|function same() { return 2; }
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  let swapped_root = {
    ..program.root,
    children: [program.root.children[1], program.root.children[0]],
  }
  let rejected = try {
    verify_candidate_program({ ..program, root: swapped_root })
    false
  } catch {
    _ => true
  }
  guard rejected else { fail("same-name sibling swap was accepted") }
}

///|
test "candidate verification rejects stale cross-compilation and malformed parent identities" {
  let source = "function child() { return 1; }"
  let first = prepare_candidate_program(@parser.parse(source).stmts)
  let second = prepare_candidate_program(@parser.parse(source).stmts)
  guard !physical_equal(first.program_identity, second.program_identity) else {
    fail("separate preparations reused a program identity")
  }
  let stale = try {
    verify_candidate_program({ ..second, root: first.root })
    false
  } catch {
    _ => true
  }
  guard stale else { fail("cross-compilation transplant was accepted") }
  let child = second.root.children[0]
  let malformed_child = {
    ..child,
    source_identity: {
      ..child.source_identity,
      parent_source_point_owner: None,
    },
  }
  let malformed_root = { ..second.root, children: [malformed_child] }
  let malformed = try {
    verify_candidate_program({ ..second, root: malformed_root })
    false
  } catch {
    _ => true
  }
  guard malformed else { fail("malformed parent identity was accepted") }

  let malformed_index_child = {
    ..child,
    source_identity: { ..child.source_identity, child_index: Some(99) },
  }
  let malformed_index_root = {
    ..second.root,
    children: [malformed_index_child],
  }
  let malformed_index = try {
    verify_candidate_program({ ..second, root: malformed_index_root })
    false
  } catch {
    _ => true
  }
  guard malformed_index else { fail("malformed child index was accepted") }

  let malformed_consumer_child = {
    ..child,
    source_identity: {
      ..child.source_identity,
      consumer_form: Some(ArrowFunctionConsumer),
    },
  }
  let malformed_consumer_root = {
    ..second.root,
    children: [malformed_consumer_child],
  }
  let malformed_consumer = try {
    verify_candidate_program({ ..second, root: malformed_consumer_root })
    false
  } catch {
    _ => true
  }
  guard malformed_consumer else { fail("malformed consumer form was accepted") }
}

///|
test "candidate preparation is deterministic across repeated calls" {
  let source =
    #|function same() { return 1; }
    #|function same() { return 2 + 3; }
    #|var holder = { method() {}, arrow: () => 1 };
  let first = prepare_candidate_program(@parser.parse(source).stmts)
  let second = prepare_candidate_program(@parser.parse(source).stmts)
  let labels = fn(children : Array[CandidateFunction]) -> Array[String] {
    children.map(child => {
      match child.consumer_form {
        Some(DeclareFunctionConsumer(name)) => "declare:" + name
        Some(MethodFunctionConsumer) => "method"
        Some(ArrowFunctionConsumer) => "arrow"
        Some(FunctionConsumer) => "function"
        Some(NamedFunctionConsumer(name)) => "named:" + name
        Some(ComputedMethodFunctionConsumer) => "computed"
        None => "root"
      }
    })
  }
  let selections = fn(children : Array[CandidateFunction]) -> Array[String] {
    children.map(child => {
      match child.selection {
        UseBytecode(_) => "bytecode"
        UseTreeWalker(CandidateLoweringUnsupported(_)) => "lowering"
        UseTreeWalker(CandidateActivationUnsupported(_)) => "activation"
      }
    })
  }
  json_inspect(labels(first.root.children), content=[
    "declare:same", "declare:same", "method", "arrow",
  ])
  json_inspect(labels(second.root.children), content=[
    "declare:same", "declare:same", "method", "arrow",
  ])
  json_inspect(selections(second.root.children), content=[
    "bytecode", "activation", "bytecode", "bytecode",
  ])
}

///|
test "candidate verification rejects coordinated identity index and consumer mutation" {
  let source =
    #|var holder = {
    #|  anonymous: function() { for (var value of [1]) {} },
    #|  named: function named() { for (var value of [1]) {} },
    #|};
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.children.length() == 2 else {
    fail("expected two unsupported function-expression children")
  }
  let first = program.root.children[0]
  let second = program.root.children[1]
  let mutated_first = {
    ..first,
    consumer_form: second.consumer_form,
    source_identity: {
      ..second.source_identity,
      child_index: Some(0),
      consumer_form: second.consumer_form,
    },
  }
  let mutated_second = {
    ..second,
    consumer_form: first.consumer_form,
    source_identity: {
      ..first.source_identity,
      child_index: Some(1),
      consumer_form: first.consumer_form,
    },
  }
  let malformed_root = {
    ..program.root,
    children: [mutated_first, mutated_second],
  }
  let rejected = try {
    verify_candidate_program({ ..program, root: malformed_root })
    false
  } catch {
    _ => true
  }
  guard rejected else {
    fail("coordinated candidate identity mutation was accepted")
  }
}
