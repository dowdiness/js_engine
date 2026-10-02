///|
// Issue #1072: binding initialization must share the canonical object-rest copy.

///|
fn issue1072_object_rest_result_for_wb(source : String) -> String raise Error {
  let stmts = @parser.parse(source).stmts
  let tree = @interpreter.new_interpreter().run(stmts)
  let candidate = run_candidate_program(@interpreter.new_interpreter(), stmts)
  assert_eq(candidate.to_string(), tree.to_string(), msg="candidate: " + source)
  candidate.to_string()
}

///|
test "issue 1072 binding object rest observes Proxy own keys and getters" {
  let source =
    #|var events = [];
    #|var target = { keep: 1, extra: 2 };
    #|var source = new Proxy(target, {
    #|  ownKeys: function(t) { events.push("keys"); return ["keep", "extra"]; },
    #|  getOwnPropertyDescriptor: function(t, key) {
    #|    events.push("desc:" + key);
    #|    return Object.getOwnPropertyDescriptor(t, key);
    #|  },
    #|  get: function(t, key) { events.push("get:" + key); return t[key]; }
    #|});
    #|var { keep, ...rest } = source;
    #|keep + ":" + rest.extra + ":" + events.join("|");
  assert_eq(
    issue1072_object_rest_result_for_wb(source),
    "1:2:get:keep|keys|desc:extra|get:extra",
  )
}

///|
test "issue 1072 binding forms share object rest copying" {
  let prefix =
    #|var source = { keep: 1, extra: 2 };
  for
    (form, expected) in [
      ("var { keep, ...rest } = source; rest.extra;", "2"),
      (
        "var result; try { throw source; } catch ({ keep, ...rest }) { result = rest.extra; } result;",
        "2",
      ),
      (
        "function read({ keep, ...rest }) { return rest.extra; } read(source);",
        "2",
      ),
    ] {
    assert_eq(
      issue1072_object_rest_result_for_wb(prefix + form),
      expected,
      msg=form,
    )
  }
}

///|
test "issue 1072 object rest observes enumerable keys and later changes" {
  let source =
    #|var events = [];
    #|var source = { keep: 1, first: 0, later: 3 };
    #|Object.defineProperty(source, "2", { enumerable: true, configurable: true,
    #|  get: function() { events.push("two"); return 20; } });
    #|Object.defineProperty(source, "1", { enumerable: true, configurable: true,
    #|  get: function() { events.push("one"); return 10; } });
    #|var inherited = { inherited: 8 };
    #|Object.setPrototypeOf(source, inherited);
    #|Object.defineProperty(source, "hidden", { value: 9, enumerable: false });
    #|Object.defineProperty(source, "first", { enumerable: true, configurable: true,
    #|  get: function() { events.push("first"); delete source.later; return 2; } });
    #|var symbol = Symbol("s");
    #|Object.defineProperty(source, symbol, { enumerable: true, get: function() {
    #|  events.push("symbol"); return 4;
    #|} });
    #|var excludedSymbol = Symbol("excluded");
    #|Object.defineProperty(source, excludedSymbol, { enumerable: true, get: function() {
    #|  events.push("excluded"); return 5;
    #|} });
    #|var { keep, [excludedSymbol]: ignored, ...rest } = source;
    #|JSON.stringify([rest["1"], rest["2"], rest.first, "later" in rest,
    #|  "inherited" in rest, "hidden" in rest, rest[symbol], rest[excludedSymbol], events]);
  assert_eq(
    issue1072_object_rest_result_for_wb(source),
    "[10,20,2,false,false,false,4,null,[\"excluded\",\"one\",\"two\",\"first\",\"symbol\"]]",
  )
}

///|
test "issue 1072 object rest handles arrays and primitive strings" {
  let array_source =
    #|var source = [];
    #|source[1] = 2;
    #|source.extra = 3;
    #|var { 1: item, ...rest } = source;
    #|JSON.stringify([item, rest.extra, "0" in rest, "1" in rest, "extra" in rest]);
  assert_eq(
    issue1072_object_rest_result_for_wb(array_source),
    "[2,3,false,false,true]",
  )
  let string_source =
    #|var { 0: first, ...rest } = "ab";
    #|first + ":" + rest[1] + ":" + ("length" in rest);
  assert_eq(issue1072_object_rest_result_for_wb(string_source), "a:b:false")
}

///|
test "issue 1072 object rest preserves abrupt completion and assignment effects" {
  let throwing_source =
    #|var trace = [];
    #|var phase = "keys";
    #|var sentinel = {};
    #|var source = new Proxy({ keep: 1, extra: 2 }, {
    #|  ownKeys: function(t) {
    #|    trace.push("keys");
    #|    if (phase === "keys") throw sentinel;
    #|    return ["keep", "extra"];
    #|  },
    #|  getOwnPropertyDescriptor: function(t, key) {
    #|    trace.push("desc:" + key);
    #|    if (phase === "descriptor") throw sentinel;
    #|    return Object.getOwnPropertyDescriptor(t, key);
    #|  },
    #|  get: function(t, key) {
    #|    trace.push("get:" + key);
    #|    if (phase === "get" && key === "extra") throw sentinel;
    #|    return t[key];
    #|  }
    #|});
    #|function run(currentPhase) {
    #|  phase = currentPhase; trace = [];
    #|  var restMarker = {};
    #|  var rest = restMarker;
    #|  var body = false, retained = false, caught = false, same = false;
    #|  try {
    #|    var { keep, ...rest } = source;
    #|    body = true;
    #|  } catch (error) {
    #|    caught = true; same = error === sentinel; retained = rest === restMarker;
    #|  }
    #|  finally { trace.push("finally"); }
    #|  return JSON.stringify([body, retained, caught, same, trace]);
    #|}
    #|[run("keys"), run("descriptor"), run("get")].join("|");
  assert_eq(
    issue1072_object_rest_result_for_wb(throwing_source),
    "[false,true,true,true,[\"get:keep\",\"keys\",\"finally\"]]|[false,true,true,true,[\"get:keep\",\"keys\",\"desc:extra\",\"finally\"]]|[false,true,true,true,[\"get:keep\",\"keys\",\"desc:extra\",\"get:extra\",\"finally\"]]",
  )

  let assignment_source =
    #|var events = [];
    #|var source = new Proxy({ keep: 1, extra: 2 }, {
    #|  ownKeys: function(t) { events.push("keys"); return ["keep", "extra"]; },
    #|  getOwnPropertyDescriptor: function(t, key) {
    #|    events.push("desc:" + key); return Object.getOwnPropertyDescriptor(t, key);
    #|  },
    #|  get: function(t, key) { events.push("get:" + key); return t[key]; }
    #|});
    #|var keep, rest;
    #|({ keep, ...rest } = source);
    #|keep + ":" + rest.extra + ":" + events.join("|");
  assert_eq(
    issue1072_object_rest_result_for_wb(assignment_source),
    "1:2:get:keep|keys|desc:extra|get:extra",
  )
}
