///|
fn typedarray_guardrail_policy_971(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid TypedArray guard policy")
  }
}

///|
fn expect_default_typedarray_guard_971(
  engine : @js_engine.Engine,
  function_name : String,
) -> Unit raise Error {
  match
    engine.call_json_bounded(
      function_name,
      [],
      typedarray_guardrail_policy_971(1000L),
    ) {
    Ok(_) => fail("expected default TypedArray native work to fail closed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "default TypedArray complex guards reject before native work" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var large = new Uint8Array(100000);
      #|var largeArray = Array(100000);
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
      #|function sortLarge() { large.sort(); return large.length; }
      #|function toSortLarge() { return large.toSorted().length; }
      #|function fromEmptyIterator() { return Uint8Array.from(source).length; }
      #|function constructFromArray() { return new Uint8Array(largeArray).length; }
      #|function constructFromObject() { return new Uint8Array(source).length; }
      #|function iteratorCounts() { return [nextCalls, closeCalls]; }
    ),
  )
  for
    function_name in [
      "sortLarge",
      "toSortLarge",
      "fromEmptyIterator",
      "constructFromArray",
      "constructFromObject",
    ] {
    expect_default_typedarray_guard_971(engine, function_name)
  }
  json_inspect(engine.call_json("iteratorCounts", []), content=[0, 2])
}

///|
test "default TypedArray guards preserve unbounded same-Engine reuse" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var large = new Uint8Array(100000); " +
    "function sortLarge() { large.sort(); return large.length; }",
  )
  expect_default_typedarray_guard_971(engine, "sortLarge")
  engine.eval(
    "function smallTypedArray() { " +
    "  var x = new Uint8Array([3, 1, 2]); x.sort(); " +
    "  return Array.from(x).join(','); " +
    "}",
  )
  json_inspect(engine.call_json("smallTypedArray", []), content="1,2,3")
}

///|
test "default TypedArray sort validates comparefn before the guard" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function invalidCompare() { " +
    "  var x = new Uint8Array(100000); " +
    "  try { x.sort({}); return 'no-error'; } " +
    "  catch (error) { return error.name; } " +
    "}",
  )
  match
    engine.call_json_bounded(
      "invalidCompare",
      [],
      typedarray_guardrail_policy_971(1000L),
    ) {
    Ok(value) => json_inspect(value, content="TypeError")
    Err(_) => fail("comparefn TypeError must precede the bounded guard")
  }
}

///|
test "default TypedArray empty sort paths do not guard" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function emptySorts() { " +
    "  return [new Uint8Array(0).sort().length, " +
    "new Uint8Array(0).toSorted().length]; " +
    "}",
  )
  match
    engine.call_json_bounded(
      "emptySorts",
      [],
      typedarray_guardrail_policy_971(1000L),
    ) {
    Ok(value) => json_inspect(value, content=[0, 0])
    Err(_) => fail("empty TypedArray sort paths must not hit the guard")
  }
}

///|
test "default TypedArray iterator construction observes newTarget prototype before guard" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var events = [];
      #|var iterator = {
      #|  next: function() { events.push("next"); return { done: true }; },
      #|  return: function() { events.push("return"); return {}; }
      #|};
      #|var source = {};
      #|Object.defineProperty(source, Symbol.iterator, {
      #|  get: function() {
      #|    events.push("iterator-get");
      #|    return function() {
      #|      events.push("iterator-call");
      #|      return iterator;
      #|    };
      #|  }
      #|});
      #|var newTarget = new Proxy(function() {}, {
      #|  get: function(target, key, receiver) {
      #|    if (key === "prototype") {
      #|      events.push("prototype");
      #|      return Uint8Array.prototype;
      #|    }
      #|    return Reflect.get(target, key, receiver);
      #|  }
      #|});
      #|function constructWithPrototype() {
      #|  return Reflect.construct(Uint8Array, [source], newTarget);
      #|}
      #|function readEvents() { return events; }
    ),
  )
  match
    engine.call_json_bounded(
      "constructWithPrototype",
      [],
      typedarray_guardrail_policy_971(1000L),
    ) {
    Ok(_) => fail("iterator construction must fail closed before next")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(
    engine.call_json("readEvents", []),
    content=["prototype", "iterator-get", "iterator-call", "return"],
  )
}

///|
test "default TypedArray complex consumers preserve unbounded results" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|function results() {
      #|  var from = Uint8Array.from([3, 1, 2]);
      #|  var constructed = new Uint8Array([4, 5, 6]);
      #|  var sorted = new Uint8Array([3, 1, 2]);
      #|  sorted.sort();
      #|  return [
      #|    Array.from(from).join(","),
      #|    Array.from(constructed).join(","),
      #|    Array.from(sorted).join(",")
      #|  ];
      #|}
    ),
  )
  json_inspect(
    engine.call_json("results", []),
    content=["3,1,2", "4,5,6", "1,2,3"],
  )
}
