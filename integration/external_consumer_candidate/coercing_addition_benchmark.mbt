// Issue #886 candidate-route benchmark. The timed region only repeats a
// stable Engine call; source generation, parsing, candidate preparation, and
// the correctness check all happen before b.bench starts.

///|
const ISSUE886_UNROLL_COUNT : Int = 10000

///|
fn issue886_unrolled_body() -> String {
  Array::makei(ISSUE886_UNROLL_COUNT, _ => "  value = left + right;\n").join("")
}

///|
fn issue886_source(name : String, initial : String, call : String) -> String {
  "function " +
  name +
  "(left, right) {\n" +
  "  var value = " +
  initial +
  ";\n" +
  issue886_unrolled_body() +
  "  return value;\n}\n" +
  name +
  call +
  ";\n"
}

///|
fn issue886_call(
  engine : @js_engine.Engine,
  name : String,
  args : Array[Json],
) -> Json {
  engine.call_json(name, args) catch {
    error => abort("issue-886 candidate call failed: " + error.to_string())
  }
}

///|
test "issue-886/candidate-engine/primitive-number-addition" (b : @bench.T) {
  let name = "issue886NumberAdd"
  let source = issue886_source(name, "0", "(1, 2)")
  let engine = @js_engine.Engine()
  engine.eval(source)
  json_inspect(issue886_call(engine, name, [1, 2]), content=3)
  b.bench(
    name="number+number",
    fn() { b.keep(issue886_call(engine, name, [1, 2])) },
    count=5,
  )
}

///|
test "issue-886/candidate-engine/primitive-string-addition" (b : @bench.T) {
  let name = "issue886StringAdd"
  let source = issue886_source(name, "\"\"", "(\"x\", \"y\")")
  let engine = @js_engine.Engine()
  engine.eval(source)
  json_inspect(issue886_call(engine, name, ["x", "y"]), content="xy")
  b.bench(
    name="string+string",
    fn() { b.keep(issue886_call(engine, name, ["x", "y"])) },
    count=5,
  )
}
