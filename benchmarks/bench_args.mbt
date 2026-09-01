///|
pub struct BenchArgs {
  run_all : Bool
  csv : Bool
  startup_phases : Bool
  list_only : Bool
  rows : Array[String]?
}

///|
fn parse_benchmark_rows(raw : String) -> Array[String] raise {
  let rows : Array[String] = []
  for part in raw.split(",") {
    let row = part.trim().to_owned()
    if row != "" {
      rows.push(row)
    }
  }
  guard rows.length() > 0 else {
    fail("--rows must select at least one benchmark row")
  }
  rows
}

///|
fn parse_bench_arg_values(args : ArrayView[String]) -> BenchArgs raise {
  let mut run_all = false
  let mut csv = false
  let mut startup_phases = false
  let mut list_only = false
  let mut rows : Array[String]? = None
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "--all" => run_all = true
      "--csv" => csv = true
      "--startup-phases" => startup_phases = true
      "--list" => list_only = true
      "--rows" => {
        guard i + 1 < args.length() else {
          fail("--rows requires a comma-separated value")
        }
        rows = Some(parse_benchmark_rows(args[i + 1]))
        i += 1
      }
      flag => fail("unknown benchmark flag: " + flag)
    }
    i += 1
  }
  { run_all, csv, startup_phases, list_only, rows }
}
