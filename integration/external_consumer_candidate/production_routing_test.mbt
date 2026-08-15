///|
fn expect_bool(
  actual : Bool,
  expected : Bool,
  label : String,
) -> Unit raise Error {
  guard actual == expected else {
    fail(label + ": expected " + expected.to_string())
  }
}

///|
// Candidate-mode external consumers use the same stable facade as default
// consumers. The virtual package only changes build-time candidate routing.
test "candidate override fixture uses the stable Engine contract" {
  let engine = @js_engine.Engine()
  engine.eval("function answer() { return 42; }")
  json_inspect(engine.call_json("answer", []), content=42)
  json_inspect(engine.call_json("answer", []), content=42)
  engine.eval("console.log(\"candidate\");")
  json_inspect(engine.take_output(), content=["candidate"])
  expect_bool(engine.has_pending_microtasks(), false, "candidate microtasks")
  expect_bool(engine.has_pending_timers(), false, "candidate timers")
  expect_bool(engine.run_microtask_checkpoint(), false, "candidate checkpoint")
  engine.run_timer_checkpoint()
  engine.eval(
    "console.log(\"before\"); queueMicrotask(() => console.log(\"after\"));",
  )
  json_inspect(engine.take_output(), content=["before"])
  expect_bool(
    engine.has_pending_microtasks(),
    true,
    "candidate queued microtask",
  )
  expect_bool(
    engine.run_microtask_checkpoint(),
    false,
    "candidate drained checkpoint",
  )
  json_inspect(engine.take_output(), content=["after"])
  expect_bool(engine.has_pending_microtasks(), false, "candidate drained queue")
}

///|
test "candidate Engine routes plain addition coercion and remains reusable" {
  let engine = @js_engine.Engine()
  engine.eval("function add(left, right) { return left + right; }")
  json_inspect(engine.call_json("add", [2, 3]), content=5)
  engine.eval(
    "var events = ''; " +
    "var box = {}; " +
    "box[Symbol.toPrimitive] = function(hint) { " +
    "events = events + hint; console.log(hint); " +
    "queueMicrotask(() => console.log('micro')); return 4; }; " +
    "function addBox() { return box + 2; }",
  )
  json_inspect(engine.call_json("addBox", []), content=6)
  json_inspect(engine.take_output(), content=["default"])
  expect_bool(engine.has_pending_microtasks(), true, "addition queue")
  expect_bool(
    engine.run_microtask_checkpoint(),
    false,
    "addition queue checkpoint",
  )
  json_inspect(engine.take_output(), content=["micro"])
  engine.eval(
    "var bad = {}; " +
    "bad[Symbol.toPrimitive] = function() { throw new Error('addition'); }; " +
    "function failAdd() { return bad + 1; }",
  )
  let failed = try {
    ignore(engine.call_json("failAdd", []))
    false
  } catch {
    error => error.to_string().contains("addition")
  }
  expect_bool(failed, true, "candidate addition abrupt completion")
  engine.eval("function afterAdditionFailure() { return 9 + 1; }")
  json_inspect(engine.call_json("afterAdditionFailure", []), content=10)
}

///|
test "candidate mode routes each mixed child independently" {
  let engine = @js_engine.Engine()
  let source =
    #|function bytecodeParent() {
    #|  function treeChild() {
    #|    for (var value of [1]) {}
    #|    return 3;
    #|  }
    #|  return treeChild();
    #|}
    #|function treeParent() {
    #|  for (var value of [1]) {}
    #|  function bytecodeChild() { return 4; }
    #|  return bytecodeChild();
    #|}
  engine.eval(source)
  json_inspect(engine.call_json("bytecodeParent", []), content=3)
  json_inspect(engine.call_json("treeParent", []), content=4)
}

///|
test "candidate mode keeps same-name siblings tied to their source identities" {
  let engine = @js_engine.Engine()
  let source =
    #|function firstFactory() {
    #|  function same() { return 11; }
    #|  return same;
    #|}
    #|function secondFactory() {
    #|  function same() {
    #|    for (var value of [1]) {}
    #|    return 22;
    #|  }
    #|  return same;
    #|}
    #|var first = firstFactory();
    #|var second = secondFactory();
  engine.eval(source)
  json_inspect(engine.call_json("first", []), content=11)
  json_inspect(engine.call_json("second", []), content=22)
}

///|
test "candidate mode retains function values after later eval" {
  let engine = @js_engine.Engine()
  engine.eval("function oldFunction() { return 41; }")
  engine.eval("function anotherFunction() { return 42; }")
  json_inspect(engine.call_json("oldFunction", []), content=41)
  json_inspect(engine.call_json("oldFunction", []), content=41)
  json_inspect(engine.call_json("anotherFunction", []), content=42)
}

///|
test "candidate mode starts a fresh activation for repeated script calls" {
  let engine = @js_engine.Engine()
  let source =
    #|function repeatedAnswer() { return 42; }
    #|var repeatedResults = [repeatedAnswer(), repeatedAnswer()];
    #|function readRepeatedResults() { return repeatedResults; }
  engine.eval(source)
  json_inspect(engine.call_json("readRepeatedResults", []), content=[42, 42])
}

///|
test "candidate mode starts a fresh activation for recursive calls" {
  let engine = @js_engine.Engine()
  let source =
    #|function recursiveAnswer(reenter) {
    #|  if (reenter) return recursiveAnswer();
    #|  return 42;
    #|}
    #|var recursiveResult = recursiveAnswer(true);
    #|function readRecursiveResult() { return recursiveResult; }
  engine.eval(source)
  json_inspect(engine.call_json("readRecursiveResult", []), content=42)
}

///|
test "candidate mode materializes function expressions arrows and methods" {
  let engine = @js_engine.Engine()
  let source =
    #|function allForms(value) {
    #|  let object = {
    #|    method(x) { return x + 1; },
    #|    ["computed"](x) { return x + 2; },
    #|    arrow: x => x + 3,
    #|    named: function named(x) { return x + 4; },
    #|    anonymous: function(x) { return x + 5; },
    #|  };
    #|  return object.method(value) + object.computed(value) + object.arrow(value) + object.named(value) + object.anonymous(value);
    #|}
  engine.eval(source)
  json_inspect(engine.call_json("allForms", [1]), content=20)
}

///|
test "candidate mode keeps computed class methods independent" {
  let engine = @js_engine.Engine()
  let source =
    #|function classForms(value) {
    #|  class Example {
    #|    method(x) { return x + 1; }
    #|    ["computed"](x) { return x + 2; }
    #|  }
    #|  let object = new Example();
    #|  return object.method(value) + object.computed(value);
    #|}
  engine.eval(source)
  json_inspect(engine.call_json("classForms", [1]), content=5)
}

///|
test "candidate mode completes unsupported root before observable effects" {
  let engine = @js_engine.Engine()
  engine.eval("for (var value of [1]) {}; console.log(\"tree\");")
  json_inspect(engine.take_output(), content=["tree"])
}

///|
test "candidate mode guest throw leaves Engine reusable" {
  let engine = @js_engine.Engine()
  engine.eval("function failGuest() { throw \"boom\"; }")
  let failed = try {
    ignore(engine.call_json("failGuest", []))
    false
  } catch {
    error => error.to_string().contains("boom")
  }
  expect_bool(failed, true, "candidate guest throw")
  engine.eval("function recovered() { return 9; }")
  json_inspect(engine.call_json("recovered", []), content=9)
}

///|
test "candidate mode reuses an eligible function after abrupt completion" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function maybeFail(shouldFail) { " +
    "if (shouldFail) throw \"boom\"; return 7; }",
  )
  let failed = try {
    ignore(engine.call_json("maybeFail", [true]))
    false
  } catch {
    error => error.to_string().contains("boom")
  }
  expect_bool(failed, true, "candidate repeated guest throw")
  json_inspect(engine.call_json("maybeFail", [false]), content=7)
}
