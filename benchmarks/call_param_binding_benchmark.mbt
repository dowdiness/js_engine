// =============================================================================
// Call param-binding microbenchmark (issues #362 / #363)
//
// Run with:
//   moon bench -p benchmarks -f call_param_binding_benchmark.mbt --target js --release
//
// Measures the per-call double-binding cost the #362 fast path targets:
//   1. env round-trip: def_parameter × N + has+get × N per local (current path)
//   2. direct array write: locals[i] = args[j] × N (fast path)
//   3. end-to-end JS: 5-param function called 100K times (regression guard for #362)
//
// The "double-binding": params bound into func_env by bind_simple_params
// (closure_conversion.mbt:1618), then read back into BytecodeFrame.locals by
// BytecodeFrame::BytecodeFrame (bytecode_vm.mbt:28-32).
// =============================================================================

///|
/// 5-param function called 100K times.
/// Last value: add5(99999,99999,99999,99999,99999) = 5 * 99999 = 499995.
const CALL_5PARAM_100K_SRC : String =
  #|function add5(a,b,c,d,e){return a+b+c+d+e}
  #|var r=0
  #|for(var i=0;i<100000;i++){r=add5(i,i,i,i,i)}
  #|r

///|
/// Replicates local_index_from_names (compiler/bytecode_ir.mbt:617) used by
/// string_array_contains inside BytecodeFrame::BytecodeFrame (bytecode_vm.mbt:28).
fn find_param_index(params : Array[String], name : String) -> Int? {
  for i, p in params {
    if p == name {
      return Some(i)
    }
  }
  None
}

///|
/// Isolated cost of the per-call double-binding: env Map round-trip vs direct array write.
///
/// What it measures:
///   "env round-trip (current)": def_parameter × N into func_env
///     (bind_simple_params, closure_conversion.mbt:1618), then linear-scan +
///     has + get × N locals back out (BytecodeFrame ctor, bytecode_vm.mbt:28-32)
///   "direct array write (fast path)": locals[i] = args[j] × N with a linear
///     param-index lookup; zero env Map operations on the param-to-local path
///
/// What it answers: how much Map overhead the #362 fast path eliminates per call.
/// What it excludes: Environment::new is on both paths; the fast path still
///   creates func_env for this/new.target/arguments bindings.
///
/// All 5 params are in local_names — the common !captured && !refs_arguments
/// case that the fast path covers (see plan_bytecode_locals, bytecode_lower.mbt:1331).
test "call/param_binding_5params" (b : @bench.T) {
  let closure = @runtime.Environment::new()
  let args : Array[@runtime.Value] = [
    @runtime.Value::Number(1.0),
    @runtime.Value::Number(2.0),
    @runtime.Value::Number(3.0),
    @runtime.Value::Number(4.0),
    @runtime.Value::Number(5.0),
  ]
  let params : Array[String] = ["a", "b", "c", "d", "e"]
  let local_names : Array[String] = ["a", "b", "c", "d", "e"]

  b.bench(name="env round-trip (current)", fn() {
    try {
      // bind_simple_params: def_parameter × N (closure_conversion.mbt:1623)
      let func_env = @runtime.Environment::new(parent=Some(closure))
      for i, param in params {
        let v = if i < args.length() {
          args[i]
        } else {
          @runtime.Value::Undefined
        }
        func_env.def_parameter(param, v)
      }
      // BytecodeFrame ctor: linear-scan + has + get × N (bytecode_vm.mbt:28-32)
      let locals = Array::make(local_names.length(), @runtime.Value::Undefined)
      for idx, name in local_names {
        if find_param_index(params, name) is Some(_) && func_env.has(name) {
          locals[idx] = func_env.get(name)
        }
      }
      b.keep(locals)
    } catch {
      _ => abort("env round-trip: unexpected raise")
    }
  })

  b.bench(name="direct array write (fast path)", fn() {
    let locals = Array::make(local_names.length(), @runtime.Value::Undefined)
    for idx, name in local_names {
      match find_param_index(params, name) {
        Some(j) =>
          locals[idx] = if j < args.length() {
            args[j]
          } else {
            @runtime.Value::Undefined
          }
        None => ()
      }
    }
    b.keep(locals)
  })
}

///|
/// End-to-end JS call benchmark: 5-param bytecode function called 100K times.
///
/// What it measures: full @lib.run() cost including interpreter startup,
///   JS compilation, and 100K bytecode function calls each paying the
///   double-binding cost.
/// What it answers: is the per-call double-binding cost measurable at 100K
///   call volume? Run before and after #362 to quantify the end-to-end speedup.
/// What it excludes: startup cost is included; isolated per-call cost is in
///   call/param_binding_5params above.
///
/// Expected result: "499995"
test "call/e2e_5param_100k" (b : @bench.T) {
  try {
    let (_, got) = @lib.run(CALL_5PARAM_100K_SRC)
    if got != "499995" {
      abort("[call/e2e_5param_100k] expected \"499995\", got \"\{got}\"")
    }
  } catch {
    e => abort("[call/e2e_5param_100k] pre-check raised: \{e}")
  }
  b.bench(fn() {
    try {
      let (_, v) = @lib.run(CALL_5PARAM_100K_SRC)
      b.keep(v)
    } catch {
      _ => abort("run raised")
    }
  })
}
