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
