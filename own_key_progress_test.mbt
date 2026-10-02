///|
test "own-key materialization respects the bounded call budget" {
  let engine = @js_engine.Engine()
  let source =
    #|var source = {};
    #|for (var i = 0; i < 5000; i++) source["key" + i] = i;
    #|function enumerate() { return Reflect.ownKeys(source).length; }
  engine.eval(source)
  let policy = match
    @js_engine.ExecutionPolicy::new(
      1000L,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  match engine.call_json_bounded("enumerate", [], policy) {
    Ok(result) =>
      fail("own-key materialization completed: " + result.stringify())
    Err(diagnostic) => {
      assert_eq(diagnostic.failure_kind_code(), "execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
fn own_key_consumer_policy() -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      1000L,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid own-key consumer policy")
  }
}

///|
test "public own-key consumers expose bounded progress across prepared sources" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|function makeLargeObject() {
      #|  var result = {};
      #|  for (var i = 0; i < 5000; i++) result["key" + i] = i;
      #|  return result;
      #|}
      #|function makeDefinitions() {
      #|  var result = {};
      #|  for (var i = 0; i < 5000; i++) result["key" + i] = {
      #|    value: i, enumerable: true, configurable: true, writable: true
      #|  };
      #|  return result;
      #|}
      #|function makeSymbolObject() {
      #|  var result = {};
      #|  for (var i = 0; i < 2000; i++) result[Symbol("symbol" + i)] = i;
      #|  return result;
      #|}
      #|var source = makeLargeObject();
      #|var definitions = makeDefinitions();
      #|var symbolSource = makeSymbolObject();
      #|var sparseSource = new Array(5000);
      #|sparseSource[4999] = 1;
      #|var asciiSource = "a".repeat(5000);
      #|var typedSource = new Uint8Array(5000);
      #|var freezeTarget = makeLargeObject();
      #|var sealTarget = makeLargeObject();
      #|var frozenTarget = makeLargeObject();
      #|var sealedTarget = makeLargeObject();
      #|Object.freeze(frozenTarget);
      #|Object.seal(sealedTarget);
      #|function keysLarge() { return Object.keys(source).length; }
      #|function valuesLarge() { return Object.values(source).length; }
      #|function entriesLarge() { return Object.entries(source).length; }
      #|function ownNamesLarge() { return Object.getOwnPropertyNames(source).length; }
      #|function ownSymbolsLarge() { return Object.getOwnPropertySymbols(symbolSource).length; }
      #|function descriptorsLarge() {
      #|  return Object.getOwnPropertyNames(Object.getOwnPropertyDescriptors(source)).length;
      #|}
      #|function definePropertiesLarge() {
      #|  var target = {};
      #|  Object.defineProperties(target, definitions);
      #|  return target.key4999;
      #|}
      #|function assignLarge() {
      #|  var target = {};
      #|  Object.assign(target, source);
      #|  return target.key4999;
      #|}
      #|function enumerateLarge() { return Reflect.ownKeys(source).length; }
      #|function restLarge() {
      #|  var { ...copy } = source;
      #|  return copy.key4999;
      #|}
      #|function spreadLarge() {
      #|  var copy = { ...source };
      #|  return copy.key4999;
      #|}
      #|function forInLarge() {
      #|  for (var key in source) return 1;
      #|  return 0;
      #|}
      #|function freezeLarge() { return Object.freeze(freezeTarget) === freezeTarget; }
      #|function sealLarge() { return Object.seal(sealTarget) === sealTarget; }
      #|function isFrozenLarge() { return Object.isFrozen(frozenTarget); }
      #|function isSealedLarge() { return Object.isSealed(sealedTarget); }
      #|function sparseOwnKeysLarge() { return Reflect.ownKeys(sparseSource).length; }
      #|function asciiNamesLarge() { return Object.getOwnPropertyNames(asciiSource).length; }
      #|function typedOwnKeysLarge() { return Reflect.ownKeys(typedSource).length; }
      #|function afterOwnKeyLimit() { return 1; }
    ),
  )
  json_inspect(engine.call_json("enumerateLarge", []), content=5000)
  let cases = [
    ("keys", "keysLarge"),
    ("values", "valuesLarge"),
    ("entries", "entriesLarge"),
    ("own-names", "ownNamesLarge"),
    ("own-symbols", "ownSymbolsLarge"),
    ("descriptors", "descriptorsLarge"),
    ("define-properties", "definePropertiesLarge"),
    ("assign", "assignLarge"),
    ("reflect-own-keys", "enumerateLarge"),
    ("rest", "restLarge"),
    ("spread", "spreadLarge"),
    ("for-in", "forInLarge"),
    ("freeze", "freezeLarge"),
    ("seal", "sealLarge"),
    ("is-frozen", "isFrozenLarge"),
    ("is-sealed", "isSealedLarge"),
    ("sparse-array", "sparseOwnKeysLarge"),
    ("ascii-string", "asciiNamesLarge"),
    ("typed-array", "typedOwnKeysLarge"),
  ]
  let outcomes : Array[String] = []
  for case in cases {
    let (label, function_name) = case
    let outcome = match
      engine.call_json_bounded(function_name, [], own_key_consumer_policy()) {
      Ok(value) => label + "=completed:" + value.stringify()
      Err(diagnostic) => {
        let pending = if diagnostic.pending_jobs()
          is @js_engine.PendingJobs::None {
          "none"
        } else {
          "present"
        }
        label + "=" + diagnostic.failure_kind_code() + ":" + pending
      }
    }
    outcomes.push(outcome)
  }
  let reuse = match
    engine.call_json_bounded("afterOwnKeyLimit", [], own_key_consumer_policy()) {
    Ok(value) => "reuse=" + value.stringify()
    Err(diagnostic) => "reuse-error=" + diagnostic.failure_kind_code()
  }
  outcomes.push(reuse)
  let expected = cases.map(case => case.0 + "=execution-limit:none")
  expected.push("reuse=1")
  assert_eq(outcomes.join("|"), expected.join("|"))
}

///|
test "Object.assign charges each source argument before conversion" {
  let engine = @js_engine.Engine()
  engine.eval("var assignNative = Object.assign;")
  let args : Array[Json] = [Json::object({})]
  for _ in 0..<5000 {
    args.push(Json::null())
  }
  match
    engine.call_json_bounded("assignNative", args, own_key_consumer_policy()) {
    Ok(value) =>
      fail("Object.assign source traversal completed: " + value.stringify())
    Err(diagnostic) => {
      assert_eq(diagnostic.failure_kind_code(), "execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  match
    engine.call_json_bounded(
      "assignNative",
      [Json::object({}), Json::null()],
      own_key_consumer_policy(),
    ) {
    Ok(value) => json_inspect(value, content={})
    Err(diagnostic) => fail(diagnostic.message())
  }
}
