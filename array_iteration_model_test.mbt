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

///|
test "phase1: Array.from materializes a hole-free array" {
  let src =
    #|var a = Array.from([, , 9]);
    #|console.log((0 in a) + "," + (1 in a) + "," + (2 in a) + "," + a[2]);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["true,true,true,9"])
}

///|
test "phase1: shrink-then-push does not leak holes above new length" {
  let src =
    #|var a = [, 2, 3];
    #|a.length = 1;
    #|a.push(9);
    #|console.log(a.length + "," + (1 in a) + "," + a[1]);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["2,true,9"])
}
