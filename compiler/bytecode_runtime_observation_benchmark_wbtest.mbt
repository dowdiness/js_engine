// Runtime observation cost microbenchmark. `source-resolution` isolates the
// eliminated verified-metadata lookup, `former-barrier` replays the old VM
// path, and `current-barrier` tracks the work the VM actually performs.
//
// Run with:
//   moon bench -p dowdiness/js_engine/compiler \
//     -f bytecode_runtime_observation_benchmark_wbtest.mbt \
//     --target js --release

///|
fn runtime_observation_source() -> String {
  let mut source = "var value = 0;"
  for _ in 0..<64 {
    source = source + "value++;"
  }
  source + "value;"
}

///|
fn runtime_observation_fixture() -> (
  BytecodeFunction,
  Array[SourcePointId],
  @runtime.Interpreter,
) {
  let stmts = @parser.parse(runtime_observation_source()).stmts catch {
      _ => abort("runtime observation benchmark: source failed to parse")
    }
  let program = compile_script_to_bytecode(stmts) catch {
    _ => abort("runtime observation benchmark: source failed to compile")
  }
  let function = program.verified_main.function
  let source_ids : Array[SourcePointId] = []
  for instruction in function.code {
    match instruction {
      ObserveStatement(source_id) | ObserveExpression(source_id) =>
        source_ids.push(source_id)
      _ => ()
    }
  }
  guard source_ids.length() > 0 else {
    abort("runtime observation benchmark: no observation instructions")
  }
  (function, source_ids, @interpreter.new_interpreter())
}

///|
fn observe_unbounded_or_abort(interp : @runtime.Interpreter) -> Unit {
  interp.observe_execution_step() catch {
    _ => abort("runtime observation benchmark: unbounded observation failed")
  }
}

///|
fn run_bytecode_runtime_observation_benchmark(b : @bench.T) -> Unit {
  let (function, source_ids, interp) = runtime_observation_fixture()
  let source_id_count = source_ids.length()
  let scales = [10000, 100000]
  for scale in scales {
    b.bench(name="control/\{scale}", fn() {
      let mut checksum = 0
      for index in 0..<scale {
        let SourcePointId(_, _, source_index) = source_ids[index %
          source_id_count]
        checksum += source_index
      }
      b.keep(checksum)
    })
    b.bench(name="source-resolution/\{scale}", fn() {
      let mut checksum = 0
      for index in 0..<scale {
        let source_id = source_ids[index % source_id_count]
        let SourcePointId(_, _, source_index) = source_id
        checksum += source_index
        ignore(function.resolve_source_point(source_id))
      }
      b.keep(checksum)
    })
    b.bench(name="former-barrier/\{scale}", fn() {
      let mut checksum = 0
      for index in 0..<scale {
        let source_id = source_ids[index % source_id_count]
        let SourcePointId(_, _, source_index) = source_id
        checksum += source_index
        ignore(function.resolve_source_point(source_id))
        observe_unbounded_or_abort(interp)
      }
      b.keep(checksum)
    })
    b.bench(name="current-barrier/\{scale}", fn() {
      let mut checksum = 0
      for index in 0..<scale {
        let SourcePointId(_, _, source_index) = source_ids[index %
          source_id_count]
        checksum += source_index
        observe_unbounded_or_abort(interp)
      }
      b.keep(checksum)
    })
  }
}

///|
test "bytecode/runtime-observation-cost" (b : @bench.T) {
  run_bytecode_runtime_observation_benchmark(b)
}
