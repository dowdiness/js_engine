// Issue #886 primitive-addition measurement gate.
//
// The source is parsed once before timing. Each timed sample runs a prepared
// candidate program whose hot function performs 100,000 fixed primitive `+`
// operations. The loop uses post-increment for control, so no property access
// or guest hook is part of the measured addition body.

///|
const ISSUE886_NUMBER_ADD_SRC : String =
  #|function issue886NumberAdd() {
  #|  var value = 0;
  #|  for (var i = 0; i < 100000; i++) {
  #|    value = 1 + 2;
  #|  }
  #|  return value;
  #|}
  #|issue886NumberAdd();

///|
const ISSUE886_STRING_ADD_SRC : String =
  #|function issue886StringAdd() {
  #|  var value = "";
  #|  for (var i = 0; i < 100000; i++) {
  #|    value = "x" + "y";
  #|  }
  #|  return value;
  #|}
  #|issue886StringAdd();

///|
fn issue886_parse_candidate_source(source : String) -> Array[@ast.Stmt] {
  @parser.parse(source).stmts catch {
    _ => abort("issue-886 benchmark source failed to parse")
  }
}

///|
fn issue886_run_candidate_source(stmts : Array[@ast.Stmt]) -> @runtime.Value {
  let interp = @interpreter.new_interpreter()
  @compiler.run_candidate_program(interp, stmts) catch {
    error => abort("issue-886 candidate benchmark raised: " + error.to_string())
  }
}

///|
fn issue886_expect_candidate_result(
  name : String,
  stmts : Array[@ast.Stmt],
  expected : String,
) -> Unit {
  let actual = issue886_run_candidate_source(stmts).to_string()
  guard actual == expected else {
    abort(
      "[" +
      name +
      "] benchmark correctness failed; expected " +
      expected +
      ", got " +
      actual,
    )
  }
}

///|
test "issue-886/candidate/primitive-number-addition" (b : @bench.T) {
  let stmts = issue886_parse_candidate_source(ISSUE886_NUMBER_ADD_SRC)
  issue886_expect_candidate_result(
    "issue-886/candidate/primitive-number-addition", stmts, "3",
  )
  b.bench(
    name="number+number",
    fn() { b.keep(issue886_run_candidate_source(stmts)) },
    count=5,
  )
}

///|
test "issue-886/candidate/primitive-string-addition" (b : @bench.T) {
  let stmts = issue886_parse_candidate_source(ISSUE886_STRING_ADD_SRC)
  issue886_expect_candidate_result(
    "issue-886/candidate/primitive-string-addition", stmts, "xy",
  )
  b.bench(
    name="string+string",
    fn() { b.keep(issue886_run_candidate_source(stmts)) },
    count=5,
  )
}
