///|
test "Engine preserves named closures and Promise callbacks across eval turns" {
  let engine = @js_engine.Engine()
  let function_source =
    #|function self() {
    #|  Promise.resolve().then(function() { result = self === first; });
    #|  return function() { return self; };
    #|}
  engine.eval(
    "var result = false; var first = " +
    function_source +
    "; var read = first();",
  )
  let later =
    #|var unrelated = function self() { return 99; };
    #|function check(expectedSource) {
    #|  return {
    #|    escapedClosure: read() === first,
    #|    promiseCallback: result,
    #|    otherFunction: unrelated(),
    #|    originalSource: first.toString() === expectedSource
    #|  };
    #|}
  engine.eval(later)
  let _ = engine.run_microtask_checkpoint()
  json_inspect(engine.call_json("check", [Json::string(function_source)]), content={
    "escapedClosure": true,
    "promiseCallback": true,
    "otherFunction": 99,
    "originalSource": true,
  })
}
