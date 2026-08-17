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
