///|
fn issue891_default_run_for_wb(source : String) -> @runtime.Value raise Error {
  let interp = @interpreter.new_interpreter()
  interp.run(@parser.parse(source).stmts)
}

///|
fn issue891_assert_evidence_for_wb(
  evidence : Ref[CandidateRouteEvidence],
) -> Unit raise Error {
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
// Issue #891: Array.prototype.forEach preserves an abrupt Proxy
// [[HasProperty]] completion while the candidate child is bytecode.
test "issue 891 candidate forEach preserves Proxy has abrupt completion" {
  let source =
    #|var events = [];
    #|var callbacks = 0;
    #|var target = [1, 2];
    #|var receiver = new Proxy(target, { get: function(t,k,r) { events.push("get:" + k); return Reflect.get(t,k,r); }, has: function(t,k) { events.push("has:" + k); throw new Error("has"); } });
    #|var each = Array.prototype.forEach;
    #|var run = function() { each.call(receiver, function() { callbacks = callbacks + 1; events.push("callback"); }); };
    #|var result = "none";
    #|try { run(); }
    #|catch (error) { result = error instanceof Error ? "Error:" + error.message : "other"; }
    #|(each === Array.prototype.forEach) + ":" + result + ":" + events.join(",") + ":" + callbacks;
  let default_value = issue891_default_run_for_wb(source)
  assert_eq(default_value.to_string(), "true:Error:has:get:length,has:0:0")
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true:Error:has:get:length,has:0:0")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 forEach non-callable callback does not coerce after length" {
  let source =
    #|var events = [];
    #|var target = { length: 1 };
    #|var receiver = new Proxy(target, { get: function(t,k,r) { events.push("get:" + k); return Reflect.get(t,k,r); }, has: function(t,k) { events.push("has:" + k); return Reflect.has(t,k); } });
    #|var callbackTarget = {
    #|  [Symbol.toPrimitive]: function() { events.push("primitive-call"); throw new Error("primitive"); },
    #|  toString: function() { events.push("toString-call"); throw new Error("toString"); },
    #|  valueOf: function() { events.push("valueOf-call"); throw new Error("valueOf"); }
    #|};
    #|var callback = new Proxy(callbackTarget, { get: function(t,k,r) { events.push(k === Symbol.toPrimitive ? "primitive-get" : k + "-get"); return Reflect.get(t,k,r); } });
    #|var run = function() { return Array.prototype.forEach.call(receiver, callback); };
    #|var result = "none";
    #|try { run(); }
    #|catch (error) { result = error instanceof TypeError ? "TypeError:" + error.message : "other"; }
    #|result + ":" + events.join(",");
  let default_value = issue891_default_run_for_wb(source)
  assert_eq(
    default_value.to_string(),
    "TypeError:callback is not a function:get:length",
  )
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(
    value.to_string(),
    "TypeError:callback is not a function:get:length",
  )
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 candidate forEach callback receives value index object and thisArg" {
  let source =
    #|var receiver = { 0: "a", 1: "b", length: 2 };
    #|var thisArg = { marker: "!" };
    #|var seen = [];
    #|var run = function() {
    #|  var ignored = Array.prototype.forEach.call(receiver, function(value, index, object) {
    #|    seen.push(value + index + (object === receiver) + this.marker);
    #|    return 99;
    #|  }, thisArg);
    #|  return seen.join(",") + ":" + (ignored === undefined);
    #|};
    #|run();
  let default_value = issue891_default_run_for_wb(source)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "a0true!,b1true!:true")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 candidate forEach snapshots length and observes holes inheritance and mutation" {
  let source =
    #|var proto = { 1: "inherited" };
    #|var receiver = Object.create(proto);
    #|receiver.length = 4;
    #|receiver[0] = "a";
    #|receiver[2] = "c";
    #|var seen = [];
    #|var run = function() {
    #|  Array.prototype.forEach.call(receiver, function(value, index) {
    #|    seen.push(value + ":" + index);
    #|    if (index === 0) { receiver[3] = "d"; receiver[2] = "updated"; delete receiver[2]; }
    #|  });
    #|  return seen.join(",");
    #|};
    #|run();
  let default_value = issue891_default_run_for_wb(source)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "a:0,inherited:1,d:3")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 candidate forEach observes shift without extending the snapshot" {
  let source =
    #|var receiver = [1, 2, 3];
    #|var seen = [];
    #|var run = function() {
    #|  Array.prototype.forEach.call(receiver, function(value, index) {
    #|    seen.push(value + ":" + index);
    #|    if (index === 0) receiver.shift();
    #|  });
    #|  return seen.join(",");
    #|};
    #|run();
  let default_value = issue891_default_run_for_wb(source)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "1:0,3:1")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 candidate forEach preserves Proxy length has get callback order" {
  let source =
    #|var events = [];
    #|var target = { 0: "v", length: 1 };
    #|var receiver = new Proxy(target, {
    #|  get: function(t, key, receiver) { events.push("get:" + key); return Reflect.get(t, key, receiver); },
    #|  has: function(t, key) { events.push("has:" + key); return Reflect.has(t, key); }
    #|});
    #|var run = function() {
    #|  Array.prototype.forEach.call(receiver, function(value, index, object) {
    #|    events.push("callback:" + value + ":" + index + ":" + (object === receiver));
    #|  });
    #|  return events.join(",");
    #|};
    #|run();
  let default_value = issue891_default_run_for_wb(source)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "get:length,has:0,get:0,callback:v:0:true")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 candidate forEach retains effects before abrupt Get" {
  let source =
    #|var events = [];
    #|var target = { length: 2 };
    #|Object.defineProperty(target, "0", { get: function() { events.push("get"); throw new Error("get"); } });
    #|var result = "none";
    #|var run = function() {
    #|  try { Array.prototype.forEach.call(target, function() { events.push("callback"); }); }
    #|  catch (error) { result = error instanceof Error ? error.message : "other"; }
    #|  return result + ":" + events.join(",");
    #|};
    #|run();
  let default_value = issue891_default_run_for_wb(source)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "get:get")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 candidate forEach propagates abrupt length snapshot" {
  let source =
    #|var events = [];
    #|var receiver = {};
    #|Object.defineProperty(receiver, "length", { get: function() { events.push("length"); throw new Error("length"); } });
    #|var result = "none";
    #|var run = function() {
    #|  try { Array.prototype.forEach.call(receiver, function() { events.push("callback"); }); }
    #|  catch (error) { result = error instanceof Error ? error.message : "other"; }
    #|  return result + ":" + events.join(",");
    #|};
    #|run();
  let default_value = issue891_default_run_for_wb(source)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "length:length")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 candidate forEach stops after callback abrupt completion" {
  let source =
    #|var events = [];
    #|var receiver = { 0: "a", 1: "b", length: 2 };
    #|var result = "none";
    #|var run = function() {
    #|  try { Array.prototype.forEach.call(receiver, function(value, index) { events.push(value + ":" + index); throw new Error("callback"); }); }
    #|  catch (error) { result = error instanceof Error ? error.message : "other"; }
    #|  return result + ":" + events.join(",");
    #|};
    #|run();
  let default_value = issue891_default_run_for_wb(source)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "callback:a:0")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 candidate forEach reuses one Engine after abrupt and normal calls" {
  let source =
    #|var mode = 0;
    #|var seen = [];
    #|var receiver = { 0: "a", 1: "b", length: 2 };
    #|var run = function() {
    #|  Array.prototype.forEach.call(receiver, function(value, index) {
    #|    seen.push(value + ":" + index);
    #|    if (mode === 0) throw new Error("boom");
    #|  });
    #|};
    #|var first = "none";
    #|try { run(); } catch (error) { first = error instanceof Error ? error.message : "other"; }
    #|mode = 1;
    #|run();
    #|first + ":" + seen.join(",");
  let default_value = issue891_default_run_for_wb(source)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "boom:a:0,a:0,b:1")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 candidate forEach callback queueMicrotask drains exactly once" {
  let source =
    #|var queued = 0;
    #|var receiver = { 0: 1, length: 1 };
    #|var run = function() {
    #|  Array.prototype.forEach.call(receiver, function() { queueMicrotask(function() { queued = queued + 1; }); });
    #|  return queued;
    #|};
    #|run();
  let interp = @interpreter.new_interpreter()
  let (value, evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(source).stmts,
  )
  assert_eq(value.to_string(), "0")
  assert_eq(interp.host.microtask_queue.length(), 1)
  interp.run_microtasks()
  assert_eq(interp.global.get("queued").to_string(), "1")
  assert_eq(interp.host.microtask_queue.length(), 0)
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 candidate forEach supports deep finite callback re-entry" {
  let source =
    #|var active = 0;
    #|var maximum = 0;
    #|var receiver = { 0: 1, length: 1 };
    #|var run = function(depth) {
    #|  if (depth === 0) return;
    #|  Array.prototype.forEach.call(receiver, function() {
    #|    active = active + 1;
    #|    if (active > maximum) maximum = active;
    #|    run(depth - 1);
    #|    active = active - 1;
    #|  });
    #|};
    #|run(64);
    #|maximum;
  let value = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  assert_eq(value.to_string(), "64")
}

///|
test "issue 891 candidate forEach sibling map keeps its existing result path" {
  let source =
    #|var run = function() { return [1, 2].map(function(value) { return value + 1; }).join(","); };
    #|run();
  let default_value = issue891_default_run_for_wb(source)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "2,3")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 candidate forEach excludes sibling some" {
  let source =
    #|var run = function() { return [1, 2].some(function(value) { return value === 1; }); };
    #|run();
  let default_value = issue891_default_run_for_wb(source)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 candidate forEach excludes sibling every" {
  let source =
    #|var run = function() { return [1, 2].every(function(value) { return value === 1; }); };
    #|run();
  let default_value = issue891_default_run_for_wb(source)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "false")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 candidate forEach excludes sibling filter" {
  let source =
    #|var run = function() { return [1, 2].filter(function(value) { return value === 1; }).length; };
    #|run();
  let default_value = issue891_default_run_for_wb(source)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "1")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 callback depth rejection precedes callback body" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var events = []; var receiver = { 0: 1, length: 1 }; " +
    "function callback() { events.push('body'); } " +
    "function run() { Array.prototype.forEach.call(receiver, callback); }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(10000L, 0L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let caught : Error? = interp.with_execution_policy(policy, () => {
    try {
      let _ = run_executor_neutral_bytecode(interp, "run();")
      None
    } catch {
      error => Some(error)
    }
  })
  match caught {
    Some(@runtime.JsException(value)) =>
      assert_true(@runtime.is_engine_stack_depth_error(value))
    Some(error) =>
      assert_eq(
        @runtime.execution_control_failure_code(error),
        Some("stack-depth-limit"),
      )
    None => fail("callback depth must be rejected")
  }
  assert_eq(interp.global.get("events").to_string(), "")
}

///|
test "issue 891 sparse loop budget rejects before any callback" {
  let source =
    #|var callbacks = 0;
    #|var receiver = { length: 100 };
    #|var run = function() {
    #|  Array.prototype.forEach.call(receiver, function() { callbacks = callbacks + 1; });
    #|};
    #|run();
  let interp = @interpreter.new_interpreter()
  let policy = match
    @runtime.ExecutionPolicy::new(20L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let caught : Error? = interp.with_execution_policy(policy, () => {
    try {
      let _ = run_candidate_program_with_evidence(
        interp,
        @parser.parse(source).stmts,
      )
      None
    } catch {
      error => Some(error)
    }
  })
  match caught {
    Some(error) =>
      assert_eq(
        @runtime.execution_control_failure_code(error),
        Some("execution-limit"),
      )
    None => fail("sparse loop budget must be rejected")
  }
  assert_eq(interp.global.get("callbacks").to_string(), "0")
}

///|
test "issue 891 large finite sparse array-like yields without host recursion" {
  let source =
    #|var callbacks = 0;
    #|var receiver = { length: 1000000 };
    #|var run = function() {
    #|  Array.prototype.forEach.call(receiver, function() { callbacks = callbacks + 1; });
    #|  return callbacks;
    #|};
    #|run();
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "0")
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 exact identity excludes a replaced forEach" {
  let source =
    #|var original = Array.prototype.forEach;
    #|var receiver = { length: 1 };
    #|Array.prototype.forEach = function() { return "replacement"; };
    #|var run = function() {
    #|  var replacement = Array.prototype.forEach.call(receiver, function() {});
    #|  var intrinsic = original.call(receiver, function() {});
    #|  return replacement + ":" + (intrinsic === undefined);
    #|};
    #|run();
  let default_value = issue891_default_run_for_wb(source)
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "replacement:true")
  assert_eq(default_value.to_string(), value.to_string())
  issue891_assert_evidence_for_wb(evidence)
}

///|
test "issue 891 forEach callback captured through Proxy-backed with uses managed binding" {
  let source =
    #|var events = [];
    #|var target = { captured: 7 };
    #|var scope = new Proxy(target, {
    #|  has: function(t, key) { events.push(key === "captured" ? "has" : "other"); return Reflect.has(t, key); },
    #|  get: function(t, key, receiver) { events.push(key === Symbol.unscopables ? "unscopables" : "get"); return Reflect.get(t, key, receiver); }
    #|});
    #|var callback;
    #|with (scope) { callback = function(value) { this.seen = captured + value; }; }
    #|events = [];
    #|var run = function() { [1].forEach(callback, target); };
    #|run();
    #|String(target.seen) + ":" + events.join(",");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "8:has,unscopables,has,get")
  issue891_assert_evidence_for_wb(evidence)
}
