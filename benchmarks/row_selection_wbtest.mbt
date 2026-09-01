///|
test "benchmark row selection executes canonical subset only" {
  let selected = select_benchmark_cases([
    "isolate/bytecode/call_frame", "isolate/bytecode/dispatch_stack",
  ])
  json_inspect(selected.map(benchmark => benchmark.name), content=[
    "isolate/bytecode/dispatch_stack", "isolate/bytecode/call_frame",
  ])
}

///|
test "benchmark row selection rejects an unknown row" {
  let result : Result[Array[BenchmarkCase], Error] = Ok(
    select_benchmark_cases(["missing/benchmark"]),
  ) catch {
    error => Err(error)
  }
  match result {
    Err(Failure::Failure(message)) =>
      assert_true(message.contains("unknown benchmark row: missing/benchmark"))
    _ => fail("expected unknown benchmark row failure")
  }
}

///|
test "benchmark arguments parse selected rows" {
  let values = [
    "--csv", "--rows", "isolate/bytecode/call_frame,isolate/bytecode/dispatch_stack",
  ]
  let args = parse_bench_arg_values(values[0:])
  inspect(args.csv, content="true")
  match args.rows {
    Some(rows) =>
      json_inspect(rows, content=[
        "isolate/bytecode/call_frame", "isolate/bytecode/dispatch_stack",
      ])
    None => fail("expected selected benchmark rows")
  }
}
