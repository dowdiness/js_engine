///|
// This fixture imports only the stable facade. Its package-level virtual
// override keeps the Tree-walker available after Bytecode becomes the default.
test "issue 986 explicit Tree-walker override keeps the stable Engine contract" {
  let engine = @js_engine.Engine()
  engine.eval("function answer() { return 42; }")
  json_inspect(engine.call_json("answer", []), content=42)
  json_inspect(engine.call_json("answer", []), content=42)
}
