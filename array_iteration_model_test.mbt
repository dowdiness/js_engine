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

///|
test "phase2: forEach observes own accessor side effect" {
  let src =
    #|var arr = [, 1, 2];
    #|var observed = "none";
    #|Object.defineProperty(arr, "0", {
    #|  get: function() { return 99; },
    #|  configurable: true,
    #|});
    #|arr.forEach(function(v, i) { if (i === 0) observed = v; });
    #|console.log(observed);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["99"])
}

///|
test "phase2: indexOf walks Array.prototype for hole indices" {
  let src =
    #|var arr = [0, , 2];
    #|Array.prototype[1] = 6.99;
    #|var idx = arr.indexOf(6.99);
    #|delete Array.prototype[1];
    #|console.log(idx);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["1"])
}
