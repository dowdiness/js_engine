///|
test "candidate retained class field uses its defining source plan" {
  let engine = @js_engine.Engine()
  engine.eval(
    "globalThis.Issue989Holder = class _Issue989Holder { " +
    "field = () => 42; };",
  )
  engine.eval(
    (
      #|const { Issue989Holder } = globalThis;
      #|const issue989Holder = new Issue989Holder();
      #|var issue989Result = issue989Holder.field();
      #|function issue989ReadResult() { return issue989Result; }
    ),
  )
  json_inspect(engine.call_json("issue989ReadResult", []), content=42)
}
