///|
fn computed_set_root_executor(source : String) -> String raise Error {
  let report = profile_candidate_route_plan_json(@parser.parse(source).stmts)
  match report {
    Json::Object(fields) =>
      match fields.get("functions") {
        Some(Json::Array([Json::Object(root), ..])) =>
          match root.get("executor") {
            Some(Json::String(executor)) => executor
            _ => fail("route profile root omitted executor")
          }
        _ => fail("route profile omitted root function")
      }
    _ => fail("route profile was not an object")
  }
}

///|
fn computed_set_candidate_run(
  source : String,
) -> (@runtime.Value, Ref[CandidateRouteEvidence]) raise Error {
  let interp = @interpreter.new_interpreter()
  run_candidate_program_with_evidence(interp, @parser.parse(source).stmts)
}

///|
test "candidate computed set converts the key after evaluating the RHS" {
  let source =
    #|var trace = "";
    #|var target = {};
    #|var key = { toString: function() { trace = trace + "k"; return "x"; } };
    #|function rhs() { trace = trace + "r"; return 9; }
    #|target[key] = rhs();
    #|trace + ":" + target.x;
  inspect(computed_set_root_executor(source), content="bytecode")
  let (value, evidence) = computed_set_candidate_run(source)
  inspect(value.to_string(), content="rk:9")
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
}

///|
test "candidate computed compound set converts the key once before evaluating the RHS" {
  let source =
    #|var trace = "";
    #|var target = { x: 1 };
    #|var key = { toString: function() { trace = trace + "k"; return "x"; } };
    #|function rhs() { trace = trace + "r"; return 2; }
    #|function update(target, key) { target[key] += rhs(); }
    #|update(target, key);
    #|trace + ":" + target.x;
  let (value, evidence) = computed_set_candidate_run(source)
  inspect(value.to_string(), content="kr:3")
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("computed compound set did not start bytecode")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
}

///|
test "candidate computed set validates a nullish base after RHS and before key conversion" {
  let source =
    #|var trace = "";
    #|var key = { toString: function() { trace = trace + "k"; return "x"; } };
    #|function rhs() { trace = trace + "r"; return 9; }
    #|function write(target, key) { target[key] = rhs(); }
    #|function attempt(target) {
    #|  try {
    #|    write(target, key);
    #|  } catch (error) {
    #|    trace = trace + (error instanceof TypeError ? "t" : "e");
    #|  }
    #|}
    #|attempt(null);
    #|attempt(undefined);
    #|trace;
  let (value, evidence) = computed_set_candidate_run(source)
  inspect(value.to_string(), content="rtrt")
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("computed null-base set did not start bytecode")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
}

///|
test "candidate computed set preserves Proxy Symbol traps" {
  let source =
    #|var key = Symbol("key");
    #|var target = {};
    #|var sawKey = false;
    #|var proxy = new Proxy(target, {
    #|  set: function(inner, property, value, receiver) {
    #|    sawKey = property === key && receiver === proxy;
    #|    return Reflect.set(inner, property, value, receiver);
    #|  }
    #|});
    #|function write(target, key, value) { return target[key] = value; }
    #|var result = write(proxy, key, 11);
    #|sawKey + ":" + result + ":" + target[key];
  let (value, evidence) = computed_set_candidate_run(source)
  inspect(value.to_string(), content="true:11:11")
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("computed Proxy set did not start bytecode")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
}

///|
test "candidate computed set preserves Receiver through nested trapless Proxies" {
  let source =
    #|var key = Symbol("key");
    #|var receiver;
    #|var sawReceiver = false;
    #|var target = {};
    #|Object.defineProperty(target, key, {
    #|  set: function(value) { sawReceiver = this === receiver; }
    #|});
    #|var first = new Proxy(target, {});
    #|var second = new Proxy(first, {});
    #|receiver = Object.create(second);
    #|function write(receiver, key) { receiver[key] = 1; }
    #|write(receiver, key);
    #|sawReceiver;
  let (value, evidence) = computed_set_candidate_run(source)
  inspect(value.to_string(), content="true")
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("nested trapless Proxy set did not start bytecode")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
}

///|
test "candidate computed set only fast paths canonical array indices" {
  let source =
    #|var values = [3, 4];
    #|var key = { toString: function() { return "01"; } };
    #|values[key] = 9;
    #|values[1] + ":" + values["01"];
  let (value, evidence) = computed_set_candidate_run(source)
  inspect(value.to_string(), content="4:9")
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
}
