///|
fn issue1074_callable_proxy_iterator_result_for_wb(
  source : String,
) -> String raise Error {
  let stmts = @parser.parse(source).stmts
  let tree = @interpreter.new_interpreter().run(stmts)
  let candidate = run_candidate_program(@interpreter.new_interpreter(), stmts)
  assert_eq(candidate.to_string(), tree.to_string(), msg="candidate: " + source)
  candidate.to_string()
}

///|
test "issue 1074 binding accepts a callable Proxy iterator method" {
  let source =
    #|var trace = [];
    #|var iterator = {
    #|  next: function() { trace.push("next"); return { value: 7, done: false }; },
    #|  return: function() { trace.push("return"); return {}; }
    #|};
    #|var method = new Proxy(function() { throw "target"; }, {
    #|  apply: function(target, receiver, args) {
    #|    trace.push("apply:" + (receiver === source) + ":" + args.length);
    #|    return iterator;
    #|  }
    #|});
    #|var source = {};
    #|source[Symbol.iterator] = method;
    #|try {
    #|  var [value] = source;
    #|  trace.push("value:" + value);
    #|} catch (error) { trace.push(error.name); }
    #|trace.join("|");
  assert_eq(
    issue1074_callable_proxy_iterator_result_for_wb(source),
    "apply:true:0|next|return|value:7",
  )
}

///|
test "issue 1074 assignment shares callable Proxy iterator acquisition" {
  let source =
    #|var trace = [];
    #|var iterator = {
    #|  next: function() { trace.push("next"); return { value: 7, done: false }; },
    #|  return: function() { trace.push("return"); return {}; }
    #|};
    #|var method = new Proxy(function() { throw "target"; }, {
    #|  apply: function(target, receiver, args) {
    #|    trace.push("apply:" + (receiver === source) + ":" + args.length);
    #|    return iterator;
    #|  }
    #|});
    #|var source = {};
    #|source[Symbol.iterator] = method;
    #|var value;
    #|[value] = source;
    #|trace.push("value:" + value);
    #|trace.join("|");
  assert_eq(
    issue1074_callable_proxy_iterator_result_for_wb(source),
    "apply:true:0|next|return|value:7",
  )
}

///|
test "issue 1074 empty patterns get next before closing" {
  let source =
    #|var trace = [];
    #|var iterator = { return: function() { trace.push("return"); return {}; } };
    #|Object.defineProperty(iterator, "next", {
    #|  get: function() { trace.push("next:get"); return 1; }
    #|});
    #|var source = {};
    #|source[Symbol.iterator] = function() { trace.push("method"); return iterator; };
    #|var [] = source;
    #|trace.join("|");
  assert_eq(
    issue1074_callable_proxy_iterator_result_for_wb(source),
    "method|next:get|return",
  )
}

///|
test "issue 1074 failed iterator acquisition preserves errors and effects" {
  let non_callable_proxy =
    #|var trace = [];
    #|var source = {};
    #|source[Symbol.iterator] = new Proxy({}, {
    #|  apply: function() { trace.push("apply"); }
    #|});
    #|try { var [] = source; } catch (error) { trace.push(error.name); }
    #|trace.join("|");
  assert_eq(
    issue1074_callable_proxy_iterator_result_for_wb(non_callable_proxy),
    "TypeError",
  )

  let revoked_callable_proxy =
    #|var trace = [];
    #|var target = function() { trace.push("target"); };
    #|var revocable = Proxy.revocable(target, {
    #|  apply: function() { trace.push("apply"); }
    #|});
    #|revocable.revoke();
    #|var source = {};
    #|source[Symbol.iterator] = revocable.proxy;
    #|try { var [] = source; } catch (error) { trace.push(error.name); }
    #|trace.join("|");
  assert_eq(
    issue1074_callable_proxy_iterator_result_for_wb(revoked_callable_proxy),
    "TypeError",
  )

  let throwing_apply =
    #|var trace = [];
    #|var sentinel = {};
    #|var method = new Proxy(function() {}, {
    #|  apply: function() { trace.push("apply"); throw sentinel; }
    #|});
    #|var source = {};
    #|source[Symbol.iterator] = method;
    #|try { var [] = source; }
    #|catch (error) { trace.push(error === sentinel ? "same" : "different"); }
    #|finally { trace.push("finally"); }
    #|trace.join("|");
  assert_eq(
    issue1074_callable_proxy_iterator_result_for_wb(throwing_apply),
    "apply|same|finally",
  )
}
