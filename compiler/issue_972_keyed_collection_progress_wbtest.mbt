///|
fn keyed_collection_policy_972(
  step_budget : Int64,
) -> @runtime.ExecutionPolicy raise Error {
  match
    @runtime.ExecutionPolicy::new(
      step_budget,
      100L,
      @runtime.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid keyed-collection policy")
  }
}

///|
fn keyed_collection_setup_source_972() -> String {
  (
    #|var pairSource = new Array(2001);
    #|var valueSource = new Array(2001);
    #|for (var i = 0; i < 2001; i += 1) {
    #|  pairSource[i] = [i, i];
    #|  valueSource[i] = i;
    #|}
    #|var largeMap = new Map(pairSource);
    #|var largeSet = new Set(valueSource);
    #|var iteratorSet = new Set(valueSource);
    #|var setIterator = iteratorSet.values();
    #|for (var j = 0; j < 2000; j += 1) iteratorSet.delete(j);
    #|var callbackTotal = 2001;
    #|var mapCallbackSeen = [];
    #|var setCallbackSeen = [];
    #|var mutatorCallbackCalls = 0;
    #|function mapGetMissing() { return largeMap.get(-1); }
    #|function mapSetMissing() { return largeMap.set(-1, -1); }
    #|function mapHasMissing() { return largeMap.has(-1); }
    #|function mapDeleteMissing() { return largeMap.delete(-1); }
    #|function mapClearLarge() { return largeMap.clear(); }
    #|function mapGetOrInsertMissing() {
    #|  return largeMap.getOrInsert(-1, -1);
    #|}
    #|function mapGetOrInsertComputedMissing() {
    #|  return largeMap.getOrInsertComputed(-1, function() { return -1; });
    #|}
    #|function mapForEachLarge() {
    #|  return largeMap.forEach(function() {});
    #|}
    #|function mapForEachWithCallback() {
    #|  mapCallbackSeen = [];
    #|  return largeMap.forEach(function(value, key) {
    #|    mapCallbackSeen.push(key);
    #|  });
    #|}
    #|function mapCallbackPrefixIsValid() {
    #|  if (mapCallbackSeen.length <= 0 || mapCallbackSeen.length >= callbackTotal) return false;
    #|  for (var i = 0; i < mapCallbackSeen.length; i++) {
    #|    if (mapCallbackSeen[i] !== i) return false;
    #|  }
    #|  return true;
    #|}
    #|function mapSetStopped() { return largeMap.set(-1, -1); }
    #|function mapDeleteStopped() { return largeMap.delete(-1); }
    #|function mapGetOrInsertComputedStopped() {
    #|  return largeMap.getOrInsertComputed(-1, function() {
    #|    mutatorCallbackCalls = mutatorCallbackCalls + 1;
    #|    return -1;
    #|  });
    #|}
    #|function mapClearStopped() { return largeMap.clear(); }
    #|function mapMutatorState() {
    #|  return largeMap.size + ":" + largeMap.has(-1) + ":" + mutatorCallbackCalls;
    #|}
    #|function setAddMissing() { return largeSet.add(-1); }
    #|function setHasMissing() { return largeSet.has(-1); }
    #|function setDeleteMissing() { return largeSet.delete(-1); }
    #|function setClearLarge() { return largeSet.clear(); }
    #|function setForEachLarge() {
    #|  return largeSet.forEach(function() {});
    #|}
    #|function setForEachWithCallback() {
    #|  setCallbackSeen = [];
    #|  return largeSet.forEach(function(value) {
    #|    setCallbackSeen.push(value);
    #|  });
    #|}
    #|function setCallbackPrefixIsValid() {
    #|  if (setCallbackSeen.length <= 0 || setCallbackSeen.length >= callbackTotal) return false;
    #|  for (var i = 0; i < setCallbackSeen.length; i++) {
    #|    if (setCallbackSeen[i] !== i) return false;
    #|  }
    #|  return true;
    #|}
    #|function setAddStopped() { return largeSet.add(-1); }
    #|function setDeleteStopped() { return largeSet.delete(-1); }
    #|function setClearStopped() { return largeSet.clear(); }
    #|function setMutatorState() {
    #|  return largeSet.size + ":" + largeSet.has(-1) + ":" + mutatorCallbackCalls;
    #|}
    #|function resetMutatorState() {
    #|  largeMap = new Map(pairSource);
    #|  largeSet = new Set(valueSource);
    #|  mutatorCallbackCalls = 0;
    #|}
    #|function nextAfterTombstones() { return setIterator.next().value; }
  )
}

///|
fn assert_tree_keyed_collection_limit_972(
  interp : @interpreter.Interpreter,
  call_source : String,
) -> Unit raise Error {
  let policy = keyed_collection_policy_972(1000L)
  let caught : Error? = interp.with_execution_policy(policy, () => {
    try {
      ignore(interp.run(@parser.parse(call_source).stmts))
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
    None =>
      fail("Tree keyed-collection work completed without observing progress")
  }
}

///|
fn assert_candidate_keyed_collection_limit_972(
  interp : @interpreter.Interpreter,
  call_source : String,
) -> Unit raise Error {
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let policy = keyed_collection_policy_972(1000L)
  let caught : Error? = interp.with_execution_policy(policy, () => {
    try {
      ignore(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse(call_source).stmts,
          evidence,
        ),
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
    None =>
      fail(
        "candidate keyed-collection work completed without observing progress",
      )
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "direct Map and Set entry scans observe progress on Tree" {
  let interp = @interpreter.new_interpreter()
  ignore(interp.run(@parser.parse(keyed_collection_setup_source_972()).stmts))
  for
    call_source in [
      "mapGetMissing();", "mapSetMissing();", "mapHasMissing();", "mapDeleteMissing();",
      "mapClearLarge();", "mapGetOrInsertMissing();", "mapGetOrInsertComputedMissing();",
      "mapForEachLarge();", "setAddMissing();", "setHasMissing();", "setDeleteMissing();",
      "setClearLarge();", "setForEachLarge();",
    ] {
    ignore(interp.run(@parser.parse(keyed_collection_setup_source_972()).stmts))
    assert_tree_keyed_collection_limit_972(interp, call_source)
  }
}

///|
test "representative direct Map and Set scans stay on candidate Bytecode" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(interp, keyed_collection_setup_source_972()),
  )
  for
    call_source in [
      "mapGetMissing();", "setHasMissing();", "mapForEachLarge();", "setForEachLarge();",
    ] {
    ignore(
      run_executor_neutral_bytecode(interp, keyed_collection_setup_source_972()),
    )
    assert_candidate_keyed_collection_limit_972(interp, call_source)
  }
}

///|
test "Map and Set forEach callbacks preserve a bounded monotonic prefix" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(interp, keyed_collection_setup_source_972()),
  )
  assert_tree_keyed_collection_limit_972(interp, "mapForEachWithCallback();")
  assert_tree_keyed_collection_limit_972(interp, "setForEachWithCallback();")
  assert_eq(
    interp.run(@parser.parse("mapCallbackPrefixIsValid();").stmts).to_string(),
    "true",
  )
  assert_eq(
    interp.run(@parser.parse("setCallbackPrefixIsValid();").stmts).to_string(),
    "true",
  )
}

///|
test "interrupted Map and Set mutators preserve pre-probe state" {
  let interp = @interpreter.new_interpreter()
  ignore(interp.run(@parser.parse(keyed_collection_setup_source_972()).stmts))
  for
    (call_source, state_source) in [
      ("mapSetStopped();", "mapMutatorState();"),
      ("mapDeleteStopped();", "mapMutatorState();"),
      ("mapGetOrInsertComputedStopped();", "mapMutatorState();"),
      ("mapClearStopped();", "mapMutatorState();"),
      ("setAddStopped();", "setMutatorState();"),
      ("setDeleteStopped();", "setMutatorState();"),
      ("setClearStopped();", "setMutatorState();"),
    ] {
    ignore(interp.run(@parser.parse("resetMutatorState();").stmts))
    assert_tree_keyed_collection_limit_972(interp, call_source)
    assert_eq(
      interp.run(@parser.parse(state_source).stmts).to_string(),
      "2001:false:0",
    )
  }
}

///|
test "empty Set forEach validates callback before bounded iteration" {
  let source =
    #|function invalidEmptySetCallback() {
    #|  var empty = new Set();
    #|  try { empty.forEach({}); }
    #|  catch (error) {
    #|    return error instanceof TypeError ? "TypeError:" + error.message : "other";
    #|  }
    #|  return "no-error";
    #|}
    #|invalidEmptySetCallback();
  let interp = @interpreter.new_interpreter()
  let actual = interp.with_execution_policy(keyed_collection_policy_972(100L), () => {
    interp.run(@parser.parse(source).stmts).to_string()
  }) catch {
    error =>
      fail(
        "empty Set invalid callback was not checked first: " + error.to_string(),
      )
  }
  assert_eq(actual, "TypeError:callbackfn is not callable")
}

///|
test "Set iterator tombstone probes stop before cursor advance" {
  let interp = @interpreter.new_interpreter()
  ignore(interp.run(@parser.parse(keyed_collection_setup_source_972()).stmts))
  let policy = keyed_collection_policy_972(1000L)
  let caught : Error? = interp.with_execution_policy(policy, () => {
    try {
      ignore(interp.run(@parser.parse("nextAfterTombstones();").stmts))
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
    None =>
      fail("Set iterator tombstone scan completed without observing progress")
  }
  assert_eq(
    interp.run(@parser.parse("nextAfterTombstones();").stmts).to_string(),
    "2000",
  )
}

///|
test "candidate Set iterator rejection preserves the first live value" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(interp, keyed_collection_setup_source_972()),
  )
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let caught : Error? = interp.with_execution_policy(
    keyed_collection_policy_972(1000L),
    () => {
      try {
        ignore(
          run_candidate_program_with_recorder(
            interp,
            @parser.parse("nextAfterTombstones();").stmts,
            evidence,
          ),
        )
        None
      } catch {
        error => Some(error)
      }
    },
  )
  match caught {
    Some(error) =>
      assert_eq(
        @runtime.execution_control_failure_code(error),
        Some("execution-limit"),
      )
    None => fail("candidate Set iterator tombstone scan completed")
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  assert_eq(
    interp.run(@parser.parse("nextAfterTombstones();").stmts).to_string(),
    "2000",
  )
}

///|
fn keyed_collection_semantics_source_972() -> String {
  (
    #|function snapshot() {
    #|  var m = new Map([[1, "a"], [2, "b"]]);
    #|  var mapSeen = [];
    #|  m.forEach(function(value, key) {
    #|    mapSeen.push(key);
    #|    if (key === 1) { m.delete(2); m.set(3, "c"); }
    #|  });
    #|  var s = new Set([1, 2]);
    #|  var setSeen = [];
    #|  s.forEach(function(value) {
    #|    setSeen.push(value);
    #|    if (value === 1) { s.delete(2); s.add(3); }
    #|  });
    #|  var nestedMapSeen = [];
    #|  var nestedMap = new Map([[1, 1], [2, 2]]);
    #|  nestedMap.forEach(function(value, key) {
    #|    nestedMapSeen.push(key);
    #|    if (key === 1) {
    #|      nestedMap.forEach(function(innerValue, innerKey) {
    #|        nestedMapSeen.push(innerKey + 10);
    #|      });
    #|    }
    #|  });
    #|  var nestedSetSeen = [];
    #|  var nestedSet = new Set([1, 2]);
    #|  nestedSet.forEach(function(value) {
    #|    nestedSetSeen.push(value);
    #|    if (value === 1) {
    #|      nestedSet.forEach(function(innerValue) {
    #|        nestedSetSeen.push(innerValue + 10);
    #|      });
    #|    }
    #|  });
    #|  var computedCalls = 0;
    #|  var computedMap = new Map();
    #|  var computedValue = computedMap.getOrInsertComputed("k", function(key) {
    #|    computedCalls = computedCalls + 1;
    #|    computedMap.set(key, "from-callback");
    #|    return "computed";
    #|  });
    #|  var nanMap = new Map();
    #|  nanMap.set(NaN, 1);
    #|  nanMap.set(-0, 2);
    #|  var nanSet = new Set([NaN, -0]);
    #|  var clearedMap = new Map([[1, 1], [2, 2]]);
    #|  clearedMap.clear();
    #|  var clearedSet = new Set([1, 2]);
    #|  clearedSet.clear();
    #|  return mapSeen.join(",") + "|" + m.get(3) + "|" + m.has(2) + "|" +
    #|    m.getOrInsert(3, "new") + "|" + computedValue + "|" +
    #|    computedCalls + "|" + computedMap.get("k") + "|" +
    #|    setSeen.join(",") + "|" + s.has(3) + "|" + s.size + "|" +
    #|    nestedMapSeen.join(",") + "|" + nestedSetSeen.join(",") + "|" +
    #|    nanMap.size + "|" + nanMap.get(NaN) + "|" + nanMap.get(0) + "|" +
    #|    nanSet.size + "|" + nanSet.has(-0) + "|" + nanSet.has(NaN) + "|" +
    #|    clearedMap.size + "|" + clearedSet.size;
    #|}
    #|snapshot();
  )
}

///|
test "direct Map and Set methods preserve live and canonical semantics" {
  let expected = "1,3|c|false|c|computed|1|computed|1,3|true|2|1,11,12,2|1,11,12,2|2|1|2|2|true|true|0|0"
  let source = keyed_collection_semantics_source_972()
  let unbounded = @interpreter.new_interpreter()
  let unbounded_actual = unbounded.run(@parser.parse(source).stmts).to_string() catch {
      error => fail("unbounded semantics run failed: " + error.to_string())
    }
  assert_eq(unbounded_actual, expected)
  let bounded_setup =
    #|var boundedMap = new Map([[1, "a"], [2, "b"]]);
    #|var boundedSet = new Set([1, 2]);
    #|function boundedSnapshot() {
    #|  var mapSeen = [];
    #|  boundedMap.forEach(function(value, key) {
    #|    mapSeen.push(key);
    #|    if (key === 1) { boundedMap.delete(2); boundedMap.set(3, "c"); }
    #|  });
    #|  var setSeen = [];
    #|  boundedSet.forEach(function(value) {
    #|    setSeen.push(value);
    #|    if (value === 1) { boundedSet.delete(2); boundedSet.add(3); }
    #|  });
    #|  return mapSeen.join(",") + "|" + boundedMap.has(2) + "|" +
    #|    boundedMap.size + "|" + setSeen.join(",") + "|" + boundedSet.has(3);
    #|}
  let bounded = @interpreter.new_interpreter()
  ignore(bounded.run(@parser.parse(bounded_setup).stmts))
  let actual = bounded.with_execution_policy(
    keyed_collection_policy_972(100000L),
    () => bounded.run(@parser.parse("boundedSnapshot();").stmts).to_string(),
  ) catch {
    error => {
      let code = match @runtime.execution_control_failure_code(error) {
        Some(value) => value
        None => "unknown"
      }
      fail("bounded semantics run failed: " + code + ": " + error.to_string())
    }
  }
  assert_eq(actual, "1,3|false|2|1,3|true")
}

///|
test "Map and Set forEach preserve branding and callback precedence" {
  let source =
    #|function snapshot() {
    #|  var mapBrand = "";
    #|  var setBrand = "";
    #|  var mapCallback = "";
    #|  var setCallback = "";
    #|  try { Map.prototype.forEach.call({}, function() {}); }
    #|  catch (error) { mapBrand = error.message; }
    #|  try { Set.prototype.forEach.call({}, function() {}); }
    #|  catch (error) { setBrand = error.message; }
    #|  try { new Map([[1, 1]]).forEach({}); }
    #|  catch (error) { mapCallback = error.message; }
    #|  try { new Set([1]).forEach({}); }
    #|  catch (error) { setCallback = error.message; }
    #|  return mapBrand + "|" + setBrand + "|" + mapCallback + "|" + setCallback;
    #|}
    #|snapshot();
  let interp = @interpreter.new_interpreter()
  assert_eq(
    interp.run(@parser.parse(source).stmts).to_string(),
    "Method Map.prototype.forEach called on incompatible receiver|Method Set.prototype.forEach called on incompatible receiver|callbackfn is not callable|callbackfn is not callable",
  )
}
