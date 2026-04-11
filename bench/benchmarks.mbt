// =============================================================================
// Native MoonBit benchmark suite — @bench.T test blocks
//
// Run with:
//   moon test bench/ --target js
//   moon test bench/ --target js --filter "exec/fibonacci_30"
//
// Each test block is a self-contained benchmark scenario. The test name is
// the stable benchmark identifier used for regression tracking. Do not rename
// tests without updating any saved baseline files.
//
// Correctness contract
// --------------------
// Execution benchmarks verify their expected output *once*, outside the
// timed b.bench() region, before the measurement loop runs. A wrong result
// causes the test to abort with a clear diagnostic — this prevents measuring
// "fast but wrong" code paths.
//
// Category labels
// ---------------
// See Category enum in runner.mbt:
//   Regression — low-noise, CI-suitable (run by default)
//   Component  — subsystem benchmarks (run with --all on CLI runner)
//   Workflow   — end-to-end, higher variance (manual / exploratory)
//
// @bench.T behaviour
// ------------------
// - b.bench(fn) auto-detects the right inner iteration count so that each
//   outer run lasts long enough for stable timing.
// - count=N controls outer runs (default 10); lower for slow benchmarks.
// - b.keep(value) prevents dead-code elimination of pure expressions.
// - Warmup is handled internally by the framework.
// =============================================================================

// ---------------------------------------------------------------------------
// Helper: non-raising correctness check for use inside test bodies.
// Uses abort() (always fatal) so it works in any error context.
// ---------------------------------------------------------------------------

///|
fn expect(src : String, want : String) -> Unit {
  try {
    let (_, got) = @lib.run(src)
    if got != want {
      abort(
        "bench correctness check failed\n  expected: \{want}\n  got:      \{got}",
      )
    }
  } catch {
    _ => abort("bench correctness check: execution raised an error")
  }
}

// =============================================================================
// REGRESSION benchmarks
// These are the default CI benchmarks: stable, low-noise, fast enough to
// run on every commit. Rename or remove only when the underlying workload
// fundamentally changes — renaming breaks baseline continuity.
// =============================================================================

///|
/// Lexer throughput on a small (~130-token) realistic JS snippet.
///
/// What it measures: @lexer.tokenize() per-call cost on a short source.
/// What it answers:  Is the lexer regressing for typical short scripts?
/// What it excludes: parsing, interpretation, error handling.
///
/// The framework auto-detects batch size so each outer run is well-resolved.
test "lexer/small" (b : @bench.T) {
  b.bench(
    fn() {
      try {
        b.keep(@lexer.tokenize(LEXER_SMALL_SRC))
      } catch {
        _ => abort("tokenize raised")
      }
    },
  )
}

///|
/// Lexer throughput on a large (~1 100-token) realistic JS source.
///
/// What it measures: @lexer.tokenize() per-call cost on a realistic-size source.
/// What it answers:  Does lexer cost scale linearly with source size?
///                   Compare mean with lexer/small after normalising by token
///                   count to detect super-linear (O(n²)) regressions.
/// What it excludes: parsing, interpretation.
test "lexer/large" (b : @bench.T) {
  b.bench(
    fn() {
      try {
        b.keep(@lexer.tokenize(LEXER_LARGE_SRC))
      } catch {
        _ => abort("tokenize raised")
      }
    },
  )
}

///|
/// Scaling comparison: small vs large source in a single batch.
///
/// Batch output lets you read the throughput ratio directly without
/// normalising manually. Use this when investigating lexer scaling.
test "lexer: size scaling" (b : @bench.T) {
  b.bench(
    name="small (~130 tok)",
    fn() {
      try {
        b.keep(@lexer.tokenize(LEXER_SMALL_SRC))
      } catch {
        _ => abort("tokenize raised")
      }
    },
  )
  b.bench(
    name="large (~1100 tok)",
    fn() {
      try {
        b.keep(@lexer.tokenize(LEXER_LARGE_SRC))
      } catch {
        _ => abort("tokenize raised")
      }
    },
  )
}

///|
/// Full pipeline cost dominated by recursive function call overhead.
///
/// fib(30) makes ≈ 2.7 million recursive invocations. Each invocation
/// exercises: call_value() → Environment allocation → exec_stmt() →
/// eval_expr() for the conditional and arithmetic → return.
///
/// What it measures: call/return cycle cost across the full pipeline.
/// What it answers:  What is the raw function call throughput of the interpreter?
/// What it excludes: built-in methods, I/O, event loop, type coercion.
///
/// Each outer run takes several seconds; total wall time per full run is ~30–60s.
/// Expected result: "832040"
test "exec/fibonacci_30" (b : @bench.T) {
  expect(FIBONACCI_SRC, "832040")
  // count is kept at the default (10 outer runs).
  // fib(30) takes several seconds per run; total wall time is ~30–60s.
  // This is acceptable for an explicit regression benchmark run.
  b.bench(
    fn() {
      try {
        let (_, v) = @lib.run(FIBONACCI_SRC)
        b.keep(v)
      } catch {
        _ => abort("run raised")
      }
    },
  )
}

///|
/// Property chain access in a 10 000-iteration JS loop.
///
/// Each iteration reads `obj.a.b.c.d.e` — five own-property lookups
/// through plain object literals. Total: 50 000 get_property() calls
/// per run(). The JS loop removes loop overhead from the measurement.
///
/// What it measures: get_property() throughput on own properties.
/// What it answers:  What is the per-lookup cost in the property access hot path?
/// What it excludes: prototype chain traversal, accessor descriptors,
///                   computed keys, Proxy traps.
///
/// Expected result: "420000"  (10 000 × 42)
test "exec/property_chain" (b : @bench.T) {
  expect(PROPERTY_CHAIN_SRC, "420000")
  b.bench(
    fn() {
      try {
        let (_, v) = @lib.run(PROPERTY_CHAIN_SRC)
        b.keep(v)
      } catch {
        _ => abort("run raised")
      }
    },
  )
}

// =============================================================================
// COMPONENT benchmarks
// Isolated subsystem benchmarks. More variance than regression benchmarks;
// run locally or in a nightly CI job rather than per-commit.
// =============================================================================

///|
/// Array.prototype.map + filter on 1 000 elements.
///
/// What it measures: native callable dispatch (builtins_array.mbt),
///                   array iteration, new Array allocation, closure dispatch.
/// What it answers:  What is the overhead of the array built-in method path?
/// What it excludes: sparse arrays, species constructor, Symbol.iterator.
///
/// Expected result: "334"
test "exec/array_map_filter" (b : @bench.T) {
  expect(ARRAY_MAP_FILTER_SRC, "334")
  b.bench(
    fn() {
      try {
        let (_, v) = @lib.run(ARRAY_MAP_FILTER_SRC)
        b.keep(v)
      } catch {
        _ => abort("run raised")
      }
    },
  )
}

///|
/// Closure factory: 1 000 closures created, each called once.
///
/// What it measures: Environment allocation per closure, captured-variable
///                   lookup through parent-chain, call overhead for factory
///                   and the returned function.
/// What it answers:  How expensive is closure creation vs plain function calls?
/// What it excludes: deep scope chains (> 2 levels), class methods, bind().
///
/// Expected result: "500500"
test "exec/closure_factory" (b : @bench.T) {
  expect(CLOSURE_FACTORY_SRC, "500500")
  b.bench(
    fn() {
      try {
        let (_, v) = @lib.run(CLOSURE_FACTORY_SRC)
        b.keep(v)
      } catch {
        _ => abort("run raised")
      }
    },
  )
}

///|
/// Object literal construction: 1 000 objects × 5 properties.
///
/// What it measures: ObjectData allocation, property insertion (Map write),
///                   string key handling ("item" + i), array push overhead.
/// What it answers:  What is the cost of the object literal fast path?
/// What it excludes: Object.create(), class instantiation, defineProperty().
///
/// Expected result: "1000"
test "exec/object_construction" (b : @bench.T) {
  expect(OBJECT_CONSTRUCTION_SRC, "1000")
  b.bench(
    fn() {
      try {
        let (_, v) = @lib.run(OBJECT_CONSTRUCTION_SRC)
        b.keep(v)
      } catch {
        _ => abort("run raised")
      }
    },
  )
}

///|
/// String method dispatch: toUpperCase + concatenation in a 100-iter loop.
///
/// What it measures: String.prototype.toUpperCase dispatch (builtins_string.mbt),
///                   string allocation from concatenation, primitive boxing.
/// What it answers:  What is the overhead of calling a built-in string method
///                   and concatenating results repeatedly?
/// What it excludes: regex, split/join, template literals, charCodeAt.
///
/// Expected result: "600"  (100 × len("HELLO ") = 100 × 6)
test "exec/string_ops" (b : @bench.T) {
  expect(STRING_OPS_SRC, "600")
  b.bench(
    fn() {
      try {
        let (_, v) = @lib.run(STRING_OPS_SRC)
        b.keep(v)
      } catch {
        _ => abort("run raised")
      }
    },
  )
}

///|
/// Batch: component execution scenarios side-by-side.
///
/// Useful for quickly reading relative component costs without running
/// each test individually. Use when profiling where time goes in typical
/// workloads that mix these patterns.
test "exec: component comparison" (b : @bench.T) {
  b.bench(
    name="array_map_filter",
    fn() {
      try {
        let (_, v) = @lib.run(ARRAY_MAP_FILTER_SRC)
        b.keep(v)
      } catch {
        _ => abort("run raised")
      }
    },
  )
  b.bench(
    name="closure_factory",
    fn() {
      try {
        let (_, v) = @lib.run(CLOSURE_FACTORY_SRC)
        b.keep(v)
      } catch {
        _ => abort("run raised")
      }
    },
  )
  b.bench(
    name="object_construction",
    fn() {
      try {
        let (_, v) = @lib.run(OBJECT_CONSTRUCTION_SRC)
        b.keep(v)
      } catch {
        _ => abort("run raised")
      }
    },
  )
  b.bench(
    name="string_ops",
    fn() {
      try {
        let (_, v) = @lib.run(STRING_OPS_SRC)
        b.keep(v)
      } catch {
        _ => abort("run raised")
      }
    },
  )
}

// =============================================================================
// WORKFLOW benchmarks
// End-to-end or pipeline-level scenarios. Exploratory and higher variance.
// Run manually when investigating pipeline-stage cost.
// =============================================================================

///|
/// Lexer + parser combined throughput on a complex expression-heavy source.
///
/// What it measures: @parser.parse() (which includes @lexer.tokenize())
///                   on a source heavy with binary chains, ternary, and
///                   function declarations.
/// What it answers:  How fast is the combined lexer + parser pipeline on
///                   a realistically complex source?
/// What it excludes: interpreter execution (source is not run()).
///
/// Note: parse time is typically a small fraction of total script cost
/// but matters for REPL-style use and hot-module-reload scenarios.
test "pipeline/parse_heavy" (b : @bench.T) {
  b.bench(
    fn() {
      try {
        b.keep(@parser.parse(PARSER_HEAVY_SRC))
      } catch {
        _ => abort("parse raised")
      }
    },
  )
}
