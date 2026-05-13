// =============================================================================
// Closure-conversion baseline benchmarks
//
// These @bench.T tests group the interpreter workloads most relevant before
// changing function and closure execution. They intentionally do not replace
// the stable regression/component tests in benchmarks.mbt; the baseline/*
// names give closure-conversion work a focused, separately runnable set:
//
//   moon bench -p dowdiness/js_engine/benchmarks --target js -f baseline.mbt
//
// Correctness is checked once before each timed region with expect(). The
// timed section always keeps the run() result so the compiler cannot eliminate
// the work being measured.
// =============================================================================

///|
/// Loop-only arithmetic workload.
///
/// Category: closure-conversion baseline
/// Exercises: variable reads/writes, numeric addition, comparison, update
///            expressions, and statement dispatch in a large loop.
/// Excludes: function calls, closure creation, object/property lookup,
///           builtin method dispatch, and array allocation.
///
/// Expected result: "500000500000"  (sum 1..1,000,000)
const BASELINE_ARITHMETIC_LOOP_SRC : String =
  #|var sum = 0;
  #|for (var i = 1; i <= 1000000; i++) {
  #|  sum = sum + i;
  #|}
  #|sum;

///|
fn keep_run_result(b : @bench.T, src : String) -> Unit {
  try {
    let (_, v) = @lib.run(src)
    b.keep(v)
  } catch {
    _ => abort("run raised")
  }
}

///|
/// Recursive function calls: fib(30).
///
/// What it measures: function invocation and return through the full
/// interpreter pipeline: call_value(), environment allocation, statement
/// execution, expression evaluation, and recursive lookup of fib.
/// What it answers:  What is the current call/return cost before closure
/// conversion changes the function representation?
/// What it excludes: closures that capture variables, object property access,
/// builtin calls, and array operations.
///
/// fib(30) is intentionally expensive, so this baseline uses fewer outer
/// runs than the default @bench.T count while keeping the same workload.
test "baseline/exec/fibonacci_30" (b : @bench.T) {
  expect("baseline/exec/fibonacci_30", FIBONACCI_SRC, "832040")
  b.bench(fn() { keep_run_result(b, FIBONACCI_SRC) }, count=3)
}

///|
/// Closure factory: 1,000 closures created, then called once each.
///
/// What it measures: closure environment allocation, captured-variable lookup
/// through the parent chain, and call overhead for both factory and returned
/// functions.
/// What it answers:  How expensive is the current closure representation before
/// closure conversion can remove or simplify captured environments?
/// What it excludes: deep scope chains beyond two levels, class methods,
/// Function.prototype.bind, and prototype/property descriptor behavior.
test "baseline/exec/closure_factory" (b : @bench.T) {
  expect("baseline/exec/closure_factory", CLOSURE_FACTORY_SRC, "500500")
  b.bench(fn() { keep_run_result(b, CLOSURE_FACTORY_SRC) })
}

///|
/// Property chain access in a 10,000-iteration JS loop.
///
/// What it measures: own-property lookup cost on a stable five-segment chain
/// while the interpreter executes loop control and arithmetic around it.
/// What it answers:  Whether closure-conversion work accidentally regresses
/// unrelated object/property hot paths.
/// What it excludes: prototype chain traversal, accessors, computed keys,
/// Proxy traps, and builtin dispatch.
test "baseline/exec/property_chain" (b : @bench.T) {
  expect("baseline/exec/property_chain", PROPERTY_CHAIN_SRC, "420000")
  b.bench(fn() { keep_run_result(b, PROPERTY_CHAIN_SRC) })
}

///|
/// Simple arithmetic loop with no function calls.
///
/// What it measures: baseline expression and statement execution without call
/// frames or closures, giving a control workload for comparison against the
/// function-heavy benchmarks above.
/// What it answers:  Did closure-conversion work improve calls specifically,
/// or did it also change the generic loop/expression evaluator cost?
/// What it excludes: function invocation, closure capture, property access,
/// arrays, objects, and builtins.
test "baseline/exec/arithmetic_loop" (b : @bench.T) {
  expect(
    "baseline/exec/arithmetic_loop",
    BASELINE_ARITHMETIC_LOOP_SRC,
    "500000500000",
  )
  b.bench(fn() { keep_run_result(b, BASELINE_ARITHMETIC_LOOP_SRC) })
}

///|
/// Fixed-configuration CLI counterpart for CSV baseline snapshots.
///
/// The existing CLI runner already covers fib(30), closure_factory, and
/// property_chain. This adds the loop-only control workload to `--all --csv`
/// without changing the established benchmark names.
fn bench_arithmetic_loop() -> BenchResult raise {
  verify(BASELINE_ARITHMETIC_LOOP_SRC, "500000500000")
  run_bench(
    "exec/arithmetic_loop",
    Component,
    { warmup: 2, iterations: 8, group_size: 1 },
    fn() raise { let _ = @lib.run(BASELINE_ARITHMETIC_LOOP_SRC) },
  )
}
