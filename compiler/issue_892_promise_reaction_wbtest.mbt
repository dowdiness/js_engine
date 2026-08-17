///|
// Issue #892 RED: a settled Promise must enqueue its selected reaction as a
// private executor callable while retaining the guest argument in the generic
// microtask carrier.  The current implementation uses an interpreter-native
// callback, so this intentionally fails until the managed reaction seam lands.
test "issue 892 candidate queues a typed Promise reaction executor" {
  let interp = @interpreter.new_interpreter()
  let source =
    #|var seen = 0;
    #|Promise.resolve(1).then(function(value) { seen = value; });
  let (_, evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(source).stmts,
  )
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(interp.host.microtask_queue.length(), 1)
  let task = interp.host.microtask_queue[0]
  match task.callback {
    @runtime.Object({ callable: Some(@runtime.ExecutorCallable(_)), .. }) => ()
    _ => fail("Promise reaction queue entry must be an executor callable")
  }
  assert_eq(task.args.length(), 1)
  assert_eq(task.args[0].to_string(), "1")
}

///|
fn issue892_candidate_run_and_drain_for_wb(
  source : String,
) -> (@runtime.Interpreter, Ref[CandidateRouteEvidence]) raise Error {
  let interp = @interpreter.new_interpreter()
  let (_, evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(source).stmts,
  )
  interp.run_microtasks()
  (interp, evidence)
}

///|
fn issue892_candidate_run_without_drain_for_wb(
  source : String,
) -> (@runtime.Interpreter, Ref[CandidateRouteEvidence]) raise Error {
  let interp = @interpreter.new_interpreter()
  let (_, evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(source).stmts,
  )
  (interp, evidence)
}

///|
fn issue892_global_string_for_wb(
  interp : @runtime.Interpreter,
  name : String,
) -> String raise Error {
  match interp.global.get(name) {
    @runtime.String_(value) => value
    value => fail("expected global string, got " + value.to_string())
  }
}

///|
test "issue 892 candidate thenable jobs run after the current script" {
  let source =
    #|var log = "";
    #|var thenable = { then: function(resolve) { log = log + "t"; resolve(); } };
    #|Promise.resolve(thenable);
    #|log = log + "s";
  let (interp, evidence) = issue892_candidate_run_without_drain_for_wb(source)
  assert_eq(issue892_global_string_for_wb(interp, "log"), "s")
  assert_eq(interp.host.microtask_queue.length(), 1)
  let task = interp.host.microtask_queue[0]
  match task.callback {
    @runtime.Object({ callable: Some(@runtime.ExecutorCallable(_)), .. }) => ()
    _ => fail("thenable job must be a private executor callable")
  }
  assert_eq(task.args.length(), 0)
  interp.run_microtasks()
  assert_eq(issue892_global_string_for_wb(interp, "log"), "st")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate thenable job preserves sibling FIFO" {
  let source =
    #|var log = "";
    #|var thenable = { then: function(resolve) { log = log + "t"; resolve(); } };
    #|Promise.resolve(thenable).then(function() { log = log + "r"; });
    #|Promise.resolve().then(function() { log = log + "s"; });
  let (interp, evidence) = issue892_candidate_run_without_drain_for_wb(source)
  assert_eq(issue892_global_string_for_wb(interp, "log"), "")
  assert_eq(interp.host.microtask_queue.length(), 2)
  interp.run_microtasks()
  assert_eq(issue892_global_string_for_wb(interp, "log"), "tsr")
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate thenable job creates resolving functions in the then realm" {
  let source =
    #|var r = $262.createRealm();
    #|var foreignFunctionProto = r.evalScript("Function.prototype");
    #|var localFunctionProto = Function.prototype;
    #|var thenable = r.evalScript("({ calls: 0, then: function(resolve, reject) { this.calls += 1; this.resolve = resolve; this.reject = reject; resolve('ok'); resolve('late'); reject('bad'); } })");
    #|var settled = "";
    #|Promise.resolve(thenable).then(function(value) { settled = "fulfilled:" + value; }, function(reason) { settled = "rejected:" + reason; });
    #|var snapshot = "";
    #|queueMicrotask(function() { queueMicrotask(function() { snapshot = thenable.calls + ":" + (Object.getPrototypeOf(thenable.resolve) === foreignFunctionProto) + ":" + (Object.getPrototypeOf(thenable.resolve) === localFunctionProto) + ":" + (Object.getPrototypeOf(thenable.reject) === foreignFunctionProto) + ":" + (Object.getPrototypeOf(thenable.reject) === localFunctionProto) + ":" + settled; }); });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(
    issue892_global_string_for_wb(interp, "snapshot"),
    "1:true:false:true:false:fulfilled:ok",
  )
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate thenable job follows proxy and revoked realm rules" {
  let source =
    #|var r = $262.createRealm();
    #|var foreignFunctionProto = r.evalScript("Function.prototype");
    #|var localFunctionProto = Function.prototype;
    #|var foreignThen = r.evalScript("(function(resolve) { this.resolve = resolve; resolve('proxy'); })");
    #|var proxiedThenable = { then: new Proxy(foreignThen, {}) };
    #|var proxied = "";
    #|Promise.resolve(proxiedThenable).then(function(value) { proxied = (Object.getPrototypeOf(proxiedThenable.resolve) === foreignFunctionProto) + ":" + (Object.getPrototypeOf(proxiedThenable.resolve) === localFunctionProto) + ":" + value; });
    #|var revocable = Proxy.revocable(foreignThen, {});
    #|var revokedThenable = { then: revocable.proxy };
    #|revocable.revoke();
    #|var revoked = "";
    #|Promise.resolve(revokedThenable).catch(function(error) { revoked = error instanceof TypeError ? "type-error" : "wrong"; });
    #|var snapshot = "";
    #|queueMicrotask(function() { queueMicrotask(function() { snapshot = proxied + ":" + revoked; }); });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(
    issue892_global_string_for_wb(interp, "snapshot"),
    "true:false:proxy:type-error",
  )
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate reaction frame preserves FIFO and deep chaining" {
  let source =
    #|var events = "";
    #|Promise.resolve(1).then(function(value) { events = events + "a" + value; });
    #|Promise.resolve(2).then(function(value) { events = events + "b" + value; });
    #|Promise.resolve(3)
    #|  .then(function(value) { return value + 1; })
    #|  .then(function(value) { return value + 1; })
    #|  .then(function(value) { events = events + "c" + value; });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(issue892_global_string_for_wb(interp, "events"), "a1b2c5")
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate managed resolution is first-call-wins" {
  let source =
    #|var resolve;
    #|var reject;
    #|var result = "";
    #|var p = new Promise(function(r, j) { resolve = r; reject = j; });
    #|resolve(1);
    #|reject(2);
    #|resolve(3);
    #|p.then(function(value) { result = "fulfilled:" + value; }, function(error) { result = "rejected:" + error; });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(issue892_global_string_for_wb(interp, "result"), "fulfilled:1")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate managed resolution assimilates thenable failures" {
  let source =
    #|var getterResult = "";
    #|var callResult = "";
    #|Promise.resolve({ get then() { throw "getter"; } }).catch(function(error) { getterResult = error; });
    #|Promise.resolve({ then: function() { throw "call"; } }).catch(function(error) { callResult = error; });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(issue892_global_string_for_wb(interp, "getterResult"), "getter")
  assert_eq(issue892_global_string_for_wb(interp, "callResult"), "call")
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate managed resolution settles thenables once" {
  let source =
    #|var twice = "";
    #|var resolveReject = "";
    #|var resolveThrow = "";
    #|var getterCount = 0;
    #|var callCount = 0;
    #|Promise.resolve({ then: function(resolve, reject) { resolve(1); resolve(2); reject(3); } }).then(function(value) { twice = "value:" + value; }, function(error) { twice = "error:" + error; });
    #|Promise.resolve({ then: function(resolve, reject) { resolve(4); reject(5); } }).then(function(value) { resolveReject = "value:" + value; }, function(error) { resolveReject = "error:" + error; });
    #|Promise.resolve({ then: function(resolve) { resolve(6); throw "ignored"; } }).then(function(value) { resolveThrow = "value:" + value; }, function(error) { resolveThrow = "error:" + error; });
    #|var thenable = { get then() { getterCount += 1; return function(resolve) { callCount += 1; resolve(7); }; } };
    #|Promise.resolve(thenable);
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(issue892_global_string_for_wb(interp, "twice"), "value:1")
  assert_eq(issue892_global_string_for_wb(interp, "resolveReject"), "value:4")
  assert_eq(issue892_global_string_for_wb(interp, "resolveThrow"), "value:6")
  match interp.global.get("getterCount") {
    @runtime.Number(value) => assert_eq(value, 1.0)
    value => fail("expected one then getter, got " + value.to_string())
  }
  match interp.global.get("callCount") {
    @runtime.Number(value) => assert_eq(value, 1.0)
    value => fail("expected one then call, got " + value.to_string())
  }
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate managed resolution handles self and callable Proxy" {
  let source =
    #|var resolve;
    #|var selfResult = "";
    #|var proxyResult = "";
    #|var p = new Promise(function(r) { resolve = r; });
    #|resolve(p);
    #|p.catch(function(error) { selfResult = error instanceof TypeError ? "self" : "wrong"; });
    #|var thenable = new Proxy(function(r) { r(9); }, {});
    #|Promise.resolve({ then: thenable }).then(function(value) { proxyResult = String(value); });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(issue892_global_string_for_wb(interp, "selfResult"), "self")
  assert_eq(issue892_global_string_for_wb(interp, "proxyResult"), "9")
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate reaction frame covers missing handlers and throws" {
  let source =
    #|var fulfilled = "";
    #|var rejected = "";
    #|var thrown = "";
    #|Promise.resolve(4).then().then(function(value) { fulfilled = String(value); });
    #|Promise.reject("bad").then(undefined, function(error) { rejected = error; });
    #|Promise.resolve(5).then(function() { throw "handler"; }).catch(function(error) { thrown = error; });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(issue892_global_string_for_wb(interp, "fulfilled"), "4")
  assert_eq(issue892_global_string_for_wb(interp, "rejected"), "bad")
  assert_eq(issue892_global_string_for_wb(interp, "thrown"), "handler")
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate custom species capabilities receive normal and abrupt jobs" {
  let source =
    #|var calls = "";
    #|function Species(executor) {
    #|  executor(
    #|    function(value) { calls = calls + "resolve:" + value + ";"; },
    #|    function(reason) { calls = calls + "reject:" + reason + ";"; }
    #|  );
    #|  return {};
    #|}
    #|var holder = {};
    #|holder[Symbol.species] = Species;
    #|var normal = Promise.resolve(1);
    #|normal.constructor = holder;
    #|normal.then(function(value) { return value + 1; });
    #|var abrupt = Promise.resolve(2);
    #|abrupt.constructor = holder;
    #|abrupt.then(function() { throw "handler"; });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(
    issue892_global_string_for_wb(interp, "calls"),
    "resolve:2;reject:handler;",
  )
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate custom resolve failure consumes only the selected job" {
  let source =
    #|var events = [];
    #|function Species(executor) {
    #|  executor(
    #|    function(value) { events.push("resolve"); throw "resolve-failure"; },
    #|    function(reason) { events.push("reject"); }
    #|  );
    #|  return {};
    #|}
    #|var holder = {};
    #|holder[Symbol.species] = Species;
    #|var p = Promise.resolve(1);
    #|p.constructor = holder;
    #|p.then(function(value) { events.push("handler"); return value; });
    #|queueMicrotask(function() { events.push("suffix"); });
  let (interp, evidence) = issue892_candidate_run_without_drain_for_wb(source)
  let failure = try {
    interp.run_microtasks()
    "no failure"
  } catch {
    @runtime.JsException(_) => "guest"
    error => "runtime:" + error.to_string()
  }
  assert_eq(failure, "guest")
  match interp.global.get("events") {
    @runtime.Array(events) =>
      assert_eq(events.elements.map(value => value.to_string()), [
        "handler", "resolve",
      ])
    value => fail("expected event array, got " + value.to_string())
  }
  assert_eq(interp.host.microtask_queue.length(), 1)
  interp.run_microtasks()
  match interp.global.get("events") {
    @runtime.Array(events) =>
      assert_eq(events.elements.map(value => value.to_string()), [
        "handler", "resolve", "suffix",
      ])
    value => fail("expected retained suffix array, got " + value.to_string())
  }
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate custom reject failure remains a guest throw" {
  let source =
    #|var events = [];
    #|function Species(executor) {
    #|  executor(
    #|    function(value) { events.push("resolve"); },
    #|    function(reason) { events.push("reject"); throw "reject-failure"; }
    #|  );
    #|  return {};
    #|}
    #|var holder = {};
    #|holder[Symbol.species] = Species;
    #|var p = Promise.resolve(1);
    #|p.constructor = holder;
    #|p.then(function(value) { events.push("handler"); throw "handler-failure"; });
    #|queueMicrotask(function() { events.push("suffix"); });
  let (interp, evidence) = issue892_candidate_run_without_drain_for_wb(source)
  let failure = try {
    interp.run_microtasks()
    "no failure"
  } catch {
    @runtime.JsException(_) => "guest"
    error => "runtime:" + error.to_string()
  }
  assert_eq(failure, "guest")
  match interp.global.get("events") {
    @runtime.Array(events) =>
      assert_eq(events.elements.map(value => value.to_string()), [
        "handler", "reject",
      ])
    value => fail("expected custom reject effects, got " + value.to_string())
  }
  assert_eq(interp.host.microtask_queue.length(), 1)
  interp.run_microtasks()
  match interp.global.get("events") {
    @runtime.Array(events) =>
      assert_eq(events.elements.map(value => value.to_string()), [
        "handler", "reject", "suffix",
      ])
    value => fail("expected retained suffix, got " + value.to_string())
  }
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate handler throw retains mutation and dependent enqueue" {
  let source =
    #|var events = [];
    #|Promise.resolve().then(function() { events.push("before"); throw "boom"; }).catch(function(error) { events.push("caught:" + error); });
    #|Promise.resolve().then(function() { events.push("sibling"); });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  match interp.global.get("events") {
    @runtime.Array(events) =>
      assert_eq(events.elements.map(value => value.to_string()), [
        "before", "sibling", "caught:boom",
      ])
    value => fail("expected retained handler effects, got " + value.to_string())
  }
  assert_eq(interp.host.microtask_queue.length(), 0)
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}
