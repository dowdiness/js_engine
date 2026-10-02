///|
// RED: a normal function containing a lexical switch declaration must remain
// eligible for candidate Bytecode and preserve the outer binding after exit.
test "candidate admits switch lexical scope and restores outer binding" {
  let source =
    #|function read(flag) {
    #|  let outer = "outer";
    #|  let result = "unset";
    #|  switch (flag) {
    #|    case 1:
    #|      let outer = "inner";
    #|      result = outer;
    #|      break;
    #|    default:
    #|      result = "default";
    #|  }
    #|  return result + ":" + outer;
    #|}
    #|read(1);
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.children.length() == 1 else {
    fail("switch fixture did not retain its function candidate")
  }
  match program.root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) =>
      fail("switch lexical function was not admitted to Bytecode")
  }
  let bytecode = parse_bytecode_for_wb(source)
  let function = bytecode.main_for_wb().children[0]
  json_inspect(function.local_names, content=["flag"])
  assert_eq(function.local_slot_count, function.local_names.length() + 1)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "inner:outer")
  guard candidate_started_executors_for_wb(evidence)[1]
    is CandidateBytecodeExecutor else {
    fail("switch lexical function did not start through Bytecode")
  }
}

///|
test "nonlexical switches do not reserve a private local" {
  let bytecode = parse_bytecode_for_wb(
    "function f(flag) { switch (flag) { case 1: var value = 1; break; } return value; } f(1);",
  )
  let function = bytecode.main_for_wb().children[0]
  assert_eq(function.local_slot_count, function.local_names.length())
}

///|
fn switch_js_error_for_wb(source : String) -> (String, String) raise Error {
  let tree_error : String = try {
    ignore(@interpreter.new_interpreter().run(@parser.parse(source).stmts))
    fail("tree execution unexpectedly completed")
  } catch {
    @runtime.JsException(value) => value.to_string()
    error => raise error
  }
  let candidate_error : String = try {
    ignore(
      run_candidate_program(
        @interpreter.new_interpreter(),
        @parser.parse(source).stmts,
      ),
    )
    fail("candidate execution unexpectedly completed")
  } catch {
    @runtime.JsException(value) => value.to_string()
    error => raise error
  }
  (tree_error, candidate_error)
}

///|
fn assert_switch_early_error_preserves_effect_for_wb(
  source : String,
) -> Unit raise Error {
  let tree = @interpreter.new_interpreter()
  tree.global.def("effect", @runtime.Number(0.0), @runtime.VarBinding)
  try {
    ignore(tree.run(@parser.parse(source).stmts))
    fail("tree execution unexpectedly completed")
  } catch {
    @runtime.JsException(value) =>
      assert_true(value.to_string().contains("SyntaxError"))
    error => raise error
  }
  assert_eq(tree.global.get("effect").to_string(), "0")

  let candidate = @interpreter.new_interpreter()
  candidate.global.def("effect", @runtime.Number(0.0), @runtime.VarBinding)
  try {
    ignore(run_candidate_program(candidate, @parser.parse(source).stmts))
    fail("candidate execution unexpectedly completed")
  } catch {
    @runtime.JsException(value) =>
      assert_true(value.to_string().contains("SyntaxError"))
    error => raise error
  }
  assert_eq(candidate.global.get("effect").to_string(), "0")
}

///|
test "switch lexical declarations cover comma declarations and fallthrough" {
  let source =
    #|function probe(flag) {
    #|  let result = 0;
    #|  switch (flag) {
    #|    case 1:
    #|      let a = 1, b = 2;
    #|      result = a + b;
    #|    case 2:
    #|      const c = 3, d = 4;
    #|      result = result + c + d;
    #|      break;
    #|    default:
    #|      result = 9;
    #|  }
    #|  return result;
    #|}
    #|probe(1) + ":" + probe(2) + ":" + probe(0);
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.children.length() == 1 else {
    fail("comma declaration fixture did not retain its function candidate")
  }
  match program.root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      fail(
        "comma declarations lowered through Tree-walker: " +
        unsupported.reason.display_text(),
      )
    UseTreeWalker(CandidateActivationUnsupported(unsupported)) =>
      fail(
        "comma declarations were rejected by activation at " +
        unsupported.instruction_index.to_string(),
      )
  }
  let tree_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  assert_eq(tree_value.to_string(), "10:7:9")
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(candidate_value.to_string(), "10:7:9")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
}

///|
test "switch declarations leave expression completion intact" {
  let source = "switch (1) { case 1: let value = 7; 'expression'; }"
  let tree_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  assert_eq(tree_value.to_string(), "expression")
  let (candidate_value, _) = candidate_run_with_evidence_for_wb(source)
  assert_eq(candidate_value.to_string(), "expression")
}

///|
test "switch statement-list declaration forms keep prior completion" {
  let cases = [
    ("switch (1) { case 1: 'before'; let value = 1; }", "before"),
    ("switch (1) { case 1: 'before'; let a = 1, b = 2; }", "before"),
    ("switch (1) { case 1: 'before'; var a = 1, b = 2; }", "before"),
  ]
  for (source, expected) in cases {
    let tree_value = @interpreter.new_interpreter().run(
      @parser.parse(source).stmts,
    )
    assert_eq(tree_value.to_string(), expected)
    let (candidate_value, _) = candidate_run_with_evidence_for_wb(source)
    assert_eq(candidate_value.to_string(), expected)
  }
}

///|
test "switch discriminants use the outer environment before entering scope" {
  let source =
    #|function probe() {
    #|  let value = 1;
    #|  switch (value) {
    #|    case 1:
    #|      let value = 2;
    #|      return value;
    #|    default:
    #|      return 0;
    #|  }
    #|}
    #|probe();
  let tree_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  assert_eq(tree_value.to_string(), "2")
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(candidate_value.to_string(), "2")
  assert_eq(evidence.val.summary.tree_starts, 0)
}

///|
test "switch case expressions observe the shared TDZ" {
  let source =
    #|switch (1) {
    #|  case missing:
    #|    "unreachable";
    #|  case 1:
    #|    let missing = 1;
    #|}
  let (tree_error, candidate_error) = switch_js_error_for_wb(source)
  assert_true(tree_error.contains("ReferenceError"))
  assert_true(candidate_error.contains("ReferenceError"))
}

///|
test "switch default placement and no-match exits restore scope" {
  let source =
    #|function probe(flag) {
    #|  let result = "unset";
    #|  switch (flag) {
    #|    case 1:
    #|      let first = "one";
    #|      result = first;
    #|      break;
    #|    default:
    #|      result = "default";
    #|    case 2:
    #|      const second = "two";
    #|      result = result + second;
    #|      break;
    #|  }
    #|  return result;
    #|}
    #|function noMatch(flag) {
    #|  let result = "none";
    #|  switch (flag) {
    #|    case 1:
    #|      let value = "one";
    #|      result = value;
    #|  }
    #|  return result;
    #|}
    #|probe(0) + ":" + probe(2) + ":" + noMatch(0);
  let tree_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  assert_eq(tree_value.to_string(), "defaulttwo:unsettwo:none")
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(candidate_value.to_string(), "defaulttwo:unsettwo:none")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
}

///|
test "switch lexical declarations preserve TDZ across unselected cases" {
  let source =
    #|var observed = "unset";
    #|switch (0) {
    #|  case 0:
    #|    observed = missing;
    #|    break;
    #|  case 1:
    #|    let missing = 1;
    #|}
  let (tree_error, candidate_error) = switch_js_error_for_wb(source)
  assert_true(tree_error.contains("ReferenceError"))
  assert_true(candidate_error.contains("ReferenceError"))
}

///|
test "switch const assignment errors agree across executors" {
  let source = "switch (1) { case 1: const value = 1; value = 2; }"
  let (tree_error, candidate_error) = switch_js_error_for_wb(source)
  assert_true(tree_error.contains("TypeError"))
  assert_true(candidate_error.contains("TypeError"))
}

///|
test "switch duplicate lexical and var declarations reject before effects" {
  for
    source in [
      "switch (effect = 1) { case 1: let value; var value; } effect;", "switch (effect = 1) { case 1: let value; let value; } effect;",
    ] {
    assert_switch_early_error_preserves_effect_for_wb(source)
  }
}

///|
test "switch lexical closures and nested abrupt exits restore scope" {
  let source =
    #|function closure(flag) {
    #|  let read = function() { return "outer"; };
    #|  switch (flag) {
    #|    case 1:
    #|      let value = "inner";
    #|      read = function() { return value; };
    #|      break;
    #|    default:
    #|      break;
    #|  }
    #|  return read();
    #|}
    #|function nested(flag) {
    #|  let log = "";
    #|  try {
    #|    switch (flag) {
    #|      case 1:
    #|        {
    #|          let block = "block";
    #|          switch (block) {
    #|            case "block":
    #|              let nested = "nested";
    #|              log = block + ":" + nested;
    #|              break;
    #|          }
    #|          break;
    #|        }
    #|      default:
    #|        throw "boom";
    #|    }
    #|  } catch (error) {
    #|    switch (error) {
    #|      case "boom":
    #|        let error = "caught";
    #|        log = error;
    #|        break;
    #|    }
    #|  } finally {
    #|    log = log + ":finally";
    #|  }
    #|  return log;
    #|}
    #|closure(1) + ":" + closure(1) + ":" + closure(0) + ":" + nested(1) + ":" + nested(0);
  let tree_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  assert_eq(
    tree_value.to_string(),
    "inner:inner:outer:block:nested:finally:caught:finally",
  )
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(
    candidate_value.to_string(),
    "inner:inner:outer:block:nested:finally:caught:finally",
  )
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
}

///|
test "switch lexical scopes unwind return throw labels and finally" {
  let source =
    #|var events = "";
    #|function returning() {
    #|  try {
    #|    switch (1) {
    #|      case 1:
    #|        let value = "return";
    #|        return value;
    #|    }
    #|  } finally {
    #|    events = events + "R";
    #|  }
    #|}
    #|function throwing() {
    #|  try {
    #|    switch (1) {
    #|      case 1:
    #|        let value = "throw";
    #|        throw value;
    #|    }
    #|  } finally {
    #|    events = events + "T";
    #|  }
    #|}
    #|function labeledBreak() {
    #|  let log = "";
    #|  outer: for (var i = 0; i < 1; i = i + 1) {
    #|    switch (i) {
    #|      case 0:
    #|        let value = "B";
    #|        log = log + value;
    #|        break outer;
    #|    }
    #|  }
    #|  return log;
    #|}
    #|function labeledContinue() {
    #|  let log = "";
    #|  outer: for (var i = 0; i < 2; i = i + 1) {
    #|    switch (i) {
    #|      case 0:
    #|        let value = "C";
    #|        log = log + value;
    #|        continue outer;
    #|      default:
    #|        log = log + "D";
    #|    }
    #|    log = log + "X";
    #|  }
    #|  return log;
    #|}
    #|function replaced() {
    #|  try {
    #|    switch (1) {
    #|      case 1:
    #|        let value = "pending";
    #|        return value;
    #|    }
    #|  } finally {
    #|    return "finally";
    #|  }
    #|}
    #|var returned = returning();
    #|var thrown = "";
    #|try { throwing(); } catch (error) { thrown = error; }
    #|returned + ":" + thrown + ":" + labeledBreak() + ":" + labeledContinue() + ":" + replaced() + ":" + events;
  let tree_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  assert_eq(tree_value.to_string(), "return:throw:B:CDX:finally:RT")
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(candidate_value.to_string(), "return:throw:B:CDX:finally:RT")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
}

///|
test "re-entered switch lexical scopes give closures fresh bindings" {
  let source =
    #|function probe() {
    #|  let outer = "outer";
    #|  let saved = [];
    #|  for (var i = 0; i < 3; i = i + 1) {
    #|    switch (i) {
    #|      default:
    #|        let outer = i;
    #|        saved.push(function() { return outer; });
    #|    }
    #|  }
    #|  return saved[0]() + ":" + saved[1]() + ":" + saved[2]() + ":" + outer;
    #|}
    #|probe();
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "0:1:2:outer")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
}
