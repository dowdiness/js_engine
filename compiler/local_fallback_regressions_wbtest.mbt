///|
test "candidate arrow block completion is not an implicit return" {
  let source =
    #|var named = function self() {};
    #|var block = v => { v + 1; };
    #|var expression = v => v + 1;
    #|var explicit = v => { return v + 1; };
    #|[block(1) === undefined, expression(1), explicit(1)].join(',');
  let (value, _) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true,2,2")
}

///|
test "native construction retains the constructor child materializer" {
  for parameters in ["executor", "executor, unused = 0"] {
    let source = "var named = function self() {}; var checkpoint = '';" +
      "function run(fn) { try { fn(); } catch(e) { return e.name; } }" +
      "var error = run(function() { Promise.resolve.call(function(" +
      parameters +
      ") { checkpoint += 'a'; executor(undefined, function() {});" +
      "checkpoint += 'b'; executor(function() {}, function() {}); }, {}); });" +
      "error + ':' + checkpoint;"
    let (value, _) = candidate_run_with_evidence_for_wb(source)
    assert_eq(value.to_string(), "TypeError:ab", msg=parameters)
  }
}

///|
test "nested script evaluation does not inherit its callers candidate plan" {
  let source =
    #|var named = function self() {};
    #|$262.evalScript('function f() { return 1; } function f() { return 2; }');
    #|function after() { return 3; }
    #|f() + after();
  let (value, _) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "5")
}

///|
test "candidate typed array string indices bypass prototype getters" {
  let source =
    #|var named = function self() {};
    #|var sample = new Float64Array([42]);
    #|var proto = Object.getPrototypeOf(Float64Array.prototype);
    #|for (var key of ['0', '1', '-0', '1.5']) {
    #|  Object.defineProperty(proto, key, { get: function() { throw new Error('prototype accessed'); } });
    #|}
    #|function read() {
    #|  return sample['0'] === 42 && sample['1'] === undefined &&
    #|    sample['-0'] === undefined && sample['1.5'] === undefined;
    #|}
    #|read();
  let (value, _) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "true")
}

///|
test "candidate strict assignments respect readonly global bindings" {
  for name in ["NaN", "undefined", "Infinity"] {
    let source = "'use strict'; var named = function self() {};" +
      "function write() { " +
      name +
      " = 12; }" +
      "var error = ''; try { write(); } catch(e) { error = e.name; } error;"
    let (value, _) = candidate_run_with_evidence_for_wb(source)
    assert_eq(value.to_string(), "TypeError", msg=name)
  }
}

///|
test "global lexical binding shadows a readonly global object property" {
  let source =
    #|'use strict';
    #|var named = function self() {};
    #|let value = 2;
    #|Object.defineProperty(globalThis, 'value', { value: 1, writable: false, configurable: true });
    #|function write() { value = 3; }
    #|write();
    #|value + ':' + globalThis.value;
  let (value, _) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "3:1")
}
