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
using @runtime {type ExecContext, type Value}

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
/// Counter factory expression used by the opt-in closure-conversion prototype
/// benchmark. The MoonBit harness performs the outer loop so this isolates the
/// compiled function-expression and compiled function-body call path without
/// requiring whole-program statement compilation yet.
const COMPILED_COUNTER_FACTORY_EXPR : String =
  #|(function(start) {
  #|  var count = start;
  #|  return function() {
  #|    count = count + 1;
  #|    return count;
  #|  };
  #|})

///|
/// Closure-conversion loop microbenchmark with a braced body that contains no
/// lexical declarations. This isolates the cost of creating a block
/// Environment for loop bodies whose semantics do not require one.
const COMPILED_BLOCK_BODY_LOOP_SRC : String =
  #|(function() {
  #|  var sum = 0;
  #|  for (var i = 0; i < 20000; i++) {
  #|    sum = sum + i;
  #|  }
  #|  return sum;
  #|})()

///|
/// Same workload as COMPILED_BLOCK_BODY_LOOP_SRC, but without a braced loop
/// body. Comparing the two isolates block-body environment overhead.
const COMPILED_BARE_BODY_LOOP_SRC : String =
  #|(function() {
  #|  var sum = 0;
  #|  for (var i = 0; i < 20000; i++)
  #|    sum = sum + i;
  #|  return sum;
  #|})()

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
fn parse_single_expr(src : String) -> @ast.Expr raise Error {
  let prog = @parser.parse(src)
  match prog.stmts {
    [ExprStmt(expr, _)] => expr
    _ => abort("expected a single expression statement")
  }
}

///|
fn default_exec_ctx() -> ExecContext {
  { strict: false, current_generator: None }
}

///|
fn run_compiled_counter_factory() -> Value raise Error {
  let interp = @interpreter.new_interpreter()
  let compiled = @compiler.compile_expr_to_closure(
    parse_single_expr(COMPILED_COUNTER_FACTORY_EXPR),
  )
  let factory = compiled(interp, default_exec_ctx(), interp.global)
  let counters : Array[Value] = []
  for i = 0; i < 1000; i = i + 1 {
    counters.push(
      interp.call_value(
        factory,
        Value::Undefined,
        [Value::Number(i.to_double())],
        @token.Loc::default(),
      ),
    )
  }
  let mut total = 0.0
  for counter in counters {
    match
      interp.call_value(counter, Value::Undefined, [], @token.Loc::default()) {
      Value::Number(n) => total += n
      other => abort("compiled counter returned \{other}")
    }
  }
  Value::Number(total)
}

///|
fn compile_bytecode_closure_factory() -> @compiler.BytecodeProgram raise Error {
  let prog = @parser.parse(CLOSURE_FACTORY_SRC)
  @compiler.compile_script_to_bytecode(prog.stmts)
}

///|
fn expect_value_string(name : String, actual : Value, want : String) -> Unit {
  let got = actual.to_string()
  guard got == want else {
    abort(
      "[\{name}] bench correctness check failed\n  expected: \{want}\n  got:      \{got}",
    )
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
/// Opt-in closure-conversion prototype counter factory.
///
/// What it measures: the compiled function-expression and compiled function
/// body path for the same captured-variable shape used by closure_factory.
/// What it answers: whether the prototype call path is viable before wiring
/// whole-program statement compilation into `pipeline/exec/evaluate`.
/// What it excludes: JavaScript-level arrays, for-loops, function declarations,
/// and member/computed calls, which still require statement compilation work.
test "baseline/closure_legacy/compiled_counter_factory" (b : @bench.T) {
  let precheck = run_compiled_counter_factory() catch {
    _ => abort("compiled counter factory precheck raised")
  }
  expect_value_string(
    "baseline/closure_legacy/compiled_counter_factory", precheck, "500500",
  )
  b.bench(fn() {
    let result = run_compiled_counter_factory() catch {
      _ => abort("compiled counter factory raised")
    }
    b.keep(result)
  })
}

///|
/// Opt-in closure-conversion script-level closure factory.
///
/// What it measures: evaluating a pre-parsed, pre-compiled script closure for
/// the same JavaScript source as baseline/exec/closure_factory, including the
/// same script setup envelope as Interpreter::run.
/// What it answers: whether whole-program closure conversion can move the
/// primary closure_factory target, excluding frontend parse/compile cost.
/// What it excludes: lexer/parser cost and closure-conversion compilation cost.
test "baseline/closure_legacy/closure_factory" (b : @bench.T) {
  let prog = @parser.parse(CLOSURE_FACTORY_SRC) catch {
    _ => abort("parse raised")
  }
  let compiled = @compiler.compile_script_to_closure(prog.stmts)
  let precheck_interp = @interpreter.new_interpreter()
  let got = compiled(precheck_interp) catch {
    _ => abort("compiled program raised")
  }
  expect_value_string("baseline/closure_legacy/closure_factory", got, "500500")
  b.bench(fn() {
    let interp = @interpreter.new_interpreter()
    let result = compiled(interp) catch {
      _ => abort("compiled closure_factory raised")
    }
    b.keep(result)
  })
}

///|
/// Opt-in bytecode/IR prototype script-level closure factory.
///
/// What it measures: evaluating a pre-parsed, pre-compiled bytecode program for
/// the same JavaScript source as baseline/exec/closure_factory.
/// What it answers: whether the first bytecode skeleton can run the primary
/// closure-factory shape without changing the default interpreter.
test "baseline/bytecode/closure_factory" (b : @bench.T) {
  let compiled = compile_bytecode_closure_factory() catch {
    _ => abort("bytecode compile raised")
  }
  let got = compiled.run(@interpreter.new_interpreter()) catch {
    _ => abort("bytecode precheck raised")
  }
  expect_value_string("baseline/bytecode/closure_factory", got, "500500")
  b.bench(fn() {
    let result = compiled.run(@interpreter.new_interpreter()) catch {
      _ => abort("bytecode closure_factory raised")
    }
    b.keep(result)
  })
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
/// Isolate closure-conversion block-body environment overhead.
///
/// The two programs differ only in whether the `for` body is a braced block.
/// The braced body has no `let`, `const`, class, or function declaration, so a
/// gap here points at avoidable block Environment allocation in the compiled
/// statement path rather than JavaScript work performed by the loop body.
test "isolate/closure_legacy/block_body_env" (b : @bench.T) {
  let block_prog = @parser.parse(COMPILED_BLOCK_BODY_LOOP_SRC) catch {
    _ => abort("block-body loop parse raised")
  }
  let bare_prog = @parser.parse(COMPILED_BARE_BODY_LOOP_SRC) catch {
    _ => abort("bare-body loop parse raised")
  }
  let block_compiled = @compiler.compile_script_to_closure(block_prog.stmts)
  let bare_compiled = @compiler.compile_script_to_closure(bare_prog.stmts)
  let block_precheck = block_compiled(@interpreter.new_interpreter()) catch {
    _ => abort("block-body loop precheck raised")
  }
  let bare_precheck = bare_compiled(@interpreter.new_interpreter()) catch {
    _ => abort("bare-body loop precheck raised")
  }
  expect_value_string(
    "isolate/closure_legacy/block_body_env block", block_precheck, "199990000",
  )
  expect_value_string(
    "isolate/closure_legacy/block_body_env bare", bare_precheck, "199990000",
  )
  b.bench(name="braced body", fn() {
    let result = block_compiled(@interpreter.new_interpreter()) catch {
      _ => abort("compiled block-body loop raised")
    }
    b.keep(result)
  })
  b.bench(name="bare body", fn() {
    let result = bare_compiled(@interpreter.new_interpreter()) catch {
      _ => abort("compiled bare-body loop raised")
    }
    b.keep(result)
  })
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
