///|
fn sync_delegate_result_test_interpreter() -> Interpreter {
  let interp = Interpreter::new()
  interp.global.def_builtin(
    "iterKey",
    Symbol(interp.realm_state.well_known_symbols.iterator),
  )
  interp.global.def_builtin(
    "Proxy",
    make_canonical_proxy_constructor(interp.realm_state),
  )
  interp
}

///|
fn sync_delegate_result_run_output(
  source : String,
) -> Array[String] raise Error {
  let interp = sync_delegate_result_test_interpreter()
  try {
    let _ = interp.run(@parser.parse(source).stmts)
    interp.host.output
  } catch {
    JsException(value) =>
      fail("unexpected JavaScript exception: " + value.to_string())
    error => fail("unexpected runtime error: " + error.to_string())
  }
}

///|
test "sync yield star preserves the initial iterator result object" {
  let output = sync_delegate_result_run_output(
    (
      #|let result = { done: false, value: 7 };
      #|let iterator = {
      #|  [iterKey]() { return this; },
      #|  next() { return result; },
      #|};
      #|function* delegated() { yield* iterator; }
      #|let generator = delegated();
      #|let observed = generator.next();
      #|console.log(observed === result);
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "sync yield star preserves resumed next throw and return results" {
  let output = sync_delegate_result_run_output(
    (
      #|let firstResult = { done: false, value: 1, tag: "first" };
      #|let secondResult = { done: false, value: 2, tag: "second" };
      #|let throwResult = { done: false, value: 3, tag: "throw" };
      #|let returnResult = { done: false, value: 4, tag: "return" };
      #|let nextCalls = 0;
      #|let iterator = {
      #|  [iterKey]() { return this; },
      #|  next() {
      #|    nextCalls++;
      #|    return nextCalls === 1 ? firstResult : secondResult;
      #|  },
      #|  throw() { return throwResult; },
      #|  return() { return returnResult; },
      #|};
      #|function* delegated() { yield* iterator; }
      #|let generator = delegated();
      #|console.log(generator.next() === firstResult);
      #|console.log(generator.next() === secondResult);
      #|console.log(generator.throw("boom") === throwResult);
      #|console.log(generator.return("stop") === returnResult);
    ),
  )
  json_inspect(output, content=["true", "true", "true", "true"])
}

///|
test "sync delegated Proxy result defers value access" {
  let output = sync_delegate_result_run_output(
    (
      #|let doneGets = 0;
      #|let proxyValueGets = 0;
      #|let sourceValueGets = 0;
      #|let source = {
      #|  done: false,
      #|  get value() { sourceValueGets++; return 17; },
      #|  tag: "proxy",
      #|};
      #|let result = new Proxy(source, {
      #|  get(target, key) {
      #|    if (key === "done") doneGets++;
      #|    if (key === "value") proxyValueGets++;
      #|    return target[key];
      #|  },
      #|});
      #|let iterator = {
      #|  [iterKey]() { return this; },
      #|  next() { return result; },
      #|};
      #|function* delegated() { yield* iterator; }
      #|let observed = delegated().next();
      #|console.log(observed === result);
      #|console.log(doneGets);
      #|console.log(proxyValueGets);
      #|console.log(sourceValueGets);
      #|console.log(observed.tag);
      #|console.log(observed.value);
      #|console.log(proxyValueGets);
      #|console.log(sourceValueGets);
    ),
  )
  json_inspect(output, content=["true", "1", "0", "0", "proxy", "17", "1", "1"])
}

///|
test "sync yield star done true gets value and ordinary yield wraps" {
  let output = sync_delegate_result_run_output(
    (
      #|let valueGets = 0;
      #|let iterator = {
      #|  [iterKey]() { return this; },
      #|  next() {
      #|    return { done: true, get value() { valueGets++; return 42; } };
      #|  },
      #|};
      #|function* delegated() { return yield* iterator; }
      #|let completed = delegated().next();
      #|console.log(completed.done);
      #|console.log(completed.value);
      #|console.log(valueGets);
      #|function* ordinary() { yield { marker: 9 }; }
      #|let normal = ordinary().next();
      #|console.log(normal.done);
      #|console.log(normal.value.marker);
    ),
  )
  json_inspect(output, content=["true", "42", "1", "false", "9"])
}
