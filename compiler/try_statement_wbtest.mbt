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
