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

///|
test "phase2: forEach skips own holes when prototype has nothing at that index" {
  // Per ES2024 §22.1.3.10 step 6.b.i, forEach calls the callback only when
  // HasProperty(O, Pk) is true. A hole with no inherited prototype
  // property must NOT be visited — exercises has_array_like_element.
  let src =
    #|var seen = [];
    #|[0, , 2].forEach(function(v, i) { seen.push(i + ":" + v); });
    #|console.log(seen.join("|"));
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["0:0|2:2"])
}

///|
test "phase2: forEach visits inherited prototype index at a hole position" {
  let src =
    #|var arr = [0, , 2];
    #|Array.prototype[1] = 99;
    #|var seen = [];
    #|arr.forEach(function(v, i) { seen.push(i + ":" + v); });
    #|delete Array.prototype[1];
    #|console.log(seen.join("|"));
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["0:0|1:99|2:2"])
}

///|
test "phase2: direct arr[i] read walks Array.prototype for OOB index" {
  let src =
    #|var arr = [0, 1, 2];
    #|Array.prototype[5] = "inherited";
    #|var val = arr[5];
    #|delete Array.prototype[5];
    #|console.log(val);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["inherited"])
}

///|
test "phase2: direct arr[i] read walks Array.prototype for hole" {
  let src =
    #|var arr = [0, , 2];
    #|Array.prototype[1] = "inherited";
    #|var val = arr[1];
    #|delete Array.prototype[1];
    #|console.log(val);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["inherited"])
}

///|
test "phase3: Array(n) creates a hole-bearing array" {
  let src =
    #|var a = Array(5);
    #|Array.prototype[2] = "inherited";
    #|var v = a[2];
    #|delete Array.prototype[2];
    #|console.log((0 in a) + "," + a.length + "," + v);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["false,5,inherited"])
}

///|
test "phase3: sparse CreateDataPropertyOrThrow target leaves padding as holes" {
  let src =
    #|// Sparse write through set_property: indices 0..2 must remain holes.
    #|var a = [];
    #|a[3] = 9;
    #|console.log((0 in a) + "," + (1 in a) + "," + (2 in a) + "," + a.length);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["false,false,false,4"])
}

///|
test "phase3: a.length = N extension marks new indices as holes" {
  // After length extension, new indices have no own property; 'in' walks the
  // prototype chain so 3 in a is true when Array.prototype[3] is set.
  // The value at a[3] is inherited from Array.prototype, not undefined.
  let src =
    #|var a = [1, 2];
    #|a.length = 5;
    #|Array.prototype[3] = "inherited";
    #|var v3 = a[3];
    #|var has3 = (3 in a);
    #|delete Array.prototype[3];
    #|console.log(has3 + "," + v3);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["true,inherited"])
}

///|
test "phase3: defineProperty OOB index raises length and marks gap as holes" {
  let src =
    #|var a = [10, 20, 30];
    #|Object.defineProperty(a, "5", { value: 7, writable: true, enumerable: true, configurable: true });
    #|console.log(a.length + "," + (3 in a) + "," + (4 in a) + "," + (5 in a) + "," + a[5]);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["6,false,false,true,7"])
}

///|
test "review F1: arr[s] falls through to %Array.prototype% walk on shortcut miss" {
  // PR-#122 follow-up review: when no prototype override is set, the
  // get_computed_property String_ branch's built-in-method shortcut
  // returns Undefined for ES5 methods delegated to Array.prototype
  // (map/filter/forEach/…). The fall-through to lookup_builtin_proto
  // must fire so `arr["map"]` matches `arr.map`.
  let src =
    #|var a = [1, 2, 3];
    #|console.log(typeof a["map"] + "," + (a["map"] === a.map));
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["function,true"])
}

///|
test "review F2: large numeric string key walks the prototype chain" {
  // PR-#122 follow-up review: "3000000000" is a valid array-like key
  // per spec but >= 2^31. The String_ branch must mirror Number's
  // Int-range discipline (i64-and-bound, not bare `n.to_int()`) so the
  // key flows into the non-index path and ascends to Object.prototype.
  let src =
    #|var a = [10, 20, 30];
    #|Object.prototype["3000000000"] = "from-proto";
    #|var v = a["3000000000"];
    #|delete Object.prototype["3000000000"];
    #|console.log(v);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["from-proto"])
}

///|
test "review P1-A: sort over hole-bearing array (stale-holes guard)" {
  // Regression test for the Codex P1-A finding: sort() reorders
  // `data.elements` in place but doesn't touch `data.holes`, so a real
  // value reordered into a hole-marked slot would (without the
  // defensive read) leak through as Hole and walk the prototype.
  // Spec §23.1.3.30: defined values sorted first (1, 3 at indices 0,1)
  // followed by holes (index 2). (1 in a) must be true.
  let src =
    #|var a = [3, , 1];
    #|a.sort();
    #|console.log(a[0] + "," + a[1] + "," + a[2] + "," + (1 in a));
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["1,3,undefined,true"])
}

///|
test "issue 123: sort preserves explicit undefined moved into hole slot" {
  // ES2024 §23.1.3.30 writes sorted present items back first, then deletes
  // the remaining indices. For [undefined, , 3], index 1 must become an own
  // explicit undefined property, not remain a stale hole marker.
  let src =
    #|var a = [undefined, , 3];
    #|a.sort();
    #|var has1 = (1 in a);
    #|var has2 = (2 in a);
    #|Array.prototype[1] = "proto";
    #|var observed = a[1];
    #|delete Array.prototype[1];
    #|console.log(a[0] + "," + a[1] + "," + has1 + "," + has2 + "," + observed);
    #|var b = [undefined, , 3];
    #|Array.prototype.sort.call(b);
    #|console.log(b[0] + "," + b[1] + "," + (1 in b) + "," + (2 in b));
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=[
    "3,undefined,true,false,undefined", "3,undefined,true,false",
  ])
}

///|
test "issue 123: Array mutators maintain holes around explicit undefined" {
  let src =
    #|function probe(a, i) {
    #|  var has = (i in a);
    #|  Array.prototype[i] = "proto";
    #|  var observed = a[i];
    #|  delete Array.prototype[i];
    #|  return has + ":" + observed;
    #|}
    #|var r = [undefined, 0];
    #|delete r[1];
    #|r.reverse();
    #|console.log("reverse:" + probe(r, 1) + "," + (0 in r));
    #|var c = [undefined, 0, 3];
    #|delete c[1];
    #|c.copyWithin(1, 0, 1);
    #|console.log("copyWithin:" + probe(c, 1) + "," + (2 in c));
    #|var sh = [0, undefined, 3];
    #|delete sh[0];
    #|sh.shift();
    #|console.log("shift:" + probe(sh, 0) + "," + (1 in sh));
    #|var un = [undefined, , 3];
    #|un.unshift(9);
    #|console.log("unshift:" + probe(un, 1) + "," + (2 in un));
    #|var sp = [undefined, , 3];
    #|sp.splice(0, 0, 9);
    #|console.log("splice:" + probe(sp, 1) + "," + (2 in sp));
    #|var f = [0, 0, 3];
    #|delete f[0];
    #|delete f[1];
    #|f.fill(undefined, 0, 2);
    #|console.log("fill:" + probe(f, 0) + "," + probe(f, 1));
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=[
    "reverse:true:undefined,false", "copyWithin:true:undefined,true", "shift:true:undefined,true",
    "unshift:true:undefined,false", "splice:true:undefined,false", "fill:true:undefined,true:undefined",
  ])
}

///|
test "issue 123: indexed mutators use Proxy-aware HasProperty" {
  let src =
    #|var log = [];
    #|var target = { 0: "a", 1: "b", length: 2 };
    #|var proxy = new Proxy(target, {
    #|  has: function(t, k) { log.push("has:" + k); return k in t; },
    #|  get: function(t, k) { log.push("get:" + k); return t[k]; },
    #|  set: function(t, k, v) { log.push("set:" + k + "=" + v); t[k] = v; return true; },
    #|  deleteProperty: function(t, k) { log.push("delete:" + k); delete t[k]; return true; }
    #|});
    #|var first = Array.prototype.shift.call(proxy);
    #|console.log(first + "," + target[0] + "," + target.length + "," + ("1" in target));
    #|console.log((log.indexOf("has:1") >= 0) + "," + (log.indexOf("delete:0") >= 0));
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["a,b,1,false", "true,false"])
}

///|
test "review P2: Object-branch HasProperty walks past Array prototype holes" {
  // A non-array object whose prototype is an Array — the Array node's
  // hole at the queried index must NOT terminate the walk; the parent
  // Object.prototype property should be found. Codex+CodeRabbit PR-#122
  // review regression test.
  let src =
    #|var ap = [10, 20, 30];
    #|delete ap[1];
    #|Object.prototype["1"] = "inherited";
    #|var child = Object.create(ap);
    #|var seen = (1 in child);
    #|delete Object.prototype["1"];
    #|console.log(seen);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["true"])
}

///|
test "review P1-B: custom prototype shadows built-in Array method for arr[s]" {
  // Object.setPrototypeOf(arr, { map: 42 }); arr["map"] must resolve to 42
  // (custom prototype) rather than the built-in Array.prototype.map. Codex
  // PR-#122 review regression test — guards against the method shortcut
  // being consulted before an explicit prototype override.
  let src =
    #|var arr = [1, 2, 3];
    #|Object.setPrototypeOf(arr, { map: 42 });
    #|console.log(arr["map"] + "," + (arr.map === 42));
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["42,true"])
}

///|
test "phase2 P1: prototype-chain walk continues through Array nodes" {
  // Object.setPrototypeOf with an Array as prototype: a hole at the
  // child's index should fall through to the prototype's prototype
  // (in this case Object.prototype) — Codex v3 P1 regression test.
  let src =
    #|var ap = [];
    #|Object.prototype["7"] = "from-object";
    #|var child = Object.create(ap);
    #|child.length = 8;
    #|var seen = child[7];
    #|delete Object.prototype["7"];
    #|console.log(seen);
  let (output, _) = @js_engine.run(src)
  json_inspect(output, content=["from-object"])
}
