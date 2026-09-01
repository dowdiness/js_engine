///|
// Issue #936 RED: computed call preparation must retain the original base as
// the receiver while the managed property lookup completes.
test "issue 936 admits ordinary computed receiver calls" {
  let source =
    #|var receiver = { value: 42, method: function() { return this.value; } };
    #|var key = "method";
    #|receiver[key]();
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "42")
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 936 graduates the unchanged closure factory benchmark" {
  let source =
    #|function makeCounter(start) {
    #|  var count = start;
    #|  return function() {
    #|    count = count + 1;
    #|    return count;
    #|  };
    #|}
    #|var counters = [];
    #|for (var i = 0; i < 1000; i++) {
    #|  counters.push(makeCounter(i));
    #|}
    #|var total = 0;
    #|for (var i = 0; i < 1000; i++) {
    #|  total = total + counters[i]();
    #|}
    #|total;
  let (value, evidence) = candidate_run_with_summary_for_wb(source)
  assert_eq(value.to_string(), "500500")
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 936 keeps independently captured counter cells" {
  let source =
    #|function makeCounter(start) {
    #|  var count = start;
    #|  return function() {
    #|    count = count + 1;
    #|    return count;
    #|  };
    #|}
    #|var first = makeCounter(0);
    #|var second = makeCounter(1);
    #|var third = makeCounter(10);
    #|first() + ":" + second() + ":" + third();
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "1:2:11")
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 936 keeps an old counter closure callable after later eval" {
  let interp = @interpreter.new_interpreter()
  let initial_source =
    #|function makeCounter(start) {
    #|  var count = start;
    #|  return function() {
    #|    count = count + 1;
    #|    return count;
    #|  };
    #|}
    #|var oldCounter = makeCounter(2);
  let (_, initial_evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(initial_source).stmts,
  )
  let initial_start_count = candidate_started_executors_for_wb(initial_evidence).length()
  ignore(
    run_candidate_program_with_evidence(
      interp,
      @parser.parse("var later = 7;").stmts,
    ),
  )
  let (value, call_evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse("oldCounter();").stmts,
  )
  assert_eq(value.to_string(), "3")
  assert_eq(call_evidence.val.summary.tree_starts, 0)
  assert_true(call_evidence.val.summary.bytecode_starts > 0)
  assert_eq(call_evidence.val.summary.fallback_violations, 0)
  assert_eq(call_evidence.val.summary.replay_violations, 0)
  assert_eq(call_evidence.val.summary.active_activations, 0)
  let initial_starts = candidate_started_executors_for_wb(initial_evidence)
  assert_eq(initial_starts.length(), initial_start_count + 1)
  match initial_starts[initial_starts.length() - 1] {
    CandidateBytecodeExecutor => ()
    CandidateTreeWalkerExecutor =>
      fail("old counter closure did not start through bytecode")
  }
  assert_eq(initial_evidence.val.summary.tree_starts, 0)
  assert_eq(initial_evidence.val.summary.fallback_violations, 0)
  assert_eq(initial_evidence.val.summary.replay_violations, 0)
  assert_eq(initial_evidence.val.summary.active_activations, 0)
}

///|
test "issue 936 preserves computed call receiver identity" {
  let source =
    #|var functions = [function() { return this === functions; }];
    #|functions[0]();
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
  assert_eq(candidate_started_executors_for_wb(evidence).length(), 2)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 936 preserves key getter argument call ordering" {
  let source =
    #|var log = "";
    #|var receiver = {
    #|  get method() {
    #|    log = log + "g";
    #|    return function(value) {
    #|      log = log + "c" + value;
    #|      return this === receiver;
    #|    };
    #|  }
    #|};
    #|function key() { log = log + "k"; return "method"; }
    #|function argument() { log = log + "a"; return 7; }
    #|receiver[key()](argument()) + ":" + log;
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "true:kgac7")
  assert_eq(value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 936 getter throw skips computed call arguments" {
  let source =
    #|var log = "";
    #|var receiver = { get method() { log = log + "g"; throw new Error("getter"); } };
    #|function argument() { log = log + "a"; return 7; }
    #|receiver["method"](argument());
  let interp = @interpreter.new_interpreter()
  let caught : Error? = try {
    ignore(run_executor_neutral_bytecode(interp, source))
    None
  } catch {
    error => Some(error)
  }
  guard caught is Some(_) else { fail("computed getter must throw") }
  assert_eq(interp.global.get("log").to_string(), "g")
}

///|
test "issue 936 non-callable computed callee evaluates arguments first" {
  let source =
    #|var log = "";
    #|var receiver = { method: 1 };
    #|function argument() { log = log + "a"; return 7; }
    #|receiver["method"](argument());
  let interp = @interpreter.new_interpreter()
  let caught : Error? = try {
    ignore(run_executor_neutral_bytecode(interp, source))
    None
  } catch {
    error => Some(error)
  }
  guard caught is Some(_) else {
    fail("non-callable computed callee must throw")
  }
  assert_eq(interp.global.get("log").to_string(), "a")
}

///|
test "issue 936 argument throw retains one computed get effect" {
  let source =
    #|var log = "";
    #|var receiver = { get method() { log = log + "g"; return function() {}; } };
    #|function argument() { log = log + "a"; throw new Error("argument"); }
    #|receiver["method"](argument());
  let interp = @interpreter.new_interpreter()
  let caught : Error? = try {
    ignore(run_executor_neutral_bytecode(interp, source))
    None
  } catch {
    error => Some(error)
  }
  guard caught is Some(_) else { fail("argument throw must propagate") }
  assert_eq(interp.global.get("log").to_string(), "ga")
}

///|
test "issue 936 converts object Symbol and numeric computed keys once" {
  let source =
    #|var events = "";
    #|var receiver = { method: function() { return this === receiver; } };
    #|var key = {};
    #|Object.defineProperty(key, Symbol.toPrimitive, { value: function(hint) { events = events + hint; return "method"; } });
    #|var symbol = Symbol("method");
    #|Object.defineProperty(receiver, symbol, { value: function() { return this === receiver; } });
    #|var functions = [function() { return this === functions; }];
    #|receiver[key]() + ":" + receiver[symbol]() + ":" + functions[0]() + ":" + events;
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "true:true:true:string")
  assert_eq(value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 936 preserves inherited and Proxy computed call lookup" {
  let inherited =
    #|var log = "";
    #|var proto = { get method() { log = log + "g"; return function() { log = log + "c"; return 7; }; } };
    #|var receiver = Object.create(proto);
    #|receiver["method"]() + ":" + log;
  let inherited_value = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    inherited,
  )
  assert_eq(inherited_value.to_string(), "7:gc")
  let proxied =
    #|var log = "";
    #|var target = { method: function() { log = log + "c"; return 7; } };
    #|var receiver = new Proxy(target, { get: function(t, key, r) { log = log + "p"; return Reflect.get(t, key, r); } });
    #|receiver["method"]() + ":" + log;
  let proxied_value = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    proxied,
  )
  assert_eq(proxied_value.to_string(), "7:pc")
}

///|
test "issue 936 preserves the original base for callable Proxy thisArg" {
  let source =
    #|var base = {};
    #|var target = function() { return 0; };
    #|var callable = new Proxy(target, { apply: function(_target, thisArg, _args) { return thisArg === base; } });
    #|base.method = callable;
    #|base["method"]();
  let value = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  assert_eq(value.to_string(), "true")
}

///|
test "issue 936 does not replay base key or getter after suspension" {
  let source =
    #|var keyCalls = 0;
    #|var getCalls = 0;
    #|var receiver = {};
    #|var key = { [Symbol.toPrimitive]: function() { keyCalls = keyCalls + 1; receiver.changed = 1; return "method"; } };
    #|Object.defineProperty(receiver, "method", { get: function() { getCalls = getCalls + 1; receiver.changed = 2; return function() { return receiver.changed; }; } });
    #|receiver[key]() + ":" + keyCalls + ":" + getCalls;
  let value = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  assert_eq(value.to_string(), "2:1:1")
}

///|
test "issue 936 rejects null computed call before key conversion" {
  let source =
    #|var keyCalls = 0;
    #|var key = { [Symbol.toPrimitive]: function() { keyCalls = keyCalls + 1; return "method"; } };
    #|null[key]();
  let interp = @interpreter.new_interpreter()
  let caught : Error? = try {
    ignore(run_executor_neutral_bytecode(interp, source))
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@runtime.JsException(value)) =>
      match value {
        Object(data) => assert_eq(data.class_name, "TypeError")
        _ => fail("null computed call must throw a TypeError object")
      }
    Some(error) => fail("null computed call raised: " + error.to_string())
    None => fail("null computed call must throw TypeError")
  }
  assert_eq(interp.global.get("keyCalls").to_string(), "0")
}

///|
test "issue 936 rejects undefined computed call before key conversion" {
  let source =
    #|var keyCalls = 0;
    #|var key = { [Symbol.toPrimitive]: function() { keyCalls = keyCalls + 1; return "method"; } };
    #|undefined[key]();
  let interp = @interpreter.new_interpreter()
  let caught : Error? = try {
    ignore(run_executor_neutral_bytecode(interp, source))
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@runtime.JsException(value)) =>
      match value {
        Object(data) => assert_eq(data.class_name, "TypeError")
        _ => fail("undefined computed call must throw a TypeError object")
      }
    Some(error) => fail("undefined computed call raised: " + error.to_string())
    None => fail("undefined computed call must throw TypeError")
  }
  assert_eq(interp.global.get("keyCalls").to_string(), "0")
}

///|
test "issue 936 boxes primitive computed-call bases but preserves receiver" {
  let source =
    #|var key = "issue936Receiver";
    #|Number.prototype.issue936Receiver = function() { "use strict"; return typeof this + ":" + this.valueOf(); };
    #|(1)[key]();
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "number:1")
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 936 propagates revoked Proxy computed call errors" {
  let source =
    #|var target = { method: function() { return 7; } };
    #|var revocable = Proxy.revocable(target, {});
    #|var receiver = revocable.proxy;
    #|revocable.revoke();
    #|receiver["method"]();
  let interp = @interpreter.new_interpreter()
  let caught : Error? = try {
    ignore(run_executor_neutral_bytecode(interp, source))
    None
  } catch {
    error => Some(error)
  }
  guard caught is Some(_) else { fail("revoked computed call must throw") }
}

///|
test "issue 936 admits fixed spread optional and tagged computed calls" {
  let fixed =
    #|var receiver = { method: function(value) { return value; } };
    #|receiver["method"](3);
  let spread =
    #|var receiver = { method: function(left, right) { return left + right; } };
    #|receiver["method"](...[2, 4]);
  let optional_chain =
    #|var receiver = { method: function() { return "chain"; } };
    #|receiver?.["method"]();
  let optional_callee =
    #|var receiver = { method: function() { return "callee"; } };
    #|receiver["method"]?.();
  let tagged =
    #|var receiver = { tag: function(strings, value) { return value; } };
    #|receiver["tag"]`a${2}b`;
  let mut index = 0
  for
    pair in [
      (fixed, "3"),
      (spread, "6"),
      (optional_chain, "chain"),
      (optional_callee, "callee"),
      (tagged, "2"),
    ] {
    let source = pair.0
    let expected = pair.1
    let (value, evidence) = candidate_run_with_evidence_for_wb(source)
    assert_eq(value.to_string(), expected)
    if evidence.val.summary.tree_starts != 0 {
      fail(
        "computed consumer form selected Tree-walker at index " +
        index.to_string(),
      )
    }
    assert_eq(evidence.val.summary.fallback_violations, 0)
    assert_eq(evidence.val.summary.replay_violations, 0)
    assert_eq(evidence.val.summary.active_activations, 0)
    index += 1
  }
}

///|
test "issue 936 admits computed reads without admitting computed updates" {
  let read = prepare_candidate_program(
    @parser.parse(
      "var receiver = { method: 1 }; var key = 'method'; receiver[key];",
    ).stmts,
  )
  guard read.root.selection is UseBytecode(_) else {
    fail("managed computed Get did not select bytecode")
  }
  let update = prepare_candidate_program(
    @parser.parse(
      "var receiver = { method: 1 }; var key = 'method'; receiver[key]++;",
    ).stmts,
  )
  guard update.root.selection is UseTreeWalker(_) else {
    fail("computed Update was admitted with computed-call preparation")
  }
}
