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
