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
    UseTreeWalker(_) => fail("eligible parent unexpectedly selected tree walker")
  }
  match program.root.children[1].selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      if unsupported.reason is ForOfStatement {
        ()
      } else {
        fail("child fallback lost its lowering reason")
      }
    UseTreeWalker(_) => fail("child fallback was not typed as lowering unsupported")
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
test "candidate extended signatures keep lowering fallback local" {
  let source =
    #|function parent() { return 1; }
    #|function child(value = 1) { return value; }
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  match root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("eligible parent unexpectedly selected tree walker")
  }
  match root.children[1].selection {
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      match unsupported.reason {
        DefaultParameter => ()
        _ => fail("extended parameter fallback lost its lowering reason")
      }
    UseTreeWalker(_) => fail("extended parameter fallback was not lowering unsupported")
    UseBytecode(_) => fail("unsupported extended child selected bytecode")
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
test "candidate verification rejects stale cross-compilation and malformed parent identities" {
  let source = "function child() { return 1; }"
  let first = prepare_candidate_program(@parser.parse(source).stmts)
  let second = prepare_candidate_program(@parser.parse(source).stmts)
  guard !physical_equal(first.program_identity, second.program_identity) else {
    fail("separate preparations reused a program identity")
  }
  let stale = try {
    verify_candidate_function(second.root, first.program_identity, None)
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
  let malformed_root = {
    ..second.root,
    children: [malformed_child],
  }
  let malformed = try {
    verify_candidate_function(malformed_root, second.program_identity, None)
    false
  } catch {
    _ => true
  }
  guard malformed else { fail("malformed parent identity was accepted") }

  let malformed_index_child = {
    ..child,
    source_identity: {
      ..child.source_identity,
      child_index: Some(99),
    },
  }
  let malformed_index_root = {
    ..second.root,
    children: [malformed_index_child],
  }
  let malformed_index = try {
    verify_candidate_function(malformed_index_root, second.program_identity, None)
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
    verify_candidate_function(malformed_consumer_root, second.program_identity, None)
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
    children.map(child => match child.consumer_form {
      Some(DeclareFunctionConsumer(name)) => "declare:" + name
      Some(MethodFunctionConsumer) => "method"
      Some(ArrowFunctionConsumer) => "arrow"
      Some(FunctionConsumer) => "function"
      Some(NamedFunctionConsumer(name)) => "named:" + name
      Some(ComputedMethodFunctionConsumer) => "computed"
      None => "root"
    })
  }
  let selections = fn(children : Array[CandidateFunction]) -> Array[String] {
    children.map(child => match child.selection {
      UseBytecode(_) => "bytecode"
      UseTreeWalker(CandidateLoweringUnsupported(_)) => "lowering"
      UseTreeWalker(CandidateActivationUnsupported(_)) => "activation"
    })
  }
  json_inspect(labels(first.root.children), content=[
    "declare:same",
    "declare:same",
    "method",
    "arrow",
  ])
  json_inspect(labels(second.root.children), content=[
    "declare:same",
    "declare:same",
    "method",
    "arrow",
  ])
  json_inspect(
    selections(second.root.children),
    content=["bytecode", "activation", "bytecode", "bytecode"],
  )
}
