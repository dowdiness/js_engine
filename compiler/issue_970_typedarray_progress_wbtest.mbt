///|
test "RED: candidate TypedArray.includes must charge each logical element" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(
      interp,
      "var large = new Uint8Array(5000); " +
      "function missing() { return large.includes(255); }",
    ),
  )
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid TypedArray execution policy")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let outcome : Result[@runtime.Value, Error] = interp.with_execution_policy(
    policy,
    () => {
      Ok(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse("missing();").stmts,
          evidence,
        ),
      ) catch {
        error => Err(error)
      }
    },
  )
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  match outcome {
    Err(error) =>
      assert_eq(
        @runtime.execution_control_failure_code(error),
        Some("execution-limit"),
      )
    Ok(value) => fail("TypedArray.includes completed with " + value.to_string())
  }
}

///|
fn issue970_assert_execution_limit(
  interp : @interpreter.Interpreter,
  call_source : String,
) -> Unit raise Error {
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid TypedArray execution policy")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let outcome : Result[@runtime.Value, Error] = interp.with_execution_policy(
    policy,
    () => {
      Ok(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse(call_source).stmts,
          evidence,
        ),
      ) catch {
        error => Err(error)
      }
    },
  )
  match outcome {
    Err(error) => {
      assert_eq(
        @runtime.execution_control_failure_code(error),
        Some("execution-limit"),
      )
      assert_true(evidence.val.summary.bytecode_starts > 0)
      assert_eq(evidence.val.summary.tree_starts, 0)
    }
    Ok(_) =>
      fail(
        "candidate TypedArray consumer completed under element budget: " +
        call_source,
      )
  }
}

///|
fn issue970_assert_precondition_error(
  interp : @interpreter.Interpreter,
  call_source : String,
) -> Unit raise Error {
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid precondition policy")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let outcome : Result[@runtime.Value, Error] = interp.with_execution_policy(
    policy,
    () => {
      Ok(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse(call_source).stmts,
          evidence,
        ),
      ) catch {
        error => Err(error)
      }
    },
  )
  match outcome {
    Err(error) => {
      assert_eq(@runtime.execution_control_failure_code(error), None)
      assert_true(evidence.val.summary.bytecode_starts > 0)
      assert_eq(evidence.val.summary.tree_starts, 0)
    }
    Ok(value) =>
      fail("TypedArray precondition unexpectedly returned " + value.to_string())
  }
}

///|
test "candidate TypedArray consumers charge logical work units" {
  let interp = @interpreter.new_interpreter()
  let setup_source =
    #|var large = new Uint8Array(5000);
    #|var target = new Uint8Array(5000);
    #|var arraylike = { length: 5000 };
    #|function setTyped(){ target.set(large); }
    #|function setArrayLike(){ target.set(arraylike); }
    #|function sliceLarge(){ return large.slice(); }
    #|function copyLarge(){ return large.copyWithin(0, 1); }
    #|function fillLarge(){ return large.fill(1); }
    #|function indexLarge(){ return large.indexOf(255); }
    #|function lastIndexLarge(){ return large.lastIndexOf(255); }
    #|function includesLarge(){ return large.includes(255); }
    #|function joinLarge(){ return large.join(); }
    #|function toStringLarge(){ return large.toString(); }
    #|function localeLarge(){ return large.toLocaleString(); }
    #|function reverseLarge(){ return large.reverse(); }
    #|function forEachLarge(){ large.forEach(function(){ }); }
    #|function mapLarge(){ return large.map(function(x){ return x; }); }
    #|function filterLarge(){ return large.filter(function(){ return true; }); }
    #|function reduceLarge(){ return large.reduce(function(a, x){ return a + x; }, 0); }
    #|function reduceRightLarge(){ return large.reduceRight(function(a, x){ return a + x; }, 0); }
    #|function everyLarge(){ return large.every(function(){ return true; }); }
    #|function someLarge(){ return large.some(function(){ return false; }); }
    #|function findLarge(){ return large.find(function(){ return false; }); }
    #|function findIndexLarge(){ return large.findIndex(function(){ return false; }); }
    #|function findLastLarge(){ return large.findLast(function(){ return false; }); }
    #|function findLastIndexLarge(){ return large.findLastIndex(function(){ return false; }); }
    #|function reversedLarge(){ return large.toReversed(); }
    #|function withLarge(){ return large.with(0, 1); }
    #|function fromArrayLike(){ return Uint8Array.from(arraylike); }
    #|function fromArrayLikeMapped(){ return Uint8Array.from(arraylike, function(x){ return x; }); }
    #|function constructArrayLike(){ return new Uint8Array(arraylike); }
  ignore(run_executor_neutral_bytecode(interp, setup_source))
  let calls = [
    "setTyped();", "setArrayLike();", "sliceLarge();", "copyLarge();", "fillLarge();",
    "indexLarge();", "lastIndexLarge();", "includesLarge();", "joinLarge();", "toStringLarge();",
    "localeLarge();", "reverseLarge();", "forEachLarge();", "mapLarge();", "filterLarge();",
    "reduceLarge();", "reduceRightLarge();", "everyLarge();", "someLarge();", "findLarge();",
    "findIndexLarge();", "findLastLarge();", "findLastIndexLarge();", "reversedLarge();",
    "withLarge();", "fromArrayLike();", "fromArrayLikeMapped();", "constructArrayLike();",
  ]
  for call_source in calls {
    issue970_assert_execution_limit(interp, call_source)
  }
}

///|
test "candidate TypedArray consumers preserve bounded and unbounded values" {
  let source =
    #|var small = new Uint8Array([1, 2, 3]);
    #|var arraylike = { 0: 7, 1: 8, 2: 9, length: 3 };
    #|var target = new Uint8Array(3);
    #|target.set(arraylike);
    #|var from = Uint8Array.from(arraylike);
    #|var constructed = new Uint8Array(arraylike);
    #|var mapped = small.map(function(x){ return x + 1; });
    #|var reversed = small.toReversed();
    #|var replaced = small.with(1, 9);
    #|var filtered = small.filter(function(x){ return x > 1; });
    #|var reduced = small.reduce(function(a, x){ return a + x; }, 0);
    #|var made = Uint8Array.of(4, 5, 6);
    #|[
    #|  target.join('-'), from.join('-'), constructed.join('-'),
    #|  mapped.join('-'), reversed.join('-'), replaced.join('-'),
    #|  filtered.join('-'), reduced, made.join('-')
    #|].join('|');
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(
    value.to_string(),
    "7-8-9|7-8-9|7-8-9|2-3-4|3-2-1|1-9-3|2-3|6|4-5-6",
  )
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate TypedArray preconditions run before element work" {
  let interp = @interpreter.new_interpreter()
  let setup_source =
    #|var large = new Uint8Array(5000);
    #|function badBrand(){ return Uint8Array.prototype.includes.call({}, 1); }
    #|function badForEach(){ return large.forEach(1); }
    #|function badEvery(){ return large.every(1); }
    #|function badSome(){ return large.some(1); }
    #|function badIndex(){
    #|  return large.includes(1, { valueOf: function(){ throw new Error('coercion'); } });
    #|}
    #|function badSpecies(){
    #|  large.constructor = { [Symbol.species]: 1 };
    #|  return large.slice();
    #|}
    #|function badDetach(){
    #|  var buffer = new ArrayBuffer(8);
    #|  var view = new Uint8Array(buffer);
    #|  $262.detachArrayBuffer(buffer);
    #|  return view.includes(1);
    #|}
  ignore(run_executor_neutral_bytecode(interp, setup_source))
  let calls = [
    "badBrand();", "badForEach();", "badEvery();", "badSome();", "badIndex();", "badSpecies();",
    "badDetach();",
  ]
  for call_source in calls {
    issue970_assert_precondition_error(interp, call_source)
  }
}

///|
test "candidate TypedArray native callbacks stop at the execution boundary" {
  let interp = @interpreter.new_interpreter()
  let trace : Ref[Array[Int]] = { val: [], }
  interp.global.def_builtin(
    "issue970NativeCallback",
    @runtime.make_native_func(name="issue970NativeCallback", args => {
      match args[1] {
        @runtime.Value::Number(index) => trace.val.push(index.to_int())
        _ => ()
      }
      @runtime.Value::Undefined
    }),
  )
  let setup_source =
    #|var large = new Uint8Array(5000);
    #|function callbackRun(){ return large.forEach(issue970NativeCallback); }
  ignore(run_executor_neutral_bytecode(interp, setup_source))
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid native callback policy")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let outcome : Result[@runtime.Value, Error] = interp.with_execution_policy(
    policy,
    () => {
      Ok(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse("callbackRun();").stmts,
          evidence,
        ),
      ) catch {
        error => Err(error)
      }
    },
  )
  match outcome {
    Err(error) =>
      assert_eq(
        @runtime.execution_control_failure_code(error),
        Some("execution-limit"),
      )
    Ok(_) => fail("native callback traversal completed under element budget")
  }
  assert_true(trace.val.length() > 0)
  assert_true(trace.val.length() < 5000)
  let mut expected = 0
  for index in trace.val {
    assert_eq(index, expected)
    expected += 1
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "TypedArray.of charges each logical result write" {
  let interp = @interpreter.new_interpreter()
  let ctor = interp.global.get("Uint8Array")
  let of_fn = interp.get_property(ctor, "of", @token.Loc::default())
  let args : Array[@runtime.Value] = Array::makei(5000, _ => {
    @runtime.Value::Number(0.0)
  })
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid TypedArray.of policy")
  }
  let outcome : Result[@runtime.Value, Error] = interp.with_execution_policy(
    policy,
    () => {
      Ok(interp.call_value(of_fn, ctor, args, @token.Loc::default())) catch {
        error => Err(error)
      }
    },
  )
  match outcome {
    Err(error) =>
      assert_eq(
        @runtime.execution_control_failure_code(error),
        Some("execution-limit"),
      )
    Ok(_) => fail("TypedArray.of completed under element budget")
  }
}

///|
test "candidate TypedArray arraylike reads stop before the sentinel" {
  let interp = @interpreter.new_interpreter()
  let setup_source =
    #|var touched = 0;
    #|var source = { length: 5000 };
    #|var target = new Uint8Array(5000);
    #|Object.defineProperty(source, "4999", {
    #|  get: function(){ touched = touched + 1; return 1; }
    #|});
    #|function readArrayLike(){ target.set(source); }
  ignore(run_executor_neutral_bytecode(interp, setup_source))
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid sentinel policy")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let outcome : Result[@runtime.Value, Error] = interp.with_execution_policy(
    policy,
    () => {
      Ok(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse("readArrayLike();").stmts,
          evidence,
        ),
      ) catch {
        error => Err(error)
      }
    },
  )
  match outcome {
    Err(error) =>
      assert_eq(
        @runtime.execution_control_failure_code(error),
        Some("execution-limit"),
      )
    Ok(_) => fail("arraylike read completed under element budget")
  }
  assert_eq(interp.global.get("touched").to_string(), "0")
}
