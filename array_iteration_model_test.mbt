///| End-to-end JS tests for the Array iteration-model fix.
/// Tests live at repo root so they import @js_engine like other facade tests.

///|
test "phase1: write to hole clears the hole flag (fill case)" {
  let src =
    #|var a = [, 2, 3];
    #|a[0] = 10;
    #|console.log((0 in a) + "," + a.hasOwnProperty(0) + "," + a[0]);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["true,true,10"])
}
