///|
/// CLI benchmark runner — secondary interface for CI baseline tracking.
///
/// This main function provides machine-readable output (CSV) and explicit
/// control over which benchmark categories run. It complements the native
/// @bench.T test blocks in benchmarks.mbt.
///
/// Usage:
///   moon run bench/main --target js                   # regression only
///   moon run bench/main --target js -- --all          # all categories
///   moon run bench/main --target js -- --csv          # CSV output
///   moon run bench/main --target js -- --list         # list benchmarks
///   moon run bench/main --target js -- --all --csv    # full CSV snapshot
///
/// CSV output can be redirected to a file and committed as a performance
/// baseline:
///   moon run bench/main --target js -- --all --csv > bench/baseline.csv
///
/// To compare two baselines:
///   diff bench/baseline.csv bench/current.csv
///
/// NOTE: Timing is only meaningful on the JS backend.
///       Other targets return 0.0 from now_ms() — see timer.*.mbt.
fn main {
  let args = parse_bench_args()
  if args.list_only {
    println("Available benchmarks (name, category):")
    for pair in all_bench_names() {
      let (name, cat) = pair
      println("  \{name}  [\{cat}]")
    }
    println(
      "\nRun with --all to include component and workflow benchmarks.",
    )
    return
  }
  if args.csv {
    print_csv_header()
  } else {
    println("=== js_engine Benchmark Suite (CLI runner) ===")
    println("Primary interface: moon test bench/ --target js")
    println("")
    if args.run_all {
      println(
        "Running all benchmarks (regression + component + workflow)...",
      )
    } else {
      println(
        "Running regression benchmarks only. Use --all for full suite.",
      )
    }
    println("")
  }
  try {
    let results = if args.run_all { run_all() } else { run_regression() }
    for r in results {
      if args.csv {
        print_result_csv(r)
      } else {
        print_result(r)
      }
    }
    if args.csv == false {
      println("")
      println(
        "Done. Run with --all --csv to produce a full baseline snapshot.",
      )
    }
  } catch {
    e => println("FATAL: benchmark failed: \{e}")
  }
}
