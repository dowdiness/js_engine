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
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
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
test "candidate aggregate evidence retains no per-call storage" {
  let program = prepare_candidate_program(
    @parser.parse("function child() {}").stmts,
  )
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=false),
  }
  for _ in 0..<100 {
    let activation = candidate_route_prepare(
      evidence,
      program.root.source_identity,
      program.root.selection,
    )
    candidate_route_start(activation, CandidateBytecodeExecutor)
    candidate_route_complete(activation, CandidateRouteNormal)
  }
  guard candidate_route_trace_length(evidence) == 0 else {
    fail("aggregate candidate recorder retained per-call trace")
  }
  guard evidence.val.summary.active_activations == 0 else {
    fail("aggregate candidate recorder retained completed activations")
  }
  guard evidence.val.summary.normal_completions == 100 else {
    fail("aggregate candidate recorder lost completion counts")
  }
}

///|
// A bytecode parent cannot safely retain a tree child until their closure
// storage is executor-neutral. A tree parent may still retain bytecode children.
test "candidate tree retains only the safe mixed parent direction" {
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
  guard bytecode_parent.bytecode is None else {
    fail("parent retained bytecode around a tree child")
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
test "candidate preparation retains independently selected children" {
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
  guard program.root.bytecode is None else {
    fail("candidate root retained bytecode around a tree child")
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
    #|function child() { return 1 ** 2; }
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
    #|  function child() { return 1 ** 2; }
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
  let program = prepare_candidate_program(@parser.parse("1 ** 2;").stmts)
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
test "RED: plain multiplication selects bytecode" {
  let program = prepare_candidate_program(@parser.parse("1 * 2;").stmts)
  match program.root.selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("plain multiplication must select bytecode")
  }
}

///|
fn assert_plain_multiplicative_route_for_wb(
  source : String,
  expected : String,
) -> Unit raise Error {
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  match program.root.selection {
    UseBytecode(ManagedSuspension) => ()
    UseBytecode(_) =>
      fail("plain multiplicative operation lost managed disposition")
    UseTreeWalker(_) =>
      fail("plain multiplicative operation selected Tree-walker")
  }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), expected)
  assert_eq(evidence.val.summary.bytecode_starts, 1)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate plain multiplicative family selects bytecode" {
  assert_plain_multiplicative_route_for_wb("2 * 3;", "6")
  assert_plain_multiplicative_route_for_wb("6 / 2;", "3")
  assert_plain_multiplicative_route_for_wb("5 % 2;", "1")
}

///|
test "candidate multiplicative compound and sibling operators stay tree-walker" {
  assert_candidate_tree_route_evidence_for_wb(
    "var value = 2; value *= 3; value;", "6",
  )
  assert_candidate_tree_route_evidence_for_wb(
    "var value = 6; value /= 2; value;", "3",
  )
  assert_candidate_tree_route_evidence_for_wb(
    "var value = 5; value %= 2; value;", "1",
  )
  assert_candidate_tree_route_evidence_for_wb("2 ** 3;", "8")
  assert_candidate_tree_route_evidence_for_wb("5 & 3;", "1")
}

///|
test "candidate object construction graduates through multiplicative family" {
  let program = prepare_candidate_program(
    @parser.parse(@benchmark_workloads.OBJECT_CONSTRUCTION_SRC).stmts,
  )
  match program.root.selection {
    UseBytecode(ManagedSuspension) => ()
    UseBytecode(_) => fail("object construction lost managed root disposition")
    UseTreeWalker(_) => fail("object construction selected Tree-walker")
  }
  let (value, evidence) = candidate_run_with_summary_for_wb(
    @benchmark_workloads.OBJECT_CONSTRUCTION_SRC,
  )
  assert_eq(value.to_string(), "1000")
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("object construction did not start a Bytecode activation")
  }
}

///|
test "candidate object construction keeps exact small multiplicative shape" {
  let source =
    #|var objects = [];
    #|for (var i = 0; i < 2; i++) {
    #|  objects.push({
    #|    id: i,
    #|    value: i * 2,
    #|    label: "item" + i,
    #|    active: true,
    #|    score: i * i
    #|  });
    #|}
    #|objects.length;
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  let bytecode = match program.root.bytecode {
    Some(bytecode) => bytecode.function.code
    None => fail("small object construction lost retained Bytecode")
  }
  let multiply_count = bytecode
    .filter(instruction => {
      match instruction {
        BinaryOp(Mul, BinaryExpression, _) => true
        _ => false
      }
    })
    .length()
  let push_count = bytecode
    .filter(instruction => {
      match instruction {
        PreparePlainPropertyCall("push", _) => true
        _ => false
      }
    })
    .length()
  let mut property_count = 0
  for instruction in bytecode {
    match instruction {
      MakeObject(keys) => property_count += keys.length()
      _ => ()
    }
  }
  assert_eq(multiply_count, 2)
  assert_eq(push_count, 1)
  assert_eq(property_count, 5)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "2")
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
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
// Candidate evidence for #886: plain addition enters the managed route once,
// before the runtime request frame is constructed.
test "candidate plain addition selects bytecode before frame construction" {
  let (value, evidence) = candidate_run_with_evidence_for_wb("1 + 2;")
  assert_eq(value.to_string(), "3")
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() == 1 else {
    fail("plain addition started an unexpected number of executors")
  }
  if starts[0] != CandidateBytecodeExecutor {
    fail("plain addition did not select bytecode")
  }
}

///|
test "candidate plain less-than-or-equal selects bytecode before frame construction" {
  let source = "1 <= 2;"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  match program.root.selection {
    UseBytecode(ManagedSuspension) => ()
    UseBytecode(_) =>
      fail("plain less-than-or-equal lost its managed disposition")
    UseTreeWalker(_) => fail("plain less-than-or-equal selected Tree-walker")
  }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.bytecode_starts, 1)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  guard evidence.val.events.length() == 3 else {
    fail("plain less-than-or-equal did not close exactly one route")
  }
  match evidence.val.events[0] {
    CandidateRoutePreparedEvent(prepared) =>
      match prepared.decision {
        UseBytecode(ManagedSuspension) => ()
        _ =>
          fail(
            "plain less-than-or-equal route was not prepared as managed bytecode",
          )
      }
    _ => fail("plain less-than-or-equal did not prepare before starting")
  }
  match evidence.val.events[1] {
    CandidateRouteStartedEvent(started) =>
      match started.executor {
        CandidateBytecodeExecutor => ()
        CandidateTreeWalkerExecutor =>
          fail("plain less-than-or-equal started Tree-walker")
      }
    _ => fail("plain less-than-or-equal did not start after preparation")
  }
  match evidence.val.events[2] {
    CandidateRouteCompletedEvent(completed) =>
      match completed.completion {
        CandidateRouteNormal => ()
        CandidateRouteAbrupt =>
          fail("plain less-than-or-equal completed abruptly")
      }
    _ => fail("plain less-than-or-equal did not complete exactly once")
  }
}

///|
test "candidate less-than-or-equal preserves UTF-16 String ordering" {
  let source =
    #|"\u{10000}" <= "\u{E000}";
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.bytecode_starts, 1)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate less-than-or-equal resumes through guest conversion" {
  let source =
    #|var events = "";
    #|var left = {};
    #|var right = {};
    #|left[Symbol.toPrimitive] = function(hint) {
    #|  events = events + "left:" + hint + ";";
    #|  return "2";
    #|};
    #|right[Symbol.toPrimitive] = function(hint) {
    #|  events = events + "right:" + hint + ";";
    #|  return "10";
    #|};
    #|function compare() { return left <= right; }
    #|compare();
    #|events;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "left:number;right:number;")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate plain relational operators retain exact binary origins" {
  let less_than = prepare_candidate_program(@parser.parse("1 < 2;").stmts)
  match less_than.root.selection {
    UseBytecode(ManagedSuspension) => ()
    UseBytecode(_) => fail("plain less-than lost its managed disposition")
    UseTreeWalker(_) => fail("plain less-than selected Tree-walker")
  }
  let greater_than = prepare_candidate_program(@parser.parse("1 > 2;").stmts)
  match greater_than.root.selection {
    UseBytecode(ManagedSuspension) => ()
    UseBytecode(_) => fail("plain greater-than lost its managed disposition")
    UseTreeWalker(_) => fail("plain greater-than selected Tree-walker")
  }
  let equality = prepare_candidate_program(@parser.parse("1 == 2;").stmts)
  match equality.root.selection {
    UseTreeWalker(CandidateActivationUnsupported(unsupported)) =>
      match unsupported.reason {
        BinaryOperation => ()
        _ => fail("equality lost its typed unsupported reason")
      }
    UseTreeWalker(_) => fail("equality lost its typed unsupported reason")
    UseBytecode(_) => fail("equality was admitted with relational operators")
  }
}

///|
test "candidate plain greater relational operators admit exact origins" {
  let greater_than = prepare_candidate_program(@parser.parse("1 > 2;").stmts)
  match greater_than.root.selection {
    UseBytecode(ManagedSuspension) => ()
    UseBytecode(_) => fail("plain greater-than lost its managed disposition")
    UseTreeWalker(_) => fail("plain greater-than selected Tree-walker")
  }
  let greater_than_or_equal = prepare_candidate_program(
    @parser.parse("1 >= 2;").stmts,
  )
  match greater_than_or_equal.root.selection {
    UseBytecode(ManagedSuspension) => ()
    UseBytecode(_) =>
      fail("plain greater-than-or-equal lost its managed disposition")
    UseTreeWalker(_) => fail("plain greater-than-or-equal selected Tree-walker")
  }
  let equality = prepare_candidate_program(@parser.parse("1 == 2;").stmts)
  match equality.root.selection {
    UseTreeWalker(CandidateActivationUnsupported(unsupported)) =>
      match unsupported.reason {
        BinaryOperation => ()
        _ => fail("equality lost its typed unsupported reason")
      }
    UseTreeWalker(_) => fail("equality lost its typed unsupported reason")
    UseBytecode(_) =>
      fail("equality was admitted with greater relational operators")
  }
}

///|
test "candidate plain greater-than closes its own route" {
  let source = "1 > 2;"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  match program.root.selection {
    UseBytecode(ManagedSuspension) => ()
    UseBytecode(_) => fail("plain greater-than lost its managed disposition")
    UseTreeWalker(_) => fail("plain greater-than selected Tree-walker")
  }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "false")
  assert_eq(evidence.val.summary.bytecode_starts, 1)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  guard evidence.val.events.length() == 3 else {
    fail("plain greater-than did not close exactly one route")
  }
  match evidence.val.events[0] {
    CandidateRoutePreparedEvent(prepared) =>
      match prepared.decision {
        UseBytecode(ManagedSuspension) => ()
        _ =>
          fail("plain greater-than route was not prepared as managed bytecode")
      }
    _ => fail("plain greater-than did not prepare before starting")
  }
  match evidence.val.events[1] {
    CandidateRouteStartedEvent(started) =>
      match started.executor {
        CandidateBytecodeExecutor => ()
        CandidateTreeWalkerExecutor =>
          fail("plain greater-than started Tree-walker")
      }
    _ => fail("plain greater-than did not start after preparation")
  }
  match evidence.val.events[2] {
    CandidateRouteCompletedEvent(completed) =>
      match completed.completion {
        CandidateRouteNormal => ()
        CandidateRouteAbrupt => fail("plain greater-than completed abruptly")
      }
    _ => fail("plain greater-than did not complete exactly once")
  }
}

///|
test "candidate plain greater-than-or-equal closes its own route" {
  let source = "1 >= 2;"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  match program.root.selection {
    UseBytecode(ManagedSuspension) => ()
    UseBytecode(_) =>
      fail("plain greater-than-or-equal lost its managed disposition")
    UseTreeWalker(_) => fail("plain greater-than-or-equal selected Tree-walker")
  }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "false")
  assert_eq(evidence.val.summary.bytecode_starts, 1)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  guard evidence.val.events.length() == 3 else {
    fail("plain greater-than-or-equal did not close exactly one route")
  }
  match evidence.val.events[0] {
    CandidateRoutePreparedEvent(prepared) =>
      match prepared.decision {
        UseBytecode(ManagedSuspension) => ()
        _ =>
          fail(
            "plain greater-than-or-equal route was not prepared as managed bytecode",
          )
      }
    _ => fail("plain greater-than-or-equal did not prepare before starting")
  }
  match evidence.val.events[1] {
    CandidateRouteStartedEvent(started) =>
      match started.executor {
        CandidateBytecodeExecutor => ()
        CandidateTreeWalkerExecutor =>
          fail("plain greater-than-or-equal started Tree-walker")
      }
    _ => fail("plain greater-than-or-equal did not start after preparation")
  }
  match evidence.val.events[2] {
    CandidateRouteCompletedEvent(completed) =>
      match completed.completion {
        CandidateRouteNormal => ()
        CandidateRouteAbrupt =>
          fail("plain greater-than-or-equal completed abruptly")
      }
    _ => fail("plain greater-than-or-equal did not complete exactly once")
  }
}

///|
test "candidate plain less-than preserves coercion order and Symbol failure" {
  let source =
    #|var events = "";
    #|var left = {};
    #|var right = {};
    #|left[Symbol.toPrimitive] = function(hint) {
    #|  events = events + "left:" + hint + ";";
    #|  return "2";
    #|};
    #|right[Symbol.toPrimitive] = function(hint) {
    #|  events = events + "right:" + hint + ";";
    #|  return "10";
    #|};
    #|var stringResult = left < right;
    #|var symbolThrew = false;
    #|try { Symbol("x") < right; } catch (error) { symbolThrew = true; }
    #|stringResult + "|" + events + "|" + symbolThrew;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(
    value.to_string(),
    "false|left:number;right:number;right:number;|true",
  )
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate plain greater relational operators preserve coercion order" {
  let source =
    #|var events = "";
    #|var left = {};
    #|var right = {};
    #|left[Symbol.toPrimitive] = function(hint) {
    #|  events = events + "left:" + hint + ";";
    #|  return "2";
    #|};
    #|right[Symbol.toPrimitive] = function(hint) {
    #|  events = events + "right:" + hint + ";";
    #|  return "10";
    #|};
    #|var less = left < right;
    #|var greater = left > right;
    #|var greaterEqual = left >= right;
    #|var symbolThrew = false;
    #|try { Symbol("x") > right; } catch (error) { symbolThrew = true; }
    #|less + "|" + greater + "|" + greaterEqual + "|" + events + "|" + symbolThrew;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(
    value.to_string(),
    "false|true|true|left:number;right:number;left:number;right:number;left:number;right:number;right:number;|true",
  )
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate relational siblings stay Tree-walker before effects" {
  assert_candidate_tree_route_evidence_for_wb(
    "var value = 1; value == 1;", "true",
  )
  assert_candidate_tree_route_evidence_for_wb(
    "var value = 1; value += 1; value;", "2",
  )
}

///|
test "candidate benchmark fixed-unroll shape selects managed bytecode" {
  let source =
    #|function issue886NumberAdd(left, right) {
    #|  var value = 0;
    #|  value = left + right;
    #|  value = left + right;
    #|  value = left + right;
    #|  return value;
    #|}
    #|issue886NumberAdd(1, 2);
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.children.length() == 1 else {
    fail("benchmark shape must contain one hot function")
  }
  let addition_count = match program.root.children[0].bytecode {
    Some(bytecode) =>
      bytecode.function.code
      .filter(instruction => {
        match instruction {
          BinaryOp(Add, BinaryExpression, _) => true
          _ => false
        }
      })
      .length()
    None => 0
  }
  match program.root.children[0].selection {
    UseBytecode(ManagedSuspension) => ()
    _ => fail("benchmark hot function was not UseBytecode(ManagedSuspension)")
  }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "3")
  assert_eq(addition_count, 3)
  let bytecode_starts = evidence.val.summary.bytecode_starts
  let tree_starts = evidence.val.summary.tree_starts
  let fallback_violations = evidence.val.summary.fallback_violations
  let replay_violations = evidence.val.summary.replay_violations
  guard addition_count == 3 &&
    bytecode_starts == 2 &&
    tree_starts == 0 &&
    fallback_violations == 0 &&
    replay_violations == 0 else {
    fail(
      "benchmark route mismatch: additions=" +
      addition_count.to_string() +
      ", bytecode=" +
      bytecode_starts.to_string() +
      ", tree=" +
      tree_starts.to_string() +
      ", fallback=" +
      fallback_violations.to_string() +
      ", replay=" +
      replay_violations.to_string(),
    )
  }
}

///|
test "candidate plain addition resumes through guest ToPrimitive" {
  let source =
    #|var events = "";
    #|var object = {};
    #|object[Symbol.toPrimitive] = function(hint) {
    #|  events = events + hint;
    #|  return 2;
    #|};
    #|function add(value) { return value + 1; }
    #|add(object);
    #|events;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "default")
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.contains(CandidateBytecodeExecutor) else {
    fail("plain addition did not enter the bytecode route")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate plain subtraction resumes through guest ToPrimitive" {
  let source =
    #|var events = "";
    #|var object = {};
    #|object[Symbol.toPrimitive] = function(hint) {
    #|  events = events + hint;
    #|  return 2;
    #|};
    #|function subtract(value) { return value - 1; }
    #|subtract(object);
    #|events;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "number")
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.contains(CandidateBytecodeExecutor) else {
    fail("plain subtraction did not enter the bytecode route")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate equality Fibonacci 20 keeps bounded full route evidence" {
  let source =
    #|function fib(n) {
    #|  if (n === 0 || n === 1) return n;
    #|  return fib(n - 1) + fib(n - 2);
    #|}
    #|fib(20);
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "6765")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
fn issue925_assert_fibonacci_candidates_bytecode_for_wb(
  program : CandidateProgram,
) -> Unit raise Error {
  match program.root.selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("Fibonacci root selected Tree-walker")
  }
  let fib_candidates = program.root.children.filter(child => {
    child.name == Some("fib")
  })
  guard fib_candidates.length() == 1 else {
    fail("Fibonacci candidate did not retain exactly one fib function")
  }
  match fib_candidates[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("fib activation selected Tree-walker")
  }
}

///|
test "issue 925 Fibonacci 10 keeps full route evidence on bytecode" {
  let source = @benchmark_workloads.FIBONACCI_SMALL_SRC
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  issue925_assert_fibonacci_candidates_bytecode_for_wb(program)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "55")
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_true(evidence.val.events.length() > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 925 Fibonacci 30 uses bounded aggregate route evidence" {
  let source = @benchmark_workloads.FIBONACCI_SRC
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  issue925_assert_fibonacci_candidates_bytecode_for_wb(program)
  let (value, evidence) = candidate_run_with_summary_for_wb(source)
  assert_eq(value.to_string(), "832040")
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  guard evidence.val.summary.maximum_concurrent_activations <= 64 else {
    fail(
      "Fibonacci 30 active depth grew beyond its recursive source depth: " +
      evidence.val.summary.maximum_concurrent_activations.to_string(),
    )
  }
  guard evidence.val.events.length() == 0 &&
    evidence.val.lifecycles.length() == 0 else {
    fail("Fibonacci 30 retained full per-activation route trace")
  }
}

///|
test "candidate equality descend 100000 stays entirely bytecode" {
  let source =
    #|function descend(n) {
    #|  if (n === 0) return 0;
    #|  return descend(n - 1);
    #|}
    #|descend(100000);
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "0")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate plain addition supports finite guest re-entry" {
  let source =
    #|var depth = 0;
    #|var object = {};
    #|object[Symbol.toPrimitive] = function(hint) {
    #|  if (depth === 320) return 1;
    #|  depth = depth + 1;
    #|  return object + 0;
    #|};
    #|function add(value) { return value + 0; }
    #|add(object);
    #|depth;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "320")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate compound addition evidence starts TreeWalker before effects" {
  let source = "var value = 1; value += 2; value;"
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "3")
  assert_eq(evidence.val.summary.tree_starts, 1)
  assert_eq(evidence.val.summary.bytecode_starts, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  guard evidence.val.events.length() >= 3 else {
    fail("compound addition route evidence is incomplete")
  }
  match evidence.val.events[0] {
    CandidateRoutePreparedEvent(prepared) =>
      match prepared.decision {
        UseTreeWalker(CandidateActivationUnsupported(_)) => ()
        UseTreeWalker(CandidateLoweringUnsupported(_)) =>
          fail("compound addition was mislabeled as lowering unsupported")
        UseBytecode(_) => fail("compound addition prepared bytecode")
      }
    _ => fail("compound addition started before its route decision")
  }
  match evidence.val.events[1] {
    CandidateRouteStartedEvent(started) =>
      match started.executor {
        CandidateTreeWalkerExecutor => ()
        CandidateBytecodeExecutor => fail("compound addition started bytecode")
      }
    _ => fail("compound addition route did not start after preparation")
  }
}

///|
fn assert_candidate_tree_route_evidence_for_wb(
  source : String,
  expected_value : String,
  child? : Bool = false,
) -> Unit raise Error {
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  let function = if child { root.children[0] } else { root }
  let source_identity = function.source_identity
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), expected_value)
  let mut prepared_count = 0
  let mut tree_starts = 0
  let mut bytecode_starts = 0
  let mut completed_count = 0
  let activation_ids : Array[Int] = []
  for event in evidence.val.events {
    match event {
      CandidateRoutePreparedEvent(prepared) =>
        if bytecode_source_identity_coordinates_equal_for_wb(
            prepared.source_identity,
            source_identity,
          ) {
          prepared_count += 1
          activation_ids.push(prepared.activation_id)
          match prepared.decision {
            UseTreeWalker(_) => ()
            UseBytecode(_) =>
              fail("excluded candidate prepared a bytecode route")
          }
        }
      CandidateRouteStartedEvent(started) =>
        if bytecode_source_identity_coordinates_equal_for_wb(
            started.source_identity,
            source_identity,
          ) {
          match started.executor {
            CandidateTreeWalkerExecutor => tree_starts += 1
            CandidateBytecodeExecutor => bytecode_starts += 1
          }
        }
      CandidateRouteCompletedEvent(completed) =>
        if bytecode_source_identity_coordinates_equal_for_wb(
            completed.source_identity,
            source_identity,
          ) {
          completed_count += 1
          match completed.completion {
            CandidateRouteNormal => ()
            CandidateRouteAbrupt =>
              fail("excluded candidate completed abruptly")
          }
        }
    }
  }
  guard prepared_count == 1 else {
    fail("excluded candidate did not record exactly one route decision")
  }
  guard tree_starts == prepared_count else {
    fail("excluded candidate did not start TreeWalker after preparation")
  }
  guard bytecode_starts == 0 else {
    fail("excluded candidate started bytecode")
  }
  guard completed_count == tree_starts else {
    fail("excluded candidate did not complete exactly once")
  }
  assert_eq(evidence.val.summary.bytecode_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  for activation_id in activation_ids {
    match evidence.val.lifecycles.get(activation_id) {
      Some(CandidateRouteFinished(completed)) =>
        match completed.completion {
          CandidateRouteNormal => ()
          CandidateRouteAbrupt =>
            fail("excluded candidate lifecycle completed abruptly")
        }
      _ => fail("excluded candidate lifecycle did not finish")
    }
  }
}

///|
// The execution helper prepares a fresh program, so its compilation token is
// intentionally distinct. Match the stable source coordinates while keeping
// the route decision and executor evidence authoritative.
fn bytecode_source_identity_coordinates_equal_for_wb(
  left : BytecodeSourceIdentity,
  right : BytecodeSourceIdentity,
) -> Bool {
  left.source_unit == right.source_unit &&
  left.source_point_owner == right.source_point_owner &&
  left.parent_source_point_owner == right.parent_source_point_owner &&
  left.child_index == right.child_index &&
  left.consumer_form == right.consumer_form
}

///|
test "candidate local identifier compound addition stays tree-walker" {
  assert_candidate_tree_route_evidence_for_wb(
    "for (var unused of [0]) {}; function local() { var x = 1; x += 2; return x; } local();",
    "3",
    child=true,
  )
}

///|
test "candidate environment or global compound addition stays tree-walker" {
  assert_candidate_tree_route_evidence_for_wb("var x = 1; x += 2; x;", "3")
}

///|
test "candidate property compound addition stays tree-walker" {
  assert_candidate_tree_route_evidence_for_wb(
    "var o = { x: 1 }; o.x += 2; o.x;", "3",
  )
}

///|
test "candidate computed compound addition stays tree-walker" {
  assert_candidate_tree_route_evidence_for_wb(
    "var o = { x: 1 }; var k = 'x'; o[k] += 2; o[k];", "3",
  )
}

///|
// RED: property deletion must eventually admit the called function through
// the candidate route even when the target is a Proxy.
test "RED: candidate static Proxy deletion enters bytecode" {
  let source =
    #|function remove(target) { return delete target.value; }
    #|var target = {};
    #|var proxy = new Proxy(target, {});
    #|remove(proxy);
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() >= 2 else {
    fail("static Proxy deletion did not start its callable")
  }
  match starts[1] {
    CandidateBytecodeExecutor => ()
    CandidateTreeWalkerExecutor =>
      fail("static Proxy deletion remained on the tree walker")
  }
}

///|
// RED: computed deletion must eventually admit the called function through
// the candidate route while retaining the raw key for runtime coercion.
test "RED: candidate computed deletion enters bytecode" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var target = {};
    #|remove(target, "value");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() >= 2 else {
    fail("computed deletion did not start its callable")
  }
  match starts[1] {
    CandidateBytecodeExecutor => ()
    CandidateTreeWalkerExecutor =>
      fail("computed deletion remained on the tree walker")
  }
}

///|
test "candidate static deletion preserves ordinary descriptor semantics" {
  let source =
    #|function remove(target) { return delete target.value; }
    #|function strictRemove(target) { "use strict"; return delete target.value; }
    #|var configurable = { value: 1 };
    #|var absent = {};
    #|var fixed = {};
    #|Object.defineProperty(fixed, "value", { value: 1, configurable: false });
    #|var accessorCalls = 0;
    #|var accessor = {};
    #|Object.defineProperty(accessor, "value", {
    #|  get: function() { accessorCalls = accessorCalls + 1; throw new Error("getter"); },
    #|  set: function(value) { accessorCalls = accessorCalls + 1; },
    #|  configurable: true
    #|});
    #|var configurableResult = remove(configurable);
    #|var absentResult = remove(absent);
    #|var sloppyFixedResult = remove(fixed);
    #|var strictThrew = false;
    #|try { strictRemove(fixed); } catch (error) { strictThrew = true; }
    #|var accessorResult = remove(accessor);
    #|configurableResult && absentResult && sloppyFixedResult === false &&
    #|  strictThrew && accessorResult && accessorCalls === 0 &&
    #|  Object.getOwnPropertyDescriptor(configurable, "value") === undefined &&
    #|  Object.getOwnPropertyDescriptor(accessor, "value") === undefined;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate computed deletion owns String hint ToPropertyKey" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var target = { value: 1, "7": 2 };
    #|var symbol = Symbol("value");
    #|target[symbol] = 3;
    #|var hint = "";
    #|var symbolKey = {
    #|  [Symbol.toPrimitive]: function(value) { hint = hint + value; return symbol; }
    #|};
    #|var order = "";
    #|var fallbackKey = {
    #|  toString: function() { order = order + "t"; return {}; },
    #|  valueOf: function() { order = order + "v"; return "7"; }
    #|};
    #|var objectResultKey = { toString: function() { return {}; }, valueOf: function() { return {}; } };
    #|var symbolResult = remove(target, symbolKey);
    #|var numberResult = remove(target, 7);
    #|var fallbackResult = remove(target, fallbackKey);
    #|var objectResultThrew = false;
    #|try { remove(target, objectResultKey); } catch (error) { objectResultThrew = true; }
    #|symbolResult && numberResult && fallbackResult && hint === "string" &&
    #|  order === "tv" && objectResultThrew &&
    #|  target[symbol] === undefined && target["7"] === undefined;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate computed deletion String fallback throws after one pair" {
  let source =
    #|var calls = "";
    #|var key = {
    #|  toString: function() { calls = calls + "t"; return {}; },
    #|  valueOf: function() { calls = calls + "v"; return {}; }
    #|};
    #|var threw = false;
    #|try { delete ({ value: 1 })[key]; } catch (error) { threw = true; }
    #|threw && calls === "tv";
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate computed deletion String hint gets non-callable methods once" {
  let source =
    #|var gets = "";
    #|var key = {};
    #|Object.defineProperty(key, "toString", { get: function() { gets = gets + "t"; return 1; } });
    #|Object.defineProperty(key, "valueOf", { get: function() { gets = gets + "v"; return 2; } });
    #|var threw = false;
    #|try { delete ({ value: 1 })[key]; } catch (error) { threw = true; }
    #|threw && gets === "tv";
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate computed deletion propagates key getter and call throws" {
  let source =
    #|var getterCalls = 0;
    #|var getterKey = {};
    #|Object.defineProperty(getterKey, Symbol.toPrimitive, {
    #|  get: function() { getterCalls = getterCalls + 1; throw new Error("getter"); }
    #|});
    #|var callCalls = 0;
    #|var callKey = {
    #|  [Symbol.toPrimitive]: function() { callCalls = callCalls + 1; throw new Error("call"); }
    #|};
    #|var getterThrew = false;
    #|try { delete ({ value: 1 })[getterKey]; } catch (error) { getterThrew = true; }
    #|var callThrew = false;
    #|try { delete ({ value: 1 })[callKey]; } catch (error) { callThrew = true; }
    #|getterThrew && callThrew && getterCalls === 1 && callCalls === 1;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate Proxy deletion suspends trap forwarding and invariants" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var forwardedTarget = { value: 1 };
    #|var forwarded = new Proxy(forwardedTarget, {});
    #|var forwardedResult = remove(forwarded, "value");
    #|var handler;
    #|var receiverSeen = false;
    #|var argsSeen = false;
    #|handler = {
    #|  deleteProperty: function(target, key) {
    #|    receiverSeen = this === handler;
    #|    argsSeen = target === trappedTarget && key === "value";
    #|    return false;
    #|  }
    #|};
    #|var trappedTarget = { value: 1 };
    #|var trapped = new Proxy(trappedTarget, handler);
    #|var sloppyFalse = remove(trapped, "value");
    #|var strictThrew = false;
    #|function strictRemove(target, key) { "use strict"; return delete target[key]; }
    #|try { strictRemove(trapped, "value"); } catch (error) { strictThrew = true; }
    #|var trueTarget = { value: 1 };
    #|var trueProxy = new Proxy(trueTarget, { deleteProperty: function() { return true; } });
    #|var trueResult = remove(trueProxy, "value");
    #|var nonCallableThrew = false;
    #|try { remove(new Proxy({}, { deleteProperty: 1 }), "value"); } catch (error) { nonCallableThrew = true; }
    #|var getterThrew = false;
    #|var getterHandler = {};
    #|Object.defineProperty(getterHandler, "deleteProperty", { get: function() { throw new Error("get"); } });
    #|try { remove(new Proxy({}, getterHandler), "value"); } catch (error) { getterThrew = true; }
    #|var callThrew = false;
    #|try { remove(new Proxy({}, { deleteProperty: function() { throw new Error("call"); } }), "value"); } catch (error) { callThrew = true; }
    #|var revoked = Proxy.revocable({}, {});
    #|revoked.revoke();
    #|var revokedThrew = false;
    #|try { remove(revoked.proxy, "value"); } catch (error) { revokedThrew = true; }
    #|var nonConfigTarget = {};
    #|Object.defineProperty(nonConfigTarget, "value", { value: 1, configurable: false });
    #|var nonConfigThrew = false;
    #|try { remove(new Proxy(nonConfigTarget, { deleteProperty: function() { return true; } }), "value"); } catch (error) { nonConfigThrew = true; }
    #|var sealedTarget = {};
    #|Object.preventExtensions(sealedTarget);
    #|var missingResult = remove(new Proxy(sealedTarget, { deleteProperty: function() { return true; } }), "value");
    #|var configurableTarget = { value: 1 };
    #|Object.preventExtensions(configurableTarget);
    #|var configurableThrew = false;
    #|try { remove(new Proxy(configurableTarget, { deleteProperty: function() { return true; } }), "value"); } catch (error) { configurableThrew = true; }
    #|forwardedResult && forwardedTarget.value === undefined && sloppyFalse === false &&
    #|  strictThrew && trueResult && receiverSeen && argsSeen && nonCallableThrew &&
    #|  getterThrew && callThrew && revokedThrew && nonConfigThrew && missingResult && configurableThrew;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate descriptor Proxy has absent fields skips isExtensible" {
  let source =
    #|var events = "";
    #|var count = 0;
    #|var rawTarget = {};
    #|Object.defineProperty(rawTarget, "value", { value: undefined, writable: false, enumerable: false, configurable: false });
    #|var descriptorTarget = new Proxy({}, {
    #|  isExtensible: function() { count = count + 1; events = events + "e"; return true; }
    #|});
    #|var descriptor = new Proxy(descriptorTarget, {
    #|  has: function(target, key) { events = events + "h" + key; return false; }
    #|});
    #|var target = new Proxy(rawTarget, {
    #|  getOwnPropertyDescriptor: function() { events = events + "d"; return descriptor; }
    #|});
    #|var proxy = new Proxy(target, { deleteProperty: function() { return true; } });
    #|var errorName = "";
    #|try { delete proxy.value; } catch (error) { errorName = error.name; }
    #|errorName + ":" + events + ":" + count;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(
    value.to_string(),
    "TypeError:dhenumerablehconfigurablehvaluehwritablehgethset:0",
  )
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate descriptor Proxy has absent fields skips throwing isExtensible" {
  let source =
    #|var events = "";
    #|var rawTarget = {};
    #|Object.defineProperty(rawTarget, "value", { value: undefined, writable: false, enumerable: false, configurable: false });
    #|var descriptorTarget = new Proxy({}, {
    #|  isExtensible: function() { events = events + "e"; throw new Error("extensible"); }
    #|});
    #|var descriptor = new Proxy(descriptorTarget, {
    #|  has: function(target, key) { events = events + "h" + key; return false; }
    #|});
    #|var target = new Proxy(rawTarget, {
    #|  getOwnPropertyDescriptor: function() { events = events + "d"; return descriptor; }
    #|});
    #|var proxy = new Proxy(target, { deleteProperty: function() { return true; } });
    #|var errorName = "";
    #|try { delete proxy.value; } catch (error) { errorName = error.name; }
    #|errorName + ":" + events;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(
    value.to_string(),
    "TypeError:dhenumerablehconfigurablehvaluehwritablehgethset",
  )
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate Proxy deletion skips isExtensible for absent target descriptor" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var events = "";
    #|var raw = {};
    #|var target = new Proxy(raw, {
    #|  getOwnPropertyDescriptor: function() { events = events + "d"; return undefined; },
    #|  isExtensible: function() { events = events + "e"; throw new Error("extensible"); }
    #|});
    #|var proxy = new Proxy(target, { deleteProperty: function() { return true; } });
    #|var result = false;
    #|var errorName = "";
    #|try { result = remove(proxy, "missing"); } catch (error) { errorName = error.name; }
    #|var count = 0;
    #|var events2 = "";
    #|var raw2 = {};
    #|var target2 = new Proxy(raw2, {
    #|  getOwnPropertyDescriptor: function() { events2 = events2 + "d"; return undefined; },
    #|  isExtensible: function() { count = count + 1; events2 = events2 + "e"; return false; }
    #|});
    #|var result2 = remove(new Proxy(target2, { deleteProperty: function() { return true; } }), "missing");
    #|result + ":" + errorName + ":" + events + ":" + result2 + ":" + events2 + ":" + count;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true::d:true:d:0")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate nested Proxy delete forwarding suspends invariant guest edges" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var forwardingEvents = "";
    #|var forwardingInner = new Proxy({ value: 1 }, {
    #|  deleteProperty: function(target, key) { forwardingEvents = forwardingEvents + "i"; return true; }
    #|});
    #|var forwardingOuter = new Proxy(forwardingInner, {});
    #|var forwarded = remove(forwardingOuter, "value");
    #|var invariantEvents = "";
    #|var invariantRaw = {};
    #|Object.defineProperty(invariantRaw, "missing", { value: 1, configurable: true });
    #|Object.preventExtensions(invariantRaw);
    #|var invariantInner = new Proxy(invariantRaw, {
    #|  isExtensible: function(target) { invariantEvents = invariantEvents + "e"; return false; }
    #|});
    #|var invariantMiddle = new Proxy(invariantInner, {
    #|  getOwnPropertyDescriptor: function(target, key) {
    #|    invariantEvents = invariantEvents + "a";
    #|    return undefined;
    #|  }
    #|});
    #|var invariantOuter = new Proxy(invariantMiddle, { deleteProperty: function() { return true; } });
    #|var invariantThrew = false;
    #|try { remove(invariantOuter, "missing"); } catch (error) { invariantThrew = true; }
    #|forwarded && forwardingEvents === "i" && invariantThrew && invariantEvents === "ae";
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate Proxy delete parses descriptor fields in canonical order" {
  let source =
    #|var events = "";
    #|var target = { value: 1 };
    #|var descriptor = {};
    #|Object.defineProperty(descriptor, "enumerable", { get: function() { events = events + "e"; return true; } });
    #|Object.defineProperty(descriptor, "configurable", { get: function() { events = events + "c"; return true; } });
    #|Object.defineProperty(descriptor, "value", { get: function() { events = events + "v"; return 1; } });
    #|Object.defineProperty(descriptor, "writable", { get: function() { events = events + "w"; return true; } });
    #|var descriptorProxyTarget = new Proxy(target, {
    #|  getOwnPropertyDescriptor: function() { events = events + "t"; return descriptor; }
    #|});
    #|var proxy = new Proxy(descriptorProxyTarget, { deleteProperty: function() { return true; } });
    #|var dataResult = delete proxy.value;
    #|var accessorEvents = "";
    #|var accessorGetter = function() { return 1; };
    #|var accessorSetter = function(value) {};
    #|var accessorTarget = {};
    #|Object.defineProperty(accessorTarget, "accessor", { get: accessorGetter, configurable: true });
    #|var accessorDescriptor = {};
    #|Object.defineProperty(accessorDescriptor, "enumerable", { get: function() { accessorEvents = accessorEvents + "e"; return false; } });
    #|Object.defineProperty(accessorDescriptor, "configurable", { get: function() { accessorEvents = accessorEvents + "c"; return true; } });
    #|Object.defineProperty(accessorDescriptor, "get", { get: function() { accessorEvents = accessorEvents + "g"; return accessorGetter; } });
    #|Object.defineProperty(accessorDescriptor, "set", { get: function() { accessorEvents = accessorEvents + "s"; return accessorSetter; } });
    #|var accessorDescriptorProxyTarget = new Proxy(accessorTarget, {
    #|  getOwnPropertyDescriptor: function() { accessorEvents = accessorEvents + "t"; return accessorDescriptor; }
    #|});
    #|var accessorProxy = new Proxy(accessorDescriptorProxyTarget, { deleteProperty: function() { return true; } });
    #|var accessorResult = delete accessorProxy.accessor;
    #|dataResult && events === "tecvw" && accessorResult && accessorEvents === "tecgs";
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate descriptor conversion observes six fields once and completes defaults" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var output = "";
    #|var events = "";
    #|var firstTarget = { value: 1 };
    #|var firstDescriptor = {};
    #|Object.defineProperty(firstDescriptor, "enumerable", { get: function() { events = events + "e"; return true; } });
    #|Object.defineProperty(firstDescriptor, "configurable", { get: function() { events = events + "c"; return true; } });
    #|Object.defineProperty(firstDescriptor, "value", { get: function() { events = events + "v"; return 1; } });
    #|Object.defineProperty(firstDescriptor, "writable", { get: function() { events = events + "w"; return true; } });
    #|var firstTargetProxy = new Proxy(firstTarget, { getOwnPropertyDescriptor: function() { events = events + "t"; return firstDescriptor; } });
    #|remove(new Proxy(firstTargetProxy, { deleteProperty: function() { return true; } }), "value");
    #|output = events;
    #|events = "";
    #|var descriptorValues = { enumerable: true, configurable: true, value: 1, writable: true };
    #|var descriptorProxy = new Proxy(descriptorValues, {
    #|  has: function(target, key) { events = events + "H" + key; return key in target; },
    #|  get: function(target, key) { events = events + "G" + key; return target[key]; }
    #|});
    #|var secondTargetProxy = new Proxy({ value: 1 }, { getOwnPropertyDescriptor: function() { return descriptorProxy; } });
    #|var secondResult = remove(new Proxy(secondTargetProxy, { deleteProperty: function() { return true; } }), "value");
    #|output = output + "|" + (secondResult && events);
    #|events = "";
    #|var accessorDescriptorValues = { enumerable: true, configurable: true, get: function() { return 1; }, set: undefined };
    #|var accessorDescriptorProxy = new Proxy(accessorDescriptorValues, {
    #|  has: function(target, key) { events = events + "H" + key; return key in target; },
    #|  get: function(target, key) { events = events + "G" + key; return target[key]; }
    #|});
    #|var accessorTargetProxy = new Proxy({ value: 1 }, { getOwnPropertyDescriptor: function() { return accessorDescriptorProxy; } });
    #|var accessorResult = remove(new Proxy(accessorTargetProxy, { deleteProperty: function() { return true; } }), "value");
    #|output = output + "|" + (accessorResult && events);
    #|var outcome = function(target) {
    #|  try { remove(new Proxy(target, { deleteProperty: function() { return true; } }), "value"); return "ok:" + events; }
    #|  catch (error) { return error.name + ":" + error.message + ":" + events; }
    #|};
    #|events = "";
    #|var accessorRaw = {};
    #|Object.defineProperty(accessorRaw, "value", { get: function() { return 1; }, configurable: false });
    #|var accessorTarget = new Proxy(accessorRaw, { getOwnPropertyDescriptor: function() { return { configurable: false }; } });
    #|output = output + "|" + outcome(accessorTarget);
    #|events = "";
    #|var writableRaw = {};
    #|Object.defineProperty(writableRaw, "value", { value: 1, writable: true, configurable: false });
    #|var writableDescriptor = { configurable: false };
    #|Object.defineProperty(writableDescriptor, "value", { get: function() { events = events + "v"; return 1; } });
    #|var writableTarget = new Proxy(writableRaw, { getOwnPropertyDescriptor: function() { return writableDescriptor; } });
    #|output = output + "|" + outcome(writableTarget);
    #|events = "";
    #|var frozenRaw = {};
    #|Object.defineProperty(frozenRaw, "value", { value: 1, writable: false, configurable: false });
    #|var frozenTarget = new Proxy(frozenRaw, { getOwnPropertyDescriptor: function() { return { configurable: false }; } });
    #|output = output + "|" + outcome(frozenTarget);
    #|output;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(
    value.to_string(),
    "tecvw|HenumerableGenumerableHconfigurableGconfigurableHvalueGvalueHwritableGwritableHgetHset|HenumerableGenumerableHconfigurableGconfigurableHvalueHwritableHgetGgetHsetGset|TypeError:'getOwnPropertyDescriptor' on proxy: trap reported descriptor kind (data/accessor) mismatch for non-configurable property on proxy target:|TypeError:'getOwnPropertyDescriptor' on proxy: trap reported non-configurable and non-writable for property which is writable on the proxy target:v|TypeError:'getOwnPropertyDescriptor' on proxy: trap reported different value for non-configurable non-writable data property on proxy target:",
  )
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate rejects writable lie for frozen data descriptor" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var events = "";
    #|var raw = {};
    #|Object.defineProperty(raw, "value", { value: 1, writable: false, configurable: false });
    #|var descriptor = { configurable: false };
    #|Object.defineProperty(descriptor, "value", { get: function() { events = events + "v"; return 1; } });
    #|Object.defineProperty(descriptor, "writable", { get: function() { events = events + "w"; return true; } });
    #|var target = new Proxy(raw, { getOwnPropertyDescriptor: function() { events = events + "t"; return descriptor; } });
    #|var errorName = "";
    #|var errorMessage = "";
    #|try { remove(new Proxy(target, { deleteProperty: function() { return true; } }), "value"); } catch (error) { errorName = error.name; errorMessage = error.message; }
    #|errorName + ":" + errorMessage + ":" + events;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(
    value.to_string(),
    "TypeError:'getOwnPropertyDescriptor' on proxy: trap reported non-configurable and writable for property which is non-writable on the proxy target:tvw",
  )
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate rejects configurable lie for frozen data descriptor" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var events = "";
    #|var raw = {};
    #|Object.defineProperty(raw, "value", { value: 1, writable: false, enumerable: true, configurable: false });
    #|var descriptor = { enumerable: true };
    #|Object.defineProperty(descriptor, "configurable", { get: function() { events = events + "c"; return true; } });
    #|Object.defineProperty(descriptor, "value", { get: function() { events = events + "v"; return 1; } });
    #|Object.defineProperty(descriptor, "writable", { get: function() { events = events + "w"; return false; } });
    #|var target = new Proxy(raw, { getOwnPropertyDescriptor: function() { events = events + "t"; return descriptor; } });
    #|var errorName = "";
    #|var errorMessage = "";
    #|try { remove(new Proxy(target, { deleteProperty: function() { return true; } }), "value"); } catch (error) { errorName = error.name; errorMessage = error.message; }
    #|errorName + ":" + errorMessage + ":" + events;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(
    value.to_string(),
    "TypeError:'getOwnPropertyDescriptor' on proxy: trap reported a different configurable value for a property on the proxy target:tcvw",
  )
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate nested Proxy target precedes descriptor getters and extensibility" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var events = "";
    #|var raw = { value: 1 };
    #|Object.defineProperty(raw, "value", { value: 1, writable: false, configurable: false });
    #|var inner = new Proxy(raw, {
    #|  getOwnPropertyDescriptor: function() { events = events + "g"; return { value: 1, configurable: false, enumerable: true }; },
    #|  isExtensible: function() { events = events + "e"; return true; }
    #|});
    #|var descriptor = { enumerable: true };
    #|Object.defineProperty(descriptor, "configurable", { get: function() { events = events + "c"; return false; } });
    #|Object.defineProperty(descriptor, "value", { get: function() { events = events + "v"; return 1; } });
    #|var target = new Proxy(inner, { getOwnPropertyDescriptor: function() { events = events + "o"; return descriptor; } });
    #|var proxy = new Proxy(target, { deleteProperty: function() { return true; } });
    #|var errorName = "";
    #|try { remove(proxy, "value"); } catch (error) { errorName = error.name; }
    #|errorName + ":" + events;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "TypeError:ogecv")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate nested target getOwnPropertyDescriptor throw wins descriptor getter" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var events = "";
    #|var descriptor = {};
    #|Object.defineProperty(descriptor, "configurable", { get: function() { events = events + "d"; throw new Error("descriptor"); } });
    #|var inner = new Proxy({ value: 1 }, { getOwnPropertyDescriptor: function() { events = events + "g"; throw new Error("target"); } });
    #|var target = new Proxy(inner, { getOwnPropertyDescriptor: function() { events = events + "o"; return descriptor; } });
    #|var proxy = new Proxy(target, { deleteProperty: function() { return true; } });
    #|var errorName = "";
    #|try { remove(proxy, "value"); } catch (error) { errorName = error.name; }
    #|errorName === "Error" && events === "og";
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate nested target isExtensible throw wins descriptor getter" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var events = "";
    #|var descriptor = {};
    #|Object.defineProperty(descriptor, "configurable", { get: function() { events = events + "d"; throw new Error("descriptor"); } });
    #|var inner = new Proxy({ value: 1 }, {
    #|  getOwnPropertyDescriptor: function() { events = events + "g"; return { value: 1, configurable: true }; },
    #|  isExtensible: function() { events = events + "e"; throw new Error("extensible"); }
    #|});
    #|var target = new Proxy(inner, { getOwnPropertyDescriptor: function() { events = events + "o"; return descriptor; } });
    #|var proxy = new Proxy(target, { deleteProperty: function() { return true; } });
    #|var errorName = "";
    #|try { remove(proxy, "value"); } catch (error) { errorName = error.name; }
    #|errorName === "Error" && events === "oge";
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate non-extensible absent descriptor reports TypeError" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var raw = {};
    #|Object.preventExtensions(raw);
    #|var target = new Proxy(raw, { getOwnPropertyDescriptor: function() { return { configurable: true }; } });
    #|var proxy = new Proxy(target, { deleteProperty: function() { return true; } });
    #|var errorName = "";
    #|try { remove(proxy, "missing"); } catch (error) { errorName = error.name; }
    #|errorName === "TypeError";
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate parses absent nonextensible descriptor before invariant" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var events = "";
    #|var raw = {};
    #|Object.preventExtensions(raw);
    #|var descriptor = {};
    #|Object.defineProperty(descriptor, "configurable", { get: function() { events = events + "c"; throw new Error("descriptor"); } });
    #|var inner = new Proxy(raw, { isExtensible: function() { events = events + "g"; return false; } });
    #|var target = new Proxy(inner, {
    #|  getOwnPropertyDescriptor: function() { events = events + "d"; return descriptor; }
    #|});
    #|var proxy = new Proxy(target, { deleteProperty: function() { return true; } });
    #|var errorName = "";
    #|try { remove(proxy, "missing"); } catch (error) { errorName = error.name; }
    #|errorName + ":" + events;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "Error:dgc")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate rejects undefined nonconfigurable descriptor before extensibility" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var events = "";
    #|var raw = {};
    #|Object.defineProperty(raw, "value", { value: 1, configurable: false });
    #|var inner = new Proxy(raw, { isExtensible: function() { events = events + "e"; throw new Error("extensible"); } });
    #|var target = new Proxy(inner, {
    #|  getOwnPropertyDescriptor: function() { events = events + "du"; return undefined; }
    #|});
    #|var proxy = new Proxy(target, { deleteProperty: function() { return true; } });
    #|var errorName = "";
    #|try { remove(proxy, "value"); } catch (error) { errorName = error.name; }
    #|errorName + ":" + events;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "TypeError:du")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate Proxy delete propagates descriptor getter throws and shape invariants" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var getterEvents = "";
    #|var throwingDescriptor = {};
    #|Object.defineProperty(throwingDescriptor, "enumerable", { get: function() { getterEvents = getterEvents + "e"; return true; } });
    #|Object.defineProperty(throwingDescriptor, "configurable", { get: function() { getterEvents = getterEvents + "c"; return true; } });
    #|Object.defineProperty(throwingDescriptor, "value", { get: function() { getterEvents = getterEvents + "v"; throw new Error("descriptor"); } });
    #|Object.defineProperty(throwingDescriptor, "writable", { get: function() { getterEvents = getterEvents + "w"; return true; } });
    #|var getterThrew = false;
    #|var throwingTarget = new Proxy({ value: 1 }, { getOwnPropertyDescriptor: function() { return throwingDescriptor; } });
    #|try { remove(new Proxy(throwingTarget, { deleteProperty: function() { return true; } }), "value"); } catch (error) { getterThrew = true; }
    #|var dataTarget = {};
    #|Object.defineProperty(dataTarget, "value", { value: 1, writable: false, configurable: false });
    #|var accessorReport = { get: function() {}, configurable: false };
    #|var dataKindThrew = false;
    #|var dataDescriptorTarget = new Proxy(dataTarget, { getOwnPropertyDescriptor: function() { return accessorReport; } });
    #|try { remove(new Proxy(dataDescriptorTarget, { deleteProperty: function() { return true; } }), "value"); } catch (error) { dataKindThrew = true; }
    #|var accessorTarget = {};
    #|Object.defineProperty(accessorTarget, "value", { get: function() { return 1; }, configurable: false });
    #|var dataReport = { value: 1, configurable: false };
    #|var accessorKindThrew = false;
    #|var accessorDescriptorTarget = new Proxy(accessorTarget, { getOwnPropertyDescriptor: function() { return dataReport; } });
    #|try { remove(new Proxy(accessorDescriptorTarget, { deleteProperty: function() { return true; } }), "value"); } catch (error) { accessorKindThrew = true; }
    #|getterThrew && getterEvents === "ecv" && dataKindThrew && accessorKindThrew;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate computed deletion preserves object key trap ordering" {
  let source =
    #|function remove(target, key) { return delete target[key]; }
    #|var events = "";
    #|var key = { [Symbol.toPrimitive]: function(hint) { events = events + "p"; return "value"; } };
    #|var target = { value: 1 };
    #|var handler = {};
    #|Object.defineProperty(handler, "deleteProperty", {
    #|  get: function() {
    #|    events = events + "l";
    #|    return function(target, key) { events = events + "c"; return false; };
    #|  }
    #|});
    #|var proxy = new Proxy(target, handler);
    #|var result = remove((events = events + "o", proxy), (events = events + "k", key));
    #|events === "okplc" && result === false;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate computed deletion supports finite guest re-entry" {
  let source =
    #|var depth = 0;
    #|var proxy;
    #|var key = {
    #|  [Symbol.toPrimitive]: function(hint) {
    #|    if (depth === 24) return "value";
    #|    depth = depth + 1;
    #|    return delete proxy[key];
    #|  }
    #|};
    #|proxy = new Proxy({ value: 1 }, { deleteProperty: function() { return true; } });
    #|function remove(target, key) { return delete target[key]; }
    #|remove(proxy, key);
    #|depth;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "24")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate non-property deletion remains lowering unsupported" {
  assert_bytecode_unsupported(
    "function remove() { return delete 1; }",
    DeleteNonPropertyOperator,
  )
}

///|
test "candidate plain subtraction selects managed bytecode" {
  let (value, evidence) = candidate_run_with_evidence_for_wb("1 - 2;")
  assert_eq(value.to_string(), "-1")
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() == 1 else {
    fail("plain subtraction started an unexpected number of executors")
  }
  if starts[0] != CandidateBytecodeExecutor {
    fail("plain subtraction did not select bytecode")
  }
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 924 default and candidate Array subtraction hooks stay equivalent" {
  let source =
    #|var events = "";
    #|var ownSymbol = [1];
    #|ownSymbol[Symbol.toPrimitive] = function(hint) {
    #|  events = events + "own-symbol:" + hint + ":" + (this === ownSymbol) + ";";
    #|  return 11;
    #|};
    #|var ownValue = [1];
    #|ownValue.valueOf = function() {
    #|  events = events + "own-value:" + (this === ownValue) + ";";
    #|  return 10;
    #|};
    #|var ownString = [1];
    #|ownString.valueOf = function() {
    #|  events = events + "own-string-value:" + (this === ownString) + ";";
    #|  return {};
    #|};
    #|ownString.toString = function() {
    #|  events = events + "own-string-toString:" + (this === ownString) + ";";
    #|  return "9";
    #|};
    #|var inheritedSymbol = [1];
    #|var inheritedSymbolProto = {};
    #|inheritedSymbolProto[Symbol.toPrimitive] = function(hint) {
    #|  events = events + "inherited-symbol:" + hint + ":" + (this === inheritedSymbol) + ";";
    #|  return 8;
    #|};
    #|Object.setPrototypeOf(inheritedSymbol, inheritedSymbolProto);
    #|var inheritedValue = [1];
    #|var inheritedValueProto = { valueOf: function() {
    #|  events = events + "inherited-value:" + (this === inheritedValue) + ";";
    #|  return 7;
    #|} };
    #|Object.setPrototypeOf(inheritedValue, inheritedValueProto);
    #|var inheritedString = [1];
    #|var inheritedStringProto = {
    #|  valueOf: function() {
    #|    events = events + "inherited-string-value:" + (this === inheritedString) + ";";
    #|    return {};
    #|  },
    #|  toString: function() {
    #|    events = events + "inherited-string-toString:" + (this === inheritedString) + ";";
    #|    return "6";
    #|  }
    #|};
    #|Object.setPrototypeOf(inheritedString, inheritedStringProto);
    #|function arraySubtractionMatrix() {
    #|  var results = [
    #|    ownSymbol - 1,
    #|    ownValue - 1,
    #|    ownString - 1,
    #|    inheritedSymbol - 1,
    #|    inheritedValue - 1,
    #|    inheritedString - 1
    #|  ];
    #|  return results.join(",") + "|" + events;
    #|}
    #|arraySubtractionMatrix();
  let expected = "10,9,8,7,6,5|" +
    "own-symbol:number:true;own-value:true;" +
    "own-string-value:true;own-string-toString:true;" +
    "inherited-symbol:number:true;inherited-value:true;" +
    "inherited-string-value:true;inherited-string-toString:true;"
  let default_interp = @interpreter.new_interpreter()
  let default_value = default_interp.run(@parser.parse(source).stmts)
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), expected)
  assert_eq(candidate_value.to_string(), expected)
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  let matrix_candidates = root.children.filter(child => {
    child.name == Some("arraySubtractionMatrix")
  })
  guard matrix_candidates.length() == 1 else {
    fail("Array subtraction matrix function was not retained exactly once")
  }
  issue924_assert_candidate_function_route_for_wb(
    matrix_candidates[0],
    evidence,
    CandidateRouteNormal,
  )
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 924 candidate throwing Array subtraction stays bytecode and cleans up" {
  let source =
    #|var events = "";
    #|var throwing = [1];
    #|throwing.valueOf = function() { events = events + "throw;"; throw "guest"; };
    #|function arraySubtractionThrowing() { return throwing - 1; }
  let default_interp = @interpreter.new_interpreter()
  let _ = default_interp.run(@parser.parse(source).stmts)
  let default_error = try {
    ignore(
      default_interp.call_value(
        default_interp.global.get("arraySubtractionThrowing"),
        @runtime.Undefined,
        [],
        @token.Loc::default(),
      ),
    )
    "no error"
  } catch {
    @runtime.JsException(value) => value.to_string()
    error => error.to_string()
  }
  let interp = @interpreter.new_interpreter()
  let (_, evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(source).stmts,
  )
  let candidate_error = try {
    ignore(
      interp.call_value(
        interp.global.get("arraySubtractionThrowing"),
        @runtime.Undefined,
        [],
        @token.Loc::default(),
      ),
    )
    "no error"
  } catch {
    @runtime.JsException(value) => value.to_string()
    error => error.to_string()
  }
  assert_eq(default_error, "guest")
  assert_eq(candidate_error, default_error)
  assert_eq(interp.global.get("events").to_string(), "throw;")
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  let throwing_candidates = root.children.filter(child => {
    child.name == Some("arraySubtractionThrowing")
  })
  guard throwing_candidates.length() == 1 else {
    fail("throwing Array subtraction function was not retained exactly once")
  }
  issue924_assert_candidate_function_route_for_wb(
    throwing_candidates[0],
    evidence,
    CandidateRouteAbrupt,
  )
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 924 candidate subtraction keeps queue and route evidence reusable" {
  let source =
    #|var events = "";
    #|var left = {};
    #|left[Symbol.toPrimitive] = function(hint) {
    #|  events = events + "left:" + hint + ";";
    #|  return 8;
    #|};
    #|function subtractLeft() { return left - 2; }
    #|var right = {};
    #|right[Symbol.toPrimitive] = function(hint) {
    #|  events = events + "right:" + hint + ";";
    #|  queueMicrotask(function() { events = events + "micro;"; });
    #|  throw new Error("right");
    #|};
    #|function subtractRight() { return left - right; }
  let interp = @interpreter.new_interpreter()
  let (_, evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(source).stmts,
  )
  let first = interp.call_value(
    interp.global.get("subtractLeft"),
    @runtime.Undefined,
    [],
    @token.Loc::default(),
  )
  assert_eq(first.to_string(), "6")
  assert_eq(interp.global.get("events").to_string(), "left:number;")
  let right_failed = try {
    let _ = interp.call_value(
      interp.global.get("subtractRight"),
      @runtime.Undefined,
      [],
      @token.Loc::default(),
    )
    false
  } catch {
    @runtime.JsException(value) => value.to_string().contains("right")
    _ => false
  }
  assert_true(right_failed)
  assert_eq(
    interp.global.get("events").to_string(),
    "left:number;left:number;right:number;",
  )
  assert_eq(interp.host.microtask_queue.length(), 1)
  interp.run_microtasks()
  assert_eq(interp.host.microtask_queue.length(), 0)
  assert_eq(
    interp.global.get("events").to_string(),
    "left:number;left:number;right:number;micro;",
  )
  let second = interp.call_value(
    interp.global.get("subtractLeft"),
    @runtime.Undefined,
    [],
    @token.Loc::default(),
  )
  assert_eq(second.to_string(), "6")
  assert_eq(
    interp.global.get("events").to_string(),
    "left:number;left:number;right:number;micro;left:number;",
  )
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 925 candidate less-than-or-equal keeps queue and route evidence reusable" {
  let source =
    #|var events = "";
    #|var left = {};
    #|left[Symbol.toPrimitive] = function(hint) {
    #|  events = events + "left:" + hint + ";";
    #|  return 8;
    #|};
    #|function compareLeft() { return left <= 10; }
    #|var right = {};
    #|right[Symbol.toPrimitive] = function(hint) {
    #|  events = events + "right:" + hint + ";";
    #|  queueMicrotask(function() { events = events + "micro;"; });
    #|  throw new Error("right");
    #|};
    #|function compareRight() { return left <= right; }
  let interp = @interpreter.new_interpreter()
  let (_, evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(source).stmts,
  )
  let first = interp.call_value(
    interp.global.get("compareLeft"),
    @runtime.Undefined,
    [],
    @token.Loc::default(),
  )
  assert_eq(first.to_string(), "true")
  assert_eq(interp.global.get("events").to_string(), "left:number;")
  let right_failed = try {
    let _ = interp.call_value(
      interp.global.get("compareRight"),
      @runtime.Undefined,
      [],
      @token.Loc::default(),
    )
    false
  } catch {
    @runtime.JsException(value) => value.to_string().contains("right")
    _ => false
  }
  assert_true(right_failed)
  assert_eq(
    interp.global.get("events").to_string(),
    "left:number;left:number;right:number;",
  )
  assert_eq(interp.host.microtask_queue.length(), 1)
  interp.run_microtasks()
  assert_eq(interp.host.microtask_queue.length(), 0)
  assert_eq(
    interp.global.get("events").to_string(),
    "left:number;left:number;right:number;micro;",
  )
  let second = interp.call_value(
    interp.global.get("compareLeft"),
    @runtime.Undefined,
    [],
    @token.Loc::default(),
  )
  assert_eq(second.to_string(), "true")
  assert_eq(
    interp.global.get("events").to_string(),
    "left:number;left:number;right:number;micro;left:number;",
  )
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
fn issue924_assert_candidate_function_route_for_wb(
  candidate : CandidateFunction,
  evidence : Ref[CandidateRouteEvidence],
  expected_completion : CandidateRouteCompletion,
) -> Unit raise Error {
  let source_identity = candidate.source_identity
  let mut prepared_count = 0
  let mut bytecode_starts = 0
  let mut tree_starts = 0
  let mut completed_count = 0
  for event in evidence.val.events {
    match event {
      CandidateRoutePreparedEvent(item) if bytecode_source_identity_coordinates_equal_for_wb(
          item.source_identity,
          source_identity,
        ) => {
        prepared_count += 1
        match item.decision {
          UseBytecode(_) => ()
          UseTreeWalker(_) =>
            fail("issue 924 Array subtraction function selected Tree-walker")
        }
      }
      CandidateRouteStartedEvent(item) if bytecode_source_identity_coordinates_equal_for_wb(
          item.source_identity,
          source_identity,
        ) =>
        match item.executor {
          CandidateBytecodeExecutor => bytecode_starts += 1
          CandidateTreeWalkerExecutor => tree_starts += 1
        }
      CandidateRouteCompletedEvent(item) if bytecode_source_identity_coordinates_equal_for_wb(
          item.source_identity,
          source_identity,
        ) => {
        completed_count += 1
        match (expected_completion, item.completion) {
          (CandidateRouteNormal, CandidateRouteNormal)
          | (CandidateRouteAbrupt, CandidateRouteAbrupt) => ()
          _ => fail("issue 924 Array subtraction completion mismatched")
        }
      }
      _ => ()
    }
  }
  assert_eq(prepared_count, 1)
  assert_eq(bytecode_starts, 1)
  assert_eq(tree_starts, 0)
  assert_eq(completed_count, 1)
}

///|
test "candidate compound subtraction remains tree-walker" {
  assert_candidate_tree_route_evidence_for_wb(
    "var value = 3; value -= 1; value;", "2",
  )
}

///|
test "candidate local identifier compound subtraction stays tree-walker" {
  assert_candidate_tree_route_evidence_for_wb(
    "for (var unused of [0]) {}; function local() { var x = 3; x -= 1; return x; } local();",
    "2",
    child=true,
  )
}

///|
test "candidate environment or global compound subtraction stays tree-walker" {
  assert_candidate_tree_route_evidence_for_wb("var x = 3; x -= 1; x;", "2")
}

///|
test "candidate property compound subtraction stays tree-walker" {
  assert_candidate_tree_route_evidence_for_wb(
    "var o = { x: 3 }; o.x -= 1; o.x;", "2",
  )
}

///|
test "candidate computed compound subtraction stays tree-walker" {
  assert_candidate_tree_route_evidence_for_wb(
    "var o = { x: 3 }; var k = 'x'; o[k] -= 1; o[k];", "2",
  )
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
fn candidate_run_with_summary_for_wb(
  source : String,
) -> (@runtime.Value, Ref[CandidateRouteEvidence]) raise Error {
  let interp = @interpreter.new_interpreter()
  run_candidate_program_with_summary(interp, @parser.parse(source).stmts) catch {
    @runtime.JsException(value) =>
      fail("candidate execution threw: " + value.to_string())
    error => fail("candidate execution failed: " + error.to_string())
  }
}

///|
test "production candidate recorder remains bounded across repeated calls" {
  let source =
    #|function answer() { return 42; }
    #|for (var index = 0; index < 100; index++) answer();
  let (_, evidence) = candidate_run_with_summary_for_wb(source)
  guard evidence.val.events.length() == 0 else {
    fail("production candidate recorder retained event history")
  }
  guard evidence.val.lifecycles.length() == 0 else {
    fail("production candidate recorder retained lifecycle history")
  }
  guard evidence.val.summary.active_activations == 0 else {
    fail("production candidate recorder retained in-flight activations")
  }
  guard evidence.val.summary.bytecode_starts == 101 else {
    fail("production candidate recorder lost bytecode start counts")
  }
  guard evidence.val.summary.tree_starts == 0 else {
    fail("production candidate recorder lost tree start counts")
  }
  guard evidence.val.summary.normal_completions == 101 else {
    fail("production candidate recorder lost completion counts")
  }
}

///|
test "old candidate functions retain bounded summaries after later eval" {
  let interp = @interpreter.new_interpreter()
  let (_, old_evidence) = run_candidate_program_with_summary(
    interp,
    @parser.parse("function oldFunction() { return 41; }").stmts,
  )
  ignore(
    run_candidate_program_with_summary(
      interp,
      @parser.parse("function anotherFunction() { return 42; }").stmts,
    ),
  )
  ignore(
    run_candidate_program_with_summary(
      interp,
      @parser.parse("for (var index = 0; index < 100; index++) oldFunction();").stmts,
    ),
  )
  guard old_evidence.val.events.length() == 0 else {
    fail("old candidate function retained event history")
  }
  guard old_evidence.val.lifecycles.length() == 0 else {
    fail("old candidate function retained lifecycle history")
  }
  guard old_evidence.val.summary.active_activations == 0 else {
    fail("old candidate function retained completed activations")
  }
  guard old_evidence.val.summary.bytecode_starts == 101 else {
    fail("old candidate function lost aggregate start counts")
  }
  guard old_evidence.val.summary.normal_completions == 101 else {
    fail("old candidate function lost aggregate completion counts")
  }
}

///|
test "aggregate recorder releases abrupt activation state" {
  let source =
    #|function maybeFail(shouldFail) {
    #|  if (shouldFail) throw "boom";
    #|  return 7;
    #|}
    #|try { maybeFail(true); } catch (error) {}
    #|maybeFail(false);
  let (value, evidence) = candidate_run_with_summary_for_wb(source)
  guard value.to_string() == "7" else {
    fail("aggregate abrupt fixture returned an unexpected value")
  }
  guard evidence.val.events.length() == 0 else {
    fail("aggregate abrupt fixture retained event history")
  }
  guard evidence.val.lifecycles.length() == 0 else {
    fail("aggregate abrupt fixture retained lifecycle history")
  }
  guard evidence.val.summary.active_activations == 0 else {
    fail("aggregate abrupt fixture retained an in-flight activation")
  }
  guard evidence.val.summary.abrupt_completions == 1 else {
    fail("aggregate abrupt fixture lost its abrupt completion count")
  }
  guard evidence.val.summary.normal_completions == 2 else {
    fail("aggregate abrupt fixture lost its normal completion counts")
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
test "repeated bytecode calls record distinct completed activations" {
  let (value, evidence) = candidate_run_with_evidence_for_wb(
    "function answer() { return 42; } answer(); answer();",
  )
  if value.to_string() != "42" {
    fail("repeated candidate calls returned an unexpected value")
  }
  guard evidence.val.events.length() == 9 else {
    fail("repeated candidate calls did not record two complete activations")
  }
  let first = match evidence.val.events[2] {
    CandidateRoutePreparedEvent(prepared) => prepared
    _ => fail("first function activation was not prepared before start")
  }
  let second = match evidence.val.events[5] {
    CandidateRoutePreparedEvent(prepared) => prepared
    _ => fail("second function activation was not prepared before start")
  }
  guard bytecode_source_identity_equal(
    first.source_identity,
    second.source_identity,
  ) else {
    fail("repeated calls did not retain the same function source identity")
  }
  guard first.activation_id != second.activation_id else {
    fail("repeated calls reused a route activation id")
  }
  for activation_id in [first.activation_id, second.activation_id] {
    match evidence.val.lifecycles.get(activation_id) {
      Some(CandidateRouteFinished(completed)) =>
        if completed.activation_id != activation_id ||
          completed.completion is CandidateRouteAbrupt {
          fail("repeated call activation did not complete normally")
        }
      _ => fail("repeated call activation did not reach completion")
    }
  }
}

///|
test "recursive bytecode calls record overlapping distinct activations" {
  let source =
    #|function recursiveAnswer(reenter) {
    #|  if (reenter) return recursiveAnswer();
    #|  return 42;
    #|}
    #|recursiveAnswer(true);
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  match program.root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("recursive fixture did not select bytecode")
  }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  if value.to_string() != "42" {
    fail("recursive candidate call returned an unexpected value")
  }
  let prepared = evidence.val.events.filter_map(event => {
    match event {
      CandidateRoutePreparedEvent(prepared) => Some(prepared)
      _ => None
    }
  })
  guard prepared.length() == 3 else {
    fail("recursive candidate call did not prepare root and two calls")
  }
  guard prepared[1].activation_id != prepared[2].activation_id else {
    fail("recursive candidate call reused the running activation id")
  }
  guard bytecode_source_identity_equal(
    prepared[1].source_identity,
    prepared[2].source_identity,
  ) else {
    fail("recursive calls did not retain the same function source identity")
  }
  guard evidence.val.summary.active_activations == 0 else {
    fail("recursive candidate calls retained in-flight lifecycle state")
  }
  guard evidence.val.summary.maximum_concurrent_activations == 3 else {
    fail("recursive candidate calls did not record overlapping activations")
  }
}

///|
test "bytecode call after abrupt completion records a fresh activation" {
  let source =
    #|function maybeFail(shouldFail) {
    #|  if (shouldFail) throw "boom";
    #|  return 7;
    #|}
    #|try { maybeFail(true); } catch (error) {}
    #|maybeFail(false);
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  match program.root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("abrupt-reuse fixture did not select bytecode")
  }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  if value.to_string() != "7" {
    fail("post-abrupt candidate call returned an unexpected value")
  }
  let prepared = evidence.val.events.filter_map(event => {
    match event {
      CandidateRoutePreparedEvent(prepared) => Some(prepared)
      _ => None
    }
  })
  guard prepared.length() == 3 else {
    fail("post-abrupt candidate call did not prepare two function calls")
  }
  guard prepared[1].activation_id != prepared[2].activation_id else {
    fail("post-abrupt candidate call reused its activation id")
  }
  guard bytecode_source_identity_equal(
    prepared[1].source_identity,
    prepared[2].source_identity,
  ) else {
    fail("post-abrupt calls did not retain the same source identity")
  }
  match evidence.val.lifecycles.get(prepared[1].activation_id) {
    Some(CandidateRouteFinished(completed)) =>
      if !(completed.completion is CandidateRouteAbrupt) {
        fail("first candidate call did not record abrupt completion")
      }
    _ => fail("first candidate call did not finish")
  }
  match evidence.val.lifecycles.get(prepared[2].activation_id) {
    Some(CandidateRouteFinished(completed)) =>
      if !(completed.completion is CandidateRouteNormal) {
        fail("second candidate call did not record normal completion")
      }
    _ => fail("second candidate call did not finish")
  }
  guard evidence.val.summary.active_activations == 0 else {
    fail("post-abrupt candidate calls retained in-flight lifecycle state")
  }
}

///|
fn assert_candidate_route_closed_abruptly(
  activation : CandidateRouteActivation,
  evidence : Ref[CandidateRouteEvidence],
  context : String,
) -> Unit raise {
  match activation.lifecycle.val {
    CandidateRouteFinished({ completion: CandidateRouteAbrupt, .. }) => ()
    _ => fail("\{context} did not close its candidate route abruptly")
  }
  guard evidence.val.summary.active_activations == 0 else {
    fail("\{context} retained an in-flight candidate activation")
  }
}

///|
test "candidate frame startup error completes its route abruptly" {
  let source = "function child() { return 1; }"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.bytecode is Some(bytecode) else {
    fail("startup-error fixture did not retain root bytecode")
  }
  guard program.script_preparation is Some(preparation) else {
    fail("startup-error fixture did not retain script preparation")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=false),
  }
  let activation = candidate_route_prepare(
    evidence,
    program.root.source_identity,
    program.root.selection,
  )
  candidate_route_start(activation, CandidateBytecodeExecutor)
  let failing_children : CandidateChildMaterializer = {
    materialize: fn(_interp, _child_index, _closure) raise {
      raise @errors.InternalError(message="injected candidate startup failure")
    },
  }
  let execution = CandidateBytecodeExecution(bytecode, failing_children)
  let interp = @interpreter.new_interpreter()
  ignore(
    interp.run_prepared_compiled_script(preparation, fn(ctx, env) raise {
      let frame = BytecodeFrame::candidate(execution, env, ctx, activation)
      let startup_failed = try {
        ignore(start_candidate_bytecode_frame(interp, frame))
        false
      } catch {
        @errors.InternalError(message~) =>
          message == "injected candidate startup failure"
        _ => false
      }
      guard startup_failed else {
        fail("candidate frame startup did not propagate its failure")
      }
      assert_candidate_route_closed_abruptly(
        activation, evidence, "candidate frame startup",
      )
      @runtime.Undefined
    }),
  )
}

///|
test "candidate function startup error completes its route abruptly" {
  let source = "function parent() { function child() { return 1; } return 2; }"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.children.length() == 1 else {
    fail("function-startup fixture did not retain its parent candidate")
  }
  let parent = program.root.children[0]
  guard parent.bytecode is Some(bytecode) else {
    fail("function-startup fixture did not retain parent bytecode")
  }
  guard program.script_preparation is Some(preparation) else {
    fail("function-startup fixture did not retain script preparation")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=false),
  }
  let activation = candidate_route_prepare(
    evidence,
    parent.source_identity,
    parent.selection,
  )
  candidate_route_start(activation, CandidateBytecodeExecutor)
  let failing_children : CandidateChildMaterializer = {
    materialize: fn(_interp, _child_index, _closure) raise {
      raise @errors.InternalError(
        message="injected candidate function startup failure",
      )
    },
  }
  let execution = CandidateBytecodeExecution(bytecode, failing_children)
  let interp = @interpreter.new_interpreter()
  ignore(
    interp.run_prepared_compiled_script(preparation, fn(ctx, env) raise {
      let frame = BytecodeFrame::candidate(execution, env, ctx, activation)
      let startup_failed = try {
        ignore(start_candidate_bytecode_frame(interp, frame))
        false
      } catch {
        @errors.InternalError(message~) =>
          message == "injected candidate function startup failure"
        _ => false
      }
      guard startup_failed else {
        fail("candidate function startup did not propagate its failure")
      }
      assert_candidate_route_closed_abruptly(
        activation, evidence, "candidate function startup",
      )
      @runtime.Undefined
    }),
  )
}

///|
test "candidate resume protocol error completes its route abruptly" {
  let source = "x += 1;"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.bytecode is Some(bytecode) else {
    fail("resume-error fixture did not retain root bytecode")
  }
  guard program.script_preparation is Some(preparation) else {
    fail("resume-error fixture did not retain script preparation")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=false),
  }
  let activation = candidate_route_prepare(
    evidence,
    program.root.source_identity,
    UseBytecode(ManagedSuspension),
  )
  candidate_route_start(activation, CandidateBytecodeExecutor)
  let execution = CandidateBytecodeExecution(
    bytecode,
    candidate_child_materializer(program.root, bytecode, evidence),
  )
  let interp = @interpreter.new_interpreter()
  ignore(
    interp.run_prepared_compiled_script(preparation, fn(ctx, env) raise {
      let frame = BytecodeFrame::candidate(execution, env, ctx, activation)
      let frame = start_candidate_bytecode_frame(interp, frame)
      let step = @runtime.ExecutorActivationFrame::step(frame, interp)
      guard step is @runtime.ExecutorActivationBindingReference(_) else {
        fail("resume-error fixture did not suspend on binding resolution")
      }
      let delivery_failed = try {
        @runtime.ExecutorActivationFrame::deliver_activation_completion(
          frame,
          @runtime.executor_activation_completion_normal(@runtime.Undefined),
        )
        false
      } catch {
        @errors.InternalError(message~) =>
          message == "bytecode binding reference resolution returned a value"
        _ => false
      }
      guard delivery_failed else {
        fail("candidate frame did not reject the mismatched completion")
      }
      assert_candidate_route_closed_abruptly(
        activation, evidence, "candidate resume protocol error",
      )
      @runtime.Undefined
    }),
  )
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
test "candidate runner falls back parent with tree child before activation" {
  let source =
    #|function parent() {
    #|  function child() { for (var value of [1]) {} }
    #|  return child();
    #|}
    #|parent();
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  let parent = program.root.children[0]
  guard parent.bytecode is None else { fail("mixed parent retained bytecode") }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  if value.to_string() != "undefined" {
    fail("mixed bytecode-parent result was unexpected")
  }
  let starts = candidate_started_executors_for_wb(evidence)
  guard starts.length() >= 3 else {
    fail("mixed parent route did not start root, parent, and child")
  }
  if starts[0] != CandidateTreeWalkerExecutor ||
    starts[1] != CandidateTreeWalkerExecutor ||
    starts[2] != CandidateTreeWalkerExecutor {
    fail("tree child did not conservatively move its parent to tree execution")
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
  if starts[0] != CandidateTreeWalkerExecutor ||
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
  if starts[0] != CandidateTreeWalkerExecutor ||
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
  if starts[0] != CandidateTreeWalkerExecutor ||
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
  if starts[0] != CandidateTreeWalkerExecutor ||
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
    #|parent(false) - parent(true);
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  if value.to_string() != "10" {
    fail("same-name sibling route returned an unexpected value")
  }
  assert_eq(
    candidate_started_executor_labels_for_wb(evidence),
    "tree,tree,tree,tree,tree",
  )
  let starts = evidence.val.events.filter_map(event => {
    match event {
      CandidateRouteStartedEvent(started) => Some(started)
      _ => None
    }
  })
  let parent = prepare_candidate_program(@parser.parse(source).stmts).root.children[0]
  assert_true(
    bytecode_source_identity_coordinates_equal_for_wb(
      starts[2].source_identity,
      parent.children[1].source_identity,
    ),
  )
  assert_true(
    bytecode_source_identity_coordinates_equal_for_wb(
      starts[4].source_identity,
      parent.children[0].source_identity,
    ),
  )
  assert_true(
    !bytecode_source_identity_equal(
      starts[2].source_identity,
      starts[4].source_identity,
    ),
  )
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
  if starts[0] != CandidateTreeWalkerExecutor ||
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
test "candidate nested fallback stops at the nearest safe tree parent" {
  let source =
    #|function outer() {
    #|  function parent() { return 1; }
    #|  function child() { for (var value of [1]) {} }
    #|}
  let outer = prepare_candidate_program(@parser.parse(source).stmts).root.children[0]
  match outer.selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        ForOfStatement => ()
        _ => fail("outer fallback lost the descendant lowering reason")
      }
    UseTreeWalker(_) => fail("outer fallback was not lowering unsupported")
    UseBytecode(_) => fail("outer retained bytecode around a tree child")
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
test "lowering-unsupported child moves the script root to tree execution" {
  let source =
    #|function parent() { return 1; }
    #|function child() { for (var value of [1]) {} }
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.bytecode is None else {
    fail("script root retained bytecode around a tree child")
  }
  match program.root.selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        ForOfStatement => ()
        _ => fail("script fallback lost the child lowering reason")
      }
    UseTreeWalker(_) => fail("script fallback was not owned by lowering")
    UseBytecode(_) => fail("script selected bytecode around a tree child")
  }
  match program.root.children[1].selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        ForOfStatement => ()
        _ => fail("tree child lost its lowering reason")
      }
    UseTreeWalker(_) => fail("tree child has the wrong fallback reason")
    UseBytecode(_) => fail("lowering-unsupported child selected bytecode")
  }
}

///|
test "lowering-unsupported child with eligible descendant stays tree-local" {
  let source =
    #|function fromIndexThrow() {
    #|  var position = { valueOf() { throw "position"; } };
    #|  try { [1].includes(1, position); } catch (error) { return error; }
    #|  return "missing";
    #|}
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  match root.selection {
    UseTreeWalker(CandidateLoweringUnsupported(_)) => ()
    UseTreeWalker(_) => fail("script root lost its lowering reason")
    UseBytecode(_) => fail("script root retained bytecode around a tree child")
  }
  guard root.children.length() == 1 else {
    fail("script root lost its lowering-unsupported child")
  }
  let outer = root.children[0]
  match outer.selection {
    UseTreeWalker(CandidateLoweringUnsupported(_)) => ()
    UseTreeWalker(_) => fail("outer function lost its lowering reason")
    UseBytecode(_) => fail("lowering-unsupported outer selected bytecode")
  }
  guard outer.children.length() == 1 else {
    fail("tree-only outer lost its eligible descendant")
  }
  match outer.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("eligible nested method lost bytecode")
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
test "candidate tree parent owns unsupported nested function-form outcomes" {
  let source =
    #|function parent() {
    #|  function* child() { yield 1; }
    #|  var asyncChild = async function named() { return 1; };
    #|}
  let parent = prepare_candidate_program(@parser.parse(source).stmts).root.children[0]
  guard parent.bytecode is None else {
    fail(
      "parent retained bytecode without a form-preserving child materializer",
    )
  }
  match parent.selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        GeneratorDeclaration => ()
        _ => fail("parent fallback lost the first unsupported function form")
      }
    UseTreeWalker(_) => fail("parent fallback was not owned by lowering")
    UseBytecode(_) => fail("parent selected bytecode around unsupported forms")
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
test "candidate root falls back around a generator declaration" {
  let source =
    #|function* value() { return 42; }
    #|let iterator = value();
    #|iterator.next().value;
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  match root.children[0].selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        GeneratorDeclaration => ()
        _ => fail("generator child fallback lost its declaration reason")
      }
    UseTreeWalker(_) =>
      fail("generator child fallback was not owned by lowering")
    UseBytecode(_) => fail("generator child selected bytecode")
  }
  match root.selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        GeneratorDeclaration => ()
        _ => fail("root fallback lost the generator declaration reason")
      }
    UseTreeWalker(_) =>
      fail("root generator fallback was not owned by lowering")
    UseBytecode(_) =>
      fail("root selected bytecode around a generator declaration")
  }
  let (value, _) = candidate_run_with_evidence_for_wb(source)
  if value.to_string() != "42" {
    fail("tree fallback did not preserve generator declaration semantics")
  }
}

///|
test "candidate object method forms keep their parent on the tree walker" {
  let source =
    #|var holder = {
    #|  *generator() { yield 1; },
    #|  async method() { return 1; },
    #|  async *combined() { yield 1; },
    #|};
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  guard root.bytecode is None else {
    fail("object method parent retained bytecode without form preservation")
  }
  match root.selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        ObjectLiteralGeneratorMethodProperty => ()
        _ => fail("object method parent lost its first unsupported form")
      }
    UseTreeWalker(_) => fail("object method parent fallback left lowering")
    UseBytecode(_) => fail("object method parent selected bytecode")
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
    #|function same() { return 2 - 3; }
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
    "bytecode", "bytecode", "bytecode", "bytecode",
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
