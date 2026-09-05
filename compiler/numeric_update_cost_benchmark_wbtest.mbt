// Compare this identical fixture on #1015's parent and merge commit.
// Parsing/lowering stay outside timing; every invocation creates a fresh frame.

///|
fn numeric_update_cost_function(body : String) -> VerifiedBytecodeFunction {
  let program = parse_bytecode_for_wb("function measured(x) { " + body + " }")
  let function = program.verified_main.child(0)
  guard !function.function.needs_own_env else {
    abort("numeric update benchmark unexpectedly needs an environment")
  }
  function
}

///|
fn numeric_update_cost_run(
  interp : Interpreter,
  function : VerifiedBytecodeFunction,
  seed : Int,
) -> Double {
  let result = run_bytecode_function(
    interp,
    { strict: false, current_generator: None },
    interp.global,
    function,
    direct_args=Some([Value::Number(seed.to_double())]),
  ) catch {
    _ => abort("numeric update benchmark execution failed")
  }
  match result {
    BytecodeReturn(Number(value)) => value
    _ => abort("numeric update benchmark did not return a number")
  }
}

///|
test "numeric-update/cost" (b : @bench.T) {
  let mut straight = ""
  for _ in 0..<256 {
    straight += "x++;"
  }
  let cases = [
    ("straight-postfix", straight + "return x;", 256.0),
    ("loop-postfix", "for(var i=0;i<4096;i=i+1) { x++; } return x;", 4096.0),
    ("loop-prefix", "for(var i=0;i<4096;i=i+1) { ++x; } return x;", 4096.0),
    (
      "loop-add-control", "for(var i=0;i<4096;i=i+1) { x=x+1; } return x;", 4096.0,
    ),
  ]
  for entry in cases {
    let (name, body, delta) = entry
    let function = numeric_update_cost_function(body)
    let interp = @interpreter.new_interpreter()
    for seed in [0, 17, -31] {
      assert_eq(
        numeric_update_cost_run(interp, function, seed),
        seed.to_double() + delta,
      )
    }
    let mut iteration = 0
    b.bench(name~, () => {
      iteration = (iteration + 17) % 1024
      b.keep(numeric_update_cost_run(interp, function, iteration))
    })
  }
}
