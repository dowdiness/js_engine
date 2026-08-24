///|
fn promise_guardrail_policy_977(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid Promise combinator execution policy")
  }
}

///|
test "default Promise.all fails closed before first iterator step" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue977LargeIterable = new Array(100000); " +
    "var issue977NextCalls = 0; " +
    "var issue977CloseCalls = 0; " +
    "var issue977Iterator = { " +
    "next() { issue977NextCalls += 1; return { done: true }; }, " +
    "return() { issue977CloseCalls += 1; return {}; } }; " +
    "var issue977Iterable = { " +
    "[Symbol.iterator]() { return issue977Iterator; } }; " +
    "function issue977PromiseAllLarge() { return Promise.all(issue977Iterable); } " +
    "function issue977Counts() { return [issue977NextCalls, issue977CloseCalls]; }",
  )
  match
    engine.call_json_bounded(
      "issue977PromiseAllLarge",
      [],
      promise_guardrail_policy_977(1000L),
    ) {
    Ok(_) => fail("Promise.all silently bypassed bounded execution control")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("issue977Counts", []), content=[0, 1])
}

///|
test "default Promise combinators fail closed before native iteration" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue977LargeArray = new Array(100000); " +
    "function issue977AllLarge() { return Promise.all(issue977LargeArray); } " +
    "function issue977RaceLarge() { return Promise.race(issue977LargeArray); } " +
    "function issue977AllSettledLarge() { " +
    "return Promise.allSettled(issue977LargeArray); } " +
    "function issue977AnyLarge() { return Promise.any(issue977LargeArray); }",
  )
  for function_name in [
    "issue977AllLarge",
    "issue977RaceLarge",
    "issue977AllSettledLarge",
    "issue977AnyLarge",
  ] {
    match
      engine.call_json_bounded(
        function_name,
        [],
        promise_guardrail_policy_977(1000L),
      ) {
      Ok(_) => fail("Promise combinator silently bypassed bounded execution")
      Err(diagnostic) => {
        inspect(diagnostic.failure_kind_code(), content="execution-limit")
        assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
      }
    }
  }
}

///|
test "default Promise combinators do not close iterator-step abrupt completion" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue977OrdinaryNextCalls = 0; " +
    "var issue977OrdinaryCloseCalls = 0; " +
    "var issue977OrdinaryEvents = []; " +
    "var issue977OrdinaryIterator = { " +
    "next() { issue977OrdinaryNextCalls += 1; throw new Error('next'); }, " +
    "return() { issue977OrdinaryCloseCalls += 1; return {}; } }; " +
    "var issue977OrdinaryIterable = { " +
    "[Symbol.iterator]() { return issue977OrdinaryIterator; } }; " +
    "function issue977OrdinaryAbrupt() { " +
    "Promise.all(issue977OrdinaryIterable).then(" +
    "() => issue977OrdinaryEvents.push('fulfilled'), " +
    "() => issue977OrdinaryEvents.push('rejected')); return 1; } " +
    "function issue977OrdinaryCounts() { " +
    "return [issue977OrdinaryNextCalls, issue977OrdinaryCloseCalls]; } " +
    "function issue977OrdinarySnapshot() { return issue977OrdinaryEvents; }",
  )
  json_inspect(engine.call_json("issue977OrdinaryAbrupt", []), content=1)
  json_inspect(engine.call_json("issue977OrdinaryCounts", []), content=[1, 0])
  inspect(engine.run_microtask_checkpoint(), content="false")
  json_inspect(
    engine.call_json("issue977OrdinarySnapshot", []),
    content=["rejected"],
  )
}

///|
test "default Promise combinators close each acquired iterator once" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue977GuardNextCalls = 0; " +
    "var issue977GuardCloseCalls = 0; " +
    "var issue977GuardIterable = { " +
    "[Symbol.iterator]() { return { " +
    "next() { issue977GuardNextCalls += 1; return { done: true }; }, " +
    "return() { issue977GuardCloseCalls += 1; return {}; } }; } }; " +
    "function issue977GuardAll() { return Promise.all(issue977GuardIterable); } " +
    "function issue977GuardRace() { return Promise.race(issue977GuardIterable); } " +
    "function issue977GuardAllSettled() { " +
    "return Promise.allSettled(issue977GuardIterable); } " +
    "function issue977GuardAny() { return Promise.any(issue977GuardIterable); } " +
    "function issue977GuardCounts() { " +
    "return [issue977GuardNextCalls, issue977GuardCloseCalls]; }",
  )
  for function_name in [
    "issue977GuardAll",
    "issue977GuardRace",
    "issue977GuardAllSettled",
    "issue977GuardAny",
  ] {
    match
      engine.call_json_bounded(
        function_name,
        [],
        promise_guardrail_policy_977(1000L),
      ) {
      Ok(_) => fail("Promise guard must reject before the first next call")
      Err(diagnostic) =>
        inspect(diagnostic.failure_kind_code(), content="execution-limit")
    }
  }
  json_inspect(engine.call_json("issue977GuardCounts", []), content=[0, 4])
}

///|
test "default Promise combinators reject iterator abrupt completion without close" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue977AbruptNextCalls = 0; " +
    "var issue977AbruptCloseCalls = 0; " +
    "var issue977AbruptEvents = []; " +
    "var issue977AbruptIterable = { [Symbol.iterator]() { return { " +
    "next() { issue977AbruptNextCalls += 1; throw new Error('next'); }, " +
    "return() { issue977AbruptCloseCalls += 1; return {}; } }; } }; " +
    "function issue977AbruptAll() { Promise.all(issue977AbruptIterable).then(" +
    "() => issue977AbruptEvents.push('all-ok'), " +
    "() => issue977AbruptEvents.push('all-rejected')); return 1; } " +
    "function issue977AbruptRace() { Promise.race(issue977AbruptIterable).then(" +
    "() => issue977AbruptEvents.push('race-ok'), " +
    "() => issue977AbruptEvents.push('race-rejected')); return 1; } " +
    "function issue977AbruptAllSettled() { " +
    "Promise.allSettled(issue977AbruptIterable).then(" +
    "() => issue977AbruptEvents.push('settled-ok'), " +
    "() => issue977AbruptEvents.push('settled-rejected')); return 1; } " +
    "function issue977AbruptAny() { Promise.any(issue977AbruptIterable).then(" +
    "() => issue977AbruptEvents.push('any-ok'), " +
    "() => issue977AbruptEvents.push('any-rejected')); return 1; } " +
    "function issue977AbruptCounts() { " +
    "return [issue977AbruptNextCalls, issue977AbruptCloseCalls]; } " +
    "function issue977AbruptSnapshot() { return issue977AbruptEvents; }",
  )
  for function_name in [
    "issue977AbruptAll",
    "issue977AbruptRace",
    "issue977AbruptAllSettled",
    "issue977AbruptAny",
  ] {
    json_inspect(engine.call_json(function_name, []), content=1)
  }
  json_inspect(
    engine.call_json("issue977AbruptCounts", []),
    content=[4, 0],
  )
  inspect(engine.run_microtask_checkpoint(), content="false")
  json_inspect(
    engine.call_json("issue977AbruptSnapshot", []),
    content=["all-rejected", "race-rejected", "settled-rejected", "any-rejected"],
  )
}

///|
test "default Promise.all runs capability and iterator prelude before guard" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue977PreludeEvents = ''; " +
    "function issue977PreludeConstructor(executor) { " +
    "issue977PreludeEvents += 'c'; return new Promise(executor); } " +
    "Object.defineProperty(issue977PreludeConstructor, 'resolve', { " +
    "configurable: true, get() { issue977PreludeEvents += 'r'; " +
    "return function() {}; } }); " +
    "issue977PreludeConstructor.all = Promise.all; " +
    "var issue977PreludeIterator = {}; " +
    "Object.defineProperty(issue977PreludeIterator, 'next', { " +
    "configurable: true, get() { issue977PreludeEvents += 'n'; " +
    "return function() { issue977PreludeEvents += 'N'; " +
    "return { done: true }; }; } }); " +
    "Object.defineProperty(issue977PreludeIterator, 'return', { " +
    "configurable: true, get() { issue977PreludeEvents += 'g'; " +
    "return function() { issue977PreludeEvents += 'R'; return {}; }; } }); " +
    "var issue977PreludeIterable = {}; " +
    "Object.defineProperty(issue977PreludeIterable, Symbol.iterator, { " +
    "configurable: true, get() { issue977PreludeEvents += 'i'; " +
    "return function() { issue977PreludeEvents += 'I'; " +
    "return issue977PreludeIterator; }; } }); " +
    "function issue977PreludeAll() { return issue977PreludeConstructor.all(" +
    "issue977PreludeIterable); } " +
    "function issue977PreludeSnapshot() { return issue977PreludeEvents; }",
  )
  match
    engine.call_json_bounded(
      "issue977PreludeAll",
      [],
      promise_guardrail_policy_977(1000L),
    ) {
    Ok(_) => fail("Promise guard must run after the iterator prelude")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(
    engine.call_json("issue977PreludeSnapshot", []),
    content="criIngR",
  )
}

///|
test "default Promise combinators preserve pre-iterator errors without close" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue977PreIteratorEvents = []; " +
    "var issue977ResolveIteratorGets = 0; " +
    "var issue977NextIteratorGets = 0; " +
    "var issue977ResolveSource = {}; " +
    "Object.defineProperty(issue977ResolveSource, Symbol.iterator, { " +
    "get() { issue977ResolveIteratorGets += 1; return function() { " +
    "return { next() { return { done: true }; } }; }; } }); " +
    "function issue977BadResolveConstructor(executor) { " +
    "return new Promise(executor); } " +
    "issue977BadResolveConstructor.resolve = 1; " +
    "issue977BadResolveConstructor.all = Promise.all; " +
    "function issue977BadResolve() { " +
    "issue977BadResolveConstructor.all(issue977ResolveSource).catch(e => " +
    "issue977PreIteratorEvents.push(e instanceof TypeError ? 'resolve-type' : 'other')); " +
    "return 1; } " +
    "var issue977BadNextSource = { [Symbol.iterator]() { " +
    "return { next: 1, get return() { issue977NextIteratorGets += 1; " +
    "return function() { return {}; }; } }; } }; " +
    "function issue977BadNext() { Promise.all(issue977BadNextSource).catch(e => " +
    "issue977PreIteratorEvents.push(e instanceof TypeError ? 'next-type' : 'other')); " +
    "return 1; } " +
    "function issue977PreIteratorSnapshot() { return issue977PreIteratorEvents; } " +
    "function issue977PreIteratorCounts() { " +
    "return [issue977ResolveIteratorGets, issue977NextIteratorGets]; }",
  )
  json_inspect(engine.call_json("issue977BadResolve", []), content=1)
  json_inspect(engine.call_json("issue977BadNext", []), content=1)
  inspect(engine.run_microtask_checkpoint(), content="false")
  json_inspect(
    engine.call_json("issue977PreIteratorSnapshot", []),
    content=["resolve-type", "next-type"],
  )
  json_inspect(
    engine.call_json("issue977PreIteratorCounts", []),
    content=[0, 0],
  )
}

///|
test "default Promise guard preserves control failure when IteratorClose throws" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue977CloseThrowEvents = ''; " +
    "var issue977CloseThrowSource = { [Symbol.iterator]() { return { " +
    "next() { issue977CloseThrowEvents += 'N'; return { done: true }; }, " +
    "get return() { issue977CloseThrowEvents += 'g'; return function() { " +
    "issue977CloseThrowEvents += 'R'; throw new Error('close'); }; } }; } }; " +
    "function issue977CloseThrow() { return Promise.all(issue977CloseThrowSource); } " +
    "function issue977CloseThrowSnapshot() { return issue977CloseThrowEvents; }",
  )
  match
    engine.call_json_bounded(
      "issue977CloseThrow",
      [],
      promise_guardrail_policy_977(1000L),
    ) {
    Ok(_) => fail("IteratorClose failure must not replace execution control")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(
    engine.call_json("issue977CloseThrowSnapshot", []),
    content="gR",
  )
}

///|
test "default Promise combinators close on PromiseResolve and then abrupt completion" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue977ResolveThenEvents = []; " +
    "var issue977ResolveThenNextCalls = 0; " +
    "var issue977ResolveThenCloseCalls = 0; " +
    "function issue977ResolveThenConstructor(executor) { " +
    "return new Promise(executor); } " +
    "issue977ResolveThenConstructor.all = Promise.all; " +
    "issue977ResolveThenConstructor.race = Promise.race; " +
    "issue977ResolveThenConstructor.resolve = function(value) { " +
    "issue977ResolveThenEvents.push('resolve'); throw new Error('resolve'); }; " +
    "var issue977ResolveThenIterable = { [Symbol.iterator]() { return { " +
    "next() { issue977ResolveThenNextCalls += 1; " +
    "return { done: false, value: 1 }; }, " +
    "return() { issue977ResolveThenCloseCalls += 1; return {}; } }; } }; " +
    "function issue977ResolveAbrupt() { " +
    "issue977ResolveThenConstructor.all(issue977ResolveThenIterable).then(" +
    "undefined, () => issue977ResolveThenEvents.push('all-rejected')); return 1; } " +
    "function issue977ResolveThenSnapshot() { " +
    "return [issue977ResolveThenNextCalls, issue977ResolveThenCloseCalls, " +
    "issue977ResolveThenEvents]; }",
  )
  json_inspect(engine.call_json("issue977ResolveAbrupt", []), content=1)
  json_inspect(
    engine.call_json("issue977ResolveThenSnapshot", []),
    content=[1, 1, ["resolve"]],
  )
  inspect(engine.run_microtask_checkpoint(), content="false")
  json_inspect(
    engine.call_json("issue977ResolveThenSnapshot", []),
    content=[1, 1, ["resolve", "all-rejected"]],
  )

  engine.eval(
    "issue977ResolveThenConstructor.resolve = function(value) { " +
    "return { then() { issue977ResolveThenEvents.push('then'); " +
    "throw new Error('then'); } }; }; " +
    "function issue977ThenAbrupt() { " +
    "issue977ResolveThenConstructor.race(issue977ResolveThenIterable).then(" +
    "undefined, () => issue977ResolveThenEvents.push('race-rejected')); return 1; }",
  )
  json_inspect(engine.call_json("issue977ThenAbrupt", []), content=1)
  json_inspect(
    engine.call_json("issue977ResolveThenSnapshot", []),
    content=[2, 2, ["resolve", "all-rejected", "then"]],
  )
  inspect(engine.run_microtask_checkpoint(), content="false")
  json_inspect(
    engine.call_json("issue977ResolveThenSnapshot", []),
    content=[2, 2, ["resolve", "all-rejected", "then", "race-rejected"]],
  )
}

///|
test "default Promise combinators preserve unbounded settlement behavior" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue977NormalEvents = []; " +
    "function issue977NormalAll() { Promise.all([1, 2]).then(v => " +
    "issue977NormalEvents.push('all:' + v.length)); return 1; } " +
    "function issue977NormalRace() { Promise.race([1]).then(v => " +
    "issue977NormalEvents.push('race:' + v)); return 1; } " +
    "function issue977NormalAllSettled() { Promise.allSettled([1]).then(v => " +
    "issue977NormalEvents.push('settled:' + v.length)); return 1; } " +
    "function issue977NormalAny() { Promise.any([1]).then(v => " +
    "issue977NormalEvents.push('any:' + v)); return 1; } " +
    "function issue977NormalSnapshot() { return issue977NormalEvents; }",
  )
  for function_name in [
    "issue977NormalAll",
    "issue977NormalRace",
    "issue977NormalAllSettled",
    "issue977NormalAny",
  ] {
    json_inspect(engine.call_json(function_name, []), content=1)
  }
  inspect(engine.run_microtask_checkpoint(), content="false")
  json_inspect(
    engine.call_json("issue977NormalSnapshot", []),
    content=["all:2", "race:1", "settled:1", "any:1"],
  )
}
