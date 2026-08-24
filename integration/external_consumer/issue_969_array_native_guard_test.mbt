///|
fn array_complex_guardrail_policy_969(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid Array complex execution policy")
  }
}

///|
test "default Array.sort rejects unobserved collection progress" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var sparse = Array(100000); " +
    "function sortLarge() { sparse.sort(); return 1; }",
  )
  match
    engine.call_json_bounded(
      "sortLarge",
      [],
      array_complex_guardrail_policy_969(1000L),
    ) {
    Ok(_) => fail("expected Array.sort to fail closed before collection")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
}

///|
test "default Array.toSorted rejects unobserved collection progress" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var sparse = Array(100000); " +
    "function toSortLarge() { return sparse.toSorted().length; }",
  )
  match
    engine.call_json_bounded(
      "toSortLarge",
      [],
      array_complex_guardrail_policy_969(1000L),
    ) {
    Ok(_) => fail("expected Array.toSorted to fail closed before collection")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
}

///|
test "default Array.flat rejects unobserved collection progress" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var sparse = Array(100000); " +
    "function flattenLarge() { return sparse.flat().length; }",
  )
  match
    engine.call_json_bounded(
      "flattenLarge",
      [],
      array_complex_guardrail_policy_969(1000L),
    ) {
    Ok(_) => fail("expected Array.flat to fail closed before collection")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
}

///|
test "default Array.flatMap rejects unobserved collection progress" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var sparse = Array(100000); " +
    "function flatMapLarge() { return sparse.flatMap(Array).length; }",
  )
  match
    engine.call_json_bounded(
      "flatMapLarge",
      [],
      array_complex_guardrail_policy_969(1000L),
    ) {
    Ok(_) => fail("expected Array.flatMap to fail closed before collection")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
}

///|
test "default Array.from rejects before the first iterator step" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var nextCalls = 0;
      #|var closeCalls = 0;
      #|var iterator = {
      #|  next: function() {
      #|    nextCalls += 1;
      #|    return { done: true, value: 0 };
      #|  },
      #|  return: function() {
      #|    closeCalls += 1;
      #|    return {};
      #|  }
      #|};
      #|var source = {};
      #|source[Symbol.iterator] = function() { return iterator; };
      #|function fromEmptyIterator() { return Array.from(source).length; }
      #|function iteratorCounts() { return [nextCalls, closeCalls]; }
    ),
  )
  match
    engine.call_json_bounded(
      "fromEmptyIterator",
      [],
      array_complex_guardrail_policy_969(1000L),
    ) {
    Ok(_) => fail("expected Array.from to fail closed before IteratorStep")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(engine.call_json("iteratorCounts", []), content=[0, 1])
}

///|
test "default Array.from keeps constructor and iterator acquisition effects" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var constructorCalls = 0;
      #|var nextCalls = 0;
      #|var closeCalls = 0;
      #|var iterator = {
      #|  next: function() {
      #|    nextCalls += 1;
      #|    return { done: true, value: 0 };
      #|  },
      #|  return: function() {
      #|    closeCalls += 1;
      #|    return {};
      #|  }
      #|};
      #|var source = {};
      #|source[Symbol.iterator] = function() { return iterator; };
      #|function Factory() { constructorCalls += 1; return []; }
      #|function fromWithConstructor() {
      #|  return Array.from.call(Factory, source).length;
      #|}
      #|function constructorCounts() {
      #|  return [constructorCalls, nextCalls, closeCalls];
      #|}
    ),
  )
  match
    engine.call_json_bounded(
      "fromWithConstructor",
      [],
      array_complex_guardrail_policy_969(1000L),
    ) {
    Ok(_) => fail("expected Array.from to fail closed before IteratorStep")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(engine.call_json("constructorCounts", []), content=[1, 0, 1])
}

///|
test "default Array ordering guards precede comparator calls" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var sparse = Array(100000);
      #|var comparatorCalls = 0;
      #|function compare(a, b) { comparatorCalls += 1; return a - b; }
      #|function sortWithCompare() { sparse.sort(compare); return 1; }
      #|function toSortWithCompare() { return sparse.toSorted(compare).length; }
      #|function readComparatorCalls() { return comparatorCalls; }
    ),
  )
  match
    engine.call_json_bounded(
      "sortWithCompare",
      [],
      array_complex_guardrail_policy_969(1000L),
    ) {
    Ok(_) => fail("expected sort to fail before comparator calls")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  match
    engine.call_json_bounded(
      "toSortWithCompare",
      [],
      array_complex_guardrail_policy_969(1000L),
    ) {
    Ok(_) => fail("expected toSorted to fail before comparator calls")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(engine.call_json("readComparatorCalls", []), content=0)
}

///|
test "default Array.flatMap guard precedes callback and source Get" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var sparse = Array(100000);
      #|var callbackCalls = 0;
      #|function mapper(value) { callbackCalls += 1; return [value]; }
      #|function flatMapWithMapper() { return sparse.flatMap(mapper).length; }
      #|function readCallbackCalls() { return callbackCalls; }
    ),
  )
  match
    engine.call_json_bounded(
      "flatMapWithMapper",
      [],
      array_complex_guardrail_policy_969(1000L),
    ) {
    Ok(_) => fail("expected flatMap to fail before callback calls")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(engine.call_json("readCallbackCalls", []), content=0)
}

///|
test "default Array complex consumers preserve unbounded results" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|function results() {
      #|  return [
      #|    [3, 1, 2].sort().join(","),
      #|    [3, 1, 2].toSorted().join(","),
      #|    [1, [2, 3]].flat().join(","),
      #|    [1, 2].flatMap(function(x) { return [x]; }).join(",")
      #|  ];
      #|}
    ),
  )
  json_inspect(
    engine.call_json("results", []),
    content=["1,2,3", "1,2,3", "1,2,3", "1,2"],
  )
}

///|
test "default Array complex consumers keep zero-length fast returns" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|function emptyResults() {
      #|  return [
      #|    [].sort().length,
      #|    [].toSorted().length,
      #|    [].flat().length,
      #|    [].flatMap(Array).length
      #|  ];
      #|}
    ),
  )
  let policy = array_complex_guardrail_policy_969(1000L)
  match engine.call_json_bounded("emptyResults", [], policy) {
    Ok(value) => json_inspect(value, content=[0, 0, 0, 0])
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "default Array complex guards preserve prelude error precedence" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var source = [1, 2];
      #|var depth = { valueOf: function() { throw "depth"; } };
      #|var iteratorLookups = 0;
      #|var iterable = {};
      #|Object.defineProperty(iterable, Symbol.iterator, {
      #|  get: function() { iteratorLookups += 1; return 1; }
      #|});
      #|function preludeErrors() {
      #|  var sortError = "";
      #|  var sortedError = "";
      #|  var flatError = "";
      #|  var flatMapError = "";
      #|  var fromError = "";
      #|  try { source.sort(1); } catch (e) { sortError = e.name; }
      #|  try { source.toSorted(1); } catch (e) { sortedError = e.name; }
      #|  try { source.flat(depth); } catch (e) { flatError = e; }
      #|  try { source.flatMap(1); } catch (e) { flatMapError = e.name; }
      #|  try { Array.from(iterable, 1); } catch (e) { fromError = e.name; }
      #|  return [sortError, sortedError, flatError, flatMapError, fromError,
      #|    iteratorLookups];
      #|}
    ),
  )
  match
    engine.call_json_bounded(
      "preludeErrors",
      [],
      array_complex_guardrail_policy_969(1000L),
    ) {
    Ok(value) => json_inspect(value, content=["TypeError", "TypeError", "depth", "TypeError", "TypeError", 0])
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "default Array.flat snapshots generic length once" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var lengthReads = 0;
      #|var arrayLike = { 0: [1, 2] };
      #|Object.defineProperty(arrayLike, "length", {
      #|  get: function() { lengthReads += 1; return 1; }
      #|});
      #|function flattenLike() {
      #|  return [Array.prototype.flat.call(arrayLike).join(","), lengthReads];
      #|}
    ),
  )
  json_inspect(
    engine.call_json("flattenLike", []),
    content=["1,2", 1],
  )
}

///|
test "default Array.flat retains species effects before the guard" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var speciesCalls = 0;
      #|var source = Array(100000);
      #|function Species() { speciesCalls += 1; return []; }
      #|var constructor = {};
      #|constructor[Symbol.species] = Species;
      #|source.constructor = constructor;
      #|function flattenWithSpecies() { return source.flat().length; }
      #|function readSpeciesCalls() { return speciesCalls; }
    ),
  )
  match
    engine.call_json_bounded(
      "flattenWithSpecies",
      [],
      array_complex_guardrail_policy_969(1000L),
    ) {
    Ok(_) => fail("expected Array.flat to fail closed after species")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(engine.call_json("readSpeciesCalls", []), content=1)
}
