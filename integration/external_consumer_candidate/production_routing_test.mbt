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
test "candidate external Engine iterable spread remains reusable" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function arraySpread() { return [0, ...[1, 2], 3].join(','); } " +
    "function callSpread(left, right) { " +
    "return (function(a, b, c, d) { return [a, b, c, d].join(','); })(" +
    "0, ...left, 2, ...right); }",
  )
  json_inspect(engine.call_json("arraySpread", []), content="0,1,2,3")
  json_inspect(
    engine.call_json("callSpread", [
      Json::array([Json::number(1.0)]),
      Json::array([Json::number(3.0)]),
    ]),
    content="0,1,2,3",
  )
  json_inspect(engine.call_json("arraySpread", []), content="0,1,2,3")
}

///|
test "candidate Engine iterable spread preserves deep guest re-entry and queue" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var events = [];
      #|function makeIterable(level) {
      #|  return { [Symbol.iterator]: function() {
      #|    var index = 0;
      #|    return { next: function() {
      #|      var current = index;
      #|      events.push("next:" + level + ":" + current);
      #|      if (current === 1) return { done: true };
      #|      index = index + 1;
      #|      if (level === 3) queueMicrotask(function() { events.push("micro:3:0"); });
      #|      var nested = level === 0 ? [] : [...makeIterable(level - 1)];
      #|      return { done: false, value: level + ":" + nested.length };
      #|    } };
      #|  } };
      #|}
      #|function deepSpread() { return [...makeIterable(3)].join(","); }
      #|function eventsSnapshot() { return events; }
    ),
  )
  json_inspect(engine.call_json("deepSpread", []), content="3:1")
  json_inspect(engine.call_json("eventsSnapshot", []), content=[
    "next:3:0", "next:2:0", "next:1:0", "next:0:0", "next:0:1", "next:1:1", "next:2:1",
    "next:3:1",
  ])
  expect_bool(engine.has_pending_microtasks(), true, "candidate spread queue")
  expect_bool(
    engine.run_microtask_checkpoint(),
    false,
    "candidate spread queue checkpoint",
  )
  json_inspect(engine.call_json("eventsSnapshot", []), content=[
    "next:3:0", "next:2:0", "next:1:0", "next:0:0", "next:0:1", "next:1:1", "next:2:1",
    "next:3:1", "micro:3:0",
  ])
}

///|
test "candidate Engine iterable spread observes inherited iterator overrides" {
  let engine = @js_engine.Engine()
  let source =
    #|function prototypeIteratorMatrix() {
    #|  var result = {};
    #|  String.prototype[Symbol.iterator] = undefined;
    #|  try { [..."ab"]; result.stringUndefined = "completed"; }
    #|  catch (error) { result.stringUndefined = error instanceof TypeError ? "TypeError" : "other"; }
    #|  var stringCalls = 0;
    #|  var stringReceiver = false;
    #|  String.prototype[Symbol.iterator] = function() {
    #|    "use strict";
    #|    stringCalls = stringCalls + 1;
    #|    stringReceiver = typeof this === "string" && this === "ab";
    #|    return { next: function() { return { done: true }; } };
    #|  };
    #|  result.stringCustom = [..."ab"].length;
    #|  result.stringCalls = stringCalls;
    #|  result.stringReceiver = stringReceiver;
    #|  Array.prototype[Symbol.iterator] = undefined;
    #|  try { [...[1, 2]]; result.arrayUndefined = "completed"; }
    #|  catch (error) { result.arrayUndefined = error instanceof TypeError ? "TypeError" : "other"; }
    #|  var arrayCalls = 0;
    #|  var arrayReceiver = false;
    #|  Array.prototype[Symbol.iterator] = function() {
    #|    "use strict";
    #|    arrayCalls = arrayCalls + 1;
    #|    arrayReceiver = Array.isArray(this) && this.length === 2;
    #|    return { next: function() { return { done: true }; } };
    #|  };
    #|  result.arrayCustom = [...[1, 2]].length;
    #|  result.arrayCalls = arrayCalls;
    #|  result.arrayReceiver = arrayReceiver;
    #|  return result;
    #|}
  engine.eval(source)
  json_inspect(engine.call_json("prototypeIteratorMatrix", []), content={
    "stringUndefined": "TypeError",
    "stringCustom": 0,
    "stringCalls": 1,
    "stringReceiver": true,
    "arrayUndefined": "TypeError",
    "arrayCustom": 0,
    "arrayCalls": 1,
    "arrayReceiver": true,
  })
}

///|
test "candidate Engine iterable spread does not probe replaced array prototypes" {
  let engine = @js_engine.Engine()
  let source =
    #|function replacedArrayPrototypeMatrix() {
    #|  var result = {};
    #|  var array = [1, 2];
    #|  Object.setPrototypeOf(array, {});
    #|  try { [...array]; result.replaced = "completed"; }
    #|  catch (error) { result.replaced = error instanceof TypeError ? "TypeError" : "other"; }
    #|  var getCalls = 0;
    #|  var hasCalls = 0;
    #|  var receiverIsArray = false;
    #|  var proxyPrototype = new Proxy({}, {
    #|    get: function(target, key, receiver) {
    #|      if (key === Symbol.iterator) {
    #|        getCalls = getCalls + 1;
    #|        receiverIsArray = Array.isArray(receiver) && receiver === array;
    #|      }
    #|      return undefined;
    #|    },
    #|    has: function(target, key) {
    #|      hasCalls = hasCalls + 1;
    #|      return false;
    #|    }
    #|  });
    #|  Object.setPrototypeOf(array, proxyPrototype);
    #|  try { [...array]; result.proxy = "completed"; }
    #|  catch (error) { result.proxy = error instanceof TypeError ? "TypeError" : "other"; }
    #|  result.getCalls = getCalls;
    #|  result.hasCalls = hasCalls;
    #|  result.receiverIsArray = receiverIsArray;
    #|  return result;
    #|}
  engine.eval(source)
  json_inspect(engine.call_json("replacedArrayPrototypeMatrix", []), content={
    "replaced": "TypeError",
    "proxy": "TypeError",
    "getCalls": 1,
    "hasCalls": 0,
    "receiverIsArray": true,
  })
}

///|
test "candidate Engine iterable spread honors deep prototype accessors" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var result = {};
      #|var originalArrayProto = Object.getPrototypeOf(Array.prototype);
      #|var originalArrayIterator = Object.getOwnPropertyDescriptor(Array.prototype, Symbol.iterator);
      #|var higherCalls = 0;
      #|var higher = {};
      #|Object.defineProperty(higher, Symbol.iterator, { value: function() {
      #|  higherCalls = higherCalls + 1;
      #|  return { next: function() { return { done: true }; } };
      #|} });
      #|var deep = {};
      #|Object.setPrototypeOf(deep, higher);
      #|delete Array.prototype[Symbol.iterator];
      #|Object.defineProperty(deep, Symbol.iterator, { set: function(value) {} });
      #|Object.setPrototypeOf(Array.prototype, deep);
      #|try { [...[1, 2]]; result.arraySetter = "completed"; }
      #|catch (error) { result.arraySetter = error instanceof TypeError ? "TypeError" : "other"; }
      #|result.higherCalls = higherCalls;
      #|Object.setPrototypeOf(Array.prototype, originalArrayProto);
      #|Object.defineProperty(Array.prototype, Symbol.iterator, originalArrayIterator);
      #|var getterCalls = 0;
      #|var iteratorCalls = 0;
      #|var receiverIsArray = false;
      #|var array = [1, 2];
      #|var getterDeep = {};
      #|Object.defineProperty(getterDeep, Symbol.iterator, { get: function() {
      #|  getterCalls = getterCalls + 1;
      #|  receiverIsArray = this === array;
      #|  return function() {
      #|    iteratorCalls = iteratorCalls + 1;
      #|    return { next: function() { return { done: true }; } };
      #|  };
      #|} });
      #|delete Array.prototype[Symbol.iterator];
      #|Object.setPrototypeOf(Array.prototype, getterDeep);
      #|try { result.getterLength = [...array].length; }
      #|catch (error) { result.getterLength = -1; }
      #|result.getterCalls = getterCalls;
      #|result.iteratorCalls = iteratorCalls;
      #|result.receiverIsArray = receiverIsArray;
      #|Object.setPrototypeOf(Array.prototype, originalArrayProto);
      #|Object.defineProperty(Array.prototype, Symbol.iterator, originalArrayIterator);
      #|var originalPromiseProto = Object.getPrototypeOf(Promise.prototype);
      #|var promiseCalls = 0;
      #|var promiseHigher = {};
      #|Object.defineProperty(promiseHigher, Symbol.iterator, { value: function() {
      #|  promiseCalls = promiseCalls + 1;
      #|  return { next: function() { return { done: true }; } };
      #|} });
      #|Object.setPrototypeOf(Promise.prototype, promiseHigher);
      #|var promise = new Promise(function(resolve) { resolve(1); });
      #|Object.defineProperty(promise, Symbol.iterator, { set: function(value) {} });
      #|try { [...promise]; result.promiseSetter = "completed"; }
      #|catch (error) { result.promiseSetter = error instanceof TypeError ? "TypeError" : "other"; }
      #|result.promiseCalls = promiseCalls;
      #|Object.setPrototypeOf(Promise.prototype, originalPromiseProto);
    ),
  )
  engine.eval("function deepPrototypeAccessorMatrix() { return result; }")
  json_inspect(engine.call_json("deepPrototypeAccessorMatrix", []), content={
    "arraySetter": "TypeError",
    "higherCalls": 0,
    "getterLength": 0,
    "getterCalls": 1,
    "iteratorCalls": 1,
    "receiverIsArray": true,
    "promiseSetter": "TypeError",
    "promiseCalls": 0,
  })
}

///|
test "candidate minimal Map iterator prototype probe" {
  let engine = @js_engine.Engine()
  let source =
    #|var map = new Map();
    #|var proto = {};
    #|var calls = 0;
    #|var receiver = false;
    #|Object.defineProperty(proto, Symbol.iterator, { value: function() {
    #|  calls = calls + 1;
    #|  receiver = this === map;
    #|  return { next: function() { return { done: true }; } };
    #|} });
    #|Object.setPrototypeOf(map, proto);
    #|function probe() { return [...map].length + ":" + calls + ":" + receiver; }
  engine.eval(source)
  json_inspect(engine.call_json("probe", []), content="0:1:true")
}

///|
test "candidate minimal Set iterator prototype probe" {
  let engine = @js_engine.Engine()
  let source =
    #|var set = new Set();
    #|var proto = {};
    #|var calls = 0;
    #|var receiver = false;
    #|Object.defineProperty(proto, Symbol.iterator, { value: function() {
    #|  calls = calls + 1;
    #|  receiver = this === set;
    #|  return { next: function() { return { done: true }; } };
    #|} });
    #|Object.setPrototypeOf(set, proto);
    #|function probe() { return [...set].length + ":" + calls + ":" + receiver; }
  engine.eval(source)
  json_inspect(engine.call_json("probe", []), content="0:1:true")
}

///|
test "candidate minimal Map getter iterator prototype probe" {
  let engine = @js_engine.Engine()
  let source =
    #|var map = new Map();
    #|var proto = {};
    #|var gets = 0;
    #|Object.defineProperty(proto, Symbol.iterator, { get: function() {
    #|  gets = gets + 1;
    #|  throw new TypeError("getter");
    #|} });
    #|Object.setPrototypeOf(map, proto);
    #|function probe() { try { [...map]; return "completed"; } catch (error) { return error instanceof TypeError ? gets + ":TypeError" : "other"; } }
  engine.eval(source)
  json_inspect(engine.call_json("probe", []), content="1:TypeError")
}

///|
test "candidate inherited Map and Set undefined iterators remain errors" {
  let engine = @js_engine.Engine()
  let source =
    #|function probe() {
    #|  var result = {};
    #|  Map.prototype[Symbol.iterator] = undefined;
    #|  Set.prototype[Symbol.iterator] = undefined;
    #|  try { [...new Map()]; result.map = "completed"; }
    #|  catch (error) { result.map = error instanceof TypeError ? "TypeError" : "other"; }
    #|  try { [...new Set()]; result.set = "completed"; }
    #|  catch (error) { result.set = error instanceof TypeError ? "TypeError" : "other"; }
    #|  return result;
    #|}
  engine.eval(source)
  json_inspect(engine.call_json("probe", []), content={
    "map": "TypeError",
    "set": "TypeError",
  })
}

///|
test "candidate inherited Map iterator getter propagates once" {
  let engine = @js_engine.Engine()
  let source =
    #|var gets = 0;
    #|Object.defineProperty(Map.prototype, Symbol.iterator, { get: function() {
    #|  gets = gets + 1;
    #|  throw new TypeError("iterator getter");
    #|} });
    #|function probe() {
    #|  try { [...new Map()]; return "completed"; }
    #|  catch (error) { return error instanceof TypeError ? gets + ":TypeError" : "other"; }
    #|}
  engine.eval(source)
  json_inspect(engine.call_json("probe", []), content="1:TypeError")
}

///|
test "candidate inherited Set iterator getter propagates once" {
  let engine = @js_engine.Engine()
  let source =
    #|var gets = 0;
    #|Object.defineProperty(Set.prototype, Symbol.iterator, { get: function() {
    #|  gets = gets + 1;
    #|  throw new TypeError("iterator getter");
    #|} });
    #|function probe() {
    #|  try { [...new Set()]; return "completed"; }
    #|  catch (error) { return error instanceof TypeError ? gets + ":TypeError" : "other"; }
    #|}
  engine.eval(source)
  json_inspect(engine.call_json("probe", []), content="1:TypeError")
}

///|
test "candidate getterless Object iterator accessor shadows its prototype" {
  let engine = @js_engine.Engine()
  let source =
    #|var inherited = {};
    #|Object.defineProperty(inherited, Symbol.iterator, { value: function() {
    #|  return { next: function() { return { done: true }; } };
    #|} });
    #|var object = {};
    #|Object.setPrototypeOf(object, inherited);
    #|Object.defineProperty(object, Symbol.iterator, { set: function(value) {} });
    #|function probe() { try { [...object]; return "completed"; } catch (error) { return error instanceof TypeError ? "TypeError" : "other"; } }
  engine.eval(source)
  json_inspect(engine.call_json("probe", []), content="TypeError")
}

///|
test "candidate getterless Array iterator accessor shadows its intrinsic" {
  let engine = @js_engine.Engine()
  let source =
    #|var array = [1, 2];
    #|Object.defineProperty(array, Symbol.iterator, { get: undefined });
    #|function probe() { try { [...array]; return "completed"; } catch (error) { return error instanceof TypeError ? "TypeError" : "other"; } }
  engine.eval(source)
  json_inspect(engine.call_json("probe", []), content="TypeError")
}

///|
test "candidate getterless Map iterator accessor shadows its intrinsic" {
  let engine = @js_engine.Engine()
  let source =
    #|var map = new Map();
    #|Object.defineProperty(map, Symbol.iterator, { set: function(value) {} });
    #|function probe() { try { [...map]; return "completed"; } catch (error) { return error instanceof TypeError ? "TypeError" : "other"; } }
  engine.eval(source)
  json_inspect(engine.call_json("probe", []), content="TypeError")
}

///|
test "candidate getterless Set iterator accessor shadows its intrinsic" {
  let engine = @js_engine.Engine()
  let source =
    #|var set = new Set();
    #|Object.defineProperty(set, Symbol.iterator, { get: undefined });
    #|function probe() { try { [...set]; return "completed"; } catch (error) { return error instanceof TypeError ? "TypeError" : "other"; } }
  engine.eval(source)
  json_inspect(engine.call_json("probe", []), content="TypeError")
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
test "candidate Engine Array valueOf participates in addition" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var a = [1]; " +
    "a.valueOf = function() { return 2; }; " +
    "function arrayValueOfAdd() { return a + 1; }",
  )
  json_inspect(engine.call_json("arrayValueOfAdd", []), content=3)
}

///|
test "candidate Engine Array Symbol.toPrimitive keeps hint and receiver" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var a = [1]; " +
    "var seen = ''; " +
    "a[Symbol.toPrimitive] = function(hint) { " +
    "seen = hint + (this === a); return 40; }; " +
    "function arraySymbolAdd() { return [a + 1, seen]; }",
  )
  json_inspect(engine.call_json("arraySymbolAdd", []), content=[
    41, "defaulttrue",
  ])
}

///|
test "candidate Engine Array toString participates in addition" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var a = [1]; " +
    "a.toString = function() { return 'custom'; }; " +
    "function arrayToStringAdd() { return a + 1; }",
  )
  json_inspect(engine.call_json("arrayToStringAdd", []), content="custom1")
}

///|
test "candidate Engine Array coercion hook matrix preserves parity" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var events = ''; " +
    "var symbolArray = [1]; " +
    "symbolArray[Symbol.toPrimitive] = function(hint) { " +
    "events = events + 'symbol:' + hint + ':' + (this === symbolArray) + ';'; " +
    "return 4; }; " +
    "var valueOfArray = [1]; " +
    "valueOfArray.valueOf = function() { " +
    "events = events + 'valueOf:' + (this === valueOfArray) + ';'; " +
    "return 5; }; " +
    "var toStringArray = [1]; " +
    "toStringArray.toString = function() { " +
    "events = events + 'toString:' + (this === toStringArray) + ';'; " +
    "return 'string'; }; " +
    "var accessorArray = [1]; " +
    "Object.defineProperty(accessorArray, Symbol.toPrimitive, { get: function() { " +
    "events = events + 'getter;'; " +
    "return function(hint) { events = events + 'accessor:' + hint + ':' + (this === accessorArray) + ';'; return 6; }; " +
    "} }); " +
    "var throwArray = [1]; " +
    "throwArray.valueOf = function() { events = events + 'throw;'; throw 'guest'; }; " +
    "var objectResultArray = [1]; " +
    "objectResultArray.valueOf = function() { events = events + 'object;'; return {}; }; " +
    "objectResultArray.toString = function() { events = events + 'objectString;'; return {}; }; " +
    "function arrayCoercionMatrix() { " +
    "var thrown = 'none'; try { throwArray + 1; } catch (error) { thrown = error; } " +
    "var typeError = false; try { objectResultArray + 1; } catch (error) { typeError = error instanceof TypeError; } " +
    "return { results: [symbolArray + 1, valueOfArray + 1, toStringArray + 1, accessorArray + 1], thrown: thrown, typeError: typeError, events: events }; }",
  )
  json_inspect(engine.call_json("arrayCoercionMatrix", []), content={
    "results": [5, 6, "string1", 7],
    "thrown": "guest",
    "typeError": true,
    "events": "throw;object;objectString;symbol:default:true;valueOf:true;toString:true;getter;accessor:default:true;",
  })
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
