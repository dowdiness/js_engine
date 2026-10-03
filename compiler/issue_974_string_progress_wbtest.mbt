///|
fn issue974_native_string_object(
  name : String,
  calls : Ref[Int],
  result : String,
) -> Value {
  let to_string : Value = Value::Object({
    bag: PropertyBag::PropertyBag(),
    prototype: Value::Null,
    callable: Some(
      Callable::NonConstructableCallable(name, fn(_args) {
        calls.val += 1
        Value::String_(result)
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
  let bag = PropertyBag::PropertyBag()
  bag.properties["toString"] = to_string
  Value::Object({
    bag,
    prototype: Value::Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
test "candidate String.concat observes output code units" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(
      interp,
      "var large = \"a\".repeat(5000); " +
      "function concatLarge() { return large.concat(\"\"); }",
    ),
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let caught : Error? = interp.with_execution_policy(policy, () => {
    try {
      ignore(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse("concatLarge();").stmts,
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
      match @runtime.execution_control_failure_code(error) {
        Some("execution-limit") => ()
        _ => fail("large String.concat raised the wrong error")
      }
    None => fail("large String.concat must be interruptible")
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate String.concat coerces a throwing first argument before output" {
  let interp = @interpreter.new_interpreter()
  let first_calls : Ref[Int] = { val: 0, }
  let throwing_to_string : Value = Value::Object({
    bag: PropertyBag::PropertyBag(),
    prototype: Value::Null,
    callable: Some(
      Callable::NonConstructableCallable("issue-974-concat-throwing-toString", fn(
        _args,
      ) raise {
        first_calls.val += 1
        @runtime.raise_js_exception(Value::String_("concat-first-arg"))
        Value::Undefined
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
  let first_arg : Value = Value::Object({
    bag: {
      let bag = PropertyBag::PropertyBag()
      bag.properties["toString"] = throwing_to_string
      bag
    },
    prototype: Value::Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  interp.global.def_builtin("issue974ConcatThrowingArg", first_arg)
  ignore(
    run_executor_neutral_bytecode(
      interp,
      "var issue974ConcatLarge = 'a'.repeat(5000); " +
      "function concatThrowingFirst() { " +
      "return issue974ConcatLarge.concat(issue974ConcatThrowingArg); }",
    ),
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid concat coercion policy")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let caught : Error? = interp.with_execution_policy(policy, () => {
    try {
      ignore(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse("concatThrowingFirst();").stmts,
          evidence,
        ),
      )
      None
    } catch {
      error => Some(error)
    }
  })
  match caught {
    Some(@runtime.JsException(value)) =>
      assert_eq(value.to_string(), "concat-first-arg")
    Some(error) => fail("first concat coercion raised " + error.to_string())
    None => fail("throwing first concat coercion unexpectedly completed")
  }
  assert_eq(first_calls.val, 1)
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate String.concat interleaves host coercion and output" {
  let interp = @interpreter.new_interpreter()
  let first_calls : Ref[Int] = { val: 0, }
  let later_calls : Ref[Int] = { val: 0, }
  interp.global.def_builtin(
    "issue974ConcatFirstHostArg",
    issue974_native_string_object(
      "issue-974-concat-first-host-toString", first_calls, "first",
    ),
  )
  interp.global.def_builtin(
    "issue974ConcatLaterHostArg",
    issue974_native_string_object(
      "issue-974-concat-later-host-toString", later_calls, "later",
    ),
  )
  ignore(
    run_executor_neutral_bytecode(
      interp,
      "var issue974ConcatInterleaveLarge = 'a'.repeat(5000); " +
      "function concatHostOrder() { return " +
      "issue974ConcatInterleaveLarge.concat(" +
      "issue974ConcatFirstHostArg, issue974ConcatLaterHostArg); }",
    ),
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid concat interleaving policy")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let caught : Error? = interp.with_execution_policy(policy, () => {
    try {
      ignore(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse("concatHostOrder();").stmts,
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
    None => fail("long concat unexpectedly completed")
  }
  assert_eq(first_calls.val, 1)
  assert_eq(later_calls.val, 0)
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
fn assert_issue974_true(
  interp : @runtime.Interpreter,
  source : String,
) -> Unit raise Error {
  let result = run_executor_neutral_bytecode(interp, source)
  assert_eq(result.to_string(), "true")
}

///|
test "String progress preserves UTF-16 and selected output ranges" {
  let interp = @interpreter.new_interpreter()
  assert_issue974_true(
    interp,
    "var pair = String.fromCharCode(0xD83D, 0xDE00); " +
    "var lone = String.fromCharCode(0xD800); " +
    "pair.length === 2 && " +
    "pair.charAt(0) === String.fromCharCode(0xD83D) && " +
    "pair.charCodeAt(1) === 0xDE00 && " +
    "pair.codePointAt(0) === 0x1F600 && " +
    "pair.codePointAt(1) === 0xDE00 && " +
    "pair.at(-1) === String.fromCharCode(0xDE00) && " +
    "lone.isWellFormed() === false && " +
    "lone.toWellFormed() === String.fromCharCode(0xFFFD) && " +
    "pair.slice(1) === String.fromCharCode(0xDE00);",
  )
}

///|
test "String progress consumers preserve ordinary results" {
  let interp = @interpreter.new_interpreter()
  assert_issue974_true(
    interp,
    "var whitespace = String.fromCharCode(0x20, 0x09); " +
    "whitespace + 'Abc' + String.fromCharCode(0x0A); " +
    "'Abc'.concat('!') === 'Abc!' && " +
    "'abcdef'.slice(1, 3) === 'bc' && " +
    "'abcdef'.substring(4, 1) === 'bcd' && " +
    "'abcdef'.substr(1, 2) === 'bc' && " +
    "'Abc'.toLowerCase() === 'abc' && " +
    "'abc'.toUpperCase() === 'ABC' && " +
    "'Abc'.toLocaleLowerCase() === 'abc' && " +
    "'abc'.toLocaleUpperCase() === 'ABC' && " +
    "(whitespace + 'Abc' + String.fromCharCode(0x0A)).trim() === 'Abc' && " +
    "(whitespace + 'Abc' + String.fromCharCode(0x0A)).trimStart() === " +
    "'Abc' + String.fromCharCode(0x0A) && " +
    "(whitespace + 'Abc' + String.fromCharCode(0x0A)).trimEnd() === " +
    "String.fromCharCode(0x20, 0x09) + 'Abc' && " +
    "(whitespace + 'Abc' + String.fromCharCode(0x0A)).trimLeft() === " +
    "'Abc' + String.fromCharCode(0x0A) && " +
    "(whitespace + 'Abc' + String.fromCharCode(0x0A)).trimRight() === " +
    "String.fromCharCode(0x20, 0x09) + 'Abc' && " +
    "'a,b'.split(',')[1] === 'b' && " +
    "'a-b-a'.replace('a', 'x') === 'x-b-a' && " +
    "'a-b-a'.replaceAll('a', 'x') === 'x-b-x' && " +
    "'abc'.padStart(5, '0') === '00abc' && " +
    "'abc'.padEnd(5, '0') === 'abc00';",
  )
}

///|
test "String progress observes expanded Annex B HTML output" {
  let interp = @interpreter.new_interpreter(annex_b=true)
  assert_issue974_true(
    interp,
    "var quote = String.fromCharCode(34); " +
    "'x'.anchor(quote) === '<a name=\"&quot;\">x</a>' && " +
    "'x'.fontcolor(quote) === '<font color=\"&quot;\">x</font>' && " +
    "'x'.link(quote) === '<a href=\"&quot;\">x</a>';",
  )
}

///|
test "String replace keeps protocol, coercion, and callback precedence" {
  let interp = @interpreter.new_interpreter()
  assert_issue974_true(
    interp,
    "var calls = 0; " +
    "var hook = {}; " +
    "hook[Symbol.replace] = function(value, replacement) { calls += 1; return 'hook'; }; " +
    "var callbackThrew = false; " +
    "try { 'abc'.replace('a', function() { throw new Error('callback'); }); } " +
    "catch (error) { callbackThrew = true; } " +
    "'abc'.replace(hook, 'x') === 'hook' && calls === 1 && callbackThrew;",
  )
}

///|
test "String progress keeps empty and invalid fast paths" {
  let interp = @interpreter.new_interpreter()
  assert_issue974_true(
    interp,
    "var empty = ''; " +
    "var invalid = false; " +
    "try { 'abc'.replaceAll(/a/, 'x'); } catch (error) { invalid = true; } " +
    "empty.concat() === '' && " +
    "'abc'.slice(99) === '' && " +
    "'abc'.substring(99) === '' && " +
    "'abc'.substr(0, 0) === '' && " +
    "'abc'.padStart(3, 'x') === 'abc' && " +
    "invalid;",
  )
}

///|
test "candidate String selected access stays bounded on a huge input" {
  let interp = @interpreter.new_interpreter()
  ignore(
    run_executor_neutral_bytecode(
      interp,
      "var issue974Huge = 'a'.repeat(100000); " +
      "function selectedRead() { return issue974Huge.charAt(99999); } " +
      "function selectedCode() { return issue974Huge.codePointAt(0); } " +
      "function selectedRange() { return issue974Huge.slice(99997, 100000); }",
    ),
  )
  for
    (call_source, expected) in [
      ("selectedRead();", "a"),
      ("selectedCode();", "97"),
      ("selectedRange();", "aaa"),
    ] {
    let policy = match
      @runtime.ExecutionPolicy::new(500L, 100L, @runtime.InterruptionHandle()) {
      Ok(policy) => policy
      Err(_) => fail("expected a valid selected-access policy")
    }
    let evidence : Ref[CandidateRouteEvidence] = {
      val: CandidateRouteEvidence(trace=true),
    }
    let outcome : Result[@runtime.Value, Error] = Ok(
      interp.with_execution_policy(policy, () => {
        run_candidate_program_with_recorder(
          interp,
          @parser.parse(call_source).stmts,
          evidence,
        )
      }),
    ) catch {
      error => Err(error)
    }
    match outcome {
      Ok(result) => assert_eq(result.to_string(), expected)
      Err(_) =>
        fail("selected String access exceeded its bounded work: " + call_source)
    }
    assert_true(evidence.val.summary.bytecode_starts > 0)
    assert_eq(evidence.val.summary.tree_starts, 0)
    assert_eq(evidence.val.summary.fallback_violations, 0)
    assert_eq(evidence.val.summary.replay_violations, 0)
    assert_eq(evidence.val.summary.active_activations, 0)
  }
}

///|
test "candidate String replace observes native callback boundary" {
  let interp = @interpreter.new_interpreter()
  let callback_calls : Ref[Int] = { val: 0, }
  let native_callback : Value = Value::Object({
    bag: PropertyBag::PropertyBag(),
    prototype: Value::Null,
    callable: Some(
      Callable::NonConstructableCallable("issue-974-native-replace", fn(_args) {
        callback_calls.val += 1
        Value::String_("x")
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
  interp.global.def_builtin("issue974NativeReplace", native_callback)
  ignore(
    run_executor_neutral_bytecode(
      interp,
      "var issue974ReplaceLarge = 'a'.repeat(2000) + 'z'; " +
      "function replaceLate() { return issue974ReplaceLarge.replace('z', issue974NativeReplace); }",
    ),
  )
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid callback policy")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let caught : Error? = interp.with_execution_policy(policy, () => {
    try {
      ignore(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse("replaceLate();").stmts,
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
        "native replacement callback must be preceded by bounded prefix work",
      )
  }
  assert_eq(callback_calls.val, 0)
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
fn assert_issue974_bounded_call(
  interp : @runtime.Interpreter,
  call_source : String,
) -> Unit raise Error {
  let policy = match
    @runtime.ExecutionPolicy::new(1000L, 100L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid String progress policy")
  }
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
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
      match @runtime.execution_control_failure_code(error) {
        Some("execution-limit") => ()
        _ => fail("long String consumer raised the wrong error: " + call_source)
      }
    None =>
      fail(
        "long String consumer completed without an execution limit: " +
        call_source,
      )
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate String consumers stop bounded input and output work" {
  let interp = @interpreter.new_interpreter(annex_b=true)
  ignore(
    run_executor_neutral_bytecode(
      interp,
      "var issue974Large = 'a'.repeat(2000); " +
      "var issue974TrimLarge = ' '.repeat(2000) + 'a'; " +
      "function sliceLarge() { return issue974Large.slice(0, 2000); } " +
      "function substringLarge() { return issue974Large.substring(0, 2000); } " +
      "function substrLarge() { return issue974Large.substr(0, 2000); } " +
      "function lowerLarge() { return issue974Large.toLowerCase(); } " +
      "function trimLarge() { return issue974TrimLarge.trim(); } " +
      "function splitLarge() { return issue974Large.split('z'); } " +
      "function replaceLarge() { return issue974Large.replace('z', 'x'); } " +
      "function replaceAllLarge() { return issue974Large.replaceAll('a', 'x'); } " +
      "function padStartLarge() { return 'a'.padStart(3000, 'x'); } " +
      "function padEndLarge() { return 'a'.padEnd(3000, 'x'); } " +
      "function wellFormedLarge() { return issue974Large.isWellFormed(); } " +
      "function toWellFormedLarge() { return issue974Large.toWellFormed(); } " +
      "function htmlLarge() { return issue974Large.bold(); }",
    ),
  )
  for
    call_source in [
      "sliceLarge();", "substringLarge();", "substrLarge();", "lowerLarge();", "trimLarge();",
      "splitLarge();", "replaceLarge();", "replaceAllLarge();", "padStartLarge();",
      "padEndLarge();", "wellFormedLarge();", "toWellFormedLarge();", "htmlLarge();",
    ] {
    assert_issue974_bounded_call(interp, call_source)
  }
}
