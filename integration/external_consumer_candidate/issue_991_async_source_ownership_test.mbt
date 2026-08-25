///|
test "candidate root does not lend its materializer to retained async work" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|1 ** 2;
      #|globalThis.issue991RetainedAsync = async () => {
      #|  return (() => 42)();
      #|};
      #|function issue991ReadAsyncType() {
      #|  return typeof globalThis.issue991RetainedAsync;
      #|}
    ),
  )
  json_inspect(
    engine.call_json("issue991ReadAsyncType", []),
    content="function",
  )
  engine.eval(
    (
      #|var issue991Result = -1;
      #|var issue991Error = "";
      #|globalThis.issue991RetainedAsync()
      #|  .then(value => { issue991Result = value; })
      #|  .catch(error => { issue991Error = `${error.name}: ${error.message}`; });
      #|function issue991ReadState() { return [issue991Result, issue991Error]; }
    ),
  )
  let _ = engine.run_microtask_checkpoint()
  json_inspect(engine.call_json("issue991ReadState", []), content=[42, ""])
}

///|
test "candidate root does not lend its materializer to extended async work" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|1 ** 2;
      #|globalThis.issue991RetainedAsyncExt = async (value = 40, ...rest) => {
      #|  return (() => value + rest[0])();
      #|};
    ),
  )
  engine.eval(
    (
      #|var issue991ExtResult = -1;
      #|var issue991ExtError = "";
      #|globalThis.issue991RetainedAsyncExt(undefined, 2)
      #|  .then(value => { issue991ExtResult = value; })
      #|  .catch(error => { issue991ExtError = `${error.name}: ${error.message}`; });
      #|function issue991ReadExtState() {
      #|  return [issue991ExtResult, issue991ExtError];
      #|}
    ),
  )
  let _ = engine.run_microtask_checkpoint()
  json_inspect(engine.call_json("issue991ReadExtState", []), content=[42, ""])
}
