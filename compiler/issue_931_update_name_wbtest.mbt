///|
// Issue #931 RED: a name update is currently typed pre-start, so the
// candidate route falls back before executing the UpdateName instruction.

///|
fn issue931_assert_form_route_for_wb(
  source : String,
  expected : String,
) -> Unit raise Error {
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), expected)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.bytecode_starts, 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 931 candidate admits typed UpdateName" {
  let (value, evidence) = candidate_run_with_evidence_for_wb(
    "var value = 1; value++; value;",
  )
  assert_eq(value.to_string(), "2")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 931 admits each opcode-specific UpdateName form" {
  issue931_assert_form_route_for_wb("var value = 1; ++value; value;", "2")
  issue931_assert_form_route_for_wb("var value = 1; value++; value;", "2")
  issue931_assert_form_route_for_wb("var value = 1; --value; value;", "0")
  issue931_assert_form_route_for_wb("var value = 1; value--; value;", "0")
}

///|
test "issue 931 candidate preserves all name update result forms" {
  let source =
    #|var value = 1;
    #|var prefix_increment = ++value;
    #|var postfix_increment = value++;
    #|var prefix_decrement = --value;
    #|var postfix_decrement = value--;
    #|[prefix_increment, postfix_increment, prefix_decrement, postfix_decrement, value].join(",");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "2,2,2,2,1")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 931 default and candidate agree on name update results" {
  let source =
    #|var value = 1;
    #|var postfix = value++;
    #|var prefix = ++value;
    #|[postfix, prefix, value].join(",");
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "1,3,3")
  assert_eq(candidate_value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.bytecode_starts, 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 931 candidate owns primitive Number-domain conversions" {
  let source =
    #|var numeric_string = "4";
    #|var bool_value = true;
    #|var null_value = null;
    #|var undefined_value;
    #|[numeric_string++, ++bool_value, null_value++, undefined_value++].join(",") + ":" + [numeric_string, bool_value, null_value, undefined_value].join(",");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "4,2,0,NaN:5,2,1,NaN")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 931 candidate preserves Number-hint hooks and receivers" {
  let source =
    #|var events = [];
    #|var primitive = {};
    #|primitive[Symbol.toPrimitive] = function(hint) { events.push(hint + ":" + (this === primitive)); return "6"; };
    #|var primitive_old = primitive++;
    #|var fallback = { valueOf: function() { events.push("valueOf:" + (this === fallback)); return {}; }, toString: function() { events.push("toString:" + (this === fallback)); return "8"; } };
    #|var fallback_old = fallback++;
    #|var array = [9];
    #|var array_old = array++;
    #|var proxy_target = { valueOf: function() { events.push("proxyValueOf:" + (this === proxy)); return 10; } };
    #|var proxy = new Proxy(proxy_target, { get: function(t, key, receiver) { events.push("get:" + String(key)); return Reflect.get(t, key, receiver); } });
    #|var proxy_old = proxy++;
    #|[primitive_old, fallback_old, array_old, proxy_old].join(",") + ":" + events.join("|");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(
    value.to_string(),
    "6,8,9,10:number:true|valueOf:true|toString:true|get:Symbol(Symbol.toPrimitive)|get:valueOf|proxyValueOf:true",
  )
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 931 candidate propagates Symbol conversion TypeError" {
  let interp = @interpreter.new_interpreter()
  let source = "var value = Symbol('value'); value++;"
  let result : String = try {
    ignore(run_candidate_program_with_evidence(interp, @parser.parse(source).stmts))
    "no error"
  } catch {
    @runtime.JsException(value) => value.to_string()
    error => error.to_string()
  }
  assert_true(result.contains("Cannot convert a Symbol value to a number"))
  assert_eq(interp.host.microtask_queue.length(), 0)
}

///|
test "issue 931 candidate retains one with Proxy Reference" {
  let source =
    #|var events = [];
    #|var target = { value: 3 };
    #|var outer = { value: 90 };
    #|var scope = new Proxy(target, {
    #|  has: function(t, key) { events.push("has:" + key); return Reflect.has(t, key); },
    #|  get: function(t, key, receiver) { events.push(key === Symbol.unscopables ? "unscopables" : "get:" + key); return Reflect.get(t, key, receiver); },
    #|  set: function(t, key, value, receiver) { events.push("set:" + key + ":" + value); return Reflect.set(t, key, value, receiver); }
    #|});
    #|var update;
    #|with (scope) { update = function() { return value++; }; }
    #|events = [];
    #|var old = update();
    #|old + ":" + target.value + ":" + outer.value + ":" + events.join(",");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(
    value.to_string(),
    "3:4:90:has:value,unscopables,has:value,get:value,set:value:4",
  )
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 931 candidate does not re-resolve after conversion mutation" {
  let source =
    #|var events = [];
    #|var phase = 0;
    #|var outer = { value: 100 };
    #|var target = {};
    #|var changing = { valueOf: function() { phase = 1; events.push("convert"); return 3; } };
    #|target.value = changing;
    #|var scope = new Proxy(target, {
    #|  has: function(t, key) { events.push("has:" + key + ":" + phase); return phase === 0 && Reflect.has(t, key); },
    #|  get: function(t, key, receiver) { events.push(key === Symbol.unscopables ? "unscopables" : "get:" + key); return Reflect.get(t, key, receiver); },
    #|  set: function(t, key, value, receiver) { events.push("set:" + key + ":" + value); return Reflect.set(t, key, value, receiver); }
    #|});
    #|var update;
    #|with (scope) { update = function() { return value++; }; }
    #|events = [];
    #|var old = update();
    #|old + ":" + target.value + ":" + outer.value + ":" + events.join(",");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(
    value.to_string(),
    "3:4:100:has:value:0,unscopables,has:value:0,get:value,convert,set:value:4",
  )
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 931 candidate retains conversion effects when PutValue throws" {
  let source =
    #|var events = [];
    #|var target = { value: { valueOf: function() { events.push("convert"); return 3; } } };
    #|var scope = new Proxy(target, {
    #|  has: function(t, key) { return Reflect.has(t, key); },
    #|  get: function(t, key, receiver) { return Reflect.get(t, key, receiver); },
    #|  set: function(t, key, value, receiver) { events.push("set:" + value); throw "write failed"; }
    #|});
    #|var update;
    #|with (scope) { update = function() { return value++; }; }
    #|try { update(); } catch (error) { events.push(error); }
    #|events.join(",") + ":" + (typeof target.value);
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "convert,set:4,write failed:object")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 931 candidate preserves TDZ const unresolved and immutable rules" {
  let source =
    #|var results = [];
    #|try { { let tdz = tdz++; } } catch (error) { results.push(error.name); }
    #|try { { const fixed = 1; fixed++; } } catch (error) { results.push(error.name); }
    #|try { missing++; } catch (error) { results.push(error.name); }
    #|var sloppy = undefined++;
    #|results.push("sloppy:" + sloppy);
    #|(function() { "use strict"; try { undefined++; } catch (error) { results.push("strict:" + error.name); } })();
    #|results.join(",");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "ReferenceError,TypeError,ReferenceError,sloppy:NaN,strict:TypeError")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 931 leaves excluded UpdateLocal typed" {
  assert_candidate_tree_route_evidence_for_wb(
    "for (var unused of [0]) {}; function local() { var value = 1; return value++; } local();",
    "1",
    child=true,
  )
}

///|
test "issue 931 leaves excluded UpdateEnvSlot typed" {
  let source =
    #|function outer() { var value = 1; function read() { return value; } value++; return value; }
    #|outer();
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  let outer = root.children[0]
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "2")
  let mut prepared = 0
  let mut tree_starts = 0
  let mut bytecode_starts = 0
  let mut completed = 0
  for event in evidence.val.events {
    match event {
      CandidateRoutePreparedEvent(item) if
        bytecode_source_identity_coordinates_equal_for_wb(
          item.source_identity,
          outer.source_identity,
        ) => {
        prepared += 1
        match item.decision {
          UseTreeWalker(CandidateActivationUnsupported(_)) => ()
          UseTreeWalker(CandidateLoweringUnsupported(_)) =>
            fail("captured UpdateEnvSlot used lowering fallback")
          UseBytecode(_) => fail("captured UpdateEnvSlot prepared bytecode")
        }
      }
      CandidateRouteStartedEvent(item) if
        bytecode_source_identity_coordinates_equal_for_wb(
          item.source_identity,
          outer.source_identity,
        ) =>
        match item.executor {
          CandidateTreeWalkerExecutor => tree_starts += 1
          CandidateBytecodeExecutor => bytecode_starts += 1
        }
      CandidateRouteCompletedEvent(item) if
        bytecode_source_identity_coordinates_equal_for_wb(
          item.source_identity,
          outer.source_identity,
        ) => {
        completed += 1
        match item.completion {
          CandidateRouteNormal => ()
          CandidateRouteAbrupt => fail("captured UpdateEnvSlot completed abruptly")
        }
      }
      _ => ()
    }
  }
  assert_eq(prepared, 1)
  assert_eq(tree_starts, 1)
  assert_eq(bytecode_starts, 0)
  assert_eq(completed, 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 931 characterization sees captured update env slot" {
  let source =
    #|function outer() { var value = 1; function read() { return value; } value++; return value; }
    #|outer();
  let bytecode = parse_bytecode_for_wb(source)
  let outer = bytecode.main_for_wb().children[0]
  let mut saw_env_update = false
  for instr in outer.code {
    match instr {
      UpdateEnvSlot(_, _, _) => saw_env_update = true
      UpdateName(_, _, _, _) => fail("captured update lowered to UpdateName")
      _ => ()
    }
  }
  assert_true(saw_env_update)
}

///|
test "issue 931 leaves excluded UpdateComputed typed" {
  assert_candidate_tree_route_evidence_for_wb(
    "var target = { value: 1 }; var key = 'value'; target[key]++; target[key];",
    "2",
  )
}

///|
test "issue 931 canonical property chain graduates with aggregate evidence" {
  let source =
    #|var obj = { a: { b: { c: { d: { e: 42 } } } } };
    #|var sum = 0;
    #|for (var i = 0; i < 10000; i++) {
    #|  sum = sum + obj.a.b.c.d.e;
    #|}
    #|sum;
  let (value, evidence) = candidate_run_with_summary_for_wb(source)
  assert_eq(value.to_string(), "420000")
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.bytecode_starts, 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  assert_eq(evidence.val.events.length(), 0)
  assert_eq(evidence.val.lifecycles.length(), 0)
}

///|
test "issue 931 three-iteration chain has exact observable counts" {
  let source =
    #|var events = "";
    #|var limit = { valueOf: function() { events = events + "l"; return 3; } };
    #|var leaf = { valueOf: function() { events = events + "a"; return 42; } };
    #|var level4 = { get e() { events = events + "r"; return leaf; } };
    #|var level3 = { get d() { events = events + "r"; return level4; } };
    #|var level2 = { get c() { events = events + "r"; return level3; } };
    #|var level1 = { get b() { events = events + "r"; return level2; } };
    #|var root = { get a() { events = events + "r"; return level1; } };
    #|var sum = 0;
    #|for (var i = 0; i < limit; i++) { sum = sum + root.a.b.c.d.e; }
    #|sum + ":" + i + ":" + events;
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "126:3:lrrrrralrrrrralrrrrral")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 931 loop-only control remains aggregate and route-clean" {
  let source =
    #|var total = 0;
    #|for (var i = 0; i < 10000; i++) { total = total + 1; }
    #|total;
  let (value, evidence) = candidate_run_with_summary_for_wb(source)
  assert_eq(value.to_string(), "10000")
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.bytecode_starts, 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  assert_eq(evidence.val.events.length(), 0)
  assert_eq(evidence.val.lifecycles.length(), 0)
}
