// Focused Bytecode benchmark for issue #931.
//
// Candidate route hygiene for the same shared PROPERTY_CHAIN_SRC is asserted
// in compiler/issue_931_update_name_wbtest.mbt. Parsing, lowering, verifier
// work, interpreter setup, and correctness checks stay outside timed regions.

///|
test "issue931/bytecode_property_chain_vs_loop_control" (b : @bench.T) {
  let loop_control_source =
    #|var total = 0;
    #|for (var i = 0; i < 10000; i++) { total = total + 1; }
    #|total;
  let property_chain_program = @parser.parse(PROPERTY_CHAIN_SRC)
  let loop_control_program = @parser.parse(loop_control_source)
  let property_chain_bytecode = @compiler.compile_script_to_bytecode(
    property_chain_program.stmts,
  )
  let loop_control_bytecode = @compiler.compile_script_to_bytecode(
    loop_control_program.stmts,
  )
  let property_chain_interp = @interpreter.new_interpreter()
  let loop_control_interp = @interpreter.new_interpreter()
  let property_chain_result = property_chain_bytecode.run(property_chain_interp)
  let loop_control_result = loop_control_bytecode.run(loop_control_interp)
  guard property_chain_result.to_string() == "420000" else {
    abort("issue-931 property-chain benchmark correctness check failed")
  }
  guard loop_control_result.to_string() == "10000" else {
    abort("issue-931 loop-control benchmark correctness check failed")
  }
  b.bench(name="bytecode property chain", fn() {
    b.keep(property_chain_bytecode.run(property_chain_interp)) catch {
      _ => abort("issue-931 property-chain benchmark execution failed")
    }
  })
  b.bench(name="bytecode loop-only control", fn() {
    b.keep(loop_control_bytecode.run(loop_control_interp)) catch {
      _ => abort("issue-931 loop-control benchmark execution failed")
    }
  })
}
