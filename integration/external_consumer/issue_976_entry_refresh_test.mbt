///|
fn issue_976_policy() -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      1000L,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid issue-976 execution policy")
  }
}

///|
test "JSON.parse stops bounded execution before native parsing" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976JsonText = '\"' + 'a'.repeat(100000) + '\"'; " +
    "function issue976ParseLarge() { return JSON.parse(issue976JsonText).length; }",
  )
  match
    engine.call_json_bounded(
      "issue976ParseLarge",
      [],
      issue_976_policy(),
    ) {
    Ok(_) => fail("JSON.parse silently bypassed bounded execution control")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "JSON.stringify stops bounded execution before native escaping" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976StringValue = 'a'.repeat(100000); " +
    "function issue976StringifyLarge() { " +
    "return JSON.stringify(issue976StringValue).length; }",
  )
  match
    engine.call_json_bounded(
      "issue976StringifyLarge",
      [],
      issue_976_policy(),
    ) {
    Ok(_) => fail("JSON.stringify silently bypassed bounded execution control")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "JSON.parse coerces input before the execution-control boundary" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976ParseEvents = ''; " +
    "var issue976PrebuiltParseText = '\"' + 'a'.repeat(100000) + '\"'; " +
    "var issue976ParseInput = { toString() { " +
    "issue976ParseEvents += 's'; return issue976PrebuiltParseText; } }; " +
    "function issue976ParsePrelude() { " +
    "return JSON.parse(issue976ParseInput, function() { " +
    "issue976ParseEvents += 'r'; return 0; }); } " +
    "function issue976ReadParseEvents() { return issue976ParseEvents; }",
  )
  let stopped = match
    engine.call_json_bounded(
      "issue976ParsePrelude",
      [],
      issue_976_policy(),
    ) {
    Ok(_) => false
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      true
    }
  }
  json_inspect(engine.call_json("issue976ReadParseEvents", []), content="s")
  assert_true(stopped)
}

///|
test "JSON.stringify runs root protocol before the execution-control boundary" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976StringifyEvents = ''; " +
    "var issue976PrebuiltStringValue = 'a'.repeat(100000); " +
    "var issue976Root = { toJSON() { issue976StringifyEvents += 't'; " +
    "return issue976PrebuiltStringValue; } }; " +
    "function issue976StringifyPrelude() { " +
    "return JSON.stringify(issue976Root, function(key, value) { " +
    "issue976StringifyEvents += 'r'; return value; }); } " +
    "function issue976ReadStringifyEvents() { return issue976StringifyEvents; }",
  )
  let stopped = match
    engine.call_json_bounded(
      "issue976StringifyPrelude",
      [],
      issue_976_policy(),
    ) {
    Ok(_) => false
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      true
    }
  }
  json_inspect(
    engine.call_json("issue976ReadStringifyEvents", []),
    content="tr",
  )
  assert_true(stopped)
}

///|
test "JSON.stringify replacer list stops before first element Get" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976ListEvents = ''; " +
    "var issue976ListTarget = ['x']; " +
    "var issue976List = new Proxy(issue976ListTarget, { get(t, k) { " +
    "if (k === 'length') issue976ListEvents += 'l'; " +
    "if (k === '0') issue976ListEvents += 'g'; return t[k]; } }); " +
    "var issue976ListRoot = { toJSON() { issue976ListEvents += 't'; " +
    "return { x: 1 }; } }; " +
    "function issue976StringifyList() { " +
    "return JSON.stringify(issue976ListRoot, issue976List); } " +
    "function issue976ReadListEvents() { return issue976ListEvents; }",
  )
  let stopped = match
    engine.call_json_bounded(
      "issue976StringifyList",
      [],
      issue_976_policy(),
    ) {
    Ok(_) => false
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      true
    }
  }
  json_inspect(engine.call_json("issue976ReadListEvents", []), content="l")
  assert_true(stopped)
}

///|
test "JSON.stringify trivial primitive remains bounded without native-progress control" {
  let engine = @js_engine.Engine()
  engine.eval("function issue976StringifyNumber() { return JSON.stringify(1); }")
  match
    engine.call_json_bounded(
      "issue976StringifyNumber",
      [],
      issue_976_policy(),
    ) {
    Ok(value) => json_inspect(value, content="1")
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "JSON.parse conversion throws before the execution-control boundary" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976BadParseInput = { toString() { throw new Error('input'); } }; " +
    "function issue976ParseConversionThrows() { " +
    "return JSON.parse(issue976BadParseInput); }",
  )
  match
    engine.call_json_bounded(
      "issue976ParseConversionThrows",
      [],
      issue_976_policy(),
    ) {
    Ok(_) => fail("JSON.parse conversion must precede execution control")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="javascript-exception")
  }
}

///|
test "JSON.parse rejection leaves the Engine reusable" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976ReusableParseText = 'a'.repeat(100000); " +
    "function issue976ParseReusableLarge() { " +
    "return JSON.parse('\"' + issue976ReusableParseText + '\"'); } " +
    "function issue976ParseReusableSmall() { return JSON.parse('3'); }",
  )
  match
    engine.call_json_bounded(
      "issue976ParseReusableLarge",
      [],
      issue_976_policy(),
    ) {
    Ok(_) => fail("large JSON.parse unexpectedly completed")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(
    engine.call_json("issue976ParseReusableSmall", []),
    content=3,
  )
}

///|
test "JSON.stringify root container stops bounded execution before traversal" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976LargeJsonArray = Array(100000); " +
    "function issue976StringifyContainer() { " +
    "return JSON.stringify(issue976LargeJsonArray); }",
  )
  match
    engine.call_json_bounded(
      "issue976StringifyContainer",
      [],
      issue_976_policy(),
    ) {
    Ok(_) => fail("JSON.stringify container traversal bypassed bounded execution control")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
}

///|
test "JSON.stringify empty replacer list keeps its fast path" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976EmptyListEvents = ''; " +
    "var issue976EmptyListRoot = { toJSON() { " +
    "issue976EmptyListEvents += 't'; return 1; } }; " +
    "function issue976EmptyListStringify() { " +
    "return JSON.stringify(issue976EmptyListRoot, []); } " +
    "function issue976ReadEmptyListEvents() { return issue976EmptyListEvents; }",
  )
  match
    engine.call_json_bounded(
      "issue976EmptyListStringify",
      [],
      issue_976_policy(),
    ) {
    Ok(value) => json_inspect(value, content="1")
    Err(diagnostic) => fail(diagnostic.message())
  }
  json_inspect(
    engine.call_json("issue976ReadEmptyListEvents", []),
    content="t",
  )
}
