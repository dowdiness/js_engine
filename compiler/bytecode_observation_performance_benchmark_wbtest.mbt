// =============================================================================
// Observation coverage finalization microbenchmark (issue #896)
//
// Run with:
//   moon bench -p compiler -f bytecode_observation_performance_benchmark_wbtest.mbt \
//     --target native --release
//
// Parsing is deliberately outside every timed closure.  The two benchmark
// groups isolate lowering (AST -> BytecodeUnverifiedProgram) from finalization
// (BytecodeUnverifiedProgram -> BytecodeProgram).
// =============================================================================

///|
fn issue_896_flat_source(statement_count : Int) -> String {
  let mut source = ""
  for _ in 0..<statement_count {
    source = source + "value;"
  }
  source
}

///|
fn issue_896_parse_flat_source(statement_count : Int) -> Array[@ast.Stmt] {
  @parser.parse(issue_896_flat_source(statement_count)).stmts catch {
    _ => abort("issue-896 benchmark: flat source failed to parse")
  }
}

///|
fn issue_896_lower_or_abort(stmts : Array[@ast.Stmt]) -> Int {
  let program = build_script_bytecode(stmts) catch {
    _ => abort("issue-896 benchmark: lowering failed")
  }
  let instruction_count = program.main.code.length()
  instruction_count
}

///|
fn issue_896_finalize_or_abort(program : BytecodeUnverifiedProgram) -> Int {
  let finalized = finalize_bytecode_program(program) catch {
    _ => abort("issue-896 benchmark: finalization failed")
  }
  finalized.verified_main.function.code.length()
}

///|
test "issue-896/observation-coverage-scaling" (b : @bench.T) {
  let sizes = [500, 1000, 2000, 4000]
  let parsed = sizes.map(size => (size, issue_896_parse_flat_source(size)))
  let prepared = parsed.map(pair => {
    let (size, stmts) = pair
    let program = build_script_bytecode(stmts) catch {
      _ => abort("issue-896 benchmark: setup lowering failed")
    }
    (size, program)
  })
  for pair in parsed {
    let (size, stmts) = pair
    b.bench(name="lower/\{size}", fn() {
      b.keep(issue_896_lower_or_abort(stmts))
    })
  }
  for pair in prepared {
    let (size, program) = pair
    b.bench(name="finalize/\{size}", fn() {
      b.keep(issue_896_finalize_or_abort(program))
    })
  }
}
