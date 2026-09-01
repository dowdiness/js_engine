// Isolates repeated bytecode LoadName reads of one captured binding. The
// four-function chain approximates Navier-Stokes' measured parent depth while
// the local-slot control keeps the loop and activation shape identical.

///|
const CAPTURED_READ_SOURCE =
  #|function outer() {
  #|  var captured = 1;
  #|  function level1() {
  #|    function level2() {
  #|      function level3() {
  #|        var sum = 0;
  #|        for (var i = 0; i < 1024; i++) sum += captured;
  #|        return sum;
  #|      }
  #|      return level3();
  #|    }
  #|    return level2();
  #|  }
  #|  return level1();
  #|}
  #|outer();

///|
const LOCAL_READ_SOURCE =
  #|function outer() {
  #|  function level1() {
  #|    function level2() {
  #|      function level3() {
  #|        var captured = 1;
  #|        var sum = 0;
  #|        for (var i = 0; i < 1024; i++) sum += captured;
  #|        return sum;
  #|      }
  #|      return level3();
  #|    }
  #|    return level2();
  #|  }
  #|  return level1();
  #|}
  #|outer();

///|
test "isolate/bytecode/captured_binding_read" (b : @bench.T) {
  let captured = @compiler.compile_script_to_bytecode(
    @parser.parse(CAPTURED_READ_SOURCE).stmts,
  )
  let local_program = @compiler.compile_script_to_bytecode(
    @parser.parse(LOCAL_READ_SOURCE).stmts,
  )
  let captured_interp = @interpreter.new_interpreter()
  let local_interp = @interpreter.new_interpreter()
  guard captured.run(captured_interp).to_string() == "1024" else {
    abort("captured binding benchmark pre-check failed")
  }
  guard local_program.run(local_interp).to_string() == "1024" else {
    abort("local binding benchmark pre-check failed")
  }
  b.bench(name="captured binding read", fn() {
    b.keep(captured.run(captured_interp)) catch {
      _ => abort("captured binding read raised")
    }
  })
  b.bench(name="local slot read control", fn() {
    b.keep(local_program.run(local_interp)) catch {
      _ => abort("local slot read raised")
    }
  })
}
