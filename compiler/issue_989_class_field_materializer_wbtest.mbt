///|
test "issue 989 retained class field uses its defining candidate plan" {
  let interp = @interpreter.new_interpreter()
  let (_, defining_evidence) = run_candidate_program_with_summary(
    interp,
    @parser.parse("globalThis.Holder = class _Holder { field = () => 42; };").stmts,
  )
  let caller_source =
    #|const { Holder } = globalThis;
    #|const holder = new Holder();
    #|holder.field();
  let program = prepare_candidate_program(@parser.parse(caller_source).stmts)
  match program.root.selection {
    UseTreeWalker(_) => ()
    UseBytecode(_) => fail("unsupported destructuring root selected Bytecode")
  }
  let (value, evidence) = run_candidate_program_with_summary(
    interp,
    @parser.parse(caller_source).stmts,
  )
  assert_eq(value.to_string(), "42")
  assert_eq(evidence.val.summary.bytecode_starts, 0)
  assert_true(evidence.val.summary.tree_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  assert_true(defining_evidence.val.summary.bytecode_starts > 0)
  assert_eq(defining_evidence.val.summary.fallback_violations, 0)
  assert_eq(defining_evidence.val.summary.replay_violations, 0)
  assert_eq(defining_evidence.val.summary.active_activations, 0)
}

///|
test "issue 989 private field initializer retains its defining candidate plan" {
  let interp = @interpreter.new_interpreter()
  let (_, defining_evidence) = run_candidate_program_with_summary(
    interp,
    @parser.parse(
      (
        #|globalThis.PrivateHolder = class _PrivateHolder {
        #|  #field = () => 43;
        #|  read() { return this.#field(); }
        #|};
      ),
    ).stmts,
  )
  let caller_source =
    #|const { PrivateHolder } = globalThis;
    #|const holder = new PrivateHolder();
    #|holder.read();
  let (value, caller_evidence) = run_candidate_program_with_summary(
    interp,
    @parser.parse(caller_source).stmts,
  )
  assert_eq(value.to_string(), "43")
  assert_true(defining_evidence.val.summary.bytecode_starts > 0)
  assert_eq(defining_evidence.val.summary.fallback_violations, 0)
  assert_eq(defining_evidence.val.summary.replay_violations, 0)
  assert_eq(defining_evidence.val.summary.active_activations, 0)
  assert_eq(caller_evidence.val.summary.bytecode_starts, 0)
  assert_true(caller_evidence.val.summary.tree_starts > 0)
  assert_eq(caller_evidence.val.summary.fallback_violations, 0)
  assert_eq(caller_evidence.val.summary.replay_violations, 0)
  assert_eq(caller_evidence.val.summary.active_activations, 0)
}

///|
test "issue 989 retained class constructor uses its own child plan" {
  let interp = @interpreter.new_interpreter()
  let defining_source =
    #|globalThis.ConstructorHolder = class _ConstructorHolder {
    #|  constructor() {
    #|    [1].forEach(() => { this.value = 44; });
    #|  }
    #|};
  let defining_program = prepare_candidate_program(
    @parser.parse(defining_source).stmts,
  )
  match defining_program.root.children[0].selection {
    UseTreeWalker(
      CandidateLoweringUnsupported({ reason: ClassConstructor, .. })
    ) => ()
    UseTreeWalker(_) => fail("class constructor lost its typed route reason")
    UseBytecode(_) => fail("class constructor selected Bytecode")
  }
  let (_, defining_evidence) = run_candidate_program_with_summary(
    interp,
    @parser.parse(defining_source).stmts,
  )
  let caller_source =
    #|const { ConstructorHolder } = globalThis;
    #|const holder = new ConstructorHolder();
    #|holder.value;
  let (value, caller_evidence) = run_candidate_program_with_summary(
    interp,
    @parser.parse(caller_source).stmts,
  )
  assert_eq(value.to_string(), "44")
  assert_true(defining_evidence.val.summary.tree_starts > 1)
  assert_eq(defining_evidence.val.summary.fallback_violations, 0)
  assert_eq(defining_evidence.val.summary.replay_violations, 0)
  assert_eq(defining_evidence.val.summary.active_activations, 0)
  assert_eq(caller_evidence.val.summary.bytecode_starts, 0)
  assert_true(caller_evidence.val.summary.tree_starts > 0)
  assert_eq(caller_evidence.val.summary.fallback_violations, 0)
  assert_eq(caller_evidence.val.summary.replay_violations, 0)
  assert_eq(caller_evidence.val.summary.active_activations, 0)
}
