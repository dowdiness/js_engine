// Focused activation benchmarks for fallbacks seen in JetStream 3
// Navier-Stokes. Setup and route assertions stay outside timed regions.

///|
const UPDATE_LOCAL_SOURCE : String =
  #|function updateLocalKernel(rounds, width) {
  #|  var total = 0;
  #|  for (var round = 0; round < rounds; round = round + 1) {
  #|    for (var index = 0; index < width; index++) {
  #|      total = total + index;
  #|    }
  #|  }
  #|  return total;
  #|}

///|
const UPDATE_LOCAL_BYTECODE_CONTROL_SOURCE : String =
  #|function updateLocalKernel(rounds, width) {
  #|  var total = 0;
  #|  for (var round = 0; round < rounds; round = round + 1) {
  #|    for (var index = 0; index < width; index = index + 1) {
  #|      total = total + index;
  #|    }
  #|  }
  #|  return total;
  #|}

///|
const UPDATE_LOCAL_CALL_SOURCE : String = "updateLocalKernel(64, 256);"

///|
const UPDATE_LOCAL_EXPECTED_RESULT : String = "2088960"

///|
const COMPUTED_READ_DEFINITION_SOURCE : String =
  #|var computedReadValues = [
  #|  0, 1, 2, 3, 4, 5, 6, 7,
  #|  8, 9, 10, 11, 12, 13, 14, 15
  #|];
  #|function computedReadKernel(values, rounds) {
  #|  var total = 0;
  #|  for (var round = 0; round < rounds; round = round + 1) {
  #|    for (var index = 0; index < values.length; index = index + 1) {
  #|      total = total + values[index];
  #|    }
  #|  }
  #|  return total;
  #|}

///|
const COMPUTED_READ_CALL_SOURCE : String = "computedReadKernel(computedReadValues, 1024);"

///|
const COMPUTED_READ_EXPECTED_RESULT : String = "122880"

///|
test "update-local activation benchmark route matrix" {
  json_inspect(
    @compiler.profile_candidate_route_plan_json(
      @parser.parse(UPDATE_LOCAL_SOURCE).stmts,
    ),
    content={
      "schema_version": 1,
      "summary": {
        "functions": 2,
        "bytecode": 2,
        "tree": 0,
        "lowering_unsupported": 0,
        "activation_unsupported": 0,
      },
      "functions": [
        {
          "path": [],
          "name": null,
          "executor": "bytecode",
          "reason_phase": null,
          "reason": null,
        },
        {
          "path": [0],
          "name": "updateLocalKernel",
          "executor": "bytecode",
          "reason_phase": null,
          "reason": null,
        },
      ],
    },
  )
  json_inspect(
    @compiler.profile_candidate_route_plan_json(
      @parser.parse(UPDATE_LOCAL_BYTECODE_CONTROL_SOURCE).stmts,
    ),
    content={
      "schema_version": 1,
      "summary": {
        "functions": 2,
        "bytecode": 2,
        "tree": 0,
        "lowering_unsupported": 0,
        "activation_unsupported": 0,
      },
      "functions": [
        {
          "path": [],
          "name": null,
          "executor": "bytecode",
          "reason_phase": null,
          "reason": null,
        },
        {
          "path": [0],
          "name": "updateLocalKernel",
          "executor": "bytecode",
          "reason_phase": null,
          "reason": null,
        },
      ],
    },
  )
}

///|
test "isolate/activation/update_local_numeric_loop" (b : @bench.T) {
  let update_definition = @compiler.compile_script_to_bytecode(
    @parser.parse(UPDATE_LOCAL_SOURCE).stmts,
  )
  let bytecode_definition = @compiler.compile_script_to_bytecode(
    @parser.parse(UPDATE_LOCAL_BYTECODE_CONTROL_SOURCE).stmts,
  )
  let call_program = @compiler.compile_script_to_bytecode(
    @parser.parse(UPDATE_LOCAL_CALL_SOURCE).stmts,
  )
  let update_interp = @interpreter.new_interpreter()
  let bytecode_interp = @interpreter.new_interpreter()
  let _ = update_definition.run(update_interp)
  let _ = bytecode_definition.run(bytecode_interp)
  let update_result = call_program.run(update_interp)
  let bytecode_result = call_program.run(bytecode_interp)
  guard update_result.to_string() == UPDATE_LOCAL_EXPECTED_RESULT else {
    abort("update-local benchmark correctness check failed")
  }
  guard bytecode_result.to_string() == UPDATE_LOCAL_EXPECTED_RESULT else {
    abort("update-local bytecode benchmark correctness check failed")
  }
  b.bench(name="managed local update: index++", fn() {
    b.keep(call_program.run(update_interp)) catch {
      _ => abort("update-local benchmark execution failed")
    }
  })
  b.bench(name="bytecode control: index = index + 1", fn() {
    b.keep(call_program.run(bytecode_interp)) catch {
      _ => abort("update-local bytecode benchmark execution failed")
    }
  })
}

///|
test "conditional-computed-property benchmark route" {
  json_inspect(
    @compiler.profile_candidate_route_plan_json(
      @parser.parse(COMPUTED_READ_DEFINITION_SOURCE).stmts,
    ),
    content={
      "schema_version": 1,
      "summary": {
        "functions": 2,
        "bytecode": 2,
        "tree": 0,
        "lowering_unsupported": 0,
        "activation_unsupported": 0,
      },
      "functions": [
        {
          "path": [],
          "name": null,
          "executor": "bytecode",
          "reason_phase": null,
          "reason": null,
        },
        {
          "path": [0],
          "name": "computedReadKernel",
          "executor": "bytecode",
          "reason_phase": null,
          "reason": null,
        },
      ],
    },
  )
}

///|
test "isolate/activation/conditional_computed_property_numeric_array" (
  b : @bench.T,
) {
  let definition = @compiler.compile_script_to_bytecode(
    @parser.parse(COMPUTED_READ_DEFINITION_SOURCE).stmts,
  )
  let call_program = @compiler.compile_script_to_bytecode(
    @parser.parse(COMPUTED_READ_CALL_SOURCE).stmts,
  )
  let interp = @interpreter.new_interpreter()
  let _ = definition.run(interp)
  let result = call_program.run(interp)
  guard result.to_string() == COMPUTED_READ_EXPECTED_RESULT else {
    abort("computed-read benchmark correctness check failed")
  }
  b.bench(name="dynamic numeric-array read: values[index]", fn() {
    b.keep(call_program.run(interp)) catch {
      _ => abort("computed-read benchmark execution failed")
    }
  })
}

///|
const NAVIER_LIN_SOLVE_DEFINITION_SOURCE : String =
  #|var navierValues = [];
  #|var navierSource = [];
  #|for (var init = 0; init < 48; init = init + 1) {
  #|  navierValues[init] = init % 7;
  #|  navierSource[init] = (init * 3) % 11;
  #|}
  #|function navierLinSolveKernel(values, source, size) {
  #|  for (var sweep = 0; sweep < 4; sweep = sweep + 1) {
  #|    for (var index = 1; index < size - 1; index++) {
  #|      values[index] =
  #|        (source[index] + values[index - 1] + values[index + 1]) * 0.25;
  #|    }
  #|  }
  #|  return values[24];
  #|}

///|
const NAVIER_LIN_SOLVE_CALL_SOURCE : String =
  #|var checksum = 0;
  #|for (var repetition = 0; repetition < 24; repetition = repetition + 1) {
  #|  checksum = checksum + navierLinSolveKernel(navierValues, navierSource, 48);
  #|}
  #|checksum;

///|
test "isolate/activation/navier_lin_solve_route" (b : @bench.T) {
  let definition = @compiler.compile_script_to_bytecode(
    @parser.parse(NAVIER_LIN_SOLVE_DEFINITION_SOURCE).stmts,
  )
  let call_program = @compiler.compile_script_to_bytecode(
    @parser.parse(NAVIER_LIN_SOLVE_CALL_SOURCE).stmts,
  )
  let interp = @interpreter.new_interpreter()
  let _ = definition.run(interp)
  let result = call_program.run(interp)
  guard result is @runtime.Value::Number(checksum) else {
    abort("Navier lin_solve route benchmark correctness check failed")
  }
  guard checksum == 66.53883839328586 else {
    abort("Navier lin_solve route benchmark returned the wrong checksum")
  }
  b.bench(name="computed read, computed set, and local update", fn() {
    b.keep(call_program.run(interp)) catch {
      _ => abort("Navier lin_solve route benchmark execution failed")
    }
  })
}
