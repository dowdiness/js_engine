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
