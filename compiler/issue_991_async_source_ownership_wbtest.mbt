///|
test "issue 991 candidate root cannot lend its plan to retained async work" {
  let interp = @interpreter.new_interpreter()
  let defining_source =
    #|1 ** 2;
    #|globalThis.issue991RetainedAsync = async () => {
    #|  return (() => 42)();
    #|};
  let (_, defining_evidence) = run_candidate_program_with_summary(
    interp,
    @parser.parse(defining_source).stmts,
  )
  assert_eq(defining_evidence.val.summary.bytecode_starts, 0)
  assert_eq(defining_evidence.val.summary.tree_starts, 1)

  let caller_source =
    #|globalThis.issue991Promise = globalThis.issue991RetainedAsync();
    #|0;
  let caller_program = prepare_candidate_program(
    @parser.parse(caller_source).stmts,
  )
  match caller_program.root.selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("issue 991 caller root lost Bytecode eligibility")
  }
  let (_, caller_evidence) = run_candidate_program_with_summary(
    interp,
    @parser.parse(caller_source).stmts,
  )
  let observer_source =
    #|var issue991Result = -1;
    #|var issue991Error = "";
    #|globalThis.issue991Promise
    #|  .then(value => { issue991Result = value; })
    #|  .catch(error => { issue991Error = String(error); });
  let _ = run_candidate_program_with_summary(
    interp,
    @parser.parse(observer_source).stmts,
  )
  interp.run_microtasks()
  let (state, state_evidence) = run_candidate_program_with_summary(
    interp,
    @parser.parse("[issue991Result, issue991Error].join('|');").stmts,
  )
  assert_eq(state.to_string(), "42|")
  assert_true(caller_evidence.val.summary.bytecode_starts > 0)
  assert_eq(caller_evidence.val.summary.fallback_violations, 0)
  assert_eq(caller_evidence.val.summary.replay_violations, 0)
  assert_eq(caller_evidence.val.summary.active_activations, 0)
  assert_eq(state_evidence.val.summary.fallback_violations, 0)
  assert_eq(state_evidence.val.summary.replay_violations, 0)
  assert_eq(state_evidence.val.summary.active_activations, 0)
}
