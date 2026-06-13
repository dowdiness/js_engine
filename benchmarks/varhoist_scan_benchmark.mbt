// =============================================================================
// Var-hoist scan microbenchmark (issue #325)
//
// Run with:
//   moon bench -p benchmarks -f varhoist_scan_benchmark.mbt --target js --release
//
// Isolated in its own file so `moon bench -f` can target it without running the
// multi-second execution benchmarks in benchmarks.mbt.
// =============================================================================

///|
/// Parse a body-shaped source into a statement list. Aborts (always fatal) on
/// parse failure so a broken workload cannot be timed.
fn parse_body_or_abort(src : String) -> Array[@ast.Stmt] {
  @parser.parse(src).stmts catch {
    _ => abort("var_hoist_scan: parse failed for body workload")
  }
}

///|
/// Isolated cost of the per-call var-hoist re-walk that issue #325 removes.
///
/// What it measures: @static_semantics.collect_var_declared_names(body) — the
///   exact recursive AST descent BytecodeFrame::hoist_env_var_bindings runs on
///   *every* bytecode function call (compiler/bytecode_vm.mbt) — versus simply
///   iterating the precomputed name array the Stage-7 fix stores on
///   BytecodeFunction and reads at runtime.
/// What it answers: how much work the fix eliminates from the per-call hoist
///   path. Multiply the per-scan delta by call volume to size the real win: a
///   hot helper (e.g. fib(30) ≈ 2.7M calls) pays this on every invocation.
/// What it excludes: define_compiled_binding (identical in both designs) and the
///   local_index_from_names filter (a small linear scan moved to lowering in the
///   fix). Excluding them is conservative — it understates the win.
///
/// The body is fixed across iterations on purpose: the real scenario is the
/// *same* function body re-walked on each call, so a fixed AST is honest here,
/// not a JIT-deflation artifact (collect_var_declared_names allocates a fresh
/// out array and re-pushes every name on each call regardless of caching).
test "frontend/var_hoist_scan" (b : @bench.T) {
  let small_body = parse_body_or_abort(VARHOIST_SMALL_BODY)
  let nested_body = parse_body_or_abort(VARHOIST_NESTED_BODY)
  // Precomputed name arrays — what the optimized VM iterates per call.
  let small_names = @static_semantics.collect_var_declared_names(small_body)
  let nested_names = @static_semantics.collect_var_declared_names(nested_body)
  if small_names.length() != 2 {
    abort("var_hoist_scan: expected 2 small names, got \{small_names.length()}")
  }
  if nested_names.length() != 9 {
    abort(
      "var_hoist_scan: expected 9 nested names, got \{nested_names.length()}",
    )
  }
  b.bench(name="small: re-walk (current)", fn() {
    b.keep(@static_semantics.collect_var_declared_names(small_body))
  })
  b.bench(name="small: iterate precomputed (fix)", fn() {
    let mut n = 0
    for _name in small_names {
      n = n + 1
    }
    b.keep(n)
  })
  b.bench(name="nested: re-walk (current)", fn() {
    b.keep(@static_semantics.collect_var_declared_names(nested_body))
  })
  b.bench(name="nested: iterate precomputed (fix)", fn() {
    let mut n = 0
    for _name in nested_names {
      n = n + 1
    }
    b.keep(n)
  })
}
