///|
fn issue_976_candidate_policy() -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      1000L,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid candidate JSON execution policy")
  }
}

///|
test "candidate JSON.parse stops bounded execution before native parsing" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976CandidateJsonText = '\"' + 'a'.repeat(100000) + '\"'; " +
    "function issue976CandidateParseLarge() { " +
    "return JSON.parse(issue976CandidateJsonText); }",
  )
  match
    engine.call_json_bounded(
      "issue976CandidateParseLarge",
      [],
      issue_976_candidate_policy(),
    ) {
    Ok(_) => fail("candidate JSON.parse bypassed bounded execution control")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "candidate JSON.stringify stops bounded execution before native escaping" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976CandidateStringValue = 'a'.repeat(100000); " +
    "function issue976CandidateStringifyLarge() { " +
    "return JSON.stringify(issue976CandidateStringValue); }",
  )
  match
    engine.call_json_bounded(
      "issue976CandidateStringifyLarge",
      [],
      issue_976_candidate_policy(),
    ) {
    Ok(_) => fail("candidate JSON.stringify bypassed bounded execution control")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "candidate JSON.stringify preserves root protocol ordering before execution control" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976CandidateEvents = ''; " +
    "var issue976CandidateStringValue = 'a'.repeat(100000); " +
    "var issue976CandidateRoot = { toJSON() { issue976CandidateEvents += 't'; " +
    "return issue976CandidateStringValue; } }; " +
    "function issue976CandidateStringifyPrelude() { " +
    "return JSON.stringify(issue976CandidateRoot, function(key, value) { " +
    "issue976CandidateEvents += 'r'; return value; }); } " +
    "function issue976CandidateReadEvents() { return issue976CandidateEvents; }",
  )
  match
    engine.call_json_bounded(
      "issue976CandidateStringifyPrelude",
      [],
      issue_976_candidate_policy(),
    ) {
    Ok(_) =>
      fail("candidate root serialization bypassed bounded execution control")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(
    engine.call_json("issue976CandidateReadEvents", []),
    content="tr",
  )
}

///|
test "candidate JSON.stringify preserves revoked Proxy IsArray error precedence" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976CandidateProxyEvents = ''; " +
    "var issue976CandidateProxyRecord = Proxy.revocable([], { get(t, k) { " +
    "if (k === 'toJSON') issue976CandidateProxyEvents += 't'; " +
    "return t[k]; } }); " +
    "var issue976CandidateRootProxy = issue976CandidateProxyRecord.proxy; " +
    "function issue976CandidateRevokeRootProxy(key, value) { " +
    "if (key === '') { issue976CandidateProxyRecord.revoke(); " +
    "return issue976CandidateRootProxy; } return value; } " +
    "function issue976CandidateStringifyRevokedProxy() { " +
    "return JSON.stringify(issue976CandidateRootProxy, " +
    "issue976CandidateRevokeRootProxy); } " +
    "function issue976CandidateReadProxyEvents() { " +
    "return issue976CandidateProxyEvents; }",
  )
  match
    engine.call_json_bounded(
      "issue976CandidateStringifyRevokedProxy",
      [],
      issue_976_candidate_policy(),
    ) {
    Ok(_) => fail("candidate revoked Proxy must report its IsArray TypeError")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="javascript-exception")
  }
  json_inspect(
    engine.call_json("issue976CandidateReadProxyEvents", []),
    content="t",
  )
}

///|
test "candidate JSON.stringify treats callable Proxy as undefined without native progress" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976CandidateCallableProxy = new Proxy(function() {}, {}); " +
    "function issue976CandidateStringifyCallableProxy() { " +
    "return JSON.stringify(issue976CandidateCallableProxy); }",
  )
  match
    engine.call_json_bounded(
      "issue976CandidateStringifyCallableProxy",
      [],
      issue_976_candidate_policy(),
    ) {
    Ok(_) =>
      fail("candidate callable Proxy must not enter native JSON progress")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="json-conversion-error")
      inspect(diagnostic.phase_code(), content="result-conversion")
    }
  }
  let unbounded_kind = try {
    let _ = engine.call_json("issue976CandidateStringifyCallableProxy", [])
    "completed"
  } catch {
    @js_engine.JsonConversionError(_) => "json-conversion-error"
    _ => "other-error"
  }
  inspect(unbounded_kind, content="json-conversion-error")
}

///|
test "candidate JSON.stringify observes boxed String ToPrimitive before native escaping" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976CandidateBoxEvents = ''; " +
    "var issue976CandidateBoxReplacement = 'a'.repeat(100000); " +
    "var issue976CandidateBox = new String('original'); " +
    "issue976CandidateBox[Symbol.toPrimitive] = function(hint) { " +
    "issue976CandidateBoxEvents += hint; " +
    "return issue976CandidateBoxReplacement; }; " +
    "function issue976CandidateStringifyBox() { " +
    "return JSON.stringify(issue976CandidateBox); } " +
    "function issue976CandidateBoxUsesReplacement() { " +
    "return JSON.stringify(issue976CandidateBox) === " +
    "JSON.stringify(issue976CandidateBoxReplacement); } " +
    "function issue976CandidateReadBoxEvents() { " +
    "return issue976CandidateBoxEvents; } " +
    "var issue976CandidateThrowBox = new String('original'); " +
    "issue976CandidateThrowBox[Symbol.toPrimitive] = function(hint) { " +
    "issue976CandidateBoxEvents += hint; " +
    "throw new Error('boxed conversion'); }; " +
    "function issue976CandidateStringifyThrowBox() { " +
    "return JSON.stringify(issue976CandidateThrowBox); } " +
    "var issue976CandidateFallbackBoxEvents = ''; " +
    "var issue976CandidateFallbackBox = new String('original'); " +
    "issue976CandidateFallbackBox.toString = function() { " +
    "issue976CandidateFallbackBoxEvents += 't'; " +
    "return issue976CandidateBoxReplacement; }; " +
    "function issue976CandidateFallbackBoxUsesReplacement() { " +
    "return JSON.stringify(issue976CandidateFallbackBox) === " +
    "JSON.stringify(issue976CandidateBoxReplacement); } " +
    "function issue976CandidateReadFallbackBoxEvents() { " +
    "return issue976CandidateFallbackBoxEvents; }",
  )
  match
    engine.call_json_bounded(
      "issue976CandidateStringifyBox",
      [],
      issue_976_candidate_policy(),
    ) {
    Ok(_) =>
      fail("candidate boxed String replacement must reach execution control")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(
    engine.call_json("issue976CandidateReadBoxEvents", []),
    content="string",
  )
  json_inspect(
    engine.call_json("issue976CandidateBoxUsesReplacement", []),
    content=true,
  )
  match
    engine.call_json_bounded(
      "issue976CandidateStringifyThrowBox",
      [],
      issue_976_candidate_policy(),
    ) {
    Ok(_) =>
      fail("candidate boxed String conversion throw must precede control")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="javascript-exception")
  }
  json_inspect(
    engine.call_json("issue976CandidateReadBoxEvents", []),
    content="stringstringstring",
  )
  json_inspect(
    engine.call_json("issue976CandidateFallbackBoxUsesReplacement", []),
    content=true,
  )
  json_inspect(
    engine.call_json("issue976CandidateReadFallbackBoxEvents", []),
    content="t",
  )
}

///|
test "candidate JSON.stringify trivial primitive remains bounded" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function issue976CandidateStringifyNumber() { return JSON.stringify(1); }",
  )
  match
    engine.call_json_bounded(
      "issue976CandidateStringifyNumber",
      [],
      issue_976_candidate_policy(),
    ) {
    Ok(value) => json_inspect(value, content="1")
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "candidate JSON.parse execution-control stop leaves the Engine reusable" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976CandidateReusableText = '\"' + 'a'.repeat(100000) + '\"'; " +
    "function issue976CandidateParseReusableLarge() { " +
    "return JSON.parse(issue976CandidateReusableText); } " +
    "function issue976CandidateParseReusableSmall() { return JSON.parse('3'); }",
  )
  match
    engine.call_json_bounded(
      "issue976CandidateParseReusableLarge",
      [],
      issue_976_candidate_policy(),
    ) {
    Ok(_) => fail("candidate JSON.parse unexpectedly completed")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(
    engine.call_json("issue976CandidateParseReusableSmall", []),
    content=3,
  )
}

///|
test "candidate JSON.stringify replacer list stops after length and before first Get" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976CandidateListEvents = ''; " +
    "var issue976CandidateListTarget = ['x']; " +
    "var issue976CandidateList = new Proxy(issue976CandidateListTarget, { get(t, k) { " +
    "if (k === 'length') issue976CandidateListEvents += 'l'; " +
    "if (k === '0') issue976CandidateListEvents += 'g'; return t[k]; } }); " +
    "var issue976CandidateListRoot = { toJSON() { " +
    "issue976CandidateListEvents += 't'; return { x: 1 }; } }; " +
    "function issue976CandidateStringifyList() { " +
    "return JSON.stringify(issue976CandidateListRoot, issue976CandidateList); } " +
    "function issue976CandidateReadListEvents() { " +
    "return issue976CandidateListEvents; }",
  )
  match
    engine.call_json_bounded(
      "issue976CandidateStringifyList",
      [],
      issue_976_candidate_policy(),
    ) {
    Ok(_) => fail("candidate replacer-list traversal unexpectedly completed")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
  }
  json_inspect(
    engine.call_json("issue976CandidateReadListEvents", []),
    content="l",
  )
}

///|
test "candidate JSON.parse conversion throws before execution control" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue976CandidateBadParseInput = { " +
    "toString() { throw new Error('input'); } }; " +
    "function issue976CandidateParseConversionThrows() { " +
    "return JSON.parse(issue976CandidateBadParseInput); }",
  )
  match
    engine.call_json_bounded(
      "issue976CandidateParseConversionThrows",
      [],
      issue_976_candidate_policy(),
    ) {
    Ok(_) =>
      fail("candidate JSON.parse conversion must precede execution control")
    Err(diagnostic) =>
      inspect(diagnostic.failure_kind_code(), content="javascript-exception")
  }
}
