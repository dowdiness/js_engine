// =============================================================================
// Scenario helpers shared by both benchmark surfaces
//
// Two benchmark surfaces exist in this package:
//
//   1. Native @bench.T test blocks (benchmarks.mbt)
//      Run with:  moon test bench/ --target js
//      Purpose:   interactive development, automatic iteration detection,
//                 moon-native output, regression detection per-commit.
//
//   2. CLI runner using run_bench() from runner.mbt (main.mbt)
//      Run with:  moon run bench/main --target js [-- --all] [-- --csv]
//      Purpose:   CI baseline snapshots, CSV output for long-term tracking.
//
// Both surfaces share the JS workload strings from workloads.mbt and the
// verify() helper defined below.
// =============================================================================

///|
/// Verify that run(src) produces the expected result string.
///
/// Called once *outside* any timed region (before bench loops or before
/// b.bench() calls) to confirm the workload is exercising correct behaviour.
/// Aborts with a clear message on mismatch — a mismatch means the workload
/// constant or the interpreter has a bug, not a performance problem.
///
/// Not timed: the interpreter startup and parse cost here is intentionally
/// not representative; that cost is already covered by the pipeline benchmarks.
pub fn verify(src : String, expected : String) -> Unit raise {
  let (_, got) = @lib.run(src)
  if got != expected {
    abort(
      "bench correctness check failed\n  source:   (see workloads.mbt)\n  expected: \{expected}\n  got:      \{got}",
    )
  }
}

// ---------------------------------------------------------------------------
// CLI runner scenarios (used by main.mbt via run_regression, run_all, etc.)
// ---------------------------------------------------------------------------

///|
pub fn bench_lexer_small() -> BenchResult raise {
  run_bench(
    "lexer/small",
    Regression,
    { warmup: 3, iterations: 100, group_size: 100 },
    fn() raise { let _ = @lexer.tokenize(LEXER_SMALL_SRC) },
  )
}

///|
pub fn bench_lexer_large() -> BenchResult raise {
  run_bench(
    "lexer/large",
    Regression,
    { warmup: 3, iterations: 30, group_size: 10 },
    fn() raise { let _ = @lexer.tokenize(LEXER_LARGE_SRC) },
  )
}

///|
pub fn bench_fibonacci() -> BenchResult raise {
  verify(FIBONACCI_SRC, "832040")
  run_bench(
    "exec/fibonacci_30",
    Regression,
    { warmup: 2, iterations: 5, group_size: 1 },
    fn() raise { let _ = @lib.run(FIBONACCI_SRC) },
  )
}

///|
pub fn bench_property_chain() -> BenchResult raise {
  verify(PROPERTY_CHAIN_SRC, "420000")
  run_bench(
    "exec/property_chain",
    Regression,
    { warmup: 2, iterations: 8, group_size: 1 },
    fn() raise { let _ = @lib.run(PROPERTY_CHAIN_SRC) },
  )
}

///|
pub fn bench_array_map_filter() -> BenchResult raise {
  verify(ARRAY_MAP_FILTER_SRC, "334")
  run_bench(
    "exec/array_map_filter",
    Component,
    { warmup: 2, iterations: 10, group_size: 1 },
    fn() raise { let _ = @lib.run(ARRAY_MAP_FILTER_SRC) },
  )
}

///|
pub fn bench_closure_factory() -> BenchResult raise {
  verify(CLOSURE_FACTORY_SRC, "500500")
  run_bench(
    "exec/closure_factory",
    Component,
    { warmup: 2, iterations: 10, group_size: 1 },
    fn() raise { let _ = @lib.run(CLOSURE_FACTORY_SRC) },
  )
}

///|
pub fn bench_closure_conversion_closure_factory() -> BenchResult raise {
  verify(CLOSURE_FACTORY_SRC, "500500")
  let prog = @parser.parse(CLOSURE_FACTORY_SRC)
  let compiled = @compiler.compile_program_to_closure(prog.stmts)
  let precheck_interp = @interpreter.new_interpreter()
  let got = compiled(
    precheck_interp,
    default_exec_ctx(),
    precheck_interp.global,
  ).to_string()
  if got != "500500" {
    abort(
      "bench correctness check failed\n  source:   CLOSURE_FACTORY_SRC compiled\n  expected: 500500\n  got:      \{got}",
    )
  }
  run_bench(
    "baseline/closure_conversion/closure_factory",
    Component,
    { warmup: 2, iterations: 10, group_size: 1 },
    fn() raise {
      let interp = @interpreter.new_interpreter()
      let _ = compiled(interp, default_exec_ctx(), interp.global)
    },
  )
}

///|
pub fn bench_object_construction() -> BenchResult raise {
  verify(OBJECT_CONSTRUCTION_SRC, "1000")
  run_bench(
    "exec/object_construction",
    Component,
    { warmup: 2, iterations: 10, group_size: 1 },
    fn() raise { let _ = @lib.run(OBJECT_CONSTRUCTION_SRC) },
  )
}

///|
pub fn bench_string_ops() -> BenchResult raise {
  verify(STRING_OPS_SRC, "600")
  run_bench(
    "exec/string_ops",
    Component,
    { warmup: 2, iterations: 10, group_size: 1 },
    fn() raise { let _ = @lib.run(STRING_OPS_SRC) },
  )
}

///|
pub fn bench_pipeline_exec_lex() -> BenchResult raise {
  verify(PIPELINE_EXEC_SRC, PIPELINE_EXEC_EXPECTED)
  run_bench(
    "pipeline/exec/lex",
    Workflow,
    { warmup: 3, iterations: 30, group_size: 500 },
    fn() raise { let _ = @lexer.tokenize(PIPELINE_EXEC_SRC) },
  )
}

///|
pub fn bench_pipeline_exec_parse() -> BenchResult raise {
  verify(PIPELINE_EXEC_SRC, PIPELINE_EXEC_EXPECTED)
  let tokens = @lexer.tokenize(PIPELINE_EXEC_SRC)
  let _ = @parser.parse_tokens(tokens)
  run_bench(
    "pipeline/exec/parse",
    Workflow,
    { warmup: 3, iterations: 30, group_size: 500 },
    fn() raise { let _ = @parser.parse_tokens(tokens) },
  )
}

///|
pub fn bench_pipeline_exec_evaluate() -> BenchResult raise {
  verify(PIPELINE_EXEC_SRC, PIPELINE_EXEC_EXPECTED)
  let prog = @parser.parse(PIPELINE_EXEC_SRC)
  let precheck_interp = @interpreter.new_interpreter()
  let got = precheck_interp.run(prog.stmts).to_string()
  if got != PIPELINE_EXEC_EXPECTED {
    abort(
      "bench correctness check failed\n  source:   PIPELINE_EXEC_SRC\n  expected: \{PIPELINE_EXEC_EXPECTED}\n  got:      \{got}",
    )
  }
  let interp = @interpreter.new_interpreter()
  run_bench(
    "pipeline/exec/evaluate",
    Workflow,
    { warmup: 2, iterations: 10, group_size: 1 },
    fn() raise { let _ = interp.run(prog.stmts) },
  )
}

///|
pub fn bench_pipeline_closure_conversion_evaluate() -> BenchResult raise {
  verify(PIPELINE_EXEC_SRC, PIPELINE_EXEC_EXPECTED)
  let prog = @parser.parse(PIPELINE_EXEC_SRC)
  let compiled = @compiler.compile_program_to_closure(prog.stmts)
  let precheck_interp = @interpreter.new_interpreter()
  let got = compiled(
    precheck_interp,
    default_exec_ctx(),
    precheck_interp.global,
  ).to_string()
  if got != PIPELINE_EXEC_EXPECTED {
    abort(
      "bench correctness check failed\n  source:   PIPELINE_EXEC_SRC compiled\n  expected: \{PIPELINE_EXEC_EXPECTED}\n  got:      \{got}",
    )
  }
  let interp = @interpreter.new_interpreter()
  run_bench(
    "pipeline/closure_conversion/evaluate",
    Workflow,
    { warmup: 2, iterations: 10, group_size: 1 },
    fn() raise { let _ = compiled(interp, default_exec_ctx(), interp.global) },
  )
}

///|
pub fn bench_parse_heavy() -> BenchResult raise {
  run_bench(
    "pipeline/parse_heavy",
    Workflow,
    { warmup: 3, iterations: 30, group_size: 50 },
    fn() raise { let _ = @parser.parse(PARSER_HEAVY_SRC) },
  )
}

// ---------------------------------------------------------------------------
// Grouped runners (used by main.mbt)
// ---------------------------------------------------------------------------

///|
pub fn run_regression() -> Array[BenchResult] raise {
  [
    bench_lexer_small(),
    bench_lexer_large(),
    bench_fibonacci(),
    bench_property_chain(),
  ]
}

///|
pub fn run_component() -> Array[BenchResult] raise {
  [
    bench_array_map_filter(),
    bench_closure_factory(),
    bench_closure_conversion_closure_factory(),
    bench_arithmetic_loop(),
    bench_object_construction(),
    bench_string_ops(),
  ]
}

///|
pub fn run_workflow() -> Array[BenchResult] raise {
  [
    bench_pipeline_exec_lex(),
    bench_pipeline_exec_parse(),
    bench_pipeline_exec_evaluate(),
    bench_pipeline_closure_conversion_evaluate(),
    bench_parse_heavy(),
  ]
}

///|
pub fn run_all() -> Array[BenchResult] raise {
  let out : Array[BenchResult] = []
  for r in run_regression() {
    out.push(r)
  }
  for r in run_component() {
    out.push(r)
  }
  for r in run_workflow() {
    out.push(r)
  }
  out
}

///|
/// Stable list of all benchmark names, in canonical run order.
/// Used by main.mbt to print --list output.
pub fn all_bench_names() -> Array[(String, String)] {
  [
    ("lexer/small", "regression"),
    ("lexer/large", "regression"),
    ("exec/fibonacci_30", "regression"),
    ("exec/property_chain", "regression"),
    ("exec/array_map_filter", "component"),
    ("exec/closure_factory", "component"),
    ("baseline/closure_conversion/closure_factory", "component"),
    ("exec/arithmetic_loop", "component"),
    ("exec/object_construction", "component"),
    ("exec/string_ops", "component"),
    ("pipeline/exec/lex", "workflow"),
    ("pipeline/exec/parse", "workflow"),
    ("pipeline/exec/evaluate", "workflow"),
    ("pipeline/closure_conversion/evaluate", "workflow"),
    ("pipeline/parse_heavy", "workflow"),
  ]
}
