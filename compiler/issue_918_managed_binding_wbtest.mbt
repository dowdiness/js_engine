///|
// Issue #918 candidate-route coverage for managed name resolution through a
// captured `with` object. The parent is Tree-walker-only; the child is routed
// independently and must suspend through the runtime binding seam.

///|
fn issue918_default_run_for_wb(source : String) -> @runtime.Value raise Error {
  let interp = @interpreter.new_interpreter()
  interp.run(@parser.parse(source).stmts)
}

///|
test "issue 918 candidate child resolves a Proxy-backed with binding" {
  let source =
    #|var events = [];
    #|var target = { captured: 7 };
    #|var scope = new Proxy(target, {
    #|  has: function(t, key) { events.push(key === "captured" ? "has:c" : "has:o"); return Reflect.has(t, key); },
    #|  get: function(t, key, receiver) { events.push(key === Symbol.unscopables ? "get:u" : "get:c"); return Reflect.get(t, key, receiver); }
    #|});
    #|var child;
    #|with (scope) { child = function() { return captured; }; }
    #|events = [];
    #|child() + ":" + events.join(",");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "7:has:c,get:u,get:c")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 918 preserves lexical binding fast paths above with objects" {
  let source =
    #|var events = [];
    #|var target = { captured: 7 };
    #|var scope = new Proxy(target, {
    #|  has: function(t, key) { events.push("has"); return Reflect.has(t, key); },
    #|  get: function(t, key, receiver) { events.push("get"); return Reflect.get(t, key, receiver); }
    #|});
    #|var child;
    #|with (scope) { child = function() { var local = 4; return local; }; }
    #|events = [];
    #|child() + ":" + events.join(",");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "4:")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 918 candidate child stores through a Proxy-backed with binding" {
  let source =
    #|var events = [];
    #|var target = { captured: 1 };
    #|var scope = new Proxy(target, {
    #|  has: function(t, key) { events.push(key === "captured" ? "has" : "other"); return Reflect.has(t, key); },
    #|  get: function(t, key, receiver) { events.push(key === Symbol.unscopables ? "unscopables" : "get"); return Reflect.get(t, key, receiver); },
    #|  set: function(t, key, value, receiver) { events.push("set"); return Reflect.set(t, key, value, receiver); }
    #|});
    #|var child;
    #|with (scope) { child = function(value) { captured = value; return captured; }; }
    #|events = [];
    #|child(9) + ":" + target.captured + ":" + events.join(",");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "9:9:has,unscopables,set,has,unscopables,get")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 918 binding seam survives a native callback activation" {
  let source =
    #|var events = [];
    #|var target = { captured: 7 };
    #|var scope = new Proxy(target, {
    #|  has: function(t, key) { events.push("has"); return Reflect.has(t, key); },
    #|  get: function(t, key, receiver) { events.push(key === Symbol.unscopables ? "unscopables" : "get"); return Reflect.get(t, key, receiver); }
    #|});
    #|var callback;
    #|with (scope) { callback = function(value) { this.seen = captured + value; }; }
    #|events = [];
    #|[1].forEach(callback, target);
    #|String(target.seen) + ":" + events.join(",");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "8:has,unscopables,get")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 918 candidate child resolves typeof through a Proxy-backed with binding" {
  let source =
    #|var events = [];
    #|var target = { captured: 7 };
    #|var scope = new Proxy(target, {
    #|  has: function(t, key) { events.push(key === "captured" ? "has" : "other"); return Reflect.has(t, key); },
    #|  get: function(t, key, receiver) { events.push(key === Symbol.unscopables ? "unscopables" : "get"); return Reflect.get(t, key, receiver); }
    #|});
    #|var child;
    #|with (scope) { child = function() { return typeof captured; }; }
    #|events = [];
    #|child() + ":" + events.join(",");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "number:has,unscopables,get")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 918 candidate with unscopables preserves fallback ordering" {
  let source =
    #|var events = [];
    #|var captured = 3;
    #|var target = { captured: 7 };
    #|target[Symbol.unscopables] = { captured: true };
    #|var scope = new Proxy(target, {
    #|  has: function(t, key) { events.push(key === "captured" ? "has" : "other"); return Reflect.has(t, key); },
    #|  get: function(t, key, receiver) { events.push(key === Symbol.unscopables ? "unscopables" : "get"); return Reflect.get(t, key, receiver); }
    #|});
    #|var child;
    #|with (scope) { child = function() { return captured; }; }
    #|events = [];
    #|child() + ":" + events.join(",");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "3:has,unscopables")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 918 default and candidate with binding paths stay equivalent" {
  let source =
    #|var events = [];
    #|var phase = 0;
    #|var target = { captured: 7 };
    #|var scope = new Proxy(target, {
    #|  has: function(t, key) { if (phase === 1 && key === "captured") events.push("has"); return Reflect.has(t, key); },
    #|  get: function(t, key, receiver) { if (phase === 1 && key === Symbol.unscopables) events.push("unscopables"); if (phase === 1 && key === "captured") events.push("get"); return Reflect.get(t, key, receiver); }
    #|});
    #|var child;
    #|with (scope) { child = function() { return captured; }; }
    #|events = [];
    #|phase = 1;
    #|child() + ":" + events.join(",");
  let default_value = issue918_default_run_for_wb(source)
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), candidate_value.to_string())
  assert_eq(candidate_value.to_string(), "7:has,unscopables,get")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 918 candidate with binding abrupt completion cleans for reuse" {
  let source =
    #|var attempts = 0;
    #|var target = { get captured() { attempts = attempts + 1; if (attempts === 1) throw new Error("boom"); return 8; } };
    #|var scope = new Proxy(target, {
    #|  has: function(t, key) { return Reflect.has(t, key); },
    #|  get: function(t, key, receiver) { return Reflect.get(t, key, receiver); }
    #|});
    #|var child;
    #|with (scope) { child = function() { return captured; }; }
    #|var first = "none";
    #|try { child(); } catch (error) { first = error.name; }
    #|first + ":" + child() + ":" + attempts;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "Error:8:2")
  assert_true(evidence.val.summary.abrupt_completions > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 918 candidate with binding traps terminate exactly once" {
  let source =
    #|var mode = 0;
    #|var events = [];
    #|var target = { captured: 1 };
    #|var scope = new Proxy(target, {
    #|  has: function(t, key) { events.push("h"); if (mode === 1) throw new Error("has"); return Reflect.has(t, key); },
    #|  get: function(t, key, receiver) { events.push(key === Symbol.unscopables ? "u" : "g"); if (mode === 2 && key === Symbol.unscopables) throw new Error("get"); return Reflect.get(t, key, receiver); },
    #|  set: function(t, key, value, receiver) { events.push("s"); if (mode === 3) throw new Error("set"); return Reflect.set(t, key, value, receiver); }
    #|});
    #|var read;
    #|var store;
    #|with (scope) { read = function() { return captured; }; store = function(value) { captured = value; return value; }; }
    #|events = [];
    #|var errors = [];
    #|mode = 1; try { read(); } catch (error) { errors.push(error.name); }
    #|mode = 2; try { read(); } catch (error) { errors.push(error.name); }
    #|mode = 3; try { store(9); } catch (error) { errors.push(error.name); }
    #|errors.join(",") + ":" + events.join("");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "Error,Error,Error:hhuhus")
  assert_true(evidence.val.summary.abrupt_completions > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}
