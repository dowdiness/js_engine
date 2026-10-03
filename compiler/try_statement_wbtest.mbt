///|
fn assert_try_result(source : String, expected : String) -> Unit raise {
  let stmts = @parser.parse(source).stmts
  let tree = @interpreter.new_interpreter().run(stmts)
  assert_eq(tree.to_string(), expected, msg="tree: " + source)
  let candidate = run_candidate_program(@interpreter.new_interpreter(), stmts)
  assert_eq(candidate.to_string(), expected, msg="candidate: " + source)
}

///|
test "try statement blocks create TDZ for every lexical declaration kind" {
  for
    statement in [
      "try { typeof value; let value; } finally {}", "try { typeof value; const value = 1; } finally {}",
      "try { typeof value; let [value] = [1]; } finally {}", "try { typeof value; class value {} } finally {}",
      "try { throw 0; } catch (e) { typeof value; let value; }", "try { throw 0; } catch (e) { typeof value; const value = 1; }",
      "try { throw 0; } catch (e) { typeof value; let [value] = [1]; }", "try { throw 0; } catch (e) { typeof value; class value {} }",
      "try {} finally { typeof value; let value; }", "try {} finally { typeof value; const value = 1; }",
      "try {} finally { typeof value; let [value] = [1]; }", "try {} finally { typeof value; class value {} }",
    ] {
    assert_try_result(
      "var value = 99; var result; try { " +
      statement +
      " } catch (error) { result = error.name; } result;",
      "ReferenceError",
    )
  }
}

///|
test "block initialization preserves catch parameters and scope" {
  let source =
    #|var result = [];
    #|try { let value = 1; result.push(value); throw 2; }
    #|catch (error) { let value = error; result.push(value); }
    #|finally { let value = 3; result.push(value); }
    #|result.push(typeof value);
    #|result.join(',');
  assert_try_result(source, "1,2,3,undefined")
}

///|
test "try block retains TDZ after yield" {
  let source =
    #|function* sequence() {
    #|  try { yield 0; typeof value; let value; } finally {}
    #|}
    #|var it = sequence(); it.next();
    #|var result;
    #|try { it.next(); } catch (error) { result = error.name; }
    #|result;
  assert_try_result(source, "ReferenceError")
}

///|
test "catch block retains TDZ after yield" {
  let source =
    #|function* sequence() {
    #|  try { throw 0; } catch (e) { yield 0; typeof value; let value; }
    #|}
    #|var it = sequence(); it.next();
    #|var result;
    #|try { it.next(); } catch (error) { result = error.name; }
    #|result;
  assert_try_result(source, "ReferenceError")
}

///|
test "finally block retains TDZ after yield" {
  let source =
    #|function* sequence() {
    #|  try {} finally { yield 0; typeof value; let value; }
    #|}
    #|var it = sequence(); it.next();
    #|var result;
    #|try { it.next(); } catch (error) { result = error.name; }
    #|result;
  assert_try_result(source, "ReferenceError")
}

///|
test "normal finally preserves the thrown object" {
  let source =
    #|var marker = {}, trace = [], same = false;
    #|try {
    #|  try { throw marker; } finally { trace.push('finally'); }
    #|} catch (error) { same = error === marker; }
    #|same + ':' + trace.join(',');
  assert_try_result(source, "true:finally")
}

///|
test "finally runs when catch throws" {
  let source =
    #|var trace = [], result;
    #|try {
    #|  try { throw 'try'; }
    #|  catch (error) { trace.push('catch'); throw 'catch'; }
    #|  finally { trace.push('finally'); }
    #|} catch (error) { result = error; }
    #|result + ':' + trace.join(',');
  assert_try_result(source, "catch:catch,finally")
}

///|
test "finally runs when optional catch throws" {
  let source =
    #|var trace = [], result;
    #|try {
    #|  try { throw 'try'; }
    #|  catch { trace.push('catch'); throw 'catch'; }
    #|  finally { trace.push('finally'); }
    #|} catch (error) { result = error; }
    #|result + ':' + trace.join(',');
  assert_try_result(source, "catch:catch,finally")
}

///|
test "finally return replaces a throw" {
  let source =
    #|function f() {
    #|  try { throw 'try'; } finally { return 'finally'; }
    #|}
    #|f();
  assert_try_result(source, "finally")
}

///|
test "finally throw replaces a throw" {
  let source =
    #|var result;
    #|try {
    #|  try { throw 'try'; } finally { throw 'finally'; }
    #|} catch (error) { result = error; }
    #|result;
  assert_try_result(source, "finally")
}

///|
test "finally break replaces a throw" {
  let source =
    #|exit: {
    #|  try { throw 'try'; } finally { break exit; }
    #|}
    #|'ok';
  assert_try_result(source, "ok")
}

///|
test "finally continue replaces a throw" {
  let source =
    #|var count = 0;
    #|for (var i = 0; i < 2; i++) {
    #|  try { throw 'try'; } finally { count++; continue; }
    #|}
    #|count;
  assert_try_result(source, "2")
}

///|
test "normal finally preserves a return" {
  let source =
    #|function f() {
    #|  try { return 'try'; } finally { 'finally'; }
    #|}
    #|f();
  assert_try_result(source, "try")
}

///|
test "finally yield preserves the pending thrown object" {
  let source =
    #|var marker = {}, same = false;
    #|function* sequence() {
    #|  try { throw marker; } finally { yield 'cleanup'; }
    #|}
    #|var it = sequence();
    #|var first = it.next().value;
    #|try { it.next(); } catch (error) { same = error === marker; }
    #|first + ':' + same;
  assert_try_result(source, "cleanup:true")
}

///|
test "finally runs when resumed catch throws" {
  let source =
    #|var trace = [], result;
    #|function* sequence() {
    #|  try { throw 'try'; }
    #|  catch (error) { yield 'pause'; throw 'catch'; }
    #|  finally { trace.push('finally'); }
    #|}
    #|var it = sequence(); it.next();
    #|try { it.next(); } catch (error) { result = error; }
    #|result + ':' + trace.join(',');
  assert_try_result(source, "catch:finally")
}

///|
test "finally runs when resumed optional catch throws" {
  let source =
    #|var trace = [], result;
    #|function* sequence() {
    #|  try { throw 'try'; }
    #|  catch { yield 'pause'; throw 'catch'; }
    #|  finally { trace.push('finally'); }
    #|}
    #|var it = sequence(); it.next();
    #|try { it.next(); } catch (error) { result = error; }
    #|result + ':' + trace.join(',');
  assert_try_result(source, "catch:finally")
}

///|
test "finally runs when catch binding initialization throws" {
  let source =
    #|var trace = [], result;
    #|try {
    #|  try { throw { get value() { throw 'binding'; } }; }
    #|  catch ({value}) { trace.push('body'); }
    #|  finally { trace.push('finally'); }
    #|} catch (error) { result = error; }
    #|result + ':' + trace.join(',');
  assert_try_result(source, "binding:finally")
}

///|
test "catch pattern predeclares bindings before defaults" {
  let source =
    #|var later = 42, trace = [];
    #|try {
    #|  try { throw []; }
    #|  catch ([first = later, later, ...rest]) { trace.push("body"); }
    #|  finally { trace.push("finally"); }
    #|} catch (error) { trace.push(error.name); }
    #|JSON.stringify([trace, later]);
  assert_try_result(source, "[[\"finally\",\"ReferenceError\"],42]")
}

///|
test "catch pattern predeclares self and rest bindings" {
  let self_default =
    #|var self = 42, trace = [];
    #|try {
    #|  try { throw []; }
    #|  catch ([self = self, ...rest]) { trace.push("body"); }
    #|  finally { trace.push("finally"); }
    #|} catch (error) { trace.push(error.name); }
    #|JSON.stringify([trace, self]);
  assert_try_result(self_default, "[[\"finally\",\"ReferenceError\"],42]")
  let rest_default =
    #|var rest = 43, trace = [];
    #|try {
    #|  try { throw []; }
    #|  catch ([first = rest, ...rest]) { trace.push("body"); }
    #|  finally { trace.push("finally"); }
    #|} catch (error) { trace.push(error.name); }
    #|JSON.stringify([trace, rest]);
  assert_try_result(rest_default, "[[\"finally\",\"ReferenceError\"],43]")
}

///|
test "catch pattern predeclares object defaults and computed keys" {
  let object_default =
    #|var later = 42, trace = [];
    #|try {
    #|  try { throw {}; }
    #|  catch ({first: first = later, later, ...rest}) { trace.push("body"); }
    #|  finally { trace.push("finally"); }
    #|} catch (error) { trace.push(error.name); }
    #|JSON.stringify([trace, later]);
  assert_try_result(object_default, "[[\"finally\",\"ReferenceError\"],42]")
  let computed_key =
    #|var later = 42, trace = [];
    #|try {
    #|  try { throw {42: 1}; }
    #|  catch ({[later]: first, later, ...rest}) { trace.push("body"); }
    #|  finally { trace.push("finally"); }
    #|} catch (error) { trace.push(error.name); }
    #|JSON.stringify([trace, later]);
  assert_try_result(computed_key, "[[\"finally\",\"ReferenceError\"],42]")
}

///|
test "catch pattern defaults retain initialized cells in closures" {
  let source =
    #|var read;
    #|try { throw {}; }
    #|catch ({first = 1, second = first, closure = () => [first, second], ...rest}) { read = closure; }
    #|JSON.stringify(read());
  assert_try_result(source, "[1,1]")
}

///|
test "catch pattern partial initialization preserves escaped cells" {
  let source =
    #|var escaped, result, trace = [], c = 99;
    #|try {
    #|  try { throw [1]; }
    #|  catch ([a, b = (escaped = [() => a, () => c])[0], c = missing]) { trace.push("body"); }
    #|  finally { trace.push("finally"); }
    #|} catch (error) {
    #|  result = escaped[0]() + ":";
    #|  try { escaped[1](); } catch (inner) { result += inner.name; }
    #|}
    #|JSON.stringify([trace, result]);
  assert_try_result(source, "[[\"finally\"],\"1:ReferenceError\"]")
}

///|
test "catch pattern closes iterator after TDZ failure" {
  let source =
    #|var later = 42, trace = [], iterator = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { trace.push("next"); return {value: undefined, done: false}; },
    #|  return() { trace.push("return"); throw "close"; }
    #|};
    #|try {
    #|  try { throw iterator; }
    #|  catch ([first = later, later, ...rest]) { trace.push("body"); }
    #|  finally { trace.push("finally"); }
    #|} catch (error) { trace.push(error.name); }
    #|JSON.stringify(trace);
  assert_try_result(
    source, "[\"next\",\"return\",\"finally\",\"ReferenceError\"]",
  )
}

///|
test "finally yield preserves the injected generator return" {
  let source =
    #|function* sequence() {
    #|  try { yield 'start'; } finally { yield 'cleanup'; }
    #|}
    #|var it = sequence(); it.next();
    #|var cleanup = it.return('returned');
    #|var result = it.next();
    #|[cleanup.value, cleanup.done, result.value, result.done].join(',');
  assert_try_result(source, "cleanup,false,returned,true")
}

///|
test "catch pattern retains initialization cells across yield" {
  let source =
    #|var later = 42, read;
    #|function* sample() {
    #|  try { throw []; }
    #|  catch ([first = () => later, later = (read = first, yield 'pause')]) {
    #|    return [first(), read()];
    #|  }
    #|}
    #|var iterator = sample(), trace = [iterator.next().value];
    #|try { read(); trace.push('initialized'); }
    #|catch (error) { trace.push(error.name); }
    #|try { trace.push(iterator.next(7).value); }
    #|catch (error) { trace.push(error.name); }
    #|JSON.stringify(trace);
  assert_try_result(source, "[\"pause\",\"ReferenceError\",[7,7]]")
}
