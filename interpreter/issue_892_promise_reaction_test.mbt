///|
// Stable tree-walker execution and candidate bytecode execution share the
// same runtime-owned Promise reaction job. This test pins the stable side of
// the entry gate before draining the selected generic microtask.
test "issue 892 stable reaction queue uses a managed callable" {
  let interp = new_interpreter()
  let source =
    #|var seen = "";
    #|Promise.resolve(1).then(function(value) { seen = String(value); });
  let _ = interp.run(@parser.parse(source).stmts)
  assert_eq(interp.host.microtask_queue.length(), 1)
  let task = interp.host.microtask_queue[0]
  match task.callback {
    @runtime.Object({ callable: Some(@runtime.ExecutorCallable(_)), .. }) => ()
    _ => fail("Promise reaction queue entry must be an executor callable")
  }
  assert_eq(task.args.length(), 1)
  assert_eq(task.args[0].to_string(), "1")
  interp.run_microtasks()
  match interp.global.get("seen") {
    @runtime.String_(value) => assert_eq(value, "1")
    value => fail("expected stable reaction result, got " + value.to_string())
  }
}

///|
test "issue 892 stable thenable job waits behind the current script" {
  let interp = new_interpreter()
  let source =
    #|var log = "";
    #|var thenable = { then: function(resolve) { log = log + "t"; resolve(); } };
    #|Promise.resolve(thenable);
    #|log = log + "s";
  let _ = interp.run(@parser.parse(source).stmts)
  match interp.global.get("log") {
    @runtime.String_(value) => assert_eq(value, "s")
    value => fail("expected pre-checkpoint log, got " + value.to_string())
  }
  assert_eq(interp.host.microtask_queue.length(), 1)
  interp.run_microtasks()
  match interp.global.get("log") {
    @runtime.String_(value) => assert_eq(value, "st")
    value => fail("expected post-checkpoint log, got " + value.to_string())
  }
}

///|
test "issue 892 stable thenable job preserves sibling FIFO" {
  let interp = new_interpreter()
  let source =
    #|var log = "";
    #|var thenable = { then: function(resolve) { log = log + "t"; resolve(); } };
    #|Promise.resolve(thenable).then(function() { log = log + "r"; });
    #|Promise.resolve().then(function() { log = log + "s"; });
  let _ = interp.run(@parser.parse(source).stmts)
  assert_eq(interp.host.microtask_queue.length(), 2)
  interp.run_microtasks()
  match interp.global.get("log") {
    @runtime.String_(value) => assert_eq(value, "tsr")
    value => fail("expected stable FIFO log, got " + value.to_string())
  }
}

///|
test "issue 892 stable thenable job creates resolving functions in the then realm" {
  let interp = new_interpreter()
  let source =
    #|var r = $262.createRealm();
    #|var foreignFunctionProto = r.evalScript("Function.prototype");
    #|var localFunctionProto = Function.prototype;
    #|var thenable = r.evalScript("({ calls: 0, then: function(resolve, reject) { this.calls += 1; this.resolve = resolve; this.reject = reject; resolve('ok'); resolve('late'); reject('bad'); } })");
    #|var settled = "";
    #|Promise.resolve(thenable).then(function(value) { settled = "fulfilled:" + value; }, function(reason) { settled = "rejected:" + reason; });
    #|var snapshot = "";
    #|queueMicrotask(function() { queueMicrotask(function() { snapshot = thenable.calls + ":" + (Object.getPrototypeOf(thenable.resolve) === foreignFunctionProto) + ":" + (Object.getPrototypeOf(thenable.resolve) === localFunctionProto) + ":" + (Object.getPrototypeOf(thenable.reject) === foreignFunctionProto) + ":" + (Object.getPrototypeOf(thenable.reject) === localFunctionProto) + ":" + settled; }); });
  let _ = interp.run(@parser.parse(source).stmts)
  interp.run_microtasks()
  match interp.global.get("snapshot") {
    @runtime.String_(value) =>
      assert_eq(value, "1:true:false:true:false:fulfilled:ok")
    value => fail("expected cross-realm snapshot, got " + value.to_string())
  }
}

///|
test "issue 892 stable thenable job follows proxy and revoked realm rules" {
  let interp = new_interpreter()
  let source =
    #|var r = $262.createRealm();
    #|var foreignFunctionProto = r.evalScript("Function.prototype");
    #|var localFunctionProto = Function.prototype;
    #|var foreignThen = r.evalScript("(function(resolve) { this.resolve = resolve; resolve('proxy'); })");
    #|var proxiedThenable = { then: new Proxy(foreignThen, {}) };
    #|var proxied = "";
    #|Promise.resolve(proxiedThenable).then(function(value) { proxied = (Object.getPrototypeOf(proxiedThenable.resolve) === foreignFunctionProto) + ":" + (Object.getPrototypeOf(proxiedThenable.resolve) === localFunctionProto) + ":" + value; });
    #|var revocable = Proxy.revocable(foreignThen, {});
    #|var revokedThenable = { then: revocable.proxy };
    #|revocable.revoke();
    #|var revoked = "";
    #|Promise.resolve(revokedThenable).catch(function(error) { revoked = error instanceof TypeError ? "type-error" : "wrong"; });
    #|var snapshot = "";
    #|queueMicrotask(function() { queueMicrotask(function() { snapshot = proxied + ":" + revoked; }); });
  let _ = interp.run(@parser.parse(source).stmts)
  interp.run_microtasks()
  match interp.global.get("snapshot") {
    @runtime.String_(value) => assert_eq(value, "true:false:proxy:type-error")
    value => fail("expected proxy/revoked snapshot, got " + value.to_string())
  }
}
