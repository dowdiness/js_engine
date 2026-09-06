///|
test "finally runs before propagating the original thrown value" {
  let source =
    #|var marker = {}, trace = [], same = false;
    #|try {
    #|  try { throw marker; } finally { trace.push('finally'); }
    #|} catch (error) { same = error === marker; }
    #|same + ':' + trace.join(',');
  assert_try_block_result(source, "true:finally")
}

///|
test "finally runs after a catch throws and optional catch executes its body" {
  for clause in ["catch (error)", "catch"] {
    let source = "var trace = [], result; try { try { throw 'try'; } " +
      clause +
      " { trace.push('catch'); throw 'catch'; }" +
      " finally { trace.push('finally'); } } catch (error) { result = error; }" +
      "result + ':' + trace.join(',');"
    assert_try_block_result(source, "catch:catch,finally")
  }
}

///|
test "abrupt finally completion replaces a pending throw" {
  for
    row in [
      (
        "function f(){try{throw 'try';}finally{return 'finally';}} f();", "finally",
      ),
      (
        "var result;try{try{throw 'try';}finally{throw 'finally';}}catch(e){result=e;}result;",
        "finally",
      ),
      (
        "var result='ok';exit: {try{throw 'try';}finally{break exit;}}result;", "ok",
      ),
      (
        "var count=0;for(var i=0;i<2;i++){try{throw 'try';}finally{count++;continue;}}count;",
        "2",
      ),
    ] {
    let (source, expected) = row
    assert_try_block_result(source, expected)
  }
}

///|
test "generator finally suspension preserves a pending throw" {
  let source =
    #|var marker = {}, same = false;
    #|function* sequence() { try { throw marker; } finally { yield 'cleanup'; } }
    #|var it = sequence();
    #|var first = it.next().value;
    #|try { it.next(); } catch (error) { same = error === marker; }
    #|first + ':' + same;
  assert_try_block_result(source, "cleanup:true")
}

///|
test "generator resumed catch still runs finally before throwing" {
  for clause in ["catch (error)", "catch"] {
    let source = "var trace=[],result;function* sequence(){try{throw 'try';}" +
      clause +
      "{yield 'pause';throw 'catch';}finally{trace.push('finally');}}" +
      "var it=sequence();it.next();try{it.next();}catch(error){result=error;}" +
      "result+':'+trace.join(',');"
    assert_try_block_result(source, "catch:finally")
  }
}

///|
test "catch binding failure still executes finally" {
  let source =
    #|var trace = [], result;
    #|try {
    #|  try { throw { get value() { throw 'binding'; } }; }
    #|  catch ({value}) { trace.push('body'); }
    #|  finally { trace.push('finally'); }
    #|} catch (error) { result = error; }
    #|result + ':' + trace.join(',');
  assert_try_block_result(source, "binding:finally")
}

///|
test "normal finally preserves a return and generator return survives finally suspension" {
  assert_try_block_result(
    "function f(){try{return 'try';}finally{'finally';}}f();", "try",
  )
  let source =
    #|function* sequence() { try { yield 'start'; } finally { yield 'cleanup'; } }
    #|var it = sequence(); it.next();
    #|var cleanup = it.return('returned');
    #|var result = it.next();
    #|[cleanup.value, cleanup.done, result.value, result.done].join(',');
  assert_try_block_result(source, "cleanup,false,returned,true")
}
