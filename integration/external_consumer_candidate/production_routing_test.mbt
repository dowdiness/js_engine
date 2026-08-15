///|
// Candidate-mode external consumers use the same stable facade as default
// consumers.  Route-specific assertions are completed with Engine wiring;
// this fixture first locks the override topology.
test "candidate override fixture uses the stable Engine constructor" {
  let engine = @js_engine.Engine()
  engine.eval("function answer() { return 42; }")
  json_inspect(engine.call_json("answer", []), content=42)
}
