///|
// Issue #892 RED: a settled Promise must enqueue its selected reaction as a
// private executor callable while retaining the guest argument in the generic
// microtask carrier.  The current implementation uses an interpreter-native
// callback, so this intentionally fails until the managed reaction seam lands.
test "issue 892 candidate queues a typed Promise reaction executor" {
  let interp = @interpreter.new_interpreter()
  let source =
    #|var seen = 0;
    #|Promise.resolve(1).then(function(value) { seen = value; });
  let (_, evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(source).stmts,
  )
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(interp.host.microtask_queue.length(), 1)
  let task = interp.host.microtask_queue[0]
  match task.callback {
    @runtime.Object({ callable: Some(@runtime.ExecutorCallable(_)), .. }) => ()
    _ => fail("Promise reaction queue entry must be an executor callable")
  }
  assert_eq(task.args.length(), 1)
  assert_eq(task.args[0].to_string(), "1")
}
