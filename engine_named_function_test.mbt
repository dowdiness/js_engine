///|
test "Engine preserves named closures and Promise callbacks across eval turns" {
  let engine = @js_engine.Engine()
  let source =
    #|var result = false;
    #|var first = function self() {
    #|  Promise.resolve().then(function() { result = self === first; });
    #|  return function() { return self; };
    #|};
    #|var read = first();
  engine.eval(source)
  let later =
    #|var unrelated = function self() { return 99; };
    #|function check() { return [read() === first, result, unrelated(), first.toString()]; }
  engine.eval(later)
  let _ = engine.run_microtask_checkpoint()
  json_inspect(engine.call_json("check", []), content=[
    true, true, 99, "function self() {\n  Promise.resolve().then(function() { result = self === first; });\n  return function() { return self; };\n}",
  ])
}
