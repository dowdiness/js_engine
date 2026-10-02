///|
test "facades reject nested invalid loop declarations before eval effects" {
  let source =
    #|var effect = 0;
    #|var caught = false;
    #|Function("try { eval('effect = 1; function never() { for (let i = 0, i = 1; false;) {} }'); } catch (error) { caught = error instanceof SyntaxError; }")();
    #|JSON.stringify([caught, effect]);
  let (_, run_result) = @js_engine.run(source)
  expect_string(run_result, "[true,0]", "run facade")
  let (_, compiled_result) = @js_engine.run_compiled(source)
  expect_string(compiled_result, "[true,0]", "run_compiled facade")
}
