///|
fn keyed_collection_guardrail_policy_973(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid keyed-collection guard policy")
  }
}

///|
test "default Map constructor rejects unobserved iterable progress" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var source = new Array(2000); " +
    "for (var i = 0; i < source.length; i += 1) source[i] = [0, 0]; " +
    "function constructLarge() { return new Map(source).size; }",
  )
  match
    engine.call_json_bounded(
      "constructLarge",
      [],
      keyed_collection_guardrail_policy_973(1000L),
    ) {
    Ok(_) => fail("expected Map constructor to fail closed before iteration")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
}

///|
fn expect_keyed_collection_guard_973(
  engine : @js_engine.Engine,
  function_name : String,
) -> Unit raise Error {
  match
    engine.call_json_bounded(
      function_name,
      [],
      keyed_collection_guardrail_policy_973(1000L),
    ) {
    Ok(_) => fail("expected keyed collection native work to fail closed")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
}

///|
test "default keyed collection guards cover frozen consumers" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var pairSource = new Array(2000);
      #|var valueSource = new Array(2000);
      #|for (var i = 0; i < 2000; i += 1) {
      #|  pairSource[i] = [0, 0];
      #|  valueSource[i] = 0;
      #|}
      #|var groupSource = valueSource;
      #|var largeSet = new Set(valueSource);
      #|var hasCalls = 0;
      #|var keysCalls = 0;
      #|var nextCalls = 0;
      #|var closeCalls = 0;
      #|function makeKeysIterator() {
      #|  return {
      #|    next: function() {
      #|      nextCalls += 1;
      #|      return { done: true, value: 0 };
      #|    },
      #|    return: function() {
      #|      closeCalls += 1;
      #|      return {};
      #|    }
      #|  };
      #|}
      #|function keys() { keysCalls += 1; return makeKeysIterator(); }
      #|function has(value) { hasCalls += 1; return false; }
      #|var largeOther = { size: 3000, has: has, keys: keys };
      #|var emptyOther = { size: 0, has: has, keys: keys };
      #|function mapConstructLarge() { return new Map(pairSource).size; }
      #|function setConstructLarge() { return new Set(valueSource).size; }
      #|function mapGroupLarge() {
      #|  return Map.groupBy(groupSource, function(value) { return value; }).size;
      #|}
      #|function unionLarge() { return largeSet.union(largeOther).size; }
      #|function intersectionHasLarge() { return largeSet.intersection(largeOther).size; }
      #|function intersectionKeysLarge() { return largeSet.intersection(emptyOther).size; }
      #|function differenceHasLarge() { return largeSet.difference(largeOther).size; }
      #|function differenceKeysLarge() { return largeSet.difference(emptyOther).size; }
      #|function symmetricLarge() { return largeSet.symmetricDifference(largeOther).size; }
      #|function subsetLarge() { return largeSet.isSubsetOf(largeOther); }
      #|function supersetLarge() { return largeSet.isSupersetOf(emptyOther); }
      #|function disjointHasLarge() { return largeSet.isDisjointFrom(largeOther); }
      #|function disjointKeysLarge() { return largeSet.isDisjointFrom(emptyOther); }
      #|function readCounts() { return [hasCalls, keysCalls, nextCalls, closeCalls]; }
    ),
  )
  for
    function_name in [
      "mapConstructLarge",
      "setConstructLarge",
      "mapGroupLarge",
      "unionLarge",
      "intersectionHasLarge",
      "intersectionKeysLarge",
      "differenceHasLarge",
      "differenceKeysLarge",
      "symmetricLarge",
      "subsetLarge",
      "supersetLarge",
      "disjointHasLarge",
      "disjointKeysLarge",
    ] {
    expect_keyed_collection_guard_973(engine, function_name)
  }
  json_inspect(engine.call_json("readCounts", []), content=[0, 5, 0, 5])
}

///|
test "default keyed collection guards preserve prelude and reuse" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var iteratorNext = 0;
      #|var iteratorReturn = 0;
      #|var iterable = {};
      #|Object.defineProperty(iterable, Symbol.iterator, {
      #|  get: function() {
      #|    return function() {
      #|      return {
      #|        next: function() {
      #|          iteratorNext += 1;
      #|          return { done: true, value: 0 };
      #|        },
      #|        return: function() {
      #|          iteratorReturn += 1;
      #|          return {};
      #|        }
      #|      };
      #|    };
      #|  }
      #|});
      #|function mapConstructIterator() { return new Map(iterable).size; }
      #|function setConstructIterator() { return new Set(iterable).size; }
      #|function mapGroupIterator() {
      #|  return Map.groupBy(iterable, function(value) { return value; }).size;
      #|}
      #|function invalidGroupCallback() {
      #|  try { Map.groupBy(iterable, {}); return "no-error"; }
      #|  catch (error) { return error.name; }
      #|}
      #|function invalidSetRecord() {
      #|  try { new Set([1]).union({ size: -1, has: function() {}, keys: function() {} }); }
      #|  catch (error) { return error.name; }
      #|  return "no-error";
      #|}
      #|function readIteratorCounts() { return [iteratorNext, iteratorReturn]; }
    ),
  )
  for function_name in [
    "mapConstructIterator", "setConstructIterator", "mapGroupIterator",
  ] {
    expect_keyed_collection_guard_973(engine, function_name)
  }
  json_inspect(engine.call_json("readIteratorCounts", []), content=[0, 3])
  json_inspect(engine.call_json("invalidGroupCallback", []), content="TypeError")
  json_inspect(engine.call_json("invalidSetRecord", []), content="RangeError")
  engine.eval(
    "function smallKeyedReuse() { " +
    "var a = new Set([1, 2]); " +
    "return [a.union(new Set([2, 3])).size, " +
    "new Map([[1, 2]]).size, Map.groupBy([1, 2], function(v) { return v; }).size]; " +
    "}",
  )
  json_inspect(engine.call_json("smallKeyedReuse", []), content=[3, 1, 2])
}

///|
test "default keyed collection consumers preserve unbounded results" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function keyedResults() { " +
    "var a = new Set([1, 2, 3]); " +
    "return [" +
    "new Map([[1, 2], [3, 4]]).size, " +
    "new Set([1, 2, 2]).size, " +
    "Map.groupBy([1, 2, 3], function(v) { return v % 2; }).size, " +
    "a.union(new Set([3, 4])).size, " +
    "a.intersection(new Set([2, 3])).size, " +
    "a.difference(new Set([3])).size, " +
    "a.symmetricDifference(new Set([3, 4])).size, " +
    "a.isSubsetOf(new Set([1, 2, 3, 4])), " +
    "a.isSupersetOf(new Set([1, 2])), " +
    "a.isDisjointFrom(new Set([4]))]; " +
    "}",
  )
  json_inspect(
    engine.call_json("keyedResults", []),
    content=[2, 2, 2, 4, 2, 2, 3, true, true, true],
  )
}

///|
test "default keyed collection prelude and empty decisions precede guards" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var badIterable = {};
      #|badIterable[Symbol.iterator] = 1;
      #|var badKeys = { size: 1, has: function() {}, keys: 1 };
      #|var largeOther = { size: 3000, has: function() { return false; },
      #|  keys: function() { return { next: function() { return { done: true }; } }; } };
      #|function invalidMapIterable() {
      #|  try { new Map(badIterable); return "no-error"; }
      #|  catch (error) { return error.name; }
      #|}
      #|function invalidSetReceiver() {
      #|  try { Set.prototype.union.call({}, largeOther); return "no-error"; }
      #|  catch (error) { return error.name; }
      #|}
      #|function invalidKeysProtocol() {
      #|  try { new Set([1]).union(badKeys); return "no-error"; }
      #|  catch (error) { return error.name; }
      #|}
      #|function emptyDecisions() {
      #|  var empty = new Set();
      #|  return [
      #|    empty.intersection(largeOther).size,
      #|    empty.difference(largeOther).size,
      #|    empty.isSubsetOf(largeOther),
      #|    empty.isDisjointFrom(largeOther)
      #|  ];
      #|}
    ),
  )
  json_inspect(engine.call_json("invalidMapIterable", []), content="TypeError")
  json_inspect(engine.call_json("invalidSetReceiver", []), content="TypeError")
  json_inspect(engine.call_json("invalidKeysProtocol", []), content="TypeError")
  json_inspect(engine.call_json("emptyDecisions", []), content=[0, 0, true, true])
}
